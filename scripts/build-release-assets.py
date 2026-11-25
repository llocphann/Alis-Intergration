#!/usr/bin/env python3
"""Build lightweight base + individual per-plugin release tarballs and SHA256SUMS."""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def _load_installer():
    spec = importlib.util.spec_from_file_location("installer", ROOT / "scripts" / "install.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _deterministic_tar_gz(src_dir: Path, out_path: Path, prefix: str) -> str:
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with tarfile.open(out_path, "w:gz", format=tarfile.PAX_FORMAT) as tar:
        for path in sorted(src_dir.rglob("*")):
            if "__pycache__" in path.parts or path.suffix in (".pyc", ".pyo"):
                continue
            rel = path.relative_to(src_dir)
            arcname = f"{prefix}/{rel.as_posix()}" if prefix else rel.as_posix()
            info = tar.gettarinfo(str(path), arcname=arcname)
            info.mtime = 0
            info.uid = 0
            info.gid = 0
            info.uname = "root"
            info.gname = "root"
            if path.is_file():
                with path.open("rb") as handle:
                    tar.addfile(info, handle)
            elif path.is_dir():
                tar.addfile(info)
    return hashlib.sha256(out_path.read_bytes()).hexdigest()


def build_release_assets(source: Path, out_dir: Path, sha: str | None = None) -> dict[str, str]:
    installer = _load_installer()
    source = Path(source).resolve()
    out_dir = Path(out_dir).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    if not sha:
        sha = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=source, text=True).strip()
    manifest = json.loads((source / "manifest.json").read_text(encoding="utf-8"))
    plugin_ids = [item["id"] for item in installer.plugin_metadata(manifest)]
    checksums: dict[str, str] = {}
    with tempfile.TemporaryDirectory(prefix="alis-release-assets-") as tmp:
        stage = Path(tmp)
        base_stage = stage / "base"
        installer.assemble_base(source, base_stage, sha)
        base_name = "alis-intergration-base.tar.gz"
        checksums[base_name] = _deterministic_tar_gz(base_stage, out_dir / base_name, "alis-intergration-base")
        for plugin_id in plugin_ids:
            plugin_stage = stage / plugin_id
            installer.assemble_plugin(source, plugin_id, plugin_stage, sha)
            asset_name = f"alis-intergration-plugin-{plugin_id}.tar.gz"
            checksums[asset_name] = _deterministic_tar_gz(plugin_stage, out_dir / asset_name, f"plugins/{plugin_id}")
    lines = [f"{digest}  {name}" for name, digest in sorted(checksums.items())]
    (out_dir / "SHA256SUMS").write_text("\n".join(lines) + "\n", encoding="utf-8")
    return checksums


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=ROOT)
    parser.add_argument("--out-dir", type=Path, default=ROOT / "dist")
    parser.add_argument("--sha", default="")
    args = parser.parse_args()
    checksums = build_release_assets(args.source, args.out_dir, args.sha or None)
    for name, digest in sorted(checksums.items()):
        print(f"{digest}  {name}")


if __name__ == "__main__":
    main()
