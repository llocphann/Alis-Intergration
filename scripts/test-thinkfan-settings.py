#!/usr/bin/env python3
"""Owned cooling settings contract, independent of host navigation."""
from pathlib import Path
system_settings=(Path(__file__).resolve().parents[1]/'modules/settings/ThinkfanSettings.qml').read_text()
def check(value,message):
    assert value,message
for token in (
    'settingsTaskSection: "fan"',
    'title: Translation.tr("Fan Control")',
    'text: Translation.tr("ThinkFan managed control")',
    "ThinkFanService.applyProfile(",
    "checked: root.thinkFanManaged",
    'text: Translation.tr("Follow power profile fan level")',
    'text: Translation.tr("Power Saver fan level")',
    'text: Translation.tr("Balanced fan level")',
    'text: Translation.tr("Performance fan level")',
    "ThinkFanService.directControlAvailable",
    "ThinkFanService.fanLevelControlSupported",
    "ThinkFanService.setConfiguredFanLevel(",
    "ThinkFanService.setProfileFanControlEnabled(",
    "enabled: Config.ready",
):
    check(token in system_settings,
          f"System Settings must own the shared ThinkFan profile control: {token}")

for forbidden in (
    "root.setProfileFanLevel(",
    "root.profileFanControlReady",
    "enabled: ThinkFanService.directControlAvailable && !root.thinkFanManaged",
):
    check(forbidden not in system_settings,
          f"Fan preferences must persist independently of runtime helper readiness: {forbidden}")


print('ALIS_INTERGRATION_THINKFAN_SETTINGS_PASS')
