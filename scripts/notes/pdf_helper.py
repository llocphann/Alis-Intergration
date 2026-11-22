#!/usr/bin/env python3
"""Pure-stdlib PDF inspection, cached page rendering, text extraction, and highlight-to-note capture."""
import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path


def _cache_dir_for_pdf(pdf_path: Path) -> Path:
    xdg_cache = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache"))
    st = pdf_path.stat()
    key = hashlib.sha1(f"{pdf_path.resolve()}|{st.st_mtime_ns}|{st.st_size}".encode("utf-8")).hexdigest()[:16]
    out = xdg_cache / "alis" / "nexus-pdf" / key
    out.mkdir(parents=True, exist_ok=True)
    return out


def cmd_info(pdf_path: Path) -> dict:
    if not pdf_path.is_file():
        return {"ok": False, "error": f"PDF not found: {pdf_path}"}
    res = subprocess.run(["pdfinfo", str(pdf_path)], capture_output=True, text=True, check=False)
    if res.returncode != 0:
        return {"ok": False, "error": res.stderr.strip() or "pdfinfo failed"}
    pages = 1
    title = pdf_path.stem
    page_size = ""
    for line in res.stdout.splitlines():
        if line.startswith("Pages:"):
            try:
                pages = max(1, int(line.split(":", 1)[1].strip()))
            except ValueError:
                pass
        elif line.startswith("Title:"):
            t = line.split(":", 1)[1].strip()
            if t:
                title = t
        elif line.startswith("Page size:"):
            page_size = line.split(":", 1)[1].strip()
    return {
        "ok": True,
        "absPath": str(pdf_path),
        "title": title,
        "pages": pages,
        "pageSize": page_size,
        "sizeBytes": pdf_path.stat().st_size,
    }


def cmd_render(pdf_path: Path, page: int, dpi: int) -> dict:
    if not pdf_path.is_file():
        return {"ok": False, "error": f"PDF not found: {pdf_path}"}
    p = max(1, int(page))
    d = max(72, min(288, int(dpi)))
    cdir = _cache_dir_for_pdf(pdf_path)
    prefix = cdir / f"p{p}_d{d}"
    img_path = Path(f"{prefix}.png")
    if not img_path.is_file():
        res = subprocess.run(
            ["pdftoppm", "-png", "-f", str(p), "-l", str(p), "-r", str(d), "-singlefile", str(pdf_path), str(prefix)],
            capture_output=True,
            text=True,
            check=False,
        )
        if res.returncode != 0 or not img_path.is_file():
            return {"ok": False, "error": res.stderr.strip() or "pdftoppm failed"}
    return {
        "ok": True,
        "page": p,
        "dpi": d,
        "imagePath": str(img_path),
        "fileUrl": img_path.resolve().as_uri(),
    }


def cmd_extract_text(pdf_path: Path, page: int) -> dict:
    if not pdf_path.is_file():
        return {"ok": False, "error": f"PDF not found: {pdf_path}"}
    p = max(1, int(page))
    res = subprocess.run(
        ["pdftotext", "-f", str(p), "-l", str(p), "-layout", str(pdf_path), "-"],
        capture_output=True,
        text=True,
        check=False,
    )
    if res.returncode != 0:
        return {"ok": False, "error": res.stderr.strip() or "pdftotext failed"}
    return {
        "ok": True,
        "page": p,
        "text": res.stdout,
    }


def _safe_resolve_inside_vault(vault: Path, rel_path: str) -> Path:
    v_canon = vault.resolve()
    candidate = (v_canon / rel_path.lstrip("/")).resolve()
    if candidate != v_canon and v_canon not in candidate.parents:
        raise ValueError(f"Path escapes vault: {rel_path}")
    return candidate


def cmd_capture_highlight(vault: Path, pdf_rel: str, page: int, quote: str, note_rel: str) -> dict:
    q = quote.strip()
    if not q:
        return {"ok": False, "error": "Highlight text is empty"}
    p = max(1, int(page))
    v_canon = vault.resolve()
    if note_rel.strip():
        target = _safe_resolve_inside_vault(v_canon, note_rel.strip())
    else:
        stem = Path(pdf_rel).stem
        safe_name = re.sub(r'[\\/:*?"<>|]+', "_", stem).strip() or "PDF Notes"
        folder = v_canon / "00_Capture"
        if not folder.is_dir():
            folder = v_canon
        target = _safe_resolve_inside_vault(v_canon, str((folder / f"{safe_name} - Highlights.md").relative_to(v_canon)))

    target.parent.mkdir(parents=True, exist_ok=True)
    quote_lines = "\n".join(f"> {line}" if line.strip() else ">" for line in q.splitlines())
    snippet = f"\n{quote_lines}\n— [[{pdf_rel}#page={p}]] (p. {p})\n"
    if target.is_file():
        existing = target.read_text(encoding="utf-8")
        new_text = existing.rstrip() + "\n" + snippet
    else:
        new_text = (
            f"---\ntags:\n  - literature\n  - pdf-highlight\nsource: \"[[{pdf_rel}]]\"\n---\n\n"
            f"# {target.stem}\n"
            + snippet
        )
    tmp = target.with_name(f".{target.name}.{os.getpid()}.tmp")
    tmp.write_text(new_text, encoding="utf-8")
    os.replace(tmp, target)
    return {
        "ok": True,
        "relPath": target.relative_to(v_canon).as_posix(),
        "page": p,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_info = sub.add_parser("info")
    p_info.add_argument("--pdf", required=True)

    p_ren = sub.add_parser("render")
    p_ren.add_argument("--pdf", required=True)
    p_ren.add_argument("--page", type=int, default=1)
    p_ren.add_argument("--dpi", type=int, default=150)

    p_txt = sub.add_parser("extract-text")
    p_txt.add_argument("--pdf", required=True)
    p_txt.add_argument("--page", type=int, default=1)

    p_cap = sub.add_parser("capture-highlight")
    p_cap.add_argument("--vault", required=True)
    p_cap.add_argument("--pdf-rel", required=True)
    p_cap.add_argument("--page", type=int, default=1)
    p_cap.add_argument("--quote", required=True)
    p_cap.add_argument("--note-rel", default="")

    args = parser.parse_args()
    try:
        if args.cmd == "info":
            out = cmd_info(Path(args.pdf))
        elif args.cmd == "render":
            out = cmd_render(Path(args.pdf), args.page, args.dpi)
        elif args.cmd == "extract-text":
            out = cmd_extract_text(Path(args.pdf), args.page)
        elif args.cmd == "capture-highlight":
            out = cmd_capture_highlight(Path(args.vault), args.pdf_rel, args.page, args.quote, args.note_rel)
        else:
            out = {"ok": False, "error": f"Unknown subcommand: {args.cmd}"}
    except Exception as exc:
        out = {"ok": False, "error": str(exc)}

    print(json.dumps(out, ensure_ascii=False))
    return 0 if out.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
