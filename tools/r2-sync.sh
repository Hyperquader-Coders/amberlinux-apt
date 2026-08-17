#!/usr/bin/env bash
# Upload out/pool/** to the R2 bucket the worker serves from. Pool paths
# embed the package version, so objects never change once written: a key
# that already exists remotely is skipped by comparing against a manifest
# of what this script has uploaded before (.r2-synced, gitignored).
#
# Two upload paths, chosen by size: `wrangler r2 object put` handles files
# up to its 300 MiB CLI ceiling; anything larger (the amber-models
# weights) needs S3 multipart, which requires an R2 API token. Set
# R2_ACCESS_KEY_ID + R2_SECRET_ACCESS_KEY (create one in the Cloudflare
# dashboard → R2 → Manage API tokens) and this uses `aws s3 cp` against
# the R2 S3 endpoint. Without them, large files fail loudly rather than
# silently skipping — a Packages index naming an unservable pool file is
# the worst outcome (see docs/DEPLOY.md § The size wall).
set -eu -o pipefail

BUCKET=${BUCKET:-amberlinux-apt-pool}
OUT=${OUT:-out}
WRANGLER=${WRANGLER:-npx wrangler@4.121.0}
ACCOUNT_ID=${R2_ACCOUNT_ID:?set R2_ACCOUNT_ID (Cloudflare dashboard -> R2). Kept out of the repo.}
WRANGLER_CAP=$((300 * 1024 * 1024))
MANIFEST=.r2-synced

test -d "$OUT/pool" || { echo "r2-sync: $OUT/pool missing — run make stage first" >&2; exit 2; }
touch "$MANIFEST"

put_large() { # key file
	if [ -z "${R2_ACCESS_KEY_ID:-}" ] || [ -z "${R2_SECRET_ACCESS_KEY:-}" ]; then
		echo "r2-sync: $1 exceeds wrangler's 300 MiB cap and needs S3 multipart." >&2
		echo "  Create an R2 API token (dashboard → R2 → Manage API tokens) and set" >&2
		echo "  R2_ACCESS_KEY_ID and R2_SECRET_ACCESS_KEY, then re-run." >&2
		exit 3
	fi
	# The tree provisions awscli itself (the root mise.toml's [tools]), so a
	# missing `aws` almost always means this ran outside mise rather than that
	# anything needs installing — say that instead of sending the operator off to
	# pip, which would leave a second copy shadowing the pinned one.
	command -v aws >/dev/null || {
		echo "r2-sync: no aws on PATH. It is provisioned by the tree's mise.toml —" >&2
		echo "  run this under mise (\`mise exec -- make deploy\`) or from a mise shell." >&2
		exit 3
	}
	# Three environment settings, none of them optional against R2:
	#
	#   AWS_DEFAULT_REGION  R2 has no regions but the S3 protocol demands one, and the CLI
	#                       refuses to sign without it. `auto` is the value R2 documents.
	#   *_CHECKSUM_*        aws-cli v2 sends CRC32 full-object checksums on multipart by
	#                       default, which R2 rejects outright. `when_required` stops the
	#                       CLI volunteering them. Untested here — no token existed when
	#                       this was written — so if a first upload fails on a header named
	#                       x-amz-checksum-*, this is the line to look at.
	AWS_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID" AWS_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY" \
		AWS_DEFAULT_REGION=auto \
		AWS_REQUEST_CHECKSUM_CALCULATION=when_required \
		AWS_RESPONSE_CHECKSUM_VALIDATION=when_required \
		aws s3 cp "$2" "s3://$BUCKET/$1" \
		--endpoint-url "https://$ACCOUNT_ID.r2.cloudflarestorage.com" \
		--content-type application/vnd.debian.binary-package >/dev/null
}

uploaded=0 skipped=0
while IFS= read -r -d '' f; do
    key=${f#"$OUT"/}
    sum=$(sha256sum "$f" | cut -d' ' -f1)
    if grep -q "^$sum  $key\$" "$MANIFEST"; then
        skipped=$((skipped + 1))
        continue
    fi
    echo "r2-sync: put $key ($(du -h "$f" | cut -f1))"
    if [ "$(stat -c%s "$f")" -gt "$WRANGLER_CAP" ]; then
        put_large "$key" "$f"
    else
        $WRANGLER r2 object put "$BUCKET/$key" --file "$f" --remote \
            --content-type application/vnd.debian.binary-package >/dev/null
    fi
    echo "$sum  $key" >> "$MANIFEST"
    uploaded=$((uploaded + 1))
done < <(find "$OUT/pool" -type f -print0)

echo "r2-sync: $uploaded uploaded, $skipped already present"
