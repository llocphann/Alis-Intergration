pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.settings
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

SettingsCardSection {
    id: root
    objectName: "alisIntergrationExercisesTrackerSettings"
    settingsTaskSection: "exercisesTracker"
    expanded: true
    icon: "fitness_center"
    title: Translation.tr("Exercises Tracker")

    readonly property var tracker: AlisIntergration?.exercisesTracker
        ?? AlisIntergration?.session?.exercisesTracker
        ?? null
    readonly property var prefs: tracker?.preferences ?? ({
        weightUnit: "kg",
        defaultSets: 3,
        defaultRestSeconds: 90,
        autoStartRestOnSet: true,
        autoSyncPlanner: true,
        showInNexus: true,
        workoutDefaultHour: 18,
        workoutDefaultDurationMin: 60,
        workoutReminderMinutes: 15,
        bodyPhotosStorageMode: "auto",
        bodyPhotosCustomDir: "",
        defaultGalleryMode: "timeline",
        showBodyMetrics: true
    })

    SettingsNativeDialogGuard { dialog: bodyPhotosFolderPicker; dialogKey: "exercisesBodyPhotosPicker" }
    FolderDialog {
        id: bodyPhotosFolderPicker
        title: Translation.tr("Body Tracker photos folder")
        onAccepted: {
            const chosen = FileUtils.trimFileProtocol(String(selectedFolder)).trim()
            if (chosen.length > 0 && root.tracker && typeof root.tracker.updatePreferences === "function") {
                root.tracker.updatePreferences({
                    bodyPhotosStorageMode: "custom",
                    bodyPhotosCustomDir: chosen
                })
            }
        }
    }

    function ensureExercisesTrackerInPageOrder(): void {
        const current = Array.from(Config.options?.dashboard?.pageOrder ?? ["dashboard", "music", "weeklyPlanner"])
        if (!current.includes("exercisesTracker"))
            Config.setNestedValue("dashboard.pageOrder", current.concat(["exercisesTracker"]))
    }

    function setPref(key: string, value): void {
        if (!root.tracker || typeof root.tracker.updatePreferences !== "function")
            return
        if (root.prefs?.[key] === value)
            return
        const patch = {}
        patch[key] = value
        root.tracker.updatePreferences(patch)
    }

    SettingsGroup {
        SettingsSwitch {
            objectName: "exercisesSettingsEnableTabSwitch"
            Layout.fillWidth: true
            buttonIcon: "fitness_center"
            text: Translation.tr("Show Exercises Tracker tab in Dashboard")
            checked: Config.options?.dashboard?.exercisesTracker?.enable ?? true
            onCheckedChanged: {
                Config.setNestedValue("dashboard.exercisesTracker.enable", checked)
                if (checked)
                    root.ensureExercisesTrackerInPageOrder()
            }
        }

        ContentSubsection {
            title: Translation.tr("Units & workout defaults")

            ConfigSelectionArray {
                objectName: "exercisesSettingsWeightUnitSelector"
                currentValue: String(root.prefs.weightUnit ?? "kg")
                onSelected: value => root.setPref("weightUnit", value)
                options: [
                    { displayName: Translation.tr("Kilograms (kg)"), icon: "scale", value: "kg" },
                    { displayName: Translation.tr("Pounds (lb)"), icon: "fitness_center", value: "lb" }
                ]
            }

            ConfigRow {
                uniform: true

                ConfigSpinBox {
                    objectName: "exercisesSettingsDefaultSetsSpin"
                    Layout.fillWidth: true
                    icon: "repeat"
                    text: Translation.tr("Default sets")
                    value: Number(root.prefs.defaultSets ?? 3)
                    from: 1
                    to: 30
                    stepSize: 1
                    onValueChanged: root.setPref("defaultSets", value)
                }

                ConfigSpinBox {
                    objectName: "exercisesSettingsDefaultRestSpin"
                    Layout.fillWidth: true
                    icon: "timer"
                    text: Translation.tr("Default rest (s)")
                    value: Number(root.prefs.defaultRestSeconds ?? 90)
                    from: 15
                    to: 600
                    stepSize: 15
                    onValueChanged: root.setPref("defaultRestSeconds", value)
                }
            }

            SettingsSwitch {
                objectName: "exercisesSettingsAutoRestSwitch"
                Layout.fillWidth: true
                buttonIcon: "play_circle"
                text: Translation.tr("Auto-start rest timer after completing a set")
                checked: root.prefs.autoStartRestOnSet !== false
                onCheckedChanged: root.setPref("autoStartRestOnSet", checked)
            }
        }

        ContentSubsection {
            title: Translation.tr("Weekly routine split")

            ConfigSelectionArray {
                objectName: "exercisesSettingsSplitPresetSelector"
                currentValue: ""
                onSelected: value => {
                    if (root.tracker && typeof root.tracker.applySplitPreset === "function")
                        root.tracker.applySplitPreset(value)
                }
                options: [
                    { displayName: Translation.tr("Push / Pull / Legs"), icon: "fitness_center", value: "ppl" },
                    { displayName: Translation.tr("Upper / Lower"), icon: "swap_vert", value: "upper_lower" },
                    { displayName: Translation.tr("Full Body 3×"), icon: "sports_martial_arts", value: "full_body" },
                    { displayName: Translation.tr("Cardio & Core"), icon: "monitor_heart", value: "cardio_core" }
                ]
            }

            Flow {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 6

                Repeater {
                    model: [
                        { key: "1", label: Translation.tr("Mon") },
                        { key: "2", label: Translation.tr("Tue") },
                        { key: "3", label: Translation.tr("Wed") },
                        { key: "4", label: Translation.tr("Thu") },
                        { key: "5", label: Translation.tr("Fri") },
                        { key: "6", label: Translation.tr("Sat") },
                        { key: "0", label: Translation.tr("Sun") }
                    ]
                    delegate: RippleButton {
                        id: wdChip
                        required property var modelData
                        objectName: "exercisesWeekdaySplit_" + modelData.key
                        readonly property string routineId: String(root.tracker?.weeklyTemplates?.[modelData.key] ?? "push")
                        readonly property var orderIds: ["push", "pull", "legs", "core", "cardio", "full_body", "rest", "custom"]
                        implicitHeight: 30
                        implicitWidth: wdChipRow.implicitWidth + 18
                        buttonRadius: 15
                        colBackground: Appearance.colors.colLayer2
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        onClicked: {
                            if (!root.tracker || typeof root.tracker.setWeekdayRoutine !== "function")
                                return
                            const idx = Math.max(0, wdChip.orderIds.indexOf(wdChip.routineId))
                            const nextId = wdChip.orderIds[(idx + 1) % wdChip.orderIds.length]
                            root.tracker.setWeekdayRoutine(wdChip.modelData.key, nextId)
                        }
                        contentItem: Item {
                            Row {
                                id: wdChipRow
                                anchors.centerIn: parent
                                spacing: 5
                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: wdChip.modelData.label + ":"
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: Appearance.colors.colSubtext
                                }
                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: wdChip.routineId === "full_body" ? "Full Body"
                                        : wdChip.routineId === "rest" ? "Recovery"
                                        : (wdChip.routineId.charAt(0).toUpperCase() + wdChip.routineId.slice(1))
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    font.weight: Font.DemiBold
                                    color: ColorUtils.ensureReadable(Appearance.colors.colPrimary, Appearance.colors.colLayer2, 4.5)
                                }
                            }
                        }
                        StyledToolTip { text: Translation.tr("Click to cycle weekday routine") }
                    }
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Weekly Planner & Alis Nexus sync")

            ConfigRow {
                uniform: true

                SettingsSwitch {
                    objectName: "exercisesSettingsAutoPlannerSwitch"
                    Layout.fillWidth: true
                    buttonIcon: "calendar_month"
                    text: Translation.tr("Auto-sync workouts with Weekly & Yearly Planner")
                    checked: root.prefs.autoSyncPlanner !== false
                    onCheckedChanged: root.setPref("autoSyncPlanner", checked)
                }

                SettingsSwitch {
                    objectName: "exercisesSettingsShowNexusSwitch"
                    Layout.fillWidth: true
                    buttonIcon: "hub"
                    text: Translation.tr("Show workout card on Nexus Homepage")
                    checked: root.prefs.showInNexus !== false
                    onCheckedChanged: root.setPref("showInNexus", checked)
                }
            }

            ConfigRow {
                uniform: true

                ConfigSpinBox {
                    objectName: "exercisesSettingsStartHourSpin"
                    Layout.fillWidth: true
                    icon: "schedule"
                    text: Translation.tr("Default start hour")
                    value: Number(root.prefs.workoutDefaultHour ?? 18)
                    from: 0
                    to: 23
                    stepSize: 1
                    onValueChanged: root.setPref("workoutDefaultHour", value)
                }

                ConfigSpinBox {
                    objectName: "exercisesSettingsDurationSpin"
                    Layout.fillWidth: true
                    icon: "hourglass_bottom"
                    text: Translation.tr("Default duration (m)")
                    value: Number(root.prefs.workoutDefaultDurationMin ?? 60)
                    from: 15
                    to: 240
                    stepSize: 15
                    onValueChanged: root.setPref("workoutDefaultDurationMin", value)
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                StyledText {
                    text: Translation.tr("Workout reminder")
                    color: Appearance.colors.colOnSurfaceVariant
                    font.pixelSize: Appearance.font.pixelSize.small
                }

                ConfigSelectionArray {
                    objectName: "exercisesSettingsReminderSelector"
                    currentValue: Number(root.prefs.workoutReminderMinutes ?? 15)
                    onSelected: value => root.setPref("workoutReminderMinutes", Number(value))
                    options: [
                        { displayName: Translation.tr("Off"), icon: "notifications_off", value: 0 },
                        { displayName: Translation.tr("5m"), icon: "notifications", value: 5 },
                        { displayName: Translation.tr("10m"), icon: "notifications", value: 10 },
                        { displayName: Translation.tr("15m"), icon: "alarm", value: 15 },
                        { displayName: Translation.tr("30m"), icon: "alarm", value: 30 },
                        { displayName: Translation.tr("1h"), icon: "schedule", value: 60 }
                    ]
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Post-workout Body Tracker")

            ConfigSelectionArray {
                objectName: "exercisesSettingsGalleryModeSelector"
                currentValue: String(root.prefs.defaultGalleryMode ?? "timeline")
                onSelected: value => root.setPref("defaultGalleryMode", value)
                options: [
                    { displayName: Translation.tr("Timeline"), icon: "view_agenda", value: "timeline" },
                    { displayName: Translation.tr("Before / After Compare"), icon: "compare", value: "compare" }
                ]
            }

            SettingsSwitch {
                objectName: "exercisesSettingsShowMetricsSwitch"
                Layout.fillWidth: true
                buttonIcon: "monitor_weight"
                text: Translation.tr("Show body weight & body-fat % inputs")
                checked: root.prefs.showBodyMetrics !== false
                onCheckedChanged: root.setPref("showBodyMetrics", checked)
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6

                StyledText {
                    text: Translation.tr("Photo storage")
                    color: Appearance.colors.colOnSurfaceVariant
                    font.pixelSize: Appearance.font.pixelSize.small
                }

                ConfigSelectionArray {
                    objectName: "exercisesSettingsPhotoStorageModeSelector"
                    currentValue: String(root.prefs.bodyPhotosStorageMode ?? "auto")
                    onSelected: value => root.setPref("bodyPhotosStorageMode", value)
                    options: [
                        { displayName: Translation.tr("Nexus Auto (Smart)"), icon: "auto_awesome", value: "auto" },
                        { displayName: Translation.tr("Custom Folder"), icon: "folder", value: "custom" }
                    ]
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    visible: String(root.prefs.bodyPhotosStorageMode ?? "auto") === "custom"

                    MaterialTextField {
                        id: customPhotoDirField
                        objectName: "exercisesSettingsCustomPhotoDirField"
                        Layout.fillWidth: true
                        wrapMode: TextInput.NoWrap
                        placeholderText: Translation.tr("Absolute path or vault-relative folder (e.g. 90_System/95_Attachments/Body)")
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.family: Appearance.font.family.monospace
                        color: Appearance.colors.colOnSurface
                        text: String(root.prefs.bodyPhotosCustomDir ?? "")
                        background: Rectangle {
                            color: Appearance.colors.colLayer1
                            radius: Appearance.rounding.small
                            border.width: customPhotoDirField.activeFocus ? 2 : 1
                            border.color: customPhotoDirField.activeFocus
                                ? Appearance.colors.colPrimary
                                : Appearance.colors.colLayer0Border
                        }
                        onEditingFinished: root.setPref("bodyPhotosCustomDir", text.trim())
                    }

                    RippleButtonWithIcon {
                        objectName: "exercisesSettingsBrowsePhotoDirButton"
                        materialIcon: "folder_open"
                        mainText: Translation.tr("Browse")
                        onClicked: bodyPhotosFolderPicker.open()
                    }
                }

                Rectangle {
                    objectName: "exercisesSettingsPhotosStorageStatus"
                    Layout.fillWidth: true
                    implicitHeight: photosStorageStatusCol.implicitHeight + 14
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colLayer1
                    border.width: 1
                    border.color: Appearance.colors.colLayer0Border

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 7
                        spacing: 8

                        MaterialSymbol {
                            Layout.alignment: Qt.AlignVCenter
                            text: root.tracker?.resolvedPhotosSource === "nexus-auto"
                                ? "hub"
                                : (root.tracker?.resolvedPhotosSource === "custom" ? "folder" : "info")
                            iconSize: 18
                            color: Appearance.colors.colPrimary
                        }

                        ColumnLayout {
                            id: photosStorageStatusCol
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            spacing: 1

                            StyledText {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                text: {
                                    const src = String(root.tracker?.resolvedPhotosSource ?? "local-fallback")
                                    const vrel = String(root.tracker?.resolvedPhotosVaultRelDir ?? "")
                                    if (src === "nexus-auto" && vrel.length > 0)
                                        return Translation.tr("Synced with Nexus Vault · %1").arg(vrel)
                                    if (src === "custom")
                                        return vrel.length > 0
                                            ? Translation.tr("Custom folder (inside Nexus Vault · %1)").arg(vrel)
                                            : Translation.tr("Custom folder")
                                    return String(root.tracker?.resolvedPhotosReason || Translation.tr("Local fallback folder"))
                                }
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnLayer1
                                elide: Text.ElideRight
                            }

                            StyledText {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                text: String(root.tracker?.effectivePhotosDir ?? root.tracker?.photosDir ?? "")
                                font.family: Appearance.font.family.monospace
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: Appearance.colors.colSubtext
                                elide: Text.ElideMiddle
                            }
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 8

                RippleButton {
                    objectName: "exercisesSettingsOpenTrackerButton"
                    implicitHeight: 34
                    implicitWidth: openTrackerBtnRow.implicitWidth + 24
                    buttonRadius: 17
                    colBackground: Appearance.colors.colPrimary
                    colBackgroundHover: Qt.lighter(Appearance.colors.colPrimary, 1.1)
                    onClicked: {
                        GlobalStates.settingsOverlayOpen = false
                        Config.setNestedValue("dashboard.lastPageId", "exercisesTracker")
                        GlobalStates.dashboardPageId = "exercisesTracker"
                        GlobalStates.dashboardOpen = true
                    }
                    contentItem: Item {
                        Row {
                            id: openTrackerBtnRow
                            anchors.centerIn: parent
                            spacing: 6
                            MaterialSymbol {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "open_in_new"
                                iconSize: 16
                                color: Appearance.colors.colOnPrimary
                            }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: Translation.tr("Open Exercises Tracker")
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnPrimary
                            }
                        }
                    }
                }

                RippleButton {
                    objectName: "exercisesSettingsOpenPhotosButton"
                    implicitHeight: 34
                    implicitWidth: openPhotosBtnRow.implicitWidth + 24
                    buttonRadius: 17
                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    onClicked: root.tracker?.openPhotosFolder()
                    contentItem: Item {
                        Row {
                            id: openPhotosBtnRow
                            anchors.centerIn: parent
                            spacing: 6
                            MaterialSymbol {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "folder_open"
                                iconSize: 16
                                color: Appearance.colors.colOnLayer1
                            }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: Translation.tr("Open Photos Folder")
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.Medium
                                color: Appearance.colors.colOnLayer1
                            }
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                }
            }
        }
    }
}
