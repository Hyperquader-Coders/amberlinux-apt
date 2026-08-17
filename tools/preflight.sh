#!/usr/bin/env bash
# Refuse to touch the archive unless reprepro is present and the archive key can
# actually sign. Without this, a missing key yields a silently unsigned tree that
# only fails on the user's machine, at `apt update`.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
reprepro=${REPREPRO:-reprepro}

die() { echo "preflight: $*" >&2; exit 1; }

command -v "$reprepro" >/dev/null 2>&1 || die \
	"reprepro not found (tried '$reprepro'). Run 'make deps', or set REPREPRO=/path/to/reprepro."
command -v gpg >/dev/null 2>&1 || die "gpg not found. Run 'make deps'."

fpr=$(sed -n 's/^SignWith:[[:space:]]*//p' "$root/conf/distributions" | tr -d '[:space:]')
[ -n "$fpr" ] || die "conf/distributions has no SignWith fingerprint."

gpg --list-secret-keys "$fpr" >/dev/null 2>&1 || die \
	"no secret key $fpr in the default GPG keyring. See README 'Signing key'."

# Listing the key is not enough: it can be expired, revoked or passphrase-locked.
printf 'preflight' | gpg --batch --yes --pinentry-mode error --local-user "$fpr" \
	--detach-sign --output /dev/null 2>/dev/null || die \
	"key $fpr cannot sign unattended (expired, revoked, or passphrase-protected)."

# The README tells users which fingerprint to trust; a rotation that misses it ships a lie.
readme_fpr=$(grep -oE '([0-9A-F]{4} ){5} ([0-9A-F]{4} ){4}[0-9A-F]{4}' "$root/README.md" | tr -d ' ')
[ "$readme_fpr" = "$fpr" ] || die \
	"README fingerprint '$readme_fpr' does not match conf/distributions '$fpr'."

echo "preflight: reprepro OK, signing key $fpr can sign, README fingerprint matches"
