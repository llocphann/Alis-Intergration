pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings
import "." as Integration

ColumnLayout {
    id: root
    objectName: "alisIntergrationTlpPowerSettings"

    property bool _tlpDemandRefreshed: false

    function _refreshTlpDemand(): void {
        if (!root.visible || root._tlpDemandRefreshed)
            return
        root._tlpDemandRefreshed = true
        TlpRuntimeCapabilities.refresh()
        TlpSettingsService.refresh()
    }

    onVisibleChanged: {
        if (!visible) {
            root._tlpDemandRefreshed = false
            return
        }
        root._refreshTlpDemand()
    }

    Component.onCompleted: root._refreshTlpDemand()

    width: parent ? parent.width : 0
    Layout.fillWidth: true
    spacing: SettingsMaterialPreset.pageSpacing

    // Search/navigation uses this ancestor marker to activate System → Power
    // before attempting to spotlight a nested TLP control.
    property string settingsTaskSection: "power"
    property int selectedCategoryIndex: 0
    property string filterText: ""

    readonly property string profileGuidanceSource: "When overriding this group, set every shown profile together to avoid values spilling between TLP profiles."
    // Charge care is integrated into the Battery/TLP card on the left.
    // The right card surfaces only the essential power/CPU/device groups on a single screen.
    readonly property var navigationCategories:
        TlpSettingsService._array(TlpSettingsService.navigationCategories)
            .filter(category => String(category?.id ?? "") !== "battery-care")
    readonly property var selectedCategory: {
        const categories = root.navigationCategories
        if (categories.length === 0)
            return null
        return categories[Math.max(0, Math.min(root.selectedCategoryIndex, categories.length - 1))]
    }
    readonly property var cpuProfileGroupIds: [
        "TLP_ENABLE",
        "TLP_AUTO_SWITCH",
        "PLATFORM_PROFILE",
        "CPU_ENERGY_PERF_POLICY",
        "CPU_BOOST"
    ]
    readonly property var deviceSavingGroupIds: [
        "WIFI_PWR",
        "SOUND_POWER_SAVE",
        "USB_AUTOSUSPEND"
    ]
    readonly property var essentialGroupIds: root.cpuProfileGroupIds.concat(root.deviceSavingGroupIds)

    function _groupsByIds(ids): var {
        const cats = root.navigationCategories
        const byId = ({})
        for (let i = 0; i < cats.length; i++) {
            const groups = TlpSettingsService._array(
                TlpSettingsService.groupsForCategory(cats[i], ""))
            for (let j = 0; j < groups.length; j++) {
                const g = groups[j]
                const gid = String(g?.id ?? "")
                if (gid.length > 0 && ids.includes(gid))
                    byId[gid] = g
            }
        }
        const ordered = []
        for (let k = 0; k < ids.length; k++) {
            const id = ids[k]
            if (byId[id])
                ordered.push(byId[id])
        }
        return ordered
    }

    readonly property var cpuProfileGroups: root._groupsByIds(root.cpuProfileGroupIds)
    readonly property var deviceSavingGroups: root._groupsByIds(root.deviceSavingGroupIds)
    readonly property var visibleGroups: root.cpuProfileGroups.concat(root.deviceSavingGroups)
    readonly property bool profileGuidanceVisible: false

    function conciseGroupDescription(group): string {
        const description = String(group?.description ?? "")
        if (description === root.profileGuidanceSource)
            return ""
        const suffix = " " + root.profileGuidanceSource
        return description.endsWith(suffix)
            ? description.slice(0, description.length - suffix.length)
            : description
    }

    function statusDescription(): string {
        if (!TlpSettingsService.schemaLoaded)
            return Translation.tr("The bundled TLP settings schema could not be loaded")
        if (!TlpSettingsService.available)
            return Translation.tr("TLP is not installed")
        if (!TlpSettingsService.supported)
            return TlpSettingsService.statusReason === "unsupported-tlp-version"
                ? Translation.tr("This TLP version is not supported yet")
                : Translation.tr("The installed TLP runtime is unavailable")
        if (!TlpSettingsService.configAvailable)
            return TlpSettingsService.statusReason === "managed-config-invalid"
                ? Translation.tr("The Alis TLP override file is invalid; reset overrides to recover")
                : Translation.tr("TLP configuration could not be read")
        return TlpSettingsService.enabled
            ? Translation.tr("TLP %1 is active · %2 Alis overrides").arg(
                TlpSettingsService.tlpVersion).arg(TlpSettingsService.managedCount)
            : Translation.tr("TLP %1 is disabled by configuration").arg(TlpSettingsService.tlpVersion)
    }

    function selectCategory(index: int): void {
        if (index === root.selectedCategoryIndex || TlpSettingsService.busy)
            return
        root.selectedCategoryIndex = index
    }

    onSelectedCategoryIndexChanged: root.filterText = ""

    RowLayout {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        spacing: SettingsMaterialPreset.pageSpacing

        // LEFT COLUMN: Battery & Charge Care + Wireless, Audio & USB Power Saving
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredWidth: 1
            Layout.alignment: Qt.AlignTop
            spacing: SettingsMaterialPreset.pageSpacing

            SettingsCardSection {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                _preventBentoReparent: true
                expanded: true
                collapsible: false
                icon: "battery_saver"
                title: Translation.tr("Battery & Charge Care")

                SettingsGroup {
                    ConfigSpinBox {
                        icon: "warning"
                        text: Translation.tr("Low battery warning (%)")
                        value: Config.options?.battery?.low ?? 0
                        from: 0
                        to: 100
                        stepSize: 5
                        onValueChanged: Config.setNestedValue("battery.low", value)
                        StyledToolTip {
                            text: Translation.tr("Show warning notification when battery drops below this level")
                        }
                    }

                    ConfigSpinBox {
                        icon: "dangerous"
                        text: Translation.tr("Critical battery warning (%)")
                        value: Config.options?.battery?.critical ?? 0
                        from: 0
                        to: 100
                        stepSize: 5
                        onValueChanged: Config.setNestedValue("battery.critical", value)
                        StyledToolTip {
                            text: Translation.tr("Show critical warning when battery drops below this level")
                        }
                    }

                    ConfigSpinBox {
                        icon: "charger"
                        text: Translation.tr("Full / Plugged alert (%)")
                        value: Config.options?.battery?.full ?? 0
                        from: 0
                        to: 101
                        stepSize: 5
                        onValueChanged: Config.setNestedValue("battery.full", value)
                        StyledToolTip {
                            text: Translation.tr("Notify when battery reaches this level while charging (101 = disabled)")
                        }
                    }

                    ConfigRow {
                        uniform: false

                        SettingsSwitch {
                            buttonIcon: "pause"
                            text: Translation.tr("Automatic suspend")
                            checked: Config.options?.battery?.automaticSuspend ?? false
                            onCheckedChanged: Config.setNestedValue("battery.automaticSuspend", checked)
                            StyledToolTip {
                                text: Translation.tr("Automatically suspends the system when battery is low")
                            }
                        }

                        ConfigSpinBox {
                            enabled: Config.options?.battery?.automaticSuspend ?? false
                            text: Translation.tr("at (%)")
                            value: Config.options?.battery?.suspend ?? 0
                            from: 0
                            to: 100
                            stepSize: 5
                            onValueChanged: Config.setNestedValue("battery.suspend", value)
                            StyledToolTip {
                                text: Translation.tr("Percentage of battery to trigger suspend")
                            }
                        }
                    }

                    BatteryChargeLimitSettings {
                        Layout.fillWidth: true
                        staged: true
                        showStatus: false
                    }

                    SettingsDivider {}

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        MaterialSymbol {
                            text: TlpSettingsService.configAvailable
                                ? (TlpSettingsService.enabled ? "check_circle" : "pause_circle")
                                : "warning"
                            iconSize: Appearance.font.pixelSize.large
                            color: TlpSettingsService.configAvailable
                                ? Appearance.colors.colPrimary
                                : Appearance.colors.colError
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: root.statusDescription()
                                + (TlpSettingsService.hasPendingChanges
                                    ? " · " + Translation.tr("%1 staged change(s)").arg(TlpSettingsService.pendingCount)
                                    : "")
                            font.pixelSize: Appearance.font.pixelSize.small
                            wrapMode: Text.WordWrap
                        }

                        DialogButton {
                            buttonText: Translation.tr("Refresh")
                            enabled: !TlpSettingsService.busy
                            onClicked: {
                                TlpSettingsService.refresh()
                                TlpService.refresh()
                            }
                        }

                        DialogButton {
                            buttonText: Translation.tr("Discard")
                            visible: TlpSettingsService.hasPendingChanges
                            enabled: TlpSettingsService.hasPendingChanges && !TlpSettingsService.busy
                            onClicked: TlpSettingsService.discard()
                        }

                        DialogButton {
                            buttonText: TlpSettingsService.busy
                                ? Translation.tr("Applying…")
                                : Translation.tr("Apply")
                            enabled: TlpSettingsService.hasPendingChanges
                                && TlpSettingsService.supported
                                && TlpSettingsService.configAvailable
                                && !TlpSettingsService.busy
                            colBackground: Appearance.colors.colPrimary
                            colBackgroundHover: Appearance.colors.colPrimaryHover
                            colRipple: Appearance.colors.colPrimaryActive
                            colText: Appearance.colors.colOnPrimary
                            onClicked: TlpSettingsService.apply()
                        }

                        DialogButton {
                            buttonText: Translation.tr("Reset")
                            enabled: TlpSettingsService.canResetOverrides
                            onClicked: TlpSettingsService.reset()
                        }
                    }

                    StyledText {
                        visible: TlpSettingsService.lastError.length > 0
                        Layout.fillWidth: true
                        text: TlpSettingsService.lastError
                        color: Appearance.colors.colError
                        wrapMode: Text.WordWrap
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }
                }
            }

            SettingsCardSection {
                id: tlpDevicesCard
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                _preventBentoReparent: true
                visible: root.deviceSavingGroups.length > 0
                expanded: true
                collapsible: false
                icon: "wifi"
                title: Translation.tr("Wireless, Audio & USB Power Saving")

                SettingsGroup {
                    Repeater {
                        model: root.visible ? root.deviceSavingGroups : []

                        delegate: ColumnLayout {
                            id: devGroupBlock
                            required property var modelData
                            required property int index
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignTop
                            spacing: 4
                            readonly property var groupSettings: TlpSettingsService._array(devGroupBlock.modelData?.settings)
                            readonly property bool compactProfileRows: TlpSettingsService._settingsUseCompactProfileRows(devGroupBlock.groupSettings)
                            readonly property bool singleSettingGroup: devGroupBlock.groupSettings.length === 1
                            readonly property string groupTitleText: String(devGroupBlock.modelData?.title ?? "")

                            StyledText {
                                visible: !devGroupBlock.singleSettingGroup
                                    && devGroupBlock.groupTitleText.length > 0
                                Layout.fillWidth: true
                                text: Translation.tr(devGroupBlock.groupTitleText)
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnLayer1
                            }

                            Repeater {
                                model: devGroupBlock.groupSettings

                                delegate: Integration.TlpSettingRow {
                                    required property var modelData
                                    definition: modelData
                                    groupTitle: devGroupBlock.groupTitleText
                                    groupDescription: ""
                                    compactProfileRows: devGroupBlock.compactProfileRows
                                    singleSettingGroup: devGroupBlock.singleSettingGroup
                                }
                            }
                        }
                    }
                }
            }
        }

        // RIGHT COLUMN: Platform & CPU Power Profiles
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredWidth: 1
            Layout.alignment: Qt.AlignTop
            spacing: SettingsMaterialPreset.pageSpacing

            SettingsCardSection {
                id: tlpTuningCard
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                _preventBentoReparent: true
                visible: root.cpuProfileGroups.length > 0
                expanded: true
                collapsible: false
                icon: "tune"
                title: Translation.tr("Platform & CPU Power Profiles")

                SettingsGroup {
                    Repeater {
                        model: root.visible ? root.cpuProfileGroups : []

                        delegate: ColumnLayout {
                            id: groupBlock
                            required property var modelData
                            required property int index
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignTop
                            spacing: 4
                            readonly property var groupSettings: TlpSettingsService._array(groupBlock.modelData?.settings)
                            readonly property bool compactProfileRows: TlpSettingsService._settingsUseCompactProfileRows(groupBlock.groupSettings)
                            readonly property bool singleSettingGroup: groupBlock.groupSettings.length === 1
                            readonly property string groupTitleText: String(groupBlock.modelData?.title ?? "")

                            StyledText {
                                visible: !groupBlock.singleSettingGroup
                                    && groupBlock.groupTitleText.length > 0
                                Layout.fillWidth: true
                                text: Translation.tr(groupBlock.groupTitleText)
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnLayer1
                            }

                            Repeater {
                                model: groupBlock.groupSettings

                                delegate: Integration.TlpSettingRow {
                                    required property var modelData
                                    definition: modelData
                                    groupTitle: groupBlock.groupTitleText
                                    groupDescription: ""
                                    compactProfileRows: groupBlock.compactProfileRows
                                    singleSettingGroup: groupBlock.singleSettingGroup
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Item {
        id: categoryRailContainer
        objectName: "tlpCategoryNavigator"
        visible: false
        Layout.fillWidth: true
        Layout.preferredHeight: 0
        Layout.maximumHeight: 0
        implicitHeight: 0
        opacity: 0
        clip: true
    }
}
