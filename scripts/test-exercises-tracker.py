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
HELPER = ROOT / "plugins/exercises_tracker/scripts/integrations/exercises_tracker.py"
ENGINE_JS = ROOT / "plugins/exercises_tracker/services/ExercisesTrackerEngine.js"
SERVICE_QML = ROOT / "plugins/exercises_tracker/services/ExercisesTracker.qml"
DASHBOARD_QML = ROOT / "plugins/exercises_tracker/modules/dashboard/DashboardExercisesTracker.qml"


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

// 2b. PhotoVaultRel + schedule shift + reminderMinutes & unique #workout date tag
let shifted = ctx.updateDayMetadata(state, today, { scheduledStart: "19:30" });
assert.ok(shifted.days[today].scheduledEnd > "19:30", "scheduledEnd must advance past scheduledStart");
shifted = ctx.updatePreferences(shifted, { workoutReminderMinutes: 30 });
const shiftedPayload = ctx.buildPlannerEventPayload(shifted, today);
assert.strictEqual(shiftedPayload.reminderMinutes, 30);
assert.ok(shiftedPayload.description.includes("#workout · " + today), "payload must tag date to prevent multi-day collapse");
const offRemState = ctx.updatePreferences(shifted, { workoutReminderMinutes: 0 });
assert.strictEqual(ctx.buildPlannerEventPayload(offRemState, today).reminderMinutes, 0);
const vaultBcState = ctx.addBodyCheckin(state, {
    date: today,
    photoPath: "/tmp/vault/90_System/95_Media_Assets/Exercise/Body_Tracker/2026-11-18_bc-9.png",
    photoRel: "90_System/95_Media_Assets/Exercise/Body_Tracker/2026-11-18_bc-9.png",
    photoVaultRel: "90_System/95_Media_Assets/Exercise/Body_Tracker/2026-11-18_bc-9.png",
    weightKg: 71.5
}).state;
assert.ok(ctx.exportWorkoutMarkdown(vaultBcState, today).includes("![[90_System/95_Media_Assets/Exercise/Body_Tracker/2026-11-18_bc-9.png]]"));

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

// 6. Preferences & Weekly Split Customization
let customState = ctx.updatePreferences(migrated1, {
    weightUnit: "lb",
    defaultSets: 5,
    defaultRestSeconds: 150,
    autoStartRestOnSet: true,
    showInNexus: false,
    workoutReminderMinutes: 30,
    bodyPhotosStorageMode: "custom",
    bodyPhotosCustomDir: "90_System/CustomBody",
    defaultGalleryMode: "compare",
    showBodyMetrics: false
});
assert.strictEqual(customState.preferences.weightUnit, "lb");
assert.strictEqual(customState.preferences.defaultSets, 5);
assert.strictEqual(customState.preferences.defaultRestSeconds, 150);
assert.strictEqual(customState.preferences.autoStartRestOnSet, true);
assert.strictEqual(customState.preferences.showInNexus, false);
assert.strictEqual(customState.preferences.workoutReminderMinutes, 30);
assert.strictEqual(customState.preferences.bodyPhotosStorageMode, "custom");
assert.strictEqual(customState.preferences.bodyPhotosCustomDir, "90_System/CustomBody");
assert.strictEqual(customState.preferences.defaultGalleryMode, "compare");
assert.strictEqual(customState.preferences.showBodyMetrics, false);
assert.strictEqual(customState.preferences.unknownPref, "preserved");

customState = ctx.applyWeeklySplitPreset(customState, "upper_lower");
assert.strictEqual(customState.weeklyTemplates["1"], "push");
assert.strictEqual(customState.weeklyTemplates["2"], "legs");
assert.strictEqual(customState.weeklyTemplates["3"], "rest");
assert.strictEqual(customState.weeklyTemplates["4"], "pull");
customState = ctx.updateWeeklyTemplate(customState, 3, "cardio");
assert.strictEqual(customState.weeklyTemplates["3"], "cardio");

// 7. Nexus Catalog Match, Search Ranking, Unsynced Planner Fallback & Idempotent Reconcile
const nexusLib = [
    {
        title: "Barbell Bench Press",
        relPath: "20_Personal_Life/33_Bodybuilding/Gym_n_Calisthenics_Exercises/Barbell Bench Press.md",
        muscleGroup: "chest",
        secondaryMuscles: "triceps, shoulders",
        equipment: "barbell",
        level: "intermediate",
        posterUrl: "file:///tmp/bench.png"
    },
    {
        title: "Push-Ups",
        relPath: "20_Personal_Life/33_Bodybuilding/Gym_n_Calisthenics_Exercises/Push-Ups.md",
        muscleGroup: "chest",
        equipment: "body only"
    }
];
const matchedPush = ctx.matchNexusExercise({ name: "Push ups" }, nexusLib);
assert.ok(matchedPush && matchedPush.title === "Push-Ups");

const searchBench = ctx.searchExercisesCatalog("bench", nexusLib, state, 10);
assert.ok(searchBench.length >= 1 && searchBench[0].title === "Barbell Bench Press" && searchBench[0].source === "nexus");

const fallbackEvents = ctx.buildUnsyncedPlannerEvents(state, []);
assert.ok(fallbackEvents.some(ev => ev.sourceKind === "exerciseWorkout" && ev.workoutDate === today));

const recon1 = ctx.reconcilePlannerWorkoutEvent(state, "2026-11-20", {
    eventId: 88,
    title: "Friday Upper",
    routine: "push",
    startHm: "18:30",
    endHm: "19:30",
    allDay: false,
    exercises: [{ name: "Barbell Bench Press", sets: 4, reps: "8", weight: 70, completed: true, hasCheckbox: true }]
});
assert.strictEqual(recon1.changed, true);
const recon2 = ctx.reconcilePlannerWorkoutEvent(recon1.state, "2026-11-20", {
    eventId: 88,
    title: "Friday Upper",
    routine: "push",
    startHm: "18:30",
    endHm: "19:30",
    allDay: false,
    exercises: [{ name: "Barbell Bench Press", sets: 4, reps: "8", weight: 70, completed: true, hasCheckbox: true }]
});
assert.strictEqual(recon2.changed, false);
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

        # 6. Read-only Nexus Exercise Library scan & detail parsing + path traversal guard
        vault = base / "vault"
        ex_dir = vault / "20_Personal_Life/33_Bodybuilding/Gym_n_Calisthenics_Exercises"
        att_dir = vault / "90_System/95_Attachments"
        ex_dir.mkdir(parents=True)
        att_dir.mkdir(parents=True)
        (att_dir / "bench.png").write_bytes(png_bytes)
        (ex_dir / "Barbell Bench Press.md").write_text(
            "---\n"
            "id: Barbell_Bench_Press\n"
            "name: Barbell Bench Press\n"
            "level: intermediate\n"
            "force: push\n"
            "mechanic: compound\n"
            "equipment: barbell\n"
            "primaryMuscles:\n"
            "  - chest\n"
            "secondaryMuscles:\n"
            "  - triceps\n"
            "  - shoulders\n"
            "poster: \"[[bench.png]]\"\n"
            "---\n\n"
            "## How to Perform\n"
            "1. Lie flat on a bench with eyes under the bar.\n"
            "2. Lower bar to mid-chest under control and press up.\n\n"
            "## Tips\n"
            "- Keep shoulder blades retracted.\n",
            encoding="utf-8",
        )
        scan_proc = subprocess.run(
            [sys.executable, str(HELPER), "scan-exercises", "--vault", str(vault)],
            capture_output=True, text=True, check=True,
        )
        scan_payload = json.loads(scan_proc.stdout)
        assert scan_payload["ok"] is True and len(scan_payload["exercises"]) == 1
        assert scan_payload["exercises"][0]["title"] == "Barbell Bench Press"

        det_proc = subprocess.run(
            [
                sys.executable, str(HELPER), "exercise-detail",
                "--vault", str(vault),
                "--rel-path", "20_Personal_Life/33_Bodybuilding/Gym_n_Calisthenics_Exercises/Barbell Bench Press.md",
            ],
            capture_output=True, text=True, check=True,
        )
        det_payload = json.loads(det_proc.stdout)
        assert det_payload["ok"] is True
        assert det_payload["primaryMuscles"] == ["chest"]
        assert det_payload["secondaryMuscles"] == ["triceps", "shoulders"]
        assert len(det_payload["steps"]) == 2
        assert len(det_payload["tips"]) == 1
        assert det_payload["previewUrl"].startswith("file://")

        bad_trav = subprocess.run(
            [sys.executable, str(HELPER), "exercise-detail", "--vault", str(vault), "--rel-path", "../outside.md"],
            capture_output=True, text=True, check=False,
        )
        assert bad_trav.returncode != 0 and json.loads(bad_trav.stdout)["ok"] is False

        secret_md = base / "secret.md"
        secret_md.write_text("# Secret\n", encoding="utf-8")
        escape_link = ex_dir / "Escape.md"
        escape_link.symlink_to(secret_md)
        bad_sym_note = subprocess.run(
            [
                sys.executable, str(HELPER), "exercise-detail",
                "--vault", str(vault),
                "--rel-path", "20_Personal_Life/33_Bodybuilding/Gym_n_Calisthenics_Exercises/Escape.md",
            ],
            capture_output=True, text=True, check=False,
        )
        assert bad_sym_note.returncode != 0 and json.loads(bad_sym_note.stdout)["ok"] is False

        # 7. Smart Nexus Body Tracker photos dir resolution & in-vault photo import/delete
        vault_media = base / "vault_media"
        (vault_media / "90_System/95_Media_Assets/Exercise").mkdir(parents=True)
        res_ex = json.loads(subprocess.check_output([
            sys.executable, str(HELPER), "resolve-photos-dir",
            "--photos-dir", str(photos_dir), "--vault", str(vault_media), "--storage-mode", "auto",
        ], text=True))
        assert res_ex["ok"] and res_ex["source"] == "nexus-auto"
        assert res_ex["vaultRelDir"] == "90_System/95_Media_Assets/Exercise/Body_Tracker"
        assert res_ex["photosDir"] == str(vault_media / "90_System/95_Media_Assets/Exercise/Body_Tracker")
        assert not (vault_media / "90_System/95_Media_Assets/Exercise/Body_Tracker").exists(), "resolve-photos-dir must be read-only"

        vault_obs = base / "vault_obs"
        (vault_obs / ".obsidian").mkdir(parents=True)
        (vault_obs / "90_System/CustomAtt").mkdir(parents=True)
        (vault_obs / ".obsidian/app.json").write_text(json.dumps({"attachmentFolderPath": "90_System/CustomAtt"}), encoding="utf-8")
        res_obs = json.loads(subprocess.check_output([
            sys.executable, str(HELPER), "resolve-photos-dir",
            "--photos-dir", str(photos_dir), "--vault", str(vault_obs), "--storage-mode", "auto",
        ], text=True))
        assert res_obs["ok"] and res_obs["vaultRelDir"] == "90_System/CustomAtt/Body_Tracker"

        vault_plain = base / "vault_plain"
        vault_plain.mkdir(parents=True)
        res_plain = json.loads(subprocess.check_output([
            sys.executable, str(HELPER), "resolve-photos-dir",
            "--photos-dir", str(photos_dir), "--vault", str(vault_plain), "--storage-mode", "auto",
        ], text=True))
        assert res_plain["ok"] and res_plain["vaultRelDir"] == "Attachments/Body_Tracker"

        res_local = json.loads(subprocess.check_output([
            sys.executable, str(HELPER), "resolve-photos-dir",
            "--photos-dir", str(photos_dir), "--vault", "", "--storage-mode", "auto",
        ], text=True))
        assert res_local["ok"] and res_local["source"] == "local-fallback" and res_local["inVault"] is False

        custom_rel = json.loads(subprocess.check_output([
            sys.executable, str(HELPER), "resolve-photos-dir",
            "--photos-dir", str(photos_dir), "--vault", str(vault_media),
            "--storage-mode", "custom", "--custom-dir", "90_System/MyBodyPhotos",
        ], text=True))
        assert custom_rel["ok"] and custom_rel["source"] == "custom" and custom_rel["inVault"] is True
        assert custom_rel["vaultRelDir"] == "90_System/MyBodyPhotos"

        bad_custom = subprocess.run([
            sys.executable, str(HELPER), "resolve-photos-dir",
            "--photos-dir", str(photos_dir), "--vault", str(vault_media),
            "--storage-mode", "custom", "--custom-dir", "../../escape",
        ], capture_output=True, text=True, check=False)
        assert bad_custom.returncode != 0 and json.loads(bad_custom.stdout)["ok"] is False

        vault_imp = json.loads(subprocess.check_output([
            sys.executable, str(HELPER), "import-photo",
            "--source", str(src_img), "--photos-dir", str(photos_dir),
            "--checkin-id", "bc-202", "--date", "2026-11-24",
            "--vault", str(vault_media), "--storage-mode", "auto",
        ], text=True))
        assert vault_imp["ok"] is True and vault_imp["storageSource"] == "nexus-auto"
        assert vault_imp["photoVaultRel"] == "90_System/95_Media_Assets/Exercise/Body_Tracker/2026-11-24_bc-202.png"
        imp_file = Path(vault_imp["photoPath"])
        assert imp_file.is_file() and stat.S_IMODE(imp_file.stat().st_mode) == 0o600
        del_allowed = json.loads(subprocess.check_output([
            sys.executable, str(HELPER), "delete-photo",
            "--photo-path", str(imp_file), "--photos-dir", str(photos_dir),
            "--allowed-dir", str(vault_media / "90_System/95_Media_Assets/Exercise/Body_Tracker"),
        ], text=True))
        assert del_allowed == {"ok": True, "deleted": True} and not imp_file.exists()


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

    # Rest timer must delegate to TimerService (Timer Edgebar) with zero private restTickTimer
    assert "id: restTickTimer" not in svc_qml, "Exercise Tracker must not run an isolated restTickTimer"
    for contract in ("startCountdown(", "toggleCountdown(", "stopCountdown(", "countdownSecondsLeft"):
        assert contract in svc_qml, f"Missing TimerService sync contract: {contract}"

    # Tab-jump buttons must stay removed per design contract
    for forbidden_btn in (
        "exercisesOpenPlannerButton",
        "exercisesOpenNexusButton",
        "exercisesSyncPlannerButton",
        "exercisesExportNexusButton",
        "exercisesPlannerSyncBanner",
    ):
        assert forbidden_btn not in dash_qml, f"Removed button/banner reappeared: {forbidden_btn}"


def main() -> None:
    env_check = os.environ.get("QT_QPA_PLATFORM", "offscreen")
    _ = env_check
    run_engine_unit_tests()
    run_photo_helper_security_tests()
    run_qml_memory_and_timer_contract_checks()
    print(
        "EXERCISES_TRACKER_UNIT_PASS engine CRUD/streak/volume/search/planner-reconcile, legacy migration parity, "
        "TimerService Edgebar sync, Nexus exercise-detail/scan security, bounded Image sourceSize & removed tab jumps"
    )


if __name__ == "__main__":
    main()
