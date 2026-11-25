pragma ComponentBehavior: Bound

import QtQuick
import qs.services as HostServices
import Quickshell
import Quickshell.Io
import qs.modules.common

/**
 * Filesystem-canonical Zettelkasten quick-note capture.
 *
 * Uses HostServices.Todo.sharedVaultPath, the same resolved vault as the Todo backends.
 * Legacy Quick Notes vault overrides are handled centrally by HostServices.Todo.
 * No external process/plugin is needed.
 */
Item {
    id: root

    readonly property string configuredVaultPath: HostServices.Todo.sharedVaultPath
    readonly property string folder:
        String(Config.options?.notes?.zettelkasten?.folder
            ?? "00_Capture/03_Zettelkasten")
    readonly property string defaultType:
        String(Config.options?.notes?.zettelkasten?.defaultType ?? "Fleeting")
    readonly property bool ready:
        root.configuredVaultPath.length > 0 && root.folder.trim().length > 0

    property bool busy: false
    property string errorCode: ""
    property string errorMessage: ""
    property string lastCreatedPath: ""
    property string lastCreatedFullPath: ""

    property string helperPath:
        decodeURIComponent(String(Qt.resolvedUrl("../scripts/notes/zettelkasten.py")).replace(/^file:\/\//, ""))

    property QtObject _captureRequester: null
    signal captured(var payload)
    signal captureFinished(QtObject requester, string notePath, string message)

    function _setError(code: string, message: string): void {
        root.errorCode = code
        root.errorMessage = message
    }

    function _clearError(): void {
        root.errorCode = ""
        root.errorMessage = ""
    }

    function capture(title, body): bool {
        return root.captureWithAttachments(title, body, "")
    }

    function captureWithAttachments(title, body, attachmentRoot): bool {
        return root._beginCapture(title, body, attachmentRoot, null, root.configuredVaultPath)
    }

    function captureFor(requester: QtObject, title: string, body: string, vaultPath: string): bool {
        return root._beginCapture(title, body, "", requester, vaultPath)
    }

    function _beginCapture(title, body, attachmentRoot, requester, vaultPath): bool {
        const content = String(body ?? "")
        if (!vaultPath.length || !root.folder.trim().length) {
            root._setError(
                "not_configured",
                "Configure a Nexus vault before saving a Zettelkasten quick note"
            )
            return false
        }
        if (root.busy || captureProc.running) {
            root._setError("busy", "Another Zettelkasten note is being saved")
            return false
        }
        if (content.trim().length === 0 && String(title ?? "").trim().length === 0) {
            root._setError("empty_note", "Quick note is empty")
            return false
        }

        root._captureRequester = requester
        root.busy = true
        root._clearError()
        captureProc.command = [
            "/usr/bin/python3", root.helperPath,
            "--vault", vaultPath,
            "--folder", root.folder,
            "--title", String(title ?? ""),
            "--body", content,
            "--type", root.defaultType,
            "--attachment-root", String(attachmentRoot ?? ""),
            "--config-path", String(Config.options?.integrations?.nexus?.configPath ?? "")
        ]
        captureProc.running = true
        return true
    }

    function _finishCapture(payload, code, message): void {
        if (!root.busy)
            return
        const requester = root._captureRequester
        root._captureRequester = null
        if (payload) {
            root.lastCreatedPath = payload.notePath
            root.lastCreatedFullPath = payload.noteFullPath
            root._clearError()
        } else {
            root._setError(code, message)
        }
        root.busy = false
        if (requester)
            root.captureFinished(requester, payload ? payload.notePath : "", message)
        if (payload)
            root.captured(payload)
    }

    function openLast(): bool {
        if (root.lastCreatedFullPath.length === 0)
            return false
        if (HostServices.AlisIntergration.nexus && typeof HostServices.AlisIntergration.nexus.openNote === "function") {
            HostServices.AlisIntergration.nexus.openNote(root.lastCreatedPath.length > 0 ? root.lastCreatedPath : root.lastCreatedFullPath)
            return true
        }
        Quickshell.execDetached(["xdg-open", root.lastCreatedFullPath])
        return true
    }

    Timer {
        id: captureTimeout
        interval: 8000
        repeat: false
        onTriggered: {
            if (!captureProc.running)
                return
            captureProc.timedOut = true
            captureProc.running = false
        }
    }

    Timer {
        id: captureFlushTimer
        interval: 120
        repeat: false
        onTriggered: {
            if (!captureProc._exited || captureProc._finalized)
                return
            captureProc._streamDone = true
            captureProc._finalizeCapture()
        }
    }

    Process {
        id: captureProc
        running: false
        property bool startObserved: false
        property bool timedOut: false
        property bool _exited: false
        property bool _streamDone: false
        property bool _finalized: false
        property int _exitCode: -1
        function _finalizeCapture(): void {
            if (!captureProc._exited || captureProc._finalized)
                return
            if (captureProc.timedOut) {
                captureProc._finalized = true
                captureProc._exited = false
                captureProc._streamDone = false
                captureFlushTimer.stop()
                root._finishCapture(null, "capture_timeout", "Zettelkasten quick-note capture timed out")
                return
            }
            if (!captureProc._streamDone)
                return
            captureProc._finalized = true
            captureProc._exited = false
            captureProc._streamDone = false
            captureFlushTimer.stop()
            if (captureProc._exitCode !== 0) {
                root._finishCapture(null, "capture_failed", "Zettelkasten helper failed; no saved-note receipt was accepted")
                return
            }
            const output = String(captureCollector.text ?? "").trim()
            if (output.length === 0) {
                root._finishCapture(null, "capture_failed", "Zettelkasten helper returned no result")
                return
            }
            try {
                const payload = JSON.parse(output)
                if (payload?.ok !== true) {
                    root._finishCapture(
                        null,
                        String(payload?.error?.code ?? "capture_failed"),
                        String(payload?.error?.message ?? "Failed to save Zettelkasten quick note")
                    )
                    return
                }
                if (Array.isArray(payload) || typeof payload.notePath !== "string"
                        || typeof payload.noteFullPath !== "string"
                        || !payload.notePath.endsWith(".md")
                        || payload.notePath.startsWith("/")
                        || payload.notePath.split("/").some(part => !part || part === "." || part === "..")
                        || !payload.noteFullPath.startsWith("/")
                        || !payload.noteFullPath.endsWith("/" + payload.notePath)
                        || /[\x00-\x1f\x7f]/.test(payload.notePath + payload.noteFullPath)) {
                    root._finishCapture(null, "capture_invalid_output", "Zettelkasten helper returned no valid saved-note receipt")
                    return
                }
                root._finishCapture(payload, "", "")
            } catch (error) {
                root._finishCapture(null, "capture_invalid_output", "Zettelkasten helper returned invalid JSON")
            }
        }
        stdout: StdioCollector {
            id: captureCollector
            onStreamFinished: {
                captureProc._streamDone = true
                captureProc._finalizeCapture()
            }
        }

        onRunningChanged: {
            if (captureProc.running) {
                captureProc.startObserved = false
                captureProc._exited = false
                captureProc._streamDone = false
                captureProc._finalized = false
                captureProc._exitCode = -1
                captureFlushTimer.stop()
                return
            }
            if (captureProc.startObserved)
                return
            captureTimeout.stop()
            captureFlushTimer.stop()
            root._finishCapture(null, "capture_start_failed", "Failed to start Zettelkasten helper")
        }

        onStarted: {
            captureProc.startObserved = true
            captureProc.timedOut = false
            captureProc._finalized = false
            captureTimeout.restart()
        }

        onExited: (exitCode, exitStatus) => {
            captureTimeout.stop()
            captureProc._exitCode = exitCode
            captureProc._exited = true
            if (captureProc._streamDone || captureProc.timedOut)
                captureProc._finalizeCapture()
            else
                captureFlushTimer.restart()
        }
    }
}
