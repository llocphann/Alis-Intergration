#!/usr/bin/env python3
"""Independent heading-based Markdown Todo helper.

The filesystem Markdown note is canonical. Obsidian or any third-party plugin
may use the same file, but this helper does not require or invoke them.
"""
from __future__ import annotations

import argparse
import codecs
import json
import re
import sys
from datetime import date as Date
from pathlib import Path, PurePosixPath
from typing import Any

import obsidian_todo as core
import agenda_metadata

DEFAULT_FOLDER = "00_Capture/01_Journal"
DEFAULT_FORMAT = "YYYY/MMMM/DD-MM-YYYY-dddd"
DEFAULT_HEADING = "Tasks"
DEFAULT_HEADING_LEVEL = 2
DEFAULT_DURATION_MINUTES = 30

_HEADING_RE = re.compile(r"^(#{1,6})[ \t]+(.+?)[ \t]*#*[ \t]*$")
_GROUP_RE = re.compile(r"^\s*\*\*(.+?)\*\*\s*$")
_TIME_RE = re.compile(
    r"^(?P<start>(?:[01]?\d|2[0-3]):[0-5]\d)"
    r"(?:\s*-\s*(?P<end>(?:[01]?\d|2[0-3]):[0-5]\d))?"
    r"(?:\s+|$)"
)


def _parse_date(value: str | None) -> Date:
    if value is None or not str(value).strip():
        return Date.today()
    try:
        return Date.fromisoformat(str(value).strip())
    except ValueError as exc:
        raise core.TodoError("invalid_date", "date must use YYYY-MM-DD") from exc


def _render_daily_path(folder: str, fmt: str, day: Date) -> str:
    raw_folder = str(folder or "").strip().strip("/")
    raw_format = str(fmt or "").strip().strip("/")
    if not raw_format:
        raise core.TodoError("invalid_daily_format", "Markdown note path pattern is empty")
    tokens = {
        "YYYY": f"{day.year:04d}",
        "MMMM": day.strftime("%B"),
        "dddd": day.strftime("%A"),
        "MM": f"{day.month:02d}",
        "DD": f"{day.day:02d}",
    }
    rendered = raw_format
    for token in ("YYYY", "MMMM", "dddd", "MM", "DD"):
        rendered = rendered.replace(token, tokens[token])
    if "%" in rendered:
        raise core.TodoError("invalid_daily_format", "strftime-style '%' tokens are not supported")
    if not rendered.lower().endswith(".md"):
        rendered += ".md"
    joined = PurePosixPath(raw_folder, rendered).as_posix() if raw_folder else PurePosixPath(rendered).as_posix()
    core._normalize_note_path(joined)
    return joined


def resolve_daily_note(
    vault_path: str,
    folder: str = DEFAULT_FOLDER,
    fmt: str = DEFAULT_FORMAT,
    day: str | None = None,
) -> tuple[Path, str, Path, Date]:
    resolved_day = _parse_date(day)
    note_path = _render_daily_path(folder, fmt, resolved_day)
    try:
        vault, normalized, resolved = core.resolve_note(vault_path, note_path)
    except core.TodoError as exc:
        if exc.code == "note_not_found":
            raise core.TodoError(
                "daily_note_not_found", f"task note does not exist: {note_path}"
            ) from exc
        raise
    return vault, normalized, resolved, resolved_day


def _load_document(
    vault_path: str,
    folder: str,
    fmt: str,
    day: str | None,
    heading: str,
    heading_level: int,
) -> dict[str, Any]:
    if not 1 <= int(heading_level) <= 6:
        raise core.TodoError("invalid_planner_heading", "heading level must be between 1 and 6")
    clean_heading = str(heading or "").strip()
    if not clean_heading:
        raise core.TodoError("invalid_planner_heading", "task heading is empty")

    vault, note_path, resolved, resolved_day = resolve_daily_note(
        vault_path, folder, fmt, day
    )
    try:
        raw = resolved.read_bytes()
    except OSError as exc:
        raise core.TodoError("note_read_failed", f"cannot read task note: {exc}") from exc

    has_bom = raw.startswith(codecs.BOM_UTF8)
    payload = raw[len(codecs.BOM_UTF8):] if has_bom else raw
    try:
        text = payload.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise core.TodoError("invalid_utf8", f"task note is not valid UTF-8: {exc}") from exc

    lines = text.splitlines(keepends=True)
    outside = core._outside_fence_flags(lines)
    matches: list[int] = []
    for index, physical in enumerate(lines):
        if not outside[index]:
            continue
        match = _HEADING_RE.match(physical.rstrip("\r\n"))
        if match and len(match.group(1)) == int(heading_level) and match.group(2).strip() == clean_heading:
            matches.append(index)
    if len(matches) != 1:
        raise core.TodoError(
            "invalid_planner_section",
            f"expected exactly one level-{heading_level} heading named '{clean_heading}'",
        )

    start_index = matches[0]
    end_index = len(lines)
    for index in range(start_index + 1, len(lines)):
        if not outside[index]:
            continue
        match = _HEADING_RE.match(lines[index].rstrip("\r\n"))
        if match and len(match.group(1)) <= int(heading_level):
            end_index = index
            break

    return {
        "vault": vault,
        "notePath": note_path,
        "resolved": resolved,
        "date": resolved_day.isoformat(),
        "raw": raw,
        "bom": has_bom,
        "lines": lines,
        "outside": outside,
        "startIndex": start_index,
        "endIndex": end_index,
        "heading": clean_heading,
        "headingLevel": int(heading_level),
    }


def _section_text(doc: dict[str, Any]) -> str:
    return "".join(doc["lines"][doc["startIndex"] + 1:doc["endIndex"]])


def _time_metadata(content: str, default_duration: int) -> tuple[str, str, str, int | None]:
    match = _TIME_RE.match(content)
    if match is None:
        return content, "", "", None
    start = match.group("start") or ""
    end = match.group("end") or ""
    clean = content[match.end():].strip()
    if not end:
        return clean, start, "", int(default_duration)
    sh, sm = map(int, start.split(":"))
    eh, em = map(int, end.split(":"))
    start_minutes = sh * 60 + sm
    end_minutes = eh * 60 + em
    if end_minutes <= start_minutes:
        end_minutes += 24 * 60
    return clean, start, end, end_minutes - start_minutes


def _group_label(raw_line: str) -> str:
    match = _GROUP_RE.match(raw_line)
    return match.group(1).strip().rstrip(",").strip() if match else ""


def _task_from_line(
    doc: dict[str, Any], index: int, group: str, default_duration: int
) -> dict[str, Any] | None:
    if not doc["outside"][index]:
        return None
    raw_line = doc["lines"][index].rstrip("\r\n")
    match = core._TASK_RE.match(raw_line)
    if match is None:
        return None
    indent, list_marker, status_char, raw_content = match.groups()
    raw_content, agenda = agenda_metadata.split(raw_content)
    content, start_time, end_time, duration = _time_metadata(raw_content, default_duration)
    raw_hash = core._sha256_text(raw_line)
    source_line = index + 1
    task_id = core._sha256_text(
        doc["notePath"] + "\x00" + str(source_line) + "\x00" + raw_hash
    )[:24]
    status_type = core._status_type(status_char)
    result = {
        "content": content,
        "rawContent": raw_content,
        "done": status_type == "DONE",
        "id": task_id,
        "statusChar": status_char,
        "statusType": status_type,
        "sourcePath": doc["notePath"],
        "sourceLine": source_line,
        "sourceDate": doc["date"],
        "rawLine": raw_line,
        "rawHash": raw_hash,
        "indent": indent,
        "listMarker": list_marker,
        "group": group,
        "startTime": start_time,
        "endTime": end_time,
        "durationMinutes": duration,
        "_index": index,
        "_match": match,
    }
    if agenda:
        result['agenda']=agenda
        result['date']=str(agenda.get('date',''))
    return result


def _tasks(doc: dict[str, Any], default_duration: int) -> list[dict[str, Any]]:
    result: list[dict[str, Any]] = []
    group = ""
    for index in range(doc["startIndex"] + 1, doc["endIndex"]):
        label = _group_label(doc["lines"][index].rstrip("\r\n"))
        if label:
            group = label
            continue
        task = _task_from_line(doc, index, group, default_duration)
        if task is not None:
            result.append(task)
    return result


def _public_task(task: dict[str, Any]) -> dict[str, Any]:
    return {key: value for key, value in task.items() if not key.startswith("_")}


def _scan_payload(doc: dict[str, Any], default_duration: int) -> dict[str, Any]:
    return {
        "ok": True,
        "mode": "markdown-note",
        "vaultPath": str(doc["vault"]),
        "notePath": doc["notePath"],
        "noteFullPath": str(doc["resolved"]),
        "sourceDate": doc["date"],
        "document": {
            "bom": doc["bom"],
            "newline": core._newline_kind(doc["raw"]),
            "finalNewline": doc["raw"].endswith((b"\n", b"\r")),
            "sha256": core._sha256_bytes(doc["raw"]),
        },
        "managed": {
            "kind": "heading",
            "heading": doc["heading"],
            "headingLevel": doc["headingLevel"],
            "startLine": doc["startIndex"] + 1,
            "endLine": doc["endIndex"] + 1,
            "sha256": core._sha256_text(_section_text(doc)),
        },
        "tasks": [_public_task(task) for task in _tasks(doc, default_duration)],
    }


def scan_daily_note(
    vault_path: str,
    folder: str = DEFAULT_FOLDER,
    fmt: str = DEFAULT_FORMAT,
    day: str | None = None,
    heading: str = DEFAULT_HEADING,
    heading_level: int = DEFAULT_HEADING_LEVEL,
    default_duration: int = DEFAULT_DURATION_MINUTES,
) -> dict[str, Any]:
    return _scan_payload(
        _load_document(vault_path, folder, fmt, day, heading, heading_level),
        default_duration,
    )


def _require_hashes(
    doc: dict[str, Any], expected_document_sha: str, expected_section_sha: str | None = None
) -> None:
    if not expected_document_sha:
        raise core.TodoError("missing_precondition", "expected document hash is required")
    if core._sha256_bytes(doc["raw"]) != expected_document_sha:
        raise core.TodoError("conflict", "daily note changed since the last scan")
    if expected_section_sha is not None and core._sha256_text(_section_text(doc)) != expected_section_sha:
        raise core.TodoError("conflict", "configured task section changed since the last scan")


def _find_task(doc: dict[str, Any], task_id: str, default_duration: int) -> dict[str, Any]:
    first_match: dict[str, Any] | None = None
    match_count = 0
    group = ""
    for index in range(doc["startIndex"] + 1, doc["endIndex"]):
        label = _group_label(doc["lines"][index].rstrip("\r\n"))
        if label:
            group = label
            continue
        task = _task_from_line(doc, index, group, default_duration)
        if task is not None and task["id"] == task_id:
            match_count += 1
            if first_match is None:
                first_match = task
    if match_count != 1 or first_match is None:
        raise core.TodoError("conflict", "task reference is stale or ambiguous")
    return first_match


def _preferred_newline(doc: dict[str, Any]) -> str:
    for index in range(doc["startIndex"], min(len(doc["lines"]), doc["endIndex"] + 1)):
        physical = doc["lines"][index]
        if physical.endswith("\r\n"):
            return "\r\n"
        if physical.endswith("\n"):
            return "\n"
        if physical.endswith("\r"):
            return "\r"
    kind = core._newline_kind(doc["raw"])
    return "\r\n" if kind == "crlf" else ("\r" if kind == "cr" else "\n")


def _encode_document(doc: dict[str, Any], lines: list[str]) -> bytes:
    payload = "".join(lines).encode("utf-8")
    return codecs.BOM_UTF8 + payload if doc["bom"] else payload


def _format_task_text(text: str, start_time: str = "", end_time: str = "") -> str:
    clean = str(text or "").strip()
    if not clean or any(char in clean for char in ("\n", "\r", "\x00")):
        raise core.TodoError("invalid_task_text", "task text must be a non-empty single line")
    start = str(start_time or "").strip()
    end = str(end_time or "").strip()
    for label, value in (("start", start), ("end", end)):
        if value and not re.fullmatch(r"(?:[01]?\d|2[0-3]):[0-5]\d", value):
            raise core.TodoError("invalid_task_time", f"{label} time must use HH:mm")
    if end and not start:
        raise core.TodoError("invalid_task_time", "end time requires a start time")
    if start and end:
        return f"{start} - {end} {clean}"
    if start:
        return f"{start} {clean}"
    return clean


def _target_group(start_time: str) -> str:
    if not start_time:
        return ""
    hour = int(start_time.split(":", 1)[0])
    return "morning" if hour < 12 else ("afternoon" if hour < 18 else "evening")


def _section_append_index(doc: dict[str, Any]) -> int:
    """Insert before trailing whitespace/thematic break that closes the section."""
    index = doc["endIndex"]
    while index > doc["startIndex"] + 1 and not doc["lines"][index - 1].strip():
        index -= 1
    if index > doc["startIndex"] + 1 and doc["lines"][index - 1].strip() in ("---", "***", "___"):
        return index - 1
    return index


def _insertion_index(doc: dict[str, Any], start_time: str) -> int:
    target = _target_group(start_time)
    if target:
        group_start = -1
        group_end = _section_append_index(doc)
        for index in range(doc["startIndex"] + 1, doc["endIndex"]):
            label = _group_label(doc["lines"][index].rstrip("\r\n")).lower()
            if not label:
                continue
            if group_start >= 0:
                group_end = index
                break
            if target in label:
                group_start = index
        if group_start >= 0:
            return group_end
    return _section_append_index(doc)


def _mutation_result(common: dict[str, Any], action: str) -> dict[str, Any]:
    result = scan_daily_note(**common)
    result["mutation"] = action
    return result


def add_task(
    vault_path: str, folder: str, fmt: str, day: str | None, heading: str,
    heading_level: int, default_duration: int, text: str, start_time: str,
    end_time: str, expected_document_sha: str, expected_section_sha: str,
) -> dict[str, Any]:
    doc = _load_document(vault_path, folder, fmt, day, heading, heading_level)
    _require_hashes(doc, expected_document_sha, expected_section_sha)
    lines = list(doc["lines"])
    lines.insert(
        _insertion_index(doc, start_time),
        "- [ ] " + _format_task_text(text, start_time, end_time) + _preferred_newline(doc),
    )
    core._atomic_replace_if_unchanged(doc, _encode_document(doc, lines))
    common = {
        "vault_path": vault_path, "folder": folder, "fmt": fmt, "day": day,
        "heading": heading, "heading_level": heading_level,
        "default_duration": default_duration,
    }
    return _mutation_result(common, "add")


def toggle_task(
    vault_path: str, folder: str, fmt: str, day: str | None, heading: str,
    heading_level: int, default_duration: int, task_id: str,
    expected_document_sha: str,
) -> dict[str, Any]:
    doc = _load_document(vault_path, folder, fmt, day, heading, heading_level)
    _require_hashes(doc, expected_document_sha)
    task = _find_task(doc, task_id, default_duration)
    if task["statusChar"] not in (" ", "x", "X"):
        raise core.TodoError(
            "unsupported_task_status",
            "Markdown source mode only toggles ordinary space/x checkbox states",
        )
    raw_line = task["rawLine"]
    start, end = task["_match"].span(3)
    next_status = " " if task["statusChar"] in ("x", "X") else "x"
    physical = doc["lines"][task["_index"]]
    replacement = raw_line[:start] + next_status + raw_line[end:] + physical[len(raw_line):]
    lines = list(doc["lines"])
    lines[task["_index"]] = replacement
    core._atomic_replace_if_unchanged(doc, _encode_document(doc, lines))
    common = {
        "vault_path": vault_path, "folder": folder, "fmt": fmt, "day": day,
        "heading": heading, "heading_level": heading_level,
        "default_duration": default_duration,
    }
    return _mutation_result(common, "toggle")


def delete_task(
    vault_path: str, folder: str, fmt: str, day: str | None, heading: str,
    heading_level: int, default_duration: int, task_id: str,
    expected_document_sha: str,
) -> dict[str, Any]:
    doc = _load_document(vault_path, folder, fmt, day, heading, heading_level)
    _require_hashes(doc, expected_document_sha)
    task = _find_task(doc, task_id, default_duration)
    lines = list(doc["lines"])
    del lines[task["_index"]]
    core._atomic_replace_if_unchanged(doc, _encode_document(doc, lines))
    common = {
        "vault_path": vault_path, "folder": folder, "fmt": fmt, "day": day,
        "heading": heading, "heading_level": heading_level,
        "default_duration": default_duration,
    }
    return _mutation_result(common, "delete")



def preview_internal_migration(
    vault_path: str, folder: str, fmt: str, day: str | None, heading: str,
    heading_level: int, default_duration: int, internal_json_path: str,
) -> dict[str, Any]:
    doc = _load_document(vault_path, folder, fmt, day, heading, heading_level)
    source, source_raw, imported = core._load_internal_tasks(internal_json_path)
    target_tasks = _tasks(doc, default_duration)

    added = 0
    duplicates = 0
    conflicts = 0
    for content, done in imported:
        same = [task for task in target_tasks if task["content"] == content]
        if any(task["done"] is done for task in same):
            duplicates += 1
        elif same:
            conflicts += 1
        else:
            added += 1

    return {
        "ok": True,
        "mode": "markdown-note",
        "mutation": "preview-migration",
        "source": {
            "path": str(source),
            "sha256": core._sha256_bytes(source_raw),
            "taskCount": len(imported),
        },
        "target": {
            "documentSha256": core._sha256_bytes(doc["raw"]),
            "managedSha256": core._sha256_text(_section_text(doc)),
            "taskCount": len(target_tasks),
            "empty": len(target_tasks) == 0,
            "notePath": doc["notePath"],
            "sourceDate": doc["date"],
        },
        "preview": {
            "added": added,
            "duplicates": duplicates,
            "conflicts": conflicts,
        },
    }


def migrate_internal_json(
    vault_path: str, folder: str, fmt: str, day: str | None, heading: str,
    heading_level: int, default_duration: int, internal_json_path: str,
    expected_document_sha: str, expected_section_sha: str,
    expected_internal_sha: str = "",
) -> dict[str, Any]:
    doc = _load_document(vault_path, folder, fmt, day, heading, heading_level)
    _require_hashes(doc, expected_document_sha, expected_section_sha)
    if _tasks(doc, default_duration):
        raise core.TodoError(
            "migration_target_not_empty",
            "configured task heading must contain no tasks before importing the internal store",
        )

    source, source_raw, imported = core._load_internal_tasks(internal_json_path)
    source_sha = core._sha256_bytes(source_raw)
    if expected_internal_sha and source_sha != expected_internal_sha:
        raise core.TodoError(
            "migration_source_conflict",
            "internal Todo store changed since migration preview",
        )

    if not imported:
        result = _scan_payload(doc, default_duration)
        result["mutation"] = "migrate-internal"
        result["migratedCount"] = 0
        result["sourceSha256"] = source_sha
        result["backupPath"] = ""
        result["backupCreated"] = False
        return result

    try:
        if source.read_bytes() != source_raw:
            raise core.TodoError(
                "migration_source_conflict",
                "internal Todo store changed while preparing migration",
            )
    except core.TodoError:
        raise
    except OSError as exc:
        raise core.TodoError(
            "migration_source_missing",
            f"cannot revalidate internal Todo store: {exc}",
        ) from exc

    backup, backup_created = core._create_migration_backup(doc)

    try:
        if source.read_bytes() != source_raw:
            raise core.TodoError(
                "migration_source_conflict",
                "internal Todo store changed after target backup",
            )
    except core.TodoError:
        raise
    except OSError as exc:
        raise core.TodoError(
            "migration_source_missing",
            f"cannot revalidate internal Todo store: {exc}",
        ) from exc

    newline = _preferred_newline(doc)
    lines = list(doc["lines"])
    index = _section_append_index(doc)
    lines[index:index] = [
        "- [" + ("x" if done else " ") + "] " + content + newline
        for content, done in imported
    ]
    core._atomic_replace_if_unchanged(doc, _encode_document(doc, lines))

    common = {
        "vault_path": vault_path, "folder": folder, "fmt": fmt, "day": day,
        "heading": heading, "heading_level": heading_level,
        "default_duration": default_duration,
    }
    result = scan_daily_note(**common)
    result["mutation"] = "migrate-internal"
    result["migratedCount"] = len(imported)
    result["sourceSha256"] = source_sha
    result["backupPath"] = str(backup)
    result["backupCreated"] = backup_created
    return result


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)

    def source_args(cmd: argparse.ArgumentParser) -> None:
        cmd.add_argument("--vault", required=True)
        cmd.add_argument("--folder", default=DEFAULT_FOLDER)
        cmd.add_argument("--format", default=DEFAULT_FORMAT)
        cmd.add_argument("--date", default="")
        cmd.add_argument("--heading", default=DEFAULT_HEADING)
        cmd.add_argument("--heading-level", type=int, default=DEFAULT_HEADING_LEVEL)
        cmd.add_argument("--default-duration", type=int, default=DEFAULT_DURATION_MINUTES)

    scan = sub.add_parser("scan")
    source_args(scan)
    add = sub.add_parser("add")
    source_args(add)
    add.add_argument("--text", required=True)
    add.add_argument("--start-time", default="")
    add.add_argument("--end-time", default="")
    add.add_argument("--expected-document-sha", required=True)
    add.add_argument("--expected-section-sha", required=True)
    toggle = sub.add_parser("toggle")
    source_args(toggle)
    toggle.add_argument("--id", required=True)
    toggle.add_argument("--expected-document-sha", required=True)
    delete = sub.add_parser("delete")
    source_args(delete)
    delete.add_argument("--id", required=True)
    delete.add_argument("--expected-document-sha", required=True)

    preview = sub.add_parser("preview-migration")
    source_args(preview)
    preview.add_argument("--internal-json", required=True)

    migrate = sub.add_parser("migrate-internal")
    source_args(migrate)
    migrate.add_argument("--internal-json", required=True)
    migrate.add_argument("--expected-document-sha", required=True)
    migrate.add_argument("--expected-section-sha", required=True)
    migrate.add_argument("--expected-internal-sha", default="")
    return parser


def _source_kwargs(args: argparse.Namespace) -> dict[str, Any]:
    return {
        "vault_path": args.vault,
        "folder": args.folder,
        "fmt": args.format,
        "day": args.date or None,
        "heading": args.heading,
        "heading_level": args.heading_level,
        "default_duration": args.default_duration,
    }


def _emit(payload: dict[str, Any]) -> None:
    json.dump(payload, sys.stdout, ensure_ascii=False, separators=(",", ":"))
    sys.stdout.write("\n")


def main(argv: list[str] | None = None) -> int:
    args = _build_parser().parse_args(argv)
    try:
        common = _source_kwargs(args)
        if args.command == "scan":
            payload = scan_daily_note(**common)
        elif args.command == "add":
            payload = add_task(
                **common, text=args.text, start_time=args.start_time, end_time=args.end_time,
                expected_document_sha=args.expected_document_sha,
                expected_section_sha=args.expected_section_sha,
            )
        elif args.command == "toggle":
            payload = toggle_task(
                **common, task_id=args.id,
                expected_document_sha=args.expected_document_sha,
            )
        elif args.command == "delete":
            payload = delete_task(
                **common, task_id=args.id,
                expected_document_sha=args.expected_document_sha,
            )
        elif args.command == "preview-migration":
            payload = preview_internal_migration(
                **common, internal_json_path=args.internal_json,
            )
        elif args.command == "migrate-internal":
            payload = migrate_internal_json(
                **common,
                internal_json_path=args.internal_json,
                expected_document_sha=args.expected_document_sha,
                expected_section_sha=args.expected_section_sha,
                expected_internal_sha=args.expected_internal_sha,
            )
        else:
            raise core.TodoError("unsupported_command", f"unsupported command: {args.command}")
        _emit(payload)
        return 0
    except core.TodoError as exc:
        _emit({"ok": False, "error": {"code": exc.code, "message": exc.message}})
        return 2
    except Exception as exc:
        _emit({"ok": False, "error": {"code": "internal_error", "message": str(exc)}})
        return 3


if __name__ == "__main__":
    raise SystemExit(main())
