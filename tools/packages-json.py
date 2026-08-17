#!/usr/bin/env python3
"""Render the archive's Packages index as JSON for the amberlinux.org
packages page. Generated at build time from what the archive actually
serves, so the page cannot drift from reality. Stdout."""
import json
import sys

FIELDS = ("Package", "Version", "Architecture", "Description", "Depends",
          "Recommends", "Provides", "Conflicts", "Homepage", "Section",
          "Installed-Size", "Size", "Filename")


def parse(path):
    pkgs, cur, last_key = [], {}, None
    for line in open(path, encoding="utf-8"):
        if not line.strip():
            if cur:
                pkgs.append(cur)
            cur, last_key = {}, None
            continue
        if line.startswith((" ", "\t")) and last_key:
            cur[last_key] += "\n" + line.strip()
            continue
        key, _, val = line.partition(":")
        last_key = key
        if key in FIELDS:
            cur[key] = val.strip()
    if cur:
        pkgs.append(cur)
    return sorted(pkgs, key=lambda p: p.get("Package", ""))


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: packages-json.py <Packages file>")
    json.dump(parse(sys.argv[1]), sys.stdout, indent=1)
    print()
