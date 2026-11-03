pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.abyss.looks

Item {
    id: root
    objectName: "dashboardSpacedRepetition"
    focus: true

    property bool presentationActive: false
    property var backend: SpacedRepetition

    // Sub-navigation: "study" | "capture" | "library"
    property string subTab: "study"
    property alias activeSubTab: root.subTab
    property string librarySearch: ""
    onLibrarySearchChanged: {
        if (root.backend && root.backend.searchQuery !== root.librarySearch)
            root.backend.searchQuery = root.librarySearch
        if (librarySearchField && librarySearchField.text !== root.librarySearch)
            librarySearchField.text = root.librarySearch
    }
    property bool libraryLeechesOnly: false

    // Study session UI state
    property bool answerRevealed: false
    onAnswerRevealedChanged: {
        if (root.backend && root.backend.cardRevealed !== root.answerRevealed)
            root.backend.cardRevealed = root.answerRevealed
    }
    readonly property bool isMultipleChoiceMode: root.backend.studyMode === "mc" || root.backend.studyMode === "rmc"
    property var multipleChoiceOptions: []
    property int pendingChoiceIndex: -1
    property int selectedChoiceIndex: -1
    property string typedClozeAttempt: ""
    property string clozeCheckState: "" // "" | "exact" | "close" | "miss"
    property string statusBannerText: ""

    // Smart Composer state
    property string composerCategory: "vocabulary"
    property string composerLanguage: ""
    property string composerDeck: ""
    property string composerFront: ""
    property string composerBack: ""
    property string composerExample: ""
    property string composerPhonetics: ""
    property string composerPos: ""
    property string composerGender: ""
    property string composerPlural: ""
    property string composerCefrOverride: ""
    property string composerSynonyms: ""
    property string composerAntonyms: ""
    property string composerNotes: ""
    property bool composerShowManualOverrides: false
    property bool composerBackUserEdited: false
    property bool composerExampleUserEdited: false
    property string bulkInputText: ""
    property bool bulkShowSyntaxGuide: false

    readonly property bool abyss: Config.options?.panelFamily === "abyss"
    readonly property bool alisEverywhere: Appearance.alisEverywhere
    readonly property bool auroraEverywhere: Appearance.auroraEverywhere

    // Match DashCard.qml surface & border tokens so cards blend seamlessly with the rest of the Dashboard
    readonly property color colSurface: abyss
        ? AbyssStyle.contentLayer
        : Appearance.angelEverywhere ? Appearance.angel.colGlassCard
        : alisEverywhere ? Appearance.alis.colLayer1
        : auroraEverywhere ? Appearance.aurora.colSubSurface
        : Appearance.colors.colLayer1
    readonly property color colSurfaceElevated: abyss
        ? Qt.alpha(AbyssStyle.textColor, 0.06)
        : Appearance.angelEverywhere ? Appearance.angel.colGlassCardHover
        : alisEverywhere ? Appearance.alis.colLayer2
        : Appearance.colors.colLayer2
    readonly property color colBorder: Qt.alpha(root.colText, 0.07)
    readonly property color colText: abyss
        ? (Appearance.m3colors.darkmode ? AbyssStyle.textColor : "#000000")
        : Appearance.angelEverywhere ? Appearance.angel.colText
        : alisEverywhere ? Appearance.alis.colText
        : Appearance.colors.colOnLayer0
    readonly property color colSubtext: abyss
        ? (Appearance.m3colors.darkmode ? AbyssStyle.textColorMuted : Qt.alpha("#000000", 0.66))
        : Appearance.angelEverywhere ? Appearance.angel.colTextSecondary
        : alisEverywhere ? Appearance.alis.colTextSecondary
        : Appearance.colors.colSubtext

    readonly property var draftPreview: root.backend.analyzeDraft({
        front: root.composerFront,
        example: root.composerExampleUserEdited ? root.composerExample : "",
        category: root.composerCategory,
        language: root.composerLanguage || (root.backend.options?.defaultLanguage ?? "en"),
        deck: root.composerDeck,
        phonetics: root.composerPhonetics,
        pos: root.composerPos,
        gender: root.composerGender,
        plural: root.composerPlural,
        cefrLevel: root.composerCefrOverride,
        lookupSnapshot: root.backend.lastLookupResult,
        synonyms: root.composerSynonyms.trim().length > 0
            ? root.composerSynonyms.split(",").map(s => s.trim()).filter(Boolean)
            : null,
        antonyms: root.composerAntonyms.trim().length > 0
            ? root.composerAntonyms.split(",").map(s => s.trim()).filter(Boolean)
            : null
    })
    readonly property string draftAutoCefr: String(root.draftPreview?.cefrLevel ?? "")
    onDraftPreviewChanged: root.applyAutoSuggestionsFromDraft()

    readonly property var bulkPreviewCards: root.subTab === "capture" && root.bulkInputText.trim().length > 0
        ? root.backend.previewQuickText(
            root.bulkInputText,
            root.composerDeck.trim(),
            root.composerLanguage || (root.backend.options?.defaultLanguage ?? "en"),
            root.composerCategory || "vocabulary"
        )
        : []

    readonly property var filteredLibraryCards: {
        const list = Array.from(root.backend.cards ?? [])
        const q = String(root.librarySearch || root.backend.searchQuery || "").trim().toLowerCase()
        const cat = String(root.backend.selectedCategory ?? "all").toLowerCase()
        const lang = String(root.backend.selectedLanguage ?? "all").toLowerCase()
        const cefr = String(root.backend.selectedCefrLevel ?? "all").toUpperCase()
        const deck = root.backend.selectedDeck
        const onlyLeeches = root.libraryLeechesOnly || root.backend.leechesOnly
        return list.filter(card => {
            if (!card) return false
            if (cat !== "all" && card.category !== cat) return false
            if (lang !== "all" && card.language !== lang) return false
            if (cefr !== "ALL" && String(card.cefrLevel ?? "").toUpperCase() !== cefr) return false
            if (deck !== "all" && card.deck !== deck) return false
            if (onlyLeeches && !card.isLeech && (Number(card.lapses) || 0) < (root.backend.options?.leechThreshold ?? 6)) return false
            if (!q.length) return true
            return String(card.front ?? "").toLowerCase().includes(q)
                || String(card.term ?? "").toLowerCase().includes(q)
                || String(card.back ?? "").toLowerCase().includes(q)
                || String(card.definitionEn ?? "").toLowerCase().includes(q)
                || String(card.meaningVi ?? "").toLowerCase().includes(q)
                || String(card.example ?? "").toLowerCase().includes(q)
                || String(card.cefrLevel ?? "").toLowerCase().includes(q)
                || String(card.deck ?? "").toLowerCase().includes(q)
                || String(card.morphologyText ?? "").toLowerCase().includes(q)
                || (card.collocations ?? []).some(c => String(c).toLowerCase().includes(q))
        })
    }

    function formatCardMorphology(card): string {
        if (!card) return ""
        if (typeof card.morphologyText === "string" && card.morphologyText.trim().length > 0)
            return card.morphologyText.trim()
        return root.backend.formatMorphology(card)
    }

    function escapeHtml(raw): string {
        return String(raw ?? "")
            .replace(/&/g, "&amp;")
            .replace(/</g, "&lt;")
            .replace(/>/g, "&gt;")
    }

    function formatContextExampleRich(card, revealed): string {
        if (!card) return ""
        const rawCloze = String(card.clozeText || card.example || "").trim()
        if (!rawCloze.length) return ""
        const highlightColor = "#38bdf8"
        const maskColor = "#94a3b8"
        if (/\{\{c\d+::/.test(rawCloze)) {
            const escaped = root.escapeHtml(rawCloze)
            return escaped.replace(/\{\{c\d+::([^:}]+)(?:::([^}]+))?\}\}/g, (_, answer, hint) => {
                if (revealed)
                    return `<b><font color="${highlightColor}"><u>${answer.trim()}</u></font></b>`
                let safeHint = hint ? hint.trim() : ""
                if (safeHint.includes("—"))
                    safeHint = safeHint.split("—")[0].trim()
                else if (safeHint.includes(" - "))
                    safeHint = safeHint.split(" - ")[0].trim()
                const label = safeHint ? `[ ${safeHint} ]` : "[ ... ]"
                return `<b><font color="${maskColor}">${label}</font></b>`
            })
        }
        const plain = root.escapeHtml(card.example || rawCloze)
        const term = String(card.headword || card.term || card.front || "").replace(/^(der|die|das|sich)\s+/i, "").trim()
        if (!term.length) return plain
        const escTerm = term.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
        const re = new RegExp(`(\\b${escTerm}[a-zA-ZäöüÄÖÜß]{0,3}\\b)`, "gi")
        if (revealed)
            return plain.replace(re, `<b><font color="${highlightColor}"><u>$1</u></font></b>`)
        return plain.replace(re, `<b><font color="${maskColor}">[ ... ]</font></b>`)
    }

    function parseCollocation(raw): var {
        const clean = String(raw ?? "").replace(/\*+/g, "").trim()
        if (!clean.length) return { phrase: "", gloss: "" }
        const sepMatch = clean.match(/^(.+?)\s+(?:—|–|-)\s+(.+)$/)
        if (sepMatch) {
            return {
                phrase: sepMatch[1].trim(),
                gloss: sepMatch[2].trim()
            }
        }
        return { phrase: clean, gloss: "" }
    }

    function cefrColor(level): color {
        switch (String(level ?? "").toUpperCase()) {
        case "A1": return "#10b981"
        case "A2": return "#84cc16"
        case "B1": return "#eab308"
        case "B2": return "#f97316"
        case "C1": return "#f43f5e"
        case "C2": return "#a855f7"
        default: return Appearance.colors.colPrimary
        }
    }

    function genderColor(article): color {
        const lower = String(article ?? "").toLowerCase()
        if (lower === "der") return "#3b82f6"
        if (lower === "die") return "#ec4899"
        if (lower === "das") return "#10b981"
        return Appearance.colors.colPrimary
    }

    function languageLabel(code): string {
        if (code === "en") return "EN"
        if (code === "de") return "DE"
        if (code === "general") return Translation.tr("General")
        return String(code ?? "").toUpperCase()
    }

    function formatPosLabel(posCode): string {
        const p = String(posCode ?? "").trim().toLowerCase()
        if (p === "noun" || p === "n") return Translation.tr("Noun")
        if (p === "verb" || p === "v") return Translation.tr("Verb")
        if (p === "adj" || p === "adjective") return Translation.tr("Adjective")
        if (p === "adv" || p === "adverb") return Translation.tr("Adverb")
        if (p === "phrase") return Translation.tr("Phrase")
        if (p === "idiom") return Translation.tr("Idiom")
        if (p === "word") return Translation.tr("Term")
        return p.length > 0 ? (p.charAt(0).toUpperCase() + p.slice(1)) : ""
    }

    function storeBrowserState(): void {
        GlobalStates.dashboardSpacedRepetitionBrowser = {
            subTab: root.subTab,
            studyMode: root.backend.studyMode,
            category: root.backend.selectedCategory,
            language: root.backend.selectedLanguage,
            cefrLevel: root.backend.selectedCefrLevel,
            deck: root.backend.selectedDeck
        }
    }

    function restoreBrowserState(): void {
        const saved = GlobalStates.dashboardSpacedRepetitionBrowser
        if (!saved || typeof saved !== "object") return
        if (typeof saved.subTab === "string" && ["study", "capture", "library"].includes(saved.subTab))
            root.subTab = saved.subTab
        if (typeof saved.studyMode === "string" && ["flashcard", "reverse", "mc", "rmc", "cloze"].includes(saved.studyMode))
            root.backend.studyMode = saved.studyMode
        if (typeof saved.category === "string")
            root.backend.selectedCategory = saved.category
        if (typeof saved.language === "string")
            root.backend.selectedLanguage = saved.language
        if (typeof saved.cefrLevel === "string")
            root.backend.selectedCefrLevel = saved.cefrLevel
        if (typeof saved.deck === "string")
            root.backend.selectedDeck = saved.deck
    }

    function toMultipleChoiceOption(c, targetId): var {
        if (!c) return null
        return {
            id: String(c.id ?? ""),
            front: String(c.front || c.headword || c.term || ""),
            headword: String(c.headword || c.term || c.front || ""),
            gender: String(c.gender || c.article || ""),
            phonetics: String(c.phonetics || c.phonetic || ""),
            pos: String(c.pos || ""),
            cefrLevel: String(c.cefrLevel || c.level || ""),
            definitionEn: String(c.definitionEn || c.back || c.meaning || ""),
            meaningVi: String(c.meaningVi || ""),
            isCorrect: String(c.id ?? "") === String(targetId ?? "")
        }
    }

    function rebuildMultipleChoiceOptions(): void {
        const target = root.backend?.currentCard
        if (!target) {
            root.multipleChoiceOptions = []
            root.selectedChoiceIndex = -1
            return
        }
        const allCards = Array.from(root.backend?.cards ?? [])
        const targetId = String(target.id ?? "")
        const usedFronts = [String(target.front || target.term || "").trim().toLowerCase()]
        const usedDefs = [String(target.definitionEn || target.back || "").trim().toLowerCase()]

        const sameLangAndCat = []
        const sameCat = []
        const others = []
        for (const c of allCards) {
            if (!c || String(c.id ?? "") === targetId) continue
            const f = String(c.front || c.term || "").trim()
            const d = String(c.definitionEn || c.back || "").trim()
            if (!f.length || !d.length) continue
            if (c.category === target.category && c.language === target.language)
                sameLangAndCat.push(c)
            else if (c.category === target.category)
                sameCat.push(c)
            else
                others.push(c)
        }

        const shuffle = arr => {
            const copy = arr.slice()
            for (let i = copy.length - 1; i > 0; i--) {
                const j = Math.floor(Math.random() * (i + 1))
                const tmp = copy[i]
                copy[i] = copy[j]
                copy[j] = tmp
            }
            return copy
        }

        const distractors = []
        const candidatePool = [...shuffle(sameLangAndCat), ...shuffle(sameCat), ...shuffle(others)]
        for (const cand of candidatePool) {
            if (distractors.length >= 3) break
            const fKey = String(cand.front || cand.term || "").trim().toLowerCase()
            const dKey = String(cand.definitionEn || cand.back || "").trim().toLowerCase()
            if (usedFronts.includes(fKey) || usedDefs.includes(dKey)) continue
            usedFronts.push(fKey)
            usedDefs.push(dKey)
            distractors.push(root.toMultipleChoiceOption(cand, targetId))
        }

        const combined = shuffle([root.toMultipleChoiceOption(target, targetId), ...distractors].filter(Boolean))
        root.pendingChoiceIndex = -1
        root.selectedChoiceIndex = -1
        root.multipleChoiceOptions = combined
    }

    function stageMultipleChoiceOption(index): bool {
        if (!root.isMultipleChoiceMode || root.answerRevealed) return false
        if (index < 0 || index >= root.multipleChoiceOptions.length) return false
        root.pendingChoiceIndex = index
        root.focusPrimarySurface()
        return true
    }

    function selectMultipleChoiceOption(index): void {
        if (index < 0 || index >= root.multipleChoiceOptions.length) return
        root.pendingChoiceIndex = index
        root.selectedChoiceIndex = index
        root.answerRevealed = true
        root.focusPrimarySurface()
    }

    function resetCardInteraction(): void {
        root.answerRevealed = false
        root.pendingChoiceIndex = -1
        root.selectedChoiceIndex = -1
        root.typedClozeAttempt = ""
        if (clozeInputField.text !== "")
            clozeInputField.text = ""
        root.clozeCheckState = ""
        root.rebuildMultipleChoiceOptions()
        if (root.presentationActive && root.visible && root.subTab === "study")
            root.focusPrimarySurface()
    }

    function checkClozeAttempt(): void {
        const card = root.backend.currentCard
        if (!card) return
        const rawActual = (root.typedClozeAttempt || clozeInputField.text || "").trim().toLowerCase()
        const actualStripped = rawActual.replace(/^(der|die|das|sich)\s+/i, "").trim()
        if (!rawActual.length) {
            root.clozeCheckState = ""
            root.answerRevealed = true
            root.forceActiveFocus()
            return
        }

        const candidates = []
        const addCandidate = val => {
            const clean = String(val ?? "").trim().toLowerCase()
            if (clean && !candidates.includes(clean))
                candidates.push(clean)
            const stripped = clean.replace(/^(der|die|das|sich)\s+/i, "").trim()
            if (stripped && !candidates.includes(stripped))
                candidates.push(stripped)
        }
        const clozeTargets = Array.from(root.backend.extractClozeTargets(card) ?? [])
        for (const t of clozeTargets)
            addCandidate(t)
        if (clozeTargets.length > 1)
            addCandidate(clozeTargets.join(" "))
        addCandidate(card.headword)
        addCandidate(card.front)
        addCandidate(card.term)

        if (candidates.includes(rawActual) || (actualStripped.length > 0 && candidates.includes(actualStripped))) {
            root.clozeCheckState = "exact"
        } else if (actualStripped.length >= 3 && candidates.some(c => c.length >= 4 && (c.startsWith(actualStripped) || actualStripped.startsWith(c)))) {
            root.clozeCheckState = "close"
        } else {
            root.clozeCheckState = "miss"
        }
        root.answerRevealed = true
        root.forceActiveFocus()
    }

    function submitReviewRating(rating): void {
        if (!root.backend.hasActiveCard) return
        root.backend.submitRating(rating)
        root.resetCardInteraction()
    }

    function syncComposerFieldsFromState(): void {
        if (composerFrontField.text !== root.composerFront) composerFrontField.text = root.composerFront
        if (composerBackField.text !== root.composerBack) composerBackField.text = root.composerBack
        if (composerExampleField.text !== root.composerExample) composerExampleField.text = root.composerExample
        if (composerDeckField.text !== root.composerDeck) composerDeckField.text = root.composerDeck
        if (composerPhoneticsField.text !== root.composerPhonetics) composerPhoneticsField.text = root.composerPhonetics
        if (composerPosField.text !== root.composerPos) composerPosField.text = root.composerPos
        if (composerCefrField.text !== root.composerCefrOverride) composerCefrField.text = root.composerCefrOverride
        if (composerSynonymsField.text !== root.composerSynonyms) composerSynonymsField.text = root.composerSynonyms
        if (composerAntonymsField.text !== root.composerAntonyms) composerAntonymsField.text = root.composerAntonyms
    }

    function applyAutoSuggestionsFromDraft(): void {
        const preview = root.draftPreview
        if (!preview || !root.composerFront.trim().length) return
        const nextBack = String(preview.meaning ?? "")
        if (!root.composerBackUserEdited && nextBack.length > 0 && root.composerBack !== nextBack) {
            root.composerBack = nextBack
        }
        const nextEx = String(preview.example ?? "")
        if (!root.composerExampleUserEdited && nextEx.length > 0 && root.composerExample !== nextEx) {
            root.composerExample = nextEx
        }
        root.syncComposerFieldsFromState()
    }

    Timer {
        id: autoLookupTimer
        interval: 420
        repeat: false
        onTriggered: {
            const term = root.composerFront.trim()
            if (!term.length || root.composerCategory !== "vocabulary")
                return
            root.applyAutoSuggestionsFromDraft()
            if (root.backend.options?.autoLookupOnline) {
                root.backend.lookupWordOnline(
                    term,
                    root.composerLanguage || (root.backend.options?.defaultLanguage ?? "en")
                )
            }
        }
    }

    onComposerFrontChanged: {
        if (!root.composerFront.trim().length) {
            autoLookupTimer.stop()
            if (!root.composerBackUserEdited) root.composerBack = ""
            if (!root.composerExampleUserEdited) root.composerExample = ""
            root.syncComposerFieldsFromState()
            return
        }
        root.applyAutoSuggestionsFromDraft()
        autoLookupTimer.restart()
    }

    function submitComposerCard(): void {
        const front = root.composerFront.trim()
        let back = (root.composerBack.trim() || String(root.draftPreview?.meaning ?? "").trim())
        if (!front.length) return
        if (!back.length) {
            if (root.composerCategory === "vocabulary") {
                back = "..."
            } else {
                return
            }
        }
        const syns = root.composerSynonyms.trim().length > 0
            ? root.composerSynonyms.split(",").map(s => s.trim()).filter(Boolean)
            : Array.from(root.draftPreview?.synonyms ?? [])
        const ants = root.composerAntonyms.trim().length > 0
            ? root.composerAntonyms.split(",").map(s => s.trim()).filter(Boolean)
            : Array.from(root.draftPreview?.antonyms ?? [])
        const created = root.backend.addCard({
            front: front,
            back: back,
            example: root.composerExample.trim() || String(root.draftPreview?.example ?? "").trim(),
            category: root.composerCategory,
            language: root.composerLanguage || String(root.draftPreview?.language ?? "") || (root.backend.options?.defaultLanguage ?? "en"),
            deck: root.composerDeck.trim(),
            phonetics: root.composerPhonetics.trim() || String(root.draftPreview?.phonetics ?? "").trim(),
            pos: root.composerPos.trim() || String(root.draftPreview?.pos ?? "").trim(),
            gender: root.composerGender.trim() || String(root.draftPreview?.gender ?? "").trim(),
            plural: root.composerPlural.trim() || String(root.draftPreview?.plural ?? "").trim(),
            cefrLevel: root.composerCefrOverride.trim() || String(root.draftPreview?.cefrLevel ?? "").trim(),
            morphology: Array.from(root.draftPreview?.morphology ?? []),
            morphologyText: String(root.draftPreview?.morphologyText ?? "").trim(),
            synonyms: syns,
            antonyms: ants,
            notes: root.composerNotes.trim()
        })
        if (created) {
            root.statusBannerText = Translation.tr("Added \"%1\" (%2)").arg(created.front).arg(created.cefrLevel || "B1")
            root.composerFront = ""
            root.composerBack = ""
            root.composerExample = ""
            root.composerPhonetics = ""
            root.composerPos = ""
            root.composerGender = ""
            root.composerPlural = ""
            root.composerCefrOverride = ""
            root.composerSynonyms = ""
            root.composerAntonyms = ""
            root.composerNotes = ""
            root.composerBackUserEdited = false
            root.composerExampleUserEdited = false
            root.syncComposerFieldsFromState()
        }
    }

    function submitBulkImport(): void {
        if (!root.bulkInputText.trim().length) return
        const count = root.backend.importQuickText(
            root.bulkInputText,
            root.composerDeck.trim(),
            root.composerLanguage || (root.backend.options?.defaultLanguage ?? "en"),
            root.composerCategory || "vocabulary"
        )
        if (count > 0) {
            root.statusBannerText = Translation.tr("Imported %1 cards with automatic CEFR & cloze syntax").arg(count)
            root.bulkInputText = ""
            if (bulkInputArea.text !== "")
                bulkInputArea.text = ""
        }
    }

    function loadSampleBatch(): void {
        const sample = [
            "ubiquitous - present, appearing, or found everywhere // Smartphones have become ubiquitous in modern life.",
            "die Herausforderung - challenge; demanding task // Der Klimawandel ist eine globale Herausforderung.",
            "alleviate - make suffering, deficiency, or a problem less severe // Measures to alleviate traffic congestion.",
            "nachhaltig - sustainable; lasting // Wir brauchen eine nachhaltige Energiepolitik.",
            "What is the spacing effect in cognitive psychology? :: Long-term retention improves when study sessions are spaced apart rather than massed."
        ].join("\n")
        root.bulkInputText = sample
        if (bulkInputArea.text !== sample)
            bulkInputArea.text = sample
    }

    function handleEscape(): bool {
        if (root.subTab === "capture" && root.bulkShowSyntaxGuide) {
            root.bulkShowSyntaxGuide = false
            return true
        }
        if (root.subTab === "capture" && root.composerShowManualOverrides) {
            root.composerShowManualOverrides = false
            return true
        }
        return false
    }

    function panHorizontally(_amount): bool {
        return false
    }

    readonly property bool textInputFocused: clozeInputField.activeFocus
        || sidebarQuickInput.activeFocus
        || composerFrontField.activeFocus
        || composerBackField.activeFocus
        || composerExampleField.activeFocus
        || composerDeckField.activeFocus
        || composerPhoneticsField.activeFocus
        || composerPosField.activeFocus
        || composerCefrField.activeFocus
        || composerSynonymsField.activeFocus
        || composerAntonymsField.activeFocus
        || bulkInputArea.activeFocus
        || librarySearchField.activeFocus
    readonly property bool windowTextInputFocused: {
        const item = root.Window.activeFocusItem
        return Boolean(item && item.visible && item.enabled && item.readOnly === false
            && item.cursorPosition !== undefined)
    }
    readonly property bool studyShortcutsActive: root.presentationActive
        && root.visible
        && root.subTab === "study"
        && !root.textInputFocused
        && !root.windowTextInputFocused
    property double _lastShortcutMs: 0

    function focusPrimarySurface(): void {
        if (!root.textInputFocused)
            root.forceActiveFocus()
    }

    function triggerStudyShortcut(action): bool {
        if (!root.presentationActive || !root.visible || root.subTab !== "study") return false
        if (root.textInputFocused || root.windowTextInputFocused) return false
        const now = Date.now()
        if (now - root._lastShortcutMs < 40) return true
        if (action === "undo") {
            if (root.backend.undoLastReview()) {
                root._lastShortcutMs = now
                root.resetCardInteraction()
                root.focusPrimarySurface()
                return true
            }
            return false
        }
        if (!root.backend.hasActiveCard) return false
        if (action === "space") {
            if (!root.answerRevealed) {
                if (root.isMultipleChoiceMode) {
                    if (root.pendingChoiceIndex >= 0 && root.pendingChoiceIndex < root.multipleChoiceOptions.length) {
                        root._lastShortcutMs = now
                        root.selectMultipleChoiceOption(root.pendingChoiceIndex)
                        return true
                    }
                    root.focusPrimarySurface()
                    return true
                }
                root._lastShortcutMs = now
                root.answerRevealed = true
            }
            root.focusPrimarySurface()
            return true
        }
        if (action === "enter") {
            if (!root.answerRevealed && !root.isMultipleChoiceMode) {
                root._lastShortcutMs = now
                root.answerRevealed = true
                root.focusPrimarySurface()
                return true
            }
            return false
        }
        if (action.startsWith("pick-") && !root.answerRevealed && root.isMultipleChoiceMode) {
            const idx = parseInt(action.slice(5), 10)
            if (root.stageMultipleChoiceOption(idx)) {
                root._lastShortcutMs = now
                return true
            }
            return false
        }
        if (action === "mode") {
            root._lastShortcutMs = now
            const modes = ["flashcard", "reverse", "mc", "rmc", "cloze"]
            const next = modes[(modes.indexOf(root.backend.studyMode) + 1) % modes.length]
            root.backend.studyMode = next
            root.resetCardInteraction()
            root.storeBrowserState()
            root.focusPrimarySurface()
            return true
        }
        if (root.answerRevealed && (action === "again" || action === "hard" || action === "good" || action === "easy")) {
            root._lastShortcutMs = now
            root.submitReviewRating(action)
            root.focusPrimarySurface()
            return true
        }
        return false
    }

    onSubTabChanged: {
        root.storeBrowserState()
        if (root.presentationActive)
            root.focusPrimarySurface()
    }
    onPresentationActiveChanged: {
        if (root.presentationActive && root.subTab === "study")
            root.focusPrimarySurface()
    }
    onVisibleChanged: {
        if (root.visible && root.presentationActive && root.subTab === "study")
            Qt.callLater(() => root.focusPrimarySurface())
    }

    Connections {
        target: root.backend
        function onCurrentCardChanged(): void {
            root.resetCardInteraction()
        }
        function onCardsChanged(): void {
            if (root.multipleChoiceOptions.length < 4)
                root.rebuildMultipleChoiceOptions()
        }
        function onStudyModeChanged(): void {
            root.rebuildMultipleChoiceOptions()
        }
        function onCardRevealedChanged(): void {
            if (root.answerRevealed !== root.backend.cardRevealed)
                root.answerRevealed = root.backend.cardRevealed
        }
        function onSearchQueryChanged(): void {
            if (root.librarySearch !== root.backend.searchQuery)
                root.librarySearch = root.backend.searchQuery
        }
        function onOnlineLookupFinished(result): void {
            if (!result || !result.found) {
                root.statusBannerText = Translation.tr("Offline CEFR heuristic used")
                return
            }
            const currentHead = String(root.draftPreview?.word || root.composerFront.trim().replace(/^(der|die|das|sich)\s+/i, "")).trim().toLowerCase()
            const resultHead = String(result.word || result.headword || "").trim().toLowerCase()
            if (root.subTab === "capture" && currentHead.length > 0 && (!resultHead.length || currentHead === resultHead)) {
                if (result.definition && (!root.composerBackUserEdited || !root.composerBack.trim().length))
                    root.composerBack = result.definition
                if (result.example && (!root.composerExampleUserEdited || !root.composerExample.trim().length))
                    root.composerExample = result.example
                root.syncComposerFieldsFromState()
            }
            root.statusBannerText = Translation.tr("Resolved %1 (%2)").arg(result.cefrLevel || "B1").arg(result.cefrSource || "Dictionary")
        }
    }

    Component.onCompleted: {
        root.restoreBrowserState()
        root.rebuildMultipleChoiceOptions()
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape && root.handleEscape()) {
            event.accepted = true
            return
        }
        if (!root.presentationActive || root.subTab !== "study") return
        if (root.textInputFocused || root.windowTextInputFocused) return
        if (event.modifiers & Qt.ControlModifier && event.key === Qt.Key_Z) {
            if (root.triggerStudyShortcut("undo"))
                event.accepted = true
            return
        }
        if (!root.backend.hasActiveCard) return
        if (event.key === Qt.Key_Space) {
            if (root.triggerStudyShortcut("space"))
                event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (root.triggerStudyShortcut("enter"))
                event.accepted = true
        } else if (!root.answerRevealed && root.isMultipleChoiceMode && (event.key === Qt.Key_1 || event.key === Qt.Key_A)) {
            if (root.triggerStudyShortcut("pick-0"))
                event.accepted = true
        } else if (!root.answerRevealed && root.isMultipleChoiceMode && (event.key === Qt.Key_2 || event.key === Qt.Key_B)) {
            if (root.triggerStudyShortcut("pick-1"))
                event.accepted = true
        } else if (!root.answerRevealed && root.isMultipleChoiceMode && (event.key === Qt.Key_3 || event.key === Qt.Key_C)) {
            if (root.triggerStudyShortcut("pick-2"))
                event.accepted = true
        } else if (!root.answerRevealed && root.isMultipleChoiceMode && (event.key === Qt.Key_4 || event.key === Qt.Key_D)) {
            if (root.triggerStudyShortcut("pick-3"))
                event.accepted = true
        } else if (root.answerRevealed && event.key === Qt.Key_0) {
            if (root.triggerStudyShortcut("again"))
                event.accepted = true
        } else if (root.answerRevealed && event.key === Qt.Key_1) {
            if (root.triggerStudyShortcut("hard"))
                event.accepted = true
        } else if (root.answerRevealed && event.key === Qt.Key_2) {
            if (root.triggerStudyShortcut("good"))
                event.accepted = true
        } else if (root.answerRevealed && event.key === Qt.Key_3) {
            if (root.triggerStudyShortcut("easy"))
                event.accepted = true
        } else if (event.key === Qt.Key_M && !(event.modifiers & Qt.ControlModifier)) {
            if (root.triggerStudyShortcut("mode"))
                event.accepted = true
        }
    }

    Shortcut {
        sequences: ["Space"]
        context: Qt.WindowShortcut
        autoRepeat: false
        enabled: root.studyShortcutsActive && root.backend.hasActiveCard
        onActivated: root.triggerStudyShortcut("space")
    }
    Shortcut {
        sequences: ["Return", "Enter"]
        context: Qt.WindowShortcut
        autoRepeat: false
        enabled: root.studyShortcutsActive && root.backend.hasActiveCard && !root.answerRevealed && !root.isMultipleChoiceMode
        onActivated: root.triggerStudyShortcut("enter")
    }
    Shortcut {
        sequences: ["0"]
        context: Qt.WindowShortcut
        autoRepeat: false
        enabled: root.studyShortcutsActive && root.backend.hasActiveCard && root.answerRevealed
        onActivated: root.triggerStudyShortcut("again")
    }
    Shortcut {
        sequences: ["1"]
        context: Qt.WindowShortcut
        autoRepeat: false
        enabled: root.studyShortcutsActive && root.backend.hasActiveCard && (root.answerRevealed || root.isMultipleChoiceMode)
        onActivated: root.triggerStudyShortcut(root.answerRevealed ? "hard" : "pick-0")
    }
    Shortcut {
        sequences: ["2"]
        context: Qt.WindowShortcut
        autoRepeat: false
        enabled: root.studyShortcutsActive && root.backend.hasActiveCard && (root.answerRevealed || root.isMultipleChoiceMode)
        onActivated: root.triggerStudyShortcut(root.answerRevealed ? "good" : "pick-1")
    }
    Shortcut {
        sequences: ["3"]
        context: Qt.WindowShortcut
        autoRepeat: false
        enabled: root.studyShortcutsActive && root.backend.hasActiveCard && (root.answerRevealed || root.isMultipleChoiceMode)
        onActivated: root.triggerStudyShortcut(root.answerRevealed ? "easy" : "pick-2")
    }
    Shortcut {
        sequences: ["4"]
        context: Qt.WindowShortcut
        autoRepeat: false
        enabled: root.studyShortcutsActive && root.backend.hasActiveCard && !root.answerRevealed && root.isMultipleChoiceMode
        onActivated: root.triggerStudyShortcut("pick-3")
    }
    Shortcut {
        sequences: ["A"]
        context: Qt.WindowShortcut
        autoRepeat: false
        enabled: root.studyShortcutsActive && root.backend.hasActiveCard && !root.answerRevealed && root.isMultipleChoiceMode
        onActivated: root.triggerStudyShortcut("pick-0")
    }
    Shortcut {
        sequences: ["B"]
        context: Qt.WindowShortcut
        autoRepeat: false
        enabled: root.studyShortcutsActive && root.backend.hasActiveCard && !root.answerRevealed && root.isMultipleChoiceMode
        onActivated: root.triggerStudyShortcut("pick-1")
    }
    Shortcut {
        sequences: ["C"]
        context: Qt.WindowShortcut
        autoRepeat: false
        enabled: root.studyShortcutsActive && root.backend.hasActiveCard && !root.answerRevealed && root.isMultipleChoiceMode
        onActivated: root.triggerStudyShortcut("pick-2")
    }
    Shortcut {
        sequences: ["D"]
        context: Qt.WindowShortcut
        autoRepeat: false
        enabled: root.studyShortcutsActive && root.backend.hasActiveCard && !root.answerRevealed && root.isMultipleChoiceMode
        onActivated: root.triggerStudyShortcut("pick-3")
    }
    Shortcut {
        sequences: ["M"]
        context: Qt.WindowShortcut
        autoRepeat: false
        enabled: root.studyShortcutsActive && root.backend.hasActiveCard
        onActivated: root.triggerStudyShortcut("mode")
    }
    Shortcut {
        sequences: ["Ctrl+Z"]
        context: Qt.WindowShortcut
        autoRepeat: false
        enabled: root.studyShortcutsActive && root.backend.hasActiveCard && root.backend.canUndoReview
        onActivated: root.triggerStudyShortcut("undo")
    }

    component FilterChip: RippleButton {
        id: chip
        releaseAction: () => {
            if (root.subTab === "study")
                Qt.callLater(() => root.focusPrimarySurface())
        }
        property string label: ""
        property string iconName: ""
        property string tooltipText: ""
        property bool activeChip: false
        property color badgeColor: Appearance.colors.colPrimary
        property bool showDot: false
        readonly property bool iconOnly: chip.label.length === 0 && chip.iconName.length > 0
        implicitHeight: 30
        implicitWidth: iconOnly ? 30 : Math.max(30, chipRow.implicitWidth + 20)
        buttonRadius: Appearance.rounding.full
        toggled: activeChip
        colBackground: activeChip
            ? Qt.alpha(chip.badgeColor, 0.16)
            : root.colSurfaceElevated
        colBackgroundHover: activeChip
            ? Qt.alpha(chip.badgeColor, 0.24)
            : Qt.alpha(root.colText, 0.10)
        colBackgroundToggled: Qt.alpha(chip.badgeColor, 0.18)
        colBackgroundToggledHover: Qt.alpha(chip.badgeColor, 0.26)
        Rectangle {
            anchors.fill: parent
            radius: chip.buttonRadius
            color: "transparent"
            border.width: chip.activeChip ? 1 : 0
            border.color: chip.activeChip ? Qt.alpha(chip.badgeColor, 0.45) : "transparent"
        }
        // Qt Controls stretches contentItem to the button's full width. Wrap the
        // actual row inside an Item so anchors.centerIn keeps equal left/right margins.
        contentItem: Item {
            Row {
                id: chipRow
                anchors.centerIn: parent
                spacing: 5
                Rectangle {
                    visible: chip.showDot
                    anchors.verticalCenter: parent.verticalCenter
                    width: 6
                    height: 6
                    radius: 3
                    color: chip.badgeColor
                }
                MaterialSymbol {
                    visible: chip.iconName.length > 0
                    anchors.verticalCenter: parent.verticalCenter
                    text: chip.iconName
                    iconSize: chip.iconOnly ? 17 : 15
                    color: chip.activeChip ? chip.badgeColor : root.colSubtext
                }
                StyledText {
                    visible: chip.label.length > 0
                    anchors.verticalCenter: parent.verticalCenter
                    text: chip.label
                    horizontalAlignment: Text.AlignHCenter
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: chip.activeChip ? Font.DemiBold : Font.Normal
                    color: chip.activeChip ? root.colText : root.colSubtext
                }
            }
        }
        StyledToolTip {
            visible: chip.hovered && chip.tooltipText.length > 0
            text: chip.tooltipText
        }
    }

    component StyledTextField: ToolbarTextField {
        id: styledField
        Layout.fillHeight: false
        implicitHeight: 38
        leftPadding: 12
        rightPadding: 12
        colBackground: root.colSurfaceElevated
        color: root.colText
        placeholderTextColor: root.colSubtext
        selectByMouse: true
        cursorVisible: activeFocus
        background: Rectangle {
            color: styledField.colBackground
            radius: Appearance.rounding.full
            border.width: styledField.activeFocus ? 1.5 : 0
            border.color: styledField.activeFocus ? Appearance.colors.colPrimary : "transparent"
        }
    }

    component MorphologyStrip: Rectangle {
        id: morphPill
        property string morphText: ""
        visible: morphPill.morphText.length > 0
        implicitHeight: 22
        implicitWidth: Math.min(parent ? parent.width : 560, morphRow.implicitWidth + 16)
        radius: 6
        color: Qt.alpha(root.colText, 0.05)
        border.width: 0
        Row {
            id: morphRow
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 8
            spacing: 6
            MaterialSymbol {
                anchors.verticalCenter: parent.verticalCenter
                text: "account_tree"
                iconSize: 13
                color: root.colSubtext
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(Math.max(120, morphPill.width - 28), implicitWidth)
                elide: Text.ElideRight
                text: morphPill.morphText
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.Normal
                color: root.colSubtext
            }
        }
    }

    component DetailTag: Rectangle {
        property string label: ""
        implicitWidth: 38
        implicitHeight: 20
        radius: 5
        color: Qt.alpha(root.colText, 0.06)
        StyledText {
            anchors.centerIn: parent
            text: parent.label
            font.pixelSize: Appearance.font.pixelSize.smallest
            font.weight: Font.Medium
            color: root.colSubtext
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 10

        // 1. Top Navigation & Status Bar
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: topBarLayout.implicitHeight + 16
            radius: Appearance.rounding.small
            color: root.colSurface
            border.width: 0

            RowLayout {
                id: topBarLayout
                anchors.fill: parent
                anchors.margins: 8
                spacing: 8

                // Sub-tab switcher: Study | Capture | Library
                RowLayout {
                    spacing: 6
                    FilterChip {
                        objectName: "srSubTabStudy"
                        iconName: "school"
                        label: Translation.tr("Study") + " · " + (root.backend.studyQueue?.length ?? 0)
                        tooltipText: Translation.tr("Active recall study queue")
                        activeChip: root.subTab === "study"
                        onClicked: root.subTab = "study"
                    }
                    FilterChip {
                        objectName: "srSubTabCapture"
                        iconName: "auto_awesome"
                        label: Translation.tr("Capture")
                        tooltipText: Translation.tr("Smart vocabulary composer & bulk auto-syntax importer")
                        activeChip: root.subTab === "capture"
                        onClicked: root.subTab = "capture"
                    }
                    FilterChip {
                        objectName: "srSubTabLibrary"
                        iconName: "library_books"
                        label: Translation.tr("Library") + " · " + (root.backend.analytics?.total ?? 0)
                        tooltipText: Translation.tr("Browse, search, and manage all cards")
                        activeChip: root.subTab === "library"
                        onClicked: root.subTab = "library"
                    }
                }

                Item { Layout.fillWidth: true }

                // Status message toast pill
                Rectangle {
                    visible: root.statusBannerText.length > 0
                    implicitHeight: 28
                    implicitWidth: Math.min(280, bannerLabel.implicitWidth + 20)
                    radius: Appearance.rounding.full
                    color: Qt.alpha(Appearance.colors.colPrimary, 0.14)
                    StyledText {
                        id: bannerLabel
                        anchors.centerIn: parent
                        width: parent.width - 16
                        elide: Text.ElideRight
                        horizontalAlignment: Text.AlignHCenter
                        text: root.statusBannerText
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colPrimary
                    }
                }

                // Compact Streak pill (icon + number)
                Rectangle {
                    id: streakBadge
                    implicitHeight: 30
                    implicitWidth: streakRow.implicitWidth + 18
                    radius: Appearance.rounding.full
                    color: Qt.alpha("#f97316", 0.12)
                    Row {
                        id: streakRow
                        anchors.centerIn: parent
                        spacing: 4
                        MaterialSymbol {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "local_fire_department"
                            iconSize: 16
                            color: "#f97316"
                        }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "%1d".arg(root.backend.analytics?.streak ?? 0)
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.DemiBold
                            color: root.colText
                        }
                    }
                    HoverHandler { id: streakHover }
                    StyledToolTip {
                        visible: streakHover.hovered
                        text: Translation.tr("Study streak: %1 consecutive days").arg(root.backend.analytics?.streak ?? 0)
                    }
                }

                // Compact Today's reviewed pill (icon + number)
                Rectangle {
                    id: todayBadge
                    implicitHeight: 30
                    implicitWidth: todayRow.implicitWidth + 18
                    radius: Appearance.rounding.full
                    color: root.colSurfaceElevated
                    Row {
                        id: todayRow
                        anchors.centerIn: parent
                        spacing: 4
                        MaterialSymbol {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "check_circle"
                            iconSize: 15
                            color: "#10b981"
                        }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: String(root.backend.todayReviewedCount ?? 0)
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.DemiBold
                            color: root.colText
                        }
                    }
                    HoverHandler { id: todayHover }
                    StyledToolTip {
                        visible: todayHover.hovered
                        text: Translation.tr("Reviewed today: %1 cards").arg(root.backend.todayReviewedCount ?? 0)
                    }
                }

                // Undo Review icon button
                FilterChip {
                    objectName: "srUndoButton"
                    visible: root.backend.canUndoReview
                    iconName: "undo"
                    label: ""
                    tooltipText: Translation.tr("Undo last review (Ctrl+Z)")
                    onClicked: {
                        root.backend.undoLastReview()
                        root.resetCardInteraction()
                    }
                }

                // Boost session icon/compact toggle
                FilterChip {
                    objectName: "srBoostToggleButton"
                    iconName: "bolt"
                    label: root.backend.boostActive
                        ? (root.backend.boostMode === "ahead"
                            ? "+3d"
                            : root.backend.boostMode === "hard"
                            ? Translation.tr("Hard")
                            : Translation.tr("Cram"))
                        : ""
                    tooltipText: root.backend.boostActive
                        ? Translation.tr("Boost active (%1) — click to cycle mode or turn off").arg(root.backend.boostMode)
                        : Translation.tr("Boost Study: practice ahead (+3d), drill hard/leeches, or cram")
                    activeChip: root.backend.boostActive
                    badgeColor: "#f59e0b"
                    onClicked: {
                        if (!root.backend.boostActive) {
                            root.backend.startBoost("ahead")
                        } else if (root.backend.boostMode === "ahead") {
                            root.backend.startBoost("hard")
                        } else if (root.backend.boostMode === "hard") {
                            root.backend.startBoost("cram", Math.max(7, root.backend.boostAheadDays))
                        } else {
                            root.backend.stopBoost()
                        }
                        root.subTab = "study"
                    }
                }

                // Quick shortcut to Spaced Repetition Settings
                FilterChip {
                    objectName: "srOpenSettingsButton"
                    iconName: "tune"
                    label: ""
                    tooltipText: Translation.tr("Spaced Repetition settings")
                    onClicked: GlobalStates.openSettingsSection(AlisIntergration.spacedRepetitionEnabled ? 38 : 22, Translation.tr("Spaced Repetition"))
                }
            }
        }

        // 2. Filter Bar (Icon-first Category, Language, CEFR A1-C2)
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: filterBarLayout.implicitHeight + 14
            radius: Appearance.rounding.small
            color: root.colSurface
            border.width: 0

            RowLayout {
                id: filterBarLayout
                anchors.fill: parent
                anchors.margins: 7
                spacing: 6

                // Category icon filters
                Repeater {
                    model: [
                        { id: "all", tip: Translation.tr("All categories"), icon: "layers" },
                        { id: "vocabulary", tip: Translation.tr("Vocabulary"), icon: "translate" },
                        { id: "knowledge", tip: Translation.tr("Knowledge & Q/A"), icon: "psychology" },
                        { id: "cloze", tip: Translation.tr("Cloze deletion"), icon: "short_text" }
                    ]
                    delegate: FilterChip {
                        required property var modelData
                        label: ""
                        iconName: modelData.icon
                        tooltipText: modelData.tip
                        activeChip: root.backend.selectedCategory === modelData.id
                        onClicked: {
                            root.backend.selectedCategory = modelData.id
                            root.storeBrowserState()
                        }
                    }
                }

                Rectangle { width: 1; Layout.fillHeight: true; Layout.topMargin: 4; Layout.bottomMargin: 4; color: root.colBorder }

                // Language filters
                Repeater {
                    model: [
                        { id: "all", label: "", icon: "language", tip: Translation.tr("All languages") },
                        { id: "en", label: "EN", icon: "", tip: Translation.tr("English") },
                        { id: "de", label: "DE", icon: "", tip: Translation.tr("German (Deutsch)") },
                        { id: "general", label: "", icon: "public", tip: Translation.tr("General knowledge") }
                    ]
                    delegate: FilterChip {
                        required property var modelData
                        label: modelData.label
                        iconName: modelData.icon
                        tooltipText: modelData.tip
                        activeChip: root.backend.selectedLanguage === modelData.id
                        onClicked: {
                            root.backend.selectedLanguage = modelData.id
                            root.storeBrowserState()
                        }
                    }
                }

                Rectangle { width: 1; Layout.fillHeight: true; Layout.topMargin: 4; Layout.bottomMargin: 4; color: root.colBorder }

                // CEFR Level filters (A1 - C2)
                FilterChip {
                    label: Translation.tr("All")
                    tooltipText: Translation.tr("All CEFR levels")
                    activeChip: root.backend.selectedCefrLevel === "all"
                    onClicked: {
                        root.backend.selectedCefrLevel = "all"
                        root.storeBrowserState()
                    }
                }
                Repeater {
                    model: ["A1", "A2", "B1", "B2", "C1", "C2"]
                    delegate: FilterChip {
                        required property string modelData
                        objectName: "srCefrFilter-" + modelData
                        label: modelData
                        tooltipText: Translation.tr("Filter CEFR level %1").arg(modelData)
                        showDot: true
                        badgeColor: root.cefrColor(modelData)
                        activeChip: root.backend.selectedCefrLevel === modelData
                        onClicked: {
                            root.backend.selectedCefrLevel = (root.backend.selectedCefrLevel === modelData ? "all" : modelData)
                            root.storeBrowserState()
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                FilterChip {
                    visible: root.backend.selectedCategory !== "all"
                        || root.backend.selectedLanguage !== "all"
                        || root.backend.selectedCefrLevel !== "all"
                        || root.backend.boostActive
                    iconName: "filter_alt_off"
                    label: ""
                    tooltipText: Translation.tr("Clear active filters")
                    onClicked: {
                        root.backend.clearFilters()
                        root.storeBrowserState()
                    }
                }
            }
        }

        // 3. Main Content Stack
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            // =================================================================
            // SUB-TAB 1: STUDY ARENA
            // =================================================================
            RowLayout {
                anchors.fill: parent
                visible: root.subTab === "study"
                spacing: 12

                // Left / Center Flashcard Surface
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 10

                    // Study Mode Bar (compact icon modes + live telemetry)
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 38
                        radius: Appearance.rounding.small
                        color: root.colSurface
                        border.width: 0

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 6

                            Repeater {
                                model: [
                                    { id: "flashcard", label: Translation.tr("Flashcard Mode (Front → Back)"), icon: "style" },
                                    { id: "reverse", label: Translation.tr("Reverse Recall Mode (Meaning → Term)"), icon: "swap_horiz" },
                                    { id: "mc", label: Translation.tr("Multiple Choice Mode (1 Term → 4 Definitions)"), icon: "quiz" },
                                    { id: "rmc", label: Translation.tr("Reverse Multiple Choice Mode (1 Definition → 4 Terms)"), icon: "checklist" },
                                    { id: "cloze", label: Translation.tr("Cloze / Type-Check Mode"), icon: "edit_note" }
                                ]
                                delegate: FilterChip {
                                    required property var modelData
                                    objectName: "srStudyMode-" + modelData.id
                                    iconName: modelData.icon
                                    label: ""
                                    tooltipText: modelData.label
                                    activeChip: root.backend.studyMode === modelData.id
                                    onClicked: {
                                        root.backend.studyMode = modelData.id
                                        root.resetCardInteraction()
                                        root.storeBrowserState()
                                    }
                                }
                            }

                            StyledText {
                                text: root.backend.studyMode === "reverse"
                                    ? Translation.tr("Reverse Recall")
                                    : root.backend.studyMode === "mc"
                                    ? Translation.tr("Multiple Choice")
                                    : root.backend.studyMode === "rmc"
                                    ? Translation.tr("Reverse MC")
                                    : root.backend.studyMode === "cloze"
                                    ? Translation.tr("Cloze / Type")
                                    : Translation.tr("Flashcard")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.DemiBold
                                color: root.colSubtext
                            }

                            Item { Layout.fillWidth: true }

                            StyledText {
                                visible: root.width >= 680
                                text: Translation.tr("Due %1 · New %2 · Learning %3")
                                    .arg(root.backend.analytics?.dueToday ?? 0)
                                    .arg(root.backend.analytics?.newCount ?? 0)
                                    .arg(root.backend.analytics?.learningCount ?? 0)
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: root.colSubtext
                            }
                        }
                    }

                    // Active Flashcard Box
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: root.backend.hasActiveCard
                        radius: Appearance.rounding.small
                        color: root.colSurface
                        border.width: 0
                        clip: true

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 20
                            spacing: 14

                            // Card Metadata Header
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                // CEFR Badge (A1-C2)
                                Rectangle {
                                    visible: Boolean(root.backend.currentCard?.cefrLevel)
                                    implicitHeight: 26
                                    implicitWidth: cefrBadgeRow.implicitWidth + 18
                                    radius: Appearance.rounding.full
                                    color: Qt.alpha(root.cefrColor(root.backend.currentCard?.cefrLevel), 0.16)
                                    Row {
                                        id: cefrBadgeRow
                                        anchors.centerIn: parent
                                        spacing: 5
                                        Rectangle {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 7
                                            height: 7
                                            radius: 3.5
                                            color: root.cefrColor(root.backend.currentCard?.cefrLevel)
                                        }
                                        StyledText {
                                            objectName: "srCurrentCardCefrBadge"
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: root.backend.currentCard?.cefrLevel ?? ""
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                            font.weight: Font.Bold
                                            color: root.cefrColor(root.backend.currentCard?.cefrLevel)
                                        }
                                    }
                                }

                                // Language Pill
                                Rectangle {
                                    implicitHeight: 24
                                    implicitWidth: langText.implicitWidth + 16
                                    radius: Appearance.rounding.full
                                    color: root.colSurfaceElevated
                                    StyledText {
                                        id: langText
                                        anchors.centerIn: parent
                                        text: root.languageLabel(root.backend.currentCard?.language)
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        font.weight: Font.DemiBold
                                        color: root.colSubtext
                                    }
                                }

                                // Part of Speech Pill
                                Rectangle {
                                    visible: Boolean(root.backend.currentCard?.pos)
                                    implicitHeight: 24
                                    implicitWidth: posCardText.implicitWidth + 16
                                    radius: Appearance.rounding.full
                                    color: root.colSurfaceElevated
                                    StyledText {
                                        id: posCardText
                                        anchors.centerIn: parent
                                        text: root.formatPosLabel(root.backend.currentCard?.pos)
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        font.weight: Font.Medium
                                        color: root.colSubtext
                                    }
                                }

                                // Deck Pill (only if non-default)
                                Rectangle {
                                    visible: Boolean(root.backend.currentCard?.deck)
                                        && (root.backend.currentCard?.deck ?? "Default") !== "Default"
                                    implicitHeight: 24
                                    implicitWidth: deckCatText.implicitWidth + 16
                                    radius: Appearance.rounding.full
                                    color: root.colSurfaceElevated
                                    StyledText {
                                        id: deckCatText
                                        anchors.centerIn: parent
                                        text: root.backend.currentCard?.deck ?? ""
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: root.colSubtext
                                    }
                                }

                                // Leech warning badge
                                Rectangle {
                                    visible: Boolean(root.backend.currentCard?.isLeech)
                                    implicitHeight: 24
                                    implicitWidth: leechRow.implicitWidth + 16
                                    radius: Appearance.rounding.full
                                    color: Qt.alpha("#ef4444", 0.16)
                                    Row {
                                        id: leechRow
                                        anchors.centerIn: parent
                                        spacing: 4
                                        MaterialSymbol {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: "warning"
                                            iconSize: 14
                                            color: "#ef4444"
                                        }
                                        StyledText {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: Translation.tr("Leech (%1)").arg(root.backend.currentCard?.lapses ?? 0)
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            color: "#ef4444"
                                        }
                                    }
                                }

                                Item { Layout.fillWidth: true }

                                // Online Dictionary Enrich button (icon-only with tooltip)
                                FilterChip {
                                    objectName: "srEnrichCurrentCardButton"
                                    visible: root.backend.currentCard?.category === "vocabulary"
                                    iconName: root.backend.lookupBusy ? "sync" : "travel_explore"
                                    label: ""
                                    tooltipText: root.backend.lookupBusy
                                        ? Translation.tr("Looking up online dictionary...")
                                        : Translation.tr("Verify IPA, CEFR, Synonyms & Antonyms online (Cambridge / DWDS / Wiktionary)")
                                    onClicked: {
                                        if (root.backend.currentCard?.id)
                                            root.backend.enrichCardOnline(root.backend.currentCard.id)
                                    }
                                }
                            }

                            // Prompt Section
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.topMargin: 4
                                spacing: 8

                                // Mode prompt subtitle
                                StyledText {
                                    Layout.fillWidth: true
                                    visible: root.backend.studyMode !== "flashcard"
                                    text: root.backend.studyMode === "reverse"
                                        ? Translation.tr("Recall the vocabulary term or concept for:")
                                        : root.backend.studyMode === "mc"
                                        ? Translation.tr("Choose the correct definition for:")
                                        : root.backend.studyMode === "rmc"
                                        ? Translation.tr("Choose the vocabulary term that matches this definition:")
                                        : Translation.tr("Complete the missing cloze term:")
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: root.colSubtext
                                }

                                // Main Front Display (Word/Prompt + Inline Example Box on the same row)
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 12

                                    // German der/die/das color pill (shown on front in Flashcard & MC mode)
                                    Rectangle {
                                        visible: (root.backend.studyMode === "flashcard" || root.backend.studyMode === "mc")
                                            && Boolean(root.backend.currentCard?.gender)
                                        implicitHeight: 30
                                        implicitWidth: genderBadgeText.implicitWidth + 18
                                        radius: Appearance.rounding.small
                                        color: Qt.alpha(root.genderColor(root.backend.currentCard?.gender), 0.16)
                                        StyledText {
                                            id: genderBadgeText
                                            anchors.centerIn: parent
                                            text: root.backend.currentCard?.gender ?? ""
                                            font.pixelSize: Appearance.font.pixelSize.normal
                                            font.weight: Font.Bold
                                            color: root.genderColor(root.backend.currentCard?.gender)
                                        }
                                    }

                                    StyledText {
                                        objectName: "srCardPromptText"
                                        Layout.fillWidth: !topExampleBox.visible
                                        Layout.maximumWidth: topExampleBox.visible
                                            ? Math.max(150, Math.round(parent.width * 0.36))
                                            : parent.width
                                        wrapMode: Text.WordWrap
                                        text: {
                                            const card = root.backend.currentCard
                                            if (!card) return ""
                                            if (root.backend.studyMode === "reverse" || root.backend.studyMode === "rmc")
                                                return card.definitionEn || card.back || ""
                                            if (root.backend.studyMode === "cloze")
                                                return root.backend.renderClozeFront(card)
                                            return card.headword || card.front || ""
                                        }
                                        font.pixelSize: (root.backend.studyMode === "flashcard" || root.backend.studyMode === "mc") ? 26 : 20
                                        font.weight: Font.Bold
                                        color: root.colText
                                    }

                                    // Inline Contextual Example sentence with EX badge (same row as word)
                                    Rectangle {
                                        id: topExampleBox
                                        objectName: "srStudyTopExampleBox"
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignVCenter
                                        visible: (root.backend.studyMode === "flashcard"
                                                || root.backend.studyMode === "mc"
                                                || (root.answerRevealed && root.backend.studyMode !== "cloze"))
                                            && Boolean(root.backend.currentCard?.example || root.backend.currentCard?.clozeText)
                                        implicitHeight: Math.max(34, topExampleRow.implicitHeight + 14)
                                        radius: Appearance.rounding.small
                                        color: Qt.alpha(Appearance.colors.colPrimary, 0.09)
                                        border.width: 1
                                        border.color: Qt.alpha(Appearance.colors.colPrimary, 0.24)

                                        RowLayout {
                                            id: topExampleRow
                                            anchors.fill: parent
                                            anchors.leftMargin: 10
                                            anchors.rightMargin: 10
                                            anchors.topMargin: 7
                                            anchors.bottomMargin: 7
                                            spacing: 8

                                            DetailTag {
                                                Layout.alignment: Qt.AlignTop
                                                Layout.topMargin: 1
                                                label: "EX"
                                                color: Qt.alpha(Appearance.colors.colPrimary, 0.20)
                                            }

                                            StyledText {
                                                id: contextClozeText
                                                objectName: "srStudyTopExampleText"
                                                Layout.fillWidth: true
                                                wrapMode: Text.WordWrap
                                                textFormat: Text.StyledText
                                                font.pixelSize: Appearance.font.pixelSize.small
                                                color: Qt.alpha(root.colText, 0.90)
                                                text: root.formatContextExampleRich(root.backend.currentCard, root.answerRevealed)
                                            }
                                        }
                                    }
                                }

                                // Phonetics (IPA) + Plural + Prefix/Root/Suffix Morphology on the same row
                                RowLayout {
                                    Layout.fillWidth: true
                                    visible: (root.backend.studyMode === "flashcard" || root.backend.studyMode === "mc")
                                        && Boolean((root.backend.currentCard?.phonetics ?? "").length
                                            || (root.backend.currentCard?.plural ?? "").length
                                            || root.formatCardMorphology(root.backend.currentCard).length)
                                    spacing: 10

                                    StyledText {
                                        visible: Boolean(root.backend.currentCard?.phonetics)
                                        text: root.backend.currentCard?.phonetics ?? ""
                                        font.pixelSize: Appearance.font.pixelSize.normal
                                        color: Appearance.colors.colPrimary
                                    }
                                    StyledText {
                                        visible: Boolean(root.backend.currentCard?.plural)
                                        text: "Pl.: " + (root.backend.currentCard?.plural ?? "")
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        color: root.colSubtext
                                    }
                                    MorphologyStrip {
                                        objectName: "srStudyMorphologyStrip"
                                        Layout.fillWidth: false
                                        visible: morphText.length > 0
                                        morphText: root.formatCardMorphology(root.backend.currentCard)
                                    }
                                    Item { Layout.fillWidth: true }
                                }

                                // Meaning cue + Type-to-check input in Cloze mode
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    visible: root.backend.studyMode === "cloze"
                                    spacing: 8

                                    StyledText {
                                        Layout.fillWidth: true
                                        wrapMode: Text.WordWrap
                                        text: Translation.tr("Meaning cue: %1").arg(root.backend.currentCard?.back ?? "")
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        color: root.colSubtext
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8

                                        StyledTextField {
                                            id: clozeInputField
                                            objectName: "srClozeInput"
                                            Layout.fillWidth: true
                                            placeholderText: Translation.tr("Type the missing word or phrase and press Enter...")
                                            text: root.typedClozeAttempt
                                            onTextEdited: root.typedClozeAttempt = text
                                            onTextChanged: if (root.typedClozeAttempt !== text) root.typedClozeAttempt = text
                                            onAccepted: root.checkClozeAttempt()
                                        }

                                        FilterChip {
                                            objectName: "srCheckClozeButton"
                                            iconName: "check"
                                            label: Translation.tr("Check")
                                            activeChip: true
                                            onClicked: root.checkClozeAttempt()
                                        }
                                    }

                                    // Cloze feedback badge
                                    StyledText {
                                        visible: root.clozeCheckState.length > 0
                                        text: root.clozeCheckState === "exact"
                                            ? Translation.tr("Exact match!")
                                            : root.clozeCheckState === "close"
                                            ? Translation.tr("Close match — check spelling/article below.")
                                            : Translation.tr("Not quite — review the target term below.")
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        font.weight: Font.DemiBold
                                        color: root.clozeCheckState === "exact"
                                            ? "#10b981"
                                            : root.clozeCheckState === "close" ? "#f59e0b" : "#ef4444"
                                    }
                                }
                            }

                            // 4-Option Multiple Choice / Reverse Multiple Choice Grid (remains visible before & after selection)
                            GridLayout {
                                id: mcOptionsGrid
                                objectName: "srMultipleChoiceGrid"
                                visible: root.isMultipleChoiceMode
                                Layout.fillWidth: true
                                columns: root.width >= 680 ? 2 : 1
                                uniformCellWidths: true
                                columnSpacing: 12
                                rowSpacing: 8

                                Repeater {
                                    model: root.multipleChoiceOptions
                                    delegate: RippleButton {
                                        id: mcOptionBtn
                                        required property var modelData
                                        required property int index
                                        objectName: "srMcOption-" + index
                                        Layout.fillWidth: true
                                        Layout.preferredWidth: 1
                                        Layout.alignment: Qt.AlignTop
                                        property bool forceHoverDetail: false
                                        readonly property bool isChosen: root.selectedChoiceIndex === index
                                        readonly property bool isPending: !root.answerRevealed && root.pendingChoiceIndex === index
                                        readonly property bool isRight: Boolean(modelData.isCorrect)
                                        readonly property bool detailsExpanded: root.answerRevealed
                                            && (mcOptionBtn.isRight || mcOptionBtn.isChosen || mcOptionBtn.hovered || mcOptionBtn.forceHoverDetail)
                                        implicitHeight: Math.max(44, mcOptionHeaderRow.implicitHeight
                                            + (mcOptionDefDrawer.implicitHeight > 0.5 ? mcOptionDefDrawer.implicitHeight + 5 : 0) + 18)
                                        buttonRadius: Appearance.rounding.small
                                        readonly property color stateAccent: !root.answerRevealed
                                            ? Appearance.colors.colPrimary
                                            : isRight
                                            ? "#10b981"
                                            : isChosen
                                            ? "#ef4444"
                                            : root.colSubtext

                                        colBackground: !root.answerRevealed
                                            ? (isPending ? Qt.alpha(Appearance.colors.colPrimary, 0.14) : root.colSurfaceElevated)
                                            : isRight
                                            ? Qt.alpha("#10b981", 0.16)
                                            : isChosen
                                            ? Qt.alpha("#ef4444", 0.16)
                                            : root.colSurfaceElevated
                                        colBackgroundHover: !root.answerRevealed
                                            ? Qt.alpha(Appearance.colors.colPrimary, isPending ? 0.20 : 0.14)
                                            : isRight || isChosen
                                            ? colBackground
                                            : Qt.alpha(root.colText, 0.10)

                                        onClicked: root.selectMultipleChoiceOption(index)

                                        Rectangle {
                                            anchors.fill: parent
                                            radius: mcOptionBtn.buttonRadius
                                            color: "transparent"
                                            border.width: (root.answerRevealed && (mcOptionBtn.isRight || mcOptionBtn.isChosen)) || mcOptionBtn.isPending ? 1.5 : 1
                                            border.color: (root.answerRevealed && (mcOptionBtn.isRight || mcOptionBtn.isChosen)) || mcOptionBtn.isPending
                                                ? mcOptionBtn.stateAccent
                                                : root.colBorder
                                        }

                                        contentItem: Item {
                                            ColumnLayout {
                                                id: mcOptionCol
                                                anchors.left: parent.left
                                                anchors.right: parent.right
                                                anchors.verticalCenter: parent.verticalCenter
                                                anchors.leftMargin: 12
                                                anchors.rightMargin: 12
                                                spacing: 4

                                                RowLayout {
                                                    id: mcOptionHeaderRow
                                                    Layout.fillWidth: true
                                                    spacing: 8

                                                    Rectangle {
                                                        Layout.alignment: Qt.AlignVCenter
                                                        implicitWidth: 22
                                                        implicitHeight: 22
                                                        radius: 6
                                                        color: (root.answerRevealed && (mcOptionBtn.isRight || mcOptionBtn.isChosen)) || mcOptionBtn.isPending
                                                            ? Qt.alpha(mcOptionBtn.stateAccent, 0.24)
                                                            : Qt.alpha(root.colText, 0.08)
                                                        StyledText {
                                                            anchors.centerIn: parent
                                                            text: ["A", "B", "C", "D"][mcOptionBtn.index] ?? String(mcOptionBtn.index + 1)
                                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                                            font.weight: Font.Bold
                                                            color: (root.answerRevealed && (mcOptionBtn.isRight || mcOptionBtn.isChosen)) || mcOptionBtn.isPending
                                                                ? mcOptionBtn.stateAccent
                                                                : root.colSubtext
                                                        }
                                                    }

                                                    // Term row: shown before reveal in RMC mode, and on ALL 4 options after reveal
                                                    StyledText {
                                                        objectName: "srMcOptionTerm-" + mcOptionBtn.index
                                                        visible: root.backend.studyMode === "rmc" || root.answerRevealed
                                                        Layout.fillWidth: true
                                                        Layout.alignment: Qt.AlignVCenter
                                                        wrapMode: Text.WordWrap
                                                        text: (mcOptionBtn.modelData.front ?? "")
                                                            + (mcOptionBtn.modelData.phonetics ? "  " + mcOptionBtn.modelData.phonetics : "")
                                                        font.pixelSize: Appearance.font.pixelSize.small
                                                        font.weight: Font.Bold
                                                        color: root.colText
                                                    }

                                                    // Definition row (when in MC mode before reveal, sits inline with letter badge)
                                                    StyledText {
                                                        visible: root.backend.studyMode === "mc" && !root.answerRevealed
                                                        Layout.fillWidth: true
                                                        Layout.alignment: Qt.AlignVCenter
                                                        wrapMode: Text.WordWrap
                                                        text: mcOptionBtn.modelData.definitionEn ?? ""
                                                        font.pixelSize: Appearance.font.pixelSize.small
                                                        font.weight: Font.Medium
                                                        color: root.colText
                                                    }

                                                    Rectangle {
                                                        objectName: "srMcOptionPendingBadge-" + mcOptionBtn.index
                                                        visible: mcOptionBtn.isPending
                                                        Layout.alignment: Qt.AlignVCenter
                                                        implicitWidth: pendingHintRow.implicitWidth + 14
                                                        implicitHeight: 22
                                                        radius: 6
                                                        color: Qt.alpha(Appearance.colors.colPrimary, 0.20)
                                                        border.width: 1
                                                        border.color: Qt.alpha(Appearance.colors.colPrimary, 0.45)

                                                        Row {
                                                            id: pendingHintRow
                                                            anchors.centerIn: parent
                                                            spacing: 4

                                                            MaterialSymbol {
                                                                anchors.verticalCenter: parent.verticalCenter
                                                                text: "space_bar"
                                                                iconSize: 14
                                                                color: Appearance.colors.colPrimary
                                                            }

                                                            StyledText {
                                                                id: pendingHintText
                                                                anchors.verticalCenter: parent.verticalCenter
                                                                text: "Space"
                                                                font.pixelSize: Appearance.font.pixelSize.smallest - 1
                                                                font.weight: Font.DemiBold
                                                                color: Appearance.colors.colPrimary
                                                            }
                                                        }
                                                    }

                                                    MaterialSymbol {
                                                        visible: root.answerRevealed && (mcOptionBtn.isRight || mcOptionBtn.isChosen)
                                                        Layout.alignment: Qt.AlignVCenter
                                                        text: mcOptionBtn.isRight ? "check_circle" : "cancel"
                                                        iconSize: 18
                                                        color: mcOptionBtn.stateAccent
                                                    }
                                                }

                                                // Expandable 2-line Definition (EN + VI): shown for right & chosen options, or on hover with slide animation for other options
                                                Item {
                                                    id: mcOptionDefDrawer
                                                    objectName: "srMcOptionDefDrawer-" + mcOptionBtn.index
                                                    Layout.fillWidth: true
                                                    Layout.leftMargin: 30
                                                    clip: true
                                                    readonly property real targetHeight: mcOptionBtn.detailsExpanded ? mcOptionDefCol.implicitHeight : 0
                                                    implicitHeight: targetHeight
                                                    Layout.preferredHeight: implicitHeight
                                                    opacity: mcOptionBtn.detailsExpanded ? 1 : 0
                                                    visible: implicitHeight > 0.5 || mcOptionBtn.detailsExpanded

                                                    Behavior on implicitHeight {
                                                        NumberAnimation {
                                                            duration: 180
                                                            easing.type: Easing.OutCubic
                                                        }
                                                    }
                                                    Behavior on opacity {
                                                        NumberAnimation {
                                                            duration: 150
                                                            easing.type: Easing.OutCubic
                                                        }
                                                    }

                                                    ColumnLayout {
                                                        id: mcOptionDefCol
                                                        width: parent.width
                                                        spacing: 2

                                                        // Line 1: English Definition
                                                        StyledText {
                                                            objectName: "srMcOptionDef-" + mcOptionBtn.index
                                                            visible: mcOptionBtn.detailsExpanded
                                                            Layout.fillWidth: true
                                                            wrapMode: Text.WordWrap
                                                            text: mcOptionBtn.modelData.definitionEn ?? ""
                                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                                            color: Qt.alpha(root.colText, 0.90)
                                                        }

                                                        // Line 2: Vietnamese Meaning
                                                        StyledText {
                                                            objectName: "srMcOptionMeaningVi-" + mcOptionBtn.index
                                                            visible: mcOptionBtn.detailsExpanded && Boolean(mcOptionBtn.modelData.meaningVi)
                                                            Layout.fillWidth: true
                                                            wrapMode: Text.WordWrap
                                                            text: mcOptionBtn.modelData.meaningVi ?? ""
                                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                                            color: root.colSubtext
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                visible: !root.answerRevealed && root.isMultipleChoiceMode
                            }

                            // Reveal Button (when answer is still hidden in non-MC modes)
                            Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                visible: !root.answerRevealed && !root.isMultipleChoiceMode

                                RippleButton {
                                    objectName: "srRevealButton"
                                    anchors.centerIn: parent
                                    implicitWidth: Math.max(220, revealRow.implicitWidth + 36)
                                    implicitHeight: 42
                                    buttonRadius: Appearance.rounding.full
                                    colBackground: Appearance.colors.colPrimaryContainer
                                    colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                                    onClicked: {
                                        root.answerRevealed = true
                                        root.focusPrimarySurface()
                                    }
                                    contentItem: Item {
                                        Row {
                                            id: revealRow
                                            anchors.centerIn: parent
                                            spacing: 8
                                            MaterialSymbol {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: "visibility"
                                                iconSize: 19
                                                color: Appearance.colors.colOnPrimaryContainer
                                            }
                                            StyledText {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: Translation.tr("Reveal Answer (Space)")
                                                font.pixelSize: Appearance.font.pixelSize.normal
                                                font.weight: Font.DemiBold
                                                color: Appearance.colors.colOnPrimaryContainer
                                            }
                                        }
                                    }
                                }
                            }

                            // Revealed Answer Panel
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                visible: root.answerRevealed
                                spacing: 10

                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 1
                                    color: root.colBorder
                                }

                                ScrollView {
                                    id: answerScrollView
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    clip: true

                                    ColumnLayout {
                                        width: answerScrollView.width
                                        spacing: 8

                                        // 2-Column English Definition (EN) & Vietnamese Meaning (VI) Row with Center Separator (hidden in Multiple Choice modes where options already show definitions)
                                        RowLayout {
                                            id: enViRow
                                            objectName: "srEnViRow"
                                            visible: !root.isMultipleChoiceMode
                                            Layout.fillWidth: true
                                            spacing: 12
                                            readonly property bool hasVi: Boolean(root.backend.currentCard?.meaningVi)
                                            readonly property real halfColWidth: Math.max(120, Math.floor((answerScrollView.width - 25) / 2))

                                            // Left Column: English Definition
                                            RowLayout {
                                                Layout.fillWidth: true
                                                Layout.preferredWidth: enViRow.hasVi ? enViRow.halfColWidth : answerScrollView.width
                                                Layout.maximumWidth: enViRow.hasVi ? enViRow.halfColWidth : answerScrollView.width
                                                Layout.alignment: Qt.AlignTop
                                                spacing: 10
                                                DetailTag {
                                                    Layout.alignment: Qt.AlignTop
                                                    Layout.topMargin: 2
                                                    label: "EN"
                                                }
                                                StyledText {
                                                    objectName: "srCardAnswerText"
                                                    Layout.fillWidth: true
                                                    wrapMode: Text.WordWrap
                                                    text: (root.backend.studyMode === "flashcard" || root.backend.studyMode === "mc")
                                                        ? (root.backend.currentCard?.definitionEn || root.backend.currentCard?.back || "")
                                                        : ((root.backend.currentCard?.front ?? "")
                                                            + (root.backend.currentCard?.phonetics ? "  " + root.backend.currentCard.phonetics : "")
                                                            + " — " + (root.backend.currentCard?.definitionEn || root.backend.currentCard?.back || ""))
                                                    font.pixelSize: Appearance.font.pixelSize.normal
                                                    font.weight: Font.Medium
                                                    color: root.colText
                                                }
                                            }

                                            // Center Vertical Separator
                                            Rectangle {
                                                objectName: "srEnViSeparator"
                                                visible: enViRow.hasVi
                                                Layout.preferredWidth: 1
                                                Layout.fillHeight: true
                                                Layout.minimumHeight: 20
                                                Layout.topMargin: 2
                                                Layout.bottomMargin: 2
                                                color: Qt.alpha(root.colText, 0.14)
                                            }

                                            // Right Column: Vietnamese Meaning
                                            RowLayout {
                                                Layout.fillWidth: true
                                                Layout.preferredWidth: enViRow.halfColWidth
                                                Layout.maximumWidth: enViRow.halfColWidth
                                                Layout.alignment: Qt.AlignTop
                                                visible: enViRow.hasVi
                                                spacing: 10
                                                DetailTag {
                                                    Layout.alignment: Qt.AlignTop
                                                    Layout.topMargin: 2
                                                    label: "VI"
                                                }
                                                StyledText {
                                                    objectName: "srStudyCardMeaningVi"
                                                    Layout.fillWidth: true
                                                    wrapMode: Text.WordWrap
                                                    font.pixelSize: Appearance.font.pixelSize.normal
                                                    font.weight: Font.Normal
                                                    color: Qt.alpha(root.colText, 0.88)
                                                    text: root.backend.currentCard?.meaningVi ?? ""
                                                }
                                            }
                                        }

                                        // Morphology Strip in Reverse / RMC / Cloze mode when revealed
                                        MorphologyStrip {
                                            visible: root.backend.studyMode !== "flashcard"
                                                && root.backend.studyMode !== "mc"
                                                && morphText.length > 0
                                            morphText: root.formatCardMorphology(root.backend.currentCard)
                                        }

                                        // Collocations Row (when present on card)
                                        RowLayout {
                                            id: collocationsRow
                                            objectName: "srCollocationsRow"
                                            Layout.fillWidth: true
                                            visible: (root.backend.currentCard?.collocations?.length ?? 0) > 0
                                            spacing: 10
                                            DetailTag {
                                                Layout.alignment: Qt.AlignTop
                                                Layout.topMargin: 3
                                                label: "USE"
                                            }
                                            Flow {
                                                Layout.fillWidth: true
                                                spacing: 8
                                                Repeater {
                                                    model: root.backend.currentCard?.collocations ?? []
                                                    delegate: Rectangle {
                                                        id: collocationChip
                                                        required property var modelData
                                                        required property int index
                                                        objectName: "srCollocationChip-" + index
                                                        readonly property var parsed: root.parseCollocation(modelData)
                                                        implicitWidth: Math.min(answerScrollView.width - 52, collocationChipRow.implicitWidth + 20)
                                                        implicitHeight: collocationChipRow.implicitHeight + 8
                                                        radius: 6
                                                        color: Qt.alpha(Appearance.colors.colPrimary, 0.08)
                                                        border.width: 1
                                                        border.color: Qt.alpha(Appearance.colors.colPrimary, 0.22)

                                                        RowLayout {
                                                            id: collocationChipRow
                                                            anchors.centerIn: parent
                                                            spacing: 6

                                                            StyledText {
                                                                objectName: "srCollocationPhrase-" + collocationChip.index
                                                                text: collocationChip.parsed.phrase
                                                                font.pixelSize: Appearance.font.pixelSize.small
                                                                font.weight: Font.DemiBold
                                                                color: root.colText
                                                            }

                                                            StyledText {
                                                                visible: collocationChip.parsed.gloss.length > 0
                                                                text: "·"
                                                                font.pixelSize: Appearance.font.pixelSize.small
                                                                font.weight: Font.Bold
                                                                color: Appearance.colors.colPrimary
                                                            }

                                                            StyledText {
                                                                objectName: "srCollocationGloss-" + collocationChip.index
                                                                visible: collocationChip.parsed.gloss.length > 0
                                                                text: collocationChip.parsed.gloss
                                                                font.pixelSize: Appearance.font.pixelSize.small
                                                                font.weight: Font.Normal
                                                                color: root.colSubtext
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        // 2-Column Synonyms (SYN) & Antonyms (ANT) Row with Center Separator
                                        RowLayout {
                                            id: synAntRow
                                            Layout.fillWidth: true
                                            visible: (root.backend.currentCard?.synonyms?.length ?? 0) > 0
                                                || (root.backend.currentCard?.antonyms?.length ?? 0) > 0
                                            spacing: 12
                                            readonly property real halfColWidth: Math.max(120, Math.floor((answerScrollView.width - 25) / 2))

                                            // Left Column: Synonyms (SYN)
                                            RowLayout {
                                                Layout.fillWidth: true
                                                Layout.preferredWidth: synAntRow.halfColWidth
                                                Layout.maximumWidth: synAntRow.halfColWidth
                                                Layout.alignment: Qt.AlignTop
                                                spacing: 10
                                                DetailTag {
                                                    Layout.alignment: Qt.AlignTop
                                                    Layout.topMargin: 3
                                                    label: "SYN"
                                                }
                                                Flow {
                                                    objectName: "srStudyCardSynonyms"
                                                    Layout.fillWidth: true
                                                    spacing: 6

                                                    Repeater {
                                                        model: root.backend.currentCard?.synonyms ?? []
                                                        delegate: Rectangle {
                                                            id: synChip
                                                            required property var modelData
                                                            required property int index
                                                            objectName: "srSynChip-" + index
                                                            implicitWidth: synChipText.implicitWidth + 20
                                                            implicitHeight: synChipText.implicitHeight + 8
                                                            radius: 6
                                                            color: Qt.alpha(Appearance.colors.colPrimary, 0.08)
                                                            border.width: 1
                                                            border.color: Qt.alpha(Appearance.colors.colPrimary, 0.22)

                                                            StyledText {
                                                                id: synChipText
                                                                anchors.centerIn: parent
                                                                text: String(synChip.modelData ?? "")
                                                                font.pixelSize: Appearance.font.pixelSize.small
                                                                font.weight: Font.Medium
                                                                color: root.colText
                                                            }
                                                        }
                                                    }

                                                    StyledText {
                                                        visible: (root.backend.currentCard?.synonyms?.length ?? 0) === 0
                                                        font.pixelSize: Appearance.font.pixelSize.small
                                                        color: root.colSubtext
                                                        text: "—"
                                                    }
                                                }
                                            }

                                            // Center Vertical Separator
                                            Rectangle {
                                                objectName: "srSynAntSeparator"
                                                Layout.preferredWidth: 1
                                                Layout.fillHeight: true
                                                Layout.minimumHeight: 22
                                                Layout.topMargin: 2
                                                Layout.bottomMargin: 2
                                                color: Qt.alpha(root.colText, 0.14)
                                            }

                                            // Right Column: Antonyms (ANT)
                                            RowLayout {
                                                Layout.fillWidth: true
                                                Layout.preferredWidth: synAntRow.halfColWidth
                                                Layout.maximumWidth: synAntRow.halfColWidth
                                                Layout.alignment: Qt.AlignTop
                                                spacing: 10
                                                DetailTag {
                                                    Layout.alignment: Qt.AlignTop
                                                    Layout.topMargin: 3
                                                    label: "ANT"
                                                }
                                                Flow {
                                                    objectName: "srStudyCardAntonyms"
                                                    Layout.fillWidth: true
                                                    spacing: 6

                                                    Repeater {
                                                        model: root.backend.currentCard?.antonyms ?? []
                                                        delegate: Rectangle {
                                                            id: antChip
                                                            required property var modelData
                                                            required property int index
                                                            objectName: "srAntChip-" + index
                                                            implicitWidth: antChipText.implicitWidth + 20
                                                            implicitHeight: antChipText.implicitHeight + 8
                                                            radius: 6
                                                            color: Qt.alpha(Appearance.colors.colPrimary, 0.08)
                                                            border.width: 1
                                                            border.color: Qt.alpha(Appearance.colors.colPrimary, 0.22)

                                                            StyledText {
                                                                id: antChipText
                                                                anchors.centerIn: parent
                                                                text: String(antChip.modelData ?? "")
                                                                font.pixelSize: Appearance.font.pixelSize.small
                                                                font.weight: Font.Medium
                                                                color: root.colText
                                                            }
                                                        }
                                                    }

                                                    StyledText {
                                                        visible: (root.backend.currentCard?.antonyms?.length ?? 0) === 0
                                                        font.pixelSize: Appearance.font.pixelSize.small
                                                        color: root.colSubtext
                                                        text: "—"
                                                    }
                                                }
                                            }
                                        }

                                        StyledText {
                                            Layout.fillWidth: true
                                            visible: Boolean(root.backend.currentCard?.notes)
                                            wrapMode: Text.WordWrap
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            color: root.colSubtext
                                            text: root.backend.currentCard?.notes ?? ""
                                        }
                                    }
                                }

                                // 4 Rating Buttons (0 · Again / 1 · Hard / 2 · Good / 3 · Easy)
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    Repeater {
                                        model: [
                                            { id: "again", key: "0", label: Translation.tr("Again"), interval: root.backend.currentIntervals?.again ?? "<10m", color: "#ef4444", obj: "srRateAgain" },
                                            { id: "hard", key: "1", label: Translation.tr("Hard"), interval: root.backend.currentIntervals?.hard ?? "1d", color: "#f59e0b", obj: "srRateHard" },
                                            { id: "good", key: "2", label: Translation.tr("Good"), interval: root.backend.currentIntervals?.good ?? "2d", color: Appearance.colors.colPrimary, obj: "srRateGood" },
                                            { id: "easy", key: "3", label: Translation.tr("Easy"), interval: root.backend.currentIntervals?.easy ?? "3d", color: "#10b981", obj: "srRateEasy" }
                                        ]
                                        delegate: RippleButton {
                                            required property var modelData
                                            objectName: modelData.obj
                                            Layout.fillWidth: true
                                            implicitHeight: 44
                                            buttonRadius: Appearance.rounding.small
                                            colBackground: Qt.alpha(modelData.color, 0.14)
                                            colBackgroundHover: Qt.alpha(modelData.color, 0.24)
                                            onClicked: root.submitReviewRating(modelData.id)

                                            contentItem: Item {
                                                Column {
                                                    anchors.centerIn: parent
                                                    spacing: 1
                                                    StyledText {
                                                        anchors.horizontalCenter: parent.horizontalCenter
                                                        text: modelData.key + " · " + modelData.label
                                                        font.pixelSize: Appearance.font.pixelSize.small
                                                        font.weight: Font.Bold
                                                        color: root.colText
                                                    }
                                                    StyledText {
                                                        anchors.horizontalCenter: parent.horizontalCenter
                                                        text: modelData.interval
                                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                                        color: modelData.color
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Caught-up / Empty Queue View
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: !root.backend.hasActiveCard
                        radius: Appearance.rounding.small
                        color: root.colSurface
                        border.width: 0

                        ColumnLayout {
                            anchors.centerIn: parent
                            width: Math.min(480, parent.width - 40)
                            spacing: 12

                            MaterialSymbol {
                                Layout.alignment: Qt.AlignHCenter
                                text: "task_alt"
                                iconSize: 40
                                color: "#10b981"
                            }

                            StyledText {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                text: Translation.tr("You're all caught up for this filter!")
                                font.pixelSize: Appearance.font.pixelSize.large
                                font.weight: Font.Bold
                                color: root.colText
                            }

                            StyledText {
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                horizontalAlignment: Text.AlignHCenter
                                text: Translation.tr("Use Boost to practice ahead of schedule, drill difficult vocabulary, or capture new terms with automatic IPA, POS, CEFR, and synonym detection.")
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: root.colSubtext
                            }

                            Flow {
                                Layout.alignment: Qt.AlignHCenter
                                spacing: 8

                                FilterChip {
                                    objectName: "srEmptyBoostAhead"
                                    iconName: "bolt"
                                    label: Translation.tr("Practice Ahead (+3d)")
                                    activeChip: true
                                    badgeColor: "#f59e0b"
                                    onClicked: root.backend.startBoost("ahead")
                                }
                                FilterChip {
                                    objectName: "srEmptyBoostHard"
                                    iconName: "local_fire_department"
                                    label: Translation.tr("Hard & Leeches")
                                    badgeColor: "#ef4444"
                                    onClicked: root.backend.startBoost("hard")
                                }
                                FilterChip {
                                    objectName: "srEmptyBoostCram"
                                    iconName: "all_inclusive"
                                    label: Translation.tr("Cram All")
                                    badgeColor: "#a855f7"
                                    onClicked: root.backend.startBoost("cram", Math.max(7, root.backend.boostAheadDays))
                                }
                                FilterChip {
                                    objectName: "srEmptyGoCapture"
                                    iconName: "add_circle"
                                    label: Translation.tr("Capture")
                                    onClicked: root.subTab = "capture"
                                }
                            }
                        }
                    }
                }

                // Right Sidebar: CEFR Mastery & Instant Quick-Add
                Rectangle {
                    Layout.preferredWidth: 276
                    Layout.fillHeight: true
                    visible: root.width >= 860
                    radius: Appearance.rounding.small
                    color: root.colSurface
                    border.width: 0

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 10

                        StyledText {
                            text: Translation.tr("CEFR Mastery")
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.Bold
                            color: root.colText
                        }

                        // A1 - C2 Progress Bars
                        Repeater {
                            model: ["A1", "A2", "B1", "B2", "C1", "C2"]
                            delegate: ColumnLayout {
                                required property string modelData
                                Layout.fillWidth: true
                                spacing: 3
                                readonly property int totalAtLevel: root.backend.analytics?.cefrCounts?.[modelData] ?? 0
                                readonly property int masteredAtLevel: root.backend.analytics?.cefrMastered?.[modelData] ?? 0

                                RowLayout {
                                    Layout.fillWidth: true
                                    Rectangle {
                                        width: 28
                                        height: 18
                                        radius: 4
                                        color: Qt.alpha(root.cefrColor(modelData), 0.18)
                                        StyledText {
                                            anchors.centerIn: parent
                                            text: modelData
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            font.weight: Font.Bold
                                            color: root.cefrColor(modelData)
                                        }
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: Translation.tr("%1 / %2 mastered").arg(masteredAtLevel).arg(totalAtLevel)
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: root.colSubtext
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 6
                                    radius: 3
                                    color: root.colSurfaceElevated
                                    Rectangle {
                                        width: parent.width * (parent.parent.totalAtLevel > 0
                                            ? Math.min(1, parent.parent.masteredAtLevel / parent.parent.totalAtLevel)
                                            : 0)
                                        height: parent.height
                                        radius: 3
                                        color: root.cefrColor(modelData)
                                    }
                                }
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: root.colBorder }

                        // Maturity Summary
                        GridLayout {
                            Layout.fillWidth: true
                            columns: 2
                            rowSpacing: 4
                            columnSpacing: 8

                            StyledText {
                                text: Translation.tr("New: %1").arg(root.backend.analytics?.newCount ?? 0)
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: root.colSubtext
                            }
                            StyledText {
                                text: Translation.tr("Young: %1").arg(root.backend.analytics?.youngCount ?? 0)
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: root.colSubtext
                            }
                            StyledText {
                                text: Translation.tr("Mature: %1").arg(root.backend.analytics?.matureCount ?? 0)
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: "#10b981"
                            }
                            StyledText {
                                text: Translation.tr("Leeches: %1").arg(root.backend.analytics?.leechCount ?? 0)
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: "#ef4444"
                            }
                        }

                        Item { Layout.fillHeight: true }

                        Rectangle { Layout.fillWidth: true; height: 1; color: root.colBorder }

                        // Instant One-Line Capture
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            MaterialSymbol {
                                text: "flash_on"
                                iconSize: 15
                                color: Appearance.colors.colPrimary
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("Quick Capture")
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.DemiBold
                                color: root.colText
                            }
                        }

                        StyledTextField {
                            id: sidebarQuickInput
                            objectName: "srQuickAddField"
                            Layout.fillWidth: true
                            placeholderText: Translation.tr("word - meaning // example")
                            onAccepted: {
                                if (!text.trim().length) return
                                const count = root.backend.importQuickText(
                                    text,
                                    root.backend.selectedDeck === "all" ? "Default" : root.backend.selectedDeck,
                                    root.backend.selectedLanguage === "all"
                                        ? (root.backend.options?.defaultLanguage ?? "en")
                                        : root.backend.selectedLanguage,
                                    "vocabulary"
                                )
                                if (count > 0) {
                                    root.statusBannerText = Translation.tr("Captured %1 card").arg(count)
                                    text = ""
                                }
                            }
                        }
                    }
                }
            }

            // =================================================================
            // SUB-TAB 2: AUTO-SYNTAX & SMART COMPOSER
            // =================================================================
            RowLayout {
                anchors.fill: parent
                visible: root.subTab === "capture"
                spacing: 12

                // Left Column: Structured Smart Vocabulary & Knowledge Composer
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 1
                    radius: Appearance.rounding.small
                    color: root.colSurface
                    border.width: 0

                    Flickable {
                        id: composerScrollView
                        objectName: "srComposerScrollView"
                        anchors.fill: parent
                        anchors.margins: 16
                        contentWidth: width
                        contentHeight: composerContentCol.implicitHeight
                        boundsBehavior: Flickable.StopAtBounds
                        clip: true

                        ColumnLayout {
                            id: composerContentCol
                            width: composerScrollView.width
                            spacing: 10

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                StyledText {
                                    text: Translation.tr("Smart Vocabulary & Concept Composer")
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    font.weight: Font.Bold
                                    color: root.colText
                                }

                                Item { Layout.fillWidth: true }

                                FilterChip {
                                    objectName: "srLookupOnlineButton"
                                    iconName: root.backend.lookupBusy ? "sync" : "travel_explore"
                                    label: ""
                                    activeChip: root.backend.lookupBusy
                                    tooltipText: root.backend.lookupBusy
                                        ? Translation.tr("Looking up IPA, CEFR, POS, Synonyms & Antonyms...")
                                        : Translation.tr("Refresh online dictionary lookup (Cambridge / DWDS / Wiktionary)")
                                    onClicked: {
                                        if (root.composerFront.trim().length > 0) {
                                            root.backend.lookupWordOnline(
                                                root.composerFront.trim(),
                                                root.composerLanguage || (root.backend.options?.defaultLanguage ?? "en")
                                            )
                                        }
                                    }
                                }

                                FilterChip {
                                    objectName: "srToggleComposerOverridesButton"
                                    iconName: "tune"
                                    label: ""
                                    activeChip: root.composerShowManualOverrides
                                    tooltipText: Translation.tr("Toggle manual overrides (Deck, IPA, POS, CEFR, Synonyms, Antonyms)")
                                    onClicked: root.composerShowManualOverrides = !root.composerShowManualOverrides
                                }
                            }

                            // Category & Language Selector Row
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                Repeater {
                                    model: [
                                        { id: "vocabulary", label: Translation.tr("Vocabulary"), icon: "translate" },
                                        { id: "knowledge", label: Translation.tr("Q&A"), icon: "quiz" },
                                        { id: "cloze", label: Translation.tr("Cloze"), icon: "edit_note" }
                                    ]
                                    delegate: FilterChip {
                                        required property var modelData
                                        iconName: modelData.icon
                                        label: modelData.label
                                        activeChip: root.composerCategory === modelData.id
                                        onClicked: root.composerCategory = modelData.id
                                    }
                                }

                                Rectangle { width: 1; height: 18; color: root.colBorder }

                                Repeater {
                                    model: [
                                        { id: "", label: Translation.tr("Auto"), tooltip: Translation.tr("Auto-detect English or German") },
                                        { id: "en", label: "EN", tooltip: Translation.tr("English") },
                                        { id: "de", label: "DE", tooltip: Translation.tr("German (Deutsch)") },
                                        { id: "general", label: Translation.tr("Gen"), tooltip: Translation.tr("General Knowledge") }
                                    ]
                                    delegate: FilterChip {
                                        required property var modelData
                                        label: modelData.label
                                        tooltipText: modelData.tooltip
                                        activeChip: root.composerLanguage === modelData.id
                                        onClicked: root.composerLanguage = modelData.id
                                    }
                                }
                            }

                            // Word / Term / Question
                            StyledTextField {
                                id: composerFrontField
                                objectName: "srComposerFront"
                                Layout.fillWidth: true
                                placeholderText: root.composerCategory === "vocabulary"
                                    ? Translation.tr("Headword (e.g. ubiquitous, die Sehenswürdigkeit, Nachhaltigkeit)...")
                                    : Translation.tr("Question or Cloze Prompt (no :: or == markup needed)...")
                                text: root.composerFront
                                onTextEdited: root.composerFront = text
                                onTextChanged: if (root.composerFront !== text) root.composerFront = text
                                onAccepted: root.submitComposerCard()
                            }

                            // Auto-Detected Linguistic Strip (IPA, POS, CEFR, Article, Synonyms, Antonyms)
                            Rectangle {
                                Layout.fillWidth: true
                                visible: root.composerCategory === "vocabulary" || root.composerFront.trim().length > 0
                                implicitHeight: liveAnalysisCol.implicitHeight + 16
                                radius: Appearance.rounding.small
                                color: root.colSurfaceElevated
                                border.width: 0

                                ColumnLayout {
                                    id: liveAnalysisCol
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    spacing: 6

                                    Flow {
                                        Layout.fillWidth: true
                                        spacing: 6

                                        // Auto CEFR Badge
                                        Rectangle {
                                            implicitHeight: 24
                                            implicitWidth: previewCefrText.implicitWidth + 14
                                            radius: Appearance.rounding.full
                                            color: Qt.alpha(root.cefrColor(root.draftPreview?.cefrLevel), 0.18)
                                            StyledText {
                                                id: previewCefrText
                                                objectName: "srComposerAutoCefr"
                                                anchors.centerIn: parent
                                                text: root.composerFront.trim().length > 0
                                                    ? ((root.draftPreview?.cefrLevel || "B1")
                                                        + " · " + (root.draftPreview?.cefrSource || "Auto"))
                                                    : Translation.tr("CEFR Auto (A1–C2)")
                                                font.pixelSize: Appearance.font.pixelSize.smallest
                                                font.weight: Font.Bold
                                                color: root.cefrColor(root.draftPreview?.cefrLevel)
                                            }
                                        }

                                        // Auto POS Pill
                                        Rectangle {
                                            implicitHeight: 24
                                            implicitWidth: previewPosText.implicitWidth + 14
                                            radius: Appearance.rounding.full
                                            color: Qt.alpha(root.colText, 0.06)
                                            StyledText {
                                                id: previewPosText
                                                anchors.centerIn: parent
                                                text: (root.draftPreview?.pos ?? "").length > 0
                                                    ? root.formatPosLabel(root.draftPreview.pos)
                                                    : Translation.tr("POS: Auto")
                                                font.pixelSize: Appearance.font.pixelSize.smallest
                                                font.weight: Font.DemiBold
                                                color: (root.draftPreview?.pos ?? "").length > 0 ? root.colText : root.colSubtext
                                            }
                                        }

                                        // Auto IPA Pill
                                        Rectangle {
                                            implicitHeight: 24
                                            implicitWidth: previewIpaText.implicitWidth + 14
                                            radius: Appearance.rounding.full
                                            color: Qt.alpha(Appearance.colors.colPrimary, 0.12)
                                            StyledText {
                                                id: previewIpaText
                                                anchors.centerIn: parent
                                                text: (root.draftPreview?.phonetics ?? "").length > 0
                                                    ? root.draftPreview.phonetics
                                                    : (root.backend.lookupBusy ? Translation.tr("IPA: fetching...") : Translation.tr("IPA: Auto"))
                                                font.pixelSize: Appearance.font.pixelSize.smallest
                                                font.weight: Font.Medium
                                                color: Appearance.colors.colPrimary
                                            }
                                        }

                                        // German Article Pill
                                        Rectangle {
                                            visible: Boolean(root.draftPreview?.gender)
                                            implicitHeight: 24
                                            implicitWidth: previewGenderText.implicitWidth + 14
                                            radius: Appearance.rounding.full
                                            color: Qt.alpha(root.genderColor(root.draftPreview?.gender), 0.16)
                                            StyledText {
                                                id: previewGenderText
                                                anchors.centerIn: parent
                                                text: (root.draftPreview?.gender ?? "")
                                                    + (root.draftPreview?.plural ? " · Pl. " + root.draftPreview.plural : "")
                                                font.pixelSize: Appearance.font.pixelSize.smallest
                                                font.weight: Font.Bold
                                                color: root.genderColor(root.draftPreview?.gender)
                                            }
                                        }

                                        // Synonyms Pill
                                        Rectangle {
                                            visible: (root.draftPreview?.synonyms?.length ?? 0) > 0
                                            implicitHeight: 24
                                            implicitWidth: Math.min(260, previewSynText.implicitWidth + 14)
                                            radius: Appearance.rounding.full
                                            color: Qt.alpha("#10b981", 0.14)
                                            StyledText {
                                                id: previewSynText
                                                anchors.centerIn: parent
                                                width: Math.min(246, implicitWidth)
                                                elide: Text.ElideRight
                                                text: "≈ " + (root.draftPreview?.synonyms ?? []).slice(0, 4).join(", ")
                                                font.pixelSize: Appearance.font.pixelSize.smallest
                                                color: "#10b981"
                                            }
                                        }

                                        // Antonyms Pill
                                        Rectangle {
                                            visible: (root.draftPreview?.antonyms?.length ?? 0) > 0
                                            implicitHeight: 24
                                            implicitWidth: Math.min(260, previewAntText.implicitWidth + 14)
                                            radius: Appearance.rounding.full
                                            color: Qt.alpha("#f59e0b", 0.14)
                                            StyledText {
                                                id: previewAntText
                                                anchors.centerIn: parent
                                                width: Math.min(246, implicitWidth)
                                                elide: Text.ElideRight
                                                text: "≠ " + (root.draftPreview?.antonyms ?? []).slice(0, 4).join(", ")
                                                font.pixelSize: Appearance.font.pixelSize.smallest
                                                color: "#f59e0b"
                                            }
                                        }
                                    }

                                    // Auto-Detected Word Roots, Prefixes & Suffixes (Morphology Strip)
                                    MorphologyStrip {
                                        objectName: "srComposerMorphologyStrip"
                                        morphText: root.composerFront.trim().length > 0
                                            ? root.formatCardMorphology(root.draftPreview)
                                            : ""
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        visible: Boolean(root.draftPreview?.clozeText)
                                        elide: Text.ElideRight
                                        text: Translation.tr("Auto Cloze: %1").arg(root.draftPreview?.clozeText ?? "")
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        font.italic: true
                                        color: root.colSubtext
                                    }
                                }
                            }

                            // Meaning / Definition / Answer (auto-filled when available unless user edits)
                            StyledTextField {
                                id: composerBackField
                                objectName: "srComposerBack"
                                Layout.fillWidth: true
                                placeholderText: Translation.tr("Meaning, translation, or concise answer (auto-suggested when recognized)...")
                                text: root.composerBack
                                onTextEdited: {
                                    root.composerBackUserEdited = text.trim().length > 0
                                    root.composerBack = text
                                }
                                onTextChanged: if (root.composerBack !== text) root.composerBack = text
                                onAccepted: root.submitComposerCard()
                            }

                            // Example Sentence (auto-filled when available and auto-converted to Cloze)
                            StyledTextField {
                                id: composerExampleField
                                objectName: "srComposerExample"
                                Layout.fillWidth: true
                                placeholderText: Translation.tr("Example sentence (auto-suggested & linked for Cloze mode)...")
                                text: root.composerExample
                                onTextEdited: {
                                    root.composerExampleUserEdited = text.trim().length > 0
                                    root.composerExample = text
                                }
                                onTextChanged: if (root.composerExample !== text) root.composerExample = text
                                onAccepted: root.submitComposerCard()
                            }

                            // Collapsible Manual Overrides Drawer (hidden by default so raw inputs don't clutter)
                            ColumnLayout {
                                Layout.fillWidth: true
                                visible: root.composerShowManualOverrides
                                spacing: 8

                                StyledText {
                                    text: Translation.tr("Manual Overrides (optional — leave blank to use automatic detection)")
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: root.colSubtext
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    StyledTextField {
                                        id: composerDeckField
                                        Layout.fillWidth: true
                                        placeholderText: Translation.tr("Deck name (Default)")
                                        text: root.composerDeck
                                        onTextEdited: root.composerDeck = text
                                        onTextChanged: if (root.composerDeck !== text) root.composerDeck = text
                                    }
                                    StyledTextField {
                                        id: composerPhoneticsField
                                        Layout.fillWidth: true
                                        placeholderText: Translation.tr("IPA override (/.../)")
                                        text: root.composerPhonetics
                                        onTextEdited: root.composerPhonetics = text
                                        onTextChanged: if (root.composerPhonetics !== text) root.composerPhonetics = text
                                    }
                                    StyledTextField {
                                        id: composerPosField
                                        Layout.preferredWidth: 110
                                        placeholderText: Translation.tr("Part of Speech")
                                        text: root.composerPos
                                        onTextEdited: root.composerPos = text
                                        onTextChanged: if (root.composerPos !== text) root.composerPos = text
                                    }
                                    StyledTextField {
                                        id: composerCefrField
                                        Layout.preferredWidth: 90
                                        placeholderText: Translation.tr("CEFR (A1-C2)")
                                        text: root.composerCefrOverride
                                        onTextEdited: root.composerCefrOverride = text
                                        onTextChanged: if (root.composerCefrOverride !== text) root.composerCefrOverride = text
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    StyledTextField {
                                        id: composerSynonymsField
                                        Layout.fillWidth: true
                                        placeholderText: Translation.tr("Synonyms override (comma-separated)")
                                        text: root.composerSynonyms
                                        onTextEdited: root.composerSynonyms = text
                                        onTextChanged: if (root.composerSynonyms !== text) root.composerSynonyms = text
                                    }

                                    StyledTextField {
                                        id: composerAntonymsField
                                        Layout.fillWidth: true
                                        placeholderText: Translation.tr("Antonyms override (comma-separated)")
                                        text: root.composerAntonyms
                                        onTextEdited: root.composerAntonyms = text
                                        onTextChanged: if (root.composerAntonyms !== text) root.composerAntonyms = text
                                    }
                                }
                            }

                            // Action Footer
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                StyledText {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    text: Translation.tr("Deck: %1 · IPA, POS, CEFR, Roots & Synonyms populate automatically")
                                        .arg(root.composerDeck.trim() || "Default")
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: root.colSubtext
                                }

                                RippleButton {
                                    objectName: "srSaveCardButton"
                                    implicitWidth: Math.max(136, saveCardRow.implicitWidth + 28)
                                    implicitHeight: 36
                                    buttonRadius: Appearance.rounding.full
                                    colBackground: Appearance.colors.colPrimary
                                    colBackgroundHover: Qt.lighter(Appearance.colors.colPrimary, 1.1)
                                    onClicked: root.submitComposerCard()
                                    contentItem: Item {
                                        Row {
                                            id: saveCardRow
                                            anchors.centerIn: parent
                                            spacing: 6
                                            MaterialSymbol {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: "add_task"
                                                iconSize: 18
                                                color: Appearance.colors.colOnPrimary
                                            }
                                            StyledText {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: Translation.tr("Add Card")
                                                font.pixelSize: Appearance.font.pixelSize.small
                                                font.weight: Font.Bold
                                                color: Appearance.colors.colOnPrimary
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Right Column: Zero-Markup Bulk Auto-Syntax & Obsidian SR Importer
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 1
                    radius: Appearance.rounding.small
                    color: root.colSurface
                    border.width: 0

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 10

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            StyledText {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: Translation.tr("Bulk Auto-Syntax & Obsidian SR Importer")
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.Bold
                                color: root.colText
                            }
                            FilterChip {
                                objectName: "srLoadSampleBatchButton"
                                iconName: "playlist_add"
                                label: Translation.tr("Sample Batch")
                                tooltipText: Translation.tr("Load sample English & German vocabulary batch")
                                onClicked: {
                                    root.bulkShowSyntaxGuide = false
                                    root.loadSampleBatch()
                                }
                            }
                            FilterChip {
                                objectName: "srBulkSyntaxGuideButton"
                                iconName: "help_outline"
                                label: Translation.tr("Guide")
                                tooltipText: Translation.tr("View supported auto-syntax & Obsidian SR formats (Esc to close)")
                                activeChip: root.bulkShowSyntaxGuide
                                onClicked: {
                                    root.bulkShowSyntaxGuide = !root.bulkShowSyntaxGuide
                                    if (root.bulkShowSyntaxGuide)
                                        root.forceActiveFocus()
                                }
                            }
                        }

                        // Syntax Guide Overlay Card (replaces editor & preview when toggled; Esc closes)
                        Rectangle {
                            objectName: "srBulkSyntaxGuidePanel"
                            visible: root.bulkShowSyntaxGuide
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: Appearance.rounding.small
                            color: root.colSurfaceElevated
                            border.width: 1
                            border.color: Qt.alpha(Appearance.colors.colPrimary, 0.25)

                            ScrollView {
                                anchors.fill: parent
                                anchors.margins: 14
                                clip: true

                                ColumnLayout {
                                    width: parent.width
                                    spacing: 10

                                    RowLayout {
                                        Layout.fillWidth: true
                                        MaterialSymbol {
                                            text: "menu_book"
                                            iconSize: 18
                                            color: Appearance.colors.colPrimary
                                        }
                                        StyledText {
                                            Layout.fillWidth: true
                                            text: Translation.tr("Auto-Syntax & Obsidian SR Guide")
                                            font.pixelSize: Appearance.font.pixelSize.normal
                                            font.weight: Font.Bold
                                            color: root.colText
                                        }
                                        StyledText {
                                            text: Translation.tr("Press Esc to close")
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                            color: root.colSubtext
                                        }
                                    }

                                    Repeater {
                                        model: [
                                            {
                                                title: Translation.tr("• 1. Natural One-Line Vocabulary (No Markup Required)"),
                                                code: "word - meaning // example sentence",
                                                desc: Translation.tr("Automatically assigns IPA, POS, CEFR (A1–C2), word roots/affixes, synonyms, antonyms, and contextual cloze.")
                                            },
                                            {
                                                title: Translation.tr("• 2. German Nouns & Separable Verbs"),
                                                code: "der Zeitraum (-e) - period of time // Über einen längeren Zeitraum.",
                                                desc: Translation.tr("Extracts article (der/die/das), plural form, and splits separable verbs in cloze sentences automatically.")
                                            },
                                            {
                                                title: Translation.tr("• 3. Obsidian Multi-Line & Unit Flashcards"),
                                                code: "Sentence with **____** (Verb — short hint).\n?\n**headword** (C1) (/IPA/)\n* **Nghĩa:** detailed meaning\n* **Collocations:**\n* phrase - meaning",
                                                desc: Translation.tr("Imports vocabulary blocks, collocations, and <!--SR:!YYYY-MM-DD,interval,ease--> schedules while skipping exercises.")
                                            },
                                            {
                                                title: Translation.tr("• 4. Inline Q&A & Custom Cloze Highlights"),
                                                code: "Question :: Answer   |   Term ::: Bidirectional   |   Sentence with ==cloze==",
                                                desc: Translation.tr("Supports single-sided (::), bidirectional (:::), multi-line (? / ??), ==highlight==, and {{c1::answer::hint}}.")
                                            }
                                        ]
                                        delegate: ColumnLayout {
                                            required property var modelData
                                            Layout.fillWidth: true
                                            spacing: 3

                                            StyledText {
                                                Layout.fillWidth: true
                                                wrapMode: Text.WordWrap
                                                text: modelData.title
                                                font.pixelSize: Appearance.font.pixelSize.normal
                                                font.weight: Font.Bold
                                                color: root.colText
                                            }
                                            Rectangle {
                                                Layout.fillWidth: true
                                                implicitHeight: guideCodeText.implicitHeight + 10
                                                radius: 6
                                                color: Qt.alpha(root.colText, 0.06)
                                                StyledText {
                                                    id: guideCodeText
                                                    anchors.fill: parent
                                                    anchors.margins: 5
                                                    wrapMode: Text.WordWrap
                                                    text: modelData.code
                                                    font.pixelSize: Appearance.font.pixelSize.normal
                                                    font.weight: Font.Medium
                                                    color: Appearance.colors.colPrimary
                                                }
                                            }
                                            StyledText {
                                                Layout.fillWidth: true
                                                wrapMode: Text.WordWrap
                                                text: modelData.desc
                                                font.pixelSize: Appearance.font.pixelSize.small
                                                color: root.colSubtext
                                            }
                                        }
                                    }

                                    StyledText {
                                        objectName: "srBulkSyntaxGuideFooterHint"
                                        Layout.fillWidth: true
                                        text: Translation.tr("Press Esc or click Guide again to return to the editor.")
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        color: root.colSubtext
                                    }
                                }
                            }
                        }

                        Rectangle {
                            visible: !root.bulkShowSyntaxGuide
                            Layout.fillWidth: true
                            Layout.preferredHeight: 145
                            radius: Appearance.rounding.small
                            color: root.colSurfaceElevated
                            border.width: bulkInputArea.activeFocus ? 1.5 : 0
                            border.color: bulkInputArea.activeFocus ? Appearance.colors.colPrimary : "transparent"

                            ScrollView {
                                anchors.fill: parent
                                anchors.margins: 6
                                TextArea {
                                    id: bulkInputArea
                                    objectName: "srBulkInputArea"
                                    text: root.bulkInputText
                                    onTextChanged: if (root.bulkInputText !== text) root.bulkInputText = text
                                    placeholderText: "resilient - able to recover quickly // Children are often remarkably resilient.\ndie Erkenntnis - insight, realization // Eine wichtige wissenschaftliche Erkenntnis."
                                    wrapMode: TextEdit.Wrap
                                    selectByMouse: true
                                    cursorVisible: activeFocus
                                    color: root.colText
                                    placeholderTextColor: root.colSubtext
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    background: null
                                }
                            }
                        }

                        RowLayout {
                            visible: !root.bulkShowSyntaxGuide
                            Layout.fillWidth: true
                            StyledText {
                                text: Translation.tr("Live Parsed Preview (%1 cards)").arg(root.bulkPreviewCards.length)
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.DemiBold
                                color: root.colSubtext
                            }
                            Item { Layout.fillWidth: true }
                            FilterChip {
                                objectName: "srBulkImportButton"
                                enabled: root.bulkPreviewCards.length > 0
                                iconName: "download_done"
                                label: Translation.tr("Import (%1)").arg(root.bulkPreviewCards.length)
                                activeChip: root.bulkPreviewCards.length > 0
                                onClicked: root.submitBulkImport()
                            }
                        }

                        ListView {
                            visible: !root.bulkShowSyntaxGuide
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            spacing: 6
                            model: root.bulkPreviewCards
                            delegate: Rectangle {
                                required property var modelData
                                width: ListView.view.width
                                implicitHeight: previewItemCol.implicitHeight + 12
                                radius: Appearance.rounding.small
                                color: root.colSurfaceElevated
                                border.width: 0

                                ColumnLayout {
                                    id: previewItemCol
                                    anchors.fill: parent
                                    anchors.margins: 6
                                    spacing: 2

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 6
                                        Rectangle {
                                            width: 26
                                            height: 18
                                            radius: 4
                                            color: Qt.alpha(root.cefrColor(modelData.cefrLevel), 0.18)
                                            StyledText {
                                                anchors.centerIn: parent
                                                text: modelData.cefrLevel || "B1"
                                                font.pixelSize: Appearance.font.pixelSize.smallest
                                                font.weight: Font.Bold
                                                color: root.cefrColor(modelData.cefrLevel)
                                            }
                                        }
                                        StyledText {
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                            text: (modelData.front ?? "") + " → " + (modelData.back ?? "")
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                            font.weight: Font.DemiBold
                                            color: root.colText
                                        }
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        visible: Boolean(modelData.clozeText)
                                        elide: Text.ElideRight
                                        text: modelData.clozeText ?? ""
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        font.italic: true
                                        color: root.colSubtext
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // =================================================================
            // SUB-TAB 3: LIBRARY & DECK BROWSER
            // =================================================================
            Rectangle {
                anchors.fill: parent
                visible: root.subTab === "library"
                radius: Appearance.rounding.small
                color: root.colSurface
                border.width: 0

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        StyledTextField {
                            id: librarySearchField
                            objectName: "srLibrarySearch"
                            Layout.fillWidth: true
                            placeholderText: Translation.tr("Search vocabulary, meanings, examples, roots, or CEFR level...")
                            text: root.librarySearch
                            onTextEdited: root.librarySearch = text
                            onTextChanged: if (root.librarySearch !== text) root.librarySearch = text
                        }

                        FilterChip {
                            iconName: "warning"
                            label: String(root.backend.analytics?.leechCount ?? 0)
                            tooltipText: Translation.tr("Filter leeches only (%1)").arg(root.backend.analytics?.leechCount ?? 0)
                            activeChip: root.libraryLeechesOnly
                            badgeColor: "#ef4444"
                            onClicked: root.libraryLeechesOnly = !root.libraryLeechesOnly
                        }

                        StyledText {
                            text: Translation.tr("%1 cards").arg(root.filteredLibraryCards.length)
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: root.colSubtext
                        }
                    }

                    ListView {
                        id: libraryListView
                        objectName: "srLibraryListView"
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 6
                        model: root.filteredLibraryCards
                        delegate: Rectangle {
                            id: libCardDelegate
                            objectName: "srLibraryCardDelegate"
                            required property var modelData
                            property bool forceHoverDetail: false
                            readonly property bool detailsVisible: libCardHover.hovered || libCardDelegate.forceHoverDetail
                            width: ListView.view.width
                            implicitHeight: libCardCol.implicitHeight + 16
                            radius: Appearance.rounding.small
                            color: libCardDelegate.detailsVisible
                                ? Qt.alpha(Appearance.colors.colPrimary, 0.08)
                                : root.colSurfaceElevated
                            border.width: libCardDelegate.detailsVisible ? 1 : 0
                            border.color: libCardDelegate.detailsVisible
                                ? Qt.alpha(Appearance.colors.colPrimary, 0.30)
                                : "transparent"

                            HoverHandler {
                                id: libCardHover
                            }

                            ColumnLayout {
                                id: libCardCol
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 6

                                // Default 1-Line Main Summary (always visible)
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    // CEFR Badge
                                    Rectangle {
                                        implicitWidth: 34
                                        implicitHeight: 24
                                        radius: 6
                                        color: Qt.alpha(root.cefrColor(modelData.cefrLevel), 0.18)
                                        StyledText {
                                            anchors.centerIn: parent
                                            text: modelData.cefrLevel || "—"
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                            font.weight: Font.Bold
                                            color: root.cefrColor(modelData.cefrLevel)
                                        }
                                    }

                                    StyledText {
                                        text: modelData.front ?? ""
                                        font.pixelSize: Appearance.font.pixelSize.normal
                                        font.weight: Font.Bold
                                        color: root.colText
                                    }

                                    StyledText {
                                        visible: Boolean(modelData.phonetics)
                                        text: modelData.phonetics ?? ""
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: Appearance.colors.colPrimary
                                    }

                                    StyledText {
                                        visible: Boolean(modelData.pos)
                                        text: "(" + root.formatPosLabel(modelData.pos) + ")"
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: root.colSubtext
                                    }

                                    StyledText {
                                        objectName: "srLibraryCardSummaryDefEn"
                                        Layout.fillWidth: true
                                        elide: libCardDelegate.detailsVisible ? Text.ElideNone : Text.ElideRight
                                        wrapMode: libCardDelegate.detailsVisible ? Text.WordWrap : Text.NoWrap
                                        text: "— " + (modelData.definitionEn || modelData.back || "")
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        color: root.colText
                                    }

                                    Rectangle {
                                        visible: Boolean(modelData.deck)
                                        implicitHeight: 20
                                        implicitWidth: deckTagText.implicitWidth + 12
                                        radius: Appearance.rounding.full
                                        color: Qt.alpha(root.colText, 0.06)
                                        StyledText {
                                            id: deckTagText
                                            anchors.centerIn: parent
                                            text: modelData.deck ?? ""
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            color: root.colSubtext
                                        }
                                    }

                                    FilterChip {
                                        visible: modelData.category === "vocabulary"
                                        iconName: "travel_explore"
                                        label: ""
                                        tooltipText: Translation.tr("Refresh IPA, CEFR, Roots, Synonyms & Antonyms online")
                                        onClicked: root.backend.enrichCardOnline(modelData.id)
                                    }

                                    FilterChip {
                                        iconName: "restart_alt"
                                        label: ""
                                        tooltipText: Translation.tr("Reset review schedule")
                                        onClicked: root.backend.resetCardProgress(modelData.id)
                                    }

                                    FilterChip {
                                        iconName: "delete_outline"
                                        label: ""
                                        tooltipText: Translation.tr("Delete card")
                                        badgeColor: "#ef4444"
                                        onClicked: root.backend.deleteCard(modelData.id)
                                    }
                                }

                                // Full Details Section (revealed on Hover)
                                ColumnLayout {
                                    objectName: "srLibraryCardHoverDetails"
                                    Layout.fillWidth: true
                                    Layout.leftMargin: 42
                                    visible: libCardDelegate.detailsVisible
                                    spacing: 6

                                    Rectangle {
                                        Layout.fillWidth: true
                                        height: 1
                                        color: Qt.alpha(root.colText, 0.06)
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        visible: Boolean(modelData.meaningVi)
                                        spacing: 10
                                        DetailTag {
                                            Layout.alignment: Qt.AlignTop
                                            Layout.topMargin: 1
                                            label: "VI"
                                        }
                                        StyledText {
                                            objectName: "srLibraryCardMeaningVi"
                                            Layout.fillWidth: true
                                            wrapMode: Text.WordWrap
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            font.weight: Font.Normal
                                            color: Qt.alpha(root.colText, 0.88)
                                            text: modelData.meaningVi ?? ""
                                        }
                                    }

                                    MorphologyStrip {
                                        morphText: root.formatCardMorphology(modelData)
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        visible: Boolean(modelData.example)
                                        spacing: 10
                                        DetailTag {
                                            Layout.alignment: Qt.AlignTop
                                            Layout.topMargin: 1
                                            label: "EX"
                                        }
                                        StyledText {
                                            Layout.fillWidth: true
                                            wrapMode: Text.WordWrap
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            font.weight: Font.Normal
                                            color: root.colSubtext
                                            text: modelData.example ?? ""
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        visible: (modelData.collocations?.length ?? 0) > 0
                                        spacing: 10
                                        DetailTag {
                                            Layout.alignment: Qt.AlignTop
                                            Layout.topMargin: 1
                                            label: "USE"
                                        }
                                        StyledText {
                                            Layout.fillWidth: true
                                            wrapMode: Text.WordWrap
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            font.weight: Font.Normal
                                            color: root.colSubtext
                                            text: (modelData.collocations ?? []).join("   ·   ")
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        visible: (modelData.synonyms?.length ?? 0) > 0
                                            || (modelData.antonyms?.length ?? 0) > 0
                                        spacing: 10
                                        DetailTag {
                                            Layout.alignment: Qt.AlignTop
                                            Layout.topMargin: 1
                                            label: "SYN"
                                        }
                                        StyledText {
                                            Layout.fillWidth: true
                                            wrapMode: Text.WordWrap
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            font.weight: Font.Normal
                                            color: root.colSubtext
                                            text: {
                                                const parts = [];
                                                const syns = modelData.synonyms ?? [];
                                                const ants = modelData.antonyms ?? [];
                                                if (syns.length > 0) parts.push("≈ " + syns.join(", "));
                                                if (ants.length > 0) parts.push("≠ " + ants.join(", "));
                                                return parts.join("   ·   ");
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
