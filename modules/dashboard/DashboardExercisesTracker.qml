pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import qs
import qs.services
import qs.services as HostServices
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.abyss.looks

Item {
    id: root
    objectName: "dashboardExercisesTracker"
    focus: true

    property bool presentationActive: false
    property var backend: HostServices.AlisIntergration.exercisesTracker
        ?? HostServices.AlisIntergration.session?.exercisesTracker
        ?? null

    readonly property bool abyss: Config.options?.panelFamily === "abyss"
    readonly property bool alisEverywhere: Appearance.alisEverywhere
    readonly property bool auroraEverywhere: Appearance.auroraEverywhere

    // Stepped flat tonal layers anchored on the auto-theming root background (Layer 0 -> Layer 1 -> Layer 2 -> Layer 3 -> Hover)
    readonly property color colSurfaceBase: ColorUtils.applyAlpha(
        Qt.color(Appearance.colors.colLayer0Base).valid
            ? Appearance.colors.colLayer0Base
            : Appearance.colors.colLayer1Base,
        1.0
    )
    readonly property bool isDarkSurface: ColorUtils.relativeLuminance(root.colSurfaceBase) < 0.35
    // Lighten nested layers when headroom exists; subtly step deeper on near-white canvases
    readonly property real tonalDir: Qt.color(root.colSurfaceBase).hslLightness > 0.86 ? -1 : 1

    readonly property color colCard: abyss
        ? ColorUtils.applyAlpha(ColorUtils.tonalStep(root.colSurfaceBase, root.tonalDir * 0.032, 1.05), Math.max(0.88, AbyssStyle.cardOpacity))
        : Appearance.angelEverywhere ? Appearance.angel.colGlassCard
        : alisEverywhere ? Appearance.alis.colLayer1
        : auroraEverywhere ? Appearance.aurora.colSubSurface
        : ColorUtils.applyAlpha(ColorUtils.tonalStep(root.colSurfaceBase, root.tonalDir * 0.032, 1.05), 1.0)
    readonly property color colCardElevated: {
        const tonal = ColorUtils.tonalStep(
            root.colSurfaceBase,
            root.tonalDir * 0.068,
            1.10
        )
        const base = abyss
            ? tonal
            : Appearance.angelEverywhere ? Appearance.angel.colGlassCardHover
            : alisEverywhere ? Appearance.alis.colLayer2
            : tonal
        return ColorUtils.applyAlpha(base, Math.max(0.94, root.colCard.a))
    }
    readonly property color colInputBg: ColorUtils.applyAlpha(
        ColorUtils.tonalStep(
            root.colSurfaceBase,
            root.tonalDir * (root.tonalDir > 0 ? 0.145 : 0.105),
            1.13
        ),
        0.96
    )
    readonly property color colInputBorder: ColorUtils.applyAlpha(
        ColorUtils.tonalStep(root.colSurfaceBase, root.tonalDir * 0.24, 1.15),
        root.isDarkSurface ? 0.55 : 0.48
    )
    readonly property color colCardHover: ColorUtils.applyAlpha(
        ColorUtils.tonalStep(
            root.colSurfaceBase,
            root.tonalDir * (root.tonalDir > 0 ? 0.168 : 0.130),
            1.15
        ),
        1.0
    )

    readonly property color _rawText: abyss
        ? (root.isDarkSurface ? AbyssStyle.textColor : "#10141c")
        : Appearance.angelEverywhere ? Appearance.angel.colText
        : alisEverywhere ? Appearance.alis.colText
        : Appearance.colors.colOnLayer0
    readonly property color colText: ColorUtils.ensureReadable(root._rawText, root.colCardElevated, 7.0)
    readonly property color _rawSubtext: abyss
        ? ColorUtils.mix(root.colText, root.colSurfaceBase, 0.72)
        : Appearance.angelEverywhere ? Appearance.angel.colTextSecondary
        : alisEverywhere ? Appearance.alis.colTextSecondary
        : Appearance.colors.colSubtext
    readonly property color colSubtext: ColorUtils.ensureReadable(root._rawSubtext, root.colCardElevated, 4.6)
    readonly property color colBorder: ColorUtils.applyAlpha(
        ColorUtils.tonalStep(root.colSurfaceBase, root.tonalDir * 0.24, 1.10),
        0.07
    )
    readonly property color colAccentFill: ColorUtils.applyAlpha(
        abyss ? AbyssStyle.accent : Appearance.colors.colPrimary,
        1.0
    )
    readonly property color colAccent: ColorUtils.adaptAccent(root.colAccentFill, root.colCardElevated, 4.5)
    readonly property color colOnAccent: ColorUtils.ensureReadable(
        Appearance.colors.colOnPrimary,
        root.colAccentFill,
        5.5
    )
    readonly property color colToggledBg: ColorUtils.applyAlpha(
        Appearance.colors.colSecondaryContainer,
        Math.max(0.92, root.colCardElevated.a)
    )
    readonly property color colOnToggled: ColorUtils.ensureReadable(
        Appearance.colors.colOnSecondaryContainer,
        root.colToggledBg,
        5.5
    )
    readonly property color colErrorText: ColorUtils.ensureReadable(
        Appearance.colors.colError,
        root.colCardElevated,
        4.6
    )
    readonly property color colTrackBg: ColorUtils.applyAlpha(
        ColorUtils.tonalStep(root.colSurfaceBase, root.tonalDir * (root.tonalDir > 0 ? 0.108 : 0.095), 1.11),
        1.0
    )
    readonly property color colBannerBg: ColorUtils.mix(root.colCardElevated, root.colAccentFill, 0.82)
    readonly property color colOnBanner: ColorUtils.ensureReadable(root.colAccent, root.colBannerBg, 5.0)
    readonly property color colCompletedRowBg: ColorUtils.mix(root.colCardElevated, root.colAccentFill, 0.86)

    readonly property string preferredWeightUnit: root.backend?.preferences?.weightUnit ?? "kg"
    readonly property bool showBodyMetricsInputs: root.backend?.preferences?.showBodyMetrics ?? true

    // Composer & UI state
    property string editingExerciseId: ""
    property string draftCategory: "chest"
    property int draftSets: root.backend?.preferences?.defaultSets ?? 3
    property string draftReps: "10"
    property string draftWeight: ""
    property string draftDurationMin: ""
    property int draftRestSec: root.backend?.preferences?.defaultRestSeconds ?? 90

    property string stagedPhotoPath: ""
    property bool showPhotoPathInput: false
    property string bodyGalleryMode: root.backend?.preferences?.defaultGalleryMode ?? "timeline" // "timeline" | "compare"
    property string confirmDeleteCheckinId: ""
    property var previewCheckin: null

    readonly property var dayPlan: root.backend?.dayPlan ?? ({
        date: "",
        routine: "push",
        routineLabel: "Push",
        title: "Push Strength",
        plannerEventId: 0,
        scheduledStart: "18:00",
        scheduledEnd: "19:00",
        sessionNote: "",
        exercises: [],
        totalExercises: 0,
        completedExercises: 0,
        completionPct: 0,
        volumeKg: 0,
        estimatedDurationMin: 0
    })

    readonly property var summary: root.backend?.todaySummary ?? ({
        currentStreakDays: 0,
        weeklyVolumeKg: 0,
        totalLoggedWorkouts: 0,
        totalBodyCheckins: 0,
        latestWeightKg: 0,
        latestBodyFatPct: 0
    })

    readonly property var checkins: root.backend?.bodyCheckins ?? []
    readonly property var checkinsWithPhotos: root.checkins.filter(item => item.hasPhoto)
    readonly property var latestCheckin: root.checkins.length > 0 ? root.checkins[0] : null
    readonly property var baselineCheckin: root.checkins.length > 1 ? root.checkins[root.checkins.length - 1] : root.latestCheckin

    function syncBackendActive(): void {
        if (root.backend && root.backend.presentationActive !== (root.presentationActive && root.visible))
            root.backend.presentationActive = root.presentationActive && root.visible
    }

    onPresentationActiveChanged: root.syncBackendActive()
    onVisibleChanged: root.syncBackendActive()
    onBackendChanged: root.syncBackendActive()
    Component.onCompleted: root.syncBackendActive()

    function formatSecondsClock(sec: int): string {
        const total = Math.max(0, Math.floor(sec))
        const mm = String(Math.floor(total / 60)).padStart(2, "0")
        const ss = String(total % 60).padStart(2, "0")
        return mm + ":" + ss
    }

    function trimFileUrl(raw: string): string {
        const s = String(raw ?? "").trim()
        return s.startsWith("file://") ? decodeURIComponent(s.slice(7)) : s
    }

    function resetExerciseDraft(): void {
        root.editingExerciseId = ""
        exerciseNameField.text = ""
        root.draftCategory = "chest"
        root.draftSets = root.backend?.preferences?.defaultSets ?? 3
        root.draftReps = "10"
        root.draftWeight = ""
        root.draftDurationMin = ""
        root.draftRestSec = root.backend?.preferences?.defaultRestSeconds ?? 90
    }

    function beginEditExercise(ex): void {
        if (!ex)
            return
        root.editingExerciseId = String(ex.id ?? "")
        exerciseNameField.text = String(ex.name ?? "")
        root.draftCategory = String(ex.category ?? "chest")
        root.draftSets = Number(ex.sets) || 3
        root.draftReps = String(ex.reps ?? "10")
        root.draftWeight = Number(ex.weight) > 0 ? String(ex.weight) : ""
        root.draftDurationMin = Number(ex.durationSec) > 0 ? String(Math.round(Number(ex.durationSec) / 60)) : ""
        root.draftRestSec = Number(ex.restSec) || 90
        exerciseNameField.forceActiveFocus()
    }

    function submitExerciseDraft(): void {
        if (!root.backend)
            return
        const cleanName = exerciseNameField.text.trim()
        if (!cleanName.length)
            return
        const durMin = Number(root.draftDurationMin) || 0
        const payload = {
            name: cleanName,
            category: root.draftCategory,
            sets: Math.max(1, Math.min(30, Number(setsSpinField.text) || root.draftSets || 3)),
            reps: repsTextField.text.trim() || "10",
            weight: Math.max(0, Number(weightTextField.text) || 0),
            weightUnit: root.preferredWeightUnit,
            durationSec: durMin > 0 ? Math.round(durMin * 60) : 0,
            restSec: Math.max(15, Math.min(600, Number(restTextField.text) || root.draftRestSec || 90))
        }
        if (root.editingExerciseId.length > 0)
            root.backend.updateExercise(root.editingExerciseId, payload)
        else
            root.backend.addExercise(payload)
        root.resetExerciseDraft()
    }

    function submitBodyCheckin(): void {
        if (!root.backend)
            return
        const chosenPath = root.stagedPhotoPath.trim() || root.trimFileUrl(bodyPhotoPathField.text)
        const weightVal = Number(bodyWeightField.text) || 0
        const bfVal = Number(bodyFatField.text) || 0
        const noteVal = bodyNoteField.text.trim()
        if (root.backend.addBodyCheckin(chosenPath, weightVal, bfVal, noteVal, root.backend.selectedDate)) {
            root.stagedPhotoPath = ""
            bodyPhotoPathField.text = ""
            root.showPhotoPathInput = false
            bodyWeightField.text = ""
            bodyFatField.text = ""
            bodyNoteField.text = ""
        }
    }

    function focusPrimarySurface(): void {
        root.forceActiveFocus()
    }

    function handleEscape(): bool {
        if (root.previewCheckin !== null) {
            root.previewCheckin = null
            return true
        }
        if (root.editingExerciseId.length > 0) {
            root.resetExerciseDraft()
            return true
        }
        if (root.confirmDeleteCheckinId.length > 0) {
            root.confirmDeleteCheckinId = ""
            return true
        }
        if (root.showPhotoPathInput) {
            root.showPhotoPathInput = false
            return true
        }
        return false
    }

    Keys.onEscapePressed: event => {
        event.accepted = root.handleEscape()
    }

    component TrackerTextField: TextField {
        id: tf
        selectByMouse: true
        verticalAlignment: TextInput.AlignVCenter
        leftPadding: 12
        rightPadding: 12
        topPadding: 4
        bottomPadding: 4
        color: root.colText
        placeholderTextColor: root.colSubtext
        selectionColor: Qt.alpha(root.colAccentFill, 0.35)
        selectedTextColor: root.colText
        font.family: Appearance.font.family.main
        font.pixelSize: Appearance.font.pixelSize.small
        background: Rectangle {
            radius: Appearance.rounding.full
            color: root.colInputBg
            border.width: tf.activeFocus ? 1.5 : 1
            border.color: tf.activeFocus ? root.colAccent : root.colInputBorder
        }
    }

    component PillButton: RippleButton {
        id: pillBtn
        property string iconName: ""
        property string label: ""
        property bool accentFill: false
        property bool subtleDanger: false
        implicitHeight: 32
        implicitWidth: label.length > 0 ? (pillInnerRow.implicitWidth + 20) : 32
        buttonRadius: 16
        Accessible.name: label.length > 0 ? label : iconName
        colBackground: pillBtn.accentFill
            ? root.colAccentFill
            : pillBtn.toggled
                ? root.colToggledBg
                : root.colCardElevated
        colBackgroundHover: pillBtn.accentFill
            ? Qt.lighter(root.colAccentFill, 1.12)
            : root.colCardHover
        colBackgroundToggled: pillBtn.accentFill
            ? root.colAccentFill
            : root.colToggledBg
        colBackgroundToggledHover: pillBtn.accentFill
            ? Qt.lighter(root.colAccentFill, 1.12)
            : Qt.lighter(root.colToggledBg, 1.10)
        contentItem: Item {
            implicitWidth: pillInnerRow.implicitWidth
            implicitHeight: pillInnerRow.implicitHeight
            Row {
                id: pillInnerRow
                anchors.centerIn: parent
                spacing: 5
                MaterialSymbol {
                    visible: pillBtn.iconName.length > 0
                    anchors.verticalCenter: parent.verticalCenter
                    text: pillBtn.iconName
                    iconSize: 16
                    color: pillBtn.accentFill
                        ? root.colOnAccent
                        : pillBtn.subtleDanger
                            ? root.colErrorText
                            : pillBtn.toggled
                                ? root.colOnToggled
                                : root.colText
                }
                StyledText {
                    visible: pillBtn.label.length > 0
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignHCenter
                    text: pillBtn.label
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: pillBtn.accentFill ? Font.DemiBold : Font.Medium
                    color: pillBtn.accentFill
                        ? root.colOnAccent
                        : pillBtn.subtleDanger
                            ? root.colErrorText
                            : pillBtn.toggled
                                ? root.colOnToggled
                                : root.colText
                }
            }
        }
    }

    FileDialog {
        id: bodyPhotoDialog
        objectName: "exercisesBodyPhotoFileDialog"
        title: Translation.tr("Select progress photo")
        fileMode: FileDialog.OpenFile
        options: FileDialog.ReadOnly | FileDialog.DontResolveSymlinks
        nameFilters: [
            Translation.tr("Images") + " (*.png *.jpg *.jpeg *.webp *.bmp *.avif *.gif)"
        ]
        onAccepted: {
            root.stagedPhotoPath = root.trimFileUrl(String(selectedFile))
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 10

        // ── 1. Top Date, Week Strip, Rest Timer & Cross-Surface Bridges ──
        Rectangle {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            implicitHeight: topHeaderFlow.implicitHeight + 16
            radius: Appearance.rounding.small
            color: root.colCard
            border.width: 0

            ColumnLayout {
                id: topHeaderFlow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 8
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 8

                    Row {
                        spacing: 4
                        Layout.alignment: Qt.AlignVCenter

                        PillButton {
                            objectName: "exercisesPrevDayButton"
                            iconName: "chevron_left"
                            onClicked: root.backend?.stepDate(-1)
                            StyledToolTip { text: Translation.tr("Previous day") }
                        }

                        PillButton {
                            objectName: "exercisesTodayButton"
                            iconName: "today"
                            label: (root.backend?.selectedDate ?? "") === (root.backend?.todayStr ?? "")
                                ? Translation.tr("Today") + " · " + (root.backend?.selectedDate ?? "")
                                : (root.backend?.selectedDate ?? Translation.tr("Today"))
                            toggled: (root.backend?.selectedDate ?? "") === (root.backend?.todayStr ?? "")
                            onClicked: root.backend?.jumpToToday()
                        }

                        PillButton {
                            objectName: "exercisesNextDayButton"
                            iconName: "chevron_right"
                            onClicked: root.backend?.stepDate(1)
                            StyledToolTip { text: Translation.tr("Next day") }
                        }
                    }

                    // 7-day interactive mini strip
                    Row {
                        Layout.alignment: Qt.AlignVCenter
                        visible: root.width >= 940
                        spacing: 4

                        Repeater {
                            model: root.backend?.weekStripDays ?? []
                            delegate: RippleButton {
                                id: dayChip
                                required property var modelData
                                objectName: "exercisesWeekDay_" + modelData.date
                                implicitWidth: 46
                                implicitHeight: 32
                                buttonRadius: 10
                                toggled: modelData.isSelected
                                colBackground: modelData.isSelected
                                    ? root.colAccentFill
                                    : modelData.isToday
                                        ? root.colBannerBg
                                        : root.colCardElevated
                                colBackgroundHover: root.colCardHover
                                colBackgroundToggled: root.colAccentFill
                                colBackgroundToggledHover: Qt.lighter(root.colAccentFill, 1.10)
                                onClicked: root.backend?.selectDate(modelData.date)
                                contentItem: Item {
                                    Row {
                                        anchors.centerIn: parent
                                        spacing: 3
                                        StyledText {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: dayChip.modelData.shortLabel
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            font.weight: dayChip.modelData.isSelected ? Font.Bold : Font.Medium
                                            color: dayChip.modelData.isSelected ? root.colOnAccent : root.colText
                                        }
                                        MaterialSymbol {
                                            visible: dayChip.modelData.allDone
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: "check_circle"
                                            iconSize: 12
                                            color: dayChip.modelData.isSelected ? root.colOnAccent : root.colAccent
                                        }
                                        Rectangle {
                                            visible: dayChip.modelData.hasAny && !dayChip.modelData.allDone
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 5
                                            height: 5
                                            radius: 2.5
                                            color: dayChip.modelData.isSelected ? root.colOnAccent : root.colAccent
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                    }

                    // Rest Timer pill (pauses when tab closes)
                    Rectangle {
                        objectName: "exercisesRestTimerPill"
                        Layout.alignment: Qt.AlignVCenter
                        implicitHeight: 32
                        implicitWidth: restRow.implicitWidth + 14
                        radius: 16
                        color: (root.backend?.restRunning ?? false)
                            ? root.colBannerBg
                            : root.colCardElevated
                        border.width: (root.backend?.restRunning ?? false) ? 1 : 0
                        border.color: (root.backend?.restRunning ?? false) ? root.colAccent : "transparent"

                        Row {
                            id: restRow
                            anchors.centerIn: parent
                            spacing: 5

                            MaterialSymbol {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "timer"
                                iconSize: 16
                                color: root.colAccent
                            }

                            StyledText {
                                objectName: "exercisesRestTimerText"
                                anchors.verticalCenter: parent.verticalCenter
                                text: (root.backend?.restRemainingSec ?? 0) > 0
                                    ? root.formatSecondsClock(root.backend.restRemainingSec)
                                    : Translation.tr("Rest 01:30")
                                font.family: Appearance.font.family.monospace
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                font.weight: Font.DemiBold
                                color: root.colText
                            }

                            RippleButton {
                                objectName: "exercisesRestToggleButton"
                                anchors.verticalCenter: parent.verticalCenter
                                implicitWidth: 22
                                implicitHeight: 22
                                buttonRadius: 11
                                colBackground: "transparent"
                                colBackgroundHover: root.colCardHover
                                onClicked: root.backend?.toggleRestTimer()
                                contentItem: Item {
                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: (root.backend?.restRunning ?? false) ? "pause" : "play_arrow"
                                        iconSize: 15
                                        color: root.colAccent
                                    }
                                }
                            }

                            RippleButton {
                                objectName: "exercisesRestStopButton"
                                visible: (root.backend?.restRemainingSec ?? 0) > 0
                                anchors.verticalCenter: parent.verticalCenter
                                implicitWidth: 22
                                implicitHeight: 22
                                buttonRadius: 11
                                colBackground: "transparent"
                                colBackgroundHover: root.colCardHover
                                onClicked: root.backend?.stopRestTimer()
                                contentItem: Item {
                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "replay"
                                        iconSize: 14
                                        color: root.colSubtext
                                    }
                                }
                            }
                        }
                    }

                    PillButton {
                        objectName: "exercisesOpenPlannerButton"
                        iconName: "calendar_month"
                        label: root.width >= 760 ? Translation.tr("Weekly Planner") : ""
                        onClicked: root.backend?.openInWeeklyPlanner(root.backend.selectedDate)
                        StyledToolTip { text: Translation.tr("Open date in Weekly Planner") }
                    }

                    PillButton {
                        objectName: "exercisesOpenNexusButton"
                        visible: HostServices.AlisIntergration.nexusEnabled
                        iconName: "hub"
                        label: root.width >= 760 ? Translation.tr("Nexus") : ""
                        onClicked: root.backend?.openInNexus()
                        StyledToolTip { text: Translation.tr("Open Alis Nexus") }
                    }

                    PillButton {
                        objectName: "exercisesOpenSettingsButton"
                        iconName: "tune"
                        onClicked: {
                            GlobalStates.dashboardOpen = false
                            GlobalStates.openSettingsSection(38, "exercises_tracker")
                        }
                        StyledToolTip { text: Translation.tr("Exercises Tracker settings") }
                    }
                }

                // Routine template chips + KPI summary bar
                RowLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 8

                    Flow {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        spacing: 5

                        Repeater {
                            model: root.backend?.routineOptions ?? []
                            delegate: RippleButton {
                                id: routineChip
                                required property var modelData
                                objectName: "exercisesRoutine_" + modelData.id
                                implicitHeight: 28
                                implicitWidth: routineChipRow.implicitWidth + 16
                                buttonRadius: 14
                                toggled: root.dayPlan.routine === modelData.id
                                colBackground: toggled ? root.colAccentFill : root.colCardElevated
                                colBackgroundHover: root.colCardHover
                                colBackgroundToggled: root.colAccentFill
                                colBackgroundToggledHover: Qt.lighter(root.colAccentFill, 1.10)
                                onClicked: root.backend?.applyTemplate(modelData.id, false)
                                contentItem: Item {
                                    Row {
                                        id: routineChipRow
                                        anchors.centerIn: parent
                                        spacing: 4
                                        MaterialSymbol {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: routineChip.modelData.icon
                                            iconSize: 14
                                            color: routineChip.toggled ? root.colOnAccent : root.colSubtext
                                        }
                                        StyledText {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: Translation.tr(routineChip.modelData.label)
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            font.weight: routineChip.toggled ? Font.DemiBold : Font.Normal
                                            color: routineChip.toggled ? root.colOnAccent : root.colText
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Row {
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 10

                        StyledText {
                            objectName: "exercisesSummaryStatsText"
                            text: root.dayPlan.completedExercises + "/" + root.dayPlan.totalExercises + " " + Translation.tr("done")
                                + " · " + root.dayPlan.volumeKg + " kg"
                                + " · " + root.summary.currentStreakDays + "d " + Translation.tr("streak")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.weight: Font.Medium
                            color: root.colSubtext
                        }
                    }
                }

                // Status / error feedback banner
                RowLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    visible: (root.backend?.errorMessage?.length ?? 0) > 0 || (root.backend?.statusMessage?.length ?? 0) > 0
                    spacing: 6

                    MaterialSymbol {
                        text: (root.backend?.errorMessage?.length ?? 0) > 0 ? "error" : "check_circle"
                        iconSize: 15
                        color: (root.backend?.errorMessage?.length ?? 0) > 0 ? root.colErrorText : root.colAccent
                    }

                    StyledText {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        elide: Text.ElideRight
                        text: (root.backend?.errorMessage?.length ?? 0) > 0
                            ? root.backend.errorMessage
                            : (root.backend?.statusMessage ?? "")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: (root.backend?.errorMessage?.length ?? 0) > 0 ? root.colErrorText : root.colSubtext
                    }
                }
            }
        }

        // ── 2. Main Split Workspace: Left = Daily Exercises Checklist, Right = Body Tracker ──
        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumWidth: 0
            columns: root.width >= 880 ? 2 : 1
            columnSpacing: 10
            rowSpacing: 10

            // ══════ LEFT COLUMN: TODAY'S WORKOUT & CHECKLIST ══════
            Rectangle {
                objectName: "exercisesWorkoutCard"
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumWidth: 0
                Layout.preferredWidth: root.width >= 880 ? Math.round(root.width * 0.54) : root.width
                radius: Appearance.rounding.small
                color: root.colCard
                border.width: 0
                clip: true

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 10

                    // Workout Title + Progress Bar + Schedule Slot
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        spacing: 8

                        MaterialSymbol {
                            text: "fitness_center"
                            iconSize: 20
                            color: root.colAccent
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            spacing: 2

                            StyledText {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                text: root.dayPlan.title
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.Bold
                                color: root.colText
                                elide: Text.ElideRight
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                height: 5
                                radius: 2.5
                                color: root.colTrackBg

                                Rectangle {
                                    width: parent.width * Math.max(0, Math.min(1, root.dayPlan.completionPct / 100))
                                    height: parent.height
                                    radius: parent.radius
                                    color: root.colAccent
                                    Behavior on width {
                                        enabled: Appearance.animationsEnabled
                                        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                                    }
                                }
                            }
                        }

                        PillButton {
                            objectName: "exercisesSyncPlannerButton"
                            iconName: root.dayPlan.plannerEventId > 0 ? "event_available" : "event_upcoming"
                            label: root.dayPlan.plannerEventId > 0
                                ? Translation.tr("Update Planner")
                                : Translation.tr("Sync Planner")
                            onClicked: root.backend?.syncDayToWeeklyPlanner(root.backend.selectedDate)
                            StyledToolTip { text: Translation.tr("Push workout block to Weekly Planner") }
                        }

                        PillButton {
                            objectName: "exercisesExportNexusButton"
                            enabled: !(root.backend?.workoutExportPending ?? false)
                            visible: HostServices.AlisIntergration.nexusEnabled && (HostServices.AlisIntergration.nexus?.vaultConfigured ?? false)
                            iconName: "note_add"
                            label: Translation.tr("Log to Nexus")
                            onClicked: root.backend?.sendWorkoutLogToNexus(root.backend.selectedDate)
                            StyledToolTip { text: Translation.tr("Save workout summary note to Alis Nexus") }
                        }
                    }

                    // Planned in Weekly Planner Banner (Two-way Planner -> Exercises Tracker)
                    Rectangle {
                        objectName: "exercisesPlannerSyncBanner"
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        visible: (root.backend?.plannerWorkouts?.length ?? 0) > 0
                        implicitHeight: plannerBannerCol.implicitHeight + 14
                        radius: Appearance.rounding.small
                        color: root.colBannerBg
                        border.width: 0

                        ColumnLayout {
                            id: plannerBannerCol
                            anchors.fill: parent
                            anchors.margins: 7
                            spacing: 4

                            Repeater {
                                model: root.backend?.plannerWorkouts ?? []
                                delegate: RowLayout {
                                    id: pwRow
                                    required property var modelData
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    spacing: 8

                                    MaterialSymbol {
                                        text: "event_note"
                                        iconSize: 16
                                        color: root.colAccent
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        elide: Text.ElideRight
                                        text: pwRow.modelData.title
                                            + (pwRow.modelData.allDay ? "" : (" · " + pwRow.modelData.startHm + "–" + pwRow.modelData.endHm))
                                            + " (" + pwRow.modelData.exercises.length + " " + Translation.tr("exercises") + ")"
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: root.colText
                                    }

                                    PillButton {
                                        objectName: "exercisesImportPlannerButton"
                                        iconName: "download_done"
                                        label: Translation.tr("Import")
                                        implicitHeight: 26
                                        onClicked: root.backend?.importPlannerWorkout(pwRow.modelData)
                                    }
                                }
                            }
                        }
                    }

                    // Quick Add / Edit Exercise Composer
                    Rectangle {
                        objectName: "exercisesComposerCard"
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        implicitHeight: composerCol.implicitHeight + 16
                        radius: Appearance.rounding.small
                        color: root.colCardElevated
                        border.width: 0

                        ColumnLayout {
                            id: composerCol
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 6

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                spacing: 6

                                TrackerTextField {
                                    id: exerciseNameField
                                    objectName: "exerciseNameField"
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    Layout.preferredHeight: 34
                                    placeholderText: Translation.tr("Exercise name (e.g. Bench Press)")
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    onAccepted: root.submitExerciseDraft()
                                }

                                TrackerTextField {
                                    id: setsSpinField
                                    objectName: "exerciseSetsField"
                                    Layout.preferredWidth: 52
                                    Layout.preferredHeight: 34
                                    placeholderText: Translation.tr("Sets")
                                    text: String(root.draftSets)
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    onAccepted: root.submitExerciseDraft()
                                }

                                StyledText {
                                    text: "×"
                                    color: root.colSubtext
                                    font.pixelSize: Appearance.font.pixelSize.small
                                }

                                TrackerTextField {
                                    id: repsTextField
                                    objectName: "exerciseRepsField"
                                    Layout.preferredWidth: 58
                                    Layout.preferredHeight: 34
                                    placeholderText: Translation.tr("Reps")
                                    text: root.draftReps
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    onAccepted: root.submitExerciseDraft()
                                }

                                TrackerTextField {
                                    id: weightTextField
                                    objectName: "exerciseWeightField"
                                    Layout.preferredWidth: 66
                                    Layout.preferredHeight: 34
                                    placeholderText: root.preferredWeightUnit
                                    text: root.draftWeight
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    onAccepted: root.submitExerciseDraft()
                                }

                                TrackerTextField {
                                    id: restTextField
                                    objectName: "exerciseRestField"
                                    visible: root.width >= 720
                                    Layout.preferredWidth: 58
                                    Layout.preferredHeight: 34
                                    placeholderText: "90s"
                                    text: String(root.draftRestSec)
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    onAccepted: root.submitExerciseDraft()
                                }

                                PillButton {
                                    objectName: "exerciseSubmitButton"
                                    accentFill: true
                                    iconName: root.editingExerciseId.length > 0 ? "check" : "add"
                                    label: root.editingExerciseId.length > 0 ? Translation.tr("Save") : Translation.tr("Add")
                                    onClicked: root.submitExerciseDraft()
                                }

                                PillButton {
                                    visible: root.editingExerciseId.length > 0
                                    iconName: "close"
                                    onClicked: root.resetExerciseDraft()
                                }
                            }

                            Flow {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                spacing: 4

                                Repeater {
                                    model: root.backend?.categories ?? []
                                    delegate: RippleButton {
                                        id: catBtn
                                        required property var modelData
                                        objectName: "exerciseCategory_" + modelData.id
                                        implicitHeight: 24
                                        implicitWidth: catBtnText.implicitWidth + 14
                                        buttonRadius: 12
                                        toggled: root.draftCategory === modelData.id
                                        colBackground: toggled ? root.colBannerBg : root.colCardElevated
                                        colBackgroundHover: root.colCardHover
                                        colBackgroundToggled: root.colBannerBg
                                        colBackgroundToggledHover: Qt.lighter(root.colBannerBg, 1.12)
                                        onClicked: root.draftCategory = modelData.id
                                        contentItem: Item {
                                            StyledText {
                                                id: catBtnText
                                                anchors.centerIn: parent
                                                horizontalAlignment: Text.AlignHCenter
                                                text: Translation.tr(catBtn.modelData.label)
                                                font.pixelSize: Appearance.font.pixelSize.smallest
                                                font.weight: catBtn.toggled ? Font.DemiBold : Font.Normal
                                                color: catBtn.toggled ? root.colOnBanner : root.colSubtext
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Exercise Checklist ListView
                    ListView {
                        id: checklistView
                        objectName: "exercisesChecklistView"
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.minimumHeight: 140
                        clip: true
                        spacing: 6
                        boundsBehavior: Flickable.StopAtBounds
                        model: root.dayPlan.exercises ?? []

                        ColumnLayout {
                            anchors.centerIn: parent
                            width: Math.min(300, checklistView.width - 24)
                            visible: checklistView.count === 0
                            spacing: 8

                            MaterialSymbol {
                                Layout.alignment: Qt.AlignHCenter
                                text: "exercise"
                                iconSize: 30
                                color: root.colSubtext
                            }

                            StyledText {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                                text: Translation.tr("No exercises scheduled for this day.")
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: root.colSubtext
                            }

                            PillButton {
                                objectName: "exercisesSeedRoutineButton"
                                Layout.alignment: Qt.AlignHCenter
                                accentFill: true
                                iconName: "bolt"
                                label: Translation.tr("Load Routine Template")
                                onClicked: root.backend?.applyTemplate(root.dayPlan.routine, true)
                            }
                        }

                        delegate: Rectangle {
                            id: exRow
                            required property var modelData
                            required property int index
                            objectName: "exerciseItem_" + modelData.id
                            width: checklistView.width
                            implicitHeight: Math.max(50, exInnerRow.implicitHeight + 14)
                            radius: Appearance.rounding.small
                            color: modelData.completed
                                ? root.colCompletedRowBg
                                : root.colCardElevated
                            border.width: 0

                            RowLayout {
                                id: exInnerRow
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 8
                                spacing: 8

                                RippleButton {
                                    objectName: "exerciseCheck_" + exRow.modelData.id
                                    implicitWidth: 28
                                    implicitHeight: 28
                                    buttonRadius: 14
                                    colBackground: exRow.modelData.completed ? root.colAccentFill : "transparent"
                                    colBackgroundHover: root.colCardHover
                                    onClicked: root.backend?.toggleExercise(exRow.modelData.id)
                                    contentItem: Item {
                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: exRow.modelData.completed ? "check" : "radio_button_unchecked"
                                            iconSize: 17
                                            color: exRow.modelData.completed ? root.colOnAccent : root.colSubtext
                                        }
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    spacing: 1

                                    StyledText {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        text: exRow.modelData.name
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        font.weight: Font.DemiBold
                                        font.strikeout: exRow.modelData.completed
                                        color: exRow.modelData.completed ? root.colSubtext : root.colText
                                        elide: Text.ElideRight
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        text: String(exRow.modelData.category).toUpperCase()
                                            + " · " + (root.backend?.formatExerciseTarget(exRow.modelData) ?? "")
                                            + " · " + Translation.tr("Rest") + " " + exRow.modelData.restSec + "s"
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: root.colSubtext
                                        elide: Text.ElideRight
                                    }
                                }

                                // Set progress pill (- 2/4 +)
                                Rectangle {
                                    implicitHeight: 26
                                    implicitWidth: setStepRow.implicitWidth + 10
                                    radius: 13
                                    color: root.colInputBg
                                    border.width: 0

                                    Row {
                                        id: setStepRow
                                        anchors.centerIn: parent
                                        spacing: 3

                                        RippleButton {
                                            implicitWidth: 20
                                            implicitHeight: 20
                                            buttonRadius: 10
                                            colBackground: "transparent"
                                            colBackgroundHover: root.colCardHover
                                            onClicked: root.backend?.stepExerciseSets(exRow.modelData.id, -1)
                                            contentItem: Item {
                                                MaterialSymbol {
                                                    anchors.centerIn: parent
                                                    text: "remove"
                                                    iconSize: 13
                                                    color: root.colSubtext
                                                }
                                            }
                                        }

                                        StyledText {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: exRow.modelData.completedSets + "/" + exRow.modelData.sets
                                            font.family: Appearance.font.family.monospace
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            color: root.colText
                                        }

                                        RippleButton {
                                            objectName: "exerciseStepSetPlus_" + exRow.modelData.id
                                            implicitWidth: 20
                                            implicitHeight: 20
                                            buttonRadius: 10
                                            colBackground: "transparent"
                                            colBackgroundHover: root.colCardHover
                                            onClicked: root.backend?.stepExerciseSets(exRow.modelData.id, 1)
                                            contentItem: Item {
                                                MaterialSymbol {
                                                    anchors.centerIn: parent
                                                    text: "add"
                                                    iconSize: 13
                                                    color: root.colAccent
                                                }
                                            }
                                        }
                                    }
                                }

                                RippleButton {
                                    objectName: "exerciseStartRest_" + exRow.modelData.id
                                    implicitWidth: 28
                                    implicitHeight: 28
                                    buttonRadius: 14
                                    colBackground: "transparent"
                                    colBackgroundHover: root.colCardHover
                                    onClicked: root.backend?.startRestTimer(exRow.modelData.restSec, exRow.modelData.name)
                                    contentItem: Item {
                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: "timer"
                                            iconSize: 16
                                            color: root.colAccent
                                        }
                                    }
                                    StyledToolTip { text: Translation.tr("Start rest timer") }
                                }

                                RippleButton {
                                    objectName: "exerciseEdit_" + exRow.modelData.id
                                    implicitWidth: 28
                                    implicitHeight: 28
                                    buttonRadius: 14
                                    colBackground: "transparent"
                                    colBackgroundHover: root.colCardHover
                                    onClicked: root.beginEditExercise(exRow.modelData)
                                    contentItem: Item {
                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: "edit"
                                            iconSize: 15
                                            color: root.colSubtext
                                        }
                                    }
                                }

                                RippleButton {
                                    objectName: "exerciseDelete_" + exRow.modelData.id
                                    implicitWidth: 28
                                    implicitHeight: 28
                                    buttonRadius: 14
                                    colBackground: "transparent"
                                    colBackgroundHover: root.colCardHover
                                    onClicked: root.backend?.removeExercise(exRow.modelData.id)
                                    contentItem: Item {
                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: "delete_outline"
                                            iconSize: 16
                                            color: root.colSubtext
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Schedule Slot & Session Note Footer
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        spacing: 6

                        MaterialSymbol {
                            text: "schedule"
                            iconSize: 16
                            color: root.colSubtext
                        }

                        TrackerTextField {
                            id: scheduleStartField
                            objectName: "exercisesScheduleStartField"
                            Layout.preferredWidth: 66
                            Layout.preferredHeight: 30
                            text: root.dayPlan.scheduledStart
                            placeholderText: "18:00"
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            onEditingFinished: root.backend?.setDayMetadata({ scheduledStart: text })
                        }

                        StyledText {
                            text: "–"
                            color: root.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.smallest
                        }

                        TrackerTextField {
                            id: scheduleEndField
                            objectName: "exercisesScheduleEndField"
                            Layout.preferredWidth: 66
                            Layout.preferredHeight: 30
                            text: root.dayPlan.scheduledEnd
                            placeholderText: "19:00"
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            onEditingFinished: root.backend?.setDayMetadata({ scheduledEnd: text })
                        }

                        TrackerTextField {
                            id: sessionNoteField
                            objectName: "exercisesSessionNoteField"
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            Layout.preferredHeight: 30
                            text: root.dayPlan.sessionNote
                            placeholderText: Translation.tr("Session note (RPE, PRs, energy)…")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            onEditingFinished: root.backend?.setDayMetadata({ sessionNote: text })
                        }
                    }
                }
            }

            // ══════ RIGHT COLUMN: POST-WORKOUT BODY TRACKER ══════
            Rectangle {
                objectName: "exercisesBodyTrackerCard"
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumWidth: 0
                Layout.preferredWidth: root.width >= 880 ? Math.round(root.width * 0.46) : root.width
                radius: Appearance.rounding.small
                color: root.colCard
                border.width: 0
                clip: true

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 10

                    // Body Tracker Header & Mode Switcher
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        spacing: 8

                        MaterialSymbol {
                            text: "photo_camera"
                            iconSize: 20
                            color: root.colAccent
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            spacing: 0

                            StyledText {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                text: Translation.tr("Body Tracker")
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.Bold
                                color: root.colText
                                elide: Text.ElideRight
                            }

                            StyledText {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                text: root.summary.latestWeightKg > 0
                                    ? (Translation.tr("Latest:") + " " + root.summary.latestWeightKg + " kg"
                                        + (root.summary.latestBodyFatPct > 0 ? (" · " + root.summary.latestBodyFatPct + "% BF") : ""))
                                    : Translation.tr("Post-workout photo & body check-ins")
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: root.colSubtext
                                elide: Text.ElideRight
                            }
                        }

                        PillButton {
                            objectName: "bodyViewTimelineButton"
                            iconName: "view_agenda"
                            label: Translation.tr("Timeline")
                            toggled: root.bodyGalleryMode === "timeline"
                            onClicked: root.bodyGalleryMode = "timeline"
                        }

                        PillButton {
                            objectName: "bodyViewCompareButton"
                            iconName: "compare"
                            label: Translation.tr("Compare")
                            toggled: root.bodyGalleryMode === "compare"
                            onClicked: root.bodyGalleryMode = "compare"
                        }
                    }

                    // Post-Workout Check-in Uploader Card
                    Rectangle {
                        objectName: "bodyTrackerComposerCard"
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        implicitHeight: bodyComposerCol.implicitHeight + 16
                        radius: Appearance.rounding.small
                        color: root.colCardElevated
                        border.width: 0

                        ColumnLayout {
                            id: bodyComposerCol
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 6

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                spacing: 6

                                PillButton {
                                    objectName: "bodyAttachPhotoButton"
                                    iconName: "add_a_photo"
                                    label: root.stagedPhotoPath.length > 0
                                        ? Translation.tr("Change Photo")
                                        : Translation.tr("Upload Photo")
                                    onClicked: bodyPhotoDialog.open()
                                }

                                PillButton {
                                    objectName: "bodyTogglePathInputButton"
                                    iconName: "folder_open"
                                    toggled: root.showPhotoPathInput
                                    onClicked: root.showPhotoPathInput = !root.showPhotoPathInput
                                    StyledToolTip { text: Translation.tr("Paste image file path") }
                                }

                                PillButton {
                                    visible: root.stagedPhotoPath.length > 0
                                    iconName: "close"
                                    onClicked: root.stagedPhotoPath = ""
                                }

                                Item {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                }

                                PillButton {
                                    objectName: "bodySaveCheckinButton"
                                    accentFill: true
                                    enabled: !(root.backend?.photoImportBusy ?? false)
                                    iconName: "check"
                                    label: (root.backend?.photoImportBusy ?? false)
                                        ? Translation.tr("Saving…")
                                        : Translation.tr("Save Check-in")
                                    onClicked: root.submitBodyCheckin()
                                }
                            }

                            TrackerTextField {
                                id: bodyPhotoPathField
                                objectName: "bodyPhotoPathField"
                                visible: root.showPhotoPathInput
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                Layout.preferredHeight: 32
                                placeholderText: Translation.tr("/path/to/post-workout-photo.jpg")
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                onAccepted: root.submitBodyCheckin()
                            }

                            // Staged photo bounded preview
                            RowLayout {
                                visible: root.stagedPhotoPath.length > 0
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                spacing: 8

                                Rectangle {
                                    Layout.preferredWidth: 52
                                    Layout.preferredHeight: 52
                                    radius: 8
                                    color: root.colCard
                                    clip: true

                                    Image {
                                        objectName: "bodyStagedPhotoPreview"
                                        anchors.fill: parent
                                        asynchronous: true
                                        cache: false
                                        sourceSize: Qt.size(200, 200)
                                        fillMode: Image.PreserveAspectCrop
                                        source: root.stagedPhotoPath.length > 0 ? ("file://" + root.stagedPhotoPath) : ""
                                    }
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    elide: Text.ElideMiddle
                                    text: root.stagedPhotoPath
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: root.colSubtext
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                spacing: 6

                                TrackerTextField {
                                    id: bodyWeightField
                                    objectName: "bodyWeightField"
                                    visible: root.showBodyMetricsInputs
                                    Layout.preferredWidth: 86
                                    Layout.preferredHeight: 32
                                    placeholderText: Translation.tr("Weight") + " " + root.preferredWeightUnit
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    onAccepted: root.submitBodyCheckin()
                                }

                                TrackerTextField {
                                    id: bodyFatField
                                    objectName: "bodyFatField"
                                    visible: root.showBodyMetricsInputs
                                    Layout.preferredWidth: 82
                                    Layout.preferredHeight: 32
                                    placeholderText: Translation.tr("Body fat %")
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    onAccepted: root.submitBodyCheckin()
                                }

                                TrackerTextField {
                                    id: bodyNoteField
                                    objectName: "bodyNoteField"
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    Layout.preferredHeight: 32
                                    placeholderText: Translation.tr("Post-workout note…")
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    onAccepted: root.submitBodyCheckin()
                                }
                            }
                        }
                    }

                    // Mode A: Timeline Gallery
                    ListView {
                        id: checkinsListView
                        objectName: "bodyCheckinsListView"
                        visible: root.bodyGalleryMode === "timeline"
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.minimumHeight: 140
                        clip: true
                        spacing: 8
                        boundsBehavior: Flickable.StopAtBounds
                        model: root.checkins

                        ColumnLayout {
                            anchors.centerIn: parent
                            width: Math.min(280, checkinsListView.width - 24)
                            visible: checkinsListView.count === 0
                            spacing: 6

                            MaterialSymbol {
                                Layout.alignment: Qt.AlignHCenter
                                text: "portrait"
                                iconSize: 30
                                color: root.colSubtext
                            }

                            StyledText {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                                text: Translation.tr("Upload a post-workout photo or log body weight to track progress.")
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: root.colSubtext
                            }
                        }

                        delegate: Rectangle {
                            id: bcCard
                            required property var modelData
                            objectName: "bodyCheckinCard_" + modelData.id
                            width: checkinsListView.width
                            implicitHeight: Math.max(76, bcRow.implicitHeight + 16)
                            radius: Appearance.rounding.small
                            color: root.colCardElevated
                            border.width: 0

                            RowLayout {
                                id: bcRow
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 10

                                Rectangle {
                                    visible: bcCard.modelData.hasPhoto
                                    Layout.preferredWidth: 64
                                    Layout.preferredHeight: 64
                                    radius: 8
                                    color: root.colInputBg
                                    border.width: 0
                                    clip: true

                                    Image {
                                        objectName: "bodyCheckinThumbnail_" + bcCard.modelData.id
                                        anchors.fill: parent
                                        asynchronous: true
                                        cache: false
                                        sourceSize: Qt.size(280, 280)
                                        fillMode: Image.PreserveAspectCrop
                                        source: bcCard.modelData.photoUrl
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.previewCheckin = bcCard.modelData
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    spacing: 2

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        spacing: 6

                                        StyledText {
                                            text: bcCard.modelData.date
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            font.weight: Font.DemiBold
                                            color: root.colText
                                        }

                                        StyledText {
                                            visible: bcCard.modelData.weightKg > 0
                                            text: bcCard.modelData.weightKg + " kg"
                                                + (bcCard.modelData.hasWeightDelta
                                                    ? (" (" + (bcCard.modelData.weightDeltaKg > 0 ? "+" : "") + bcCard.modelData.weightDeltaKg + " kg)")
                                                    : "")
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            font.weight: Font.Medium
                                            color: root.colAccent
                                        }

                                        StyledText {
                                            visible: bcCard.modelData.bodyFatPct > 0
                                            text: bcCard.modelData.bodyFatPct + "% BF"
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            color: root.colSubtext
                                        }
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        visible: String(bcCard.modelData.note ?? "").length > 0
                                        text: bcCard.modelData.note
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: root.colSubtext
                                        wrapMode: Text.WordWrap
                                        maximumLineCount: 2
                                        elide: Text.ElideRight
                                    }
                                }

                                PillButton {
                                    objectName: "bodyDeleteCheckin_" + bcCard.modelData.id
                                    subtleDanger: root.confirmDeleteCheckinId === bcCard.modelData.id
                                    iconName: "delete_outline"
                                    label: root.confirmDeleteCheckinId === bcCard.modelData.id
                                        ? Translation.tr("Confirm")
                                        : ""
                                    implicitHeight: 28
                                    onClicked: {
                                        if (root.confirmDeleteCheckinId === bcCard.modelData.id) {
                                            root.confirmDeleteCheckinId = ""
                                            root.backend?.deleteBodyCheckin(bcCard.modelData.id)
                                        } else {
                                            root.confirmDeleteCheckinId = bcCard.modelData.id
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Mode B: Before / After Side-by-Side Comparison
                    Item {
                        objectName: "bodyBeforeAfterPanel"
                        visible: root.bodyGalleryMode === "compare"
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.minimumHeight: 140

                        StyledText {
                            anchors.centerIn: parent
                            visible: root.checkins.length === 0
                            text: Translation.tr("Add at least two check-ins to compare progress.")
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: root.colSubtext
                        }

                        RowLayout {
                            anchors.fill: parent
                            visible: root.checkins.length > 0
                            spacing: 8

                            Repeater {
                                model: root.checkins.length > 0
                                    ? [
                                        { tag: Translation.tr("Baseline"), data: root.baselineCheckin },
                                        { tag: Translation.tr("Latest"), data: root.latestCheckin }
                                    ]
                                    : []
                                delegate: Rectangle {
                                    id: cmpCard
                                    required property var modelData
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    Layout.minimumWidth: 0
                                    radius: Appearance.rounding.small
                                    color: root.colCardElevated
                                    border.width: 0
                                    clip: true

                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: 8
                                        spacing: 6

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: cmpCard.modelData.tag + " · " + (cmpCard.modelData.data?.date ?? "")
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                            font.weight: Font.DemiBold
                                            color: root.colText
                                            elide: Text.ElideRight
                                        }

                                        Rectangle {
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            radius: 8
                                            color: root.colCard
                                            clip: true

                                            Image {
                                                anchors.fill: parent
                                                visible: Boolean(cmpCard.modelData.data?.hasPhoto)
                                                asynchronous: true
                                                cache: false
                                                sourceSize: Qt.size(480, 480)
                                                fillMode: Image.PreserveAspectCrop
                                                source: cmpCard.modelData.data?.photoUrl ?? ""
                                            }

                                            MaterialSymbol {
                                                anchors.centerIn: parent
                                                visible: !cmpCard.modelData.data?.hasPhoto
                                                text: "hide_image"
                                                iconSize: 28
                                                color: root.colSubtext
                                            }
                                        }

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: ((cmpCard.modelData.data?.weightKg ?? 0) > 0 ? (cmpCard.modelData.data.weightKg + " kg") : "—")
                                                + ((cmpCard.modelData.data?.bodyFatPct ?? 0) > 0 ? (" · " + cmpCard.modelData.data.bodyFatPct + "% BF") : "")
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            color: root.colAccent
                                            elide: Text.ElideRight
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Lightbox Modal for Inspecting Body Tracker Photos ──
    Rectangle {
        objectName: "bodyPhotoPreviewModal"
        anchors.fill: parent
        z: 250
        visible: root.previewCheckin !== null
        color: Qt.rgba(0, 0, 0, 0.72)

        MouseArea {
            anchors.fill: parent
            onClicked: root.previewCheckin = null
        }

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width - 40, 560)
            height: Math.min(parent.height - 40, 620)
            radius: Appearance.rounding.large
            color: root.colCard
            border.width: 1
            border.color: root.colBorder
            clip: true

            MouseArea {
                anchors.fill: parent
                onClicked: {}
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0

                    StyledText {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: (root.previewCheckin?.date ?? "")
                            + ((root.previewCheckin?.weightKg ?? 0) > 0 ? (" · " + root.previewCheckin.weightKg + " kg") : "")
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.Bold
                        color: root.colText
                        elide: Text.ElideRight
                    }

                    PillButton {
                        iconName: "close"
                        onClicked: root.previewCheckin = null
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Appearance.rounding.normal
                    color: "#0A0E14"
                    clip: true

                    Image {
                        anchors.fill: parent
                        asynchronous: true
                        cache: false
                        sourceSize: Qt.size(960, 960)
                        fillMode: Image.PreserveAspectFit
                        source: root.previewCheckin?.photoUrl ?? ""
                    }
                }

                StyledText {
                    visible: String(root.previewCheckin?.note ?? "").length > 0
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: root.previewCheckin?.note ?? ""
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: root.colSubtext
                }
            }
        }
    }
}
