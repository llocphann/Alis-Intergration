#!/usr/bin/env python3
"""Non-launching Obsidian/Tasks capability and rich-mutation bridge.

Safety invariant: no Obsidian CLI process is started until an already-running
Obsidian desktop process has been detected. CLI calls are serialized with a
helper-side lock and never target another vault by name/id.
"""

from __future__ import annotations

import argparse
import contextlib
import fcntl
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import Any, Iterator

sys.dont_write_bytecode = True
SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

import obsidian_todo  # noqa: E402

TASKS_PLUGIN_ID = "obsidian-tasks-plugin"
OBSIDIAN_FLATPAK_ID = "md.obsidian.Obsidian"
CLI_TIMEOUT_SECONDS = 4.0
MUTATION_TIMEOUT_SECONDS = 8.0
LOCK_TIMEOUT_SECONDS = 5.0
_STATUS_TYPES = {
    "TODO", "DONE", "IN_PROGRESS", "ON_HOLD", "CANCELLED", "NON_TASK", "EMPTY"
}
_CORE_STATUSES = [
    {"symbol": " ", "name": "Todo", "nextStatusSymbol": "x", "type": "TODO"},
    {"symbol": "x", "name": "Done", "nextStatusSymbol": " ", "type": "DONE"},
]
_DEFAULT_CUSTOM_STATUSES = [
    {"symbol": "/", "name": "In Progress", "nextStatusSymbol": "x", "type": "IN_PROGRESS"},
    {"symbol": "-", "name": "Cancelled", "nextStatusSymbol": " ", "type": "CANCELLED"},
]


class RuntimeErrorInfo(Exception):
    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code
        self.message = message


def _find_cli() -> str | None:
    found = shutil.which("obsidian")
    if found:
        return found
    # Official Linux registration copies the CLI here. Quickshell may have
    # started before ~/.local/bin was added to the interactive shell PATH.
    fallback = Path.home() / ".local" / "bin" / "obsidian"
    if fallback.is_file() and os.access(fallback, os.X_OK):
        return str(fallback)
    return None


def _flatpak_app_id(process_dir: Path) -> str:
    """Return the Flatpak application ID for one /proc entry, if readable."""
    info = process_dir / "root" / ".flatpak-info"
    try:
        text = info.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""

    in_application = False
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line or line.startswith(("#", ";")):
            continue
        if line.startswith("[") and line.endswith("]"):
            in_application = line[1:-1].strip() == "Application"
            continue
        if not in_application or "=" not in line:
            continue
        key, value = line.split("=", 1)
        if key.strip().lower() == "name":
            return value.strip()
    return ""


def _iter_process_identities() -> Iterator[tuple[str, list[str], str]]:
    current_pid = os.getpid()
    current_uid = os.getuid()
    try:
        scanner = os.scandir("/proc")
    except OSError:
        return
    with scanner:
        for dirent in scanner:
            name = dirent.name
            if not name.isdigit() or int(name) == current_pid:
                continue
            try:
                if dirent.stat(follow_symlinks=False).st_uid != current_uid:
                    continue
            except OSError:
                continue
            entry = Path(dirent.path)
            try:
                exe = Path(os.readlink(entry / "exe")).name
            except OSError:
                exe = ""
            try:
                raw = (entry / "cmdline").read_bytes()
                argv = [
                    part.decode("utf-8", errors="replace")
                    for part in raw.split(b"\0")
                    if part
                ]
            except OSError:
                argv = []
            if _looks_like_obsidian_app(exe, argv):
                yield exe, argv, ""
                continue
            yield exe, argv, _flatpak_app_id(entry)


def _looks_like_obsidian_app(
    exe: str,
    argv: list[str],
    flatpak_app_id: str = "",
) -> bool:
    candidates = [Path(exe).name] if exe else []
    candidates.extend(Path(arg).name for arg in argv[:4] if arg and not arg.startswith("-"))
    lowered = {name.lower() for name in candidates}
    if any("obsidian-cli" in name for name in lowered):
        return False

    # Flatpak's exported launcher ultimately runs through zypak-wrapper and
    # executable names are not a stable host-side identity. Flatpak exposes
    # the effective app metadata at /.flatpak-info inside a running sandbox;
    # reading it through /proc/<pid>/root is detection-only and never launches
    # the Flatpak application.
    if flatpak_app_id == OBSIDIAN_FLATPAK_ID:
        return True

    return bool(lowered.intersection({"obsidian", "obsidian-bin", "obsidian.appimage"}))


def _obsidian_running() -> bool:
    return any(
        _looks_like_obsidian_app(exe, argv, flatpak_app_id)
        for exe, argv, flatpak_app_id in _iter_process_identities()
    )


def runtime_probe() -> dict[str, Any]:
    """Detect Obsidian/CLI presence without invoking the launch-capable CLI."""
    cli = _find_cli()
    running = _obsidian_running()
    return {
        "ok": True,
        "obsidianInstalled": bool(cli or running),
        "obsidianRunning": running,
        "cliRegistered": bool(cli),
        "cliResponsive": False,
        "cliPath": cli or "",
    }


def _resolve_vault(vault_path: str) -> Path:
    raw = str(vault_path or "").strip()
    if not raw:
        raise RuntimeErrorInfo("invalid_vault_path", "vault path is empty")
    try:
        vault = Path(raw).expanduser().resolve(strict=True)
    except (OSError, RuntimeError) as exc:
        raise RuntimeErrorInfo("invalid_vault_path", f"cannot resolve vault path: {exc}") from exc
    if not vault.is_dir() or vault == Path(vault.anchor):
        raise RuntimeErrorInfo("invalid_vault_path", "vault path is not a usable directory")
    return vault


def _lock_path() -> Path:
    runtime_dir = os.environ.get("XDG_RUNTIME_DIR", "").strip()
    if runtime_dir:
        base = Path(runtime_dir)
    else:
        base = Path("/tmp")
    return base / f"alis-{os.getuid()}-obsidian-cli.lock"


@contextlib.contextmanager
def _cli_lock(timeout: float = LOCK_TIMEOUT_SECONDS) -> Iterator[None]:
    path = _lock_path()
    fd = os.open(path, os.O_CREAT | os.O_RDWR | os.O_CLOEXEC, 0o600)
    deadline = time.monotonic() + timeout
    try:
        while True:
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    raise RuntimeErrorInfo("cli_busy", "Obsidian CLI integration is busy")
                time.sleep(0.05)
        yield
    finally:
        try:
            fcntl.flock(fd, fcntl.LOCK_UN)
        finally:
            os.close(fd)


def _run_cli(cli: str, args: list[str], timeout: float) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(
            [cli, *args],
            cwd="/",
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=timeout,
            check=False,
        )
    except subprocess.TimeoutExpired as exc:
        raise RuntimeErrorInfo("cli_timeout", "Obsidian CLI timed out") from exc
    except OSError as exc:
        raise RuntimeErrorInfo("cli_start_failed", f"cannot start Obsidian CLI: {exc}") from exc


def _parse_eval_json(stdout: str) -> dict[str, Any]:
    lines = [line.strip() for line in str(stdout or "").splitlines() if line.strip()]
    for line in reversed(lines):
        candidate = line[3:].strip() if line.startswith("=> ") else line
        try:
            value: Any = json.loads(candidate)
            if isinstance(value, str):
                value = json.loads(value)
            if isinstance(value, dict):
                return value
        except (json.JSONDecodeError, TypeError):
            continue
    raise RuntimeErrorInfo("cli_invalid_output", "Obsidian eval did not return a JSON object")


def _sanitize_statuses(saved: Any) -> list[dict[str, str]]:
    statuses = [dict(item) for item in _CORE_STATUSES]
    custom: Any = _DEFAULT_CUSTOM_STATUSES

    if isinstance(saved, dict):
        status_settings = saved.get("statusSettings")
        if status_settings is not None:
            if not isinstance(status_settings, dict):
                return statuses
            if "customStatuses" in status_settings:
                custom = status_settings.get("customStatuses")
                if not isinstance(custom, list):
                    return statuses

    for item in custom:
        if not isinstance(item, dict):
            continue
        symbol = item.get("symbol")
        name = item.get("name")
        next_symbol = item.get("nextStatusSymbol")
        status_type = item.get("type", "TODO")
        if (
            not isinstance(symbol, str)
            or len(symbol) != 1
            or not isinstance(name, str)
            or not isinstance(next_symbol, str)
            or len(next_symbol) > 1
        ):
            continue
        if status_type not in _STATUS_TYPES:
            status_type = "TODO"

        # Tasks applies core statuses first and ignores later duplicate symbols.
        # An explicitly persisted empty customStatuses list therefore removes
        # the default "/" and "-" registrations instead of restoring them.
        if any(entry["symbol"] == symbol for entry in statuses):
            continue
        statuses.append({
            "symbol": symbol,
            "name": name,
            "nextStatusSymbol": next_symbol,
            "type": status_type,
        })
    return statuses

def _settings_summary(saved: Any) -> dict[str, Any]:
    data = saved if isinstance(saved, dict) else {}
    global_filter = data.get("globalFilter", "")
    if not isinstance(global_filter, str):
        global_filter = ""
    task_format = data.get("taskFormat", "tasksPluginEmoji")
    if task_format not in ("tasksPluginEmoji", "dataview"):
        task_format = "tasksPluginEmoji"
    return {
        "globalFilter": global_filter,
        "taskFormat": task_format,
        "setDoneDate": data.get("setDoneDate", True) is not False,
        "setCancelledDate": data.get("setCancelledDate", True) is not False,
        "recurrenceOnNextLine": data.get("recurrenceOnNextLine", False) is True,
        "removeScheduledDateOnRecurrence":
            data.get("removeScheduledDateOnRecurrence", False) is True,
        "statuses": _sanitize_statuses(data),
    }


def _capability_eval_code() -> str:
    plugin_id = json.dumps(TASKS_PLUGIN_ID)
    return (
        "(async()=>{"
        "const a=app.vault.adapter;"
        "const base=(a&&typeof a.getBasePath==='function')?a.getBasePath():null;"
        f"const p=app.plugins?.plugins?.[{plugin_id}]??app.plugins?.getPlugin?.({plugin_id})??null;"
        "let saved=null;"
        "if(p&&typeof p.loadData==='function'){saved=await p.loadData();}"
        "return JSON.stringify({"
        "vaultPath:base,"
        "tasksPluginEnabled:!!p,"
        "tasksPluginVersion:p?.manifest?.version??'',"
        "tasksApiAvailable:typeof p?.apiV1?.executeToggleTaskDoneCommand==='function',"
        "settings:saved"
        "});"
        "})()"
    )


def _probe_tasks_locked(cli: str, configured_vault: Path) -> dict[str, Any]:
    result = _run_cli(
        cli,
        ["eval", "code=" + _capability_eval_code()],
        CLI_TIMEOUT_SECONDS,
    )
    if result.returncode != 0:
        message = (result.stderr or result.stdout or "Obsidian CLI eval failed").strip()
        raise RuntimeErrorInfo("cli_eval_failed", message[:500])

    payload = _parse_eval_json(result.stdout)
    active_raw = payload.get("vaultPath")
    active_base_path = active_raw if isinstance(active_raw, str) else ""
    active_path = ""
    matches = False
    if active_base_path:
        try:
            active_path = str(Path(active_base_path).expanduser().resolve(strict=True))
            matches = active_path == str(configured_vault)
        except (OSError, RuntimeError):
            active_path = active_base_path

    plugin_enabled = payload.get("tasksPluginEnabled") is True
    api_available = payload.get("tasksApiAvailable") is True
    settings = _settings_summary(payload.get("settings")) if plugin_enabled else None
    return {
        "cliResponsive": True,
        "activeVaultPath": active_path,
        "activeVaultBasePath": active_base_path,
        "activeVaultMatches": matches,
        "tasksPluginInstalled": plugin_enabled,
        "tasksPluginEnabled": plugin_enabled,
        "tasksPluginVersion": str(payload.get("tasksPluginVersion") or ""),
        "tasksApiAvailable": api_available,
        "richMutationAvailable": matches and plugin_enabled and api_available,
        "tasksSettings": settings,
    }


def probe_capabilities(vault_path: str) -> dict[str, Any]:
    vault = _resolve_vault(vault_path)
    result = runtime_probe()
    result.update({
        "activeVaultPath": "",
        "activeVaultBasePath": "",
        "activeVaultMatches": False,
        "tasksPluginInstalled": False,
        "tasksPluginEnabled": False,
        "tasksPluginVersion": "",
        "tasksApiAvailable": False,
        "richMutationAvailable": False,
        "tasksSettings": None,
        "lastError": "",
    })

    # Critical invariant: do not invoke the CLI here if Obsidian is not already
    # running. Official CLI behavior can launch the desktop app on first use.
    if not result["obsidianRunning"]:
        return result
    cli = str(result["cliPath"] or "")
    if not cli:
        result["lastError"] = "Obsidian is running but its CLI is not registered"
        return result

    try:
        with _cli_lock():
            result.update(_probe_tasks_locked(cli, vault))
    except RuntimeErrorInfo as exc:
        result["lastError"] = exc.message
        result["errorCode"] = exc.code
    return result


def _line_range_js() -> str:
    return (
        "function rangeForLine(data,n){"
        "if(!Number.isInteger(n)||n<1)throw new Error('ALIS_BAD_LINE');"
        "let start=0;"
        "for(let line=1;line<n;line++){"
        "let i=start;"
        "while(i<data.length&&data[i]!=='\\n'&&data[i]!=='\\r')i++;"
        "if(i>=data.length)throw new Error('ALIS_CONFLICT');"
        "start=i+(data[i]==='\\r'&&data[i+1]==='\\n'?2:1);"
        "}"
        "let end=start;"
        "while(end<data.length&&data[end]!=='\\n'&&data[end]!=='\\r')end++;"
        "let sepEnd=end;"
        "if(end<data.length)sepEnd=end+(data[end]==='\\r'&&data[end+1]==='\\n'?2:1);"
        "return {start,end,sepEnd,raw:data.slice(start,end),ending:data.slice(end,sepEnd)};"
        "}"
    )


def _toggle_eval_code(
    expected_vault: str,
    note_path: str,
    source_line: int,
    expected_raw: str,
) -> str:
    vault_js = json.dumps(expected_vault, ensure_ascii=False)
    note_js = json.dumps(note_path, ensure_ascii=False)
    raw_js = json.dumps(expected_raw, ensure_ascii=False)
    plugin_js = json.dumps(TASKS_PLUGIN_ID)
    return (
        "(async()=>{"
        f"const expectedVault={vault_js};"
        f"const notePath={note_js};"
        f"const sourceLine={int(source_line)};"
        f"const expectedRaw={raw_js};"
        "const adapter=app.vault.adapter;"
        "if(!adapter||typeof adapter.getBasePath!=='function')"
        "throw new Error('ALIS_NO_FILESYSTEM_ADAPTER');"
        "if(adapter.getBasePath()!==expectedVault)"
        "throw new Error('ALIS_VAULT_MISMATCH');"
        "const file=app.vault.getFileByPath(notePath);"
        "if(!file)throw new Error('ALIS_FILE_MISSING');"
        f"const plugin=app.plugins?.plugins?.[{plugin_js}]??app.plugins?.getPlugin?.({plugin_js})??null;"
        "const toggle=plugin?.apiV1?.executeToggleTaskDoneCommand;"
        "if(typeof toggle!=='function')throw new Error('ALIS_TASKS_API_MISSING');"
        "const transformed=toggle.call(plugin.apiV1,expectedRaw,notePath);"
        "if(typeof transformed!=='string')throw new Error('ALIS_BAD_TASKS_RESULT');"
        + _line_range_js()
        + "await app.vault.process(file,(data)=>{"
        "const r=rangeForLine(data,sourceLine);"
        "if(r.raw!==expectedRaw)throw new Error('ALIS_CONFLICT');"
        "let replacement='';"
        "if(transformed.length>0){"
        "const parts=transformed.split(/\\r?\\n/);"
        "replacement=parts.join(r.ending||'\\n');"
        "if(r.ending)replacement+=r.ending;"
        "}"
        "return data.slice(0,r.start)+replacement+data.slice(r.sepEnd);"
        "});"
        "return 'alis-ok';"
        "})()"
    )


def _map_mutation_cli_error(output: str) -> RuntimeErrorInfo:
    text = str(output or "")
    markers = {
        "ALIS_VAULT_MISMATCH": ("active_vault_mismatch", "active Obsidian vault does not match configured vault"),
        "ALIS_NO_FILESYSTEM_ADAPTER": ("unsupported_adapter", "active Obsidian vault is not a desktop filesystem vault"),
        "ALIS_FILE_MISSING": ("note_not_found", "configured note is not loaded in the active Obsidian vault"),
        "ALIS_TASKS_API_MISSING": ("tasks_api_unavailable", "Obsidian Tasks API v1 is unavailable"),
        "ALIS_BAD_TASKS_RESULT": ("tasks_api_invalid_result", "Obsidian Tasks returned an invalid toggle result"),
        "ALIS_CONFLICT": ("conflict", "task changed before Obsidian could apply the mutation"),
        "ALIS_BAD_LINE": ("conflict", "task source line is invalid"),
    }
    for marker, (code, message) in markers.items():
        if marker in text:
            return RuntimeErrorInfo(code, message)
    return RuntimeErrorInfo("cli_mutation_failed", text.strip()[:500] or "Obsidian Tasks mutation failed")


def toggle_tasks_task(
    vault_path: str,
    note_path: str,
    task_id: str,
    expected_document_sha: str,
) -> dict[str, Any]:
    # The filesystem scan establishes the optimistic reference before any CLI
    # call. It also canonicalizes the configured vault and note paths.
    doc = obsidian_todo._load_document(vault_path, note_path)
    obsidian_todo._require_hashes(doc, expected_document_sha)
    task = obsidian_todo._find_task(doc, task_id)
    configured_vault = doc["vault"]

    runtime = runtime_probe()
    if not runtime["obsidianRunning"]:
        raise RuntimeErrorInfo("obsidian_not_running", "Obsidian must already be running for Tasks-aware mutation")
    cli = str(runtime["cliPath"] or "")
    if not cli:
        raise RuntimeErrorInfo("cli_unavailable", "Obsidian CLI is not registered")

    with _cli_lock():
        capability = _probe_tasks_locked(cli, configured_vault)
        if not capability["activeVaultMatches"]:
            raise RuntimeErrorInfo("active_vault_mismatch", "active Obsidian vault does not match configured vault")
        if not capability["tasksApiAvailable"]:
            raise RuntimeErrorInfo("tasks_api_unavailable", "Obsidian Tasks API v1 is unavailable")

        # Bind the mutating eval to the exact raw FileSystemAdapter base path
        # observed by the immediately preceding capability probe. The probe may
        # resolve a symlink alias to prove physical-vault equality, while the
        # in-eval guard intentionally stays an exact raw comparison so a vault
        # switch between probe and mutation still fails closed.
        active_base_path = capability.get("activeVaultBasePath")
        if not isinstance(active_base_path, str) or not active_base_path:
            raise RuntimeErrorInfo("active_vault_mismatch", "active Obsidian vault path is unavailable")
        code = _toggle_eval_code(
            active_base_path,
            doc["notePath"],
            int(task["sourceLine"]),
            str(task["rawLine"]),
        )

        result = _run_cli(
            cli,
            ["eval", "code=" + code],
            MUTATION_TIMEOUT_SECONDS,
        )
        if result.returncode != 0:
            raise _map_mutation_cli_error((result.stderr or "") + "\n" + (result.stdout or ""))

    # Mutation eval stdout is intentionally not an acknowledgement. Current CLI
    # versions can lose stdout after awaited vault writes. The filesystem is the
    # authority: require a fresh scan and a changed exact source line/document.
    after = obsidian_todo.scan_note(vault_path, note_path)
    if after["document"]["sha256"] == expected_document_sha:
        raise RuntimeErrorInfo("mutation_unverified", "Obsidian Tasks mutation did not change the note")

    old_line_still_present = any(
        item["sourceLine"] == task["sourceLine"] and item["rawLine"] == task["rawLine"]
        for item in after["tasks"]
    )
    if old_line_still_present:
        raise RuntimeErrorInfo("mutation_unverified", "original task line is still present after mutation")

    after["mutation"] = "toggle-tasks"
    after["verified"] = True
    after["capabilities"] = capability
    return after


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("probe-runtime", help="detect Obsidian without invoking its CLI")

    probe = sub.add_parser("probe-capabilities", help="probe active vault and Tasks when Obsidian is already running")
    probe.add_argument("--vault", required=True)

    toggle = sub.add_parser("toggle-tasks", help="toggle one task through Obsidian Tasks API v1")
    toggle.add_argument("--vault", required=True)
    toggle.add_argument("--note", required=True)
    toggle.add_argument("--id", required=True)
    toggle.add_argument("--expected-document-sha", required=True)
    return parser


def _emit(payload: dict[str, Any]) -> None:
    json.dump(payload, sys.stdout, ensure_ascii=False, separators=(",", ":"))
    sys.stdout.write("\n")


def main(argv: list[str] | None = None) -> int:
    args = _build_parser().parse_args(argv)
    try:
        if args.command == "probe-runtime":
            payload = runtime_probe()
        elif args.command == "probe-capabilities":
            payload = probe_capabilities(args.vault)
        elif args.command == "toggle-tasks":
            payload = toggle_tasks_task(
                args.vault, args.note, args.id, args.expected_document_sha
            )
        else:
            raise RuntimeErrorInfo("unsupported_command", f"unsupported command: {args.command}")
        _emit(payload)
        return 0
    except (RuntimeErrorInfo, obsidian_todo.TodoError) as exc:
        _emit({"ok": False, "error": {"code": exc.code, "message": exc.message}})
        return 2
    except Exception as exc:
        _emit({"ok": False, "error": {"code": "internal_error", "message": str(exc)}})
        return 3


if __name__ == "__main__":
    raise SystemExit(main())
