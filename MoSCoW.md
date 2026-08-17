# MoSCoW

Prioritisation by **Must / Should / Could / Won't have** (the lower-case Os just make it
pronounceable). This is the **scope** document, and it holds only what is **still open**: an
item leaves this file the moment it ships. Nothing here records work done — `git log` is for
that.

An empty band means that band is finished, not that it was never populated.

## Must have

- **The multipart upload path cannot be repeated on this machine.** `tools/r2-sync.sh`
  sends anything over wrangler's 300 MiB cap with `aws s3 cp`, and the `aws` CLI is not
  installed — no binary on `PATH`, no `awscli` module, no pipx entry. The script exits 3
  at that check. `amber-models-llm` is 320 MiB and did reach R2, so the path worked once,
  against a machine state that no longer exists. Either install `awscli` and record it
  alongside the other prerequisites, or the largest package in the archive cannot be
  republished.

## Should have

- **`verify-fresh` compares hashes, so it cannot tell new content from a rebuild.** A
  repo that rebuilds byte-differently but pixel-identically reads as STALE. Measured on
  `amber-theme`: 8005 differing PNGs, all pixel-identical (`AE: 0`), differing only in an
  embedded `date:create` one second apart. The verdict is still worth having — it catches
  a genuinely unpublished change — but "STALE" means "the bytes differ", not "the content
  differs", and reading it as the latter wastes a rebuild.

## Could have

## Won't have (this time)
