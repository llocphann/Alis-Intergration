#!/usr/bin/env python3
"""Contract & lifecycle verification for the built-in Alis Files plugin and host hooks."""
from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from integration_test_host import resolve_host_root  # noqa: E402

HOST = resolve_host_root(ROOT)
COMPANION = ROOT.parent / "Alis-Companion"
PLUGIN_DIR = ROOT / "plugins" / "alis_files"


def _load_mod(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def test_plugin_layout_and_qml() -> None:
    for rel in (
        "services/AlisFilesService.qml",
        "modules/files/qmldir",
        "modules/files/AlisFilesHost.qml",
        "modules/files/AlisFilesOverlayWorkspace.qml",
        "modules/settings/AlisFilesSettings.qml",
        "assets/org.alis.Files.desktop",
        "assets/org.freedesktop.FileManager1.service",
        "assets/org.alis.Files.svg",
        "scripts/install_alis_files.py",
        "native/Cargo.toml",
        "native/src/main.rs",
        "native/src/overlay_daemon.rs",
    ):
        assert (PLUGIN_DIR / rel).is_file(), f"missing {rel}"

    qmlformat = Path("/usr/lib/qt6/bin/qmlformat")
    if qmlformat.is_file():
        for qml_rel in (
            "services/AlisFilesService.qml",
            "modules/files/AlisFilesHost.qml",
            "modules/files/AlisFilesOverlayWorkspace.qml",
            "modules/settings/AlisFilesSettings.qml",
        ):
            subprocess.run(
                [str(qmlformat), str(PLUGIN_DIR / qml_rel)],
                stdout=subprocess.DEVNULL,
                check=True,
            )

    manifest = json.loads((ROOT / "manifest.json").read_text(encoding="utf-8"))
    assert "alis_files" in manifest["integrations"]
    assert any(p["id"] == "alis_files" for p in manifest["plugins"])
    assert manifest["settings"]["alisFiles"] == "plugins/alis_files/modules/settings/AlisFilesSettings.qml"
    assert manifest["views"]["alisFilesWorkspace"] == "plugins/alis_files/modules/files/AlisFilesOverlayWorkspace.qml"
    assert manifest["scripts"]["alisFilesInstaller"] == "plugins/alis_files/scripts/install_alis_files.py"

    if HOST.is_dir():
        abyss_files = HOST / "modules/abyss/content/AbyssFilesContent.qml"
        assert abyss_files.is_file(), f"missing {abyss_files}"
        if qmlformat.is_file():
            subprocess.run([str(qmlformat), str(abyss_files)], stdout=subprocess.DEVNULL, check=True)


def test_installer_assets_and_uninstall() -> None:
    installer = _load_mod("alis_files_installer", PLUGIN_DIR / "scripts/install_alis_files.py")
    with tempfile.TemporaryDirectory(prefix="alis-files-assets-") as tmp:
        base = Path(tmp)
        bin_dir = base / "bin"
        data_home = base / "share"
        cache_home = base / "cache"
        bin_dir.mkdir(parents=True)
        fake_bin = bin_dir / "alis-files"
        fake_bin.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        fake_bin.chmod(0o755)

        rep = installer.build_and_install(
            bin_dir, data_home, cache_home, assets_only=True, set_mime=False
        )
        assert rep["ok"] is True and rep["installed"] is True
        desktop = data_home / "applications/org.alis.Files.desktop"
        dbus = data_home / "dbus-1/services/org.freedesktop.FileManager1.service"
        icon = data_home / "icons/hicolor/scalable/apps/org.alis.Files.svg"
        assert desktop.is_file() and f"Exec={fake_bin}" in desktop.read_text(encoding="utf-8")
        assert dbus.is_file() and f"Exec={fake_bin} --dbus-service" in dbus.read_text(encoding="utf-8")
        assert icon.is_file()

        st = installer.status(bin_dir, data_home)
        assert st["installed"] and st["desktopInstalled"] and st["dbusInstalled"]

        rem = installer.uninstall(bin_dir, data_home)
        assert rem["ok"] is True
        assert not desktop.exists() and not dbus.exists() and not fake_bin.exists()

    # Verify paths with spaces are properly quoted in generated .desktop & D-Bus .service files.
    with tempfile.TemporaryDirectory(prefix="alis-files-spaces-") as tmp:
        base = Path(tmp)
        bin_dir = base / "my bin dir"
        data_home = base / "share"
        cache_home = base / "cache"
        bin_dir.mkdir(parents=True)
        fake_bin = bin_dir / "alis-files"
        fake_bin.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        fake_bin.chmod(0o755)
        rep = installer.build_and_install(
            bin_dir, data_home, cache_home, assets_only=True, set_mime=False
        )
        assert rep["ok"] is True
        desktop = (data_home / "applications/org.alis.Files.desktop").read_text(encoding="utf-8")
        dbus = (data_home / "dbus-1/services/org.freedesktop.FileManager1.service").read_text(encoding="utf-8")
        assert f'Exec="{fake_bin}" %U' in desktop, desktop
        assert f'Exec="{fake_bin}" --dbus-service' in dbus, dbus


def test_host_builtins_and_default_apps() -> None:
    if not HOST.is_dir():
        return
    manager = _load_mod("host_manager", HOST / "scripts/alis-intergration-manager.py")
    status = _load_mod("host_status", HOST / "scripts/alis-intergration-status.py")

    with tempfile.TemporaryDirectory(prefix="alis-builtins-test-") as tmp:
        base = Path(tmp)
        data_home = base / "data"
        home = data_home / "alis-intergration"
        res = manager.operate(
            "install-builtins",
            home,
            HOST,
            source_dir=ROOT,
            no_build=True,
        )
        assert res["ok"] is True, res
        for expected in ("alis_files", "nexus", "spaced_repetition", "exercises_tracker"):
            assert expected in res["installedPluginIds"], res
            assert (home / "plugins" / expected / "plugin-manifest.json").is_file()

        insp = status.inspect(HOST, data_home)
        assert insp["available"] is True
        for expected in ("alis_files", "nexus", "spaced_repetition", "exercises_tracker"):
            assert expected in insp["installedPluginIds"]
            assert expected in insp["pluginRoots"]

    # Verify install_plugin upgrades an outdated base release missing alisFilesLoader/alisFilesWorkspace.
    installer_mod = _load_mod("alis_installer", ROOT / "scripts/install.py")
    with tempfile.TemporaryDirectory(prefix="alis-base-upgrade-test-") as tmp:
        data_root = Path(tmp) / "alis-intergration"
        old_rel = data_root / "releases" / ("1" * 40)
        old_rel.mkdir(parents=True)
        (old_rel / "AlisSession.qml").write_text("import QtQuick\nItem { property var host }\n", encoding="utf-8")
        (old_rel / "LICENSE").write_text("MIT\n", encoding="utf-8")
        old_manifest = json.loads((ROOT / "manifest.json").read_text(encoding="utf-8"))
        old_manifest.setdefault("views", {}).pop("alisFilesWorkspace", None)
        old_manifest["sourceSha"] = "1" * 40
        old_manifest["layout"] = "base-v2"
        old_manifest["files"] = {
            "AlisSession.qml": installer_mod.digest(old_rel / "AlisSession.qml"),
            "LICENSE": installer_mod.digest(old_rel / "LICENSE"),
        }
        (old_rel / "manifest.json").write_text(json.dumps(old_manifest), encoding="utf-8")
        (data_root / "current").symlink_to(f"releases/{'1' * 40}")
        installer_mod.install_plugin(data_root, "alis_files", source=ROOT, allow_dirty=True)
        cur_session = (data_root / "current/AlisSession.qml").read_text(encoding="utf-8")
        cur_manifest = json.loads((data_root / "current/manifest.json").read_text(encoding="utf-8"))
        assert "alisFilesLoader" in cur_session, "stale base AlisSession.qml was not upgraded"
        assert "alisFilesWorkspace" in cur_manifest.get("views", {}), "stale base manifest views not upgraded"

    # Verify default_apps_helper prioritizes alis-files and appends --new for Super+Shift+E.
    with tempfile.TemporaryDirectory(prefix="alis-files-helper-") as tmp:
        base = Path(tmp)
        bin_dir = base / "bin"
        apps_dir = base / "share/applications"
        cfg_dir = base / "config/alis"
        bin_dir.mkdir(parents=True)
        apps_dir.mkdir(parents=True)
        cfg_dir.mkdir(parents=True)

        fake_fm = bin_dir / "alis-files"
        fake_fm.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        fake_fm.chmod(0o755)
        (apps_dir / "org.alis.Files.desktop").write_text(
            f"[Desktop Entry]\nName=Files\nExec={fake_fm} %U\nIcon=org.alis.Files\n"
            "Type=Application\nCategories=System;FileTools;FileManager;\nMimeType=inode/directory;\n",
            encoding="utf-8",
        )
        cfg_file = cfg_dir / "config.json"
        cfg_file.write_text(json.dumps({"apps": {"fileManager": "alis-files"}}), encoding="utf-8")

        env = os.environ.copy()
        env["PATH"] = f"{bin_dir}:{env.get('PATH', '')}"
        env["XDG_DATA_HOME"] = str(base / "share")
        env["XDG_DATA_DIRS"] = str(base / "share")

        out = subprocess.check_output(
            [sys.executable, str(HOST / "scripts/default_apps_helper.py"), "resolve-launch", "fileManager", str(cfg_file), "--", "--new"],
            env=env,
            text=True,
        )
        doc = json.loads(out)
        assert doc["ok"] is True, doc
        assert os.path.basename(doc["argv"][0]) == "alis-files", doc
        assert "--new" in doc["argv"], doc

        cfg_file.write_text(
            json.dumps({"apps": {"fileManager": "alis-files", "desktopIds": {"fileManager": "native:org.alis.Files.desktop"}}}),
            encoding="utf-8",
        )
        out2 = subprocess.check_output(
            [sys.executable, str(HOST / "scripts/default_apps_helper.py"), "resolve-launch", "fileManager", str(cfg_file), "--", "--new"],
            env=env,
            text=True,
        )
        doc2 = json.loads(out2)
        assert doc2["ok"] is True and doc2["argv"][0] == str(fake_fm) and "--new" in doc2["argv"], doc2

    # Verify all 4 exclusive Alis IPC bridges exist on host & Companion.
    ws_router = (HOST / "modules/wallpaperSelector/WallpaperSelectorRouter.qml").read_text(encoding="utf-8")
    assert "function apply(filePath: string)" in ws_router and "Wallpapers.select(" in ws_router

    interg_qml = (HOST / "services/AlisIntergration.qml").read_text(encoding="utf-8")
    assert "function openPath(absPath: string)" in interg_qml

    comp_qml = (HOST / "services/AlisCompanion.qml").read_text(encoding="utf-8")
    assert "function sendFiles(pathsJson: string)" in comp_qml

    term_sh = (HOST / "scripts/launch-terminal.sh").read_text(encoding="utf-8")
    assert '--cwd' in term_sh

    if COMPANION.is_dir():
        comp_session = (COMPANION / "AlisSession.qml").read_text(encoding="utf-8")
        assert "function sendFiles(pathsJson)" in comp_session

    # Verify Nautilus removed from Arch/Debian/Fedora/meta dependency lists.
    for rel in (
        "sdata/dist-arch/install-deps.sh",
        "sdata/dist-arch/alis-core/PKGBUILD",
        "sdata/dist-arch/alis-deps/PKGBUILD",
        "sdata/dist-debian/install-deps.sh",
        "sdata/dist-fedora/install-deps.sh",
        "distro/arch/alis-meta/PKGBUILD",
    ):
        txt = (HOST / rel).read_text(encoding="utf-8")
        assert "\n  nautilus\n" not in txt, f"nautilus still present in {rel}"


def test_cli_and_overlay_daemon_if_built() -> None:
    bin_path = Path.home() / ".local/bin/alis-files"
    if not (bin_path.is_file() and os.access(bin_path, os.X_OK)):
        return
    env = {k: v for k, v in os.environ.items() if k not in ("WAYLAND_DISPLAY", "DISPLAY")}
    help_out = subprocess.check_output([str(bin_path), "--help"], env=env, text=True)
    assert "--overlay-daemon" in help_out and "Usage:" in help_out, help_out
    ver_out = subprocess.check_output([str(bin_path), "--version"], env=env, text=True)
    assert ver_out.startswith("alis-files "), ver_out

    with tempfile.TemporaryDirectory(prefix="alis-files-daemon-") as tmp:
        payload = (
            json.dumps({"id": 1, "cmd": "init", "params": {}})
            + "\n"
            + json.dumps({"id": 2, "cmd": "list", "params": {"path": tmp}})
            + "\n"
            + json.dumps({"id": 3, "cmd": "drives", "params": {}})
            + "\n"
        )
        out = subprocess.check_output(
            [str(bin_path), "--overlay-daemon"],
            input=payload,
            env=env,
            text=True,
        )
        lines = [json.loads(line) for line in out.strip().splitlines() if line.strip()]
        by_id = {m["id"]: m for m in lines}
        assert by_id[1]["ok"] is True and "home" in by_id[1]["data"]
        assert by_id[2]["ok"] is True and by_id[2]["data"]["path"] == tmp
        assert by_id[3]["ok"] is True and isinstance(by_id[3]["data"]["drives"], list)
        mps = [d["mount_point"] for d in by_id[3]["data"]["drives"] if d.get("mount_point")]
        devs = [os.path.realpath(d["block_device"]) for d in by_id[3]["data"]["drives"] if d.get("block_device")]
        assert len(mps) == len(set(mps)), f"duplicate drive mount_points: {mps}"
        assert len(devs) == len(set(devs)), f"duplicate drive block_devices: {devs}"


def main() -> None:
    test_plugin_layout_and_qml()
    test_installer_assets_and_uninstall()
    test_host_builtins_and_default_apps()
    test_cli_and_overlay_daemon_if_built()
    print("ALIS_FILES_CONTRACT_PASS layout, qml, overlay, daemon, assets, builtins, default-apps, ipc-bridges, no-nautilus")


if __name__ == "__main__":
    main()
