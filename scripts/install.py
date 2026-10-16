#!/usr/bin/env python3
"""Install a committed Hadalird release without enabling its integrations."""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
PAYLOAD = ("HadalisSession.qml", "services", "modules", "assets", "LICENSE")
HELPERS = ("scripts/integrations", "scripts/todo", "scripts/notes")

# Pinned host API 1 entrypoints from Alis/dev. Coordinate any changes there.
EXPECTED_ENTRYPOINTS = {
    "session": "HadalisSession.qml",
    "thinkfanSettings": "modules/settings/ThinkfanSettings.qml",
    "tlpSettings": "modules/settings/TlpPowerSettings.qml",
    "obsidianSettings": "modules/settings/ObsidianThemeSettings.qml",
    "obsidianTodoSettings": "modules/settings/ObsidianTodoSettings.qml",
    "tlpRowSettings": "modules/settings/TlpSettingRow.qml",
    "tlpWaffleSettings": "modules/waffle/settings/WTlpPowerSettings.qml",
    "tlpWaffleRowSettings": "modules/waffle/settings/WTlpSettingRow.qml",
    "managedTodo": "services/ObsidianTodoBackend.qml",
    "dailyTodo": "services/DailyNoteTodoBackend.qml",
}


def validate_manifest(manifest):
    if not isinstance(manifest, dict) or manifest.get("id") != "hadalird" or (
            type(manifest.get("hostApi")) is not int or manifest["hostApi"] != 1):
        raise ValueError("Incompatible package or host API")
    version = manifest.get("version")
    if not isinstance(version, str) or not version or len(version) > 64:
        raise ValueError("Invalid package version")
    settings, backends = manifest.get("settings"), manifest.get("backends")
    if not isinstance(settings, dict) or not isinstance(backends, dict):
        raise ValueError("Invalid package entrypoints")
    entries = {
        "session": manifest.get("session"),
        "thinkfanSettings": settings.get("thinkfan"),
        "tlpSettings": settings.get("tlp"),
        "obsidianSettings": settings.get("obsidian"),
        "obsidianTodoSettings": settings.get("obsidianTodo"),
        "tlpRowSettings": settings.get("tlpRow"),
        "tlpWaffleSettings": settings.get("tlpWaffle"),
        "tlpWaffleRowSettings": settings.get("tlpWaffleRow"),
        "managedTodo": backends.get("managedTodo"),
        "dailyTodo": backends.get("dailyTodo"),
    }
    if entries != EXPECTED_ENTRYPOINTS:
        raise ValueError("Package entrypoints do not match host API 1")


def payload_inventory(folder):
    """Hash exactly the regular release files; reject unlisted symlinks."""
    if folder.is_symlink() or not folder.is_dir():
        raise ValueError("Invalid package release directory")
    files = {}
    for path in folder.rglob("*"):
        if path.is_symlink():
            raise ValueError("Symlink found in immutable package release")
        if path.is_file():
            name = str(path.relative_to(folder))
            if name != "manifest.json":
                files[name] = digest(path)
        elif not path.is_dir():
            raise ValueError("Nonregular package payload")
    if len(files) > 512:
        raise ValueError("Package exceeds host file inventory limit")
    return files


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def assemble(source, target, sha):
    manifest = json.loads((source / "manifest.json").read_text())
    validate_manifest(manifest)
    # Never import source bytes through links outside the pinned checkout.
    for name in PAYLOAD + HELPERS:
        original = source / name
        if original.is_symlink() or not original.exists() or (
                original.is_dir() and any(p.is_symlink() for p in original.rglob("*"))):
            raise ValueError("Missing or linked package source: " + name)
    target.mkdir()
    for name in PAYLOAD + HELPERS:
        original, output = source / name, target / name
        output.parent.mkdir(parents=True, exist_ok=True)
        if original.is_dir():
            shutil.copytree(original, output, ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))
        else:
            shutil.copy2(original, output)
    files = payload_inventory(target)
    if not all(path in files for path in EXPECTED_ENTRYPOINTS.values()):
        raise ValueError("Missing mandatory package entrypoint")
    manifest.update(sourceSha=sha, files=files)
    (target / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")


def owned_link(data_root):
    link = data_root / "current"
    if link.exists() or link.is_symlink():
        if not link.is_symlink() or link.resolve().parent != (data_root / "releases").resolve():
            raise ValueError("Preserve the existing unowned current path before installing")
    return link


def install(data_root, source=ROOT):
    source = Path(source).resolve()
    sha = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=source, text=True).strip()
    dirty = subprocess.check_output(["git", "status", "--porcelain", "--untracked-files=all"], cwd=source, text=True)
    if dirty:
        raise ValueError("Commit source changes before installing an exact Hadalird revision")
    releases = data_root / "releases"
    releases.mkdir(parents=True, exist_ok=True)
    link = owned_link(data_root)
    release = releases / sha
    if release.is_symlink():
        raise ValueError("Existing release is a symlink; preserve it unchanged")
    if release.exists():
        manifest_path = release / "manifest.json"
        if manifest_path.is_symlink():
            raise ValueError("Existing release manifest is linked; preserve it unchanged")
        manifest = json.loads(manifest_path.read_text())
        validate_manifest(manifest)
        if manifest.get("sourceSha") != sha:
            raise ValueError("Existing release identity does not match")
        expected = manifest.get("files")
        if not isinstance(expected, dict) or not all(
                name in expected for name in EXPECTED_ENTRYPOINTS.values()):
            raise ValueError("Existing release lacks mandatory payload identities")
        if payload_inventory(release) != expected:
            raise ValueError("Existing release was modified; preserve it before reinstalling")
    else:
        with tempfile.TemporaryDirectory(prefix=".stage-", dir=releases) as stage:
            payload = Path(stage) / "payload"
            assemble(source, payload, sha)
            os.replace(payload, release)
    temporary = data_root / (".current-" + str(os.getpid()))
    try:
        temporary.symlink_to(release.relative_to(data_root))
        os.replace(temporary, link)
    finally:
        temporary.unlink(missing_ok=True)
    return release


def uninstall(data_root):
    link = owned_link(data_root)
    if link.is_symlink():
        link.unlink()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("install", "uninstall"))
    parser.add_argument("--data-home", type=Path, default=Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")))
    args = parser.parse_args()
    data_root = (args.data_home / "hadalird").resolve()
    data_root.mkdir(parents=True, exist_ok=True)
    with (data_root / ".install.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if args.action == "install":
            print("Installed Hadalird:", install(data_root))
        else:
            uninstall(data_root)
            print("Disabled the package link; releases and user data are preserved")
    print("Run inir ipc hadalird refresh, or restart Hadalis, to apply the change")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        raise SystemExit(str(error))
