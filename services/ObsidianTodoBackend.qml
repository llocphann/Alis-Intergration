pragma ComponentBehavior: Bound

import QtQuick
import "."
import qs.services as HostServices
import Quickshell
import Quickshell.Io

/**
 * Obsidian Markdown backend for HostServices.Todo.
 *
 * Canonical reads and basic structural writes go through obsidian_todo.py.
 * Runtime/Tasks capability and rich completion semantics go through
 * obsidian_tasks.py. The latter guarantees that the official Obsidian CLI is
 * never invoked unless an already-running desktop process was detected.
 *
 * This component remains dormant until the Todo facade selects it.
 */
Scope {
    id: root
    property bool _live: true
    Component.onDestruction: root._live = false

    property bool active: false
    property string vaultPath: ""
    property string notePath: ""
    property bool preferTasksPlugin: true
    property bool allowBasicOfflineMutation: true

    property var list: []
    property bool ready: false
    property bool busy: false
    property bool capabilityBusy: false
    property string errorCode: ""
    property string errorMessage: ""
    property string noteFullPath: ""
    property var documentMeta: ({})
    property var managedMeta: ({})
    property var capabilities: root._emptyCapabilities()
    property var migrationPreview: null

    signal migrationCommitted(var payload)
    signal migrationFinished(bool success, var payload)
    signal agendaMutationFinished(bool success,var payload)
    function ensureAgenda(event): bool {return root._agendaMutation("ensure",event)}
    function unlinkAgenda(link): bool {return root._agendaMutation("unlink",link)}
    function deleteAgenda(link): bool {return root._agendaMutation("delete",link)}
    function _agendaMutation(operation,event): bool {
        if(!root.ready || root.busy || !root.allowBasicOfflineMutation)return false
        root.busy=true
        if(agendaJob.execute(operation,event))return true
        root._finishMutation();return false
    }
    AgendaTaskMutation {
        id:agendaJob
        mode:"managed"
        sourceArgs:["--vault",root.vaultPath,"--note",root.notePath]
        configured:root.configured
        onFinished:(success,payloadJson)=>{
            const payload=JSON.parse(payloadJson)
            if(success)root._applyScanPayload(payload)
            else root._setError(String(payload?.error?.code || "agenda_failed"),String(payload?.error?.message || "To-do link pending"))
            root.agendaMutationFinished(success,payload)
            root._finishMutation()
        }
    }

    property bool _refreshQueued: false
    property string _scanVaultPath: ""
    property string _scanNotePath: ""
    property string _capabilityVaultPath: ""
    property string _capabilityNotePath: ""
    property string _mutationVaultPath: ""
    property string _mutationNotePath: ""
    property var _pendingMutation: null

    readonly property bool configured:
        root.active
        && root.vaultPath.trim().length > 0
        && root.notePath.trim().length > 0

    readonly property string helperPath:
        decodeURIComponent(String(Qt.resolvedUrl("../scripts/todo/obsidian_todo.py")).replace(/^file:\/\//, ""))
    readonly property string runtimeHelperPath:
        decodeURIComponent(String(Qt.resolvedUrl("../scripts/todo/obsidian_tasks.py")).replace(/^file:\/\//, ""))

    readonly property string watchPath: {
        if (!root.configured)
            return ""
        // Once the scanner has canonicalized the note, watch the physical path
        // it returned. This also makes ~/... vault configuration work even
        // though FileView itself does not perform shell tilde expansion.
        if (root.noteFullPath.length > 0)
            return root.noteFullPath
        const base = root.vaultPath.endsWith("/")
            ? root.vaultPath.slice(0, -1)
            : root.vaultPath
        const note = root.notePath.startsWith("/")
            ? root.notePath.slice(1)
            : root.notePath
        return base + "/" + note
    }

    function _emptyCapabilities(): var {
        return {
            backend: "obsidian",
            noteReadable: false,
            noteWritable: false,
            obsidianInstalled: false,
            obsidianRunning: false,
            cliRegistered: false,
            cliResponsive: false,
            activeVaultPath: "",
            activeVaultBasePath: "",
            activeVaultMatches: false,
            tasksPluginInstalled: false,
            tasksPluginEnabled: false,
            tasksPluginVersion: "",
            tasksApiAvailable: false,
            richMutationAvailable: false,
            tasksSettings: null,
            lastError: ""
        }
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
        root._setError(code, message)
        root.noteFullPath = ""
        root.documentMeta = ({})
        root.managedMeta = ({})
        const caps = root._emptyCapabilities()
        caps.lastError = message
        root.capabilities = caps
    }

    function _scheduleRefresh(): void {
        // A queued action belongs to the exact source that was visible when
        // the user invoked it. Never carry it across backend activation, vault
        // or note changes (especially Add, which has no task-id CAS guard).
        root._pendingMutation = null
        root.migrationPreview = null

        if (!root.configured) {
            configDebounce.stop()
            scanDebounce.stop()
            capabilityDebounce.stop()
            root._clearUnavailable("", "")
            return
        }
        configDebounce.restart()
        capabilityDebounce.restart()
    }

    function _capabilitySourceCurrent(): bool {
        return root.configured
            && root._capabilityVaultPath === root.vaultPath
            && root._capabilityNotePath === root.notePath
    }

    function _mutationSourceCurrent(): bool {
        return root.configured
            && root._mutationVaultPath === root.vaultPath
            && root._mutationNotePath === root.notePath
    }

    function refresh(): void {
        if (!root.configured) {
            root._clearUnavailable("not_configured", "Obsidian Todo source is not configured")
            return
        }
        if (scanProc.running || mutationProc.running || agendaJob.busy) {
            root._refreshQueued = true
            return
        }

        root.busy = true
        root._clearError()
        root._scanVaultPath = root.vaultPath
        root._scanNotePath = root.notePath
        scanProc.command = [
            "/usr/bin/python3",
            root.helperPath,
            "scan",
            "--vault", root.vaultPath,
            "--note", root.notePath
        ]
        scanProc.running = true
    }

    function reload(): void {
        root.refresh()
        root.refreshCapabilities()
    }

    function refreshCapabilities(): void {
        if (!root.configured) {
            root.capabilities = root._emptyCapabilities()
            return
        }
        if (capabilityProc.running)
            return

        root.capabilityBusy = true
        root._capabilityVaultPath = root.vaultPath
        root._capabilityNotePath = root.notePath
        capabilityProc.command = [
            "/usr/bin/python3",
            root.runtimeHelperPath,
            "probe-capabilities",
            "--vault", root.vaultPath
        ]
        capabilityProc.running = true
    }

    function _finishScan(): void {
        root.busy = mutationProc.running || agendaJob.busy
        if (root._refreshQueued && root.configured && !mutationProc.running) {
            root._refreshQueued = false
            Qt.callLater(() => { if (root._live) root.refresh() })
        }
    }

    function _applyScanPayload(payload): bool {
        if (!payload || payload.ok !== true) {
            const error = payload?.error ?? ({})
            root._clearUnavailable(
                String(error.code ?? "scan_failed"),
                String(error.message ?? "Failed to scan Obsidian Todo note")
            )
            return false
        }

        root.migrationPreview = null
        root.list = Array.isArray(payload.tasks) ? payload.tasks : []
        root.noteFullPath = String(payload.noteFullPath ?? "")
        root.documentMeta = payload.document ?? ({})
        root.managedMeta = payload.managed ?? ({})
        root._clearError()
        root.ready = true

        const caps = Object.assign({}, root.capabilities ?? root._emptyCapabilities())
        caps.backend = "obsidian"
        caps.noteReadable = true
        caps.noteWritable = true
        root.capabilities = caps
        root._applyTasksStatusSemantics()
        return true
    }

    function _taskById(taskId: string): var {
        for (let i = 0; i < root.list.length; ++i) {
            if (String(root.list[i]?.id ?? "") === taskId)
                return root.list[i]
        }
        return null
    }

    function _queueMutation(action): bool {
        if (!root.configured || !root.ready) {
            root._setError("not_ready", "Obsidian Todo source is not ready")
            return false
        }
        if (mutationProc.running || root._pendingMutation !== null) {
            root._setError("busy", "Another Todo mutation is already in progress")
            return false
        }
        root._pendingMutation = action
        root._clearError()
        root.refreshCapabilities()
        if (!capabilityProc.running)
            Qt.callLater(() => { if (root._live) root._dispatchPendingMutation() })
        return true
    }

    function initializeSection(): bool {
        if (!root.configured) {
            root._setError("not_configured", "Obsidian Todo source is not configured")
            return false
        }
        if (mutationProc.running || root._pendingMutation !== null) {
            root._setError("busy", "Another Todo mutation is already in progress")
            return false
        }
        root._startMutation("initialize-section", [
            "/usr/bin/python3", root.helperPath,
            "initialize-section",
            "--vault", root.vaultPath,
            "--note", root.notePath
        ], "")
        return true
    }

    function _migrationGlobalFilter(): string {
        if (!root.preferTasksPlugin || !root._tasksSettingsKnown())
            return ""
        return String(root.capabilities.tasksSettings?.globalFilter ?? "").trim()
    }

    function previewInternal(internalJsonPath: string): bool {
        if (!root.configured || !root.ready) {
            root._setError("not_ready", "Obsidian Todo source is not ready")
            return false
        }
        if (mutationProc.running || root._pendingMutation !== null) {
            root._setError("busy", "Another Todo operation is already in progress")
            return false
        }

        const command = [
            "/usr/bin/python3", root.helperPath,
            "preview-migration",
            "--vault", root.vaultPath,
            "--note", root.notePath,
            "--internal-json", String(internalJsonPath ?? "")
        ]
        const filter = root._migrationGlobalFilter()
        if (filter.length > 0)
            command.push("--global-filter", filter)
        root._startMutation("preview-migration", command, "")
        return true
    }

    function migrateInternal(internalJsonPath: string, expectedInternalSha: string): bool {
        if (!root.configured || !root.ready) {
            root._setError("not_ready", "Obsidian Todo source is not ready")
            return false
        }
        if (mutationProc.running || root._pendingMutation !== null) {
            root._setError("busy", "Another Todo mutation is already in progress")
            return false
        }

        const command = [
            "/usr/bin/python3", root.helperPath,
            "migrate-internal",
            "--vault", root.vaultPath,
            "--note", root.notePath,
            "--internal-json", String(internalJsonPath ?? ""),
            "--expected-document-sha", String(root.documentMeta?.sha256 ?? ""),
            "--expected-managed-sha", String(root.managedMeta?.sha256 ?? "")
        ]
        const sourceSha = String(expectedInternalSha ?? "").trim()
        if (sourceSha.length > 0)
            command.push("--expected-internal-sha", sourceSha)
        const filter = root._migrationGlobalFilter()
        if (filter.length > 0)
            command.push("--global-filter", filter)
        root._startMutation("migrate-internal", command, "")
        return true
    }

    function addTask(text: string): bool {
        const clean = String(text ?? "").trim()
        if (clean.length === 0) {
            root._setError("invalid_task_text", "Task text is empty")
            return false
        }
        return root._queueMutation({ kind: "add", text: clean })
    }

    function toggleTask(taskId: string): bool {
        const id = String(taskId ?? "")
        if (!root._taskById(id)) {
            root._setError("conflict", "Task reference is stale")
            return false
        }
        return root._queueMutation({ kind: "toggle", taskId: id })
    }

    function deleteTask(taskId: string): bool {
        const id = String(taskId ?? "")
        if (!root._taskById(id)) {
            root._setError("conflict", "Task reference is stale")
            return false
        }
        return root._queueMutation({ kind: "delete", taskId: id })
    }

    function _tasksSettingsKnown(): bool {
        return root.capabilities?.tasksSettings !== null
            && root.capabilities?.tasksSettings !== undefined
    }

    function _applyTasksStatusSemantics(): void {
        if (!root._tasksSettingsKnown() || !Array.isArray(root.list))
            return

        const statuses = root.capabilities?.tasksSettings?.statuses
        if (!Array.isArray(statuses))
            return

        const bySymbol = ({})
        for (let i = 0; i < statuses.length; ++i) {
            const status = statuses[i] ?? ({})
            const symbol = String(status.symbol ?? "")
            if (symbol.length === 1)
                bySymbol[symbol] = String(status.type ?? "TODO")
        }

        const enriched = []
        for (let i = 0; i < root.list.length; ++i) {
            const item = Object.assign({}, root.list[i] ?? ({}))
            const symbol = String(item.statusChar ?? " ")
            const statusType = String(bySymbol[symbol] ?? "TODO")
            item.statusType = statusType
            item.done = statusType === "DONE"
            enriched.push(item)
        }
        root.list = enriched
    }

    function _taskNeedsTasks(task): bool {
        if (!root.preferTasksPlugin)
            return false

        // A live probe that proves Tasks is disabled is sufficient to allow a
        // structural space/x toggle. Unknown/offline state fails closed.
        if (root.capabilities?.obsidianRunning === true
                && root.capabilities?.cliResponsive === true
                && root.capabilities?.tasksPluginEnabled === false)
            return false

        if (!root._tasksSettingsKnown())
            return true

        const filter = String(root.capabilities.tasksSettings?.globalFilter ?? "")
        if (filter.length === 0)
            return true
        return String(task?.rawLine ?? "").includes(filter)
    }

    function _offlineBasicAllowed(): bool {
        return root.capabilities?.obsidianRunning === true
            || root.allowBasicOfflineMutation
    }

    function _dispatchPendingMutation(): void {
        if (root._pendingMutation === null || mutationProc.running)
            return

        const action = root._pendingMutation
        root._pendingMutation = null

        if (!root._offlineBasicAllowed()
                && action.kind !== "toggle"
                && root.capabilities?.obsidianRunning !== true) {
            root._setError(
                "offline_mutation_disabled",
                "Basic Todo mutation while Obsidian is closed is disabled"
            )
            return
        }

        if (action.kind === "add") {
            let text = String(action.text ?? "").trim()
            if (root.preferTasksPlugin && root._tasksSettingsKnown()) {
                const filter = String(root.capabilities.tasksSettings?.globalFilter ?? "")
                if (filter.length > 0 && !text.includes(filter))
                    text = filter + " " + text
            }
            root._startMutation("add-basic", [
                "/usr/bin/python3", root.helperPath,
                "add-basic",
                "--vault", root.vaultPath,
                "--note", root.notePath,
                "--text", text,
                "--expected-document-sha", String(root.documentMeta?.sha256 ?? ""),
                "--expected-managed-sha", String(root.managedMeta?.sha256 ?? "")
            ], "")
            return
        }

        const task = root._taskById(String(action.taskId ?? ""))
        if (!task) {
            root._setError("conflict", "Task reference became stale before mutation")
            root.refresh()
            return
        }

        if (action.kind === "delete") {
            root._startMutation("delete", [
                "/usr/bin/python3", root.helperPath,
                "delete",
                "--vault", root.vaultPath,
                "--note", root.notePath,
                "--id", String(task.id),
                "--expected-document-sha", String(root.documentMeta?.sha256 ?? "")
            ], String(task.id))
            return
        }

        if (action.kind === "toggle") {
            if (root._taskNeedsTasks(task)) {
                if (root.capabilities?.richMutationAvailable !== true) {
                    root._setError(
                        "rich_mutation_unavailable",
                        "This task requires Obsidian Tasks with the configured vault active"
                    )
                    return
                }
                root._startRichToggle(task, false)
                return
            }

            if (!root._offlineBasicAllowed()) {
                root._setError(
                    "offline_mutation_disabled",
                    "Basic Todo mutation while Obsidian is closed is disabled"
                )
                return
            }

            root._startMutation("toggle-basic", [
                "/usr/bin/python3", root.helperPath,
                "toggle-basic",
                "--vault", root.vaultPath,
                "--note", root.notePath,
                "--id", String(task.id),
                "--expected-document-sha", String(root.documentMeta?.sha256 ?? "")
            ], String(task.id))
        }
    }

    function _startRichToggle(task, retry: bool): void {
        root._startMutation(retry ? "toggle-tasks-retry" : "toggle-tasks", [
            "/usr/bin/python3", root.runtimeHelperPath,
            "toggle-tasks",
            "--vault", root.vaultPath,
            "--note", root.notePath,
            "--id", String(task.id),
            "--expected-document-sha", String(root.documentMeta?.sha256 ?? "")
        ], String(task.id))
    }

    function _startMutation(kind: string, command, taskId: string): void {
        if (mutationProc.running || agendaJob.busy) {
            root._setError("busy", "Another Todo mutation is already in progress")
            return
        }
        root.busy = true
        root._clearError()
        root._mutationVaultPath = root.vaultPath
        root._mutationNotePath = root.notePath
        mutationProc.kind = kind
        mutationProc.taskId = taskId
        mutationProc.command = command
        mutationProc.running = true
    }

    function _finishMutation(): void {
        root.busy = scanProc.running || agendaJob.busy
        if (root._refreshQueued && root.configured && !scanProc.running) {
            root._refreshQueued = false
            Qt.callLater(() => { if (root._live) root.refresh() })
        }
    }

    function _notifyMigrationFinished(success: bool, payload): void {
        if (mutationProc.kind === "migrate-internal")
            root.migrationFinished(success, payload)
    }

    function _handleMutationPayload(payload): void {
        if (payload?.ok === true) {
            if (mutationProc.kind === "preview-migration") {
                root.migrationPreview = payload
                root._clearError()
                root._finishMutation()
                return
            }

            const committedMigration = mutationProc.kind === "migrate-internal"
            root._applyScanPayload(payload)
            root._finishMutation()
            if (committedMigration) {
                root._notifyMigrationFinished(true, payload)
                root.migrationCommitted(payload)
            }
            return
        }

        const error = payload?.error ?? ({})
        const code = String(error.code ?? "mutation_failed")
        const message = String(error.message ?? "Todo mutation failed")

        // The basic helper has the final structural say. If it discovers rich
        // metadata that QML intentionally does not try to parse, retry once
        // through Tasks only when the live capability probe proved it safe.
        if (code === "rich_task_required"
                && mutationProc.kind === "toggle-basic"
                && root.capabilities?.richMutationAvailable === true) {
            const task = root._taskById(mutationProc.taskId)
            if (task) {
                root.busy = false
                Qt.callLater(() => { if (root._live) root._startRichToggle(task, true) })
                return
            }
        }

        root._setError(code, message)
        root._notifyMigrationFinished(false, payload)
        root._finishMutation()
        if (code === "conflict")
            root.refresh()
    }

    onActiveChanged: root._scheduleRefresh()
    onVaultPathChanged: root._scheduleRefresh()
    onNotePathChanged: root._scheduleRefresh()

    Component.onCompleted: root._scheduleRefresh()

    FileView {
        id: noteWatcher
        path: root.watchPath
        preload: false
        printErrors: false
        watchChanges: root.configured

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
        id: capabilityDebounce
        interval: 120
        repeat: false
        onTriggered: root.refreshCapabilities()
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
        id: capabilityTimeout
        interval: 6500
        repeat: false
        onTriggered: {
            if (!capabilityProc.running)
                return
            capabilityProc.timedOut = true
            capabilityProc.running = false
        }
    }

    Timer {
        id: mutationTimeout
        interval: 11000
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
            root._clearUnavailable("scanner_start_failed", "Failed to start Obsidian Todo scanner")
            root._finishScan()
        }

        onStarted: {
            scanProc.startObserved = true
            scanProc.timedOut = false
            scanTimeout.restart()
        }

        onExited: (exitCode, exitStatus) => {
            scanTimeout.stop()
            if (!root.configured
                    || root._scanVaultPath !== root.vaultPath
                    || root._scanNotePath !== root.notePath) {
                root._refreshQueued = root.configured
                root._finishScan()
                return
            }
            if (scanProc.timedOut) {
                root._clearUnavailable("scanner_timeout", "Obsidian Todo scanner timed out")
                root._finishScan()
                return
            }

            const output = String(scanCollector.text ?? "").trim()
            if (output.length === 0) {
                root._clearUnavailable("scanner_failed", "Obsidian Todo scanner exited without a result")
                root._finishScan()
                return
            }
            try {
                if (root._applyScanPayload(JSON.parse(output)))
                    capabilityDebounce.restart()
            } catch (error) {
                root._clearUnavailable("scanner_invalid_output", "Obsidian Todo scanner returned invalid JSON")
            }
            root._finishScan()
        }
    }

    Process {
        id: capabilityProc
        running: false
        property bool startObserved: false
        property bool timedOut: false

        stdout: StdioCollector { id: capabilityCollector }

        onRunningChanged: {
            if (capabilityProc.running) {
                capabilityProc.startObserved = false
                return
            }
            if (capabilityProc.startObserved)
                return
            capabilityTimeout.stop()
            root.capabilityBusy = false
            if (!root._capabilitySourceCurrent()) {
                if (root.configured)
                    capabilityDebounce.restart()
                return
            }
            const caps = root._emptyCapabilities()
            caps.lastError = "Failed to start Obsidian capability helper"
            root.capabilities = caps
            root._dispatchPendingMutation()
        }

        onStarted: {
            capabilityProc.startObserved = true
            capabilityProc.timedOut = false
            capabilityTimeout.restart()
        }

        onExited: (exitCode, exitStatus) => {
            capabilityTimeout.stop()
            root.capabilityBusy = false

            // The eval result belongs to the source captured at launch. A
            // config edit while it was running must not authorize a mutation
            // or overwrite capability state for the newly selected note.
            if (!root._capabilitySourceCurrent()) {
                if (root.configured)
                    capabilityDebounce.restart()
                return
            }

            if (capabilityProc.timedOut) {
                const caps = root._emptyCapabilities()
                caps.lastError = "Obsidian capability probe timed out"
                root.capabilities = caps
                root._dispatchPendingMutation()
                return
            }

            const output = String(capabilityCollector.text ?? "").trim()
            if (output.length === 0) {
                const caps = root._emptyCapabilities()
                caps.lastError = "Obsidian capability helper returned no result"
                root.capabilities = caps
                root._dispatchPendingMutation()
                return
            }

            try {
                const payload = JSON.parse(output)
                if (payload?.ok === true) {
                    payload.backend = "obsidian"
                    payload.noteReadable = root.ready
                    payload.noteWritable = root.ready
                    root.capabilities = payload
                    root._applyTasksStatusSemantics()
                } else {
                    const caps = root._emptyCapabilities()
                    caps.lastError = String(payload?.error?.message ?? "Obsidian capability probe failed")
                    root.capabilities = caps
                }
            } catch (error) {
                const caps = root._emptyCapabilities()
                caps.lastError = "Obsidian capability helper returned invalid JSON"
                root.capabilities = caps
            }
            root._dispatchPendingMutation()
        }
    }

    Process {
        id: mutationProc
        running: false
        property bool startObserved: false
        property bool timedOut: false
        property string kind: ""
        property string taskId: ""

        stdout: StdioCollector { id: mutationCollector }

        onRunningChanged: {
            if (mutationProc.running) {
                mutationProc.startObserved = false
                return
            }
            if (mutationProc.startObserved)
                return
            mutationTimeout.stop()
            if (!root._mutationSourceCurrent()) {
                root._refreshQueued = root.configured
                root._notifyMigrationFinished(false, null)
                root._finishMutation()
                return
            }
            root._setError("mutation_start_failed", "Failed to start Todo mutation helper")
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

            // A mutation may already have reached the old canonical note, but
            // its result must never be applied to a newly selected source.
            // Refresh the new source instead; filesystem scan remains
            // authoritative for whichever backend is currently active.
            if (!root._mutationSourceCurrent()) {
                root._refreshQueued = root.configured
                root._notifyMigrationFinished(false, null)
                root._finishMutation()
                return
            }

            if (mutationProc.timedOut) {
                root._setError("mutation_timeout", "Todo mutation timed out")
                root._notifyMigrationFinished(false, null)
                root._finishMutation()
                return
            }

            const output = String(mutationCollector.text ?? "").trim()
            if (output.length === 0) {
                root._setError("mutation_failed", "Todo mutation helper returned no result")
                root._notifyMigrationFinished(false, null)
                root._finishMutation()
                return
            }

            try {
                root._handleMutationPayload(JSON.parse(output))
            } catch (error) {
                root._setError("mutation_invalid_output", "Todo mutation helper returned invalid JSON")
                root._notifyMigrationFinished(false, null)
                root._finishMutation()
            }
        }
    }
}
