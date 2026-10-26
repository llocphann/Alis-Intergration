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
    objectName: "hadalirdTlpPowerSettings"

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
    // Charge care is integrated into the Battery/TLP card above the category
    // browser. Keep the browser focused on the ten general TLP categories.
    readonly property var navigationCategories:
        TlpSettingsService._array(TlpSettingsService.navigationCategories)
            .filter(category => String(category?.id ?? "") !== "battery-care")
    readonly property var selectedCategory: {
        const categories = root.navigationCategories
        if (categories.length === 0)
            return null
        return categories[Math.max(0, Math.min(root.selectedCategoryIndex, categories.length - 1))]
    }
    readonly property var visibleGroups: TlpSettingsService.groupsForCategory(
        root.selectedCategory, root.filterText)
    readonly property bool profileGuidanceVisible: root.visibleGroups.some(group =>
        String(group?.description ?? "").includes(root.profileGuidanceSource))

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

    SettingsCardSection {
        expanded: true
        collapsible: false
        icon: "battery_saver"
        title: Translation.tr("Battery & TLP")

        SettingsGroup {
            ConfigRow {
                uniform: true

                ConfigSpinBox {
                    icon: "warning"
                    text: Translation.tr("Low warning")
                    value: Config.options?.battery?.low ?? 0
                    from: 0
                    to: 100
                    stepSize: 5
                    onValueChanged: {
                        Config.setNestedValue("battery.low", value)
                    }

                    StyledToolTip {
                        text: Translation.tr("Show warning notification when battery drops below this level")
                    }
                }

                ConfigSpinBox {
                    icon: "dangerous"
                    text: Translation.tr("Critical warning")
                    value: Config.options?.battery?.critical ?? 0
                    from: 0
                    to: 100
                    stepSize: 5
                    onValueChanged: {
                        Config.setNestedValue("battery.critical", value)
                    }

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
                    onValueChanged: {
                        Config.setNestedValue("battery.full", value)
                    }

                    StyledToolTip {
                        text: Translation.tr("Notify when battery reaches this level while charging (101 = disabled)")
                    }
                }
            }

            SettingsDivider {}

            ConfigRow {
                uniform: true

                ConfigRow {
                    Layout.fillWidth: true
                    uniform: false

                    SettingsSwitch {
                        buttonIcon: "pause"
                        text: Translation.tr("Automatic suspend")
                        checked: Config.options?.battery?.automaticSuspend ?? false
                        onCheckedChanged: {
                            Config.setNestedValue("battery.automaticSuspend", checked)
                        }

                        StyledToolTip {
                            text: Translation.tr("Automatically suspends the system when battery is low")
                        }
                    }

                    ConfigSpinBox {
                        enabled: Config.options?.battery?.automaticSuspend ?? false
                        text: Translation.tr("at")
                        value: Config.options?.battery?.suspend ?? 0
                        from: 0
                        to: 100
                        stepSize: 5
                        onValueChanged: {
                            Config.setNestedValue("battery.suspend", value)
                        }

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

            SettingsDivider {}

            RowLayout {
                Layout.fillWidth: true
                spacing: SettingsMaterialPreset.groupPadding

                MaterialSymbol {
                    text: TlpSettingsService.configAvailable
                        ? (TlpSettingsService.enabled ? "check_circle" : "pause_circle")
                        : "warning"
                    iconSize: Appearance.font.pixelSize.huge
                    color: TlpSettingsService.configAvailable
                        ? Appearance.colors.colPrimary
                        : Appearance.colors.colError
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: SettingsMaterialPreset.groupSpacing

                    StyledText {
                        Layout.fillWidth: true
                        text: root.statusDescription()
                        wrapMode: Text.WordWrap
                    }

                }

                DialogButton {
                    buttonText: Translation.tr("Refresh status")
                    enabled: !TlpSettingsService.busy
                    onClicked: {
                        TlpSettingsService.refresh()
                        TlpService.refresh()
                    }
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

            SettingsDivider {}

            RowLayout {
                Layout.fillWidth: true
                spacing: SettingsMaterialPreset.groupSpacing

                StyledText {
                    Layout.fillWidth: true
                    text: TlpSettingsService.hasPendingChanges
                        ? Translation.tr("%1 staged change(s)").arg(TlpSettingsService.pendingCount)
                        : Translation.tr("Effective values")
                    color: TlpSettingsService.hasPendingChanges
                        ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                    font.weight: TlpSettingsService.hasPendingChanges ? Font.Medium : Font.Normal
                }

                DialogButton {
                    buttonText: Translation.tr("Discard")
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
                    buttonText: Translation.tr("Reset overrides")
                    enabled: TlpSettingsService.canResetOverrides
                    onClicked: TlpSettingsService.reset()
                }
            }

        }
    }

    Item {
        id: categoryRailContainer
        objectName: "tlpCategoryNavigator"
        visible: root.navigationCategories.length > 0
        Layout.fillWidth: true
        Layout.preferredHeight: 0
        Layout.maximumHeight: 0
        implicitHeight: 0
        opacity: 0
        clip: true
        readonly property bool abyssTaskStyle: Config.options?.panelFamily === "abyss"
        readonly property real padding: abyssTaskStyle ? SettingsMaterialPreset.taskTabPadding : 0

        Rectangle {
            objectName: "tlpCategoryRail"
            anchors.fill: parent
            visible: categoryRailContainer.abyssTaskStyle
            color: SettingsMaterialPreset.taskRailColor
            radius: SettingsMaterialPreset.taskRailRadius
        }

        ConfigSelectionArray {
            id: categoryTabs
            objectName: "tlpCategoryTabs"
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: parent.padding
            y: parent.padding
            enableSettingsSearch: false
            enabled: !TlpSettingsService.busy
            taskNavigation: true
            useAbyssPillShape: false
            currentValue: root.selectedCategoryIndex
            options: root.navigationCategories.map((category, index) => ({
                displayName: Translation.tr(TlpSettingsService.categoryLabel(category)),
                icon: String(category?.icon ?? "tune"),
                value: index,
                enabled: !TlpSettingsService.busy
            }))
            onSelected: value => root.selectCategory(Number(value))
        }
    }

    GridLayout {
        id: tlpCategoriesGrid
        Layout.fillWidth: true
        columns: width >= 620 ? 2 : 1
        uniformCellWidths: columns === 2
        columnSpacing: 14
        rowSpacing: 14

        Repeater {
            model: root.navigationCategories

            delegate: SettingsCardSection {
                id: categoryCard
                required property var modelData
                required property int index
                Layout.preferredWidth: 1
                Layout.fillWidth: true
                Layout.fillHeight: true
                expanded: true
                collapsible: true
                icon: String(categoryCard.modelData?.icon ?? "tune")
                title: Translation.tr(TlpSettingsService.categoryLabel(categoryCard.modelData))
                readonly property var categoryGroups: TlpSettingsService.groupsForCategory(categoryCard.modelData, root.filterText)
                visible: categoryGroups.length > 0

                SettingsGroup {
                    Repeater {
                        model: categoryCard.categoryGroups

                        delegate: ColumnLayout {
                            id: groupBlock
                            required property var modelData
                            required property int index
                            Layout.fillWidth: true
                            spacing: 6
                            readonly property var groupSettings: TlpSettingsService._array(groupBlock.modelData?.settings)
                            readonly property bool compactProfileRows: TlpSettingsService._settingsUseCompactProfileRows(groupBlock.groupSettings)
                            readonly property bool singleSettingGroup: groupBlock.groupSettings.length === 1

                            SettingsDivider {
                                visible: groupBlock.index > 0
                            }

                            StyledText {
                                visible: categoryCard.categoryGroups.length > 1 && String(groupBlock.modelData?.title ?? "").length > 0
                                Layout.fillWidth: true
                                text: Translation.tr(String(groupBlock.modelData?.title ?? ""))
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnLayer1
                            }

                            Repeater {
                                model: groupBlock.groupSettings

                                delegate: Integration.TlpSettingRow {
                                    required property var modelData
                                    definition: modelData
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
}
