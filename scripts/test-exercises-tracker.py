#!/usr/bin/env python3
"""Headless unit, security, legacy-migration, and QML contract tests for Exercises Tracker."""
from __future__ import annotations

import json
import os
from pathlib import Path
import re
import stat
import struct
import subprocess
import sys
import tempfile
import zlib

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "scripts/integrations/exercises_tracker.py"
ENGINE_JS = ROOT / "services/ExercisesTrackerEngine.js"
SERVICE_QML = ROOT / "services/ExercisesTracker.qml"
DASHBOARD_QML = ROOT / "modules/dashboard/DashboardExercisesTracker.qml"


def make_valid_png(width: int = 16, height: int = 16) -> bytes:
    def chunk(tag: bytes, data: bytes) -> bytes:
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    raw_rows = b"".join(b"\x00" + (b"\x20\x80\xe0" * width) for _ in range(height))
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", zlib.compress(raw_rows))
        + chunk(b"IEND", b"")
    )


def run_engine_unit_tests() -> None:
    node_test = r"""
const fs = require("fs");
const vm = require("vm");
const assert = require("assert");

const code = fs.readFileSync(process.argv[1], "utf8").replace(/^\.pragma\s+library\s*$/m, "");
const ctx = { console, Math, Date, JSON, Array, Object, String, Number, Boolean, RegExp };
vm.createContext(ctx);
vm.runInContext(code, ctx, { filename: "ExercisesTrackerEngine.js" });

// 1. Fresh state + Routine template + Exercise CRUD + Volume & Streak
let state = ctx.createEmptyState();
assert.strictEqual(state.schemaVersion, 1);
assert.strictEqual(state.bodyCheckins.length, 0);

const today = "2026-11-18";
const yesterday = "2026-11-17";

state = ctx.applyRoutineTemplate(state, today, "push", true);
let dayInfo = ctx.computeDaySummary(state, today);
assert.strictEqual(dayInfo.routine, "push");
assert.strictEqual(dayInfo.totalExercises, 4);
assert.strictEqual(dayInfo.completedExercises, 0);
assert.strictEqual(dayInfo.volumeKg, 0);

// Add custom exercise
state = ctx.addExercise(state, today, {
    name: "Weighted Dips",
    category: "chest",
    sets: 3,
    reps: "10",
    weight: 20,
    weightUnit: "kg",
    restSec: 90
});
dayInfo = ctx.computeDaySummary(state, today);
assert.strictEqual(dayInfo.totalExercises, 5);
const dips = dayInfo.exercises.find(e => e.name === "Weighted Dips");
assert.ok(dips);

// Step sets 1 -> 2 -> 3 auto-completes and computes partial/full volume
state = ctx.stepCompletedSets(state, today, dips.id, 2, "2026-11-18T18:10:00.000Z");
dayInfo = ctx.computeDaySummary(state, today);
assert.strictEqual(dayInfo.completedExercises, 0);
assert.strictEqual(dayInfo.volumeKg, 400); // 2 sets * 10 reps * 20 kg

state = ctx.stepCompletedSets(state, today, dips.id, 1, "2026-11-18T18:12:00.000Z");
dayInfo = ctx.computeDaySummary(state, today);
assert.strictEqual(dayInfo.completedExercises, 1);
assert.strictEqual(dayInfo.volumeKg, 600); // 3 sets * 10 reps * 20 kg

// Complete yesterday too -> 2-day streak
state = ctx.applyRoutineTemplate(state, yesterday, "pull", true);
const yExId = state.days[yesterday].exercises[0].id;
state = ctx.toggleExercise(state, yesterday, yExId, "2026-11-17T18:00:00.000Z");
const globalSum = ctx.computeGlobalSummary(state, today);
assert.strictEqual(globalSum.currentStreakDays, 2);
assert.strictEqual(globalSum.totalLoggedWorkouts, 2);

// 2. Body Tracker Check-ins & Delta Calculation
let res1 = ctx.addBodyCheckin(state, {
    date: yesterday,
    createdAt: "2026-11-17T19:00:00.000Z",
    photoPath: "/tmp/p1.png",
    photoRel: "photos/p1.png",
    weightKg: 72.0,
    bodyFatPct: 15.2,
    note: "Baseline"
});
state = res1.state;
let res2 = ctx.addBodyCheckin(state, {
    date: today,
    createdAt: "2026-11-18T19:00:00.000Z",
    photoPath: "/tmp/p2.png",
    photoRel: "photos/p2.png",
    weightKg: 71.6,
    bodyFatPct: 14.9,
    note: "Post push pump"
});
state = res2.state;
const sumAfterBc = ctx.computeGlobalSummary(state, today);
assert.strictEqual(sumAfterBc.totalBodyCheckins, 2);
assert.strictEqual(sumAfterBc.latestWeightKg, 71.6);
assert.strictEqual(sumAfterBc.latestBodyFatPct, 14.9);
assert.strictEqual(sumAfterBc.latestPhotoPath, "/tmp/p2.png");

// 3. Weekly Planner Two-Way Parsing & Payload Generation
const plannerEvent = {
    id: 77,
    title: "[Workout] Legs Hypertrophy",
    description: "- Barbell Squat — 4 × 8 · 100 kg\n- Walking Lunges: 3x12 @ 20kg\n- Zone 2 Bike — 15 min\n#workout",
    startDate: "2026-11-19T17:30:00.000Z",
    endDate: "2026-11-19T18:30:00.000Z",
    category: "reminder",
    allDay: false
};
assert.strictEqual(ctx.isWorkoutPlannerEvent(plannerEvent), true);
assert.strictEqual(ctx.isWorkoutPlannerEvent({ title: "Team Standup", category: "meeting" }), false);

const parsed = ctx.parsePlannerWorkoutEvent(plannerEvent);
assert.ok(parsed);
assert.strictEqual(parsed.eventId, 77);
assert.strictEqual(parsed.routine, "legs");
assert.strictEqual(parsed.exercises.length, 3);
assert.strictEqual(parsed.exercises[0].name, "Barbell Squat");
assert.strictEqual(parsed.exercises[0].sets, 4);
assert.strictEqual(parsed.exercises[0].weight, 100);
assert.strictEqual(parsed.exercises[2].durationSec, 900);

state = ctx.importPlannerWorkoutIntoDay(state, "2026-11-19", parsed);
// Repeated import is idempotent (no duplicate exercises)
state = ctx.importPlannerWorkoutIntoDay(state, "2026-11-19", parsed);
const importedDay = ctx.computeDaySummary(state, "2026-11-19");
assert.strictEqual(importedDay.totalExercises, 3);
assert.strictEqual(importedDay.plannerEventId, 77);

const outPayload = ctx.buildPlannerEventPayload(state, today);
assert.ok(outPayload.title.startsWith("[Workout] "));
assert.ok(outPayload.description.includes("Weighted Dips"));
assert.ok(outPayload.description.includes("#workout"));

// 4. Nexus Markdown Export
const md = ctx.exportWorkoutMarkdown(state, today);
assert.ok(md.includes("# Push Strength (2026-11-18)"));
assert.ok(md.includes("#workout #exercises-tracker"));
assert.ok(md.includes("Weighted Dips"));
assert.ok(md.includes("71.6 kg"));

// 5. Legacy / Pre-Existing User Data Parity & Idempotent Migration
const legacyRaw = {
    customUserKey: { keepMe: true, version: "0.1-alpha" },
    preferences: { weightUnit: "lb", defaultRestSeconds: 120, unknownPref: "preserved" },
    days: {
        "2026-11-10": {
            customDayField: "untouched",
            exercises: [
                { id: "legacy-1", title: "Goblet Squat", muscleGroup: "quadriceps", sets: 4, reps: 12, weight: 50, completed: true, extraExByte: 42 },
                { id: "legacy-1", title: "Plank", muscleGroup: "abs", durationMin: 2 }
            ]
        }
    },
    bodyCheckins: [
        { id: "old-bc", date: "2026-11-10", weightKg: 73.2, customBcMeta: "safe" }
    ]
};
const migrated1 = JSON.parse(ctx.serializeState(legacyRaw, today));
const migrated2 = JSON.parse(ctx.serializeState(migrated1, today));
assert.deepStrictEqual(migrated1.customUserKey, { keepMe: true, version: "0.1-alpha" });
assert.strictEqual(migrated1.preferences.unknownPref, "preserved");
assert.strictEqual(migrated1.days["2026-11-10"].customDayField, "untouched");
assert.strictEqual(migrated1.days["2026-11-10"].exercises.length, 2);
assert.strictEqual(migrated1.days["2026-11-10"].exercises[0].category, "legs");
assert.strictEqual(migrated1.days["2026-11-10"].exercises[0].extraExByte, 42);
assert.strictEqual(migrated1.days["2026-11-10"].exercises[1].durationSec, 120);
assert.notStrictEqual(migrated1.days["2026-11-10"].exercises[0].id, migrated1.days["2026-11-10"].exercises[1].id);
assert.strictEqual(migrated1.bodyCheckins[0].customBcMeta, "safe");
assert.deepStrictEqual(migrated1.days, migrated2.days);
assert.deepStrictEqual(migrated1.bodyCheckins, migrated2.bodyCheckins);
"""
    res = subprocess.run(
        ["node", "-e", node_test, str(ENGINE_JS)],
        capture_output=True,
        text=True,
        check=False,
    )
    if res.returncode != 0:
        raise AssertionError(f"Engine unit tests failed:\n{res.stderr}\n{res.stdout}")


def run_photo_helper_security_tests() -> None:
    with tempfile.TemporaryDirectory(prefix="alis-et-photo-") as tmp:
        base = Path(tmp)
        photos_dir = base / "state/exercises-tracker/photos"
        src_img = base / "post_workout.png"
        png_bytes = make_valid_png(24, 24)
        src_img.write_bytes(png_bytes)

        # 1. Valid user-selected image copies atomically with 0600 permissions
        proc = subprocess.run(
            [
                sys.executable,
                str(HELPER),
                "import-photo",
                "--source",
                f"file://{src_img}",
                "--photos-dir",
                str(photos_dir),
                "--checkin-id",
                "bc-101",
                "--date",
                "2026-11-18",
            ],
            capture_output=True,
            text=True,
            check=True,
        )
        out = json.loads(proc.stdout)
        assert out["ok"] is True
        dest = Path(out["photoPath"])
        assert dest.is_file() and not dest.is_symlink()
        assert dest.read_bytes() == png_bytes
        assert stat.S_IMODE(dest.stat().st_mode) == 0o600
        assert out["photoRel"] == "photos/2026-11-18_bc-101.png"

        # 2. Reject symlinked source file
        symlink_src = base / "linked.png"
        symlink_src.symlink_to(src_img)
        bad_sym = subprocess.run(
            [
                sys.executable,
                str(HELPER),
                "import-photo",
                "--source",
                str(symlink_src),
                "--photos-dir",
                str(photos_dir),
                "--checkin-id",
                "bc-102",
                "--date",
                "2026-11-18",
            ],
            capture_output=True,
            text=True,
            check=False,
        )
        assert bad_sym.returncode != 0 and json.loads(bad_sym.stdout)["ok"] is False

        # 3. Reject non-image disguised with .png extension
        fake_img = base / "not_an_image.png"
        fake_img.write_text("#!/bin/sh\necho nope\n", encoding="utf-8")
        bad_magic = subprocess.run(
            [
                sys.executable,
                str(HELPER),
                "import-photo",
                "--source",
                str(fake_img),
                "--photos-dir",
                str(photos_dir),
                "--checkin-id",
                "bc-103",
                "--date",
                "2026-11-18",
            ],
            capture_output=True,
            text=True,
            check=False,
        )
        assert bad_magic.returncode != 0 and json.loads(bad_magic.stdout)["ok"] is False

        # 4. Reject deleting any file outside photos_dir
        outside_file = base / "keep_me.png"
        outside_file.write_bytes(png_bytes)
        bad_del = subprocess.run(
            [
                sys.executable,
                str(HELPER),
                "delete-photo",
                "--photo-path",
                str(outside_file),
                "--photos-dir",
                str(photos_dir),
            ],
            capture_output=True,
            text=True,
            check=False,
        )
        assert bad_del.returncode != 0 and outside_file.exists()

        # 5. Safe delete inside photos_dir succeeds
        ok_del = subprocess.run(
            [
                sys.executable,
                str(HELPER),
                "delete-photo",
                "--photo-path",
                str(dest),
                "--photos-dir",
                str(photos_dir),
            ],
            capture_output=True,
            text=True,
            check=True,
        )
        assert json.loads(ok_del.stdout) == {"ok": True, "deleted": True}
        assert not dest.exists()


def run_qml_memory_and_timer_contract_checks() -> None:
    dash_qml = DASHBOARD_QML.read_text(encoding="utf-8")
    svc_qml = SERVICE_QML.read_text(encoding="utf-8")

    # Every Image in DashboardExercisesTracker.qml must be async, uncached, and sourceSize-bounded
    image_blocks = []
    for match in re.finditer(r"\bImage\s*\{", dash_qml):
        depth = 1
        idx = match.end()
        while idx < len(dash_qml) and depth > 0:
            if dash_qml[idx] == "{":
                depth += 1
            elif dash_qml[idx] == "}":
                depth -= 1
            idx += 1
        image_blocks.append(dash_qml[match.start() : idx])

    assert len(image_blocks) >= 4, f"Expected >= 4 Image blocks, found {len(image_blocks)}"
    for i, blk in enumerate(image_blocks):
        assert "asynchronous: true" in blk, f"Image #{i + 1} missing asynchronous: true"
        assert "cache: false" in blk, f"Image #{i + 1} missing cache: false"
        size_m = re.search(r"sourceSize\s*:\s*Qt\.size\(\s*(\d+)\s*,\s*(\d+)\s*\)", blk)
        assert size_m, f"Image #{i + 1} missing bounded sourceSize: Qt.size(w, h)"
        w, h = int(size_m.group(1)), int(size_m.group(2))
        assert 0 < w <= 1024 and 0 < h <= 1024, f"Image #{i + 1} sourceSize ({w}x{h}) exceeds memory cap"

    # Rest timer must strictly require presentationActive so hidden tabs cause zero wakeups
    assert (
        "running: root.restRunning && root.presentationActive && root.restRemainingSec > 0"
        in svc_qml
    ), "Rest timer must stop when presentationActive is false"


def main() -> None:
    env_check = os.environ.get("QT_QPA_PLATFORM", "offscreen")
    _ = env_check
    run_engine_unit_tests()
    run_photo_helper_security_tests()
    run_qml_memory_and_timer_contract_checks()
    print(
        "EXERCISES_TRACKER_UNIT_PASS engine CRUD/streak/volume, legacy migration parity, "
        "Weekly Planner 2-way sync, Nexus export, safe photo import/delete, bounded Image sourceSize & zero-idle timer"
    )


if __name__ == "__main__":
    main()
