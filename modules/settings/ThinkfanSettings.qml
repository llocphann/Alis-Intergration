import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

SettingsCardSection {
    id: root
    objectName: "hadalirdThinkfanSettings"
    readonly property bool thinkFanManaged:
        ThinkFanService.stateKnown && ThinkFanService.profile === "managed"
    readonly property bool thinkFanCanApply:
        ThinkFanService.stateKnown
        && ThinkFanService.serviceInstalled
        && !ThinkFanService.busy
        && (root.thinkFanManaged || ThinkFanService.available)
    readonly property bool profileFanControlEnabled:
        ThinkFanService.profileFanControlEnabled

    settingsTaskSection: "fan"
    expanded: true
    icon: "mode_fan"
    title: Translation.tr("Fan Control")

    SettingsGroup {
        SettingsSwitch {
            buttonIcon: "mode_fan"
            text: Translation.tr("ThinkFan managed control")
            description: Translation.tr("Use ThinkFan for fan control instead of firmware control. Changing ownership may require administrator authorization.")
            autoToggle: false
            checked: root.thinkFanManaged
            enabled: root.thinkFanCanApply
            onToggledByUser: nextChecked => ThinkFanService.applyProfile(
                nextChecked ? "managed" : "firmware")
        }

        SettingsNote {
            icon: ThinkFanService.serviceInstalled ? "thermostat" : "info"
            warning: ThinkFanService.stateKnown
                && (!ThinkFanService.serviceInstalled
                    || ThinkFanService.statusReason.length > 0)
            text: !ThinkFanService.stateKnown
                ? Translation.tr("Checking ThinkFan status…")
                : ThinkFanService.busy
                    ? Translation.tr("Applying fan control change…")
                : root.thinkFanManaged
                    ? Translation.tr("ThinkFan is managing the fan. Saved per-profile levels remain editable and will resume when managed mode is disabled.")
                : !ThinkFanService.fanLevelControlSupported
                    ? Translation.tr("The installed fan-control helper is too old for per-profile levels. Update the Alis-Intergration helpers so /usr/libexec/inir-thinkfan is refreshed.")
                : ThinkFanService.directControlAvailable
                    ? Translation.tr("Direct fan control is available. Level 0 means automatic firmware control.")
                : ThinkFanService.available
                    ? Translation.tr("ThinkFan is available, but direct profile fan levels require ThinkPad ACPI fan_control=1.")
                    : Translation.tr("Fan-control integration is unavailable; firmware control remains active.")
        }

        SettingsDivider {}

        SettingsSwitch {
            buttonIcon: "sync"
            text: Translation.tr("Follow power profile fan level")
            description: Translation.tr("Apply the saved fan level when Power Saver, Balanced or Performance becomes active.")
            autoToggle: false
            checked: root.profileFanControlEnabled
            enabled: Config.ready
            onToggledByUser: nextChecked =>
                ThinkFanService.setProfileFanControlEnabled(nextChecked)
        }

        ConfigRow {
            uniform: true
            enabled: Config.ready

            ConfigSpinBox {
                icon: "energy_savings_leaf"
                objectName: "powerSaverFanLevel"
                text: Translation.tr("Power Saver fan level")
                value: ThinkFanService.configuredFanLevel("powerSaver")
                from: 0
                to: 7
                stepSize: 1
                onValueChanged: ThinkFanService.setConfiguredFanLevel("powerSaver", value)
                StyledToolTip {
                    text: Translation.tr("0 = Auto; 1–7 = fixed ThinkPad ACPI fan level")
                }
            }

            ConfigSpinBox {
                icon: "airwave"
                objectName: "balancedFanLevel"
                text: Translation.tr("Balanced fan level")
                value: ThinkFanService.configuredFanLevel("balanced")
                from: 0
                to: 7
                stepSize: 1
                onValueChanged: ThinkFanService.setConfiguredFanLevel("balanced", value)
                StyledToolTip {
                    text: Translation.tr("0 = Auto; 1–7 = fixed ThinkPad ACPI fan level")
                }
            }

            ConfigSpinBox {
                icon: "local_fire_department"
                objectName: "performanceFanLevel"
                text: Translation.tr("Performance fan level")
                value: ThinkFanService.configuredFanLevel("performance")
                from: 0
                to: 7
                stepSize: 1
                onValueChanged: ThinkFanService.setConfiguredFanLevel("performance", value)
                StyledToolTip {
                    text: Translation.tr("0 = Auto; 1–7 = fixed ThinkPad ACPI fan level")
                }
            }
        }

        SettingsNote {
            icon: ThinkFanService.directControlAvailable ? "warning" : "info"
            warning: ThinkFanService.directControlAvailable
            text: ThinkFanService.directControlAvailable
                ? Translation.tr("Fixed levels 1–7 bypass temperature-based fan curves. Keep 0 (Auto) unless you understand the cooling behavior of this machine.")
                : Translation.tr("Saved levels remain in config even when direct control is unavailable. Runtime apply requires /proc/acpi/ibm/fan and thinkpad_acpi fan_control=1.")
        }
    }
}

