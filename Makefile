SHELL := /usr/bin/env bash
.SHELLFLAGS := -eu -o pipefail -c

CODENAME ?= amber
OUT      ?= out
KEYRING  ?= $(OUT)/amberlinux-archive-keyring.gpg
REPREPRO ?= reprepro
HOST     ?= 127.0.0.1
PORT     ?= 8000
BRANCH   ?= main
REMOTE   ?= origin

# Every suite repo that produces a .deb. Each answers `make deb-path` with one
# absolute path per package it publishes, so the archive never hardcodes another
# repo's output layout. The contract is docs/PACKAGING.md.
# amber-models publishes all four of its packages, the 320 MiB LLM included. That one
# is past wrangler's 300 MiB object cap and reaches R2 by S3 multipart instead, which
# needs an R2 API token (tools/r2-sync.sh). `make deploy` runs that sync BEFORE
# deploying the worker, and it exits non-zero when a file needs multipart and no
# credentials are set — so a missing token stops the deploy with the previous index
# still live, rather than publishing one that names a pool file nothing can serve.
# Which of its packages ship is that repo'"'"'s decision, next to the packages.
SUITE ?= ../amber-fonts ../amber-gtk4 ../amber-theme ../amber-desktop ../kat800 ../ambrosia ../copal ../amberlin ../amberlin-backend ../amberlin-runtime ../amber-odin ../amber-models

# The flatpak archive is a sibling, published from this machine too: the signing
# key lives in ~/.gnupg here and nowhere else, so both archives are deployed from
# the one box rather than from CI. Pre-v1 this is deliberate — see docs/DEPLOY.md.
FLATPAK_ARCHIVE ?= ../amberlinux-flatpak

# The fingerprint is read from conf/distributions so there is exactly one place to change it.
FPR = $(shell sed -n 's/^SignWith:[[:space:]]*//p' conf/distributions)

ROOT_COMMIT_MSG ?= Initial amberlinux-apt

.PHONY: all deps check preflight lint ci add add-suite remove build build-suite deploy check-debs \ check-no-agent-files
	refresh keyring stage verify verify-fresh verify-http serve list diags clean push force-push hooks \
	deploy-flatpak deploy-all

all: build

deps: hooks
	sudo apt install reprepro gnupg shellcheck

# `check` is the suite-wide name for the fast gate; here that is preflight.
check: preflight

preflight:
	@REPREPRO=$(REPREPRO) tools/preflight.sh

# Every package already in the pool, re-checked. `add` and `add-suite` gate on this
# at ingest; this target is for auditing what is already published.
check-debs:
	@tools/check-no-buildpaths.sh $$(find $(OUT)/pool -name '*.deb' | sort)

# Documentation and repository hygiene: fingerprints agree everywhere, generated
# trees stay untracked, the diagram matches its source.
lint:
	@tools/lint.sh
	@if command -v shellcheck >/dev/null; then \
		git ls-files | while read -r f; do \
			case "$$f" in *.sh|*.bash) echo "$$f";; \
			*) if head -1 "$$f" 2>/dev/null | grep -q '^#!.*sh'; then echo "$$f"; fi;; esac; \
		done | xargs -r shellcheck --severity=warning && echo "shellcheck OK"; \
	else echo "shellcheck not installed — skipping (apt install shellcheck)"; fi
	@test "$$(git config --get core.hooksPath)" = .githooks || echo "lint: hooks not installed — run 'make hooks'"

# Everything worth running before pushing. Same name and intent as in the other
# suite repos.
ci: lint stage
	@echo "CI OK"

# make add DEB=../kat800/dist/kat800_0.1.0-1_amd64.deb
add: preflight
	@test -n "$(DEB)" || { echo "usage: make add DEB=path/to.deb"; exit 2; }
	@tools/check-no-buildpaths.sh "$(DEB)"
	$(REPREPRO) -b $(CURDIR) includedeb $(CODENAME) "$(DEB)"
	@$(MAKE) --no-print-directory keyring

# Ingest the current .deb from every suite repo. reprepro refuses to re-include
# a version it already holds unless the bytes match, and a rebuild is rarely
# byte-identical, so drop the package first and re-add it.
# Rebuild every suite repo's packages (each repo's own `make deb`), then
# ingest and republish. The one-command "refresh everything" path.
build-suite:
	@for r in $(SUITE); do \
		echo "build-suite: $$r"; \
		$(MAKE) -C "$$r" deb || exit 2; \
	done

refresh: build-suite add-suite stage

add-suite: preflight
	@for r in $(SUITE); do \
		test -d "$$r" || { echo "add-suite: no such repo: $$r"; exit 2; }; \
		paths=$$($(MAKE) --no-print-directory -C "$$r" -s deb-path) || { echo "add-suite: $$r has no deb-path target"; exit 2; }; \
		for deb in $$paths; do \
			test -f "$$deb" || { echo "add-suite: not built: $$deb (run 'make deb' in $$r)"; exit 2; }; \
			tools/check-no-buildpaths.sh "$$deb" || exit 1; \
			pkg=$$(dpkg-deb -f "$$deb" Package); \
			if $(REPREPRO) -b $(CURDIR) list $(CODENAME) "$$pkg" | grep -q .; then \
				$(REPREPRO) -b $(CURDIR) remove $(CODENAME) "$$pkg" >/dev/null; \
			fi; \
			echo "add-suite: $$pkg <- $$deb"; \
			$(REPREPRO) -b $(CURDIR) includedeb $(CODENAME) "$$deb"; \
		done; \
	done
	@$(MAKE) --no-print-directory keyring
	@$(MAKE) --no-print-directory list

# make remove PKG=kat800
# Deletes the pool file. See docs/DEPLOY.md § Atomicity before using it on
# anything that has been published: supersede with a higher version instead.
remove: preflight
	@test -n "$(PKG)" || { echo "usage: make remove PKG=name"; exit 2; }
	$(REPREPRO) -b $(CURDIR) remove $(CODENAME) "$(PKG)"

# Re-export the indexes and re-sign. Safe to run at any time.
build: preflight
	$(REPREPRO) -b $(CURDIR) export $(CODENAME)
	@$(MAKE) --no-print-directory keyring
	install -m644 static/index.html $(OUT)/index.html
	install -m644 static/favicon.svg $(OUT)/favicon.svg
	python3 tools/packages-json.py $(OUT)/dists/$(CODENAME)/main/binary-amd64/Packages > $(OUT)/packages.json

# An empty FPR would make gpg export every public key in the keyring into a file we publish.
keyring:
	@test -n "$(FPR)" || { echo "no SignWith fingerprint in conf/distributions"; exit 2; }
	@mkdir -p $(OUT)
	gpg --batch --yes --export-options export-minimal --export --output $(KEYRING) $(FPR)
	@echo "keyring: $(KEYRING) ($(FPR))"

# apt against a throwaway root, over file://.
verify:
	@REPREPRO=$(REPREPRO) tools/verify-client.sh

# The same check over real HTTP. file:// cannot catch a server that redirects or
# rewrites the extension-less index files, which is the failure mode the CDN in
# docs/DEPLOY.md is designed around; BASE=https://apt.amberlinux.org points it
# at the deployed tree.
verify-http:
	@REPREPRO=$(REPREPRO) tools/verify-client.sh $(if $(BASE),"$(BASE)",--serve)

# The gate before uploading $(OUT)/ to apt.amberlinux.org — an unverifiable tree never ships.
# Fails when the archive holds a package older than what its repo builds —
# the one thing verify-client.sh cannot see.
verify-fresh:
	@SUITE="$(SUITE)" OUT="$(OUT)" CODENAME="$(CODENAME)" tools/verify-fresh.sh

stage: build verify-fresh verify verify-http
	@echo "stage: $(CURDIR)/$(OUT) is assembled and verified. 'make deploy' uploads it."

# Ship it: sync pool/** to R2, copy CDN root files, deploy the worker +
# static assets, then run the same client assertions against the live
# domain that pass locally. The last step is the only one that tests the
# CDN rather than the tree (docs/DEPLOY.md).
WRANGLER ?= npx wrangler@4.121.0
deploy: stage
	tools/r2-sync.sh
	cp cloudflare/_headers cloudflare/robots.txt $(OUT)/
	cp cloudflare/assetsignore $(OUT)/.assetsignore
	$(WRANGLER) deploy --config cloudflare/wrangler.jsonc
	$(MAKE) --no-print-directory verify-http BASE=https://apt.amberlinux.org

# Publish the sibling flatpak archive with the same key from the same machine.
# Separate target rather than folded into deploy: the two archives fail
# independently, and a flatpak problem must not leave apt half-published.
deploy-flatpak:
	@test -d $(FLATPAK_ARCHIVE) || { \
		echo "no flatpak archive at $(FLATPAK_ARCHIVE) — clone it or set FLATPAK_ARCHIVE"; \
		exit 2; }
	$(MAKE) -C $(FLATPAK_ARCHIVE) deploy

# Publishing day: both archives, apt first because more depends on it.
deploy-all: deploy deploy-flatpak
	@echo "deploy-all: apt.amberlinux.org and flatpak.amberlinux.org are both published."

serve: build
	python3 -m http.server --directory $(OUT) --bind $(HOST) $(PORT)

list:
	$(REPREPRO) -b $(CURDIR) list $(CODENAME)

# The SVG is committed so reading the repo does not require d2; `make lint`
# fails when it drifts from the source.
diags:
	@for f in diags/*.d2; do \
		d2 --theme=105 --dark-theme=300 --pad=40 "$$f" "$${f%.d2}.svg"; \
		chmod 644 "$${f%.d2}.svg"; \
	done

push:
	git push "$(REMOTE)" "$(BRANCH)"

# out/ and db/ are both regenerated by re-ingesting the .debs; see docs/ARCHITECTURE.md.
clean:
	rm -rf $(OUT) db

# Rewrite the whole tree as one signed root commit and force-push it. The suite's
# repos carry no history until the first official release.
# Agent files are never published. Two ways they get in: already tracked, or
# present-and-unignored when `git add -A` below sweeps the whole tree. Both are
# checked here, because a squashed history shows no file being added — a stray
# path simply appears in the root commit as though it always belonged.
check-no-agent-files:
	@bad=$$(git ls-files | grep -E '(^|/)(\.mcp\.json|\.claude/|\.claude-amber/)' || true); \
	if [ -n "$$bad" ]; then \
		echo "agent files are tracked and must not be published:"; \
		printf '  %s\n' $$bad; \
		echo "fix: git rm -r --cached <path>, then add it to .gitignore"; \
		exit 2; \
	fi
	@for p in .mcp.json .claude .claude-amber; do \
		if [ -e "$$p" ] && ! git check-ignore -q "$$p"; then \
			echo "$$p exists and is not gitignored — 'git add -A' would publish it"; \
			echo "fix: add $$p to .gitignore"; \
			exit 2; \
		fi; \
	done
	@echo "no agent files staged for publication"

force-push: check check-no-agent-files
	@test -z "$$(git status --porcelain)" || { \
		echo "Working tree is dirty. Commit, stash, or revert changes first."; \
		exit 2; \
	}
	@orig_branch="$$(git branch --show-current)"; \
	tmp_branch="root-squash-$$(date +%s)"; \
	git checkout --orphan "$$tmp_branch"; \
	git add -A; \
	git commit -S -m "$(ROOT_COMMIT_MSG)"; \
	git branch -D "$(BRANCH)" 2>/dev/null || true; \
	git branch -m "$(BRANCH)"; \
	git push --force --set-upstream "$(REMOTE)" "$(BRANCH)"; \
	echo "Rewrote $$orig_branch as signed root commit on $(REMOTE)/$(BRANCH)."

# A shipped hook does nothing until core.hooksPath points at it.
hooks:
	@git config core.hooksPath .githooks && echo "hooks: core.hooksPath -> .githooks"
