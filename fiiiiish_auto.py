#!/usr/bin/env python3
"""Single-file entry point.

    python fiiiiish_auto.py simulate
    python fiiiiish_auto.py fight --tier deep --trace trace.jsonl
    python fiiiiish_auto.py replay trace.jsonl
    python fiiiiish_auto.py doctor
    python fiiiiish_auto.py live --dry-run

The implementation lives in the ``fiiiiish_auto`` package; this file only makes
the tool runnable without ``python -m``.
"""

from __future__ import annotations

from fiiiiish_auto.cli import main

if __name__ == "__main__":
    raise SystemExit(main())
