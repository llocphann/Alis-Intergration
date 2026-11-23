pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import qs.services as HostServices
import QtQuick
import Quickshell
import Quickshell.Io
import "ExercisesTrackerEngine.js" as Engine

Item {
    id: root
    objectName: "exercisesTrackerService"

    property string stateDir: `${Directories.stateUserPath}/exercises-tracker`
    property string filePath: `${root.stateDir}/state.json`
    property string photosDir: `${root.stateDir}/photos`
    property string helperScriptPath: (HostServices.AlisIntergration?.exercisesTrackerHelperPath?.() ?? "")
        || decodeURIComponent(String(Qt.resolvedUrl("../scripts/integrations/exercises_tracker.py")).replace(/^(?:file:\/\/|qs:)/, ""))

    property bool ready: false
    property int revision: 0
    property bool presentationActive: false
    property var state: Engine.createEmptyState()

    readonly property string todayStr: Engine.formatDateStr(HostServices.DateTime?.todayDate ?? new Date())
    property string selectedDate: Engine.formatDateStr(HostServices.DateTime?.todayDate ?? new Date())

    readonly property var _workoutWriter: HostServices.AlisIntergration?.session?.zettelkasten ?? null
    property string _exportVaultPath: ""
    readonly property bool workoutExportPending: root._exportVaultPath.length > 0
    property bool photoImportBusy: false
    property string statusMessage: ""
    property string errorMessage: ""

    // Rest timer state — strictly paused when hidden/inactive (zero idle wakeups)
    property int restTotalSec: 90
    property int restRemainingSec: 0
    property bool restRunning: false
    property string restExerciseName: ""

    property bool _dirEnsured: false
    property bool _loadError: false
    property bool _savePending: false
    property bool _writing: false
    property string _lastSavedText: ""
    property var _pendingPhotoRequest: null
    property var _deletePhotoQueue: []
    property int _plannerTrigger: 0

    signal stateUpdated()
    signal workoutLogged(string dateStr)
    signal bodyCheckinAdded(var checkin)

    onPresentationActiveChanged: {
        if (!root.presentationActive && root.restRunning)
            root.restRunning = false
    }

    onFilePathChanged: {
        root._dirEnsured = false
        if (root.filePath.length > 0)
            stateFileView.reload()
    }

    readonly property var categories: Engine.CATEGORIES
    readonly property var routineOptions: [
        { id: "push", label: "Push", icon: "fitness_center" },
        { id: "pull", label: "Pull", icon: "accessibility_new" },
        { id: "legs", label: "Legs", icon: "directions_run" },
        { id: "core", label: "Core", icon: "self_improvement" },
        { id: "cardio", label: "Cardio", icon: "monitor_heart" },
        { id: "full_body", label: "Full Body", icon: "sports_martial_arts" },
        { id: "rest", label: "Recovery", icon: "spa" },
        { id: "custom", label: "Custom", icon: "tune" }
    ]

    readonly property var preferences: {
        void root.revision
        return root.state?.preferences ?? Engine.normalizePreferences({})
    }

    readonly property var weeklyTemplates: {
        void root.revision
        return root.state?.weeklyTemplates ?? Engine.DEFAULT_WEEKLY_TEMPLATES
    }

    readonly property var todaySummary: {
        void root.revision
        return Engine.computeGlobalSummary(root.state, root.todayStr)
    }

    readonly property int streakDays: Number(root.todaySummary?.currentStreakDays ?? 0)
    readonly property real weeklyVolumeKg: Number(root.todaySummary?.weeklyVolumeKg ?? 0)

    readonly property var dayPlan: {
        void root.revision
        return Engine.computeDaySummary(root.state, root.selectedDate)
    }

    readonly property var weekStripDays: {
        void root.revision
        const anchor = Engine.parseLocalDate(root.selectedDate)
        const dow = anchor.getDay()
        const mondayOffset = dow === 0 ? -6 : (1 - dow)
        const mondayStr = Engine.addDaysStr(root.selectedDate, mondayOffset)
        const labels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        const items = []
        for (let i = 0; i < 7; i++) {
            const dStr = Engine.addDaysStr(mondayStr, i)
            const info = Engine.computeDaySummary(root.state, dStr)
            items.push({
                date: dStr,
                dayNumber: dStr.slice(8, 10),
                shortLabel: labels[i],
                isToday: dStr === root.todayStr,
                isSelected: dStr === root.selectedDate,
                totalExercises: info.totalExercises,
                completedExercises: info.completedExercises,
                allDone: info.totalExercises > 0 && info.completedExercises >= info.totalExercises,
                hasAny: info.totalExercises > 0,
                routineLabel: info.routineLabel
            })
        }
        return items
    }

    readonly property var bodyCheckins: {
        void root.revision
        const list = Array.isArray(root.state?.bodyCheckins) ? root.state.bodyCheckins : []
        return list.map((bc, idx) => {
            let prevWeight = 0
            for (let j = idx + 1; j < list.length; j++) {
                if (Number(list[j]?.weightKg) > 0) {
                    prevWeight = Number(list[j].weightKg)
                    break
                }
            }
            const delta = (Number(bc.weightKg) > 0 && prevWeight > 0)
                ? Math.round((Number(bc.weightKg) - prevWeight) * 100) / 100
                : 0
            const hasDelta = Number(bc.weightKg) > 0 && prevWeight > 0
            return Object.assign({}, bc, {
                photoUrl: bc.photoPath ? ("file://" + bc.photoPath) : "",
                hasPhoto: Boolean(bc.photoPath && String(bc.photoPath).length > 0),
                hasWeightDelta: hasDelta,
                weightDeltaKg: delta
            })
        })
    }

    readonly property var plannerWorkouts: {
        void root.revision
        void root._plannerTrigger
        if (!root.presentationActive)
            return []
        const dateObj = Engine.parseLocalDate(root.selectedDate)
        const results = []
        const seenKeys = ({})
        const localEvents = (HostServices.Events?.ready && typeof HostServices.Events.getAllEventsForDate === "function")
            ? (HostServices.Events.getAllEventsForDate(dateObj) || [])
            : []
        for (let i = 0; i < localEvents.length; i++) {
            const ev = localEvents[i]
            const parsed = Engine.parsePlannerWorkoutEvent(ev)
            if (parsed) {
                const key = "local:" + String(ev.id ?? i)
                if (!seenKeys[key]) {
                    seenKeys[key] = true
                    results.push(Object.assign({}, parsed, { source: "local", rawEvent: ev }))
                }
            }
        }
        const extEvents = (typeof HostServices.CalendarSync?.getEventsForDate === "function")
            ? (HostServices.CalendarSync.getEventsForDate(dateObj) || [])
            : []
        for (let j = 0; j < extEvents.length; j++) {
            const extEv = extEvents[j]
            const parsedExt = Engine.parsePlannerWorkoutEvent(extEv)
            if (parsedExt) {
                const extKey = "ext:" + String(extEv.uid ?? extEv.id ?? j)
                if (!seenKeys[extKey]) {
                    seenKeys[extKey] = true
                    results.push(Object.assign({}, parsedExt, { source: "external", rawEvent: extEv }))
                }
            }
        }
        return results
    }

    Connections {
        target: root.presentationActive ? HostServices.Events : null
        function onEventAdded() { root._plannerTrigger++ }
        function onEventUpdated() { root._plannerTrigger++ }
        function onEventRemoved() { root._plannerTrigger++ }
        function onReadyChanged() { root._plannerTrigger++ }
    }

    Connections {
        target: root.presentationActive ? HostServices.CalendarSync : null
        function onEventsUpdated() { root._plannerTrigger++ }
    }

    Timer {
        id: restTickTimer
        interval: 1000
        repeat: true
        running: root.restRunning && root.presentationActive && root.restRemainingSec > 0
        onTriggered: {
            if (root.restRemainingSec <= 1) {
                root.restRemainingSec = 0
                root.restRunning = false
                root.statusMessage = root.restExerciseName.length > 0
                    ? ("Rest finished · Ready for next set (" + root.restExerciseName + ")")
                    : "Rest timer complete"
            } else {
                root.restRemainingSec = root.restRemainingSec - 1
            }
        }
    }

    Timer {
        id: saveDebounceTimer
        interval: 80
        repeat: false
        onTriggered: root._performSave()
    }

    FileView {
        id: stateFileView
        path: root.filePath.length > 0 ? ("file://" + root.filePath) : ""
        preload: true
        watchChanges: false
        printErrors: false
        onLoaded: {
            root._dirEnsured = true
            if (root._writing)
                return
            const rawText = stateFileView.text()
            if (!rawText || rawText.trim().length === 0) {
                root._loadError = false
                root.state = Engine.createEmptyState()
                root._lastSavedText = ""
                root.ready = true
                root.revision++
                return
            }
            try {
                const parsed = JSON.parse(rawText)
                root._loadError = false
                root.state = Engine.normalizeState(parsed, root.todayStr)
                root._lastSavedText = rawText
                root.errorMessage = ""
                root.ready = true
                root.revision++
                root.stateUpdated()
            } catch (err) {
                console.warn("[ExercisesTracker] Failed to parse state.json:", err)
                root._loadError = true
                root.errorMessage = "Could not read Exercises Tracker state"
                root.ready = true
                root.revision++
            }
        }
        onLoadFailed: err => {
            if (err === FileViewError.FileNotFound) {
                root._loadError = false
                root.state = Engine.createEmptyState()
                root._lastSavedText = ""
                root.errorMessage = ""
                root.ready = true
                root.revision++
            } else {
                console.warn("[ExercisesTracker] Load failed:", err)
                root._loadError = true
                root.errorMessage = "Could not load Exercises Tracker data"
                root.ready = true
                root.revision++
            }
        }
        onSaved: {
            root._writing = false
            if (root._savePending) {
                root._savePending = false
                saveDebounceTimer.restart()
            }
        }
        onSaveFailed: err => {
            root._writing = false
            root._lastSavedText = ""
            if (!root._dirEnsured && root.stateDir.length > 0 && !mkdirProc.running) {
                root._savePending = true
                mkdirProc.command = ["/usr/bin/mkdir", "-p", root.stateDir]
                mkdirProc.running = true
                return
            }
            console.warn("[ExercisesTracker] Save failed:", err)
            root.errorMessage = "Could not save Exercises Tracker state"
        }
    }

    Process {
        id: mkdirProc
        running: false
        onExited: exitCode => {
            if (exitCode === 0)
                root._dirEnsured = true
            root._savePending = false
            root._writeSerializedNow()
        }
    }

    Timer {
        id: photoImportFlushTimer
        interval: 60
        repeat: false
        onTriggered: {
            if (photoImportProc._exited && !photoImportProc._finalized) {
                photoImportProc._stdoutDone = true
                photoImportProc._maybeFinalize()
            }
        }
    }

    Process {
        id: photoImportProc
        running: false
        property bool _exited: false
        property int _exitCode: 0
        property bool _stdoutDone: false
        property bool _finalized: false
        stdout: StdioCollector {
            id: photoImportOut
            onStreamFinished: {
                photoImportProc._stdoutDone = true
                photoImportProc._maybeFinalize()
            }
        }
        stderr: StdioCollector { id: photoImportErr }
        onStarted: {
            photoImportProc._exited = false
            photoImportProc._exitCode = 0
            photoImportProc._stdoutDone = false
            photoImportProc._finalized = false
            photoImportFlushTimer.stop()
        }
        onExited: exitCode => {
            photoImportProc._exited = true
            photoImportProc._exitCode = exitCode
            if (photoImportProc._stdoutDone)
                photoImportProc._maybeFinalize()
            else
                photoImportFlushTimer.restart()
        }
        function _maybeFinalize(): void {
            if (!photoImportProc._exited || photoImportProc._finalized || !photoImportProc._stdoutDone)
                return
            photoImportProc._finalized = true
            photoImportFlushTimer.stop()
            const exitCode = photoImportProc._exitCode
            root.photoImportBusy = false
            const req = root._pendingPhotoRequest
            root._pendingPhotoRequest = null
            try {
                const payload = JSON.parse(String(photoImportOut.text ?? "").trim())
                if (exitCode !== 0 || payload.ok !== true) {
                    root.errorMessage = String(payload.error || "Could not import photo")
                    return
                }
                const added = Engine.addBodyCheckin(root.state, {
                    id: req?.checkinId ?? "",
                    date: req?.dateStr ?? root.selectedDate,
                    photoPath: String(payload.photoPath ?? ""),
                    photoRel: String(payload.photoRel ?? ""),
                    weightKg: Number(req?.weightKg) || 0,
                    bodyFatPct: Number(req?.bodyFatPct) || 0,
                    note: String(req?.note ?? "")
                })
                root.errorMessage = ""
                root.statusMessage = "Body check-in saved"
                root._commitState(added.state)
                if (added.checkin)
                    root.bodyCheckinAdded(added.checkin)
            } catch (_err) {
                root.errorMessage = String(photoImportErr.text || "Failed to import body tracker photo").trim().slice(0, 200)
            }
        }
    }

    Process {
        id: photoDeleteProc
        running: false
        onExited: () => {
            root._drainPhotoDeleteQueue()
        }
    }

    function _drainPhotoDeleteQueue(): void {
        if (photoDeleteProc.running || root._deletePhotoQueue.length === 0)
            return
        const nextPath = root._deletePhotoQueue.shift()
        if (!nextPath || !root.helperScriptPath.length)
            return
        photoDeleteProc.command = [
            "/usr/bin/python3",
            root.helperScriptPath,
            "delete-photo",
            "--photo-path", String(nextPath),
            "--photos-dir", root.photosDir
        ]
        photoDeleteProc.running = true
    }

    property var _undoStack: []
    readonly property bool canUndo: _undoStack.length > 0

    function _commitState(nextState, loggedWorkoutDate = "", skipUndo = false): void {
        if (!skipUndo && root.state) {
            try {
                const snap = JSON.parse(JSON.stringify(root.state))
                root._undoStack = root._undoStack.concat([snap]).slice(-20)
            } catch (_e) {}
        }
        root.state = Engine.normalizeState(nextState, root.todayStr)
        root.revision++
        root._savePending = true
        if (!root._dirEnsured && root.stateDir.length > 0 && !mkdirProc.running) {
            mkdirProc.command = ["/usr/bin/mkdir", "-p", root.stateDir]
            mkdirProc.running = true
        } else {
            saveDebounceTimer.restart()
        }
        root.stateUpdated()
        if (loggedWorkoutDate.length > 0)
            root.workoutLogged(loggedWorkoutDate)
    }

    function undoLastAction(): bool {
        if (root._undoStack.length === 0)
            return false
        const copy = root._undoStack.slice()
        const prev = copy.pop()
        root._undoStack = copy
        root.statusMessage = "Undid last workout change"
        root._commitState(prev, "", true)
        return true
    }

    function copyLastSession(targetDateStr = ""): bool {
        const target = Engine.formatDateStr(targetDateStr || root.selectedDate)
        const logs = root.state?.days || {}
        const prevDates = Object.keys(logs)
            .filter(d => d < target && Array.isArray(logs[d]?.exercises) && logs[d].exercises.length > 0)
            .sort()
        if (prevDates.length === 0) {
            root.statusMessage = "No previous session to copy"
            return false
        }
        const srcDay = logs[prevDates[prevDates.length - 1]]
        const clonedExercises = srcDay.exercises.map(ex => Object.assign({}, ex, {
            completedSets: 0,
            completed: false
        }))
        const nextDays = Object.assign({}, logs)
        const curDay = Object.assign({}, logs[target] || {})
        curDay.exercises = clonedExercises
        nextDays[target] = curDay
        const nextState = Object.assign({}, root.state, { days: nextDays })
        root.statusMessage = "Copied session from " + prevDates[prevDates.length - 1]
        root._commitState(nextState, target)
        return true
    }

    function _performSave(): void {
        if (!root._savePending && !saveDebounceTimer.running)
            return
        if (root._writing || mkdirProc.running) {
            root._savePending = true
            return
        }
        root._savePending = false
        root._writeSerializedNow()
    }

    function _writeSerializedNow(): void {
        if (root._loadError || root.filePath.length === 0)
            return
        const serialized = Engine.serializeState(root.state, root.todayStr)
        if (serialized === root._lastSavedText)
            return
        root._lastSavedText = serialized
        root._writing = true
        stateFileView.setText(serialized)
    }

    function flushSave(): void {
        if (saveDebounceTimer.running) {
            saveDebounceTimer.stop()
            root._savePending = true
        }
        if (root._savePending)
            root._performSave()
    }

    // ── Navigation & Date Selection ──

    function selectDate(dateStr: string): void {
        root.selectedDate = Engine.formatDateStr(dateStr)
        root.statusMessage = ""
        root.errorMessage = ""
    }

    function stepDate(deltaDays: int): void {
        root.selectDate(Engine.addDaysStr(root.selectedDate, deltaDays))
    }

    function jumpToToday(): void {
        root.selectDate(root.todayStr)
    }

    // ── Daily Workout & Checklist Actions ──

    function applyTemplate(routineKey: string, replaceExisting = false): void {
        const next = Engine.applyRoutineTemplate(root.state, root.selectedDate, routineKey, replaceExisting)
        root._commitState(next, root.selectedDate)
        if (root.state.preferences?.autoSyncPlanner && (root.dayPlan?.plannerEventId ?? 0) > 0)
            root.syncDayToWeeklyPlanner(root.selectedDate)
    }

    function addExercise(spec): bool {
        const name = String(spec?.name ?? "").trim()
        if (!name.length)
            return false
        const next = Engine.addExercise(root.state, root.selectedDate, spec)
        root._commitState(next, root.selectedDate)
        if (root.state.preferences?.autoSyncPlanner && (root.dayPlan?.plannerEventId ?? 0) > 0)
            root.syncDayToWeeklyPlanner(root.selectedDate)
        return true
    }

    function updateExercise(exerciseId: string, patch): void {
        const next = Engine.updateExercise(root.state, root.selectedDate, exerciseId, patch)
        root._commitState(next, root.selectedDate)
        if (root.state.preferences?.autoSyncPlanner && (root.dayPlan?.plannerEventId ?? 0) > 0)
            root.syncDayToWeeklyPlanner(root.selectedDate)
    }

    function toggleExercise(exerciseId: string): void {
        const next = Engine.toggleExercise(root.state, root.selectedDate, exerciseId, new Date().toISOString())
        root._commitState(next, root.selectedDate)
        if (root.state.preferences?.autoSyncPlanner && (root.dayPlan?.plannerEventId ?? 0) > 0)
            root.syncDayToWeeklyPlanner(root.selectedDate)
    }

    function stepExerciseSets(exerciseId: string, delta: int): void {
        const next = Engine.stepCompletedSets(root.state, root.selectedDate, exerciseId, delta, new Date().toISOString())
        root._commitState(next, root.selectedDate)
        if (delta > 0 && (root.preferences?.autoStartRestOnSet ?? true) && root.presentationActive) {
            const ex = (root.dayPlan?.exercises ?? []).find(item => item.id === exerciseId)
            if (ex && !ex.completed)
                root.startRestTimer(ex.restSec, ex.name)
        }
    }

    function updatePreferences(patch): void {
        const next = Engine.updatePreferences(root.state, patch, root.todayStr)
        root._commitState(next)
    }

    function setWeekdayRoutine(weekdayKey: string, routineKey: string): void {
        const next = Engine.updateWeeklyTemplate(root.state, weekdayKey, routineKey, root.todayStr)
        root._commitState(next)
    }

    function applySplitPreset(presetKey: string): void {
        const next = Engine.applyWeeklySplitPreset(root.state, presetKey, root.todayStr)
        root._commitState(next)
    }

    function openPhotosFolder(): void {
        if (!root.photosDir.length)
            return
        if (!mkdirProc.running) {
            mkdirProc.command = ["/usr/bin/mkdir", "-p", root.photosDir]
            mkdirProc.running = true
        }
        Qt.openUrlExternally("file://" + root.photosDir)
    }

    function removeExercise(exerciseId: string): void {
        const next = Engine.removeExercise(root.state, root.selectedDate, exerciseId)
        root._commitState(next, root.selectedDate)
        if (root.state.preferences?.autoSyncPlanner && (root.dayPlan?.plannerEventId ?? 0) > 0)
            root.syncDayToWeeklyPlanner(root.selectedDate)
    }

    function moveExercise(exerciseId: string, delta: int): void {
        const next = Engine.moveExercise(root.state, root.selectedDate, exerciseId, delta)
        root._commitState(next)
    }

    function setDayMetadata(patch): void {
        const next = Engine.updateDayMetadata(root.state, root.selectedDate, patch)
        root._commitState(next)
    }

    function formatExerciseTarget(ex): string {
        return Engine.formatExerciseTarget(ex)
    }

    // ── Rest Timer Controls ──

    function startRestTimer(seconds = 0, exerciseName = ""): void {
        const total = Math.max(5, Math.min(600, Math.round(Number(seconds) || root.state.preferences?.defaultRestSeconds || 90)))
        root.restTotalSec = total
        root.restRemainingSec = total
        root.restExerciseName = String(exerciseName ?? "")
        root.restRunning = root.presentationActive
    }

    function toggleRestTimer(): void {
        if (root.restRemainingSec <= 0) {
            root.startRestTimer(root.restTotalSec, root.restExerciseName)
            return
        }
        root.restRunning = !root.restRunning && root.presentationActive
    }

    function stopRestTimer(): void {
        root.restRunning = false
        root.restRemainingSec = 0
        root.restExerciseName = ""
    }

    // ── Body Tracker Check-ins (User-Explicit Photo Import Only) ──

    function addBodyCheckin(sourcePhotoPath: string, weightKg: real, bodyFatPct: real, note: string, dateStr = ""): bool {
        const cleanPath = String(sourcePhotoPath ?? "").trim()
        const targetDate = Engine.formatDateStr(dateStr || root.selectedDate)
        const w = Number(weightKg) || 0
        const bf = Number(bodyFatPct) || 0
        const cleanNote = String(note ?? "").trim()

        if (cleanPath.length === 0) {
            if (w <= 0 && bf <= 0 && cleanNote.length === 0) {
                root.errorMessage = "Select a photo or enter body metrics first"
                return false
            }
            const added = Engine.addBodyCheckin(root.state, {
                date: targetDate,
                photoPath: "",
                photoRel: "",
                weightKg: w,
                bodyFatPct: bf,
                note: cleanNote
            })
            root.errorMessage = ""
            root.statusMessage = "Body metrics logged"
            root._commitState(added.state)
            if (added.checkin)
                root.bodyCheckinAdded(added.checkin)
            return added.checkin !== null
        }

        if (photoImportProc.running || root.helperScriptPath.length === 0) {
            root.errorMessage = "Photo import is already in progress"
            return false
        }

        const nextState = Engine.cloneState(root.state)
        const checkinId = "bc-" + String(nextState.nextSeq++)
        root._pendingPhotoRequest = {
            checkinId: checkinId,
            dateStr: targetDate,
            weightKg: w,
            bodyFatPct: bf,
            note: cleanNote
        }
        root.errorMessage = ""
        root.photoImportBusy = true
        photoImportProc.command = [
            "/usr/bin/python3",
            root.helperScriptPath,
            "import-photo",
            "--source", cleanPath,
            "--photos-dir", root.photosDir,
            "--checkin-id", checkinId,
            "--date", targetDate
        ]
        photoImportProc.running = true
        return true
    }

    function deleteBodyCheckin(checkinId: string): bool {
        const res = Engine.removeBodyCheckin(root.state, checkinId)
        if (!res.removed)
            return false
        root._commitState(res.state)
        if (res.removed.photoPath && String(res.removed.photoPath).length > 0) {
            root._deletePhotoQueue.push(String(res.removed.photoPath))
            root._drainPhotoDeleteQueue()
        }
        root.statusMessage = "Removed check-in"
        return true
    }

    // ── Two-Way Weekly Planner Sync ──

    function importPlannerWorkout(workoutItem): bool {
        const parsed = (workoutItem && Array.isArray(workoutItem.exercises))
            ? workoutItem
            : Engine.parsePlannerWorkoutEvent(workoutItem)
        if (!parsed)
            return false
        const next = Engine.importPlannerWorkoutIntoDay(root.state, root.selectedDate, parsed)
        root.statusMessage = "Imported workout from Weekly Planner"
        root._commitState(next, root.selectedDate)
        return true
    }

    function syncDayToWeeklyPlanner(dateStr = ""): int {
        if (!HostServices.Events?.ready) {
            root.errorMessage = "Weekly Planner store is not ready yet"
            return 0
        }
        const targetDate = Engine.formatDateStr(dateStr || root.selectedDate)
        const payload = Engine.buildPlannerEventPayload(root.state, targetDate)
        let eventId = Number(payload.plannerEventId) || 0

        if (eventId > 0 && Array.isArray(HostServices.Events.list)
                && HostServices.Events.list.some(ev => Number(ev?.id) === eventId)) {
            HostServices.Events.updateEvent(eventId, {
                title: payload.title,
                description: payload.description,
                dateTime: payload.startIso,
                startDate: payload.startIso,
                endDate: payload.endIso,
                allDay: false
            })
            root.statusMessage = "Updated workout block in Weekly Planner"
            root._plannerTrigger++
            return eventId
        }

        const created = HostServices.Events.addEvent(
            payload.title,
            payload.description,
            payload.startIso,
            payload.category,
            payload.priority,
            15,
            "none",
            payload.endIso,
            false
        )
        if (created && Number(created.id) > 0) {
            eventId = Number(created.id)
            const next = Engine.updateDayMetadata(root.state, targetDate, { plannerEventId: eventId })
            root.statusMessage = "Scheduled workout in Weekly Planner"
            root._commitState(next)
            root._plannerTrigger++
            return eventId
        }
        return 0
    }

    function openInWeeklyPlanner(dateStr = ""): void {
        const targetDate = Engine.formatDateStr(dateStr || root.selectedDate)
        const dt = Engine.parseLocalDate(targetDate)
        GlobalStates.dashboardPlannerBrowser = {
            date: dt.toISOString(),
            followToday: targetDate === root.todayStr,
            sideView: ""
        }
        GlobalStates.dashboardPageId = "weeklyPlanner"
        GlobalStates.dashboardOpen = true
    }

    // ── Nexus Contract & Export ──

    function getDaySummary(dateStr: string): var {
        return Engine.computeDaySummary(root.state, dateStr || root.todayStr)
    }

    function getRecentCheckins(limit = 6): var {
        const maxItems = Math.max(1, Math.min(50, Math.round(Number(limit) || 6)))
        return root.bodyCheckins.slice(0, maxItems)
    }

    function exportWorkoutMarkdown(dateStr = ""): string {
        return Engine.exportWorkoutMarkdown(root.state, dateStr || root.selectedDate)
    }

    function openDashboardTracker(dateStr = ""): void {
        if (dateStr && String(dateStr).trim().length > 0)
            root.selectDate(dateStr)
        GlobalStates.dashboardPageId = "exercisesTracker"
        GlobalStates.dashboardOpen = true
    }

    function openInNexus(): bool {
        const nx = HostServices.AlisIntergration?.nexus ?? HostServices.AlisIntergration?.session?.nexus ?? null
        if (!nx || typeof nx.open !== "function") {
            root.errorMessage = "Enable Alis Nexus in Settings → Integrations first"
            return false
        }
        GlobalStates.dashboardOpen = false
        nx.open()
        return true
    }

    on_WorkoutWriterChanged: {
        if (root.workoutExportPending) {
            root._exportVaultPath = ""
            root.errorMessage = "Nexus was disconnected before the workout export was confirmed"
        }
    }

    Connections {
        target: root._workoutWriter
        function onCaptureFinished(requester, notePath, message) {
            if (requester !== root || !root.workoutExportPending)
                return
            const vault = root._exportVaultPath
            root._exportVaultPath = ""
            if (!notePath.length) {
                root.errorMessage = message || "Could not export workout to Nexus"
                return
            }
            root.errorMessage = ""
            root.statusMessage = "Exported workout note to Alis Nexus"
            const nx = HostServices.AlisIntergration.nexus
            if (nx?.configuredVaultPath === vault && GlobalStates.dashboardOpen
                    && GlobalStates.dashboardPageId === "exercisesTracker" && nx.openNote(notePath))
                GlobalStates.dashboardOpen = false
        }
    }

    function sendWorkoutLogToNexus(dateStr = ""): bool {
        if (root.workoutExportPending)
            return false
        root.statusMessage = ""
        const nx = HostServices.AlisIntergration.nexus
        const writer = root._workoutWriter
        if (!nx || !writer) {
            root.errorMessage = "Enable Alis Nexus in Settings → Integrations first"
            return false
        }
        if (!nx.vaultConfigured) {
            root.errorMessage = "Configure a Nexus vault path before exporting notes"
            return false
        }
        const targetDate = Engine.formatDateStr(dateStr || root.selectedDate)
        const info = Engine.computeDaySummary(root.state, targetDate)
        const title = "Workout " + targetDate + " " + info.title
        root.errorMessage = ""
        root._exportVaultPath = nx.configuredVaultPath
        if (writer.captureFor(root, title, Engine.exportWorkoutMarkdown(root.state, targetDate), root._exportVaultPath))
            return true
        root._exportVaultPath = ""
        root.errorMessage = writer.errorMessage || "Could not start workout export"
        return false
    }

    Component.onDestruction: {
        restTickTimer.stop()
        if (saveDebounceTimer.running || root._savePending) {
            saveDebounceTimer.stop()
            root._savePending = false
            root._writeSerializedNow()
        }
    }
}
