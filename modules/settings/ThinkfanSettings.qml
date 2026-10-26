import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

SettingsCardSection {
    id: root
    objectName: "alisIntergrationThinkfanSettings"
    readonly property bool thinkFanManaged:
        ThinkFanService.stateKnown && ThinkFanService.profile === "managed"
    readonly property bool thinkFanCanApply:
        ThinkFanService.stateKnown
        && ThinkFanService.serviceInstalled
        && !ThinkFanService.busy
        && (root.thinkFanManaged || ThinkFanService.available)
    readonly property bool profileFanControlEnabled:
        ThinkFanService.profileFanControlEnabled
    readonly property bool directFanLevelReady:
        ThinkFanService.directControlAvailable && ThinkFanService.fanLevelControlSupported

    settingsTaskSection: "fan"
    expanded: true
    icon: "mode_fan"
    title: Translation.tr("Fan Control")

    SettingsGroup {
        ConfigRow {
            uniform: true

            SettingsSwitch {
                buttonIcon: "mode_fan"
                text: Translation.tr("ThinkFan managed control")
                autoToggle: false
                checked: root.thinkFanManaged
                enabled: root.thinkFanCanApply
                onToggledByUser: nextChecked => ThinkFanService.applyProfile(
                    nextChecked ? "managed" : "firmware")
            }

            SettingsSwitch {
                buttonIcon: "sync"
                text: Translation.tr("Follow power profile fan level")
                autoToggle: false
                checked: root.profileFanControlEnabled
                enabled: Config.ready
                onToggledByUser: nextChecked =>
                    ThinkFanService.setProfileFanControlEnabled(nextChecked)
            }
        }

        SettingsDivider {}

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
    }
}

