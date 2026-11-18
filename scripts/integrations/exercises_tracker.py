#!/usr/bin/env python3
"""User-initiated Body Tracker photo import and safe cleanup helper.

Strictly operates only on an explicit file path chosen by the user and copies
into the isolated user-state photos directory. Never scans private folders,
never follows symlinks, and never deletes files outside photos_dir.
"""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import sys
import tempfile

ALLOWED_EXTENSIONS = {".png", ".jpg", ".jpeg", ".webp", ".bmp", ".avif", ".gif"}
MAX_IMAGE_BYTES = 32 * 1024 * 1024
SAFE_TOKEN_RE = re.compile(r"^[A-Za-z0-9_-]{1,64}$")
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")


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


def import_photo(source_str: str, photos_dir_str: str, checkin_id: str, date_str: str) -> dict:
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

    return {
        "ok": True,
        "photoPath": str(dest),
        "photoRel": f"photos/{filename}",
        "sizeBytes": dest.stat().st_size,
    }


def delete_photo(photo_path_str: str, photos_dir_str: str) -> dict:
    raw = str(photo_path_str or "").strip()
    if raw.startswith("file://"):
        from urllib.parse import unquote, urlsplit
        raw = unquote(urlsplit(raw).path)
    if not raw:
        return {"ok": True, "deleted": False}

    photos_dir = Path(photos_dir_str)
    if not photos_dir.exists() or photos_dir.is_symlink() or not photos_dir.is_dir():
        return {"ok": True, "deleted": False}
    resolved_dir = photos_dir.resolve()

    target = Path(raw)
    if target.is_symlink():
        raise ValueError("Refusing to delete symlink")
    if not target.exists():
        return {"ok": True, "deleted": False}
    resolved_target = target.resolve()
    if resolved_target.parent != resolved_dir or not resolved_target.is_file():
        raise ValueError("Refusing to delete file outside Body Tracker photos directory")
    resolved_target.unlink()
    return {"ok": True, "deleted": True}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="action", required=True)

    imp = sub.add_parser("import-photo")
    imp.add_argument("--source", required=True)
    imp.add_argument("--photos-dir", required=True)
    imp.add_argument("--checkin-id", required=True)
    imp.add_argument("--date", required=True)

    rem = sub.add_parser("delete-photo")
    rem.add_argument("--photo-path", required=True)
    rem.add_argument("--photos-dir", required=True)

    args = parser.parse_args()
    try:
        if args.action == "import-photo":
            out = import_photo(args.source, args.photos_dir, args.checkin_id, args.date)
        else:
            out = delete_photo(args.photo_path, args.photos_dir)
        print(json.dumps(out))
    except (OSError, ValueError) as exc:
        print(json.dumps({"ok": False, "error": str(exc)}))
        raise SystemExit(1)


if __name__ == "__main__":
    main()
