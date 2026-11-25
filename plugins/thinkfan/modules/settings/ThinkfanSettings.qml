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
    property string _dismissedError: ""
    readonly property string profileSummaryLabel: {
        const p = String(ThinkFanService.profile ?? "firmware")
        if (p === "managed")
            return Translation.tr("Managed")
        if (p === "manual")
            return Translation.tr("Manual")
        return Translation.tr("Firmware")
    }
    readonly property string telemetrySummary: {
        if (ThinkFanService.busy)
            return Translation.tr("Working…")
        if (!ThinkFanService.stateKnown) {
            return ThinkFanService.statusReason === "helper-unavailable"
                ? Translation.tr("ThinkFan helper not detected")
                : Translation.tr("Reading fan telemetry…")
        }
        const rpmPart = ThinkFanService.fanRpm >= 0
            ? (ThinkFanService.fanRpm + " RPM")
            : ("— RPM")
        const rawLevel = String(ThinkFanService.fanLevel ?? "").trim()
        const levelPart = rawLevel.length === 0
            ? "—"
            : (rawLevel.toLowerCase() === "auto"
                ? Translation.tr("Auto")
                : (Translation.tr("Level") + " " + rawLevel))
        return rpmPart + " · " + levelPart + " · " + root.profileSummaryLabel
    }
    readonly property string applyErrorSummary: {
        const err = String(ThinkFanService.lastApplyError ?? "")
        if (err.length === 0 || err === root._dismissedError)
            return ""
        if (err === "managed-control-active")
            return Translation.tr("Turn off ThinkFan managed control before setting a fixed fan level.")
        if (err === "service-unavailable")
            return Translation.tr("thinkfan.service is not installed on this system.")
        if (err === "thinkfan-unavailable")
            return Translation.tr("Configure /etc/thinkfan.conf or /etc/thinkfan.yaml before enabling managed control.")
        if (err === "apply-failed")
            return Translation.tr("Authorization cancelled or fan control request declined.")
        if (err === "direct-control-unavailable" || err === "helper-update-required")
            return Translation.tr("Direct fan-level control requires thinkpad_acpi fan_control=1.")
        return Translation.tr("Fan control note:") + " " + err
    }

    Connections {
        target: ThinkFanService
        function onBusyChanged(): void {
            if (ThinkFanService.busy)
                root._dismissedError = ""
        }
        function onLastApplyErrorChanged(): void {
            if (ThinkFanService.lastApplyError.length === 0)
                root._dismissedError = ""
        }
    }

    Component.onCompleted: {
        if (!ThinkFanService.busy)
            ThinkFanService.refresh()
    }

    settingsTaskSection: "fan"
    expanded: true
    icon: "mode_fan"
    title: Translation.tr("Fan Control")

    SettingsGroup {
        Rectangle {
            objectName: "thinkfanLiveTelemetryStrip"
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            implicitHeight: Math.max(40, telemetryRow.implicitHeight + 14)
            radius: Appearance.rounding.small
            color: Appearance.colors.colLayer1
            border.width: 1
            border.color: Appearance.colors.colLayer0Border

            RowLayout {
                id: telemetryRow
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 8
                spacing: 8

                Rectangle {
                    implicitWidth: statusBadgeRow.implicitWidth + 14
                    implicitHeight: 24
                    radius: 12
                    color: ThinkFanService.active
                        ? Appearance.colors.colSecondaryContainer
                        : Appearance.colors.colLayer2

                    Row {
                        id: statusBadgeRow
                        anchors.centerIn: parent
                        spacing: 4

                        MaterialSymbol {
                            anchors.verticalCenter: parent.verticalCenter
                            text: ThinkFanService.busy ? "sync" : (ThinkFanService.active ? "mode_fan" : "toys_fan")
                            iconSize: 13
                            color: ThinkFanService.active
                                ? Appearance.colors.colPrimary
                                : Appearance.colors.colSubtext
                        }

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: ThinkFanService.active ? Translation.tr("Active") : Translation.tr("Standby")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.weight: Font.DemiBold
                            color: ThinkFanService.active
                                ? Appearance.colors.colOnSecondaryContainer
                                : Appearance.colors.colOnLayer1
                        }
                    }
                }

                StyledText {
                    objectName: "thinkfanTelemetrySummaryText"
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: root.telemetrySummary
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnLayer1
                    elide: Text.ElideRight
                }

                RippleButton {
                    objectName: "thinkfanRefreshTelemetryButton"
                    enabled: !ThinkFanService.busy
                    implicitWidth: refreshRow.implicitWidth + 16
                    implicitHeight: 26
                    buttonRadius: 13
                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    onClicked: ThinkFanService.refresh()

                    contentItem: Item {
                        Row {
                            id: refreshRow
                            anchors.centerIn: parent
                            spacing: 4

                            MaterialSymbol {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "refresh"
                                iconSize: 13
                                color: Appearance.colors.colOnLayer1
                            }

                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: Translation.tr("Refresh")
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                font.weight: Font.Medium
                                color: Appearance.colors.colOnLayer1
                            }
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            spacing: 8
            visible: root.applyErrorSummary.length > 0

            MaterialSymbol {
                text: "info"
                iconSize: 15
                color: Appearance.colors.colSubtext
            }

            StyledText {
                objectName: "thinkfanApplyStatusNote"
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                wrapMode: Text.WordWrap
                text: root.applyErrorSummary
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
            }

            RippleButton {
                implicitWidth: 24
                implicitHeight: 24
                buttonRadius: 12
                colBackground: "transparent"
                colBackgroundHover: Appearance.colors.colLayer2Hover
                onClicked: root._dismissedError = ThinkFanService.lastApplyError

                contentItem: Item {
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "close"
                        iconSize: 14
                        color: Appearance.colors.colSubtext
                    }
                }
            }
        }

        SettingsDivider {}
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

        StyledText {
            objectName: "thinkfanModeHintText"
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            wrapMode: Text.WordWrap
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: Appearance.colors.colSubtext
            text: root.thinkFanManaged
                ? Translation.tr("Managed Mode enables thinkfan.service on boot and recovers it after sleep.")
                : (ThinkFanService.managedIntentEnabled
                    ? Translation.tr("Managed Mode preference is saved; enable above or refresh if stopped.")
                    : Translation.tr("Firmware Mode leaves fan curves to EC firmware unless per-profile levels are enabled."))
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

