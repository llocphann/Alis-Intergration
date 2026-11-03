pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import "SpacedRepetitionEngine.js" as Engine
import "SpacedRepetitionLexicon.js" as Lexicon

Singleton {
    id: root

    property string filePath: Directories.spacedRepetitionPath
    property string lookupScriptPath: AlisIntergration.spacedRepetitionLookupScriptPath()
        || `${Directories.scriptsPath}/spaced-repetition/lookup_word_level.py`
    property var cards: []
    property var historyByDay: ({})
    property var retainedStorageFields: ({})
    property int nextId: 100
    property bool ready: false
    property bool lookupBusy: false
    property var lastLookupResult: null
    property string errorMessage: ""

    // Active filters & session state
    property string filterCategory: "all"
    property string filterLanguage: "all"
    property string filterLevel: "all"
    property string filterDeck: "all"
    property alias selectedCategory: root.filterCategory
    property alias selectedLanguage: root.filterLanguage
    property alias selectedCefrLevel: root.filterLevel
    property alias selectedDeck: root.filterDeck
    property bool leechesOnly: false
    property string searchQuery: ""
    property string boostMode: ""
    property int boostAheadDays: 3
    property string studyMode: "flashcard" // "flashcard", "reverse", "cloze"
    property bool cardRevealed: false
    property var _undoStack: []
    property real _sessionClockMs: Date.now()

    readonly property bool canUndoReview: root._undoStack.length > 0
    readonly property bool boostActive: root.boostMode.length > 0
    readonly property string configuredStudyDirection: String(Config.options?.dashboard?.spacedRepetition?.studyDirection ?? "both").toLowerCase()

    onConfiguredStudyDirectionChanged: {
        if (root.configuredStudyDirection === "reverse")
            root.studyMode = "reverse"
        else if (root.configuredStudyDirection === "cloze")
            root.studyMode = "cloze"
        else if (root.configuredStudyDirection === "flashcard" || root.configuredStudyDirection === "forward")
            root.studyMode = "flashcard"
    }

    readonly property var options: Engine.normalizeOptions({
        enable: Config.options?.dashboard?.spacedRepetition?.enable ?? true,
        dailyNewLimit: Config.options?.dashboard?.spacedRepetition?.dailyNewLimit ?? 20,
        dailyReviewLimit: Config.options?.dashboard?.spacedRepetition?.dailyReviewLimit ?? 100,
        baseEase: Config.options?.dashboard?.spacedRepetition?.baseEase ?? 250,
        easyBonus: Config.options?.dashboard?.spacedRepetition?.easyBonus ?? 1.3,
        hardMultiplier: Config.options?.dashboard?.spacedRepetition?.hardMultiplier ?? 1.2,
        lapseMultiplier: Config.options?.dashboard?.spacedRepetition?.lapseMultiplier ?? 0.5,
        maximumInterval: Config.options?.dashboard?.spacedRepetition?.maximumInterval ?? 3650,
        loadBalance: Config.options?.dashboard?.spacedRepetition?.loadBalance ?? true,
        leechThreshold: Config.options?.dashboard?.spacedRepetition?.leechThreshold ?? 6,
        boostMultiplier: Config.options?.dashboard?.spacedRepetition?.boostMultiplier ?? 1.0,
        defaultLanguage: Config.options?.dashboard?.spacedRepetition?.defaultLanguage ?? "en",
        studyDirection: Config.options?.dashboard?.spacedRepetition?.studyDirection ?? "both",
        prioritizeOrder: Config.options?.dashboard?.spacedRepetition?.prioritizeOrder ?? "due_first",
        autoLookupLevel: Config.options?.dashboard?.spacedRepetition?.autoLookupLevel ?? true,
        autoLookupOnline: Config.options?.dashboard?.spacedRepetition?.autoLookupOnline ?? true,
        autoCloze: Config.options?.dashboard?.spacedRepetition?.autoCloze ?? true
    })

    readonly property var analytics: Engine.computeAnalytics(
        root.cards,
        root.historyByDay,
        root._sessionClockMs,
        root.options
    )

    readonly property var decks: root.analytics.decks ?? []
    readonly property int totalCount: root.analytics.counts?.total ?? 0
    readonly property int dueCount: root.analytics.counts?.due ?? 0
    readonly property int newCount: root.analytics.counts?.newCards ?? 0
    readonly property int learningCount: root.analytics.counts?.learning ?? 0
    readonly property int youngCount: root.analytics.counts?.young ?? 0
    readonly property int matureCount: root.analytics.counts?.mature ?? 0
    readonly property int leechCount: root.analytics.counts?.leeches ?? 0
    readonly property int vocabCount: root.analytics.counts?.vocab ?? 0
    readonly property int knowledgeCount: root.analytics.counts?.knowledge ?? 0
    readonly property int clozeCount: root.analytics.counts?.cloze ?? 0
    readonly property int streakDays: root.analytics.streakDays ?? 0
    readonly property int todayReviewedCount: root.analytics.todayReviewed ?? 0
    readonly property int retentionRate: root.analytics.retentionRate ?? 100
    readonly property int averageEase: root.analytics.averageEase ?? 250
    readonly property var levelBreakdown: root.analytics.levels ?? ({})
    readonly property var masteredLevelBreakdown: root.analytics.masteredLevels ?? ({})

    readonly property var studyQueue: {
        const todayKey = Engine.civilDayKey(root._sessionClockMs)
        const todayStats = root.historyByDay[todayKey] ?? { newStudied: 0, reviewsDone: 0 }
        return Engine.buildStudyQueue(
            root.cards,
            {
                category: root.filterCategory,
                language: root.filterLanguage,
                level: root.filterLevel,
                deck: root.filterDeck,
                leechesOnly: root.leechesOnly,
                searchQuery: root.searchQuery,
                boostMode: root.boostMode,
                aheadDays: root.boostAheadDays
            },
            todayStats,
            root._sessionClockMs,
            root.options
        )
    }

    readonly property var currentCard: root.studyQueue.length > 0 ? root.studyQueue[0] : null
    readonly property bool hasActiveCard: root.currentCard !== null
    readonly property var currentIntervals: Engine.previewIntervals(
        root.currentCard,
        root._sessionClockMs,
        root.options
    )

    readonly property var filteredLibraryCards: {
        const cat = root.filterCategory.toLowerCase()
        const lang = root.filterLanguage.toLowerCase()
        const lvl = root.filterLevel.toUpperCase()
        const dName = root.filterDeck
        const q = root.searchQuery.trim().toLowerCase()
        return root.cards.filter(card => {
            if (!card) return false
            if (cat !== "all" && card.category !== cat) return false
            if (lang !== "all" && card.language !== lang) return false
            if (lvl !== "ALL") {
                if (lvl === "UNLEVELED" && card.level) return false
                if (lvl !== "UNLEVELED" && String(card.level ?? "").toUpperCase() !== lvl) return false
            }
            if (dName !== "all" && card.deck !== dName) return false
            if (root.leechesOnly && !card.isLeech && (Number(card.lapses) || 0) < root.options.leechThreshold) return false
            if (q.length > 0) {
                const hay = `${card.term ?? ""} ${card.front ?? ""} ${card.meaning ?? ""} ${card.back ?? ""} ${card.definitionEn ?? ""} ${card.meaningVi ?? ""} ${card.example ?? ""} ${card.cefrLevel ?? ""} ${card.deck ?? ""} ${card.notes ?? ""} ${card.morphologyText ?? ""} ${(card.collocations ?? []).join(" ")}`.toLowerCase()
                if (!hay.includes(q)) return false
            }
            return true
        })
    }

    signal cardsPersisted(int count)
    signal cardReviewed(var card, string rating, string nextLabel)
    signal onlineLookupFinished(var result)

    property bool _saving: false
    property bool _saveQueued: false
    property string _lastSavedJson: ""

    Component.onCompleted: {
        loadFromFile()
    }

    onCurrentCardChanged: {
        root.cardRevealed = false
    }

    function refreshClock(): void {
        root._sessionClockMs = Date.now()
    }

    function formatMorphology(cardOrMorphology): string {
        return Engine.formatMorphology(cardOrMorphology)
    }

    function analyzeDraft(termOrPayload, language = "", exampleSentence = "", explicitArticle = ""): var {
        let term = termOrPayload
        let lang = language
        let ex = exampleSentence
        let artExplicit = explicitArticle
        let explicitPos = ""
        let explicitPhonetics = ""
        let explicitLevel = ""
        let explicitPlural = ""
        let explicitSynonyms = null
        let explicitAntonyms = null
        if (termOrPayload && typeof termOrPayload === "object") {
            term = termOrPayload.term ?? termOrPayload.front ?? termOrPayload.headword ?? ""
            lang = termOrPayload.language ?? language
            ex = termOrPayload.example ?? exampleSentence
            artExplicit = termOrPayload.article ?? termOrPayload.gender ?? explicitArticle
            explicitPos = termOrPayload.pos ?? ""
            explicitPhonetics = termOrPayload.phonetics ?? termOrPayload.phonetic ?? ""
            explicitLevel = termOrPayload.cefrLevel ?? termOrPayload.level ?? ""
            explicitPlural = termOrPayload.plural ?? ""
            explicitSynonyms = termOrPayload.synonyms ?? null
            explicitAntonyms = termOrPayload.antonyms ?? null
        }
        let lex = Lexicon.analyzeTerm(String(term ?? ""), lang || root.options.defaultLanguage)
        if (root.lastLookupResult
                && String(root.lastLookupResult.word || "").toLowerCase() === String(lex.word || "").toLowerCase()
                && String(lex.word || "").length > 0) {
            lex = Lexicon.mergeOnlineLookup(lex, root.lastLookupResult)
        }
        const art = String(artExplicit || lex.article || "").trim()
        const pos = String(explicitPos || lex.pos || "").trim()
        const phon = String(explicitPhonetics || lex.phonetics || lex.phonetic || "").trim()
        const lvl = String(explicitLevel || lex.cefrLevel || lex.level || "").toUpperCase().trim()
        const pl = String(explicitPlural || lex.plural || "").trim()
        const syns = Array.isArray(explicitSynonyms) && explicitSynonyms.length > 0
            ? explicitSynonyms
            : (Array.isArray(lex.synonyms) ? lex.synonyms : [])
        const ants = Array.isArray(explicitAntonyms) && explicitAntonyms.length > 0
            ? explicitAntonyms
            : (Array.isArray(lex.antonyms) ? lex.antonyms : [])
        const morph = Array.isArray(lex.morphology) ? lex.morphology : []
        const morphText = String(lex.morphologyText || Engine.formatMorphology(morph)).trim()
        const cloze = Engine.autoGenerateCloze(lex.word || String(term ?? ""), ex || lex.example || "", art)
        return Object.assign({}, lex, {
            pos: pos,
            phonetic: phon,
            phonetics: phon,
            level: lvl || lex.level,
            cefrLevel: lvl || lex.cefrLevel,
            article: art,
            gender: art,
            plural: pl,
            synonyms: syns,
            antonyms: ants,
            morphology: morph,
            morphologyText: morphText,
            clozeText: cloze
        })
    }

    function renderClozeQuestion(card): string {
        if (!card) return ""
        return Engine.renderClozeFront(card.clozeText || card.example || "", card.term || card.front || "")
    }

    function renderClozeAnswer(card): string {
        if (!card) return ""
        return Engine.renderClozeBack(card.clozeText || card.example || "")
    }

    function renderClozeFront(card): string {
        return root.renderClozeQuestion(card)
    }

    function renderClozeBack(card): string {
        return root.renderClozeAnswer(card)
    }

    function extractClozeTargets(card): var {
        if (!card) return []
        const rawCloze = card.clozeText || Engine.autoGenerateCloze(card.term || card.front || "", card.example || "", card.article || card.gender || "")
        return Engine.extractAllClozeTargets(rawCloze)
    }

    function extractClozeTarget(card): string {
        if (!card) return ""
        const targets = root.extractClozeTargets(card)
        return (targets && targets.length > 0) ? String(targets[0]) : String(card.headword || card.term || card.front || "")
    }

    function revealCard(): void {
        if (root.currentCard)
            root.cardRevealed = true
    }

    function submitRating(rating: string): bool {
        return root.rateCurrentCard(rating)
    }

    function rateCurrentCard(rating: string): bool {
        const active = root.currentCard
        if (!active) return false
        const now = Date.now()
        root._sessionClockMs = now
        const wasNew = (Number(active.reps) || 0) === 0 && active.state === "new"
        const prevCardSnapshot = JSON.parse(JSON.stringify(active))
        const prevHistorySnapshot = JSON.parse(JSON.stringify(root.historyByDay))

        const scheduled = Engine.scheduleReview(
            active,
            rating,
            now,
            root.options,
            root.analytics.dueCountsByDay
        )

        const nextCards = root.cards.map(item => item.id === active.id ? scheduled.card : item)
        const dayKey = Engine.civilDayKey(now)
        const nextHistory = Object.assign({}, root.historyByDay)
        const prevDay = nextHistory[dayKey] ?? { reviewed: 0, passed: 0, newStudied: 0, reviewsDone: 0 }
        const passed = rating !== "again" && rating !== "0" && rating !== "reset"

        nextHistory[dayKey] = {
            reviewed: (Number(prevDay.reviewed) || 0) + 1,
            passed: (Number(prevDay.passed) || 0) + (passed ? 1 : 0),
            newStudied: (Number(prevDay.newStudied) || 0) + (wasNew ? 1 : 0),
            reviewsDone: (Number(prevDay.reviewsDone) || 0) + (wasNew ? 0 : 1)
        }

        root._undoStack = root._undoStack.slice(-19).concat([{
            card: prevCardSnapshot,
            historyByDay: prevHistorySnapshot
        }])
        root.cards = nextCards
        root.historyByDay = nextHistory
        root.cardRevealed = false
        root.scheduleSave()
        root.cardReviewed(scheduled.card, rating, scheduled.label)
        return true
    }

    function undoLastReview(): bool {
        if (root._undoStack.length === 0) return false
        const stack = root._undoStack.slice()
        const last = stack.pop()
        root._undoStack = stack
        root.cards = root.cards.map(item => item.id === last.card.id ? last.card : item)
        root.historyByDay = last.historyByDay
        root.cardRevealed = false
        root._sessionClockMs = Date.now()
        root.scheduleSave()
        return true
    }

    function addCard(payload): var {
        const now = Date.now()
        root._sessionClockMs = now
        const allocatedId = `sr-card-${root.nextId++}`
        const normalized = Engine.normalizeCard(
            Object.assign({}, payload ?? {}, { id: allocatedId, createdAt: now, dueAt: now - 1000 }),
            root.nextId,
            now,
            root.options,
            root.options.autoLookupLevel ? Lexicon.analyzeTerm : null
        )
        if (!normalized.term && !normalized.clozeText)
            return null
        root.cards = [normalized].concat(root.cards)
        root.scheduleSave()
        if (root.options.autoLookupOnline
                && normalized.category === "vocabulary"
                && (!normalized.phonetics || !normalized.synonyms?.length || !normalized.antonyms?.length)) {
            Qt.callLater(() => root.enrichCardOnline(normalized.id))
        }
        return normalized
    }

    function updateCard(id: string, patch: var): bool {
        const index = root.cards.findIndex(item => item.id === id)
        if (index < 0) return false
        const current = root.cards[index]
        const merged = Object.assign({}, current, patch ?? {}, { id: current.id })
        const normalized = Engine.normalizeCard(
            merged,
            index + 1,
            Date.now(),
            root.options,
            root.options.autoLookupLevel ? Lexicon.analyzeTerm : null
        )
        const copy = root.cards.slice()
        copy[index] = normalized
        root.cards = copy
        root.scheduleSave()
        return true
    }

    function deleteCard(id: string): bool {
        const before = root.cards.length
        const next = root.cards.filter(item => item.id !== id)
        if (next.length === before) return false
        root.cards = next
        root.scheduleSave()
        return true
    }

    function resetCardProgress(id: string): bool {
        const now = Date.now()
        return root.updateCard(id, {
            state: "new",
            interval: 0,
            reps: 0,
            lapses: 0,
            ease: root.options.baseEase,
            dueAt: now,
            lastReviewedAt: 0
        })
    }

    function previewQuickText(rawText: string, deckName: string, language: string, category: string): var {
        return Engine.parseQuickInput(
            rawText,
            {
                deck: deckName,
                language: language || root.options.defaultLanguage,
                category: category || "auto",
                baseEase: root.options.baseEase,
                autoCloze: root.options.autoCloze
            },
            root.options.autoLookupLevel ? Lexicon.analyzeTerm : null
        )
    }

    function importQuickText(rawText: string, deckName: string, language: string, category: string): int {
        const parsed = root.previewQuickText(rawText, deckName, language, category)
        if (!Array.isArray(parsed) || parsed.length === 0)
            return 0
        const now = Date.now()
        root._sessionClockMs = now
        const created = []
        for (let i = 0; i < parsed.length; i++) {
            const item = Object.assign({}, parsed[i], {
                id: `sr-card-${root.nextId++}`,
                createdAt: now - i
            })
            created.push(item)
        }
        root.cards = created.concat(root.cards)
        root.scheduleSave()
        if (root.options.autoLookupOnline) {
            Qt.callLater(() => {
                for (let i = 0; i < created.length; i++) {
                    const card = created[i]
                    if (card.category === "vocabulary"
                            && (!card.phonetics || !card.meaning || !card.synonyms?.length || !card.antonyms?.length)) {
                        root.enrichCardOnline(card.id)
                    }
                }
            })
        }
        return created.length
    }

    function startBoostSession(mode: string): void {
        root.boostMode = String(mode ?? "").trim()
        root._sessionClockMs = Date.now()
        root.cardRevealed = false
    }

    function startBoost(mode = "ahead", days = 3): void {
        const cleanMode = String(mode ?? "ahead").trim()
        root.boostAheadDays = Math.max(1, Number(days) || 3)
        root.startBoostSession(cleanMode || "ahead")
    }

    function stopBoost(): void {
        root.startBoostSession("")
    }

    function clearFilters(): void {
        root.filterCategory = "all"
        root.filterLanguage = "all"
        root.filterLevel = "all"
        root.filterDeck = "all"
        root.leechesOnly = false
        root.searchQuery = ""
        root.boostMode = ""
    }

    property var _lookupQueue: []

    function _applyLookupToCard(targetId: string, merged: var): void {
        const existing = root.cards.find(item => item && item.id === targetId)
        if (!existing || !merged) return
        const existingMeaning = String(existing.meaning || existing.back || "").trim()
        const existingExample = String(existing.example || "").trim()
        const patch = {
            level: existing.level || merged.level,
            levelSource: existing.levelSource || merged.levelSource,
            pos: existing.pos || merged.pos,
            phonetic: existing.phonetics || existing.phonetic || merged.phonetic,
            article: existing.article || merged.article,
            plural: existing.plural || merged.plural
        }
        if ((!existingMeaning || existingMeaning === "...") && merged.meaning) {
            patch.meaning = merged.meaning
            patch.back = merged.meaning
            patch.definitionEn = merged.definitionEn || merged.meaning
        }
        if (!existing.meaningVi && merged.meaningVi) {
            patch.meaningVi = merged.meaningVi
        }
        if (!existingExample && merged.example) {
            patch.example = merged.example
        }
        if ((!Array.isArray(existing.synonyms) || existing.synonyms.length === 0)
                && Array.isArray(merged.synonyms) && merged.synonyms.length > 0) {
            patch.synonyms = merged.synonyms
        }
        if ((!Array.isArray(existing.antonyms) || existing.antonyms.length === 0)
                && Array.isArray(merged.antonyms) && merged.antonyms.length > 0) {
            patch.antonyms = merged.antonyms
        }
        if (Array.isArray(merged.morphology) && merged.morphology.length > 0) {
            patch.morphology = merged.morphology
            patch.morphologyText = merged.morphologyText || Engine.formatMorphology(merged.morphology)
        }
        root.updateCard(targetId, patch)
    }

    function _startNextQueuedLookup(): void {
        if (lookupProc.running || root._lookupQueue.length === 0) return
        const nextReq = root._lookupQueue[0]
        root._lookupQueue = root._lookupQueue.slice(1)
        if (!nextReq || !nextReq.term) {
            root._startNextQueuedLookup()
            return
        }
        const local = Lexicon.analyzeTerm(nextReq.term, nextReq.language || root.options.defaultLanguage)
        if (!root.options.autoLookupOnline) {
            if (nextReq.cardId) {
                root._applyLookupToCard(nextReq.cardId, local)
            } else {
                root.lastLookupResult = local
                root.onlineLookupFinished(local)
            }
            root._startNextQueuedLookup()
            return
        }
        lookupProc.pendingLocal = local
        lookupProc.pendingCardId = String(nextReq.cardId || "")
        lookupProc.outputBuffer = ""
        lookupProc.command = [
            "/usr/bin/python3",
            root.lookupScriptPath,
            nextReq.term,
            "--lang",
            local.language || "auto"
        ]
        root.lookupBusy = true
        lookupProc.running = true
    }

    function enrichCardOnline(cardId: string): void {
        const card = root.cards.find(item => item && item.id === cardId)
        if (!card) return
        const term = String(card.term || card.front || card.headword || "").trim()
        if (!term) return
        const lang = card.language || root.options.defaultLanguage
        if (!root.options.autoLookupOnline) {
            const local = Lexicon.analyzeTerm(term, lang)
            root._applyLookupToCard(cardId, local)
            return
        }
        if (!root._lookupQueue.some(r => r && r.cardId === cardId)) {
            root._lookupQueue = root._lookupQueue.concat([{
                term: term,
                language: lang,
                cardId: cardId
            }])
        }
        root._startNextQueuedLookup()
    }

    function lookupWordOnline(term: string, language: string): void {
        const clean = String(term ?? "").trim()
        if (!clean) return
        const lang = language || root.options.defaultLanguage
        const local = Lexicon.analyzeTerm(clean, lang)
        root.lastLookupResult = local
        if (!root.options.autoLookupOnline) {
            root.onlineLookupFinished(local)
            return
        }
        // Keep only the latest interactive lookup at the head of the queue
        const remainingBg = root._lookupQueue.filter(r => r && Boolean(r.cardId))
        root._lookupQueue = [{
            term: clean,
            language: local.language || lang || "auto",
            cardId: ""
        }].concat(remainingBg)
        root._startNextQueuedLookup()
    }

    Process {
        id: lookupProc
        property var pendingLocal: null
        property string pendingCardId: ""
        property string outputBuffer: ""
        stdout: SplitParser {
            splitMarker: ""
            onRead: data => {
                lookupProc.outputBuffer += data
            }
        }
        onExited: (exitCode) => {
            let merged = lookupProc.pendingLocal ?? ({})
            if (exitCode === 0 && lookupProc.outputBuffer.trim().length > 0) {
                try {
                    const online = JSON.parse(lookupProc.outputBuffer.trim())
                    merged = Lexicon.mergeOnlineLookup(merged, online)
                } catch (e) {
                    // Fallback to offline analysis
                }
            }
            const targetId = lookupProc.pendingCardId
            lookupProc.pendingCardId = ""
            if (targetId) {
                root._applyLookupToCard(targetId, merged)
            } else {
                root.lastLookupResult = merged
                root.onlineLookupFinished(merged)
            }
            if (root._lookupQueue.length > 0) {
                root._startNextQueuedLookup()
            } else {
                root.lookupBusy = false
            }
        }
    }

    property bool _savePending: false
    readonly property bool persistenceBusy: root._saving || root._saveQueued || root._savePending

    function scheduleSave(): void {
        if (root._saving || initDirProc.running) {
            root._saveQueued = true
            return
        }
        root._savePending = true
        saveTimer.restart()
    }

    Timer {
        id: saveTimer
        interval: 40
        repeat: false
        onTriggered: root.saveToFile()
    }

    function serializeStorage(): string {
        const payload = Object.assign({}, root.retainedStorageFields, {
            schemaVersion: Engine.SCHEMA_VERSION,
            nextId: root.nextId,
            cards: root.cards,
            historyByDay: root.historyByDay
        })
        return JSON.stringify(payload, null, 2)
    }

    function loadFromFile(): void {
        srFileView.reload()
    }

    function saveToFile(): void {
        saveTimer.stop()
        if (!root.ready) {
            root._savePending = false
            return
        }
        if (root._saving || initDirProc.running) {
            root._saveQueued = true
            return
        }
        const parentDir = root.filePath.substring(0, root.filePath.lastIndexOf('/'))
        if (parentDir.length > 0 && !initDirProc.attempted) {
            root._savePending = true
            initDirProc.command = ["/usr/bin/mkdir", "-p", parentDir]
            initDirProc.attempted = true
            initDirProc.running = true
            return
        }
        const snapshot = root.serializeStorage()
        if (snapshot === root._lastSavedJson && !root._saveQueued) {
            root._savePending = false
            return
        }
        root._savePending = false
        root._saveQueued = false
        root._saving = true
        root._lastSavedJson = snapshot
        srFileView.setText(snapshot)
    }

    Process {
        id: initDirProc
        property bool attempted: false
        onExited: {
            root.saveToFile()
        }
    }

    FileView {
        id: srFileView
        path: Qt.resolvedUrl(root.filePath)
        watchChanges: true
        printErrors: false
        onLoaded: {
            if (root._saving || root._saveQueued) return
            const rawText = srFileView.text()
            if (!rawText || rawText.trim() === "") {
                const seeded = Engine.migrateStorage(null, Date.now(), root.options, Lexicon.analyzeTerm)
                root.cards = seeded.cards
                root.historyByDay = seeded.historyByDay
                root.retainedStorageFields = seeded.retainedStorageFields
                root.nextId = seeded.nextId
                root.ready = true
                root.scheduleSave()
                return
            }
            if (rawText === root._lastSavedJson && root.ready)
                return
            try {
                const parsed = JSON.parse(rawText)
                const migrated = Engine.migrateStorage(parsed, Date.now(), root.options, Lexicon.analyzeTerm)
                root.cards = migrated.cards
                root.historyByDay = migrated.historyByDay
                root.retainedStorageFields = migrated.retainedStorageFields
                root.nextId = migrated.nextId
                root._lastSavedJson = rawText
                root.errorMessage = ""
                root.ready = true
                if (root.serializeStorage() !== rawText) {
                    root.scheduleSave()
                }
            } catch (e) {
                root.errorMessage = Translation.tr("Could not parse Spaced Repetition storage file.")
                if (!root.ready) {
                    const fallback = Engine.migrateStorage(null, Date.now(), root.options, Lexicon.analyzeTerm)
                    root.cards = fallback.cards
                    root.historyByDay = fallback.historyByDay
                    root.nextId = fallback.nextId
                    root.ready = true
                }
            }
        }
        onLoadFailed: (error) => {
            if (error === FileViewError.FileNotFound) {
                const seeded = Engine.migrateStorage(null, Date.now(), root.options, Lexicon.analyzeTerm)
                root.cards = seeded.cards
                root.historyByDay = seeded.historyByDay
                root.retainedStorageFields = seeded.retainedStorageFields
                root.nextId = seeded.nextId
                root.ready = true
                root.scheduleSave()
                return
            }
            root.ready = true
        }
        onSaved: {
            root._saving = false
            root.errorMessage = ""
            root.cardsPersisted(root.cards.length)
            if (root._saveQueued) {
                root._saveQueued = false
                root.saveToFile()
            }
        }
        onSaveFailed: (error) => {
            root._saving = false
            root.errorMessage = Translation.tr("Could not save Spaced Repetition progress.")
        }
    }
}
