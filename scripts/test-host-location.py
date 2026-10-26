#!/usr/bin/env python3
"""Offline native-host checkout selection; all paths are temporary fixtures."""
from pathlib import Path
import tempfile

from integration_test_host import resolve_host_root

with tempfile.TemporaryDirectory(prefix="alis-integration-host-path-") as name:
    root = Path(name)
    integration = root / "Alis-Intergration"
    integration.mkdir()
    legacy = root / "Alis"
    canonical = root / "Alis"

    def make_host(path):
        (path / "scripts").mkdir(parents=True, exist_ok=True)
        (path / "scripts/native_test_session.py").write_text("# fixture\n")
        return path.resolve()

    try:
        resolve_host_root(integration, {})
        raise AssertionError("missing native host accepted")
    except SystemExit as error:
        assert "Alis" in str(error)

    make_host(legacy)
    assert resolve_host_root(integration, {}) == legacy.resolve()
    make_host(canonical)
    assert resolve_host_root(integration, {}) == canonical.resolve()
    assert resolve_host_root(integration, {"ALIS_ROOT": str(legacy)}) == legacy.resolve()
    assert resolve_host_root(integration, {"ALIS_ROOT": str(canonical)}) == canonical.resolve()
    assert resolve_host_root(integration, {"ALIS_ROOT": str(canonical),
                                          "ALIS_ROOT": str(legacy)}) == canonical.resolve()
    try:
        resolve_host_root(integration, {"ALIS_ROOT": str(root / "nonexistent")})
        raise AssertionError("missing explicit host accepted")
    except SystemExit as error:
        assert "native_test_session.py" in str(error)

print("ALIS_INTEGRATION_HOST_LOCATION_PASS canonical and legacy fallback, explicit pin, fail-closed")
