# MoSCoW

Prioritisation by **Must / Should / Could / Won't have** (the lower-case Os just make it
pronounceable). This is the **scope** document, and it holds only what is **still open**: an
item leaves this file the moment it ships. Nothing here records work done — `git log` is for
that.

An empty band means that band is finished, not that it was never populated.

## Must have

## Should have

- **`verify-fresh` compares hashes, so it cannot tell new content from a rebuild.** A
  repo that rebuilds byte-differently but pixel-identically reads as STALE. Measured on
  `amber-theme`: 8005 differing PNGs, all pixel-identical (`AE: 0`), differing only in an
  embedded `date:create` one second apart. The verdict is worth having — it catches a
  genuinely unpublished change — but "STALE" means "the bytes differ", not "the content
  differs", and reading it as the latter wastes a rebuild.

## Could have

## Won't have (this time)
