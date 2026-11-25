#!/usr/bin/env node
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const crypto = require('node:crypto');
const root = path.resolve(__dirname, '..');
function load(name) {
    const context = vm.createContext({});
    vm.runInContext(fs.readFileSync(path.join(root, 'plugins', 'spaced_repetition', 'services', name + '.js'), 'utf8')
        .replace(/^\.pragma.*$/mg, ''), context);
    return context;
}
const prompts = load('SpacedRepetitionPrompts');
const corpus = load('SpacedRepetitionEssential4000');
const sha = value => crypto.createHash('sha256').update(value).digest('hex');
let checks = 0;
function check(value, label) { checks++; assert.ok(value, label); }
for (const [raw, card, expected] of [
    ['An advantage is helpful.', {term: 'advantage'}, 'An [...] is helpful.'],
    ['Choice and choices; choicest is distinct.', {term: 'choice'}, '[...] and [...]; choicest is distinct.'],
    ['Study, studies, studied; sturdy.', {term: 'study'}, '[...], [...], [...]; sturdy.'],
    ['Make and making; remake.', {term: 'make'}, '[...] and [...]; remake.'],
    ['Äpfel sind Früchte.', {term: 'Äpfel'}, '[...] sind Früchte.'],
    ['der Baum und Bäume', {term: 'der Baum', clozeText: '{{c1::Bäume}}'}, '[...] und [...]'],
    ['C++ and C++17 are different.', {term: 'C++'}, '[...] and C++17 are different.'],
    ['I am ready.', {term: 'I'}, '[...] am ready.'],
    ['There is a thin something.', {term: 'thin'}, 'There is a [...] something.'],
    ['[answer] answer', {term: 'alias', clozeText: '{{c1::answer::answer}}'}, '[[...]] [...]']
]) {
    const before = JSON.stringify(card);
    check(prompts.maskAnswer(raw, card, false) === expected, 'mask: ' + raw);
    check(prompts.maskAnswer(raw, card, true) === raw, 'revealed original: ' + raw);
    check(JSON.stringify(card) === before, 'card never mutated');
}
const letter = 'A-Za-z0-9_\\u00c0-\\u02af\\u0300-\\u036f\\u1e00-\\u1eff';
function containsTerm(text, term) {
    const escaped = term.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    return new RegExp('(^|[^' + letter + '])' + escaped + '(?=$|[^' + letter + '])', 'i').test(text);
}
function audit(cards) {
    const before = sha(JSON.stringify(cards));
    const ids = new Set();
    let originalLeaks = 0, maskedLeaks = 0, missingDefinitions = 0, clozeMissingTargets = 0;
    for (const card of cards) {
        check(!ids.has(card.id), 'unique id: ' + card.id); ids.add(card.id);
        const word = card.word || card.term || card.headword || card.front || '';
        const definition = card.definitionEn || card.back || card.meaning || '';
        if (!definition.trim()) missingDefinitions++;
        if (containsTerm(definition, word)) originalLeaks++;
        const masked = prompts.maskAnswer(definition, card, false);
        if (containsTerm(masked, word)) maskedLeaks++;
        check(prompts.maskAnswer(definition, card, true) === definition, 'full definition restored: ' + card.id);
        if (card.clozeText && !/\{\{c\d+::[^}]+\}\}/.test(card.clozeText)) clozeMissingTargets++;
    }
    check(sha(JSON.stringify(cards)) === before, 'all saved fields unchanged');
    check(maskedLeaks === 0, 'no exact answer leaks');
    return {cards: cards.length, originalLeaks, maskedLeaks, missingDefinitions, clozeMissingTargets, unchanged: true};
}
const result = {canonical: audit(Object.keys(corpus.CARDS_BY_ID).map(id => corpus.lookupByCardId(id)))};
// Optional read-only audit of existing data; receipts contain counts, never private text.
if (process.argv[2]) {
    const filename = process.argv[2], bytes = fs.readFileSync(filename);
    result.persisted = audit(JSON.parse(bytes).cards);
    check(sha(fs.readFileSync(filename)) === sha(bytes), 'persisted bytes unchanged');
}
result.checks = checks;
console.log(JSON.stringify(result, null, 2));
