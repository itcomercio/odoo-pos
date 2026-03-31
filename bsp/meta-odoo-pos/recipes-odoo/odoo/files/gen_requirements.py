#!/usr/bin/env python3
"""
Pre-process Odoo's requirements.txt for use in a Yocto build.

Actions performed:
  1. Strip environment markers (everything after the semicolon on each line)
     so that pip installs all packages regardless of python_version constraints.
     Odoo's requirements.txt uses markers like "python_version < '3.13'" that
     would silently skip packages (lxml, gevent, Pillow …) on Python 3.14+.

  2. Deduplicate by package name, keeping the LAST entry in the file.
     Odoo lists newer Python version entries last, so "last wins" selects
     the most up-to-date pinned version.

  3. Relax exact-version pins (==) to minimum-version pins (>=) for packages
     whose pinned version has no pre-built binary wheel for Python 3.14.
     This lets pip pick a newer release that ships a manylinux/abi3 wheel,
     avoiding source builds that require C dev headers on the build host.

  4. Replace psycopg2 with psycopg2-binary (self-contained .so, no libpq-dev
     needed on the target device at runtime).

Usage:
    python3 gen_requirements.py <path/to/requirements.txt>
"""

import re
import sys

# Packages where we relax == to >= so pip can find a newer binary-wheel release.
RELAX_PINS = {
    'lxml',       # 5.2.1 has no cp314 wheel; 5.3.x+ does
    'greenlet',   # older pins may lack cp314 wheel
    'gevent',     # depends on greenlet; same issue
    'pillow',     # relax to allow newer binary-only release
    'reportlab',  # older releases need freetype/etc to build from source
}


def canonical_name(pkg_spec):
    """Return a normalised package name for deduplication."""
    raw = re.split(r'[\s=<>!~\[;]', pkg_spec)[0]
    return raw.lower().replace('-', '_').replace('.', '_')


pkgs = {}  # canonical_name: requirement_line  (last entry wins)

with open(sys.argv[1]) as f:
    for raw in f:
        line = raw.strip()
        if not line or line.startswith('#'):
            continue

        # Strip environment markers
        pkg = re.split(r'\s*;', line)[0].strip()
        if not pkg:
            continue

        # psycopg2 -> psycopg2-binary
        pkg = re.sub(r'^psycopg2(?=[^-]|$)', 'psycopg2-binary', pkg)

        name = canonical_name(pkg)

        # Relax exact pins for packages without cp314 binary wheels
        if name in RELAX_PINS:
            pkg = pkg.replace('==', '>=', 1)

        pkgs[name] = pkg  # last entry wins

for p in pkgs.values():
    print(p)

