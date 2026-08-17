#!/usr/bin/env bash
# Prove the published tree works for a real apt client, without touching /etc/apt.
# Runs apt-get against a throwaway root whose only source is the tree under test
# and whose only trusted key is the shipped keyring, then downloads every package.
#
#   verify-client.sh            file://out — the fastest check, but a file URL
#                               cannot catch a server that redirects or rewrites.
#   verify-client.sh --serve    the same over real HTTP, from a local server.
#   verify-client.sh <base-url> the same against a deployed tree.
#
# Over HTTP the extension-less index files are also byte-compared against out/;
# that is the failure mode docs/DEPLOY.md is designed around.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
out=$root/out
keyring=$out/amberlinux-archive-keyring.gpg
reprepro=${REPREPRO:-reprepro}
mode=${1:-file}

die() { echo "verify: $*" >&2; exit 1; }

[ -f "$out/dists/amber/InRelease" ] || die "no out/dists/amber/InRelease. Run 'make build'."
[ -f "$keyring" ] || die "no $keyring. Run 'make build'."

# gpgv is what apt itself uses; check the signature directly before involving apt.
gpgv --keyring "$keyring" "$out/dists/amber/InRelease" >/dev/null 2>&1 || die \
	"InRelease is not signed by the shipped keyring."
echo "verify: InRelease signature OK against $(basename "$keyring")"

tmp=$(mktemp -d)
server_pid=
cleanup() { [ -n "$server_pid" ] && kill "$server_pid" 2>/dev/null; rm -rf "$tmp"; }
trap cleanup EXIT

case "$mode" in
file)
	base="file://$out"
	;;
--serve)
	# Port 0 lets the kernel pick a free one, so concurrent runs cannot collide.
	# -u, or the startup line naming that port sits in a stdout buffer forever.
	python3 -u -m http.server --directory "$out" --bind 127.0.0.1 0 >"$tmp/server.log" 2>&1 &
	server_pid=$!
	for _ in $(seq 1 3000); do
		port=$(sed -n 's/.*port \([0-9]*\).*/\1/p' "$tmp/server.log" | head -1)
		[ -n "$port" ] && break
		kill -0 "$server_pid" 2>/dev/null || die "local http server died: $(cat "$tmp/server.log")"
	done
	[ -n "${port:-}" ] || die "local http server did not report a port"
	base="http://127.0.0.1:$port"
	;;
*)
	base=${mode%/}
	;;
esac
echo "verify: base $base"

# Over HTTP, apt's own fetch would mask a redirect (it follows them) and would
# not notice a rewritten body that still parses. Check both directly.
# A deploy lands a beat after wrangler and r2-sync return (~20s): until then the
# origin serves the previous export and the pool may lack the new .deb. Only waits
# for a remote base — a redirect, a rewritten body or a real hash failure never
# resolves, and a local server serves out/ directly.
tries=1
case $base in file://*|http://127.0.0.1:*) ;; *) tries=${VERIFY_TRIES:-10} ;; esac

if [ "${base#http}" != "$base" ]; then
	for f in dists/amber/InRelease dists/amber/Release dists/amber/Release.gpg \
		dists/amber/main/binary-amd64/Packages; do
		n=0
		while :; do
			code=$(curl -sS -o "$tmp/body" -w '%{http_code}' --max-redirs 0 "$base/$f") \
				|| die "$f: curl failed (a redirect, with --max-redirs 0, counts as a failure)"
			[ "$code" = 200 ] || die "$f: HTTP $code, expected 200 with no redirect"
			cmp -s "$tmp/body" "$out/$f" && break
			n=$((n + 1))
			[ "$n" -lt "$tries" ] || die \
				"$f: served bytes differ from out/$f after $n attempt(s) over $((n * 5))s — not propagation, look at the CDN"
			[ "$n" = 1 ] && echo "verify: $f not published yet, waiting"
			sleep 5
		done
	done
	echo "verify: extension-less index files served byte-exact, no redirects"

	# A server that labels Packages.gz with Content-Encoding: gzip makes the
	# client decompress it twice; apt then reports a corrupt index.
	enc=$(curl -sS -o /dev/null -D - "$base/dists/amber/main/binary-amd64/Packages.gz" \
		| tr -d '\r' | sed -n 's/^[Cc]ontent-[Ee]ncoding: //p')
	[ -z "$enc" ] || die "Packages.gz carries Content-Encoding: $enc — apt would double-decompress"

	# apt probes paths that do not exist (by-hash, i18n, Contents). Anything but
	# a real 404 — an SPA fallback returning 200 and HTML, say — breaks it.
	code=$(curl -sS -o /dev/null -w '%{http_code}' "$base/dists/amber/no-such-file")
	[ "$code" = 404 ] || die "a missing path returned HTTP $code, expected 404"
	echo "verify: Packages.gz unencoded, missing paths 404"
fi

mkdir -p "$tmp"/{lists/partial,cache/archives/partial,empty,dl}
: > "$tmp/status"
echo "deb [arch=amd64 signed-by=$keyring] $base amber main" > "$tmp/sources.list"

# APT::Sandbox::User=root keeps apt from dropping to the _apt user, which cannot read $tmp.
apt=(apt-get
	-o Dir::Etc::sourcelist="$tmp/sources.list"
	-o Dir::Etc::sourceparts="$tmp/empty"
	-o Dir::Etc::trusted="$tmp/empty/none.gpg"
	-o Dir::Etc::trustedparts="$tmp/empty"
	-o Dir::State::lists="$tmp/lists"
	-o Dir::State::status="$tmp/status"
	-o Dir::Cache="$tmp/cache"
	-o APT::Get::AllowUnauthenticated=0
	-o APT::Sandbox::User=root
	-q)

echo "verify: $ apt-get update   # sources.list: $(cat "$tmp/sources.list")"
"${apt[@]}" update 2>&1 | tee "$tmp/update.log"
# apt downgrades some trust failures to a warning and exits 0, so scan the output too.
if grep -Eq 'NO_PUBKEY|is not signed|not have a Release file|could not be verified|couldn.t be verified' "$tmp/update.log"; then
	die "apt update reported a trust problem (see above)."
fi

pkgs=$("$reprepro" -b "$root" --list-format '${package}\n' list amber | sort -u)
[ -n "$pkgs" ] || die "archive is empty; nothing to verify."

cd "$tmp/dl"
for p in $pkgs; do
	echo "verify: $ apt-get download $p"
	n=0
	while :; do
		if "${apt[@]}" download "$p"; then break; fi
		n=$((n + 1))
		[ "$n" -lt "$tries" ] || die \
			"$p: download failed after $n attempt(s) over $((n * 5))s — not propagation, the pool and the index disagree"
		[ "$n" = 1 ] && echo "verify: $p not in the pool yet, waiting"
		rm -rf "${tmp:?}/cache/archives/partial"/* 2>/dev/null || true
		sleep 5
	done
done

ls -1 "$tmp/dl"
echo "verify: OK — $(echo "$pkgs" | wc -l) package(s) fetched from $base"
