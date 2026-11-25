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
    property string resolvedPhotosDir: ""
    property string resolvedPhotosSource: "local-fallback"
    property string resolvedPhotosVaultRelDir: ""
    property string resolvedPhotosReason: ""
    readonly property string bodyPhotosStorageMode: String(root.preferences?.bodyPhotosStorageMode ?? "auto")
    readonly property string bodyPhotosCustomDir: String(root.preferences?.bodyPhotosCustomDir ?? "")
    readonly property string effectivePhotosDir: root.resolvedPhotosDir.length > 0 ? root.resolvedPhotosDir : root.photosDir
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

    // Rest timer state synced 2-way with TimerService (Timer Edgebar & Bar indicator)
    property int _lastRestTotalSec: 90
    property string _lastRestExerciseName: ""
    property bool _wasCountdownRunning: false
    readonly property var _timerService: HostServices.TimerService ?? null
    readonly property bool _countdownActiveOnService: Boolean(
        root._timerService && (
            root._timerService.countdownRunning
            || (root._timerService.countdownSecondsLeft > 0
                && root._timerService.countdownSecondsLeft < root._timerService.countdownDuration)
        )
    )
    readonly property int restTotalSec: root._countdownActiveOnService
        ? Number(root._timerService.countdownDuration || root._lastRestTotalSec)
        : root._lastRestTotalSec
    readonly property int restRemainingSec: root._countdownActiveOnService
        ? Number(root._timerService.countdownSecondsLeft || 0)
        : 0
    readonly property bool restRunning: Boolean(
        root._timerService && root._timerService.countdownRunning && !root._timerService.countdownPaused
    )
    readonly property bool restPaused: Boolean(
        root._timerService && root._timerService.countdownRunning && root._timerService.countdownPaused
    )
    readonly property string restExerciseName: String(root._timerService?.countdownLabel ?? "").trim()
        || (root._countdownActiveOnService ? root._lastRestExerciseName : "")

    // Nexus exercise catalog & on-demand detail cache
    readonly property var _nexusService: HostServices.AlisIntergration?.nexus
        ?? HostServices.AlisIntergration?.session?.nexus
        ?? null
    readonly property string configuredVaultPath: {
        const fromNexus = String(root._nexusService?.configuredVaultPath ?? "").trim()
        if (fromNexus.length > 0)
            return fromNexus
        const todoNx = String(Config.options?.todo?.nexus?.vaultPath ?? "").trim()
        if (todoNx.length > 0)
            return todoNx
        const todoObs = String(Config.options?.todo?.obsidian?.vaultPath ?? "").trim()
        if (todoObs.length > 0)
            return todoObs
        return String(Config.options?.notes?.zettelkasten?.vaultPath ?? "").trim()
    }
    property var _vaultScannedExercises: []
    property string _lastScannedVaultPath: ""
    property var _exerciseDetailCache: ({})
    property int _detailRevision: 0
    property string _loadingDetailRelPath: ""
    property string _pendingDetailRelPath: ""
    readonly property var nexusExercises: {
        const fromService = root._nexusService?.collections?.exercises
        if (Array.isArray(fromService) && fromService.length > 0)
            return fromService
        return root._vaultScannedExercises
    }

    property bool _dirEnsured: false
    property bool _loadError: false
    property bool _savePending: false
    property bool _writing: false
    property string _lastSavedText: ""
    property var _pendingPhotoRequest: null
    property var _deletePhotoQueue: []
    property bool _photoDirResolveQueued: false
    property int _plannerTrigger: 0
    property bool _syncingPlanner: false
    property bool _initialPlannerReconciled: false
    property var _pendingPlannerSyncDates: []

    signal stateUpdated()
    signal workoutLogged(string dateStr)
    signal bodyCheckinAdded(var checkin)

    onPresentationActiveChanged: {
        if (root.presentationActive)
            root._maybeScanVaultExercises()
    }

    onConfiguredVaultPathChanged: {
        root._exerciseDetailCache = ({})
        root._detailRevision++
        root._vaultScannedExercises = []
        root._lastScannedVaultPath = ""
        root.refreshPhotosDir()
        if (root.presentationActive)
            root._maybeScanVaultExercises()
    }

    onReadyChanged: {
        if (root.ready)
            root.refreshPhotosDir()
    }
    onBodyPhotosStorageModeChanged: root.refreshPhotosDir()
    onBodyPhotosCustomDirChanged: root.refreshPhotosDir()

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
        target: root.ready ? HostServices.Events : null
        function onEventAdded(ev) {
            root._plannerTrigger++
            if (!root._syncingPlanner && (root.preferences?.autoSyncPlanner ?? true))
                root._reconcileSinglePlannerEvent(ev)
        }
        function onEventUpdated(ev) {
            root._plannerTrigger++
            if (!root._syncingPlanner && (root.preferences?.autoSyncPlanner ?? true))
                root._reconcileSinglePlannerEvent(ev)
        }
        function onEventRemoved(id) {
            root._plannerTrigger++
            if (!root._syncingPlanner)
                root._handlePlannerEventRemoved(id)
        }
        function onReadyChanged() {
            root._plannerTrigger++
            if (HostServices.Events?.ready)
                root._maybeReconcileInitialPlannerEvents()
        }
    }

    Connections {
        target: root.presentationActive ? HostServices.CalendarSync : null
        function onEventsUpdated() { root._plannerTrigger++ }
    }

    Connections {
        target: root._timerService
        function onCountdownRunningChanged(): void {
            const nowRunning = Boolean(root._timerService?.countdownRunning)
            if (root._wasCountdownRunning && !nowRunning && Number(root._timerService?.countdownSecondsLeft ?? 0) <= 0) {
                root.statusMessage = root._lastRestExerciseName.length > 0
                    ? ("Rest finished · Ready for next set (" + root._lastRestExerciseName + ")")
                    : "Rest timer complete"
            }
            root._wasCountdownRunning = nowRunning
        }
    }

    Timer {
        id: plannerAutoSyncTimer
        interval: 90
        repeat: false
        onTriggered: root._runPendingPlannerSyncs()
    }

    Timer {
        id: saveDebounceTimer
        interval: 80
        repeat: false
        onTriggered: root._performSave()
    }

    Process {
        id: vaultExercisesScanProc
        running: false
        property string _scanVault: ""
        stdout: StdioCollector {
            id: vaultExercisesScanOut
            onStreamFinished: {
                try {
                    const payload = JSON.parse(String(vaultExercisesScanOut.text ?? "").trim())
                    if (payload && payload.ok === true && Array.isArray(payload.exercises))
                        root._vaultScannedExercises = payload.exercises
                } catch (_err) {}
            }
        }
    }

    Process {
        id: detailProc
        running: false
        property string _activeRelPath: ""
        stdout: StdioCollector { id: detailOut }
        stderr: StdioCollector { id: detailErr }
        onExited: exitCode => {
            const rel = detailProc._activeRelPath
            if (root._loadingDetailRelPath === rel)
                root._loadingDetailRelPath = ""
            try {
                const payload = JSON.parse(String(detailOut.text ?? "").trim())
                if (rel) {
                    const nextCache = Object.assign({}, root._exerciseDetailCache)
                    nextCache[rel] = (exitCode === 0 && payload && payload.ok === true)
                        ? payload
                        : { ok: false, relPath: rel, error: String(payload?.error || "Could not load exercise details") }
                    root._exerciseDetailCache = nextCache
                    root._detailRevision++
                }
            } catch (_err) {
                if (rel) {
                    const errCache = Object.assign({}, root._exerciseDetailCache)
                    errCache[rel] = { ok: false, relPath: rel, error: String(detailErr.text || "Could not parse exercise details").trim().slice(0, 180) }
                    root._exerciseDetailCache = errCache
                    root._detailRevision++
                }
            }
            if (root._pendingDetailRelPath.length > 0) {
                const queued = root._pendingDetailRelPath
                root._pendingDetailRelPath = ""
                root._startDetailFetch(queued)
            }
        }
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
                Qt.callLater(root._maybeReconcileInitialPlannerEvents)
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
                Qt.callLater(root._maybeReconcileInitialPlannerEvents)
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
                Qt.callLater(root._maybeReconcileInitialPlannerEvents)
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
            if (root._savePending)
                saveDebounceTimer.restart()
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
                    photoVaultRel: String(payload.photoVaultRel ?? ""),
                    weightKg: Number(req?.weightKg) || 0,
                    bodyFatPct: Number(req?.bodyFatPct) || 0,
                    note: String(req?.note ?? "")
                })
                if (payload.photosDir && String(payload.photosDir).length > 0)
                    root.resolvedPhotosDir = String(payload.photosDir)
                if (payload.storageSource && String(payload.storageSource).length > 0)
                    root.resolvedPhotosSource = String(payload.storageSource)
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
        id: photosDirResolveProc
        running: false
        stdout: StdioCollector { id: photosDirResolveOut }
        stderr: StdioCollector { id: photosDirResolveErr }
        onExited: exitCode => {
            try {
                const payload = JSON.parse(String(photosDirResolveOut.text ?? "").trim())
                if (exitCode === 0 && payload && payload.ok === true && payload.photosDir) {
                    root.resolvedPhotosDir = String(payload.photosDir)
                    root.resolvedPhotosSource = String(payload.source || "local-fallback")
                    root.resolvedPhotosVaultRelDir = String(payload.vaultRelDir || "")
                    root.resolvedPhotosReason = String(payload.reason || "")
                } else if (payload && payload.error) {
                    root.resolvedPhotosReason = String(payload.error)
                }
            } catch (_err) {
                const errText = String(photosDirResolveErr.text ?? "").trim()
                if (errText.length > 0)
                    root.resolvedPhotosReason = errText.slice(0, 160)
            }
            if (root._photoDirResolveQueued) {
                root._photoDirResolveQueued = false
                root.refreshPhotosDir()
            }
        }
    }

    function refreshPhotosDir(): void {
        if (!root.helperScriptPath.length || !root.photosDir.length)
            return
        if (photosDirResolveProc.running) {
            root._photoDirResolveQueued = true
            return
        }
        root._photoDirResolveQueued = false
        photosDirResolveProc.command = [
            "/usr/bin/python3",
            root.helperScriptPath,
            "resolve-photos-dir",
            "--photos-dir", root.photosDir,
            "--vault", root.configuredVaultPath,
            "--storage-mode", root.bodyPhotosStorageMode,
            "--custom-dir", root.bodyPhotosCustomDir
        ]
        photosDirResolveProc.running = true
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
        const cmd = [
            "/usr/bin/python3",
            root.helperScriptPath,
            "delete-photo",
            "--photo-path", String(nextPath),
            "--photos-dir", root.effectivePhotosDir,
            "--allowed-dir", root.photosDir
        ]
        if (root.resolvedPhotosDir.length > 0 && root.resolvedPhotosDir !== root.effectivePhotosDir) {
            cmd.push("--allowed-dir")
            cmd.push(root.resolvedPhotosDir)
        }
        photoDeleteProc.command = cmd
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
        delete curDay.plannerDetached
        nextDays[target] = curDay
        const nextState = Object.assign({}, root.state, { days: nextDays })
        root.statusMessage = "Copied session from " + prevDates[prevDates.length - 1]
        root._commitState(nextState, target)
        root._schedulePlannerSync(target)
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
        let next = Engine.applyRoutineTemplate(root.state, root.selectedDate, routineKey, replaceExisting)
        next = Engine.updateDayMetadata(next, root.selectedDate, { plannerDetached: false })
        root._commitState(next, root.selectedDate)
        root._schedulePlannerSync(root.selectedDate)
    }

    function addExercise(spec): bool {
        const name = String(spec?.name ?? "").trim()
        if (!name.length)
            return false
        let next = Engine.addExercise(root.state, root.selectedDate, spec)
        next = Engine.updateDayMetadata(next, root.selectedDate, { plannerDetached: false })
        root._commitState(next, root.selectedDate)
        root._schedulePlannerSync(root.selectedDate)
        return true
    }

    function updateExercise(exerciseId: string, patch): void {
        const next = Engine.updateExercise(root.state, root.selectedDate, exerciseId, patch)
        root._commitState(next, root.selectedDate)
        root._schedulePlannerSync(root.selectedDate)
    }

    function toggleExercise(exerciseId: string): void {
        const next = Engine.toggleExercise(root.state, root.selectedDate, exerciseId, new Date().toISOString())
        root._commitState(next, root.selectedDate)
        root._schedulePlannerSync(root.selectedDate)
    }

    function stepExerciseSets(exerciseId: string, delta: int): void {
        const next = Engine.stepCompletedSets(root.state, root.selectedDate, exerciseId, delta, new Date().toISOString())
        root._commitState(next, root.selectedDate)
        root._schedulePlannerSync(root.selectedDate)
        if (delta > 0 && (root.preferences?.autoStartRestOnSet ?? true) && root.presentationActive) {
            const ex = (root.dayPlan?.exercises ?? []).find(item => item.id === exerciseId)
            if (ex && !ex.completed)
                root.startRestTimer(ex.restSec, ex.name)
        }
    }

    function updatePreferences(patch): void {
        const next = Engine.updatePreferences(root.state, patch, root.todayStr)
        root._commitState(next)
        if (patch && (patch.bodyPhotosStorageMode !== undefined || patch.bodyPhotosCustomDir !== undefined))
            root.refreshPhotosDir()
        if (patch && (patch.workoutReminderMinutes !== undefined || patch.workoutDefaultHour !== undefined || patch.workoutDefaultDurationMin !== undefined)) {
            const info = Engine.computeDaySummary(next, root.todayStr)
            if (info && (info.exercises.length > 0 || Number(info.plannerEventId) > 0))
                root._schedulePlannerSync(root.todayStr)
        }
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
        const targetDir = root.effectivePhotosDir
        if (!targetDir.length)
            return
        if (!mkdirProc.running) {
            mkdirProc.command = ["/usr/bin/mkdir", "-p", targetDir]
            mkdirProc.running = true
        }
        Qt.openUrlExternally("file://" + targetDir)
    }

    function removeExercise(exerciseId: string): void {
        const next = Engine.removeExercise(root.state, root.selectedDate, exerciseId)
        root._commitState(next, root.selectedDate)
        root._schedulePlannerSync(root.selectedDate)
    }

    function moveExercise(exerciseId: string, delta: int): void {
        const next = Engine.moveExercise(root.state, root.selectedDate, exerciseId, delta)
        root._commitState(next)
        root._schedulePlannerSync(root.selectedDate)
    }

    function setDayMetadata(patch): void {
        const next = Engine.updateDayMetadata(root.state, root.selectedDate, patch)
        root._commitState(next)
        root._schedulePlannerSync(root.selectedDate)
    }

    function formatExerciseTarget(ex): string {
        return Engine.formatExerciseTarget(ex)
    }

    // ── Rest Timer Controls (Synced with Timer Edgebar / TimerService) ──

    function startRestTimer(seconds = 0, exerciseName = ""): void {
        const total = Math.max(5, Math.min(600, Math.round(Number(seconds) || root.state.preferences?.defaultRestSeconds || 90)))
        root._lastRestTotalSec = total
        root._lastRestExerciseName = String(exerciseName ?? "").trim()
        if (root._timerService && typeof root._timerService.startCountdown === "function") {
            root._timerService.startCountdown(total, root._lastRestExerciseName)
            root._wasCountdownRunning = true
        }
    }

    function toggleRestTimer(): void {
        if (!root._timerService)
            return
        if (root._timerService.countdownRunning
                || (root.restRemainingSec > 0 && root.restRemainingSec < Number(root._timerService.countdownDuration))) {
            root._timerService.toggleCountdown()
            return
        }
        root.startRestTimer(root._lastRestTotalSec, root._lastRestExerciseName)
    }

    function stopRestTimer(): void {
        root._lastRestExerciseName = ""
        root._wasCountdownRunning = false
        if (root._timerService && typeof root._timerService.stopCountdown === "function")
            root._timerService.stopCountdown()
    }

    // ── Nexus Exercise Catalog & Detail Helpers ──

    function _maybeScanVaultExercises(): void {
        const nxList = root._nexusService?.collections?.exercises
        if (Array.isArray(nxList) && nxList.length > 0)
            return
        const vault = root.configuredVaultPath
        if (!vault.length || !root.helperScriptPath.length)
            return
        if (vaultExercisesScanProc.running || root._lastScannedVaultPath === vault)
            return
        root._lastScannedVaultPath = vault
        vaultExercisesScanProc._scanVault = vault
        vaultExercisesScanProc.command = [
            "/usr/bin/python3",
            root.helperScriptPath,
            "scan-exercises",
            "--vault", vault
        ]
        vaultExercisesScanProc.running = true
    }

    function searchExercises(query: string): var {
        void root.revision
        void root.nexusExercises
        return Engine.searchExercisesCatalog(query, root.nexusExercises, root.state, 20)
    }

    function resolveExerciseMetadata(ex): var {
        void root._detailRevision
        void root.nexusExercises
        if (!ex)
            return null
        const matched = Engine.matchNexusExercise(ex, root.nexusExercises)
        const relPath = String(ex.nexusRelPath || matched?.relPath || "").trim()
        const cached = relPath ? (root._exerciseDetailCache[relPath] ?? null) : null
        const basePrimary = Engine.normalizeStringList(
            (cached?.primaryMuscles?.length ?? 0) > 0 ? cached.primaryMuscles
            : ((ex.primaryMuscles?.length ?? 0) > 0 ? ex.primaryMuscles : matched?.muscleGroup)
        )
        const baseSecondary = Engine.normalizeStringList(
            (cached?.secondaryMuscles?.length ?? 0) > 0 ? cached.secondaryMuscles
            : ((ex.secondaryMuscles?.length ?? 0) > 0 ? ex.secondaryMuscles : matched?.secondaryMuscles)
        )
        const primary = basePrimary.length > 0 ? basePrimary : Engine.fallbackMusclesForCategory(ex.category)
        const previewUrl = String(cached?.previewUrl || ex.previewUrl || matched?.posterUrl || "")
        const animationUrl = String(cached?.animationUrl || ex.animationUrl || matched?.featuredImageUrl || "")
        return {
            name: String(cached?.name || ex.name || matched?.title || ""),
            category: String(ex.category || cached?.category || matched?.category || "chest"),
            nexusRelPath: relPath,
            isLinkedToNexus: Boolean(relPath.length > 0 && (matched !== null || cached !== null || String(ex.nexusRelPath || "").length > 0)),
            primaryMuscles: primary,
            secondaryMuscles: baseSecondary,
            equipment: String(cached?.equipment || ex.equipment || matched?.equipment || ""),
            level: String(cached?.level || ex.level || matched?.level || ""),
            force: String(cached?.force || ex.force || matched?.force || ""),
            mechanic: String(cached?.mechanic || ex.mechanic || matched?.mechanic || ""),
            previewUrl: previewUrl,
            animationUrl: animationUrl,
            steps: Array.isArray(cached?.steps) ? cached.steps : [],
            tips: Array.isArray(cached?.tips) ? cached.tips : [],
            loading: Boolean(relPath.length > 0 && root._loadingDetailRelPath === relPath && !cached),
            error: String(cached?.error || "")
        }
    }

    function _startDetailFetch(relPath: string): void {
        const cleanRel = String(relPath ?? "").trim()
        const vault = root.configuredVaultPath
        if (!cleanRel.length || !vault.length || !root.helperScriptPath.length)
            return
        if (root._exerciseDetailCache[cleanRel])
            return
        if (detailProc.running) {
            root._pendingDetailRelPath = cleanRel
            return
        }
        root._loadingDetailRelPath = cleanRel
        detailProc._activeRelPath = cleanRel
        detailProc.command = [
            "/usr/bin/python3",
            root.helperScriptPath,
            "exercise-detail",
            "--vault", vault,
            "--rel-path", cleanRel
        ]
        detailProc.running = true
    }

    function loadExerciseDetail(ex): void {
        if (!ex)
            return
        const matched = Engine.matchNexusExercise(ex, root.nexusExercises)
        const relPath = String(ex.nexusRelPath || matched?.relPath || "").trim()
        if (relPath.length > 0)
            root._startDetailFetch(relPath)
        else
            root._maybeScanVaultExercises()
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
            "--date", targetDate,
            "--vault", root.configuredVaultPath,
            "--storage-mode", root.bodyPhotosStorageMode,
            "--custom-dir", root.bodyPhotosCustomDir
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

    function _schedulePlannerSync(dateStr = ""): void {
        if ((root.preferences?.autoSyncPlanner ?? true) === false)
            return
        const dk = Engine.formatDateStr(dateStr || root.selectedDate)
        if (!root._pendingPlannerSyncDates.includes(dk))
            root._pendingPlannerSyncDates = root._pendingPlannerSyncDates.concat([dk])
        plannerAutoSyncTimer.restart()
    }

    function _runPendingPlannerSyncs(): void {
        if (root._pendingPlannerSyncDates.length === 0)
            return
        if (!HostServices.Events?.ready || (root.preferences?.autoSyncPlanner ?? true) === false)
            return
        const dates = root._pendingPlannerSyncDates.slice()
        root._pendingPlannerSyncDates = []
        for (let i = 0; i < dates.length; i++) {
            const dk = dates[i]
            const dayInfo = Engine.computeDaySummary(root.state, dk)
            const evId = Number(dayInfo?.plannerEventId) || 0
            if (dayInfo && dayInfo.exercises.length > 0) {
                root.syncDayToWeeklyPlanner(dk, true)
            } else if (evId > 0) {
                if (Array.isArray(HostServices.Events.list)
                        && HostServices.Events.list.some(ev => Number(ev?.id) === evId)) {
                    root._syncingPlanner = true
                    try {
                        HostServices.Events.removeEvent(evId)
                    } finally {
                        root._syncingPlanner = false
                    }
                }
                const cleared = Engine.updateDayMetadata(root.state, dk, { plannerEventId: 0, plannerDetached: false })
                root._commitState(cleared, "", true)
                root._plannerTrigger++
            }
        }
    }

    function _handlePlannerEventRemoved(eventId): void {
        const eid = Number(eventId) || 0
        if (eid <= 0 || !root.state?.days)
            return
        const keys = Object.keys(root.state.days)
        for (let i = 0; i < keys.length; i++) {
            const dk = keys[i]
            if (Number(root.state.days[dk]?.plannerEventId) === eid) {
                const next = Engine.updateDayMetadata(root.state, dk, { plannerEventId: 0, plannerDetached: true })
                root._commitState(next, "", true)
                root._plannerTrigger++
            }
        }
    }

    function _reconcileSinglePlannerEvent(ev): void {
        if (!ev || !root.ready || root._syncingPlanner)
            return
        const evId = Number(ev.id) || 0
        const newDk = Engine.formatDateStr(ev.startDate || ev.dateTime)
        let workingState = root.state
        let touchedOld = false
        if (evId > 0 && workingState?.days) {
            const keys = Object.keys(workingState.days)
            for (let i = 0; i < keys.length; i++) {
                const dk = keys[i]
                if (dk !== newDk && Number(workingState.days[dk]?.plannerEventId) === evId) {
                    workingState = Engine.updateDayMetadata(workingState, dk, { plannerEventId: 0 })
                    touchedOld = true
                }
            }
        }
        const isTracked = Engine.isWorkoutPlannerEvent(ev)
            || Boolean(evId > 0 && workingState?.days?.[newDk] && Number(workingState.days[newDk].plannerEventId) === evId)
        if (!isTracked) {
            if (touchedOld)
                root._commitState(workingState, "", true)
            return
        }
        const parsed = Engine.parsePlannerWorkoutEvent(ev)
        if (!parsed) {
            if (touchedOld)
                root._commitState(workingState, "", true)
            return
        }
        const res = Engine.reconcilePlannerWorkoutEvent(workingState, newDk, parsed)
        if (res.changed || touchedOld)
            root._commitState(res.state, "", true)
    }

    function _maybeReconcileInitialPlannerEvents(): void {
        if (!root.ready || !HostServices.Events?.ready)
            return
        if (root._initialPlannerReconciled)
            return
        root._initialPlannerReconciled = true
        if ((root.preferences?.autoSyncPlanner ?? true) === false)
            return
        const evList = Array.isArray(HostServices.Events.list) ? HostServices.Events.list : []
        for (let i = 0; i < evList.length; i++) {
            const ev = evList[i]
            if (Engine.isWorkoutPlannerEvent(ev))
                root._reconcileSinglePlannerEvent(ev)
        }
    }

    function getPlannerFallbackEvents(existingLocalEvents): var {
        void root.revision
        if ((root.preferences?.autoSyncPlanner ?? true) === false)
            return []
        return Engine.buildUnsyncedPlannerEvents(root.state, existingLocalEvents)
    }

    function importPlannerWorkout(workoutItem): bool {
        const parsed = (workoutItem && Array.isArray(workoutItem.exercises))
            ? workoutItem
            : Engine.parsePlannerWorkoutEvent(workoutItem)
        if (!parsed)
            return false
        let next = Engine.importPlannerWorkoutIntoDay(root.state, root.selectedDate, parsed)
        next = Engine.updateDayMetadata(next, root.selectedDate, { plannerDetached: false })
        root.statusMessage = "Imported workout from Weekly Planner"
        root._commitState(next, root.selectedDate)
        return true
    }

    function syncDayToWeeklyPlanner(dateStr = "", skipUndo = false): int {
        if (!HostServices.Events?.ready) {
            root.errorMessage = "Weekly Planner store is not ready yet"
            return 0
        }
        const targetDate = Engine.formatDateStr(dateStr || root.selectedDate)
        const dayInfo = Engine.computeDaySummary(root.state, targetDate)
        if (!dayInfo || dayInfo.exercises.length === 0)
            return 0
        const payload = Engine.buildPlannerEventPayload(root.state, targetDate)
        let eventId = Number(payload.plannerEventId) || 0

        let existingEv = (eventId > 0 && Array.isArray(HostServices.Events.list))
            ? HostServices.Events.list.find(ev => Number(ev?.id) === eventId)
            : null
        if (!existingEv && Array.isArray(HostServices.Events.list)) {
            existingEv = HostServices.Events.list.find(ev =>
                Engine.isWorkoutPlannerEvent(ev)
                && Engine.formatDateStr(ev.startDate || ev.dateTime) === targetDate
            ) ?? null
            if (existingEv)
                eventId = Number(existingEv.id) || 0
        }

        const nowMs = Date.now()
        const payStartMs = new Date(payload.startIso).getTime()
        const payEndMs = new Date(payload.endIso).getTime()
        const allCompleted = dayInfo.totalExercises > 0 && dayInfo.completedExercises >= dayInfo.totalExercises
        const alreadyPastOrDone = !Number.isFinite(payStartMs) || payStartMs <= nowMs || allCompleted
        const effectiveReminder = alreadyPastOrDone ? 0 : Math.max(0, Number(payload.reminderMinutes ?? 15))

        if (existingEv && eventId > 0) {
            const exStartMs = new Date(existingEv.startDate || existingEv.dateTime || "").getTime()
            const exEndMs = new Date(existingEv.endDate || "").getTime()
            const startChanged = exStartMs !== payStartMs
            const endChanged = exEndMs !== payEndMs
            const exRem = Number(existingEv.reminderMinutes ?? 15)
            const existingNotifiedOk = !alreadyPastOrDone
                || (existingEv.notified === true && existingEv.reminderNotified === true)
            const sameContent = String(existingEv.title || "") === payload.title
                && String(existingEv.description || "") === payload.description
                && !startChanged
                && !endChanged
                && exRem === effectiveReminder
                && existingNotifiedOk
            const needLinkPatch = Number(dayInfo.plannerEventId) !== eventId
                || Boolean(root.state?.days?.[targetDate]?.plannerDetached)
            if (!sameContent) {
                const patch = {
                    title: payload.title,
                    description: payload.description,
                    reminderMinutes: effectiveReminder,
                    allDay: false,
                    notified: alreadyPastOrDone ? true : (startChanged ? false : (existingEv.notified === true)),
                    reminderNotified: alreadyPastOrDone ? true : (startChanged ? false : (existingEv.reminderNotified === true))
                }
                if (startChanged || endChanged) {
                    patch.dateTime = payload.startIso
                    patch.startDate = payload.startIso
                    patch.endDate = payload.endIso
                }
                root._syncingPlanner = true
                try {
                    HostServices.Events.updateEvent(eventId, patch)
                } finally {
                    root._syncingPlanner = false
                }
            }
            if (needLinkPatch) {
                const next = Engine.updateDayMetadata(root.state, targetDate, { plannerEventId: eventId, plannerDetached: false })
                root._commitState(next, "", skipUndo)
            }
            root.statusMessage = "Updated workout block in Weekly Planner"
            root._plannerTrigger++
            return eventId
        }

        let created = null
        root._syncingPlanner = true
        try {
            created = HostServices.Events.addEvent(
                payload.title,
                payload.description,
                payload.startIso,
                payload.category,
                payload.priority,
                effectiveReminder,
                "none",
                payload.endIso,
                false
            )
            if (created && Number(created.id) > 0 && alreadyPastOrDone) {
                HostServices.Events.updateEvent(Number(created.id), {
                    notified: true,
                    reminderNotified: true
                })
            }
        } finally {
            root._syncingPlanner = false
        }
        if (created && Number(created.id) > 0) {
            eventId = Number(created.id)
            const next = Engine.updateDayMetadata(root.state, targetDate, { plannerEventId: eventId, plannerDetached: false })
            root.statusMessage = "Scheduled workout in Weekly Planner"
            root._commitState(next, "", skipUndo)
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
        plannerAutoSyncTimer.stop()
        root._runPendingPlannerSyncs()
        if (saveDebounceTimer.running || root._savePending) {
            saveDebounceTimer.stop()
            root._savePending = false
            root._writeSerializedNow()
        }
    }
}
