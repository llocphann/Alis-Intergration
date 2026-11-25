.pragma library

var SCHEMA_VERSION = 1;

var CATEGORIES = [
    { id: "chest", label: "Chest", icon: "fitness_center" },
    { id: "back", label: "Back", icon: "accessibility_new" },
    { id: "shoulders", label: "Shoulders", icon: "sports_gymnastics" },
    { id: "legs", label: "Legs", icon: "directions_run" },
    { id: "arms", label: "Arms", icon: "exercise" },
    { id: "core", label: "Core", icon: "self_improvement" },
    { id: "cardio", label: "Cardio", icon: "monitor_heart" },
    { id: "mobility", label: "Mobility", icon: "spa" }
];

var ROUTINE_TEMPLATES = {
    push: {
        id: "push",
        label: "Push",
        title: "Push Strength",
        exercises: [
            { name: "Barbell Bench Press", category: "chest", sets: 4, reps: "8", weight: 60, weightUnit: "kg", durationSec: 0, restSec: 90 },
            { name: "Overhead Barbell Press", category: "shoulders", sets: 3, reps: "10", weight: 35, weightUnit: "kg", durationSec: 0, restSec: 90 },
            { name: "Incline Dumbbell Press", category: "chest", sets: 3, reps: "10", weight: 22, weightUnit: "kg", durationSec: 0, restSec: 75 },
            { name: "Cable Triceps Pushdown", category: "arms", sets: 3, reps: "12", weight: 25, weightUnit: "kg", durationSec: 0, restSec: 60 }
        ]
    },
    pull: {
        id: "pull",
        label: "Pull",
        title: "Pull & Back",
        exercises: [
            { name: "Pull-Ups / Lat Pulldown", category: "back", sets: 4, reps: "8", weight: 55, weightUnit: "kg", durationSec: 0, restSec: 90 },
            { name: "Barbell Bent-Over Row", category: "back", sets: 4, reps: "10", weight: 55, weightUnit: "kg", durationSec: 0, restSec: 90 },
            { name: "Face Pulls", category: "shoulders", sets: 3, reps: "15", weight: 20, weightUnit: "kg", durationSec: 0, restSec: 60 },
            { name: "Incline Dumbbell Curl", category: "arms", sets: 3, reps: "12", weight: 14, weightUnit: "kg", durationSec: 0, restSec: 60 }
        ]
    },
    legs: {
        id: "legs",
        label: "Legs",
        title: "Legs & Lower Body",
        exercises: [
            { name: "Barbell Back Squat", category: "legs", sets: 4, reps: "8", weight: 80, weightUnit: "kg", durationSec: 0, restSec: 120 },
            { name: "Romanian Deadlift", category: "legs", sets: 3, reps: "10", weight: 70, weightUnit: "kg", durationSec: 0, restSec: 90 },
            { name: "Walking Dumbbell Lunges", category: "legs", sets: 3, reps: "12", weight: 16, weightUnit: "kg", durationSec: 0, restSec: 75 },
            { name: "Standing Calf Raise", category: "legs", sets: 4, reps: "15", weight: 50, weightUnit: "kg", durationSec: 0, restSec: 60 }
        ]
    },
    core: {
        id: "core",
        label: "Core",
        title: "Core & Stability",
        exercises: [
            { name: "Hanging Leg Raise", category: "core", sets: 3, reps: "12", weight: 0, weightUnit: "kg", durationSec: 0, restSec: 60 },
            { name: "Plank Hold", category: "core", sets: 3, reps: "1", weight: 0, weightUnit: "kg", durationSec: 60, restSec: 45 },
            { name: "Cable Woodchopper", category: "core", sets: 3, reps: "12", weight: 15, weightUnit: "kg", durationSec: 0, restSec: 60 },
            { name: "Ab Wheel Rollout", category: "core", sets: 3, reps: "10", weight: 0, weightUnit: "kg", durationSec: 0, restSec: 60 }
        ]
    },
    cardio: {
        id: "cardio",
        label: "Cardio",
        title: "Cardio & Conditioning",
        exercises: [
            { name: "Zone 2 Run / Cycling", category: "cardio", sets: 1, reps: "1", weight: 0, weightUnit: "kg", durationSec: 1800, restSec: 60 },
            { name: "Rowing Intervals", category: "cardio", sets: 4, reps: "1", weight: 0, weightUnit: "kg", durationSec: 180, restSec: 60 },
            { name: "Jump Rope Finisher", category: "cardio", sets: 3, reps: "1", weight: 0, weightUnit: "kg", durationSec: 120, restSec: 45 }
        ]
    },
    full_body: {
        id: "full_body",
        label: "Full Body",
        title: "Full Body Circuit",
        exercises: [
            { name: "Goblet Squat", category: "legs", sets: 3, reps: "12", weight: 24, weightUnit: "kg", durationSec: 0, restSec: 75 },
            { name: "Push-Ups", category: "chest", sets: 3, reps: "15", weight: 0, weightUnit: "kg", durationSec: 0, restSec: 60 },
            { name: "Single-Arm Dumbbell Row", category: "back", sets: 3, reps: "12", weight: 22, weightUnit: "kg", durationSec: 0, restSec: 60 },
            { name: "Forearm Plank", category: "core", sets: 3, reps: "1", weight: 0, weightUnit: "kg", durationSec: 45, restSec: 45 }
        ]
    },
    rest: {
        id: "rest",
        label: "Recovery",
        title: "Active Recovery & Mobility",
        exercises: [
            { name: "Thoracic Spine Mobility", category: "mobility", sets: 2, reps: "10", weight: 0, weightUnit: "kg", durationSec: 0, restSec: 30 },
            { name: "Hip Flexor & Hamstring Stretch", category: "mobility", sets: 2, reps: "1", weight: 0, weightUnit: "kg", durationSec: 120, restSec: 30 }
        ]
    },
    custom: {
        id: "custom",
        label: "Custom",
        title: "Custom Workout",
        exercises: []
    }
};

var DEFAULT_WEEKLY_TEMPLATES = {
    "1": "push",
    "2": "pull",
    "3": "legs",
    "4": "rest",
    "5": "push",
    "6": "pull",
    "0": "core"
};

function pad2(n) {
    return String(Math.max(0, Math.floor(Number(n) || 0))).padStart(2, "0");
}

function formatDateStr(value) {
    if (typeof value === "string" && /^\d{4}-\d{2}-\d{2}$/.test(value.trim()))
        return value.trim();
    var d = value instanceof Date ? value : new Date(value || Date.now());
    if (!Number.isFinite(d.getTime()))
        d = new Date();
    return String(d.getFullYear()) + "-" + pad2(d.getMonth() + 1) + "-" + pad2(d.getDate());
}

function parseLocalDate(dateStr) {
    var clean = formatDateStr(dateStr);
    var parts = clean.split("-");
    return new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]), 12, 0, 0, 0);
}

function addDaysStr(dateStr, deltaDays) {
    var d = parseLocalDate(dateStr);
    d.setDate(d.getDate() + Math.trunc(Number(deltaDays) || 0));
    return formatDateStr(d);
}

function weekdayForDateStr(dateStr) {
    return parseLocalDate(dateStr).getDay();
}

function normalizeHm(value, fallback) {
    var raw = String(value || "").trim();
    var m = raw.match(/^(\d{1,2}):(\d{2})$/);
    if (!m)
        return fallback || "18:00";
    var hh = Math.max(0, Math.min(23, Number(m[1])));
    var mm = Math.max(0, Math.min(59, Number(m[2])));
    return pad2(hh) + ":" + pad2(mm);
}

function normalizeStringList(raw) {
    if (Array.isArray(raw)) {
        var seen = {};
        var out = [];
        for (var i = 0; i < raw.length; i++) {
            var item = String(raw[i] || "").trim();
            var low = item.toLowerCase();
            if (item && !seen[low]) {
                seen[low] = true;
                out.push(item);
            }
        }
        return out;
    }
    var s = String(raw || "").trim();
    if (!s)
        return [];
    return normalizeStringList(s.split(/[,;]/));
}

function fallbackMusclesForCategory(category) {
    var c = normalizeCategory(category);
    if (c === "chest") return ["chest"];
    if (c === "back") return ["lats", "middle back"];
    if (c === "shoulders") return ["shoulders"];
    if (c === "legs") return ["quadriceps", "hamstrings", "glutes"];
    if (c === "arms") return ["biceps", "triceps"];
    if (c === "core") return ["abdominals"];
    if (c === "cardio") return ["quadriceps", "calves"];
    if (c === "mobility") return ["hamstrings", "lower back"];
    return ["chest"];
}

function normalizeCategory(value) {
    var raw = String(value || "").trim().toLowerCase().replace(/_/g, " ");
    for (var i = 0; i < CATEGORIES.length; i++) {
        if (CATEGORIES[i].id === raw)
            return raw;
    }
    if (raw === "pectorals" || raw === "pecs")
        return "chest";
    if (raw === "quadriceps" || raw === "hamstrings" || raw === "glutes" || raw === "calves" || raw === "adductors" || raw === "abductors")
        return "legs";
    if (raw === "lats" || raw === "traps" || raw === "middle back" || raw === "lower back" || raw === "upper back")
        return "back";
    if (raw === "delts" || raw === "deltoids" || raw === "neck")
        return "shoulders";
    if (raw === "biceps" || raw === "triceps" || raw === "forearms")
        return "arms";
    if (raw === "abdominals" || raw === "abs")
        return "core";
    return "chest";
}

function normalizeRoutine(value) {
    var raw = String(value || "").trim().toLowerCase().replace(/[\s-]+/g, "_");
    if (Object.prototype.hasOwnProperty.call(ROUTINE_TEMPLATES, raw))
        return raw;
    if (raw === "recovery" || raw === "mobility")
        return "rest";
    if (raw === "fullbody")
        return "full_body";
    return "custom";
}

function defaultRoutineForDate(state, dateStr) {
    var wd = String(weekdayForDateStr(dateStr));
    var map = (state && state.weeklyTemplates && typeof state.weeklyTemplates === "object")
        ? state.weeklyTemplates : DEFAULT_WEEKLY_TEMPLATES;
    return normalizeRoutine(map[wd] || DEFAULT_WEEKLY_TEMPLATES[wd] || "push");
}

function defaultTitleForRoutine(routine) {
    var key = normalizeRoutine(routine);
    return (ROUTINE_TEMPLATES[key] && ROUTINE_TEMPLATES[key].title) || "Workout Session";
}

function normalizePreferences(raw) {
    var src = (raw && typeof raw === "object" && !Array.isArray(raw)) ? raw : {};
    var out = Object.assign({}, src);
    out.weightUnit = src.weightUnit === "lb" ? "lb" : "kg";
    var defSets = Math.round(Number(src.defaultSets));
    out.defaultSets = Number.isFinite(defSets) && defSets > 0 ? Math.min(30, defSets) : 3;
    var rest = Math.round(Number(src.defaultRestSeconds));
    out.defaultRestSeconds = Number.isFinite(rest) ? Math.max(15, Math.min(600, rest)) : 90;
    out.autoStartRestOnSet = src.autoStartRestOnSet !== false;
    out.autoSyncPlanner = src.autoSyncPlanner !== false;
    out.showInNexus = src.showInNexus !== false;
    var hr = Math.round(Number(src.workoutDefaultHour));
    out.workoutDefaultHour = Number.isFinite(hr) ? Math.max(0, Math.min(23, hr)) : 18;
    var dur = Math.round(Number(src.workoutDefaultDurationMin));
    out.workoutDefaultDurationMin = Number.isFinite(dur) ? Math.max(15, Math.min(240, dur)) : 60;
    var rem = Math.round(Number(src.workoutReminderMinutes));
    out.workoutReminderMinutes = Number.isFinite(rem) ? Math.max(0, Math.min(1440, rem)) : 15;
    out.bodyPhotosStorageMode = src.bodyPhotosStorageMode === "custom" ? "custom" : "auto";
    out.bodyPhotosCustomDir = String(src.bodyPhotosCustomDir || "").trim().slice(0, 500);
    out.defaultGalleryMode = src.defaultGalleryMode === "compare" ? "compare" : "timeline";
    out.showBodyMetrics = src.showBodyMetrics !== false;
    return out;
}

function normalizeExercise(raw, fallbackIndex, defaultUnit, defaultRest) {
    if (!raw || typeof raw !== "object" || Array.isArray(raw))
        return null;
    var name = String(raw.name || raw.title || "").trim();
    if (!name.length)
        return null;
    var out = Object.assign({}, raw);
    out.id = String(raw.id || ("ex-" + String(fallbackIndex || 1)));
    out.name = name.slice(0, 120);
    var pMuscles = normalizeStringList(raw.primaryMuscles !== undefined ? raw.primaryMuscles : raw.muscleGroup);
    var sMuscles = normalizeStringList(raw.secondaryMuscles);
    var catSource = raw.category || (pMuscles.length > 0 ? pMuscles[0] : "") || raw.muscleGroup || inferCategoryFromName(name);
    out.category = normalizeCategory(catSource);
    var sets = Math.round(Number(raw.sets));
    out.sets = Number.isFinite(sets) && sets > 0 ? Math.min(30, sets) : 3;
    out.reps = String(raw.reps !== undefined && raw.reps !== null && String(raw.reps).trim() !== "" ? raw.reps : "10").trim().slice(0, 24);
    var weight = Number(raw.weight);
    out.weight = Number.isFinite(weight) && weight >= 0 ? Math.round(weight * 100) / 100 : 0;
    out.weightUnit = (raw.weightUnit === "lb" || raw.weightUnit === "kg") ? raw.weightUnit : (defaultUnit || "kg");
    var durSec = Math.round(Number(raw.durationSec !== undefined ? raw.durationSec : (Number(raw.durationMin) > 0 ? Number(raw.durationMin) * 60 : 0)));
    out.durationSec = Number.isFinite(durSec) && durSec >= 0 ? Math.min(28800, durSec) : 0;
    var restSec = Math.round(Number(raw.restSec));
    out.restSec = Number.isFinite(restSec) && restSec >= 0 ? Math.min(600, restSec) : (defaultRest || 90);
    out.completed = raw.completed === true;
    var cSets = Math.round(Number(raw.completedSets));
    if (out.completed) {
        out.completedSets = out.sets;
    } else if (Number.isFinite(cSets) && cSets >= 0) {
        out.completedSets = Math.min(out.sets, cSets);
        if (out.completedSets >= out.sets && out.sets > 0)
            out.completed = true;
    } else {
        out.completedSets = 0;
    }
    out.completedAt = out.completed ? String(raw.completedAt || "") : "";
    out.notes = String(raw.notes || "").slice(0, 400);
    if (raw.nexusRelPath)
        out.nexusRelPath = String(raw.nexusRelPath).trim().slice(0, 300);
    if (raw.equipment)
        out.equipment = String(raw.equipment).trim().slice(0, 80);
    if (raw.level)
        out.level = String(raw.level).trim().slice(0, 60);
    if (raw.force)
        out.force = String(raw.force).trim().slice(0, 60);
    if (raw.mechanic)
        out.mechanic = String(raw.mechanic).trim().slice(0, 60);
    if (pMuscles.length > 0)
        out.primaryMuscles = pMuscles;
    if (sMuscles.length > 0)
        out.secondaryMuscles = sMuscles;
    if (raw.previewUrl)
        out.previewUrl = String(raw.previewUrl).trim().slice(0, 500);
    if (raw.animationUrl)
        out.animationUrl = String(raw.animationUrl).trim().slice(0, 500);
    return out;
}

function normalizeDay(raw, dateStr, prefs, weeklyTemplates) {
    var cleanDate = formatDateStr(dateStr || (raw && raw.date));
    var src = (raw && typeof raw === "object" && !Array.isArray(raw)) ? raw : {};
    var out = Object.assign({}, src);
    var fallbackRoutine = defaultRoutineForDate({ weeklyTemplates: weeklyTemplates }, cleanDate);
    out.date = cleanDate;
    out.routine = src.routine ? normalizeRoutine(src.routine) : fallbackRoutine;
    out.title = String(src.title || defaultTitleForRoutine(out.routine)).trim().slice(0, 120) || defaultTitleForRoutine(out.routine);
    var evId = Number(src.plannerEventId);
    out.plannerEventId = (Number.isInteger(evId) && evId > 0) ? evId : 0;
    var defaultStart = pad2(prefs.workoutDefaultHour) + ":00";
    var endTotalMin = prefs.workoutDefaultHour * 60 + prefs.workoutDefaultDurationMin;
    var defaultEnd = pad2(Math.min(23, Math.floor(endTotalMin / 60))) + ":" + pad2(endTotalMin % 60);
    out.scheduledStart = normalizeHm(src.scheduledStart, defaultStart);
    out.scheduledEnd = normalizeHm(src.scheduledEnd, defaultEnd);
    out.sessionNote = String(src.sessionNote || "").slice(0, 1000);
    var rawList = Array.isArray(src.exercises) ? src.exercises : [];
    var exList = [];
    var seenIds = {};
    for (var i = 0; i < rawList.length; i++) {
        var norm = normalizeExercise(rawList[i], i + 1, prefs.weightUnit, prefs.defaultRestSeconds);
        if (!norm)
            continue;
        while (seenIds[norm.id])
            norm.id = norm.id + "-" + String(i + 1);
        seenIds[norm.id] = true;
        exList.push(norm);
    }
    out.exercises = exList;
    return out;
}

function normalizeCheckin(raw, fallbackIndex) {
    if (!raw || typeof raw !== "object" || Array.isArray(raw))
        return null;
    var photoPath = String(raw.photoPath || "").trim();
    var note = String(raw.note || "").trim();
    var w = Number(raw.weightKg);
    var bf = Number(raw.bodyFatPct);
    var hasWeight = Number.isFinite(w) && w > 0;
    var hasBf = Number.isFinite(bf) && bf > 0;
    if (!photoPath && !note && !hasWeight && !hasBf)
        return null;
    var out = Object.assign({}, raw);
    out.id = String(raw.id || ("bc-" + String(fallbackIndex || 1)));
    out.date = formatDateStr(raw.date || raw.createdAt || new Date());
    out.createdAt = String(raw.createdAt || (out.date + "T18:00:00.000Z"));
    out.photoPath = photoPath;
    out.photoRel = String(raw.photoRel || "");
    out.photoVaultRel = String(raw.photoVaultRel || "").trim().slice(0, 500);
    out.weightKg = hasWeight ? Math.round(w * 100) / 100 : 0;
    out.bodyFatPct = hasBf ? Math.round(bf * 100) / 100 : 0;
    out.routine = normalizeRoutine(raw.routine || "custom");
    out.note = note.slice(0, 600);
    return out;
}

function createEmptyState() {
    return normalizeState({});
}

function normalizeState(raw, todayStr) {
    var src = (raw && typeof raw === "object" && !Array.isArray(raw)) ? raw : {};
    var prefs = normalizePreferences(src.preferences);
    var weekly = Object.assign({}, DEFAULT_WEEKLY_TEMPLATES);
    if (src.weeklyTemplates && typeof src.weeklyTemplates === "object") {
        for (var k in DEFAULT_WEEKLY_TEMPLATES) {
            if (src.weeklyTemplates[k])
                weekly[k] = normalizeRoutine(src.weeklyTemplates[k]);
        }
    }

    var days = {};
    var maxCounter = Number(src.nextSeq) || 1;
    if (src.days && typeof src.days === "object" && !Array.isArray(src.days)) {
        var dateKeys = Object.keys(src.days);
        for (var i = 0; i < dateKeys.length; i++) {
            var dk = dateKeys[i];
            if (!/^\d{4}-\d{2}-\d{2}$/.test(dk))
                continue;
            var normDay = normalizeDay(src.days[dk], dk, prefs, weekly);
            days[dk] = normDay;
            for (var j = 0; j < normDay.exercises.length; j++) {
                var m = String(normDay.exercises[j].id).match(/^ex-(\d+)$/);
                if (m && Number(m[1]) >= maxCounter)
                    maxCounter = Number(m[1]) + 1;
            }
        }
    }

    var checkins = [];
    var seenBc = {};
    var rawBc = Array.isArray(src.bodyCheckins) ? src.bodyCheckins : [];
    for (var c = 0; c < rawBc.length; c++) {
        var bc = normalizeCheckin(rawBc[c], c + 1);
        if (!bc)
            continue;
        while (seenBc[bc.id])
            bc.id = bc.id + "-" + String(c + 1);
        seenBc[bc.id] = true;
        var bm = String(bc.id).match(/^bc-(\d+)$/);
        if (bm && Number(bm[1]) >= maxCounter)
            maxCounter = Number(bm[1]) + 1;
        checkins.push(bc);
    }
    checkins.sort(function(a, b) {
        if (a.date !== b.date)
            return b.date.localeCompare(a.date);
        return String(b.createdAt).localeCompare(String(a.createdAt));
    });

    var retained = {};
    var knownKeys = {
        schemaVersion: true,
        updatedAt: true,
        nextSeq: true,
        preferences: true,
        weeklyTemplates: true,
        days: true,
        bodyCheckins: true,
        summary: true
    };
    var topKeys = Object.keys(src);
    for (var t = 0; t < topKeys.length; t++) {
        var tk = topKeys[t];
        if (!knownKeys[tk])
            retained[tk] = src[tk];
    }

    var state = Object.assign({}, retained, {
        schemaVersion: SCHEMA_VERSION,
        updatedAt: String(src.updatedAt || new Date().toISOString()),
        nextSeq: maxCounter,
        preferences: prefs,
        weeklyTemplates: weekly,
        days: days,
        bodyCheckins: checkins
    });
    state.summary = computeGlobalSummary(state, formatDateStr(todayStr || new Date()));
    return state;
}

function serializeState(state, todayStr) {
    var normalized = normalizeState(state, todayStr);
    normalized.updatedAt = new Date().toISOString();
    normalized.summary = computeGlobalSummary(normalized, formatDateStr(todayStr || new Date()));
    return JSON.stringify(normalized, null, 2) + "\n";
}

function cloneState(state) {
    return JSON.parse(JSON.stringify(state || createEmptyState()));
}

function ensureDay(state, dateStr, seedDefaultTemplate) {
    var dk = formatDateStr(dateStr);
    if (!state.days[dk]) {
        var routine = defaultRoutineForDate(state, dk);
        var base = normalizeDay({ date: dk, routine: routine, title: defaultTitleForRoutine(routine), exercises: [] }, dk, state.preferences, state.weeklyTemplates);
        if (seedDefaultTemplate) {
            var tpl = ROUTINE_TEMPLATES[routine];
            if (tpl && Array.isArray(tpl.exercises) && tpl.exercises.length > 0) {
                base.exercises = tpl.exercises.map(function(item) {
                    var id = "ex-" + String(state.nextSeq++);
                    return normalizeExercise(Object.assign({}, item, { id: id, completed: false, completedSets: 0 }), state.nextSeq, state.preferences.weightUnit, state.preferences.defaultRestSeconds);
                });
            }
        }
        state.days[dk] = base;
    }
    return state.days[dk];
}

function getOrPreviewDay(state, dateStr) {
    var dk = formatDateStr(dateStr);
    if (state && state.days && state.days[dk])
        return state.days[dk];
    var prefs = (state && state.preferences) ? state.preferences : normalizePreferences({});
    var weekly = (state && state.weeklyTemplates) ? state.weeklyTemplates : DEFAULT_WEEKLY_TEMPLATES;
    var routine = defaultRoutineForDate(state, dk);
    return normalizeDay({
        date: dk,
        routine: routine,
        title: defaultTitleForRoutine(routine),
        exercises: []
    }, dk, prefs, weekly);
}

function applyRoutineTemplate(state, dateStr, routineKey, replaceExisting) {
    var next = cloneState(state);
    var dk = formatDateStr(dateStr);
    var routine = normalizeRoutine(routineKey);
    var day = ensureDay(next, dk, false);
    day.routine = routine;
    day.title = defaultTitleForRoutine(routine);
    var tpl = ROUTINE_TEMPLATES[routine] || ROUTINE_TEMPLATES.custom;
    var existing = replaceExisting ? [] : day.exercises.slice();
    var existingNames = {};
    for (var i = 0; i < existing.length; i++)
        existingNames[existing[i].name.toLowerCase()] = true;
    for (var j = 0; j < tpl.exercises.length; j++) {
        var item = tpl.exercises[j];
        if (!replaceExisting && existingNames[item.name.toLowerCase()])
            continue;
        var id = "ex-" + String(next.nextSeq++);
        existing.push(normalizeExercise(Object.assign({}, item, {
            id: id,
            completed: false,
            completedSets: 0
        }), next.nextSeq, next.preferences.weightUnit, next.preferences.defaultRestSeconds));
    }
    day.exercises = existing;
    next.weeklyTemplates[String(weekdayForDateStr(dk))] = routine;
    return next;
}

function addExercise(state, dateStr, spec) {
    var next = cloneState(state);
    var dk = formatDateStr(dateStr);
    var day = ensureDay(next, dk, false);
    var id = "ex-" + String(next.nextSeq++);
    var ex = normalizeExercise(Object.assign({}, spec || {}, { id: id }), next.nextSeq, next.preferences.weightUnit, next.preferences.defaultRestSeconds);
    if (!ex)
        return next;
    day.exercises.push(ex);
    return next;
}

function updateExercise(state, dateStr, exerciseId, patch) {
    var next = cloneState(state);
    var dk = formatDateStr(dateStr);
    var day = next.days[dk];
    if (!day || !Array.isArray(day.exercises))
        return next;
    for (var i = 0; i < day.exercises.length; i++) {
        if (day.exercises[i].id === exerciseId) {
            var merged = Object.assign({}, day.exercises[i], patch || {}, { id: exerciseId });
            var norm = normalizeExercise(merged, i + 1, next.preferences.weightUnit, next.preferences.defaultRestSeconds);
            if (norm)
                day.exercises[i] = norm;
            break;
        }
    }
    return next;
}

function toggleExercise(state, dateStr, exerciseId, nowIso) {
    var next = cloneState(state);
    var dk = formatDateStr(dateStr);
    var day = next.days[dk];
    if (!day || !Array.isArray(day.exercises))
        return next;
    for (var i = 0; i < day.exercises.length; i++) {
        var ex = day.exercises[i];
        if (ex.id === exerciseId) {
            ex.completed = !ex.completed;
            ex.completedSets = ex.completed ? ex.sets : 0;
            ex.completedAt = ex.completed ? String(nowIso || new Date().toISOString()) : "";
            break;
        }
    }
    return next;
}

function stepCompletedSets(state, dateStr, exerciseId, delta, nowIso) {
    var next = cloneState(state);
    var dk = formatDateStr(dateStr);
    var day = next.days[dk];
    if (!day || !Array.isArray(day.exercises))
        return next;
    for (var i = 0; i < day.exercises.length; i++) {
        var ex = day.exercises[i];
        if (ex.id === exerciseId) {
            var targetSets = Math.max(0, Math.min(ex.sets, (Number(ex.completedSets) || 0) + Math.trunc(Number(delta) || 0)));
            ex.completedSets = targetSets;
            ex.completed = ex.sets > 0 && targetSets >= ex.sets;
            ex.completedAt = ex.completed ? String(ex.completedAt || nowIso || new Date().toISOString()) : "";
            break;
        }
    }
    return next;
}

function removeExercise(state, dateStr, exerciseId) {
    var next = cloneState(state);
    var dk = formatDateStr(dateStr);
    var day = next.days[dk];
    if (!day || !Array.isArray(day.exercises))
        return next;
    day.exercises = day.exercises.filter(function(ex) { return ex.id !== exerciseId; });
    return next;
}

function moveExercise(state, dateStr, exerciseId, delta) {
    var next = cloneState(state);
    var dk = formatDateStr(dateStr);
    var day = next.days[dk];
    if (!day || !Array.isArray(day.exercises))
        return next;
    var idx = day.exercises.findIndex(function(ex) { return ex.id === exerciseId; });
    if (idx < 0)
        return next;
    var target = Math.max(0, Math.min(day.exercises.length - 1, idx + Math.trunc(Number(delta) || 0)));
    if (target === idx)
        return next;
    var item = day.exercises.splice(idx, 1)[0];
    day.exercises.splice(target, 0, item);
    return next;
}

function updateDayMetadata(state, dateStr, patch) {
    var next = cloneState(state);
    var dk = formatDateStr(dateStr);
    var day = ensureDay(next, dk, false);
    if (patch && typeof patch === "object") {
        if (patch.title !== undefined)
            day.title = String(patch.title || "").trim().slice(0, 120) || defaultTitleForRoutine(day.routine);
        if (patch.routine !== undefined)
            day.routine = normalizeRoutine(patch.routine);
        if (patch.sessionNote !== undefined)
            day.sessionNote = String(patch.sessionNote || "").slice(0, 1000);
        if (patch.scheduledStart !== undefined)
            day.scheduledStart = normalizeHm(patch.scheduledStart, day.scheduledStart);
        if (patch.scheduledEnd !== undefined)
            day.scheduledEnd = normalizeHm(patch.scheduledEnd, day.scheduledEnd);
        if (patch.scheduledStart !== undefined && patch.scheduledEnd === undefined) {
            var sParts = String(day.scheduledStart).split(":");
            var eParts = String(day.scheduledEnd).split(":");
            var sMin = Number(sParts[0]) * 60 + Number(sParts[1]);
            var eMin = Number(eParts[0]) * 60 + Number(eParts[1]);
            if (Number.isFinite(sMin) && Number.isFinite(eMin) && eMin <= sMin) {
                var durMin = Math.max(15, Number(next.preferences && next.preferences.workoutDefaultDurationMin) || 60);
                var adjMin = Math.min(23 * 60 + 59, sMin + durMin);
                if (adjMin <= sMin)
                    adjMin = Math.min(23 * 60 + 59, sMin + 15);
                day.scheduledEnd = pad2(Math.floor(adjMin / 60)) + ":" + pad2(adjMin % 60);
            }
        }
        if (patch.plannerEventId !== undefined) {
            var eid = Number(patch.plannerEventId);
            day.plannerEventId = (Number.isInteger(eid) && eid > 0) ? eid : 0;
        }
        if (patch.plannerDetached !== undefined) {
            if (patch.plannerDetached)
                day.plannerDetached = true;
            else
                delete day.plannerDetached;
        }
    }
    return next;
}

function addBodyCheckin(state, spec) {
    var next = cloneState(state);
    var id = (spec && spec.id) ? String(spec.id) : ("bc-" + String(next.nextSeq++));
    var bm = id.match(/^bc-(\d+)$/);
    if (bm && Number(bm[1]) >= next.nextSeq)
        next.nextSeq = Number(bm[1]) + 1;
    var dk = formatDateStr((spec && spec.date) || new Date());
    var dayRoutine = (next.days[dk] && next.days[dk].routine) ? next.days[dk].routine : defaultRoutineForDate(next, dk);
    var entry = normalizeCheckin(Object.assign({
        routine: dayRoutine,
        createdAt: new Date().toISOString()
    }, spec || {}, { id: id, date: dk }), next.nextSeq);
    if (!entry)
        return { state: next, checkin: null };
    next.bodyCheckins.unshift(entry);
    next.bodyCheckins.sort(function(a, b) {
        if (a.date !== b.date)
            return b.date.localeCompare(a.date);
        return String(b.createdAt).localeCompare(String(a.createdAt));
    });
    return { state: next, checkin: entry };
}

function removeBodyCheckin(state, checkinId) {
    var next = cloneState(state);
    var removed = null;
    next.bodyCheckins = next.bodyCheckins.filter(function(bc) {
        if (bc.id === checkinId) {
            removed = bc;
            return false;
        }
        return true;
    });
    return { state: next, removed: removed };
}

function formatExerciseTarget(ex) {
    if (!ex)
        return "";
    if (Number(ex.durationSec) > 0 && Number(ex.weight) <= 0) {
        var mins = Math.floor(ex.durationSec / 60);
        var secs = ex.durationSec % 60;
        var durLabel = mins > 0 ? (secs > 0 ? (mins + "m " + secs + "s") : (mins + " min")) : (secs + "s");
        return ex.sets > 1 ? (ex.sets + " × " + durLabel) : durLabel;
    }
    var base = String(ex.sets || 1) + " × " + String(ex.reps || "10");
    if (Number(ex.weight) > 0)
        base += " · " + String(ex.weight) + " " + String(ex.weightUnit || "kg");
    return base;
}

function exerciseVolumeKg(ex) {
    if (!ex)
        return 0;
    var doneSets = ex.completed ? ex.sets : (Number(ex.completedSets) || 0);
    if (doneSets <= 0 || Number(ex.weight) <= 0)
        return 0;
    var repsMatch = String(ex.reps || "").match(/\d+/);
    var repsNum = repsMatch ? Number(repsMatch[0]) : 1;
    var weightKg = ex.weightUnit === "lb" ? (Number(ex.weight) * 0.45359237) : Number(ex.weight);
    return Math.round(doneSets * repsNum * weightKg * 10) / 10;
}

function computeDaySummary(state, dateStr) {
    var dk = formatDateStr(dateStr);
    var day = getOrPreviewDay(state, dk);
    var total = day.exercises.length;
    var completed = 0;
    var volumeKg = 0;
    var estSec = 0;
    for (var i = 0; i < total; i++) {
        var ex = day.exercises[i];
        if (ex.completed)
            completed++;
        volumeKg += exerciseVolumeKg(ex);
        var perSet = ex.durationSec > 0 ? ex.durationSec : 40;
        estSec += ex.sets * (perSet + (ex.restSec || 60));
    }
    var dayCheckins = (state && Array.isArray(state.bodyCheckins))
        ? state.bodyCheckins.filter(function(bc) { return bc.date === dk; })
        : [];
    return {
        date: dk,
        routine: day.routine,
        routineLabel: (ROUTINE_TEMPLATES[day.routine] && ROUTINE_TEMPLATES[day.routine].label) || "Custom",
        title: day.title,
        plannerEventId: day.plannerEventId || 0,
        scheduledStart: day.scheduledStart,
        scheduledEnd: day.scheduledEnd,
        sessionNote: day.sessionNote || "",
        exercises: day.exercises,
        totalExercises: total,
        completedExercises: completed,
        completionPct: total > 0 ? Math.round((completed / total) * 100) : 0,
        volumeKg: Math.round(volumeKg * 10) / 10,
        estimatedDurationMin: total > 0 ? Math.max(5, Math.round(estSec / 60)) : 0,
        bodyCheckins: dayCheckins
    };
}

function hasCompletedActivityOnDate(state, dateStr) {
    var day = state && state.days && state.days[dateStr];
    if (!day || !Array.isArray(day.exercises))
        return false;
    for (var i = 0; i < day.exercises.length; i++) {
        if (day.exercises[i].completed || (Number(day.exercises[i].completedSets) || 0) > 0)
            return true;
    }
    return false;
}

function computeStreakDays(state, todayStr) {
    var cleanToday = formatDateStr(todayStr);
    var cursor = hasCompletedActivityOnDate(state, cleanToday) ? cleanToday : addDaysStr(cleanToday, -1);
    var streak = 0;
    while (streak < 3650 && hasCompletedActivityOnDate(state, cursor)) {
        streak++;
        cursor = addDaysStr(cursor, -1);
    }
    return streak;
}

function computeGlobalSummary(state, todayStr) {
    var cleanToday = formatDateStr(todayStr || new Date());
    var todayInfo = computeDaySummary(state, cleanToday);
    var totalWorkouts = 0;
    var dayKeys = state && state.days ? Object.keys(state.days) : [];
    for (var i = 0; i < dayKeys.length; i++) {
        if (hasCompletedActivityOnDate(state, dayKeys[i]))
            totalWorkouts++;
    }
    var weeklyVol = 0;
    var weeklyDone = 0;
    for (var d = 0; d < 7; d++) {
        var dk = addDaysStr(cleanToday, -d);
        var info = computeDaySummary(state, dk);
        weeklyVol += info.volumeKg;
        if (hasCompletedActivityOnDate(state, dk))
            weeklyDone++;
    }
    var checkins = (state && Array.isArray(state.bodyCheckins)) ? state.bodyCheckins : [];
    var latestWeight = 0;
    var latestBf = 0;
    var latestPhoto = "";
    for (var c = 0; c < checkins.length; c++) {
        if (!latestWeight && checkins[c].weightKg > 0)
            latestWeight = checkins[c].weightKg;
        if (!latestBf && checkins[c].bodyFatPct > 0)
            latestBf = checkins[c].bodyFatPct;
        if (!latestPhoto && checkins[c].photoPath)
            latestPhoto = checkins[c].photoPath;
    }
    return {
        todayDate: cleanToday,
        todayRoutine: todayInfo.routine,
        todayTitle: todayInfo.title,
        todayTotalExercises: todayInfo.totalExercises,
        todayCompletedExercises: todayInfo.completedExercises,
        todayCompletionPct: todayInfo.completionPct,
        todayVolumeKg: todayInfo.volumeKg,
        weeklyVolumeKg: Math.round(weeklyVol * 10) / 10,
        weeklyWorkoutsCompleted: weeklyDone,
        currentStreakDays: computeStreakDays(state, cleanToday),
        totalLoggedWorkouts: totalWorkouts,
        totalBodyCheckins: checkins.length,
        latestWeightKg: latestWeight,
        latestBodyFatPct: latestBf,
        latestPhotoPath: latestPhoto
    };
}

// ── Weekly Planner Two-Way Sync Helpers ──

function isWorkoutPlannerEvent(event) {
    if (!event || typeof event !== "object")
        return false;
    var cat = String(event.category || "").trim().toLowerCase();
    if (cat === "workout" || cat === "exercise" || cat === "fitness")
        return true;
    var title = String(event.title || "").trim();
    var desc = String(event.description || "").trim();
    if (/^\[(?:workout|exercise|gym|training)\]/i.test(title))
        return true;
    if (/(?:^|\s)#(?:workout|exercise|gym)\b/i.test(title + " " + desc))
        return true;
    return false;
}

function parseExerciseLine(line) {
    var rawLine = String(line || "");
    var hasCheckbox = /^\s*(?:[-*•]\s*)?\[[ xX]\]/.test(rawLine);
    var done = /^\s*(?:[-*•]\s*)?\[[xX]\]/.test(rawLine);
    var clean = rawLine
        .replace(/^\s*(?:[-*•]|\d+[.)])\s*/, "")
        .replace(/^\[[ xX]\]\s*/, "")
        .trim();
    if (!clean.length)
        return null;
    // Match e.g. "Barbell Bench Press — 4 × 8 · 60 kg" or "Squat: 4x10 @ 80kg"
    var setsRepsWeight = clean.match(/^(.+?)\s*(?:[—–:\-|]\s*)?(\d+)\s*[x×]\s*([0-9-]+)(?:\s*(?:·|@|-)?\s*(\d+(?:\.\d+)?)\s*(kg|lb)s?)?$/i);
    if (setsRepsWeight) {
        return {
            name: setsRepsWeight[1].trim(),
            category: inferCategoryFromName(setsRepsWeight[1]),
            sets: Number(setsRepsWeight[2]) || 3,
            reps: setsRepsWeight[3],
            weight: setsRepsWeight[4] ? Number(setsRepsWeight[4]) : 0,
            weightUnit: setsRepsWeight[5] ? setsRepsWeight[5].toLowerCase() : "kg",
            durationSec: 0,
            completed: done,
            hasCheckbox: hasCheckbox
        };
    }
    var durationMatch = clean.match(/^(.+?)\s*(?:[—–:\-|]\s*)?(\d+)\s*(min|mins|minutes|s|sec|seconds)$/i);
    if (durationMatch) {
        var mult = /^s/i.test(durationMatch[3]) ? 1 : 60;
        return {
            name: durationMatch[1].trim(),
            category: inferCategoryFromName(durationMatch[1]),
            sets: 1,
            reps: "1",
            weight: 0,
            weightUnit: "kg",
            durationSec: Number(durationMatch[2]) * mult,
            completed: done,
            hasCheckbox: hasCheckbox
        };
    }
    return {
        name: clean,
        category: inferCategoryFromName(clean),
        sets: 3,
        reps: "10",
        weight: 0,
        weightUnit: "kg",
        durationSec: 0,
        completed: done,
        hasCheckbox: hasCheckbox
    };
}

function inferCategoryFromName(name) {
    var lower = String(name || "").toLowerCase();
    if (/bench|chest|push-?up|pec|fly|dip/.test(lower))
        return "chest";
    if (/row|pull-?up|pulldown|lat|chin-?up|deadlift/.test(lower) && !/romanian/.test(lower))
        return "back";
    if (/overhead|shoulder|lateral|delt|face pull|press/.test(lower) && !/bench|leg/.test(lower))
        return "shoulders";
    if (/squat|lunge|leg|calf|romanian|hamstring|glute|hip thrust/.test(lower))
        return "legs";
    if (/curl|tricep|bicep|extension|pushdown|skull/.test(lower))
        return "arms";
    if (/plank|ab|core|crunch|leg raise|woodchop|rollout/.test(lower))
        return "core";
    if (/run|cycle|bike|row|jump rope|cardio|hiit|swim|walk/.test(lower))
        return "cardio";
    if (/stretch|mobility|yoga|foam/.test(lower))
        return "mobility";
    return "chest";
}

function inferRoutineFromText(text) {
    var lower = String(text || "").toLowerCase();
    if (/\bpush\b/.test(lower))
        return "push";
    if (/\bpull\b/.test(lower))
        return "pull";
    if (/\blegs?\b|\blower body\b/.test(lower))
        return "legs";
    if (/\bcore\b|\babs\b/.test(lower))
        return "core";
    if (/\bcardio\b|\brunning\b|\bconditioning\b/.test(lower))
        return "cardio";
    if (/\bfull[\s_-]*body\b/.test(lower))
        return "full_body";
    if (/\brecovery\b|\bmobility\b|\brest\b/.test(lower))
        return "rest";
    return "custom";
}

function parsePlannerWorkoutEvent(event) {
    if (!isWorkoutPlannerEvent(event))
        return null;
    var rawTitle = String(event.title || "Workout").trim();
    var cleanTitle = rawTitle.replace(/^\[(?:workout|exercise|gym|training)\]\s*/i, "").replace(/#(?:workout|exercise|gym)\b/gi, "").trim() || "Planned Workout";
    var routine = inferRoutineFromText(cleanTitle + " " + String(event.description || ""));
    var startD = new Date(event.startDate || event.dateTime);
    var endD = new Date(event.endDate);
    var startHm = Number.isFinite(startD.getTime()) ? (pad2(startD.getHours()) + ":" + pad2(startD.getMinutes())) : "18:00";
    var endHm = Number.isFinite(endD.getTime()) ? (pad2(endD.getHours()) + ":" + pad2(endD.getMinutes())) : "19:00";
    var lines = String(event.description || "").split(/\r?\n/);
    var exercises = [];
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i].trim();
        if (!line || /^#/.test(line) || /^routine:/i.test(line))
            continue;
        var parsed = parseExerciseLine(line);
        if (parsed)
            exercises.push(parsed);
    }
    if (exercises.length === 0 && routine !== "custom" && ROUTINE_TEMPLATES[routine]) {
        exercises = ROUTINE_TEMPLATES[routine].exercises.map(function(e) {
            return Object.assign({}, e);
        });
    }
    return {
        eventId: Number(event.id) || 0,
        title: cleanTitle,
        routine: routine,
        startHm: startHm,
        endHm: endHm,
        allDay: event.allDay === true,
        exercises: exercises
    };
}

function importPlannerWorkoutIntoDay(state, dateStr, parsedEvent) {
    return reconcilePlannerWorkoutEvent(state, dateStr, parsedEvent).state;
}

function reconcilePlannerWorkoutEvent(state, dateStr, parsedEvent) {
    if (!parsedEvent)
        return { state: cloneState(state), changed: false };
    var next = cloneState(state);
    var dk = formatDateStr(dateStr);
    var hadDay = Boolean(next.days && next.days[dk]);
    var beforeJson = hadDay ? JSON.stringify(next.days[dk]) : "";
    var day = ensureDay(next, dk, false);
    if (parsedEvent.eventId > 0)
        day.plannerEventId = parsedEvent.eventId;
    if (parsedEvent.routine && day.exercises.length === 0)
        day.routine = parsedEvent.routine;
    if (parsedEvent.title)
        day.title = parsedEvent.title;
    if (!parsedEvent.allDay) {
        day.scheduledStart = normalizeHm(parsedEvent.startHm, day.scheduledStart);
        day.scheduledEnd = normalizeHm(parsedEvent.endHm, day.scheduledEnd);
    }
    var byKey = {};
    for (var i = 0; i < day.exercises.length; i++)
        byKey[normalizeExerciseLookupKey(day.exercises[i].name)] = day.exercises[i];
    var incoming = Array.isArray(parsedEvent.exercises) ? parsedEvent.exercises : [];
    for (var j = 0; j < incoming.length; j++) {
        var item = incoming[j];
        if (!item || !item.name)
            continue;
        var key = normalizeExerciseLookupKey(item.name);
        if (byKey[key]) {
            if (item.hasCheckbox && typeof item.completed === "boolean" && byKey[key].completed !== item.completed) {
                byKey[key].completed = item.completed;
                byKey[key].completedSets = item.completed ? byKey[key].sets : 0;
            }
            continue;
        }
        var id = "ex-" + String(next.nextSeq++);
        var norm = normalizeExercise(Object.assign({}, item, { id: id }), next.nextSeq, next.preferences.weightUnit, next.preferences.defaultRestSeconds);
        if (norm) {
            byKey[key] = norm;
            day.exercises.push(norm);
        }
    }
    var afterJson = JSON.stringify(next.days[dk]);
    return { state: next, changed: !hadDay || beforeJson !== afterJson };
}

function normalizeExerciseLookupKey(name) {
    var s = String(name || "").toLowerCase();
    if (typeof s.normalize === "function")
        s = s.normalize("NFD").replace(/[\u0300-\u036f]/g, "");
    s = s.replace(/đ/g, "d");
    s = s.replace(/[^a-z0-9]+/g, " ").trim().replace(/\s+/g, " ");
    return s;
}

function _exerciseLookupVariants(name) {
    var base = normalizeExerciseLookupKey(name);
    if (!base)
        return [];
    var out = [base];
    var deplural = base.replace(/\b([a-z0-9]{3,})s\b/g, "$1");
    if (deplural !== base)
        out.push(deplural);
    var compact = deplural.replace(/\s+/g, "");
    if (compact && out.indexOf(compact) === -1)
        out.push(compact);
    return out;
}

function matchNexusExercise(exercise, nexusLibrary) {
    if (!exercise || !Array.isArray(nexusLibrary) || nexusLibrary.length === 0)
        return null;
    var targetRel = String(exercise.nexusRelPath || exercise.relPath || "").trim();
    if (targetRel) {
        for (var i = 0; i < nexusLibrary.length; i++) {
            if (String(nexusLibrary[i]?.relPath || "").trim() === targetRel)
                return nexusLibrary[i];
        }
    }
    var exName = String(exercise.name || exercise.title || "").trim();
    if (!exName)
        return null;
    var segments = [exName];
    if (exName.indexOf("/") !== -1) {
        var splitSegs = exName.split("/");
        for (var s = 0; s < splitSegs.length; s++) {
            var trimmed = splitSegs[s].trim();
            if (trimmed)
                segments.push(trimmed);
        }
    }
    var exVariants = {};
    for (var sg = 0; sg < segments.length; sg++) {
        var vars = _exerciseLookupVariants(segments[sg]);
        for (var v = 0; v < vars.length; v++)
            exVariants[vars[v]] = true;
    }
    for (var j = 0; j < nexusLibrary.length; j++) {
        var item = nexusLibrary[j];
        var itemVars = _exerciseLookupVariants(item?.title || item?.name || "");
        for (var k = 0; k < itemVars.length; k++) {
            if (exVariants[itemVars[k]])
                return item;
        }
    }
    var tokens = normalizeExerciseLookupKey(exName).split(" ").filter(function(w) { return w.length >= 3; });
    if (tokens.length >= 2) {
        var matches = [];
        for (var m = 0; m < nexusLibrary.length; m++) {
            var candKey = normalizeExerciseLookupKey(nexusLibrary[m]?.title || nexusLibrary[m]?.name || "");
            if (!candKey)
                continue;
            var allPresent = true;
            for (var t = 0; t < tokens.length; t++) {
                if (candKey.indexOf(tokens[t]) === -1) {
                    allPresent = false;
                    break;
                }
            }
            if (allPresent)
                matches.push(nexusLibrary[m]);
        }
        if (matches.length === 1)
            return matches[0];
    }
    return null;
}

function searchExercisesCatalog(query, nexusLibrary, state, maxResults) {
    var limit = Math.max(1, Math.min(50, Math.round(Number(maxResults) || 20)));
    var historyByRel = {};
    var historyByKey = {};
    var historyList = [];
    var days = (state && state.days && typeof state.days === "object") ? state.days : {};
    var dayKeys = Object.keys(days).sort().reverse();
    for (var d = 0; d < dayKeys.length; d++) {
        var day = days[dayKeys[d]];
        var exArr = Array.isArray(day?.exercises) ? day.exercises : [];
        for (var e = 0; e < exArr.length; e++) {
            var ex = exArr[e];
            if (!ex || !ex.name)
                continue;
            var hKey = normalizeExerciseLookupKey(ex.name);
            var hRel = String(ex.nexusRelPath || "").trim();
            var entry = {
                name: String(ex.name),
                category: normalizeCategory(ex.category),
                sets: Number(ex.sets) || 3,
                reps: String(ex.reps || "10"),
                weight: Number(ex.weight) || 0,
                weightUnit: ex.weightUnit || "kg",
                restSec: Number(ex.restSec) || 90,
                durationSec: Number(ex.durationSec) || 0,
                nexusRelPath: hRel,
                equipment: String(ex.equipment || ""),
                primaryMuscles: normalizeStringList(ex.primaryMuscles),
                secondaryMuscles: normalizeStringList(ex.secondaryMuscles),
                previewUrl: String(ex.previewUrl || ""),
                animationUrl: String(ex.animationUrl || "")
            };
            if (hRel && !historyByRel[hRel])
                historyByRel[hRel] = entry;
            if (hKey && !historyByKey[hKey]) {
                historyByKey[hKey] = entry;
                historyList.push(entry);
            }
        }
    }

    var catalog = [];
    var seenKeys = {};
    var lib = Array.isArray(nexusLibrary) ? nexusLibrary : [];
    for (var i = 0; i < lib.length; i++) {
        var nx = lib[i];
        if (!nx)
            continue;
        var title = String(nx.title || nx.name || "").trim();
        var relPath = String(nx.relPath || "").trim();
        if (!title)
            continue;
        var nKey = normalizeExerciseLookupKey(title);
        var hist = (relPath && historyByRel[relPath]) || historyByKey[nKey] || null;
        var pMuscles = normalizeStringList(nx.primaryMuscles !== undefined ? nx.primaryMuscles : nx.muscleGroup);
        var sMuscles = normalizeStringList(nx.secondaryMuscles);
        var cat = normalizeCategory((pMuscles[0]) || nx.category || inferCategoryFromName(title));
        seenKeys[nKey] = true;
        catalog.push({
            id: "nexus:" + (relPath || nKey),
            source: "nexus",
            sourceLabel: "Nexus",
            title: title,
            relPath: relPath,
            category: cat,
            primaryMuscles: pMuscles.length > 0 ? pMuscles : fallbackMusclesForCategory(cat),
            secondaryMuscles: sMuscles,
            equipment: String(nx.equipment || ""),
            level: String(nx.level || ""),
            force: String(nx.force || ""),
            mechanic: String(nx.mechanic || ""),
            previewUrl: String(nx.posterUrl || nx.previewUrl || ""),
            animationUrl: String(nx.featuredImageUrl || nx.animationUrl || ""),
            usedRecently: hist !== null,
            sets: hist ? hist.sets : 0,
            reps: hist ? hist.reps : "",
            weight: hist ? hist.weight : 0,
            restSec: hist ? hist.restSec : 0,
            durationSec: hist ? hist.durationSec : 0
        });
    }

    for (var h = 0; h < historyList.length; h++) {
        var hi = historyList[h];
        var hk = normalizeExerciseLookupKey(hi.name);
        if (seenKeys[hk])
            continue;
        seenKeys[hk] = true;
        var hCat = normalizeCategory(hi.category);
        catalog.push({
            id: "history:" + hk,
            source: "history",
            sourceLabel: "Recent",
            title: hi.name,
            relPath: hi.nexusRelPath,
            category: hCat,
            primaryMuscles: hi.primaryMuscles.length > 0 ? hi.primaryMuscles : fallbackMusclesForCategory(hCat),
            secondaryMuscles: hi.secondaryMuscles,
            equipment: hi.equipment,
            level: "",
            force: "",
            mechanic: "",
            previewUrl: hi.previewUrl,
            animationUrl: hi.animationUrl,
            usedRecently: true,
            sets: hi.sets,
            reps: hi.reps,
            weight: hi.weight,
            restSec: hi.restSec,
            durationSec: hi.durationSec
        });
    }

    var tplKeys = Object.keys(ROUTINE_TEMPLATES);
    for (var tk = 0; tk < tplKeys.length; tk++) {
        var tplExList = ROUTINE_TEMPLATES[tplKeys[tk]].exercises || [];
        for (var te = 0; te < tplExList.length; te++) {
            var tex = tplExList[te];
            var tKey = normalizeExerciseLookupKey(tex.name);
            if (!tKey || seenKeys[tKey])
                continue;
            seenKeys[tKey] = true;
            var tCat = normalizeCategory(tex.category);
            catalog.push({
                id: "template:" + tKey,
                source: "template",
                sourceLabel: "Preset",
                title: tex.name,
                relPath: "",
                category: tCat,
                primaryMuscles: fallbackMusclesForCategory(tCat),
                secondaryMuscles: [],
                equipment: "",
                level: "",
                force: "",
                mechanic: "",
                previewUrl: "",
                animationUrl: "",
                usedRecently: false,
                sets: tex.sets || 3,
                reps: String(tex.reps || "10"),
                weight: tex.weight || 0,
                restSec: tex.restSec || 90,
                durationSec: tex.durationSec || 0
            });
        }
    }

    var qNorm = normalizeExerciseLookupKey(query);
    var qTokens = qNorm ? qNorm.split(" ") : [];
    var scored = [];
    for (var c = 0; c < catalog.length; c++) {
        var entryItem = catalog[c];
        var titleKey = normalizeExerciseLookupKey(entryItem.title);
        var metaBlob = normalizeExerciseLookupKey(
            entryItem.title + " " + entryItem.primaryMuscles.join(" ") + " "
            + entryItem.secondaryMuscles.join(" ") + " " + entryItem.equipment + " " + entryItem.category
        );
        var score = 0;
        if (qTokens.length === 0) {
            score = (entryItem.usedRecently ? 120 : 0)
                + (entryItem.source === "nexus" ? 50 : (entryItem.source === "history" ? 25 : 10));
        } else {
            var matchesAll = true;
            for (var qt = 0; qt < qTokens.length; qt++) {
                if (metaBlob.indexOf(qTokens[qt]) === -1) {
                    matchesAll = false;
                    break;
                }
            }
            if (!matchesAll)
                continue;
            if (titleKey === qNorm)
                score = 1000;
            else if (titleKey.indexOf(qNorm) === 0)
                score = 700;
            else if ((" " + titleKey).indexOf(" " + qNorm) !== -1)
                score = 520;
            else if (titleKey.indexOf(qNorm) !== -1)
                score = 380;
            else if (qTokens.every(function(tok) { return titleKey.indexOf(tok) !== -1; }))
                score = 320;
            else
                score = 180;
            score += (entryItem.source === "nexus" ? 30 : (entryItem.usedRecently ? 20 : 5));
        }
        scored.push({ score: score, item: entryItem });
    }
    scored.sort(function(a, b) {
        if (b.score !== a.score)
            return b.score - a.score;
        return a.item.title.localeCompare(b.item.title);
    });
    return scored.slice(0, limit).map(function(x) { return x.item; });
}

function buildUnsyncedPlannerEvents(state, existingLocalEvents) {
    var localList = Array.isArray(existingLocalEvents) ? existingLocalEvents : [];
    var localById = {};
    var workoutDateCovered = {};
    for (var i = 0; i < localList.length; i++) {
        var ev = localList[i];
        if (!ev)
            continue;
        if (Number(ev.id) > 0)
            localById[Number(ev.id)] = true;
        if (isWorkoutPlannerEvent(ev)) {
            var dkEv = formatDateStr(ev.startDate || ev.dateTime);
            if (dkEv)
                workoutDateCovered[dkEv] = true;
        }
    }
    var days = (state && state.days && typeof state.days === "object") ? state.days : {};
    var out = [];
    var keys = Object.keys(days).sort();
    for (var j = 0; j < keys.length; j++) {
        var dk = keys[j];
        var day = days[dk];
        if (!day || !Array.isArray(day.exercises) || day.exercises.length === 0 || day.plannerDetached === true)
            continue;
        var evId = Number(day.plannerEventId) || 0;
        if ((evId > 0 && localById[evId]) || workoutDateCovered[dk])
            continue;
        var payload = buildPlannerEventPayload(state, dk);
        out.push({
            id: "workout-day:" + dk,
            uid: "workout-day:" + dk,
            sourceKind: "exerciseWorkout",
            workoutDate: dk,
            title: payload.title,
            description: payload.description,
            startDate: payload.startIso,
            endDate: payload.endIso,
            dateTime: payload.startIso,
            allDay: false,
            category: "workout",
            sourceColor: "#6D8B76"
        });
    }
    return out;
}

function buildPlannerEventPayload(state, dateStr) {
    var dk = formatDateStr(dateStr);
    var info = computeDaySummary(state, dk);
    var parts = dk.split("-");
    var startParts = normalizeHm(info.scheduledStart, "18:00").split(":");
    var endParts = normalizeHm(info.scheduledEnd, "19:00").split(":");
    var startDate = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]), Number(startParts[0]), Number(startParts[1]), 0, 0);
    var endDate = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]), Number(endParts[0]), Number(endParts[1]), 0, 0);
    if (endDate <= startDate)
        endDate = new Date(startDate.getTime() + 3600000);
    var lines = [];
    for (var i = 0; i < info.exercises.length; i++) {
        var ex = info.exercises[i];
        var box = ex.completed ? "[x] " : "[ ] ";
        lines.push("- " + box + ex.name + " — " + formatExerciseTarget(ex));
    }
    if (info.sessionNote)
        lines.push("\n" + info.sessionNote);
    lines.push("#workout · " + dk);
    var prefRem = Math.round(Number(state && state.preferences && state.preferences.workoutReminderMinutes !== undefined
        ? state.preferences.workoutReminderMinutes : 15));
    return {
        plannerEventId: info.plannerEventId,
        title: "[Workout] " + info.title,
        description: lines.join("\n"),
        startIso: startDate.toISOString(),
        endIso: endDate.toISOString(),
        category: "reminder",
        priority: "normal",
        reminderMinutes: Number.isFinite(prefRem) ? Math.max(0, Math.min(1440, prefRem)) : 15
    };
}

function exportWorkoutMarkdown(state, dateStr) {
    var dk = formatDateStr(dateStr);
    var info = computeDaySummary(state, dk);
    var out = [];
    out.push("# " + info.title + " (" + dk + ")");
    out.push("");
    out.push("- **Routine:** " + info.routineLabel);
    out.push("- **Completed:** " + String(info.completedExercises) + " / " + String(info.totalExercises) + " (" + String(info.completionPct) + "%)");
    out.push("- **Volume:** " + String(info.volumeKg) + " kg");
    if (info.scheduledStart)
        out.push("- **Scheduled:** " + info.scheduledStart + " – " + info.scheduledEnd);
    out.push("- **Tags:** #workout #exercises-tracker");
    out.push("");
    out.push("## Exercises");
    if (info.exercises.length === 0) {
        out.push("_No exercises logged for this date._");
    } else {
        for (var i = 0; i < info.exercises.length; i++) {
            var ex = info.exercises[i];
            out.push("- [" + (ex.completed ? "x" : " ") + "] **" + ex.name + "** (" + ex.category + ") — " + formatExerciseTarget(ex));
        }
    }
    if (info.sessionNote) {
        out.push("");
        out.push("## Session Notes");
        out.push(info.sessionNote);
    }
    if (info.bodyCheckins.length > 0) {
        out.push("");
        out.push("## Post-Workout Body Tracker");
        for (var c = 0; c < info.bodyCheckins.length; c++) {
            var bc = info.bodyCheckins[c];
            var metrics = [];
            if (bc.weightKg > 0)
                metrics.push(String(bc.weightKg) + " kg");
            if (bc.bodyFatPct > 0)
                metrics.push(String(bc.bodyFatPct) + "% BF");
            if (bc.note)
                metrics.push(bc.note);
            out.push("- **" + bc.date + "**" + (metrics.length ? (": " + metrics.join(" · ")) : ""));
            if (bc.photoVaultRel)
                out.push("  ![[" + String(bc.photoVaultRel) + "]]");
        }
    }
    return out.join("\n") + "\n";
}

function updatePreferences(state, patch, todayStr) {
    var next = cloneState(state);
    var merged = Object.assign({}, next.preferences || {}, (patch && typeof patch === "object") ? patch : {});
    next.preferences = normalizePreferences(merged);
    return normalizeState(next, todayStr);
}

function updateWeeklyTemplate(state, weekdayKey, routineKey, todayStr) {
    var next = cloneState(state);
    var wd = String(Math.max(0, Math.min(6, Math.floor(Number(weekdayKey) || 0))));
    next.weeklyTemplates = Object.assign({}, DEFAULT_WEEKLY_TEMPLATES, next.weeklyTemplates || {});
    next.weeklyTemplates[wd] = normalizeRoutine(routineKey);
    return normalizeState(next, todayStr);
}

function applyWeeklySplitPreset(state, presetKey, todayStr) {
    var presets = {
        ppl: { "1": "push", "2": "pull", "3": "legs", "4": "rest", "5": "push", "6": "pull", "0": "core" },
        full_body: { "1": "full_body", "2": "cardio", "3": "full_body", "4": "rest", "5": "full_body", "6": "core", "0": "rest" },
        upper_lower: { "1": "push", "2": "legs", "3": "rest", "4": "pull", "5": "legs", "6": "core", "0": "rest" },
        cardio_core: { "1": "cardio", "2": "core", "3": "cardio", "4": "rest", "5": "cardio", "6": "full_body", "0": "rest" }
    };
    var chosen = presets[String(presetKey || "ppl")] || presets.ppl;
    var next = cloneState(state);
    next.weeklyTemplates = Object.assign({}, chosen);
    return normalizeState(next, todayStr);
}
