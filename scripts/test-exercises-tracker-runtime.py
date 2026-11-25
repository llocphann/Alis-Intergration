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

        function verifyNexusExport(tracker) {
            const writer = AlisIntergration.session.zettelkasten
            const nexus = AlisIntergration.nexus
            tryVerify(() => writer?.ready && nexus?.vaultConfigured, 4000)
            GlobalStates.dashboardPageId = "exercisesTracker"
            GlobalStates.dashboardOpen = true
            nexus.isOpen = false

            check(writer.capture("Other note", "Independent capture"), "Other capture should start")
            check(!tracker.sendWorkoutLogToNexus(), "Busy writer should reject workout export")
            tryVerify(() => !writer.busy && writer.lastCreatedPath.includes("Other note"), 4000)
            check(GlobalStates.dashboardOpen && !nexus.isOpen, "Other capture must not navigate Tracker")

            Config.setNestedValue("notes.zettelkasten.folder", "Blocked")
            tryCompare(writer, "folder", "Blocked", 2000)
            check(tracker.sendWorkoutLogToNexus(), "Write attempt should start")
            check(tracker.workoutExportPending && !tracker.statusMessage && GlobalStates.dashboardOpen,
                "Tracker must wait for the note receipt")
            tryVerify(() => !tracker.workoutExportPending, 4000)
            check(tracker.errorMessage.length > 0 && !tracker.statusMessage && !nexus.isOpen
                && GlobalStates.dashboardOpen, "Failed write must leave the Dashboard open")

            Config.setNestedValue("notes.zettelkasten.folder", "Logs")
            tryCompare(writer, "folder", "Logs", 2000)
            check(tracker.sendWorkoutLogToNexus(), "Retry should start")
            check(!tracker.sendWorkoutLogToNexus(), "Duplicate export must be rejected while pending")
            tryVerify(() => !tracker.workoutExportPending && nexus.isOpen && !GlobalStates.dashboardOpen, 4000)
            tryCompare(nexus, "currentPath", writer.lastCreatedPath, 4000)
            check(!tracker.errorMessage && tracker.statusMessage.includes("Exported"), "Missing successful receipt")
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

                // Removed navigation & manual sync/export controls must not be mounted
                check(findChild(view, "exercisesOpenPlannerButton") === null, "exercisesOpenPlannerButton must be removed")
                check(findChild(view, "exercisesOpenNexusButton") === null, "exercisesOpenNexusButton must be removed")
                check(findChild(view, "exercisesSyncPlannerButton") === null, "exercisesSyncPlannerButton must be removed")
                check(findChild(view, "exercisesExportNexusButton") === null, "exercisesExportNexusButton must be removed")
                check(findChild(view, "exercisesPlannerSyncBanner") === null, "exercisesPlannerSyncBanner must be removed")

                // Search existing Nexus exercise, add linked exercise, and inspect Detail/Anatomy panel
                tryVerify(() => svc.searchExercises("Barbell Bench").some(e => e.title === "Barbell Bench Press" && e.relPath.length > 0), 4000)
                nameField.text = "Barbell Bench"
                const searchToggleBtn = findChild(view, "exerciseSearchToggleButton")
                check(searchToggleBtn !== null, "exerciseSearchToggleButton missing")
                searchToggleBtn.clicked()
                tryVerify(() => findChild(view, "exerciseSearchDropdown")?.visible === true, 2000)
                let searchFirst = null
                tryVerify(() => {
                    searchFirst = findChild(view, "exerciseSearchResult_0")
                    return searchFirst !== null
                }, 2000)
                searchFirst.clicked()
                setsField.text = "3"
                repsField.text = "8"
                weightField.text = "80"
                submitBtn.clicked()

                const benchEx = svc.dayPlan.exercises.find(
                    e => e.name === "Barbell Bench Press" && String(e.nexusRelPath || "").length > 0
                )
                check(!!benchEx, "Linked Nexus exercise was not attached on add")
                let inspectArea = null
                tryVerify(() => {
                    inspectArea = findChild(view, "exerciseInspectArea_" + benchEx.id)
                    return inspectArea !== null
                }, 2000)
                inspectArea.clicked(null)
                tryVerify(() => findChild(view, "exercisesDetailPanel")?.visible === true, 2000)
                tryVerify(() => !view.inspectedDetail?.loading && (view.inspectedDetail?.steps?.length ?? 0) >= 2 && findChild(view, "exercisesDetailTipsCard")?.visible === true, 4000)
                check(findChild(view, "exercisesDetailStepsCard")?.visible === true, "Detail steps card missing")
                check(findChild(view, "exercisesDetailBodyMapCanvas")?.visible === true, "Detail body map missing")
                check(findChild(view, "exercisesDetailPreviewImage")?.visible === true, "Detail preview image missing")
                const backBtn = findChild(view, "exercisesDetailBackButton")
                check(backBtn !== null && backBtn.visible === true, "exercisesDetailBackButton missing")
                backBtn.clicked()
                tryVerify(() => {
                    const panel = findChild(view, "exercisesDetailPanel")
                    return panel === null || !panel.visible
                }, 2000)

                // Rest timer syncs 2-way with TimerService (stays running across page switches)
                tryCompare(Persistent, "ready", true, 4000)
                svc.startRestTimer(75, "Weighted Dips")
                check(svc.restRunning === true && svc.restRemainingSec >= 74 && svc.restRemainingSec <= 75, "Rest timer did not start")
                check(TimerService.countdownRunning === true && TimerService.countdownSecondsLeft >= 74 && TimerService.countdownLabel === "Weighted Dips",
                    "TimerService did not mirror rest timer")
                dashboard.selectPage("dashboard")
                tryCompare(dashboard, "currentPageId", "dashboard", 2000)
                wait(80)
                check(svc.restRunning === true && TimerService.countdownRunning === true,
                    "Rest timer should keep running via Timer Edgebar when switching tabs")
                TimerService.toggleCountdown()
                check(svc.restRunning === false && svc.restPaused === true && TimerService.countdownPaused === true,
                    "TimerService pause did not sync back to ExercisesTracker")
                TimerService.toggleCountdown()
                check(svc.restRunning === true && svc.restPaused === false && TimerService.countdownRunning === true && !TimerService.countdownPaused,
                    "TimerService resume did not sync back to ExercisesTracker")
                TimerService.stopCountdown()
                check(svc.restRunning === false && svc.restRemainingSec === 0 && TimerService.countdownRunning === false && TimerService.countdownLabel === "",
                    "TimerService reset did not clear ExercisesTracker rest timer")
                dashboard.selectPage("exercisesTracker")
                tryCompare(dashboard, "currentPageId", "exercisesTracker", 2000)

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
                check(bc2.photoPath.indexOf("/90_System/95_Attachments/Body_Tracker/") !== -1
                    && bc2.photoVaultRel.indexOf("90_System/95_Attachments/Body_Tracker/") === 0,
                    "Body photo should auto-route to Nexus vault Body_Tracker dir, got " + bc2.photoPath + " / " + bc2.photoVaultRel)

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

                // Automatic 2-way Weekly Planner sync (no manual Sync/Import buttons needed)
                tryVerify(() => Events.list.some(ev => String(ev.title).indexOf("[Workout]") === 0), 3000)

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
                tryVerify(() => svc.dayPlan.exercises.some(e => e.name === "Hack Squat" && e.weight === 100), 3000)

                dashboard.selectPage("weeklyPlanner")
                tryCompare(dashboard, "currentPageId", "weeklyPlanner", 3000)
                let plannerView = null
                tryVerify(() => {
                    plannerView = findChild(dashboard, "dashboardWeeklyPlanner")
                    return plannerView !== null && plannerView.visible
                }, 3000)
                check(findChild(plannerView, "plannerExercisesAction") === null,
                    "plannerExercisesAction tab-jump button should be removed from DashboardWeeklyPlanner")
                dashboard.selectPage("exercisesTracker")
                tryCompare(dashboard, "currentPageId", "exercisesTracker", 3000)

                const workoutCard = findChild(view, "exercisesWorkoutCard")
                const bodyCard = findChild(view, "exercisesBodyTrackerCard")
                const openSettingsBtn = findChild(view, "exercisesOpenSettingsButton")
                check(workoutCard !== null && workoutCard.border.width === 0,
                    "exercisesWorkoutCard should have border.width === 0")
                check(bodyCard !== null && bodyCard.border.width === 0,
                    "exercisesBodyTrackerCard should have border.width === 0")
                check(openSettingsBtn !== null && openSettingsBtn.visible === true,
                    "exercisesOpenSettingsButton missing from Exercises Tracker header")
                const settingsSrc = AlisIntergration.settingsSource("exercisesTracker")
                check(settingsSrc.endsWith("/modules/settings/DashboardExercisesTrackerSettings.qml"),
                    "exercisesTracker settingsSource not registered: " + settingsSrc)
                const settingsComp = Qt.createComponent(settingsSrc)
                check(settingsComp.status === Component.Ready,
                    "DashboardExercisesTrackerSettings.qml failed to compile: " + settingsComp.errorString())
                const settingsView = settingsComp.createObject(win, { width: 720 })
                check(settingsView !== null && settingsView.implicitHeight > 100,
                    "DashboardExercisesTrackerSettings failed to instantiate")
                check(findChild(settingsView, "exercisesSettingsReminderSelector") !== null,
                    "exercisesSettingsReminderSelector missing in Settings")
                check(findChild(settingsView, "exercisesSettingsPhotoStorageModeSelector") !== null,
                    "exercisesSettingsPhotoStorageModeSelector missing in Settings")
                check(findChild(settingsView, "exercisesSettingsPhotosStorageStatus") !== null,
                    "exercisesSettingsPhotosStorageStatus missing in Settings")
                svc.updatePreferences({
                    bodyPhotosStorageMode: "custom",
                    bodyPhotosCustomDir: "90_System/CustomBody"
                })
                wait(80)
                const customField = findChild(settingsView, "exercisesSettingsCustomPhotoDirField")
                const browsePhotoBtn = findChild(settingsView, "exercisesSettingsBrowsePhotoDirButton")
                check(customField !== null && customField.visible === true && browsePhotoBtn !== null && browsePhotoBtn.visible === true,
                    "Custom photo directory controls should become visible in custom storage mode")
                svc.updatePreferences({ bodyPhotosStorageMode: "auto", bodyPhotosCustomDir: "" })
                settingsView.destroy()

                // Verify future-workout vs completed/past-workout notification state preservation
                let spams = 0
                const onEvt = () => { spams++ }
                const onRem = () => { spams++ }
                Events.eventTriggered.connect(onEvt)
                Events.reminderTriggered.connect(onRem)
                const pastDate = "2020-05-01"
                svc.selectDate(pastDate)
                svc.addExercise({ name: "Past Squat", category: "legs", sets: 3, reps: "8", weight: 60 })
                let pastEv = null
                tryVerify(() => {
                    pastEv = Events.list.find(e => String(e.description || "").includes("#workout · " + pastDate))
                    return Boolean(pastEv && pastEv.notified === true && pastEv.reminderNotified === true)
                }, 3000)
                Events.checkDueEvents()
                check(spams === 0, "Past synced workout emitted unexpected notification(s): " + spams)

                const futureDate = "2099-05-01"
                svc.selectDate(futureDate)
                svc.addExercise({ name: "Future Press", category: "chest", sets: 3, reps: "8", weight: 50 })
                let futEv = null
                tryVerify(() => {
                    futEv = Events.list.find(e => String(e.description || "").includes("#workout · " + futureDate))
                    return Boolean(futEv && futEv.notified === false && futEv.reminderMinutes === 15)
                }, 3000)
                Events.updateEvent(futEv.id, { notified: true, reminderNotified: true })
                const futExId = svc.dayPlan.exercises[0].id
                svc.updateExercise(futExId, { reps: "12" })
                wait(200)
                futEv = Events.list.find(e => Number(e.id) === Number(futEv.id))
                check(futEv.notified === true && futEv.reminderNotified === true,
                    "Updating future workout description reset notified/reminderNotified flags")
                Events.checkDueEvents()
                check(spams === 0, "Unchanged start time re-triggered notification after workout edit")
                const futureDate2 = "2099-05-02"
                svc.selectDate(futureDate2)
                svc.addExercise({ name: "Completed Bench", category: "chest", sets: 3, reps: "8", weight: 50 })
                let futEv2 = null
                tryVerify(() => {
                    futEv2 = Events.list.find(e => String(e.description || "").includes("#workout · " + futureDate2))
                    return Boolean(futEv2 && futEv2.notified === false)
                }, 3000)
                svc.toggleExercise(svc.dayPlan.exercises[0].id)
                tryVerify(() => {
                    futEv2 = Events.list.find(e => Number(e.id) === Number(futEv2.id))
                    return Boolean(futEv2 && futEv2.notified === true && futEv2.reminderNotified === true && futEv2.reminderMinutes === 0)
                }, 3000)
                Events.eventTriggered.disconnect(onEvt)
                Events.reminderTriggered.disconnect(onRem)

                svc.selectDate(origDate)
                verifyNexusExport(svc)
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

                // 1b. Removed buttons/banners must not be mounted + Search + Detail inspector
                check(findChild(view, "exercisesOpenPlannerButton") === null, "exercisesOpenPlannerButton must be removed")
                check(findChild(view, "exercisesOpenNexusButton") === null, "exercisesOpenNexusButton must be removed")
                check(findChild(view, "exercisesSyncPlannerButton") === null, "exercisesSyncPlannerButton must be removed")
                check(findChild(view, "exercisesExportNexusButton") === null, "exercisesExportNexusButton must be removed")
                check(findChild(view, "exercisesPlannerSyncBanner") === null, "exercisesPlannerSyncBanner must be removed")

                tryVerify(() => svc.searchExercises("Barbell Bench").some(e => e.title === "Barbell Bench Press" && e.relPath.length > 0), 4000)
                nameField.text = "Barbell Bench"
                const searchToggleBtn = findChild(view, "exerciseSearchToggleButton")
                check(searchToggleBtn !== null, "exerciseSearchToggleButton missing")
                searchToggleBtn.clicked()
                tryVerify(() => findChild(view, "exerciseSearchDropdown")?.visible === true, 2000)
                let searchFirst = null
                tryVerify(() => {
                    searchFirst = findChild(view, "exerciseSearchResult_0")
                    return searchFirst !== null
                }, 2000)
                searchFirst.clicked()
                setsField.text = "3"
                repsField.text = "8"
                weightField.text = "80"
                submitBtn.clicked()

                const benchEx = svc.dayPlan.exercises.find(
                    e => e.name === "Barbell Bench Press" && String(e.nexusRelPath || "").length > 0
                )
                check(!!benchEx, "Linked Nexus exercise was not attached on add")
                let inspectArea = null
                tryVerify(() => {
                    inspectArea = findChild(view, "exerciseInspectArea_" + benchEx.id)
                    return inspectArea !== null
                }, 2000)
                inspectArea.clicked(null)
                tryVerify(() => findChild(view, "exercisesDetailPanel")?.visible === true, 2000)
                tryVerify(() => !view.inspectedDetail?.loading && (view.inspectedDetail?.steps?.length ?? 0) >= 2 && findChild(view, "exercisesDetailTipsCard")?.visible === true, 4000)
                check(findChild(view, "exercisesDetailStepsCard")?.visible === true, "Detail steps card missing")
                check(findChild(view, "exercisesDetailBodyMapCanvas")?.visible === true, "Detail body map missing")
                check(findChild(view, "exercisesDetailPreviewImage")?.visible === true, "Detail preview image missing")
                check(view.handleEscape() === true, "handleEscape() did not dismiss detail inspector")
                tryVerify(() => {
                    const panel = findChild(view, "exercisesDetailPanel")
                    return panel === null || !panel.visible
                }, 2000)

                // 2. Rest timer syncs 2-way with TimerService & keeps running while hidden
                tryCompare(Persistent, "ready", true, 4000)
                svc.startRestTimer(75, "Weighted Dips")
                check(svc.restRunning === true && svc.restRemainingSec >= 74 && svc.restRemainingSec <= 75, "Rest timer did not start")
                check(TimerService.countdownRunning === true && TimerService.countdownSecondsLeft >= 74 && TimerService.countdownLabel === "Weighted Dips",
                    "TimerService did not mirror rest timer")
                root.tabPresentationActive = false
                wait(80)
                check(svc.restRunning === true && TimerService.countdownRunning === true,
                    "Rest timer should remain active via TimerService when hidden")
                TimerService.toggleCountdown()
                check(svc.restRunning === false && svc.restPaused === true && TimerService.countdownPaused === true,
                    "TimerService pause did not sync back to ExercisesTracker")
                TimerService.toggleCountdown()
                check(svc.restRunning === true && svc.restPaused === false && TimerService.countdownRunning === true && !TimerService.countdownPaused,
                    "TimerService resume did not sync back to ExercisesTracker")
                root.tabPresentationActive = true
                TimerService.stopCountdown()
                check(svc.restRunning === false && svc.restRemainingSec === 0 && TimerService.countdownRunning === false && TimerService.countdownLabel === "",
                    "TimerService reset did not clear ExercisesTracker rest timer")

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
                check(bc2.photoPath.indexOf("/90_System/95_Attachments/Body_Tracker/") !== -1
                    && bc2.photoVaultRel.indexOf("90_System/95_Attachments/Body_Tracker/") === 0,
                    "Body photo should auto-route to Nexus vault Body_Tracker dir, got " + bc2.photoPath + " / " + bc2.photoVaultRel)

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

                // 4. Automatic Two-Way Weekly Planner Sync (ExercisesTracker <-> Events)
                tryVerify(() => Events.list.some(ev => String(ev.title).indexOf("[Workout]") === 0), 3000)

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
                tryVerify(() => svc.dayPlan.exercises.some(e => e.name === "Hack Squat" && e.weight === 100), 3000)

                // 5. Verify borderless inner cards & Spaced Repetition colBorder parity + Integrations Settings view
                const workoutCard = findChild(view, "exercisesWorkoutCard")
                const bodyCard = findChild(view, "exercisesBodyTrackerCard")
                const openSettingsBtn = findChild(view, "exercisesOpenSettingsButton")
                check(workoutCard !== null && workoutCard.border.width === 0,
                    "exercisesWorkoutCard should have border.width === 0")
                check(bodyCard !== null && bodyCard.border.width === 0,
                    "exercisesBodyTrackerCard should have border.width === 0")
                check(openSettingsBtn !== null && openSettingsBtn.visible === true,
                    "exercisesOpenSettingsButton missing from Exercises Tracker header")
                check(Math.abs(view.colBorder.a - 0.07) < 0.015,
                    "Exercises Tracker colBorder alpha does not match Spaced Repetition (0.07): " + view.colBorder.a)

                const settingsSrc = AlisIntergration.settingsSource("exercisesTracker")
                check(settingsSrc.endsWith("/modules/settings/DashboardExercisesTrackerSettings.qml"),
                    "exercisesTracker settingsSource not registered: " + settingsSrc)
                const settingsComp = Qt.createComponent(settingsSrc)
                check(settingsComp.status === Component.Ready,
                    "DashboardExercisesTrackerSettings.qml failed to compile: " + settingsComp.errorString())
                const settingsView = settingsComp.createObject(win, { width: 720 })
                check(settingsView !== null && settingsView.implicitHeight > 100,
                    "DashboardExercisesTrackerSettings failed to instantiate")
                check(findChild(settingsView, "exercisesSettingsReminderSelector") !== null,
                    "exercisesSettingsReminderSelector missing in Settings")
                check(findChild(settingsView, "exercisesSettingsPhotoStorageModeSelector") !== null,
                    "exercisesSettingsPhotoStorageModeSelector missing in Settings")
                check(findChild(settingsView, "exercisesSettingsPhotosStorageStatus") !== null,
                    "exercisesSettingsPhotosStorageStatus missing in Settings")
                svc.updatePreferences({
                    defaultSets: 4,
                    defaultGalleryMode: "compare",
                    showBodyMetrics: false,
                    bodyPhotosStorageMode: "custom",
                    bodyPhotosCustomDir: "90_System/CustomBody"
                })
                wait(80)
                check(svc.preferences.defaultSets === 4 && svc.preferences.defaultGalleryMode === "compare",
                    "ExercisesTracker.updatePreferences did not update preferences")
                const customField = findChild(settingsView, "exercisesSettingsCustomPhotoDirField")
                const browsePhotoBtn = findChild(settingsView, "exercisesSettingsBrowsePhotoDirButton")
                check(customField !== null && customField.visible === true && browsePhotoBtn !== null && browsePhotoBtn.visible === true,
                    "Custom photo directory controls should become visible in custom storage mode")
                svc.applySplitPreset("upper_lower")
                check(svc.weeklyTemplates["1"] === "push" && svc.weeklyTemplates["2"] === "legs" && svc.weeklyTemplates["4"] === "pull",
                    "ExercisesTracker.applySplitPreset failed")
                svc.updatePreferences({
                    defaultSets: 3,
                    defaultGalleryMode: "timeline",
                    showBodyMetrics: true,
                    bodyPhotosStorageMode: "auto",
                    bodyPhotosCustomDir: ""
                })
                settingsView.destroy()

                // Verify future-workout vs completed/past-workout notification state preservation
                let spams = 0
                const onEvt = () => { spams++ }
                const onRem = () => { spams++ }
                Events.eventTriggered.connect(onEvt)
                Events.reminderTriggered.connect(onRem)
                const savedSelected = svc.selectedDate
                const pastDate = "2020-05-01"
                svc.selectDate(pastDate)
                svc.addExercise({ name: "Past Squat", category: "legs", sets: 3, reps: "8", weight: 60 })
                let pastEv = null
                tryVerify(() => {
                    pastEv = Events.list.find(e => String(e.description || "").includes("#workout · " + pastDate))
                    return Boolean(pastEv && pastEv.notified === true && pastEv.reminderNotified === true)
                }, 3000)
                Events.checkDueEvents()
                check(spams === 0, "Past synced workout emitted unexpected notification(s): " + spams)

                const futureDate = "2099-05-01"
                svc.selectDate(futureDate)
                svc.addExercise({ name: "Future Press", category: "chest", sets: 3, reps: "8", weight: 50 })
                let futEv = null
                tryVerify(() => {
                    futEv = Events.list.find(e => String(e.description || "").includes("#workout · " + futureDate))
                    return Boolean(futEv && futEv.notified === false && futEv.reminderMinutes === 15)
                }, 3000)
                // Simulating an already-fired reminder/notification before editing exercise notes/sets must preserve flags
                Events.updateEvent(futEv.id, { notified: true, reminderNotified: true })
                const futExId = svc.dayPlan.exercises[0].id
                svc.updateExercise(futExId, { reps: "12" })
                wait(200)
                futEv = Events.list.find(e => Number(e.id) === Number(futEv.id))
                check(futEv.notified === true && futEv.reminderNotified === true,
                    "Updating future workout description reset notified/reminderNotified flags")
                Events.checkDueEvents()
                check(spams === 0, "Unchanged start time re-triggered notification after workout edit")
                Events.eventTriggered.disconnect(onEvt)
                Events.reminderTriggered.disconnect(onRem)
                svc.selectDate(savedSelected)

                // 6. Explicit toggle off & back on via AlisIntergration
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
        vault = private / "vault"
        vault.mkdir()
        (vault / "Blocked").write_text("fixture sentinel", encoding="utf-8")
        ex_note = vault / "20_Personal_Life/33_Bodybuilding/Gym_n_Calisthenics_Exercises/Barbell Bench Press.md"
        ex_note.parent.mkdir(parents=True, exist_ok=True)
        ex_note.write_text(
            "---\n"
            "type: exercise\n"
            "muscles:\n"
            "  - chest\n"
            "  - triceps\n"
            "secondaryMuscles:\n"
            "  - shoulders\n"
            "equipment: Barbell\n"
            "force: push\n"
            "level: intermediate\n"
            "mechanic: compound\n"
            "category: strength\n"
            'previewImage: "[[90_System/95_Attachments/bench.png]]"\n'
            "---\n\n"
            "## How to Perform\n"
            "1. Unrack the barbell with scapulae retracted.\n"
            "2. Lower to mid-chest under control and press up.\n\n"
            "## Tips\n"
            "- Keep feet planted and wrists stacked.\n",
            encoding="utf-8",
        )
        bench_img = vault / "90_System/95_Attachments/bench.png"
        bench_img.parent.mkdir(parents=True, exist_ok=True)
        bench_img.write_bytes(make_png(64, 64, (210, 90, 60)))
        options["todo"]["nexus"]["vaultPath"] = str(vault)
        options["notes"]["zettelkasten"]["folder"] = "Logs"
        options["integrations"]["alisIntergration"] = {
            "tlp": False,
            "thinkfan": False,
            "nexus": True,
            "spaced_repetition": False,
            "exercises_tracker": True,
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

            if use_virtual_wayland:
                notes = list(vault.rglob("*.md"))
                workouts = [note for note in notes if "Workout" in note.name]
                assert len(notes) == 3 and len(workouts) == 1, notes
                assert "Weighted Dips" in workouts[0].read_text(encoding="utf-8")
                assert (vault / "Blocked").read_text(encoding="utf-8") == "fixture sentinel"

            vault_photos = list((vault / "90_System/95_Attachments/Body_Tracker").glob("*.png"))
            assert len(vault_photos) == 1, f"Expected 1 retained photo in Nexus vault Body_Tracker dir, got {vault_photos}"

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
