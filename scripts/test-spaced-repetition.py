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

const essentialCode = fs.readFileSync("plugins/spaced_repetition/services/SpacedRepetitionEssential4000.js", "utf8")
    .replace(/^\.pragma\s+library\s*$/m, "");
const promptsCode = fs.readFileSync("plugins/spaced_repetition/services/SpacedRepetitionPrompts.js", "utf8")
    .replace(/^\.pragma\s+library\s*$/m, "");
const lexiconCode = fs.readFileSync("plugins/spaced_repetition/services/SpacedRepetitionLexicon.js", "utf8")
    .replace(/^\.pragma\s+library\s*$/m, "")
    .replace(/^\.import\s+"SpacedRepetitionEssential4000\.js"\s+as\s+Essential4000\s*$/m, "");
const engineCode = fs.readFileSync("plugins/spaced_repetition/services/SpacedRepetitionEngine.js", "utf8")
    .replace(/^\.pragma\s+library\s*$/m, "")
    .replace(/^\.import\s+"SpacedRepetitionPrompts\.js"\s+as\s+Prompts\s*$/m, "")
    .replace(/^\.import\s+"SpacedRepetitionEssential4000\.js"\s+as\s+Essential4000\s*$/m, "")
    .replace(/^\.import\s+"SpacedRepetitionLexicon\.js"\s+as\s+Lexicon\s*$/m, "");

const essentialSandbox = { console, Math, Date, JSON, Array, Object, String, Number, Boolean, RegExp };
vm.createContext(essentialSandbox);
vm.runInContext(essentialCode, essentialSandbox, { filename: "SpacedRepetitionEssential4000.js" });

const promptsSandbox = { console, Math, Date, JSON, Array, Object, String, Number, Boolean, RegExp };
vm.createContext(promptsSandbox);
vm.runInContext(promptsCode, promptsSandbox, { filename: "SpacedRepetitionPrompts.js" });

const sandbox = { console, Math, Date, JSON, Array, Object, String, Number, Boolean, RegExp, Essential4000: essentialSandbox, Prompts: promptsSandbox };
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

// The learner sees the masked definition, including for the extra distractor.
const smallPair = ["huge", "massive"].map(front => ({
    id: front, front, definitionEn: "If something is " + front + ", it is very big."
}));
const fillers = seeded.cards.slice(10, 14);
for (const [first, twin] of [smallPair, smallPair.slice().reverse()]) {
    for (const queue of [[first, twin, ...fillers], [first], [first, ...fillers]]) {
        const before = JSON.stringify(queue);
        const round = sandbox.buildMatchingRound(queue, [first, twin, ...fillers], () => 0.32);
        assert(round.leftWords.some(w => w.id === first.id && w.inQueue));
        assert(!round.rightDefs.some(d => d.front === twin.front));
        const cues = round.rightDefs.map(d => promptsSandbox.maskAnswer(d.definitionEn, d, false));
        assert.strictEqual(new Set(cues).size, cues.length);
        assert.strictEqual(round.leftWords.length, 5);
        assert.strictEqual(round.rightDefs.length, 6);
        assert.strictEqual(JSON.stringify(queue), before);
    }
}
assert.strictEqual(promptsSandbox.maskAnswer("A constructor builds objects.", {front: "constructor"}, false),
    "A [...] builds objects.");

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

// 5. Schema v5 Essential 4000 lexical repair + lossless user schedule preservation + idempotency
assert.strictEqual(sandbox.SCHEMA_VERSION, 5, "Expected SCHEMA_VERSION === 5");
const v4Corrupted = {
    schemaVersion: 4,
    nextId: 5000,
    historyByDay: { "2026-11-14": { reviewed: 5, passed: 5, newStudied: 2, reviewsDone: 3 } },
    cards: [
        {
            id: "sr-b04-u29-20",
            category: "vocabulary",
            deck: "English Vocabulary",
            language: "en",
            term: "transportation",
            pos: "verb",
            level: "C1",
            meaning: "Transportation is any type of vehicle that can carry people or things.",
            meaningVi: "vận chuyển",
            collocations: [
                "to transportation - vận chuyển",
                "transportation properly - vận chuyển đúng cách"
            ],
            clozeText: "I don’t have a car, so my normal {{c1::transportation::verb — vận chuyển}} is the train.",
            state: "young",
            reps: 1,
            interval: 3,
            ease: 265,
            lapses: 0,
            dueAt: 1794900000000,
            dueDate: "2026-11-17",
            lastReviewedAt: 1794600000000
        }
    ]
};
const upgradedV5 = sandbox.migrateStorage(v4Corrupted, nowMs, baseOpts, sandbox.analyzeTerm);
assert.strictEqual(upgradedV5.schemaVersion, 5);
const fixedTransport = upgradedV5.cards.find(c => c.id === "sr-b04-u29-20");
assert.ok(fixedTransport, "Expected upgraded sr-b04-u29-20");
assert.strictEqual(fixedTransport.pos, "noun", `Expected transportation pos=noun, got ${fixedTransport.pos}`);
assert.strictEqual(fixedTransport.level, "A2", `Expected transportation level=A2, got ${fixedTransport.level}`);
assert.ok(String(fixedTransport.meaningVi || "").includes("phương tiện giao thông"), `Unexpected meaningVi: ${fixedTransport.meaningVi}`);
assert.ok(Array.isArray(fixedTransport.collocations) && fixedTransport.collocations.some(c => /public transportation/i.test(c)),
    `Expected real collocation public transportation, got ${JSON.stringify(fixedTransport.collocations)}`);
assert.ok(!fixedTransport.collocations.some(c => /^to transportation/i.test(c)),
    "Fake collocation 'to transportation' must be removed");
assert.ok(fixedTransport.clozeText.includes("{{c1::transportation::noun"), `Unexpected clozeText: ${fixedTransport.clozeText}`);
assert.strictEqual(fixedTransport.reps, 1);
assert.strictEqual(fixedTransport.interval, 3);
assert.strictEqual(fixedTransport.ease, 265);
assert.strictEqual(fixedTransport.dueDate, "2026-11-17");
assert.strictEqual(fixedTransport.state, "young");
assert.strictEqual(fixedTransport.lastReviewedAt, 1794600000000);
assert.strictEqual(upgradedV5.historyByDay["2026-11-14"].reviewed, 5);

// Idempotency: subsequent reloads at schemaVersion=5 + lexiconRevision=2 preserve manual user edits
const editedAtV5 = Object.assign({}, upgradedV5, {
    cards: [Object.assign({}, fixedTransport, { notes: "user custom note", meaningVi: "user edited meaning" })]
});
const reloadedV5 = sandbox.migrateStorage(editedAtV5, nowMs, baseOpts, sandbox.analyzeTerm);
assert.strictEqual(reloadedV5.cards[0].notes, "user custom note");
assert.strictEqual(reloadedV5.cards[0].meaningVi, "user edited meaning");

// 6. Existing user already on schemaVersion=5 (pre-lexiconRevision=2) gets circular-definition & broken-cloze repairs without losing review history
const preRev2UserV5 = {
    schemaVersion: 5,
    nextId: 5100,
    historyByDay: { "2026-11-17": { reviewed: 12, passed: 11, newStudied: 5, reviewsDone: 7 } },
    cards: [
        {
            id: "sr-b01-u01-10",
            category: "vocabulary",
            deck: "English Vocabulary",
            language: "en",
            term: "hide",
            pos: "verb",
            level: "A2",
            meaning: "To hide is to try not to let others see you.",
            definitionEn: "To hide is to try not to let others see you.",
            meaningVi: "trốn",
            clozeText: "The other children will {{c1::hide::verb — trốn}} while you count to a hundred.",
            state: "young",
            reps: 3,
            lapses: 1,
            interval: 7,
            ease: 245,
            dueAt: 1795000000000,
            dueDate: "2026-11-18",
            lastReviewedAt: 1794400000000,
            notes: "irregular hid/hidden"
        },
        {
            id: "sr-b02-u10-09",
            category: "vocabulary",
            deck: "English Vocabulary",
            language: "en",
            term: "impression",
            pos: "noun",
            level: "B1",
            meaning: "the way of thinking about someone or something",
            definitionEn: "the way of thinking about someone or something",
            meaningVi: "ấn tượng",
            clozeText: "Most people think that most monsters are {{c1::mean::noun — ấn tượng}}.",
            state: "mature",
            reps: 6,
            lapses: 0,
            interval: 28,
            ease: 280,
            dueAt: 1796800000000,
            dueDate: "2026-12-09",
            lastReviewedAt: 1794300000000
        },
        {
            id: "sr-b03-u01-14",
            category: "vocabulary",
            deck: "English Vocabulary",
            language: "en",
            term: "magic",
            pos: "noun",
            level: "A2",
            meaning: "the power to make impossible things happen",
            definitionEn: "the power to make impossible things happen",
            meaningVi: "phép thuật",
            clozeText: "The {{c1::magic::noun — phép thuật}}ian made a rabbit appear.",
            state: "new",
            reps: 0,
            lapses: 0,
            interval: 0,
            ease: 250,
            dueAt: 1794000000000,
            dueDate: "2026-11-08",
            lastReviewedAt: 0
        }
    ]
};
const upgradedRev2 = sandbox.migrateStorage(preRev2UserV5, nowMs, baseOpts, sandbox.analyzeTerm);
assert.strictEqual(upgradedRev2.retainedStorageFields.lexiconRevision, 2);
const repairedHide = upgradedRev2.cards.find(c => c.id === "sr-b01-u01-10");
assert.strictEqual(sandbox.Prompts.containsAnswerForm(repairedHide.definitionEn, { term: "hide" }), false);
assert.strictEqual(repairedHide.reps, 3);
assert.strictEqual(repairedHide.lapses, 1);
assert.strictEqual(repairedHide.interval, 7);
assert.strictEqual(repairedHide.ease, 245);
assert.strictEqual(repairedHide.notes, "irregular hid/hidden");
const repairedImp = upgradedRev2.cards.find(c => c.id === "sr-b02-u10-09");
assert.ok(repairedImp.clozeText.includes("{{c1::impression::noun"), `Expected impression cloze target repaired, got: ${repairedImp.clozeText}`);
assert.strictEqual(repairedImp.reps, 6);
assert.strictEqual(repairedImp.interval, 28);
const repairedMagic = upgradedRev2.cards.find(c => c.id === "sr-b03-u01-14");
assert.ok(!repairedMagic.clozeText.includes("}}ian"), `Mid-word cloze slice must be repaired, got: ${repairedMagic.clozeText}`);

// 7. Verify 0 pre-answer leaks across all 3,603 Essential 4000 cards (definitions + cloze fronts)
for (const cid of Object.keys(sandbox.Essential4000.CARDS_BY_ID)) {
    const entry = sandbox.Essential4000.lookupByCardId(cid);
    const probe = { id: cid, term: entry.word, front: entry.word, headword: entry.word, clozeText: entry.clozeText };
    const maskedDef = sandbox.Prompts.maskAnswer(entry.definitionEn, probe, false);
    assert.strictEqual(sandbox.Prompts.containsAnswerForm(maskedDef, probe), false, `Leak in ${cid}: ${maskedDef}`);
    const front = sandbox.Prompts.maskAnswer(sandbox.renderClozeFront(entry.clozeText, entry.word), probe, false);
    assert.strictEqual(sandbox.Prompts.containsAnswerForm(front, probe), false, `Cloze leak in ${cid}: ${front}`);
}

console.log("ALIS_INTERGRATION_SR_ENGINE_PASS");
"""
    res = subprocess.run(["node", "-e", node_script], cwd=ROOT, capture_output=True, text=True, check=False)
    if res.returncode != 0 or "ALIS_INTERGRATION_SR_ENGINE_PASS" not in res.stdout:
        print(res.stdout, file=sys.stderr)
        print(res.stderr, file=sys.stderr)
        raise AssertionError("Alis-Intergration SpacedRepetitionEngine verification failed")


def verify_qml_contracts() -> None:
    sr_qml = (ROOT / "plugins" / "spaced_repetition" / "modules" / "dashboard" / "DashboardSpacedRepetition.qml").read_text(encoding="utf-8")
    sr_service = (ROOT / "plugins" / "spaced_repetition" / "services" / "SpacedRepetition.qml").read_text(encoding="utf-8")
    sr_settings = (ROOT / "plugins" / "spaced_repetition" / "modules" / "settings" / "DashboardSpacedRepetitionSettings.qml").read_text(encoding="utf-8")

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
        'function maskedClozeMeaningCue(card): string',
        'maskedClozeMeaningCue(root.backend.currentCard)',
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
