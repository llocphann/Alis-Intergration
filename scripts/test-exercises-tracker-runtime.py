#!/usr/bin/env python3
"""Headless Quickshell offscreen runtime verification for Dashboard Exercises Tracker.

Verifies end-to-end in real QML/Quickshell offscreen runtime (zero visible windows,
zero focus stealing):
1. Optional Alis-Intergration session mounting into Alis (`AlisSession` -> `ExercisesTracker`
   -> `DashboardExercisesTracker` + `DashboardHeader` + `DockConfig` / `IntegrationsConfig`).
2. Daily workout template seeding, custom exercise CRUD, set stepping, volume & completion KPIs.
3. Rest timer countdown active when visible and deterministic auto-pause when tab switches/hides.
4. Post-workout Body Tracker photo import (`FileDialog`/path), bounded `sourceSize` async thumbnail,
   Timeline vs Compare view, Lightbox `Escape` handling, and safe check-in deletion.
5. Two-way Weekly Planner (`Events` & `DashboardWeeklyPlanner`) workout sync and navigation jump.
6. Durable persistence, toggle persistence (`prefs.json`), & legacy data reload across full restart.
"""
from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile
import time
import zlib

from integration_test_host import resolve_host_root

ROOT = Path(__file__).resolve().parents[1]
HOST = resolve_host_root(ROOT)
sys.path.insert(0, str(HOST / "scripts"))
from native_test_session import run_qs  # noqa: E402

spec = importlib.util.spec_from_file_location("installer", ROOT / "scripts/install.py")
installer = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(installer)


def make_png(w: int = 32, h: int = 32, rgb: tuple[int, int, int] = (40, 160, 220)) -> bytes:
    def chunk(tag: bytes, data: bytes) -> bytes:
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    pixel = bytes(rgb)
    raw = b"".join(b"\x00" + (pixel * w) for _ in range(h))
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", zlib.compress(raw))
        + chunk(b"IEND", b"")
    )


FULL_DASHBOARD_SHELL_QML = r"""
pragma ComponentBehavior: Bound
import QtQuick
import QtTest
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.dashboard

ShellRoot {
    id: root
    Component.onCompleted: Quickshell.watchFiles = false

    QtObject {
        id: fakeMusic
        property var libraryTracks: []
        property var activeQueue: []
        property var playlists: []
        property var localLyricsLines: []
        property var mprisPlayer: null
        property bool available: false
        property string error: ""
    }

    Window {
        id: win
        visible: true
        width: 1280
        height: 840
        color: "#11161d"

        DashboardContent {
            id: dashboard
            anchors.fill: parent
            embeddedSurface: true
            presentationActive: true
            musicBackend: fakeMusic
        }
    }

    TestCase {
        id: test
        when: false
        optional: true
        property int checks: 0
        function check(cond, msg) {
            checks++
            if (!cond)
                throw new Error(msg)
        }

        function run() {
            try {
                tryCompare(Config, "ready", true, 5000)
                tryCompare(Events, "ready", true, 5000)
                tryCompare(AlisIntergration, "available", true, 5000)
                tryVerify(() => AlisIntergration.exercisesTrackerEnabled === true, 4000)
                tryVerify(() => AlisIntergration.exercisesTracker !== null, 4000)
                const svc = AlisIntergration.exercisesTracker
                tryCompare(svc, "ready", true, 4000)

                if (Quickshell.env("ET_PHASE") === "restart") {
                    check(svc.dayPlan.totalExercises >= 5,
                        "Persisted exercises did not reload after restart: " + svc.dayPlan.totalExercises)
                    check(svc.dayPlan.completedExercises >= 2,
                        "Completed exercise state did not survive restart")
                    check(svc.bodyCheckins.length === 1,
                        "Body check-in count mismatch after restart: " + svc.bodyCheckins.length)
                    check(svc.bodyCheckins[0].weightKg === 71.4 && svc.bodyCheckins[0].hasPhoto === true,
                        "Persisted body check-in metrics/photo missing after restart")
                    check(svc.state.legacyFixtureMarker === "keep-intact",
                        "Legacy unknown top-level field was dropped during save/reload")
                    console.info("ET_RUNTIME_RESTART_PASS", checks)
                    Qt.quit()
                    return
                }

                Config.setNestedValues({
                    "performance.reduceAnimations": true,
                    "dashboard.music.enable": false
                })

                tryVerify(() => dashboard.pageIds.includes("exercisesTracker"), 3000)
                dashboard.selectPage("exercisesTracker")
                tryCompare(dashboard, "currentPageId", "exercisesTracker", 3000)

                let view = null
                tryVerify(() => {
                    view = findChild(dashboard, "dashboardExercisesTracker")
                    return view !== null && view.visible
                }, 4000)

                svc.applyTemplate("push", true)
                check(svc.dayPlan.totalExercises === 4, "Push template should load 4 exercises")

                const nameField = findChild(view, "exerciseNameField")
                const setsField = findChild(view, "exerciseSetsField")
                const repsField = findChild(view, "exerciseRepsField")
                const weightField = findChild(view, "exerciseWeightField")
                const submitBtn = findChild(view, "exerciseSubmitButton")
                check(nameField && setsField && repsField && weightField && submitBtn, "Composer controls missing")

                nameField.text = "Weighted Dips"
                setsField.text = "3"
                repsField.text = "10"
                weightField.text = "20"
                submitBtn.clicked()

                check(svc.dayPlan.totalExercises === 5, "Adding custom exercise failed")
                const firstId = svc.dayPlan.exercises[0].id
                const dipsEx = svc.dayPlan.exercises.find(e => e.name === "Weighted Dips")
                check(!!dipsEx, "Weighted Dips missing from dayPlan")

                svc.toggleExercise(firstId)
                svc.stepExerciseSets(dipsEx.id, 3)
                check(svc.dayPlan.completedExercises === 2, "Expected 2 completed exercises")
                check(svc.dayPlan.volumeKg > 600, "Expected positive training volume")

                svc.startRestTimer(75, "Weighted Dips")
                check(svc.restRunning === true && svc.restRemainingSec === 75, "Rest timer did not start")
                dashboard.selectPage("dashboard")
                tryCompare(dashboard, "currentPageId", "dashboard", 2000)
                tryVerify(() => svc.restRunning === false, 2000)
                dashboard.selectPage("exercisesTracker")
                tryCompare(dashboard, "currentPageId", "exercisesTracker", 2000)
                svc.stopRestTimer()

                const photo1 = Quickshell.env("ET_PHOTO_1")
                const photo2 = Quickshell.env("ET_PHOTO_2")
                check(svc.addBodyCheckin(photo1, 72.0, 15.1, "Baseline photo"), "First photo import rejected")
                tryVerify(() => !svc.photoImportBusy && svc.bodyCheckins.length === 1, 4000)
                const bc1Id = svc.bodyCheckins[0].id

                check(svc.addBodyCheckin(photo2, 71.4, 14.7, "Post-push check-in"), "Second photo import rejected")
                tryVerify(() => !svc.photoImportBusy && svc.bodyCheckins.length === 2, 4000)
                const bc2 = svc.bodyCheckins[0]
                check(bc2.hasWeightDelta && bc2.weightDeltaKg === -0.6,
                    "Expected -0.6 kg delta, got " + bc2.weightDeltaKg)

                wait(50)
                const thumb = findChild(view, "bodyCheckinThumbnail_" + bc2.id)
                check(thumb !== null, "Body check-in thumbnail Image not mounted")
                check(thumb.asynchronous === true && thumb.cache === false
                    && thumb.sourceSize.width <= 280 && thumb.sourceSize.height <= 280,
                    "Thumbnail Image violated async/bounded sourceSize contract")

                const compareBtn = findChild(view, "bodyViewCompareButton")
                compareBtn.clicked()
                check(view.bodyGalleryMode === "compare", "Compare mode did not activate")
                findChild(view, "bodyViewTimelineButton").clicked()

                view.previewCheckin = bc2
                const modal = findChild(view, "bodyPhotoPreviewModal")
                check(modal !== null && modal.visible === true, "Photo preview modal did not open")
                check(dashboard.handleEscape() === true && view.previewCheckin === null,
                    "DashboardContent.handleEscape() did not dismiss photo preview modal")

                check(svc.deleteBodyCheckin(bc1Id) === true && svc.bodyCheckins.length === 1,
                    "Deleting body check-in failed")

                const syncedEventId = svc.syncDayToWeeklyPlanner(svc.selectedDate)
                check(syncedEventId > 0, "syncDayToWeeklyPlanner did not create an Events record")
                check(Events.list.some(ev => Number(ev.id) === syncedEventId && String(ev.title).indexOf("[Workout]") === 0),
                    "Synced workout event missing from Events.list")

                const origDate = svc.selectedDate
                svc.stepDate(1)
                const tomorrowStr = svc.selectedDate
                const tParts = tomorrowStr.split("-")
                const startDt = new Date(Number(tParts[0]), Number(tParts[1]) - 1, Number(tParts[2]), 17, 0, 0)
                const endDt = new Date(Number(tParts[0]), Number(tParts[1]) - 1, Number(tParts[2]), 18, 0, 0)
                Events.addEvent(
                    "[Workout] Legs Hypertrophy",
                    "- Hack Squat — 4 × 10 · 100 kg\n- Seated Leg Curl — 3 × 12 · 45 kg\n#workout",
                    startDt.toISOString(),
                    "reminder",
                    "normal",
                    15,
                    "none",
                    endDt.toISOString(),
                    false
                )
                tryVerify(() => svc.plannerWorkouts.length === 1, 2000)
                const plannerBanner = findChild(view, "exercisesPlannerSyncBanner")
                check(plannerBanner !== null && plannerBanner.visible === true,
                    "Weekly Planner workout banner did not appear for planned [Workout] event")
                check(svc.importPlannerWorkout(svc.plannerWorkouts[0]) === true, "importPlannerWorkout failed")
                check(svc.dayPlan.exercises.some(e => e.name === "Hack Squat" && e.weight === 100),
                    "Imported planner exercise missing from checklist")

                svc.openInWeeklyPlanner(origDate)
                tryCompare(dashboard, "currentPageId", "weeklyPlanner", 3000)
                let plannerView = null
                tryVerify(() => {
                    plannerView = findChild(dashboard, "dashboardWeeklyPlanner")
                    return plannerView !== null && plannerView.visible
                }, 3000)
                const plannerJumpBtn = findChild(plannerView, "plannerExercisesAction")
                check(plannerJumpBtn !== null && plannerJumpBtn.visible === true,
                    "plannerExercisesAction button missing in DashboardWeeklyPlanner")
                plannerJumpBtn.clicked()
                tryCompare(dashboard, "currentPageId", "exercisesTracker", 3000)

                svc.selectDate(origDate)
                svc.flushSave()
                wait(250)
                console.info("ET_RUNTIME_INITIAL_PASS", checks)
            } catch (err) {
                console.error("ET_RUNTIME_FAIL", err.message, err.stack)
            }
            Qt.quit()
        }
    }

    Timer {
        interval: 120
        running: true
        repeat: false
        onTriggered: test.run()
    }
}
"""


OFFSCREEN_DIRECT_SHELL_QML = r"""
pragma ComponentBehavior: Bound
import QtQuick
import QtTest
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.dashboard

ShellRoot {
    id: root
    Component.onCompleted: Quickshell.watchFiles = false
    property bool tabPresentationActive: true
    readonly property var trackerItem: trackerLoader.item

    Window {
        id: win
        visible: true
        width: 1280
        height: 840
        color: "#11161d"

        DashboardHeader {
            id: header
            width: parent.width
            pageIds: ["dashboard", "weeklyPlanner", "exercisesTracker"]
            pageCount: 3
            currentPage: 2
        }

        Loader {
            id: trackerLoader
            anchors.top: header.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            active: AlisIntergration.exercisesTrackerEnabled && AlisIntergration.exercisesTrackerDashboardSource().length > 0
            source: active ? AlisIntergration.exercisesTrackerDashboardSource() : ""
            Binding {
                target: root.trackerItem
                property: "presentationActive"
                when: trackerLoader.status === Loader.Ready && root.trackerItem !== null
                value: root.tabPresentationActive
            }
        }
    }

    TestCase {
        id: test
        when: false
        optional: true
        property int checks: 0
        function check(cond, msg) {
            checks++
            if (!cond)
                throw new Error(msg)
        }

        function run() {
            try {
                tryCompare(Config, "ready", true, 5000)
                tryCompare(Events, "ready", true, 5000)
                tryCompare(AlisIntergration, "available", true, 5000)
                tryVerify(() => AlisIntergration.exercisesTrackerEnabled === true, 4000)
                tryVerify(() => AlisIntergration.exercisesTracker !== null, 4000)
                const svc = AlisIntergration.exercisesTracker
                tryCompare(svc, "ready", true, 4000)
                tryCompare(trackerLoader, "status", Loader.Ready, 4000)

                check(header.pageLabel("exercisesTracker") === "Exercises Tracker",
                    "DashboardHeader.pageLabel('exercisesTracker') mismatch")

                if (Quickshell.env("ET_PHASE") === "restart") {
                    check(svc.dayPlan.totalExercises >= 5,
                        "Persisted exercises did not reload after restart: " + svc.dayPlan.totalExercises)
                    check(svc.dayPlan.completedExercises >= 2,
                        "Completed exercise state did not survive restart")
                    check(svc.bodyCheckins.length === 1,
                        "Body check-in count mismatch after restart: " + svc.bodyCheckins.length)
                    check(svc.bodyCheckins[0].weightKg === 71.4 && svc.bodyCheckins[0].hasPhoto === true,
                        "Persisted body check-in metrics/photo missing after restart")
                    check(svc.state.legacyFixtureMarker === "keep-intact",
                        "Legacy unknown top-level field was dropped during save/reload")
                    console.info("ET_RUNTIME_RESTART_PASS", checks)
                    Qt.quit()
                    return
                }

                const view = root.trackerItem
                check(view !== null && view.objectName === "dashboardExercisesTracker",
                    "DashboardExercisesTracker did not mount")

                // 1. Apply Push template + add custom exercise + check off & step sets
                svc.applyTemplate("push", true)
                check(svc.dayPlan.totalExercises === 4, "Push template should load 4 exercises")

                const nameField = findChild(view, "exerciseNameField")
                const setsField = findChild(view, "exerciseSetsField")
                const repsField = findChild(view, "exerciseRepsField")
                const weightField = findChild(view, "exerciseWeightField")
                const submitBtn = findChild(view, "exerciseSubmitButton")
                check(nameField && setsField && repsField && weightField && submitBtn, "Composer controls missing")

                nameField.text = "Weighted Dips"
                setsField.text = "3"
                repsField.text = "10"
                weightField.text = "20"
                submitBtn.clicked()

                check(svc.dayPlan.totalExercises === 5, "Adding custom exercise failed")
                const firstId = svc.dayPlan.exercises[0].id
                const dipsEx = svc.dayPlan.exercises.find(e => e.name === "Weighted Dips")
                check(!!dipsEx, "Weighted Dips missing from dayPlan")

                svc.toggleExercise(firstId)
                svc.stepExerciseSets(dipsEx.id, 3)
                check(svc.dayPlan.completedExercises === 2, "Expected 2 completed exercises")
                check(svc.dayPlan.volumeKg > 600, "Expected positive training volume")

                // 2. Rest timer starts while visible and pauses deterministically when hidden
                svc.startRestTimer(75, "Weighted Dips")
                check(svc.restRunning === true && svc.restRemainingSec === 75, "Rest timer did not start")
                root.tabPresentationActive = false
                tryVerify(() => svc.restRunning === false, 2000)
                root.tabPresentationActive = true
                svc.stopRestTimer()

                // 3. Body Tracker Photo Check-in (explicit path import, bounded sourceSize, Lightbox Escape, delete)
                const photo1 = Quickshell.env("ET_PHOTO_1")
                const photo2 = Quickshell.env("ET_PHOTO_2")
                check(svc.addBodyCheckin(photo1, 72.0, 15.1, "Baseline photo"), "First photo import rejected")
                tryVerify(() => !svc.photoImportBusy && svc.bodyCheckins.length === 1, 4000)
                const bc1Id = svc.bodyCheckins[0].id

                check(svc.addBodyCheckin(photo2, 71.4, 14.7, "Post-push check-in"), "Second photo import rejected")
                tryVerify(() => !svc.photoImportBusy && svc.bodyCheckins.length === 2, 4000)
                const bc2 = svc.bodyCheckins[0]
                check(bc2.hasWeightDelta && bc2.weightDeltaKg === -0.6,
                    "Expected -0.6 kg delta, got " + bc2.weightDeltaKg)

                wait(50)
                const thumb = findChild(view, "bodyCheckinThumbnail_" + bc2.id)
                check(thumb !== null, "Body check-in thumbnail Image not mounted")
                check(thumb.asynchronous === true && thumb.cache === false
                    && thumb.sourceSize.width <= 280 && thumb.sourceSize.height <= 280,
                    "Thumbnail Image violated async/bounded sourceSize contract")

                findChild(view, "bodyViewCompareButton").clicked()
                check(view.bodyGalleryMode === "compare", "Compare mode did not activate")
                findChild(view, "bodyViewTimelineButton").clicked()

                view.previewCheckin = bc2
                const modal = findChild(view, "bodyPhotoPreviewModal")
                check(modal !== null && modal.visible === true, "Photo preview modal did not open")
                check(view.handleEscape() === true && view.previewCheckin === null,
                    "handleEscape() did not dismiss photo preview modal")

                check(svc.deleteBodyCheckin(bc1Id) === true && svc.bodyCheckins.length === 1,
                    "Deleting body check-in failed")

                // 4. Two-Way Weekly Planner Sync (ExercisesTracker <-> Events + GlobalStates)
                const syncedEventId = svc.syncDayToWeeklyPlanner(svc.selectedDate)
                check(syncedEventId > 0, "syncDayToWeeklyPlanner did not create an Events record")
                check(Events.list.some(ev => Number(ev.id) === syncedEventId && String(ev.title).indexOf("[Workout]") === 0),
                    "Synced workout event missing from Events.list")

                const origDate = svc.selectedDate
                svc.stepDate(1)
                const tomorrowStr = svc.selectedDate
                const tParts = tomorrowStr.split("-")
                const startDt = new Date(Number(tParts[0]), Number(tParts[1]) - 1, Number(tParts[2]), 17, 0, 0)
                const endDt = new Date(Number(tParts[0]), Number(tParts[1]) - 1, Number(tParts[2]), 18, 0, 0)
                Events.addEvent(
                    "[Workout] Legs Hypertrophy",
                    "- Hack Squat — 4 × 10 · 100 kg\n- Seated Leg Curl — 3 × 12 · 45 kg\n#workout",
                    startDt.toISOString(),
                    "reminder",
                    "normal",
                    15,
                    "none",
                    endDt.toISOString(),
                    false
                )
                tryVerify(() => svc.plannerWorkouts.length === 1, 2000)
                const plannerBanner = findChild(view, "exercisesPlannerSyncBanner")
                check(plannerBanner !== null && plannerBanner.visible === true,
                    "Weekly Planner workout banner did not appear for planned [Workout] event")
                check(svc.importPlannerWorkout(svc.plannerWorkouts[0]) === true, "importPlannerWorkout failed")
                check(svc.dayPlan.exercises.some(e => e.name === "Hack Squat" && e.weight === 100),
                    "Imported planner exercise missing from checklist")

                svc.openInWeeklyPlanner(origDate)
                check(GlobalStates.dashboardPageId === "weeklyPlanner" && GlobalStates.dashboardOpen === true,
                    "openInWeeklyPlanner did not route Dashboard to weeklyPlanner")
                svc.openDashboardTracker(origDate)
                check(GlobalStates.dashboardPageId === "exercisesTracker",
                    "openDashboardTracker did not route Dashboard back to exercisesTracker")

                // 5. Explicit toggle off & back on via AlisIntergration
                AlisIntergration.setExercisesTrackerEnabled(false)
                check(AlisIntergration.exercisesTrackerEnabled === false, "Disabling Exercises Tracker failed")
                AlisIntergration.setExercisesTrackerEnabled(true)
                tryVerify(() => AlisIntergration.exercisesTrackerEnabled === true && AlisIntergration.exercisesTracker !== null, 3000)

                const svcAfterToggle = AlisIntergration.exercisesTracker
                tryCompare(svcAfterToggle, "ready", true, 3000)
                svcAfterToggle.selectDate(origDate)
                svcAfterToggle.flushSave()
                wait(250)
                console.info("ET_RUNTIME_INITIAL_PASS", checks)
            } catch (err) {
                console.error("ET_RUNTIME_FAIL", err.message, err.stack)
            }
            Qt.quit()
        }
    }

    Timer {
        interval: 120
        running: true
        repeat: false
        onTriggered: test.run()
    }
}
"""


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="alis-et-runtime-") as tmp:
        private = Path(tmp)
        shell = private / "shell"
        shell.mkdir()
        for entry in (
            "services",
            "modules",
            "GlobalStates.qml",
            "qmldir",
            "scripts",
            "defaults",
            "translations",
            "assets",
        ):
            (shell / entry).symlink_to(HOST / entry)

        package = private / "data/alis-intergration/releases/fixture"
        package.parent.mkdir(parents=True)
        installer.assemble(ROOT, package, "e" * 40)
        (private / "data/alis-intergration/current").symlink_to("releases/fixture")

        config_dir = private / "config/alis"
        config_dir.mkdir(parents=True)
        options = json.loads((HOST / "defaults/config.json").read_text(encoding="utf-8"))
        options["integrations"]["alisIntergration"] = {
            "tlp": False,
            "thinkfan": False,
            "nexus": True,
            "spaced_repetition": False,
        }
        options["battery"]["chargeLimit"]["enable"] = False
        options["powerProfiles"]["fanControl"]["enabled"] = False
        (config_dir / "config.json").write_text(json.dumps(options), encoding="utf-8")

        et_state_dir = private / "state/quickshell/user/exercises-tracker"
        et_state_dir.mkdir(parents=True)
        (et_state_dir / "state.json").write_text(
            json.dumps({"schemaVersion": 1, "legacyFixtureMarker": "keep-intact", "days": {}, "bodyCheckins": []}),
            encoding="utf-8",
        )

        photo1 = private / "photo_baseline.png"
        photo2 = private / "photo_latest.png"
        photo1.write_bytes(make_png(48, 48, (50, 120, 200)))
        photo2.write_bytes(make_png(48, 48, (80, 200, 140)))

        runtime_dir = private / "runtime"
        runtime_dir.mkdir(mode=0o700)
        clean_env = {
            k: v
            for k, v in os.environ.items()
            if k
            not in (
                "WAYLAND_DISPLAY",
                "DISPLAY",
                "QT_QPA_PLATFORM",
                "QT_QUICK_BACKEND",
                "QSG_RHI_BACKEND",
                "NIRI_SOCKET",
                "HYPRLAND_INSTANCE_SIGNATURE",
            )
        }
        clean_env.update(
            {
                "XDG_RUNTIME_DIR": str(runtime_dir),
                "XDG_CONFIG_HOME": str(private / "config"),
                "XDG_CACHE_HOME": str(private / "cache"),
                "XDG_DATA_HOME": str(private / "data"),
                "XDG_STATE_HOME": str(private / "state"),
            }
        )

        sock = "wayland-alis-headless-et"
        kwin_bin = shutil.which("kwin_wayland")
        kwin_proc: subprocess.Popen | None = None
        use_virtual_wayland = False
        if kwin_bin:
            kwin_proc = subprocess.Popen(
                [
                    kwin_bin,
                    "--no-lockscreen",
                    "--no-global-shortcuts",
                    "--virtual",
                    "--socket",
                    sock,
                    "--width",
                    "1440",
                    "--height",
                    "960",
                ],
                env=clean_env,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )
            for _ in range(40):
                if kwin_proc.poll() is not None:
                    break
                if (runtime_dir / sock).exists():
                    use_virtual_wayland = True
                    break
                time.sleep(0.05)

        try:
            if use_virtual_wayland:
                (shell / "shell.qml").write_text(FULL_DASHBOARD_SHELL_QML, encoding="utf-8")
                base_env = dict(
                    clean_env,
                    WAYLAND_DISPLAY=sock,
                    QT_QPA_PLATFORM="wayland",
                    QT_QUICK_BACKEND="software",
                    QSG_RHI_BACKEND="software",
                    ET_PHOTO_1=str(photo1),
                    ET_PHOTO_2=str(photo2),
                    ET_PHASE="initial",
                )
            else:
                options["integrations"]["alisIntergration"]["nexus"] = False
                options["integrations"]["alisIntergration"]["spaced_repetition"] = True
                (config_dir / "config.json").write_text(json.dumps(options), encoding="utf-8")
                (shell / "shell.qml").write_text(OFFSCREEN_DIRECT_SHELL_QML, encoding="utf-8")
                base_env = dict(
                    clean_env,
                    QT_QPA_PLATFORM="offscreen",
                    QT_QUICK_BACKEND="software",
                    ET_PHOTO_1=str(photo1),
                    ET_PHOTO_2=str(photo2),
                    ET_PHASE="initial",
                )

            bad_tokens = (
                "ET_RUNTIME_FAIL",
                "TypeError:",
                "ReferenceError:",
                "Binding loop",
                "Unable to assign",
                "Cannot assign to non-existent property",
                "invalid context",
                "Failed to load configuration",
            )

            res1 = run_qs(shell, base_env, timeout=35)
            if (
                res1.returncode != 0
                or "ET_RUNTIME_INITIAL_PASS" not in res1.stdout
                or any(tok in res1.stdout for tok in bad_tokens)
            ):
                print(res1.stdout)
                raise SystemExit(1)

            photos_on_disk = list((et_state_dir / "photos").glob("*.png"))
            assert len(photos_on_disk) == 1, f"Expected 1 retained photo on disk, got {photos_on_disk}"

            restart_env = dict(base_env, ET_PHASE="restart")
            res2 = run_qs(shell, restart_env, timeout=30)
            if (
                res2.returncode != 0
                or "ET_RUNTIME_RESTART_PASS" not in res2.stdout
                or any(tok in res2.stdout for tok in bad_tokens)
            ):
                print(res2.stdout)
                raise SystemExit(1)
        finally:
            if kwin_proc is not None and kwin_proc.poll() is None:
                os.killpg(kwin_proc.pid, 15)
                try:
                    kwin_proc.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    os.killpg(kwin_proc.pid, 9)

    mode_label = "virtual-wayland" if use_virtual_wayland else "pure-offscreen"
    print(
        f"EXERCISES_TRACKER_RUNTIME_PASS ({mode_label}) Dashboard tab mount, CRUD, rest timer lifecycle, "
        "Body Tracker photo import/gallery/Escape/delete, 2-way Weekly Planner sync & restart persistence"
    )


if __name__ == "__main__":
    main()
