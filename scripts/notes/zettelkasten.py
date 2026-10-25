#!/usr/bin/env python3
"""Filesystem-canonical Zettelkasten capture and Notepad migration.

The generated Markdown mirrors the user's Obsidian Zettelkasten structure but
does not invoke Obsidian, Templater, or any plugin.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import stat
import sys
sys.dont_write_bytecode = True
from urllib.parse import unquote, urlsplit, quote
from datetime import datetime, timedelta
from pathlib import Path, PurePosixPath
from typing import Any

ALLOWED_TYPES = ("Permanent", "Literature", "Fleeting")
DEFAULT_FOLDER = "00_Capture/03_Zettelkasten"
DEFAULT_TYPE = "Fleeting"

_IMPORT_RE = re.compile(r'^hadalis_import_id:\s*"([^"]+)"\s*$')
_IMAGE_RE = re.compile(r'!\[[^\]\n]*\]\((file://[^)\r\n]+)\)')


def _attachment_dir(vault: Path, note_dir: Path, config_path: str) -> Path:
    config = Path(config_path).expanduser() if config_path else vault / ".obsidian"
    if not config.is_absolute():
        config = vault / config
    app = config / "app.json"
    try:
        options = json.loads(app.read_text(encoding="utf-8")) if app.exists() else {}
        location = options.get("attachmentFolderPath", "")
        if not isinstance(location, str):
            raise ValueError("attachmentFolderPath must be a string")
    except (OSError, ValueError, AttributeError) as error:
        raise ZettelError("attachment_config_invalid", f"cannot read vault attachment settings: {error}") from error
    if location in (".", "./"):
        target = note_dir
    elif location.startswith("./"):
        target = note_dir / location[2:]
    else:
        target = vault / location
    resolved = target.resolve(strict=False)
    if not resolved.is_relative_to(vault):
        raise ZettelError("attachment_outside_vault", "attachment folder escapes the vault")
    return resolved


def _export_images(vault: Path, note_dir: Path, body: str,
                   attachment_root: str, config_path: str) -> tuple[str, list[dict[str, str]]]:
    links = list(dict.fromkeys(match.group(1) for match in _IMAGE_RE.finditer(body)))
    if not links or not attachment_root:
        return body, []
    try:
        root = Path(attachment_root).expanduser().resolve(strict=True)
        target = _attachment_dir(vault, note_dir, config_path)
        pending = []
        for link in links:
            url = urlsplit(link)
            source = Path(unquote(url.path))
            if url.netloc not in ("", "localhost") or source.is_symlink() or source.resolve(strict=True).parent != root:
                raise ZettelError("attachment_source_invalid", "image is not in the Quick Notes attachment store")
            if not re.fullmatch(r"[0-9a-f]{64}\.(png|jpg|webp|gif|bmp|tiff)", source.name):
                raise ZettelError("attachment_source_invalid", "image has an invalid stored filename")
            if source.stat().st_size > 32 * 1024 * 1024:
                raise ZettelError("attachment_source_invalid", "stored image exceeds 32 MiB")
            data = source.read_bytes()
            digest = _sha256_bytes(data)
            if source.stem != digest:
                raise ZettelError("attachment_source_changed", "stored image bytes changed; the draft was preserved")
            pending.append((link, source, data, digest))
        # Validate every source before creating any destination image.
        target.mkdir(parents=True, exist_ok=True)
        if not target.resolve(strict=True).is_relative_to(vault):
            raise ZettelError("attachment_outside_vault", "attachment folder escapes the vault")
        exports = []
        for link, source, data, digest in pending:
            for suffix in range(100):
                name = source.name if suffix == 0 else source.stem + f"-{suffix}" + source.suffix
                destination = target / name
                try:
                    fd = os.open(destination, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
                except FileExistsError:
                    if destination.is_symlink() or destination.read_bytes() != data:
                        continue
                else:
                    try:
                        with os.fdopen(fd, "wb") as stream:
                            stream.write(data)
                            stream.flush()
                            os.fsync(stream.fileno())
                    except OSError:
                        destination.unlink(missing_ok=True)
                        raise
                if destination.read_bytes() != data:
                    raise ZettelError("attachment_verify_failed", "cannot verify copied image bytes")
                directory_fd = os.open(target, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
                try:
                    os.fsync(directory_fd)
                finally:
                    os.close(directory_fd)
                relative = Path(os.path.relpath(destination, note_dir)).as_posix()
                body = body.replace("(" + link + ")", "(" + quote(relative, safe="/") + ")")
                exports.append({"path": destination.relative_to(vault).as_posix(), "sha256": digest})
                break
            else:
                raise ZettelError("attachment_collision", "cannot allocate an image without overwriting existing files")
        return body, exports
    except ZettelError:
        raise
    except (OSError, RuntimeError, ValueError) as error:
        raise ZettelError("attachment_export_failed", f"cannot export note images: {error}") from error


class ZettelError(Exception):
    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code
        self.message = message


def _sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def _resolve_vault(vault_path: str) -> Path:
    raw = str(vault_path or "").strip()
    if not raw:
        raise ZettelError("invalid_vault_path", "vault path is empty")
    try:
        vault = Path(raw).expanduser().resolve(strict=True)
    except (OSError, RuntimeError) as exc:
        raise ZettelError("invalid_vault_path", f"cannot resolve vault path: {exc}") from exc
    if not vault.is_dir() or vault == Path(vault.anchor):
        raise ZettelError("invalid_vault_path", "vault path is not a usable directory")
    return vault


def _normalize_folder(folder: str) -> str:
    raw = str(folder or "").strip().strip("/")
    if not raw:
        raise ZettelError("invalid_folder", "Zettelkasten folder is empty")
    if "\\" in raw:
        raise ZettelError("invalid_folder", "folder must use vault-relative '/' separators")
    pure = PurePosixPath(raw)
    if pure.is_absolute() or any(part in ("", ".", "..") for part in pure.parts):
        raise ZettelError("invalid_folder", "folder contains an unsafe path component")
    return pure.as_posix()


def _candidate_folder(vault: Path, folder: str) -> tuple[str, Path]:
    normalized = _normalize_folder(folder)
    candidate = vault.joinpath(*PurePosixPath(normalized).parts)
    try:
        resolved = candidate.resolve(strict=False)
        if os.path.commonpath((str(vault), str(resolved))) != str(vault):
            raise ZettelError("folder_outside_vault", "Zettelkasten folder escapes the vault")
    except ZettelError:
        raise
    except (OSError, RuntimeError, ValueError) as exc:
        raise ZettelError("folder_read_failed", f"cannot resolve Zettelkasten folder: {exc}") from exc
    return normalized, candidate


def _resolve_folder(vault: Path, folder: str) -> tuple[str, Path]:
    normalized, candidate = _candidate_folder(vault, folder)
    try:
        candidate.mkdir(parents=True, exist_ok=True)
        resolved = candidate.resolve(strict=True)
        if os.path.commonpath((str(vault), str(resolved))) != str(vault):
            raise ZettelError("folder_outside_vault", "Zettelkasten folder escapes the vault")
    except ZettelError:
        raise
    except (OSError, RuntimeError, ValueError) as exc:
        raise ZettelError("folder_create_failed", f"cannot prepare Zettelkasten folder: {exc}") from exc
    if not resolved.is_dir():
        raise ZettelError("invalid_folder", "Zettelkasten target is not a directory")
    return normalized, resolved


def _readonly_target_dir(vault: Path, folder: str) -> tuple[str, Path | None]:
    normalized, candidate = _candidate_folder(vault, folder)
    if not candidate.exists():
        return normalized, None
    try:
        resolved = candidate.resolve(strict=True)
        if os.path.commonpath((str(vault), str(resolved))) != str(vault):
            raise ZettelError("folder_outside_vault", "Zettelkasten folder escapes the vault")
    except ZettelError:
        raise
    except (OSError, RuntimeError, ValueError) as exc:
        raise ZettelError("folder_read_failed", f"cannot inspect Zettelkasten folder: {exc}") from exc
    if not resolved.is_dir():
        raise ZettelError("invalid_folder", "Zettelkasten target is not a directory")
    return normalized, resolved


def _clean_title(title: str, body: str) -> str:
    value = str(title or "").strip()
    if not value:
        for line in str(body or "").splitlines():
            if _IMAGE_RE.fullmatch(line.strip()):
                continue
            candidate = line.strip().lstrip("#").strip()
            if candidate:
                value = candidate
                break
    if not value:
        value = "Quick note"
    value = re.sub(r"[\x00-\x1f\x7f]+", " ", value)
    value = re.sub(r"\s+", " ", value).strip()
    return value[:160]


def _filename_title(title: str) -> str:
    value = re.sub(r'[<>:"/\\|?*]+', " ", title)
    value = re.sub(r"\s+", " ", value).strip(" .")
    return (value or "Quick note")[:80]


def _normalize_type(note_type: str) -> str:
    value = str(note_type or DEFAULT_TYPE).strip() or DEFAULT_TYPE
    if value not in ALLOWED_TYPES:
        raise ZettelError(
            "invalid_note_type",
            "Zettelkasten type must be Permanent, Literature or Fleeting",
        )
    return value


def _clean_body(body: str) -> str:
    return (
        str(body or "")
        .replace("\x00", "")
        .replace("\r\n", "\n")
        .replace("\r", "\n")
        .strip()
    )


def _render_markdown(
    note_id: str,
    title: str,
    body: str,
    note_type: str,
    created: datetime,
    import_id: str = "",
) -> str:
    """Render the static schema of 90_System/91_Templates/Zettelkasten_Template.md."""

    clean_body = _clean_body(body)
    content = clean_body if clean_body else title
    explanation_lines = content.splitlines() or [title]

    parts = [
        "---",
        f"id: {note_id}",
        f"date: {created.strftime('%Y-%m-%d')}",
        f"type: {note_type}",
        "tags:",
        "  - zettelkasten",
        "aliases: []",
    ]
    if import_id:
        parts.append(f"hadalis_import_id: {json.dumps(import_id, ensure_ascii=False)}")

    parts.extend([
        "---",
        "",
        f"# {title}",
        "",
        "## Core Idea",
        "Abstract",
        title,
        "",
        "## Content",
        "> [!info] Explanation",
        *[(f"> {line}" if line else ">") for line in explanation_lines],
        "",
        "## Context & Connections",
        "*Link to existing notes using [[]] with explicit context on how they relate:*",
        "- **Parent / Overview:** [[ ]]",
        "- **Supporting / Extension:** [[ ]]",
        "- **Contradiction / Alternative:** [[ ]]",
        "",
        "## Sources & References",
        "- **Author / Source:** ",
        "- **Link / Reference:**",
        "",
    ])
    return "\n".join(parts)


def _id_in_use(target_dir: Path, note_id: str) -> bool:
    try:
        return next(target_dir.glob(f"{note_id} - *.md"), None) is not None
    except OSError as exc:
        raise ZettelError("folder_read_failed", f"cannot inspect Zettelkasten folder: {exc}") from exc


def capture(
    vault_path: str,
    folder: str,
    title: str,
    body: str,
    note_type: str = DEFAULT_TYPE,
    now: datetime | None = None,
    import_id: str = "",
    attachment_root: str = "",
    config_path: str = "",
) -> dict[str, Any]:
    vault = _resolve_vault(vault_path)
    normalized_folder, target_dir = _resolve_folder(vault, folder)
    requested_time = now or datetime.now().astimezone()
    clean_title = _clean_title(title, body)
    clean_type = _normalize_type(note_type)
    filename_title = _filename_title(clean_title)
    body, attachments = _export_images(vault, target_dir, body, attachment_root, config_path)

    for attempt in range(100):
        candidate_time = requested_time + timedelta(seconds=attempt)
        note_id = candidate_time.strftime("%Y%m%d%H%M%S")
        if _id_in_use(target_dir, note_id):
            continue

        candidate = target_dir / f"{note_id} - {filename_title}.md"
        payload = _render_markdown(
            note_id,
            clean_title,
            body,
            clean_type,
            candidate_time,
            import_id,
        ).encode("utf-8")

        try:
            fd = os.open(
                candidate,
                os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_CLOEXEC", 0),
                0o600,
            )
        except FileExistsError:
            continue
        except OSError as exc:
            raise ZettelError("note_create_failed", f"cannot create Zettelkasten note: {exc}") from exc

        try:
            with os.fdopen(fd, "wb") as stream:
                stream.write(payload)
                stream.flush()
                os.fsync(stream.fileno())
            dir_fd = os.open(target_dir, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
            try:
                os.fsync(dir_fd)
            finally:
                os.close(dir_fd)
        except OSError as exc:
            try:
                candidate.unlink(missing_ok=True)
            except OSError:
                pass
            raise ZettelError("note_write_failed", f"cannot persist Zettelkasten note: {exc}") from exc

        relative = PurePosixPath(normalized_folder, candidate.name).as_posix()
        result = {
            "ok": True,
            "id": note_id,
            "date": candidate_time.strftime("%Y-%m-%d"),
            "title": clean_title,
            "type": clean_type,
            "notePath": relative,
            "noteFullPath": str(candidate),
            "templateCompatible": True,
        }
        if attachments:
            result["attachments"] = attachments
        return result

    raise ZettelError("note_collision", "could not allocate a unique Zettelkasten ID")


def _load_notepad_tabs(
    notepad_json_path: str,
) -> tuple[Path, bytes, list[dict[str, str]]]:
    try:
        source = Path(str(notepad_json_path or "")).expanduser().resolve(strict=True)
    except (OSError, RuntimeError) as exc:
        raise ZettelError("migration_source_missing", f"cannot resolve Notepad store: {exc}") from exc
    if not source.is_file():
        raise ZettelError("migration_source_missing", "Notepad store is not a regular file")

    try:
        raw = source.read_bytes()
        payload = json.loads(raw.decode("utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ZettelError("migration_source_invalid", f"cannot read Notepad store: {exc}") from exc

    tabs = payload.get("tabs") if isinstance(payload, dict) else None
    if not isinstance(tabs, list):
        raise ZettelError("migration_source_invalid", "Notepad store must contain a tabs list")

    entries: list[dict[str, str]] = []
    occurrence: dict[str, int] = {}
    for item in tabs:
        if not isinstance(item, dict):
            continue

        raw_title = str(item.get("title", "") or "").strip()
        body = str(item.get("text", "") or "").replace("\x00", "")
        default_title = re.fullmatch(r"Note \d+", raw_title) is not None
        requested_title = "" if default_title else raw_title

        if not requested_title.strip() and not body.strip():
            continue

        title = _clean_title(requested_title, body)
        digest = hashlib.sha256(
            (title + "\0" + body).encode("utf-8")
        ).hexdigest()[:24]
        ordinal = occurrence.get(digest, 0) + 1
        occurrence[digest] = ordinal
        entries.append({
            "title": title,
            "body": body,
            "importId": f"notepad-{digest}-{ordinal}",
        })

    return source, raw, entries


def _import_marker_counts(target_dir: Path | None) -> dict[str, int]:
    counts: dict[str, int] = {}
    if target_dir is None:
        return counts

    try:
        paths = list(target_dir.glob("*.md"))
    except OSError as exc:
        raise ZettelError("folder_read_failed", f"cannot list Zettelkasten notes: {exc}") from exc

    for path in paths:
        try:
            text = path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        for line in text.splitlines()[:40]:
            match = _IMPORT_RE.match(line)
            if match:
                marker = match.group(1)
                counts[marker] = counts.get(marker, 0) + 1
                break
    return counts


def preview_notepad_migration(
    vault_path: str,
    folder: str,
    notepad_json_path: str,
    note_type: str = DEFAULT_TYPE,
) -> dict[str, Any]:
    vault = _resolve_vault(vault_path)
    clean_type = _normalize_type(note_type)
    source, raw, entries = _load_notepad_tabs(notepad_json_path)
    normalized_folder, target_dir = _readonly_target_dir(vault, folder)
    markers = _import_marker_counts(target_dir)

    added = 0
    duplicates = 0
    conflicts = 0
    for entry in entries:
        count = markers.get(entry["importId"], 0)
        if count == 0:
            added += 1
        elif count == 1:
            duplicates += 1
        else:
            conflicts += 1

    return {
        "ok": True,
        "mutation": "preview-notepad-migration",
        "type": clean_type,
        "source": {
            "path": str(source),
            "sha256": _sha256_bytes(raw),
            "tabCount": len(entries),
        },
        "target": {
            "folder": normalized_folder,
            "exists": target_dir is not None,
        },
        "preview": {
            "added": added,
            "duplicates": duplicates,
            "conflicts": conflicts,
        },
    }


def _backup_notepad_source(source: Path, raw: bytes) -> tuple[Path, bool]:
    digest = _sha256_bytes(raw)
    backup = source.parent / f".{source.name}.hadalis-zettel-backup-{digest[:12]}"

    try:
        if source.read_bytes() != raw:
            raise ZettelError(
                "migration_source_conflict",
                "Notepad store changed before migration backup",
            )
        mode = stat.S_IMODE(source.stat().st_mode)
    except ZettelError:
        raise
    except OSError as exc:
        raise ZettelError("migration_backup_failed", f"cannot prepare migration backup: {exc}") from exc

    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_CLOEXEC", 0)
    try:
        fd = os.open(backup, flags, mode)
    except FileExistsError:
        try:
            if not backup.is_file() or backup.read_bytes() != raw:
                raise ZettelError(
                    "migration_backup_conflict",
                    "existing Notepad migration backup does not match source",
                )
        except OSError as exc:
            raise ZettelError("migration_backup_failed", f"cannot verify migration backup: {exc}") from exc
        return backup, False
    except OSError as exc:
        raise ZettelError("migration_backup_failed", f"cannot create migration backup: {exc}") from exc

    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(raw)
            stream.flush()
            os.fsync(stream.fileno())
        dir_fd = os.open(source.parent, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
        try:
            os.fsync(dir_fd)
        finally:
            os.close(dir_fd)
    except OSError as exc:
        try:
            backup.unlink(missing_ok=True)
        except OSError:
            pass
        raise ZettelError("migration_backup_failed", f"cannot persist migration backup: {exc}") from exc

    return backup, True


def _revalidate_source(source: Path, raw: bytes, stage: str) -> None:
    try:
        current = source.read_bytes()
    except OSError as exc:
        raise ZettelError("migration_source_missing", f"cannot revalidate Notepad store: {exc}") from exc
    if current != raw:
        raise ZettelError(
            "migration_source_conflict",
            f"Notepad store changed {stage}",
        )


def migrate_notepad_json(
    vault_path: str,
    folder: str,
    notepad_json_path: str,
    expected_source_sha: str,
    note_type: str = DEFAULT_TYPE,
    config_path: str = "",
) -> dict[str, Any]:
    if not str(expected_source_sha or "").strip():
        raise ZettelError("missing_precondition", "expected Notepad source SHA is required")

    clean_type = _normalize_type(note_type)
    source, raw, entries = _load_notepad_tabs(notepad_json_path)
    source_sha = _sha256_bytes(raw)
    if source_sha != expected_source_sha:
        raise ZettelError(
            "migration_source_conflict",
            "Notepad store changed since migration preview",
        )

    vault = _resolve_vault(vault_path)
    _, target_dir = _readonly_target_dir(vault, folder)
    markers = _import_marker_counts(target_dir)
    if any(markers.get(entry["importId"], 0) > 1 for entry in entries):
        raise ZettelError(
            "migration_target_conflict",
            "duplicate Alis import markers exist in the Zettelkasten target",
        )

    _revalidate_source(source, raw, "while preparing migration")
    backup, backup_created = _backup_notepad_source(source, raw)
    _revalidate_source(source, raw, "after migration backup")

    created_paths: list[str] = []
    skipped = 0
    for entry in entries:
        if markers.get(entry["importId"], 0) == 1:
            skipped += 1
            continue

        _revalidate_source(source, raw, "while importing tabs")
        result = capture(
            vault_path,
            folder,
            entry["title"],
            entry["body"],
            clean_type,
            import_id=entry["importId"],
            attachment_root=str(source.parent / "notepad-attachments"),
            config_path=config_path,
        )
        created_paths.append(result["notePath"])

    _revalidate_source(source, raw, "before verification")
    _, final_dir = _readonly_target_dir(vault, folder)
    final_markers = _import_marker_counts(final_dir)
    for entry in entries:
        if final_markers.get(entry["importId"], 0) != 1:
            raise ZettelError(
                "migration_verify_failed",
                "Zettelkasten import verification failed",
            )

    return {
        "ok": True,
        "mutation": "migrate-notepad",
        "sourceSha256": source_sha,
        "sourcePreserved": True,
        "backupPath": str(backup),
        "backupCreated": backup_created,
        "migratedCount": len(created_paths),
        "duplicateCount": skipped,
        "notePaths": created_paths,
        "verified": True,
    }


def _emit(payload: dict[str, Any]) -> None:
    json.dump(payload, sys.stdout, ensure_ascii=False, separators=(",", ":"))
    sys.stdout.write("\n")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--vault", required=True)
    parser.add_argument("--folder", default=DEFAULT_FOLDER)
    parser.add_argument("--title", default="")
    parser.add_argument("--body", default="")
    parser.add_argument("--type", default=DEFAULT_TYPE)
    parser.add_argument("--preview-notepad", default="")
    parser.add_argument("--migrate-notepad", default="")
    parser.add_argument("--expected-source-sha", default="")
    parser.add_argument("--attachment-root", default="")
    parser.add_argument("--config-path", default="")
    args = parser.parse_args(argv)

    try:
        if args.preview_notepad:
            payload = preview_notepad_migration(
                args.vault,
                args.folder,
                args.preview_notepad,
                args.type,
            )
        elif args.migrate_notepad:
            payload = migrate_notepad_json(
                args.vault,
                args.folder,
                args.migrate_notepad,
                args.expected_source_sha,
                args.type,
                config_path=args.config_path,
            )
        else:
            payload = capture(
                args.vault,
                args.folder,
                args.title,
                args.body,
                args.type,
                attachment_root=args.attachment_root,
                config_path=args.config_path,
            )
        _emit(payload)
        return 0
    except ZettelError as exc:
        _emit({"ok": False, "error": {"code": exc.code, "message": exc.message}})
        return 2
    except Exception as exc:
        _emit({"ok": False, "error": {"code": "internal_error", "message": str(exc)}})
        return 3


if __name__ == "__main__":
    raise SystemExit(main())
