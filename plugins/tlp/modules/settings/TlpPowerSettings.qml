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
    property bool embeddedInIntegrationsHeader: false
    readonly property Component headerStatusBar: tlpHeaderStatusBarComponent
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

    // Shared icon-only TLP Status & Action Pills (rendered inside Integrations header when embedded, or top bar standalone)
    Component {
        id: tlpHeaderStatusBarComponent

        RowLayout {
            id: tlpTopStatusRow
            spacing: 6

            function statusSummary(): string {
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

            // 1. TLP Runtime Status Icon Pill
            RippleButton {
                objectName: "tlpStatusBadgeButton"
                implicitWidth: 32
                implicitHeight: 32
                buttonRadius: 16
                colBackground: !TlpSettingsService.configAvailable
                    ? Appearance.colors.colErrorContainer
                    : TlpSettingsService.enabled
                        ? Appearance.colors.colPrimaryContainer
                        : Appearance.colors.colLayer2
                colBackgroundHover: !TlpSettingsService.configAvailable
                    ? Appearance.colors.colErrorContainer
                    : TlpSettingsService.enabled
                        ? Appearance.colors.colPrimaryContainerHover
                        : Appearance.colors.colLayer2Hover
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: TlpSettingsService.configAvailable
                        ? (TlpSettingsService.enabled ? "check_circle" : "pause_circle")
                        : "warning"
                    iconSize: Appearance.font.pixelSize.large
                    color: !TlpSettingsService.configAvailable
                        ? Appearance.colors.colOnErrorContainer
                        : TlpSettingsService.enabled
                            ? Appearance.colors.colOnPrimaryContainer
                            : Appearance.colors.colSubtext
                }
                StyledToolTip {
                    text: tlpTopStatusRow.statusSummary() + " · "
                        + (TlpSettingsService.hasPendingChanges
                            ? Translation.tr("%1 staged change(s)").arg(TlpSettingsService.pendingCount)
                            : Translation.tr("Effective values"))
                }
            }

            // 2. Overrides / Staged vs Effective State Icon Pill
            RippleButton {
                objectName: "tlpStateBadgeButton"
                implicitWidth: 32
                implicitHeight: 32
                buttonRadius: 16
                colBackground: TlpSettingsService.hasPendingChanges
                    ? Appearance.colors.colTertiaryContainer
                    : Appearance.colors.colSecondaryContainer
                colBackgroundHover: TlpSettingsService.hasPendingChanges
                    ? Appearance.colors.colTertiaryContainer
                    : Appearance.colors.colSecondaryContainerHover
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: TlpSettingsService.hasPendingChanges ? "pending_actions" : "verified"
                    iconSize: Appearance.font.pixelSize.normal
                    color: TlpSettingsService.hasPendingChanges
                        ? Appearance.colors.colOnTertiaryContainer
                        : Appearance.colors.colOnSecondaryContainer
                }
                StyledToolTip {
                    text: TlpSettingsService.hasPendingChanges
                        ? Translation.tr("%1 staged change(s)").arg(TlpSettingsService.pendingCount)
                        : Translation.tr("Effective values")
                }
            }

            // 3. Error Indicator Icon Pill (only visible when an error exists)
            RippleButton {
                objectName: "tlpErrorBadgeButton"
                visible: TlpSettingsService.lastError.length > 0
                implicitWidth: 32
                implicitHeight: 32
                buttonRadius: 16
                colBackground: Appearance.colors.colErrorContainer
                colBackgroundHover: Appearance.colors.colErrorContainer
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "error"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnErrorContainer
                }
                StyledToolTip {
                    text: TlpSettingsService.lastError
                }
            }

            Rectangle {
                Layout.preferredWidth: 1
                Layout.preferredHeight: 18
                color: Appearance.colors.colOutlineVariant
                opacity: 0.6
            }

            // 4. Refresh Action Icon Button
            RippleButton {
                objectName: "tlpRefreshIconButton"
                implicitWidth: 32
                implicitHeight: 32
                buttonRadius: 16
                enabled: !TlpSettingsService.busy
                colBackground: Appearance.colors.colLayer2
                colBackgroundHover: Appearance.colors.colLayer2Hover
                colRipple: Appearance.colors.colLayer2Active
                onClicked: {
                    TlpSettingsService.refresh()
                    TlpService.refresh()
                }
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "refresh"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colPrimary
                }
                StyledToolTip {
                    text: Translation.tr("Refresh")
                }
            }

            // 5. Discard Staged Changes Icon Button
            RippleButton {
                objectName: "tlpDiscardIconButton"
                visible: TlpSettingsService.hasPendingChanges
                enabled: TlpSettingsService.hasPendingChanges && !TlpSettingsService.busy
                implicitWidth: 32
                implicitHeight: 32
                buttonRadius: 16
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colSecondaryActive
                onClicked: TlpSettingsService.discard()
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "undo"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnSecondaryContainer
                }
                StyledToolTip {
                    text: Translation.tr("Discard")
                }
            }

            // 6. Apply Changes Icon Button
            RippleButton {
                objectName: "tlpApplyIconButton"
                enabled: TlpSettingsService.hasPendingChanges
                    && TlpSettingsService.supported
                    && TlpSettingsService.configAvailable
                    && !TlpSettingsService.busy
                implicitWidth: 32
                implicitHeight: 32
                buttonRadius: 16
                colBackground: enabled
                    ? Appearance.colors.colPrimary
                    : Appearance.colors.colLayer2
                colBackgroundHover: enabled
                    ? Appearance.colors.colPrimaryHover
                    : Appearance.colors.colLayer2Hover
                colRipple: Appearance.colors.colPrimaryActive
                onClicked: TlpSettingsService.apply()
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: TlpSettingsService.busy ? "hourglass_top" : "check"
                    iconSize: Appearance.font.pixelSize.normal
                    color: parent.enabled
                        ? Appearance.colors.colOnPrimary
                        : Appearance.colors.colOnLayer2
                }
                StyledToolTip {
                    text: TlpSettingsService.busy
                        ? Translation.tr("Applying…")
                        : Translation.tr("Apply")
                }
            }

            // 7. Reset Overrides Icon Button
            RippleButton {
                objectName: "tlpResetIconButton"
                enabled: TlpSettingsService.canResetOverrides && !TlpSettingsService.busy
                implicitWidth: 32
                implicitHeight: 32
                buttonRadius: 16
                colBackground: enabled
                    ? Appearance.colors.colErrorContainer
                    : Appearance.colors.colLayer2
                colBackgroundHover: enabled
                    ? Appearance.colors.colErrorContainer
                    : Appearance.colors.colLayer2Hover
                colRipple: Appearance.colors.colLayer2Active
                onClicked: TlpSettingsService.reset()
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "restart_alt"
                    iconSize: Appearance.font.pixelSize.normal
                    color: parent.enabled
                        ? Appearance.colors.colOnErrorContainer
                        : Appearance.colors.colOnLayer2
                }
                StyledToolTip {
                    text: Translation.tr("Reset")
                }
            }
        }
    }

    // Standalone Top Sub-Tab Bar (hidden when Integrations header hosts the bar inline)
    Rectangle {
        id: tlpTopStatusSubTab
        objectName: "tlpTopStatusSubTab"
        visible: !root.embeddedInIntegrationsHeader
        Layout.alignment: Qt.AlignHCenter
        Layout.bottomMargin: visible ? SettingsMaterialPreset.pageSpacing : 0
        implicitWidth: (tlpStandaloneStatusLoader.item?.implicitWidth ?? 0) + 16
        implicitHeight: visible ? 42 : 0
        radius: Appearance.rounding.full
        color: Appearance.colors.colLayer1
        border.width: 1
        border.color: Appearance.colors.colLayer0Border

        Loader {
            id: tlpStandaloneStatusLoader
            anchors.centerIn: parent
            active: !root.embeddedInIntegrationsHeader
            sourceComponent: tlpHeaderStatusBarComponent
        }
    }

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
                title: Translation.tr("Battery & TLP")

                SettingsGroup {
                    ConfigSpinBox {
                        icon: "warning"
                        text: Translation.tr("Low warning")
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
                        text: Translation.tr("Full warning")
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
        visible: root.navigationCategories.length > 0
        width: root.width
        Layout.fillWidth: true
        Layout.maximumWidth: root.width
        Layout.preferredHeight: 0
        Layout.maximumHeight: 0
        implicitHeight: 0
        opacity: 0
        clip: true

        Rectangle {
            id: categoryRail
            objectName: "tlpCategoryRail"
            width: root.width
            implicitHeight: categoryTabs.implicitHeight
            height: implicitHeight
            color: "transparent"

            ConfigSelectionArray {
                id: categoryTabs
                objectName: "tlpCategoryTabs"
                width: root.width
                taskNavigation: true
                useAbyssPillShape: false
                currentValue: root.selectedCategoryIndex
                options: root.navigationCategories.map((category, index) => ({
                    displayName: Translation.tr(TlpSettingsService.categoryLabel(category)),
                    icon: String(category?.icon ?? "tune"),
                    value: index
                }))
                onSelected: value => root.selectCategory(Number(value))
            }
        }
    }
}
