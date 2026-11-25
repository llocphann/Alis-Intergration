#!/usr/bin/env python3
"""Unified silent test runner for Alis-Intergration."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import sys
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS_DIR = ROOT / "scripts"
sys.path.insert(0, str(SCRIPTS_DIR))
from integration_test_host import resolve_host_root  # noqa: E402


def resolve_companion_root() -> Path | None:
    override = os.environ.get("ALIS_COMPANION_ROOT", "").strip()
    candidates = [Path(override)] if override else [ROOT.parent / "Alis-Companion"]
    for candidate in candidates:
        resolved = candidate.resolve()
        if (resolved / "services/AquaMind.qml").is_file():
            return resolved
    return None


def build_checks(tmp_root: Path, host_root: Path, companion_root: Path | None) -> list[dict]:
    def py(script: str, *extra: str) -> list[str]:
        return [sys.executable, f"scripts/{script}", *extra]

    def sh(interp: str, script: str) -> list[str]:
        return [interp, f"scripts/{script}"]

    sr_out = tmp_root / "sr-prompts-runtime"
    reopen_dir = tmp_root / "host-reopen"
    checkin_dir = tmp_root / "checkin-startup"
    visual_dir = tmp_root / "visual-polish"
    menu_dir = tmp_root / "context-menu"
    stale_dir = tmp_root / "search-stale"

    checks: list[dict] = [
        # Fast unit, contract, helper, and QML lint checks
        {"name": "test-public-branding.py", "group": "fast", "cmd": py("test-public-branding.py")},
        {"name": "test-rebrand-compatibility.py", "group": "fast", "cmd": py("test-rebrand-compatibility.py")},
        {"name": "test-plugin-metadata.py", "group": "fast", "cmd": py("test-plugin-metadata.py")},
        {"name": "test-host-location.py", "group": "fast", "cmd": py("test-host-location.py")},
        {"name": "test-install.py", "group": "fast", "cmd": py("test-install.py")},
        {"name": "test-battery-charge-limit-helper.sh", "group": "fast", "cmd": sh("sh", "test-battery-charge-limit-helper.sh")},
        {"name": "test-thinkfan-helper.sh", "group": "fast", "cmd": sh("bash", "test-thinkfan-helper.sh")},
        {"name": "test-thinkfan-suspend-resume.py", "group": "fast", "cmd": py("test-thinkfan-suspend-resume.py")},
        {"name": "test-worker-lifecycle.sh", "group": "fast", "cmd": sh("bash", "test-worker-lifecycle.sh")},
        {"name": "test-tlp-settings-ui-guards.sh", "group": "fast", "cmd": sh("sh", "test-tlp-settings-ui-guards.sh")},
        {"name": "test-tlp-vendor-probes.py", "group": "fast", "cmd": py("test-tlp-vendor-probes.py")},
        {"name": "test-tlp-allowed-limits-parity.cjs", "group": "fast", "cmd": ["node", "scripts/test-tlp-allowed-limits-parity.cjs"]},
        {"name": "test-fan-worker-contract.py", "group": "fast", "cmd": py("test-fan-worker-contract.py")},
        {"name": "test-thinkfan-settings.py", "group": "fast", "cmd": py("test-thinkfan-settings.py")},
        {"name": "test-nexus-todo-settings.py", "group": "fast", "cmd": py("test-nexus-todo-settings.py")},
        {"name": "test-todo-nexus-helper.py", "group": "fast", "cmd": py("test-todo-nexus-helper.py")},
        {"name": "test-todo-nexus-daily-helper.py", "group": "fast", "cmd": py("test-todo-nexus-daily-helper.py")},
        {"name": "test-nexus-theme.py", "group": "fast", "cmd": py("test-nexus-theme.py")},
        {"name": "test-nexus-worker-contracts.py", "group": "fast", "cmd": py("test-nexus-worker-contracts.py")},
        {"name": "test-nexus-accel-benchmarks.py", "group": "fast", "cmd": py("test-nexus-accel-benchmarks.py")},
        {"name": "test-zettelkasten-quicknote.py", "group": "fast", "cmd": py("test-zettelkasten-quicknote.py")},
        {"name": "test-zettelkasten-images.py", "group": "fast", "cmd": py("test-zettelkasten-images.py")},
        {"name": "test-spaced-repetition.py", "group": "fast", "cmd": py("test-spaced-repetition.py")},
        {"name": "test-sr-prompts.cjs", "group": "fast", "cmd": ["node", "scripts/test-sr-prompts.cjs"]},
        {"name": "test-exercises-tracker.py", "group": "fast", "cmd": py("test-exercises-tracker.py")},
        {"name": "test-alis-files.py", "group": "fast", "cmd": py("test-alis-files.py")},
        {"name": "test-qml.py", "group": "fast", "cmd": py("test-qml.py")},
        # Quickshell / Wayland runtime suites
        {"name": "test-zettelkasten-failure-runtime.py", "group": "runtime", "cmd": py("test-zettelkasten-failure-runtime.py")},
        {"name": "test-todo-nexus-tasks-runtime.py", "group": "runtime", "cmd": py("test-todo-nexus-tasks-runtime.py")},
        {"name": "test-nexus-path-settings-runtime.py", "group": "runtime", "cmd": py("test-nexus-path-settings-runtime.py")},
        {"name": "test-zettelkasten-image-runtime.py", "group": "runtime", "cmd": py("test-zettelkasten-image-runtime.py")},
        {"name": "test-nexus.py", "group": "runtime", "cmd": py("test-nexus.py")},
        {"name": "test-nexus-graph-freeze-runtime.py", "group": "runtime", "cmd": py("test-nexus-graph-freeze-runtime.py")},
        {"name": "test-nexus-globe-freeze-runtime.py", "group": "runtime", "cmd": py("test-nexus-globe-freeze-runtime.py")},
        {"name": "test-nexus-api-trash-and-inline-edit.py", "group": "runtime", "cmd": py("test-nexus-api-trash-and-inline-edit.py")},
        {"name": "test-nexus-companion-bridge-runtime.py", "group": "runtime", "cmd": py("test-nexus-companion-bridge-runtime.py")},
        {"name": "test-nexus-places-theme-runtime.py", "group": "runtime", "cmd": py("test-nexus-places-theme-runtime.py")},
        {"name": "test-nexus-responsive-runtime.py", "group": "runtime", "cmd": py("test-nexus-responsive-runtime.py")},
        {"name": "test-nexus-round2-offscreen-runtime.py", "group": "runtime", "cmd": py("test-nexus-round2-offscreen-runtime.py")},
        {
            "name": "test-nexus-context-menu-runtime.py",
            "group": "runtime",
            "cmd": py("test-nexus-context-menu-runtime.py"),
            "env": {"ALIS_MENU_EVIDENCE": str(menu_dir)},
        },
        {
            "name": "test-nexus-search-stale-runtime.py",
            "group": "runtime",
            "cmd": py("test-nexus-search-stale-runtime.py"),
            "env": {"ALIS_RECENT_EVIDENCE": str(stale_dir)},
        },
        {
            "name": "test-nexus-host-reopen-runtime.py",
            "group": "runtime",
            "cmd": py(
                "test-nexus-host-reopen-runtime.py",
                "--host",
                str(host_root),
                "--plugin",
                str(ROOT),
                "--evidence-dir",
                str(reopen_dir),
            ),
        },
        {
            "name": "test-nexus-visual-polish-runtime.py",
            "group": "runtime",
            "cmd": py("test-nexus-visual-polish-runtime.py"),
            "env": {"ALIS_NEXUS_RESPONSIVE_EVIDENCE_DIR": str(visual_dir)},
        },
        {
            "name": "test-nexus-checkin-startup-runtime.py",
            "group": "runtime",
            "cmd": (
                py(
                    "test-nexus-checkin-startup-runtime.py",
                    "--host",
                    str(host_root),
                    "--plugin",
                    str(ROOT),
                    "--companion",
                    str(companion_root),
                    "--evidence-dir",
                    str(checkin_dir),
                )
                if companion_root is not None
                else None
            ),
            "skip_reason": "Alis-Companion sibling repo not found" if companion_root is None else "",
        },
        {
            "name": "test-sr-prompts-runtime.py",
            "group": "runtime",
            "cmd": py("test-sr-prompts-runtime.py", "--output", str(sr_out)),
        },
        {"name": "test-exercises-tracker-runtime.py", "group": "runtime", "cmd": py("test-exercises-tracker-runtime.py")},
        {"name": "test-exercises-tracker-contrast.py", "group": "runtime", "cmd": py("test-exercises-tracker-contrast.py")},
        {"name": "test-host-runtime.py", "group": "runtime", "cmd": py("test-host-runtime.py")},
        {"name": "test-settings-host-runtime.py", "group": "runtime", "cmd": py("test-settings-host-runtime.py")},
        {"name": "test-rebrand-persistence-runtime.py", "group": "runtime", "cmd": py("test-rebrand-persistence-runtime.py")},
    ]
    return checks


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fast", action="store_true", help="run only fast unit, contract, and QML lint checks")
    parser.add_argument("--only", help="run only checks whose name contains PATTERN (case-insensitive)")
    parser.add_argument("--list", action="store_true", help="list planned checks and exit")
    parser.add_argument("--fail-fast", action="store_true", help="stop on the first failing check")
    parser.add_argument("--json", type=Path, help="write structured JSON report to PATH")
    color_grp = parser.add_mutually_exclusive_group()
    color_grp.add_argument("--color", action="store_true", help="force ANSI colors")
    color_grp.add_argument("--no-color", action="store_true", help="disable ANSI colors")
    args = parser.parse_args()

    use_color = args.color or (not args.no_color and not os.environ.get("NO_COLOR") and sys.stdout.isatty())
    c_rst = "\033[0m" if use_color else ""
    c_bold = "\033[1m" if use_color else ""
    c_dim = "\033[2m" if use_color else ""
    c_pri = "\033[36m" if use_color else ""
    c_ok = "\033[1;32m" if use_color else ""
    c_err = "\033[1;31m" if use_color else ""
    c_warn = "\033[1;33m" if use_color else ""

    host_root = resolve_host_root(ROOT)
    companion_root = resolve_companion_root()

    with tempfile.TemporaryDirectory(prefix="alis-integration-tests-") as tmp_str:
        tmp_root = Path(tmp_str)
        all_checks = build_checks(tmp_root, host_root, companion_root)

        selected: list[dict] = []
        pat = (args.only or "").strip().lower()
        for entry in all_checks:
            if args.fast and entry["group"] != "fast":
                continue
            if pat and pat not in entry["name"].lower():
                continue
            selected.append(entry)

        if args.list:
            for i, entry in enumerate(selected, 1):
                print(f"[{i:03d}] {entry['group']:<8s} {entry['name']}")
            print(f"Total planned checks: {len(selected)}")
            return 0

        if not selected:
            print(f"{c_warn}No checks matched filter (only={args.only!r}, fast={args.fast}).{c_rst}")
            return 2

        base_env = {k: v for k, v in os.environ.items() if k not in ("WAYLAND_DISPLAY", "DISPLAY")}
        base_env["QT_QPA_PLATFORM"] = "offscreen"
        base_env["PYTHONDONTWRITEBYTECODE"] = "1"
        base_env["ALIS_ROOT"] = str(host_root)

        print(
            f"{c_pri}{c_bold}ALIS-INTEGRATION TEST SUITE{c_rst}  "
            f"{c_dim}checks={len(selected)}  fast={args.fast}  host={host_root.name}{c_rst}",
            flush=True,
        )

        suite_t0 = time.monotonic()
        passed = failed = skipped = 0
        results: list[dict] = []
        total = len(selected)

        for idx, entry in enumerate(selected, 1):
            name = entry["name"]
            group = entry["group"]
            cmd = entry.get("cmd")
            t0 = time.monotonic()

            if cmd is None:
                dt = 0.0
                status = "SKIP"
                rc = 77
                out_text = entry.get("skip_reason") or "dependency unavailable"
            else:
                run_env = base_env.copy()
                run_env.update(entry.get("env", {}))
                timeout = 240 if group == "runtime" else 90
                proc = subprocess.run(
                    cmd,
                    cwd=ROOT,
                    env=run_env,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    text=True,
                    timeout=timeout,
                )
                dt = time.monotonic() - t0
                rc = proc.returncode
                out_text = proc.stdout
                is_skip = rc == 77 or out_text.lstrip().startswith("SKIP:")
                status = "SKIP" if is_skip else ("PASS" if rc == 0 else "FAIL")

            dur_ms = int(round(dt * 1000))
            badge_col = c_warn if status == "SKIP" else (c_ok if status == "PASS" else c_err)
            dur_col = c_warn if dt >= 5.0 else c_dim
            print(
                f"[{idx:03d}/{total:03d}] {name:<44s} {badge_col}{status}{c_rst}  {dur_col}{dt:5.2f}s{c_rst}",
                flush=True,
            )
            results.append({
                "name": name,
                "group": group,
                "status": status,
                "exit_code": rc,
                "duration_ms": dur_ms,
            })

            if status == "SKIP":
                skipped += 1
                reason = next((ln.strip() for ln in out_text.splitlines() if ln.strip()), "")
                if reason:
                    print(f"      {c_dim}{reason[:160]}{c_rst}", flush=True)
            elif status == "PASS":
                passed += 1
                if args.only:
                    tail = "\n".join(out_text.strip().splitlines()[-8:])
                    if tail:
                        print(f"{c_dim}{tail}{c_rst}", flush=True)
            else:
                failed += 1
                tail = "\n".join(out_text.strip().splitlines()[-25:])
                if tail:
                    print(tail, flush=True)
                if args.fail_fast:
                    break

        total_dt = time.monotonic() - suite_t0

        if args.json:
            args.json.parent.mkdir(parents=True, exist_ok=True)
            payload = {
                "result": "PASS" if failed == 0 else "FAIL",
                "duration_ms": int(round(total_dt * 1000)),
                "counts": {"passed": passed, "failed": failed, "skipped": skipped, "total": len(results)},
                "checks": results,
            }
            args.json.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")

        summary_col = c_ok if failed == 0 else c_err
        summary_word = "PASS" if failed == 0 else "FAIL"
        slowest = sorted(results, key=lambda r: r["duration_ms"], reverse=True)[:5]
        print(
            f"\n{summary_col}{summary_word}{c_rst}  "
            f"{c_ok}{passed} PASS{c_rst}  /  {c_err if failed else c_dim}{failed} FAIL{c_rst}  /  "
            f"{c_warn if skipped else c_dim}{skipped} SKIP{c_rst}  "
            f"{c_dim}(elapsed {total_dt:.2f}s, {len(results)}/{total} ran){c_rst}",
            flush=True,
        )
        if slowest:
            print(f"{c_dim}Slowest checks:{c_rst}", flush=True)
            for item in slowest:
                print(f"  {c_dim}{item['duration_ms']/1000:5.2f}s  {item['group']:<8s} {item['name']}{c_rst}", flush=True)

        return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
