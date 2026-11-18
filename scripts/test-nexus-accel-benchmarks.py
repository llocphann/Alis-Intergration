#!/usr/bin/env python3
"""Benchmark and functional parity suite for Nexus native & QML optimizations
plus the Exercises Tracker <-> Nexus live state bridge.

Runs 100% silently (offscreen / headless) in temporary /tmp directories;
never touches real user vaults or ~/.local/state.
"""

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
NEXUS_BIN = ROOT / "assets" / "bin" / "alis-nexus"


def resolve_host_root() -> Path:
    env_host = os.environ.get("ALIS_HOST_ROOT", "").strip()
    if env_host:
        p = Path(env_host)
        if (p / "shell.qml").is_file():
            return p
    for cand in (ROOT.parent / "Alis", ROOT.resolve().parent / "Alis"):
        if (cand / "shell.qml").is_file():
            return cand
    raise RuntimeError("Cannot locate Alis host root")


def _headless_env(extra: dict[str, str] | None = None) -> dict[str, str]:
    env = dict(os.environ)
    env.pop("WAYLAND_DISPLAY", None)
    env.pop("DISPLAY", None)
    env.pop("NIRI_SOCKET", None)
    env["QT_QPA_PLATFORM"] = "offscreen"
    env["QT_QUICK_BACKEND"] = "software"
    if extra:
        env.update(extra)
    return env


def build_synthetic_vault(vault: Path, note_count: int = 480) -> None:
    (vault / "00_Journal").mkdir(parents=True, exist_ok=True)
    (vault / "03_Zettelkasten").mkdir(parents=True, exist_ok=True)
    (vault / "25_Media_Tracker" / "Movies").mkdir(parents=True, exist_ok=True)
    (vault / "23_Places").mkdir(parents=True, exist_ok=True)
    (vault / "33_Bodybuilding" / "Gym_n_Calisthenics_Exercises").mkdir(parents=True, exist_ok=True)
    (vault / "90_System" / "95_Attachments").mkdir(parents=True, exist_ok=True)

    for a in range(80):
        (vault / "90_System" / "95_Attachments" / f"poster_{a:03d}.jpg").write_bytes(b"\xff\xd8\xff\xd9")

    for d in range(1, 29):
        (vault / "00_Journal" / f"2026-11-{d:02d}.md").write_text(
            f"---\nmood: focused\nenergy: 8\n---\n# Daily Note 2026-11-{d:02d}\n"
            f"- [x] Morning calisthenics\n- [ ] Deep work block {d}\n"
            f"Linked to [[Zettel 001]] and mentions Zettel 002 inline.\n",
            encoding="utf-8",
        )

    for m in range(40):
        (vault / "25_Media_Tracker" / "Movies" / f"Movie_{m:03d}.md").write_text(
            f"---\ntitle: Synthetic Film {m}\nposter: \"[[poster_{m % 80:03d}.jpg]]\"\nrating: 8.5\nyear: 2025\ntags: [movie, scifi]\n---\nGreat cinematography.\n",
            encoding="utf-8",
        )

    for p in range(20):
        (vault / "23_Places" / f"Place_{p:03d}.md").write_text(
            f"---\ntitle: Landmark {p}\nplace_type: cafe\ncoordinates: \"{10.0 + p * 0.2}, {105.7 + p * 0.2}\"\ntags: [place]\n---\nVisited spot {p}.\n",
            encoding="utf-8",
        )

    remaining = max(0, note_count - 28 - 40 - 20)
    for idx in range(remaining):
        next_link = f"[[Zettel {(idx + 1) % max(1, remaining):03d}]]"
        (vault / "03_Zettelkasten" / f"Zettel {idx:03d}.md").write_text(
            f"---\ntitle: Zettel {idx:03d}\ntype: permanent\ntags: [zettelkasten, topic-{idx % 12}]\n---\n"
            f"Core atomic concept {idx} connected to {next_link}.\n"
            f"- [ ] Follow-up literature check {idx}\n",
            encoding="utf-8",
        )


def bench_native_alis_nexus(tmp: Path) -> dict[str, float]:
    assert NEXUS_BIN.is_file(), f"Missing alis-nexus binary: {NEXUS_BIN}"
    vault = tmp / "vault"
    build_synthetic_vault(vault, note_count=480)
    cache_file = tmp / "nexus_vault_cache.json"
    ui_sidecar = tmp / "nexus_vault_cache.json.ui.json"

    t0 = time.perf_counter()
    cold_out = json.loads(
        subprocess.check_output(
            [str(NEXUS_BIN), "scan", "--vault", str(vault), "--date", "2026-11-18", "--cache-file", str(cache_file)],
            env=_headless_env(),
            text=True,
        )
    )
    cold_ms = (time.perf_counter() - t0) * 1000.0
    assert cold_out["ok"] is True
    assert cold_out["stats"]["noteCount"] == 480
    assert len(cold_out["collections"]["movies"]) == 40
    assert cold_out["collections"]["movies"][0]["posterUrl"].startswith("file://")
    assert cache_file.is_file() and ui_sidecar.is_file()

    # Verify cache schema compatibility: cache_file has _cachedEntries & _scanSignature; .ui.json omits them
    cache_dom = json.loads(cache_file.read_text(encoding="utf-8"))
    ui_dom = json.loads(ui_sidecar.read_text(encoding="utf-8"))
    assert "_cachedEntries" in cache_dom and "_scanSignature" in cache_dom
    assert "_cachedEntries" not in ui_dom and "_scanSignature" not in ui_dom
    assert "collections" in cache_dom and "collections" in ui_dom

    t0 = time.perf_counter()
    skip_out = json.loads(
        subprocess.check_output(
            [
                str(NEXUS_BIN),
                "scan",
                "--vault",
                str(vault),
                "--date",
                "2026-11-18",
                "--cache-file",
                str(cache_file),
                "--skip-if-unchanged",
            ],
            env=_headless_env(),
            text=True,
        )
    )
    skip_ms = (time.perf_counter() - t0) * 1000.0
    assert skip_out.get("unchanged") is True
    assert skip_out["stats"]["cacheHits"] == 480
    assert skip_out["stats"]["parsedNotes"] == 0

    t0 = time.perf_counter()
    cal_out = json.loads(
        subprocess.check_output(
            [str(NEXUS_BIN), "calendar", "--vault", str(vault), "--year", "2026", "--month", "11"],
            env=_headless_env(),
            text=True,
        )
    )
    cal_ms = (time.perf_counter() - t0) * 1000.0
    assert cal_out["ok"] is True and len(cal_out["cells"]) == 42
    nov_journals = [c for c in cal_out["cells"] if c["inMonth"] and c["hasJournal"]]
    assert len(nov_journals) == 28

    t0 = time.perf_counter()
    search_out = json.loads(
        subprocess.check_output(
            [str(NEXUS_BIN), "search", "--vault", str(vault), "--query", "cinematography"],
            env=_headless_env(),
            text=True,
        )
    )
    search_ms = (time.perf_counter() - t0) * 1000.0
    assert search_out["ok"] is True and len(search_out["results"]) == 40

    t0 = time.perf_counter()
    read_out = json.loads(
        subprocess.check_output(
            [str(NEXUS_BIN), "read", "--vault", str(vault), "--path", "03_Zettelkasten/Zettel 002.md"],
            env=_headless_env(),
            text=True,
        )
    )
    read_ms = (time.perf_counter() - t0) * 1000.0
    assert read_out["ok"] is True
    assert len(read_out["backlinks"]) >= 1
    assert len(read_out["unlinkedMentions"]) >= 1

    return {
        "scan_480_cold_ms": round(cold_ms, 2),
        "scan_480_skip_unchanged_ms": round(skip_ms, 2),
        "calendar_480_ms": round(cal_ms, 2),
        "search_480_ms": round(search_ms, 2),
        "read_backlinks_480_ms": round(read_ms, 2),
    }


def verify_qml_graph_globe_and_exercises_bridge(tmp: Path) -> dict[str, float]:
    host_root = resolve_host_root()
    state_dir = tmp / "state_home"
    ex_dir = state_dir / "quickshell" / "user" / "exercises-tracker"
    ex_dir.mkdir(parents=True, exist_ok=True)
    state_json = ex_dir / "state.json"
    state_json.write_text(
        json.dumps(
            {
                "schemaVersion": 1,
                "currentStreakDays": 5,
                "summary": {
                    "todayDate": "2026-11-18",
                    "todayRoutine": "push",
                    "todayTitle": "Upper Push Hypertrophy",
                    "todayTotalExercises": 4,
                    "todayCompletedExercises": 3,
                    "todayCompletionPct": 75,
                    "todayVolumeKg": 2840,
                    "currentStreakDays": 5,
                    "totalLoggedWorkouts": 14,
                    "totalBodyCheckins": 2,
                    "latestWeightKg": 72.4,
                    "latestBodyFatPct": 13.8,
                    "latestPhotoPath": "",
                },
                "days": {
                    "2026-11-18": {
                        "date": "2026-11-18",
                        "routine": "push",
                        "title": "Upper Push Hypertrophy",
                        "exercises": [
                            {"id": "e1", "name": "Weighted Dips", "sets": 4, "reps": "8", "weight": 20, "completed": True},
                        ],
                    }
                },
                "bodyCheckins": [
                    {
                        "id": "ck1",
                        "date": "2026-11-18",
                        "weightKg": 72.4,
                        "bodyFatPct": 13.8,
                        "routine": "push",
                        "note": "Post-push check-in",
                    }
                ],
            }
        ),
        encoding="utf-8",
    )

    qs_root = tmp / "qs_root"
    qs_root.mkdir(parents=True, exist_ok=True)
    for entry in ("modules", "services", "GlobalStates.qml", "qmldir", "assets", "scripts", "defaults", "translations"):
        if (host_root / entry).exists():
            (qs_root / entry).symlink_to(host_root / entry)
    (qs_root / "nexus_mod").symlink_to(ROOT / "modules" / "nexus")
    harness = qs_root / "shell.qml"
    harness.write_text(
        f"""
import QtQuick
import QtQuick.Window
import Quickshell
import qs
import qs.modules.common
import "./nexus_mod" as NexusMod

ShellRoot {{
    id: testRoot

    QtObject {{
        id: fakeNexus
        property bool isOpen: true
        function close() {{ fakeNexus.isOpen = false; }}
        property bool vaultConfigured: true
        property string activeView: "homepage"
        property string activeCollection: "exercises"
        property string collectionFilterQuery: ""
        property bool leftSidebarOpen: false
        property bool rightSidebarOpen: false
        property int leftSidebarWidth: 260
        property int rightSidebarWidth: 280
        property string currentPath: ""
        property var currentDoc: null
        property string editorMode: "hybrid"
        property string vimMode: "NORMAL"
        property bool commandPaletteOpen: false
        property string commandPaletteMode: ""
        property bool newNoteModalOpen: false
        signal focusFileFilterRequested()
        signal focusVaultSearchRequested()
        function shortcutFor(actionId) {{ return ""; }}
        function isApiBackedKind(kind) {{ return false; }}
        property var cardOrder: ["explorer", "localGraph", "calendar", "vaultGraph", "context"]
        property var collections: ({{
            places: [
                {{ title: "Can Tho", lat: 10.0452, lon: 105.7469, hasCoordinates: true }},
                {{ title: "Tokyo", lat: 35.6762, lon: 139.6503, hasCoordinates: true }}
            ],
            exercises: [
                {{ title: "Weighted Dips", relPath: "Exercises/Dips.md", muscleGroup: "Chest", equipment: "Parallel Bars" }}
            ]
        }})
        property var recentNotes: []
        property var dailySchedule: ({{ exerciseRows: [], cardioRows: [], scheduleRows: [] }})
    }}

    Window {{
        width: 1280
        height: 820
        visible: true

        NexusMod.NexusGraphCanvas {{
            id: graphBench
            width: 800
            height: 600
            visible: true
            graphData: {{
                const nodes = [];
                const edges = [];
                for (let i = 0; i < 300; ++i) {{
                    nodes.push({{
                        id: "n" + i,
                        title: "Node " + i,
                        relPath: "Note_" + i + ".md",
                        degree: (i % 7),
                        isHub: (i % 25 === 0),
                        colorHex: "#82c2cf",
                        x: 0.1 + ((i * 37) % 80) / 100.0,
                        y: 0.1 + ((i * 53) % 80) / 100.0
                    }});
                    if (i > 0)
                        edges.push({{ sourceIndex: i - 1, targetIndex: i }});
                }}
                return {{ nodes: nodes, edges: edges, groups: ["root"] }};
            }}
        }}

        NexusMod.NexusGlobeWidget {{
            id: globeBench
            width: 320
            height: 240
            visible: true
            active: true
            nexus: fakeNexus
            placesModel: fakeNexus.collections.places
        }}

        NexusMod.NexusWorkspace {{
            id: wsBench
            anchors.fill: parent
            nexus: fakeNexus
            exercisesTrackerStatePath: {json.dumps(str(state_json))}
        }}
    }}

    Timer {{
        interval: 180
        running: true
        repeat: false
        onTriggered: {{
            // 1. Hit-test benchmark on 300-node graph
            const sp = graphBench._screenPosForNode(120);
            const t0 = Date.now();
            let hit = -1;
            for (let k = 0; k < 400; ++k) {{
                hit = graphBench.findNodeAtScreen(sp.x, sp.y);
            }}
            const hitMs = Date.now() - t0;
            if (hit < 0) {{
                console.error("NEXUS_BENCH_FAIL:hit_test_missed");
                Qt.exit(1);
            }}

            // 2. Verify Globe painted with typed-array ring buffers and pauses on screen lock
            if (globeBench.paintCount < 1) {{
                console.error("NEXUS_BENCH_FAIL:globe_did_not_paint");
                Qt.exit(2);
            }}
            GlobalStates.screenLocked = true;
            if (wsBench.surfaceActive !== false) {{
                console.error("NEXUS_BENCH_FAIL:workspace_must_pause_when_locked");
                Qt.exit(3);
            }}
            GlobalStates.screenLocked = false;

            // 3. Verify Exercises Tracker <-> Nexus bridge
            const sum = wsBench.exercisesTrackerSummary;
            if (Number(sum?.todayCompletedExercises ?? 0) !== 3 || Number(sum?.todayCompletionPct ?? 0) !== 75) {{
                console.error("NEXUS_BENCH_FAIL:exercises_summary_mismatch:" + JSON.stringify(sum));
                Qt.exit(4);
            }}
            if (!wsBench.exercisesTrackerCardVisible) {{
                console.error("NEXUS_BENCH_FAIL:exercises_card_not_visible");
                Qt.exit(5);
            }}
            if ("nexusOpen" in GlobalStates)
                GlobalStates.nexusOpen = true;
            wsBench.openExercisesTracker("2026-11-18");
            if (GlobalStates.dashboardPageId !== "exercisesTracker"
                    || !GlobalStates.dashboardOpen
                    || ("nexusOpen" in GlobalStates && GlobalStates.nexusOpen !== false)
                    || fakeNexus.isOpen !== false
                    || String(Config.options?.dashboard?.lastPageId ?? "") !== "exercisesTracker") {{
                console.error("NEXUS_BENCH_FAIL:open_exercises_tracker_failed:"
                    + GlobalStates.dashboardPageId + ":" + GlobalStates.nexusOpen
                    + ":" + fakeNexus.isOpen + ":" + String(Config.options?.dashboard?.lastPageId ?? ""));
                Qt.exit(6);
            }}

            console.log("NEXUS_QML_METRICS:" + JSON.stringify({{
                hitTest400CallsMs: hitMs,
                globePaintCount: globeBench.paintCount,
                exercisesCompletionPct: sum.todayCompletionPct
            }}));
            Qt.quit();
        }}
    }}
}}
""",
        encoding="utf-8",
    )

    qs_bin = shutil.which("qs") or shutil.which("quickshell")
    assert qs_bin, "Missing qs/quickshell binary"
    proc = subprocess.run(
        [qs_bin, "-p", str(harness)],
        cwd=str(host_root),
        env=_headless_env(
            {
                "XDG_CONFIG_HOME": str(tmp / "config"),
                "XDG_STATE_HOME": str(state_dir),
                "XDG_CACHE_HOME": str(tmp / "cache"),
                "XDG_RUNTIME_DIR": str(tmp),
            }
        ),
        capture_output=True,
        text=True,
        timeout=25,
        check=False,
    )
    combined = (proc.stdout or "") + "\n" + (proc.stderr or "")
    assert proc.returncode == 0, f"Nexus QML harness failed:\n{combined}"
    metrics_line = next(
        (ln for ln in combined.splitlines() if "NEXUS_QML_METRICS:" in ln),
        "",
    )
    assert metrics_line, f"Missing NEXUS_QML_METRICS in:\n{combined}"
    return json.loads(metrics_line.split("NEXUS_QML_METRICS:", 1)[1].strip())


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="nexus-accel-bench-") as tmp_str:
        tmp = Path(tmp_str)
        native_stats = bench_native_alis_nexus(tmp)
        qml_stats = verify_qml_graph_globe_and_exercises_bridge(tmp)
        summary = {**native_stats, **qml_stats}
        print("NEXUS_ACCEL_BENCH_PASS " + json.dumps(summary, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
