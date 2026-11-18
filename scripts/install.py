#!/usr/bin/env python3
"""Install a committed Alis-Intergration release without enabling its integrations."""
import argparse
import fcntl
import hashlib
import json
import os
import re
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
PAYLOAD = ("AlisSession.qml", "services", "modules", "assets", "LICENSE")
HELPERS = ("scripts/integrations", "scripts/todo", "scripts/notes")

# Pinned host API 1 entrypoints from Alis/dev. Coordinate any changes there.
EXPECTED_ENTRYPOINTS = {
    "session": "AlisSession.qml",
    "thinkfanSettings": "modules/settings/ThinkfanSettings.qml",
    "tlpSettings": "modules/settings/TlpPowerSettings.qml",
    "nexusSettings": "modules/settings/NexusThemeSettings.qml",
    "nexusTodoSettings": "modules/settings/NexusTodoSettings.qml",
    "tlpRowSettings": "modules/settings/TlpSettingRow.qml",
    "tlpWaffleSettings": "modules/waffle/settings/WTlpPowerSettings.qml",
    "tlpWaffleRowSettings": "modules/waffle/settings/WTlpSettingRow.qml",
    "managedTodo": "services/NexusTodoBackend.qml",
    "dailyTodo": "services/DailyNoteTodoBackend.qml",
}


def plugin_metadata(data):
    """Normalize declarative navigation only; never import optional code."""
    plugins = data.get("plugins", [])  # Older API 1 packages remain usable.
    integrations = data.get("integrations", [])
    settings = data.get("settings", {})
    if not isinstance(plugins, list) or len(plugins) > 32 or not isinstance(integrations, list):
        raise ValueError("Invalid plugin catalog")
    if not isinstance(settings, dict) or any(
            not isinstance(key, str) or not isinstance(path, str)
            or not re.fullmatch(r"modules/(?:[A-Za-z0-9_-]+/)*[A-Za-z0-9_-]+\.qml", path)
            for key, path in settings.items()):
        raise ValueError("Unsafe plugin settings path")
    normalized, seen = [], set()
    def token(value):
        return isinstance(value, str) and re.fullmatch(r"[a-z][a-z0-9_-]{0,47}", value)
    def label(value):
        return isinstance(value, str) and 0 < len(value) <= 80 and value.isprintable()
    for plugin in plugins:
        if not isinstance(plugin, dict):
            raise ValueError("Invalid plugin metadata")
        ident, name, icon = (plugin.get(key) for key in ("id", "name", "icon"))
        if not token(ident) or ident == "management" or ident in seen or ident not in integrations or not label(name) or not token(icon):
            raise ValueError("Invalid plugin identity")
        seen.add(ident)
        capabilities = plugin.get("capabilities")
        if not isinstance(capabilities, list) or not 0 < len(capabilities) <= 16:
            raise ValueError("Invalid plugin capabilities")
        items, ids = [], set()
        for capability in capabilities:
            if not isinstance(capability, dict):
                raise ValueError("Invalid plugin capability")
            cid, title, entry = (capability.get(key) for key in ("id", "name", "settings"))
            if not token(cid) or cid in ids or not label(title) or not isinstance(entry, str) or entry not in settings:
                raise ValueError("Invalid plugin settings reference")
            ids.add(cid)
            item = {"id": cid, "name": title, "settings": entry}
            if "waffleSettings" in capability:
                waffle = capability["waffleSettings"]
                if not isinstance(waffle, str) or waffle not in settings:
                    raise ValueError("Invalid Waffle settings reference")
                item["waffleSettings"] = waffle
            if "view" in capability:
                if entry != "nexusTodo" or capability["view"] not in ("todo", "quicknotes"):
                    raise ValueError("Unsupported settings view")
                item["view"] = capability["view"]
            items.append(item)
        normalized.append({"id": ident, "name": name, "icon": icon, "capabilities": items})
    return normalized


def validate_manifest(manifest):
    if not isinstance(manifest, dict) or manifest.get("id") != "alis-intergration" or (
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
        "nexusSettings": settings.get("nexus"),
        "nexusTodoSettings": settings.get("nexusTodo"),
        "tlpRowSettings": settings.get("tlpRow"),
        "tlpWaffleSettings": settings.get("tlpWaffle"),
        "tlpWaffleRowSettings": settings.get("tlpWaffleRow"),
        "managedTodo": backends.get("managedTodo"),
        "dailyTodo": backends.get("dailyTodo"),
    }
    plugin_metadata(manifest)
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
        rel = path.relative_to(folder)
        if "__pycache__" in rel.parts and path.is_file() and path.suffix in (".pyc", ".pyo"):
            continue
        if path.is_file():
            name = rel.as_posix()
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
    if not all(path in files for path in (*EXPECTED_ENTRYPOINTS.values(), *manifest["settings"].values())):
        raise ValueError("Missing mandatory package entrypoint")
    manifest.update(sourceSha=sha, files=files)
    (target / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")


def owned_link(data_root):
    link = data_root / "current"
    if link.exists() or link.is_symlink():
        if not link.is_symlink() or link.resolve().parent != (data_root / "releases").resolve():
            raise ValueError("Preserve the existing unowned current path before installing")
    return link


def install(data_root, source=ROOT, *, allow_dirty=False, force=False):
    source = Path(source).resolve()
    dirty = bool(subprocess.check_output(
        ["git", "status", "--porcelain", "--untracked-files=all"], cwd=source, text=True).strip())
    if dirty and not allow_dirty:
        raise ValueError("Refusing to install from a dirty working tree; commit or stash changes first")
    head_sha = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=source, text=True).strip()
    releases = data_root / "releases"
    releases.mkdir(parents=True, exist_ok=True)
    link = owned_link(data_root)
    if dirty:
        with tempfile.TemporaryDirectory(prefix=".stage-", dir=releases) as stage:
            payload = Path(stage) / "payload"
            assemble(source, payload, head_sha)
            manifest = json.loads((payload / "manifest.json").read_text())
            files = manifest["files"]
            sha = hashlib.sha1(
                (head_sha + ":" + json.dumps(files, sort_keys=True)).encode("utf-8")
            ).hexdigest()
            manifest["sourceSha"] = sha
            (payload / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
            release = releases / sha
            if release.is_symlink():
                raise ValueError("Existing release is a symlink; preserve it unchanged")
            if release.exists():
                shutil.rmtree(release)
            os.replace(payload, release)
    else:
        sha = head_sha
        release = releases / sha
        if release.is_symlink():
            raise ValueError("Existing release is a symlink; preserve it unchanged")
        if release.exists() and not force:
            manifest_path = release / "manifest.json"
            if manifest_path.is_symlink() or not manifest_path.is_file():
                raise ValueError("Existing release is incomplete; preserve it for inspection")
            manifest = json.loads(manifest_path.read_text())
            validate_manifest(manifest)
            expected = manifest.get("files")
            if (manifest.get("sourceSha") != sha or not isinstance(expected, dict) or not expected
                    or not all(name in expected for name in (*EXPECTED_ENTRYPOINTS.values(), *manifest["settings"].values()))
                    or payload_inventory(release) != expected):
                raise ValueError("Existing release was modified; refusing to overwrite it")
        else:
            with tempfile.TemporaryDirectory(prefix=".stage-", dir=releases) as stage:
                payload = Path(stage) / "payload"
                assemble(source, payload, sha)
                if release.exists():
                    shutil.rmtree(release)
                os.replace(payload, release)
    temporary = data_root / (".current-" + str(os.getpid()))
    try:
        temporary.symlink_to(release.relative_to(data_root))
        os.replace(temporary, link)
    finally:
        temporary.unlink(missing_ok=True)
    return release


def installed_plugins_path(data_root):
    return Path(data_root) / "installed-plugins.json"


def _manifest_plugin_ids(data_root, source=None):
    manifest_path = None
    link = owned_link(data_root)
    if link.exists() and (link / "manifest.json").is_file():
        manifest_path = link / "manifest.json"
    elif source is not None and (Path(source) / "manifest.json").is_file():
        manifest_path = Path(source) / "manifest.json"
    if manifest_path is None:
        return ["tlp", "thinkfan", "nexus", "spaced_repetition", "exercises_tracker"]
    data = json.loads(manifest_path.read_text(encoding="utf-8"))
    return [plugin["id"] for plugin in plugin_metadata(data)]


def load_installed_plugins(data_root, valid_ids=None):
    target = installed_plugins_path(data_root)
    if target.is_symlink():
        raise ValueError("Refusing symlinked installed-plugins.json")
    if not target.exists():
        return None, False
    doc = json.loads(target.read_text(encoding="utf-8"))
    if not isinstance(doc, dict) or doc.get("schemaVersion") != 1 or not isinstance(doc.get("plugins"), list):
        raise ValueError("Invalid installed-plugins.json schema")
    allowed = set(valid_ids) if valid_ids is not None else None
    seen = []
    for item in doc["plugins"]:
        if isinstance(item, str) and item and (allowed is None or item in allowed) and item not in seen:
            seen.append(item)
    return seen, True


def save_installed_plugins(data_root, plugin_ids):
    data_root = Path(data_root)
    data_root.mkdir(parents=True, exist_ok=True)
    target = installed_plugins_path(data_root)
    if target.is_symlink():
        raise ValueError("Refusing symlinked installed-plugins.json")
    unique = []
    for item in plugin_ids:
        if isinstance(item, str) and item and item not in unique:
            unique.append(item)
    payload = json.dumps({"schemaVersion": 1, "plugins": unique}, indent=2) + "\n"
    fd, tmp_path = tempfile.mkstemp(prefix=".installed-plugins-", suffix=".tmp", dir=data_root)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(payload)
        os.chmod(tmp_path, 0o644)
        os.replace(tmp_path, target)
    except Exception:
        Path(tmp_path).unlink(missing_ok=True)
        raise
    return unique


def install_plugin(data_root, plugin_id, source=Path(__file__).resolve().parents[1], *, allow_dirty=False, force=False):
    valid_ids = _manifest_plugin_ids(data_root, source)
    if plugin_id not in valid_ids:
        raise ValueError(f"Unknown plugin id: {plugin_id}")
    link = owned_link(data_root)
    had_package = link.exists() or link.is_symlink()
    release = install(data_root, source=source, allow_dirty=allow_dirty, force=force)
    valid_ids = _manifest_plugin_ids(data_root, release)
    current_ids, explicit = load_installed_plugins(data_root, valid_ids)
    if explicit:
        updated = list(current_ids)
    elif had_package:
        updated = list(valid_ids)
    else:
        updated = []
    if plugin_id not in updated:
        updated.append(plugin_id)
    save_installed_plugins(data_root, updated)
    return release, updated


def remove_plugin(data_root, plugin_id):
    valid_ids = _manifest_plugin_ids(data_root)
    if plugin_id not in valid_ids:
        raise ValueError(f"Unknown plugin id: {plugin_id}")
    link = owned_link(data_root)
    had_package = link.exists()
    current_ids, explicit = load_installed_plugins(data_root, valid_ids)
    if explicit:
        updated = [item for item in current_ids if item != plugin_id]
    elif had_package:
        updated = [item for item in valid_ids if item != plugin_id]
    else:
        return []
    return save_installed_plugins(data_root, updated)


def uninstall(data_root):
    link = owned_link(data_root)
    if link.is_symlink():
        link.unlink()
    selection = installed_plugins_path(data_root)
    if selection.is_file() and not selection.is_symlink():
        selection.unlink()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("install", "uninstall", "install-plugin", "remove-plugin"))
    parser.add_argument("plugin", nargs="?", default=None)
    parser.add_argument("--plugin", dest="plugin_flag", default=None)
    parser.add_argument("--data-home", type=Path, default=Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")))
    parser.add_argument("--allow-dirty", action="store_true")
    parser.add_argument("--force", action="store_true")
    args = parser.parse_args()
    target_plugin = args.plugin_flag or args.plugin
    if args.action in ("install-plugin", "remove-plugin") and not target_plugin:
        raise ValueError(f"{args.action} requires a plugin id")
    canonical = args.data_home / "alis-intergration"
    legacy = args.data_home / "".join(("hada", "lird"))
    if legacy.is_dir() and not legacy.is_symlink() and not canonical.exists():
        os.replace(legacy, canonical)
    data_root = canonical.resolve()
    data_root.mkdir(parents=True, exist_ok=True)
    with (data_root / ".install.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if args.action == "install":
            print("Installed Alis-Intergration:", install(data_root, allow_dirty=args.allow_dirty, force=args.force))
        elif args.action == "install-plugin":
            release, enabled = install_plugin(data_root, target_plugin, allow_dirty=args.allow_dirty, force=args.force)
            print(f"Installed Alis-Intergration plugin {target_plugin}: {release} (plugins={','.join(enabled)})")
        elif args.action == "remove-plugin":
            enabled = remove_plugin(data_root, target_plugin)
            print(f"Removed Alis-Intergration plugin {target_plugin} (plugins={','.join(enabled)})")
        else:
            uninstall(data_root)
            print("Disabled the package link; releases and user data are preserved")
    print("Run alis ipc integrations refresh (legacy host: alis ipc alis-intergration refresh), or restart Alis, to apply the change")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        raise SystemExit(str(error))
