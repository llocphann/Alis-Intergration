pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import "../../services/SpacedRepetitionPrompts.js" as Prompts
import qs
import qs.services
import qs.services as HostServices
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.abyss.looks

Item {
    id: root
    objectName: "dashboardSpacedRepetition"
    focus: true

    property bool presentationActive: false
    readonly property var _emptyBackend: ({
        cards: [], historyByDay: ({}), retainedStorageFields: ({}),
        ready: false, lookupBusy: false, lastLookupResult: null, errorMessage: "",
        filterCategory: "all", filterLanguage: "all", filterLevel: "all", filterDeck: "all",
        selectedCategory: "all", selectedLanguage: "all", selectedCefrLevel: "all", selectedDeck: "all",
        leechesOnly: false, searchQuery: "", boostMode: "", boostAheadDays: 3,
        studyMode: "matching", smartMixEnabled: true, cardRevealed: false,
        presentationActive: false, interactionLocked: false, canUndoReview: false, boostActive: false,
        options: ({}), analytics: ({ dueCountsByDay: ({}), counts: ({}), decks: [], total: 0, cefrCounts: ({}) }),
        decks: [], totalCount: 0, dueCount: 0, newCount: 0, learningCount: 0, youngCount: 0, matureCount: 0,
        leechCount: 0, vocabCount: 0, knowledgeCount: 0, clozeCount: 0, streakDays: 0, todayReviewedCount: 0,
        retentionRate: 100, averageEase: 250, levelBreakdown: ({}), masteredLevelBreakdown: ({}),
        studyQueue: [], currentCard: null, hasActiveCard: false, currentIntervals: ({}), filteredLibraryCards: [],
        getYearHeatmap: function() { return { weeks: [] } },
        refreshClock: function() {},
        ensureLoaded: function() {},
        formatMorphology: function() { return "" },
        analyzeDraft: function() { return ({}) },
        renderClozeFront: function() { return "" },
        buildMatchingRound: function() { return { pairs: [] } },
        previewQuickText: function() { return [] }
    })
    property var backend: ((HostServices.AlisIntergration?.spacedRepetitionEnabled ?? false)
        ? (HostServices.AlisIntergration?.spacedRepetition ?? HostServices.AlisIntergration?.session?.spacedRepetition)
        : (HostServices.AlisIntergration?.spacedRepetition ?? HostServices.AlisIntergration?.session?.spacedRepetition ?? HostServices.SpacedRepetition))
        ?? _emptyBackend

    property bool _captureLoaded: false
    property bool _libraryLoaded: false
    property bool _matchingViewLoaded: false
    property bool _singleCardViewLoaded: false
    property bool _clozeViewLoaded: false
    property bool _mcViewLoaded: false
    property bool _revealedViewLoaded: false
    property var clozeInputField: null
    property var matchingLinesCanvas: null
    property var librarySearchField: null
    property var composerFrontField: null
    property var composerBackField: null
    property var composerExampleField: null
    property var composerDeckField: null
    property var composerPhoneticsField: null
    property var composerPosField: null
    property var composerCefrField: null
    property var composerSynonymsField: null
    property var composerAntonymsField: null
    property var bulkInputArea: null

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
        root.syncLazyLoaderFlags()
        if (root.backend && root.backend.cardRevealed !== root.answerRevealed)
            root.backend.cardRevealed = root.answerRevealed
        if (root.answerRevealed && clozeInputField && (clozeInputField.focus || clozeInputField.activeFocus))
            clozeInputField.focus = false
        if (root.presentationActive && root.visible && root.subTab === "study")
            root.focusPrimarySurface()
    }
    readonly property bool isMatchingMode: root.backend.studyMode === "matching"
    readonly property bool isMultipleChoiceMode: root.backend.studyMode === "mc"
    readonly property bool isClozeMode: root.backend.studyMode === "cloze"
    onIsMatchingModeChanged: root.syncLazyLoaderFlags()
    onIsMultipleChoiceModeChanged: root.syncLazyLoaderFlags()
    onIsClozeModeChanged: root.syncLazyLoaderFlags()

    function syncLazyLoaderFlags(): void {
        if (root.subTab === "capture")
            root._captureLoaded = true
        else if (root.subTab === "library")
            root._libraryLoaded = true
        if (root.isMatchingMode) {
            root._matchingViewLoaded = true
        } else {
            root._singleCardViewLoaded = true
            if (root.isClozeMode)
                root._clozeViewLoaded = true
            if (root.isMultipleChoiceMode)
                root._mcViewLoaded = true
            if (root.answerRevealed)
                root._revealedViewLoaded = true
        }
    }
    readonly property bool showStudyArenaCard: root.backend.hasActiveCard
        || (root.isMatchingMode && (root._matchingRoundActive || root.matchingRoundComplete) && root.matchingLeftWords.length > 0)
    property var multipleChoiceOptions: []
    property int pendingChoiceIndex: -1
    property int selectedChoiceIndex: -1
    property var matchingLeftWords: []
    property var matchingRightDefs: []
    property int selectedMatchingLeftIndex: -1
    property int selectedMatchingRightIndex: -1
    property int mismatchLeftIndex: -1
    property int mismatchRightIndex: -1
    property bool matchingRoundComplete: false
    property int matchingMatchedCount: 0
    property bool _matchingRoundActive: false
    property bool _suppressMatchingQueueSync: false
    property bool _submittingReview: false
    property string _activeStudyCardId: ""
    property string typedClozeAttempt: ""
    property string clozeCheckState: "" // "" | "exact" | "close" | "miss"
    property string statusBannerText: ""

    readonly property bool backendSessionActive: root.presentationActive && root.visible
    readonly property bool studyInteractionInProgress: root.backendSessionActive
        && root.subTab === "study"
        && (root.answerRevealed
            || root.pendingChoiceIndex >= 0
            || root.typedClozeAttempt.length > 0
            || (root.isMatchingMode && root.matchingMatchedCount > 0 && !root.matchingRoundComplete))

    function syncBackendActivityFlags(): void {
        if (!root.backend) return
        if (root.backend.presentationActive !== undefined && root.backend.presentationActive !== root.backendSessionActive)
            root.backend.presentationActive = root.backendSessionActive
        if (root.backend.interactionLocked !== undefined && root.backend.interactionLocked !== root.studyInteractionInProgress)
            root.backend.interactionLocked = root.studyInteractionInProgress
    }

    onBackendChanged: {
        root.syncBackendActivityFlags()
        if (!root.backend)
            return
        if (typeof root.backend.ensureLoaded === "function" && (root.presentationActive || root.visible))
            root.backend.ensureLoaded()
        root._activeStudyCardId = String(root.backend?.currentCard?.id ?? "")
        if (root.isMultipleChoiceMode || root.isClozeMode)
            root.rebuildMultipleChoiceOptions()
        if (root.isMatchingMode)
            root.rebuildMatchingRound()
    }
    onBackendSessionActiveChanged: {
        root.syncBackendActivityFlags()
        if (!root.backendSessionActive) {
            autoLookupTimer.stop()
            matchingMismatchTimer.stop()
            matchingLinesRepaintTimer.stop()
        }
    }
    onStudyInteractionInProgressChanged: root.syncBackendActivityFlags()

    Timer {
        id: matchingMismatchTimer
        interval: 420
        repeat: false
        onTriggered: {
            root.mismatchLeftIndex = -1
            root.mismatchRightIndex = -1
            root.requestMatchingLinesRepaint()
        }
    }

    Timer {
        id: matchingLinesRepaintTimer
        interval: 32
        repeat: false
        onTriggered: {
            if (matchingLinesCanvas)
                matchingLinesCanvas.requestPaint()
        }
    }

    function requestMatchingLinesRepaint(): void {
        if (matchingLinesCanvas)
            matchingLinesCanvas.requestPaint()
        matchingLinesRepaintTimer.restart()
    }

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

    // Study-Tracker Analytics & Activity Heatmap column state
    property string analyticsScope: "week" // "today" | "week" | "month" | "total"
    property bool consistencySettingsOpen: false
    property int heatmapYear: (new Date()).getFullYear()
    property var hoveredHeatmapCell: null
    property string hoveredCefrLevel: ""
    readonly property var currentHeatmapData: {
        const currentYear = (new Date()).getFullYear()
        if (root.heatmapYear === currentYear && root.backend?.analytics?.heatmap)
            return root.backend.analytics.heatmap
        if (root.backend && typeof root.backend.getYearHeatmap === "function")
            return root.backend.getYearHeatmap(root.heatmapYear)
        return root.backend?.analytics?.heatmap ?? ({ year: root.heatmapYear, weeks: [], maxReviewed: 1, activeDays: 0, totalReviewedYear: 0 })
    }
    readonly property var activeScopeStats: {
        const scoped = root.backend?.analytics?.scopedStats
        if (!scoped) return ({ reviewed: 0, passed: 0, newStudied: 0, retention: 100, activeDays: 0 })
        return scoped[root.analyticsScope] ?? scoped.week ?? ({ reviewed: 0, passed: 0, newStudied: 0, retention: 100, activeDays: 0 })
    }
    readonly property var upcomingForecast7d: {
        const dueByDay = root.backend?.analytics?.dueCountsByDay ?? ({})
        const dueToday = Number(root.backend?.analytics?.dueToday ?? 0)
        const now = new Date(root.backend?._sessionClockMs ?? Date.now())
        const dayNames = ["S", "M", "T", "W", "T", "F", "S"]
        const days = []
        let maxCount = 1
        let total7d = 0
        for (let i = 0; i < 7; i++) {
            const d = new Date(now.getFullYear(), now.getMonth(), now.getDate() + i)
            const y = d.getFullYear()
            const m = String(d.getMonth() + 1).padStart(2, "0")
            const day = String(d.getDate()).padStart(2, "0")
            const key = `${y}-${m}-${day}`
            const cnt = i === 0 ? dueToday : Math.max(0, Number(dueByDay[key] ?? 0))
            if (cnt > maxCount) maxCount = cnt
            total7d += cnt
            days.push({
                label: i === 0 ? "Now" : dayNames[d.getDay()],
                dateStr: key,
                count: cnt,
                isToday: i === 0
            })
        }
        return { days: days, maxCount: maxCount, total7d: total7d }
    }

    function relativeLuminance(c): real {
        if (!c) return 0
        const chan = v => {
            const x = Math.max(0, Math.min(1, Number(v) || 0))
            return x <= 0.03928 ? x / 12.92 : Math.pow((x + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * chan(c.r) + 0.7152 * chan(c.g) + 0.0722 * chan(c.b)
    }

    readonly property color _heatFutureColor: ColorUtils.applyAlpha(Appearance.colors.colLayer2Base, 0.22)
    readonly property color _heatEmptyColor: ColorUtils.tonalStep(root.colAnalyticsSubBoxBg, root.tonalDir * 0.014, 1.04)
    readonly property color _heatLevel1Color: ColorUtils.mix(root.colAnalyticsSubBoxBg, Appearance.colors.colPrimary, 0.68)
    readonly property color _heatLevel2Color: ColorUtils.mix(root.colAnalyticsSubBoxBg, Appearance.colors.colPrimary, 0.46)
    readonly property color _heatLevel3Color: ColorUtils.mix(root.colAnalyticsSubBoxBg, Appearance.colors.colPrimary, 0.24)
    readonly property color _heatLevel4Color: Appearance.colors.colPrimary

    function heatmapCellColor(cell): color {
        if (!cell || !cell.inYear) return "transparent"
        if (cell.isFuture) return root._heatFutureColor
        const lvl = Number(cell.level) || 0
        if (lvl <= 0) return root._heatEmptyColor
        if (lvl === 1) return root._heatLevel1Color
        if (lvl === 2) return root._heatLevel2Color
        if (lvl === 3) return root._heatLevel3Color
        return root._heatLevel4Color
    }

    readonly property bool abyss: Config.options?.panelFamily === "abyss"
    readonly property bool alisEverywhere: Appearance.alisEverywhere
    readonly property bool auroraEverywhere: Appearance.auroraEverywhere

    // Anchor Layer 1 directly on Home Dashboard card color (DashCard / colLayer1Base)
    // and gently lift nested tiers by ~2.0% HSL so inner layers stay cohesive and restful.
    readonly property color colCardBase: ColorUtils.applyAlpha(
        Qt.color(Appearance.colors.colLayer1Base).valid
            ? Appearance.colors.colLayer1Base
            : Appearance.colors.colLayer0Base,
        1.0
    )
    readonly property bool isDarkSurface: Appearance.m3colors.darkmode
        || ColorUtils.relativeLuminance(root.colCardBase) < 0.35
    // Step lighter while headroom exists; subtly step deeper on near-white canvases
    readonly property real tonalDir: Qt.color(root.colCardBase).hslLightness > 0.86 ? -1 : 1

    // Layer 1 (main cards): matches Home Dashboard DashCard (AbyssStyle.contentLayer / colLayer1)
    readonly property color colSurface: abyss
        ? AbyssStyle.contentLayer
        : Appearance.angelEverywhere ? Appearance.angel.colGlassCard
        : alisEverywhere ? Appearance.alis.colLayer1
        : auroraEverywhere ? Appearance.aurora.colSubSurface
        : Appearance.colors.colLayer1
    // Layer 3+ (elevated options, chips, composer inputs): +5.2% HSL from Home Dashboard card base
    readonly property color colSurfaceElevated: abyss
        ? ColorUtils.applyAlpha(ColorUtils.tonalStep(root.colCardBase, root.tonalDir * 0.052, 1.08), Math.max(0.92, root.colSurface.a))
        : Appearance.angelEverywhere ? Appearance.angel.colGlassCardHover
        : alisEverywhere ? Appearance.alis.colLayer2
        : ColorUtils.applyAlpha(ColorUtils.tonalStep(root.colCardBase, root.tonalDir * 0.052, 1.08), Math.max(0.92, root.colSurface.a))
    // Layer 4 (hover & micro-badges inside elevated boxes): +7.4% HSL
    readonly property color colBoxHover: ColorUtils.applyAlpha(
        ColorUtils.tonalStep(root.colCardBase, root.tonalDir * 0.074, 1.10),
        Math.max(0.95, root.colSurface.a)
    )
    readonly property color colActivePillInk: ColorUtils.ensureReadable(
        Appearance.colors.colOnPrimary,
        Appearance.colors.colPrimary,
        5.0
    )
    // Stepped flat tonal layers for Analytics column:
    // colAnalyticsColumnBg (Layer 1) <= colAnalyticsCardBg (Layer 2) <= colAnalyticsSubBoxBg (Layer 3) < colSurfaceElevated
    readonly property color colAnalyticsColumnBg: ColorUtils.applyAlpha(
        root.colCardBase,
        root.colSurface.a
    )
    readonly property color colAnalyticsCardBg: ColorUtils.applyAlpha(
        ColorUtils.tonalStep(root.colCardBase, root.tonalDir * 0.020, 1.04),
        root.colSurface.a
    )
    readonly property color colAnalyticsSubBoxBg: ColorUtils.applyAlpha(
        ColorUtils.tonalStep(root.colCardBase, root.tonalDir * 0.040, 1.07),
        root.colSurface.a
    )
    readonly property color colAnalyticsBorder: ColorUtils.applyAlpha(
        Appearance.colors.colOutlineVariant,
        0.24
    )
    readonly property color colBorder: ColorUtils.applyAlpha(
        ColorUtils.tonalStep(root.colCardBase, root.tonalDir * 0.22, 1.10),
        0.07
    )
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

    readonly property var draftPreview: root.subTab === "capture"
        ? root.backend.analyzeDraft({
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
        : null
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
        if (root.subTab !== "library")
            return []
        const q = String(root.librarySearch || root.backend.searchQuery || "").trim().toLowerCase()
        const onlyLeeches = root.libraryLeechesOnly || root.backend.leechesOnly
        const bq = String(root.backend.searchQuery ?? "").trim().toLowerCase()
        if (q === bq && Boolean(onlyLeeches) === Boolean(root.backend.leechesOnly)
                && Array.isArray(root.backend.filteredLibraryCards)) {
            return root.backend.filteredLibraryCards
        }
        const list = root.backend.cards ?? []
        const cat = String(root.backend.selectedCategory ?? "all").toLowerCase()
        const lang = String(root.backend.selectedLanguage ?? "all").toLowerCase()
        const cefr = String(root.backend.selectedCefrLevel ?? "all").toUpperCase()
        const deck = root.backend.selectedDeck
        const leechThresh = root.backend.options?.leechThreshold ?? 6
        return list.filter(card => {
            if (!card) return false
            if (cat !== "all" && card.category !== cat) return false
            if (lang !== "all" && card.language !== lang) return false
            if (cefr !== "ALL" && String(card.cefrLevel ?? "").toUpperCase() !== cefr) return false
            if (deck !== "all" && card.deck !== deck) return false
            if (onlyLeeches && !card.isLeech && (Number(card.lapses) || 0) < leechThresh) return false
            if (!q.length) return true
            let hay = card._searchHay
            if (typeof hay !== "string") {
                hay = `${card.term ?? ""} ${card.front ?? ""} ${card.meaning ?? ""} ${card.back ?? ""} ${card.definitionEn ?? ""} ${card.meaningVi ?? ""} ${card.example ?? ""} ${card.cefrLevel ?? ""} ${card.deck ?? ""} ${card.notes ?? ""} ${card.morphologyText ?? ""} ${(card.collocations ?? []).join(" ")}`.toLowerCase()
                try {
                    Object.defineProperty(card, "_searchHay", { value: hay, enumerable: false, configurable: true })
                } catch (e) {}
            }
            return hay.includes(q)
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

    function maskedStudyText(raw, card, revealed = false): string {
        return Prompts.maskAnswer(raw, card, revealed)
    }

    function maskedClozeMeaningCue(card): string {
        const raw = String(card?.back || card?.definitionEn || card?.meaning || "")
        return root.maskedStudyText(raw, card, root.answerRevealed)
    }

    function formatContextExampleRich(card, revealed): string {
        if (!card) return ""
        const rawCloze = String(card.clozeText || card.example || "").trim()
        if (!rawCloze.length) return ""
        const highlightColor = "#38bdf8"
        const maskColor = "#94a3b8"
        if (/\{\{c\d+::/.test(rawCloze)) {
            if (revealed) {
                const escaped = root.escapeHtml(rawCloze)
                return escaped.replace(/\{\{c\d+::([^:}]+)(?:::([^}]+))?\}\}/g, (_, answer) => {
                    return `<b><font color="${highlightColor}"><u>${answer.trim()}</u></font></b>`
                })
            }
            const parts = rawCloze.split(/(\{\{c\d+::[^}]+\}\})/g)
            return parts.map(part => {
                const m = part.match(/^\{\{c\d+::([^:}]+)(?:::([^}]+))?\}\}$/)
                if (m) {
                    let safeHint = m[2] ? m[2].trim() : ""
                    if (safeHint.includes("—"))
                        safeHint = safeHint.split("—")[0].trim()
                    else if (safeHint.includes(" - "))
                        safeHint = safeHint.split(" - ")[0].trim()
                    if (safeHint && Prompts.containsAnswerForm(safeHint, card))
                        safeHint = ""
                    const label = safeHint ? `[ ${root.escapeHtml(safeHint)} ]` : "[ ... ]"
                    return `<b><font color="${maskColor}">${label}</font></b>`
                }
                const maskedSeg = Prompts.maskAnswer(part, card, false)
                return root.escapeHtml(maskedSeg).replace(/\[\.\.\.\]/g, `<b><font color="${maskColor}">[ ... ]</font></b>`)
            }).join("")
        }
        if (!revealed) {
            const maskedPlain = Prompts.maskAnswer(String(card.example || rawCloze), card, false)
            return root.escapeHtml(maskedPlain).replace(/\[\.\.\.\]/g, `<b><font color="${maskColor}">[ ... ]</font></b>`)
        }
        const plain = root.escapeHtml(card.example || rawCloze)
        const term = String(card.headword || card.term || card.front || "").replace(/^(der|die|das|sich)\s+/i, "").trim()
        if (!term.length) return plain
        const escTerm = term.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
        const re = new RegExp(`(\\b${escTerm}[a-zA-ZäöüÄÖÜß]{0,3}\\b)`, "gi")
        return plain.replace(re, `<b><font color="${highlightColor}"><u>$1</u></font></b>`)
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
            smartMixEnabled: root.backend.smartMixEnabled,
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
        if (typeof saved.smartMixEnabled === "boolean")
            root.backend.smartMixEnabled = saved.smartMixEnabled
        if (typeof saved.category === "string")
            root.backend.selectedCategory = saved.category
        if (typeof saved.language === "string")
            root.backend.selectedLanguage = saved.language
        if (typeof saved.cefrLevel === "string")
            root.backend.selectedCefrLevel = saved.cefrLevel
        if (typeof saved.deck === "string")
            root.backend.selectedDeck = saved.deck
        if (typeof saved.studyMode === "string") {
            const norm = typeof root.backend.normalizeStudyMode === "function"
                ? root.backend.normalizeStudyMode(saved.studyMode)
                : saved.studyMode
            if (["matching", "mc", "cloze", "flashcard"].includes(norm)) {
                const queueLen = root.backend.studyQueue?.length ?? 0
                const shouldRollSmart = root.backend.smartMixEnabled && typeof root.backend.rollNextStudyMode === "function" && (
                    (norm === "flashcard" && queueLen > 1)
                    || (norm === "matching" && queueLen > 0 && queueLen < 5)
                )
                if (shouldRollSmart) {
                    root.backend.rollNextStudyMode()
                } else {
                    root.backend.studyMode = norm
                }
            }
        }
    }

    function rebuildMatchingRound(): void {
        if (!root.backend || typeof root.backend.buildMatchingRound !== "function") {
            root.matchingLeftWords = []
            root.matchingRightDefs = []
            root.selectedMatchingLeftIndex = -1
            root.selectedMatchingRightIndex = -1
            root.mismatchLeftIndex = -1
            root.mismatchRightIndex = -1
            root.matchingRoundComplete = false
            root.matchingMatchedCount = 0
            root._matchingRoundActive = false
            root.requestMatchingLinesRepaint()
            return
        }
        const round = root.backend.buildMatchingRound()
        root.matchingLeftWords = Array.from(round?.leftWords ?? [])
        root.matchingRightDefs = Array.from(round?.rightDefs ?? [])
        root.selectedMatchingLeftIndex = -1
        root.selectedMatchingRightIndex = -1
        root.mismatchLeftIndex = -1
        root.mismatchRightIndex = -1
        root.matchingRoundComplete = false
        root.matchingMatchedCount = 0
        root._matchingRoundActive = root.matchingLeftWords.length > 0
        root.requestMatchingLinesRepaint()
    }

    function selectMatchingLeft(index: int): bool {
        if (!root.isMatchingMode || root.matchingRoundComplete) return false
        if (index < 0 || index >= root.matchingLeftWords.length) return false
        const wordItem = root.matchingLeftWords[index]
        if (!wordItem || wordItem.matched) return false
        matchingMismatchTimer.stop()
        root.mismatchLeftIndex = -1
        root.mismatchRightIndex = -1
        root.selectedMatchingLeftIndex = (root.selectedMatchingLeftIndex === index ? -1 : index)
        if (root.selectedMatchingLeftIndex >= 0 && root.selectedMatchingRightIndex >= 0) {
            root.evaluateMatchingSelection(root.selectedMatchingLeftIndex, root.selectedMatchingRightIndex)
        }
        root.requestMatchingLinesRepaint()
        root.focusPrimarySurface()
        return true
    }

    function selectMatchingRight(index: int): bool {
        if (!root.isMatchingMode || root.matchingRoundComplete) return false
        if (index < 0 || index >= root.matchingRightDefs.length) return false
        const defItem = root.matchingRightDefs[index]
        if (!defItem || defItem.matched) return false
        matchingMismatchTimer.stop()
        root.mismatchLeftIndex = -1
        root.mismatchRightIndex = -1
        root.selectedMatchingRightIndex = (root.selectedMatchingRightIndex === index ? -1 : index)
        if (root.selectedMatchingLeftIndex >= 0 && root.selectedMatchingRightIndex >= 0) {
            root.evaluateMatchingSelection(root.selectedMatchingLeftIndex, root.selectedMatchingRightIndex)
        }
        root.requestMatchingLinesRepaint()
        root.focusPrimarySurface()
        return true
    }

    function evaluateMatchingSelection(leftIdx: int, rightIdx: int): bool {
        if (leftIdx < 0 || leftIdx >= root.matchingLeftWords.length) return false
        if (rightIdx < 0 || rightIdx >= root.matchingRightDefs.length) return false
        const leftItem = root.matchingLeftWords[leftIdx]
        const rightItem = root.matchingRightDefs[rightIdx]
        if (!leftItem || !rightItem || leftItem.matched || rightItem.matched) return false

        const isMatch = !rightItem.isDistractor && String(rightItem.targetCardId) === String(leftItem.id)
        if (isMatch) {
            const nextLeft = root.matchingLeftWords.slice()
            nextLeft[leftIdx] = Object.assign({}, leftItem, { matched: true })
            const nextRight = root.matchingRightDefs.slice()
            nextRight[rightIdx] = Object.assign({}, rightItem, { matched: true })
            root.matchingLeftWords = nextLeft
            root.matchingRightDefs = nextRight
            root.selectedMatchingLeftIndex = -1
            root.selectedMatchingRightIndex = -1
            root.mismatchLeftIndex = -1
            root.mismatchRightIndex = -1

            if (leftItem.inQueue && root.backend && typeof root.backend.rateCardById === "function") {
                const mistakes = Number(leftItem.mistakeCount) || 0
                const srsRating = mistakes <= 1 ? "good" : (mistakes === 2 ? "hard" : "again")
                root._suppressMatchingQueueSync = true
                root.backend.rateCardById(leftItem.id, srsRating, false)
                root._suppressMatchingQueueSync = false
            }

            const matchedNow = nextLeft.filter(w => w && w.matched).length
            root.matchingMatchedCount = matchedNow
            if (matchedNow >= nextLeft.length && nextLeft.length > 0) {
                root.matchingRoundComplete = true
                root._matchingRoundActive = false
            }
            root.requestMatchingLinesRepaint()
            return true
        } else {
            const nextLeft = root.matchingLeftWords.slice()
            nextLeft[leftIdx] = Object.assign({}, leftItem, {
                mistakeCount: (Number(leftItem.mistakeCount) || 0) + 1
            })
            root.matchingLeftWords = nextLeft
            root.selectedMatchingLeftIndex = -1
            root.selectedMatchingRightIndex = -1
            root.mismatchLeftIndex = leftIdx
            root.mismatchRightIndex = rightIdx
            matchingMismatchTimer.restart()
            root.requestMatchingLinesRepaint()
            return false
        }
    }

    function finishMatchingRound(): void {
        root._matchingRoundActive = false
        root.matchingRoundComplete = false
        if (root.backend && root.backend.smartMixEnabled && typeof root.backend.rollNextStudyMode === "function") {
            root.backend.rollNextStudyMode()
        }
        root.resetCardInteraction(true)
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
        const allCards = root.backend?.cards ?? []
        const deckLen = Number(allCards.length) || 0
        const normPos = rawP => {
            const s = String(rawP ?? "").trim().toLowerCase()
            if (s === "adj") return "adjective"
            if (s === "adv") return "adverb"
            return s
        }
        const targetId = String(target.id ?? "")
        const targetPos = normPos(target.pos)
        const correctOption = root.toMultipleChoiceOption(target, targetId)
        const usedFronts = [correctOption.front.trim().toLowerCase()]
        const usedDefs = [correctOption.definitionEn.trim().toLowerCase()]
        const usedCues = [Prompts.visibleDefinitionKey(correctOption.definitionEn, correctOption)]

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
        const tryAddDistractor = cand => {
            if (!cand || distractors.length >= 3) return false
            const cid = String(cand.id ?? "")
            if (cid === targetId) return false
            const option = root.toMultipleChoiceOption(cand, targetId)
            const f = option.front.trim()
            const d = option.definitionEn.trim()
            if (!f.length || !d.length) return false
            const fKey = f.toLowerCase()
            const dKey = d.toLowerCase()
            if (usedFronts.includes(fKey) || usedDefs.includes(dKey)) return false
            if (Prompts.containsAnswerForm(f, target) || Prompts.containsAnswerForm(d, target)) return false
            const cue = Prompts.visibleDefinitionKey(d, option)
            if (usedCues.includes(cue)) return false
            usedFronts.push(fKey)
            usedDefs.push(dKey)
            usedCues.push(cue)
            distractors.push(option)
            return true
        }

        if (deckLen > 32) {
            if (targetPos.length > 0) {
                for (let p = 0; p < 64 && distractors.length < 3; p++) {
                    const cand = allCards[Math.floor(Math.random() * deckLen)]
                    if (cand
                            && cand.category === target.category
                            && cand.language === target.language
                            && normPos(cand.pos) === targetPos) {
                        tryAddDistractor(cand)
                    }
                }
            }
            for (let p = 0; p < 48 && distractors.length < 3; p++) {
                const cand = allCards[Math.floor(Math.random() * deckLen)]
                if (cand && cand.category === target.category && cand.language === target.language)
                    tryAddDistractor(cand)
            }
            for (let p = 0; p < 24 && distractors.length < 3; p++) {
                tryAddDistractor(allCards[Math.floor(Math.random() * deckLen)])
            }
        }

        if (distractors.length < 3) {
            const samePosLangCat = []
            const sameLangAndCat = []
            const sameCat = []
            const others = []
            for (let i = 0; i < deckLen; i++) {
                const c = allCards[i]
                if (!c || String(c.id ?? "") === targetId) continue
                const f = String(c.front || c.headword || c.term || "").trim()
                const d = String(c.definitionEn || c.back || c.meaning || "").trim()
                if (!f.length || !d.length) continue
                if (c.category === target.category && c.language === target.language) {
                    if (targetPos.length > 0 && normPos(c.pos) === targetPos)
                        samePosLangCat.push(c)
                    else
                        sameLangAndCat.push(c)
                } else if (c.category === target.category) {
                    sameCat.push(c)
                } else {
                    others.push(c)
                }
            }
            const fallbackDistractors = [
                { id: "fallback-1", front: "ubiquitous", headword: "ubiquitous", pos: "adj", cefrLevel: "C1", definitionEn: "present, appearing, or found everywhere", meaningVi: "phổ biến khắp nơi" },
                { id: "fallback-2", front: "ephemeral", headword: "ephemeral", pos: "adj", cefrLevel: "C1", definitionEn: "lasting for a very short time", meaningVi: "phù du, chóng tàn" },
                { id: "fallback-3", front: "resilient", headword: "resilient", pos: "adj", cefrLevel: "B2", definitionEn: "able to recover quickly from difficult conditions", meaningVi: "kiên cường, phục hồi nhanh" },
                { id: "fallback-4", front: "alleviate", headword: "alleviate", pos: "verb", cefrLevel: "C1", definitionEn: "to make suffering or a problem less severe", meaningVi: "làm dịu bớt, giảm nhẹ" }
            ]
            const candidatePool = [
                ...shuffle(samePosLangCat),
                ...shuffle(sameLangAndCat),
                ...shuffle(sameCat),
                ...shuffle(others),
                ...shuffle(fallbackDistractors)
            ]
            for (const cand of candidatePool) {
                if (distractors.length >= 3) break
                tryAddDistractor(cand)
            }
        }

        const combined = shuffle([correctOption, ...distractors])
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

    function selectClozeChoice(index: int): bool {
        if (!root.isClozeMode || root.answerRevealed) return false
        if (index < 0 || index >= root.multipleChoiceOptions.length) return false
        if (clozeInputField && (clozeInputField.focus || clozeInputField.activeFocus))
            clozeInputField.focus = false
        const opt = root.multipleChoiceOptions[index]
        const chosenTerm = String(opt?.headword || opt?.front || "").trim()
        root.pendingChoiceIndex = index
        root.selectedChoiceIndex = index
        root.typedClozeAttempt = chosenTerm
        if (clozeInputField && clozeInputField.text !== chosenTerm)
            clozeInputField.text = chosenTerm
        root.checkClozeAttempt()
        return true
    }

    function resetCardInteraction(forceRebuildMatching = false): void {
        if (clozeInputField && (clozeInputField.focus || clozeInputField.activeFocus))
            clozeInputField.focus = false
        root._activeStudyCardId = String(root.backend?.currentCard?.id ?? "")
        root.answerRevealed = false
        root.pendingChoiceIndex = -1
        root.selectedChoiceIndex = -1
        root.typedClozeAttempt = ""
        if (clozeInputField && clozeInputField.text !== "")
            clozeInputField.text = ""
        root.clozeCheckState = ""
        if (root.isMultipleChoiceMode || root.isClozeMode)
            root.rebuildMultipleChoiceOptions()
        if (root.isMatchingMode && (forceRebuildMatching || (!root._matchingRoundActive && !root.matchingRoundComplete))) {
            root.rebuildMatchingRound()
        }
        if (root.presentationActive && root.visible && root.subTab === "study")
            root.focusPrimarySurface()
    }

    function checkClozeAttempt(): void {
        const card = root.backend.currentCard
        if (!card) return
        if (clozeInputField && (clozeInputField.focus || clozeInputField.activeFocus))
            clozeInputField.focus = false
        const rawActual = (root.typedClozeAttempt || clozeInputField?.text || "").trim().toLowerCase()
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
        root._submittingReview = true
        root._activeStudyCardId = ""
        root.backend.submitRating(rating)
        root._submittingReview = false
        root.resetCardInteraction()
    }

    function syncComposerFieldsFromState(): void {
        if (composerFrontField && composerFrontField.text !== root.composerFront) composerFrontField.text = root.composerFront
        if (composerBackField && composerBackField.text !== root.composerBack) composerBackField.text = root.composerBack
        if (composerExampleField && composerExampleField.text !== root.composerExample) composerExampleField.text = root.composerExample
        if (composerDeckField && composerDeckField.text !== root.composerDeck) composerDeckField.text = root.composerDeck
        if (composerPhoneticsField && composerPhoneticsField.text !== root.composerPhonetics) composerPhoneticsField.text = root.composerPhonetics
        if (composerPosField && composerPosField.text !== root.composerPos) composerPosField.text = root.composerPos
        if (composerCefrField && composerCefrField.text !== root.composerCefrOverride) composerCefrField.text = root.composerCefrOverride
        if (composerSynonymsField && composerSynonymsField.text !== root.composerSynonyms) composerSynonymsField.text = root.composerSynonyms
        if (composerAntonymsField && composerAntonymsField.text !== root.composerAntonyms) composerAntonymsField.text = root.composerAntonyms
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
            if (bulkInputArea && bulkInputArea.text !== "")
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
        if (bulkInputArea && bulkInputArea.text !== sample)
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

    readonly property bool nonClozeTextInputFocused: Boolean(
        (sidebarQuickInput?.visible && sidebarQuickInput?.activeFocus)
        || (root.subTab === "capture" && (
            composerFrontField?.activeFocus
            || composerBackField?.activeFocus
            || composerExampleField?.activeFocus
            || composerDeckField?.activeFocus
            || composerPhoneticsField?.activeFocus
            || composerPosField?.activeFocus
            || composerCefrField?.activeFocus
            || composerSynonymsField?.activeFocus
            || composerAntonymsField?.activeFocus
            || bulkInputArea?.activeFocus))
        || (root.subTab === "library" && librarySearchField?.activeFocus))
    readonly property bool textInputFocused: Boolean((clozeInputField && clozeInputField.activeFocus && !clozeInputField.readOnly)
        || root.nonClozeTextInputFocused)
    readonly property bool windowNonClozeTextInputFocused: {
        const item = root.Window.activeFocusItem
        if (!item || item === clozeInputField) return false
        return Boolean(item.visible && item.enabled && item.readOnly === false
            && item.cursorPosition !== undefined)
    }
    readonly property bool windowTextInputFocused: {
        const item = root.Window.activeFocusItem
        return Boolean(item && item.visible && item.enabled && item.readOnly === false
            && item.cursorPosition !== undefined)
    }
    readonly property bool clozeNumericTypingActive: Boolean(root.isClozeMode
        && !root.answerRevealed
        && clozeInputField
        && clozeInputField.activeFocus
        && !clozeInputField.readOnly
        && clozeInputField.text.trim().length > 0
        && /\d/.test(String(root.backend.currentCard?.front || root.backend.currentCard?.term || root.backend.currentCard?.clozeText || "")))
    readonly property bool studyShortcutsActive: root.presentationActive
        && root.visible
        && root.subTab === "study"
        && !root.textInputFocused
        && !root.windowTextInputFocused
    readonly property bool studyDigitShortcutsActive: root.presentationActive
        && root.visible
        && root.subTab === "study"
        && !root.nonClozeTextInputFocused
        && !root.windowNonClozeTextInputFocused
        && !root.clozeNumericTypingActive
    property double _lastShortcutMs: 0
    property string _lastShortcutAction: ""

    function clearInactiveSubTabFocus(): void {
        if (root.subTab !== "library" && librarySearchField && (librarySearchField.focus || librarySearchField.activeFocus))
            librarySearchField.focus = false
        if (root.subTab !== "capture") {
            const captureFields = [
                composerFrontField, composerBackField, composerExampleField,
                composerDeckField, composerPhoneticsField, composerPosField,
                composerCefrField, composerSynonymsField, composerAntonymsField,
                bulkInputArea
            ]
            for (const f of captureFields) {
                if (f && (f.focus || f.activeFocus))
                    f.focus = false
            }
        }
        if (root.subTab !== "study" && clozeInputField && (clozeInputField.focus || clozeInputField.activeFocus))
            clozeInputField.focus = false
    }

    function focusPrimarySurface(): void {
        root.clearInactiveSubTabFocus()
        if ((!root.isClozeMode || root.answerRevealed) && clozeInputField && (clozeInputField.focus || clozeInputField.activeFocus))
            clozeInputField.focus = false
        if (!root.textInputFocused)
            root.forceActiveFocus()
    }

    function triggerStudyShortcut(action, allowFromClozeInput = false): bool {
        if (!root.presentationActive || !root.visible || root.subTab !== "study") return false
        const isDigitAction = action === "again" || action === "hard" || action === "good" || action === "easy"
            || action === "cloze-reveal" || action.startsWith("cloze-pick-")
            || action.startsWith("pick-") || action.startsWith("match-left-")
        if (allowFromClozeInput || isDigitAction) {
            if (root.nonClozeTextInputFocused || root.windowNonClozeTextInputFocused) return false
            if (clozeInputField && (clozeInputField.focus || clozeInputField.activeFocus))
                clozeInputField.focus = false
        } else {
            if (root.textInputFocused || root.windowTextInputFocused) return false
        }
        const now = Date.now()
        if (action === root._lastShortcutAction && (now - root._lastShortcutMs < 40)) return true
        if (action === "undo") {
            if (root.backend.undoLastReview()) {
                root._lastShortcutMs = now
                root._lastShortcutAction = action
                root._matchingRoundActive = false
                root.matchingRoundComplete = false
                root.resetCardInteraction(true)
                root.focusPrimarySurface()
                return true
            }
            return false
        }
        if (!root.showStudyArenaCard) return false
        if (action === "space") {
            if (root.isMatchingMode) {
                if (root.matchingRoundComplete) {
                    root._lastShortcutMs = now
                    root._lastShortcutAction = action
                    root.finishMatchingRound()
                }
                root.focusPrimarySurface()
                return true
            }
            if (!root.answerRevealed) {
                if (root.isMultipleChoiceMode) {
                    if (root.pendingChoiceIndex >= 0 && root.pendingChoiceIndex < root.multipleChoiceOptions.length) {
                        root._lastShortcutMs = now
                        root._lastShortcutAction = action
                        root.selectMultipleChoiceOption(root.pendingChoiceIndex)
                        return true
                    }
                    root.focusPrimarySurface()
                    return true
                }
                root._lastShortcutMs = now
                root._lastShortcutAction = action
                root.answerRevealed = true
            }
            root.focusPrimarySurface()
            return true
        }
        if (action === "enter") {
            if (root.isMatchingMode) {
                if (root.matchingRoundComplete) {
                    root._lastShortcutMs = now
                    root._lastShortcutAction = action
                    root.finishMatchingRound()
                    return true
                }
                return false
            }
            if (!root.answerRevealed && !root.isMultipleChoiceMode) {
                root._lastShortcutMs = now
                root._lastShortcutAction = action
                if (root.isClozeMode)
                    root.checkClozeAttempt()
                else
                    root.answerRevealed = true
                root.focusPrimarySurface()
                return true
            }
            return false
        }
        if (action === "cloze-reveal" && !root.answerRevealed && root.isClozeMode) {
            root._lastShortcutMs = now
            root._lastShortcutAction = action
            root.checkClozeAttempt()
            root.focusPrimarySurface()
            return true
        }
        if (action.startsWith("cloze-pick-") && !root.answerRevealed && root.isClozeMode) {
            const idx = parseInt(action.slice(11), 10)
            if (root.selectClozeChoice(idx)) {
                root._lastShortcutMs = now
                root._lastShortcutAction = action
                return true
            }
            return false
        }
        if (action.startsWith("match-left-") && root.isMatchingMode && !root.matchingRoundComplete) {
            const idx = parseInt(action.slice(11), 10)
            if (root.selectMatchingLeft(idx)) {
                root._lastShortcutMs = now
                root._lastShortcutAction = action
                return true
            }
            return false
        }
        if (action.startsWith("match-right-") && root.isMatchingMode && !root.matchingRoundComplete) {
            const idx = parseInt(action.slice(12), 10)
            if (root.selectMatchingRight(idx)) {
                root._lastShortcutMs = now
                root._lastShortcutAction = action
                return true
            }
            return false
        }
        if (action.startsWith("pick-") && !root.answerRevealed && root.isMultipleChoiceMode) {
            const idx = parseInt(action.slice(5), 10)
            if (root.stageMultipleChoiceOption(idx)) {
                root._lastShortcutMs = now
                root._lastShortcutAction = action
                return true
            }
            return false
        }
        if (action === "noop-mc-letter" && root.isMultipleChoiceMode) {
            root.focusPrimarySurface()
            return true
        }
        if (action === "mode") {
            root._lastShortcutMs = now
            root._lastShortcutAction = action
            const modes = ["matching", "mc", "cloze", "flashcard"]
            const next = modes[(modes.indexOf(root.backend.studyMode) + 1) % modes.length]
            root.backend.smartMixEnabled = false
            root.backend.studyMode = next
            root._matchingRoundActive = false
            root.matchingRoundComplete = false
            root.resetCardInteraction(true)
            root.storeBrowserState()
            root.focusPrimarySurface()
            return true
        }
        if (root.answerRevealed && !root.isMatchingMode && (action === "again" || action === "hard" || action === "good" || action === "easy")) {
            root._lastShortcutMs = now
            root._lastShortcutAction = action
            root.submitReviewRating(action)
            root.focusPrimarySurface()
            return true
        }
        return false
    }

    function _shouldResetMatchingRoundFromQueue(): bool {
        if (root.matchingRoundComplete)
            return false
        const queueList = root.backend?.studyQueue ?? []
        const inQueueWords = (root.matchingLeftWords ?? []).filter(w => w && w.inQueue)
        if (root.matchingMatchedCount === 0) {
            const currentQueueIds = queueList.slice(0, 5).map(c => String(c?.id ?? "")).join(",")
            const roundQueueIds = inQueueWords.map(w => String(w.id ?? "")).join(",")
            return currentQueueIds !== roundQueueIds
        }
        const queueIdSet = new Set(queueList.map(c => String(c?.id ?? "")))
        const unmatchedInQueue = inQueueWords.filter(w => !w.matched)
        return unmatchedInQueue.some(w => !queueIdSet.has(String(w.id ?? "")))
    }

    onSubTabChanged: {
        root.clearInactiveSubTabFocus()
        root.syncLazyLoaderFlags()
        root.storeBrowserState()
        if (root.presentationActive)
            root.focusPrimarySurface()
    }
    property bool _canvasesSettled: false
    Timer {
        id: _canvasSettleTimer
        interval: 160
        repeat: false
        onTriggered: {
            root._canvasesSettled = true
        }
    }

    onPresentationActiveChanged: {
        if (root.presentationActive && root.backend && typeof root.backend.ensureLoaded === "function")
            root.backend.ensureLoaded()
        if (root.presentationActive && root.backend && typeof root.backend.refreshClock === "function")
            root.backend.refreshClock()
        if (root.presentationActive && !root._canvasesSettled)
            _canvasSettleTimer.restart()
        if (root.presentationActive && root.subTab === "study")
            root.focusPrimarySurface()
    }
    onVisibleChanged: {
        if (root.visible && root.backend && typeof root.backend.ensureLoaded === "function")
            root.backend.ensureLoaded()
        if (root.visible && root.backend && typeof root.backend.refreshClock === "function")
            root.backend.refreshClock()
        if (root.visible && !root._canvasesSettled)
            _canvasSettleTimer.restart()
        if (root.visible && root.presentationActive && root.subTab === "study")
            Qt.callLater(() => root.focusPrimarySurface())
    }

    Connections {
        target: root.backend
        function onCurrentCardChanged(): void {
            if (root._suppressMatchingQueueSync)
                return
            if (root.isMatchingMode) {
                if (root._shouldResetMatchingRoundFromQueue()) {
                    root._matchingRoundActive = false
                    root.matchingRoundComplete = false
                    root.resetCardInteraction(true)
                    return
                }
                if (root._matchingRoundActive || root.matchingRoundComplete)
                    return
            } else {
                const nextCardId = String(root.backend?.currentCard?.id ?? "")
                if (nextCardId.length > 0
                        && nextCardId === root._activeStudyCardId
                        && (!root.isMultipleChoiceMode || root.multipleChoiceOptions.length > 0)) {
                    return
                }
            }
            root.resetCardInteraction()
        }
        function onCardReviewed(): void {
            if (root._suppressMatchingQueueSync || root._submittingReview)
                return
            root._activeStudyCardId = ""
            root.resetCardInteraction()
        }
        function onStudyQueueChanged(): void {
            if (root._suppressMatchingQueueSync)
                return
            if (root.isMatchingMode) {
                if (root._shouldResetMatchingRoundFromQueue()) {
                    root._matchingRoundActive = false
                    root.matchingRoundComplete = false
                    const queueLen = root.backend?.studyQueue?.length ?? 0
                    if (root.backend?.smartMixEnabled && queueLen > 0 && queueLen < 5 && typeof root.backend.rollNextStudyMode === "function") {
                        root.backend.rollNextStudyMode()
                    }
                    root.resetCardInteraction(true)
                }
            }
        }
        function onCardsChanged(): void {
            if (root._suppressMatchingQueueSync)
                return
            if ((root.isMultipleChoiceMode || root.isClozeMode)
                    && !root.answerRevealed
                    && root.pendingChoiceIndex < 0
                    && (root.multipleChoiceOptions.length < 4 || root.multipleChoiceOptions.some(o => String(o?.id ?? "").startsWith("fallback-"))))
                root.rebuildMultipleChoiceOptions()
            if (root.isMatchingMode && !root._matchingRoundActive && !root.matchingRoundComplete && root.matchingLeftWords.length === 0)
                root.rebuildMatchingRound()
        }
        function onStudyModeChanged(): void {
            root.typedClozeAttempt = ""
            if (clozeInputField && clozeInputField.text !== "")
                clozeInputField.text = ""
            root.clozeCheckState = ""
            if (clozeInputField && (clozeInputField.focus || clozeInputField.activeFocus))
                clozeInputField.focus = false
            root._matchingRoundActive = false
            root.matchingRoundComplete = false
            if (root.isMultipleChoiceMode || root.isClozeMode)
                root.rebuildMultipleChoiceOptions()
            if (root.isMatchingMode)
                root.rebuildMatchingRound()
            if (root.presentationActive && root.visible && root.subTab === "study")
                root.focusPrimarySurface()
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
        root.syncBackendActivityFlags()
        if (root.backend && typeof root.backend.ensureLoaded === "function")
            root.backend.ensureLoaded()
        if (root.backend && typeof root.backend.refreshClock === "function")
            root.backend.refreshClock()
        root.restoreBrowserState()
        root.syncLazyLoaderFlags()
        root._activeStudyCardId = String(root.backend?.currentCard?.id ?? "")
        if (root.isMultipleChoiceMode || root.isClozeMode)
            root.rebuildMultipleChoiceOptions()
        if (root.isMatchingMode)
            root.rebuildMatchingRound()
        _canvasSettleTimer.restart()
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape && root.handleEscape()) {
            event.accepted = true
            return
        }
        if (!root.presentationActive || root.subTab !== "study") return
        if (root.nonClozeTextInputFocused || root.windowNonClozeTextInputFocused) return
        if (event.modifiers & Qt.ControlModifier && event.key === Qt.Key_Z) {
            if (root.triggerStudyShortcut("undo"))
                event.accepted = true
            return
        }
        if (!root.showStudyArenaCard) return
        const isDigitKey = event.key === Qt.Key_0 || event.key === Qt.Key_1 || event.key === Qt.Key_2 || event.key === Qt.Key_3 || event.key === Qt.Key_4 || event.key === Qt.Key_5
        if (isDigitKey && root.clozeNumericTypingActive) return
        if (!isDigitKey && (root.textInputFocused || root.windowTextInputFocused)) return
        if (event.key === Qt.Key_Space) {
            if (root.triggerStudyShortcut("space"))
                event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (root.triggerStudyShortcut("enter"))
                event.accepted = true
        } else if (root.isMatchingMode && !root.matchingRoundComplete) {
            if (event.key === Qt.Key_1) {
                if (root.triggerStudyShortcut("match-left-0")) event.accepted = true
            } else if (event.key === Qt.Key_2) {
                if (root.triggerStudyShortcut("match-left-1")) event.accepted = true
            } else if (event.key === Qt.Key_3) {
                if (root.triggerStudyShortcut("match-left-2")) event.accepted = true
            } else if (event.key === Qt.Key_4) {
                if (root.triggerStudyShortcut("match-left-3")) event.accepted = true
            } else if (event.key === Qt.Key_5) {
                if (root.triggerStudyShortcut("match-left-4")) event.accepted = true
            } else if (event.key === Qt.Key_A || event.key === Qt.Key_Q) {
                if (root.triggerStudyShortcut("match-right-0")) event.accepted = true
            } else if (event.key === Qt.Key_B || event.key === Qt.Key_W) {
                if (root.triggerStudyShortcut("match-right-1")) event.accepted = true
            } else if (event.key === Qt.Key_C) {
                if (root.triggerStudyShortcut("match-right-2")) event.accepted = true
            } else if (event.key === Qt.Key_D || event.key === Qt.Key_R) {
                if (root.triggerStudyShortcut("match-right-3")) event.accepted = true
            } else if (event.key === Qt.Key_E || event.key === Qt.Key_T) {
                if (root.triggerStudyShortcut("match-right-4")) event.accepted = true
            } else if (event.key === Qt.Key_F || event.key === Qt.Key_Y) {
                if (root.triggerStudyShortcut("match-right-5")) event.accepted = true
            } else if (event.key === Qt.Key_M && !(event.modifiers & Qt.ControlModifier)) {
                if (root.triggerStudyShortcut("mode")) event.accepted = true
            }
        } else if (!root.answerRevealed && root.isClozeMode && event.key === Qt.Key_0) {
            if (root.triggerStudyShortcut("cloze-reveal"))
                event.accepted = true
        } else if (!root.answerRevealed && root.isClozeMode && event.key === Qt.Key_1) {
            if (root.triggerStudyShortcut("cloze-pick-0"))
                event.accepted = true
        } else if (!root.answerRevealed && root.isClozeMode && event.key === Qt.Key_2) {
            if (root.triggerStudyShortcut("cloze-pick-1"))
                event.accepted = true
        } else if (!root.answerRevealed && root.isClozeMode && event.key === Qt.Key_3) {
            if (root.triggerStudyShortcut("cloze-pick-2"))
                event.accepted = true
        } else if (!root.answerRevealed && root.isClozeMode && event.key === Qt.Key_4) {
            if (root.triggerStudyShortcut("cloze-pick-3"))
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
        } else if (root.answerRevealed && root.isMultipleChoiceMode
                && (event.key === Qt.Key_A || event.key === Qt.Key_B || event.key === Qt.Key_C || event.key === Qt.Key_D)) {
            if (root.triggerStudyShortcut("noop-mc-letter"))
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
        } else if (root.answerRevealed && (event.key === Qt.Key_3 || event.key === Qt.Key_4)) {
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
        enabled: root.studyShortcutsActive && root.showStudyArenaCard
        onActivated: root.triggerStudyShortcut("space")
    }
    Shortcut {
        sequences: ["Return", "Enter"]
        context: Qt.WindowShortcut
        autoRepeat: false
        enabled: root.studyShortcutsActive && root.showStudyArenaCard && ((!root.answerRevealed && !root.isMultipleChoiceMode && !root.isMatchingMode) || (root.isMatchingMode && root.matchingRoundComplete))
        onActivated: root.triggerStudyShortcut("enter")
    }
    Shortcut {
        sequences: ["0"]
        context: Qt.WindowShortcut
        autoRepeat: false
        enabled: root.studyDigitShortcutsActive && root.backend.hasActiveCard && !root.isMatchingMode && (root.answerRevealed || root.isClozeMode)
        onActivated: root.triggerStudyShortcut(root.answerRevealed ? "again" : "cloze-reveal")
    }
    Shortcut {
        sequences: ["1"]
        context: Qt.WindowShortcut
        autoRepeat: false
        enabled: root.studyDigitShortcutsActive && root.showStudyArenaCard && (root.answerRevealed || root.isMultipleChoiceMode || root.isClozeMode || (root.isMatchingMode && !root.matchingRoundComplete))
        onActivated: root.triggerStudyShortcut(root.isMatchingMode ? "match-left-0" : (root.answerRevealed ? "hard" : (root.isClozeMode ? "cloze-pick-0" : "pick-0")))
    }
    Shortcut {
        sequences: ["2"]
        context: Qt.WindowShortcut
        autoRepeat: false
        enabled: root.studyDigitShortcutsActive && root.showStudyArenaCard && (root.answerRevealed || root.isMultipleChoiceMode || root.isClozeMode || (root.isMatchingMode && !root.matchingRoundComplete))
        onActivated: root.triggerStudyShortcut(root.isMatchingMode ? "match-left-1" : (root.answerRevealed ? "good" : (root.isClozeMode ? "cloze-pick-1" : "pick-1")))
    }
    Shortcut {
        sequences: ["3"]
        context: Qt.WindowShortcut
        autoRepeat: false
        enabled: root.studyDigitShortcutsActive && root.showStudyArenaCard && (root.answerRevealed || root.isMultipleChoiceMode || root.isClozeMode || (root.isMatchingMode && !root.matchingRoundComplete))
        onActivated: root.triggerStudyShortcut(root.isMatchingMode ? "match-left-2" : (root.answerRevealed ? "easy" : (root.isClozeMode ? "cloze-pick-2" : "pick-2")))
    }
    Shortcut {
        sequences: ["4"]
        context: Qt.WindowShortcut
        autoRepeat: false
        enabled: root.studyDigitShortcutsActive && root.showStudyArenaCard && (root.answerRevealed || (!root.answerRevealed && (root.isMultipleChoiceMode || root.isClozeMode)) || (root.isMatchingMode && !root.matchingRoundComplete))
        onActivated: root.triggerStudyShortcut(root.isMatchingMode ? "match-left-3" : (root.answerRevealed ? "easy" : (root.isClozeMode ? "cloze-pick-3" : "pick-3")))
    }
    Shortcut {
        sequences: ["5"]
        context: Qt.WindowShortcut
        autoRepeat: false
        enabled: root.studyDigitShortcutsActive && root.showStudyArenaCard && root.isMatchingMode && !root.matchingRoundComplete
        onActivated: root.triggerStudyShortcut("match-left-4")
    }
    Shortcut {
        sequences: ["A", "Shift+A"]
        context: Qt.WindowShortcut
        autoRepeat: false
        enabled: root.studyShortcutsActive && root.showStudyArenaCard && (root.isMultipleChoiceMode || (root.isMatchingMode && !root.matchingRoundComplete))
        onActivated: root.triggerStudyShortcut(root.isMatchingMode ? "match-right-0" : (root.answerRevealed ? "noop-mc-letter" : "pick-0"))
    }
    Shortcut {
        sequences: ["B", "Shift+B"]
        context: Qt.WindowShortcut
        autoRepeat: false
        enabled: root.studyShortcutsActive && root.showStudyArenaCard && (root.isMultipleChoiceMode || (root.isMatchingMode && !root.matchingRoundComplete))
        onActivated: root.triggerStudyShortcut(root.isMatchingMode ? "match-right-1" : (root.answerRevealed ? "noop-mc-letter" : "pick-1"))
    }
    Shortcut {
        sequences: ["C", "Shift+C"]
        context: Qt.WindowShortcut
        autoRepeat: false
        enabled: root.studyShortcutsActive && root.showStudyArenaCard && (root.isMultipleChoiceMode || (root.isMatchingMode && !root.matchingRoundComplete))
        onActivated: root.triggerStudyShortcut(root.isMatchingMode ? "match-right-2" : (root.answerRevealed ? "noop-mc-letter" : "pick-2"))
    }
    Shortcut {
        sequences: ["D", "Shift+D"]
        context: Qt.WindowShortcut
        autoRepeat: false
        enabled: root.studyShortcutsActive && root.showStudyArenaCard && (root.isMultipleChoiceMode || (root.isMatchingMode && !root.matchingRoundComplete))
        onActivated: root.triggerStudyShortcut(root.isMatchingMode ? "match-right-3" : (root.answerRevealed ? "noop-mc-letter" : "pick-3"))
    }
    Shortcut {
        sequences: ["E"]
        context: Qt.WindowShortcut
        autoRepeat: false
        enabled: root.studyShortcutsActive && root.showStudyArenaCard && root.isMatchingMode && !root.matchingRoundComplete
        onActivated: root.triggerStudyShortcut("match-right-4")
    }
    Shortcut {
        sequences: ["F"]
        context: Qt.WindowShortcut
        autoRepeat: false
        enabled: root.studyShortcutsActive && root.showStudyArenaCard && root.isMatchingMode && !root.matchingRoundComplete
        onActivated: root.triggerStudyShortcut("match-right-5")
    }
    Shortcut {
        sequences: ["M"]
        context: Qt.WindowShortcut
        autoRepeat: false
        enabled: root.studyShortcutsActive && root.showStudyArenaCard
        onActivated: root.triggerStudyShortcut("mode")
    }
    Shortcut {
        sequences: ["Ctrl+Z"]
        context: Qt.WindowShortcut
        autoRepeat: false
        enabled: root.studyShortcutsActive && root.backend.canUndoReview
        onActivated: root.triggerStudyShortcut("undo")
    }

    component FilterChip: RippleButton {
        id: chip
        focusPolicy: Qt.NoFocus
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
            : root.colBoxHover
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
        property real maxStripWidth: 560
        visible: morphPill.morphText.length > 0
        implicitHeight: 22
        implicitWidth: Math.min(morphPill.maxStripWidth, morphRow.implicitWidth + 16)
        radius: 6
        color: root.colAnalyticsSubBoxBg
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
                width: Math.min(Math.max(120, morphPill.maxStripWidth - 28), implicitWidth)
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
        color: root.colSurfaceElevated
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
                        root._matchingRoundActive = false
                        root.matchingRoundComplete = false
                        root.resetCardInteraction(true)
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
                    onClicked: GlobalStates.openSettingsSection(38, Translation.tr("Spaced Repetition"))
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

                            FilterChip {
                                objectName: "srStudyMode-smart"
                                iconName: "auto_awesome"
                                label: Translation.tr("Smart Mix")
                                tooltipText: Translation.tr("Randomly combine Matching, Multiple Choice, and Cloze Reading when multiple cards are due (Flashcard as last resort)")
                                activeChip: root.backend.smartMixEnabled
                                badgeColor: Appearance.colors.colPrimary
                                onClicked: {
                                    root.backend.smartMixEnabled = true
                                    root._matchingRoundActive = false
                                    root.matchingRoundComplete = false
                                    if (typeof root.backend.rollNextStudyMode === "function")
                                        root.backend.rollNextStudyMode()
                                    root.resetCardInteraction(true)
                                    root.storeBrowserState()
                                }
                            }

                            Rectangle {
                                width: 1
                                Layout.fillHeight: true
                                Layout.topMargin: 6
                                Layout.bottomMargin: 6
                                color: root.colBorder
                            }

                            Repeater {
                                model: [
                                    { id: "matching", label: Translation.tr("Matching Mode (5 Words → 6 Definitions with 1 Distractor)"), icon: "join_inner" },
                                    { id: "mc", label: Translation.tr("Multiple Choice Mode (1 Term → 4 Definitions)"), icon: "quiz" },
                                    { id: "cloze", label: Translation.tr("Cloze Reading / Type-Check Mode"), icon: "edit_note" },
                                    { id: "flashcard", label: Translation.tr("Flashcard Mode (Fallback / Last Resort)"), icon: "style" }
                                ]
                                delegate: FilterChip {
                                    required property var modelData
                                    objectName: "srStudyMode-" + modelData.id
                                    iconName: modelData.icon
                                    label: ""
                                    tooltipText: modelData.label
                                    activeChip: root.backend.studyMode === modelData.id
                                    onClicked: {
                                        if (!root.backend.smartMixEnabled && root.backend.studyMode === modelData.id) {
                                            root.backend.smartMixEnabled = true
                                            root._matchingRoundActive = false
                                            root.matchingRoundComplete = false
                                            if (typeof root.backend.rollNextStudyMode === "function")
                                                root.backend.rollNextStudyMode()
                                        } else {
                                            root.backend.smartMixEnabled = false
                                            root._matchingRoundActive = false
                                            root.matchingRoundComplete = false
                                            root.backend.studyMode = modelData.id
                                        }
                                        root.resetCardInteraction(true)
                                        root.storeBrowserState()
                                    }
                                }
                            }

                            StyledText {
                                objectName: "srActiveStudyModeLabel"
                                text: root.backend.studyMode === "matching"
                                    ? Translation.tr("Matching")
                                    : root.backend.studyMode === "mc"
                                    ? Translation.tr("Multiple Choice")
                                    : root.backend.studyMode === "cloze"
                                    ? Translation.tr("Cloze Reading")
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

                    // Active Study Box
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: root.showStudyArenaCard
                        radius: Appearance.rounding.small
                        color: root.colSurface
                        border.width: 0
                        clip: true

                        TapHandler {
                            onTapped: {
                                if (root.subTab === "study" && !root.textInputFocused)
                                    root.focusPrimarySurface()
                            }
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 20
                            spacing: 14

                            // Card Metadata Header (hidden in Matching mode where 5 cards are shown side-by-side)
                            RowLayout {
                                Layout.fillWidth: true
                                visible: !root.isMatchingMode
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

                            // =========================================================
                            // MATCHING MODE BOARD (2 Columns: 5 Words Left, 6 Definitions Right)
                            // =========================================================
                            Loader {
                                id: matchingBoardLoader
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                active: root._matchingViewLoaded
                                visible: root.isMatchingMode
                                sourceComponent: Component {
                                    ColumnLayout {
                                        id: srMatchingBoard
                                        objectName: "srMatchingBoard"
                                        spacing: 10

                                // Matching Header & Progress
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10

                                    MaterialSymbol {
                                        text: "join_inner"
                                        iconSize: 18
                                        color: Appearance.colors.colPrimary
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        wrapMode: Text.WordWrap
                                        text: Translation.tr("Match each vocabulary word on the left (1–5) with its definition on the right (A–F). One extra definition is a distractor.")
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: root.colSubtext
                                    }

                                    Rectangle {
                                        objectName: "srMatchingProgressBadge"
                                        implicitHeight: 24
                                        implicitWidth: matchProgText.implicitWidth + 16
                                        radius: Appearance.rounding.full
                                        color: root.matchingRoundComplete
                                            ? Qt.alpha("#10b981", 0.18)
                                            : Qt.alpha(Appearance.colors.colPrimary, 0.14)

                                        StyledText {
                                            id: matchProgText
                                            anchors.centerIn: parent
                                            text: Translation.tr("%1 / %2 matched").arg(root.matchingMatchedCount).arg(root.matchingLeftWords.length)
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            font.weight: Font.Bold
                                            color: root.matchingRoundComplete ? "#10b981" : Appearance.colors.colPrimary
                                        }
                                    }
                                }

                                // 2-Column Matching Arena with Middle Line-Drawing Corridor
                                Item {
                                    id: matchingArenaContainer
                                    objectName: "srMatchingArenaContainer"
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true

                                    RowLayout {
                                        id: matchingColumnsRow
                                        anchors.fill: parent
                                        spacing: 0

                                        // LEFT COLUMN: 5 Compact Vocabulary Words
                                        ColumnLayout {
                                            id: srMatchingLeftColumn
                                            objectName: "srMatchingLeftColumn"
                                            Layout.fillWidth: false
                                            Layout.fillHeight: true
                                            Layout.preferredWidth: Math.round(Math.min(240, Math.max(155, matchingColumnsRow.width * 0.27)))
                                            Layout.minimumWidth: 150
                                            Layout.maximumWidth: Math.round(Math.max(190, matchingColumnsRow.width * 0.30))
                                            spacing: 6
                                            onXChanged: root.requestMatchingLinesRepaint()
                                            onWidthChanged: root.requestMatchingLinesRepaint()

                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 6
                                                StyledText {
                                                    text: Translation.tr("VOCABULARY · TỪ VỰNG (%1)").arg(root.matchingLeftWords.length)
                                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                                    font.weight: Font.Bold
                                                    font.letterSpacing: 0.5
                                                    color: root.colSubtext
                                                }
                                                Item { Layout.fillWidth: true }
                                            }

                                            Repeater {
                                                id: matchingLeftRepeater
                                                model: root.matchingLeftWords
                                                delegate: RippleButton {
                                                    id: matchWordBtn
                                                    focusPolicy: Qt.NoFocus
                                                    required property var modelData
                                                    required property int index
                                                    objectName: "srMatchingLeftWord-" + index
                                                    Layout.fillWidth: true
                                                    Layout.fillHeight: true
                                                    Layout.minimumHeight: 38
                                                    implicitHeight: Math.max(40, matchWordRow.implicitHeight + 12)
                                                    buttonRadius: Appearance.rounding.small
                                                    enabled: !Boolean(modelData.matched) && !root.matchingRoundComplete
                                                    opacity: modelData.matched ? 0.68 : 1.0
                                                    readonly property bool isSelected: root.selectedMatchingLeftIndex === index
                                                    readonly property bool isMismatch: root.mismatchLeftIndex === index
                                                    readonly property color stateAccent: modelData.matched
                                                        ? ColorUtils.mix(Appearance.colors.colPrimary, "#10b981", 0.45)
                                                        : isMismatch
                                                        ? Appearance.colors.colError
                                                        : isSelected
                                                        ? Appearance.colors.colPrimary
                                                        : root.colSubtext

                                                    colBackground: modelData.matched
                                                        ? Qt.alpha("#10b981", 0.14)
                                                        : isMismatch
                                                        ? Qt.alpha(Appearance.colors.colError, 0.18)
                                                        : isSelected
                                                        ? Qt.alpha(Appearance.colors.colPrimary, 0.16)
                                                        : root.colSurfaceElevated
                                                    colBackgroundHover: modelData.matched
                                                        ? colBackground
                                                        : Qt.alpha(Appearance.colors.colPrimary, isSelected ? 0.22 : 0.12)

                                                    onClicked: root.selectMatchingLeft(index)
                                                    onXChanged: root.requestMatchingLinesRepaint()
                                                    onYChanged: root.requestMatchingLinesRepaint()
                                                    onWidthChanged: root.requestMatchingLinesRepaint()
                                                    onHeightChanged: root.requestMatchingLinesRepaint()

                                                    Rectangle {
                                                        anchors.fill: parent
                                                        radius: matchWordBtn.buttonRadius
                                                        color: "transparent"
                                                        border.width: (matchWordBtn.modelData.matched || matchWordBtn.isSelected || matchWordBtn.isMismatch) ? 1.5 : 1
                                                        border.color: (matchWordBtn.modelData.matched || matchWordBtn.isSelected || matchWordBtn.isMismatch)
                                                            ? matchWordBtn.stateAccent
                                                            : root.colBorder
                                                    }

                                                    contentItem: Item {
                                                        RowLayout {
                                                            id: matchWordRow
                                                            anchors.left: parent.left
                                                            anchors.right: parent.right
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            anchors.leftMargin: 8
                                                            anchors.rightMargin: 8
                                                            spacing: 6

                                                            Rectangle {
                                                                Layout.alignment: Qt.AlignVCenter
                                                                implicitWidth: 20
                                                                implicitHeight: 20
                                                                radius: 5
                                                                color: (matchWordBtn.modelData.matched || matchWordBtn.isSelected || matchWordBtn.isMismatch)
                                                                    ? Qt.alpha(matchWordBtn.stateAccent, 0.24)
                                                                    : root.colBoxHover
                                                                StyledText {
                                                                    anchors.centerIn: parent
                                                                    text: String(matchWordBtn.index + 1)
                                                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                                                    font.weight: Font.Bold
                                                                    color: (matchWordBtn.modelData.matched || matchWordBtn.isSelected || matchWordBtn.isMismatch)
                                                                        ? matchWordBtn.stateAccent
                                                                        : root.colSubtext
                                                                }
                                                            }

                                                            ColumnLayout {
                                                                Layout.fillWidth: true
                                                                Layout.alignment: Qt.AlignVCenter
                                                                spacing: 1

                                                                RowLayout {
                                                                    Layout.fillWidth: true
                                                                    spacing: 5

                                                                    Rectangle {
                                                                        visible: Boolean(matchWordBtn.modelData.gender)
                                                                        implicitHeight: 16
                                                                        implicitWidth: mwGenderTxt.implicitWidth + 8
                                                                        radius: 4
                                                                        color: Qt.alpha(root.genderColor(matchWordBtn.modelData.gender), 0.16)
                                                                        StyledText {
                                                                            id: mwGenderTxt
                                                                            anchors.centerIn: parent
                                                                            text: matchWordBtn.modelData.gender ?? ""
                                                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                                                            font.weight: Font.Bold
                                                                            color: root.genderColor(matchWordBtn.modelData.gender)
                                                                        }
                                                                    }

                                                                    StyledText {
                                                                        objectName: "srMatchingLeftWordText-" + matchWordBtn.index
                                                                        Layout.fillWidth: true
                                                                        wrapMode: Text.WordWrap
                                                                        text: matchWordBtn.modelData.front ?? ""
                                                                        font.pixelSize: Appearance.font.pixelSize.small
                                                                        font.weight: Font.Bold
                                                                        color: root.colText
                                                                    }
                                                                }

                                                                RowLayout {
                                                                    visible: Boolean(matchWordBtn.modelData.phonetics || matchWordBtn.modelData.pos || matchWordBtn.modelData.cefrLevel)
                                                                    spacing: 5

                                                                    StyledText {
                                                                        visible: Boolean(matchWordBtn.modelData.phonetics)
                                                                        text: matchWordBtn.modelData.phonetics ?? ""
                                                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                                                        color: Appearance.colors.colPrimary
                                                                    }

                                                                    StyledText {
                                                                        visible: Boolean(matchWordBtn.modelData.pos)
                                                                        text: root.formatPosLabel(matchWordBtn.modelData.pos)
                                                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                                                        color: root.colSubtext
                                                                    }

                                                                    StyledText {
                                                                        visible: Boolean(matchWordBtn.modelData.cefrLevel)
                                                                        text: matchWordBtn.modelData.cefrLevel ?? ""
                                                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                                                        font.weight: Font.Bold
                                                                        color: root.cefrColor(matchWordBtn.modelData.cefrLevel)
                                                                    }
                                                                }
                                                            }

                                                            MaterialSymbol {
                                                                visible: Boolean(matchWordBtn.modelData.matched) || matchWordBtn.isMismatch
                                                                Layout.alignment: Qt.AlignVCenter
                                                                text: matchWordBtn.modelData.matched ? "check_circle" : "cancel"
                                                                iconSize: 16
                                                                color: matchWordBtn.stateAccent
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        // MIDDLE CORRIDOR: Dedicated space for connecting match lines
                                        Item {
                                            id: srMatchingCorridor
                                            objectName: "srMatchingCorridor"
                                            Layout.fillWidth: false
                                            Layout.fillHeight: true
                                            Layout.preferredWidth: Math.round(Math.min(124, Math.max(76, matchingColumnsRow.width * 0.13)))
                                            Layout.minimumWidth: 72
                                            onXChanged: root.requestMatchingLinesRepaint()
                                            onWidthChanged: root.requestMatchingLinesRepaint()
                                        }

                                        // RIGHT COLUMN: 6 Definitions (5 Matches + 1 Distractor)
                                        ColumnLayout {
                                            id: srMatchingRightColumn
                                            objectName: "srMatchingRightColumn"
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            Layout.preferredWidth: Math.max(240, matchingColumnsRow.width - srMatchingLeftColumn.width - srMatchingCorridor.width)
                                            spacing: 6
                                            onXChanged: root.requestMatchingLinesRepaint()
                                            onWidthChanged: root.requestMatchingLinesRepaint()

                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 6
                                                StyledText {
                                                    text: Translation.tr("DEFINITIONS · ĐỊNH NGHĨA (%1)").arg(root.matchingRightDefs.length)
                                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                                    font.weight: Font.Bold
                                                    font.letterSpacing: 0.5
                                                    color: root.colSubtext
                                                }
                                                Item { Layout.fillWidth: true }
                                            }

                                            Repeater {
                                                id: matchingRightRepeater
                                                model: root.matchingRightDefs
                                                delegate: RippleButton {
                                                    id: matchDefBtn
                                                    focusPolicy: Qt.NoFocus
                                                    required property var modelData
                                                    required property int index
                                                    objectName: "srMatchingRightDef-" + index
                                                    Layout.fillWidth: true
                                                    Layout.fillHeight: true
                                                    Layout.minimumHeight: 42
                                                    implicitHeight: Math.max(44, matchDefRow.implicitHeight + 14)
                                                    buttonRadius: Appearance.rounding.small
                                                    enabled: !Boolean(modelData.matched) && !root.matchingRoundComplete
                                                    opacity: modelData.matched
                                                        ? 0.68
                                                        : (root.matchingRoundComplete && modelData.isDistractor ? 0.48 : 1.0)
                                                    readonly property bool isSelected: root.selectedMatchingRightIndex === index
                                                    readonly property bool isMismatch: root.mismatchRightIndex === index
                                                    readonly property color stateAccent: modelData.matched
                                                        ? ColorUtils.mix(Appearance.colors.colPrimary, "#10b981", 0.45)
                                                        : isMismatch
                                                        ? Appearance.colors.colError
                                                        : isSelected
                                                        ? Appearance.colors.colPrimary
                                                        : root.colSubtext

                                                    colBackground: modelData.matched
                                                        ? Qt.alpha("#10b981", 0.14)
                                                        : isMismatch
                                                        ? Qt.alpha(Appearance.colors.colError, 0.18)
                                                        : isSelected
                                                        ? Qt.alpha(Appearance.colors.colPrimary, 0.16)
                                                        : root.colSurfaceElevated
                                                    colBackgroundHover: modelData.matched
                                                        ? colBackground
                                                        : Qt.alpha(Appearance.colors.colPrimary, isSelected ? 0.22 : 0.12)

                                                    onClicked: root.selectMatchingRight(index)
                                                    onXChanged: root.requestMatchingLinesRepaint()
                                                    onYChanged: root.requestMatchingLinesRepaint()
                                                    onWidthChanged: root.requestMatchingLinesRepaint()
                                                    onHeightChanged: root.requestMatchingLinesRepaint()

                                                    Rectangle {
                                                        anchors.fill: parent
                                                        radius: matchDefBtn.buttonRadius
                                                        color: "transparent"
                                                        border.width: (matchDefBtn.modelData.matched || matchDefBtn.isSelected || matchDefBtn.isMismatch) ? 1.5 : 1
                                                        border.color: (matchDefBtn.modelData.matched || matchDefBtn.isSelected || matchDefBtn.isMismatch)
                                                            ? matchDefBtn.stateAccent
                                                            : root.colBorder
                                                    }

                                                    contentItem: Item {
                                                        RowLayout {
                                                            id: matchDefRow
                                                            anchors.left: parent.left
                                                            anchors.right: parent.right
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            anchors.leftMargin: 10
                                                            anchors.rightMargin: 10
                                                            spacing: 8

                                                            Rectangle {
                                                                Layout.alignment: Qt.AlignVCenter
                                                                implicitWidth: 22
                                                                implicitHeight: 22
                                                                radius: 6
                                                                color: (matchDefBtn.modelData.matched || matchDefBtn.isSelected || matchDefBtn.isMismatch)
                                                                    ? Qt.alpha(matchDefBtn.stateAccent, 0.24)
                                                                    : root.colBoxHover
                                                                StyledText {
                                                                    anchors.centerIn: parent
                                                                    text: ["A", "B", "C", "D", "E", "F"][matchDefBtn.index] ?? String(matchDefBtn.index + 1)
                                                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                                                    font.weight: Font.Bold
                                                                    color: (matchDefBtn.modelData.matched || matchDefBtn.isSelected || matchDefBtn.isMismatch)
                                                                        ? matchDefBtn.stateAccent
                                                                        : root.colSubtext
                                                                }
                                                            }

                                                            ColumnLayout {
                                                                Layout.fillWidth: true
                                                                Layout.alignment: Qt.AlignVCenter
                                                                spacing: 2

                                                                StyledText {
                                                                    objectName: "srMatchingRightDefText-" + matchDefBtn.index
                                                                    Layout.fillWidth: true
                                                                    wrapMode: Text.WordWrap
                                                                    text: root.maskedStudyText(matchDefBtn.modelData.definitionEn, matchDefBtn.modelData, matchDefBtn.modelData.matched || root.matchingRoundComplete)
                                                                    font.pixelSize: Appearance.font.pixelSize.small
                                                                    font.weight: Font.Medium
                                                                    color: root.colText
                                                                }

                                                                StyledText {
                                                                    visible: Boolean(matchDefBtn.modelData.meaningVi)
                                                                    Layout.fillWidth: true
                                                                    wrapMode: Text.WordWrap
                                                                    text: root.maskedStudyText(matchDefBtn.modelData.meaningVi, matchDefBtn.modelData, matchDefBtn.modelData.matched || root.matchingRoundComplete)
                                                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                                                    color: root.colSubtext
                                                                }
                                                            }

                                                            Rectangle {
                                                                visible: root.matchingRoundComplete && Boolean(matchDefBtn.modelData.isDistractor)
                                                                Layout.alignment: Qt.AlignVCenter
                                                                implicitWidth: distractorBadgeText.implicitWidth + 10
                                                                implicitHeight: 20
                                                                radius: 5
                                                                color: root.colBoxHover
                                                                StyledText {
                                                                    id: distractorBadgeText
                                                                    anchors.centerIn: parent
                                                                    text: Translation.tr("Distractor")
                                                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                                                    color: root.colSubtext
                                                                }
                                                            }

                                                            MaterialSymbol {
                                                                visible: Boolean(matchDefBtn.modelData.matched) || matchDefBtn.isMismatch
                                                                Layout.alignment: Qt.AlignVCenter
                                                                text: matchDefBtn.modelData.matched ? "check_circle" : "cancel"
                                                                iconSize: 18
                                                                color: matchDefBtn.stateAccent
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // Connecting Lines Canvas across the Middle Corridor
                                    Canvas {
                                        id: matchingLinesCanvas
                                        objectName: "srMatchingLinesCanvas"
                                        anchors.fill: parent
                                        z: 5
                                        antialiasing: true
                                        Component.onCompleted: root.matchingLinesCanvas = matchingLinesCanvas

                                        readonly property int matchedLinesCount: root.matchingMatchedCount
                                        readonly property bool hasMismatchLine: root.mismatchLeftIndex >= 0 && root.mismatchRightIndex >= 0
                                        readonly property color matchedStrokeColor: ColorUtils.mix(Appearance.colors.colPrimary, "#10b981", 0.45)
                                        readonly property color mismatchStrokeColor: Appearance.colors.colError
                                        property int paintedMatchedLinesCount: 0
                                        property bool paintedMismatchLine: false
                                        property var paintedSegments: []

                                        onWidthChanged: root.requestMatchingLinesRepaint()
                                        onHeightChanged: root.requestMatchingLinesRepaint()
                                        onVisibleChanged: if (visible) root.requestMatchingLinesRepaint()
                                        onMatchedStrokeColorChanged: root.requestMatchingLinesRepaint()
                                        onMismatchStrokeColorChanged: root.requestMatchingLinesRepaint()

                                        onPaint: {
                                            const ctx = getContext("2d")
                                            ctx.clearRect(0, 0, width, height)

                                            const leftCount = matchingLeftRepeater.count
                                            const rightCount = matchingRightRepeater.count
                                            const leftWords = root.matchingLeftWords ?? []
                                            const rightDefs = root.matchingRightDefs ?? []

                                            // 1. Draw port anchors on right edge of left cards & left edge of right cards
                                            for (let i = 0; i < leftCount; i++) {
                                                const leftBtn = matchingLeftRepeater.itemAt(i)
                                                if (!leftBtn) continue
                                                const pt = leftBtn.mapToItem(matchingLinesCanvas, leftBtn.width, leftBtn.height * 0.5)
                                                const wItem = leftWords[i]
                                                const isMatched = Boolean(wItem?.matched)
                                                const isErr = root.mismatchLeftIndex === i
                                                const isSel = root.selectedMatchingLeftIndex === i
                                                ctx.beginPath()
                                                ctx.arc(pt.x, pt.y, (isMatched || isSel || isErr) ? 4.2 : 3.0, 0, Math.PI * 2)
                                                ctx.fillStyle = isMatched
                                                    ? matchedStrokeColor
                                                    : isErr
                                                    ? mismatchStrokeColor
                                                    : isSel
                                                    ? Appearance.colors.colPrimary
                                                    : Qt.alpha(root.colSubtext, 0.42)
                                                ctx.fill()
                                            }

                                            for (let j = 0; j < rightCount; j++) {
                                                const rightBtn = matchingRightRepeater.itemAt(j)
                                                if (!rightBtn) continue
                                                const pt = rightBtn.mapToItem(matchingLinesCanvas, 0, rightBtn.height * 0.5)
                                                const dItem = rightDefs[j]
                                                const isMatched = Boolean(dItem?.matched)
                                                const isErr = root.mismatchRightIndex === j
                                                const isSel = root.selectedMatchingRightIndex === j
                                                ctx.beginPath()
                                                ctx.arc(pt.x, pt.y, (isMatched || isSel || isErr) ? 4.2 : 3.0, 0, Math.PI * 2)
                                                ctx.fillStyle = isMatched
                                                    ? matchedStrokeColor
                                                    : isErr
                                                    ? mismatchStrokeColor
                                                    : isSel
                                                    ? Appearance.colors.colPrimary
                                                    : Qt.alpha(root.colSubtext, 0.42)
                                                ctx.fill()
                                            }

                                            const drawConnector = (p1, p2, strokeColor, glowColor, isDashed) => {
                                                const dx = Math.max(24, (p2.x - p1.x) * 0.48)
                                                ctx.save()
                                                ctx.lineCap = "round"
                                                ctx.lineJoin = "round"

                                                // Outer soft glow
                                                ctx.beginPath()
                                                ctx.setLineDash([])
                                                ctx.moveTo(p1.x, p1.y)
                                                ctx.bezierCurveTo(p1.x + dx, p1.y, p2.x - dx, p2.y, p2.x, p2.y)
                                                ctx.strokeStyle = glowColor
                                                ctx.lineWidth = 6.0
                                                ctx.stroke()

                                                // Crisp inner curve
                                                ctx.beginPath()
                                                if (isDashed)
                                                    ctx.setLineDash([5, 4])
                                                else
                                                    ctx.setLineDash([])
                                                ctx.moveTo(p1.x, p1.y)
                                                ctx.bezierCurveTo(p1.x + dx, p1.y, p2.x - dx, p2.y, p2.x, p2.y)
                                                ctx.strokeStyle = strokeColor
                                                ctx.lineWidth = 2.4
                                                ctx.stroke()

                                                // Crisp endpoint port circles on top of glow
                                                ctx.setLineDash([])
                                                ctx.beginPath()
                                                ctx.arc(p1.x, p1.y, 4.2, 0, Math.PI * 2)
                                                ctx.arc(p2.x, p2.y, 4.2, 0, Math.PI * 2)
                                                ctx.fillStyle = strokeColor
                                                ctx.fill()

                                                ctx.restore()
                                            }

                                            // 2. Draw smooth Bezier curves for all matched pairs
                                            let drawnMatched = 0
                                            const segments = []
                                            for (let i = 0; i < leftWords.length; i++) {
                                                const wItem = leftWords[i]
                                                if (!wItem || !wItem.matched) continue
                                                const leftBtn = matchingLeftRepeater.itemAt(i)
                                                if (!leftBtn) continue
                                                let matchedRightIdx = -1
                                                for (let j = 0; j < rightDefs.length; j++) {
                                                    const dItem = rightDefs[j]
                                                    if (dItem && dItem.matched && !dItem.isDistractor && String(dItem.targetCardId) === String(wItem.id)) {
                                                        matchedRightIdx = j
                                                        break
                                                    }
                                                }
                                                if (matchedRightIdx < 0) continue
                                                const rightBtn = matchingRightRepeater.itemAt(matchedRightIdx)
                                                if (!rightBtn) continue

                                                const p1 = leftBtn.mapToItem(matchingLinesCanvas, leftBtn.width, leftBtn.height * 0.5)
                                                const p2 = rightBtn.mapToItem(matchingLinesCanvas, 0, rightBtn.height * 0.5)
                                                drawConnector(p1, p2, matchedStrokeColor, Qt.alpha(matchedStrokeColor, 0.22), false)
                                                drawnMatched++
                                                segments.push({
                                                    leftIndex: i,
                                                    rightIndex: matchedRightIdx,
                                                    x1: p1.x,
                                                    y1: p1.y,
                                                    x2: p2.x,
                                                    y2: p2.y
                                                })
                                            }

                                            // 3. Draw error Bezier curve for active mismatch
                                            let drawnMismatch = false
                                            if (root.mismatchLeftIndex >= 0 && root.mismatchRightIndex >= 0) {
                                                const errLeftBtn = matchingLeftRepeater.itemAt(root.mismatchLeftIndex)
                                                const errRightBtn = matchingRightRepeater.itemAt(root.mismatchRightIndex)
                                                if (errLeftBtn && errRightBtn) {
                                                    const p1 = errLeftBtn.mapToItem(matchingLinesCanvas, errLeftBtn.width, errLeftBtn.height * 0.5)
                                                    const p2 = errRightBtn.mapToItem(matchingLinesCanvas, 0, errRightBtn.height * 0.5)
                                                    drawConnector(p1, p2, mismatchStrokeColor, Qt.alpha(mismatchStrokeColor, 0.24), true)
                                                    drawnMismatch = true
                                                }
                                            }

                                            paintedMatchedLinesCount = drawnMatched
                                            paintedMismatchLine = drawnMismatch
                                            paintedSegments = segments
                                        }
                                    }
                                }

                                // Round Complete Action Bar
                                RowLayout {
                                    Layout.fillWidth: true
                                    visible: root.matchingRoundComplete
                                    spacing: 10

                                    MaterialSymbol {
                                        text: "verified"
                                        iconSize: 18
                                        color: "#10b981"
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: Translation.tr("Round complete! All %1 vocabulary words matched.").arg(root.matchingLeftWords.length)
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        font.weight: Font.DemiBold
                                        color: "#10b981"
                                    }

                                    RippleButton {
                                        objectName: "srMatchingContinueButton"
                                        focusPolicy: Qt.NoFocus
                                        implicitWidth: Math.max(170, matchContinueRow.implicitWidth + 28)
                                        implicitHeight: 38
                                        buttonRadius: Appearance.rounding.full
                                        colBackground: Appearance.colors.colPrimaryContainer
                                        colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                                        onClicked: root.finishMatchingRound()

                                        contentItem: Item {
                                            Row {
                                                id: matchContinueRow
                                                anchors.centerIn: parent
                                                spacing: 6
                                                StyledText {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: Translation.tr("Continue (Space)")
                                                    font.pixelSize: Appearance.font.pixelSize.small
                                                    font.weight: Font.DemiBold
                                                    color: Appearance.colors.colOnPrimaryContainer
                                                }
                                                MaterialSymbol {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: "arrow_forward"
                                                    iconSize: 16
                                                    color: Appearance.colors.colOnPrimaryContainer
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                                }
                            }

                            // Prompt Section (Single-Card Modes: Multiple Choice, Cloze Reading, Flashcard)
                            Loader {
                                id: singleCardViewLoader
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                active: root._singleCardViewLoaded
                                visible: !root.isMatchingMode
                                sourceComponent: Component {
                                    ColumnLayout {
                                        spacing: 14

                            ColumnLayout {
                                id: promptSectionLayout
                                Layout.fillWidth: true
                                Layout.topMargin: 4
                                spacing: 8

                                // Mode prompt subtitle
                                StyledText {
                                    Layout.fillWidth: true
                                    visible: root.backend.studyMode !== "flashcard"
                                    text: root.backend.studyMode === "mc"
                                        ? Translation.tr("Choose the correct definition for:")
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
                                            ? Math.max(150, Math.round(promptSectionLayout.width * 0.36))
                                            : Math.max(150, promptSectionLayout.width)
                                        wrapMode: Text.WordWrap
                                        text: {
                                            const card = root.backend.currentCard
                                            if (!card) return ""
                                            if (root.backend.studyMode === "cloze")
                                                return root.maskedStudyText(root.backend.renderClozeFront(card), card)
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
                                        color: ColorUtils.applyAlpha(ColorUtils.mix(root.colSurfaceElevated, Appearance.colors.colPrimary, 0.88), Math.max(0.92, root.colSurface.a))
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

                                // Meaning cue + Type-to-check input + Quick 1-4 / 0 word choices in Cloze mode
                                Loader {
                                    id: clozeSectionLoader
                                    Layout.fillWidth: true
                                    active: root._clozeViewLoaded
                                    visible: root.backend.studyMode === "cloze"
                                    sourceComponent: Component {
                                        ColumnLayout {
                                            spacing: 8

                                    StyledText {
                                        Layout.fillWidth: true
                                        wrapMode: Text.WordWrap
                                        text: Translation.tr("Meaning cue: %1").arg(root.maskedClozeMeaningCue(root.backend.currentCard))
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
                                            Component.onCompleted: root.clozeInputField = clozeInputField
                                            readOnly: root.answerRevealed
                                            placeholderText: Translation.tr("Type the missing word or press 1–4 to pick (0 to reveal)...")
                                            text: root.typedClozeAttempt
                                            onTextEdited: root.typedClozeAttempt = text
                                            onTextChanged: if (root.typedClozeAttempt !== text) root.typedClozeAttempt = text
                                            onAccepted: if (!root.answerRevealed) root.checkClozeAttempt()
                                            Keys.onPressed: event => {
                                                if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_Z && (root.answerRevealed || clozeInputField.text.length === 0)) {
                                                    clozeInputField.focus = false
                                                    root.forceActiveFocus()
                                                    root.triggerStudyShortcut("undo", true)
                                                    event.accepted = true
                                                    return
                                                }
                                                if (!(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
                                                    if (event.key === Qt.Key_Space && (root.answerRevealed || clozeInputField.text.trim().length === 0)) {
                                                        clozeInputField.focus = false
                                                        root.forceActiveFocus()
                                                        root.triggerStudyShortcut("space", true)
                                                        event.accepted = true
                                                        return
                                                    }
                                                    let shortcutAction = ""
                                                    if (event.key === Qt.Key_0) {
                                                        shortcutAction = root.answerRevealed ? "again" : "cloze-reveal"
                                                    } else if (event.key === Qt.Key_1) {
                                                        shortcutAction = root.answerRevealed ? "hard" : "cloze-pick-0"
                                                    } else if (event.key === Qt.Key_2) {
                                                        shortcutAction = root.answerRevealed ? "good" : "cloze-pick-1"
                                                    } else if (event.key === Qt.Key_3) {
                                                        shortcutAction = root.answerRevealed ? "easy" : "cloze-pick-2"
                                                    } else if (event.key === Qt.Key_4) {
                                                        shortcutAction = root.answerRevealed ? "easy" : "cloze-pick-3"
                                                    }
                                                    if (shortcutAction.length > 0 && !root.clozeNumericTypingActive) {
                                                        clozeInputField.focus = false
                                                        root.forceActiveFocus()
                                                        root.triggerStudyShortcut(shortcutAction, true)
                                                        event.accepted = true
                                                        return
                                                    }
                                                }
                                            }
                                        }

                                        FilterChip {
                                            objectName: "srCheckClozeButton"
                                            iconName: "check"
                                            label: Translation.tr("Check")
                                            enabled: !root.answerRevealed
                                            activeChip: !root.answerRevealed
                                            onClicked: root.checkClozeAttempt()
                                        }
                                    }

                                    // Cloze Quick Word Choices (1–4) + 0 Reveal
                                    Flow {
                                        id: srClozeWordBank
                                        objectName: "srClozeWordBank"
                                        Layout.fillWidth: true
                                        visible: root.multipleChoiceOptions.length > 0
                                        spacing: 6

                                        Repeater {
                                            model: root.multipleChoiceOptions
                                            delegate: RippleButton {
                                                id: clozeChoiceChip
                                                focusPolicy: Qt.NoFocus
                                                required property var modelData
                                                required property int index
                                                objectName: "srClozeOption-" + index
                                                implicitHeight: 28
                                                implicitWidth: clozeChoiceRow.implicitWidth + 18
                                                buttonRadius: Appearance.rounding.full
                                                enabled: !root.answerRevealed
                                                readonly property bool isChosen: root.selectedChoiceIndex === index
                                                readonly property bool isRight: Boolean(modelData.isCorrect)
                                                opacity: (!root.answerRevealed || isRight || isChosen) ? 1.0 : 0.55
                                                colBackground: !root.answerRevealed
                                                    ? root.colSurfaceElevated
                                                    : isRight
                                                    ? Qt.alpha("#10b981", 0.18)
                                                    : isChosen
                                                    ? Qt.alpha("#ef4444", 0.18)
                                                    : root.colSurfaceElevated
                                                colBackgroundHover: Qt.alpha(Appearance.colors.colPrimary, 0.14)
                                                onClicked: root.selectClozeChoice(index)

                                                contentItem: Item {
                                                    Row {
                                                        id: clozeChoiceRow
                                                        anchors.centerIn: parent
                                                        spacing: 5
                                                        StyledText {
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            text: String(clozeChoiceChip.index + 1) + " ·"
                                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                                            font.weight: Font.Bold
                                                            color: Appearance.colors.colPrimary
                                                        }
                                                        StyledText {
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            text: clozeChoiceChip.modelData.headword || clozeChoiceChip.modelData.front || ""
                                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                                            font.weight: Font.DemiBold
                                                            color: root.colText
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        RippleButton {
                                            objectName: "srClozeRevealShortcutChip"
                                            focusPolicy: Qt.NoFocus
                                            visible: !root.answerRevealed
                                            implicitHeight: 28
                                            implicitWidth: clozeZeroRow.implicitWidth + 18
                                            buttonRadius: Appearance.rounding.full
                                            colBackground: root.colSurfaceElevated
                                            colBackgroundHover: Qt.alpha(Appearance.colors.colPrimary, 0.14)
                                            onClicked: root.triggerStudyShortcut("cloze-reveal", true)

                                            contentItem: Item {
                                                Row {
                                                    id: clozeZeroRow
                                                    anchors.centerIn: parent
                                                    spacing: 4
                                                    StyledText {
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        text: "0 · " + Translation.tr("Reveal")
                                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                                        font.weight: Font.Medium
                                                        color: root.colSubtext
                                                    }
                                                }
                                            }
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
                                }
                            }

                            // 4-Option Multiple Choice Grid (remains visible before & after selection)
                            Loader {
                                id: mcGridLoader
                                Layout.fillWidth: true
                                active: root._mcViewLoaded
                                visible: root.isMultipleChoiceMode
                                sourceComponent: Component {
                                    GridLayout {
                                        id: mcOptionsGrid
                                        objectName: "srMultipleChoiceGrid"
                                        columns: root.width >= 680 ? 2 : 1
                                uniformCellWidths: true
                                columnSpacing: 12
                                rowSpacing: 8

                                Repeater {
                                    model: root.multipleChoiceOptions
                                    delegate: RippleButton {
                                        id: mcOptionBtn
                                        focusPolicy: Qt.NoFocus
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
                                            : root.colBoxHover

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
                                                            : root.colBoxHover
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

                                                    // Term row: shown on all 4 options after reveal
                                                    StyledText {
                                                        objectName: "srMcOptionTerm-" + mcOptionBtn.index
                                                        visible: root.answerRevealed
                                                        Layout.fillWidth: true
                                                        Layout.alignment: Qt.AlignVCenter
                                                        wrapMode: Text.WordWrap
                                                        text: (mcOptionBtn.modelData.front ?? "")
                                                            + (mcOptionBtn.modelData.phonetics ? "  " + mcOptionBtn.modelData.phonetics : "")
                                                        font.pixelSize: Appearance.font.pixelSize.small
                                                        font.weight: Font.Bold
                                                        color: root.colText
                                                    }

                                                    // Definition row (in MC mode before reveal, sits inline with letter badge)
                                                    StyledText {
                                                        objectName: "srMcOptionDefinition-" + mcOptionBtn.index
                                                        visible: root.backend.studyMode === "mc" && !root.answerRevealed
                                                        Layout.fillWidth: true
                                                        Layout.alignment: Qt.AlignVCenter
                                                        wrapMode: Text.WordWrap
                                                        text: root.maskedStudyText(mcOptionBtn.modelData.definitionEn, mcOptionBtn.modelData, root.answerRevealed)
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
                                                            text: root.maskedStudyText(mcOptionBtn.modelData.definitionEn, mcOptionBtn.modelData, root.answerRevealed)
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
                                }
                            }

                            Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                visible: !root.answerRevealed && root.isMultipleChoiceMode
                            }

                            // Reveal Button (when answer is still hidden in non-MC, non-Matching modes)
                            Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                visible: !root.answerRevealed && !root.isMultipleChoiceMode && !root.isMatchingMode

                                RippleButton {
                                    objectName: "srRevealButton"
                                    focusPolicy: Qt.NoFocus
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
                            Loader {
                                id: revealedPanelLoader
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                active: root._revealedViewLoaded
                                visible: root.answerRevealed && !root.isMatchingMode
                                sourceComponent: Component {
                                    ColumnLayout {
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

                                        // Morphology Strip in Cloze mode when revealed
                                        MorphologyStrip {
                                            visible: root.backend.studyMode === "cloze"
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
                                            focusPolicy: Qt.NoFocus
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
                            }
                                }
                            }
                        }
                    }

                    // Caught-up / Empty Queue View
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: !root.showStudyArenaCard
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

                // Right Sidebar 2 (Right of CEFR Mastery): Study-Tracker Analytics & Activity Heatmap
                Rectangle {
                    id: srStudyTrackerAnalyticsColumn
                    objectName: "srStudyTrackerAnalyticsColumn"
                    Layout.preferredWidth: 276
                    Layout.fillHeight: true
                    visible: root.width >= 860
                    radius: Appearance.rounding.small
                    color: root.colAnalyticsColumnBg
                    border.width: 0
                    clip: true

                    Flickable {
                        id: srAnalyticsFlick
                        anchors.fill: parent
                        anchors.margins: 10
                        contentWidth: width
                        contentHeight: srAnalyticsCol.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        ColumnLayout {
                            id: srAnalyticsCol
                            width: srAnalyticsFlick.width
                            height: Math.max(srAnalyticsFlick.height, srAnalyticsCol.implicitHeight)
                            spacing: 8

                            // Header Row: Analytics + Streak Badge
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                StyledText {
                                    text: Translation.tr("Analytics")
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    font.weight: Font.Bold
                                    color: root.colText
                                }

                                Item { Layout.fillWidth: true }

                                Rectangle {
                                    implicitWidth: srStreakBadgeRow.implicitWidth + 10
                                    implicitHeight: 20
                                    radius: 10
                                    color: Qt.alpha(Appearance.colors.colPrimary, 0.14)

                                    RowLayout {
                                        id: srStreakBadgeRow
                                        anchors.centerIn: parent
                                        spacing: 4
                                        MaterialSymbol {
                                            text: "local_fire_department"
                                            iconSize: 13
                                            color: Appearance.colors.colPrimary
                                        }
                                        StyledText {
                                            text: Translation.tr("%1d streak").arg(root.backend.analytics?.streakDays ?? 0)
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            font.weight: Font.Bold
                                            color: Appearance.colors.colPrimary
                                        }
                                    }
                                }
                            }

                            // 1. CONSISTENCY TRACKER CARD (Study-Tracker adaptation)
                            Rectangle {
                                id: srConsistencyCard
                                objectName: "srConsistencyCard"
                                Layout.fillWidth: true
                                implicitHeight: srConsistencyCol.implicitHeight + 12
                                radius: Appearance.rounding.small
                                color: root.colAnalyticsCardBg
                                border.width: 1
                                border.color: root.colAnalyticsBorder

                                ColumnLayout {
                                    id: srConsistencyCol
                                    anchors { fill: parent; margins: 6 }
                                    spacing: 4

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 4

                                        StyledText {
                                            text: Translation.tr("CONSISTENCY")
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            font.weight: Font.Bold
                                            font.letterSpacing: 0.6
                                            color: root.colSubtext
                                        }

                                        Item { Layout.fillWidth: true }

                                        // Target badge
                                        Rectangle {
                                            implicitWidth: targetGoalRow.implicitWidth + 10
                                            implicitHeight: 18
                                            radius: 9
                                            color: Qt.alpha(Appearance.colors.colPrimary, 0.14)

                                            RowLayout {
                                                id: targetGoalRow
                                                anchors.centerIn: parent
                                                spacing: 3
                                                StyledText {
                                                    text: `🎯 ${root.backend.analytics?.consistency?.goalCards ?? 20}/d`
                                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                                    font.weight: Font.Bold
                                                    color: Appearance.colors.colPrimary
                                                }
                                            }
                                        }

                                        // Settings gear toggle
                                        Rectangle {
                                            width: 20
                                            height: 20
                                            radius: 10
                                            color: root.consistencySettingsOpen
                                                ? Qt.alpha(Appearance.colors.colPrimary, 0.22)
                                                : consistencyGearMouse.containsMouse ? root.colAnalyticsSubBoxBg : "transparent"

                                            MaterialSymbol {
                                                anchors.centerIn: parent
                                                text: "settings"
                                                iconSize: 13
                                                color: root.consistencySettingsOpen ? Appearance.colors.colPrimary : root.colSubtext
                                            }

                                            MouseArea {
                                                id: consistencyGearMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.consistencySettingsOpen = !root.consistencySettingsOpen
                                            }
                                        }
                                    }

                                    // Collapsible Inline Consistency Settings (Daily Goal + Weekends)
                                    Rectangle {
                                        visible: root.consistencySettingsOpen
                                        Layout.fillWidth: true
                                        implicitHeight: consistencyConfigCol.implicitHeight + 12
                                        radius: 6
                                        color: root.colAnalyticsSubBoxBg
                                        border.width: 1
                                        border.color: root.colAnalyticsBorder

                                        ColumnLayout {
                                            id: consistencyConfigCol
                                            anchors { fill: parent; margins: 6 }
                                            spacing: 5

                                            RowLayout {
                                                Layout.fillWidth: true
                                                StyledText {
                                                    Layout.fillWidth: true
                                                    text: Translation.tr("Daily Goal")
                                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                                    color: root.colSubtext
                                                }
                                                Rectangle {
                                                    width: 20; height: 20; radius: 5
                                                    color: Qt.alpha(Appearance.colors.colPrimary, 0.14)
                                                    StyledText { anchors.centerIn: parent; text: "-"; color: root.colText; font.weight: Font.Bold }
                                                    MouseArea {
                                                        anchors.fill: parent
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            const cur = root.backend.analytics?.consistency?.goalCards ?? 20
                                                            Config.setNestedValue("dashboard.spacedRepetition.dailyGoalCards", Math.max(5, cur - 5))
                                                        }
                                                    }
                                                }
                                                StyledText {
                                                    text: `${root.backend.analytics?.consistency?.goalCards ?? 20}`
                                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                                    font.weight: Font.Bold
                                                    color: root.colText
                                                }
                                                Rectangle {
                                                    width: 20; height: 20; radius: 5
                                                    color: Qt.alpha(Appearance.colors.colPrimary, 0.14)
                                                    StyledText { anchors.centerIn: parent; text: "+"; color: root.colText; font.weight: Font.Bold }
                                                    MouseArea {
                                                        anchors.fill: parent
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            const cur = root.backend.analytics?.consistency?.goalCards ?? 20
                                                            Config.setNestedValue("dashboard.spacedRepetition.dailyGoalCards", Math.min(300, cur + 5))
                                                        }
                                                    }
                                                }
                                            }

                                            RowLayout {
                                                Layout.fillWidth: true
                                                StyledText {
                                                    Layout.fillWidth: true
                                                    text: Translation.tr("Weekends")
                                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                                    color: root.colSubtext
                                                }
                                                Rectangle {
                                                    readonly property bool wkEnabled: root.backend.analytics?.consistency?.weekendsEnabled ?? true
                                                    implicitWidth: wkText.implicitWidth + 12
                                                    implicitHeight: 20
                                                    radius: 10
                                                    color: wkEnabled ? Qt.alpha(Appearance.colors.colPrimary, 0.18) : root.colAnalyticsCardBg
                                                    StyledText {
                                                        id: wkText
                                                        anchors.centerIn: parent
                                                        text: parent.wkEnabled ? Translation.tr("Mon–Sun") : Translation.tr("Mon–Fri")
                                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                                        font.weight: Font.DemiBold
                                                        color: parent.wkEnabled ? Appearance.colors.colPrimary : root.colSubtext
                                                    }
                                                    MouseArea {
                                                        anchors.fill: parent
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            const cur = root.backend.analytics?.consistency?.weekendsEnabled ?? true
                                                            Config.setNestedValue("dashboard.spacedRepetition.weekendsEnabled", !cur)
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // THIS WEEK Header
                                    RowLayout {
                                        Layout.fillWidth: true
                                        StyledText {
                                            text: Translation.tr("THIS WEEK")
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            font.weight: Font.DemiBold
                                            color: root.colSubtext
                                        }
                                        Item { Layout.fillWidth: true }
                                        StyledText {
                                            text: `${root.backend.analytics?.consistency?.weeklyMet ?? 0} / ${root.backend.analytics?.consistency?.weeklyTarget ?? 7} Days ✓`
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            font.weight: Font.Bold
                                            color: (root.backend.analytics?.consistency?.weeklyMet ?? 0) >= (root.backend.analytics?.consistency?.weeklyTarget ?? 7)
                                                ? "#10b981" : Appearance.colors.colPrimary
                                        }
                                    }

                                    // 7-Day Strip (Mon..Sun)
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 3

                                        Repeater {
                                            model: root.backend.analytics?.consistency?.weeklyDays ?? []
                                            delegate: ColumnLayout {
                                                required property var modelData
                                                required property int index
                                                Layout.fillWidth: true
                                                spacing: 2

                                                StyledText {
                                                    Layout.alignment: Qt.AlignHCenter
                                                    text: (modelData.label ?? "").slice(0, 1)
                                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                                    font.weight: modelData.isToday ? Font.Bold : Font.Medium
                                                    color: modelData.isToday ? Appearance.colors.colPrimary : root.colSubtext
                                                }

                                                Rectangle {
                                                    objectName: "srConsistencyDayCell-" + index
                                                    Layout.fillWidth: true
                                                    implicitHeight: 19
                                                    radius: 5
                                                    color: modelData.met
                                                        ? ColorUtils.mix(root.colAnalyticsSubBoxBg, "#10b981", 0.84)
                                                        : modelData.active
                                                            ? ColorUtils.mix(root.colAnalyticsSubBoxBg, Appearance.colors.colPrimary, 0.86)
                                                            : root.colAnalyticsSubBoxBg
                                                    border.width: modelData.isToday ? 1 : 0
                                                    border.color: Appearance.colors.colPrimary

                                                    StyledText {
                                                        anchors.centerIn: parent
                                                        text: modelData.met ? "✓"
                                                            : modelData.active ? String(modelData.reviewed)
                                                            : modelData.isRestDay ? "–" : ""
                                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                                        font.weight: Font.Bold
                                                        color: modelData.met ? "#10b981"
                                                            : modelData.active ? Appearance.colors.colPrimary
                                                            : root.colSubtext
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // Footer: Goal Streak & 30d Hit Rate
                                    RowLayout {
                                        Layout.fillWidth: true
                                        StyledText {
                                            text: Translation.tr("Goal Streak: %1d").arg(root.backend.analytics?.consistency?.goalStreak ?? 0)
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            color: root.colSubtext
                                        }
                                        Item { Layout.fillWidth: true }
                                        StyledText {
                                            text: Translation.tr("30d Hit: %1%").arg(root.backend.analytics?.consistency?.hitRate30d ?? 0)
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            font.weight: Font.DemiBold
                                            color: root.colText
                                        }
                                    }
                                }
                            }

                            // 2. ACTIVITY HEATMAP CARD (Study-Tracker adaptation)
                            Rectangle {
                                id: srHeatmapCard
                                objectName: "srActivityHeatmapCard"
                                Layout.fillWidth: true
                                implicitHeight: srHeatmapCol.implicitHeight + 12
                                radius: Appearance.rounding.small
                                color: root.colAnalyticsCardBg
                                border.width: 1
                                border.color: root.colAnalyticsBorder

                                ColumnLayout {
                                    id: srHeatmapCol
                                    anchors { fill: parent; margins: 6 }
                                    spacing: 4

                                    // Heatmap Header + Year Navigation
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 4

                                        StyledText {
                                            text: Translation.tr("ACTIVITY %1").arg(root.heatmapYear)
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            font.weight: Font.Bold
                                            font.letterSpacing: 0.6
                                            color: root.colSubtext
                                        }

                                        Item { Layout.fillWidth: true }

                                        // Prev Year
                                        Rectangle {
                                            width: 18; height: 18; radius: 4
                                            color: prevYearMouse.containsMouse ? root.colAnalyticsSubBoxBg : "transparent"
                                            StyledText { anchors.centerIn: parent; text: "‹"; color: root.colText; font.weight: Font.Bold }
                                            MouseArea {
                                                id: prevYearMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.heatmapYear -= 1
                                            }
                                        }

                                        // Today / Current Year reset
                                        Rectangle {
                                            visible: root.heatmapYear !== (new Date()).getFullYear()
                                            implicitWidth: todayYrTxt.implicitWidth + 8
                                            implicitHeight: 18
                                            radius: 4
                                            color: Qt.alpha(Appearance.colors.colPrimary, 0.16)
                                            StyledText {
                                                id: todayYrTxt
                                                anchors.centerIn: parent
                                                text: Translation.tr("Now")
                                                font.pixelSize: Appearance.font.pixelSize.smallest
                                                color: Appearance.colors.colPrimary
                                            }
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    srHeatmapFlick._userScrolledYear = false
                                                    root.heatmapYear = (new Date()).getFullYear()
                                                    Qt.callLater(() => srHeatmapFlick.scrollToFocusWeek(true))
                                                }
                                            }
                                        }

                                        // Next Year
                                        Rectangle {
                                            width: 18; height: 18; radius: 4
                                            enabled: root.heatmapYear < (new Date()).getFullYear()
                                            opacity: enabled ? 1.0 : 0.35
                                            color: nextYearMouse.containsMouse && enabled ? root.colAnalyticsSubBoxBg : "transparent"
                                            StyledText { anchors.centerIn: parent; text: "›"; color: root.colText; font.weight: Font.Bold }
                                            MouseArea {
                                                id: nextYearMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                                onClicked: if (parent.enabled) root.heatmapYear += 1
                                            }
                                        }
                                    }

                                    // Heatmap Grid (Day labels + Horizontally scrollable weeks)
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 4

                                        Column {
                                            Layout.alignment: Qt.AlignTop
                                            Layout.topMargin: 13
                                            spacing: 2
                                            Repeater {
                                                model: ["M", "", "W", "", "F", "", "S"]
                                                delegate: Item {
                                                    required property string modelData
                                                    width: 10
                                                    height: 8
                                                    StyledText {
                                                        anchors.centerIn: parent
                                                        text: modelData
                                                        font.pixelSize: 7
                                                        color: root.colSubtext
                                                    }
                                                }
                                            }
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 3

                                            Flickable {
                                                id: srHeatmapFlick
                                                objectName: "srHeatmapFlickable"
                                                Layout.fillWidth: true
                                                implicitHeight: 82
                                                contentWidth: Math.max(1, (root.currentHeatmapData?.weeks?.length ?? 0) * 10 + 10)
                                                contentHeight: 82
                                                clip: true
                                                boundsBehavior: Flickable.StopAtBounds
                                                property bool _userScrolledYear: false

                                                function scrollToFocusWeek(force = false): void {
                                                    if (!force && srHeatmapFlick._userScrolledYear)
                                                        return
                                                    if (srHeatmapFlick.width <= 0 || srHeatmapFlick.contentWidth <= srHeatmapFlick.width) {
                                                        srHeatmapFlick.contentX = 0
                                                        return
                                                    }
                                                    const weeks = root.currentHeatmapData?.weeks ?? []
                                                    let focusWeek = -1
                                                    for (let w = 0; w < weeks.length; w++) {
                                                        const days = weeks[w]?.days ?? []
                                                        for (let d = 0; d < days.length; d++) {
                                                            if (days[d]?.isToday) {
                                                                focusWeek = w
                                                                break
                                                            }
                                                        }
                                                        if (focusWeek >= 0)
                                                            break
                                                    }
                                                    if (focusWeek < 0) {
                                                        for (let w = weeks.length - 1; w >= 0; w--) {
                                                            const days = weeks[w]?.days ?? []
                                                            if (days.some(c => c?.inYear && (Number(c?.reviewed) || 0) > 0)) {
                                                                focusWeek = w
                                                                break
                                                            }
                                                        }
                                                    }
                                                    const maxX = Math.max(0, srHeatmapFlick.contentWidth - srHeatmapFlick.width)
                                                    if (focusWeek >= 0) {
                                                        const rightEdgePx = (focusWeek + 2) * 10
                                                        srHeatmapFlick.contentX = Math.max(0, Math.min(maxX, rightEdgePx - srHeatmapFlick.width))
                                                    } else {
                                                        srHeatmapFlick.contentX = maxX
                                                    }
                                                }

                                                function updateHoverAt(px: real, py: real): void {
                                                    if (!srHeatmapHover.hovered || px < 0 || py < 13 || px > srHeatmapFlick.width) {
                                                        if (root.hoveredHeatmapCell !== null)
                                                            root.hoveredHeatmapCell = null
                                                        return
                                                    }
                                                    const rx = px + srHeatmapFlick.contentX
                                                    const weekIdx = Math.floor(rx / 10)
                                                    const dayIdx = Math.floor((py - 13) / 10)
                                                    const weeks = root.currentHeatmapData?.weeks ?? []
                                                    if (weekIdx < 0 || weekIdx >= weeks.length || dayIdx < 0 || dayIdx >= 7 || (rx - weekIdx * 10) > 8.5) {
                                                        if (root.hoveredHeatmapCell !== null)
                                                            root.hoveredHeatmapCell = null
                                                        return
                                                    }
                                                    const cell = weeks[weekIdx]?.days?.[dayIdx] ?? null
                                                    const nextCell = (cell && cell.inYear) ? cell : null
                                                    if (root.hoveredHeatmapCell?.dateStr !== nextCell?.dateStr
                                                            || root.hoveredHeatmapCell?.reviewed !== nextCell?.reviewed) {
                                                        root.hoveredHeatmapCell = nextCell
                                                    }
                                                }

                                                onMovementStarted: srHeatmapFlick._userScrolledYear = true
                                                onWidthChanged: Qt.callLater(() => srHeatmapFlick.scrollToFocusWeek(false))
                                                onContentWidthChanged: Qt.callLater(() => srHeatmapFlick.scrollToFocusWeek(false))
                                                onVisibleChanged: {
                                                    if (visible)
                                                        Qt.callLater(() => srHeatmapFlick.scrollToFocusWeek(false))
                                                    else
                                                        root.hoveredHeatmapCell = null
                                                }
                                                Component.onCompleted: Qt.callLater(() => srHeatmapFlick.scrollToFocusWeek(false))

                                                Connections {
                                                    target: root
                                                    function onPresentationActiveChanged(): void {
                                                        if (root.presentationActive)
                                                            Qt.callLater(() => srHeatmapFlick.scrollToFocusWeek(false))
                                                        else
                                                            root.hoveredHeatmapCell = null
                                                    }
                                                    function onHeatmapYearChanged(): void {
                                                        root.hoveredHeatmapCell = null
                                                        srHeatmapFlick._userScrolledYear = false
                                                        Qt.callLater(() => srHeatmapFlick.scrollToFocusWeek(true))
                                                    }
                                                    function onCurrentHeatmapDataChanged(): void {
                                                        if (!srHeatmapHover.hovered)
                                                            root.hoveredHeatmapCell = null
                                                        else
                                                            srHeatmapFlick.updateHoverAt(srHeatmapHover.point.position.x, srHeatmapHover.point.position.y)
                                                        Qt.callLater(() => srHeatmapFlick.scrollToFocusWeek(false))
                                                    }
                                                }

                                                HoverHandler {
                                                    id: srHeatmapHover
                                                    onPointChanged: srHeatmapFlick.updateHoverAt(point.position.x, point.position.y)
                                                    onHoveredChanged: {
                                                        if (!hovered)
                                                            root.hoveredHeatmapCell = null
                                                        else
                                                            srHeatmapFlick.updateHoverAt(point.position.x, point.position.y)
                                                    }
                                                }

                                                WheelHandler {
                                                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                                                    onWheel: event => {
                                                        const maxX = Math.max(0, srHeatmapFlick.contentWidth - srHeatmapFlick.width)
                                                        if (maxX <= 0)
                                                            return
                                                        const rawDelta = Math.abs(event.angleDelta.x) > Math.abs(event.angleDelta.y)
                                                            ? event.angleDelta.x
                                                            : event.angleDelta.y
                                                        if (rawDelta === 0)
                                                            return
                                                        srHeatmapFlick._userScrolledYear = true
                                                        srHeatmapFlick.contentX = Math.max(0, Math.min(maxX, srHeatmapFlick.contentX - (rawDelta / 120) * 40))
                                                        if (srHeatmapHover.hovered)
                                                            srHeatmapFlick.updateHoverAt(srHeatmapHover.point.position.x, srHeatmapHover.point.position.y)
                                                        event.accepted = true
                                                    }
                                                }

                                                Canvas {
                                                    id: srHeatmapCanvas
                                                    width: Math.max(1, (root.currentHeatmapData?.weeks?.length ?? 0) * 10 + 10)
                                                    height: 82
                                                    renderStrategy: Canvas.Cooperative

                                                    readonly property var heatmapData: root.currentHeatmapData
                                                    readonly property color todayBorderColor: Appearance.colors.colPrimary
                                                    readonly property color labelColor: root.colSubtext
                                                    readonly property color futureColor: root._heatFutureColor
                                                    readonly property color emptyColor: root._heatEmptyColor
                                                    readonly property color level1Color: root._heatLevel1Color
                                                    readonly property color level2Color: root._heatLevel2Color
                                                    readonly property color level3Color: root._heatLevel3Color
                                                    readonly property color level4Color: root._heatLevel4Color

                                                    readonly property bool paintReady: available && root._canvasesSettled && visible
                                                    onPaintReadyChanged: if (paintReady) requestPaint()
                                                    onHeatmapDataChanged: if (paintReady) requestPaint()
                                                    onTodayBorderColorChanged: if (paintReady) requestPaint()
                                                    onLabelColorChanged: if (paintReady) requestPaint()
                                                    onFutureColorChanged: if (paintReady) requestPaint()
                                                    onEmptyColorChanged: if (paintReady) requestPaint()
                                                    onLevel1ColorChanged: if (paintReady) requestPaint()
                                                    onLevel2ColorChanged: if (paintReady) requestPaint()
                                                    onLevel3ColorChanged: if (paintReady) requestPaint()
                                                    onLevel4ColorChanged: if (paintReady) requestPaint()

                                                    onPaint: {
                                                        const ctx = getContext("2d")
                                                        ctx.clearRect(0, 0, width, height)
                                                        const weeks = heatmapData?.weeks ?? []
                                                        if (!weeks.length)
                                                            return
                                                        ctx.font = `7px ${Appearance.font.family.main}`
                                                        ctx.textBaseline = "top"
                                                        const buckets = new Map()
                                                        let todayRect = null
                                                        ctx.fillStyle = labelColor
                                                        for (let w = 0; w < weeks.length; w++) {
                                                            const wk = weeks[w]
                                                            if (!wk) continue
                                                            const x = w * 10
                                                            const monthLabel = String(wk.monthLabel ?? "")
                                                            if (monthLabel.length > 0)
                                                                ctx.fillText(monthLabel, x, 0)
                                                            const days = wk.days ?? []
                                                            for (let d = 0; d < days.length; d++) {
                                                                const cell = days[d]
                                                                if (!cell || !cell.inYear)
                                                                    continue
                                                                const y = 13 + d * 10
                                                                const cKey = root.heatmapCellColor(cell).toString()
                                                                let arr = buckets.get(cKey)
                                                                if (!arr) {
                                                                    arr = []
                                                                    buckets.set(cKey, arr)
                                                                }
                                                                arr.push(x, y)
                                                                if (cell.isToday)
                                                                    todayRect = [x + 0.5, y + 0.5]
                                                            }
                                                        }
                                                        buckets.forEach((coords, colorStr) => {
                                                            ctx.fillStyle = colorStr
                                                            ctx.beginPath()
                                                            for (let i = 0; i < coords.length; i += 2) {
                                                                ctx.roundedRect(coords[i], coords[i + 1], 8, 8, 2, 2)
                                                            }
                                                            ctx.fill()
                                                        })
                                                        if (todayRect) {
                                                            ctx.strokeStyle = todayBorderColor
                                                            ctx.lineWidth = 1
                                                            ctx.beginPath()
                                                            ctx.roundedRect(todayRect[0], todayRect[1], 7, 7, 2, 2)
                                                            ctx.stroke()
                                                        }
                                                    }
                                                }
                                            }

                                            // Subtle horizontal scroll indicator + click-to-seek track
                                            Rectangle {
                                                visible: srHeatmapFlick.contentWidth > srHeatmapFlick.width + 4
                                                Layout.fillWidth: true
                                                implicitHeight: 3
                                                radius: 1.5
                                                color: root.colAnalyticsSubBoxBg

                                                Rectangle {
                                                    readonly property real viewRatio: Math.max(0.12, Math.min(1, srHeatmapFlick.width / Math.max(1, srHeatmapFlick.contentWidth)))
                                                    readonly property real maxScroll: Math.max(1, srHeatmapFlick.contentWidth - srHeatmapFlick.width)
                                                    readonly property real scrollFrac: Math.max(0, Math.min(1, srHeatmapFlick.contentX / maxScroll))
                                                    width: Math.round(parent.width * viewRatio)
                                                    height: parent.height
                                                    radius: 1.5
                                                    x: Math.round((parent.width - width) * scrollFrac)
                                                    color: Qt.alpha(Appearance.colors.colPrimary, 0.55)
                                                }

                                                MouseArea {
                                                    anchors.fill: parent
                                                    anchors.topMargin: -3
                                                    anchors.bottomMargin: -3
                                                    cursorShape: Qt.PointingHandCursor
                                                    function seekAt(mx: real): void {
                                                        const maxScroll = Math.max(0, srHeatmapFlick.contentWidth - srHeatmapFlick.width)
                                                        if (maxScroll <= 0 || width <= 0)
                                                            return
                                                        srHeatmapFlick._userScrolledYear = true
                                                        const frac = Math.max(0, Math.min(1, mx / width))
                                                        srHeatmapFlick.contentX = Math.round(frac * maxScroll)
                                                    }
                                                    onPressed: mouse => seekAt(mouse.x)
                                                    onPositionChanged: mouse => {
                                                        if (pressed)
                                                            seekAt(mouse.x)
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // Heatmap Footer: Hover Readout & Less..More Legend
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 4

                                        StyledText {
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                            text: root.hoveredHeatmapCell
                                                ? `${root.hoveredHeatmapCell.dateStr}: ${root.hoveredHeatmapCell.reviewed} cards`
                                                : Translation.tr("%1 active days · %2 reviews")
                                                    .arg(root.currentHeatmapData?.activeDays ?? 0)
                                                    .arg(root.currentHeatmapData?.totalReviewedYear ?? 0)
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            color: root.colSubtext
                                        }

                                        Row {
                                            spacing: 2
                                            Repeater {
                                                model: [0, 1, 2, 3, 4]
                                                delegate: Rectangle {
                                                    required property int modelData
                                                    objectName: "srHeatmapLegendCell-" + modelData
                                                    width: 7
                                                    height: 7
                                                    radius: 1.5
                                                    color: root.heatmapCellColor({ inYear: true, isFuture: false, level: modelData })
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // 3. SCOPED ANALYTICS + DONUT & MEMORY QUALITY (Study-Tracker adaptation)
                            Rectangle {
                                id: srBreakdownCard
                                objectName: "srAnalyticsBreakdownCard"
                                Layout.fillWidth: true
                                implicitHeight: srBreakdownCol.implicitHeight + 12
                                radius: Appearance.rounding.small
                                color: root.colAnalyticsCardBg
                                border.width: 1
                                border.color: root.colAnalyticsBorder

                                ColumnLayout {
                                    id: srBreakdownCol
                                    anchors { fill: parent; margins: 7 }
                                    spacing: 6

                                    // Scope Filter Pill Bar (Today | Week | Month | Total)
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 3

                                        Repeater {
                                            model: [
                                                { id: "today", label: Translation.tr("Today") },
                                                { id: "week", label: Translation.tr("Week") },
                                                { id: "month", label: Translation.tr("Month") },
                                                { id: "total", label: Translation.tr("Total") }
                                            ]
                                            delegate: Rectangle {
                                                required property var modelData
                                                readonly property bool isScopeActive: root.analyticsScope === modelData.id
                                                Layout.fillWidth: true
                                                implicitHeight: 21
                                                radius: 6
                                                color: isScopeActive
                                                    ? Appearance.colors.colPrimary
                                                    : scopeBtnMouse.containsMouse
                                                        ? root.colBoxHover
                                                        : root.colAnalyticsSubBoxBg

                                                StyledText {
                                                    anchors.centerIn: parent
                                                    horizontalAlignment: Text.AlignHCenter
                                                    verticalAlignment: Text.AlignVCenter
                                                    text: modelData.label
                                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                                    font.weight: isScopeActive ? Font.Bold : Font.Medium
                                                    color: isScopeActive ? root.colActivePillInk : root.colSubtext
                                                }

                                                MouseArea {
                                                    id: scopeBtnMouse
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.analyticsScope = modelData.id
                                                }
                                            }
                                        }
                                    }

                                    // Scoped KPI Mini Tiles (Reviews, New, Retention)
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 4

                                        Rectangle {
                                            objectName: "srAnalyticsReviewsTile"
                                            Layout.fillWidth: true
                                            implicitHeight: 36
                                            radius: 6
                                            color: root.colAnalyticsSubBoxBg
                                            ColumnLayout {
                                                anchors.centerIn: parent
                                                spacing: 0
                                                StyledText {
                                                    Layout.alignment: Qt.AlignHCenter
                                                    text: String(root.activeScopeStats?.reviewed ?? 0)
                                                    font.pixelSize: Appearance.font.pixelSize.small
                                                    font.weight: Font.Bold
                                                    color: root.colText
                                                }
                                                StyledText {
                                                    Layout.alignment: Qt.AlignHCenter
                                                    text: Translation.tr("Reviews")
                                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                                    color: root.colSubtext
                                                }
                                            }
                                        }

                                        Rectangle {
                                            objectName: "srAnalyticsNewTile"
                                            Layout.fillWidth: true
                                            implicitHeight: 36
                                            radius: 6
                                            color: root.colAnalyticsSubBoxBg
                                            ColumnLayout {
                                                anchors.centerIn: parent
                                                spacing: 0
                                                StyledText {
                                                    Layout.alignment: Qt.AlignHCenter
                                                    text: String(root.activeScopeStats?.newStudied ?? 0)
                                                    font.pixelSize: Appearance.font.pixelSize.small
                                                    font.weight: Font.Bold
                                                    color: Appearance.colors.colPrimary
                                                }
                                                StyledText {
                                                    Layout.alignment: Qt.AlignHCenter
                                                    text: Translation.tr("New")
                                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                                    color: root.colSubtext
                                                }
                                            }
                                        }

                                        Rectangle {
                                            objectName: "srAnalyticsRetentionTile"
                                            Layout.fillWidth: true
                                            implicitHeight: 36
                                            radius: 6
                                            color: root.colAnalyticsSubBoxBg
                                            ColumnLayout {
                                                anchors.centerIn: parent
                                                spacing: 0
                                                StyledText {
                                                    Layout.alignment: Qt.AlignHCenter
                                                    text: `${root.activeScopeStats?.retention ?? 100}%`
                                                    font.pixelSize: Appearance.font.pixelSize.small
                                                    font.weight: Font.Bold
                                                    color: "#10b981"
                                                }
                                                StyledText {
                                                    Layout.alignment: Qt.AlignHCenter
                                                    text: Translation.tr("Retention")
                                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                                    color: root.colSubtext
                                                }
                                            }
                                        }
                                    }

                                    // Study-Tracker Donut Chart + Interactive CEFR Distribution Legend
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8

                                        Item {
                                            width: 78
                                            height: 78

                                            Canvas {
                                                id: srDonutCanvas
                                                anchors.fill: parent
                                                property var cefrData: root.backend.analytics?.cefrCounts ?? ({})
                                                property int totalCards: root.backend.analytics?.total ?? 0
                                                property string hoveredLvl: root.hoveredCefrLevel
                                                readonly property bool paintReady: available && root._canvasesSettled && visible
                                                onPaintReadyChanged: if (paintReady) requestPaint()
                                                onCefrDataChanged: if (paintReady) requestPaint()
                                                onTotalCardsChanged: if (paintReady) requestPaint()
                                                onHoveredLvlChanged: if (paintReady) requestPaint()

                                                onPaint: {
                                                    var ctx = getContext("2d")
                                                    ctx.reset()
                                                    var cx = width / 2
                                                    var cy = height / 2
                                                    var r = Math.min(width, height) / 2 - 6
                                                    var levels = ["A1", "A2", "B1", "B2", "C1", "C2"]
                                                    var sum = 0
                                                    for (var i = 0; i < levels.length; i++) {
                                                        sum += Number(cefrData[levels[i]] || 0)
                                                    }
                                                    if (sum <= 0) {
                                                        ctx.beginPath()
                                                        ctx.arc(cx, cy, r, 0, Math.PI * 2)
                                                        ctx.lineWidth = 8
                                                        ctx.strokeStyle = Qt.rgba(0.5, 0.5, 0.5, 0.2)
                                                        ctx.stroke()
                                                        return
                                                    }
                                                    var startAngle = -Math.PI / 2
                                                    for (var j = 0; j < levels.length; j++) {
                                                        var lv = levels[j]
                                                        var cnt = Number(cefrData[lv] || 0)
                                                        if (cnt <= 0) continue
                                                        var slice = (cnt / sum) * Math.PI * 2
                                                        var isHov = (hoveredLvl === lv)
                                                        ctx.beginPath()
                                                        ctx.arc(cx, cy, isHov ? r + 1.5 : r, startAngle, startAngle + slice)
                                                        ctx.lineWidth = isHov ? 10 : 8
                                                        ctx.strokeStyle = root.cefrColor(lv).toString()
                                                        ctx.globalAlpha = (hoveredLvl !== "" && !isHov) ? 0.35 : 1.0
                                                        ctx.stroke()
                                                        startAngle += slice
                                                    }
                                                    ctx.globalAlpha = 1.0
                                                }
                                            }

                                            ColumnLayout {
                                                anchors.centerIn: parent
                                                spacing: 0
                                                StyledText {
                                                    Layout.alignment: Qt.AlignHCenter
                                                    text: root.hoveredCefrLevel !== ""
                                                        ? String(root.backend.analytics?.cefrCounts?.[root.hoveredCefrLevel] ?? 0)
                                                        : String(root.backend.analytics?.total ?? 0)
                                                    font.pixelSize: Appearance.font.pixelSize.small
                                                    font.weight: Font.Bold
                                                    color: root.hoveredCefrLevel !== ""
                                                        ? root.cefrColor(root.hoveredCefrLevel)
                                                        : root.colText
                                                }
                                                StyledText {
                                                    Layout.alignment: Qt.AlignHCenter
                                                    text: root.hoveredCefrLevel !== "" ? root.hoveredCefrLevel : Translation.tr("cards")
                                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                                    color: root.colSubtext
                                                }
                                            }
                                        }

                                        // Compact 2-column CEFR Breakdown Legend
                                        GridLayout {
                                            Layout.fillWidth: true
                                            columns: 2
                                            rowSpacing: 2
                                            columnSpacing: 6

                                            Repeater {
                                                model: ["A1", "A2", "B1", "B2", "C1", "C2"]
                                                delegate: Rectangle {
                                                    required property string modelData
                                                    readonly property int cCount: root.backend.analytics?.cefrCounts?.[modelData] ?? 0
                                                    Layout.fillWidth: true
                                                    implicitHeight: 18
                                                    radius: 4
                                                    color: root.hoveredCefrLevel === modelData
                                                        ? Qt.alpha(root.cefrColor(modelData), 0.16)
                                                        : "transparent"

                                                    RowLayout {
                                                        anchors { fill: parent; leftMargin: 4; rightMargin: 4 }
                                                        spacing: 4
                                                        Rectangle {
                                                            width: 6; height: 6; radius: 3
                                                            color: root.cefrColor(modelData)
                                                        }
                                                        StyledText {
                                                            text: modelData
                                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                                            font.weight: Font.Bold
                                                            color: root.colText
                                                        }
                                                        Item { Layout.fillWidth: true }
                                                        StyledText {
                                                            text: String(cCount)
                                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                                            color: root.colSubtext
                                                        }
                                                    }

                                                    MouseArea {
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        onEntered: root.hoveredCefrLevel = modelData
                                                        onExited: if (root.hoveredCefrLevel === modelData) root.hoveredCefrLevel = ""
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // Memory Depth / Session Quality Distribution Bar (Mature / Young / Learning)
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 3

                                        StyledText {
                                            text: Translation.tr("MEMORY MATURITY")
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            font.weight: Font.Bold
                                            font.letterSpacing: 0.6
                                            color: root.colSubtext
                                        }

                                        Rectangle {
                                            objectName: "srAnalyticsMaturityTrack"
                                            Layout.fillWidth: true
                                            height: 5
                                            radius: 2.5
                                            color: root.colAnalyticsSubBoxBg
                                            clip: true

                                            Row {
                                                anchors.fill: parent
                                                Rectangle {
                                                    height: parent.height
                                                    width: parent.width * ((root.backend.analytics?.maturityTiers?.mature?.pct ?? 0) / 100.0)
                                                    color: "#10b981"
                                                }
                                                Rectangle {
                                                    height: parent.height
                                                    width: parent.width * ((root.backend.analytics?.maturityTiers?.young?.pct ?? 0) / 100.0)
                                                    color: Appearance.colors.colPrimary
                                                }
                                                Rectangle {
                                                    height: parent.height
                                                    width: Math.max(0, parent.width
                                                        - parent.width * ((root.backend.analytics?.maturityTiers?.mature?.pct ?? 0) / 100.0)
                                                        - parent.width * ((root.backend.analytics?.maturityTiers?.young?.pct ?? 0) / 100.0))
                                                    color: "#f59e0b"
                                                }
                                            }
                                        }

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 4

                                            StyledText {
                                                text: Translation.tr("Mature %1%").arg(root.backend.analytics?.maturityTiers?.mature?.pct ?? 0)
                                                font.pixelSize: Appearance.font.pixelSize.smallest
                                                color: "#10b981"
                                            }
                                            Item { Layout.fillWidth: true }
                                            StyledText {
                                                text: Translation.tr("Young %1%").arg(root.backend.analytics?.maturityTiers?.young?.pct ?? 0)
                                                font.pixelSize: Appearance.font.pixelSize.smallest
                                                color: Appearance.colors.colPrimary
                                            }
                                            Item { Layout.fillWidth: true }
                                            StyledText {
                                                text: Translation.tr("New/Learn %1%").arg(root.backend.analytics?.maturityTiers?.learning?.pct ?? 0)
                                                font.pixelSize: Appearance.font.pixelSize.smallest
                                                color: "#f59e0b"
                                            }
                                        }
                                    }
                                }
                            }

                            // 4. 7-DAY REVIEW FORECAST & EASE HEALTH CARD (fills exact remaining bottom space without scrolling)
                            Rectangle {
                                id: srForecastCard
                                objectName: "srAnalyticsForecastCard"
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.minimumHeight: 62
                                implicitHeight: srForecastCol.implicitHeight + 12
                                radius: Appearance.rounding.small
                                color: root.colAnalyticsCardBg
                                border.width: 1
                                border.color: root.colAnalyticsBorder

                                ColumnLayout {
                                    id: srForecastCol
                                    anchors { fill: parent; margins: 6 }
                                    spacing: 3

                                    // Header Row: 7D FORECAST + 7d Load + Avg Ease Pill
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 4

                                        StyledText {
                                            text: Translation.tr("7D FORECAST")
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            font.weight: Font.Bold
                                            font.letterSpacing: 0.6
                                            color: root.colSubtext
                                        }

                                        StyledText {
                                            text: `· ${root.upcomingForecast7d.total7d ?? 0}`
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            font.weight: Font.DemiBold
                                            color: root.colText
                                        }

                                        Item { Layout.fillWidth: true }

                                        Rectangle {
                                            implicitWidth: easePillRow.implicitWidth + 8
                                            implicitHeight: 16
                                            radius: 8
                                            color: Qt.alpha(Appearance.colors.colPrimary, 0.14)

                                            RowLayout {
                                                id: easePillRow
                                                anchors.centerIn: parent
                                                spacing: 2
                                                MaterialSymbol {
                                                    text: "bolt"
                                                    iconSize: 11
                                                    color: Appearance.colors.colPrimary
                                                }
                                                StyledText {
                                                    text: Translation.tr("Ease %1%").arg(root.backend.analytics?.averageEase ?? 250)
                                                    font.pixelSize: 10
                                                    font.weight: Font.Bold
                                                    color: Appearance.colors.colPrimary
                                                }
                                            }
                                        }
                                    }

                                    // 7-Day Vertical Bar Strip (Today + Next 6 Days)
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        Layout.minimumHeight: 34
                                        spacing: 4

                                        Repeater {
                                            model: root.upcomingForecast7d.days ?? []
                                            delegate: ColumnLayout {
                                                required property var modelData
                                                required property int index
                                                Layout.fillWidth: true
                                                Layout.fillHeight: true
                                                spacing: 1

                                                StyledText {
                                                    Layout.alignment: Qt.AlignHCenter
                                                    text: String(modelData.count ?? 0)
                                                    font.pixelSize: 9
                                                    font.weight: modelData.count > 0 ? Font.Bold : Font.Normal
                                                    color: modelData.isToday
                                                        ? Appearance.colors.colPrimary
                                                        : modelData.count > 0 ? root.colText : root.colSubtext
                                                }

                                                Rectangle {
                                                    objectName: "srForecastBarTrack-" + index
                                                    Layout.fillWidth: true
                                                    Layout.fillHeight: true
                                                    Layout.minimumHeight: 10
                                                    radius: 3
                                                    color: root.colAnalyticsSubBoxBg

                                                    Rectangle {
                                                        anchors.left: parent.left
                                                        anchors.right: parent.right
                                                        anchors.bottom: parent.bottom
                                                        height: modelData.count > 0
                                                            ? Math.max(4, Math.round((modelData.count / Math.max(1, root.upcomingForecast7d.maxCount)) * parent.height))
                                                            : 2
                                                        radius: 3
                                                        color: modelData.isToday
                                                            ? Appearance.colors.colPrimary
                                                            : modelData.count > 0
                                                                ? Qt.alpha(Appearance.colors.colPrimary, 0.62)
                                                                : ColorUtils.mix(root.colAnalyticsSubBoxBg, Appearance.colors.colPrimary, 0.86)
                                                    }
                                                }

                                                StyledText {
                                                    Layout.alignment: Qt.AlignHCenter
                                                    text: modelData.label ?? ""
                                                    font.pixelSize: 9
                                                    font.weight: modelData.isToday ? Font.Bold : Font.Medium
                                                    color: modelData.isToday ? Appearance.colors.colPrimary : root.colSubtext
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

            // =================================================================
            // SUB-TAB 2: AUTO-SYNTAX & SMART COMPOSER
            // =================================================================
            Loader {
                id: capturePaneLoader
                anchors.fill: parent
                active: root._captureLoaded
                visible: root.subTab === "capture"
                onLoaded: root.syncComposerFieldsFromState()
                sourceComponent: Component {
                    RowLayout {
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
                                Component.onCompleted: root.composerFrontField = composerFrontField
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
                                            color: root.colAnalyticsSubBoxBg
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
                                Component.onCompleted: root.composerBackField = composerBackField
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
                                Component.onCompleted: root.composerExampleField = composerExampleField
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
                                        Component.onCompleted: root.composerDeckField = composerDeckField
                                        placeholderText: Translation.tr("Deck name (Default)")
                                        text: root.composerDeck
                                        onTextEdited: root.composerDeck = text
                                        onTextChanged: if (root.composerDeck !== text) root.composerDeck = text
                                    }
                                    StyledTextField {
                                        id: composerPhoneticsField
                                        Layout.fillWidth: true
                                        Component.onCompleted: root.composerPhoneticsField = composerPhoneticsField
                                        placeholderText: Translation.tr("IPA override (/.../)")
                                        text: root.composerPhonetics
                                        onTextEdited: root.composerPhonetics = text
                                        onTextChanged: if (root.composerPhonetics !== text) root.composerPhonetics = text
                                    }
                                    StyledTextField {
                                        id: composerPosField
                                        Layout.preferredWidth: 110
                                        Component.onCompleted: root.composerPosField = composerPosField
                                        placeholderText: Translation.tr("Part of Speech")
                                        text: root.composerPos
                                        onTextEdited: root.composerPos = text
                                        onTextChanged: if (root.composerPos !== text) root.composerPos = text
                                    }
                                    StyledTextField {
                                        id: composerCefrField
                                        Layout.preferredWidth: 90
                                        Component.onCompleted: root.composerCefrField = composerCefrField
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
                                        Component.onCompleted: root.composerSynonymsField = composerSynonymsField
                                        placeholderText: Translation.tr("Synonyms override (comma-separated)")
                                        text: root.composerSynonyms
                                        onTextEdited: root.composerSynonyms = text
                                        onTextChanged: if (root.composerSynonyms !== text) root.composerSynonyms = text
                                    }

                                    StyledTextField {
                                        id: composerAntonymsField
                                        Layout.fillWidth: true
                                        Component.onCompleted: root.composerAntonymsField = composerAntonymsField
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
                                                color: root.colActivePillInk
                                            }
                                            StyledText {
                                                anchors.verticalCenter: parent.verticalCenter
                                                horizontalAlignment: Text.AlignHCenter
                                                text: Translation.tr("Add Card")
                                                font.pixelSize: Appearance.font.pixelSize.small
                                                font.weight: Font.Bold
                                                color: root.colActivePillInk
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Right Column: Zero-Markup Bulk Auto-Syntax & Nexus SR Importer
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
                                text: Translation.tr("Bulk Auto-Syntax & Nexus SR Importer")
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
                                tooltipText: Translation.tr("View supported auto-syntax & Nexus SR formats (Esc to close)")
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
                                            text: Translation.tr("Auto-Syntax & Nexus SR Guide")
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
                                                title: Translation.tr("• 3. Nexus Multi-Line & Unit Flashcards"),
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
                                                color: root.colAnalyticsSubBoxBg
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
                                    Component.onCompleted: root.bulkInputArea = bulkInputArea
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
                }
            }

            // =================================================================
            // SUB-TAB 3: LIBRARY & DECK BROWSER
            // =================================================================
            Loader {
                id: libraryPaneLoader
                anchors.fill: parent
                active: root._libraryLoaded
                visible: root.subTab === "library"
                sourceComponent: Component {
                    Rectangle {
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
                                    Component.onCompleted: root.librarySearchField = librarySearchField
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
                                        color: root.colAnalyticsSubBoxBg
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
                                        color: root.colBorder
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
    }
}
