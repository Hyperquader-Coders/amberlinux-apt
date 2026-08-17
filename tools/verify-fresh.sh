#!/usr/bin/env bash
# Every package the archive holds must be byte-identical to what its repo
# currently builds. verify-client.sh proves the tree is signed and consumable;
# it passes just as happily on a package built hours ago.
#
# Compares the SHA256 in the exported Packages index against each repo's
# `make deb-path` output. A repo that has never built is skipped with a note,
# not treated as fresh.
set -eu -o pipefail

OUT=${OUT:-out}
CODENAME=${CODENAME:-amber}
SUITE=${SUITE:?verify-fresh: SUITE not set}
INDEX="$OUT/dists/$CODENAME/main/binary-amd64/Packages"

test -f "$INDEX" || { echo "verify-fresh: no $INDEX — run make build first" >&2; exit 2; }

stale=0 checked=0 skipped=0 missing=0
for repo in $SUITE; do
	[ -d "$repo" ] || { echo "  skip  $repo (not checked out)"; skipped=$((skipped + 1)); continue; }
	# --no-print-directory: under a parent make invoked with -C, MAKEFLAGS
	# carries --print-directory into this sub-make, and the Entering/Leaving
	# banners land in the captured paths — which then "are not built", and the
	# freshness gate silently skips every sibling.
	paths=$(make --no-print-directory -C "$repo" -s deb-path 2>/dev/null) || {
		echo "  skip  $repo (no deb-path)"; skipped=$((skipped + 1)); continue; }
	for deb in $paths; do
		[ -f "$deb" ] || { echo "  skip  $(basename "$deb") (not built)"; skipped=$((skipped + 1)); continue; }
		pkg=$(dpkg-deb -f "$deb" Package)
		want=$(sha256sum "$deb" | cut -d' ' -f1)
		have=$(awk -v p="$pkg" '$1=="Package:"&&$2==p{f=1} f&&$1=="SHA256:"{print $2; exit}' "$INDEX")
		checked=$((checked + 1))
		if [ -z "$have" ]; then
			# Absent is visible to users the moment they try to install it;
			# stale is the failure nothing else catches.
			echo "  absent   $pkg is not in the archive"
			missing=$((missing + 1))
		elif [ "$have" != "$want" ]; then
			echo "  STALE    $pkg: archive has ${have:0:12}…, $repo builds ${want:0:12}…"
			stale=$((stale + 1))
		else
			echo "  ok       $pkg"
		fi
	done
done

if [ "$stale" -ne 0 ]; then
	echo "verify-fresh: $stale package(s) older than their repo — 'make add-suite', then stage again" >&2
	exit 1
fi
echo "verify-fresh: $((checked - missing)) package(s) match their repo's current build ($missing absent, $skipped skipped)"
