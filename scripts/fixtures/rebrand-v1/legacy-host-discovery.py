#!/usr/bin/env python3
"""Finite, read-only discovery of a committed optional integration package."""
import hashlib
import json
import os
from pathlib import Path
import re
import sys

ENTRYPOINTS = {
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
                if entry != "obsidianTodo" or capability["view"] not in ("todo", "quicknotes"):
                    raise ValueError("Unsupported settings view")
                item["view"] = capability["view"]
            items.append(item)
        normalized.append({"id": ident, "name": name, "icon": icon, "capabilities": items})
    return normalized


def inspect_package(package):
    result = {"available": False, "diagnostic": "not-installed"}
    try:
        manifest = package / "manifest.json"
        if not manifest.is_file():
            return result
        if manifest.is_symlink() or manifest.stat().st_size > 65536:
            raise ValueError("oversized manifest")
        data = json.loads(manifest.read_text())
        if not isinstance(data, dict):
            raise ValueError("manifest must be an object")
        if data.get("id") != "hadalird" or type(data.get("hostApi")) is not int or data["hostApi"] != 1:
            return {**result, "diagnostic": "incompatible-package"}
        settings, backends = data.get("settings", {}), data.get("backends", {})
        if not isinstance(settings, dict) or not isinstance(backends, dict):
            raise ValueError("invalid entrypoints")
        entries = {"session": data.get("session"), "tlpSettings": settings.get("tlp"), "thinkfanSettings": settings.get("thinkfan"),
                   "obsidianSettings": settings.get("obsidian"),
                   "obsidianTodoSettings": settings.get("obsidianTodo"), "tlpRowSettings": settings.get("tlpRow"),
                   "tlpWaffleSettings": settings.get("tlpWaffle"), "tlpWaffleRowSettings": settings.get("tlpWaffleRow"),
                   "managedTodo": backends.get("managedTodo"),
                   "dailyTodo": backends.get("dailyTodo")}
        if entries != ENTRYPOINTS:
            raise ValueError("unexpected entrypoints")
        plugins = plugin_metadata(data)
        root = package.resolve()
        hashes = data.get("files")
        if not isinstance(hashes, dict) or not hashes or len(hashes) > 512:
            raise ValueError("missing payload identity")
        if not all(name in hashes for name in (*ENTRYPOINTS.values(), *settings.values())):
            raise ValueError("incomplete package")
        inventory = {}
        total = 0
        for path in root.rglob("*"):
            if path.is_symlink():
                raise ValueError("linked payload")
            if path.is_file() and path != manifest.resolve():
                if len(inventory) >= 512 or path.stat().st_size > 2 * 1024 * 1024:
                    raise ValueError("oversized payload")
                total += path.stat().st_size
                if total > 24 * 1024 * 1024:
                    raise ValueError("oversized package")
                inventory[path.relative_to(root).as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
            elif not path.is_file() and not path.is_dir():
                raise ValueError("nonregular payload")
        for name, digest in hashes.items():
            if not isinstance(name, str) or not isinstance(digest, str) or not re.fullmatch(r"[0-9a-f]{64}", digest):
                raise ValueError("invalid payload identity")
            if inventory.get(name) != digest:
                raise ValueError("modified payload")
        if inventory != hashes:
            raise ValueError("unlisted payload")
        version, sha = data.get("version"), data.get("sourceSha")
        if not isinstance(version, str) or not version or len(version) > 64 or not isinstance(sha, str) or not re.fullmatch(r"[0-9a-f]{40}", sha):
            raise ValueError("invalid revision")
        return {"available": True, "diagnostic": "ready", "root": str(root),
                "version": version, "sourceSha": sha, "plugins": plugins,
                "settings": settings, "pluginMetadataAvailable": bool(plugins)}
    except (OSError, ValueError, TypeError):
        return {**result, "diagnostic": "invalid-package"}


def inspect(shell_root, data_home=None):
    user_data = Path(data_home or os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "hadalird"
    package = Path(shell_root) / "optional/hadalird"
    if not package.exists():
        package = user_data / "current"
    result = inspect_package(package)
    result["canRollback"] = False
    try:
        previous_file = user_data / ".previous"
        if previous_file.is_file() and not previous_file.is_symlink() and previous_file.stat().st_size <= 64:
            previous = previous_file.read_text().strip()
            prior = user_data / "releases" / previous
            if re.fullmatch(r"[0-9a-f]{40}", previous) and not prior.is_symlink():
                report = inspect_package(prior)
                result["canRollback"] = report.get("available") is True and report.get("sourceSha") == previous
        catalog = json.loads((Path(shell_root) / "defaults/integration-plugins.json").read_text())
        result["catalog"] = plugin_metadata(catalog)
    except (OSError, ValueError, TypeError):
        result["catalog"] = []
    return result


if __name__ == "__main__":
    print(json.dumps(inspect(sys.argv[1] if len(sys.argv) == 2 else Path(__file__).resolve().parents[1])))
