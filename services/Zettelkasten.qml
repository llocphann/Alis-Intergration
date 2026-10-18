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
 * No Obsidian process/plugin is needed.
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

    signal captured(var payload)

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
        const content = String(body ?? "")
        if (!root.ready) {
            root._setError(
                "not_configured",
                "Configure an Obsidian vault before saving a Zettelkasten quick note"
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

        root.busy = true
        root._clearError()
        captureProc.command = [
            "/usr/bin/python3", root.helperPath,
            "--vault", root.configuredVaultPath,
            "--folder", root.folder,
            "--title", String(title ?? ""),
            "--body", content,
            "--type", root.defaultType,
            "--attachment-root", String(attachmentRoot ?? ""),
            "--config-path", String(Config.options?.integrations?.obsidian?.configPath ?? "")
        ]
        captureProc.running = true
        return true
    }

    function openLast(): bool {
        if (root.lastCreatedFullPath.length === 0)
            return false
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

    Process {
        id: captureProc
        running: false
        property bool startObserved: false
        property bool timedOut: false
        stdout: StdioCollector { id: captureCollector }

        onRunningChanged: {
            if (captureProc.running) {
                captureProc.startObserved = false
                return
            }
            if (captureProc.startObserved)
                return
            captureTimeout.stop()
            root.busy = false
            root._setError("capture_start_failed", "Failed to start Zettelkasten helper")
        }

        onStarted: {
            captureProc.startObserved = true
            captureProc.timedOut = false
            captureTimeout.restart()
        }

        onExited: (exitCode, exitStatus) => {
            captureTimeout.stop()
            root.busy = false
            if (captureProc.timedOut) {
                root._setError("capture_timeout", "Zettelkasten quick-note capture timed out")
                return
            }
            if (exitCode !== 0) {
                root._setError("capture_failed", "Zettelkasten helper failed; no saved-note receipt was accepted")
                return
            }
            const output = String(captureCollector.text ?? "").trim()
            if (output.length === 0) {
                root._setError("capture_failed", "Zettelkasten helper returned no result")
                return
            }
            try {
                const payload = JSON.parse(output)
                if (payload?.ok !== true) {
                    root._setError(
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
                    root._setError("capture_invalid_output", "Zettelkasten helper returned no valid saved-note receipt")
                    return
                }
                root.lastCreatedPath = payload.notePath
                root.lastCreatedFullPath = payload.noteFullPath
                root._clearError()
                root.captured(payload)
            } catch (error) {
                root._setError("capture_invalid_output", "Zettelkasten helper returned invalid JSON")
            }
        }
    }
}
