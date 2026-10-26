#!/usr/bin/env python3
"""Resolve a sibling Alis checkout for optional native test fixtures only."""
import os
from pathlib import Path


def resolve_host_root(integration_root, environ=None):
    """Prefer canonical Alis, while accepting a legacy Alis checkout."""
    if environ is None:
        environ = os.environ
    explicit = environ.get("ALIS_ROOT") or environ.get("ALIS_ROOT")
    if explicit:
        candidate = Path(explicit).expanduser().resolve()
        if not (candidate / "scripts/native_test_session.py").is_file():
            raise SystemExit("Invalid explicit Alis host checkout: native_test_session.py missing")
        return candidate
    for sibling in ("Alis", "Alis"):
        candidate = (Path(integration_root).resolve().parent / sibling).resolve()
        if (candidate / "scripts/native_test_session.py").is_file():
            return candidate
    raise SystemExit(
        "Alis host checkout missing: use a sibling Alis clone or set ALIS_ROOT "
        "(legacy ALIS_ROOT is also supported)"
    )
