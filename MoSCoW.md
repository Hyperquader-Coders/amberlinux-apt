# MoSCoW

Prioritisation by **Must / Should / Could / Won't have** (the lower-case Os just make it
pronounceable). This is the **scope** document, and it holds only what is **still open**: an
item leaves this file the moment it ships. Nothing here records work done — `git log` is for
that.

An empty band means that band is finished, not that it was never populated.

## Must have

## Should have

- **`verify-fresh` has no way to say "this repo is mid-change, leave it".** It gates
  `stage`, and it fails on any suite package whose repo builds different bytes — which is
  the normal state of a repo someone is working in. Publishing one repo's fix therefore
  means either republishing everyone's work in progress or narrowing `SUITE` by hand on
  the command line, and the second is a judgement call made under pressure with no record
  of what was skipped. A `HOLD` list read from a file, reported as `held` rather than
  `STALE` and excluded from the failure count, makes the decision explicit and reviewable.

- **`verify-fresh` compares hashes, so it cannot tell new content from a rebuild.** A
  repo that rebuilds byte-differently but pixel-identically reads as STALE. Measured on
  `amber-theme`: 8005 differing PNGs, all pixel-identical (`AE: 0`), differing only in an
  embedded `date:create` one second apart. The verdict is worth having — it catches a
  genuinely unpublished change — but "STALE" means "the bytes differ", not "the content
  differs", and reading it as the latter wastes a rebuild.

## Could have

## Won't have (this time)
