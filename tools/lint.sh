#!/usr/bin/env bash
# Repository hygiene, checked rather than remembered. Everything here is a rule
# stated somewhere in docs/ that would otherwise rot: the fingerprint users are
# told to trust, the trees that must never be committed, the diagram that must
# match its source, and the suite contract in docs/PACKAGING.md.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"
fail=0
bad() { echo "lint: $*" >&2; fail=1; }

fpr=$(sed -n 's/^SignWith:[[:space:]]*//p' conf/distributions | tr -d '[:space:]')
[ -n "$fpr" ] || { echo "lint: conf/distributions has no SignWith fingerprint" >&2; exit 1; }

# A rotation that updates conf/distributions and misses a doc ships a lie: the
# reader checks the printed fingerprint against a key that no longer signs.
found=0
while read -r f; do
	while read -r printed; do
		found=$((found + 1))
		[ "$printed" = "$fpr" ] || bad "$f states fingerprint $printed, conf/distributions says $fpr"
	done < <(grep -oE '([0-9A-F]{4} ){5} ([0-9A-F]{4} ){4}[0-9A-F]{4}' "$f" | tr -d ' ')
done < <(find . -name '*.md' -not -path './.git/*' -not -path './out/*')
[ "$found" -gt 0 ] || bad "no document states the archive fingerprint; users have nothing to check"

# out/ holds the signed tree and the pool (which will hold model weights); db/
# is meaningless without it. Neither is ever committed.
for d in out db; do
	git check-ignore -q "$d" || bad "$d/ is not gitignored"
	git ls-files --error-unmatch "$d" >/dev/null 2>&1 && bad "$d/ has tracked files"
done

# The secret key lives in ~/.gnupg and nowhere else. The exported public keyring
# is generated into out/, so it must not appear in the tree either.
tracked_keys=$(git ls-files | grep -Ei '\.(gpg|asc|key|pem)$|secring|private-key' || true)
[ -z "$tracked_keys" ] || bad "key-shaped files are tracked: $tracked_keys"

# Published sources lines must match the one verify-client.sh tests.
line=$(grep -oE 'deb \[[^]]*\] \$base amber main' tools/verify-client.sh | head -1)
case "$line" in
	*arch=amd64*) ;;
	*) bad "tools/verify-client.sh does not test an arch=amd64 sources line" ;;
esac
for doc in README.md docs/SPEC.md static/index.html ../amber-astro/src/pages/packages.astro; do
	[ -f "$doc" ] || continue
	grep -q 'apt.amberlinux.org amber main' "$doc" || continue
	grep -q 'deb \[arch=amd64 signed-by=' "$doc" \
		|| bad "$doc publishes a sources line without arch=amd64"
done

# The SVG is committed so reading the repo needs no d2; that only helps if it
# still matches. Regenerate with `make diags`.
for src in diags/*.d2; do
	[ -e "$src" ] || continue
	svg=${src%.d2}.svg
	[ -f "$svg" ] || { bad "$src has no committed $svg (run 'make diags')"; continue; }
	if command -v d2 >/dev/null; then
		tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
		d2 --theme=105 --dark-theme=300 --pad=40 "$src" "$tmp/out.svg" >/dev/null 2>&1
		cmp -s "$tmp/out.svg" "$svg" || bad "$svg is stale (run 'make diags')"
	fi
done

# docs/PACKAGING.md names the repos the archive ingests; the Makefile's SUITE
# list is what it actually ingests. They drift the moment a repo is added.
doc_repos=$(sed -n '/^## Provenance/,/^## /p' docs/PACKAGING.md \
	| sed -n 's/^| `\([a-z0-9-]*\)` .*/\1/p' | sort -u)
mk_repos=$(sed -n 's/^SUITE ?= //p' Makefile | tr ' ' '\n' | sed 's|^\.\./||' | sort -u)
[ -n "$doc_repos" ] || bad "docs/PACKAGING.md lists no repos in its provenance table"
diff <(echo "$doc_repos") <(echo "$mk_repos") >/dev/null \
	|| bad "docs/PACKAGING.md and the Makefile's SUITE list disagree:
$(diff <(echo "$doc_repos") <(echo "$mk_repos") | sed 's/^/    /')"

# Every one of those repos must answer the contract. A missing checkout is not a
# failure — the suite is developed one repo at a time — but a present one that
# cannot say where its package lands is.
for r in $mk_repos; do
	[ -d "../$r" ] || { echo "lint: ../$r not checked out, skipping"; continue; }
	paths=$(make -C "../$r" -s deb-path 2>/dev/null) \
		|| { bad "../$r has no working 'deb-path' target"; continue; }
	# A repo shipping several packages may keep a convenience target per package,
	# but anything not also printed by deb-path is a package the archive would
	# silently never ingest.
	for t in $(make -C "../$r" -np 2>/dev/null | sed -n 's/^\(deb-path[a-z0-9-]\+\):.*/\1/p' | sort -u); do
		extra=$(make -C "../$r" -s "$t" 2>/dev/null)
		grep -qxF "$extra" <<<"$paths" || bad "../$r: '$t' names $extra, which 'deb-path' does not print"
	done
done

[ "$fail" -eq 0 ] || exit 1
echo "lint: fingerprint $fpr consistent, out/ and db/ untracked, diags current, suite contract holds"
