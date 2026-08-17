#!/usr/bin/env bash
# Every package the archive holds must be byte-identical to what its repo
# currently builds. verify-client.sh proves the tree is signed and consumable;
# it passes just as happily on a package built hours ago.
#
# Compares the SHA256 in the exported Packages index against each repo's
# `make deb-path` output. A repo that has never built is skipped with a note,
# not treated as fresh.
#
# conf/hold names repos under active development, whose packages are expected to
# lag. They report as `held` and do not fail the gate — see that file for why,
# and for the rule that a hold pauses re-publication rather than withdrawing
# anything already published.
set -eu -o pipefail

OUT=${OUT:-out}
CODENAME=${CODENAME:-amber}
SUITE=${SUITE:?verify-fresh: SUITE not set}
HOLD_FILE=${HOLD_FILE:-conf/hold}
INDEX="$OUT/dists/$CODENAME/main/binary-amd64/Packages"

test -f "$INDEX" || { echo "verify-fresh: no $INDEX — run make build first" >&2; exit 2; }

# Held repo names, comments and blank lines stripped, flattened to one
# space-separated line so the `case` match below can anchor on spaces. Absent
# file = hold nothing.
HELD=""
if [ -f "$HOLD_FILE" ]; then
	HELD=$(sed -e 's/#.*//' -e 's/[[:space:]]//g' "$HOLD_FILE" | grep -v '^$' | tr '\n' ' ' || true)
fi
is_held() { # is_held REPO_DIR
	case " $HELD " in *" $(basename "$1") "*) return 0 ;; *) return 1 ;; esac
}

stale=0 checked=0 skipped=0 missing=0 held=0
held_names=""
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
			# Held: the difference is expected, so report it and keep the exit
			# code clean. Still printed with both hashes — a hold makes the lag
			# allowed, not invisible.
			if is_held "$repo"; then
				echo "  held     $pkg: archive has ${have:0:12}…, $repo builds ${want:0:12}…"
				held=$((held + 1))
				case " $held_names " in *" $(basename "$repo") "*) ;;
					*) held_names="$held_names $(basename "$repo")" ;; esac
			else
				echo "  STALE    $pkg: archive has ${have:0:12}…, $repo builds ${want:0:12}…"
				stale=$((stale + 1))
			fi
		else
			echo "  ok       $pkg"
		fi
	done
done

if [ "$stale" -ne 0 ]; then
	echo "verify-fresh: $stale package(s) older than their repo — 'make add-suite', then stage again" >&2
	exit 1
fi
# Held repos are named on their own line, not folded into the counts: the whole
# point is that a hold is visible to whoever reads a passing report.
echo "verify-fresh: $((checked - missing - held)) package(s) match their repo's current build ($missing absent, $skipped skipped, $held held)"
if [ "$held" -ne 0 ]; then
	echo "verify-fresh: held by $HOLD_FILE —$held_names (their published versions stay served)"
fi
