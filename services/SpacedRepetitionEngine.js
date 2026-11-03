// SpacedRepetitionEngine.js
// Pure scheduling, automated syntax parsing, queue construction, and storage migration
// for the Alis Dashboard Spaced Repetition system.
// Inspired by st3v3nmw/obsidian-spaced-repetition with enhancements:
// - Automated syntax & zero-markup structured cards (no <!--SR:...--> pollution)
// - Vocabulary-first (CEFR A1-C2, EN/DE gender/plural/IPA) + General Knowledge & Auto-Cloze
// - Configurable boost multiplier, lapse retention, load balancing, and leech detection.

var SCHEMA_VERSION = 4;
var DAY_MS = 86400000;
var MINUTE_MS = 60000;
var CEFR_ORDER = { "A1": 1, "A2": 2, "B1": 3, "B2": 4, "C1": 5, "C2": 6 };

function defaultOptions() {
    return {
        enable: true,
        dailyNewLimit: 20,
        dailyReviewLimit: 100,
        baseEase: 250,
        easyBonus: 1.3,
        hardMultiplier: 1.2,
        lapseMultiplier: 0.5,
        maximumInterval: 3650,
        loadBalance: true,
        leechThreshold: 6,
        boostMultiplier: 1.0,
        defaultLanguage: "en",
        studyDirection: "both",
        prioritizeOrder: "due_first",
        autoLookupLevel: true,
        autoLookupOnline: true,
        autoCloze: true
    };
}

function clampNumber(val, minVal, maxVal, fallback) {
    var n = Number(val);
    if (!Number.isFinite(n)) return fallback;
    return Math.max(minVal, Math.min(maxVal, n));
}

function normalizeRatio(val, minRatio, maxRatio, fallback) {
    var n = Number(val);
    if (!Number.isFinite(n)) return fallback;
    if (n > maxRatio && n <= maxRatio * 100) n = n / 100;
    return Math.max(minRatio, Math.min(maxRatio, n));
}

function normalizeOptions(raw) {
    var d = defaultOptions();
    var src = (raw && typeof raw === "object") ? raw : {};
    var lang = String(src.defaultLanguage || d.defaultLanguage).toLowerCase();
    if (["en", "de", "general", "other"].indexOf(lang) < 0) lang = "en";
    var dir = String(src.studyDirection || d.studyDirection).toLowerCase();
    if (dir === "flashcard") dir = "forward";
    if (["forward", "reverse", "both", "cloze"].indexOf(dir) < 0) dir = "both";
    var prio = String(src.prioritizeOrder || d.prioritizeOrder).toLowerCase().replace(/-/g, "_");
    if (prio === "hard_first") prio = "hardest_first";
    if (["due_first", "level_asc", "hardest_first", "new_first", "interleaved"].indexOf(prio) < 0) prio = "due_first";

    return {
        enable: src.enable !== false,
        dailyNewLimit: Math.round(clampNumber(src.dailyNewLimit, 1, 200, d.dailyNewLimit)),
        dailyReviewLimit: Math.round(clampNumber(src.dailyReviewLimit, 10, 1000, d.dailyReviewLimit)),
        baseEase: Math.round(clampNumber(src.baseEase, 130, 500, d.baseEase)),
        easyBonus: normalizeRatio(src.easyBonus, 1.0, 2.5, d.easyBonus),
        hardMultiplier: normalizeRatio(src.hardMultiplier, 0.5, 1.5, d.hardMultiplier),
        lapseMultiplier: normalizeRatio(src.lapseMultiplier, 0.0, 1.0, d.lapseMultiplier),
        maximumInterval: Math.round(clampNumber(src.maximumInterval, 7, 36525, d.maximumInterval)),
        loadBalance: src.loadBalance !== false,
        leechThreshold: Math.round(clampNumber(src.leechThreshold, 2, 20, d.leechThreshold)),
        boostMultiplier: normalizeRatio(src.boostMultiplier, 0.5, 2.5, d.boostMultiplier),
        defaultLanguage: lang,
        studyDirection: dir,
        prioritizeOrder: prio,
        autoLookupLevel: src.autoLookupLevel !== false,
        autoLookupOnline: src.autoLookupOnline !== false,
        autoCloze: src.autoCloze !== false
    };
}

function civilDayKey(ms) {
    var d = new Date(Number.isFinite(Number(ms)) ? Number(ms) : Date.now());
    var year = d.getFullYear();
    var month = String(d.getMonth() + 1).padStart(2, "0");
    var day = String(d.getDate()).padStart(2, "0");
    return year + "-" + month + "-" + day;
}

function escapeRegExp(str) {
    return String(str || "").replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function normalizeClozeMarkup(text) {
    var s = String(text || "");
    var counter = 1;
    // Convert Obsidian ==highlight== into {{c1::highlight}}
    s = s.replace(/==([^=\n]+)==/g, function(_, inner) {
        return "{{c" + (counter++) + "::" + inner.trim() + "}}";
    });
    return s;
}

function buildUmlautStemPattern(str) {
    return escapeRegExp(str)
        .replace(/a/gi, "[aäAÄ]")
        .replace(/o/gi, "[oöOÖ]")
        .replace(/u/gi, "[uüUÜ]");
}

function autoGenerateCloze(term, sentence, article) {
    var rawSentence = normalizeClozeMarkup(sentence);
    if (!rawSentence.trim()) return "";
    if (/\{\{c\d+::[^}]+\}\}/.test(rawSentence)) return rawSentence;

    var cleanTerm = String(term || "").trim();
    if (!cleanTerm) return rawSentence;
    var bareTerm = cleanTerm
        .replace(/^(?:der|die|das|sich)\s+/i, "")
        .replace(/\s+(?:mit|an|auf|über|für|von|zu|in|um|nach|vor|aus|bei|gegen|durch|unter|zwischen|to|on|with|for|from|about|of|at)$/i, "")
        .trim();
    if (!bareTerm) return rawSentence;

    var wbStart = "(^|[^a-zA-ZäöüÄÖÜß])";
    var wbEnd = "(?=$|[^a-zA-ZäöüÄÖÜß])";

    // 1. Try matching optional article + word or exact/umlaut-inflected word
    var artPrefix = article && /^(?:der|die|das)$/i.test(article)
        ? "(?:(?:der|die|das|den|dem|des|ein|eine|einen|einem|eines)\\s+)?"
        : "";
    var exactRegex = new RegExp(wbStart + "(" + artPrefix + buildUmlautStemPattern(bareTerm) + "[a-zA-ZäöüÄÖÜß]{0,3})" + wbEnd, "i");
    if (exactRegex.test(rawSentence)) {
        return rawSentence.replace(exactRegex, "$1{{c1::$2}}");
    }

    // 2. Try stem prefix if bareTerm >= 5 chars (handles inflected verbs/nouns and umlauts)
    if (bareTerm.length >= 5) {
        var stem = bareTerm.replace(/(?:en|ern|eln|ing|ed|es)$/i, "");
        if (stem.length < 4) stem = bareTerm.slice(0, Math.max(4, bareTerm.length - 2));
        var stemRegex = new RegExp(wbStart + "(" + buildUmlautStemPattern(stem) + "[a-zA-ZäöüÄÖÜß]{0,5})" + wbEnd, "i");
        if (stemRegex.test(rawSentence)) {
            return rawSentence.replace(stemRegex, "$1{{c1::$2}}");
        }
    }

    // 3. Try German separable verb split across clause (e.g. widerspiegeln -> "spiegeln ... wider", auseinandersetzen -> "setzt ... auseinander")
    var sepMatch = bareTerm.match(/^(auseinander|zusammen|zurück|zurecht|zwischen|gegenüber|entgegen|entlang|entzwei|herunter|herüber|heraus|herein|herauf|heran|herab|herbei|hervor|herum|hinunter|hinüber|hinaus|hinein|hinauf|hinab|hinweg|hinzu|vorüber|vorbei|voraus|voran|vorher|weiter|wieder|wider|nieder|empor|statt|unter|über|nach|teil|fort|fest|frei|fern|gleich|heim|hoch|rein|raus|weg|mit|vor|auf|aus|ein|bei|los|her|hin|dar|ab|an|um|zu)([a-zäöüß]{3,}?)(?:en|eln|ern)$/i);
    if (sepMatch) {
        var prefix = sepMatch[1];
        var verbStem = sepMatch[2];
        var splitRegex = new RegExp(
            wbStart + "(" + buildUmlautStemPattern(verbStem) + "[a-zA-ZäöüÄÖÜß]{0,4})" + wbEnd
            + "([\\s\\S]+?\\s)(" + escapeRegExp(prefix) + ")" + wbEnd,
            "i"
        );
        if (splitRegex.test(rawSentence)) {
            return rawSentence.replace(splitRegex, "$1{{c1::$2}}$3{{c2::$4}}");
        }
    }

    return rawSentence;
}

function renderClozeFront(clozeText, fallbackTerm) {
    var s = normalizeClozeMarkup(clozeText);
    if (!s) return "";
    if (/\{\{c\d+::/.test(s)) {
        return s.replace(/\{\{c\d+::([^:}]+)(?:::([^}]+))?\}\}/g, function(_, answer, hint) {
            return hint ? "[ " + hint.trim() + " ]" : "[ ... ]";
        });
    }
    if (fallbackTerm) {
        var generated = autoGenerateCloze(fallbackTerm, s, "");
        if (/\{\{c\d+::/.test(generated)) {
            return renderClozeFront(generated, "");
        }
    }
    return s;
}

function renderClozeBack(clozeText) {
    var s = normalizeClozeMarkup(clozeText);
    return s.replace(/\{\{c\d+::([^:}]+)(?:::[^}]+)?\}\}/g, "$1");
}

function extractFirstClozeTarget(clozeText) {
    var s = normalizeClozeMarkup(clozeText);
    var m = s.match(/\{\{c\d+::([^:}]+)(?:::([^}]+))?\}\}/);
    return m ? { target: m[1].trim(), hint: (m[2] || "").trim() } : null;
}

function extractAllClozeTargets(clozeText) {
    var s = normalizeClozeMarkup(clozeText);
    var targets = [];
    var re = /\{\{c\d+::([^:}]+)(?:::([^}]+))?\}\}/g;
    var m;
    while ((m = re.exec(s)) !== null) {
        if (m[1] && m[1].trim()) targets.push(m[1].trim());
    }
    return targets;
}

function formatIntervalLabel(days) {
    var d = Number(days);
    if (!Number.isFinite(d) || d <= 0.05) return "<10m";
    if (d < 1) return Math.max(1, Math.round(d * 24)) + "h";
    var rounded = Math.round(d);
    if (rounded < 30) return rounded + "d";
    if (rounded < 365) return (Math.round((rounded / 30) * 10) / 10) + "mo";
    return (Math.round((rounded / 365) * 10) / 10) + "y";
}

function formatMorphology(cardOrMorphology) {
    if (!cardOrMorphology) return "";
    if (typeof cardOrMorphology === "string") return cardOrMorphology.trim();
    var list = Array.isArray(cardOrMorphology)
        ? cardOrMorphology
        : (Array.isArray(cardOrMorphology.morphology) ? cardOrMorphology.morphology : []);
    if (!list || list.length === 0) {
        return typeof cardOrMorphology.morphologyText === "string" ? cardOrMorphology.morphologyText.trim() : "";
    }
    var parts = [];
    for (var i = 0; i < list.length; i++) {
        var item = list[i];
        if (!item) continue;
        if (typeof item === "string") {
            if (item.trim()) parts.push(item.trim());
            continue;
        }
        var p = String(item.part || "").trim();
        var m = String(item.meaning || "").trim();
        if (!p) continue;
        parts.push(m ? (p + " (" + m + ")") : p);
    }
    return parts.join(" + ");
}

function containsVietnameseDiacritics(str) {
    return /[àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ]/i.test(String(str || ""));
}

function cleanVietnameseMeaning(raw) {
    var s = String(raw || "").trim();
    if (!s || s.indexOf(" — ") < 0) return s;
    var parts = s.split(" — ");
    var left = String(parts[0] || "").trim();
    var right = parts.slice(1).join(" — ").trim();
    if (!left) return right;
    if (!right) return left;
    if (right.toLowerCase().indexOf(left.toLowerCase()) >= 0) {
        return right;
    }
    return left + ", " + right;
}

function normalizeCard(raw, indexFallback, nowMs, rawOptions, lexiconAnalyzer) {
    // Allow calling normalizeCard(raw, nowMs[, rawOptions]) with 2 or 3 arguments
    if (typeof indexFallback === "number" && indexFallback > 1000000000 && (nowMs === undefined || (nowMs && typeof nowMs === "object"))) {
        if (nowMs && typeof nowMs === "object" && rawOptions === undefined) {
            rawOptions = nowMs;
        }
        nowMs = indexFallback;
        indexFallback = 1;
    }
    var opts = normalizeOptions(rawOptions);
    var now = Number.isFinite(Number(nowMs)) ? Number(nowMs) : Date.now();
    var src = (raw && typeof raw === "object") ? raw : {};

    var category = String(src.category || "").toLowerCase();
    if (category === "vocab") category = "vocabulary";
    if (["vocabulary", "knowledge", "cloze"].indexOf(category) < 0) {
        category = (src.clozeText && !src.term && !src.front) ? "cloze" : "vocabulary";
    }

    var rawTerm = String(src.term || src.front || src.word || "").trim();
    var rawMeaning = String(src.meaning || src.back || src.answer || "").trim();
    var rawExample = String(src.example || src.context || "").trim();
    var rawCloze = String(src.clozeText || "").trim();

    if (!rawTerm && rawCloze) {
        var extracted = extractFirstClozeTarget(rawCloze);
        if (extracted && extracted.target) {
            rawTerm = extracted.target;
        }
    }

    var analyzer = typeof lexiconAnalyzer === "function"
        ? lexiconAnalyzer
        : (typeof analyzeTerm === "function" ? analyzeTerm : null);
    var lex = null;
    if (category === "vocabulary" && typeof analyzer === "function" && rawTerm) {
        lex = analyzer(rawTerm, src.language || "");
    }

    var language = String((lex && lex.language) || src.language || (category === "vocabulary" ? opts.defaultLanguage : "general")).toLowerCase();
    if (["en", "de", "general", "other"].indexOf(language) < 0) language = "en";

    var article = String(src.article || src.gender || (lex && lex.article) || "").trim();
    var plural = String(src.plural !== undefined && src.plural !== "" ? src.plural : ((lex && lex.plural) || "")).trim();
    var pos = String(src.pos !== undefined && src.pos !== "" ? src.pos : ((lex && lex.pos) || "")).trim();
    var phonetic = String(src.phonetic || src.phonetics || (lex && lex.phonetic) || "").trim();

    // Clean bogus noun article on German non-nouns (e.g. adjectives like "nachhaltig" previously inferred as "der")
    if (language === "de"
            && pos
            && ["adj", "adjective", "adv", "adverb", "verb", "v"].indexOf(pos.toLowerCase()) >= 0
            && ["der", "die", "das"].indexOf(article.toLowerCase()) >= 0
            && !(lex && lex.article)) {
        article = "";
    }

    var rawLevel = String(src.level || src.cefrLevel || (opts.autoLookupLevel !== false && lex && lex.level) || "").toUpperCase().trim();
    if (["A1", "A2", "B1", "B2", "C1", "C2"].indexOf(rawLevel) < 0) {
        rawLevel = (category === "vocabulary" && opts.autoLookupLevel !== false) ? "B1" : "";
    }
    var levelSource = String(src.levelSource || src.cefrSource || (opts.autoLookupLevel !== false && lex && lex.levelSource) || (rawLevel ? "Manual / Heuristic" : "")).trim();

    var term = (lex && lex.word && !src.keepRawTerm) ? lex.word : rawTerm;
    var rawFrontFallback = String(src.front || term).trim();
    if (language === "de" && !article && ["adj", "adjective", "adv", "adverb", "verb", "v"].indexOf(pos.toLowerCase()) >= 0) {
        rawFrontFallback = rawFrontFallback.replace(/^(der|die|das)\s+/i, "").trim() || term;
    }
    var displayFront = (language === "de" && article && ["der", "die", "das", "sich"].indexOf(article.toLowerCase()) >= 0 && !new RegExp("^" + escapeRegExp(article) + "\\s+", "i").test(term))
        ? (article + " " + term)
        : rawFrontFallback;
    var explicitDefinitionEn = String(src.definitionEn || "").trim();
    var explicitMeaningVi = String(src.meaningVi || "").trim();
    var lexMeaningEn = String((lex && (lex.definitionEn || lex.meaning)) || "").trim();
    var lexMeaningVi = String((lex && lex.meaningVi) || "").trim();

    if (category === "vocabulary") {
        if (containsVietnameseDiacritics(rawMeaning)) {
            if (!explicitMeaningVi) explicitMeaningVi = rawMeaning;
            if (explicitDefinitionEn && !containsVietnameseDiacritics(explicitDefinitionEn)) {
                rawMeaning = explicitDefinitionEn;
            } else if (lexMeaningEn && !containsVietnameseDiacritics(lexMeaningEn)) {
                rawMeaning = lexMeaningEn;
            }
        } else {
            if (!rawMeaning && lexMeaningEn) rawMeaning = lexMeaningEn;
            if (!explicitDefinitionEn && rawMeaning) explicitDefinitionEn = rawMeaning;
        }
        if (!explicitMeaningVi && lexMeaningVi) explicitMeaningVi = lexMeaningVi;
        if (!explicitDefinitionEn && lexMeaningEn && !containsVietnameseDiacritics(lexMeaningEn)) {
            explicitDefinitionEn = lexMeaningEn;
        }
        if (!rawMeaning && explicitDefinitionEn) rawMeaning = explicitDefinitionEn;
        if (!rawMeaning && explicitMeaningVi) rawMeaning = explicitMeaningVi;
    } else {
        if (!rawMeaning && lexMeaningEn) rawMeaning = lexMeaningEn;
    }
    var definitionEn = explicitDefinitionEn || rawMeaning;
    var meaningVi = cleanVietnameseMeaning(explicitMeaningVi);
    if (!rawExample && lex && lex.example) rawExample = lex.example;

    var clozeText = rawCloze;
    if (!clozeText && opts.autoCloze && rawExample && term) {
        clozeText = autoGenerateCloze(term, rawExample, article);
    } else if (clozeText) {
        clozeText = normalizeClozeMarkup(clozeText);
    }

    var reps = Math.max(0, Math.round(Number(src.reps) || 0));
    var lapses = Math.max(0, Math.round(Number(src.lapses) || 0));
    var interval = Math.max(0, Number(src.interval) || 0);
    var ease = Math.round(clampNumber(src.ease, 130, 500, opts.baseEase));
    var dueAt = now;
    if (typeof src.dueDate === "string" && /^\d{4}-\d{2}-\d{2}$/.test(src.dueDate.trim()) && (!Number.isFinite(Number(src.dueAt)) || civilDayKey(Number(src.dueAt)) !== src.dueDate.trim())) {
        var parsedDue = Date.parse(src.dueDate.trim() + "T09:00:00Z");
        if (Number.isFinite(parsedDue)) dueAt = parsedDue;
    } else if (Number.isFinite(Number(src.dueAt))) {
        dueAt = Number(src.dueAt);
    }
    var dueDate = (typeof src.dueDate === "string" && /^\d{4}-\d{2}-\d{2}$/.test(src.dueDate.trim()))
        ? src.dueDate.trim()
        : civilDayKey(dueAt);
    var createdAt = Number.isFinite(Number(src.createdAt)) ? Number(src.createdAt) : now;
    var lastReviewedAt = Number.isFinite(Number(src.lastReviewedAt)) ? Number(src.lastReviewedAt) : 0;

    var state = String(src.state || "").toLowerCase();
    if (["new", "learning", "review", "relearning", "young", "mature"].indexOf(state) < 0) {
        state = reps === 0 ? "new" : (interval < 1 ? "learning" : (interval >= 21 ? "mature" : "young"));
    }

    var synonyms = [];
    if (Array.isArray(src.synonyms)) {
        synonyms = src.synonyms.map(function(s) { return String(s || "").trim(); }).filter(Boolean);
    } else if (typeof src.synonyms === "string" && src.synonyms.trim()) {
        synonyms = src.synonyms.split(/[,;]/).map(function(s) { return s.trim(); }).filter(Boolean);
    }
    if (synonyms.length === 0 && lex && Array.isArray(lex.synonyms)) {
        synonyms = lex.synonyms.slice();
    }

    var antonyms = [];
    if (Array.isArray(src.antonyms)) {
        antonyms = src.antonyms.map(function(s) { return String(s || "").trim(); }).filter(Boolean);
    } else if (typeof src.antonyms === "string" && src.antonyms.trim()) {
        antonyms = src.antonyms.split(/[,;]/).map(function(s) { return s.trim(); }).filter(Boolean);
    }
    if (antonyms.length === 0 && lex && Array.isArray(lex.antonyms)) {
        antonyms = lex.antonyms.slice();
    }

    var collocations = [];
    if (Array.isArray(src.collocations)) {
        collocations = src.collocations.map(function(c) { return String(c || "").trim(); }).filter(Boolean);
    } else if (typeof src.collocations === "string" && src.collocations.trim()) {
        collocations = src.collocations.split(/[\n;]/).map(function(c) { return c.trim(); }).filter(Boolean);
    }
    if (collocations.length === 0 && lex && Array.isArray(lex.collocations)) {
        collocations = lex.collocations.slice();
    }

    var morphology = [];
    if (Array.isArray(src.morphology) && src.morphology.length > 0) {
        morphology = src.morphology.map(function(m) {
            if (!m || typeof m !== "object") return null;
            return {
                part: String(m.part || "").trim(),
                kind: String(m.kind || "root").trim(),
                meaning: String(m.meaning || "").trim()
            };
        }).filter(function(m) { return m && m.part; });
    }
    if (morphology.length === 0 && lex && Array.isArray(lex.morphology) && lex.morphology.length > 0) {
        morphology = lex.morphology.slice();
    }
    if (morphology.length === 0 && category === "vocabulary" && term && typeof inferMorphology === "function") {
        morphology = inferMorphology(term, language);
    }
    var morphologyText = String(src.morphologyText || formatMorphology(morphology) || (lex && lex.morphologyText) || "").trim();

    var tags = [];
    if (Array.isArray(src.tags)) {
        tags = src.tags.map(function(t) { return String(t || "").trim(); }).filter(Boolean);
    }

    var isLeech = Boolean(src.isLeech) || lapses >= opts.leechThreshold;

    return {
        id: String(src.id || ("sr-card-" + (indexFallback || 1))),
        category: category,
        deck: (function() {
            var d = String(src.deck || "").trim();
            if (category === "vocabulary" && (!d || /^(?:Default|Unit\s*\d+)$/i.test(d))) {
                return language === "de" ? "German Vocabulary" : "English Vocabulary";
            }
            return d || (category === "vocabulary" ? (language === "de" ? "German Vocabulary" : "English Vocabulary") : "Knowledge & Concepts");
        })(),
        language: language,
        term: term,
        headword: term,
        front: displayFront,
        article: article,
        gender: article,
        plural: plural,
        pos: pos,
        phonetic: phonetic,
        phonetics: phonetic,
        level: rawLevel,
        cefrLevel: rawLevel,
        levelSource: levelSource,
        cefrSource: levelSource,
        meaning: rawMeaning,
        back: rawMeaning,
        definitionEn: definitionEn,
        meaningVi: meaningVi,
        example: rawExample,
        clozeText: clozeText,
        notes: String(src.notes || "").trim(),
        collocations: collocations,
        morphology: morphology,
        morphologyText: morphologyText,
        synonyms: synonyms,
        antonyms: antonyms,
        tags: tags,
        bidirectional: src.bidirectional !== undefined ? Boolean(src.bidirectional) : (category === "vocabulary"),
        state: state,
        interval: interval,
        ease: ease,
        reps: reps,
        lapses: lapses,
        isLeech: isLeech,
        dueAt: dueAt,
        dueDate: dueDate,
        createdAt: createdAt,
        lastReviewedAt: lastReviewedAt
    };
}

function chooseBalancedInterval(rawDays, nowMs, dueCountsByDay, maxInterval) {
    var base = Math.max(1, Math.min(maxInterval, Math.round(rawDays)));
    if (!dueCountsByDay || typeof dueCountsByDay !== "object" || base < 4) {
        return base;
    }
    var span = base <= 14 ? 1 : 2;
    var bestOffset = 0;
    var bestLoad = Infinity;
    for (var offset = -span; offset <= span; offset++) {
        var candidate = base + offset;
        if (candidate < 2 || candidate > maxInterval) continue;
        var key = civilDayKey(nowMs + candidate * DAY_MS);
        var load = Number(dueCountsByDay[key]) || 0;
        // Tie-break toward the exact base interval (offset === 0)
        if (load < bestLoad || (load === bestLoad && Math.abs(offset) < Math.abs(bestOffset))) {
            bestLoad = load;
            bestOffset = offset;
        }
    }
    return base + bestOffset;
}

function computePositiveRatingDays(c, opts, now, dueCountsByDay) {
    var ease = c.ease;
    var reps = c.reps;
    var oldInterval = Math.max(0, Number(c.interval) || 0);
    var boost = opts.boostMultiplier;
    var maxInt = opts.maximumInterval;

    if (reps === 0 && oldInterval < 1) {
        var initHard = Math.min(maxInt, Math.max(1, Math.round(1 * boost)));
        var initGood = Math.min(maxInt, Math.max(initHard + 1, Math.round(2 * boost)));
        var initEasy = Math.min(maxInt, Math.max(initGood + 1, Math.round(3 * boost)));
        return { hard: initHard, good: initGood, easy: initEasy };
    }

    var baseInt = Math.max(1, oldInterval);
    var hardRaw = Math.max(baseInt + 1, baseInt * opts.hardMultiplier * boost);
    var hardDays = Math.min(maxInt, Math.round(hardRaw));

    var goodEaseFactor = (reps <= 1 && baseInt <= 3)
        ? Math.min(Math.max(1.3, ease / 100), 2.0)
        : Math.max(1.3, ease / 100);
    var goodRaw = Math.max(hardDays + 1, baseInt * goodEaseFactor * boost);
    var goodDays = (opts.loadBalance && reps >= 2)
        ? Math.max(hardDays + 1, chooseBalancedInterval(goodRaw, now, dueCountsByDay, maxInt))
        : Math.min(maxInt, Math.max(hardDays + 1, Math.round(goodRaw)));

    var easyEaseFactor = (reps <= 1 && baseInt <= 3)
        ? Math.min(Math.max(1.5, Math.min(500, ease + 15) / 100), 2.2)
        : Math.max(1.3, Math.min(500, ease + 15) / 100);
    var easyRaw = Math.max(goodDays + 1, baseInt * easyEaseFactor * opts.easyBonus * boost);
    var easyDays = (opts.loadBalance && reps >= 2)
        ? Math.max(goodDays + 1, chooseBalancedInterval(easyRaw, now, dueCountsByDay, maxInt))
        : Math.min(maxInt, Math.max(goodDays + 1, Math.round(easyRaw)));

    return { hard: hardDays, good: goodDays, easy: easyDays };
}

function computeNextSchedule(card, rating, nowMs, rawOptions, dueCountsByDay) {
    // Support both (card, rating, nowMs, rawOptions, dueCountsByDay)
    // and (card, rating, rawOptions, dueCountsByDay, nowMs)
    if (nowMs && typeof nowMs === "object") {
        var tmpOpts = nowMs;
        var tmpCounts = rawOptions;
        var tmpNow = dueCountsByDay;
        rawOptions = tmpOpts;
        dueCountsByDay = tmpCounts;
        nowMs = tmpNow;
    }
    var opts = normalizeOptions(rawOptions);
    var now = Number.isFinite(Number(nowMs)) ? Number(nowMs) : Date.now();
    var c = normalizeCard(card, 1, now, opts, null);
    var r = String(rating || "good").toLowerCase();

    var ease = c.ease;
    var reps = c.reps;
    var lapses = c.lapses;
    var oldInterval = Math.max(0, Number(c.interval) || 0);
    var nextInterval = 1;
    var nextDueMs = now + DAY_MS;
    var nextState = "young";
    var positiveDays = computePositiveRatingDays(c, opts, now, dueCountsByDay);

    if (r === "again" || r === "0" || r === "reset") {
        lapses += 1;
        ease = Math.max(130, ease - 20);
        if (reps >= 2 && oldInterval > 2 && opts.lapseMultiplier > 0) {
            nextInterval = Math.max(1, Math.round(oldInterval * opts.lapseMultiplier));
            nextDueMs = now + nextInterval * DAY_MS;
            nextState = "relearning";
        } else {
            nextInterval = 0.01;
            nextDueMs = now + 10 * MINUTE_MS;
            nextState = reps === 0 ? "learning" : "relearning";
        }
        reps = 0;
    } else if (r === "hard" || r === "1") {
        ease = Math.max(130, ease - 15);
        nextInterval = positiveDays.hard;
        nextDueMs = now + nextInterval * DAY_MS;
        reps += 1;
        nextState = nextInterval >= 21 ? "mature" : "young";
    } else if (r === "easy" || r === "3") {
        ease = Math.min(500, ease + 15);
        nextInterval = positiveDays.easy;
        nextDueMs = now + nextInterval * DAY_MS;
        reps += 1;
        nextState = nextInterval >= 21 ? "mature" : "young";
    } else {
        // "good" / "2" (default)
        nextInterval = positiveDays.good;
        nextDueMs = now + nextInterval * DAY_MS;
        reps += 1;
        nextState = nextInterval >= 21 ? "mature" : "young";
    }

    var isLeech = lapses >= opts.leechThreshold;
    var updated = Object.assign({}, c, {
        ease: ease,
        reps: reps,
        lapses: lapses,
        isLeech: isLeech,
        interval: nextInterval,
        dueAt: nextDueMs,
        dueDate: civilDayKey(nextDueMs),
        lastReviewedAt: now,
        state: nextState
    });

    return Object.assign({}, updated, {
        card: updated,
        intervalDays: nextInterval,
        nextDueMs: nextDueMs,
        label: formatIntervalLabel(nextInterval),
        state: nextState,
        isLeech: isLeech
    });
}

function scheduleReview(card, rating, nowMs, rawOptions, dueCountsByDay) {
    return computeNextSchedule(card, rating, nowMs, rawOptions, dueCountsByDay);
}

function previewIntervals(card, nowMs, rawOptions) {
    if (!card || typeof card !== "object") {
        return { again: "<10m", hard: "1d", good: "2d", easy: "3d" };
    }
    return {
        again: computeNextSchedule(card, "again", nowMs, rawOptions, null).label,
        hard: computeNextSchedule(card, "hard", nowMs, rawOptions, null).label,
        good: computeNextSchedule(card, "good", nowMs, rawOptions, null).label,
        easy: computeNextSchedule(card, "easy", nowMs, rawOptions, null).label
    };
}

function parseObsidianSrComment(text) {
    // Matches <!--SR:!2026-11-05,4,270-->
    var m = String(text || "").match(/<!--\s*SR:!(\d{4}-\d{2}-\d{2}),(\d+),(\d+)\s*-->/);
    var cleaned = String(text || "").replace(/<!--\s*SR:![\s\S]*?-->/g, "").trim();
    if (!m) {
        return { cleaned: cleaned, schedule: null };
    }
    var dueMs = Date.parse(m[1] + "T09:00:00Z");
    var interval = Math.max(1, parseInt(m[2], 10) || 1);
    var ease = clampNumber(parseInt(m[3], 10), 130, 500, 250);
    return {
        cleaned: cleaned,
        schedule: {
            dueAt: Number.isFinite(dueMs) ? dueMs : Date.now(),
            dueDate: m[1],
            interval: interval,
            ease: ease,
            reps: 1,
            state: "review"
        }
    };
}

function parseObsidianUnitCard(frontLines, backLines, deck, prefLang, schedule, opts, lexiconAnalyzer) {
    var headLine = String(backLines[0] || "").trim();
    var headMatch = headLine.match(/^\*\*(.+?)\*\*\s*(?:\(([A-C][12])\))?\s*(?:\(([^)]+)\))?/i);
    if (!headMatch) return null;

    var word = headMatch[1].trim();
    var cefr = (headMatch[2] || "").toUpperCase();
    var ipa = (headMatch[3] || "").trim();

    var hintMatch = frontLines.match(/\*\*____\*\*\s*(?:\(([^)]+)\))?/);
    var pos = "";
    var shortMeaning = "";
    if (hintMatch && hintMatch[1]) {
        var inside = hintMatch[1].trim();
        var sepParts = inside.split(/\s*(?:—|–|-)\s*/);
        if (sepParts.length >= 2) {
            var rawPos = sepParts[0].trim().toLowerCase();
            if (rawPos === "adjective") pos = "adj";
            else if (rawPos === "adverb") pos = "adv";
            else if (rawPos === "noun" || rawPos === "verb") pos = rawPos;
            else pos = rawPos;
            shortMeaning = sepParts.slice(1).join(" — ").trim();
        } else {
            shortMeaning = inside;
        }
    }

    var cleanExample = frontLines.replace(/\*\*____\*\*\s*(?:\([^)]+\))?/g, word).replace(/\s+/g, " ").trim();
    var clozeHint = (pos && shortMeaning) ? (pos + " — " + shortMeaning) : (shortMeaning || pos);
    var clozeReplacement = clozeHint ? ("{{c1::" + word + "::" + clozeHint + "}}") : ("{{c1::" + word + "}}");
    var clozeText = frontLines.replace(/\*\*____\*\*\s*(?:\([^)]+\))?/g, clozeReplacement).replace(/\s+/g, " ").trim();

    var meaningDetail = "";
    var collocations = [];
    for (var i = 1; i < backLines.length; i++) {
        var bl = String(backLines[i] || "").trim();
        if (!bl) continue;
        if (/^[-*•]\s*\*\*(?:Nghĩa|Meaning|Definition)\s*:\*\*/i.test(bl)) {
            meaningDetail = bl.replace(/^[-*•]\s*\*\*(?:Nghĩa|Meaning|Definition)\s*:\*\*\s*/i, "").trim();
        } else if (/^[-*•]\s*\*\*Collocations\s*:\*\*/i.test(bl)) {
            continue;
        } else if (/^[-*•]\s+/.test(bl) && !/^[-*•]\s*\*\*/.test(bl)) {
            collocations.push(bl.replace(/^[-*•]\s+/, "").trim());
        }
    }

    var fullMeaning = cleanVietnameseMeaning((shortMeaning && meaningDetail && shortMeaning.toLowerCase() !== meaningDetail.toLowerCase())
        ? (shortMeaning + " — " + meaningDetail)
        : (meaningDetail || shortMeaning));

    var resolvedDeck = (deck && !/^(?:Default|Unit\s*\d+)$/i.test(deck))
        ? deck
        : ((prefLang || "en") === "de" ? "German Vocabulary" : "English Vocabulary");
    var now = Date.now();
    var payload = {
        category: "vocabulary",
        deck: resolvedDeck,
        language: prefLang || "en",
        term: word,
        pos: pos,
        phonetic: ipa,
        level: cefr,
        levelSource: cefr ? "4000 Essential English Words Vol. 5" : "",
        meaning: "",
        meaningVi: fullMeaning,
        example: cleanExample,
        clozeText: clozeText,
        collocations: collocations,
        bidirectional: true,
        state: "new",
        interval: 0,
        ease: opts.baseEase,
        reps: 0,
        lapses: 0,
        dueAt: now,
        dueDate: civilDayKey(now),
        lastReviewedAt: 0
    };
    return normalizeCard(payload, 1, now, opts, lexiconAnalyzer);
}

function parseSingleQuickEntry(rawBlock, defaults, lexiconAnalyzer) {
    var srParsed = parseObsidianSrComment(rawBlock);
    var text = srParsed.cleaned.trim();
    if (!text || /^#+$/.test(text)) return null;

    var opts = normalizeOptions(defaults);
    var deck = String((defaults && defaults.deck) || "").trim();
    var prefLang = String((defaults && defaults.language) || opts.defaultLanguage);
    var category = String((defaults && defaults.category) || "auto").toLowerCase();

    // Check multi-line ? or ?? separator (Obsidian SR multi-line card)
    var lines = text.split(/\r?\n/).map(function(l) { return l.trim(); }).filter(Boolean);
    var qIndex = lines.indexOf("?");
    var qqIndex = lines.indexOf("??");
    if (qIndex > 0 || qqIndex > 0) {
        var sepIdx = qqIndex > 0 ? qqIndex : qIndex;
        var frontLines = lines.slice(0, sepIdx).join(" ");
        var backLines = lines.slice(sepIdx + 1);
        if (/\*\*____\*\*/.test(frontLines) && backLines.length > 0 && /^\*\*.+?\*\*/.test(backLines[0])) {
            var unitCard = parseObsidianUnitCard(frontLines, backLines, deck, prefLang, srParsed.schedule, opts, lexiconAnalyzer);
            if (unitCard) return unitCard;
        }
        var meaningLine = backLines[0] || "";
        var exampleLine = backLines.slice(1).join(" ");
        return buildParsedEntry(frontLines, meaningLine, exampleLine, qqIndex > 0, category, deck, prefLang, srParsed.schedule, opts, lexiconAnalyzer);
    }

    // Check if the block is a pure cloze line (contains ==...== or {{c1::...}} without separator)
    var hasClozeMarkup = /==[^=\n]+==|\{\{c\d+::[^}]+\}\}/.test(text);
    var hasInlineSep = /\s(?:::|::|—|–|-|\||=)\s|\t/.test(text);
    if (hasClozeMarkup && !hasInlineSep) {
        var normCloze = normalizeClozeMarkup(text);
        var targetObj = extractFirstClozeTarget(normCloze);
        var targetWord = targetObj ? targetObj.target : "";
        var cardCat = category === "vocab" ? "vocab" : "cloze";
        return normalizeCard({
            category: cardCat,
            deck: deck || "Cloze & Context",
            language: prefLang,
            term: targetWord || normCloze.slice(0, 40),
            meaning: targetObj && targetObj.hint ? targetObj.hint : targetWord,
            example: renderClozeBack(normCloze),
            clozeText: normCloze,
            bidirectional: false,
            dueAt: srParsed.schedule ? srParsed.schedule.dueAt : undefined,
            interval: srParsed.schedule ? srParsed.schedule.interval : 0,
            ease: srParsed.schedule ? srParsed.schedule.ease : opts.baseEase,
            reps: srParsed.schedule ? srParsed.schedule.reps : 0,
            state: srParsed.schedule ? srParsed.schedule.state : "new"
        }, 1, Date.now(), opts, lexiconAnalyzer);
    }

    // Check single-line or multi-line natural entry
    var singleLine = lines[0] || "";
    var extraLines = lines.slice(1);
    var bidirectional = false;
    var leftPart = "";
    var rightPart = "";

    if (singleLine.indexOf(":::") >= 0) {
        var parts3 = singleLine.split(":::");
        leftPart = parts3[0].trim();
        rightPart = parts3.slice(1).join(":::").trim();
        bidirectional = true;
    } else if (singleLine.indexOf("::") >= 0) {
        var parts2 = singleLine.split("::");
        leftPart = parts2[0].trim();
        rightPart = parts2.slice(1).join("::").trim();
    } else if (singleLine.indexOf("\t") >= 0) {
        var tabParts = singleLine.split("\t");
        leftPart = tabParts[0].trim();
        rightPart = tabParts.slice(1).join(" ").trim();
    } else {
        var dashMatch = singleLine.match(/^(.+?)\s+(?:—|–|-|:|=)\s+(.+)$/);
        if (dashMatch) {
            leftPart = dashMatch[1].trim();
            rightPart = dashMatch[2].trim();
        } else if (extraLines.length > 0) {
            leftPart = singleLine;
            rightPart = extraLines[0];
            extraLines = extraLines.slice(1);
        } else {
            // Bare word or phrase! Automatically enrich from Lexicon!
            leftPart = singleLine;
            rightPart = "";
        }
    }

    // Extract inline example from rightPart if separated by "//" or "| Ex:" or "|"
    var inlineExample = extraLines.join(" ").trim();
    if (rightPart) {
        var exSplit = rightPart.split(/\s*(?:\/\/|\|\s*(?:ex|e\.g\.|bsp)\s*:?|\|)\s*/i);
        if (exSplit.length > 1) {
            rightPart = exSplit[0].trim();
            if (!inlineExample) inlineExample = exSplit.slice(1).join(" ").trim();
        }
    }

    return buildParsedEntry(leftPart, rightPart, inlineExample, bidirectional, category, deck, prefLang, srParsed.schedule, opts, lexiconAnalyzer);
}

function buildParsedEntry(rawLeft, rawRight, rawExample, isBidir, category, deck, prefLang, schedule, opts, lexiconAnalyzer) {
    var left = String(rawLeft || "").replace(/^[-*•\d.)\s]+/, "").trim();
    if (!left) return null;

    var explicitLevel = "";
    var explicitPos = "";
    var explicitPhonetic = "";

    // Extract optional [A1..C2] badge from left or right
    var levelMatch = left.match(/\[(A1|A2|B1|B2|C1|C2)\]/i) || String(rawRight || "").match(/\[(A1|A2|B1|B2|C1|C2)\]/i);
    if (levelMatch) {
        explicitLevel = levelMatch[1].toUpperCase();
        left = left.replace(/\s*\[(A1|A2|B1|B2|C1|C2)\]\s*/gi, " ").trim();
        rawRight = String(rawRight || "").replace(/\s*\[(A1|A2|B1|B2|C1|B2)\]\s*/gi, " ").trim();
    }

    // Extract optional /phonetic/ from left
    var phonMatch = left.match(/\/([^/]{1,40})\//);
    if (phonMatch) {
        explicitPhonetic = "/" + phonMatch[1].trim() + "/";
        left = left.replace(phonMatch[0], " ").trim();
    }

    // Extract optional (noun/verb/adj/adv/phrase/n/v/adj.) from left
    var posMatch = left.match(/\((noun|verb|adj\.?|adv\.?|phrase|idiom|prep\.?|conj\.?|n\.|v\.)\)/i);
    if (posMatch) {
        explicitPos = posMatch[1].toLowerCase().replace(/\.$/, "");
        if (explicitPos === "n") explicitPos = "noun";
        if (explicitPos === "v") explicitPos = "verb";
        left = left.replace(posMatch[0], " ").trim();
    }

    left = left.replace(/\s+/g, " ").trim();

    var wordCount = left.split(/\s+/).length;
    var effectiveCategory = category;
    if (effectiveCategory === "auto" || !effectiveCategory) {
        effectiveCategory = (wordCount <= 4 && !/\?$/.test(left)) ? "vocabulary" : "knowledge";
    } else if (effectiveCategory === "vocab" || effectiveCategory === "vocabulary") {
        effectiveCategory = (wordCount <= 4 && !/\?$/.test(left)) ? "vocabulary" : "knowledge";
    }

    var basePayload = {
        category: effectiveCategory,
        deck: deck || "",
        language: prefLang,
        term: left,
        meaning: String(rawRight || "").trim(),
        example: String(rawExample || "").trim(),
        level: explicitLevel,
        pos: explicitPos,
        phonetic: explicitPhonetic,
        bidirectional: isBidir || (effectiveCategory === "vocabulary")
    };
    if (schedule) {
        basePayload.dueAt = schedule.dueAt;
        basePayload.dueDate = schedule.dueDate;
        basePayload.interval = schedule.interval;
        basePayload.ease = schedule.ease;
        basePayload.reps = schedule.reps;
        basePayload.state = schedule.state;
    }

    var primaryCard = normalizeCard(basePayload, 1, Date.now(), opts, lexiconAnalyzer);
    if (isBidir && rawRight) {
        var reversePayload = Object.assign({}, basePayload, {
            term: String(rawRight || "").trim(),
            front: String(rawRight || "").trim(),
            meaning: left,
            back: left,
            keepRawTerm: true
        });
        var reverseCard = normalizeCard(reversePayload, 2, Date.now(), opts, null);
        primaryCard._reverseCompanion = reverseCard;
    }
    return primaryCard;
}

function todayKey(nowMs) {
    return civilDayKey(nowMs);
}

function addDaysKey(dayKeyStr, days, fallbackMs) {
    var baseMs = (typeof dayKeyStr === "string" && /^\d{4}-\d{2}-\d{2}$/.test(dayKeyStr))
        ? Date.parse(dayKeyStr + "T12:00:00Z")
        : (Number.isFinite(Number(fallbackMs)) ? Number(fallbackMs) : Date.now());
    return civilDayKey(baseMs + (Number(days) || 0) * DAY_MS);
}

function parseQuickInput(rawText, defaultsOrDeck, langOrAnalyzer, categoryOpt, analyzerOpt) {
    var text = String(rawText || "").trim();
    if (!text) return [];

    var defaults = {};
    var lexiconAnalyzer = null;
    if (typeof defaultsOrDeck === "string") {
        defaults = {
            deck: defaultsOrDeck,
            language: typeof langOrAnalyzer === "string" ? langOrAnalyzer : "en",
            category: typeof categoryOpt === "string" ? categoryOpt : "auto"
        };
        lexiconAnalyzer = typeof analyzerOpt === "function" ? analyzerOpt : (typeof analyzeTerm === "function" ? analyzeTerm : null);
    } else {
        defaults = (defaultsOrDeck && typeof defaultsOrDeck === "object") ? Object.assign({}, defaultsOrDeck) : {};
        lexiconAnalyzer = typeof langOrAnalyzer === "function" ? langOrAnalyzer : (typeof analyzeTerm === "function" ? analyzeTerm : null);
    }

    var results = [];
    var rawLines = text.split(/\r?\n/);
    var inYaml = false;
    var inTemplateGuide = false;
    var skipExerciseSection = false;
    var activeDeck = String(defaults.deck || "").trim();

    for (var i = 0; i < rawLines.length; i++) {
        var rawLine = rawLines[i];
        var line = rawLine.trim();

        if (line === "---") {
            inYaml = !inYaml;
            if (inYaml) {
                skipExerciseSection = false;
                inTemplateGuide = false;
            }
            continue;
        }
        if (inYaml) {
            continue;
        }

        var unitHeaderMatch = line.match(/\[\[Unit[_\s]?(\d+)\]\]/i);
        if (unitHeaderMatch && (/Danh sách/i.test(line) || /^📝/.test(line) || /^#/.test(line))) {
            if (!activeDeck || /^Unit\s*\d+$/i.test(activeDeck)) {
                activeDeck = "English Vocabulary";
            }
            skipExerciseSection = false;
            inTemplateGuide = false;
            continue;
        }

        if (/^ℹ️\s*Hướng dẫn/i.test(line)) {
            inTemplateGuide = true;
            continue;
        }
        if (/^📥\s*Khu vực nhập/i.test(line)) {
            inTemplateGuide = false;
            continue;
        }
        if (inTemplateGuide) {
            continue;
        }

        var cleanHeading = line.replace(/^[#>*\s]+|\*+$/g, "").trim();
        if (/^(?:Exercise\s+\d+|Reading Comprehension|Part\s+[AB]\b)/i.test(cleanHeading)) {
            skipExerciseSection = true;
            continue;
        }
        if (skipExerciseSection) {
            continue;
        }

        if (!line || /^#+\s/.test(line) || /^\/\//.test(line) || /^[📝ℹ️📥]/.test(line) || /^Ví dụ cho câu mới\s*:/i.test(line)) {
            continue;
        }

        // Gather multi-line block if followed by standalone ? or ??
        var probeIdx = i + 1;
        var prefixLines = [line];
        while (probeIdx < rawLines.length
                && rawLines[probeIdx].trim().length > 0
                && rawLines[probeIdx].trim() !== "?"
                && rawLines[probeIdx].trim() !== "??"
                && !/\s(?:::|::|—|–|-|\||=)\s|\t/.test(line)) {
            // Check if a nearby line is ? or ??
            if (probeIdx + 1 < rawLines.length && (rawLines[probeIdx + 1].trim() === "?" || rawLines[probeIdx + 1].trim() === "??")) {
                prefixLines.push(rawLines[probeIdx].trim());
                probeIdx++;
                break;
            }
            break;
        }

        var nextLine = (probeIdx < rawLines.length) ? rawLines[probeIdx].trim() : "";
        var entryDefaults = activeDeck ? Object.assign({}, defaults, { deck: activeDeck }) : defaults;

        if (nextLine === "?" || nextLine === "??") {
            var blockLines = prefixLines.concat([nextLine]);
            i = probeIdx + 1;
            while (i < rawLines.length && rawLines[i].trim().length > 0) {
                blockLines.push(rawLines[i].trim());
                i++;
            }
            var mlCard = parseSingleQuickEntry(blockLines.join("\n"), entryDefaults, lexiconAnalyzer);
            if (mlCard && (mlCard.term || mlCard.clozeText)) {
                var mlComp = mlCard._reverseCompanion;
                delete mlCard._reverseCompanion;
                mlCard.id = "sr-import-" + (results.length + 1);
                results.push(mlCard);
                if (mlComp) {
                    mlComp.id = "sr-import-" + (results.length + 1);
                    results.push(mlComp);
                }
            }
            continue;
        }

        var parsed = parseSingleQuickEntry(line, entryDefaults, lexiconAnalyzer);
        if (parsed && (parsed.term || parsed.clozeText)) {
            var comp = parsed._reverseCompanion;
            delete parsed._reverseCompanion;
            parsed.id = "sr-import-" + (results.length + 1);
            results.push(parsed);
            if (comp) {
                comp.id = "sr-import-" + (results.length + 1);
                results.push(comp);
            }
        }
    }
    return results;
}

function parseBulkText(rawText, defaultsOrDeck, langOrAnalyzer, categoryOpt, analyzerOpt) {
    return parseQuickInput(rawText, defaultsOrDeck, langOrAnalyzer, categoryOpt, analyzerOpt);
}

function buildStudyQueue(cards, filters, statsToday, nowMs, rawOptions) {
    // Allow 3-argument call: buildStudyQueue(cards, filtersWithOptions, nowMs)
    if (typeof statsToday === "number" && nowMs === undefined) {
        nowMs = statsToday;
        rawOptions = filters && filters.options ? filters.options : undefined;
        statsToday = filters && filters.statsToday ? filters.statsToday : {};
    }
    var opts = normalizeOptions(rawOptions || (filters && filters.options));
    var now = Number.isFinite(Number(nowMs)) ? Number(nowMs) : Date.now();
    var f = (filters && typeof filters === "object") ? filters : {};
    var catFilter = String(f.category || "all").toLowerCase();
    if (catFilter === "vocab") catFilter = "vocabulary";
    var langFilter = String(f.language || "all").toLowerCase();
    var levelFilter = String(f.level || f.cefrLevel || "all").toUpperCase();
    var deckFilter = String(f.deck || "all");
    var leechesOnly = Boolean(f.leechesOnly);
    var query = String(f.searchQuery || "").trim().toLowerCase();
    var boostMode = String(f.boostMode || "").toLowerCase(); // "", "ahead", "hard", "cram"
    var aheadDays = Math.max(1, Number(f.aheadDays) || 3);

    var source = Array.isArray(cards) ? cards : [];
    var filtered = [];
    for (var i = 0; i < source.length; i++) {
        var c = source[i];
        if (!c || typeof c !== "object") continue;
        var cCat = c.category === "vocab" ? "vocabulary" : c.category;
        if (catFilter !== "all" && cCat !== catFilter) continue;
        if (langFilter !== "all" && c.language !== langFilter) continue;
        if (levelFilter !== "ALL") {
            if (levelFilter === "UNLEVELED" && (c.level || c.cefrLevel)) continue;
            if (levelFilter !== "UNLEVELED" && String(c.level || c.cefrLevel || "").toUpperCase() !== levelFilter) continue;
        }
        if (deckFilter !== "all" && c.deck !== deckFilter) continue;
        if (leechesOnly && !c.isLeech && (Number(c.lapses) || 0) < opts.leechThreshold) continue;
        if (query) {
            var hay = (String(c.term || c.front || "") + " " + String(c.meaning || c.back || "") + " " + String(c.example || "") + " " + String(c.deck || "")).toLowerCase();
            if (hay.indexOf(query) < 0) continue;
        }
        filtered.push(c);
    }

    var newTodayDone = Math.max(0, Number(statsToday && statsToday.newStudied) || 0);
    var revTodayDone = Math.max(0, Number(statsToday && statsToday.reviewsDone) || 0);
    var remNew = boostMode ? 9999 : Math.max(0, opts.dailyNewLimit - newTodayDone);
    var remRev = boostMode ? 9999 : Math.max(0, opts.dailyReviewLimit - revTodayDone);

    var todayStr = civilDayKey(now);
    var aheadCutoffStr = addDaysKey(todayStr, aheadDays, now);

    var dueReviews = [];
    var dueNew = [];
    var aheadPool = [];

    for (var j = 0; j < filtered.length; j++) {
        var item = filtered[j];
        var isNew = (Number(item.reps) || 0) === 0 && item.state === "new";
        var itemDueMs = Number(item.dueAt);
        var isDue = (Number.isFinite(itemDueMs) && itemDueMs <= now)
            || (typeof item.dueDate === "string" && item.dueDate <= todayStr);
        if (isNew) {
            if (dueNew.length < remNew) dueNew.push(item);
            else aheadPool.push(item);
        } else if (isDue) {
            if (dueReviews.length < remRev) dueReviews.push(item);
            else aheadPool.push(item);
        } else {
            aheadPool.push(item);
        }
    }

    var sorter = function(a, b) {
        if (opts.prioritizeOrder === "level_asc") {
            var la = CEFR_ORDER[a.level || a.cefrLevel] || 99;
            var lb = CEFR_ORDER[b.level || b.cefrLevel] || 99;
            if (la !== lb) return la - lb;
        } else if (opts.prioritizeOrder === "hardest_first") {
            var ea = Number(a.ease) || 250;
            var eb = Number(b.ease) || 250;
            if (ea !== eb) return ea - eb;
        }
        return (Number(a.dueAt) || 0) - (Number(b.dueAt) || 0);
    };

    dueReviews.sort(sorter);
    dueNew.sort(sorter);

    var queue = [];
    if (opts.prioritizeOrder === "interleaved") {
        var rIdx = 0, nIdx = 0;
        while (rIdx < dueReviews.length || nIdx < dueNew.length) {
            if (rIdx < dueReviews.length) queue.push(dueReviews[rIdx++]);
            if (rIdx < dueReviews.length) queue.push(dueReviews[rIdx++]);
            if (nIdx < dueNew.length) queue.push(dueNew[nIdx++]);
        }
    } else if (opts.prioritizeOrder === "new_first") {
        queue = dueNew.concat(dueReviews);
    } else {
        queue = dueReviews.concat(dueNew);
    }

    if (boostMode === "hard") {
        var hardCards = filtered.filter(function(c) {
            return Boolean(c.isLeech) || (Number(c.lapses) || 0) > 0 || (Number(c.ease) || 250) < 230;
        });
        hardCards.sort(function(a, b) {
            var lapseDiff = (Number(b.lapses) || 0) - (Number(a.lapses) || 0);
            if (lapseDiff !== 0) return lapseDiff;
            return (Number(a.ease) || 250) - (Number(b.ease) || 250);
        });
        return hardCards.slice(0, 25);
    } else if (boostMode === "ahead") {
        var aheadCandidates = aheadPool.filter(function(c) {
            if (typeof c.dueDate === "string") return c.dueDate <= aheadCutoffStr;
            return (Number(c.dueAt) || 0) <= now + aheadDays * DAY_MS;
        });
        aheadCandidates.sort(sorter);
        return queue.concat(aheadCandidates).slice(0, 25);
    } else if (boostMode === "cram") {
        aheadPool.sort(sorter);
        return queue.concat(aheadPool).slice(0, 30);
    }

    return queue;
}

function computeAnalytics(cards, historyByDay, nowMs, rawOptions) {
    var opts = normalizeOptions(rawOptions);
    var now = Number.isFinite(Number(nowMs)) ? Number(nowMs) : Date.now();
    var list = Array.isArray(cards) ? cards : [];
    var hist = (historyByDay && typeof historyByDay === "object") ? historyByDay : {};

    var counts = {
        total: list.length,
        due: 0,
        newCards: 0,
        learning: 0,
        young: 0,
        mature: 0,
        leeches: 0,
        vocab: 0,
        knowledge: 0,
        cloze: 0
    };
    var levels = { "A1": 0, "A2": 0, "B1": 0, "B2": 0, "C1": 0, "C2": 0 };
    var masteredLevels = { "A1": 0, "A2": 0, "B1": 0, "B2": 0, "C1": 0, "C2": 0 };
    var languages = { "en": 0, "de": 0, "general": 0 };
    var deckMap = {};
    var dueCountsByDay = {};
    var easeSum = 0;

    for (var i = 0; i < list.length; i++) {
        var c = list[i];
        if (!c || typeof c !== "object") continue;
        var reps = Number(c.reps) || 0;
        var interval = Number(c.interval) || 0;
        var lapses = Number(c.lapses) || 0;
        var dueAt = Number(c.dueAt) || 0;

        easeSum += (Number(c.ease) || opts.baseEase);
        if (dueAt <= now) counts.due++;
        if (reps === 0 && c.state === "new") counts.newCards++;
        else if (interval < 1 || c.state === "learning" || c.state === "relearning") counts.learning++;
        else if (interval < 21) counts.young++;
        else counts.mature++;

        if (c.isLeech || lapses >= opts.leechThreshold) counts.leeches++;
        if (c.category === "vocab" || c.category === "vocabulary") counts.vocab++;
        else if (c.category === "cloze") counts.cloze++;
        else counts.knowledge++;

        var lvl = String(c.level || c.cefrLevel || "").toUpperCase();
        if (levels[lvl] !== undefined) {
            levels[lvl]++;
            if (reps >= 1 && interval >= 3) masteredLevels[lvl]++;
        }

        var lang = c.language === "de" ? "de" : (c.language === "en" ? "en" : "general");
        languages[lang] = (languages[lang] || 0) + 1;

        var dName = String(c.deck || "General");
        if (!deckMap[dName]) deckMap[dName] = { name: dName, total: 0, due: 0, newCount: 0 };
        deckMap[dName].total++;
        if (dueAt <= now) deckMap[dName].due++;
        if (reps === 0) deckMap[dName].newCount++;

        var dayKey = civilDayKey(dueAt);
        dueCountsByDay[dayKey] = (dueCountsByDay[dayKey] || 0) + 1;
    }

    var todayKeyStr = civilDayKey(now);
    var todayEntry = hist[todayKeyStr] || { reviewed: 0, passed: 0, newStudied: 0, reviewsDone: 0 };
    var totalReviewedAllTime = 0;
    var totalPassedAllTime = 0;
    var dayKeys = Object.keys(hist);
    for (var k = 0; k < dayKeys.length; k++) {
        var h = hist[dayKeys[k]];
        if (h && typeof h === "object") {
            totalReviewedAllTime += (Number(h.reviewed) || 0);
            totalPassedAllTime += (Number(h.passed) || 0);
        }
    }

    // Calculate consecutive day streak
    var streak = 0;
    var probeMs = now;
    if ((Number(todayEntry.reviewed) || 0) === 0) {
        probeMs = now - DAY_MS;
    }
    for (var s = 0; s < 3650; s++) {
        var key = civilDayKey(probeMs - s * DAY_MS);
        var entry = hist[key];
        if (entry && (Number(entry.reviewed) || 0) > 0) {
            streak++;
        } else {
            break;
        }
    }

    return {
        counts: counts,
        total: counts.total,
        dueToday: counts.due,
        newCount: counts.newCards,
        learningCount: counts.learning,
        youngCount: counts.young,
        matureCount: counts.mature,
        leechCount: counts.leeches,
        levels: levels,
        cefrCounts: levels,
        masteredLevels: masteredLevels,
        cefrMastered: masteredLevels,
        languages: languages,
        decks: Object.keys(deckMap).sort().map(function(name) { return deckMap[name]; }),
        dueCountsByDay: dueCountsByDay,
        averageEase: list.length > 0 ? Math.round(easeSum / list.length) : opts.baseEase,
        retentionRate: totalReviewedAllTime > 0 ? Math.round((totalPassedAllTime / totalReviewedAllTime) * 100) : 100,
        streakDays: streak,
        streak: streak,
        todayReviewed: Number(todayEntry.reviewed) || 0,
        todayNewStudied: Number(todayEntry.newStudied) || 0,
        todayReviewsDone: Number(todayEntry.reviewsDone) || 0
    };
}

function starterCards(nowMs, rawOptions, lexiconAnalyzer) {
    var now = Number.isFinite(Number(nowMs)) ? Number(nowMs) : Date.now();
    var opts = normalizeOptions(rawOptions);
    var seeds = [
        {
            id: "sr-seed-en-1",
            category: "vocab",
            deck: "English Vocabulary",
            language: "en",
            term: "ephemeral",
            pos: "adj",
            phonetic: "/ɪˈfem.ər.əl/",
            level: "C1",
            levelSource: "Cambridge EVP",
            meaning: "lasting for only a very short time; fleeting",
            example: "Short-term cramming creates ephemeral memories that fade within days.",
            collocations: ["ephemeral nature - bản chất phù du", "ephemeral fame - danh tiếng thoáng qua"],
            synonyms: ["transient", "fleeting", "short-lived"],
            notes: "Greek ephemeros — lasting only one day.",
            bidirectional: true,
            dueAt: now - 300000
        },
        {
            id: "sr-seed-de-1",
            category: "vocab",
            deck: "German Vocabulary",
            language: "de",
            term: "Zeitraum",
            article: "der",
            plural: "Zeiträume",
            pos: "noun",
            phonetic: "/ˈt͡saɪ̯tˌʁaʊ̯m/",
            level: "B1",
            levelSource: "Goethe-Zertifikat B1 / DWDS",
            meaning: "period of time, time span, interval",
            example: "Über einen längeren Zeitraum bleibt das Wissen im Gedächtnis.",
            synonyms: ["Zeitspanne", "Periode"],
            notes: "Compound: die Zeit (time) + der Raum (space).",
            bidirectional: true,
            dueAt: now - 240000
        },
        {
            id: "sr-seed-en-2",
            category: "vocab",
            deck: "English Vocabulary",
            language: "en",
            term: "ubiquitous",
            pos: "adj",
            phonetic: "/juːˈbɪk.wɪ.təs/",
            level: "C1",
            levelSource: "Cambridge EVP / Oxford 5000",
            meaning: "seeming to be everywhere or in several places at the same time",
            example: "Digital flashcards have become ubiquitous in modern language learning.",
            synonyms: ["omnipresent", "pervasive", "universal"],
            bidirectional: true,
            dueAt: now - 180000
        },
        {
            id: "sr-seed-de-2",
            category: "vocab",
            deck: "German Vocabulary",
            language: "de",
            term: "nachhaltig",
            article: "",
            plural: "",
            pos: "adj",
            phonetic: "/ˈnaːxˌhaltɪç/",
            level: "B2",
            levelSource: "DWDS / Telc B2",
            meaning: "sustainable, lasting, enduring in effect",
            example: "Spaced Repetition sorgt für einen nachhaltigen Lernerfolg.",
            synonyms: ["dauerhaft", "langfristig"],
            notes: "Noun form: die Nachhaltigkeit [B2].",
            bidirectional: true,
            dueAt: now - 120000
        },
        {
            id: "sr-seed-de-3",
            category: "vocab",
            deck: "German Vocabulary",
            language: "de",
            term: "gewährleisten",
            article: "",
            plural: "",
            pos: "verb",
            phonetic: "/ɡəˈvɛːɐ̯ˌlaɪ̯stn̩/",
            level: "C1",
            levelSource: "DWDS / TestDaF C1",
            meaning: "to guarantee, to ensure, to warrant",
            example: "Regelmäßige Intervalle gewährleisten eine hohe Behaltensquote.",
            synonyms: ["sicherstellen", "garantieren"],
            notes: "Inseparable verb: er gewährleistet, hat gewährleistet.",
            bidirectional: true,
            dueAt: now - 60000
        },
        {
            id: "sr-seed-en-3",
            category: "vocab",
            deck: "English Vocabulary",
            language: "en",
            term: "pragmatic",
            pos: "adj",
            phonetic: "/præɡˈmæt.ɪk/",
            level: "C1",
            levelSource: "Oxford 5000 / Cambridge EVP",
            meaning: "solving problems in a sensible, practical way rather than following fixed theories",
            example: "Automating card syntax is a pragmatic improvement over manual markup.",
            synonyms: ["practical", "realistic", "matter-of-fact"],
            bidirectional: true,
            dueAt: now - 30000
        },
        {
            id: "sr-seed-know-1",
            category: "knowledge",
            deck: "Cognitive Science & Learning",
            language: "general",
            term: "Why does the Spacing Effect outperform massed cramming?",
            meaning: "Allowing partial forgetting between retrieval attempts forces deeper synaptic reconsolidation, multiplying interval stability with each successful recall.",
            example: "Reviewing at expanding intervals (1d → 3d → 7d → 18d) builds durable long-term memory.",
            clozeText: "Allowing partial forgetting between retrieval attempts forces deeper {{c1::synaptic reconsolidation}}.",
            notes: "Ebbinghaus Forgetting Curve & Bjork's Desirable Difficulties.",
            bidirectional: false,
            dueAt: now - 20000
        },
        {
            id: "sr-seed-know-2",
            category: "cloze",
            deck: "Linux & Systems Architecture",
            language: "general",
            term: "Wayland frame callback lifecycle",
            meaning: "Offscreen or hidden surfaces suspend frame callbacks (0 FPS) so GPU/CPU resources stay idle until presented.",
            example: "In Wayland/Quickshell, hidden Dashboard tabs suspend animations and frame timers to maintain 0 FPS idle power.",
            clozeText: "In Wayland/Quickshell, hidden Dashboard tabs suspend animations and frame timers to maintain {{c1::0 FPS}} idle power.",
            bidirectional: false,
            dueAt: now - 10000
        }
    ];
    var baseCards = seeds.map(function(s, idx) {
        return normalizeCard(s, idx + 1, now, opts, lexiconAnalyzer);
    });
    return baseCards.concat(unitVocabularyCards(now, opts, lexiconAnalyzer));
}

function unitVocabularyCards(nowMs, rawOptions, lexiconAnalyzer) {
    var now = Number.isFinite(Number(nowMs)) ? Number(nowMs) : Date.now();
    var opts = normalizeOptions(rawOptions);
    var unitSeeds = [
        {
                "id": "sr-unit01-01",
                "category": "vocabulary",
                "deck": "English Vocabulary",
                "language": "en",
                "term": "allot",
                "pos": "verb",
                "phonetic": "/əˈlɒt/",
                "level": "C1",
                "levelSource": "4000 Essential English Words Vol. 5",
                "meaning": "to give a particular share of time, money, or resources to someone or something",
                "example": "IELTS candidates should allot their time logically to achieve optimal results.",
                "clozeText": "IELTS candidates should {{c1::allot::verb — phân bổ}} their time logically to achieve optimal results.",
                "collocations": [
                        "allot time/resources - phân bổ thời gian/nguồn lực",
                        "allot a portion - phân chia một phần"
                ],
                "bidirectional": true,
                "interval": 0,
                "ease": 250,
                "reps": 0,
                "state": "new",
                "meaningVi": "chia, phân bổ, phân phối (thời gian, nguồn lực cho mục đích cụ thể)",
                "definitionEn": "to give a particular share of time, money, or resources to someone or something",
                "lapses": 0
        },
        {
                "id": "sr-unit01-02",
                "category": "vocabulary",
                "deck": "English Vocabulary",
                "language": "en",
                "term": "appall",
                "pos": "verb",
                "phonetic": "/əˈpɔːl/",
                "level": "C1",
                "levelSource": "4000 Essential English Words Vol. 5",
                "meaning": "to shock or offend someone very much; to fill with horror or dismay",
                "example": "The horror movie was expected to appall audiences, but it proved to be a disappointment.",
                "clozeText": "The horror movie was expected to {{c1::appall::verb — làm kinh hãi}} audiences, but it proved to be a disappointment.",
                "collocations": [
                        "appall the public - làm công chúng bàng hoàng",
                        "be deeply appalled - cực kỳ phẫn nộ/kinh hãi"
                ],
                "bidirectional": true,
                "interval": 0,
                "ease": 250,
                "reps": 0,
                "state": "new",
                "meaningVi": "làm kinh hãi, làm khiếp sợ, gây sốc",
                "definitionEn": "to shock or offend someone very much; to fill with horror or dismay",
                "lapses": 0
        },
        {
                "id": "sr-unit01-03",
                "category": "vocabulary",
                "deck": "English Vocabulary",
                "language": "en",
                "term": "cache",
                "pos": "noun",
                "phonetic": "/kæʃ/",
                "level": "C2",
                "levelSource": "4000 Essential English Words Vol. 5",
                "meaning": "a hidden store of things such as weapons, treasure, or data kept for future use",
                "example": "When my brothers and I were young, we pretended to be ruthless pirates searching for a hidden cache of treasure.",
                "clozeText": "When my brothers and I were young, we pretended to be ruthless pirates searching for a hidden {{c1::cache::noun — kho cất giấu}} of treasure.",
                "collocations": [
                        "arms cache - kho vũ khí bí mật",
                        "hidden cache - kho giấu kín"
                ],
                "bidirectional": true,
                "interval": 0,
                "ease": 250,
                "reps": 0,
                "state": "new",
                "meaningVi": "kho cất giấu, nơi cất giấu, kho bí mật (vũ khí, kho báu, dữ liệu)",
                "definitionEn": "a hidden store of things such as weapons, treasure, or data kept for future use",
                "lapses": 0
        },
        {
                "id": "sr-unit01-04",
                "category": "vocabulary",
                "deck": "English Vocabulary",
                "language": "en",
                "term": "dearth",
                "pos": "noun",
                "phonetic": "/dɜːθ/",
                "level": "C2",
                "levelSource": "4000 Essential English Words Vol. 5",
                "meaning": "a severe shortage or lack of something that is needed",
                "example": "The young often suffer from a dearth of money but possess a plethora of time, whereas the elderly face the reverse.",
                "clozeText": "The young often suffer from a {{c1::dearth::noun — sự khan hiếm}} of money but possess a plethora of time, whereas the elderly face the reverse.",
                "collocations": [
                        "dearth of evidence - sự thiếu hụt bằng chứng",
                        "dearth of resources - sự khan hiếm nguồn lực"
                ],
                "bidirectional": true,
                "interval": 0,
                "ease": 250,
                "reps": 0,
                "state": "new",
                "meaningVi": "sự khan hiếm, sự thiếu hụt nghiêm trọng",
                "definitionEn": "a severe shortage or lack of something that is needed",
                "lapses": 0
        },
        {
                "id": "sr-unit01-05",
                "category": "vocabulary",
                "deck": "English Vocabulary",
                "language": "en",
                "term": "deliberate",
                "pos": "adj",
                "phonetic": "/dɪˈlɪb.ər.ət/",
                "level": "C1",
                "levelSource": "4000 Essential English Words Vol. 5",
                "meaning": "done intentionally and carefully planned rather than by accident",
                "example": "Every effort I make to improve my English proficiency is deliberate and strategic.",
                "clozeText": "Every effort I make to improve my English proficiency is {{c1::deliberate::adj — có chủ đích}} and strategic.",
                "collocations": [
                        "deliberate attempt - nỗ lực có chủ đích",
                        "deliberate choice - lựa chọn có cân nhắc"
                ],
                "bidirectional": true,
                "interval": 0,
                "ease": 250,
                "reps": 0,
                "state": "new",
                "meaningVi": "cố ý, có chủ đích, được tính toán cẩn thận",
                "definitionEn": "done intentionally and carefully planned rather than by accident",
                "lapses": 0
        },
        {
                "id": "sr-unit01-06",
                "category": "vocabulary",
                "deck": "English Vocabulary",
                "language": "en",
                "term": "dire",
                "pos": "adj",
                "phonetic": "/ˈdaɪər/",
                "level": "C1",
                "levelSource": "4000 Essential English Words Vol. 5",
                "meaning": "extremely serious, urgent, or terrible in consequence",
                "example": "Most natural disasters cause dire consequences that society struggles to mitigate.",
                "clozeText": "Most natural disasters cause {{c1::dire::adj — thảm khốc}} consequences that society struggles to mitigate.",
                "collocations": [
                        "dire consequences - hậu quả thảm khốc",
                        "in dire need - trong tình thế cấp thiết"
                ],
                "bidirectional": true,
                "interval": 0,
                "ease": 250,
                "reps": 0,
                "state": "new",
                "meaningVi": "thảm khốc, khốc liệt, vô cùng tồi tệ",
                "definitionEn": "extremely serious, urgent, or terrible in consequence",
                "lapses": 0
        },
        {
                "id": "sr-unit01-07",
                "category": "vocabulary",
                "deck": "English Vocabulary",
                "language": "en",
                "term": "elapse",
                "pos": "verb",
                "phonetic": "/ɪˈlæps/",
                "level": "C1",
                "levelSource": "4000 Essential English Words Vol. 5",
                "meaning": "(of time) to pass or go by",
                "example": "Few realize how quickly time will elapse turning cherished memories into distant history.",
                "clozeText": "Few realize how quickly time will {{c1::elapse::verb — trôi qua}} turning cherished memories into distant history.",
                "collocations": [
                        "time elapses - thời gian trôi qua",
                        "years elapse - nhiều năm trôi qua"
                ],
                "bidirectional": true,
                "interval": 0,
                "ease": 250,
                "reps": 0,
                "state": "new",
                "meaningVi": "trôi qua (dùng cho thời gian)",
                "definitionEn": "(of time) to pass or go by",
                "lapses": 0
        },
        {
                "id": "sr-unit01-08",
                "category": "vocabulary",
                "deck": "English Vocabulary",
                "language": "en",
                "term": "empathy",
                "pos": "noun",
                "phonetic": "/ˈem.pə.θi/",
                "level": "B2",
                "levelSource": "4000 Essential English Words Vol. 5",
                "meaning": "the ability to understand and share the feelings and experiences of another person",
                "example": "Some individuals lack empathy for others, appearing entirely indifferent to their suffering.",
                "clozeText": "Some individuals lack {{c1::empathy::noun — sự đồng cảm}} for others, appearing entirely indifferent to their suffering.",
                "collocations": [
                        "demonstrate empathy - thể hiện sự thấu cảm",
                        "empathy towards someone - sự đồng cảm dành cho ai"
                ],
                "bidirectional": true,
                "interval": 0,
                "ease": 250,
                "reps": 0,
                "state": "new",
                "meaningVi": "sự đồng cảm, sự thấu cảm (khả năng hiểu và chia sẻ cảm xúc)",
                "definitionEn": "the ability to understand and share the feelings and experiences of another person",
                "lapses": 0
        },
        {
                "id": "sr-unit01-09",
                "category": "vocabulary",
                "deck": "English Vocabulary",
                "language": "en",
                "term": "fanciful",
                "pos": "adj",
                "phonetic": "/ˈfæn.sɪ.fəl/",
                "level": "C2",
                "levelSource": "4000 Essential English Words Vol. 5",
                "meaning": "imagined rather than based on realistic facts; overly whimsical or unrealistic",
                "example": "Some of my career plans are purely fanciful rather than rooted in practical reality.",
                "clozeText": "Some of my career plans are purely {{c1::fanciful::adj — viển vông}} rather than rooted in practical reality.",
                "collocations": [
                        "fanciful idea - ý tưởng viển vông",
                        "fanciful notion - khái niệm xa rời thực tế"
                ],
                "bidirectional": true,
                "interval": 0,
                "ease": 250,
                "reps": 0,
                "state": "new",
                "meaningVi": "viển vông, kỳ lạ, tưởng tượng không thực tế",
                "definitionEn": "imagined rather than based on realistic facts; overly whimsical or unrealistic",
                "lapses": 0
        },
        {
                "id": "sr-unit01-10",
                "category": "vocabulary",
                "deck": "English Vocabulary",
                "language": "en",
                "term": "gripe",
                "pos": "verb",
                "phonetic": "/ɡraɪp/",
                "level": "C2",
                "levelSource": "4000 Essential English Words Vol. 5",
                "meaning": "to complain continually about something, especially something minor",
                "example": "My mother will constantly gripe whenever I neglect my daily household chores.",
                "clozeText": "My mother will constantly {{c1::gripe::verb — cằn nhằn}} whenever I neglect my daily household chores.",
                "collocations": [
                        "gripe about something - phàn nàn về điều gì",
                        "gripe continuously - cằn nhằn không ngừng"
                ],
                "bidirectional": true,
                "interval": 0,
                "ease": 250,
                "reps": 0,
                "state": "new",
                "meaningVi": "cằn nhằn, phàn nàn (thường về những điều nhỏ nhặt)",
                "definitionEn": "to complain continually about something, especially something minor",
                "lapses": 0
        },
        {
                "id": "sr-unit01-11",
                "category": "vocabulary",
                "deck": "English Vocabulary",
                "language": "en",
                "term": "gruelling",
                "pos": "adj",
                "phonetic": "/ˈɡruː.ə.lɪŋ/",
                "level": "C2",
                "levelSource": "4000 Essential English Words Vol. 5",
                "meaning": "extremely tiring, demanding, and difficult to endure",
                "example": "Professional mountain climbers must endure a gruelling training regimen before attempting high peaks.",
                "clozeText": "Professional mountain climbers must endure a {{c1::gruelling::adj — kiệt sức}} training regimen before attempting high peaks.",
                "collocations": [
                        "gruelling schedule - lịch trình kiệt sức",
                        "gruelling journey - hành trình gian khổ"
                ],
                "bidirectional": true,
                "interval": 0,
                "ease": 250,
                "reps": 0,
                "state": "new",
                "meaningVi": "cam go, kiệt sức, đòi hỏi nhiều sức lực và sự chịu đựng",
                "definitionEn": "extremely tiring, demanding, and difficult to endure",
                "lapses": 0
        },
        {
                "id": "sr-unit01-12",
                "category": "vocabulary",
                "deck": "English Vocabulary",
                "language": "en",
                "term": "mundane",
                "pos": "adj",
                "phonetic": "/mʌnˈdeɪn/",
                "level": "C1",
                "levelSource": "4000 Essential English Words Vol. 5",
                "meaning": "very ordinary and therefore not interesting or exciting",
                "example": "Working in a purely mundane job without any creative freedom would drive me insane.",
                "clozeText": "Working in a purely {{c1::mundane::adj — tẻ nhạt}} job without any creative freedom would drive me insane.",
                "collocations": [
                        "mundane tasks - công việc tẻ nhạt hằng ngày",
                        "mundane reality - thực tại tầm thường"
                ],
                "bidirectional": true,
                "interval": 0,
                "ease": 250,
                "reps": 0,
                "state": "new",
                "meaningVi": "tẻ nhạt, bình thường, thuộc về đời thường trần tục",
                "definitionEn": "very ordinary and therefore not interesting or exciting",
                "lapses": 0
        },
        {
                "id": "sr-unit01-13",
                "category": "vocabulary",
                "deck": "English Vocabulary",
                "language": "en",
                "term": "opt",
                "pos": "verb",
                "phonetic": "/ɒpt/",
                "level": "B2",
                "levelSource": "4000 Essential English Words Vol. 5",
                "meaning": "to make a choice from a range of possibilities",
                "example": "While many prioritize financial security, I would still opt for love regardless of the sacrifices required.",
                "clozeText": "While many prioritize financial security, I would still {{c1::opt::verb — lựa chọn}} for love regardless of the sacrifices required.",
                "collocations": [
                        "opt for something - chọn cái gì",
                        "opt to do something - quyết định làm gì"
                ],
                "bidirectional": true,
                "interval": 0,
                "ease": 250,
                "reps": 0,
                "state": "new",
                "meaningVi": "lựa chọn, chọn lựa (sau khi cân nhắc các phương án)",
                "definitionEn": "to make a choice from a range of possibilities",
                "lapses": 0
        },
        {
                "id": "sr-unit01-14",
                "category": "vocabulary",
                "deck": "English Vocabulary",
                "language": "en",
                "term": "outrage",
                "pos": "noun",
                "phonetic": "/ˈaʊt.reɪdʒ/",
                "level": "B2",
                "levelSource": "4000 Essential English Words Vol. 5",
                "meaning": "a strong feeling of shock and anger caused by something unfair or cruel",
                "example": "Hank could not conceal his outrage when falsely accused of stealing food.",
                "clozeText": "Hank could not conceal his {{c1::outrage::noun — sự phẫn nộ}} when falsely accused of stealing food.",
                "collocations": [
                        "spark public outrage - gây ra sự phẫn nộ trong công chúng",
                        "express outrage - bày tỏ sự giận dữ"
                ],
                "bidirectional": true,
                "interval": 0,
                "ease": 250,
                "reps": 0,
                "state": "new",
                "meaningVi": "sự phẫn nộ, sự giận dữ tột cùng",
                "definitionEn": "a strong feeling of shock and anger caused by something unfair or cruel",
                "lapses": 0
        },
        {
                "id": "sr-unit01-15",
                "category": "vocabulary",
                "deck": "English Vocabulary",
                "language": "en",
                "term": "paltry",
                "pos": "adj",
                "phonetic": "/ˈpɔːl.tri/",
                "level": "C2",
                "levelSource": "4000 Essential English Words Vol. 5",
                "meaning": "(of an amount of money or resources) very small and of little or no value",
                "example": "They offered him a paltry sum of money that barely covered his travel expenses.",
                "clozeText": "They offered him a {{c1::paltry::adj — bèo bọt}} sum of money that barely covered his travel expenses.",
                "collocations": [
                        "paltry sum - số tiền bèo bọt",
                        "paltry amount - lượng ít ỏi"
                ],
                "bidirectional": true,
                "interval": 0,
                "ease": 250,
                "reps": 0,
                "state": "new",
                "meaningVi": "ít ỏi, bèo bọt, không đáng kể",
                "definitionEn": "(of an amount of money or resources) very small and of little or no value",
                "lapses": 0
        },
        {
                "id": "sr-unit01-16",
                "category": "vocabulary",
                "deck": "English Vocabulary",
                "language": "en",
                "term": "rectify",
                "pos": "verb",
                "phonetic": "/ˈrek.tɪ.faɪ/",
                "level": "C1",
                "levelSource": "4000 Essential English Words Vol. 5",
                "meaning": "to correct something that is wrong or put a mistake right",
                "example": "We apologize for the inconvenience caused and are taking immediate steps to rectify the situation.",
                "clozeText": "We apologize for the inconvenience caused and are taking immediate steps to {{c1::rectify::verb — khắc phục}} the situation.",
                "collocations": [
                        "rectify an error - khắc phục một sai sót",
                        "rectify a situation - chấn chỉnh/sửa chữa tình hình"
                ],
                "bidirectional": true,
                "interval": 0,
                "ease": 250,
                "reps": 0,
                "state": "new",
                "meaningVi": "khắc phục, sửa chữa, chấn chỉnh (sai sót, tình huống)",
                "definitionEn": "to correct something that is wrong or put a mistake right",
                "lapses": 0
        },
        {
                "id": "sr-unit01-17",
                "category": "vocabulary",
                "deck": "English Vocabulary",
                "language": "en",
                "term": "resourceful",
                "pos": "adj",
                "phonetic": "/rɪˈzɔː.sfəl/",
                "level": "C1",
                "levelSource": "4000 Essential English Words Vol. 5",
                "meaning": "skilled at finding clever and practical ways to overcome difficulties",
                "example": "A resourceful manager can find creative solutions even when facing tight budget constraints.",
                "clozeText": "A {{c1::resourceful::adj — tháo vát}} manager can find creative solutions even when facing tight budget constraints.",
                "collocations": [
                        "resourceful person - người tháo vát",
                        "highly resourceful - cực kỳ linh hoạt/tháo vát"
                ],
                "bidirectional": true,
                "interval": 0,
                "ease": 250,
                "reps": 0,
                "state": "new",
                "meaningVi": "tháo vát, linh hoạt, xoay xở giỏi",
                "definitionEn": "skilled at finding clever and practical ways to overcome difficulties",
                "lapses": 0
        },
        {
                "id": "sr-unit01-18",
                "category": "vocabulary",
                "deck": "English Vocabulary",
                "language": "en",
                "term": "sustenance",
                "pos": "noun",
                "phonetic": "/ˈsʌs.tən.əns/",
                "level": "C2",
                "levelSource": "4000 Essential English Words Vol. 5",
                "meaning": "food and drink needed to stay alive and healthy; means of livelihood",
                "example": "My part-time tutoring job barely provides enough income for basic sustenance.",
                "clozeText": "My part-time tutoring job barely provides enough income for basic {{c1::sustenance::noun — kế sinh nhai}}.",
                "collocations": [
                        "basic sustenance - kế sinh nhai cơ bản",
                        "draw sustenance from - lấy nguồn sống từ"
                ],
                "bidirectional": true,
                "interval": 0,
                "ease": 250,
                "reps": 0,
                "state": "new",
                "meaningVi": "thực phẩm nuôi sống, kế sinh nhai, sự duy trì cuộc sống",
                "definitionEn": "food and drink needed to stay alive and healthy; means of livelihood",
                "lapses": 0
        },
        {
                "id": "sr-unit01-19",
                "category": "vocabulary",
                "deck": "English Vocabulary",
                "language": "en",
                "term": "tedious",
                "pos": "adj",
                "phonetic": "/ˈtiː.di.əs/",
                "level": "C1",
                "levelSource": "4000 Essential English Words Vol. 5",
                "meaning": "lasting too long and not interesting; monotonous and tiresome",
                "example": "Preparing lesson plans manually can be so tedious that teachers often delegate the task to AI models.",
                "clozeText": "Preparing lesson plans manually can be so {{c1::tedious::adj — tẻ nhạt}} that teachers often delegate the task to AI models.",
                "collocations": [
                        "tedious process - quy trình tẻ nhạt",
                        "tedious task - công việc chán ngắt"
                ],
                "bidirectional": true,
                "interval": 0,
                "ease": 250,
                "reps": 0,
                "state": "new",
                "meaningVi": "chán ngắt, tẻ nhạt, rườm rà và kéo dài",
                "definitionEn": "lasting too long and not interesting; monotonous and tiresome",
                "lapses": 0
        },
        {
                "id": "sr-unit02-01",
                "category": "vocabulary",
                "deck": "English Vocabulary",
                "language": "en",
                "term": "abbey",
                "pos": "noun",
                "phonetic": "/ˈæb.i/",
                "level": "B2",
                "levelSource": "4000 Essential English Words Vol. 5",
                "meaning": "a large church together with a group of buildings where monks or nuns live",
                "example": "An abbey is a large building where monks or nuns live, whereas a monastery is typically for monks and a convent for nuns.",
                "clozeText": "An {{c1::abbey::noun — tu viện}} is a large building where monks or nuns live, whereas a monastery is typically for monks and a convent for nuns.",
                "collocations": [
                        "historic abbey - tu viện cổ kính",
                        "abbey church - nhà thờ tu viện"
                ],
                "bidirectional": true,
                "interval": 0,
                "ease": 250,
                "reps": 0,
                "state": "new",
                "meaningVi": "tu viện, đại tu viện (nơi các tu sĩ hoặc nữ tu sinh sống và tu tập)",
                "definitionEn": "a large church together with a group of buildings where monks or nuns live",
                "lapses": 0
        },
        {
                "id": "sr-unit02-02",
                "category": "vocabulary",
                "deck": "English Vocabulary",
                "language": "en",
                "term": "abundant",
                "pos": "adj",
                "phonetic": "/əˈbʌn.dənt/",
                "level": "C1",
                "levelSource": "4000 Essential English Words Vol. 5",
                "meaning": "existing or available in large quantities; more than enough",
                "example": "My budget for gaming is abundant whereas others are struggling to allocate their resources properly.",
                "clozeText": "My budget for gaming is {{c1::abundant::adj — dồi dào}} whereas others are struggling to allocate their resources properly.",
                "collocations": [
                        "abundant evidence - bằng chứng dồi dào",
                        "abundant supply - nguồn cung dồi dào"
                ],
                "bidirectional": true,
                "interval": 0,
                "ease": 250,
                "reps": 0,
                "state": "new",
                "meaningVi": "dồi dào, phong phú, nhiều hơn mức đủ dùng",
                "definitionEn": "existing or available in large quantities; more than enough",
                "lapses": 0
        },
        {
                "id": "sr-unit02-03",
                "category": "vocabulary",
                "deck": "English Vocabulary",
                "language": "en",
                "term": "adjoin",
                "pos": "verb",
                "phonetic": "/əˈdʒɔɪn/",
                "level": "C2",
                "levelSource": "4000 Essential English Words Vol. 5",
                "meaning": "to be very near, next to, or touching another building, room, or area",
                "example": "My house does not adjoin any other properties in the neighborhood.",
                "clozeText": "My house does not {{c1::adjoin::verb — sát vách}} any other properties in the neighborhood.",
                "collocations": [
                        "adjoin a building - tiếp giáp một tòa nhà",
                        "directly adjoin - tiếp giáp trực tiếp"
                ],
                "bidirectional": true,
                "interval": 0,
                "ease": 250,
                "reps": 0,
                "state": "new",
                "meaningVi": "sát vách, tiếp giáp, nằm ngay bên cạnh",
                "definitionEn": "to be very near, next to, or touching another building, room, or area",
                "lapses": 0
        },
        {
                "id": "sr-unit02-04",
                "category": "vocabulary",
                "deck": "English Vocabulary",
                "language": "en",
                "term": "ample",
                "pos": "adj",
                "phonetic": "/ˈæm.pəl/",
                "level": "C1",
                "levelSource": "4000 Essential English Words Vol. 5",
                "meaning": "enough or more than enough; plentiful and generous in scope",
                "example": "Due to poor time management, I do not have ample time to complete my course assignments.",
                "clozeText": "Due to poor time management, I do not have {{c1::ample::adj — dư dả}} time to complete my course assignments.",
                "collocations": [
                        "ample time - thời gian dư dả",
                        "ample opportunity - cơ hội rộng mở"
                ],
                "bidirectional": true,
                "interval": 0,
                "ease": 250,
                "reps": 0,
                "state": "new",
                "meaningVi": "dư dả, rộng rãi, thừa đủ cho một nhu cầu cụ thể",
                "definitionEn": "enough or more than enough; plentiful and generous in scope",
                "lapses": 0
        },
        {
                "id": "sr-unit02-05",
                "category": "vocabulary",
                "deck": "English Vocabulary",
                "language": "en",
                "term": "arid",
                "pos": "adj",
                "phonetic": "/ˈær.ɪd/",
                "level": "C1",
                "levelSource": "4000 Essential English Words Vol. 5",
                "meaning": "having very little rain and therefore extremely dry and barren",
                "example": "Summer heat makes the desert even more arid than ever.",
                "clozeText": "Summer heat makes the desert even more {{c1::arid::adj — khô cằn}} than ever.",
                "collocations": [
                        "arid climate - khí hậu khô cằn",
                        "arid region - vùng khô cằn"
                ],
                "bidirectional": true,
                "interval": 0,
                "ease": 250,
                "reps": 0,
                "state": "new",
                "meaningVi": "khô cằn, hoang vu (khí hậu hoặc đất đai vô cùng khô do rất ít mưa)",
                "definitionEn": "having very little rain and therefore extremely dry and barren",
                "lapses": 0
        },
        {
                "id": "sr-unit02-06",
                "category": "vocabulary",
                "deck": "English Vocabulary",
                "language": "en",
                "term": "deprive",
                "pos": "verb",
                "phonetic": "/dɪˈpraɪv/",
                "level": "C1",
                "levelSource": "4000 Essential English Words Vol. 5",
                "meaning": "to take something important or necessary away from someone",
                "example": "Her tedious job would deprive her of any enjoyment in life.",
                "clozeText": "Her tedious job would {{c1::deprive::verb — tước đoạt}} her of any enjoyment in life.",
                "collocations": [
                        "deprive somebody of something - tước đoạt cái gì của ai",
                        "sleep deprived - bị thiếu ngủ"
                ],
                "bidirectional": true,
                "interval": 0,
                "ease": 250,
                "reps": 0,
                "state": "new",
                "meaningVi": "tước đoạt, lấy đi, không cho ai hưởng cái gì thiết yếu",
                "definitionEn": "to take something important or necessary away from someone",
                "lapses": 0
        },
        {
                "id": "sr-unit02-07",
                "category": "vocabulary",
                "deck": "English Vocabulary",
                "language": "en",
                "term": "drought",
                "pos": "noun",
                "phonetic": "/draʊt/",
                "level": "B2",
                "levelSource": "4000 Essential English Words Vol. 5",
                "meaning": "a long period when there is little or no rain, causing water shortages",
                "example": "The drought in Vietnam usually lasts for three months, from March to June.",
                "clozeText": "The {{c1::drought::noun — hạn hán}} in Vietnam usually lasts for three months, from March to June.",
                "collocations": [
                        "severe drought - hạn hán nghiêm trọng",
                        "drought-stricken - bị hạn hán tàn phá"
                ],
                "bidirectional": true,
                "interval": 0,
                "ease": 250,
                "reps": 0,
                "state": "new",
                "meaningVi": "trận hạn hán, tình trạng khô hạn kéo dài",
                "definitionEn": "a long period when there is little or no rain, causing water shortages",
                "lapses": 0
        },
        {
                "id": "sr-unit02-08",
                "category": "vocabulary",
                "deck": "English Vocabulary",
                "language": "en",
                "term": "eligible",
                "pos": "adj",
                "phonetic": "/ˈel.ɪ.dʒə.bəl/",
                "level": "B2",
                "levelSource": "4000 Essential English Words Vol. 5",
                "meaning": "having the necessary qualifications or meeting the conditions to do or receive something",
                "example": "Those who bought tickets are eligible to enter the venue.",
                "clozeText": "Those who bought tickets are {{c1::eligible::adj — đủ điều kiện}} to enter the venue.",
                "collocations": [
                        "eligible for something - đủ điều kiện hưởng cái gì",
                        "eligible to do something - đủ điều kiện làm gì"
                ],
                "bidirectional": true,
                "interval": 0,
                "ease": 250,
                "reps": 0,
                "state": "new",
                "meaningVi": "đủ điều kiện, đủ tư cách, hợp pháp (theo quy định)",
                "definitionEn": "having the necessary qualifications or meeting the conditions to do or receive something",
                "lapses": 0
        },
        {
                "id": "sr-unit02-09",
                "category": "vocabulary",
                "deck": "English Vocabulary",
                "language": "en",
                "term": "fast",
                "pos": "verb",
                "phonetic": "/fæst/",
                "level": "B2",
                "levelSource": "4000 Essential English Words Vol. 5",
                "meaning": "to eat no food for a period of time, often for religious or health reasons",
                "example": "Sometimes I decide to fast for a day to feel less guilty about overeating.",
                "clozeText": "Sometimes I decide to {{c1::fast::verb — nhịn ăn}} for a day to feel less guilty about overeating.",
                "collocations": [
                        "fast for a day - nhịn ăn một ngày",
                        "intermittent fasting - nhịn ăn gián đoạn"
                ],
                "bidirectional": true,
                "interval": 0,
                "ease": 250,
                "reps": 0,
                "state": "new",
                "meaningVi": "nhịn ăn, ăn chay (trong một khoảng thời gian)",
                "definitionEn": "to eat no food for a period of time, often for religious or health reasons",
                "lapses": 0
        },
        {
                "id": "sr-unit02-10",
                "category": "vocabulary",
                "deck": "English Vocabulary",
                "language": "en",
                "term": "grumble",
                "pos": "verb",
                "phonetic": "/ˈɡrʌm.bəl/",
                "level": "C1",
                "levelSource": "4000 Essential English Words Vol. 5",
                "meaning": "to complain about someone or something in a bad-tempered or low voice",
                "example": "Every morning, I grumble about getting up early and going to work.",
                "clozeText": "Every morning, I {{c1::grumble::verb — càu nhàu}} about getting up early and going to work.",
                "collocations": [
                        "grumble about something - càu nhàu về điều gì",
                        "grumble constantly - càu nhàu liên tục"
                ],
                "bidirectional": true,
                "interval": 0,
                "ease": 250,
                "reps": 0,
                "state": "new",
                "meaningVi": "càu nhàu, lầm bầm phàn nàn (trong miệng hoặc với giọng bực bội)",
                "definitionEn": "to complain about someone or something in a bad-tempered or low voice",
                "lapses": 0
        },
        {
                "id": "sr-unit02-11",
                "category": "vocabulary",
                "deck": "English Vocabulary",
                "language": "en",
                "term": "inland",
                "pos": "adv",
                "phonetic": "/ˈɪn.lənd/",
                "level": "B2",
                "levelSource": "4000 Essential English Words Vol. 5",
                "meaning": "in or toward the interior of a country, away from the coast",
                "example": "The storm is moving inland, threatening severe destruction to lives and property.",
                "clozeText": "The storm is moving {{c1::inland::adv — vào nội địa}}, threatening severe destruction to lives and property.",
                "collocations": [
                        "move inland - di chuyển vào đất liền",
                        "inland area - khu vực nội địa"
                ],
                "bidirectional": true,
                "interval": 0,
                "ease": 250,
                "reps": 0,
                "state": "new",
                "meaningVi": "vào nội địa, vào trong đất liền, hướng về vùng nội địa",
                "definitionEn": "in or toward the interior of a country, away from the coast",
                "lapses": 0
        },
        {
                "id": "sr-unit02-12",
                "category": "vocabulary",
                "deck": "English Vocabulary",
                "language": "en",
                "term": "moisture",
                "pos": "noun",
                "phonetic": "/ˈmɔɪs.tʃər/",
                "level": "B2",
                "levelSource": "4000 Essential English Words Vol. 5",
                "meaning": "very small drops of water present in the air, on a surface, or in the ground",
                "example": "Some couples express their affection by breathing on a window pane and drawing a heart in the moisture.",
                "clozeText": "Some couples express their affection by breathing on a window pane and drawing a heart in the {{c1::moisture::noun — hơi ẩm}}.",
                "collocations": [
                        "retain moisture - giữ ẩm",
                        "moisture content - hàm lượng độ ẩm"
                ],
                "bidirectional": true,
                "interval": 0,
                "ease": 250,
                "reps": 0,
                "state": "new",
                "meaningVi": "hơi ẩm, độ ẩm (giọt nước nhỏ đọng lại trong không khí hoặc trên bề mặt)",
                "definitionEn": "very small drops of water present in the air, on a surface, or in the ground",
                "lapses": 0
        },
        {
                "id": "sr-unit02-13",
                "category": "vocabulary",
                "deck": "English Vocabulary",
                "language": "en",
                "term": "nonetheless",
                "pos": "adv",
                "phonetic": "/ˌnʌn.ðəˈles/",
                "level": "C1",
                "levelSource": "4000 Essential English Words Vol. 5",
                "meaning": "despite what has just been said; nevertheless",
                "example": "His life is gruelling; nonetheless, he still pushes forward with resolute effort.",
                "clozeText": "His life is gruelling; {{c1::nonetheless::adv — tuy nhiên}}, he still pushes forward with resolute effort.",
                "collocations": [
                        "nonetheless important - tuy vậy vẫn quan trọng",
                        "but nonetheless - nhưng dù sao thì"
                ],
                "bidirectional": true,
                "interval": 0,
                "ease": 250,
                "reps": 0,
                "state": "new",
                "meaningVi": "tuy nhiên, dù sao thì, mặc dù vậy",
                "definitionEn": "despite what has just been said; nevertheless",
                "lapses": 0
        },
        {
                "id": "sr-unit02-14",
                "category": "vocabulary",
                "deck": "English Vocabulary",
                "language": "en",
                "term": "oath",
                "pos": "noun",
                "phonetic": "/əʊθ/",
                "level": "C1",
                "levelSource": "4000 Essential English Words Vol. 5",
                "meaning": "a formal and solemn promise, especially to tell the truth or fulfill a duty",
                "example": "Medical students must swear the Hippocratic oath to dedicate their lives to healing others.",
                "clozeText": "Medical students must swear the Hippocratic {{c1::oath::noun — lời tuyên thệ}} to dedicate their lives to healing others.",
                "collocations": [
                        "take an oath - tuyên thệ",
                        "under oath - dưới lời tuyên thệ"
                ],
                "bidirectional": true,
                "interval": 0,
                "ease": 250,
                "reps": 0,
                "state": "new",
                "meaningVi": "lời thề, lời tuyên thệ trang trọng",
                "definitionEn": "a formal and solemn promise, especially to tell the truth or fulfill a duty",
                "lapses": 0
        },
        {
                "id": "sr-unit02-15",
                "category": "vocabulary",
                "deck": "English Vocabulary",
                "language": "en",
                "term": "prairie",
                "pos": "noun",
                "phonetic": "/ˈpreə.ri/",
                "level": "C2",
                "levelSource": "4000 Essential English Words Vol. 5",
                "meaning": "a wide, flat, treeless area of grassland, especially in North America",
                "example": "Vietnam does not have any vast prairie as it is situated in a tropical climate region.",
                "clozeText": "Vietnam does not have any vast {{c1::prairie::noun — thảo nguyên}} as it is situated in a tropical climate region.",
                "collocations": [
                        "vast prairie - thảo nguyên bao la",
                        "prairie ecosystem - hệ sinh thái thảo nguyên"
                ],
                "bidirectional": true,
                "interval": 0,
                "ease": 250,
                "reps": 0,
                "state": "new",
                "meaningVi": "thảo nguyên, đồng cỏ rộng lớn",
                "definitionEn": "a wide, flat, treeless area of grassland, especially in North America",
                "lapses": 0
        },
        {
                "id": "sr-unit02-16",
                "category": "vocabulary",
                "deck": "English Vocabulary",
                "language": "en",
                "term": "ragged",
                "pos": "adj",
                "phonetic": "/ˈræɡ.ɪd/",
                "level": "C1",
                "levelSource": "4000 Essential English Words Vol. 5",
                "meaning": "(of clothes or fabric) old, torn, and in poor condition",
                "example": "My clothes are ragged, yet I still spend most of my money on video games.",
                "clozeText": "My clothes are {{c1::ragged::adj — rách rưới}}, yet I still spend most of my money on video games.",
                "collocations": [
                        "ragged clothes - quần áo rách rưới",
                        "ragged edge - mép nham nhở"
                ],
                "bidirectional": true,
                "interval": 0,
                "ease": 250,
                "reps": 0,
                "state": "new",
                "meaningVi": "rách rưới, tả tơi, cũ nát (dùng cho quần áo, vải vóc)",
                "definitionEn": "(of clothes or fabric) old, torn, and in poor condition",
                "lapses": 0
        },
        {
                "id": "sr-unit02-17",
                "category": "vocabulary",
                "deck": "English Vocabulary",
                "language": "en",
                "term": "rugged",
                "pos": "adj",
                "phonetic": "/ˈrʌɡ.ɪd/",
                "level": "C1",
                "levelSource": "4000 Essential English Words Vol. 5",
                "meaning": "(of land or terrain) rocky, uneven, and difficult to travel over",
                "example": "Teachers in mountainous areas must travel on rugged roads to inspire their students.",
                "clozeText": "Teachers in mountainous areas must travel on {{c1::rugged::adj — gồ ghề}} roads to inspire their students.",
                "collocations": [
                        "rugged terrain - địa hình hiểm trở",
                        "rugged coastline - bờ biển gồ ghề"
                ],
                "bidirectional": true,
                "interval": 0,
                "ease": 250,
                "reps": 0,
                "state": "new",
                "meaningVi": "gồ ghề, lởm chởm, hiểm trở (địa hình khó di chuyển)",
                "definitionEn": "(of land or terrain) rocky, uneven, and difficult to travel over",
                "lapses": 0
        },
        {
                "id": "sr-unit02-18",
                "category": "vocabulary",
                "deck": "English Vocabulary",
                "language": "en",
                "term": "scarce",
                "pos": "adj",
                "phonetic": "/skeəs/",
                "level": "C1",
                "levelSource": "4000 Essential English Words Vol. 5",
                "meaning": "not easy to find or obtain; existing in insufficient quantity",
                "example": "Due to the conflict, gasoline has become scarce as imports have dropped sharply.",
                "clozeText": "Due to the conflict, gasoline has become {{c1::scarce::adj — khan hiếm}} as imports have dropped sharply.",
                "collocations": [
                        "scarce resources - tài nguyên khan hiếm",
                        "make oneself scarce - lén rút lui, chuồn mất"
                ],
                "bidirectional": true,
                "interval": 0,
                "ease": 250,
                "reps": 0,
                "state": "new",
                "meaningVi": "khan hiếm, ít ỏi, không đủ cho nhu cầu",
                "definitionEn": "not easy to find or obtain; existing in insufficient quantity",
                "lapses": 0
        },
        {
                "id": "sr-unit02-19",
                "category": "vocabulary",
                "deck": "English Vocabulary",
                "language": "en",
                "term": "speculate",
                "pos": "verb",
                "phonetic": "/ˈspek.jə.leɪt/",
                "level": "C1",
                "levelSource": "4000 Essential English Words Vol. 5",
                "meaning": "to form opinions or guesses about something without having complete evidence",
                "example": "Some exam questions are extremely challenging, forcing me to speculate before time runs out.",
                "clozeText": "Some exam questions are extremely challenging, forcing me to {{c1::speculate::verb — suy đoán}} before time runs out.",
                "collocations": [
                        "speculate about something - suy đoán về điều gì",
                        "wildly speculate - suy đoán vô căn cứ"
                ],
                "bidirectional": true,
                "interval": 0,
                "ease": 250,
                "reps": 0,
                "state": "new",
                "meaningVi": "suy đoán, đoán mò, đưa ra giả định khi chưa có bằng chứng chắc chắn",
                "definitionEn": "to form opinions or guesses about something without having complete evidence",
                "lapses": 0
        },
        {
                "id": "sr-unit03-01",
                "category": "vocabulary",
                "deck": "English Vocabulary",
                "language": "en",
                "term": "analytic",
                "pos": "adj",
                "phonetic": "/ˌæn.əˈlɪt.ɪk/",
                "level": "C1",
                "levelSource": "4000 Essential English Words Vol. 5",
                "meaning": "examining things very carefully using logical and systematic reasoning",
                "example": "The report is so analytic that it provides clear insights into complex data.",
                "clozeText": "The report is so {{c1::analytic::adj — có tính phân tích}} that it provides clear insights into complex data.",
                "collocations": [
                        "analytical depth - độ sâu phân tích",
                        "analytical mindset - tư duy phân tích"
                ],
                "bidirectional": true,
                "interval": 0,
                "ease": 250,
                "reps": 0,
                "state": "new",
                "meaningVi": "có tính phân tích, sử dụng phương pháp phân tích suy luận",
                "definitionEn": "examining things very carefully using logical and systematic reasoning",
                "lapses": 0
        },
        {
                "id": "sr-unit03-02",
                "category": "vocabulary",
                "deck": "English Vocabulary",
                "language": "en",
                "term": "assert",
                "pos": "verb",
                "phonetic": "/əˈsɜːt/",
                "level": "C1",
                "levelSource": "4000 Essential English Words Vol. 5",
                "meaning": "to state clearly and firmly that something is true",
                "example": "After having assert that the Earth was flat, he felt deeply humiliated.",
                "clozeText": "After having {{c1::assert::verb — khẳng định}} that the Earth was flat, he felt deeply humiliated.",
                "collocations": [
                        "assert authority - khẳng định quyền lực",
                        "boldly assert - dũng cảm khẳng định"
                ],
                "bidirectional": true,
                "interval": 0,
                "ease": 250,
                "reps": 0,
                "state": "new",
                "meaningVi": "khẳng định, quả quyết, tuyên bố chắc chắn",
                "definitionEn": "to state clearly and firmly that something is true",
                "lapses": 0
        },
        {
                "id": "sr-unit03-03",
                "category": "vocabulary",
                "deck": "English Vocabulary",
                "language": "en",
                "term": "bachelor",
                "pos": "noun",
                "phonetic": "/ˈbætʃ.əl.ər/",
                "level": "B2",
                "levelSource": "4000 Essential English Words Vol. 5",
                "meaning": "an unmarried man; or a person who holds a first university degree",
                "example": "After remaining a bachelor into his late twenties, Tom finally settled down with a loving partner.",
                "clozeText": "After remaining a {{c1::bachelor::noun — người độc thân}} into his late twenties, Tom finally settled down with a loving partner.",
                "collocations": [
                        "eligible bachelor - người độc thân sáng giá",
                        "remain a bachelor - giữ tình trạng độc thân"
                ],
                "bidirectional": true,
                "interval": 0,
                "ease": 250,
                "reps": 0,
                "state": "new",
                "meaningVi": "người đàn ông chưa vợ, người độc thân; bằng cử nhân",
                "definitionEn": "an unmarried man; or a person who holds a first university degree",
                "lapses": 0
        },
        {
                "id": "sr-unit03-04",
                "category": "vocabulary",
                "deck": "English Vocabulary",
                "language": "en",
                "term": "calculus",
                "pos": "noun",
                "phonetic": "/ˈkæl.kjə.ləs/",
                "level": "C2",
                "levelSource": "4000 Essential English Words Vol. 5",
                "meaning": "a branch of mathematics that deals with rates of change and continuous quantities",
                "example": "Majoring in English allowed me to avoid calculus, a subject I always struggled with.",
                "clozeText": "Majoring in English allowed me to avoid {{c1::calculus::noun — môn giải tích}}, a subject I always struggled with.",
                "collocations": [
                        "differential calculus - giải tích vi phân",
                        "grasp calculus - hiểu/nắm vững giải tích"
                ],
                "bidirectional": true,
                "interval": 0,
                "ease": 250,
                "reps": 0,
                "state": "new",
                "meaningVi": "môn giải tích, phép tính giải tích (phân nhánh toán học nghiên cứu sự thay đổi)",
                "definitionEn": "a branch of mathematics that deals with rates of change and continuous quantities",
                "lapses": 0
        },
        {
                "id": "sr-unit03-05",
                "category": "vocabulary",
                "deck": "English Vocabulary",
                "language": "en",
                "term": "celestial",
                "pos": "adj",
                "phonetic": "/səˈles.ti.əl/",
                "level": "C2",
                "levelSource": "4000 Essential English Words Vol. 5",
                "meaning": "of or relating to the sky, heaven, or outer space",
                "example": "Scientists fear that a massive celestial body colliding with Earth could wipe out all life.",
                "clozeText": "Scientists fear that a massive {{c1::celestial::adj — thuộc vũ trụ}} body colliding with Earth could wipe out all life.",
                "collocations": [
                        "celestial body - thiên thể",
                        "celestial navigation - dẫn đường bằng thiên văn"
                ],
                "bidirectional": true,
                "interval": 0,
                "ease": 250,
                "reps": 0,
                "state": "new",
                "meaningVi": "thuộc vũ trụ, thuộc về bầu trời, thuộc về vũ trụ",
                "definitionEn": "of or relating to the sky, heaven, or outer space",
                "lapses": 0
        },
        {
                "id": "sr-unit03-06",
                "category": "vocabulary",
                "deck": "English Vocabulary",
                "language": "en",
                "term": "cognitive",
                "pos": "adj",
                "phonetic": "/ˈkɒɡ.nə.tɪv/",
                "level": "C1",
                "levelSource": "4000 Essential English Words Vol. 5",
                "meaning": "connected with mental processes of understanding, thinking, and learning",
                "example": "Decision-making is a complex cognitive process that occurs before one forms a final opinion.",
                "clozeText": "Decision-making is a complex {{c1::cognitive::adj — thuộc về nhận thức}} process that occurs before one forms a final opinion.",
                "collocations": [
                        "cognitive process - tiến trình nhận thức",
                        "cognitive impairment - suy giảm nhận thức"
                ],
                "bidirectional": true,
                "interval": 0,
                "ease": 250,
                "reps": 0,
                "state": "new",
                "meaningVi": "thuộc về nhận thức, liên quan đến tư duy và trí tuệ",
                "definitionEn": "connected with mental processes of understanding, thinking, and learning",
                "lapses": 0
        },
        {
                "id": "sr-unit03-07",
                "category": "vocabulary",
                "deck": "English Vocabulary",
                "language": "en",
                "term": "collision",
                "pos": "noun",
                "phonetic": "/kəˈlɪʒ.ən/",
                "level": "B2",
                "levelSource": "4000 Essential English Words Vol. 5",
                "meaning": "an accident or event in which two or more objects or vehicles crash into each other",
                "example": "A catastrophic mid-air collision occurred due to miscommunication with air traffic control.",
                "clozeText": "A catastrophic mid-air {{c1::collision::noun — vụ va chạm}} occurred due to miscommunication with air traffic control.",
                "collocations": [
                        "mid-air collision - va chạm trên không",
                        "head-on collision - va chạm trực diện"
                ],
                "bidirectional": true,
                "interval": 0,
                "ease": 250,
                "reps": 0,
                "state": "new",
                "meaningVi": "vụ va chạm, sự đụng độ giữa các phương tiện",
                "definitionEn": "an accident or event in which two or more objects or vehicles crash into each other",
                "lapses": 0
        },
        {
                "id": "sr-unit03-08",
                "category": "vocabulary",
                "deck": "English Vocabulary",
                "language": "en",
                "term": "competent",
                "pos": "adj",
                "phonetic": "/ˈkɒm.pɪ.tənt/",
                "level": "C1",
                "levelSource": "4000 Essential English Words Vol. 5",
                "meaning": "able to do something well and effectively; having the required skill",
                "example": "She is highly competent, earning admission to one of the most prestigious universities.",
                "clozeText": "She is highly {{c1::competent::adj — có năng lực}}, earning admission to one of the most prestigious universities.",
                "collocations": [
                        "highly competent - rất có năng lực",
                        "academically competent - có năng lực học thuật"
                ],
                "bidirectional": true,
                "interval": 0,
                "ease": 250,
                "reps": 0,
                "state": "new",
                "meaningVi": "có năng lực, thành thạo, đủ khả năng làm tốt nhiệm vụ",
                "definitionEn": "able to do something well and effectively; having the required skill",
                "lapses": 0
        },
        {
                "id": "sr-unit03-09",
                "category": "vocabulary",
                "deck": "English Vocabulary",
                "language": "en",
                "term": "diploma",
                "pos": "noun",
                "phonetic": "/dɪˈpləʊ.mə/",
                "level": "B1",
                "levelSource": "4000 Essential English Words Vol. 5",
                "meaning": "an official document certifying that someone has completed a course of study",
                "example": "After obtaining my diploma, I felt aimless due to the lack of a clear career plan.",
                "clozeText": "After obtaining my {{c1::diploma::noun — bằng cấp}}, I felt aimless due to the lack of a clear career plan.",
                "collocations": [
                        "obtain a diploma - nhận/lấy bằng",
                        "high school diploma - bằng tốt nghiệp trung học"
                ],
                "bidirectional": true,
                "interval": 0,
                "ease": 250,
                "reps": 0,
                "state": "new",
                "meaningVi": "bằng cấp, chứng chỉ (do trường phổ thông hoặc cao đẳng/đại học cấp)",
                "definitionEn": "an official document certifying that someone has completed a course of study",
                "lapses": 0
        },
        {
                "id": "sr-unit03-10",
                "category": "vocabulary",
                "deck": "English Vocabulary",
                "language": "en",
                "term": "excel",
                "pos": "verb",
                "phonetic": "/ɪkˈsel/",
                "level": "C1",
                "levelSource": "4000 Essential English Words Vol. 5",
                "meaning": "to be extremely good at doing something or to surpass others",
                "example": "My parents excel at public speaking, captivating audiences for hours without fatigue.",
                "clozeText": "My parents {{c1::excel::verb — cực kỳ giỏi}} at public speaking, captivating audiences for hours without fatigue.",
                "collocations": [
                        "excel in/at - xuất sắc về",
                        "excel academically - học tập xuất sắc"
                ],
                "bidirectional": true,
                "interval": 0,
                "ease": 250,
                "reps": 0,
                "state": "new",
                "meaningVi": "cực kỳ giỏi, xuất sắc trong một lĩnh vực cụ thể",
                "definitionEn": "to be extremely good at doing something or to surpass others",
                "lapses": 0
        },
        {
                "id": "sr-unit03-11",
                "category": "vocabulary",
                "deck": "English Vocabulary",
                "language": "en",
                "term": "geology",
                "pos": "noun",
                "phonetic": "/dʒiˈɒl.ə.dʒi/",
                "level": "B2",
                "levelSource": "4000 Essential English Words Vol. 5",
                "meaning": "the scientific study of the Earth's physical structure, rocks, and history",
                "example": "In my view, geology seems tedious because it revolves primarily around analyzing rock formations.",
                "clozeText": "In my view, {{c1::geology::noun — ngành địa chất học}} seems tedious because it revolves primarily around analyzing rock formations.",
                "collocations": [
                        "field of geology - lĩnh vực địa chất",
                        "structural geology - địa chất cấu tạo"
                ],
                "bidirectional": true,
                "interval": 0,
                "ease": 250,
                "reps": 0,
                "state": "new",
                "meaningVi": "ngành địa chất học (nghiên cứu cấu trúc và lịch sử Trái Đất)",
                "definitionEn": "the scientific study of the Earth's physical structure, rocks, and history",
                "lapses": 0
        },
        {
                "id": "sr-unit03-12",
                "category": "vocabulary",
                "deck": "English Vocabulary",
                "language": "en",
                "term": "harness",
                "pos": "verb",
                "phonetic": "/ˈhɑː.nəs/",
                "level": "C1",
                "levelSource": "4000 Essential English Words Vol. 5",
                "meaning": "to control and use the force or strength of something to produce power or achieve a result",
                "example": "The hydroelectric dam harness the power of water to generate electricity for nearby cities.",
                "clozeText": "The hydroelectric dam {{c1::harness::verb — khai thác}} the power of water to generate electricity for nearby cities.",
                "collocations": [
                        "harness energy - khai thác năng lượng",
                        "harness natural resources - khai thác tài nguyên thiên nhiên"
                ],
                "bidirectional": true,
                "interval": 0,
                "ease": 250,
                "reps": 0,
                "state": "new",
                "meaningVi": "khai thác, tận dụng (nguồn năng lượng, sức mạnh)",
                "definitionEn": "to control and use the force or strength of something to produce power or achieve a result",
                "lapses": 0
        },
        {
                "id": "sr-unit03-13",
                "category": "vocabulary",
                "deck": "English Vocabulary",
                "language": "en",
                "term": "intellect",
                "pos": "noun",
                "phonetic": "/ˈɪn.təl.ekt/",
                "level": "C1",
                "levelSource": "4000 Essential English Words Vol. 5",
                "meaning": "the ability to think logically, understand complex ideas, and reason at a high level",
                "example": "Dolphins possess a remarkable intellect, enabling them to communicate in sophisticated ways.",
                "clozeText": "Dolphins possess a remarkable {{c1::intellect::noun — trí tuệ}}, enabling them to communicate in sophisticated ways.",
                "collocations": [
                        "remarkable intellect - trí tuệ phi thường",
                        "keen intellect - trí tuệ sắc sảo"
                ],
                "bidirectional": true,
                "interval": 0,
                "ease": 250,
                "reps": 0,
                "state": "new",
                "meaningVi": "trí tuệ, khả năng tư duy và hiểu biết cấp cao",
                "definitionEn": "the ability to think logically, understand complex ideas, and reason at a high level",
                "lapses": 0
        },
        {
                "id": "sr-unit03-14",
                "category": "vocabulary",
                "deck": "English Vocabulary",
                "language": "en",
                "term": "keen",
                "pos": "adj",
                "phonetic": "/kiːn/",
                "level": "C1",
                "levelSource": "4000 Essential English Words Vol. 5",
                "meaning": "very interested, eager, or enthusiastic; or having a sharp mind or edge",
                "example": "I lack the keen judgment required to make rapid decisions under pressure.",
                "clozeText": "I lack the {{c1::keen::adj — sắc sảo}} judgment required to make rapid decisions under pressure.",
                "collocations": [
                        "keen judgment - sự phán đoán sắc sảo",
                        "keen eye for detail - mắt nhìn chi tiết tinh tường"
                ],
                "bidirectional": true,
                "interval": 0,
                "ease": 250,
                "reps": 0,
                "state": "new",
                "meaningVi": "sắc sảo, nhạy bén, tinh tường",
                "definitionEn": "very interested, eager, or enthusiastic; or having a sharp mind or edge",
                "lapses": 0
        },
        {
                "id": "sr-unit03-15",
                "category": "vocabulary",
                "deck": "English Vocabulary",
                "language": "en",
                "term": "mythology",
                "pos": "noun",
                "phonetic": "/mɪˈθɒl.ə.dʒi/",
                "level": "B2",
                "levelSource": "4000 Essential English Words Vol. 5",
                "meaning": "a collection of traditional stories and myths belonging to a particular culture",
                "example": "I enjoy studying global mythology, as every culture embeds its core values within its legends.",
                "clozeText": "I enjoy studying global {{c1::mythology::noun — thần thoại học}}, as every culture embeds its core values within its legends.",
                "collocations": [
                        "classical mythology - thần thoại cổ điển",
                        "Norse mythology - thần thoại Bắc Âu"
                ],
                "bidirectional": true,
                "interval": 0,
                "ease": 250,
                "reps": 0,
                "state": "new",
                "meaningVi": "thần thoại học, thần thoại, hệ thống truyền thuyết thần thoại",
                "definitionEn": "a collection of traditional stories and myths belonging to a particular culture",
                "lapses": 0
        },
        {
                "id": "sr-unit03-16",
                "category": "vocabulary",
                "deck": "English Vocabulary",
                "language": "en",
                "term": "physiology",
                "pos": "noun",
                "phonetic": "/ˌfɪz.iˈɒl.ə.dʒi/",
                "level": "C1",
                "levelSource": "4000 Essential English Words Vol. 5",
                "meaning": "the scientific study of how living organisms and their body parts function",
                "example": "I didn't fully grasp human physiology until I had the opportunity to attend the medical conference.",
                "clozeText": "I didn't fully grasp human {{c1::physiology::noun — ngành sinh lý học}} until I had the opportunity to attend the medical conference.",
                "collocations": [
                        "human physiology - sinh lý học con người",
                        "principles of physiology - các nguyên lý sinh lý học"
                ],
                "bidirectional": true,
                "interval": 0,
                "ease": 250,
                "reps": 0,
                "state": "new",
                "meaningVi": "ngành sinh lý học (nghiên cứu chức năng hoạt động của cơ thể sống)",
                "definitionEn": "the scientific study of how living organisms and their body parts function",
                "lapses": 0
        },
        {
                "id": "sr-unit03-17",
                "category": "vocabulary",
                "deck": "English Vocabulary",
                "language": "en",
                "term": "radioactive",
                "pos": "adj",
                "phonetic": "/ˌreɪ.di.əʊˈæk.tɪv/",
                "level": "B2",
                "levelSource": "4000 Essential English Words Vol. 5",
                "meaning": "sending out harmful radiation caused when atomic nuclei break up",
                "example": "The explosion released highly radioactive fallout, leaving the area contaminated decades later.",
                "clozeText": "The explosion released highly {{c1::radioactive::adj — có tính phóng xạ}} fallout, leaving the area contaminated decades later.",
                "collocations": [
                        "radioactive fallout - bụi phóng xạ",
                        "radioactive waste - rác thải phóng xạ"
                ],
                "bidirectional": true,
                "interval": 0,
                "ease": 250,
                "reps": 0,
                "state": "new",
                "meaningVi": "có tính phóng xạ, phát ra tia phóng xạ độc hại",
                "definitionEn": "sending out harmful radiation caused when atomic nuclei break up",
                "lapses": 0
        },
        {
                "id": "sr-unit03-18",
                "category": "vocabulary",
                "deck": "English Vocabulary",
                "language": "en",
                "term": "relativity",
                "pos": "noun",
                "phonetic": "/ˌrel.əˈtɪv.ə.ti/",
                "level": "C1",
                "levelSource": "4000 Essential English Words Vol. 5",
                "meaning": "the physics theory that space and time are relative to the observer's motion",
                "example": "Albert Einstein formulated the theory of relativity, which became a cornerstone of modern science.",
                "clozeText": "Albert Einstein formulated the theory of {{c1::relativity::noun — thuyết tương đối}}, which became a cornerstone of modern science.",
                "collocations": [
                        "theory of relativity - thuyết tương đối",
                        "general relativity - thuyết tương đối tổng quát"
                ],
                "bidirectional": true,
                "interval": 0,
                "ease": 250,
                "reps": 0,
                "state": "new",
                "meaningVi": "thuyết tương đối (vật lý học)",
                "definitionEn": "the physics theory that space and time are relative to the observer's motion",
                "lapses": 0
        },
        {
                "id": "sr-unit03-19",
                "category": "vocabulary",
                "deck": "English Vocabulary",
                "language": "en",
                "term": "sociology",
                "pos": "noun",
                "phonetic": "/ˌsəʊ.siˈɒl.ə.dʒi/",
                "level": "B2",
                "levelSource": "4000 Essential English Words Vol. 5",
                "meaning": "the scientific study of human society, social relationships, and institutions",
                "example": "Although sociology is a social science, it plays a critical role in understanding human behavior.",
                "clozeText": "Although {{c1::sociology::noun — ngành xã hội học}} is a social science, it plays a critical role in understanding human behavior.",
                "collocations": [
                        "field of sociology - lĩnh vực xã hội học",
                        "urban sociology - xã hội học đô thị"
                ],
                "bidirectional": true,
                "interval": 0,
                "ease": 250,
                "reps": 0,
                "state": "new",
                "meaningVi": "ngành xã hội học (nghiên cứu sự phát triển và hành vi xã hội)",
                "definitionEn": "the scientific study of human society, social relationships, and institutions",
                "lapses": 0
        },
        {
                "id": "sr-unit03-20",
                "category": "vocabulary",
                "deck": "English Vocabulary",
                "language": "en",
                "term": "theoretical",
                "pos": "adj",
                "phonetic": "/ˌθɪəˈret.ɪ.kəl/",
                "level": "C1",
                "levelSource": "4000 Essential English Words Vol. 5",
                "meaning": "based on theories and ideas rather than practical experiments or experience",
                "example": "My entire proposal remains purely theoretical because I have not had the opportunity to put it into practice.",
                "clozeText": "My entire proposal remains purely {{c1::theoretical::adj — thuộc về lý thuyết}} because I have not had the opportunity to put it into practice.",
                "collocations": [
                        "purely theoretical - hoàn toàn mang tính lý thuyết",
                        "theoretical framework - khung lý thuyết"
                ],
                "bidirectional": true,
                "interval": 0,
                "ease": 250,
                "reps": 0,
                "state": "new",
                "meaningVi": "thuộc về lý thuyết, dựa trên lý thuyết hơn là thực hành",
                "definitionEn": "based on theories and ideas rather than practical experiments or experience",
                "lapses": 0
        },
        {
                "id": "sr-unit04-01",
                "category": "vocabulary",
                "deck": "English Vocabulary",
                "language": "en",
                "term": "administrator",
                "pos": "noun",
                "phonetic": "/ədˈmɪn.ɪ.streɪ.tər/",
                "level": "C1",
                "levelSource": "4000 Essential English Words Vol. 5",
                "meaning": "a person whose job is to manage and organize the affairs of a business or institution",
                "example": "The board hired a skilled administrator to oversee daily campus operations.",
                "clozeText": "The board hired a skilled {{c1::administrator::noun — người quản lý}} to oversee daily campus operations.",
                "collocations": [
                        "system administrator - quản trị viên hệ thống",
                        "hospital administrator - người quản lý bệnh viện"
                ],
                "bidirectional": true,
                "interval": 0,
                "ease": 250,
                "reps": 0,
                "state": "new",
                "meaningVi": "Người quản lý, người điều hành hoặc quản trị viên kiểm soát một tổ chức, công ty hay cơ quan.",
                "definitionEn": "a person whose job is to manage and organize the affairs of a business or institution",
                "lapses": 0
        },
        {
                "id": "sr-unit04-02",
                "category": "vocabulary",
                "deck": "English Vocabulary",
                "language": "en",
                "term": "affluent",
                "pos": "adj",
                "phonetic": "/ˈæf.lu.ənt/",
                "level": "C1",
                "levelSource": "4000 Essential English Words Vol. 5",
                "meaning": "having a great deal of money, wealth, and a high standard of living",
                "example": "They moved into an affluent neighborhood filled with private estates and luxury cars.",
                "clozeText": "They moved into an {{c1::affluent::adj — giàu có}} neighborhood filled with private estates and luxury cars.",
                "collocations": [
                        "affluent society - xã hội giàu có",
                        "affluent lifestyle - lối sống thượng lưu"
                ],
                "bidirectional": true,
                "interval": 0,
                "ease": 250,
                "reps": 0,
                "state": "new",
                "meaningVi": "Giàu có, thịnh vượng, có nhiều tiền bạc và tài sản.",
                "definitionEn": "having a great deal of money, wealth, and a high standard of living",
                "lapses": 0
        },
        {
                "id": "sr-unit04-03",
                "category": "vocabulary",
                "deck": "English Vocabulary",
                "language": "en",
                "term": "audit",
                "pos": "verb",
                "phonetic": "/ˈɔː.dɪt/",
                "level": "B2",
                "levelSource": "4000 Essential English Words Vol. 5",
                "meaning": "to conduct an official examination of financial accounts or organizational processes",
                "example": "The tax authority decided to audit the corporation's financial records.",
                "clozeText": "The tax authority decided to {{c1::audit::verb — kiểm toán}} the corporation's financial records.",
                "collocations": [
                        "audit accounts - kiểm toán sổ sách tài khoản",
                        "conduct an audit - thực hiện kiểm toán"
                ],
                "bidirectional": true,
                "interval": 0,
                "ease": 250,
                "reps": 0,
                "state": "new",
                "meaningVi": "Kiểm toán, kiểm tra chính thức sổ sách và hồ sơ tài chính của cá nhân hay tổ chức.",
                "definitionEn": "to conduct an official examination of financial accounts or organizational processes",
                "lapses": 0
        },
        {
                "id": "sr-unit04-04",
                "category": "vocabulary",
                "deck": "English Vocabulary",
                "language": "en",
                "term": "automate",
                "pos": "verb",
                "phonetic": "/ˈɔː.tə.meɪt/",
                "level": "C1",
                "levelSource": "4000 Essential English Words Vol. 5",
                "meaning": "to use machines or computers instead of human labor to do a job or process",
                "example": "The company plans to automate assembly operations to reduce labor costs.",
                "clozeText": "The company plans to {{c1::automate::verb — tự động hóa}} assembly operations to reduce labor costs.",
                "collocations": [
                        "automate the process - tự động hóa quy trình",
                        "fully automated - hoàn toàn tự động"
                ],
                "bidirectional": true,
                "interval": 0,
                "ease": 250,
                "reps": 0,
                "state": "new",
                "meaningVi": "Tự động hóa, lắp đặt máy móc hoặc hệ thống máy tính để thực hiện công việc thay con người.",
                "definitionEn": "to use machines or computers instead of human labor to do a job or process",
                "lapses": 0
        },
        {
                "id": "sr-unit04-05",
                "category": "vocabulary",
                "deck": "English Vocabulary",
                "language": "en",
                "term": "bribe",
                "pos": "verb",
                "phonetic": "/braɪb/",
                "level": "C1",
                "levelSource": "4000 Essential English Words Vol. 5",
                "meaning": "to dishonestly give money or gifts to someone to persuade them to help you",
                "example": "The suspect attempted to bribe the officer to avoid getting arrested.",
                "clozeText": "The suspect attempted to {{c1::bribe::verb — hối lộ}} the officer to avoid getting arrested.",
                "collocations": [
                        "bribe an official - hối lộ quan chức",
                        "accept a bribe - nhận tiền hối lộ"
                ],
                "bidirectional": true,
                "interval": 0,
                "ease": 250,
                "reps": 0,
                "state": "new",
                "meaningVi": "Hối lộ, đút lót tiền hoặc lợi ích bất hợp pháp để thuyết phục ai đó giúp đỡ mình.",
                "definitionEn": "to dishonestly give money or gifts to someone to persuade them to help you",
                "lapses": 0
        },
        {
                "id": "sr-unit04-06",
                "category": "vocabulary",
                "deck": "English Vocabulary",
                "language": "en",
                "term": "corrupt",
                "pos": "adj",
                "phonetic": "/kəˈrʌpt/",
                "level": "C1",
                "levelSource": "4000 Essential English Words Vol. 5",
                "meaning": "dishonest or illegal behavior, especially by people in positions of power",
                "example": "The government promised to punish corrupt officials who took public funds.",
                "clozeText": "The government promised to punish {{c1::corrupt::adj — tham nhũng}} officials who took public funds.",
                "collocations": [
                        "corrupt official - quan chức tham nhũng",
                        "corrupt practices - các hành vi tham nhũng"
                ],
                "bidirectional": true,
                "interval": 0,
                "ease": 250,
                "reps": 0,
                "state": "new",
                "meaningVi": "Tham nhũng, tha hóa, vi phạm pháp luật hoặc đạo đức vì lợi ích tiền bạc, quyền lực.",
                "definitionEn": "dishonest or illegal behavior, especially by people in positions of power",
                "lapses": 0
        },
        {
                "id": "sr-unit04-07",
                "category": "vocabulary",
                "deck": "English Vocabulary",
                "language": "en",
                "term": "dispose",
                "pos": "verb",
                "phonetic": "/dɪˈspoʊz/",
                "level": "C1",
                "levelSource": "4000 Essential English Words Vol. 5",
                "meaning": "to get rid of something that is no longer wanted or needed",
                "example": "Factories must safely dispose of hazardous chemical waste.",
                "clozeText": "Factories must safely {{c1::dispose::verb — xử lý/vứt bỏ}} of hazardous chemical waste.",
                "collocations": [
                        "dispose of waste - xử lý/vứt bỏ rác thải",
                        "properly dispose - xử lý đúng quy cách"
                ],
                "bidirectional": true,
                "interval": 0,
                "ease": 250,
                "reps": 0,
                "state": "new",
                "meaningVi": "xử lý/vứt bỏ, Vứt bỏ, xử lý hoặc loại bỏ cái gì đó (thường đi kèm giới từ *of*).",
                "definitionEn": "to get rid of something that is no longer wanted or needed",
                "lapses": 0
        },
        {
                "id": "sr-unit04-08",
                "category": "vocabulary",
                "deck": "English Vocabulary",
                "language": "en",
                "term": "headquarters",
                "pos": "noun",
                "phonetic": "/ˈhed.kwɔː.təz/",
                "level": "B2",
                "levelSource": "4000 Essential English Words Vol. 5",
                "meaning": "the main offices of an organization where its leaders and central management work",
                "example": "The tech giant moved its international headquarters to London to expand its European operations.",
                "clozeText": "The tech giant moved its international {{c1::headquarters::noun — trụ sở chính}} to London to expand its European operations.",
                "collocations": [
                        "corporate headquarters - trụ sở chính của tập đoàn",
                        "set up headquarters - đặt trụ sở chính"
                ],
                "bidirectional": true,
                "interval": 0,
                "ease": 250,
                "reps": 0,
                "state": "new",
                "meaningVi": "Trụ sở chính, đại bản doanh của một công ty, tổ chức hoặc lực lượng quân sự.",
                "definitionEn": "the main offices of an organization where its leaders and central management work",
                "lapses": 0
        },
        {
                "id": "sr-unit04-09",
                "category": "vocabulary",
                "deck": "English Vocabulary",
                "language": "en",
                "term": "incentive",
                "pos": "noun",
                "phonetic": "/ɪnˈsen.tɪv/",
                "level": "C1",
                "levelSource": "4000 Essential English Words Vol. 5",
                "meaning": "something that encourages a person or organization to do something or work harder",
                "example": "The company offered a financial incentive to employees who met their quarterly sales targets.",
                "clozeText": "The company offered a financial {{c1::incentive::noun — sự khuyến khích, động lực}} to employees who met their quarterly sales targets.",
                "collocations": [
                        "financial incentive - động lực tài chính",
                        "provide an incentive - đưa ra động lực/sự khuyến khích"
                ],
                "bidirectional": true,
                "interval": 0,
                "ease": 250,
                "reps": 0,
                "state": "new",
                "meaningVi": "sự khuyến khích, động lực, Động lực, sự khuyến khích hoặc phần thưởng nhằm thúc đẩy ai đó làm việc gì.",
                "definitionEn": "something that encourages a person or organization to do something or work harder",
                "lapses": 0
        },
        {
                "id": "sr-unit04-10",
                "category": "vocabulary",
                "deck": "English Vocabulary",
                "language": "en",
                "term": "infrastructure",
                "pos": "noun",
                "phonetic": "/ˈɪn.frəˌstrʌk.tʃər/",
                "level": "B2",
                "levelSource": "4000 Essential English Words Vol. 5",
                "meaning": "the basic physical systems and structures a country or organization needs to function",
                "example": "The government invested billions of dollars to rebuild the country's aging infrastructure.",
                "clozeText": "The government invested billions of dollars to rebuild the country's aging {{c1::infrastructure::noun — cơ sở hạ tầng}}.",
                "collocations": [
                        "transport infrastructure - cơ sở hạ tầng giao thông",
                        "infrastructure development - sự phát triển cơ sở hạ tầng"
                ],
                "bidirectional": true,
                "interval": 0,
                "ease": 250,
                "reps": 0,
                "state": "new",
                "meaningVi": "Cơ sở hạ tầng (hệ thống giao thông, điện, nước, viễn thông...) cần thiết cho một quốc gia hoặc tổ chức hoạt động.",
                "definitionEn": "the basic physical systems and structures a country or organization needs to function",
                "lapses": 0
        },
        {
                "id": "sr-unit04-11",
                "category": "vocabulary",
                "deck": "English Vocabulary",
                "language": "en",
                "term": "legislate",
                "pos": "verb",
                "phonetic": "/ˈledʒ.ɪ.sleɪt/",
                "level": "C2",
                "levelSource": "4000 Essential English Words Vol. 5",
                "meaning": "to make or enact laws officially through a parliament or government body",
                "example": "Parliament plans to legislate against illegal pollution by industrial factories.",
                "clozeText": "Parliament plans to {{c1::legislate::verb — lập pháp, làm luật}} against illegal pollution by industrial factories.",
                "collocations": [
                        "legislate against - làm luật cấm/chống lại",
                        "power to legislate - quyền lập pháp"
                ],
                "bidirectional": true,
                "interval": 0,
                "ease": 250,
                "reps": 0,
                "state": "new",
                "meaningVi": "lập pháp, làm luật, Lập pháp, ban hành luật pháp để điều chỉnh hoặc kiểm soát một hành vi hay lĩnh vực.",
                "definitionEn": "to make or enact laws officially through a parliament or government body",
                "lapses": 0
        },
        {
                "id": "sr-unit04-12",
                "category": "vocabulary",
                "deck": "English Vocabulary",
                "language": "en",
                "term": "legitimate",
                "pos": "adj",
                "phonetic": "/lɪˈdʒɪt.ə.mət/",
                "level": "C1",
                "levelSource": "4000 Essential English Words Vol. 5",
                "meaning": "allowed by law, or reasonable, valid, and acceptable",
                "example": "They expressed legitimate concerns about the safety of the new medical treatment.",
                "clozeText": "They expressed {{c1::legitimate::adj — hợp pháp, chính đáng}} concerns about the safety of the new medical treatment.",
                "collocations": [
                        "legitimate business - doanh nghiệp hợp pháp",
                        "legitimate concern - mối quan ngại chính đáng"
                ],
                "bidirectional": true,
                "interval": 0,
                "ease": 250,
                "reps": 0,
                "state": "new",
                "meaningVi": "Hợp pháp, chính đáng, dựa trên lý do hoặc căn cứ hợp lý.",
                "definitionEn": "allowed by law, or reasonable, valid, and acceptable",
                "lapses": 0
        },
        {
                "id": "sr-unit04-13",
                "category": "vocabulary",
                "deck": "English Vocabulary",
                "language": "en",
                "term": "manipulate",
                "pos": "verb",
                "phonetic": "/məˈnɪp.jə.leɪt/",
                "level": "C1",
                "levelSource": "4000 Essential English Words Vol. 5",
                "meaning": "to control or influence someone or something cleverly or unscrupulously",
                "example": "He tried to manipulate the media coverage to protect his reputation.",
                "clozeText": "He tried to {{c1::manipulate::verb — thao túng, điều khiển}} the media coverage to protect his reputation.",
                "collocations": [
                        "manipulate public opinion - thao túng dư luận",
                        "manipulate market prices - thao túng giá thị trường"
                ],
                "bidirectional": true,
                "interval": 0,
                "ease": 250,
                "reps": 0,
                "state": "new",
                "meaningVi": "Thao túng, điều khiển hoặc ảnh hưởng một cách xảo quyệt/không công bằng tới người khác hoặc dữ liệu.",
                "definitionEn": "to control or influence someone or something cleverly or unscrupulously",
                "lapses": 0
        },
        {
                "id": "sr-unit04-14",
                "category": "vocabulary",
                "deck": "English Vocabulary",
                "language": "en",
                "term": "merchandise",
                "pos": "noun",
                "phonetic": "/ˈmɜː.tʃən.daɪz/",
                "level": "C1",
                "levelSource": "4000 Essential English Words Vol. 5",
                "meaning": "goods that are bought, sold, or traded in commerce",
                "example": "The store displayed a wide variety of official sports merchandise near the entrance.",
                "clozeText": "The store displayed a wide variety of official sports {{c1::merchandise::noun — hàng hóa}} near the entrance.",
                "collocations": [
                        "official merchandise - hàng hóa chính hãng",
                        "display merchandise - trưng bày hàng hóa"
                ],
                "bidirectional": true,
                "interval": 0,
                "ease": 250,
                "reps": 0,
                "state": "new",
                "meaningVi": "Hàng hóa được bày bán hoặc chuẩn bị để mua bán.",
                "definitionEn": "goods that are bought, sold, or traded in commerce",
                "lapses": 0
        },
        {
                "id": "sr-unit04-15",
                "category": "vocabulary",
                "deck": "English Vocabulary",
                "language": "en",
                "term": "retail",
                "pos": "noun",
                "phonetic": "/ˈriː.teɪl/",
                "level": "B2",
                "levelSource": "4000 Essential English Words Vol. 5",
                "meaning": "the sale of goods directly to the public in relatively small quantities for personal use",
                "example": "Online shopping has completely transformed the traditional retail industry.",
                "clozeText": "Online shopping has completely transformed the traditional {{c1::retail::noun — ngành bán lẻ}} industry.",
                "collocations": [
                        "retail outlet / store - cửa hàng bán lẻ",
                        "retail price - giá bán lẻ"
                ],
                "bidirectional": true,
                "interval": 0,
                "ease": 250,
                "reps": 0,
                "state": "new",
                "meaningVi": "ngành bán lẻ, Việc bán lẻ (bán trực tiếp hàng hóa tới người tiêu dùng cuối cùng).",
                "definitionEn": "the sale of goods directly to the public in relatively small quantities for personal use",
                "lapses": 0
        },
        {
                "id": "sr-unit04-16",
                "category": "vocabulary",
                "deck": "English Vocabulary",
                "language": "en",
                "term": "revenue",
                "pos": "noun",
                "phonetic": "/ˈrev.ən.juː/",
                "level": "B2",
                "levelSource": "4000 Essential English Words Vol. 5",
                "meaning": "the total income that a government or company receives regularly",
                "example": "The company's annual revenue increased by 15 percent thanks to successful marketing campaigns.",
                "clozeText": "The company's annual {{c1::revenue::noun — doanh thu}} increased by 15 percent thanks to successful marketing campaigns.",
                "collocations": [
                        "generate revenue - tạo ra doanh thu",
                        "annual revenue - doanh thu hàng năm"
                ],
                "bidirectional": true,
                "interval": 0,
                "ease": 250,
                "reps": 0,
                "state": "new",
                "meaningVi": "Doanh thu, tổng số tiền một công ty hoặc chính phủ thu về.",
                "definitionEn": "the total income that a government or company receives regularly",
                "lapses": 0
        },
        {
                "id": "sr-unit04-17",
                "category": "vocabulary",
                "deck": "English Vocabulary",
                "language": "en",
                "term": "rubbish",
                "pos": "noun",
                "phonetic": "/ˈrʌb.ɪʃ/",
                "level": "B1",
                "levelSource": "4000 Essential English Words Vol. 5",
                "meaning": "waste material or things that are no longer wanted and have been thrown away",
                "example": "Please remember to take out the rubbish before you leave the house.",
                "clozeText": "Please remember to take out the {{c1::rubbish::noun — rác thải}} before you leave the house.",
                "collocations": [
                        "rubbish bin - thùng rác",
                        "talk rubbish - nói nhảm nhí/vô lý"
                ],
                "bidirectional": true,
                "interval": 0,
                "ease": 250,
                "reps": 0,
                "state": "new",
                "meaningVi": "Rác thải, đồ bỏ đi; (nghĩa lóng) điều nhảm nhí/kém chất lượng.",
                "definitionEn": "waste material or things that are no longer wanted and have been thrown away",
                "lapses": 0
        },
        {
                "id": "sr-unit04-18",
                "category": "vocabulary",
                "deck": "English Vocabulary",
                "language": "en",
                "term": "subsidy",
                "pos": "noun",
                "phonetic": "/ˈsʌb.sə.di/",
                "level": "C1",
                "levelSource": "4000 Essential English Words Vol. 5",
                "meaning": "money paid by a government or organization to reduce the cost of producing goods or services",
                "example": "The local government granted a state subsidy to support renewable energy projects.",
                "clozeText": "The local government granted a state {{c1::subsidy::noun — tiền trợ cấp, trợ giá}} to support renewable energy projects.",
                "collocations": [
                        "government subsidy - trợ cấp chính phủ",
                        "agricultural subsidy - trợ cấp nông nghiệp"
                ],
                "bidirectional": true,
                "interval": 0,
                "ease": 250,
                "reps": 0,
                "state": "new",
                "meaningVi": "tiền trợ cấp, trợ giá, Tiền trợ cấp, khoản tiền chính phủ chi trả để hỗ trợ doanh nghiệp hoặc ngành công nghiệp.",
                "definitionEn": "money paid by a government or organization to reduce the cost of producing goods or services",
                "lapses": 0
        },
        {
                "id": "sr-unit04-19",
                "category": "vocabulary",
                "deck": "English Vocabulary",
                "language": "en",
                "term": "transaction",
                "pos": "noun",
                "phonetic": "/trænˈzæk.ʃən/",
                "level": "B2",
                "levelSource": "4000 Essential English Words Vol. 5",
                "meaning": "an occasion when someone buys or sells something, or an exchange of money",
                "example": "You will receive a confirmation email immediately after the financial transaction is completed.",
                "clozeText": "You will receive a confirmation email immediately after the financial {{c1::transaction::noun — giao dịch}} is completed.",
                "collocations": [
                        "financial transaction - giao dịch tài chính",
                        "online transaction - giao dịch trực tuyến"
                ],
                "bidirectional": true,
                "interval": 0,
                "ease": 250,
                "reps": 0,
                "state": "new",
                "meaningVi": "Giao dịch (hành vi mua bán, chuyển tiền hoặc trao đổi công việc).",
                "definitionEn": "an occasion when someone buys or sells something, or an exchange of money",
                "lapses": 0
        },
        {
                "id": "sr-unit04-20",
                "category": "vocabulary",
                "deck": "English Vocabulary",
                "language": "en",
                "term": "violate",
                "pos": "verb",
                "phonetic": "/ˈvaɪ.ə.leɪt/",
                "level": "C1",
                "levelSource": "4000 Essential English Words Vol. 5",
                "meaning": "to break or act against a law, agreement, rule, or principle",
                "example": "Companies that violate safety regulations face heavy fines and potential closure.",
                "clozeText": "Companies that {{c1::violate::verb — vi phạm}} safety regulations face heavy fines and potential closure.",
                "collocations": [
                        "violate a law - vi phạm luật pháp",
                        "violate human rights - vi phạm quyền con người"
                ],
                "bidirectional": true,
                "interval": 0,
                "ease": 250,
                "reps": 0,
                "state": "new",
                "meaningVi": "Vi phạm, xâm phạm (luật pháp, quy định, thỏa thuận, quyền riêng tư).",
                "definitionEn": "to break or act against a law, agreement, rule, or principle",
                "lapses": 0
        }
];
    return unitSeeds.map(function(s, idx) {
        return normalizeCard(s, 100 + idx + 1, now, opts, lexiconAnalyzer);
    });
}

function migrateStorage(rawPayload, nowMs, rawOptions, lexiconAnalyzer) {
    var now = Number.isFinite(Number(nowMs)) ? Number(nowMs) : Date.now();
    var opts = normalizeOptions(rawOptions);

    if (!rawPayload || typeof rawPayload !== "object" || Array.isArray(rawPayload)) {
        return {
            schemaVersion: SCHEMA_VERSION,
            nextId: 200,
            cards: starterCards(now, opts, lexiconAnalyzer),
            historyByDay: {},
            retainedStorageFields: {}
        };
    }

    var retained = (rawPayload.retainedStorageFields && typeof rawPayload.retainedStorageFields === "object" && !Array.isArray(rawPayload.retainedStorageFields))
        ? Object.assign({}, rawPayload.retainedStorageFields)
        : {};
    var knownKeys = ["schemaVersion", "nextId", "cards", "historyByDay", "retainedStorageFields"];
    var keys = Object.keys(rawPayload);
    for (var k = 0; k < keys.length; k++) {
        var key = keys[k];
        if (knownKeys.indexOf(key) < 0) {
            retained[key] = rawPayload[key];
        }
    }

    var rawCards = Array.isArray(rawPayload.cards) ? rawPayload.cards : [];
    var cards = [];
    var seenIds = {};
    var maxNumericId = Math.max(1, Number(rawPayload.nextId) || 1);

    for (var i = 0; i < rawCards.length; i++) {
        var item = rawCards[i];
        if (!item || typeof item !== "object" || Array.isArray(item)) continue;
        var norm = normalizeCard(item, i + 1, now, opts, lexiconAnalyzer);
        if (!norm.term && !norm.clozeText) continue;
        if (seenIds[norm.id]) {
            norm.id = norm.id + "-" + (i + 1);
        }
        seenIds[norm.id] = true;
        var numMatch = norm.id.match(/(\d+)$/);
        if (numMatch) {
            var num = parseInt(numMatch[1], 10);
            if (num >= maxNumericId) maxNumericId = num + 1;
        }
        cards.push(norm);
    }

    var prevSchema = Number(rawPayload.schemaVersion) || 0;
    var hasUserStarterDeck = cards.some(function(c) { return c && (c.id === "sr-seed-en-1" || /^sr-unit\d+/i.test(c.id)); }) || Boolean(rawPayload.includeUnitVocabulary);
    if (prevSchema < SCHEMA_VERSION && hasUserStarterDeck) {
        var seenTerms = {};
        for (var st = 0; st < cards.length; st++) {
            var existingTerm = String(cards[st].term || "").trim().toLowerCase();
            if (existingTerm) seenTerms[existingTerm] = true;
        }
        var unitCards = unitVocabularyCards(now, opts, lexiconAnalyzer);
        for (var u = 0; u < unitCards.length; u++) {
            var uc = unitCards[u];
            var uTerm = String(uc.term || "").trim().toLowerCase();
            if (seenIds[uc.id] || (uTerm && seenTerms[uTerm])) continue;
            seenIds[uc.id] = true;
            if (uTerm) seenTerms[uTerm] = true;
            cards.push(uc);
        }
        for (var rc = 0; rc < cards.length; rc++) {
            var cardItem = cards[rc];
            if (cardItem && (/^sr-unit\d+/i.test(cardItem.id) || /^sr-seed-/i.test(cardItem.id))) {
                cardItem.state = "new";
                cardItem.interval = 0;
                cardItem.ease = opts.baseEase;
                cardItem.reps = 0;
                cardItem.lapses = 0;
                cardItem.isLeech = false;
                cardItem.dueAt = now;
                cardItem.dueDate = civilDayKey(now);
                cardItem.lastReviewedAt = 0;
            }
        }
        if (maxNumericId < 200) maxNumericId = 200;
    }

    var historyByDay = {};
    if (rawPayload.historyByDay && typeof rawPayload.historyByDay === "object" && !Array.isArray(rawPayload.historyByDay)) {
        var dayKeys = Object.keys(rawPayload.historyByDay);
        for (var d = 0; d < dayKeys.length; d++) {
            var dk = dayKeys[d];
            var entry = rawPayload.historyByDay[dk];
            if (entry && typeof entry === "object") {
                historyByDay[dk] = {
                    reviewed: Math.max(0, Math.round(Number(entry.reviewed) || 0)),
                    passed: Math.max(0, Math.round(Number(entry.passed) || 0)),
                    newStudied: Math.max(0, Math.round(Number(entry.newStudied) || 0)),
                    reviewsDone: Math.max(0, Math.round(Number(entry.reviewsDone) || 0))
                };
            }
        }
    }

    return {
        schemaVersion: SCHEMA_VERSION,
        nextId: maxNumericId,
        cards: cards,
        historyByDay: historyByDay,
        retainedStorageFields: retained
    };
}
