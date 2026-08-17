# LICENSING — the BSL question, with sources

Research written for the maintainer's own question, not legal advice. Every
claim below is backed by a source in **Sources**; read the primary text
(mariadb.com/bsl11) yourself before relying on any of this for a real
decision, and get a lawyer for anything that matters.

## The question

Publishing a `.deb` through this archive and through GitHub releases —
before publishing binaries, does BUSL-1.1 oblige the **Licensor** (not the
licensee) to release source code at the same time, or does it force anything
to happen before the Change Date?

**Short answer: no.** BUSL-1.1 has no clause that runs the other direction —
from Licensor to the world. It grants *licensees* rights over a work the
Licensor already chose to publish; it places no publish-or-else duty on the
Licensor, at binary-release time or at the Change Date. What already governs
this suite is simpler: the source and the `LICENSE` file live in the same
public git repo the `.deb` is built from, so source and binary are already
public together. Publishing a compiled `.deb` of code that is already
sitting in a public GitHub repo adds nothing new to disclose.

## Which repo gets which licence

**Applications are BSL.** `kat800`, `ambrosia`, `copal`, `amberlin` and the rest
of the shipped software: that is the work the restrictions exist to protect.

**Infrastructure is BSD-3-Clause.** The archives (`amberlinux-apt`,
`amberlinux-flatpak`), the packaging-only repos (`amber-desktop`), the libraries
written to be contributed upstream (`amber-lib`, `katlib`) and the toolchain
packaging (`amber-odin`, `odin-sdk-extension`, `setup-amber-odin`). None of it
carries the product, and BSL on it restricts nothing while breaking GitHub's
licence detection — which shows `NOASSERTION` for any licence outside the
choosealicense set.

`amber-desktop` is the clearest case: it is a metapackage whose `.deb` contains
no files at all, so a restrictive licence there governed a `control` template and
nothing else. The restriction that matters lives in the applications it depends
on, and it is theirs to state.

**`amber-theme` is GPL-3.0-or-later outright**, and not by choice: its work is
derivative of GPL material (vendored Mint-Y theme references; icon output derived
from Yaru / Mint-Y-Yaru art). It ships no `.deb` and is not in the archive — if
that changes, its packaging carries GPL obligations (corresponding source), not
BSL's.

The rule of thumb: **licence the thing by what it is, not by which tree it sits
in.** A permissive licence on packaging around a restricted application is the
normal shape, and it says nothing about what may be done with what the packaging
installs.

## 1. What BUSL-1.1 actually obliges the Licensor to do

The operative clause is the **Grant**: "The Licensor hereby grants you the
right to copy, modify, create derivative works, redistribute, and make
non-production use of the Licensed Work." That is a grant *to the licensee*,
scoped to a work the Licensor has already made available. Nothing in the
license compels the Licensor to make the work available in the first place,
to keep it available, or to re-publish it at any milestone.

The **Change Date** clause reads the same way: "Effective on the Change
Date, … the Licensor hereby grants you rights under the terms of the Change
License." This is a second grant, self-executing, over *the same work that
was already public*. It does not require a re-release, a new upload, or any
affirmative act — the source doesn't move, only the usage rights attached to
it change. If a Licensor never published a work under BUSL-1.1 at all, no one
holds a license and the Change Date promise never attaches to anyone, so
there is nothing to enforce. The "obligation" that does exist is a covenant
running to people who *already received a copy* — the Licensor commits, in
writing, to a Change License compatible with GPL 2.0+ — and if the Licensor
broke that covenant (e.g. took a public repo private before the Change Date),
existing licensees would have a breach claim; a stranger who never received a
copy has nothing to sue over.

Consequence for this suite specifically: because `ambrosia`, `copal`,
`kat800`, `amberlin`, and `amber-odin`'s own packaging keep source public on
GitHub under a `LICENSE` file, the "obligation" question is moot before it
starts — the source predates and outlives every `.deb` built from it.

## 2. No GPL-style copyleft trigger

GPL's distribution trigger is the actual copyleft mechanism: distributing
**object code** requires either shipping the corresponding source alongside
it or making a written offer good for a set period (GPLv2 §3(a)/(b); GPLv3
§6 is the same idea with more paperwork). That is what "copyleft" means in
practice — the act of distributing a binary is what pulls the source-code
duty into existence.

BUSL-1.1 has no equivalent clause. Its Grant is written in terms of the
Licensed Work, never in terms of "if you distribute binaries built from it."
Distributing a `.deb` under BUSL-1.1 is legally inert with respect to source
disclosure — no clause fires. The disclosure that already exists here is a
policy choice (publish the repo openly), not something the license compels.

## 3. Bundled third-party components in the same `.deb`

Each bundled component carries its own license, independent of BSL, and each
imposes its own redistribution terms on the `.deb` that ships it:

| Component | License | What redistribution requires | Status in this suite |
| --- | --- | --- | --- |
| ONNX Runtime | MIT | Keep the copyright notice and license text with any copy distributed. No source-disclosure duty. | Done — `amberlin-runtime/debian/copyright` carries the upstream MIT block for `/usr/lib/amberlin/*`. |
| Kokoro model weights | Apache-2.0 | License copy + copyright notice + a `NOTICE` file if upstream ships one + a statement of changes to any modified files. No general source-disclosure duty (weights aren't "source" in the copyleft sense anyway). | Done — `amber-models/debian/copyright` carries an Apache-2.0 stanza for the weights and the voices, with the change statement Apache-2.0 § 4(b) wants (the voices are re-split out of upstream's npz, values unchanged), and points at `/usr/share/common-licenses/Apache-2.0`. |
| Qwen2.5-0.5B-Instruct weights | Apache-2.0 | As above. | Done — same file. `qwen_vocab.bin` is derived from upstream's `tokenizer.json`, so it carries the same change statement. |
| Moonshine STT weights | MIT (© 2024 Useful Sensors) | Keep the copyright notice and license text with any copy distributed. | Done — upstream's own `LICENSE` ships inside the model directory, where upstream put it, and `amber-models/debian/copyright` reproduces it inline (MIT is not in `common-licenses`). |
| VTE (bundled in kat800) | LGPL-3.0-or-later | The **dynamic-linking safe harbor**: ship the LGPL notices, make the *exact corresponding source* of the bundled library version available (or a written offer), and don't block relinking against a different build of the library. | kat800 ships `libvte-2.91-gtk4.so.0` as a separate `.so` under `/usr/lib/kat800/`, dynamically linked from the `kat800` binary — the safe harbor applies, not GPL-style whole-program disclosure. |
| GTK (bundled in kat800) | LGPL-2.1-or-later | Same dynamic-linking safe harbor as VTE, above. | kat800 ships `libgtk-4.so.1` the same way, as a separate `.so`. |

An earlier pass at this table said VTE was LGPL-2.1-or-later, copyright
"Christian Persch and contributors" — that was wrong on both counts. VTE's
own source headers say LGPL-3.0-or-later, copyright Red Hat, Inc. and
Christian Persch; GTK is the LGPL-2.1-or-later one, with its own distinct
copyright holders (Peter Mattis, Spencer Kimball, Josh MacDonald, and the
GTK Team). `kat800/packaging/debian/copyright` now carries separate,
corrected `Files:` stanzas for each, each with a corresponding-source
pointer (upstream URL + exact bundled tarball) and a
`/usr/share/common-licenses/` reference — the exact gap `PACKAGING.md` §
Divergences recorded ("an LGPL copyright not referencing common-licenses")
is fixed, not just noted.

## 4. Debian-packaging expectations

- `debian/copyright` should list every bundled license by `Files:` stanza,
  not just the top-level one — every package in the archive now does
  (`amber-odin`, `amberlin`, `amberlin-runtime`/`-cuda`, `ambrosia`, `copal`,
  `kat800`). Two of those (`ambrosia`, `copal`) had no DEP-5
  `packaging/debian/copyright` at all until this pass — their `deb` target
  was shipping the plain-English `LICENSE` text straight to
  `usr/share/doc/<pkg>/copyright`, which isn't machine-readable and isn't
  what lintian or a downstream auditor expects at that path. `amberlin`'s
  file existed but claimed `License: GPL-3+` for the whole package, which
  was simply wrong — amberlin is BSL like every sibling.
- A private-path bundle (kat800's `/usr/lib/kat800/`) needs its own
  `Files:` stanza distinct from the system package it shadows; conflating
  the two would misstate what license governs which file.
- A vendored tree with many third-party licenses (amber-odin's `vendor/`,
  fetched wholesale from the upstream Odin release) does not need every one
  of those licenses transcribed. A `Files: vendor/*` stanza describing the
  aggregate accurately and pointing at the LICENSE/COPYING file already
  shipped in each subdirectory is enough — the earlier version of
  `amber-odin`'s copyright said `Files: *` was BSD-3-Clause, which is true
  for Odin itself but was silently claiming the same for every vendored
  library too.
- Reference `/usr/share/common-licenses/` for GPL/LGPL/Apache-2.0 rather than
  re-embedding the full text; short MIT/BSD/OFL texts (not present on a
  stock Debian system) still belong inline. `ambrosia` and `kat800` were
  both shipping the full LGPL-3.0 text a second time, as a standalone
  `XSI-ICONS-LICENSE` doc file, for the bundled XSI symbolic icons —
  removed in favour of a `Files:` stanza plus the common-licenses pointer.
- Copyright accuracy is not just tidiness: `debian/copyright` is the artifact
  a downstream redistributor or an auditor reads first, and it's what
  lintian's license checks compare against.

## Sources

- [Business Source License 1.1 — full text](https://mariadb.com/bsl11/) (MariaDB, the license's origin)
- [Business Source License 1.1 — SPDX entry](https://spdx.org/licenses/BUSL-1.1.html)
- [Business Source License (BSL 1.1): Requirements, Provisions, and History — FOSSA Blog](https://fossa.com/blog/business-source-license-requirements-provisions-history/)
- [Business Source License — Wikipedia](https://en.wikipedia.org/wiki/Business_Source_License)
- [Software Freedom Law Center — Guide to GPL Compliance, 2nd ed.](https://softwarefreedom.org/resources/2014/SFLC-Guide_to_GPL_Compliance_2d_ed.html) (the GPL §3(a)/(b) distribution trigger)
- [The Comprehensive GPL Guide — Chapter 15, Details of Compliant Distribution](https://copyleft.org/guide/comprehensive-gpl-guidech16.html)
- [FOSSA Blog — Open Source Software Licenses 101: The LGPL License](https://fossa.com/blog/open-source-software-licenses-101-lgpl-license/) (dynamic-linking safe harbor)
