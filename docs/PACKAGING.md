# PACKAGING — the suite's Makefile contract

Every Amber Linux repository that produces a `.deb` answers the same target
names, so one command means one thing everywhere and the archive can ingest the
suite without knowing anything about how each project builds.

This is an entry-point contract. It deliberately says nothing about *how* a repo
builds — kat800 bundles VTE and GTK from source, copal renders a logo through a
Python venv, amberlin-runtime unpacks an upstream tarball. Those stay as they
are.

## The targets

| Target | Contract |
| --- | --- |
| `deps` | install the system build dependencies (`sudo apt install …`) |
| `check` | the fast static check; no link, no package |
| `build` | build the project's primary artefact |
| `lint` | package sanity: desktop entries, man pages, lintian where it passes |
| `ci` | the full local gate, in the order the workflow runs it; ends `CI OK` |
| `deb` | build the binary package into `dist/` |
| `deb-path` | print the absolute path of every package the repo publishes, one per line, and nothing else |
| `deb-install` | `deb`, then install it locally |
| `deb-remove` | `sudo apt remove` the package |
| `clean` | delete all generated output |

`deb-path` is the load-bearing one. `make add-suite` in this repository asks
each repo where its package is rather than hardcoding a path, so a repo can
rename or move its output without breaking the archive. It must print paths and
nothing else — no progress text, no build. `tools/lint.sh` checks that every
repo listed below answers it.

**Three directories, one meaning each.**

| | |
| --- | --- |
| `build/` | sources fetched or compiled from upstream, and compile intermediates |
| `out/` | packaging staging — `out/deb`, `out/shlibwork` |
| `dist/` | the finished `.deb`, and nothing else |

Every repo follows this. Four have a `build/`: amber-gtk4 (the GTK tree),
amber-odin (the Odin release and the ols checkout), kat800 (VTE, plus generated
icons and locales), yggr (an object file and the binary). None of them stage a
package there, so cleaning a vendored tree never costs the staging and the other
way round.

`out/` must be in `.gitignore` before it exists — `force-push` runs `git add -A`.

## Provenance

Where each package in the archive comes from. `make list` is what is actually
ingested; this is where it was built.

| Repo | Package | Builds with | Lands in |
| --- | --- | --- | --- |
| `amber-fonts` | `amber-fonts` | `make deb` (no build; the suite's SauceCodePro faces, both cuts, staged into `out/deb`) | `dist/amber-fonts_<v>-1_all.deb` |
| `amber-desktop` | `amber-desktop` | `make deb` (metapackage; no payload, the Depends line is the product) | `dist/amber-desktop_<v>-1_all.deb` |
| `amber-gtk4` | `amber-gtk4` | `make deb` (GTK 4.16 from upstream tarball, configured `--prefix=/usr --libdir=lib/amber-gtk4` and staged through `DESTDIR`, stripped) | `dist/amber-gtk4_<v>-1_amd64.deb` |
| `amber-odin` | `amber-odin`, `amber-ols` | `make deb-upstream` (fetches the official compiled Odin release, sha256-verified against the GitHub API; compiles ols from source with that exact compiler) | `dist/amber-{odin,ols}_<YYYY.MM>+dev-1_amd64.deb` |
| `amber-theme` | `amber-theme` | `make deb` (Dart Sass compiles five profiles of GTK3/GTK4/libadwaita/Cinnamon CSS, `build-icons.sh` recolours the folder icon themes, both staged into `out/deb`) | `dist/amber-theme_<v>-1_all.deb` |
| `amberlin` | `amberlin` | `make deb` (Odin/GTK4 → `out/deb` staging) | `dist/amberlin_<v>-1_amd64.deb` |
| `amberlin-backend` | `amberlin-backend` | `make deb` (Odin/GLib D-Bus service; models load at runtime) | `dist/amberlin-backend_<v>-1_amd64.deb` |
| `amberlin-settings` | `amberlin-settings` | `make deb` (Odin/GTK4, unstripped and linked `-rdynamic` so the crash log can name its own frames; GTK comes from `amber-gtk4`, the model catalogue from `amberlin-backend`) | `dist/amberlin-settings_<v>-1_amd64.deb` |
| `amber-models` | `amber-models-tts`, `amber-models-stt`, `amber-models-llm`, `amber-models` | `make deb` (`dpkg-buildpackage`, six sha256-pinned upstream artefacts staged into `out/models`; the voices and the LM vocabulary generated from them, plus a metapackage that pulls all three modalities) | `dist/amber-models{,-tts,-stt,-llm}_<v>-<r>_all.deb` |
| `amberlin-runtime` | `amberlin-runtime`, `amberlin-runtime-cuda`, `amberlin-runtime-dev` | `make deb` (`dpkg-buildpackage`, upstream ONNX Runtime CPU and GPU tarballs) | `dist/amberlin-runtime{,-cuda,-dev}_<v>-<r>_amd64.deb` |
| `ambrosia` | `ambrosia` | `make deb` (Odin/GTK3 → `out/deb` staging) | `dist/ambrosia_<v>-1_amd64.deb` |
| `copal` | `copal` | `make deb` (Odin/GTK3, rasterises the logo first) | `dist/copal_<v>-1_amd64.deb` |
| `kat800` | `kat800` | `make deb` (Odin/GTK4; bundles VTE 0.84 from `make vte`, GTK comes from `amber-gtk4`) | `dist/kat800_<v>-1_amd64.deb` |

## Not ingested

| Repo | Package | Why | Builds with |
| --- | --- | --- | --- |
| `amber-models-llm` | the 320 MB language model | Over wrangler's 300 MiB object cap, so an archive that ingests it publishes an index naming a pool file it cannot serve. Multipart upload needs an R2 API token and the `aws` CLI; without them `tools/r2-sync.sh` stops rather than serve a broken index. | `make deb` in `amber-models` |
| `amber-models` (metapackage) | pulls in all three modalities | `Depends:` on `amber-models-llm`, so publishing it while that is absent would offer an uninstallable package. | `make deb` in `amber-models` |

Both are still built and still wanted. They are held back by `amber-models`'
`PUBLISHABLE` list rather than by an omission from `SUITE` — the repo is ingested,
and the decision about which of its packages can be served lives next to the
packages. Add them to that list in the same change that adds the credentials.

`amberlin-runtime` is the only repo shipping more than one package — three of
them — so it is the reason `deb-path` prints one path *per line* rather than one
path. `amberlin-runtime-cuda`
is 123 MB and does not fit under Cloudflare's 25 MiB per-file cap — see
`DEPLOY.md` § The size wall, which that package turned from a future concern
into a blocker on the first upload.

The model weights are the archive's largest packages by two orders of magnitude —
499 MB of Kokoro, Moonshine and Qwen2.5 across three, and the only
`Architecture: all` ones. They are split by modality rather than shipped as one
package because the three change at entirely different rates, and because a
speech-only machine has no reason to carry a language model.

Not a byte of any of them is committed: `upstream.sha256` pins the six downloads,
`payload.sha256` pins all 64 staged files including the two generated at build
time, and its `make verify` unpacks all three `.deb`s over one another and
re-hashes every file in the reassembled tree — which is what proves the split
moved files between packages and never between paths.

`amber-odin` tracks upstream's monthly compiled release: its GitHub Action
(`monthly-release.yml`) fetches each new `dev-YYYY-MM`, packages it, and
publishes the deb on that repo's GitHub releases; `make add-suite` here
ingests whatever its `dist/` holds (newest build wins).

## Divergences

Recorded rather than forced.

- **kat800's `deps` is an alias for `install`.** `install` predates the suite's
  naming and reads as "install the app" to everyone else, so both exist.
- **kat800 has no CI workflow.** `make ci` is the whole gate there.
- **amberlin-runtime's `build` is `fetch`.** It compiles nothing of its own.
- **amberlin-runtime publishes three packages.** The CPU runtime, the CUDA
  variant, and `amberlin-runtime-dev` — the unversioned `libonnxruntime.so`
  symlink, which the runtime packages omit because only a compiler needs it.
  `deb-path` prints all three, one per line, and `make add-suite` reads every
  line.
- **amberlinux-apt has no `deb`.** It publishes an archive, not a package. It
  answers `deps`, `check`, `lint`, `ci` and `clean`; `stage` is its `build`.
