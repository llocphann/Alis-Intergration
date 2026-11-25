#!/usr/bin/env python3
"""Body Tracker photo helper and read-only Nexus exercise library inspector.

Photo operations strictly act on an explicit user-chosen file path and copy into
the isolated user-state photos directory. Exercise read operations strictly stay
within the resolved Nexus vault root, reject path traversal and symlinks that
escape the vault, and cap file reads.
"""
import argparse
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import sys
import tempfile

ALLOWED_EXTENSIONS = {".png", ".jpg", ".jpeg", ".webp", ".bmp", ".avif", ".gif"}
MAX_IMAGE_BYTES = 32 * 1024 * 1024
MAX_NOTE_BYTES = 2 * 1024 * 1024
MAX_SCAN_EXERCISES = 500
SAFE_TOKEN_RE = re.compile(r"^[A-Za-z0-9_-]{1,64}$")
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
EXERCISE_DIRS = (
    "20_Personal_Life/33_Bodybuilding/Gym_n_Calisthenics_Exercises",
    "21_Health_&_Fitness/Exercise_Library",
)
SKIP_DIR_NAMES = {".git", ".obsidian", ".trash", "91_templates", "01_templates", "templates", "template_scripts"}
_HEADING_RE = re.compile(r"^(#{1,6})\s+(.+?)\s*#*\s*$")
_NUMBERED_RE = re.compile(r"^\d+[.)]\s+(.+)$")
_WIKI_EMBED_RE = re.compile(r"!\[\[([^\]|]+)(?:\|[^\]]*)?\]\]")
_MD_EMBED_RE = re.compile(r"!\[[^\]]*\]\(([^)]+)\)")


def _looks_like_image(header: bytes, ext: str) -> bool:
    if len(header) < 6:
        return False
    if header.startswith(b"\x89PNG\r\n\x1a\n"):
        return True
    if header.startswith(b"\xff\xd8\xff"):
        return True
    if header.startswith((b"GIF87a", b"GIF89a")):
        return True
    if header.startswith(b"BM"):
        return True
    if len(header) >= 12 and header[:4] == b"RIFF" and header[8:12] == b"WEBP":
        return True
    if len(header) >= 12 and header[4:8] == b"ftyp" and header[8:12] in (
        b"avif",
        b"avis",
        b"mif1",
        b"heic",
    ):
        return True
    return False


def _ensure_safe_photos_dir(photos_dir: Path) -> Path:
    if photos_dir.is_symlink():
        raise ValueError("Refusing symlinked photos directory")
    for parent in (photos_dir.parent,):
        if parent.exists() and parent.is_symlink():
            raise ValueError("Refusing symlinked state directory")
    photos_dir.mkdir(parents=True, exist_ok=True)
    if photos_dir.is_symlink() or not photos_dir.is_dir():
        raise ValueError("Invalid photos directory")
    return photos_dir.resolve()


def _try_resolve_vault_root(vault_str: str) -> Path | None:
    try:
        return _resolve_vault_root(vault_str)
    except (OSError, ValueError):
        return None


def _read_obsidian_attachment_folder(vault_root: Path) -> str:
    app_cfg = vault_root / ".obsidian" / "app.json"
    if not app_cfg.is_file() or app_cfg.is_symlink():
        return ""
    try:
        data = json.loads(app_cfg.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return ""
    raw = str(data.get("attachmentFolderPath") or "").strip().replace("\\", "/")
    if not raw or raw in (".", "./") or raw.startswith("./") or "\x00" in raw:
        return ""
    rel = raw.strip("/")
    posix = PurePosixPath(rel)
    if not rel or posix.is_absolute() or ".." in posix.parts:
        return ""
    cand = vault_root.joinpath(*posix.parts)
    if not _is_within_vault(cand, vault_root):
        return ""
    return posix.as_posix()


def _vault_rel_from_target(target: Path, vault_root: Path | None) -> tuple[bool, str]:
    if vault_root is None:
        return False, ""
    try:
        resolved = target.resolve()
        if resolved == vault_root or resolved.is_relative_to(vault_root):
            rel = resolved.relative_to(vault_root).as_posix()
            return True, "" if rel == "." else rel
    except OSError:
        pass
    return False, ""


def resolve_body_photos_dir(
    vault_str: str,
    fallback_photos_dir_str: str,
    storage_mode: str = "auto",
    custom_dir_str: str = "",
) -> dict:
    """Resolve the effective Body Tracker photos directory without creating it on disk."""
    vault_root = _try_resolve_vault_root(vault_str)
    mode = "custom" if str(storage_mode or "").strip().lower() == "custom" else "auto"
    raw_custom = str(custom_dir_str or "").strip()
    if raw_custom.startswith("file://"):
        from urllib.parse import unquote, urlsplit
        raw_custom = unquote(urlsplit(raw_custom).path).strip()

    if mode == "custom" and raw_custom:
        if "\x00" in raw_custom:
            raise ValueError("Invalid custom photos directory path")
        expanded = Path(raw_custom).expanduser()
        if not expanded.is_absolute():
            if vault_root is None:
                raise ValueError("Custom relative photos folder requires a configured Nexus vault")
            rel_norm = raw_custom.replace("\\", "/").lstrip("/")
            posix = PurePosixPath(rel_norm)
            if not rel_norm or posix.is_absolute() or ".." in posix.parts:
                raise ValueError("Custom photos path traversal is not permitted")
            target = vault_root.joinpath(*posix.parts)
            if not _is_within_vault(target, vault_root):
                raise ValueError("Custom photos folder escapes vault root")
        else:
            target = expanded
        if target.is_symlink() or (target.parent.exists() and target.parent.is_symlink()):
            raise ValueError("Refusing symlinked custom photos directory")
        if target.exists() and not target.is_dir():
            raise ValueError("Custom photos path exists and is not a directory")
        resolved_target = target.resolve()
        in_vault, vault_rel_dir = _vault_rel_from_target(resolved_target, vault_root)
        return {
            "ok": True,
            "photosDir": str(resolved_target),
            "storageMode": "custom",
            "source": "custom",
            "inVault": in_vault,
            "vaultRelDir": vault_rel_dir,
            "reason": "Custom folder",
        }

    if vault_root is not None:
        obs_att = _read_obsidian_attachment_folder(vault_root)
        candidates: list[tuple[str, str, str]] = [
            ("90_System/95_Media_Assets/Exercise", "90_System/95_Media_Assets/Exercise/Body_Tracker", "Nexus Exercise media assets"),
            ("90_System/95_Media_Assets", "90_System/95_Media_Assets/Body_Tracker", "Nexus media assets"),
            ("90_System/95_Attachments", "90_System/95_Attachments/Body_Tracker", "Nexus attachments"),
        ]
        if obs_att:
            obs_rel = obs_att if obs_att.endswith("/Body_Tracker") or obs_att == "Body_Tracker" else f"{obs_att}/Body_Tracker"
            candidates.append((obs_att, obs_rel, "Obsidian/Nexus attachment folder"))
        candidates.extend([
            ("90_System/96_Auto_Attachments", "90_System/96_Auto_Attachments/Body_Tracker", "Nexus auto attachments"),
            ("20_Personal_Life/33_Bodybuilding", "20_Personal_Life/33_Bodybuilding/Body_Tracker", "Nexus Bodybuilding folder"),
            ("21_Health_&_Fitness", "21_Health_&_Fitness/Body_Tracker", "Nexus Health & Fitness folder"),
            ("99_Attachments", "99_Attachments/Body_Tracker", "Nexus attachments"),
            ("Attachments", "Attachments/Body_Tracker", "Nexus attachments"),
        ])
        chosen_rel = "Attachments/Body_Tracker"
        chosen_reason = "Nexus vault default"
        for probe_rel, target_rel, reason in candidates:
            probe_dir = vault_root.joinpath(*PurePosixPath(probe_rel).parts)
            target_cand = vault_root.joinpath(*PurePosixPath(target_rel).parts)
            if probe_dir.is_dir() and not probe_dir.is_symlink() and _is_within_vault(target_cand, vault_root):
                if target_cand.is_symlink():
                    continue
                chosen_rel = target_rel
                chosen_reason = reason
                break
        target = vault_root.joinpath(*PurePosixPath(chosen_rel).parts)
        if target.is_symlink() or not _is_within_vault(target, vault_root):
            raise ValueError("Resolved vault photos directory is invalid")
        return {
            "ok": True,
            "photosDir": str(target.resolve()),
            "storageMode": mode,
            "source": "nexus-auto",
            "inVault": True,
            "vaultRelDir": chosen_rel,
            "reason": chosen_reason,
        }

    fallback = Path(fallback_photos_dir_str).expanduser()
    if fallback.is_symlink() or (fallback.parent.exists() and fallback.parent.is_symlink()):
        raise ValueError("Refusing symlinked local photos directory")
    return {
        "ok": True,
        "photosDir": str(fallback.resolve()),
        "storageMode": mode,
        "source": "local-fallback",
        "inVault": False,
        "vaultRelDir": "",
        "reason": "Local state folder (configure Nexus vault to sync)",
    }


def import_photo(
    source_str: str,
    photos_dir_str: str,
    checkin_id: str,
    date_str: str,
    vault_str: str = "",
    storage_mode: str = "",
    custom_dir_str: str = "",
) -> dict:
    raw = str(source_str or "").strip()
    if raw.startswith("file://"):
        from urllib.parse import unquote, urlsplit
        raw = unquote(urlsplit(raw).path)
    if not raw:
        raise ValueError("No image path provided")

    src = Path(raw)
    if src.is_symlink():
        raise ValueError("Refusing symlinked image file")
    if not src.exists() or not src.is_file():
        raise ValueError("Selected image file does not exist")

    ext = src.suffix.lower()
    if ext not in ALLOWED_EXTENSIONS:
        raise ValueError(f"Unsupported image format: {ext or 'none'}")

    size = src.stat().st_size
    if size <= 0:
        raise ValueError("Selected image file is empty")
    if size > MAX_IMAGE_BYTES:
        raise ValueError("Selected image exceeds 32 MB limit")

    with src.open("rb") as fh:
        header = fh.read(32)
    if not _looks_like_image(header, ext):
        raise ValueError("File contents do not match a valid image header")

    safe_id = checkin_id if SAFE_TOKEN_RE.fullmatch(str(checkin_id or "")) else "checkin"
    safe_date = date_str if DATE_RE.fullmatch(str(date_str or "")) else "photo"
    vault_rel_dir = ""
    storage_source = "local-fallback"
    if str(storage_mode or "").strip() or str(vault_str or "").strip() or str(custom_dir_str or "").strip():
        resolved_info = resolve_body_photos_dir(
            vault_str,
            photos_dir_str,
            storage_mode or "auto",
            custom_dir_str,
        )
        photos_dir = _ensure_safe_photos_dir(Path(resolved_info["photosDir"]))
        vault_rel_dir = str(resolved_info.get("vaultRelDir") or "")
        storage_source = str(resolved_info.get("source") or "local-fallback")
    else:
        photos_dir = _ensure_safe_photos_dir(Path(photos_dir_str))
    filename = f"{safe_date}_{safe_id}{ext}"
    dest = photos_dir / filename
    if dest.is_symlink():
        raise ValueError("Refusing symlinked destination file")

    fd, tmp_name = tempfile.mkstemp(prefix=".body-photo-", suffix=ext, dir=str(photos_dir))
    try:
        os.close(fd)
        shutil.copyfile(src, tmp_name)
        os.chmod(tmp_name, 0o600)
        os.replace(tmp_name, dest)
    except Exception:
        Path(tmp_name).unlink(missing_ok=True)
        raise

    photo_rel = f"{vault_rel_dir}/{filename}" if vault_rel_dir else f"photos/{filename}"
    photo_vault_rel = f"{vault_rel_dir}/{filename}" if vault_rel_dir else ""
    return {
        "ok": True,
        "photoPath": str(dest),
        "photoRel": photo_rel,
        "photoVaultRel": photo_vault_rel,
        "photosDir": str(photos_dir),
        "storageSource": storage_source,
        "sizeBytes": dest.stat().st_size,
    }


def delete_photo(photo_path_str: str, photos_dir_str: str, allowed_dirs: list[str] | None = None) -> dict:
    raw = str(photo_path_str or "").strip()
    if raw.startswith("file://"):
        from urllib.parse import unquote, urlsplit
        raw = unquote(urlsplit(raw).path)
    if not raw:
        return {"ok": True, "deleted": False}

    raw_candidates = [photos_dir_str, *(allowed_dirs or [])]
    resolved_dirs: set[Path] = set()
    for d_str in raw_candidates:
        clean_d = str(d_str or "").strip()
        if not clean_d:
            continue
        p = Path(clean_d).expanduser()
        if p.exists() and not p.is_symlink() and p.is_dir():
            resolved_dirs.add(p.resolve())
    if not resolved_dirs:
        return {"ok": True, "deleted": False}

    target = Path(raw)
    if target.is_symlink():
        raise ValueError("Refusing to delete symlink")
    if not target.exists():
        return {"ok": True, "deleted": False}
    resolved_target = target.resolve()
    if resolved_target.parent not in resolved_dirs or not resolved_target.is_file():
        raise ValueError("Refusing to delete file outside Body Tracker photos directory")
    resolved_target.unlink()
    return {"ok": True, "deleted": True}


def _strip_wikilink(value: str) -> str:
    s = str(value or "").strip().strip('"').strip("'").strip()
    if s.startswith("![[") and s.endswith("]]"):
        s = s[3:-2].strip()
    elif s.startswith("[[") and s.endswith("]]"):
        s = s[2:-2].strip()
    if "|" in s:
        s = s.split("|", 1)[0].strip()
    return s


def _resolve_vault_root(vault_str: str) -> Path:
    raw = str(vault_str or "").strip()
    if not raw:
        raise ValueError("Vault path is empty")
    vault = Path(raw).expanduser()
    if not vault.exists() or not vault.is_dir():
        raise ValueError("Vault directory does not exist")
    return vault.resolve()


def _is_within_vault(candidate: Path, vault_root: Path) -> bool:
    try:
        resolved = candidate.resolve()
        return resolved.is_relative_to(vault_root)
    except OSError:
        return False


def _resolve_vault_note(vault_root: Path, rel_path_str: str) -> tuple[str, Path]:
    raw_rel = str(rel_path_str or "").strip().replace("\\", "/").lstrip("/")
    if not raw_rel or "\x00" in raw_rel:
        raise ValueError("Invalid exercise note path")
    posix = PurePosixPath(raw_rel)
    if posix.is_absolute() or ".." in posix.parts:
        raise ValueError("Path traversal is not permitted")
    if not raw_rel.lower().endswith(".md"):
        raise ValueError("Exercise note must be a Markdown file")
    candidate = vault_root.joinpath(*posix.parts)
    if not _is_within_vault(candidate, vault_root):
        raise ValueError("Exercise path escapes vault root")
    resolved = candidate.resolve()
    if not resolved.exists() or not resolved.is_file():
        raise ValueError(f"Exercise note not found: {raw_rel}")
    if resolved.stat().st_size > MAX_NOTE_BYTES:
        raise ValueError("Exercise note exceeds size limit")
    return raw_rel, resolved


def _parse_yaml_frontmatter(text: str) -> tuple[dict[str, str], dict[str, list[str]], list[str]]:
    lines = text.splitlines()
    scalars: dict[str, str] = {}
    lists: dict[str, list[str]] = {}
    if not lines or lines[0].strip() != "---":
        return scalars, lists, lines

    end_idx = -1
    for i in range(1, len(lines)):
        if lines[i].strip() in ("---", "..."):
            end_idx = i
            break
    if end_idx < 0:
        return scalars, lists, lines

    current_list_key: str | None = None
    for raw_line in lines[1:end_idx]:
        stripped = raw_line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if (raw_line.startswith((" ", "\t")) or stripped.startswith("- ")) and stripped.startswith("-") and current_list_key:
            item = _strip_wikilink(stripped[1:].strip())
            if item:
                lists.setdefault(current_list_key, []).append(item)
            continue

        m = re.match(r"^([A-Za-z0-9_-]+)\s*:\s*(.*)$", raw_line)
        if not m:
            current_list_key = None
            continue
        key = m.group(1).strip().lower()
        val = m.group(2).strip()
        if val == "" or val in ("|", ">", "|-", ">-"):
            current_list_key = key
            lists.setdefault(key, [])
            continue
        current_list_key = None
        if val.startswith("[") and val.endswith("]"):
            inner = val[1:-1].strip()
            items = [_strip_wikilink(part) for part in inner.split(",") if _strip_wikilink(part)]
            lists[key] = items
            scalars[key] = ", ".join(items)
        else:
            cleaned = _strip_wikilink(val)
            scalars[key] = cleaned
            if key in ("primarymuscles", "primary_muscles", "secondarymuscles", "secondary_muscles", "instructions", "tips", "images"):
                items = [_strip_wikilink(part) for part in cleaned.split(",") if _strip_wikilink(part)]
                if items:
                    lists[key] = items

    return scalars, lists, lines[end_idx + 1 :]


def _build_asset_basename_index(vault_root: Path) -> dict[str, Path]:
    index: dict[str, Path] = {}
    search_roots = [
        vault_root / "90_System/95_Attachments",
        vault_root / "90_System/95_Media_Assets",
    ]
    for ex_dir in EXERCISE_DIRS:
        search_roots.append(vault_root / ex_dir)
    for base in search_roots:
        if not base.exists() or not _is_within_vault(base, vault_root):
            continue
        for root_dir, dirnames, filenames in os.walk(base, followlinks=False):
            dirnames[:] = [d for d in dirnames if d.lower() not in SKIP_DIR_NAMES]
            root_path = Path(root_dir)
            if not _is_within_vault(root_path, vault_root):
                continue
            for fname in filenames:
                ext = Path(fname).suffix.lower()
                if ext not in ALLOWED_EXTENSIONS:
                    continue
                low = fname.lower()
                if low not in index:
                    cand = root_path / fname
                    if _is_within_vault(cand, vault_root) and cand.is_file():
                        index[low] = cand.resolve()
    return index


def _resolve_vault_asset_url(
    vault_root: Path,
    note_dir: Path,
    raw_ref: str,
    asset_index: dict[str, Path] | None = None,
) -> str:
    cleaned = _strip_wikilink(raw_ref)
    if not cleaned:
        return ""
    if cleaned.startswith(("http://", "https://")):
        return cleaned
    if cleaned.startswith("file://"):
        from urllib.parse import unquote, urlsplit
        cleaned = unquote(urlsplit(cleaned).path)
        cand = Path(cleaned)
        if _is_within_vault(cand, vault_root) and cand.is_file():
            return cand.resolve().as_uri()
        return ""

    rel = cleaned.replace("\\", "/").lstrip("/")
    if "\x00" in rel or ".." in PurePosixPath(rel).parts:
        return ""

    candidates = [
        note_dir / rel,
        vault_root / rel,
        vault_root / "90_System/95_Attachments" / rel,
        vault_root / "90_System/95_Media_Assets" / rel,
    ]
    for cand in candidates:
        if _is_within_vault(cand, vault_root) and cand.exists() and cand.is_file():
            return cand.resolve().as_uri()

    if asset_index is not None:
        fname = PurePosixPath(rel).name.lower()
        found = asset_index.get(fname)
        if found is not None and _is_within_vault(found, vault_root) and found.is_file():
            return found.as_uri()
    return ""


def _split_frontmatter_list(scalars: dict[str, str], lists: dict[str, list[str]], keys: tuple[str, ...]) -> list[str]:
    for key in keys:
        vals = lists.get(key)
        if vals:
            return [v for v in vals if v]
        raw = scalars.get(key, "")
        if raw:
            return [part.strip() for part in raw.split(",") if part.strip()]
    return []


def _first_scalar(scalars: dict[str, str], lists: dict[str, list[str]], keys: tuple[str, ...]) -> str:
    for key in keys:
        val = str(scalars.get(key, "")).strip()
        if val:
            return val
        arr = lists.get(key)
        if arr:
            for item in arr:
                if str(item).strip():
                    return str(item).strip()
    return ""


def _parse_exercise_body(body_lines: list[str]) -> tuple[list[str], list[str], list[str]]:
    steps: list[str] = []
    tips: list[str] = []
    embeds: list[str] = []
    in_fence = False
    mode = ""

    for raw in body_lines:
        stripped = raw.strip()
        if stripped.startswith("```") or stripped.startswith("~~~"):
            in_fence = not in_fence
            continue
        if in_fence:
            continue

        for m in _WIKI_EMBED_RE.finditer(stripped):
            target = m.group(1).strip()
            if Path(target).suffix.lower() in ALLOWED_EXTENSIONS:
                embeds.append(target)
        for m in _MD_EMBED_RE.finditer(stripped):
            target = m.group(1).strip()
            if Path(target).suffix.lower() in ALLOWED_EXTENSIONS:
                embeds.append(target)

        heading_m = _HEADING_RE.match(stripped)
        if heading_m:
            low_h = heading_m.group(2).strip().lower()
            if any(tok in low_h for tok in ("how to perform", "execution", "instruction", "steps")):
                mode = "steps"
            elif ("tip" in low_h or "note" in low_h) and "daily" not in low_h:
                mode = "tips"
            else:
                mode = ""
            continue

        if not stripped or stripped.startswith("![[") or stripped.startswith("!["):
            continue

        clean_line = stripped
        if clean_line.startswith(("- ", "* ", "• ")):
            clean_line = clean_line[2:].strip()
        num_m = _NUMBERED_RE.match(clean_line)
        if num_m:
            clean_line = num_m.group(1).strip()

        if mode == "steps" or num_m:
            if clean_line:
                steps.append(clean_line)
        elif mode == "tips":
            if clean_line:
                tips.append(clean_line)

    return steps, tips, embeds


def get_exercise_detail(vault_str: str, rel_path_str: str) -> dict:
    vault_root = _resolve_vault_root(vault_str)
    rel_path, resolved = _resolve_vault_note(vault_root, rel_path_str)
    text = resolved.read_text(encoding="utf-8", errors="replace")
    scalars, lists, body_lines = _parse_yaml_frontmatter(text)
    body_steps, body_tips, embeds = _parse_exercise_body(body_lines)

    fm_steps = _split_frontmatter_list(scalars, lists, ("instructions", "steps"))
    fm_tips = _split_frontmatter_list(scalars, lists, ("tips",))
    steps = fm_steps + [s for s in body_steps if s not in fm_steps]
    tips = fm_tips + [t for t in body_tips if t not in fm_tips]

    primary_muscles = _split_frontmatter_list(
        scalars,
        lists,
        ("primarymuscles", "primary_muscles", "muscles", "muscle_group", "target_muscle", "primary_muscle", "muscle"),
    )
    secondary_muscles = _split_frontmatter_list(
        scalars,
        lists,
        ("secondarymuscles", "secondary_muscles"),
    )

    asset_index = _build_asset_basename_index(vault_root)
    poster_raw = _first_scalar(scalars, lists, ("poster", "cover", "preview", "previewimage", "preview_image", "image", "thumbnail"))
    featured_raw = _first_scalar(scalars, lists, ("featured_image", "animation", "gif", "photo"))
    images_list = _split_frontmatter_list(scalars, lists, ("images",))

    preview_url = _resolve_vault_asset_url(vault_root, resolved.parent, poster_raw, asset_index) if poster_raw else ""
    animation_url = _resolve_vault_asset_url(vault_root, resolved.parent, featured_raw, asset_index) if featured_raw else ""

    all_media_refs = images_list + embeds
    for ref in all_media_refs:
        resolved_url = _resolve_vault_asset_url(vault_root, resolved.parent, ref, asset_index)
        if not resolved_url:
            continue
        ext = Path(ref.split("|", 1)[0].strip()).suffix.lower()
        if ext in (".gif", ".webp") and not animation_url:
            animation_url = resolved_url
        if not preview_url:
            preview_url = resolved_url
        elif not animation_url and resolved_url != preview_url:
            animation_url = resolved_url

    title = _first_scalar(scalars, lists, ("name", "title")) or resolved.stem
    return {
        "ok": True,
        "relPath": rel_path,
        "id": _first_scalar(scalars, lists, ("id",)) or resolved.stem,
        "name": title,
        "level": _first_scalar(scalars, lists, ("level",)),
        "force": _first_scalar(scalars, lists, ("force",)),
        "mechanic": _first_scalar(scalars, lists, ("mechanic",)),
        "equipment": _first_scalar(scalars, lists, ("equipment",)),
        "category": _first_scalar(scalars, lists, ("category", "exercise_type")),
        "primaryMuscles": primary_muscles,
        "secondaryMuscles": secondary_muscles,
        "steps": steps,
        "tips": tips,
        "previewUrl": preview_url,
        "animationUrl": animation_url,
    }


def scan_exercises_library(vault_str: str) -> dict:
    vault_root = _resolve_vault_root(vault_str)
    asset_index = _build_asset_basename_index(vault_root)
    items: list[dict] = []
    seen_rel: set[str] = set()

    for rel_dir in EXERCISE_DIRS:
        base_dir = vault_root / rel_dir
        if not base_dir.exists() or not _is_within_vault(base_dir, vault_root):
            continue
        for root_dir, dirnames, filenames in os.walk(base_dir, followlinks=False):
            dirnames[:] = sorted(d for d in dirnames if d.lower() not in SKIP_DIR_NAMES)
            root_path = Path(root_dir)
            if not _is_within_vault(root_path, vault_root):
                continue
            for fname in sorted(filenames):
                if not fname.lower().endswith(".md") or "<%" in fname:
                    continue
                cand = root_path / fname
                if not _is_within_vault(cand, vault_root):
                    continue
                resolved = cand.resolve()
                if not resolved.is_file() or resolved.stat().st_size > MAX_NOTE_BYTES:
                    continue
                rel_path = cand.relative_to(vault_root).as_posix()
                if rel_path in seen_rel:
                    continue
                seen_rel.add(rel_path)
                try:
                    text = resolved.read_text(encoding="utf-8", errors="replace")
                except OSError:
                    continue
                scalars, lists, body_lines = _parse_yaml_frontmatter(text)
                _, _, embeds = _parse_exercise_body(body_lines)
                primary = _split_frontmatter_list(
                    scalars,
                    lists,
                    ("primarymuscles", "primary_muscles", "muscles", "muscle_group", "target_muscle", "primary_muscle", "muscle"),
                )
                secondary = _split_frontmatter_list(
                    scalars,
                    lists,
                    ("secondarymuscles", "secondary_muscles"),
                )
                poster_raw = _first_scalar(scalars, lists, ("poster", "cover", "preview", "previewimage", "preview_image", "image", "thumbnail"))
                featured_raw = _first_scalar(scalars, lists, ("featured_image", "animation", "gif", "photo"))
                images_list = _split_frontmatter_list(scalars, lists, ("images",))
                poster_url = _resolve_vault_asset_url(vault_root, resolved.parent, poster_raw, asset_index) if poster_raw else ""
                featured_url = _resolve_vault_asset_url(vault_root, resolved.parent, featured_raw, asset_index) if featured_raw else ""
                for ref in images_list + embeds:
                    resolved_url = _resolve_vault_asset_url(vault_root, resolved.parent, ref, asset_index)
                    if not resolved_url:
                        continue
                    ext = Path(ref.split("|", 1)[0].strip()).suffix.lower()
                    if ext in (".gif", ".webp") and not featured_url:
                        featured_url = resolved_url
                    if not poster_url:
                        poster_url = resolved_url
                    elif not featured_url and resolved_url != poster_url:
                        featured_url = resolved_url

                items.append({
                    "title": _first_scalar(scalars, lists, ("name", "title")) or resolved.stem,
                    "relPath": rel_path,
                    "level": _first_scalar(scalars, lists, ("level",)),
                    "force": _first_scalar(scalars, lists, ("force",)),
                    "mechanic": _first_scalar(scalars, lists, ("mechanic",)),
                    "muscleGroup": ", ".join(primary),
                    "secondaryMuscles": ", ".join(secondary),
                    "equipment": _first_scalar(scalars, lists, ("equipment",)),
                    "category": _first_scalar(scalars, lists, ("category", "exercise_type")),
                    "posterUrl": poster_url,
                    "featuredImageUrl": featured_url,
                })
                if len(items) >= MAX_SCAN_EXERCISES:
                    return {"ok": True, "exercises": items}

    return {"ok": True, "exercises": items}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="action", required=True)

    imp = sub.add_parser("import-photo")
    imp.add_argument("--source", required=True)
    imp.add_argument("--photos-dir", required=True)
    imp.add_argument("--checkin-id", required=True)
    imp.add_argument("--date", required=True)
    imp.add_argument("--vault", default="")
    imp.add_argument("--storage-mode", default="")
    imp.add_argument("--custom-dir", default="")

    res = sub.add_parser("resolve-photos-dir")
    res.add_argument("--photos-dir", required=True)
    res.add_argument("--vault", default="")
    res.add_argument("--storage-mode", default="auto")
    res.add_argument("--custom-dir", default="")

    rem = sub.add_parser("delete-photo")
    rem.add_argument("--photo-path", required=True)
    rem.add_argument("--photos-dir", required=True)
    rem.add_argument("--allowed-dir", action="append", default=[])

    det = sub.add_parser("exercise-detail")
    det.add_argument("--vault", required=True)
    det.add_argument("--rel-path", required=True)

    scn = sub.add_parser("scan-exercises")
    scn.add_argument("--vault", required=True)

    args = parser.parse_args()
    try:
        if args.action == "import-photo":
            out = import_photo(
                args.source,
                args.photos_dir,
                args.checkin_id,
                args.date,
                vault_str=args.vault,
                storage_mode=args.storage_mode,
                custom_dir_str=args.custom_dir,
            )
        elif args.action == "resolve-photos-dir":
            out = resolve_body_photos_dir(
                args.vault,
                args.photos_dir,
                storage_mode=args.storage_mode,
                custom_dir_str=args.custom_dir,
            )
        elif args.action == "delete-photo":
            out = delete_photo(args.photo_path, args.photos_dir, allowed_dirs=args.allowed_dir)
        elif args.action == "exercise-detail":
            out = get_exercise_detail(args.vault, args.rel_path)
        elif args.action == "scan-exercises":
            out = scan_exercises_library(args.vault)
        else:
            raise ValueError(f"Unsupported action: {args.action}")
        print(json.dumps(out))
    except (OSError, ValueError) as exc:
        print(json.dumps({"ok": False, "error": str(exc)}))
        raise SystemExit(1)


if __name__ == "__main__":
    main()
