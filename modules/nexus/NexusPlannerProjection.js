.pragma library

// Shared projection & swatch helper for Nexus Weekly Planner & Daily Schedule.
// Mirrors Alis/modules/dashboard/WeeklyPlannerPolicy.js,
// Alis/services/EventFutureSchedule.js, and Alis/modules/dashboard/PlannerEventPalette.js
// so Nexus Weekly Planner and Daily Schedule stay 100% synchronized with DashboardWeeklyPlanner.qml.

var minute = 60000;
var hour = 60 * minute;
var dayMs = 86400000;

function validDate(value) {
    if (value === undefined || value === null || value === "")
        return null;
    if (typeof value === "string" && /^\d{4}-\d{2}-\d{2}$/.test(value.trim())) {
        var parts = value.trim().split("-");
        var localD = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]), 0, 0, 0, 0);
        return Number.isFinite(localD.getTime()) ? localD : null;
    }
    var d = new Date(value);
    return Number.isFinite(d.getTime()) ? d : null;
}

function midnight(value) {
    var d = validDate(value) || new Date();
    var out = new Date(d.getTime());
    out.setHours(0, 0, 0, 0);
    return out;
}

function addDays(value, count) {
    var d = new Date(value.getTime());
    d.setDate(d.getDate() + count);
    return d;
}

function civil(value) {
    return Date.UTC(value.getFullYear(), value.getMonth(), value.getDate());
}

function civilIndex(value) {
    return civil(value) / dayMs;
}

function formatIsoDate(value) {
    var d = validDate(value);
    if (!d)
        return "";
    var y = String(d.getFullYear());
    var m = String(d.getMonth() + 1).padStart(2, "0");
    var day = String(d.getDate()).padStart(2, "0");
    return y + "-" + m + "-" + day;
}

function formatHm(value) {
    var d = validDate(value);
    if (!d)
        return "";
    return String(d.getHours()).padStart(2, "0") + ":" + String(d.getMinutes()).padStart(2, "0");
}

// ── EventFutureSchedule projection ──
function clock(value) {
    return [value.getHours(), value.getMinutes(), value.getSeconds(), value.getMilliseconds()];
}

function supportedRecurrence(mode) {
    return ["daily", "weekly", "monthly", "yearly"].indexOf(mode) !== -1;
}

function slots(event) {
    return Array.isArray(event.occurrences) && event.occurrences.length
        ? event.occurrences : [event];
}

function anchor(slot) {
    var start = validDate(slot.plannerSeriesStartDate || slot.startDate || slot.dateTime);
    var end = validDate(slot.plannerSeriesEndDate || slot.endDate);
    if (!start)
        return null;
    if (!end || end <= start)
        end = new Date(start.getTime() + 3600000);
    return { start: start, end: end };
}

function signature(mode, start, end) {
    return JSON.stringify([
        mode,
        mode === "daily" ? 0
            : mode === "weekly" ? start.getDay()
            : mode === "monthly" ? start.getDate()
            : [start.getMonth(), start.getDate()],
        clock(start),
        (civil(end) - civil(start)) / dayMs,
        clock(end)
    ]);
}

function validRule(rule) {
    return Boolean(
        rule && rule.version === 1 && supportedRecurrence(rule.mode)
        && typeof rule.key === "string" && rule.key.length > 0
        && Number.isSafeInteger(rule.fromCycle)
        && Number.isSafeInteger(rule.anchorCycle)
        && validDate(rule.rootStartDate) && validDate(rule.rootEndDate)
        && validDate(rule.startDate) && validDate(rule.endDate)
        && (validDate(rule.endDate) - validDate(rule.startDate) >= 15 * 60000)
    );
}

function rules(event) {
    return Array.isArray(event.plannerFutureSchedule)
        ? event.plannerFutureSchedule.filter(function(rule) {
            return validRule(rule) && rule.mode === event.recurrence;
        }) : [];
}

function hasFutureSchedule(event) {
    return Boolean(event && supportedRecurrence(event.recurrence) && rules(event).length > 0);
}

function cycleOf(start, value, mode) {
    if (mode === "daily" || mode === "weekly")
        return Math.floor((civil(value) - civil(start)) / dayMs / (mode === "daily" ? 1 : 7));
    if (mode === "monthly")
        return 12 * (value.getFullYear() - start.getFullYear()) + value.getMonth() - start.getMonth();
    return value.getFullYear() - start.getFullYear();
}

function cycleIndex(value, mode) {
    if (mode === "daily")
        return civil(value) / dayMs;
    if (mode === "weekly")
        return Math.floor((civil(value) / dayMs - 4) / 7);
    if (mode === "monthly")
        return value.getFullYear() * 12 + value.getMonth();
    return value.getFullYear();
}

function atCycle(startValue, endValue, mode, step) {
    var start = validDate(startValue), end = validDate(endValue);
    if (!start || !end || end <= start || !Number.isInteger(step))
        return null;
    var year = start.getFullYear(), month = start.getMonth(), day = start.getDate();
    if (mode === "daily" || mode === "weekly") {
        var moved = new Date(year, month, day + step * (mode === "daily" ? 1 : 7), 12);
        year = moved.getFullYear();
        month = moved.getMonth();
        day = moved.getDate();
    } else if (mode === "monthly") {
        var target = new Date(year, month + step, 1, 12);
        year = target.getFullYear();
        month = target.getMonth();
    } else if (mode === "yearly") {
        year += step;
    } else {
        return null;
    }
    var begin = new Date(year, month, day, start.getHours(), start.getMinutes(), start.getSeconds(), start.getMilliseconds());
    if (begin.getFullYear() !== year || begin.getMonth() !== month || begin.getDate() !== day)
        return null;
    var finish = new Date(year, month, day + (civil(end) - civil(start)) / dayMs, end.getHours(), end.getMinutes(), end.getSeconds(), end.getMilliseconds());
    return finish > begin ? { startDate: begin.toISOString(), endDate: finish.toISOString() } : null;
}

function rootRange(info, mode, cycle) {
    return atCycle(info.rootStartDate, info.rootEndDate, mode, cycle - cycleIndex(validDate(info.rootStartDate), mode));
}

function branch(event, index) {
    var entries = slots(event), slot = entries[index], range = slot && anchor(slot);
    if (!range || !supportedRecurrence(event.recurrence))
        return null;
    var key = slot.plannerBranchKey || signature(event.recurrence, range.start, range.end);
    var known = rules(event).find(function(rule) { return rule.key === key; });
    if (known)
        return { key: key, rootStartDate: known.rootStartDate, rootEndDate: known.rootEndDate };
    var candidates = entries.concat(
        Array.isArray(event.repeatTemplate) ? event.repeatTemplate : [],
        Array.isArray(event.selectedTemplate) ? event.selectedTemplate : []
    );
    candidates.forEach(function(candidate) {
        var other = anchor(candidate);
        if (other && signature(event.recurrence, other.start, other.end) === key && other.start < range.start)
            range = other;
    });
    return { key: key, rootStartDate: range.start.toISOString(), rootEndDate: range.end.toISOString() };
}

function resolved(event, info, cycle) {
    var selected = null;
    rules(event).forEach(function(rule) {
        if (rule.key === info.key && rule.fromCycle <= cycle)
            selected = rule;
    });
    return selected
        ? atCycle(selected.startDate, selected.endDate, event.recurrence, cycle - selected.anchorCycle)
        : rootRange(info, event.recurrence, cycle);
}

function cycleForSlot(event, index) {
    var slot = slots(event)[index];
    return Number.isInteger(slot.plannerScheduleCycle)
        ? slot.plannerScheduleCycle
        : cycleIndex(anchor(slot).start, event.recurrence);
}

function branches(event) {
    var found = new Map(), entries = slots(event);
    var first = Array.isArray(event.repeatTemplate) && event.repeatTemplate.length
        ? Math.max(0, Number(event.repeatCycleStart) || 0)
        : Array.isArray(event.selectedTemplate) && event.selectedTemplate.length
            ? Math.max(0, entries.length - event.selectedTemplate.length) : 0;
    entries.forEach(function(slot, index) {
        if (index < first)
            return;
        var info = branch(event, index);
        if (!info)
            return;
        var cycle = cycleForSlot(event, index), previous = found.get(info.key);
        if (!previous || cycle >= previous.cycle)
            found.set(info.key, Object.assign({}, info, { index: index, cycle: cycle }));
    });
    return Array.from(found.values());
}

function pendingOverride(event, info, cycle) {
    var original = rootRange(info, event.recurrence, cycle);
    if (!original || !Array.isArray(event.plannerOverrides))
        return null;
    return event.plannerOverrides.find(function(item) {
        var source = Number.isInteger(item.occurrenceIndex) && branch(event, item.occurrenceIndex);
        var start = validDate(item.startDate), end = validDate(item.endDate);
        return source && source.key === info.key && item.originalStartDate === original.startDate
            && item.materializedOccurrenceIndex === undefined && item.forwardedEventId === undefined
            && start && end && (end - start >= 15 * 60000);
    }) || null;
}

function projectFutureSchedule(event, beginValue, endValue) {
    var begin = validDate(beginValue), end = validDate(endValue), result = [], saved = new Set();
    if (!begin || !end)
        return result;
    slots(event).forEach(function(slot, index) {
        var info = branch(event, index), start = validDate(slot.startDate || slot.dateTime), finish = validDate(slot.endDate);
        if (!info || !start)
            return;
        if (!finish || finish <= start)
            finish = new Date(start.getTime() + 3600000);
        var cycle = cycleForSlot(event, index);
        saved.add(JSON.stringify([info.key, cycle]));
        if (start < end && finish > begin) {
            result.push({
                startDate: start.toISOString(),
                endDate: finish.toISOString(),
                occurrenceIndex: index,
                virtual: false,
                branchKey: info.key,
                cycle: cycle,
                originalStartIso: ""
            });
        }
    });
    if (!Array.isArray(event.occurrences) && event.notified === true)
        return result;
    branches(event).forEach(function(info) {
        var candidates = new Set();
        var sources = [{
            startDate: info.rootStartDate,
            anchorCycle: cycleIndex(validDate(info.rootStartDate), event.recurrence)
        }].concat(rules(event).filter(function(rule) { return rule.key === info.key; }));
        sources.forEach(function(rule) {
            var first = rule.anchorCycle + cycleOf(validDate(rule.startDate), begin, event.recurrence) - 3;
            var last = rule.anchorCycle + cycleOf(validDate(rule.startDate), end, event.recurrence) + 3;
            for (var cycle = first; cycle <= last && candidates.size < 1024; cycle++)
                candidates.add(cycle);
        });
        Array.from(candidates).sort(function(a, b) { return a - b; }).forEach(function(cycle) {
            if (cycle <= info.cycle || saved.has(JSON.stringify([info.key, cycle])))
                return;
            var range = pendingOverride(event, info, cycle) || resolved(event, info, cycle);
            if (!range || validDate(range.startDate) >= end || validDate(range.endDate) <= begin)
                return;
            var original = rootRange(info, event.recurrence, cycle);
            result.push(Object.assign({}, range, {
                occurrenceIndex: info.index,
                virtual: true,
                branchKey: info.key,
                cycle: cycle,
                originalStartIso: (original && original.startDate) ? original.startDate : range.startDate
            }));
        });
    });
    return result;
}

// ── WeeklyPlannerPolicy projection ──
function week(value, firstDay) {
    var start = midnight(value);
    var fd = (firstDay === undefined || firstDay === null) ? 1 : Number(firstDay);
    start.setDate(start.getDate() - (start.getDay() - fd + 7) % 7);
    return Array.from({ length: 7 }, function(_, index) {
        var d = addDays(start, index), end = addDays(d, 1);
        return {
            date: d,
            end: end,
            dateStr: formatIsoDate(d),
            minutes: (end - d) / minute,
            timed: [],
            allDay: [],
            overflow: 0
        };
    });
}

function starts(event, days, source, duration) {
    var base = validDate(event.startDate || event.dateTime);
    if (!base)
        return { dates: [], limited: false };
    var recurrence = source === "local" && !event.notified ? (event.recurrence || "none") : "none";
    var dates = [base];
    var earliest = new Date(days[0].date.getTime() - duration - 2 * dayMs);
    var through = days[6].end;
    var limited = false;
    function range(first, last, create) {
        if (last - first + 1 > 1024) {
            first = last - 1023;
            limited = true;
        }
        for (var index = first; index <= last; index++)
            dates.push(create(index));
    }
    if (recurrence === "daily" || recurrence === "weekly") {
        var step = recurrence === "daily" ? 1 : 7;
        var first = Math.max(1, Math.floor((civilIndex(earliest) - civilIndex(base)) / step) - 1);
        var last = Math.ceil((civilIndex(through) - civilIndex(base)) / step);
        range(first, last, function(n) { return addDays(base, n * step); });
    } else if (recurrence === "monthly") {
        var firstMonth = (earliest.getFullYear() - base.getFullYear()) * 12 + earliest.getMonth() - base.getMonth();
        var lastMonth = (through.getFullYear() - base.getFullYear()) * 12 + through.getMonth() - base.getMonth();
        range(Math.max(1, firstMonth - 1), lastMonth + 1, function(m) {
            var month = new Date(base.getFullYear(), base.getMonth() + m, 1, 12);
            var monthly = new Date(month.getFullYear(), month.getMonth(), base.getDate(),
                base.getHours(), base.getMinutes(), base.getSeconds(), base.getMilliseconds());
            return monthly.getMonth() === month.getMonth() ? monthly : null;
        });
    } else if (recurrence === "yearly") {
        range(Math.max(1, earliest.getFullYear() - base.getFullYear() - 1), through.getFullYear() - base.getFullYear() + 1, function(y) {
            var yearly = new Date(base.getFullYear() + y, base.getMonth(), base.getDate(),
                base.getHours(), base.getMinutes(), base.getSeconds(), base.getMilliseconds());
            return yearly.getMonth() === base.getMonth() ? yearly : null;
        });
    }
    return { dates: dates, limited: limited };
}

function pack(rows) {
    rows.sort(function(a, b) { return a.start - b.start || a.end - b.end || a.key.localeCompare(b.key); });
    var active = [], cluster = [], clusterEnd = -Infinity, lanes = 0;
    function finish() {
        cluster.forEach(function(row) { row.lanes = lanes; });
        cluster = [];
        active = [];
        lanes = 0;
    }
    rows.forEach(function(row) {
        if (row.start >= clusterEnd)
            finish();
        active = active.filter(function(other) { return other.end > row.start; });
        var lane = 0;
        while (active.some(function(other) { return other.lane === lane; }))
            lane++;
        row.lane = lane;
        lanes = Math.max(lanes, lane + 1);
        cluster.push(row);
        active.push(row);
        clusterEnd = Math.max(clusterEnd, row.end);
    });
    finish();
    return rows;
}

// ── PlannerEventPalette ──
var EVENT_SWATCHES = [
    "#947E68", // muted bronze
    "#796783", // smoky violet
    "#648392", // dusty blue
    "#946F68", // muted terracotta
    "#638079", // muted teal
    "#777F9A", // slate periwinkle
    "#898263", // sage olive
    "#866978", // faded rose
    "#668791", // steel cyan
    "#85745C", // warm stone
    "#7F7796", // lavender slate
    "#6D8B76", // sage green
    "#997B86", // muted mauve
    "#687C94", // slate blue
    "#8F846A", // sand olive
    "#698382"  // dusty jade
];

function eventColorIdentity(event, source) {
    var origin = String(source || "local");
    var id = origin === "external"
        ? (event ? (event.uid ?? event.iCalUID ?? event.externalId ?? event.id) : undefined)
        : (event ? (event.id ?? event.uid ?? event.iCalUID ?? event.externalId) : undefined);
    if (id !== undefined && id !== null && id !== "") {
        if ((typeof id === "number" || typeof id === "string")
                && /^\d+$/.test(String(id)) && Number.isSafeInteger(Number(id)))
            return origin + ":id:" + String(Number(id));
        return origin + ":id:" + String(id);
    }
    return origin + ":missing-id:" + String((event && event.title) || "").trim();
}

function colorNumber(identity) {
    var hash = 2166136261;
    for (var i = 0; i < identity.length; i++)
        hash = Math.imul(hash ^ identity.charCodeAt(i), 16777619) >>> 0;
    return hash;
}

function eventSwatch(event, source) {
    var origin = String(source || "local");
    var id = origin === "external"
        ? (event ? (event.uid ?? event.iCalUID ?? event.externalId ?? event.id) : undefined)
        : (event ? (event.id ?? event.uid ?? event.iCalUID ?? event.externalId) : undefined);
    var numeric = (typeof id === "number" || typeof id === "string")
        && /^\d+$/.test(String(id)) ? Number(id) : NaN;
    var stable = eventColorIdentity(event, source);
    var number = Number.isSafeInteger(numeric) && numeric >= 0
        ? numeric : colorNumber(stable);
    var index = number % EVENT_SWATCHES.length;
    var variant = Math.floor(number / EVENT_SWATCHES.length) % 3;
    var hex = EVENT_SWATCHES[index];
    if (variant === 0)
        return hex;
    var blend = variant === 1 ? 0 : 255;
    var amount = variant === 1 ? 0.11 : 0.10;
    var channels = [1, 3, 5].map(function(start) {
        var channel = parseInt(hex.slice(start, start + 2), 16);
        return Math.round(channel * (1 - amount) + blend * amount)
            .toString(16).padStart(2, "0");
    });
    return "#" + channels.join("").toUpperCase();
}

function decorateRow(row) {
    var ev = row.event || {};
    var isAllDay = Boolean(ev.allDay);
    var startHm = isAllDay ? "All day" : formatHm(row.startDate);
    var endHm = isAllDay ? "" : formatHm(row.endDate);
    var timeRange = isAllDay ? "All day" : (endHm ? (startHm + " – " + endHm) : startHm);
    var swatch = eventSwatch(ev, row.source);
    var startMin = Number(row.start || 0);
    var endMin = Number(row.end || (startMin + 60));
    var durMin = Math.max(15, endMin - startMin);
    return Object.assign({}, row, {
        id: ev.id ?? ev.uid ?? "",
        title: String(ev.title || "Untitled"),
        description: String(ev.description || ""),
        location: String(ev.location || ""),
        category: String(ev.category || (row.source === "external" ? "Calendar" : "Planner")),
        allDay: isAllDay,
        time: startHm,
        endTime: endHm,
        timeRange: timeRange,
        startMinutes: startMin,
        durationMinutes: durMin,
        startHour: startMin / 60.0,
        durationHours: durMin / 60.0,
        swatch: swatch,
        color: swatch.accent,
        source: row.source === "external" ? "calendar" : "dashboard",
        rawSource: row.source,
        recurrence: String(ev.recurrence || "none")
    });
}

function project(local, external, value, firstDay) {
    var days = week(value, firstDay);
    [[local, "local"], [external, "external"]].forEach(function(pair) {
        (pair[0] || []).forEach(function(event) {
            if (!event)
                return;
            if (pair[1] === "local" && hasFutureSchedule(event)) {
                projectFutureSchedule(event, days[0].date, days[6].end).forEach(function(range) {
                    var start = validDate(range.startDate), finish = validDate(range.endDate);
                    if (!start || !finish)
                        return;
                    days.forEach(function(day, index) {
                        if (start >= day.end || finish <= day.date)
                            return;
                        var bucket = event.allDay ? day.allDay : day.timed;
                        if (bucket.length >= 512) {
                            day.overflow++;
                            return;
                        }
                        bucket.push(decorateRow({
                            key: "local:" + String(event.id) + ":" + range.occurrenceIndex + ":" + start.getTime() + ":" + index,
                            event: event,
                            source: "local",
                            occurrenceIndex: range.occurrenceIndex,
                            virtual: range.virtual,
                            plannerOriginalStartIso: range.originalStartIso,
                            plannerBranchKey: range.branchKey,
                            plannerScheduleCycle: range.cycle,
                            start: (Math.max(start, day.date) - day.date) / minute,
                            end: (Math.min(finish, day.end) - day.date) / minute,
                            startDate: start,
                            endDate: finish,
                            lane: 0,
                            lanes: 1
                        }));
                    });
                });
                return;
            }
            var grouped = Array.isArray(event.occurrences) && event.occurrences.length > 0;
            var ranges = grouped ? event.occurrences : [event];
            ranges.forEach(function(slot, slotIndex) {
                var base = validDate(slot.startDate || slot.dateTime);
                if (!base)
                    return;
                var baseEnd = validDate(slot.endDate);
                var duration = baseEnd && baseEnd > base ? baseEnd - base : hour;
                var allDaySpan = event.allDay && baseEnd && baseEnd > base
                    ? Math.max(1, civilIndex(baseEnd) - civilIndex(base)) : 1;
                var repeatingGroup = Array.isArray(event.repeatTemplate)
                    && event.repeatTemplate.length > 0
                    && (event.recurrence || "none") !== "none";
                var activeGroup = repeatingGroup && slotIndex >= Number(event.repeatCycleStart || 0);
                var recurring = pair[1] === "local" && (event.recurrence || "none") !== "none";
                var anchorDate = (recurring && validDate(slot.plannerSeriesStartDate)) || base;
                var anchorEnd = (recurring && validDate(slot.plannerSeriesEndDate)) || baseEnd;
                var seriesDuration = anchorEnd && anchorEnd > anchorDate ? anchorEnd - anchorDate : duration;
                var occurrenceSource = Object.assign({}, event, {
                    startDate: anchorDate.toISOString(),
                    dateTime: anchorDate.toISOString(),
                    endDate: anchorEnd && anchorEnd > anchorDate ? anchorEnd.toISOString() : "",
                    notified: (repeatingGroup && !activeGroup) || (slot.notified === true && !activeGroup)
                });
                var generated = starts(occurrenceSource, days, pair[1], event.allDay ? allDaySpan * dayMs : seriesDuration);
                if (generated.limited)
                    days.forEach(function(day) { day.projectionLimited = true; });
                var overrides = recurring && Array.isArray(event.plannerOverrides)
                    ? event.plannerOverrides.filter(function(item) {
                        return item.occurrenceIndex === slotIndex
                            && item.materializedOccurrenceIndex === undefined
                            && item.forwardedEventId === undefined;
                    }) : [];
                function overrideFor(occurrence) {
                    return overrides.find(function(item) {
                        return item.originalStartDate === occurrence.toISOString();
                    }) || null;
                }
                function drawOccurrence(occurrence, saved, correction) {
                    var actualStart = correction && validDate(correction.startDate);
                    var actualEnd = correction && validDate(correction.endDate);
                    if (!actualStart || !actualEnd || actualEnd <= actualStart)
                        correction = null;
                    var start = correction ? actualStart
                        : event.allDay ? midnight(saved ? base : occurrence)
                        : (saved ? base : occurrence);
                    var finish = correction ? actualEnd
                        : event.allDay ? addDays(start, allDaySpan)
                        : new Date(start.getTime() + (saved ? duration : seriesDuration));
                    days.forEach(function(day, index) {
                        if (start >= day.end || finish <= day.date)
                            return;
                        var bucket = event.allDay ? day.allDay : day.timed;
                        if (bucket.length >= 512) {
                            day.overflow++;
                            return;
                        }
                        var from = Math.max(start, day.date), to = Math.min(finish, day.end);
                        bucket.push(decorateRow({
                            key: pair[1] + ":" + String(event.id || event.uid || "") + ":" + slotIndex + ":" + start.getTime() + ":" + index,
                            event: event,
                            source: pair[1],
                            occurrenceIndex: slotIndex,
                            virtual: !saved,
                            plannerOriginalStartIso: saved ? "" : occurrence.toISOString(),
                            start: (from - day.date) / minute,
                            end: (to - day.date) / minute,
                            startDate: new Date(start),
                            endDate: finish,
                            lane: 0,
                            lanes: 1
                        }));
                    });
                }
                var sawAnchor = false, seenVirtual = new Set();
                generated.dates.filter(function(d) { return d !== null; }).forEach(function(occurrence) {
                    var saved = occurrence.getTime() === anchorDate.getTime();
                    if (saved)
                        sawAnchor = true;
                    if (!saved)
                        seenVirtual.add(occurrence.toISOString());
                    if (!saved && occurrence.getTime() === base.getTime() && base.getTime() !== anchorDate.getTime())
                        return;
                    drawOccurrence(occurrence, saved, saved ? null : overrideFor(occurrence));
                });
                overrides.forEach(function(item) {
                    if (seenVirtual.has(item.originalStartDate))
                        return;
                    var original = validDate(item.originalStartDate);
                    if (original)
                        drawOccurrence(original, false, item);
                });
                if (!sawAnchor && anchorDate.getTime() !== base.getTime())
                    drawOccurrence(base, true, null);
            });
        });
    });
    var weekdayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
    days.forEach(function(day) {
        pack(day.timed);
        day.allItems = day.allDay.concat(day.timed);
        day.allDayEvents = day.allDay;
        day.timedEvents = day.timed;
        day.dayName = weekdayNames[day.date.getDay()] || "";
    });
    return days;
}

function projectDay(local, external, dateOrIso, firstDay) {
    var target = midnight(dateOrIso);
    var targetStr = formatIsoDate(target);
    var days = project(local, external, target, firstDay === undefined ? 1 : firstDay);
    for (var i = 0; i < days.length; i++) {
        if (days[i].dateStr === targetStr)
            return days[i];
    }
    return days[0] || { date: target, dateStr: targetStr, timed: [], allDay: [], allDayEvents: [], timedEvents: [], allItems: [], dayName: "", overflow: 0 };
}
