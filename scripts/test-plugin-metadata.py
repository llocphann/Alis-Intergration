#!/usr/bin/env python3
"""Manifest navigation contracts stay additive and agree with the pinned host."""
import copy
import importlib.util
import json
from pathlib import Path
from integration_test_host import resolve_host_root

ROOT = Path(__file__).resolve().parents[1]
HOST = resolve_host_root(ROOT)
def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result
installer = module("installer", ROOT / "scripts/install.py")
host = module("discovery", HOST / "scripts/hadalird-status.py")
manifest = json.loads((ROOT / "manifest.json").read_text())
for count in (0, 1, len(manifest["plugins"])):
    data = {**manifest, "plugins": manifest["plugins"][:count]}
    assert installer.plugin_metadata(data) == host.plugin_metadata(data)
    assert len(host.plugin_metadata(data)) == count
legacy = {key: value for key, value in manifest.items() if key != "plugins"}
assert installer.plugin_metadata(legacy) == host.plugin_metadata(legacy) == []
assert [cap["id"] for cap in manifest["plugins"][2]["capabilities"]] == ["theming", "quicknotes", "todo"]
invalid = []
for field, value in (("id", "../escape"), ("id", "management"), ("name", "bad\nlabel"), ("capabilities", [])):
    data = copy.deepcopy(manifest); data["plugins"][0][field] = value; invalid.append(data)
data = copy.deepcopy(manifest); data["plugins"].append(data["plugins"][0]); invalid.append(data)
for field, value in (("settings", "../../foreign.qml"), ("view", "execute"), ("id", [])):
    data = copy.deepcopy(manifest); data["plugins"][0]["capabilities"][0][field] = value; invalid.append(data)
data = copy.deepcopy(manifest); data["settings"]["foreign"] = "../../foreign.qml"; data["plugins"][0]["capabilities"][0]["settings"] = "foreign"; invalid.append(data)
for data in invalid:
    for validate in (installer.plugin_metadata, host.plugin_metadata):
        try:
            validate(data)
            raise AssertionError("Malformed plugin metadata accepted")
        except ValueError:
            pass
print("INTEGRATION_PLUGIN_METADATA_PASS legacy, zero/one/many, capability references, malformed metadata, host parity")
