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
import "ExerciseAnatomyData.js" as ExerciseAnatomyData

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

    // Stepped flat tonal layers anchored on Home Dashboard card color (DashCard / colLayer1Base)
    // with gentle ~2.2% HSL steps for nested layers (Layer 1 -> Layer 2 -> Layer 3 -> Hover).
    readonly property color colSurfaceBase: ColorUtils.applyAlpha(
        Qt.color(Appearance.colors.colLayer1Base).valid
            ? Appearance.colors.colLayer1Base
            : Appearance.colors.colLayer0Base,
        1.0
    )
    readonly property bool isDarkSurface: ColorUtils.relativeLuminance(root.colSurfaceBase) < 0.35
    // Lighten nested layers when headroom exists; subtly step deeper on near-white canvases
    readonly property real tonalDir: Qt.color(root.colSurfaceBase).hslLightness > 0.86 ? -1 : 1

    readonly property color colCard: abyss
        ? ColorUtils.applyAlpha(root.colSurfaceBase, Math.max(0.88, AbyssStyle.cardOpacity))
        : Appearance.angelEverywhere ? Appearance.angel.colGlassCard
        : alisEverywhere ? Appearance.alis.colLayer1
        : auroraEverywhere ? Appearance.aurora.colSubSurface
        : Appearance.colors.colLayer1
    readonly property color colCardElevated: {
        const tonal = ColorUtils.tonalStep(
            root.colSurfaceBase,
            root.tonalDir * 0.022,
            1.04
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
            root.tonalDir * (root.tonalDir > 0 ? 0.068 : 0.055),
            1.09
        ),
        0.96
    )
    readonly property color colInputBorder: ColorUtils.applyAlpha(
        ColorUtils.tonalStep(root.colSurfaceBase, root.tonalDir * 0.22, 1.12),
        root.isDarkSurface ? 0.42 : 0.38
    )
    readonly property color colCardHover: ColorUtils.applyAlpha(
        ColorUtils.tonalStep(
            root.colSurfaceBase,
            root.tonalDir * (root.tonalDir > 0 ? 0.084 : 0.075),
            1.10
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
        ColorUtils.tonalStep(root.colSurfaceBase, root.tonalDir * 0.22, 1.10),
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
        ColorUtils.tonalStep(root.colSurfaceBase, root.tonalDir * 0.044, 1.07),
        1.0
    )
    readonly property color colBannerBg: ColorUtils.mix(root.colCardElevated, root.colAccentFill, 0.82)
    readonly property color colOnBanner: ColorUtils.ensureReadable(root.colAccent, root.colBannerBg, 5.0)
    readonly property color colCompletedRowBg: ColorUtils.mix(root.colCardElevated, root.colAccentFill, 0.86)
    readonly property color colSecondaryMuscle: ColorUtils.adaptAccent(
        Qt.color(Appearance.colors.colSecondary).valid ? Appearance.colors.colSecondary : root.colSubtext,
        root.colCardElevated,
        4.5
    )

    readonly property string preferredWeightUnit: root.backend?.preferences?.weightUnit ?? "kg"
    readonly property bool showBodyMetricsInputs: root.backend?.preferences?.showBodyMetrics ?? true

    // Composer & UI state
    property string editingExerciseId: ""
    property string draftNameQuery: ""
    property string draftNexusRelPath: ""
    property var draftNexusMeta: null
    property bool exerciseSearchOpen: false
    property bool searchDropdownHovered: false
    property int exerciseSearchIndex: -1
    property string draftCategory: "chest"
    property int draftSets: root.backend?.preferences?.defaultSets ?? 3
    property string draftReps: "10"
    property string draftWeight: ""
    property string draftDurationMin: ""
    property int draftRestSec: root.backend?.preferences?.defaultRestSeconds ?? 90

    // Inspected exercise detail state (replaces right-hand Body Tracker temporarily)
    property string inspectedExerciseId: ""
    property bool detailDemoPlaying: true

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

    readonly property var exerciseSearchResults: {
        void root.backend?.revision
        void root.backend?.nexusExercises
        if (!root.exerciseSearchOpen || !root.backend || typeof root.backend.searchExercises !== "function")
            return []
        return root.backend.searchExercises(root.draftNameQuery)
    }

    readonly property var inspectedExercise: {
        if (!root.inspectedExerciseId.length)
            return null
        const list = root.dayPlan?.exercises ?? []
        for (let i = 0; i < list.length; i++) {
            if (String(list[i]?.id ?? "") === root.inspectedExerciseId)
                return list[i]
        }
        return null
    }

    readonly property var inspectedDetail: {
        void root.backend?._detailRevision
        void root.backend?.nexusExercises
        if (!root.inspectedExercise || !root.backend || typeof root.backend.resolveExerciseMetadata !== "function")
            return null
        return root.backend.resolveExerciseMetadata(root.inspectedExercise)
    }

    onDayPlanChanged: {
        if (root.inspectedExerciseId.length > 0) {
            const exists = (root.dayPlan?.exercises ?? []).some(ex => String(ex?.id ?? "") === root.inspectedExerciseId)
            if (!exists)
                root.inspectedExerciseId = ""
        }
    }

    function inspectExercise(ex): void {
        if (!ex)
            return
        searchCloseTimer.stop()
        root.exerciseSearchOpen = false
        root.inspectedExerciseId = String(ex.id ?? "")
        root.detailDemoPlaying = true
        if (root.backend && typeof root.backend.loadExerciseDetail === "function")
            root.backend.loadExerciseDetail(ex)
    }

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
        searchCloseTimer.stop()
        root.editingExerciseId = ""
        root.draftNameQuery = ""
        root.draftNexusRelPath = ""
        root.draftNexusMeta = null
        root.exerciseSearchOpen = false
        root.exerciseSearchIndex = -1
        exerciseNameField.text = ""
        root.draftCategory = "chest"
        root.draftSets = root.backend?.preferences?.defaultSets ?? 3
        root.draftReps = "10"
        root.draftWeight = ""
        root.draftDurationMin = ""
        root.draftRestSec = root.backend?.preferences?.defaultRestSeconds ?? 90
        setsSpinField.text = String(root.draftSets)
        repsTextField.text = root.draftReps
        weightTextField.text = ""
        restTextField.text = String(root.draftRestSec)
    }

    function selectSearchExercise(item): void {
        if (!item)
            return
        searchCloseTimer.stop()
        const title = String(item.title || "")
        exerciseNameField.text = title
        root.draftNameQuery = title
        root.draftCategory = String(item.category || root.draftCategory || "chest")
        root.draftNexusRelPath = String(item.relPath || "")
        root.draftNexusMeta = item
        if (Number(item.sets) > 0)
            root.draftSets = Number(item.sets)
        if (String(item.reps || "").length > 0)
            root.draftReps = String(item.reps)
        if (Number(item.weight) > 0)
            root.draftWeight = String(item.weight)
        if (Number(item.durationSec) > 0)
            root.draftDurationMin = String(Math.round(Number(item.durationSec) / 60))
        if (Number(item.restSec) > 0)
            root.draftRestSec = Number(item.restSec)
        setsSpinField.text = String(root.draftSets)
        repsTextField.text = root.draftReps
        weightTextField.text = root.draftWeight
        restTextField.text = String(root.draftRestSec)
        root.exerciseSearchOpen = false
        root.exerciseSearchIndex = -1
    }

    function beginEditExercise(ex): void {
        if (!ex)
            return
        searchCloseTimer.stop()
        root.editingExerciseId = String(ex.id ?? "")
        exerciseNameField.text = String(ex.name ?? "")
        root.draftNameQuery = exerciseNameField.text
        root.draftNexusRelPath = String(ex.nexusRelPath ?? "")
        root.draftNexusMeta = null
        root.exerciseSearchOpen = false
        root.exerciseSearchIndex = -1
        root.draftCategory = String(ex.category ?? "chest")
        root.draftSets = Number(ex.sets) || 3
        root.draftReps = String(ex.reps ?? "10")
        root.draftWeight = Number(ex.weight) > 0 ? String(ex.weight) : ""
        root.draftDurationMin = Number(ex.durationSec) > 0 ? String(Math.round(Number(ex.durationSec) / 60)) : ""
        root.draftRestSec = Number(ex.restSec) || 90
        setsSpinField.text = String(root.draftSets)
        repsTextField.text = root.draftReps
        weightTextField.text = root.draftWeight
        restTextField.text = String(root.draftRestSec)
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
        if (root.draftNexusRelPath.length > 0)
            payload.nexusRelPath = root.draftNexusRelPath
        if (root.draftNexusMeta) {
            if (root.draftNexusMeta.equipment)
                payload.equipment = String(root.draftNexusMeta.equipment)
            if (root.draftNexusMeta.level)
                payload.level = String(root.draftNexusMeta.level)
            if (root.draftNexusMeta.force)
                payload.force = String(root.draftNexusMeta.force)
            if (root.draftNexusMeta.mechanic)
                payload.mechanic = String(root.draftNexusMeta.mechanic)
            if (Array.isArray(root.draftNexusMeta.primaryMuscles) && root.draftNexusMeta.primaryMuscles.length > 0)
                payload.primaryMuscles = root.draftNexusMeta.primaryMuscles
            if (Array.isArray(root.draftNexusMeta.secondaryMuscles) && root.draftNexusMeta.secondaryMuscles.length > 0)
                payload.secondaryMuscles = root.draftNexusMeta.secondaryMuscles
            if (root.draftNexusMeta.previewUrl)
                payload.previewUrl = String(root.draftNexusMeta.previewUrl)
            if (root.draftNexusMeta.animationUrl)
                payload.animationUrl = String(root.draftNexusMeta.animationUrl)
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
        if (root.exerciseSearchOpen) {
            root.exerciseSearchOpen = false
            root.exerciseSearchIndex = -1
            return true
        }
        if (root.inspectedExerciseId.length > 0) {
            root.inspectedExerciseId = ""
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

    Timer {
        id: searchCloseTimer
        interval: 120
        repeat: false
        onTriggered: {
            if (!root.searchDropdownHovered && !exerciseNameField.activeFocus) {
                root.exerciseSearchOpen = false
                root.exerciseSearchIndex = -1
            }
        }
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

                    // Rest Timer pill (synced with Timer Edgebar / TimerService)
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

                        StyledToolTip {
                            text: (root.backend?.restExerciseName ?? "").length > 0
                                ? (Translation.tr("Synced with Timer Edgebar") + " · " + root.backend.restExerciseName)
                                : Translation.tr("Synced with Timer Edgebar")
                        }
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
                    }

                    // Quick Add / Edit Exercise Composer (with Nexus search)
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
                                    placeholderText: Translation.tr("Search Nexus exercises or type new…")
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    onActiveFocusChanged: {
                                        if (activeFocus) {
                                            searchCloseTimer.stop()
                                            root.exerciseSearchOpen = true
                                        } else {
                                            searchCloseTimer.restart()
                                        }
                                    }
                                    onTextEdited: {
                                        searchCloseTimer.stop()
                                        root.draftNameQuery = text
                                        root.exerciseSearchOpen = true
                                        root.exerciseSearchIndex = -1
                                        if (root.draftNexusMeta && text.trim() !== String(root.draftNexusMeta.title || "")) {
                                            root.draftNexusRelPath = ""
                                            root.draftNexusMeta = null
                                        }
                                    }
                                    onTextChanged: {
                                        if (root.draftNameQuery !== text)
                                            root.draftNameQuery = text
                                    }
                                    Keys.onDownPressed: event => {
                                        const count = root.exerciseSearchResults.length
                                        if (count > 0) {
                                            root.exerciseSearchOpen = true
                                            root.exerciseSearchIndex = (root.exerciseSearchIndex + 1) % count
                                            event.accepted = true
                                        }
                                    }
                                    Keys.onUpPressed: event => {
                                        const count = root.exerciseSearchResults.length
                                        if (count > 0) {
                                            root.exerciseSearchOpen = true
                                            root.exerciseSearchIndex = root.exerciseSearchIndex <= 0 ? (count - 1) : (root.exerciseSearchIndex - 1)
                                            event.accepted = true
                                        }
                                    }
                                    Keys.onReturnPressed: event => {
                                        if (root.exerciseSearchOpen && root.exerciseSearchIndex >= 0
                                                && root.exerciseSearchIndex < root.exerciseSearchResults.length) {
                                            root.selectSearchExercise(root.exerciseSearchResults[root.exerciseSearchIndex])
                                            event.accepted = true
                                        } else {
                                            root.submitExerciseDraft()
                                            event.accepted = true
                                        }
                                    }
                                    Keys.onEnterPressed: event => {
                                        if (root.exerciseSearchOpen && root.exerciseSearchIndex >= 0
                                                && root.exerciseSearchIndex < root.exerciseSearchResults.length) {
                                            root.selectSearchExercise(root.exerciseSearchResults[root.exerciseSearchIndex])
                                            event.accepted = true
                                        } else {
                                            root.submitExerciseDraft()
                                            event.accepted = true
                                        }
                                    }
                                }

                                PillButton {
                                    id: exerciseSearchToggleBtn
                                    objectName: "exerciseSearchToggleButton"
                                    iconName: root.exerciseSearchOpen ? "expand_less" : "search"
                                    toggled: root.exerciseSearchOpen
                                    onClicked: {
                                        searchCloseTimer.stop()
                                        root.exerciseSearchOpen = !root.exerciseSearchOpen
                                        if (root.exerciseSearchOpen) {
                                            root.draftNameQuery = exerciseNameField.text
                                            exerciseNameField.forceActiveFocus()
                                        }
                                    }
                                    StyledToolTip { text: Translation.tr("Search existing exercises") }
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

                            // Linked Nexus badge when an existing Nexus exercise is selected
                            RowLayout {
                                visible: root.draftNexusRelPath.length > 0
                                Layout.fillWidth: true
                                spacing: 6

                                Rectangle {
                                    radius: 10
                                    implicitHeight: 22
                                    implicitWidth: linkedBadgeRow.implicitWidth + 14
                                    color: root.colBannerBg

                                    Row {
                                        id: linkedBadgeRow
                                        anchors.centerIn: parent
                                        spacing: 4

                                        MaterialSymbol {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: "link"
                                            iconSize: 13
                                            color: root.colOnBanner
                                        }

                                        StyledText {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: Translation.tr("Linked to Nexus exercise")
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            font.weight: Font.DemiBold
                                            color: root.colOnBanner
                                        }
                                    }
                                }

                                RippleButton {
                                    implicitWidth: 20
                                    implicitHeight: 20
                                    buttonRadius: 10
                                    colBackground: "transparent"
                                    colBackgroundHover: root.colCardHover
                                    onClicked: {
                                        root.draftNexusRelPath = ""
                                        root.draftNexusMeta = null
                                    }
                                    contentItem: Item {
                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: "close"
                                            iconSize: 13
                                            color: root.colSubtext
                                        }
                                    }
                                    StyledToolTip { text: Translation.tr("Clear Nexus link") }
                                }

                                Item { Layout.fillWidth: true }
                            }

                            // Search autocomplete dropdown (Nexus library + recent history + presets)
                            Rectangle {
                                id: exerciseSearchDropdown
                                objectName: "exerciseSearchDropdown"
                                visible: root.exerciseSearchOpen && root.exerciseSearchResults.length > 0
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                Layout.preferredHeight: Math.min(184, Math.max(44, searchResultsList.contentHeight + 8))
                                radius: Appearance.rounding.small
                                color: root.colCard
                                border.width: 1
                                border.color: root.colInputBorder
                                clip: true

                                HoverHandler {
                                    onHoveredChanged: root.searchDropdownHovered = hovered
                                }

                                ListView {
                                    id: searchResultsList
                                    anchors.fill: parent
                                    anchors.margins: 4
                                    spacing: 3
                                    clip: true
                                    boundsBehavior: Flickable.StopAtBounds
                                    model: root.exerciseSearchResults

                                    delegate: RippleButton {
                                        id: searchItemBtn
                                        required property var modelData
                                        required property int index
                                        objectName: "exerciseSearchResult_" + index
                                        width: searchResultsList.width
                                        implicitHeight: 40
                                        buttonRadius: Appearance.rounding.small - 2
                                        colBackground: index === root.exerciseSearchIndex ? root.colBannerBg : "transparent"
                                        colBackgroundHover: root.colCardHover
                                        onClicked: root.selectSearchExercise(searchItemBtn.modelData)

                                        contentItem: RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 6
                                            anchors.rightMargin: 6
                                            spacing: 8

                                            Rectangle {
                                                Layout.preferredWidth: 28
                                                Layout.preferredHeight: 28
                                                radius: 6
                                                color: root.colCardElevated
                                                clip: true

                                                Image {
                                                    anchors.fill: parent
                                                    visible: String(searchItemBtn.modelData.previewUrl || "").length > 0
                                                    asynchronous: true
                                                    cache: false
                                                    sourceSize: Qt.size(64, 64)
                                                    fillMode: Image.PreserveAspectCrop
                                                    source: searchItemBtn.modelData.previewUrl || ""
                                                }

                                                Canvas {
                                                    anchors.fill: parent
                                                    anchors.margins: 2
                                                    visible: String(searchItemBtn.modelData.previewUrl || "").length === 0
                                                    onVisibleChanged: if (visible) requestPaint()
                                                    onPaint: {
                                                        const ctx = getContext("2d")
                                                        const prim = searchItemBtn.modelData.primaryMuscles?.[0] ?? searchItemBtn.modelData.category ?? "chest"
                                                        ExerciseAnatomyData.paintMiniMuscleIcon(ctx, width, height, prim, String(root.colSubtext), String(root.colAccent))
                                                    }
                                                }
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                Layout.minimumWidth: 0
                                                spacing: 0

                                                StyledText {
                                                    Layout.fillWidth: true
                                                    Layout.minimumWidth: 0
                                                    text: searchItemBtn.modelData.title || ""
                                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                                    font.weight: Font.DemiBold
                                                    color: root.colText
                                                    elide: Text.ElideRight
                                                }

                                                StyledText {
                                                    Layout.fillWidth: true
                                                    Layout.minimumWidth: 0
                                                    text: {
                                                        const parts = []
                                                        const prims = searchItemBtn.modelData.primaryMuscles
                                                        if (Array.isArray(prims) && prims.length > 0)
                                                            parts.push(prims.slice(0, 2).join(", "))
                                                        else
                                                            parts.push(String(searchItemBtn.modelData.category || "").toUpperCase())
                                                        if (searchItemBtn.modelData.equipment)
                                                            parts.push(searchItemBtn.modelData.equipment)
                                                        if (Number(searchItemBtn.modelData.weight) > 0)
                                                            parts.push("Last: " + searchItemBtn.modelData.sets + "×" + searchItemBtn.modelData.reps + " · " + searchItemBtn.modelData.weight + " kg")
                                                        return parts.join(" · ")
                                                    }
                                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                                    color: root.colSubtext
                                                    elide: Text.ElideRight
                                                }
                                            }

                                            Rectangle {
                                                radius: 8
                                                implicitHeight: 20
                                                implicitWidth: srcTagTxt.implicitWidth + 12
                                                color: searchItemBtn.modelData.source === "nexus" ? root.colBannerBg : root.colInputBg

                                                StyledText {
                                                    id: srcTagTxt
                                                    anchors.centerIn: parent
                                                    text: searchItemBtn.modelData.sourceLabel || ""
                                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                                    font.weight: Font.DemiBold
                                                    color: searchItemBtn.modelData.source === "nexus" ? root.colOnBanner : root.colSubtext
                                                }
                                            }
                                        }
                                    }
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
                            readonly property bool isInspected: root.inspectedExerciseId === modelData.id
                            width: checklistView.width
                            implicitHeight: Math.max(50, exInnerRow.implicitHeight + 14)
                            radius: Appearance.rounding.small
                            color: exRow.isInspected
                                ? root.colBannerBg
                                : modelData.completed
                                    ? root.colCompletedRowBg
                                    : root.colCardElevated
                            border.width: exRow.isInspected ? 1.5 : 0
                            border.color: exRow.isInspected ? root.colAccent : "transparent"

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

                                Item {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    implicitHeight: exNameCol.implicitHeight

                                    ColumnLayout {
                                        id: exNameCol
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 1

                                        RowLayout {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            spacing: 5

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

                                            MaterialSymbol {
                                                visible: String(exRow.modelData.nexusRelPath || "").length > 0
                                                text: "hub"
                                                iconSize: 13
                                                color: root.colAccent
                                            }
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

                                    MouseArea {
                                        objectName: "exerciseInspectArea_" + exRow.modelData.id
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.inspectExercise(exRow.modelData)
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
                            onEditingFinished: {
                                root.backend?.setDayMetadata({ scheduledStart: text })
                                text = root.dayPlan.scheduledStart
                                scheduleEndField.text = root.dayPlan.scheduledEnd
                            }
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
                            onEditingFinished: {
                                root.backend?.setDayMetadata({ scheduledEnd: text })
                                text = root.dayPlan.scheduledEnd
                            }
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

            // ══════ RIGHT COLUMN: BODY TRACKER OR INSPECTED EXERCISE DETAIL ══════
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
                    id: bodyTrackerCol
                    visible: root.inspectedExercise === null
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

                // Exercise Detail Panel (Demo, Front/Back Muscle Map, Profile, Instructions & Tips)
                ColumnLayout {
                    id: exerciseDetailPanel
                    objectName: "exercisesDetailPanel"
                    visible: root.inspectedExercise !== null
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 10

                    readonly property var detail: root.inspectedDetail
                    readonly property string previewUrl: String(detail?.previewUrl || "")
                    readonly property string animUrl: String(detail?.animationUrl || "")
                    readonly property bool hasMedia: previewUrl.length > 0 || animUrl.length > 0

                    // Detail Header: Back to Body Tracker + Title + Quick Rest Timer
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        spacing: 8

                        PillButton {
                            objectName: "exercisesDetailBackButton"
                            iconName: "arrow_back"
                            label: Translation.tr("Body Tracker")
                            onClicked: root.inspectedExerciseId = ""
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            spacing: 0

                            StyledText {
                                objectName: "exercisesDetailTitle"
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                text: exerciseDetailPanel.detail?.name || root.inspectedExercise?.name || ""
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.Bold
                                color: root.colText
                                elide: Text.ElideRight
                            }

                            StyledText {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                text: {
                                    const ex = root.inspectedExercise
                                    const dt = exerciseDetailPanel.detail
                                    const parts = []
                                    parts.push(dt?.isLinkedToNexus ? Translation.tr("Nexus Exercise") : Translation.tr("Custom Exercise"))
                                    if (dt?.level)
                                        parts.push(dt.level)
                                    if (ex)
                                        parts.push(root.backend?.formatExerciseTarget(ex) ?? "")
                                    return parts.filter(p => p.length > 0).join(" · ")
                                }
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: root.colSubtext
                                elide: Text.ElideRight
                            }
                        }

                        PillButton {
                            objectName: "exercisesDetailRestButton"
                            iconName: "timer"
                            label: root.inspectedExercise ? (root.inspectedExercise.restSec + "s") : ""
                            onClicked: {
                                if (root.inspectedExercise)
                                    root.backend?.startRestTimer(root.inspectedExercise.restSec, root.inspectedExercise.name)
                            }
                            StyledToolTip { text: Translation.tr("Start rest countdown on Timer Edgebar") }
                        }
                    }

                    Flickable {
                        id: detailFlickable
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.minimumWidth: 0
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        contentWidth: width
                        contentHeight: detailContentCol.implicitHeight

                        ColumnLayout {
                            id: detailContentCol
                            width: detailFlickable.width
                            spacing: 10

                            // 1. Demo Media Frame
                            Rectangle {
                                objectName: "exercisesDetailMediaCard"
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                implicitHeight: mediaCol.implicitHeight + 16
                                radius: Appearance.rounding.small
                                color: root.colCardElevated
                                border.width: 0

                                ColumnLayout {
                                    id: mediaCol
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    spacing: 8

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        spacing: 6

                                        MaterialSymbol {
                                            text: "play_circle"
                                            iconSize: 16
                                            color: root.colAccent
                                        }

                                        StyledText {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            text: Translation.tr("Form & Technique Demo")
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                            font.weight: Font.DemiBold
                                            color: root.colText
                                            elide: Text.ElideRight
                                        }

                                        PillButton {
                                            objectName: "exercisesDetailPlayDemoButton"
                                            visible: exerciseDetailPanel.animUrl.length > 0
                                            implicitHeight: 26
                                            toggled: root.inspectedExercise !== null && exerciseDetailPanel.animUrl.length > 0 && root.detailDemoPlaying
                                            iconName: root.detailDemoPlaying ? "pause" : "play_arrow"
                                            label: root.detailDemoPlaying ? Translation.tr("Pause Demo") : Translation.tr("Play Demo")
                                            onClicked: root.detailDemoPlaying = !root.detailDemoPlaying
                                        }
                                    }

                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        implicitHeight: Math.round(Math.max(150, Math.min(220, width * 0.56)))
                                        radius: Appearance.rounding.small
                                        color: root.colCard
                                        clip: true

                                        Image {
                                            id: exDetailPreviewImg
                                            objectName: "exercisesDetailPreviewImage"
                                            anchors.fill: parent
                                            visible: exerciseDetailPanel.hasMedia
                                                && !(root.detailDemoPlaying && exDetailAnimImg.visible && exDetailAnimImg.status === AnimatedImage.Ready)
                                            source: exerciseDetailPanel.previewUrl.length > 0
                                                ? exerciseDetailPanel.previewUrl
                                                : exerciseDetailPanel.animUrl
                                            sourceSize: Qt.size(480, 360)
                                            fillMode: Image.PreserveAspectFit
                                            asynchronous: true
                                            cache: false
                                        }

                                        AnimatedImage {
                                            id: exDetailAnimImg
                                            objectName: "exercisesDetailAnimatedImage"
                                            anchors.fill: parent
                                            visible: root.inspectedExercise !== null
                                                && root.detailDemoPlaying
                                                && exerciseDetailPanel.animUrl.length > 0
                                            source: visible ? exerciseDetailPanel.animUrl : ""
                                            fillMode: Image.PreserveAspectFit
                                            playing: visible && status === AnimatedImage.Ready && root.presentationActive && root.visible
                                            asynchronous: true
                                            cache: false
                                        }

                                        ColumnLayout {
                                            visible: !exerciseDetailPanel.hasMedia
                                            anchors.centerIn: parent
                                            spacing: 6

                                            Canvas {
                                                id: fallbackEqCanvas
                                                Layout.alignment: Qt.AlignHCenter
                                                width: 40
                                                height: 40
                                                readonly property string eqStr: String(exerciseDetailPanel.detail?.equipment || "body only")
                                                readonly property color strokeCol: root.colAccent
                                                onEqStrChanged: if (visible) requestPaint()
                                                onStrokeColChanged: if (visible) requestPaint()
                                                onVisibleChanged: if (visible) requestPaint()
                                                onPaint: {
                                                    const ctx = getContext("2d")
                                                    ExerciseAnatomyData.paintEquipmentIcon(ctx, width, height, eqStr, String(strokeCol))
                                                }
                                            }

                                            StyledText {
                                                Layout.alignment: Qt.AlignHCenter
                                                text: Translation.tr("No demo animation linked in Nexus note")
                                                font.pixelSize: Appearance.font.pixelSize.smallest
                                                color: root.colSubtext
                                            }
                                        }
                                    }
                                }
                            }

                            // 2. Front / Back Body Muscle Focus Map (from Nexus Anatomy)
                            Rectangle {
                                objectName: "exercisesDetailAnatomyCard"
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                implicitHeight: anatomyCol.implicitHeight + 16
                                radius: Appearance.rounding.small
                                color: root.colCardElevated
                                border.width: 0

                                ColumnLayout {
                                    id: anatomyCol
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    spacing: 8

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        spacing: 8

                                        StyledText {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            text: Translation.tr("Target Muscle Focus (Front / Back)")
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                            font.weight: Font.DemiBold
                                            color: root.colText
                                            elide: Text.ElideRight
                                        }

                                        Row {
                                            spacing: 5
                                            Rectangle {
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: 8
                                                height: 8
                                                radius: 4
                                                color: root.colAccent
                                            }
                                            StyledText {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: Translation.tr("Primary")
                                                font.pixelSize: Appearance.font.pixelSize.smallest
                                                color: root.colSubtext
                                            }
                                            Item { width: 4; height: 1 }
                                            Rectangle {
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: 8
                                                height: 8
                                                radius: 4
                                                color: root.colSecondaryMuscle
                                            }
                                            StyledText {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: Translation.tr("Secondary")
                                                font.pixelSize: Appearance.font.pixelSize.smallest
                                                color: root.colSubtext
                                            }
                                        }
                                    }

                                    Canvas {
                                        id: detailBodyMapCanvas
                                        objectName: "exercisesDetailBodyMapCanvas"
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        implicitHeight: Math.max(250, Math.min(340, Math.round(width * 0.86)))
                                        readonly property var pList: exerciseDetailPanel.detail?.primaryMuscles ?? []
                                        readonly property var sList: exerciseDetailPanel.detail?.secondaryMuscles ?? []
                                        readonly property color pCol: root.colAccent
                                        readonly property color sCol: root.colSecondaryMuscle
                                        readonly property color bgCol: root.colCardElevated

                                        onPListChanged: if (visible) requestPaint()
                                        onSListChanged: if (visible) requestPaint()
                                        onPColChanged: if (visible) requestPaint()
                                        onSColChanged: if (visible) requestPaint()
                                        onBgColChanged: if (visible) requestPaint()
                                        onWidthChanged: if (visible) requestPaint()
                                        onHeightChanged: if (visible) requestPaint()
                                        onVisibleChanged: if (visible) requestPaint()

                                        onPaint: {
                                            const ctx = getContext("2d")
                                            const bodyFill = String(Qt.tint(root.colCard, Qt.rgba(root.colSubtext.r, root.colSubtext.g, root.colSubtext.b, 0.14)))
                                            const bodyStroke = String(Qt.rgba(root.colSubtext.r, root.colSubtext.g, root.colSubtext.b, 0.52))
                                            const muscleFill = String(Qt.tint(root.colCard, Qt.rgba(root.colSubtext.r, root.colSubtext.g, root.colSubtext.b, 0.22)))
                                            const muscleStroke = String(root.colCardElevated)
                                            ExerciseAnatomyData.paintAnatomyMap(ctx, width, height, pList, sList, {
                                                bodyFill: bodyFill,
                                                bodyStroke: bodyStroke,
                                                muscleFill: muscleFill,
                                                muscleStroke: muscleStroke,
                                                secondaryFill: String(Qt.rgba(sCol.r, sCol.g, sCol.b, 0.52)),
                                                secondaryStroke: String(sCol),
                                                secondaryGlowOuter: String(Qt.rgba(sCol.r, sCol.g, sCol.b, 0.03)),
                                                secondaryGlowInner: String(Qt.rgba(sCol.r, sCol.g, sCol.b, 0.12)),
                                                secondaryRim: String(Qt.rgba(sCol.r, sCol.g, sCol.b, 0.22)),
                                                primaryFill: String(Qt.rgba(pCol.r, pCol.g, pCol.b, 0.62)),
                                                primaryStroke: String(pCol),
                                                primaryGlowOuter: String(Qt.rgba(pCol.r, pCol.g, pCol.b, 0.04)),
                                                primaryGlowInner: String(Qt.rgba(pCol.r, pCol.g, pCol.b, 0.14)),
                                                primaryRim: String(Qt.rgba(pCol.r, pCol.g, pCol.b, 0.24)),
                                                labelColor: String(root.colSubtext)
                                            })
                                        }
                                    }

                                    Flow {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        spacing: 5

                                        Repeater {
                                            model: exerciseDetailPanel.detail?.primaryMuscles ?? []
                                            delegate: Rectangle {
                                                required property string modelData
                                                radius: 10
                                                implicitHeight: 22
                                                implicitWidth: primChipTxt.implicitWidth + 14
                                                color: root.colBannerBg
                                                StyledText {
                                                    id: primChipTxt
                                                    anchors.centerIn: parent
                                                    text: Translation.tr("Primary") + ": " + modelData
                                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                                    font.weight: Font.DemiBold
                                                    color: root.colOnBanner
                                                }
                                            }
                                        }

                                        Repeater {
                                            model: exerciseDetailPanel.detail?.secondaryMuscles ?? []
                                            delegate: Rectangle {
                                                required property string modelData
                                                radius: 10
                                                implicitHeight: 22
                                                implicitWidth: secChipTxt.implicitWidth + 14
                                                color: root.colInputBg
                                                StyledText {
                                                    id: secChipTxt
                                                    anchors.centerIn: parent
                                                    text: Translation.tr("Secondary") + ": " + modelData
                                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                                    color: root.colText
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // 3. Movement Profile & Equipment
                            Rectangle {
                                objectName: "exercisesDetailProfileCard"
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                implicitHeight: profileGrid.implicitHeight + 16
                                radius: Appearance.rounding.small
                                color: root.colCardElevated
                                border.width: 0

                                RowLayout {
                                    id: profileGrid
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    spacing: 10

                                    Rectangle {
                                        Layout.preferredWidth: 38
                                        Layout.preferredHeight: 38
                                        radius: 8
                                        color: root.colCard

                                        Canvas {
                                            anchors.fill: parent
                                            anchors.margins: 6
                                            readonly property string eqName: String(exerciseDetailPanel.detail?.equipment || "body only")
                                            readonly property color eqCol: root.colAccent
                                            onEqNameChanged: if (visible) requestPaint()
                                            onEqColChanged: if (visible) requestPaint()
                                            onVisibleChanged: if (visible) requestPaint()
                                            onPaint: {
                                                const ctx = getContext("2d")
                                                ExerciseAnatomyData.paintEquipmentIcon(ctx, width, height, eqName, String(eqCol))
                                            }
                                        }
                                    }

                                    Flow {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        spacing: 12

                                        Column {
                                            spacing: 1
                                            StyledText {
                                                text: Translation.tr("Equipment")
                                                font.pixelSize: Appearance.font.pixelSize.smallest
                                                color: root.colSubtext
                                            }
                                            StyledText {
                                                text: exerciseDetailPanel.detail?.equipment || Translation.tr("Body only")
                                                font.pixelSize: Appearance.font.pixelSize.smaller
                                                font.weight: Font.DemiBold
                                                color: root.colText
                                            }
                                        }

                                        Column {
                                            visible: String(exerciseDetailPanel.detail?.force || "").length > 0
                                            spacing: 1
                                            StyledText {
                                                text: Translation.tr("Force")
                                                font.pixelSize: Appearance.font.pixelSize.smallest
                                                color: root.colSubtext
                                            }
                                            StyledText {
                                                text: exerciseDetailPanel.detail?.force || ""
                                                font.pixelSize: Appearance.font.pixelSize.smaller
                                                font.weight: Font.DemiBold
                                                color: root.colText
                                            }
                                        }

                                        Column {
                                            visible: String(exerciseDetailPanel.detail?.mechanic || "").length > 0
                                            spacing: 1
                                            StyledText {
                                                text: Translation.tr("Mechanic")
                                                font.pixelSize: Appearance.font.pixelSize.smallest
                                                color: root.colSubtext
                                            }
                                            StyledText {
                                                text: exerciseDetailPanel.detail?.mechanic || ""
                                                font.pixelSize: Appearance.font.pixelSize.smaller
                                                font.weight: Font.DemiBold
                                                color: root.colText
                                            }
                                        }

                                        Column {
                                            visible: String(exerciseDetailPanel.detail?.level || "").length > 0
                                            spacing: 1
                                            StyledText {
                                                text: Translation.tr("Level")
                                                font.pixelSize: Appearance.font.pixelSize.smallest
                                                color: root.colSubtext
                                            }
                                            StyledText {
                                                text: exerciseDetailPanel.detail?.level || ""
                                                font.pixelSize: Appearance.font.pixelSize.smaller
                                                font.weight: Font.DemiBold
                                                color: root.colText
                                            }
                                        }
                                    }
                                }
                            }

                            // 4. How to Perform (Steps from Nexus note)
                            Rectangle {
                                objectName: "exercisesDetailStepsCard"
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                implicitHeight: stepsCol.implicitHeight + 16
                                radius: Appearance.rounding.small
                                color: root.colCardElevated
                                border.width: 0

                                ColumnLayout {
                                    id: stepsCol
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    spacing: 6

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: Translation.tr("How to Perform")
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        font.weight: Font.DemiBold
                                        color: root.colText
                                    }

                                    StyledText {
                                        visible: Boolean(exerciseDetailPanel.detail?.loading)
                                        Layout.fillWidth: true
                                        text: Translation.tr("Loading instructions from Nexus…")
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: root.colSubtext
                                    }

                                    StyledText {
                                        visible: !Boolean(exerciseDetailPanel.detail?.loading)
                                            && (exerciseDetailPanel.detail?.steps?.length ?? 0) === 0
                                        Layout.fillWidth: true
                                        wrapMode: Text.WordWrap
                                        text: String(root.inspectedExercise?.notes || "").length > 0
                                            ? root.inspectedExercise.notes
                                            : Translation.tr("No step-by-step instructions recorded for this exercise.")
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: root.colSubtext
                                    }

                                    Repeater {
                                        model: exerciseDetailPanel.detail?.steps ?? []
                                        delegate: RowLayout {
                                            required property string modelData
                                            required property int index
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            spacing: 6

                                            StyledText {
                                                Layout.alignment: Qt.AlignTop
                                                text: String(index + 1) + "."
                                                font.family: Appearance.font.family.monospace
                                                font.pixelSize: Appearance.font.pixelSize.smallest
                                                font.weight: Font.Bold
                                                color: root.colAccent
                                            }

                                            StyledText {
                                                Layout.fillWidth: true
                                                Layout.minimumWidth: 0
                                                wrapMode: Text.WordWrap
                                                text: modelData
                                                font.pixelSize: Appearance.font.pixelSize.smallest
                                                color: root.colText
                                            }
                                        }
                                    }
                                }
                            }

                            // 5. Personal Tips & Notes from Nexus
                            Rectangle {
                                objectName: "exercisesDetailTipsCard"
                                visible: (exerciseDetailPanel.detail?.tips?.length ?? 0) > 0
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                implicitHeight: tipsCol.implicitHeight + 16
                                radius: Appearance.rounding.small
                                color: root.colCardElevated
                                border.width: 0

                                ColumnLayout {
                                    id: tipsCol
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    spacing: 4

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: Translation.tr("Tips & Cues")
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        font.weight: Font.DemiBold
                                        color: root.colText
                                    }

                                    Repeater {
                                        model: exerciseDetailPanel.detail?.tips ?? []
                                        delegate: StyledText {
                                            required property string modelData
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            wrapMode: Text.WordWrap
                                            text: "• " + modelData
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            color: root.colSubtext
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
