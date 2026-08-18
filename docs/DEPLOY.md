# Deploying the archive

The archive is served from `apt.amberlinux.org` by its own Cloudflare Worker:
metadata as static assets, `pool/**` from R2. This document says where the tree
goes, what breaks it, and why the alternatives were rejected.

`make deploy` uploads it; `make deploy-all` publishes the flatpak archive in the
same run. Both go out from the machine holding the signing key — see
[the publish sequence](#publish-sequence).

The zone already hosts the main site, `amber-astro` — an Astro static site on
its own Worker, which also owns every redirect host (`.com`, `www`). Its
deployed state is documented in
[`../amber-astro/docs/CLOUDFLARE.md`](../../amber-astro/docs/CLOUDFLARE.md);
what matters here is that it is a **separate** worker, so nothing the site
does can touch the archive.

## Decision: a separate Worker on `apt.amberlinux.org`

The alternative was `amberlinux.org/apt`, dropping the tree into the site's
`public/`. It costs no DNS work and has one deploy story. It is rejected, for
four reasons in descending order of severity.

**1. `html_handling` is one setting for a whole deployment, and the two trees
want opposite values.** Cloudflare's asset server defaults to
`auto-trailing-slash`: for `/foo` it tries the exact asset, then `/foo.html`,
then `/foo/index.html` — and the last of those answers with a **307 redirect to
`/foo/`**. The site depends on that: Astro's default `build.format: 'directory'`
means every page is `index.html` inside a directory. An apt tree wants
`html_handling: "none"`, where a path is either an exact asset or a 404, so
`dists/amber/InRelease` can never become a redirect. Sharing a deployment means
betting the archive on Cloudflare's match order (exact asset beats `.html` beats
`index.html`) never changing. It is a bet we do not have to take.

**2. The site's 404 behaviour is apt-safe today by luck, and one word from
being fatal.** `not_found_handling: "404-page"` returns `dist/404.html` with a
real HTTP 404, which is what apt needs — it probes paths that legitimately do
not exist (`Release.gpg`, `by-hash/`, `i18n/Translation-en*`, `Contents-*`,
`.diff/Index`) on every update. Had that key been
`single-page-application`, every probe would return **200 with an HTML body**
and apt would fail with hash and format errors that read like archive
corruption. Nothing in the site repo says that key is load-bearing for anything
but the website. A separate deployment removes the coupling instead of
documenting it.

**3. Blast radius and cadence.** `wrangler deploy` re-uploads the whole asset
manifest as one new version. Shared, a website typo fix republishes the archive
and an archive publish redeploys the website. The site repo has no
preview/production split, so there is no staging rehearsal either.

**4. Git.** The site commits `public/` and its maintenance workflow includes a
history-squashing `force-push` target. Putting `.deb` payloads under
`public/apt/` writes binaries into that history permanently, and the site's
`.gitattributes` (`* text=auto eol=lf`) would need binary markers for `.deb`
and `.gz`. This repo already refuses to commit `out/`; the subdomain keeps that
true.

The cost is one dashboard action — an `apt` record and a Worker custom domain in
a zone Cloudflare already manages — and a second deploy path. The dashboard part
is genuinely a downside: no zone configuration is in git anywhere in the suite,
so it must be written down (below) or it is lost.

## Shape

```
amberlinux-apt/
  out/                     <- reprepro's output, the asset directory
  cloudflare/
    wrangler.jsonc         <- assets.directory = ../out
    _headers               <- copied to out/_headers at publish time
    robots.txt             <- copied to out/robots.txt at publish time
```

`out/` is gitignored and regenerated, so anything the CDN needs at the tree root
must be copied in by the publish step, not stored there. `reprepro export`
rewrites `dists/` and manages `pool/`; it leaves unrelated root files alone, but
`make clean` does not.

```jsonc
{
  "name": "amberlinux-apt",
  "compatibility_date": "2026-06-21",
  "main": "worker.js",
  "assets": {
    "binding": "ASSETS",
    "directory": "../out",
    "html_handling": "none",
    "not_found_handling": "none",
    "run_worker_first": true,
  },
  "r2_buckets": [
    { "binding": "POOL", "bucket_name": "amberlinux-apt-pool" },
  ],
  "routes": [
    { "pattern": "apt.amberlinux.org", "custom_domain": true },
  ],
}
```

The worker does three things and nothing else: 301s plain HTTP to https,
serves `pool/**` from R2, and maps `/` to the landing page; every other path
falls through to the assets. `html_handling: "none"` is the point of the whole
exercise. `not_found_handling: "none"` gives apt a bare 404 rather than a
15 KB HTML body on every optional probe.

Pin wrangler. The site repo does not have it as a dependency at all, so every
deploy resolves `npx wrangler` to whatever is latest that day — and asset-server
semantics are baked into the deployed configuration. Use
`npx wrangler@<version> deploy` or a `devDependencies` pin.

## The extension-less files

This is the risk the layout is chosen around, so it is stated precisely.

`dists/amber/InRelease`, `Release`, `Release.gpg` and
`dists/amber/main/binary-amd64/Packages` have no file extension, and apt
requires them **byte-for-byte** — `InRelease` is a clearsigned document, and
`Release` carries the SHA256 of `Packages` which carries the SHA256 of every
`.deb`. A redirect, a rewrite, a re-compression or a stray byte breaks the
chain, and apt's error message points at the archive rather than the CDN.

What the pieces actually do:

| Layer | Behaviour | Verdict |
| --- | --- | --- |
| Astro | never sees them — a separate Worker, `directory: "../out"` | safe |
| Astro, if under `public/` | `public/` is copied verbatim, no renaming, no extension inference; `astro build` wipes `dist/` first, so a post-build write would vanish | safe but fragile |
| `html_handling: "none"` | exact asset or 404; no `.html` probing, no 307 | safe by construction |
| `html_handling: "auto-trailing-slash"` (default) | exact asset wins over `.html` and `index.html`, so it *probably* serves them — an argument from match order, not a guarantee | avoided |
| `not_found_handling: "none"` | real 404 status for missing probes | required |
| `not_found_handling: "single-page-application"` | 200 + HTML for every missing probe | **fatal** |
| Content-Type | inferred from extension; no extension means `application/octet-stream` | harmless, apt ignores it |
| `Packages.gz` | must **not** carry `Content-Encoding: gzip`, or the client decompresses twice | must be checked |
| The site's canonicalising Worker | `apt.amberlinux.org` is a custom domain on this repo's own worker, so the site's worker never sees archive traffic | not a factor |

`tools/verify-client.sh` already enforces the checkable half of that table over
real HTTP: no redirects, bytes identical to `out/`, no `Content-Encoding` on
`Packages.gz`, 404 for a missing path, then a real `apt-get update` and a
download of every package. `make verify-http` runs it against a local server;
`make verify-http BASE=https://apt.amberlinux.org` runs the same assertions
against the deployed tree, and is the post-deploy smoke test.

### Headers

```
/*
  Strict-Transport-Security: max-age=31536000
/dists/*
  Cache-Control: no-cache
/amberlinux-archive-keyring.gpg
  Cache-Control: public, max-age=3600
/packages.json
  Cache-Control: no-cache
  Access-Control-Allow-Origin: *
```

`dists/` must revalidate: a cached `InRelease` paired with a fresh `Packages` is
exactly the mismatch that makes apt report a hash failure.

The worker serves pool objects `immutable` with a one-year cache. That header is a
claim about the **path**, not about the bytes behind it: while versions are held
before v1 a rebuild republishes the same path with different content, so what keeps
it safe is § Atomicity's argument — the worker reads R2 per request and its
responses are not edge-cached — rather than the objects genuinely never changing.
The header reaches clients and any intermediary cache, of which this archive has
none; if one ever appears in front of it, that is the reason to bound the `max-age`.

`_headers` only applies to static assets, so anything the worker serves gets its
headers from the worker, HSTS included — a `/pool/*` rule added there would be
silently ignored.

TLS is enforced, not offered: the worker 301s plain HTTP to https and every
response carries HSTS. Signatures prove origin, not freshness — on plain HTTP
an on-path attacker can stall or replay an older validly signed `InRelease` —
so transport is the only replay defence a client gets.

`_headers` must sit at the **root of the assets directory** — `out/_headers` —
which is why the tracked copy lives in `cloudflare/` and the publish step copies
it in.

`robots.txt` should `Disallow: /`. There is nothing here worth crawling and the
pool is the largest thing the suite serves.

## Atomicity

**Greenfield exception: until Amberlin v1 ships, suite packages republish
under the SAME version rather than bumping.** This is safe in the deployed architecture specifically because
pool/** is served by the worker straight from R2 — worker responses are
not edge-cached, so overwritten objects serve immediately; the immutable
Cache-Control only reaches clients, and apt does not cache debs. The
moment real users exist, versions bump again and the rule below is the
rule.

A `wrangler deploy` swaps to a new version atomically, but an apt client's work
is not one request. It fetches `InRelease`, then `Packages`, then — possibly
days later, on `apt install` — a pool file.

- **The pool is append-only in practice.** A pool path contains the version, and
  `make add` only ever adds, so a client holding a stale `Packages` can still
  fetch what it names after a publish. This is what makes the deploy safe
  without any coordination.
- **`make remove` is the operation that breaks that**, because it deletes the
  pool file. Never remove a version users may hold; supersede it with a higher
  one. `make remove` is for mistakes caught before the first upload. The
  Makefile comment says so and points here.
- **The `InRelease` → `Packages` window** is one deployment version and flips
  together, so the only exposure is an edge serving a cached `InRelease` beside
  a fresh `Packages`. The `no-cache` header on `dists/*` closes it.
- **`Acquire-By-Hash` is not available.** reprepro 5.3 does not emit `by-hash/`
  directories, so the standard mitigation for exactly this window is off the
  table. If the window ever bites, that is the reason to look at a different
  archive tool, not at more caching rules.

## The size wall

Workers Static Assets caps a deployment at **20,000 files** and any single file
at **25 MiB**. The file count is not a concern — a six-package pool is dozens of
files. The per-file cap already is:

| Package | Size today | |
| --- | --- | --- |
| `amber-models-llm` | **320 MB** (Qwen2.5-0.5B int8) | **over the cap, and over wrangler's 300 MiB CLI ceiling too — the only file needing S3 multipart** |
| `amber-models-tts` | **80 MB** (Kokoro int8 + 54 voices) | **over the cap** |
| `amberlin-runtime-cuda` | **123.3 MB** | **over the cap** |
| `kat800` | 16.7 MB (bundles VTE and GTK) | 8 MB of headroom, and growing |
| `amber-models-stt` | 99 MB (Moonshine tiny) | **over the cap** |
| `amberlin-runtime` | 6.2 MB | |
| `copal` | 1.7 MB | |
| `ambrosia` | 0.2 MB | |
| `amberlin` | 0.1 MB | |

So this is not a future problem. `amberlin-runtime-cuda` landed while this plan
was being written and **cannot be served as a static asset at all**; the
weights package landed after it and is six times worse. Static assets alone are
therefore not a viable end state, only a viable first step for the five small
packages.

The answer: keep `dists/**` as static assets and move `pool/**` to R2 behind a
Worker route.

**Upload path (learned on the models packages): `wrangler r2 object put` caps
at 300 MiB.** The LLM package is over it, so `tools/r2-sync.sh` uploads files
over that cap with `aws s3 cp` against the R2 S3 endpoint, gated on
R2_ACCESS_KEY_ID / R2_SECRET_ACCESS_KEY (an R2 API token from the dashboard).
`R2_ACCOUNT_ID` is required too — it names the account and is deliberately not in
this repo; the amber tree's `mise.toml` sets it.
The worker serving path is unaffected — objects read back identically however
they were written. Small pool files still take the wrangler path (no token
needed).
Metadata stays byte-exact and cheap; payloads become an R2 `get` with the object
key taken from the path. That requires `main`, an `r2_buckets` binding,
`run_worker_first: ["/pool/*"]`, and an upload step that syncs `out/pool` to the
bucket before the assets deploy. Nothing else about the archive changes —
reprepro's layout, the signing, and the client `sources.list` line are all the
same, and `make verify-http BASE=…` tests the result identically.

Sequencing, then: ship the static-asset deployment first and leave
`amberlin-runtime-cuda` out of it, or do the R2 route before the first upload.
Publishing a `Packages` index that names a pool file the CDN refuses to serve is
the worst of the three options — apt would resolve the dependency and then fail
to fetch it.

## Publish sequence

```sh
make deploy    # publish, R2-sync pool/**, copy CDN root files, wrangler deploy,
               # then verify-http against the live domain
```

Two traps encoded in `cloudflare/`, easy to re-discover:

- apt percent-encodes `+` in versions (`2026.08%2bdev`); `URL.pathname`
  preserves the encoding while R2 keys hold literal bytes, so the worker
  `decodeURIComponent`s before the R2 `get`. The 404 only appears on a
  package with a `+` in its version.
- `html_handling: "none"` also disables `/` → `index.html`, and a bare `"/"`
  pattern in `run_worker_first` does not match; the config uses
  `run_worker_first: true` and the worker maps `/` to the landing page
  itself. `make verify-http BASE=…` proves assets stay byte-exact and
  `_headers` still apply on the worker path.


The last line is not optional. It is the only step that tests the CDN rather
than the tree, and it is the same assertions that pass locally, so a difference
is the CDN's.

## Dashboard state

Not in git anywhere, so recorded here: worker `amberlinux-apt`, R2 bucket
`amberlinux-apt-pool`, custom domain `apt.amberlinux.org` — created by
`wrangler deploy` from the `routes` entry, no dashboard step needed.

1. `apt.amberlinux.org` — the Worker custom domain on the `amberlinux.org`
   zone (wrangler created the DNS record).
2. Confirm no zone-level Redirect Rule, Transform Rule or Page Rule matches
   `apt.*`. The `.com` → `.org` redirect lives in the *other* zone's dashboard,
   per the site repo's commit `fa7760a`, but zone rules are invisible from any
   repository and are the one thing that could reintroduce a redirect on
   `InRelease` after everything above is correct.
3. Leave Auto Minify and Rocket Loader off for the zone. They only touch
   HTML/CSS/JS by content type, and these files have none — but "only touches
   HTML" is exactly the kind of assumption this document exists to not rely on.
   `make verify-http BASE=…` is what actually settles it.
