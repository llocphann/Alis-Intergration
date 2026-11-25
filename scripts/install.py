#!/usr/bin/env python3
"""Install the lightweight Alis-Intergration base and independent per-plugin payloads."""
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
BASE_PAYLOAD = ("AlisSession.qml", "LICENSE")
PLUGIN_IDS = ("tlp", "thinkfan", "nexus", "spaced_repetition", "exercises_tracker", "alis_files")

# Pinned host API 1 entrypoints from Alis/dev.
EXPECTED_ENTRYPOINTS = {
    "session": "AlisSession.qml",
    "thinkfanSettings": "plugins/thinkfan/modules/settings/ThinkfanSettings.qml",
    "tlpSettings": "plugins/tlp/modules/settings/TlpPowerSettings.qml",
    "nexusSettings": "plugins/nexus/modules/settings/NexusThemeSettings.qml",
    "nexusTodoSettings": "plugins/nexus/modules/settings/NexusTodoSettings.qml",
    "tlpRowSettings": "plugins/tlp/modules/settings/TlpSettingRow.qml",
    "tlpWaffleSettings": "plugins/tlp/modules/waffle/settings/WTlpPowerSettings.qml",
    "tlpWaffleRowSettings": "plugins/tlp/modules/waffle/settings/WTlpSettingRow.qml",
    "spacedRepetitionSettings": "plugins/spaced_repetition/modules/settings/DashboardSpacedRepetitionSettings.qml",
    "exercisesTrackerSettings": "plugins/exercises_tracker/modules/settings/DashboardExercisesTrackerSettings.qml",
    "alisFilesSettings": "plugins/alis_files/modules/settings/AlisFilesSettings.qml",
    "managedTodo": "plugins/nexus/services/NexusTodoBackend.qml",
    "dailyTodo": "plugins/nexus/services/DailyNoteTodoBackend.qml",
}

LEGACY_ENTRYPOINTS = {
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

SETTINGS_PATH_RE = re.compile(r"(?:plugins/[a-z][a-z0-9_-]{0,47}/)?modules/(?:[A-Za-z0-9_-]+/)*[A-Za-z0-9_-]+\.qml")
PLUGIN_RELATIVE_SETTINGS_RE = re.compile(r"plugins/([a-z][a-z0-9_-]{0,47})/(.*)")


def plugin_metadata(data):
    """Normalize declarative navigation only; never import optional code."""
    plugins = data.get("plugins", [])  # Older API 1 packages remain usable.
    integrations = data.get("integrations", [])
    settings = data.get("settings", {})
    if not isinstance(plugins, list) or len(plugins) > 32 or not isinstance(integrations, list):
        raise ValueError("Invalid plugin catalog")
    if not isinstance(settings, dict) or any(
            not isinstance(key, str) or not isinstance(path, str)
            or not SETTINGS_PATH_RE.fullmatch(path)
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
        entry_meta = {"id": ident, "name": name, "icon": icon, "capabilities": items}
        if isinstance(plugin.get("helpersScope"), str) and token(plugin["helpersScope"]):
            entry_meta["helpersScope"] = plugin["helpersScope"]
        normalized.append(entry_meta)
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
    plugin_metadata(manifest)
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
    split_entries = {
        **entries,
        "spacedRepetitionSettings": settings.get("spacedRepetition"),
        "exercisesTrackerSettings": settings.get("exercisesTracker"),
        "alisFilesSettings": settings.get("alisFiles"),
    }
    if split_entries != EXPECTED_ENTRYPOINTS and entries != LEGACY_ENTRYPOINTS:
        raise ValueError("Package entrypoints do not match host API 1")


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def payload_inventory(folder, *, ignore_names=("manifest.json",)):
    """Hash regular files; reject unlisted symlinks."""
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
            if name not in ignore_names:
                files[name] = digest(path)
        elif not path.is_dir():
            raise ValueError("Nonregular package payload")
    if len(files) > 512:
        raise ValueError("Package exceeds host file inventory limit")
    return files


def _copy_safe_tree(src, dst):
    if src.is_symlink() or not src.exists():
        raise ValueError(f"Missing or linked package source: {src.name}")
    if src.is_dir():
        for p in src.rglob("*"):
            rel = p.relative_to(src)
            if "target" in rel.parts or "__pycache__" in rel.parts:
                continue
            if p.is_symlink():
                raise ValueError(f"Missing or linked package source: {src.name}")
    dst.parent.mkdir(parents=True, exist_ok=True)
    if src.is_dir():
        shutil.copytree(src, dst, ignore=shutil.ignore_patterns("__pycache__", "*.pyc", "target"))
    else:
        shutil.copy2(src, dst)


def assemble_base(source, target, sha):
    source = Path(source)
    target = Path(target)
    manifest = json.loads((source / "manifest.json").read_text(encoding="utf-8"))
    validate_manifest(manifest)
    for name in BASE_PAYLOAD:
        original = source / name
        if original.is_symlink() or not original.is_file():
            raise ValueError("Missing or linked base source: " + name)
    target.mkdir(parents=True, exist_ok=True)
    for name in BASE_PAYLOAD:
        _copy_safe_tree(source / name, target / name)
    files = payload_inventory(target)
    if set(files) != set(BASE_PAYLOAD):
        raise ValueError("Unexpected base payload inventory")
    manifest.update(sourceSha=sha, layout="base-v2", files=files)
    (target / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")


def assemble_plugin(source, plugin_id, target, sha):
    source = Path(source)
    target = Path(target)
    if plugin_id not in PLUGIN_IDS:
        raise ValueError(f"Unknown plugin id: {plugin_id}")
    plugin_src = source / "plugins" / plugin_id
    if not plugin_src.is_dir():
        raise ValueError(f"Missing plugin directory: plugins/{plugin_id}")
    _copy_safe_tree(plugin_src, target)
    files = payload_inventory(target, ignore_names=("plugin-manifest.json",))
    if not files:
        raise ValueError(f"Empty plugin payload: {plugin_id}")
    plugin_manifest = {
        "schemaVersion": 1,
        "id": plugin_id,
        "hostApi": 1,
        "sourceSha": sha,
        "files": files,
    }
    (target / "plugin-manifest.json").write_text(json.dumps(plugin_manifest, indent=2) + "\n", encoding="utf-8")
    return plugin_manifest


def assemble(source, target, sha, *, plugins=PLUGIN_IDS):
    source = Path(source)
    target = Path(target)
    manifest = json.loads((source / "manifest.json").read_text(encoding="utf-8"))
    validate_manifest(manifest)
    for name in BASE_PAYLOAD:
        original = source / name
        if original.is_symlink() or not original.is_file():
            raise ValueError("Missing or linked base source: " + name)
    target.mkdir()
    for name in BASE_PAYLOAD:
        _copy_safe_tree(source / name, target / name)
    for plugin_id in plugins:
        if plugin_id not in PLUGIN_IDS:
            raise ValueError(f"Unknown plugin id: {plugin_id}")
        _copy_safe_tree(source / "plugins" / plugin_id, target / "plugins" / plugin_id)
    files = payload_inventory(target)
    required = [manifest["session"]]
    if set(plugins) == set(PLUGIN_IDS):
        required.extend(manifest["settings"].values())
        required.extend(manifest["backends"].values())
        required.extend(manifest.get("views", {}).values())
    if not all(path in files for path in required):
        raise ValueError("Missing mandatory package entrypoint")
    manifest.update(sourceSha=sha, layout="split-v2", files=files)
    (target / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")


def owned_link(data_root):
    link = Path(data_root) / "current"
    if link.exists() or link.is_symlink():
        if not link.is_symlink() or link.resolve().parent != (Path(data_root) / "releases").resolve():
            raise ValueError("Preserve the existing unowned current path before installing")
    return link


def _source_revision(source, allow_dirty=False):
    source = Path(source).resolve()
    if (source / ".git").exists():
        dirty = bool(subprocess.check_output(
            ["git", "status", "--porcelain", "--untracked-files=all"], cwd=source, text=True).strip())
        if dirty and not allow_dirty:
            raise ValueError("Refusing to install from a dirty working tree; commit or stash changes first")
        head_sha = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=source, text=True).strip()
        return source, head_sha, dirty
    # Standalone unpacked base / fixture source (non-git directory).
    manifest_path = source / "manifest.json"
    if not manifest_path.is_file():
        raise ValueError(f"Missing manifest.json in {source}")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    sha = str(manifest.get("sourceSha") or hashlib.sha1(manifest_path.read_bytes()).hexdigest())
    return source, sha, False


def _verify_existing_base(release, sha):
    manifest_path = release / "manifest.json"
    if manifest_path.is_symlink() or not manifest_path.is_file():
        raise ValueError("Existing release is incomplete; preserve it for inspection")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    validate_manifest(manifest)
    expected = manifest.get("files")
    if (manifest.get("sourceSha") != sha or not isinstance(expected, dict) or not expected
            or manifest.get("session") not in expected
            or payload_inventory(release) != expected):
        raise ValueError("Existing release was modified; refusing to overwrite it")
    return manifest


def install_base(data_root, source=ROOT, *, allow_dirty=False, force=False):
    data_root = Path(data_root)
    source, head_sha, dirty = _source_revision(source, allow_dirty=allow_dirty)
    releases = data_root / "releases"
    releases.mkdir(parents=True, exist_ok=True)
    link = owned_link(data_root)
    if dirty:
        with tempfile.TemporaryDirectory(prefix=".stage-", dir=releases) as stage:
            payload = Path(stage) / "payload"
            assemble_base(source, payload, head_sha)
            manifest = json.loads((payload / "manifest.json").read_text(encoding="utf-8"))
            sha = hashlib.sha1(
                (head_sha + ":" + json.dumps(manifest["files"], sort_keys=True)).encode("utf-8")
            ).hexdigest()
            manifest["sourceSha"] = sha
            (payload / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
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
            _verify_existing_base(release, sha)
        else:
            with tempfile.TemporaryDirectory(prefix=".stage-", dir=releases) as stage:
                payload = Path(stage) / "payload"
                assemble_base(source, payload, sha)
                if release.exists():
                    shutil.rmtree(release)
                os.replace(payload, release)
    temporary = data_root / (".current-" + str(os.getpid()))
    try:
        temporary.symlink_to(release.relative_to(data_root))
        os.replace(temporary, link)
    finally:
        temporary.unlink(missing_ok=True)
    if not installed_plugins_path(data_root).exists():
        save_installed_plugins(data_root, [])
    return release


def install(data_root, source=ROOT, *, allow_dirty=False, force=False, include_all_plugins=False):
    data_root = Path(data_root)
    if not include_all_plugins:
        return install_base(data_root, source=source, allow_dirty=allow_dirty, force=force)
    source, head_sha, dirty = _source_revision(source, allow_dirty=allow_dirty)
    releases = data_root / "releases"
    releases.mkdir(parents=True, exist_ok=True)
    link = owned_link(data_root)
    if dirty:
        with tempfile.TemporaryDirectory(prefix=".stage-", dir=releases) as stage:
            payload = Path(stage) / "payload"
            assemble(source, payload, head_sha, plugins=PLUGIN_IDS)
            manifest = json.loads((payload / "manifest.json").read_text(encoding="utf-8"))
            sha = hashlib.sha1(
                (head_sha + ":" + json.dumps(manifest["files"], sort_keys=True)).encode("utf-8")
            ).hexdigest()
            manifest["sourceSha"] = sha
            (payload / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
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
            _verify_existing_base(release, sha)
        else:
            with tempfile.TemporaryDirectory(prefix=".stage-", dir=releases) as stage:
                payload = Path(stage) / "payload"
                assemble(source, payload, sha, plugins=PLUGIN_IDS)
                if release.exists():
                    shutil.rmtree(release)
                os.replace(payload, release)
    temporary = data_root / (".current-" + str(os.getpid()))
    try:
        temporary.symlink_to(release.relative_to(data_root))
        os.replace(temporary, link)
    finally:
        temporary.unlink(missing_ok=True)
    save_installed_plugins(data_root, list(PLUGIN_IDS))
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
        return list(PLUGIN_IDS)
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


def install_plugin(data_root, plugin_id, source=ROOT, *, allow_dirty=False, force=False):
    data_root = Path(data_root)
    valid_ids = _manifest_plugin_ids(data_root, source)
    if plugin_id not in valid_ids:
        raise ValueError(f"Unknown plugin id: {plugin_id}")
    link = owned_link(data_root)
    had_package = link.exists() or link.is_symlink()
    if had_package and not (link / "manifest.json").is_file():
        raise ValueError("Existing release is incomplete; preserve it for inspection")
    source_path, sha, _ = _source_revision(source, allow_dirty=allow_dirty)
    if not had_package or force:
        release = install_base(data_root, source=source_path, allow_dirty=allow_dirty, force=force)
    else:
        release = link.resolve()
        # Upgrade lightweight base if needed while keeping installed plugins intact.
        installed_manifest = _verify_existing_base(
            release,
            json.loads((release / "manifest.json").read_text(encoding="utf-8")).get("sourceSha"),
        )
        source_manifest = json.loads((source_path / "manifest.json").read_text(encoding="utf-8"))
        base_outdated = (
            (release / "AlisSession.qml").read_bytes() != (source_path / "AlisSession.qml").read_bytes()
            or installed_manifest.get("sourceSha") != sha
            or any(
                installed_manifest.get(k) != source_manifest.get(k)
                for k in ("integrations", "plugins", "settings", "views", "backends", "scripts")
            )
        )
        if base_outdated:
            release = install_base(data_root, source=source_path, allow_dirty=allow_dirty, force=True)
    plugins_dir = data_root / "plugins"
    if plugins_dir.is_symlink():
        raise ValueError("Refusing symlinked plugins directory")
    plugins_dir.mkdir(parents=True, exist_ok=True)
    plugin_dest = plugins_dir / plugin_id
    if plugin_dest.is_symlink():
        raise ValueError(f"Refusing symlinked plugin directory: {plugin_id}")
    with tempfile.TemporaryDirectory(prefix=f".stage-{plugin_id}-", dir=plugins_dir) as stage:
        staged = Path(stage) / plugin_id
        assemble_plugin(source_path, plugin_id, staged, sha)
        if plugin_dest.exists():
            backup = Path(stage) / "old"
            os.replace(plugin_dest, backup)
            os.replace(staged, plugin_dest)
        else:
            os.replace(staged, plugin_dest)

    current_ids, explicit = load_installed_plugins(data_root, valid_ids)
    updated = list(current_ids) if explicit else []
    if plugin_id not in updated:
        updated.append(plugin_id)
    save_installed_plugins(data_root, updated)
    return release, updated


def remove_plugin(data_root, plugin_id):
    data_root = Path(data_root)
    valid_ids = _manifest_plugin_ids(data_root)
    if plugin_id not in valid_ids:
        raise ValueError(f"Unknown plugin id: {plugin_id}")
    plugin_dest = data_root / "plugins" / plugin_id
    if plugin_dest.is_symlink():
        raise ValueError(f"Refusing symlinked plugin directory: {plugin_id}")
    if plugin_dest.exists():
        shutil.rmtree(plugin_dest)
    link = owned_link(data_root)
    had_package = link.exists()
    current_ids, explicit = load_installed_plugins(data_root, valid_ids)
    if explicit:
        updated = [item for item in current_ids if item != plugin_id]
    elif had_package:
        # Legacy monolithic symlink migration without installed-plugins.json.
        updated = [item for item in valid_ids if item != plugin_id]
    else:
        return []
    return save_installed_plugins(data_root, updated)


def uninstall(data_root):
    data_root = Path(data_root)
    link = owned_link(data_root)
    if link.is_symlink():
        link.unlink()
    plugins_dir = data_root / "plugins"
    if plugins_dir.is_dir() and not plugins_dir.is_symlink():
        shutil.rmtree(plugins_dir)
    selection = installed_plugins_path(data_root)
    if selection.is_file() and not selection.is_symlink():
        selection.unlink()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("install", "install-base", "install-all", "uninstall", "install-plugin", "remove-plugin"))
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
        if args.action in ("install", "install-base"):
            print("Installed Alis-Intergration base:", install_base(data_root, allow_dirty=args.allow_dirty, force=args.force))
        elif args.action == "install-all":
            print("Installed Alis-Intergration (all plugins):", install(data_root, allow_dirty=args.allow_dirty, force=args.force, include_all_plugins=True))
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
