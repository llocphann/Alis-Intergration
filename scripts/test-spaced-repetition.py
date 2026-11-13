#!/usr/bin/env python3
"""Headless verification suite for Alis-Intergration Spaced Repetition:
1. Removal of Reverse Flashcard & Reverse Multiple Choice and legacy migration to Matching.
2. 2-column Matching mode (5 vocabulary words on left, 6 definitions on right with 1 distractor).
3. Smart Mix mode selector (randomly combines Matching, Multiple Choice, Cloze Reading; Flashcard as last resort).
4. Analytics column darker, Appearance.colors-derived component backgrounds with strict luminance hierarchy.
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def run_engine_verification() -> None:
    node_script = r"""
const fs = require("fs");
const vm = require("vm");
const assert = require("assert");

const lexiconCode = fs.readFileSync("services/SpacedRepetitionLexicon.js", "utf8")
    .replace(/^\.pragma\s+library\s*$/m, "");
const engineCode = fs.readFileSync("services/SpacedRepetitionEngine.js", "utf8")
    .replace(/^\.pragma\s+library\s*$/m, "")
    .replace(/^\.import\s+"SpacedRepetitionLexicon\.js"\s+as\s+Lexicon\s*$/m, "");

const sandbox = { console, Math, Date, JSON, Array, Object, String, Number, Boolean, RegExp };
vm.createContext(sandbox);
vm.runInContext(lexiconCode, sandbox, { filename: "SpacedRepetitionLexicon.js" });
sandbox.Lexicon = sandbox;
vm.runInContext(engineCode, sandbox, { filename: "SpacedRepetitionEngine.js" });

const nowMs = Date.UTC(2026, 10, 8, 12, 0, 0);
const seeded = sandbox.migrateStorage(null, nowMs);

// 1. Legacy Mode Normalization
for (const legacy of ["reverse", "reverse_flashcard", "reverseFlashcard", "rmc", "reverse_mcq", "reverseMultipleChoice", "matching"]) {
    assert.strictEqual(sandbox.normalizeStudyMode(legacy), "matching", `Expected ${legacy} -> matching`);
}
assert.strictEqual(sandbox.normalizeStudyMode("mcq"), "mc");
assert.strictEqual(sandbox.normalizeStudyMode("cloze"), "cloze");
assert.strictEqual(sandbox.normalizeStudyMode("flashcard"), "flashcard");

const migratedLegacy = sandbox.migrateStorage({
    schemaVersion: 4,
    reviewMode: "reverse_flashcard",
    studyMode: "reverse_mcq",
    cards: seeded.cards.slice(0, 6)
}, nowMs);
assert.strictEqual(migratedLegacy.retainedStorageFields.reviewMode, "matching");
assert.strictEqual(migratedLegacy.retainedStorageFields.studyMode, "matching");
assert.strictEqual(sandbox.normalizeOptions({ studyDirection: "reverse_mcq" }).studyDirection, "matching");

// 2. Matching Round Builder (5 Left Words + 6 Right Definitions with 1 Distractor + Padding when <5 Due)
const dueSix = seeded.cards.slice(0, 6);
const roundFull = sandbox.buildMatchingRound(dueSix, seeded.cards);
assert.strictEqual(roundFull.leftWords.length, 5, "Expected 5 left words");
assert.strictEqual(roundFull.rightDefs.length, 6, "Expected 6 right definitions");
assert.strictEqual(roundFull.leftWords.filter(w => w.inQueue).length, 5);
assert.strictEqual(roundFull.rightDefs.filter(d => d.isDistractor).length, 1, "Expected 1 distractor definition");
for (const w of roundFull.leftWords) {
    assert.ok(roundFull.rightDefs.some(d => !d.isDistractor && d.targetCardId === w.id));
}

// Edge case: only 2 due cards in queue -> pads 3 cards from deck so left column still has 5 words and right column has 6 definitions
const dueTwo = seeded.cards.slice(0, 2);
const roundPadded = sandbox.buildMatchingRound(dueTwo, seeded.cards);
assert.strictEqual(roundPadded.leftWords.length, 5);
assert.strictEqual(roundPadded.leftWords.filter(w => w.inQueue).length, 2);
assert.strictEqual(roundPadded.leftWords.filter(w => !w.inQueue).length, 3);
assert.strictEqual(roundPadded.rightDefs.length, 6);
assert.strictEqual(roundPadded.rightDefs.filter(d => d.isDistractor).length, 1);

// Edge case: deck with <5 total cards (e.g. 3 cards) -> 3 left words + 4 right definitions (3 matching + 1 distractor)
const tinyDeck = seeded.cards.slice(0, 3);
const roundTiny = sandbox.buildMatchingRound(tinyDeck, tinyDeck);
assert.strictEqual(roundTiny.leftWords.length, 3);
assert.strictEqual(roundTiny.rightDefs.length, 4);
assert.strictEqual(roundTiny.rightDefs.filter(d => d.isDistractor).length, 1);

// Edge case: empty studyQueue (0 due/new cards for active filter) -> must return empty round so caught-up state is shown
const roundEmpty = sandbox.buildMatchingRound([], seeded.cards);
assert.strictEqual(roundEmpty.leftWords.length, 0, "Empty studyQueue must not pad non-due cards into a phantom round");
assert.strictEqual(roundEmpty.rightDefs.length, 0);

// 3. Smart Mode Selection (Combines Matching, Multiple Choice, Cloze Reading; Flashcard as Last Resort)
let state = { bag: [], lastMode: "" };
const seen = new Set();
for (let i = 0; i < 12; i++) {
    const pick = sandbox.selectNextStudyMode(dueSix, seeded.cards, state);
    state = pick.state;
    assert.ok(["matching", "mc", "cloze"].includes(pick.mode), `Unexpected mode ${pick.mode}`);
    assert.notStrictEqual(pick.mode, "flashcard");
    seen.add(pick.mode);
}
assert.strictEqual(seen.size, 3, "Expected all 3 active modes (matching, mc, cloze) to be combined");

// When < 5 cards remain in studyQueue, Smart Mix must use mc/cloze instead of 5-word matching
let tailState = { bag: ["matching", "mc", "cloze"], lastMode: "" };
for (let i = 0; i < 8; i++) {
    const pick = sandbox.selectNextStudyMode(tinyDeck, seeded.cards, tailState);
    tailState = pick.state;
    assert.ok(["mc", "cloze"].includes(pick.mode), `Expected mc/cloze for <5 remaining queue, got ${pick.mode}`);
}

// Last-resort fallback to Flashcard when only 1 bare card without cloze/example exists in deck
const bareSingle = [{
    id: "only-1",
    term: "monad",
    front: "monad",
    meaning: "single unit",
    back: "single unit",
    definitionEn: "single unit",
    example: "",
    clozeText: ""
}];
const fallback = sandbox.selectNextStudyMode(bareSingle, bareSingle, { bag: [], lastMode: "" });
assert.strictEqual(fallback.mode, "flashcard");

// 4. Civil-day interval scheduling & sub-day midnight learning preservation
const baseOpts = sandbox.normalizeOptions({});
const day0EveningMs = new Date(2026, 10, 7, 22, 0, 0).getTime();
const day1MorningMs = new Date(2026, 10, 8, 8, 30, 0).getTime();
const day2MorningMs = new Date(2026, 10, 9, 9, 0, 0).getTime();
const cardHard = sandbox.scheduleReview(Object.assign({}, seeded.cards[0], { id: "c-hard", dueAt: day0EveningMs, dueDate: "2026-11-07" }), "hard", day0EveningMs, baseOpts, {}).card;
const cardGood = sandbox.scheduleReview(Object.assign({}, seeded.cards[1], { id: "c-good", dueAt: day0EveningMs, dueDate: "2026-11-07" }), "good", day0EveningMs, baseOpts, {}).card;
assert.strictEqual(cardHard.interval, 1);
assert.strictEqual(cardGood.interval, 2);
const nextMorningQueue = sandbox.buildStudyQueue([cardHard, cardGood], { options: baseOpts }, day1MorningMs);
assert.strictEqual(JSON.stringify(nextMorningQueue.map(c => c.id)), JSON.stringify(["c-hard"]));
const day2Queue = sandbox.buildStudyQueue([cardGood], { options: baseOpts }, day2MorningMs);
assert.strictEqual(JSON.stringify(day2Queue.map(c => c.id)), JSON.stringify(["c-good"]));

console.log("ALIS_INTERGRATION_SR_ENGINE_PASS");
"""
    res = subprocess.run(["node", "-e", node_script], cwd=ROOT, capture_output=True, text=True, check=False)
    if res.returncode != 0 or "ALIS_INTERGRATION_SR_ENGINE_PASS" not in res.stdout:
        print(res.stdout, file=sys.stderr)
        print(res.stderr, file=sys.stderr)
        raise AssertionError("Alis-Intergration SpacedRepetitionEngine verification failed")


def verify_qml_contracts() -> None:
    sr_qml = (ROOT / "modules" / "dashboard" / "DashboardSpacedRepetition.qml").read_text(encoding="utf-8")
    sr_service = (ROOT / "services" / "SpacedRepetition.qml").read_text(encoding="utf-8")
    sr_settings = (ROOT / "modules" / "settings" / "DashboardSpacedRepetitionSettings.qml").read_text(encoding="utf-8")

    for required in (
        'objectName: "srMatchingBoard"',
        'objectName: "srMatchingLeftColumn"',
        'objectName: "srMatchingCorridor"',
        'objectName: "srMatchingRightColumn"',
        'objectName: "srMatchingLinesCanvas"',
        'objectName: "srMatchingContinueButton"',
        'objectName: "srClozeWordBank"',
        'objectName: "srStudyMode-smart"',
        'objectName: "srStudyMode-" + modelData.id',
        '{ id: "matching",',
        '{ id: "mc",',
        '{ id: "cloze",',
        '{ id: "flashcard",',
        'property bool _suppressMatchingQueueSync: false',
        'function _shouldResetMatchingRoundFromQueue(): bool',
        'function onStudyQueueChanged(): void',
        'readonly property bool isClozeMode: root.backend.studyMode === "cloze"',
        'readonly property bool studyDigitShortcutsActive:',
        'readonly property bool clozeNumericTypingActive:',
        'property string _lastShortcutAction: ""',
        'readonly property color matchedStrokeColor: ColorUtils.mix(Appearance.colors.colPrimary, "#10b981", 0.45)',
        'readonly property color mismatchStrokeColor: Appearance.colors.colError',
        'readOnly: root.answerRevealed',
        'function selectClozeChoice(index: int): bool',
        'readonly property color colAnalyticsColumnBg:',
        'readonly property color colAnalyticsCardBg:',
        'readonly property color colAnalyticsSubBoxBg:',
        'function relativeLuminance(',
        'Appearance.colors.colLayer1Base',
        'Appearance.colors.colLayer2Base',
        'Appearance.colors.colLayer0Base',
        'Appearance.colors.colOutlineVariant',
    ):
        assert required in sr_qml, f"Missing {required} in DashboardSpacedRepetition.qml"

    for forbidden in (
        'objectName: "srStudyMode-reverse"',
        'objectName: "srStudyMode-rmc"',
        'Translation.tr("Reverse MC")',
    ):
        assert forbidden not in sr_qml, f"Forbidden legacy mode token {forbidden} found in DashboardSpacedRepetition.qml"

    assert "function rateCardById(" in sr_service
    assert "function rollNextStudyMode(" in sr_service
    assert "function buildMatchingRound(" in sr_service
    assert "function syncConfiguredStudyDirection(" in sr_service
    assert "function refreshClock(" in sr_service
    assert 'value: "matching"' in sr_settings
    assert '"reverse_flashcard"' in sr_settings
    assert '"reverse_mcq"' in sr_settings


def main() -> None:
    run_engine_verification()
    verify_qml_contracts()
    print("ALIS_INTERGRATION_SPACED_REPETITION_PASS")


if __name__ == "__main__":
    main()
