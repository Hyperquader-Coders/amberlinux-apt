# amberlinux-apt

The apt repository for the **Amber Linux** suite — [amberlin](../amberlin),
[ambrosia](../ambrosia), [copal](../copal), [kat800](../kat800) and
[amberlin-runtime](../amberlin-runtime). Built with **reprepro** in the standard
Debian pool layout, signed with the Amber Linux archive key, and published as a
plain static tree to **https://apt.amberlinux.org/**.

One suite, `amber`, one component, `main`, targeting Linux Mint 22+ (Ubuntu
noble).

## Install on a client

```sh
sudo curl -fsSL -o /usr/share/keyrings/amberlinux-archive-keyring.gpg \
  https://apt.amberlinux.org/amberlinux-archive-keyring.gpg

echo 'deb [arch=amd64 signed-by=/usr/share/keyrings/amberlinux-archive-keyring.gpg] https://apt.amberlinux.org amber main' \
  | sudo tee /etc/apt/sources.list.d/amberlinux.list

sudo apt update
sudo apt install kat800
```

Check the key before trusting it — it should be:

```sh
gpg --show-keys /usr/share/keyrings/amberlinux-archive-keyring.gpg
#   481A 11AA 5483 3219 6B29  0D09 C5B0 67A7 99C4 3065
#   Amber Linux Archive Signing Key <apt@amberlinux.org>
```

To remove the repository, delete `/etc/apt/sources.list.d/amberlinux.list` and
`/usr/share/keyrings/amberlinux-archive-keyring.gpg`.

## Maintaining the archive

```sh
make deps          # apt install reprepro gnupg
make add-suite     # ingest the current .deb from every suite repo
make add DEB=…     # or one file
make list          # what is in the archive
make stage       # export, sign, and verify with a real apt client
make serve         # http://127.0.0.1:8000 for poking at by hand
make ci            # lint + publish, the gate before pushing
make clean         # drop out/ and db/
```

`make add-suite` asks each sibling repo for `make deb-path` rather than
hardcoding where it builds; run `make deb` there first.

`REPREPRO=/path/to/reprepro` overrides the binary if it is not on `PATH`.

## Docs

| | |
| --- | --- |
| [docs/SPEC.md](docs/SPEC.md) | what the archive publishes and what a client can rely on |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | reprepro layout, key handling and rotation, adding a package, the checks |
| [docs/DEPLOY.md](docs/DEPLOY.md) | the plan for serving it from Cloudflare, and why extension-less files are the risk |
| [docs/PACKAGING.md](docs/PACKAGING.md) | the suite's shared Makefile targets, and where each package comes from |
| [docs/LICENSING.md](docs/LICENSING.md) | the BSL Change Date question, with sources — research, not legal advice |

## Publishing the flatpak archive too

The sibling [`amberlinux-flatpak`](https://github.com/Hyperquader-Coders/amberlinux-flatpak)
serves `flatpak.amberlinux.org`, signed with its own dedicated key from this
same machine, because that is where the keys live:

```sh
make deploy-all        # this archive, then the flatpak one
make deploy-flatpak    # only the sibling
```

They are separate targets rather than one so the two fail independently — a
flatpak problem must not leave apt half-published. Set `FLATPAK_ARCHIVE` if the
sibling is not at `../amberlinux-flatpak`.

## What is committed

Only the configuration, the scripts, the docs and the diagram. `out/` (the
published tree) and `db/` (reprepro's index) are **generated and gitignored** —
`db/` is meaningless without the pool it indexes, and the pool will hold model
weights. `make lint` fails if either is ever tracked, or if any document states
a signing fingerprint that `conf/distributions` does not.

The private key lives in the publishing machine's `~/.gnupg` and nowhere else;
nothing in this repository will ever contain it. Publishing therefore always
happens from that machine.

## Licence

**This licence covers the archive tooling only** — the Makefile, `tools/`,
`conf/`, the Cloudflare worker and the docs in this repository. BSD-3-Clause; see
[LICENSE](LICENSE).

**It does not cover the packages served from the archive.** Each `.deb` carries
the licence of the repository it was built from, recorded in that package's own
`copyright` file, and most of the suite is **BUSL-1.1** — source-available, with
commercial-use restrictions and a change date — not a permissive licence. One
exception is `amber-theme`, which is GPL-3.0-or-later outright. See
[docs/LICENSING.md](docs/LICENSING.md), and read a package's `copyright` before
assuming anything about it:

```sh
dpkg-deb -I <package>.deb copyright     # or: /usr/share/doc/<package>/copyright
```

Permissive tooling around restrictively-licensed payloads is the normal shape for
an archive, and the distinction matters: being allowed to run the publishing
scripts says nothing about what you may do with what they publish.
