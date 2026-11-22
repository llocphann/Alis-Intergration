#!/usr/bin/env python3
"""Pure-stdlib external snapshot & Git note history + diff + reversible restore."""
import argparse
import datetime
import difflib
import hashlib
import json
import os
import subprocess
from pathlib import Path

MAX_SNAPSHOTS_PER_NOTE = 20


def _state_root(vault_canon: Path, rel_path: str) -> Path:
    xdg_state = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local" / "state"))
    v_hash = hashlib.sha1(str(vault_canon).encode("utf-8")).hexdigest()[:12]
    n_hash = hashlib.sha1(rel_path.encode("utf-8")).hexdigest()[:16]
    folder = xdg_state / "quickshell" / "user" / "nexus_history" / v_hash / n_hash
    folder.mkdir(parents=True, exist_ok=True)
    return folder


def _resolve_note(vault: Path, rel_path: str) -> tuple[Path, Path, str]:
    v_canon = vault.resolve()
    clean_rel = rel_path.strip().lstrip("/")
    target = (v_canon / clean_rel).resolve()
    if target != v_canon and v_canon not in target.parents:
        raise ValueError(f"Path escapes vault: {rel_path}")
    return v_canon, target, target.relative_to(v_canon).as_posix()


def _snapshot_meta_path(hist_dir: Path) -> Path:
    return hist_dir / "index.json"


def _load_snap_index(hist_dir: Path) -> list[dict]:
    idx_file = _snapshot_meta_path(hist_dir)
    if not idx_file.is_file():
        return []
    try:
        data = json.loads(idx_file.read_text(encoding="utf-8"))
        return data if isinstance(data, list) else []
    except Exception:
        return []


def _save_snap_index(hist_dir: Path, items: list[dict]) -> None:
    idx_file = _snapshot_meta_path(hist_dir)
    tmp = idx_file.with_name(f".index.{os.getpid()}.tmp")
    tmp.write_text(json.dumps(items, ensure_ascii=False, indent=2), encoding="utf-8")
    os.replace(tmp, idx_file)


def cmd_snapshot(vault: Path, rel_path: str, label: str = "Edit snapshot") -> dict:
    v_canon, target, norm_rel = _resolve_note(vault, rel_path)
    if not target.is_file():
        return {"ok": False, "error": f"Note not found: {norm_rel}"}
    content = target.read_text(encoding="utf-8")
    digest = hashlib.sha1(content.encode("utf-8")).hexdigest()[:12]
    hist_dir = _state_root(v_canon, norm_rel)
    snaps = _load_snap_index(hist_dir)
    if snaps and snaps[0].get("sha1") == digest:
        return {"ok": True, "created": False, "revId": snaps[0]["revId"], "relPath": norm_rel}

    now = datetime.datetime.now(datetime.timezone.utc).astimezone()
    rev_id = f"snap:{now.strftime('%Y%m%d%H%M%S')}_{digest[:6]}"
    snap_file = hist_dir / f"{rev_id.replace(':', '_')}.txt"
    snap_file.write_text(content, encoding="utf-8")
    snaps.insert(0, {
        "revId": rev_id,
        "source": "snapshot",
        "timestamp": now.isoformat(timespec="seconds"),
        "displayTime": now.strftime("%Y-%m-%d %H:%M:%S"),
        "summary": label or "Snapshot",
        "sha1": digest,
        "bytes": len(content.encode("utf-8")),
        "file": snap_file.name,
    })
    while len(snaps) > MAX_SNAPSHOTS_PER_NOTE:
        dropped = snaps.pop()
        old_f = hist_dir / str(dropped.get("file", ""))
        if old_f.is_file():
            old_f.unlink(missing_ok=True)
    _save_snap_index(hist_dir, snaps)
    return {"ok": True, "created": True, "revId": rev_id, "relPath": norm_rel}


def _git_log_for_note(v_canon: Path, norm_rel: str, limit: int = 20) -> list[dict]:
    probe = subprocess.run(
        ["git", "-C", str(v_canon), "rev-parse", "--is-inside-work-tree"],
        capture_output=True, text=True, check=False,
    )
    if probe.returncode != 0 or probe.stdout.strip() != "true":
        return []
    log_res = subprocess.run(
        ["git", "-C", str(v_canon), "log", f"-n{limit}", "--format=%H%x1f%cI%x1f%s", "--", norm_rel],
        capture_output=True, text=True, check=False,
    )
    if log_res.returncode != 0:
        return []
    out = []
    for line in log_res.stdout.splitlines():
        parts = line.split("\x1f", 2)
        if len(parts) == 3:
            sha, iso_dt, subj = parts
            out.append({
                "revId": f"git:{sha}",
                "source": "git",
                "timestamp": iso_dt,
                "displayTime": iso_dt[:19].replace("T", " "),
                "summary": subj or sha[:8],
                "sha1": sha[:8],
            })
    return out


def _read_revision_content(v_canon: Path, norm_rel: str, rev_id: str) -> str:
    if rev_id.startswith("snap:"):
        hist_dir = _state_root(v_canon, norm_rel)
        for item in _load_snap_index(hist_dir):
            if item.get("revId") == rev_id:
                f = hist_dir / str(item.get("file", ""))
                if f.is_file():
                    return f.read_text(encoding="utf-8")
        raise FileNotFoundError(f"Snapshot not found: {rev_id}")
    if rev_id.startswith("git:"):
        sha = rev_id[4:]
        if not sha.isalnum():
            raise ValueError("Invalid git revision id")
        res = subprocess.run(
            ["git", "-C", str(v_canon), "show", f"{sha}:{norm_rel}"],
            capture_output=True, text=True, check=False,
        )
        if res.returncode != 0:
            raise RuntimeError(res.stderr.strip() or "git show failed")
        return res.stdout
    raise ValueError(f"Unsupported revId: {rev_id}")


def cmd_list(vault: Path, rel_path: str) -> dict:
    v_canon, _, norm_rel = _resolve_note(vault, rel_path)
    hist_dir = _state_root(v_canon, norm_rel)
    snaps = _load_snap_index(hist_dir)
    commits = _git_log_for_note(v_canon, norm_rel, 20)
    revisions = snaps + commits
    revisions.sort(key=lambda r: str(r.get("timestamp", "")), reverse=True)
    return {
        "ok": True,
        "relPath": norm_rel,
        "revisions": revisions[:40],
    }


def cmd_diff(vault: Path, rel_path: str, rev_id: str) -> dict:
    v_canon, target, norm_rel = _resolve_note(vault, rel_path)
    rev_text = _read_revision_content(v_canon, norm_rel, rev_id)
    cur_text = target.read_text(encoding="utf-8") if target.is_file() else ""
    diff_lines = list(difflib.unified_diff(
        rev_text.splitlines(),
        cur_text.splitlines(),
        fromfile=rev_id,
        tofile=f"current:{norm_rel}",
        lineterm="",
    ))
    return {
        "ok": True,
        "relPath": norm_rel,
        "revId": rev_id,
        "diff": "\n".join(diff_lines) if diff_lines else "(Identical to current file)",
        "revisionContent": rev_text,
    }


def cmd_restore(vault: Path, rel_path: str, rev_id: str) -> dict:
    v_canon, target, norm_rel = _resolve_note(vault, rel_path)
    if target.is_file():
        cmd_snapshot(v_canon, norm_rel, f"Pre-restore backup before {rev_id[:16]}")
    rev_text = _read_revision_content(v_canon, norm_rel, rev_id)
    target.parent.mkdir(parents=True, exist_ok=True)
    tmp = target.with_name(f".{target.name}.{os.getpid()}.tmp")
    tmp.write_text(rev_text, encoding="utf-8")
    os.replace(tmp, target)
    return {
        "ok": True,
        "relPath": norm_rel,
        "restoredRevId": rev_id,
        "content": rev_text,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="cmd", required=True)

    for name in ("snapshot", "list", "diff", "restore"):
        p = sub.add_parser(name)
        p.add_argument("--vault", required=True)
        p.add_argument("--path", required=True)
        if name == "snapshot":
            p.add_argument("--label", default="Manual snapshot")
        if name in ("diff", "restore"):
            p.add_argument("--rev", required=True)

    args = parser.parse_args()
    try:
        if args.cmd == "snapshot":
            out = cmd_snapshot(Path(args.vault), args.path, args.label)
        elif args.cmd == "list":
            out = cmd_list(Path(args.vault), args.path)
        elif args.cmd == "diff":
            out = cmd_diff(Path(args.vault), args.path, args.rev)
        elif args.cmd == "restore":
            out = cmd_restore(Path(args.vault), args.path, args.rev)
        else:
            out = {"ok": False, "error": f"Unknown subcommand: {args.cmd}"}
    except Exception as exc:
        out = {"ok": False, "error": str(exc)}
    print(json.dumps(out, ensure_ascii=False))
    return 0 if out.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
