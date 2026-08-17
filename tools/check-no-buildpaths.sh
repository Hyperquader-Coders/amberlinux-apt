#!/usr/bin/env bash
# Refuse to publish a .deb that names the machine it was built on.
#
# strip does not remove these: Odin's Source_Code_Location and a meson prefix inside a
# build tree both land in .rodata. Fixes are per-repo —
#   Odin  -> -source-code-locations:filename on the release build
#   meson -> configure with the real --prefix and stage through DESTDIR
#
#   tools/check-no-buildpaths.sh a.deb b.deb ...
set -uo pipefail

[ $# -gt 0 ] || { echo "usage: check-no-buildpaths.sh <deb> [deb...]" >&2; exit 2; }

# Fail only on paths naming the machine that publishes the archive. Third-party
# binaries we repackage (ONNX Runtime, NVIDIA's CUDA providers, the official Odin
# release) carry their own vendors' build paths — /root/usr/include, Alpine's
# /home/buildozer, NVIDIA's /home/scratch.* — which are upstream's to fix, not ours,
# and are reported without failing. HOME is overridable so a CI runner can pass the
# developer path it is checking on behalf of.
PUBLISHER_HOME=${PUBLISHER_HOME:-$HOME}

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fail=0

for deb in "$@"; do
	[ -f "$deb" ] || { echo "check-no-buildpaths: not a file: $deb" >&2; fail=1; continue; }
	pkg=$(dpkg-deb -f "$deb" Package 2>/dev/null || basename "$deb")

	rm -rf "$tmp/x"; mkdir -p "$tmp/x"
	dpkg-deb --fsys-tarfile "$deb" 2>/dev/null | tar -x -C "$tmp/x" 2>/dev/null

	hits=""; foreign=0
	while IFS= read -r f; do
		[ "$(head -c4 "$f" 2>/dev/null | od -An -tx1 | tr -d ' \n')" = "7f454c46" ] || continue
		p=$(strings -a "$f" \
			| grep -aoE '(/home/[A-Za-z0-9_.-]+|/root|/tmp)/[A-Za-z0-9_./+-]*' | sort -u)
		[ -n "$p" ] || continue
		ours=$(grep -F "$PUBLISHER_HOME/" <<<"$p" || true)
		if [ -n "$ours" ]; then
			n=$(grep -c . <<<"$ours")
			hits="$hits${f#"$tmp/x"} :: $(head -1 <<<"$ours")$([ "$n" -gt 1 ] && echo "  (+$((n - 1)) more)")"$'\n'
		fi
		grep -qvF "$PUBLISHER_HOME/" <<<"$p" && foreign=1
	done < <(find "$tmp/x" -type f 2>/dev/null)

	note=""; [ "$foreign" -eq 1 ] && note="  (also carries upstream vendors' own build paths)"
	if [ -n "$hits" ]; then
		echo "LEAK — $pkg names this machine:"
		sed 's/^/    /' <<<"${hits%$'\n'}"
		fail=1
	else
		echo "  ok  $pkg$note"
	fi
done

[ "$fail" -eq 0 ] || { echo "check-no-buildpaths: refusing to publish the above"; exit 1; }
echo "check-no-buildpaths: no package names the machine it was built on"
