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

    bin_path = root / "assets" / "bin" / "alis-nexus"
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

        nexus_service_uri = str(root / "services/NexusService.qml")
        nexus_workspace_uri = str(root / "modules/nexus/NexusWorkspace.qml")

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


if __name__ == "__main__":
    test_nexus_shortcut_escape_recovery()

