pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
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
        defaultGalleryMode: "timeline",
        showBodyMetrics: true
    })

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
                                    color: Appearance.colors.colPrimary
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
                    text: Translation.tr("Auto-update linked Weekly Planner blocks")
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
