#!/usr/bin/env python3
"""Exercise real SR input and persisted reloads in a private Wayland session."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
HOST = Path(os.environ.get("ALIS_ROOT", Path.home() / ".config/quickshell/alis"))
sys.path.insert(0, str(HOST / "scripts"))
from contextlib import nullcontext
from native_test_session import private_wayland, run_qs

QML = r'''
import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import qs.modules.common
import "__PACKAGE__/services" as IntegrationServices
import "__PACKAGE__/modules/dashboard" as IntegrationViews
Window {
    id: win
    width: 1240; height: 820; visible: true
    Component.onCompleted: Quickshell.watchFiles = false
    IntegrationServices.SpacedRepetition {
        id: srBackend
        filePath: Quickshell.env("SR_TEST_FILE")
    }
    IntegrationViews.DashboardSpacedRepetition {
        id: view
        anchors.fill: parent
        presentationActive: true
        backend: srBackend
    }
    Process {
        id: rewrite
        command: ["python3", "-c", "import pathlib,sys;p=pathlib.Path(sys.argv[1]);p.write_text(p.read_text()+'\\n')", Quickshell.env("SR_TEST_FILE")]
    }
    Timer { interval: 1000; running: true; onTriggered: test.run() }
    TestCase {
        id: test
        when: false
        optional: true
        property int checks: 0
        property int failures: 0
        function check(ok, message) {
            checks++
            console.info(ok ? "SR_INPUT_PASS" : "SR_INPUT_FAIL", message)
            if (!ok) failures++
        }
        function run() {
          try {
            tryCompare(Config, "ready", true, 10000)
            tryCompare(srBackend, "ready", true, 10000)
            tryVerify(() => srBackend.cards.length > 0, 10000)
            wait(1000)
            srBackend.smartMixEnabled = true
            srBackend.studyMode = "mc"
            view.resetCardInteraction()
            view.forceActiveFocus()
            wait(150)
            const id = srBackend.currentCard.id
            const history = JSON.stringify(srBackend.historyByDay)
            for (let i = 0; i < view.multipleChoiceOptions.length; i++) {
                const definition = findChild(view, "srMcOptionDefinition-" + i)
                const option = view.multipleChoiceOptions[i]
                check(definition && definition.visible && definition.text.indexOf(option.front) < 0,
                    "MC visible definition hides its answer: " + i)
            }
            for (const key of [Qt.Key_A, Qt.Key_B, Qt.Key_C, Qt.Key_D, Qt.Key_D]) {
                keyClick(key)
                wait(60)
                check(srBackend.studyMode === "mc" && srBackend.currentCard.id === id && !view.answerRevealed,
                    "answer letter stages without changing card or mode: " + key)
            }
            keyClick(Qt.Key_D, Qt.ShiftModifier)
            wait(60)
            check(srBackend.studyMode === "mc" && srBackend.currentCard.id === id && !view.answerRevealed && view.pendingChoiceIndex === 3,
                "Shift+D stages option four without changing card or mode")
            check(srBackend.interactionLocked === true && srBackend.presentationActive === true,
                "staged MC option locks backend session clock against mid-question preemption")
            // Clicking Study Arena buttons must keep keyboard focus on view so 'd' still works immediately.
            const mcModeChip = findChild(view, "srStudyMode-mc")
            if (mcModeChip) {
                mouseClick(mcModeChip)
                wait(60)
                srBackend.smartMixEnabled = true
                keyClick(Qt.Key_D)
                wait(60)
                check(view.pendingChoiceIndex === 3 && !view.answerRevealed && srBackend.currentCard.id === id,
                    "D still stages option four right after clicking mode chip")
            }
            // Switching from Library search input back to Study must clear hidden search focus so 'd' never filters studyQueue.
            mouseClick(findChild(view, "srSubTabLibrary"))
            wait(80)
            const libSearch = findChild(view, "srLibrarySearch")
            if (libSearch) {
                mouseClick(libSearch)
                wait(50)
            }
            mouseClick(findChild(view, "srSubTabStudy"))
            wait(80)
            keyClick(Qt.Key_D)
            wait(60)
            check(srBackend.searchQuery === "" && view.librarySearch === "" && srBackend.currentCard.id === id
                && srBackend.studyMode === "mc" && view.pendingChoiceIndex === 3 && !view.answerRevealed,
                "D after Library->Study switch never types into hidden search or jumps card")
            // Same-card background update (e.g. online lookup enrichment) must not wipe staged D or reshuffle MC options.
            const optionsBeforeUpdate = JSON.stringify(view.multipleChoiceOptions.map(o => o.id))
            srBackend.updateCard(id, { notes: "background enrichment sync" })
            wait(80)
            check(srBackend.currentCard.id === id && view.pendingChoiceIndex === 3 && !view.answerRevealed
                && JSON.stringify(view.multipleChoiceOptions.map(o => o.id)) === optionsBeforeUpdate,
                "same-card updateCard preserves staged D and option order")
            // Expired <10m learning card + non-forced refreshClock must not preempt active MC question while locked.
            const clockBefore = srBackend._sessionClockMs
            srBackend.refreshClock(false)
            check(srBackend._sessionClockMs === clockBefore && srBackend.currentCard.id === id && srBackend.studyMode === "mc",
                "refreshClock(false) does not preempt active MC question while interactionLocked")
            check(view.pendingChoiceIndex === 3, "D stages option four")
            check(JSON.stringify(srBackend.historyByDay) === history, "letters never submit a review")
            // A file watcher echo can arrive while the same question is staged.
            rewrite.running = true
            tryCompare(rewrite, "running", false, 3000)
            srBackend.loadFromFile()
            wait(1200)
            check(srBackend.studyMode === "mc", "equivalent persisted reload keeps active mode")
            check(view.pendingChoiceIndex === 3 && !view.answerRevealed, "equivalent reload keeps staged D")
            srBackend.smartMixEnabled = true
            srBackend.studyMode = "mc"
            view.resetCardInteraction()
            view.forceActiveFocus()
            wait(100)
            keyClick(Qt.Key_D); wait(60); keyClick(Qt.Key_Space); wait(60)
            check(view.answerRevealed && view.selectedChoiceIndex === 3, "Space confirms D only")
            check(JSON.stringify(srBackend.historyByDay) === history, "confirm does not grade")
            for (const postKey of [Qt.Key_D, Qt.Key_D, Qt.Key_A, Qt.Key_C]) {
                keyClick(postKey)
                wait(60)
                check(srBackend.currentCard.id === id && srBackend.studyMode === "mc" && view.answerRevealed,
                    "letter after reveal never jumps card or Smart Mix mode: " + postKey)
            }
            keyClick(Qt.Key_D, Qt.ShiftModifier); wait(60)
            check(srBackend.currentCard.id === id && srBackend.studyMode === "mc" && view.answerRevealed, "Shift+D after reveal does not advance")
            srBackend.smartMixEnabled = false
            keyClick(Qt.Key_2); wait(120)
            check(JSON.stringify(srBackend.historyByDay) !== history, "explicit rating records review")
            keyClick(Qt.Key_Z, Qt.ControlModifier); wait(120)
            check(srBackend.currentCard.id === id && JSON.stringify(srBackend.historyByDay) === history, "undo restores review")
            srBackend.studyMode = "matching"
            view.resetCardInteraction(true)
            wait(150)
            for (let i = 0; i < view.matchingRightDefs.length; i++) {
                const definition = findChild(view, "srMatchingRightDefText-" + i)
                const option = view.matchingRightDefs[i]
                check(definition && definition.visible && definition.text.indexOf(option.front) < 0,
                    "Matching visible definition hides its answer: " + i)
            }
            const left = view.matchingLeftWords[0]
            const right = view.matchingRightDefs.findIndex(d => d.targetCardId === left.id)
            mouseClick(findChild(view, "srMatchingLeftWord-0"))
            mouseClick(findChild(view, "srMatchingRightDef-" + right))
            wait(80)
            check(findChild(view, "srMatchingRightDefText-" + right).text === view.matchingRightDefs[right].definitionEn,
                "matched pair restores original definition")
            srBackend.studyMode = "cloze"
            view.resetCardInteraction()
            wait(150)
            const active = srBackend.currentCard
            check(view.maskedClozeMeaningCue(active).toLowerCase().indexOf(active.term.toLowerCase()) < 0,
                "Cloze meaning hides the answer")
            const saved = JSON.stringify(active)
            const custom = {term: "advantage", back: "An advantage is useful", clozeText: "{{c1::advantage::advantage}} and advantages"}
            check(view.maskedStudyText(srBackend.renderClozeFront(custom), custom).toLowerCase().indexOf("advantage") < 0,
                "Cloze hint and repeated outside answer are masked")
            const richPre = view.formatContextExampleRich(custom, false)
            check(richPre.toLowerCase().indexOf("advantage") < 0,
                "formatContextExampleRich masks self-hint and inflected secondary occurrences before reveal")
            const customIrreg = {term: "hide", back: "conceal", example: "The boy hid where others were hiding."}
            check(view.formatContextExampleRich(customIrreg, false).toLowerCase().indexOf("hid") < 0,
                "formatContextExampleRich masks irregular verb forms before reveal")
            view.answerRevealed = true
            check(view.maskedClozeMeaningCue(active) === active.back, "Cloze reveal restores original definition")
            check(JSON.stringify(active) === saved, "rendering never changes card data")
            view.presentationActive = false
            wait(40)
            check(srBackend.presentationActive === false, "hiding view suspends backend presentationActive timer gate")
            } catch(e) { failures++; console.error("SR_INPUT_FAIL", e.message, e.stack) }
            console.info("SR_INPUT_DONE", checks, failures)
            Qt.quit()
        }
    }
}
'''

OFFSCREEN_POPUP_STUB = """import QtQuick
Loader {
    id: root
    active: false
    property var model: []
    property Item anchorItem: parent
    property real padding: 4
    property bool noSmoothClosing: false
    property bool closeOnFocusLost: true
    property bool keyboardGrab: true
    property bool closeOnHoverLost: true
    property bool closeOnHoverLostAfterEntered: false
    property int closeOnHoverLostDelay: 500
    property bool anchorHovered: false
    property bool closeOnOutsideClick: false
    property var anchorRect: null
    property var popupAdjustment: null
    property bool scaleContent: false
    property bool cursorSlide: false
    property var cursorAnchorWindow: null
    property real cursorAnchorX: 0
    property real cursorAnchorY: 0
    property real visualMargin: 8
    property bool popupAbove: true
    property int popupSide: 0
    property real ambientShadowWidth: 1
    property color panelFallbackColor: "transparent"
    property real panelRadius: 8
    property real panelBorderWidth: 0
    property color panelBorderColor: "transparent"
    signal focusCleared()
    function grabFocus() {}
    function close() { root.active = false }
    function requestOpen() { root.active = true }
    function requestOpenAt(x, y, newModel) { if (newModel !== undefined) root.model = newModel; root.active = true }
}
"""

def _install_offscreen_modules_overlay(folder: Path, host_root: Path) -> None:
    mod_link = folder / "modules"
    if mod_link.is_symlink():
        mod_link.unlink()
    mod_link.mkdir(parents=True, exist_ok=True)
    for child in (host_root / "modules").iterdir():
        if child.name == "common":
            common_dir = mod_link / "common"
            common_dir.mkdir(parents=True, exist_ok=True)
            for cchild in child.iterdir():
                if cchild.name == "widgets":
                    w_dir = common_dir / "widgets"
                    w_dir.mkdir(parents=True, exist_ok=True)
                    for wchild in cchild.iterdir():
                        if wchild.name == "ContextMenu.qml":
                            (w_dir / "ContextMenu.qml").write_text(OFFSCREEN_POPUP_STUB, encoding="utf-8")
                        else:
                            (w_dir / wchild.name).symlink_to(wchild)
                else:
                    (common_dir / cchild.name).symlink_to(cchild)
        else:
            (mod_link / child.name).symlink_to(child)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--package", type=Path, default=ROOT)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    folder = args.output.resolve()
    folder.mkdir(parents=True, exist_ok=False)
    for name in ("modules", "services", "GlobalStates.qml", "qmldir", "assets", "scripts", "defaults", "translations"):
        (folder / name).symlink_to(HOST / name)
    (folder / "shell.qml").write_text(QML.replace("__PACKAGE__", args.package.resolve().as_uri()))
    def build_offscreen_env():
        e = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND=os.environ.get("QT_QUICK_BACKEND", "software"))
        for k in ("WAYLAND_DISPLAY", "DISPLAY", "NIRI_SOCKET", "HYPRLAND_INSTANCE_SIGNATURE"):
            e.pop(k, None)
        for kind in ("config", "state", "cache", "data"):
            d = folder / kind
            d.mkdir(parents=True, exist_ok=True)
            e[f"XDG_{kind.upper()}_HOME"] = str(d)
        return e

    use_offscreen = os.environ.get("QT_QPA_PLATFORM") == "offscreen"
    native_wayland = False
    ctx = nullcontext(build_offscreen_env()) if use_offscreen else private_wayland(folder)
    try:
        cm_env = ctx.__enter__()
        if not use_offscreen and cm_env is not None:
            native_wayland = True
    except RuntimeError:
        ctx = nullcontext(build_offscreen_env())
        cm_env = ctx.__enter__()
        native_wayland = False

    try:
        env = cm_env
        if env is None:
            raise RuntimeError("Private Wayland unavailable; native input gate UNRUN")
        if not native_wayland:
            _install_offscreen_modules_overlay(folder, HOST)
        config = json.loads((HOST / "defaults/config.json").read_text())
        config.setdefault("dashboard", {}).setdefault("spacedRepetition", {}).update({"autoLookupOnline": False})
        config.setdefault("weather", {})["enable"] = False
        config.setdefault("abyss", {}).setdefault("companion", {})["enabled"] = False
        for relative in ("config/alis/config.json", "config/illogical-impulse/config.json"):
            p = folder / relative; p.parent.mkdir(parents=True, exist_ok=True); p.write_text(json.dumps(config))
        payload = {"schemaVersion": 5, "cards": [
            {"id": "fixture-" + str(i), "term": word, "front": word, "headword": word,
             "definitionEn": word + " is " + meaning, "meaning": word + " is " + meaning,
             "back": word + " is " + meaning, "category": "vocabulary", "deck": "Fixture",
             "language": "en", "example": "We study " + word + ".", "reps": 0,
             "dueAt": 1, "createdAt": i + 1, "state": "new"}
            for i, (word, meaning) in enumerate([("advantage", "a benefit"), ("cause", "a reason"),
                ("choice", "a selection"), ("community", "a group"), ("distance", "a separation"),
                ("weather", "the atmospheric conditions")])], "historyByDay": {}, "nextId": 100}
        data = folder / "fixture.json"; data.write_text(json.dumps(payload))
        result = run_qs(folder, dict(env, SR_TEST_FILE=str(data)), timeout=50)
        (folder / "runtime.log").write_text(result.stdout)
        markers = [line for line in result.stdout.splitlines() if "SR_INPUT_" in line or "Error:" in line]
        print("\n".join(markers))
        passed = result.returncode == 0 and "SR_INPUT_DONE" in result.stdout and "SR_INPUT_FAIL" not in result.stdout
        (folder / "receipt.json").write_text(json.dumps({"passed": passed, "exitCode": result.returncode,
            "package": str(args.package.resolve()), "nativeWayland": native_wayland, "offscreenQtQuick": not native_wayland, "privateFixture": True}, indent=2))
        raise SystemExit(0 if passed else 1)
    finally:
        ctx.__exit__(None, None, None)

if __name__ == "__main__":
    main()
