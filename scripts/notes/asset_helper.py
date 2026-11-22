#!/usr/bin/env python3
"""Pure-stdlib Wayland clipboard image saver into Vault attachment folder."""
import argparse
import datetime
import json
import os
import subprocess
import sys
from pathlib import Path


MIME_EXT = (
    ("image/png", "png"),
    ("image/jpeg", "jpg"),
    ("image/webp", "webp"),
    ("image/gif", "gif"),
)


def _attachment_dir(vault: Path, current_rel: str, override_folder: str) -> Path:
    v_canon = vault.resolve()
    rel = override_folder.strip()
    if not rel:
        app_cfg = v_canon / ".obsidian" / "app.json"
        if app_cfg.is_file():
            try:
                cfg = json.loads(app_cfg.read_text(encoding="utf-8"))
                cfg_folder = str(cfg.get("attachmentFolderPath") or "").strip()
                if cfg_folder:
                    if cfg_folder.startswith("./") and current_rel:
                        parent = (v_canon / current_rel).resolve().parent
                        cand = (parent / cfg_folder[2:]).resolve()
                        if cand == v_canon or v_canon in cand.parents:
                            return cand
                    elif cfg_folder == "./" and current_rel:
                        cand = (v_canon / current_rel).resolve().parent
                        if cand == v_canon or v_canon in cand.parents:
                            return cand
                    else:
                        rel = cfg_folder.strip("/")
            except Exception:
                pass
    if not rel:
        rel = "99_Attachments" if (v_canon / "99_Attachments").is_dir() else "Attachments"
    target = (v_canon / rel).resolve()
    if target != v_canon and v_canon not in target.parents:
        raise ValueError(f"Attachment folder escapes vault: {rel}")
    return target


def cmd_paste_image(vault: Path, current_rel: str, folder: str, png_bytes_file: str = "") -> dict:
    v_canon = vault.resolve()
    if not v_canon.is_dir():
        return {"ok": False, "error": f"Vault directory missing: {vault}"}

    ext = "png"
    data = b""
    if png_bytes_file:
        src = Path(png_bytes_file)
        if not src.is_file():
            return {"ok": False, "error": f"Missing test file: {png_bytes_file}"}
        ext = src.suffix.lstrip(".").lower() or "png"
        data = src.read_bytes()
    else:
        lt = subprocess.run(["wl-paste", "--list-types"], capture_output=True, text=True, check=False)
        if lt.returncode != 0:
            return {"ok": True, "hasImage": False, "error": "Clipboard unavailable"}
        types = {line.strip() for line in lt.stdout.splitlines() if line.strip()}
        chosen_mime = ""
        for mime, candidate_ext in MIME_EXT:
            if mime in types:
                chosen_mime = mime
                ext = candidate_ext
                break
        if not chosen_mime:
            return {"ok": True, "hasImage": False}
        paste = subprocess.run(["wl-paste", "--no-newline", "--type", chosen_mime], capture_output=True, check=False)
        if paste.returncode != 0 or not paste.stdout:
            return {"ok": True, "hasImage": False, "error": "Clipboard read failed"}
        data = paste.stdout

    if not data:
        return {"ok": True, "hasImage": False}

    dest_dir = _attachment_dir(v_canon, current_rel, folder)
    dest_dir.mkdir(parents=True, exist_ok=True)
    ts = datetime.datetime.now().strftime("%Y%m%d%H%M%S")
    stem = f"Pasted-image-{ts}"
    dest = dest_dir / f"{stem}.{ext}"
    idx = 1
    while dest.exists():
        dest = dest_dir / f"{stem}-{idx}.{ext}"
        idx += 1

    tmp = dest.with_name(f".{dest.name}.{os.getpid()}.tmp")
    tmp.write_bytes(data)
    os.replace(tmp, dest)
    rel_out = dest.relative_to(v_canon).as_posix()
    return {
        "ok": True,
        "hasImage": True,
        "relPath": rel_out,
        "filename": dest.name,
        "markdownEmbed": f"![[{dest.name}]]",
        "sizeBytes": len(data),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("paste-image")
    p.add_argument("--vault", required=True)
    p.add_argument("--current-rel", default="")
    p.add_argument("--folder", default="")
    p.add_argument("--from-file", default="")

    args = parser.parse_args()
    try:
        out = cmd_paste_image(Path(args.vault), args.current_rel, args.folder, args.from_file)
    except Exception as exc:
        out = {"ok": False, "error": str(exc)}
    print(json.dumps(out, ensure_ascii=False))
    return 0 if out.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
