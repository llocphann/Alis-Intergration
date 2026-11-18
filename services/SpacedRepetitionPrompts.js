.pragma library

// Presentation-only answer masking & O(1) compiled pattern cache.
// Never mutates stored dictionary text or user review records.

var LETTERS = "A-Za-z0-9_\\u00c0-\\u02af\\u0300-\\u036f\\u1e00-\\u1eff";

var IRREGULAR_FORMS = {
    "arise": ["arose", "arisen"],
    "awake": ["awoke", "awoken"],
    "bear": ["bore", "borne", "born"],
    "beat": ["beaten"],
    "become": ["became"],
    "begin": ["began", "begun"],
    "bend": ["bent"],
    "bind": ["bound"],
    "bite": ["bit", "bitten"],
    "bleed": ["bled"],
    "blow": ["blew", "blown"],
    "break": ["broke", "broken"],
    "breed": ["bred"],
    "bring": ["brought"],
    "build": ["built"],
    "burn": ["burnt"],
    "buy": ["bought"],
    "catch": ["caught"],
    "choose": ["chose", "chosen"],
    "cling": ["clung"],
    "come": ["came"],
    "creep": ["crept"],
    "deal": ["dealt"],
    "dig": ["dug"],
    "dive": ["dove"],
    "draw": ["drew", "drawn"],
    "dream": ["dreamt"],
    "drink": ["drank", "drunk"],
    "drive": ["drove", "driven"],
    "dwell": ["dwelt"],
    "eat": ["ate", "eaten"],
    "fall": ["fell", "fallen"],
    "feed": ["fed"],
    "feel": ["felt"],
    "fight": ["fought"],
    "find": ["found"],
    "flee": ["fled"],
    "fling": ["flung"],
    "fly": ["flew", "flown", "flies"],
    "forbid": ["forbade", "forbidden"],
    "forget": ["forgot", "forgotten"],
    "forgive": ["forgave", "forgiven"],
    "forsake": ["forsook", "forsaken"],
    "freeze": ["froze", "frozen"],
    "give": ["gave", "given"],
    "go": ["went", "gone", "goes"],
    "grind": ["ground"],
    "grow": ["grew", "grown"],
    "hang": ["hung"],
    "hide": ["hid", "hidden"],
    "hold": ["held"],
    "keep": ["kept"],
    "kneel": ["knelt"],
    "know": ["knew", "known"],
    "lay": ["laid"],
    "lead": ["led"],
    "lean": ["leant"],
    "leap": ["leapt"],
    "learn": ["learnt"],
    "leave": ["left"],
    "lend": ["lent"],
    "lie": ["lay", "lain", "lying"],
    "light": ["lit"],
    "lose": ["lost"],
    "make": ["made"],
    "mean": ["meant"],
    "meet": ["met"],
    "mistake": ["mistook", "mistaken"],
    "overcome": ["overcame"],
    "overtake": ["overtook", "overtaken"],
    "pay": ["paid"],
    "prove": ["proven"],
    "ride": ["rode", "ridden"],
    "ring": ["rang", "rung"],
    "rise": ["rose", "risen"],
    "run": ["ran"],
    "say": ["said"],
    "see": ["saw", "seen"],
    "seek": ["sought"],
    "sell": ["sold"],
    "send": ["sent"],
    "sew": ["sewn"],
    "shake": ["shook", "shaken"],
    "shine": ["shone"],
    "shoot": ["shot"],
    "show": ["shown"],
    "shrink": ["shrank", "shrunk"],
    "sing": ["sang", "sung"],
    "sink": ["sank", "sunk"],
    "sit": ["sat"],
    "slay": ["slew", "slain"],
    "sleep": ["slept"],
    "slide": ["slid"],
    "smell": ["smelt"],
    "sneak": ["snuck"],
    "sow": ["sown"],
    "speak": ["spoke", "spoken"],
    "speed": ["sped"],
    "spell": ["spelt"],
    "spend": ["spent"],
    "spill": ["spilt"],
    "spin": ["spun"],
    "spit": ["spat"],
    "spoil": ["spoilt"],
    "spring": ["sprang", "sprung"],
    "stand": ["stood"],
    "steal": ["stole", "stolen"],
    "stick": ["stuck"],
    "sting": ["stung"],
    "stink": ["stank", "stunk"],
    "stride": ["strode", "stridden"],
    "strike": ["struck"],
    "string": ["strung"],
    "strive": ["strove", "striven"],
    "swear": ["swore", "sworn"],
    "sweep": ["swept"],
    "swell": ["swollen"],
    "swim": ["swam", "swum"],
    "swing": ["swung"],
    "take": ["took", "taken"],
    "teach": ["taught"],
    "tear": ["tore", "torn"],
    "tell": ["told"],
    "think": ["thought"],
    "thrive": ["throve", "thriven"],
    "throw": ["threw", "thrown"],
    "tread": ["trod", "trodden"],
    "undergo": ["underwent", "undergone"],
    "understand": ["understood"],
    "undertake": ["undertook", "undertaken"],
    "uphold": ["upheld"],
    "wake": ["woke", "woken"],
    "wear": ["wore", "worn"],
    "weave": ["wove", "woven"],
    "weep": ["wept"],
    "win": ["won"],
    "wind": ["wound"],
    "withdraw": ["withdrew", "withdrawn"],
    "withhold": ["withheld"],
    "withstand": ["withstood"],
    "worsen": ["worse", "worst"],
    "wring": ["wrung"],
    "write": ["wrote", "written"],
    "child": ["children"],
    "person": ["people", "persons"],
    "man": ["men"],
    "woman": ["women"],
    "foot": ["feet"],
    "tooth": ["teeth"],
    "goose": ["geese"],
    "mouse": ["mice"],
    "louse": ["lice"],
    "ox": ["oxen"],
    "leaf": ["leaves"],
    "wolf": ["wolves"],
    "calf": ["calves"],
    "half": ["halves"],
    "knife": ["knives"],
    "wife": ["wives"],
    "life": ["lives"],
    "thief": ["thieves"],
    "loaf": ["loaves"],
    "shelf": ["shelves"],
    "scarf": ["scarves"],
    "bad": ["worse", "worst"]
};

var _compiledMaskCache = {};
var _compiledMaskCacheCount = 0;

function _escapeRegExp(str) {
    return String(str || "").replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function answerForms(card) {
    if (!card) return [];
    var forms = [];
    var seenLower = {};
    function add(value) {
        var text = String(value || "").trim();
        if (!text) return;
        var low = text.toLowerCase();
        if (!seenLower[low]) {
            seenLower[low] = true;
            forms.push(text);
        }
    }
    var keys = ["headword", "term", "front", "word"];
    for (var k = 0; k < keys.length; k++) {
        var head = String(card[keys[k]] || "").trim();
        // A legacy front may itself be a cloze sentence, not a headword.
        if (!head || head.indexOf("{{") >= 0) continue;
        add(head);
        var stripped = head.replace(/^(?:der|die|das|sich|to)\s+/i, "").trim();
        add(stripped);
        var irr = IRREGULAR_FORMS[stripped.toLowerCase()];
        if (irr) {
            for (var ir = 0; ir < irr.length; ir++) add(irr[ir]);
        }
    }
    if (card.plural) add(card.plural);
    var clozeStr = String(card.clozeText || "");
    if (clozeStr.indexOf("{{") >= 0) {
        var re = /\{\{c\d+::([^:}]+)(?:::[^}]+)?\}\}/g;
        var match;
        while ((match = re.exec(clozeStr)) !== null) add(match[1]);
    }
    return forms.sort(function(a, b) { return b.length - a.length; });
}

function _patternForForm(form) {
    var escaped = _escapeRegExp(form);
    if (form.length < 3 || !/^[A-Za-z]+$/.test(form)) {
        return escaped;
    }
    var low = form.toLowerCase();
    var alts = [escaped + "(?:s|es|ed|ing|d|ly)?"];

    // Comparatives/superlatives on stems not ending in -ce/-ge/-ion/-ment/-ness/-ity
    if (!/(?:ce|ge|ion|ment|ness|ity|ship|hood)$/i.test(low)) {
        alts.push(escaped + "(?:er|est)");
    }
    if (/[^aeiou]y$/i.test(low)) {
        var yStem = _escapeRegExp(form.slice(0, -1));
        alts.push(yStem + "(?:ies|ied|ier|iest|ily)");
    }
    if (/e$/i.test(low)) {
        var eStem = _escapeRegExp(form.slice(0, -1));
        alts.push(eStem + "(?:ing|ed)");
        if (!/(?:ce|ge)$/i.test(low) && low.length >= 4) {
            alts.push(eStem + "(?:er|est)");
        }
        if (/le$/i.test(low) && low.length >= 4) {
            alts.push(eStem + "y");
        }
        if (/ie$/i.test(low)) {
            alts.push(_escapeRegExp(form.slice(0, -2)) + "ying");
        }
    }
    if (/ic$/i.test(low) && low.length >= 4) {
        alts.push(escaped + "ally");
    }
    if (/(?:f|fe)$/i.test(low) && low.length >= 4) {
        var fStem = _escapeRegExp(low.slice(0, low.slice(-2) === "fe" ? -2 : -1));
        alts.push(fStem + "ves");
    }
    // CVC consonant doubling: zip -> zipped/zipping/zipper, swim -> swimming, big -> bigger/biggest
    if (low.length >= 3
            && "aeiouwxy".indexOf(low.charAt(low.length - 1)) < 0
            && "aeiou".indexOf(low.charAt(low.length - 2)) >= 0
            && "aeiou".indexOf(low.charAt(low.length - 3)) < 0) {
        var lastCh = _escapeRegExp(form.charAt(form.length - 1));
        alts.push(escaped + lastCh + "(?:ed|ing|er|est|y)");
    }
    return alts.length === 1 ? alts[0] : ("(?:" + alts.join("|") + ")");
}

function _compiledRegexes(forms) {
    if (!forms || forms.length === 0) return null;
    var key = forms.join("\u0000").toLowerCase();
    var cached = _compiledMaskCache[key];
    if (cached) return cached;
    if (_compiledMaskCacheCount >= 4096) {
        _compiledMaskCache = {};
        _compiledMaskCacheCount = 0;
    }
    var patterns = [];
    for (var i = 0; i < forms.length; i++) {
        patterns.push(_patternForForm(forms[i]));
    }
    var combined = patterns.join("|");
    var entry = {
        replaceRe: new RegExp("(^|[^" + LETTERS + "])(?:" + combined + ")(?=$|[^" + LETTERS + "])", "gi"),
        testRe: new RegExp("(^|[^" + LETTERS + "])(?:" + combined + ")(?=$|[^" + LETTERS + "])", "i")
    };
    _compiledMaskCache[key] = entry;
    _compiledMaskCacheCount++;
    return entry;
}

function maskAnswer(raw, card, revealed) {
    var text = String(raw || "");
    if (revealed || !text) return text;
    var forms = answerForms(card);
    var compiled = _compiledRegexes(forms);
    if (!compiled) return text;
    compiled.replaceRe.lastIndex = 0;
    return text.replace(compiled.replaceRe, "$1[...]");
}

function containsAnswerForm(raw, card) {
    var text = String(raw || "");
    if (!text || !card) return false;
    var forms = answerForms(card);
    var compiled = _compiledRegexes(forms);
    if (!compiled) return false;
    return compiled.testRe.test(text);
}
