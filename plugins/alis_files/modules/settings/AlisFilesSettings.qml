pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.settings
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

SettingsCardSection {
    id: root
    objectName: "alisIntergrationAlisFilesSettings"
    settingsTaskSection: "alisFiles"
    expanded: true
    icon: "folder_open"
    title: Translation.tr("Alis Files")

    readonly property string configPath: `${Directories.config}/alis/alis-files.json`
    readonly property string installerScriptPath: AlisIntergration.resolveEntryPath("plugins/alis_files/scripts/install_alis_files.py")

    property bool prefsLoaded: false
    property bool overlayMode: true
    property string viewMode: "grid"
    property bool showHidden: false
    property bool confirmPermanentDelete: true
    property bool splitViewDefault: false
    property bool inspectorOpenDefault: false
    property bool vimKeybindings: true
    property bool gitBadges: true
    property bool thumbnailsEnabled: true
    property bool directoriesFirst: true
    property var extraPrefs: ({})

    property bool binaryInstalled: false
    property string binaryPath: ""
    property bool buildBusy: false
    property string buildMessage: ""
    property string buildError: ""

    function loadPrefsFromText(raw: string): void {
        try {
            const doc = JSON.parse(String(raw ?? "").trim() || "{}")
            if (doc && typeof doc === "object") {
                root.extraPrefs = doc
                root.overlayMode = doc.overlay_mode !== false
                root.viewMode = (doc.view_mode === "list" || doc.view_mode === "gallery") ? doc.view_mode : "grid"
                root.showHidden = doc.show_hidden === true
                root.confirmPermanentDelete = doc.confirm_permanent_delete !== false
                root.splitViewDefault = doc.split_view_default === true
                root.inspectorOpenDefault = doc.inspector_open_default === true
                root.vimKeybindings = doc.vim_keybindings !== false
                root.gitBadges = doc.git_badges !== false
                root.thumbnailsEnabled = doc.thumbnails_enabled !== false
                root.directoriesFirst = doc.directories_first !== false
            }
        } catch (_e) {}
        root.prefsLoaded = true
    }

    function savePrefs(): void {
        if (!root.prefsLoaded)
            return
        const merged = Object.assign({}, root.extraPrefs, {
            overlay_mode: root.overlayMode,
            view_mode: root.viewMode,
            show_hidden: root.showHidden,
            confirm_permanent_delete: root.confirmPermanentDelete,
            split_view_default: root.splitViewDefault,
            inspector_open_default: root.inspectorOpenDefault,
            vim_keybindings: root.vimKeybindings,
            git_badges: root.gitBadges,
            thumbnails_enabled: root.thumbnailsEnabled,
            directories_first: root.directoriesFirst
        })
        root.extraPrefs = merged
        saveDirProc.pendingPayload = JSON.stringify(merged, null, 2) + "\n"
        if (!saveDirProc.running) {
            saveDirProc.command = ["/usr/bin/mkdir", "-p", `${Directories.config}/alis`]
            saveDirProc.running = true
        }
    }

    function checkBinaryStatus(): void {
        if (statusProc.running || root.installerScriptPath.length === 0)
            return
        statusProc.command = ["/usr/bin/python3", root.installerScriptPath, "--status"]
        statusProc.running = true
    }

    function rebuildBinary(): void {
        if (root.buildBusy || root.installerScriptPath.length === 0)
            return
        root.buildBusy = true
        root.buildError = ""
        root.buildMessage = Translation.tr("Building Alis Files locally…")
        const cmd = ["/usr/bin/python3", root.installerScriptPath]
        if (root.binaryInstalled)
            cmd.push("--force")
        buildProc.command = cmd
        buildProc.running = true
    }

    FileView {
        id: prefsFileView
        path: "file://" + root.configPath
        preload: true
        watchChanges: false
        printErrors: false
        onLoaded: root.loadPrefsFromText(prefsFileView.text())
        onLoadFailed: root.prefsLoaded = true
    }

    Process {
        id: saveDirProc
        property string pendingPayload: ""
        running: false
        onExited: {
            if (saveDirProc.pendingPayload.length > 0) {
                const payload = saveDirProc.pendingPayload
                saveDirProc.pendingPayload = ""
                prefsFileView.setText(payload)
            }
        }
    }

    Process {
        id: statusProc
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const doc = JSON.parse(String(text ?? "").trim())
                    root.binaryInstalled = doc.installed === true
                    root.binaryPath = String(doc.binaryPath ?? "")
                } catch (_e) {}
            }
        }
    }

    Process {
        id: buildProc
        running: false
        stdout: StdioCollector { id: buildStdout }
        stderr: StdioCollector { id: buildStderr }
        onExited: exitCode => {
            root.buildBusy = false
            if (exitCode === 0) {
                root.buildError = ""
                root.buildMessage = Translation.tr("Alis Files built and installed.")
                root.checkBinaryStatus()
            } else {
                const errText = String(buildStderr.text || buildStdout.text || "").trim()
                root.buildError = errText.length > 0 ? errText.slice(-240) : Translation.tr("Build failed")
                root.buildMessage = ""
            }
        }
    }

    Component.onCompleted: root.checkBinaryStatus()

    SettingsGroup {
        ContentSubsection {
            title: Translation.tr("Application")

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                StyledText {
                    Layout.fillWidth: true
                    text: root.binaryInstalled
                        ? Translation.tr("Installed at %1").arg(root.binaryPath || "~/.local/bin/alis-files")
                        : Translation.tr("Alis Files binary is not built yet. Build it locally to launch.")
                    color: root.binaryInstalled ? Appearance.colors.colSubtext : Appearance.colors.colError
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    wrapMode: Text.WordWrap
                }

                DialogButton {
                    objectName: "alisFilesLaunchOverlayButton"
                    buttonText: Translation.tr("Open Overlay")
                    enabled: root.binaryInstalled && !root.buildBusy
                    onClicked: Quickshell.execDetached(["alis", "files", "toggle"])
                }

                DialogButton {
                    objectName: "alisFilesLaunchButton"
                    buttonText: Translation.tr("Open Window")
                    enabled: root.binaryInstalled && !root.buildBusy
                    onClicked: Quickshell.execDetached(["alis", "files", "--new"])
                }

                DialogButton {
                    objectName: "alisFilesRebuildButton"
                    buttonText: root.buildBusy
                        ? Translation.tr("Building…")
                        : (root.binaryInstalled ? Translation.tr("Rebuild") : Translation.tr("Build & Install"))
                    enabled: !root.buildBusy && root.installerScriptPath.length > 0
                    onClicked: root.rebuildBinary()
                }
            }

            StyledText {
                visible: root.buildMessage.length > 0 || root.buildError.length > 0
                Layout.fillWidth: true
                text: root.buildError.length > 0 ? root.buildError : root.buildMessage
                color: root.buildError.length > 0 ? Appearance.colors.colError : Appearance.colors.colPrimary
                font.pixelSize: Appearance.font.pixelSize.smaller
                wrapMode: Text.WordWrap
            }
        }

        ContentSubsection {
            title: Translation.tr("Default layout")

            SettingsSwitch {
                objectName: "alisFilesOverlayModeSwitch"
                Layout.fillWidth: true
                buttonIcon: "dock_to_bottom"
                text: Translation.tr("Open in Abyss Bottom-Edge Overlay mode on Super+E")
                checked: root.overlayMode
                onCheckedChanged: {
                    if (root.overlayMode !== checked) {
                        root.overlayMode = checked
                        root.savePrefs()
                    }
                }
            }

            ConfigSelectionArray {
                objectName: "alisFilesViewModeSelector"
                currentValue: root.viewMode
                onSelected: value => {
                    root.viewMode = value
                    root.savePrefs()
                }
                options: [
                    { displayName: Translation.tr("Grid view"), icon: "grid_view", value: "grid" },
                    { displayName: Translation.tr("List view"), icon: "view_list", value: "list" },
                    { displayName: Translation.tr("Gallery view"), icon: "photo_library", value: "gallery" }
                ]
            }

            SettingsSwitch {
                objectName: "alisFilesSplitDefaultSwitch"
                Layout.fillWidth: true
                buttonIcon: "vertical_split"
                text: Translation.tr("Open with Split View enabled by default (F3)")
                checked: root.splitViewDefault
                onCheckedChanged: {
                    if (root.splitViewDefault !== checked) {
                        root.splitViewDefault = checked
                        root.savePrefs()
                    }
                }
            }

            SettingsSwitch {
                objectName: "alisFilesInspectorDefaultSwitch"
                Layout.fillWidth: true
                buttonIcon: "right_panel_open"
                text: Translation.tr("Show right Preview Inspector by default (Alt+I)")
                checked: root.inspectorOpenDefault
                onCheckedChanged: {
                    if (root.inspectorOpenDefault !== checked) {
                        root.inspectorOpenDefault = checked
                        root.savePrefs()
                    }
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Behavior & power features")

            SettingsSwitch {
                objectName: "alisFilesShowHiddenSwitch"
                Layout.fillWidth: true
                buttonIcon: "visibility"
                text: Translation.tr("Show hidden files by default (Ctrl+H)")
                checked: root.showHidden
                onCheckedChanged: {
                    if (root.showHidden !== checked) {
                        root.showHidden = checked
                        root.savePrefs()
                    }
                }
            }

            SettingsSwitch {
                objectName: "alisFilesVimKeysSwitch"
                Layout.fillWidth: true
                buttonIcon: "keyboard"
                text: Translation.tr("Enable Vim navigation keybindings (j/k/h/l, gg/G, yy, dd, p)")
                checked: root.vimKeybindings
                onCheckedChanged: {
                    if (root.vimKeybindings !== checked) {
                        root.vimKeybindings = checked
                        root.savePrefs()
                    }
                }
            }

            SettingsSwitch {
                objectName: "alisFilesGitBadgesSwitch"
                Layout.fillWidth: true
                buttonIcon: "commit"
                text: Translation.tr("Show Git status badges in repositories")
                checked: root.gitBadges
                onCheckedChanged: {
                    if (root.gitBadges !== checked) {
                        root.gitBadges = checked
                        root.savePrefs()
                    }
                }
            }

            SettingsSwitch {
                objectName: "alisFilesThumbnailsSwitch"
                Layout.fillWidth: true
                buttonIcon: "image"
                text: Translation.tr("Generate image, PDF, and video thumbnails")
                checked: root.thumbnailsEnabled
                onCheckedChanged: {
                    if (root.thumbnailsEnabled !== checked) {
                        root.thumbnailsEnabled = checked
                        root.savePrefs()
                    }
                }
            }

            SettingsSwitch {
                objectName: "alisFilesConfirmDeleteSwitch"
                Layout.fillWidth: true
                buttonIcon: "delete_forever"
                text: Translation.tr("Ask confirmation before permanent deletion")
                checked: root.confirmPermanentDelete
                onCheckedChanged: {
                    if (root.confirmPermanentDelete !== checked) {
                        root.confirmPermanentDelete = checked
                        root.savePrefs()
                    }
                }
            }
        }
    }
}
