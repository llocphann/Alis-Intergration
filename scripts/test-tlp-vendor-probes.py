#!/usr/bin/env python3
"""Regression: do not probe absent vendor-specific CPU sysfs with Quickshell.

The owner runs a system where the Intel pstate status file does not exist.
Quickshell FileView.path='' explicitly unloads a file rather than reading it;
refresh must also skip probes with an empty path. Hardware acceptance remains
separate: this test does not assume that any CPU driver is present.
"""
from pathlib import Path
import re

source = (Path(__file__).resolve().parents[1] / "services/TlpRuntimeCapabilities.qml").read_text()

for id_, path, drivers in (
    ("intelPstateStatusFile", "/sys/devices/system/cpu/intel_pstate/status",
     ["intel_pstate", "intel_cpufreq"]),
    ("amdPstateStatusFile", "/sys/devices/system/cpu/amd_pstate/status",
     ["amd-pstate", "amd-pstate-epp"]),
):
    view = re.search(r"\bFileView\s*\{\s*id:\s*" + id_ +
                     r"\b([\s\S]*?)\n\s*\}", source)
    assert view, f"{id_}: missing FileView"
    body = view.group(1)
    assert path in body, f"{id_}: lost vendor ABI"
    assert ' : ""' in body, f"{id_}: missing empty-path unload"
    assert "printErrors: false" in body, f"{id_}: optional sysfs should fail silently"
    assert all(driver in body for driver in drivers), f"{id_}: wrong scaling driver gate"
    assert f"if ({id_}.path.length > 0)" in source, (
        f"{id_}: refresh must not reload an unloaded path")

assert 'root.intelPstateStatus = ""' in source
assert 'root.amdPstateStatus = ""' in source
assert "root._refreshCpuDriverModes()" in source
print("ALIS_INTERGRATION_CPU_VENDOR_PROBE_PASS vendor paths are empty unless active, refresh guarded")
