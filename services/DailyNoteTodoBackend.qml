pragma ComponentBehavior: Bound

import QtQuick
import "."
import qs.services as HostServices
import Quickshell
import Quickshell.Io

/**
 * Independent heading-based Markdown Todo backend.
 *
 * Reads and mutates checkbox lines under one configured Markdown heading.
 * Obsidian and third-party plugins may share the file, but none are required.
 */
Scope {
    id: root
    property bool _live: true
    Component.onDestruction: root._live = false

    property bool active: false
    property string vaultPath: ""
    property string folder: "00_Capture/01_Journal"
    property string noteFormat: "YYYY/MMMM/DD-MM-YYYY-dddd"
    property string plannerHeading: "Tasks"
    property int plannerHeadingLevel: 2
    property int defaultDurationMinutes: 30

    property var list: []
    property bool ready: false
    property bool busy: false
    property string errorCode: ""
    property string errorMessage: ""
    property string noteFullPath: ""
    property string sourceDate: Qt.formatDate(new Date(), "yyyy-MM-dd")
    property var documentMeta: ({})
    property var managedMeta: ({})
    property var migrationPreview: null
    readonly property var capabilities: ({
        backend: "obsidian",
        sourceMode: "markdown-note",
        noteReadable: root.ready,
        noteWritable: root.ready,
        pluginIndependent: true,
        richMutationAvailable: false,
        lastError: root.errorMessage
    })

    signal migrationCommitted(var payload)
    signal migrationFinished(bool success, var payload)
    property string _scanSourceKey: ""
    property string _mutationSourceKey: ""
    property bool _refreshQueued: false

    readonly property bool configured:
        root.active
        && root.vaultPath.trim().length > 0
        && root.noteFormat.trim().length > 0
        && root.plannerHeading.trim().length > 0
        && root.plannerHeadingLevel >= 1
        && root.plannerHeadingLevel <= 6
        && root.defaultDurationMinutes > 0

    readonly property string helperPath:
        decodeURIComponent(String(Qt.resolvedUrl("../scripts/todo/obsidian_daily_todo.py")).replace(/^file:\/\//, ""))
    readonly property string watchPath: root.noteFullPath

    function _sourceKey(): string {
        return [
            root.vaultPath,
            root.folder,
            root.noteFormat,
            root.plannerHeading,
            root.plannerHeadingLevel,
            root.defaultDurationMinutes,
            root.sourceDate
        ].join("\u001f")
    }

    function _sourceArgs(): var {
        return [
            "--vault", root.vaultPath,
            "--folder", root.folder,
            "--format", root.noteFormat,
            "--date", root.sourceDate,
            "--heading", root.plannerHeading,
            "--heading-level", String(root.plannerHeadingLevel),
            "--default-duration", String(root.defaultDurationMinutes)
        ]
    }

    function _setError(code: string, message: string): void {
        root.errorCode = code
        root.errorMessage = message
    }

    function _clearError(): void {
        root.errorCode = ""
        root.errorMessage = ""
    }

    function _clearUnavailable(code: string, message: string): void {
        root.list = []
        root.ready = false
        root.busy = false
        root.noteFullPath = ""
        root.documentMeta = ({})
        root.managedMeta = ({})
        root._setError(code, message)
    }

    function _scheduleRefresh(): void {
        root.migrationPreview = null
        if (!root.configured) {
            configDebounce.stop()
            scanDebounce.stop()
            root._clearUnavailable("", "")
            return
        }
        configDebounce.restart()
    }

    function refresh(): void {
        if (!root.configured) {
            root._clearUnavailable("not_configured", "Markdown Todo source is not configured")
            return
        }
        if (scanProc.running || mutationProc.running) {
            root._refreshQueued = true
            return
        }

        root.busy = true
        root._clearError()
        root._scanSourceKey = root._sourceKey()
        scanProc.command = ["/usr/bin/python3", root.helperPath, "scan"].concat(root._sourceArgs())
        scanProc.running = true
    }

    function reload(): void {
        root.refresh()
    }

    function refreshCapabilities(): void {
        // Markdown source mode intentionally does not need Obsidian or plugin state.
    }

    function initializeSection(): bool {
        root._setError(
            "daily_note_heading_required",
            "Create the configured Markdown note from its normal template so the configured task heading exists"
        )
        return false
    }

    function previewInternal(internalJsonPath: string): bool {
        if (!root.ready)
            return false
        return root._startMutation(
            "preview-migration",
            ["/usr/bin/python3", root.helperPath, "preview-migration"]
                .concat(root._sourceArgs())
                .concat(["--internal-json", String(internalJsonPath ?? "")])
        )
    }

    function migrateInternal(internalJsonPath: string, expectedInternalSha: string): bool {
        if (!root.ready)
            return false
        return root._startMutation(
            "migrate-internal",
            ["/usr/bin/python3", root.helperPath, "migrate-internal"]
                .concat(root._sourceArgs())
                .concat([
                    "--internal-json", String(internalJsonPath ?? ""),
                    "--expected-document-sha", String(root.documentMeta?.sha256 ?? ""),
                    "--expected-section-sha", String(root.managedMeta?.sha256 ?? ""),
                    "--expected-internal-sha", String(expectedInternalSha ?? "")
                ])
        )
    }

    function addTask(text: string, startTime: string, endTime: string): bool {
        const clean = String(text ?? "").trim()
        if (!root.ready || clean.length === 0) {
            root._setError(
                clean.length === 0 ? "invalid_task_text" : "not_ready",
                clean.length === 0 ? "Task text is empty" : "Markdown Todo source is not ready"
            )
            return false
        }
        const args = [
            "/usr/bin/python3", root.helperPath, "add"
        ].concat(root._sourceArgs()).concat([
            "--text", clean,
            "--start-time", String(startTime ?? ""),
            "--end-time", String(endTime ?? ""),
            "--expected-document-sha", String(root.documentMeta?.sha256 ?? ""),
            "--expected-section-sha", String(root.managedMeta?.sha256 ?? "")
        ])
        return root._startMutation("add", args)
    }

    function toggleTask(taskId: string): bool {
        const id = String(taskId ?? "")
        if (!root._taskById(id)) {
            root._setError("conflict", "Task reference is stale")
            return false
        }
        return root._startMutation(
            "toggle",
            ["/usr/bin/python3", root.helperPath, "toggle"]
                .concat(root._sourceArgs())
                .concat([
                    "--id", id,
                    "--expected-document-sha", String(root.documentMeta?.sha256 ?? "")
                ])
        )
    }

    function deleteTask(taskId: string): bool {
        const id = String(taskId ?? "")
        if (!root._taskById(id)) {
            root._setError("conflict", "Task reference is stale")
            return false
        }
        return root._startMutation(
            "delete",
            ["/usr/bin/python3", root.helperPath, "delete"]
                .concat(root._sourceArgs())
                .concat([
                    "--id", id,
                    "--expected-document-sha", String(root.documentMeta?.sha256 ?? "")
                ])
        )
    }

    function _taskById(taskId: string): var {
        for (let i = 0; i < root.list.length; ++i) {
            if (String(root.list[i]?.id ?? "") === taskId)
                return root.list[i]
        }
        return null
    }

    function _startMutation(kind: string, command): bool {
        if (!root.configured || !root.ready) {
            root._setError("not_ready", "Markdown Todo source is not ready")
            return false
        }
        if (mutationProc.running) {
            root._setError("busy", "Another Todo mutation is already in progress")
            return false
        }
        root.busy = true
        root._clearError()
        root._mutationSourceKey = root._sourceKey()
        mutationProc.kind = kind
        mutationProc.command = command
        mutationProc.running = true
        return true
    }

    function _applyPayload(payload): bool {
        if (!payload || payload.ok !== true) {
            const error = payload?.error ?? ({})
            root._clearUnavailable(
                String(error.code ?? "scan_failed"),
                String(error.message ?? "Failed to scan Markdown Todo source")
            )
            return false
        }
        root.list = Array.isArray(payload.tasks) ? payload.tasks : []
        root.noteFullPath = String(payload.noteFullPath ?? "")
        root.sourceDate = String(payload.sourceDate ?? root.sourceDate)
        root.documentMeta = payload.document ?? ({})
        root.managedMeta = payload.managed ?? ({})
        root._clearError()
        root.ready = true
        return true
    }

    function _finishScan(): void {
        root.busy = mutationProc.running
        if (root._refreshQueued && root.configured && !mutationProc.running) {
            root._refreshQueued = false
            Qt.callLater(() => { if (root._live) root.refresh() })
        }
    }

    function _finishMutation(): void {
        root.busy = scanProc.running
        if (root._refreshQueued && root.configured && !scanProc.running) {
            root._refreshQueued = false
            Qt.callLater(() => { if (root._live) root.refresh() })
        }
    }

    function _notifyMigrationFinished(success: bool, payload): void {
        if (mutationProc.kind === "migrate-internal")
            root.migrationFinished(success, payload)
    }

    onActiveChanged: root._scheduleRefresh()
    onVaultPathChanged: root._scheduleRefresh()
    onFolderChanged: root._scheduleRefresh()
    onNoteFormatChanged: root._scheduleRefresh()
    onPlannerHeadingChanged: root._scheduleRefresh()
    onPlannerHeadingLevelChanged: root._scheduleRefresh()
    onDefaultDurationMinutesChanged: root._scheduleRefresh()

    Component.onCompleted: root._scheduleRefresh()

    Timer {
        interval: 60000
        repeat: true
        running: root.configured
        triggeredOnStart: true
        onTriggered: {
            const today = Qt.formatDate(new Date(), "yyyy-MM-dd")
            if (today !== root.sourceDate) {
                root.sourceDate = today
                root._scheduleRefresh()
            }
        }
    }

    FileView {
        id: noteWatcher
        path: root.watchPath
        preload: false
        printErrors: false
        watchChanges: root.configured && root.watchPath.length > 0
        onFileChanged: {
            if (root.configured)
                scanDebounce.restart()
        }
    }

    Timer {
        id: configDebounce
        interval: 80
        repeat: false
        onTriggered: root.refresh()
    }

    Timer {
        id: scanDebounce
        interval: 250
        repeat: false
        onTriggered: root.refresh()
    }

    Timer {
        id: scanTimeout
        interval: 5000
        repeat: false
        onTriggered: {
            if (!scanProc.running)
                return
            scanProc.timedOut = true
            scanProc.running = false
        }
    }

    Timer {
        id: mutationTimeout
        interval: 8000
        repeat: false
        onTriggered: {
            if (!mutationProc.running)
                return
            mutationProc.timedOut = true
            mutationProc.running = false
        }
    }

    Process {
        id: scanProc
        running: false
        property bool startObserved: false
        property bool timedOut: false
        stdout: StdioCollector { id: scanCollector }

        onRunningChanged: {
            if (scanProc.running) {
                scanProc.startObserved = false
                return
            }
            if (scanProc.startObserved)
                return
            scanTimeout.stop()
            root._clearUnavailable("scanner_start_failed", "Failed to start Markdown Todo scanner")
            root._finishScan()
        }

        onStarted: {
            scanProc.startObserved = true
            scanProc.timedOut = false
            scanTimeout.restart()
        }

        onExited: (exitCode, exitStatus) => {
            scanTimeout.stop()
            if (!root.configured || root._scanSourceKey !== root._sourceKey()) {
                root._refreshQueued = root.configured
                root._finishScan()
                return
            }
            if (scanProc.timedOut) {
                root._clearUnavailable("scanner_timeout", "Markdown Todo scanner timed out")
                root._finishScan()
                return
            }
            const output = String(scanCollector.text ?? "").trim()
            if (output.length === 0) {
                root._clearUnavailable("scanner_failed", "Markdown Todo scanner returned no result")
                root._finishScan()
                return
            }
            try {
                root._applyPayload(JSON.parse(output))
            } catch (error) {
                root._clearUnavailable("scanner_invalid_output", "Markdown Todo scanner returned invalid JSON")
            }
            root._finishScan()
        }
    }

    Process {
        id: mutationProc
        running: false
        property bool startObserved: false
        property bool timedOut: false
        property string kind: ""
        stdout: StdioCollector { id: mutationCollector }

        onRunningChanged: {
            if (mutationProc.running) {
                mutationProc.startObserved = false
                return
            }
            if (mutationProc.startObserved)
                return
            mutationTimeout.stop()
            root._setError("mutation_start_failed", "Failed to start Markdown Todo mutation helper")
            root._notifyMigrationFinished(false, null)
            root._finishMutation()
        }

        onStarted: {
            mutationProc.startObserved = true
            mutationProc.timedOut = false
            mutationTimeout.restart()
        }

        onExited: (exitCode, exitStatus) => {
            mutationTimeout.stop()
            if (!root.configured || root._mutationSourceKey !== root._sourceKey()) {
                root._refreshQueued = root.configured
                root._notifyMigrationFinished(false, null)
                root._finishMutation()
                return
            }
            if (mutationProc.timedOut) {
                root._setError("mutation_timeout", "Markdown Todo mutation timed out")
                root._notifyMigrationFinished(false, null)
                root._finishMutation()
                return
            }
            const output = String(mutationCollector.text ?? "").trim()
            if (output.length === 0) {
                root._setError("mutation_failed", "Markdown Todo mutation returned no result")
                root._notifyMigrationFinished(false, null)
                root._finishMutation()
                return
            }
            try {
                const payload = JSON.parse(output)
                if (payload?.ok === true) {
                    if (mutationProc.kind === "preview-migration") {
                        root.migrationPreview = payload
                        root._clearError()
                        root._finishMutation()
                        return
                    }
                    const committedMigration = mutationProc.kind === "migrate-internal"
                    root._applyPayload(payload)
                    root._finishMutation()
                    if (committedMigration) {
                        root._notifyMigrationFinished(true, payload)
                        root.migrationCommitted(payload)
                    }
                    return
                }

                const error = payload?.error ?? ({})
                const code = String(error.code ?? "mutation_failed")
                root._setError(code, String(error.message ?? "Markdown Todo mutation failed"))
                root._notifyMigrationFinished(false, payload)
                if (code === "conflict" || code === "migration_source_conflict")
                    root._refreshQueued = true
            } catch (error) {
                root._setError("mutation_invalid_output", "Markdown Todo mutation returned invalid JSON")
                root._notifyMigrationFinished(false, null)
            }
            root._finishMutation()
        }
    }
}
