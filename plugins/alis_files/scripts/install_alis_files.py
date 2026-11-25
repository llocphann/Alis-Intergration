#!/usr/bin/env python3
"""Build and install the native Alis Files binary, .desktop entry, icon, and D-Bus FileManager1 service."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

PLUGIN_ROOT = Path(__file__).resolve().parents[1]
NATIVE_DIR = PLUGIN_ROOT / "native"
ASSETS_DIR = PLUGIN_ROOT / "assets"


def _default_bin_dir() -> Path:
    xdg_bin = os.environ.get("XDG_BIN_HOME", "").strip()
    return Path(xdg_bin).expanduser() if xdg_bin else (Path.home() / ".local" / "bin")


def _default_data_home() -> Path:
    xdg_data = os.environ.get("XDG_DATA_HOME", "").strip()
    return Path(xdg_data).expanduser() if xdg_data else (Path.home() / ".local" / "share")


def _default_cache_home() -> Path:
    xdg_cache = os.environ.get("XDG_CACHE_HOME", "").strip()
    return Path(xdg_cache).expanduser() if xdg_cache else (Path.home() / ".cache")


def source_fingerprint(native_dir: Path) -> str:
    h = hashlib.sha256()
    for rel_name in ("Cargo.toml", "Cargo.lock"):
        p = native_dir / rel_name
        if p.is_file():
            h.update(rel_name.encode("utf-8"))
            h.update(p.read_bytes())
    src_dir = native_dir / "src"
    if src_dir.is_dir():
        for path in sorted(src_dir.rglob("*.rs")):
            rel = path.relative_to(native_dir).as_posix()
            h.update(rel.encode("utf-8"))
            h.update(path.read_bytes())
    return h.hexdigest()


def install_desktop_assets(bin_path: Path, data_home: Path, *, set_mime: bool = True) -> dict[str, str]:
    apps_dir = data_home / "applications"
    dbus_dir = data_home / "dbus-1" / "services"
    icons_dir = data_home / "icons" / "hicolor" / "scalable" / "apps"
    apps_dir.mkdir(parents=True, exist_ok=True)
    dbus_dir.mkdir(parents=True, exist_ok=True)
    icons_dir.mkdir(parents=True, exist_ok=True)

    bin_str = str(bin_path)
    exec_bin = f'"{bin_str}"' if (" " in bin_str or "\t" in bin_str) else bin_str

    desktop_src = ASSETS_DIR / "org.alis.Files.desktop"
    desktop_dst = apps_dir / "org.alis.Files.desktop"
    desktop_text = desktop_src.read_text(encoding="utf-8")
    desktop_text = desktop_text.replace("Exec=alis-files", f"Exec={exec_bin}")
    _atomic_write(desktop_dst, desktop_text.encode("utf-8"), 0o644)

    service_src = ASSETS_DIR / "org.freedesktop.FileManager1.service"
    service_dst = dbus_dir / "org.freedesktop.FileManager1.service"
    service_text = service_src.read_text(encoding="utf-8").replace("@ALIS_FILES_BIN@", exec_bin)
    _atomic_write(service_dst, service_text.encode("utf-8"), 0o644)

    icon_src = ASSETS_DIR / "org.alis.Files.svg"
    icon_dst = icons_dir / "org.alis.Files.svg"
    if icon_src.is_file():
        _atomic_write(icon_dst, icon_src.read_bytes(), 0o644)

    if set_mime and shutil.which("xdg-mime"):
        subprocess.run(
            ["xdg-mime", "default", "org.alis.Files.desktop", "inode/directory"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )

    return {
        "desktopFile": str(desktop_dst),
        "dbusService": str(service_dst),
        "iconFile": str(icon_dst),
    }


def _atomic_write(target: Path, data: bytes, mode: int) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(prefix=f".{target.name}-", dir=target.parent)
    tmp_path = Path(tmp_name)
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(data)
        os.chmod(tmp_path, mode)
        os.replace(tmp_path, target)
    except BaseException:
        tmp_path.unlink(missing_ok=True)
        raise


def build_and_install(
    bin_dir: Path,
    data_home: Path,
    cache_home: Path,
    *,
    force: bool = False,
    assets_only: bool = False,
    set_mime: bool = True,
) -> dict:
    bin_dir.mkdir(parents=True, exist_ok=True)
    bin_path = bin_dir / "alis-files"
    stamp_path = cache_home / "alis" / "alis-files-build.sha256"
    fp = source_fingerprint(NATIVE_DIR)

    built = False
    if not assets_only:
        already_up_to_date = (
            not force
            and bin_path.is_file()
            and os.access(bin_path, os.X_OK)
            and stamp_path.is_file()
            and stamp_path.read_text(encoding="utf-8").strip() == fp
        )
        if not already_up_to_date:
            cargo = shutil.which("cargo")
            if not cargo:
                raise RuntimeError("Rust toolchain ('cargo') is required to build Alis Files")
            target_dir = cache_home / "alis" / "alis-files-target"
            target_dir.mkdir(parents=True, exist_ok=True)
            env = os.environ.copy()
            env["CARGO_TARGET_DIR"] = str(target_dir)
            cmd = [
                cargo,
                "build",
                "--release",
                "--manifest-path",
                str(NATIVE_DIR / "Cargo.toml"),
            ]
            subprocess.run(cmd, env=env, stdout=sys.stderr, check=True)
            compiled = target_dir / "release" / "alis-files"
            if not compiled.is_file():
                raise RuntimeError("cargo build completed without producing alis-files binary")
            _atomic_write(bin_path, compiled.read_bytes(), 0o755)
            _atomic_write(stamp_path, (fp + "\n").encode("utf-8"), 0o644)
            built = True

    assets = install_desktop_assets(bin_path, data_home, set_mime=set_mime)
    return {
        "ok": True,
        "installed": bin_path.is_file() and os.access(bin_path, os.X_OK),
        "built": built,
        "binaryPath": str(bin_path),
        "fingerprint": fp,
        **assets,
    }


def uninstall(bin_dir: Path, data_home: Path) -> dict:
    removed = []
    for target in (
        bin_dir / "alis-files",
        data_home / "applications" / "org.alis.Files.desktop",
        data_home / "dbus-1" / "services" / "org.freedesktop.FileManager1.service",
        data_home / "icons" / "hicolor" / "scalable" / "apps" / "org.alis.Files.svg",
    ):
        if target.exists() and not target.is_symlink():
            target.unlink()
            removed.append(str(target))
    return {"ok": True, "removed": removed}


def status(bin_dir: Path, data_home: Path) -> dict:
    bin_path = bin_dir / "alis-files"
    desktop = data_home / "applications" / "org.alis.Files.desktop"
    dbus = data_home / "dbus-1" / "services" / "org.freedesktop.FileManager1.service"
    return {
        "ok": True,
        "installed": bin_path.is_file() and os.access(bin_path, os.X_OK),
        "binaryPath": str(bin_path),
        "desktopInstalled": desktop.is_file(),
        "dbusInstalled": dbus.is_file(),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bin-dir", type=Path, default=_default_bin_dir())
    parser.add_argument("--data-home", type=Path, default=_default_data_home())
    parser.add_argument("--cache-home", type=Path, default=_default_cache_home())
    parser.add_argument("--status", action="store_true")
    parser.add_argument("--uninstall", action="store_true")
    parser.add_argument("--assets-only", action="store_true")
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--no-mime", action="store_true")
    args = parser.parse_args()

    try:
        if args.status:
            print(json.dumps(status(args.bin_dir, args.data_home)))
            return 0
        if args.uninstall:
            print(json.dumps(uninstall(args.bin_dir, args.data_home)))
            return 0
        report = build_and_install(
            args.bin_dir,
            args.data_home,
            args.cache_home,
            force=args.force,
            assets_only=args.assets_only,
            set_mime=not args.no_mime,
        )
        print(json.dumps(report))
        return 0
    except (OSError, RuntimeError, subprocess.CalledProcessError) as exc:
        print(json.dumps({"ok": False, "error": str(exc)}), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
