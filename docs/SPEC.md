# SPEC — what the archive is

The source of truth for what this repository publishes and what a client can
rely on. `ARCHITECTURE.md` is the how, `DEPLOY.md` the plan for getting it
online, `PACKAGING.md` the contract with the projects that feed it.

## The archive

One distribution, one component, one architecture.

| | |
| --- | --- |
| Origin / Label | `AmberLinux` |
| Codename / Suite | `amber` |
| Components | `main` |
| Architectures | `amd64` |
| Target | Linux Mint 22+ (Ubuntu noble) |
| Layout | standard Debian pool, produced by reprepro |
| Signing key | `481A 11AA 5483 3219 6B29  0D09 C5B0 67A7 99C4 3065` |
| Base URL (planned) | `https://apt.amberlinux.org/` |

`Architectures` lists `amd64` only. `all` must **not** be listed: reprepro
rejects it outright, and folds `Architecture: all` packages into every listed
binary index — which is where they belong, so
`dists/amber/main/binary-amd64/Packages` serves them correctly.

Besides the apt tree, `make build` publishes two human/site-facing files:
`index.html` (a static landing page, copied verbatim from `static/` — it
links to the package directory on amberlinux.org and never needs updating
per release) and `packages.json` (generated from the signed Packages index
by `tools/packages-json.py`; the amberlinux.org `/packages/` page renders
from it at site build time, so the site cannot drift from the archive).

## What it contains

Whatever the suite builds. `make list` is authoritative; the
provenance of each package — which repo and which target produces it — is
`PACKAGING.md`.

## Client contract

```sh
sudo curl -fsSL -o /usr/share/keyrings/amberlinux-archive-keyring.gpg \
  https://apt.amberlinux.org/amberlinux-archive-keyring.gpg

echo 'deb [arch=amd64 signed-by=/usr/share/keyrings/amberlinux-archive-keyring.gpg] https://apt.amberlinux.org amber main' \
  | sudo tee /etc/apt/sources.list.d/amberlinux.list

sudo apt update
```

The client should check the key before trusting it:

```sh
gpg --show-keys /usr/share/keyrings/amberlinux-archive-keyring.gpg
#   481A 11AA 5483 3219 6B29  0D09 C5B0 67A7 99C4 3065
#   Amber Linux Archive Signing Key <apt@amberlinux.org>
```

Removing the repository means deleting both files.

Guarantees:

- `dists/amber/InRelease` is always clearsigned by the key above. An unsigned or
  differently-signed tree cannot be produced: `tools/preflight.sh` runs before
  every archive operation and refuses if the key cannot sign unattended.
- A pool path is **append-only**: `make add` only ever adds, and a published
  version is superseded rather than removed, so a client holding an older
  `Packages` can still fetch what it names. `make remove` is the one operation
  that breaks this; see `DEPLOY.md` § Atomicity.
- A pool path's **contents** are not fixed, and nothing here depends on them
  being. Versions are held rather than bumped before v1, so a rebuilt package
  republishes under the same path with different bytes. What makes that safe is
  that the worker reads R2 on every request — `DEPLOY.md` § Atomicity has the
  full argument. The name being stable and the bytes being stable are two
  different claims and only the first one holds.
- Index files are served byte-exact, with no redirect and no re-encoding. This
  is a property of the CDN rather than the tree, so it is asserted rather than
  assumed: `make verify-http BASE=…` checks it against whatever is deployed.

## Not in scope

- Source packages. Binary `.deb` only; the suite's sources are the sibling
  repositories.
- Architectures other than `amd64`.
- Older Ubuntu or Debian bases. One suite, one target.
