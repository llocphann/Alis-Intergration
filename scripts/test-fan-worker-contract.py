#!/usr/bin/env python3
"""Owned fan-level worker/helper guards moved from the core shell."""
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
failures=[]
def read(path): return (ROOT/path).read_text(encoding="utf-8")
def check(condition,message):
    if not condition: failures.append(message)
def main():
    thinkfan_service=read("services/ThinkFanService.qml")
    thinkfan_helper=read("assets/helpers/alis-thinkfan")
    for token in (
        "import Quickshell.Services.UPower",
        "property bool directControlAvailable: false",
        "property bool fanLevelControlSupported: false",
        "readonly property string activePowerProfileKey:",
        "readonly property int configuredActiveFanLevel:",
        "function setConfiguredFanLevel(key: string, requestedLevel): bool",
        "function setProfileFanControlEnabled(requestedEnabled: bool): bool",
        "function applyFanLevel(requestedLevel): bool",
        "function applyConfiguredPowerProfileFanLevel(): bool",
        "Config.flushWrites()",
        'root.lastApplyError = "managed-control-active"',
        '"direct-control-unavailable"',
        '"helper-update-required"',
        'Config.getNestedValue("powerProfiles.fanControl.enabled", false)',
        'Config.getNestedValue(path, 0)',
        "function _scheduleConfiguredFanLevelApply(): void",
        "function onConfigChanged(): void",
        "root._scheduleConfiguredFanLevelApply()",
        'String(root.fanLevel ?? "").trim().toLowerCase() === normalized',
        "root._profileFollowArmed",
        'property string _queuedFanLevel: ""',
        "function _drainQueuedFanLevel(): void",
        'completedOperation === "profile:firmware"',
        "onTriggered: {",
        "root._profileFollowArmed = true",
    ):
        check(token in thinkfan_service,
              f"ThinkFan service must own guarded power-profile fan levels: {token}")

    for token in (
        "fan_control_path=/sys/module/thinkpad_acpi/parameters/fan_control",
        "direct_control_available()",
        '"fanLevelControlSupported":true',
        "--set-level auto|1..7",
        "set_fan_level()",
        "auto|1|2|3|4|5|6|7",
        "stop ThinkFan managed control before setting a fixed fan level",
        "level auto",
    ):
        check(token in thinkfan_helper,
              f"Privileged helper must guard direct fan-level control: {token}")

    for token in ("find_thinkfan()", "service_name=thinkfan.service", 'systemctl cat "$service_name"', "[ -r /etc/thinkfan.yaml ]", "[ -r /etc/thinkfan.conf ]"):
        check(token in thinkfan_helper,"missing optional ThinkFan dependency guard: "+token)
    if failures: raise AssertionError("\n".join(failures))
    print("ALIS_INTERGRATION_FAN_WORKER_CONTRACT_PASS")
if __name__=="__main__": main()
