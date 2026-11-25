#!/usr/bin/env python3
"""Parse extracted QML with the installed Qt 6 parser and run headless Quickshell shortcut regression test."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import sys

root = Path(__file__).resolve().parents[1]
files = sorted(root.rglob("*.qml"))
for path in files:
    subprocess.run(["/usr/lib/qt6/bin/qmlformat", str(path)], stdout=subprocess.DEVNULL, check=True)
print("ALIS_INTERGRATION_QML_PARSE_PASS", len(files))


def test_nexus_shortcut_escape_recovery():
    """Dedicated headless Quickshell test: Alt+Enter -> Esc -> Alt+Esc -> Esc -> Alt+T -> Esc -> Alt+Enter / Alt+N / Alt+1."""
    sys.path.insert(0, str(root / "scripts"))
    from integration_test_host import resolve_host_root

    host = resolve_host_root(root)
    sys.path.insert(0, str(host / "scripts"))
    from native_test_session import private_wayland, run_qs

    bin_path = root / "plugins" / "nexus" / "assets" / "bin" / "alis-nexus"
    if not bin_path.is_file() or not host.is_dir():
        return

    with tempfile.TemporaryDirectory(prefix="alis-qml-nexus-shortcut-") as tmp:
        private = Path(tmp)
        shell = private / "shell"
        shell.mkdir()
        for entry in ("services", "modules", "GlobalStates.qml", "qmldir", "scripts", "defaults", "translations", "assets"):
            (shell / entry).symlink_to(host / entry)

        vault = private / "Vault"
        (vault / "00_Capture").mkdir(parents=True, exist_ok=True)
        (vault / "10_Projects").mkdir(parents=True, exist_ok=True)
        (vault / ".obsidian").mkdir(parents=True, exist_ok=True)
        (vault / "10_Projects" / "Alpha.md").write_text("# Alpha\n\nTest note.\n", encoding="utf-8")
        (vault / ".obsidian" / "hotkeys.json").write_text(
            json.dumps(
                {
                    "command-palette:open": [{"modifiers": ["Alt"], "key": "Enter"}],
                    "omnisearch:show-modal": [{"modifiers": ["Alt"], "key": "Escape"}],
                    "quickadd:choice:e26ead52-86bc-4f2e-a0e4-d144cb7f3c4b": [{"modifiers": ["Alt"], "key": "t"}],
                }
            ),
            encoding="utf-8",
        )

        config = private / "config/alis"
        config.mkdir(parents=True)
        options = json.loads((host / "defaults/config.json").read_text())
        options["todo"]["nexus"]["vaultPath"] = str(vault)
        (config / "config.json").write_text(json.dumps(options))

        nexus_service_uri = str(root / "plugins/nexus/services/NexusService.qml")
        nexus_workspace_uri = str(root / "plugins/nexus/modules/nexus/NexusWorkspace.qml")

        (shell / "shell.qml").write_text(
            f"""import QtQuick
import QtTest
import Quickshell
import qs
import qs.services
import qs.modules.common

ShellRoot {{
    id: root
    Component.onCompleted: Quickshell.watchFiles = false
    FloatingWindow {{
        id: win
        visible: true
        implicitWidth: 1280
        implicitHeight: 820
        Loader {{
            id: serviceLoader
            source: "{nexus_service_uri}"
        }}
        Item {{
            id: perimeterEscapeFallback
            objectName: "perimeterEscapeFallback"
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: event => {{
                if (workspaceLoader.item && workspaceLoader.item.handleEscape()) {{
                    event.accepted = true
                    workspaceLoader.item.focusPrimarySurface()
                }}
            }}
            Keys.onPressed: event => {{
                if (event.key === Qt.Key_Escape && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.KeypadModifier)) {{
                    if (workspaceLoader.item && workspaceLoader.item.handleEscape()) {{
                        event.accepted = true
                        workspaceLoader.item.focusPrimarySurface()
                    }}
                    return
                }}
                if (workspaceLoader.item && workspaceLoader.item.forwardKeyEvent(event)) {{
                    workspaceLoader.item.focusPrimarySurface()
                }}
            }}
            Loader {{
                id: workspaceLoader
                anchors.fill: parent
                source: "{nexus_workspace_uri}"
                onLoaded: item.nexus = serviceLoader.item
            }}
        }}
    }}
    TestCase {{
        id: tc
        name: "NexusShortcutEscapeRecovery"
        when: false
        optional: true
        function check(cond, msg) {{
            if (!cond) throw new Error(msg)
        }}
        function runTest() {{
            try {{
                tryCompare(Config, "ready", true, 4000)
                tryCompare(serviceLoader, "status", Loader.Ready, 4000)
                tryCompare(workspaceLoader, "status", Loader.Ready, 4000)
                const nexus = serviceLoader.item
                const ws = workspaceLoader.item
                ws.nexus = nexus
                nexus.open()
                tryCompare(nexus, "vaultLoaded", true, 5000)
                const cpModal = findChild(ws, "nexusCommandPaletteModal")
                const cpInput = findChild(ws, "nexusCommandPaletteInput")
                const keyScope = findChild(ws, "nexusWorkspaceKeyScope")
                check(cpModal !== null && cpInput !== null && keyScope !== null, "missing modal/input/keyScope")

                ws.restoreWorkspaceFocus()
                wait(30)

                // 1. Alt+Enter -> Esc -> Alt+Esc -> Esc -> Alt+T -> Esc
                keyClick(Qt.Key_Return, Qt.AltModifier)
                wait(40)
                check(nexus.commandPaletteOpen === true && nexus.commandPaletteMode === "commands" && cpInput.activeFocus === true, "Alt+Enter failed to open Command Palette")
                keyClick(Qt.Key_Escape, Qt.NoModifier)
                wait(40)
                check(nexus.commandPaletteOpen === false && cpInput.focus === false && ws.activeFocus === true && keyScope.activeFocus === true, "Esc failed to close Command Palette and restore focus")

                keyClick(Qt.Key_Escape, Qt.AltModifier)
                wait(40)
                check(nexus.commandPaletteOpen === true && nexus.commandPaletteMode === "switcher" && cpInput.activeFocus === true, "Alt+Esc failed to open Quick Switcher after Esc")
                keyClick(Qt.Key_Escape, Qt.NoModifier)
                wait(40)
                check(nexus.commandPaletteOpen === false && cpInput.focus === false && ws.activeFocus === true && keyScope.activeFocus === true, "Esc failed to close Quick Switcher and restore focus")

                keyClick(Qt.Key_T, Qt.AltModifier)
                wait(40)
                check(nexus.commandPaletteOpen === true && nexus.commandPaletteMode === "task" && cpInput.activeFocus === true, "Alt+T failed to open Quick Task modal after Esc")
                keyClick(Qt.Key_Escape, Qt.NoModifier)
                wait(40)
                check(nexus.commandPaletteOpen === false && cpInput.focus === false && ws.activeFocus === true && keyScope.activeFocus === true, "Esc failed to close Quick Task modal and restore focus")

                // 2. Trigger Alt+Enter, Alt+N, Alt+3, Alt+1 again after Esc cycles
                keyClick(Qt.Key_Return, Qt.AltModifier)
                wait(40)
                check(nexus.commandPaletteOpen === true && nexus.commandPaletteMode === "commands", "Alt+Enter failed after Esc cycles")
                keyClick(Qt.Key_Escape, Qt.NoModifier)
                wait(40)
                check(nexus.commandPaletteOpen === false, "Esc failed on second Alt+Enter")

                keyClick(Qt.Key_N, Qt.AltModifier)
                tryVerify(() => !nexus.docBusy && nexus.activeView === "document" && String(nexus.currentPath).startsWith("00_Capture/Note-"), 4000)

                keyClick(Qt.Key_3, Qt.AltModifier)
                wait(40)
                check(nexus.activeView === "graph", "Alt+3 failed after Esc cycles")
                keyClick(Qt.Key_1, Qt.AltModifier)
                wait(40)
                check(nexus.activeView === "homepage", "Alt+1 failed after Esc cycles")

                // 3. Even if host perimeterEscapeFallback steals activeFocus, Alt+Enter -> Esc -> Alt+Esc -> Esc -> Alt+T -> Esc still work 100%
                perimeterEscapeFallback.forceActiveFocus()
                wait(20)
                keyClick(Qt.Key_Return, Qt.AltModifier)
                wait(40)
                check(nexus.commandPaletteOpen === true && nexus.commandPaletteMode === "commands" && cpInput.activeFocus === true, "Alt+Enter failed when perimeterEscapeFallback held focus")
                keyClick(Qt.Key_Escape, Qt.NoModifier)
                wait(40)
                check(nexus.commandPaletteOpen === false && ws.activeFocus === true, "Esc failed after perimeterEscapeFallback recovery")

                console.info("ALIS_QML_SHORTCUT_ESCAPE_RECOVERY_PASS")
            }} catch (e) {{
                console.error("ALIS_QML_SHORTCUT_ESCAPE_RECOVERY_FAIL", e.message, e.stack)
            }}
            Qt.quit()
        }}
    }}
    Timer {{ interval: 100; running: true; onTriggered: tc.runTest() }}
}}
""",
            encoding="utf-8",
        )

        runtime = private / "runtime"
        runtime.mkdir(mode=0o700)
        env = dict(
            os.environ,
            QT_QPA_PLATFORM="offscreen",
            QT_QUICK_BACKEND="software",
            XDG_RUNTIME_DIR=str(runtime),
            XDG_CONFIG_HOME=str(private / "config"),
            XDG_STATE_HOME=str(private / "state"),
            XDG_CACHE_HOME=str(private / "cache"),
            XDG_DATA_HOME=str(private / "data"),
            ALIS_NEXUS_DISABLE_XDG_OPEN="1",
            ALIS_NEXUS_HEADLESS_SERVICE_ONLY="1",
        )
        env.pop("NIRI_SOCKET", None)
        env.pop("HYPRLAND_INSTANCE_SIGNATURE", None)
        with private_wayland(private) as wayland_env:
            if wayland_env is not None:
                env.update({k: v for k, v in wayland_env.items() if k in ("WAYLAND_DISPLAY", "NIRI_SOCKET", "DISPLAY", "XDG_RUNTIME_DIR")})
                env["QT_QPA_PLATFORM"] = "wayland"
            result = run_qs(shell, env, timeout=25)
        if result.returncode or "ALIS_QML_SHORTCUT_ESCAPE_RECOVERY_PASS" not in result.stdout or "ALIS_QML_SHORTCUT_ESCAPE_RECOVERY_FAIL" in result.stdout:
            print(result.stdout)
            raise SystemExit(1)
        print("ALIS_QML_SHORTCUT_ESCAPE_RECOVERY_PASS")


def test_alis_files_prompt_escape_tab_recovery():
    """Dedicated headless Quickshell test: a -> Esc -> Yazi ([, ], 1..3) and Alt+1..3 tab switches + / -> Esc + Ctrl+L -> Esc."""
    sys.path.insert(0, str(root / "scripts"))
    from integration_test_host import resolve_host_root

    host = resolve_host_root(root)
    sys.path.insert(0, str(host / "scripts"))
    from native_test_session import private_wayland, run_qs

    if not host.is_dir():
        return

    with tempfile.TemporaryDirectory(prefix="alis-qml-files-escape-") as tmp:
        private = Path(tmp)
        shell = private / "shell"
        shell.mkdir()
        for entry in ("services", "modules", "GlobalStates.qml", "qmldir", "scripts", "defaults", "translations", "assets"):
            (shell / entry).symlink_to(host / entry)

        config = private / "config/alis"
        config.mkdir(parents=True)
        options = json.loads((host / "defaults/config.json").read_text())
        (config / "config.json").write_text(json.dumps(options))

        files_workspace_uri = str(root / "plugins/alis_files/modules/files/AlisFilesOverlayWorkspace.qml")

        (shell / "shell.qml").write_text(
            f"""import QtQuick
import QtTest
import Quickshell
import qs
import qs.services
import qs.modules.common

ShellRoot {{
    id: root
    Component.onCompleted: Quickshell.watchFiles = false
    FloatingWindow {{
        id: win
        visible: true
        implicitWidth: 1280
        implicitHeight: 820
        QtObject {{
            id: mockFiles
            property string homePath: "/tmp"
            property string configHomePath: "/tmp/.config"
            property string trashPath: "/tmp/.trash"
            property string currentPath: "/tmp"
            property string parentPath: "/"
            property bool isTrash: false
            property var dirEntry: ({{ name: "tmp", path: "/tmp", is_dir: true }})
            property var entries: []
            property var tabs: [
                ({{ path: "/tmp", title: "Home", backStack: [], forwardStack: [], split: null }}),
                ({{ path: "/tmp/docs", title: "Documents", backStack: [], forwardStack: [], split: null }}),
                ({{ path: "/tmp/dl", title: "Downloads", backStack: [], forwardStack: [], split: null }})
            ]
            property int activeTab: 0
            readonly property var currentTabObj: tabs[activeTab]
            readonly property bool splitOpen: false
            property bool activeIsSecondary: false
            property real splitRatio: 0.5
            property string secondaryPath: "/tmp"
            property string secondaryParentPath: "/"
            property bool secondaryIsTrash: false
            property var secondaryDirEntry: null
            property var secondaryEntries: []
            property var secondarySelectedPaths: []
            property string secondaryGitBranch: ""
            property var secondaryGitBadges: ({{}})
            readonly property string activePath: currentPath
            readonly property string activeParentPath: parentPath
            readonly property bool activeIsTrash: false
            readonly property var activeDirEntry: dirEntry
            readonly property var activeEntries: entries
            readonly property int activeTabIndex: activeTab
            readonly property var activeTabNode: currentTabObj
            readonly property var activeSelectedPaths: selectedPaths
            readonly property string activeGitBranch: ""
            readonly property var activeGitBadges: ({{}})
            property var places: []
            property var bookmarks: []
            property var drives: []
            property string viewMode: "list"
            property bool showHidden: false
            property bool railOpen: true
            property bool inspectorOpen: false
            property int railWidth: 228
            property int inspectorWidth: 296
            property real inspectorPreviewRatio: 0.38
            property var propsData: null
            property bool propsLoading: false
            property string propsTargetPath: ""
            property var propsDirTotals: null
            property bool propsDirLoading: false
            property var propsChecksums: ({{}})
            property var propsChecksumBusy: ({{}})
            property bool dirsFirst: true
            property bool thumbnailsEnabled: true
            property bool vimKeybindings: true
            property bool confirmPermanentDelete: true
            property string sortField: "name"
            property string sortOrder: "asc"
            property int gridIconSize: 72
            property int listZoom: 1
            property string filterText: ""
            property bool recursiveSearch: false
            property var selectedPaths: []
            property var clipboardPaths: []
            property string clipboardOp: ""
            property var gitBadges: ({{}})
            property var thumbMap: ({{}})
            property real totalBytes: 0
            property real freeBytes: 0
            property string freeLabel: "10 GB free"
            property int trashCount: 0
            property string toastMessage: ""
            property bool toastUndoable: false
            property bool toastIsError: false
            property string errorMessage: ""
            property var quickLookEntry: null
            property string quickLookText: ""
            function switchTab(idx, _sec) {{
                if (idx >= 0 && idx < tabs.length) {{
                    activeTab = idx;
                    currentPath = tabs[idx].path;
                }}
            }}
            function nextTab() {{ switchTab((activeTab + 1) % tabs.length, false); }}
            function prevTab() {{ switchTab((activeTab - 1 + tabs.length) % tabs.length, false); }}
            function closeTab(_idx) {{}}
            function closeTabHalf(_idx, _side) {{}}
            function newTab(_p) {{}}
            function setActivePane(_sec) {{}}
            function setPaneSelectedPaths(_sec, ps) {{ selectedPaths = ps; }}
            function setFilter(txt, rec) {{ filterText = txt; recursiveSearch = Boolean(rec); }}
            function openQuickLook(_e) {{}}
            function closeQuickLook() {{ quickLookEntry = null; }}
            function stepQuickLook(_d) {{}}
            function goBack() {{}}
            function goForward() {{}}
            function goParent() {{}}
            function navigate(_p) {{}}
            function toggleSplitView() {{}}
            function toggleRail() {{}}
            function toggleInspector() {{}}
            function toggleHidden() {{}}
            function toggleDirsFirst() {{}}
            function refresh() {{}}
            function setViewMode(_m) {{}}
            function setSort(_f) {{}}
            function setGridIconSize(_s) {{}}
            function setListZoom(_z) {{}}
            function setRailWidth(_w) {{}}
            function setInspectorWidth(_w) {{}}
            function setInspectorPreviewRatio(_r) {{}}
            function setSplitRatio(_r) {{}}
            function loadProperties(_p) {{}}
            function computeChecksum(_p, _a) {{}}
            function setItemPermissions(_p, _m) {{}}
            function setDefaultApp(_a, _b) {{}}
            function createEntry(_n) {{}}
            function createFolder(_n) {{}}
            function createFile(_n) {{}}
            function renamePath(_p, _n) {{}}
            function copyPaths(_ps) {{}}
            function cutPaths(_ps) {{}}
            function paste() {{}}
            function undo() {{}}
            function redo() {{}}
            function trashPaths(_ps) {{}}
            function deletePaths(_ps) {{}}
            function restorePaths(_ps) {{}}
            function emptyTrash() {{}}
            function compressPaths(_ps, _n, _f) {{}}
            function extractArchive(_p, _h) {{}}
            function mountDrive(_d) {{}}
            function unmountDrive(_d) {{}}
            function addBookmark(_p, _n) {{}}
            function removeBookmark(_p) {{}}
            function openExternal(_p) {{}}
            function runAlisAction(_a, _p) {{}}
            function showToast(_m, _u) {{}}
        }}
        Item {{
            id: perimeterEscapeFallback
            objectName: "perimeterEscapeFallback"
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: event => {{
                if (workspaceLoader.item && workspaceLoader.item.handleEscape()) {{
                    event.accepted = true
                    workspaceLoader.item.focusPrimarySurface()
                }}
            }}
            Keys.onPressed: event => {{
                if (event.key === Qt.Key_Escape && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.KeypadModifier)) {{
                    if (workspaceLoader.item && workspaceLoader.item.handleEscape()) {{
                        event.accepted = true
                        workspaceLoader.item.focusPrimarySurface()
                    }}
                    return
                }}
                if (workspaceLoader.item && workspaceLoader.item.forwardKeyEvent(event)) {{
                    workspaceLoader.item.focusPrimarySurface()
                }}
            }}
            Loader {{
                id: workspaceLoader
                anchors.fill: parent
                source: "{files_workspace_uri}"
                onLoaded: {{
                    item.files = mockFiles
                    item.embeddedSurface = true
                    item.transitionSettled = true
                    item.focusPrimarySurface()
                }}
            }}
        }}
    }}
    TestCase {{
        id: tc
        name: "AlisFilesPromptEscapeRecovery"
        when: false
        optional: true
        function check(cond, msg) {{
            if (!cond) throw new Error(msg)
        }}
        function runTest() {{
            try {{
                tryCompare(Config, "ready", true, 4000)
                tryCompare(workspaceLoader, "status", Loader.Ready, 4000)
                const ws = workspaceLoader.item
                const keyTarget = findChild(ws, "alisFilesSurfaceKeyTarget")
                const promptInput = findChild(ws, "alisFilesPromptInput")
                const pathInput = findChild(ws, "alisFilesPathInput")
                const filterInput = findChild(ws, "alisFilesFilterInput")
                check(keyTarget !== null && promptInput !== null && pathInput !== null && filterInput !== null, "missing workspace inputs/keyTarget")

                ws.focusPrimarySurface()
                wait(30)
                check(keyTarget.activeFocus === true && ws.activeFocus === true, "initial surfaceKeyTarget did not have activeFocus")

                // 1. Press 'a' -> open create prompt, then 'Esc' -> restore focus & switch tabs via Yazi + Alt+number
                keyClick(Qt.Key_A, Qt.NoModifier)
                wait(40)
                check(ws.promptMode === "create" && promptInput.activeFocus === true, "Key 'a' failed to open create prompt with focus")

                keyClick(Qt.Key_Escape, Qt.NoModifier)
                wait(40)
                check(ws.promptMode === "" && promptInput.focus === false && promptInput.activeFocus === false, "Esc failed to close create prompt and drop TextField focus")
                check(keyTarget.activeFocus === true && ws.activeFocus === true, "Esc failed to restore activeFocus to surfaceKeyTarget")

                keyClick(Qt.Key_BracketRight, Qt.NoModifier)
                wait(25)
                check(mockFiles.activeTab === 1, "Yazi ']' failed to switch tab after a -> Esc, activeTab=" + mockFiles.activeTab)

                keyClick(Qt.Key_BracketLeft, Qt.NoModifier)
                wait(25)
                check(mockFiles.activeTab === 0, "Yazi '[' failed to switch tab after a -> Esc, activeTab=" + mockFiles.activeTab)

                keyClick(Qt.Key_3, Qt.NoModifier)
                wait(25)
                check(mockFiles.activeTab === 2, "Yazi '3' failed to switch tab after a -> Esc, activeTab=" + mockFiles.activeTab)

                keyClick(Qt.Key_1, Qt.NoModifier)
                wait(25)
                check(mockFiles.activeTab === 0, "Yazi '1' failed to switch tab after a -> Esc, activeTab=" + mockFiles.activeTab)

                keyClick(Qt.Key_2, Qt.AltModifier)
                wait(25)
                check(mockFiles.activeTab === 1, "Alt+2 failed to switch tab after a -> Esc, activeTab=" + mockFiles.activeTab)

                keyClick(Qt.Key_3, Qt.AltModifier)
                wait(25)
                check(mockFiles.activeTab === 2, "Alt+3 failed to switch tab after a -> Esc, activeTab=" + mockFiles.activeTab)

                keyClick(Qt.Key_1, Qt.AltModifier)
                wait(25)
                check(mockFiles.activeTab === 0, "Alt+1 failed to switch tab after a -> Esc, activeTab=" + mockFiles.activeTab)

                // 2. Filter '/' -> Esc -> ']' still works
                keyClick(Qt.Key_Slash, Qt.NoModifier)
                wait(40)
                check(ws.filterBarOpen === true && filterInput.activeFocus === true, "Slash failed to focus filterInput")
                keyClick(Qt.Key_Escape, Qt.NoModifier)
                wait(40)
                check(ws.filterBarOpen === false && filterInput.focus === false && keyTarget.activeFocus === true, "Esc from filter failed to restore surfaceKeyTarget")
                keyClick(Qt.Key_BracketRight, Qt.NoModifier)
                wait(25)
                check(mockFiles.activeTab === 1, "Yazi ']' failed after / -> Esc")

                // 3. Ctrl+L path edit -> Esc -> Alt+1 still works
                keyClick(Qt.Key_L, Qt.ControlModifier)
                wait(40)
                check(ws.pathEditActive === true && pathInput.activeFocus === true, "Ctrl+L failed to focus pathInput")
                keyClick(Qt.Key_Escape, Qt.NoModifier)
                wait(40)
                check(ws.pathEditActive === false && pathInput.focus === false && keyTarget.activeFocus === true, "Esc from pathEdit failed to restore surfaceKeyTarget")
                keyClick(Qt.Key_1, Qt.AltModifier)
                wait(25)
                check(mockFiles.activeTab === 0, "Alt+1 failed after Ctrl+L -> Esc")

                console.info("ALIS_QML_FILES_PROMPT_ESCAPE_RECOVERY_PASS")
            }} catch (e) {{
                console.error("ALIS_QML_FILES_PROMPT_ESCAPE_RECOVERY_FAIL", e.message, e.stack)
            }}
            Qt.quit()
        }}
    }}
    Timer {{ interval: 100; running: true; onTriggered: tc.runTest() }}
}}
""",
            encoding="utf-8",
        )

        runtime = private / "runtime"
        runtime.mkdir(mode=0o700)
        env = dict(
            os.environ,
            QT_QPA_PLATFORM="offscreen",
            QT_QUICK_BACKEND="software",
            XDG_RUNTIME_DIR=str(runtime),
            XDG_CONFIG_HOME=str(private / "config"),
            XDG_STATE_HOME=str(private / "state"),
            XDG_CACHE_HOME=str(private / "cache"),
            XDG_DATA_HOME=str(private / "data"),
        )
        env.pop("NIRI_SOCKET", None)
        env.pop("HYPRLAND_INSTANCE_SIGNATURE", None)
        with private_wayland(private) as wayland_env:
            if wayland_env is not None:
                env.update({k: v for k, v in wayland_env.items() if k in ("WAYLAND_DISPLAY", "NIRI_SOCKET", "DISPLAY", "XDG_RUNTIME_DIR")})
                env["QT_QPA_PLATFORM"] = "wayland"
            result = run_qs(shell, env, timeout=25)
        if result.returncode or "ALIS_QML_FILES_PROMPT_ESCAPE_RECOVERY_PASS" not in result.stdout or "ALIS_QML_FILES_PROMPT_ESCAPE_RECOVERY_FAIL" in result.stdout:
            print(result.stdout)
            raise SystemExit(1)
        print("ALIS_QML_FILES_PROMPT_ESCAPE_RECOVERY_PASS")


if __name__ == "__main__":
    test_nexus_shortcut_escape_recovery()
    test_alis_files_prompt_escape_tab_recovery()

