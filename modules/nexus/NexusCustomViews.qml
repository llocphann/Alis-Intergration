import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.modules.common
import qs.modules.common.widgets
import qs.services as HostServices
import "NexusPlannerProjection.js" as PlannerProjection
import "NexusExerciseAnatomyData.js" as ExerciseAnatomyData

Item {
    id: root
    objectName: "nexusCustomViewsRoot"
    property var nexus: null
    property var workspace: null
    property var service: nexus
    property var doc: service ? service.currentDoc : null
    property int plannerRevision: 0
    readonly property string noteKind: String(doc?.noteKind ?? "standard")
    readonly property var dossier: doc?.dossier ?? ({})
    readonly property var jView: doc?.journalView ?? ({})
    readonly property var jSchedule: {
        const s = jView?.schedule;
        if (s && (s.available || (s.exerciseRows?.length ?? 0) > 0 || (s.cardioRows?.length ?? 0) > 0 || (s.scheduleRows?.length ?? 0) > 0))
            return s;
        const snap = jView?.snapshotSchedule;
        if (snap && (snap.available || (snap.exerciseRows?.length ?? 0) > 0 || (snap.cardioRows?.length ?? 0) > 0 || (snap.scheduleRows?.length ?? 0) > 0))
            return snap;
        return service?.dailySchedule ?? snap ?? s ?? ({});
    }
    readonly property var jPlannerRows: {
        const _rev = root.plannerRevision;
        const targetDate = String(root.jView?.dateStr || root.service?.selectedDateStr || "");
        const localEvs = HostServices.Events?.list ?? [];
        const extEvs = HostServices.CalendarSync?.events ?? [];
        const projected = PlannerProjection.projectDay(localEvs, extEvs, targetDate, 1);
        const items = projected?.allItems ?? [];
        const rows = [];
        for (let i = 0; i < items.length; ++i) {
            const it = items[i];
            rows.push([String(it.timeRange || it.time || "All day"), String(it.title || "Untitled"), String(it.swatch || "#648392")]);
        }
        return rows;
    }
    readonly property var cView: doc?.cornellView ?? ({})
    readonly property var zView: doc?.zettelkastenView ?? ({})
    readonly property var rView: doc?.recipeView ?? ({})
    readonly property var eView: doc?.exerciseView ?? ({})
    readonly property var sView: doc?.settingsView ?? ({})
    readonly property var fSummary: doc?.financeSummary ?? service?.financeSummary ?? ({})

    function ccStop(idx): color {
        if (root.workspace && typeof root.workspace.ccStop === "function")
            return Qt.color(root.workspace.ccStop(idx));
        const l0 = Appearance.colors.colLayer0 ?? "#0c1113";
        const l1 = Appearance.colors.colLayer1 ?? "#10181b";
        const l2 = Appearance.colors.colLayer2 ?? "#162024";
        const acc = Appearance.colors.colPrimary ?? "#a0cddf";
        const txt = Appearance.colors.colOnLayer1 ?? "#c6d6dc";
        const sub = Appearance.colors.colSubtext ?? "#a0bac5";
        switch (idx) {
        case 0: return Qt.darker(l0, 1.18);
        case 1: return l0;
        case 2: return l1;
        case 3: return l2;
        case 4: return Appearance.colors.colLayer2Hover ?? Qt.lighter(l2, 1.15);
        case 5: return Appearance.colors.colLayer2Active ?? Qt.lighter(l2, 1.28);
        case 6: return Qt.tint(l2, Qt.rgba(acc.r, acc.g, acc.b, 0.28));
        case 7: return Qt.tint(l2, Qt.rgba(acc.r, acc.g, acc.b, 0.40));
        case 8: return Qt.tint(l2, Qt.rgba(acc.r, acc.g, acc.b, 0.52));
        case 9: return Qt.rgba(sub.r, sub.g, sub.b, 0.72);
        case 10: return Qt.rgba(sub.r, sub.g, sub.b, 0.86);
        case 11: return sub;
        case 12: return txt;
        case 13: return Appearance.colors.colOnLayer0 ?? Qt.lighter(txt, 1.12);
        default: return l1;
        }
    }

    property int viewportHeight: 0
    property int topBannerHeight: 0
    readonly property int minDocumentSurfaceHeight: Math.max(520, viewportHeight - topBannerHeight)

    readonly property color accentColor: root.workspace ? Qt.color(root.workspace._settledPrimary) : (Appearance.colors.colPrimary ?? "#a0cddf")
    readonly property color onAccentColor: root.workspace ? Qt.color(root.workspace._settledOnPrimary) : (Appearance.colors.colOnPrimary ?? ccStop(0))
    readonly property color cardDeepBg: ccStop(0)
    readonly property color cardSubtleBg: ccStop(1)
    readonly property color cardBg: ccStop(2)
    readonly property color cardRaisedBg: ccStop(3)
    readonly property color cardHoverBg: ccStop(4)
    readonly property color journalSubSurfaceBg: Qt.tint(
        Qt.lighter(root.cardDeepBg, 1.28),
        Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.08)
    )
    readonly property color journalSubSurfaceHoverBg: Qt.tint(
        Qt.lighter(root.cardDeepBg, 1.42),
        Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.16)
    )
    readonly property color borderSubtle: Qt.rgba(ccStop(6).r, ccStop(6).g, ccStop(6).b, 0.55)
    readonly property color borderAccent: Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.36)
    readonly property color textStrong: ccStop(13)
    readonly property color textPrimary: ccStop(12)
    readonly property color textSecondary: ccStop(11)
    readonly property color textMuted: ccStop(9)
    readonly property string serifFontFamily: Appearance.font?.family?.main ?? "Noto Serif"
    readonly property string themeSignature: root.workspace ? root.workspace.themeSignature : [
        String(root.accentColor),
        String(root.borderSubtle),
        String(root.cardBg),
        String(root.textStrong)
    ].join("|")

    function _opaqueHex(c, fallback): string {
        const col = Qt.color(c ?? fallback ?? "#334155");
        if (!col || isNaN(col.r) || isNaN(col.g) || isNaN(col.b))
            return String(fallback ?? "#334155");
        const toHex = v => Math.max(0, Math.min(255, Math.round(v * 255))).toString(16).padStart(2, "0");
        return "#" + toHex(col.r) + toHex(col.g) + toHex(col.b);
    }

    function themeRichHtml(rawHtml): string {
        const s = String(rawHtml ?? "");
        if (s.length === 0)
            return "";
        const accHex = root._opaqueHex(root.accentColor, "#82c2cf");
        const codeBgHex = root._opaqueHex(root.cardRaisedBg, "#162024");
        const codeFgHex = root._opaqueHex(root.textStrong, "#eaf1f2");
        const bodyFgHex = root._opaqueHex(root.textPrimary, "#d9e1e3");
        const borderHex = root._opaqueHex(root.ccStop(6), "#334155");
        const markBgHex = root._opaqueHex(Qt.tint(root.cardRaisedBg, Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.32)), "#1f3338");
        const subHex = root._opaqueHex(root.textSecondary, "#8f9d9f");
        const themedHr = "<table width='100%' cellspacing='0' cellpadding='0' style='margin-top:8px;margin-bottom:8px;'><tr><td height='1' style='background-color:" + borderHex + ";font-size:1px;line-height:1px;'></td></tr></table>";
        return s
            .replace(/<hr\b[^>]*\/?>/gi, themedHr)
            .replace(/#38bdf8/gi, accHex)
            .replace(/#7dd3fc/gi, accHex)
            .replace(/#7dcfff/gi, accHex)
            .replace(/#1e293b/gi, codeBgHex)
            .replace(/#334155/gi, borderHex)
            .replace(/#e2e8f0/gi, bodyFgHex)
            .replace(/#f8fafc/gi, codeFgHex)
            .replace(/#94a3b8/gi, subHex)
            .replace(/#422006/gi, markBgHex)
            .replace(/#fde047/gi, accHex)
            .replace(/#c084fc/gi, subHex);
    }

    function escapeHtmlText(raw): string {
        return String(raw ?? "")
            .replace(/&/g, "&amp;")
            .replace(/</g, "&lt;")
            .replace(/>/g, "&gt;")
            .replace(/"/g, "&quot;");
    }

    function renderInlineMarkdownHtml(rawText): string {
        const s = String(rawText ?? "");
        if (!s)
            return "";
        const accHex = String(root.accentColor);
        const codeBgHex = String(root.cardRaisedBg);
        const codeFgHex = String(root.textStrong);
        const subHex = String(root.textSecondary);
        const markBgHex = String(Qt.tint(root.cardRaisedBg, Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.32)));

        // Escape first, then replace inline tokens
        let out = root.escapeHtmlText(s);
        // Preserve <br>, <br/>, <br /> line breaks
        out = out.replace(/&lt;br\s*\/?&gt;/gi, "<br/>");
        // Inline code `code`
        out = out.replace(/`([^`\n]+)`/g, (_m, c) =>
            "<span style='background-color:" + codeBgHex + ";color:" + codeFgHex + ";font-family:monospace;'>&nbsp;" + c + "&nbsp;</span>"
        );
        // Wikilinks [[target|alias]] or [[ ]]
        out = out.replace(/!?\[\[([^\[\]\n]*)\]\]/g, (_m, inner) => {
            const trimmed = String(inner ?? "").trim();
            if (!trimmed) {
                return "<span style='background-color:" + codeBgHex + ";color:" + subHex + ";font-style:italic;padding:1px 6px;'>&nbsp;Related note&nbsp;</span>";
            }
            const pipeIdx = trimmed.indexOf("|");
            const target = (pipeIdx >= 0 ? trimmed.slice(0, pipeIdx) : trimmed).trim();
            const label = (pipeIdx >= 0 ? trimmed.slice(pipeIdx + 1) : trimmed).trim() || target;
            return "<a href=\"wikilink:" + encodeURIComponent(target) + "\" style=\"color:" + accHex + ";text-decoration:none;font-weight:600;\">" + label + "</a>";
        });
        // Markdown links [label](url) including empty [Title]( ) placeholders
        out = out.replace(/\[([^\]]+)\]\(([^)]*)\)/g, (_m, lbl, url) => {
            const cleanUrl = String(url ?? "").trim();
            if (!cleanUrl) {
                return "<span style='background-color:" + codeBgHex + ";color:" + subHex + ";font-style:italic;padding:1px 6px;'>&nbsp;" + String(lbl ?? "Source").trim() + "&nbsp;</span>";
            }
            return "<a href=\"" + cleanUrl + "\" style=\"color:" + accHex + ";text-decoration:underline;\">" + lbl + "</a>";
        });
        // Highlights ==text==
        out = out.replace(/==([^=\n]+)==/g, (_m, h) =>
            "<span style='background-color:" + markBgHex + ";color:" + accHex + ";font-weight:600;'>&nbsp;" + h + "&nbsp;</span>"
        );
        // Bold **text**
        out = out.replace(/\*\*([^*\n]+)\*\*/g, "<b>$1</b>");
        // Italic *text* and _text_
        out = out.replace(/(^|[^*])\*([^*\n]+)\*(?!\*)/g, "$1<i>$2</i>");
        out = out.replace(/(^|[\s(>\[])_([^_\n]+)_(?=$|[\s.,;:!?)\]<])/g, "$1<i>$2</i>");
        // Tags #tag
        out = out.replace(/(^|\s)#([A-Za-z0-9_\/-]+)/g, (_m, pre, tag) =>
            pre + "<span style='color:" + subHex + ";font-weight:600;'>#" + tag + "</span>"
        );
        return out;
    }

    function cornellCueAccentColor(cueType): color {
        const t = String(cueType ?? "").toUpperCase();
        if (t === "CORNELL_IMPORTANT")
            return Qt.rgba(0.953, 0.545, 0.659, 1.0); // #f38ba8
        if (t === "CORNELL_KEYPOINT" || t === "CORNELL_KEY")
            return Qt.rgba(0.976, 0.886, 0.686, 1.0); // #f9e2af
        if (t === "CORNELL_EXAMPLE")
            return Qt.rgba(0.651, 0.890, 0.631, 1.0); // #a6e3a1
        if (t === "CORNELL_VERIFIED" || t === "CORNELL_VOCAB")
            return Qt.rgba(0.580, 0.886, 0.835, 1.0); // #94e2d5
        if (t === "CORNELL_MISTAKE" || t === "CORNELL_REF")
            return Qt.rgba(0.980, 0.702, 0.529, 1.0); // #fab387
        if (t === "CORNELL_RELATED" || t === "CORNELL_RESEARCH")
            return Qt.rgba(0.706, 0.745, 0.996, 1.0); // #b4befe
        if (t === "CORNELL_FEYNMAN" || t === "CORNELL_GENERAL")
            return Qt.rgba(0.796, 0.651, 0.969, 1.0); // #cba6f7
        return root.accentColor;
    }

    function renderMarkdownBlocksHtml(rawMd): string {
        const raw = String(rawMd ?? "").trim();
        if (!raw)
            return "";
        const accHex = String(root.accentColor);
        const strongHex = String(root.textStrong);
        const bodyHex = String(root.textPrimary);
        const subHex = String(root.textSecondary);
        const mutedHex = String(root.textMuted);
        const codeBgHex = String(root.cardRaisedBg);
        const borderHex = String(root.borderSubtle);
        const lines = raw.split(/\r?\n/);
        const blocks = [];

        for (let i = 0; i < lines.length; ++i) {
            const line = lines[i];
            const t = line.trim();
            if (!t)
                continue;
            if (t.startsWith("![[") && t.indexOf("Custom_Views/") >= 0)
                continue;
            if (t.toLowerCase() === "<center>end</center>")
                continue;
            if (t.startsWith("|") && t.endsWith("|") && t.length > 2) {
                const tableRows = [];
                while (i < lines.length) {
                    const rt = lines[i].trim();
                    if (rt.startsWith("|") && rt.endsWith("|") && rt.length > 2) {
                        tableRows.push(rt);
                        i++;
                    } else {
                        break;
                    }
                }
                i--;
                if (tableRows.length > 0) {
                    let tbl = "<table width='100%' cellspacing='0' cellpadding='6' style='border-collapse:collapse;margin:6px 0;border:1px solid " + borderHex + ";'>";
                    let isHeader = true;
                    for (let r = 0; r < tableRows.length; ++r) {
                        const rowStr = tableRows[r].slice(1, -1);
                        const cells = rowStr.split("|").map(c => c.trim());
                        const isSep = cells.every(c => c.length > 0 && /^[-:\s]+$/.test(c));
                        if (isSep) {
                            isHeader = false;
                            continue;
                        }
                        tbl += "<tr>";
                        for (let c = 0; c < cells.length; ++c) {
                            if (isHeader) {
                                tbl += "<th align='left' style='background-color:" + codeBgHex + ";color:" + accHex + ";font-weight:700;padding:6px 8px;border:1px solid " + borderHex + ";'>" + root.renderInlineMarkdownHtml(cells[c]) + "</th>";
                            } else {
                                tbl += "<td style='color:" + bodyHex + ";padding:5px 8px;border:1px solid " + borderHex + ";'>" + root.renderInlineMarkdownHtml(cells[c]) + "</td>";
                            }
                        }
                        tbl += "</tr>";
                        isHeader = false;
                    }
                    tbl += "</table>";
                    blocks.push(tbl);
                    continue;
                }
            }
            if (t === "---" || t === "***" || t === "___") {
                const sepHex = root._opaqueHex(root.ccStop(6), "#334155");
                blocks.push("<table width='100%' cellspacing='0' cellpadding='0' style='margin-top:8px;margin-bottom:8px;'><tr><td height='1' style='background-color:" + sepHex + ";font-size:1px;line-height:1px;'></td></tr></table>");
                continue;
            }
            const hMatch = t.match(/^(#{1,6})\s+(.*)$/);
            if (hMatch) {
                const lvl = hMatch[1].length;
                const hText = hMatch[2].trim();
                const sz = lvl === 1 ? "large" : (lvl === 2 ? "medium" : "small");
                const col = lvl <= 2 ? accHex : strongHex;
                blocks.push("<div style='margin-top:6px;margin-bottom:3px;font-weight:700;font-size:" + sz + ";color:" + col + ";'>" + root.renderInlineMarkdownHtml(hText) + "</div>");
                continue;
            }
            if (t.startsWith(">")) {
                let q = t.replace(/^>+\s*/, "").trim();
                if (q.startsWith("[!")) {
                    const closeIdx = q.indexOf("]");
                    if (closeIdx >= 0) {
                        const cType = q.slice(2, closeIdx).trim();
                        const cTitle = q.slice(closeIdx + 1).trim() || cType;
                        blocks.push("<div style='margin:4px 0 2px 0;padding-left:8px;border-left:2px solid " + accHex + ";color:" + accHex + ";font-weight:700;'>" + root.renderInlineMarkdownHtml(cTitle) + "</div>");
                        continue;
                    }
                }
                if (q.length > 0) {
                    blocks.push("<div style='margin:2px 0;padding-left:8px;border-left:2px solid " + accHex + ";color:" + subHex + ";font-style:italic;'>" + root.renderInlineMarkdownHtml(q) + "</div>");
                }
                continue;
            }
            const taskMatch = t.match(/^[-*+]\s+\[([ xX])\]\s*(.*)$/);
            if (taskMatch) {
                const done = taskMatch[1].toLowerCase() === "x";
                const body = taskMatch[2].trim();
                if (!body && !done)
                    continue;
                const box = done
                    ? "<span style='color:" + accHex + ";font-weight:700;'>☑</span> "
                    : "<span style='color:" + mutedHex + ";'>☐</span> ";
                const rendered = done ? ("<s>" + root.renderInlineMarkdownHtml(body) + "</s>") : root.renderInlineMarkdownHtml(body);
                blocks.push("<div style='margin:2px 0;'>" + box + rendered + "</div>");
                continue;
            }
            if (t === "-" || t === "*" || t === "+") {
                blocks.push("<div style='margin:2px 0;'><span style='color:" + accHex + ";font-weight:700;'>•</span></div>");
                continue;
            }
            const bulletMatch = t.match(/^[-*+]\s+(.*)$/);
            if (bulletMatch) {
                const body = bulletMatch[1].trim();
                if (!body)
                    continue;
                blocks.push("<div style='margin:2px 0;'><span style='color:" + accHex + ";font-weight:700;'>•</span>&nbsp;" + root.renderInlineMarkdownHtml(body) + "</div>");
                continue;
            }
            const numMatch = t.match(/^(\d+)[.)]\s+(.*)$/);
            if (numMatch) {
                const num = numMatch[1];
                const body = numMatch[2].trim();
                if (!body)
                    continue;
                blocks.push("<div style='margin:2px 0;'><span style='color:" + accHex + ";font-weight:600;'>" + num + ".</span>&nbsp;" + root.renderInlineMarkdownHtml(body) + "</div>");
                continue;
            }
            blocks.push("<div style='margin:2px 0;'>" + root.renderInlineMarkdownHtml(t) + "</div>");
        }
        return blocks.join("");
    }

    readonly property string cleanNoteBodyMarkdown: {
        const _docRef = root.doc;
        void(_docRef);
        const raw = root.service ? String(root.service.getNoteBodyMarkdown() ?? "") : "";
        if (!raw)
            return "";
        const lines = raw.split(/\r?\n/);
        const filtered = [];
        for (let i = 0; i < lines.length; ++i) {
            const t = lines[i].trim();
            if (t.startsWith("![[") && t.indexOf("Custom_Views/") >= 0)
                continue;
            filtered.push(lines[i]);
        }
        return filtered.join("\n").trim();
    }

    readonly property var mediaCastList: {
        const rawVal = root.dossier?.cast ?? root.dossier?.actors ?? root.doc?.frontmatter?.cast ?? root.doc?.frontmatter?.actors ?? "";
        const parts = Array.isArray(rawVal)
            ? rawVal
            : String(rawVal ?? "").split(",");
        const out = [];
        for (let i = 0; i < parts.length; ++i) {
            const name = String(parts[i] ?? "").replace(/^\[\[|\]\]$/g, "").trim();
            if (name.length > 0)
                out.push(name);
        }
        return out;
    }

    readonly property bool isDossierBannerNote: noteKind === "movie" || noteKind === "tvseries" || noteKind === "game"
                                                || noteKind === "website" || noteKind === "place" || noteKind === "book"
                                                || noteKind === "clipping" || noteKind === "settings"
                                                || noteKind === "contact" || noteKind === "teaching" || noteKind === "vocabulary"
    readonly property bool isCustomViewNote: isDossierBannerNote || noteKind === "journal" || noteKind === "cornell"
                                             || noteKind === "zettelkasten" || noteKind === "recipe" || noteKind === "finance"
                                             || noteKind === "exercise"

    property string cornellTypeFilter: "ALL"
    property bool cornellStudyMode: false
    property var cornellRevealedRows: ({})
    property string mediaActiveTab: "journal"
    property string financeActiveRange: "monthly"
    property int financeVisibleTransactionCount: 12
    onFinanceActiveRangeChanged: financeVisibleTransactionCount = 12
    property bool exerciseShowAnimation: false
    property int exerciseStepProgress: -1
    property string exerciseLevelOverride: ""
    property var checkedIngredients: ({})
    property bool editingPlaytime: false
    property bool editingCompletion: false

    // Inline Click-to-Edit state (all notes/custom views default to Reading mode)
    property bool journalEditingDailyLog: false
    property bool journalEditingWeight: false
    property string journalWeightOverride: ""
    property bool journalWeightHasOverride: false
    readonly property string journalEffectiveWeight: root.journalWeightHasOverride
        ? root.journalWeightOverride
        : String(root.jView?.weight ?? "")
    property bool journalEditingReflection: false
    property bool editingNoteBody: false

    // Recipe Custom View state (`Custom_Views/Recipe/Recipe.{html,js,css}`)
    property string recipeActiveSection: "overview"
    property string recipeEditingField: ""
    property int recipeEditingIndex: -1
    property string recipeDraftTextA: ""
    property string recipeDraftTextB: ""
    property bool recipeEditingPersonalNote: false
    property int recipeStepProgressOverride: -1
    property int recipeFavoriteOverride: -1
    property int recipeBookmarkOverride: -1

    readonly property bool hasActiveInlineEditor: root.journalEditingDailyLog
        || root.journalEditingWeight
        || root.journalEditingReflection
        || root.editingNoteBody
        || root.recipeEditingField.length > 0
        || root.recipeEditingIndex >= 0
        || root.recipeEditingPersonalNote
        || root.editingPlaytime
        || root.editingCompletion
    onHasActiveInlineEditorChanged: {
        if (!hasActiveInlineEditor)
            root.restoreWorkspaceFocus();
    }

    function restoreWorkspaceFocus(): void {
        if (root.workspace && typeof root.workspace.restoreWorkspaceFocus === "function") {
            root.workspace.restoreWorkspaceFocus();
            Qt.callLater(root.workspace.restoreWorkspaceFocus);
        } else if (root.workspace && typeof root.workspace.focusPrimarySurface === "function") {
            root.workspace.focusPrimarySurface();
            Qt.callLater(root.workspace.focusPrimarySurface);
        }
    }

    function forwardWorkspaceShortcut(event): bool {
        if (!event)
            return false;
        if ((event.modifiers & (Qt.AltModifier | Qt.ControlModifier | Qt.MetaModifier)) !== 0
            && root.service
            && typeof root.service.handleKeyEvent === "function"
            && root.service.handleKeyEvent(event)) {
            event.accepted = true;
            return true;
        }
        return false;
    }

    function stripPlainMarkdown(raw): string {
        let s = String(raw ?? "").trim();
        if (!s)
            return "";
        s = s.replace(/!\[\[[^\]]*\]\]/g, "");
        s = s.replace(/\[\[([^\]|#]+)(?:#[^\]|]+)?\|([^\]]+)\]\]/g, "$2");
        s = s.replace(/\[\[([^\]|#]+)(?:#[^\]]+)?\]\]/g, "$1");
        s = s.replace(/\[([^\]]+)\]\([^)]+\)/g, "$1");
        s = s.replace(/\*\*([^*]+)\*\*/g, "$1");
        s = s.replace(/__([^_]+)__/g, "$1");
        s = s.replace(/\*([^*\n]+)\*/g, "$1");
        s = s.replace(/`([^`]+)`/g, "$1");
        return s.replace(/\s+/g, " ").trim();
    }

    function isExerciseTipsHeading(headingText): bool {
        const h = String(headingText ?? "").trim().toLowerCase();
        return h.indexOf("tip") >= 0
            || h.indexOf("note") >= 0
            || h.indexOf("cue") >= 0
            || h.indexOf("variation") >= 0
            || h.indexOf("caution") >= 0
            || h.indexOf("mistake") >= 0;
    }

    function parseLiveExerciseSteps(rawMd): var {
        const s = String(rawMd ?? "").replace(/\r\n/g, "\n");
        const lines = s.split("\n");
        const steps = [];
        let inTipsSection = false;
        for (let i = 0; i < lines.length; ++i) {
            const t = lines[i].trim();
            if (!t || t.startsWith("```") || (t.startsWith("![[") && t.indexOf("Custom_Views/") >= 0))
                continue;
            const mHead = /^#{1,6}\s+(.*)$/.exec(t);
            if (mHead) {
                inTipsSection = root.isExerciseTipsHeading(mHead[1]);
                continue;
            }
            if (inTipsSection)
                continue;
            const mNum = /^\d+[.)]\s+(.*)$/.exec(t);
            if (mNum && mNum[1].trim().length > 0) {
                steps.push(mNum[1].trim());
                continue;
            }
            const mBul = /^[-*+]\s+(.*)$/.exec(t);
            if (mBul && mBul[1].trim().length > 0) {
                steps.push(mBul[1].trim());
                continue;
            }
            if (steps.length > 0)
                steps[steps.length - 1] += " " + t;
            else
                steps.push(t);
        }
        return steps;
    }

    function parseLiveExerciseTips(rawMd): var {
        const s = String(rawMd ?? "").replace(/\r\n/g, "\n");
        const lines = s.split("\n");
        const tips = [];
        let inTipsSection = false;
        for (let i = 0; i < lines.length; ++i) {
            const t = lines[i].trim();
            if (!t || t.startsWith("```") || (t.startsWith("![[") && t.indexOf("Custom_Views/") >= 0))
                continue;
            const mHead = /^#{1,6}\s+(.*)$/.exec(t);
            if (mHead) {
                inTipsSection = root.isExerciseTipsHeading(mHead[1]);
                continue;
            }
            if (!inTipsSection)
                continue;
            const mBul = /^[-*+]\s+(.*)$/.exec(t);
            if (mBul && mBul[1].trim().length > 0) {
                tips.push(mBul[1].trim());
                continue;
            }
            const mNum = /^\d+[.)]\s+(.*)$/.exec(t);
            if (mNum && mNum[1].trim().length > 0) {
                tips.push(mNum[1].trim());
                continue;
            }
            if (tips.length > 0)
                tips[tips.length - 1] += " " + t;
            else
                tips.push(t);
        }
        return tips;
    }

    function commitActiveNoteBodyEdit(): void {
        if (!root.service)
            return;
        if (root.noteKind === "game" && typeof gameBodyEditor !== "undefined") {
            root.service.saveNoteBodyMarkdown(gameBodyEditor.text);
        } else if (root.noteKind === "exercise" && typeof exBodyEditor !== "undefined") {
            root.service.saveNoteBodyMarkdown(exBodyEditor.text);
        } else if (root.noteKind === "cornell" && typeof cornellBodyEditor !== "undefined") {
            root.service.saveNoteBodyMarkdown(cornellBodyEditor.text);
        } else if (root.noteKind === "zettelkasten" && typeof zettelBodyEditor !== "undefined") {
            root.service.saveNoteBodyMarkdown(zettelBodyEditor.text);
        } else if (root.noteKind === "finance" && typeof financeBodyEditor !== "undefined") {
            root.service.saveNoteBodyMarkdown(financeBodyEditor.text);
        } else if (typeof dossierBodyEditor !== "undefined") {
            root.service.saveNoteBodyMarkdown(dossierBodyEditor.text);
        }
    }

    function startPrimaryInlineEdit(): bool {
        if (!root.isCustomViewNote)
            return false;
        if (root.noteKind === "journal") {
            if (typeof dailyLogEditor !== "undefined")
                dailyLogEditor.text = String(root.jView?.dailyLogText ?? "");
            root.journalEditingDailyLog = true;
            return true;
        }
        if (root.noteKind === "recipe") {
            if (typeof recipePersonalNoteEditor !== "undefined")
                recipePersonalNoteEditor.text = String(root.rView?.personalNotes ?? "");
            root.recipeActiveSection = "notes";
            root.recipeEditingPersonalNote = true;
            return true;
        }
        if (root.noteKind === "settings") {
            if (root.service)
                root.service.setEditorMode("raw");
            return true;
        }
        const mdBody = root.service ? root.service.getNoteBodyMarkdown() : "";
        if (root.noteKind === "game" && typeof gameBodyEditor !== "undefined")
            gameBodyEditor.text = mdBody;
        else if (root.noteKind === "exercise" && typeof exBodyEditor !== "undefined")
            exBodyEditor.text = mdBody;
        else if (root.noteKind === "cornell" && typeof cornellBodyEditor !== "undefined")
            cornellBodyEditor.text = mdBody;
        else if (root.noteKind === "zettelkasten" && typeof zettelBodyEditor !== "undefined")
            zettelBodyEditor.text = mdBody;
        else if (root.noteKind === "finance" && typeof financeBodyEditor !== "undefined")
            financeBodyEditor.text = mdBody;
        else if (typeof dossierBodyEditor !== "undefined")
            dossierBodyEditor.text = mdBody;
        root.editingNoteBody = true;
        return true;
    }

    function finishOrCancelInlineEditing(): bool {
        let handled = false;
        if (root.journalEditingDailyLog) {
            if (root.service && typeof dailyLogEditor !== "undefined" && dailyLogEditor.text !== String(root.jView?.dailyLogText ?? ""))
                root.service.saveJournalDailyLog(dailyLogEditor.text);
            root.journalEditingDailyLog = false;
            handled = true;
        }
        if (root.journalEditingWeight) {
            if (typeof weightInputField !== "undefined" && typeof weightInputField.commitWeight === "function")
                weightInputField.commitWeight();
            else
                root.journalEditingWeight = false;
            handled = true;
        }
        if (root.journalEditingReflection) {
            root.journalEditingReflection = false;
            handled = true;
        }
        if (root.editingNoteBody) {
            root.commitActiveNoteBodyEdit();
            root.editingNoteBody = false;
            handled = true;
        }
        if (root.recipeEditingField === "description") {
            if (root.service && typeof recipeDescEditor !== "undefined")
                root.service.updateNoteFrontmatter({ "description": recipeDescEditor.text.trim() });
            root.recipeEditingField = "";
            root.recipeEditingIndex = -1;
            handled = true;
        } else if (root.recipeEditingField.length > 0 || root.recipeEditingIndex >= 0) {
            root.recipeEditingField = "";
            root.recipeEditingIndex = -1;
            handled = true;
        }
        if (root.recipeEditingPersonalNote) {
            if (root.service && typeof recipePersonalNoteEditor !== "undefined" && recipePersonalNoteEditor.text !== String(root.rView?.personalNotes ?? ""))
                root.service.saveRecipePersonalNotes(recipePersonalNoteEditor.text);
            root.recipeEditingPersonalNote = false;
            handled = true;
        }
        if (root.editingPlaytime) {
            root.editingPlaytime = false;
            handled = true;
        }
        if (root.editingCompletion) {
            root.editingCompletion = false;
            handled = true;
        }
        if (handled) {
            root.restoreWorkspaceFocus();
        }
        return handled;
    }

    function isSyntheticSynopsisBlock(blk): bool {
        if (!blk)
            return false;
        if (Number(blk.id ?? -1) === 0 && String(blk.kind ?? "") === "callout" && String(blk.title ?? "") === "Synopsis")
            return true;
        const plotStr = String(root.dossier?.plot ?? root.doc?.frontmatter?.plot ?? root.doc?.frontmatter?.description ?? "").trim();
        const blkStr = String(blk.text ?? "").trim();
        if (plotStr.length > 0 && blkStr === plotStr)
            return true;
        return false;
    }

    // Journal Mood & Energy scales: strictly Low-to-High from Left to Right (`thấp đến cao`)
    readonly property var journalMoodOptions: [
        { "value": "terrible", "label": "Awful", "icon": "sentiment_very_dissatisfied", "aliases": ["terrible", "rough", "awful", "1"] },
        { "value": "bad",      "label": "Low",   "icon": "sentiment_dissatisfied",      "aliases": ["bad", "low", "2"] },
        { "value": "okay",     "label": "Okay",  "icon": "sentiment_neutral",           "aliases": ["okay", "ok", "neutral", "3"] },
        { "value": "good",     "label": "Good",  "icon": "sentiment_satisfied",         "aliases": ["good", "4"] },
        { "value": "great",    "label": "Great", "icon": "sentiment_very_satisfied",    "aliases": ["great", "excellent", "5"] }
    ]

    readonly property var journalEnergyOptions: [
        { "value": "drained", "label": "Drained", "icon": "battery_0_bar", "num": 2,  "aliases": ["drained", "exhausted", "1", "2"] },
        { "value": "low",     "label": "Low",     "icon": "battery_2_bar", "num": 4,  "aliases": ["low", "tired", "3", "4"] },
        { "value": "medium",  "label": "Mid",     "icon": "battery_4_bar", "num": 6,  "aliases": ["medium", "mid", "moderate", "5", "6"] },
        { "value": "high",    "label": "High",    "icon": "battery_5_bar", "num": 8,  "aliases": ["high", "energized", "7", "8"] },
        { "value": "peak",    "label": "Peak",    "icon": "bolt",          "num": 10, "aliases": ["peak", "full", "9", "10"] }
    ]

    function journalCanonicalMood(rawVal): string {
        const s = String(rawVal ?? "").trim().toLowerCase();
        if (!s)
            return "";
        for (let i = 0; i < root.journalMoodOptions.length; ++i) {
            const opt = root.journalMoodOptions[i];
            if (opt.value === s || opt.label.toLowerCase() === s || opt.aliases.indexOf(s) >= 0)
                return opt.value;
        }
        return s;
    }

    function journalMoodDisplayLabel(rawVal): string {
        const canon = root.journalCanonicalMood(rawVal);
        for (let i = 0; i < root.journalMoodOptions.length; ++i) {
            if (root.journalMoodOptions[i].value === canon)
                return root.journalMoodOptions[i].label;
        }
        const raw = String(rawVal ?? "").trim();
        return raw.length > 0 ? raw : "Not set";
    }

    function journalCanonicalEnergy(rawVal): string {
        const s = String(rawVal ?? "").trim().toLowerCase();
        if (!s || s === "0")
            return "";
        for (let i = 0; i < root.journalEnergyOptions.length; ++i) {
            const opt = root.journalEnergyOptions[i];
            if (opt.value === s || opt.label.toLowerCase() === s || opt.aliases.indexOf(s) >= 0)
                return opt.value;
        }
        const n = Number(s);
        if (Number.isFinite(n) && n > 0) {
            if (n <= 2) return "drained";
            if (n <= 4) return "low";
            if (n <= 6) return "medium";
            if (n <= 8) return "high";
            return "peak";
        }
        return s;
    }

    function journalEnergyDisplayLabel(rawVal): string {
        const canon = root.journalCanonicalEnergy(rawVal);
        for (let i = 0; i < root.journalEnergyOptions.length; ++i) {
            if (root.journalEnergyOptions[i].value === canon)
                return root.journalEnergyOptions[i].label;
        }
        const raw = String(rawVal ?? "").trim();
        return (raw.length > 0 && raw !== "0") ? raw : "Not set";
    }

    // Recipe helpers (`Custom_Views/Recipe/Recipe.js`)
    readonly property int recipeActiveStepProgress: {
        const stepsCount = (root.rView?.instructions ?? []).length;
        if (root.recipeStepProgressOverride >= 0)
            return Math.min(stepsCount, root.recipeStepProgressOverride);
        const sp = Number(root.rView?.stepsProgress ?? -1);
        if (Number.isFinite(sp) && sp >= 0)
            return Math.min(stepsCount, sp);
        const doneArr = root.rView?.instructionDone ?? [];
        let prog = 0;
        for (let i = 0; i < stepsCount && i < doneArr.length; ++i) {
            const ok = doneArr[i] === true || String(doneArr[i]).toLowerCase() === "true";
            if (!ok) break;
            prog = i + 1;
        }
        return prog;
    }

    function isRecipeIngredientChecked(idx: int): bool {
        if (root.checkedIngredients[idx] !== undefined)
            return Boolean(root.checkedIngredients[idx]);
        const done = root.rView?.ingredientsDone ?? [];
        if (!Array.isArray(done))
            return false;
        for (let i = 0; i < done.length; ++i) {
            if (Number(done[i]) === idx)
                return true;
        }
        return false;
    }

    readonly property bool recipeIsFavorite: root.recipeFavoriteOverride >= 0
        ? (root.recipeFavoriteOverride === 1)
        : Boolean(root.rView?.favorite ?? root.dossier?.favorite ?? false)

    readonly property bool recipeIsBookmarked: root.recipeBookmarkOverride >= 0
        ? (root.recipeBookmarkOverride === 1)
        : Boolean(root.rView?.bookmarked ?? root.dossier?.bookmarked ?? false)

    function setRecipeStepProgress(nextProg: int) {
        const count = (root.rView?.instructions ?? []).length;
        const bounded = Math.max(0, Math.min(count, Number(nextProg) || 0));
        root.recipeStepProgressOverride = bounded;
        const snapshot = [];
        for (let i = 0; i < count; ++i)
            snapshot.push(i < bounded);
        if (root.service)
            root.service.updateNoteFrontmatter({ "steps_progress": bounded, "instruction_done": snapshot });
    }

    function formatRecipeScalar(key: string, rawVal): string {
        let s = String(rawVal ?? "").trim();
        if ((!s || s === "—" || s === "0") && key === "cook_time") {
            const totalRaw = String(root.rView?.totalTime || root.dossier?.runtime || "").trim();
            if (totalRaw && totalRaw !== "0" && totalRaw !== "—") {
                s = totalRaw;
            } else {
                const desc = String(root.rView?.description || root.dossier?.plot || "");
                const mMin = /(?:takes?\s+(?:around|about)|in\s+(?:around|about)|ready\s+in)\s+(\d+)\s*(?:minutes|mins|min)\b/i.exec(desc);
                if (mMin && mMin[1])
                    s = mMin[1] + " min";
            }
        }
        if (!s || s === "—")
            return "—";
        if ((key === "prep_time" || key === "cook_time") && /^\d+(?:\.\d+)?$/.test(s))
            return s + " min";
        return s;
    }

    function extractRecipeNutrition(): var {
        const rv = root.rView ?? ({});
        const ds = root.dossier ?? ({});
        const fm = root.doc?.frontmatter ?? ({});
        const desc = String(rv.description || ds.plot || fm.description || "");

        const parseNum = (v) => {
            if (v === undefined || v === null)
                return 0;
            const m = /(\d+(?:\.\d+)?)/.exec(String(v));
            return m ? parseFloat(m[1]) : 0;
        };

        let calNum = parseNum(rv.calories ?? ds.calories ?? fm.calories);
        if (calNum <= 0) {
            const mCal = /(\d+(?:\.\d+)?)\s*(?:calories|kcal)\b/i.exec(desc);
            if (mCal)
                calNum = parseFloat(mCal[1]);
        }

        let protNum = parseNum(fm.protein ?? rv.protein ?? ds.protein);
        if (protNum <= 0) {
            const mProt = /(\d+(?:\.\d+)?)\s*g\s+(?:of\s+)?protein\b/i.exec(desc)
                || /protein\s*[:=-]\s*(\d+(?:\.\d+)?)/i.exec(desc);
            if (mProt)
                protNum = parseFloat(mProt[1]);
        }

        let fatNum = parseNum(fm.fat ?? rv.fat ?? ds.fat);
        if (fatNum <= 0) {
            const mFat = /(\d+(?:\.\d+)?)\s*g\s+(?:of\s+)?fat\b/i.exec(desc)
                || /fat\s*[:=-]\s*(\d+(?:\.\d+)?)/i.exec(desc);
            if (mFat)
                fatNum = parseFloat(mFat[1]);
        }

        let carbsNum = parseNum(fm.carbs ?? fm.carbohydrates ?? rv.carbs ?? ds.carbs);
        let carbsEstimated = false;
        if (carbsNum <= 0) {
            const mCarbs = /(\d+(?:\.\d+)?)\s*g\s+(?:of\s+)?(?:carbs|carbohydrates)\b/i.exec(desc)
                || /(?:carbs|carbohydrates)\s*[:=-]\s*(\d+(?:\.\d+)?)/i.exec(desc);
            if (mCarbs) {
                carbsNum = parseFloat(mCarbs[1]);
            } else if (calNum > 0 && (protNum > 0 || fatNum > 0)) {
                const remCal = calNum - (protNum * 4.0 + fatNum * 9.0);
                if (remCal > 4) {
                    carbsNum = Math.round(remCal / 4.0);
                    carbsEstimated = true;
                }
            }
        }

        let costStr = String(fm.cost_per_serving ?? fm.costPerServing ?? "").trim();
        if (!costStr) {
            const mCost = /(\$\d+(?:\.\d+)?)\s*(?:per\s+serving)/i.exec(desc);
            if (mCost)
                costStr = mCost[1] + " / serving";
        }

        let scoreStr = "";
        const mScore = /spoonacular\s+score\s+of\s+(\d+%)/i.exec(desc);
        if (mScore)
            scoreStr = mScore[1];
        else if (Number(rv.rating || ds.score || 0) > 0)
            scoreStr = String(rv.rating || ds.score) + " / 5";

        const protCal = Math.max(0, protNum * 4.0);
        const fatCal = Math.max(0, fatNum * 9.0);
        const carbCal = Math.max(0, carbsNum * 4.0);
        const macroTotalCal = Math.max(1, protCal + fatCal + carbCal);

        return {
            "hasAny": calNum > 0 || protNum > 0 || fatNum > 0 || carbsNum > 0,
            "calories": calNum > 0 ? (String(Math.round(calNum)) + " kcal") : "—",
            "caloriesNum": calNum,
            "protein": protNum > 0 ? (String(Math.round(protNum)) + "g") : "—",
            "proteinNum": protNum,
            "proteinRatio": protNum > 0 ? Math.min(1, protCal / macroTotalCal) : 0,
            "fat": fatNum > 0 ? (String(Math.round(fatNum)) + "g") : "—",
            "fatNum": fatNum,
            "fatRatio": fatNum > 0 ? Math.min(1, fatCal / macroTotalCal) : 0,
            "carbs": carbsNum > 0 ? ((carbsEstimated ? "~" : "") + String(Math.round(carbsNum)) + "g") : "—",
            "carbsNum": carbsNum,
            "carbsRatio": carbsNum > 0 ? Math.min(1, carbCal / macroTotalCal) : 0,
            "costPerServing": costStr,
            "scoreLabel": scoreStr
        };
    }

    function splitRecipeIngredient(rawText): var {
        const cleaned = String(rawText ?? "").trim().replace(/^[-*+]\s+/, "");
        if (!cleaned)
            return { "name": "", "amount": "" };
        const pipeIdx = cleaned.indexOf("|");
        if (pipeIdx >= 0) {
            return {
                "name": cleaned.slice(0, pipeIdx).trim(),
                "amount": cleaned.slice(pipeIdx + 1).trim()
            };
        }
        const dashIdx = cleaned.indexOf(" — ");
        if (dashIdx > 0) {
            return {
                "name": cleaned.slice(0, dashIdx).trim(),
                "amount": cleaned.slice(dashIdx + 3).trim()
            };
        }
        return { "name": cleaned, "amount": "" };
    }

    function joinRecipeIngredient(nameStr, amountStr): string {
        const cleanName = String(nameStr ?? "").trim();
        const cleanAmount = String(amountStr ?? "").trim();
        if (cleanName && cleanAmount)
            return cleanName + " | " + cleanAmount;
        return cleanName || cleanAmount;
    }

    function updateRecipeListItem(fmKey: string, sourceList, itemIndex: int, nextValue: string) {
        if (!root.service)
            return;
        const arr = [];
        const src = sourceList ?? [];
        for (let i = 0; i < src.length; ++i)
            arr.push(String(src[i] ?? ""));
        const trimmed = String(nextValue ?? "").trim();
        if (itemIndex >= 0 && itemIndex < arr.length) {
            if (trimmed.length === 0)
                arr.splice(itemIndex, 1);
            else
                arr[itemIndex] = trimmed;
        } else if (trimmed.length > 0) {
            arr.push(trimmed);
        }
        const patch = ({});
        patch[fmKey] = arr;
        root.service.updateNoteFrontmatter(patch);
        root.recipeEditingField = "";
        root.recipeEditingIndex = -1;
        root.restoreWorkspaceFocus();
    }

    function appendRecipeListItem(fmKey: string, sourceList, defaultVal: string, editFieldKey: string) {
        if (!root.service)
            return;
        const arr = [];
        const src = sourceList ?? [];
        for (let i = 0; i < src.length; ++i)
            arr.push(String(src[i] ?? ""));
        arr.push(defaultVal);
        const newIdx = arr.length - 1;
        const patch = ({});
        patch[fmKey] = arr;
        root.service.updateNoteFrontmatter(patch);
        if (editFieldKey === "ingredient") {
            const parts = root.splitRecipeIngredient(defaultVal);
            root.recipeDraftTextA = parts.name;
            root.recipeDraftTextB = parts.amount === "To taste" ? "" : parts.amount;
        } else {
            root.recipeDraftTextA = defaultVal;
            root.recipeDraftTextB = "";
        }
        root.recipeEditingField = editFieldKey;
        root.recipeEditingIndex = newIdx;
    }

    readonly property color exerciseBeginnerColor: root.accentColor
    readonly property color exerciseIntermediateColor: Qt.tint(Qt.color("#e0af68"), Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.16))
    readonly property color exerciseAdvancedColor: Qt.tint(Qt.color("#f7768e"), Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.14))
    readonly property color exerciseSecondaryMuscleColor: root.exerciseIntermediateColor

    function exerciseDisplayText(val, fallback = "—"): string {
        const text = String(val ?? "").trim();
        if (!text || text.toLowerCase() === "none") return fallback;
        return text.replace(/_/g, " ").replace(/\b\w/g, ch => ch.toUpperCase());
    }

    function exerciseListText(val, fallback = "—"): string {
        const arr = Array.isArray(val) ? val : (val ? String(val).split(",") : []);
        const out = [];
        for (let i = 0; i < arr.length; ++i) {
            const t = root.exerciseDisplayText(arr[i], "");
            if (t) out.push(t);
        }
        return out.length > 0 ? out.join(", ") : fallback;
    }

    function exerciseCanonicalLevel(val): string {
        const lvl = String(val ?? "").trim().toLowerCase();
        if (lvl === "expert" || lvl === "advanced") return "expert";
        if (lvl === "intermediate") return "intermediate";
        return "beginner";
    }

    function exerciseLevelLabel(val): string {
        const lvl = root.exerciseCanonicalLevel(val);
        return lvl === "expert" ? "Advanced" : root.exerciseDisplayText(lvl, "Beginner");
    }

    function exerciseLevelColor(val): color {
        const lvl = root.exerciseCanonicalLevel(val);
        if (lvl === "expert") return root.exerciseAdvancedColor;
        if (lvl === "intermediate") return root.exerciseIntermediateColor;
        return root.exerciseBeginnerColor;
    }

    readonly property string exerciseActiveLevel: root.exerciseLevelOverride.length > 0
        ? root.exerciseCanonicalLevel(root.exerciseLevelOverride)
        : root.exerciseCanonicalLevel(root.eView?.level || root.dossier?.level || "beginner")

    readonly property int exerciseActiveProgress: {
        const stepsCount = (root.eView?.steps ?? []).length;
        if (root.exerciseStepProgress >= 0)
            return Math.min(stepsCount, root.exerciseStepProgress);
        const doneArr = root.eView?.instructionDone ?? [];
        let prog = 0;
        for (let i = 0; i < stepsCount && i < doneArr.length; ++i) {
            const ok = doneArr[i] === true || String(doneArr[i]).toLowerCase() === "true";
            if (!ok) break;
            prog = i + 1;
        }
        return prog;
    }

    readonly property string exerciseTapeSide: {
        const seed = String(root.doc?.relPath || root.doc?.title || "exercise-note");
        let hash = 0;
        for (let i = 0; i < seed.length; ++i)
            hash = ((hash * 31) + seed.charCodeAt(i)) | 0;
        return (Math.abs(hash) % 2) ? "right" : "left";
    }

    function setExerciseStepProgress(nextProg: int) {
        const count = (root.eView?.steps ?? []).length;
        const bounded = Math.max(0, Math.min(count, Number(nextProg) || 0));
        root.exerciseStepProgress = bounded;
        const snapshot = [];
        for (let i = 0; i < count; ++i)
            snapshot.push(i < bounded);
        if (root.service)
            root.service.updateNoteFrontmatter({ "instruction_done": snapshot });
    }

    function setExerciseLevel(nextLevel: string) {
        const canon = root.exerciseCanonicalLevel(nextLevel);
        root.exerciseLevelOverride = canon;
        if (root.service)
            root.service.updateNoteFrontmatter({ "level": canon });
    }

    function gamePlatformList(rawPlatform) {
        const s = String(rawPlatform || "").toLowerCase();
        const out = [];
        const add = (id, label, icon) => {
            for (let i = 0; i < out.length; i++) if (out[i].id === id) return;
            out.push({ id: id, label: label, icon: icon });
        };
        if (s.includes("win") || s.includes("pc")) add("windows", "Windows / PC", "desktop_windows");
        if (s.includes("mac") || s.includes("osx") || s.includes("apple")) add("macos", "macOS", "laptop_mac");
        if (s.includes("linux") || s.includes("steam deck") || s.includes("deck")) add("linux", "Linux", "terminal");
        if (s.includes("steam")) add("steam", "Steam", "sports_esports");
        if (s.includes("ps") || s.includes("playstation")) add("playstation", "PlayStation", "videogame_asset");
        if (s.includes("xbox")) add("xbox", "Xbox", "gamepad");
        if (s.includes("switch") || s.includes("nintendo")) add("switch", "Nintendo Switch", "joystick");
        if (out.length === 0 && String(rawPlatform || "").trim().length > 0) {
            add("default", String(rawPlatform).trim(), "sports_esports");
        }
        return out;
    }

    implicitHeight: mainCol.implicitHeight
    visible: isCustomViewNote

    property string _lastDocPath: ""
    onDocChanged: {
        const nextPath = String(root.doc?.relPath ?? "");
        const isDifferentDoc = nextPath !== root._lastDocPath;
        root._lastDocPath = nextPath;
        if (isDifferentDoc) {
            root.financeVisibleTransactionCount = 12;
            root.checkedIngredients = ({});
            root.editingPlaytime = false;
            root.editingCompletion = false;
            root.exerciseShowAnimation = false;
            root.exerciseStepProgress = -1;
            root.exerciseLevelOverride = "";
            root.journalEditingDailyLog = false;
            root.journalEditingWeight = false;
            root.journalWeightOverride = "";
            root.journalWeightHasOverride = false;
            root.journalEditingReflection = false;
            root.editingNoteBody = false;
            root.recipeActiveSection = "overview";
            root.recipeEditingField = "";
            root.recipeEditingIndex = -1;
            root.recipeEditingPersonalNote = false;
            root.recipeStepProgressOverride = -1;
            root.recipeFavoriteOverride = -1;
            root.recipeBookmarkOverride = -1;
        } else if (root.journalWeightHasOverride && String(root.jView?.weight ?? "") === root.journalWeightOverride) {
            root.journalWeightHasOverride = false;
        }
    }

    Connections {
        target: root.service
        ignoreUnknownSignals: true
        function onFileRead(relPath) {
            if (root.noteKind === "recipe" && String(relPath) === String(root.doc?.relPath ?? "")) {
                root.recipeActiveSection = "overview";
                root.recipeEditingField = "";
                root.recipeEditingIndex = -1;
                root.recipeEditingPersonalNote = false;
            }
        }
        function onFileOpened(relPath, category) {
            if (String(relPath || "") !== root._lastDocPath) {
                root.recipeActiveSection = "overview";
            }
        }
    }

    component OrnamentalDivider: RowLayout {
        Layout.fillWidth: true
        spacing: 8
        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: root.borderAccent }
        Text { text: "◇"; font.pixelSize: 9; color: root.accentColor }
        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: root.borderAccent }
    }

    ColumnLayout {
        id: mainCol
        width: parent.width
        spacing: 14

        // =====================================================================
        // 1A. ABYSSAL GAME DOSSIER CUSTOM VIEW (`Custom_Views/Game/Game.{html,js,css}`)
        // =====================================================================
        ColumnLayout {
            id: gameCustomView
            objectName: "nexusGameCustomView"
            Layout.minimumWidth: 0
            visible: root.noteKind === "game"
            Layout.fillWidth: true
            spacing: 22

            // Game Hero (`cv-game-hero`)
            Rectangle {
                id: gameHeroCard
                Layout.fillWidth: true
                implicitHeight: Math.max(300, gameHeroRow.implicitHeight + 44)
                radius: 8
                color: Qt.tint(root.cardBg, Qt.rgba(root.cardDeepBg.r, root.cardDeepBg.g, root.cardDeepBg.b, 0.25))
                border.width: 1
                border.color: root.borderSubtle
                clip: true

                Image {
                    anchors.fill: parent
                    source: String(root.dossier.backdropUrl || root.dossier.posterUrl || "")
                    sourceSize: Qt.size(960, 540)
                    fillMode: Image.PreserveAspectCrop
                    opacity: status === Image.Ready ? 0.30 : 0.0
                    visible: String(source).length > 0
                    asynchronous: true
                    cache: false
                }

                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: Qt.rgba(root.cardDeepBg.r, root.cardDeepBg.g, root.cardDeepBg.b, 0.90) }
                        GradientStop { position: 0.55; color: Qt.rgba(root.cardSubtleBg.r, root.cardSubtleBg.g, root.cardSubtleBg.b, 0.82) }
                        GradientStop { position: 1.0; color: Qt.rgba(root.cardDeepBg.r, root.cardDeepBg.g, root.cardDeepBg.b, 0.95) }
                    }
                }

                GridLayout {
                    id: gameHeroRow
                    columns: width >= 600 ? 2 : 1
                    columnSpacing: 24
                    rowSpacing: 14
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 22

                    // 2:3 Cover (`cv-game-cover-shell`)
                    Rectangle {
                        Layout.preferredWidth: 176
                        Layout.preferredHeight: 264
                        Layout.alignment: Qt.AlignBottom
                        radius: 4
                        color: root.cardDeepBg
                        border.width: 1
                        border.color: root.borderSubtle
                        clip: true

                        Text {
                            anchors.centerIn: parent
                            visible: gameCoverImg.status !== Image.Ready
                            text: "ABYSS"
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: 12
                            font.letterSpacing: 3.2
                            color: root.textMuted
                        }

                        Image {
                            id: gameCoverImg
                            anchors.fill: parent
                            source: String(root.dossier.posterUrl ?? "")
                            sourceSize: Qt.size(480, 640)
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: false
                        }

                        // Inner 7px frame (`cv-game-cover-shell::after`)
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 7
                            color: "transparent"
                            border.width: 1
                            border.color: Qt.rgba(root.textStrong.r, root.textStrong.g, root.textStrong.b, 0.16)
                        }
                    }

                    // Identity (`cv-game-identity`)
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignBottom
                        spacing: 10

                        Flow {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            spacing: 6
                            Text {
                                text: "ABYSSAL GAME DOSSIER"
                                font.family: Appearance.font.family.monospace
                                font.pixelSize: 10
                                font.letterSpacing: 2.2
                                color: root.textMuted
                            }
                            Item { Layout.fillWidth: true }
                            Rectangle {
                                radius: 4
                                color: gameSyncHover.containsMouse ? root.cardHoverBg : root.cardRaisedBg
                                border.width: 1
                                border.color: gameSyncHover.containsMouse ? root.accentColor : root.borderSubtle
                                implicitWidth: gameSyncRow.implicitWidth + 14
                                implicitHeight: 24
                                RowLayout {
                                    id: gameSyncRow
                                    anchors.centerIn: parent
                                    spacing: 5
                                    MaterialSymbol { text: "cloud_download"; iconSize: 13; color: root.accentColor }
                                    Text {
                                        text: "Sync Steam/RAWG"
                                        font.family: Appearance.font.family.monospace
                                        font.pixelSize: 10
                                        font.weight: Font.DemiBold
                                        color: root.accentColor
                                    }
                                }
                                MouseArea {
                                    id: gameSyncHover
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (root.service)
                                            root.service.fetchMediaMetadataForCurrentNote();
                                    }
                                }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: String(root.doc?.title ?? root.dossier.title ?? "")
                            font.pixelSize: 28
                            font.weight: Font.Bold
                            color: root.textStrong
                            wrapMode: Text.Wrap
                        }

                        Text {
                            Layout.fillWidth: true
                            text: {
                                const dev = String(root.dossier.developer || "").trim();
                                const pub = String(root.dossier.publisher || "").trim();
                                if (dev && pub && dev !== pub) return dev + " · " + pub;
                                return dev || pub || "Unknown Studio";
                            }
                            font.pixelSize: 13
                            color: root.textSecondary
                            elide: Text.ElideRight
                        }

                        // Platform chips (`cv-game-chips`)
                        Flow {
                            Layout.fillWidth: true
                            spacing: 8
                            Repeater {
                                model: root.gamePlatformList(root.dossier.platform || root.doc?.frontmatter?.platforms || root.doc?.frontmatter?.platform)
                                delegate: Rectangle {
                                    required property var modelData
                                    height: 24
                                    width: platChipRow.implicitWidth + 14
                                    radius: 4
                                    color: Qt.rgba(root.cardRaisedBg.r, root.cardRaisedBg.g, root.cardRaisedBg.b, 0.78)
                                    border.width: 1
                                    border.color: root.borderSubtle

                                    RowLayout {
                                        id: platChipRow
                                        anchors.centerIn: parent
                                        spacing: 5
                                        MaterialSymbol {
                                            text: modelData.icon
                                            iconSize: 14
                                            color: root.accentColor
                                        }
                                        Text {
                                            text: modelData.label
                                            font.family: Appearance.font.family.monospace
                                            font.pixelSize: 10
                                            color: root.textSecondary
                                        }
                                    }
                                }
                            }
                        }

                        // 4-column metrics strip (`cv-game-metrics`)
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.topMargin: 2
                            implicitHeight: 54
                            color: "transparent"

                            Rectangle { anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right; height: 1; color: root.borderSubtle }
                            Rectangle { anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right; height: 1; color: root.borderSubtle }

                            RowLayout {
                                anchors.fill: parent
                                spacing: 0

                                // Metric 1: STATUS
                                Item {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    ColumnLayout {
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.left: parent.left
                                        spacing: 3
                                        Text {
                                            text: "STATUS"
                                            font.family: Appearance.font.family.monospace
                                            font.pixelSize: 9
                                            font.letterSpacing: 1.5
                                            color: root.textMuted
                                        }
                                        Text {
                                            readonly property string st: String(root.dossier.status || "Backlog")
                                            text: st
                                            font.family: Appearance.font.family.monospace
                                            font.pixelSize: 14
                                            font.weight: Font.Bold
                                            color: st.toLowerCase() === "completed" ? root.accentColor : root.textStrong
                                        }
                                    }
                                }

                                Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; Layout.topMargin: 10; Layout.bottomMargin: 10; color: root.borderSubtle }

                                // Metric 2: RATING
                                Item {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    ColumnLayout {
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.left: parent.left
                                        anchors.leftMargin: 14
                                        spacing: 3
                                        Text {
                                            text: "RATING"
                                            font.family: Appearance.font.family.monospace
                                            font.pixelSize: 9
                                            font.letterSpacing: 1.5
                                            color: root.textMuted
                                        }
                                        Text {
                                            readonly property real rv: Number(root.dossier.rating || root.dossier.score || 0)
                                            text: rv > 0 ? (String(rv) + "/10") : "—"
                                            font.family: Appearance.font.family.monospace
                                            font.pixelSize: 14
                                            font.weight: Font.Bold
                                            color: root.textStrong
                                        }
                                    }
                                }

                                Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; Layout.topMargin: 10; Layout.bottomMargin: 10; color: root.borderSubtle }

                                // Metric 3: PLAYTIME (Editable on click)
                                Item {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    ColumnLayout {
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.left: parent.left
                                        anchors.leftMargin: 14
                                        spacing: 3
                                        Text {
                                            text: "PLAYTIME"
                                            font.family: Appearance.font.family.monospace
                                            font.pixelSize: 9
                                            font.letterSpacing: 1.5
                                            color: root.textMuted
                                        }
                                        Text {
                                            visible: !root.editingPlaytime
                                            text: String(Number(root.dossier.hoursPlayed || 0)) + "h"
                                            font.family: Appearance.font.family.monospace
                                            font.pixelSize: 14
                                            font.weight: Font.Bold
                                            color: playtimeMouse.containsMouse ? root.accentColor : root.textStrong
                                            MouseArea {
                                                id: playtimeMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    playtimeInput.text = String(Number(root.dossier.hoursPlayed || 0));
                                                    root.editingPlaytime = true;
                                                    playtimeInput.forceActiveFocus();
                                                    playtimeInput.selectAll();
                                                }
                                            }
                                        }
                                        TextField {
                                            id: playtimeInput
                                            visible: root.editingPlaytime
                                            Layout.preferredWidth: 74
                                            implicitHeight: 22
                                            font.family: Appearance.font.family.monospace
                                            font.pixelSize: 12
                                            color: root.textStrong
                                            background: Rectangle {
                                                radius: 3
                                                color: root.cardDeepBg
                                                border.width: 1
                                                border.color: root.accentColor
                                            }
                                            onAccepted: {
                                                const v = Math.max(0, Number(text) || 0);
                                                root.editingPlaytime = false;
                                                if (root.service)
                                                    root.service.updateNoteFrontmatter({ "PlaytimeHours": v });
                                                root.restoreWorkspaceFocus();
                                            }
                                            Keys.onEscapePressed: event => {
                                                root.editingPlaytime = false;
                                                root.restoreWorkspaceFocus();
                                                event.accepted = true;
                                            }
                                            Keys.onPressed: event => root.forwardWorkspaceShortcut(event)
                                            onEditingFinished: root.editingPlaytime = false
                                        }
                                    }
                                }

                                Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; Layout.topMargin: 10; Layout.bottomMargin: 10; color: root.borderSubtle }

                                // Metric 4: RELEASED
                                Item {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    ColumnLayout {
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.left: parent.left
                                        anchors.leftMargin: 14
                                        spacing: 3
                                        Text {
                                            text: "RELEASED"
                                            font.family: Appearance.font.family.monospace
                                            font.pixelSize: 9
                                            font.letterSpacing: 1.5
                                            color: root.textMuted
                                        }
                                        Text {
                                            text: String(root.dossier.releaseDate || root.dossier.year || "TBA")
                                            font.family: Appearance.font.family.monospace
                                            font.pixelSize: 14
                                            font.weight: Font.Bold
                                            color: root.textStrong
                                            elide: Text.ElideRight
                                        }
                                    }
                                }
                            }
                        }

                        // Completion bar (`cv-game-completion`)
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    text: "COMPLETION"
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: 10
                                    font.letterSpacing: 1.4
                                    color: root.textMuted
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    visible: !root.editingCompletion
                                    text: String(Math.max(0, Math.min(100, Number(root.dossier.completion || 0)))) + "%"
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: 11
                                    font.weight: Font.Bold
                                    color: compMouse.containsMouse ? root.accentColor : root.textStrong
                                    MouseArea {
                                        id: compMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            compInput.text = String(Math.max(0, Math.min(100, Number(root.dossier.completion || 0))));
                                            root.editingCompletion = true;
                                            compInput.forceActiveFocus();
                                            compInput.selectAll();
                                        }
                                    }
                                }
                                TextField {
                                    id: compInput
                                    visible: root.editingCompletion
                                    Layout.preferredWidth: 56
                                    implicitHeight: 20
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: 11
                                    color: root.textStrong
                                    background: Rectangle {
                                        radius: 3
                                        color: root.cardDeepBg
                                        border.width: 1
                                        border.color: root.accentColor
                                    }
                                    onAccepted: {
                                        const v = Math.max(0, Math.min(100, Math.round(Number(text) || 0)));
                                        root.editingCompletion = false;
                                        if (root.service)
                                            root.service.updateNoteFrontmatter({ "Completion": v });
                                        root.restoreWorkspaceFocus();
                                    }
                                    Keys.onEscapePressed: event => {
                                        root.editingCompletion = false;
                                        root.restoreWorkspaceFocus();
                                        event.accepted = true;
                                    }
                                    Keys.onPressed: event => root.forwardWorkspaceShortcut(event)
                                    onEditingFinished: root.editingCompletion = false
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 4
                                radius: 2
                                color: Qt.rgba(root.cardDeepBg.r, root.cardDeepBg.g, root.cardDeepBg.b, 0.85)
                                clip: true

                                Rectangle {
                                    readonly property real pct: Math.max(0, Math.min(1, Number(root.dossier.completion || 0) / 100.0))
                                    width: parent.width * pct
                                    height: parent.height
                                    radius: 2
                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal
                                        GradientStop { position: 0.0; color: root.ccStop(9) }
                                        GradientStop { position: 1.0; color: root.accentColor }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Main 2-Column Game Layout (`cv-game-layout`: Left Personal Log Journal + Right Dossier Sidebar)
            GridLayout {
                columns: width >= 660 ? 2 : 1
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                columnSpacing: 24
                rowSpacing: 16

                // Left Column: PERSONAL LOG / Journal (`cv-game-journal`)
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 640
                    Layout.alignment: Qt.AlignTop
                    spacing: 12

                    // Section Head (`cv-game-section-head--outer`)
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12
                        ColumnLayout {
                            spacing: 2
                            Text {
                                text: "PERSONAL LOG"
                                font.family: Appearance.font.family.monospace
                                font.pixelSize: 9
                                font.letterSpacing: 2.0
                                color: root.textMuted
                            }
                            Text {
                                text: "Journal"
                                font.pixelSize: 18
                                font.weight: Font.Bold
                                color: root.textStrong
                            }
                        }
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 1
                            color: root.borderSubtle
                        }
                    }

                    // Ruled Paper Sheet (`cv-game-log cv-game-paper`)
                    Rectangle {
                        id: gamePaperCard
                        objectName: "nexusGamePaperCard"
                        readonly property int minPaperHeight: Math.max(380, root.minDocumentSurfaceHeight - gameHeroCard.implicitHeight - 66)
                        Layout.fillWidth: true
                        implicitHeight: Math.max(minPaperHeight, gamePaperCol.implicitHeight + 36)
                        radius: 9
                        color: root.cardSubtleBg
                        border.width: 1
                        border.color: root.borderSubtle
                        clip: true

                        // Subtle notebook lines matching Viewing Notes
                        Canvas {
                            anchors.fill: parent
                            opacity: 0.25
                            readonly property color _ruleColor: root.borderSubtle
                            on_RuleColorChanged: if (visible) requestPaint()
                            onWidthChanged: if (visible) requestPaint()
                            onHeightChanged: if (visible) requestPaint()
                            onVisibleChanged: if (visible) requestPaint()
                            onPaint: {
                                const ctx = getContext("2d");
                                ctx.reset();
                                ctx.strokeStyle = root.borderSubtle;
                                ctx.lineWidth = 1;
                                for (let y = 52; y < height - 12; y += 26) {
                                    ctx.beginPath();
                                    ctx.moveTo(14, y);
                                    ctx.lineTo(width - 14, y);
                                    ctx.stroke();
                                }
                            }
                        }

                        ColumnLayout {
                            id: gamePaperCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.leftMargin: 18
                            anchors.rightMargin: 18
                            anchors.topMargin: 18
                            anchors.bottomMargin: 18
                            spacing: 8

                            // Paper header (`cv-game-paper-head`)
                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    text: "YOUR NOTES"
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: 10
                                    font.letterSpacing: 1.8
                                    color: root.textMuted
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: root.editingNoteBody ? "Editing · Esc to finish" : "Click prose · Edit mode"
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: 10
                                    color: (editProseMouse.containsMouse || root.editingNoteBody) ? root.accentColor : root.textMuted
                                    MouseArea {
                                        id: editProseMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (root.editingNoteBody) {
                                                if (root.service)
                                                    root.service.saveNoteBodyMarkdown(gameBodyEditor.text);
                                                root.editingNoteBody = false;
                                            } else {
                                                gameBodyEditor.text = root.service ? root.service.getNoteBodyMarkdown() : "";
                                                root.editingNoteBody = true;
                                            }
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 1
                                color: root.borderSubtle
                            }

                            // Reading Mode (Default): Rendered markdown blocks (`## Personal Log`, `## Mechanics`, `## Story & World`, `## Memorable Moments`)
                            Item {
                                id: gameBodyReadingArea
                                objectName: "nexusGameBodyReadingArea"
                                visible: !root.editingNoteBody
                                Layout.fillWidth: true
                                implicitHeight: Math.max(240, gamePaperCard.minPaperHeight - 76, gameReadingBlocksCol.implicitHeight + 12)

                                ColumnLayout {
                                    id: gameReadingBlocksCol
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    spacing: 8

                                    Repeater {
                                        model: root.doc?.blocks ?? []
                                        delegate: Item {
                                            required property var modelData
                                            Layout.fillWidth: true
                                            readonly property string rawTxt: String(modelData?.text ?? "").trim()
                                            visible: rawTxt.length > 0
                                                     && !rawTxt.includes("Custom_Views/")
                                                     && !root.isSyntheticSynopsisBlock(modelData)
                                                     && !(modelData?.kind === "heading" && Number(modelData?.level ?? 1) === 1)
                                            implicitHeight: visible ? gameProseBlkCol.implicitHeight + (modelData?.kind === "heading" ? 12 : 4) : 0

                                            ColumnLayout {
                                                id: gameProseBlkCol
                                                width: parent.width
                                                anchors.bottom: parent.bottom
                                                spacing: 4

                                                Text {
                                                    Layout.fillWidth: true
                                                    text: modelData?.kind === "bullet"
                                                        ? ("•  " + (modelData?.richHtml ? root.themeRichHtml(modelData.richHtml) : String(modelData?.text || "")))
                                                        : (modelData?.richHtml ? root.themeRichHtml(modelData.richHtml) : String(modelData?.text || ""))
                                                    textFormat: modelData?.richHtml ? Text.RichText : Text.PlainText
                                                    font.family: modelData?.kind === "heading" ? Appearance.font.family.monospace : Appearance.font.family.main
                                                    font.pixelSize: modelData?.kind === "heading" ? 12 : 13
                                                    font.weight: modelData?.kind === "heading" ? Font.Bold : Font.Normal
                                                    font.letterSpacing: modelData?.kind === "heading" ? 1.5 : 0
                                                    font.capitalization: modelData?.kind === "heading" ? Font.AllUppercase : Font.MixedCase
                                                    color: modelData?.kind === "heading" ? root.accentColor : root.textPrimary
                                                    wrapMode: Text.Wrap
                                                    onLinkActivated: link => {
                                                        if (root.service && link.startsWith("wikilink:"))
                                                            root.service.followWikilink(decodeURIComponent(link.substring(9)));
                                                    }
                                                }

                                                Rectangle {
                                                    visible: modelData?.kind === "heading"
                                                    Layout.fillWidth: true
                                                    implicitHeight: 1
                                                    color: root.borderSubtle
                                                }
                                            }
                                        }
                                    }

                                    Text {
                                        visible: {
                                            const blks = root.doc?.blocks ?? [];
                                            for (let i = 0; i < blks.length; ++i) {
                                                const b = blks[i];
                                                const rt = String(b?.text ?? "").trim();
                                                if (rt.length > 0 && !rt.includes("Custom_Views/") && !root.isSyntheticSynopsisBlock(b) && !(b?.kind === "heading" && Number(b?.level ?? 1) === 1))
                                                    return false;
                                            }
                                            return true;
                                        }
                                        Layout.fillWidth: true
                                        Layout.topMargin: 8
                                        text: "Click to write your personal log, mechanics notes, and memorable moments..."
                                        font.pixelSize: 12
                                        font.italic: true
                                        color: root.textMuted
                                        wrapMode: Text.Wrap
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.IBeamCursor
                                    onClicked: {
                                        gameBodyEditor.text = root.service ? root.service.getNoteBodyMarkdown() : "";
                                        root.editingNoteBody = true;
                                    }
                                }
                            }

                            // Editing Mode (Activated on Click)
                            ColumnLayout {
                                visible: root.editingNoteBody && root.noteKind === "game"
                                Layout.fillWidth: true
                                spacing: 8

                                TextArea {
                                    id: gameBodyEditor
                                    objectName: "nexusGameBodyEditor"
                                    Layout.fillWidth: true
                                    Layout.minimumHeight: 260
                                    text: root.service ? root.service.getNoteBodyMarkdown() : ""
                                    placeholderText: "Write your game journal & notes here..."
                                    placeholderTextColor: root.textMuted
                                    color: root.textPrimary
                                    font.family: Appearance.font.family.main
                                    font.pixelSize: 13
                                    wrapMode: TextEdit.Wrap
                                    background: Item {}
                                    onVisibleChanged: {
                                        if (visible)
                                            Qt.callLater(() => { if (gameBodyEditor.visible) gameBodyEditor.forceActiveFocus(); });
                                    }
                                    onActiveFocusChanged: {
                                        if (!activeFocus && visible && root.editingNoteBody && root.noteKind === "game" && !gameCancelBtnMouse.containsMouse && !gameCancelBtnMouse.pressed) {
                                            if (root.service)
                                                root.service.saveNoteBodyMarkdown(gameBodyEditor.text);
                                            root.editingNoteBody = false;
                                        }
                                    }
                                    Keys.onEscapePressed: event => {
                                        if (root.service)
                                            root.service.saveNoteBodyMarkdown(gameBodyEditor.text);
                                        gameBodyEditor.focus = false;
                                        root.editingNoteBody = false;
                                        root.restoreWorkspaceFocus();
                                        event.accepted = true;
                                    }
                                    Keys.onPressed: event => {
                                        if ((event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_S)) {
                                            if (root.service)
                                                root.service.saveNoteBodyMarkdown(gameBodyEditor.text);
                                            gameBodyEditor.focus = false;
                                            root.editingNoteBody = false;
                                            root.restoreWorkspaceFocus();
                                            event.accepted = true;
                                            return;
                                        }
                                        root.forwardWorkspaceShortcut(event);
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    Item { Layout.fillWidth: true }
                                    Rectangle {
                                        radius: 5
                                        color: root.cardRaisedBg
                                        border.width: 1
                                        border.color: root.borderSubtle
                                        implicitWidth: gameCancelBtnTxt.implicitWidth + 16
                                        implicitHeight: 24
                                        Text {
                                            id: gameCancelBtnTxt
                                            anchors.centerIn: parent
                                            text: "Cancel"
                                            font.pixelSize: 10
                                            color: root.textSecondary
                                        }
                                        MouseArea {
                                            id: gameCancelBtnMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.editingNoteBody = false
                                        }
                                    }
                                    Rectangle {
                                        objectName: "nexusGameBodySaveButton"
                                        radius: 5
                                        color: root.accentColor
                                        implicitWidth: gameSaveBtnTxt.implicitWidth + 16
                                        implicitHeight: 24
                                        Text {
                                            id: gameSaveBtnTxt
                                            anchors.centerIn: parent
                                            text: "Save Notes"
                                            font.pixelSize: 10
                                            font.weight: Font.Bold
                                            color: root.onAccentColor
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (root.service)
                                                    root.service.saveNoteBodyMarkdown(gameBodyEditor.text);
                                                root.editingNoteBody = false;
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Right Column: Sticky Dossier Sidebar (`cv-game-dossier`)
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 300
                    Layout.minimumWidth: 0
                    Layout.maximumWidth: parent.columns === 1 ? Infinity : 330
                    Layout.alignment: Qt.AlignTop
                    implicitHeight: gameDossierCol.implicitHeight + 36
                    radius: 6
                    color: Qt.tint(root.cardSubtleBg, Qt.rgba(root.cardBg.r, root.cardBg.g, root.cardBg.b, 0.35))
                    border.width: 1
                    border.color: root.borderSubtle

                    ColumnLayout {
                        id: gameDossierCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 18
                        spacing: 16

                        // 1. DOSSIER Summary
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            Text {
                                text: "DOSSIER"
                                font.family: Appearance.font.family.monospace
                                font.pixelSize: 10
                                font.weight: Font.Bold
                                font.letterSpacing: 1.8
                                color: root.textMuted
                            }
                            Text {
                                Layout.fillWidth: true
                                text: String(root.dossier.plot || root.doc?.frontmatter?.description || "No summary recorded yet.")
                                font.family: Appearance.font.family.monospace
                                font.pixelSize: 12
                                color: root.textPrimary
                                wrapMode: Text.Wrap
                                horizontalAlignment: Text.AlignJustify
                            }
                        }

                        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: root.borderSubtle }

                        // 2. PLAY STATUS (2x3 Interactive Grid)
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Text {
                                text: "PLAY STATUS"
                                font.family: Appearance.font.family.monospace
                                font.pixelSize: 10
                                font.weight: Font.Bold
                                font.letterSpacing: 1.8
                                color: root.textMuted
                            }
                            GridLayout {
                                Layout.fillWidth: true
                                columns: 3
                                rowSpacing: 6
                                columnSpacing: 6
                                Repeater {
                                    model: ["Backlog", "Playing", "Completed", "Paused", "Dropped", "Wishlist"]
                                    delegate: Rectangle {
                                        required property string modelData
                                        readonly property bool isActive: String(root.dossier.status || "Backlog").toLowerCase() === modelData.toLowerCase()
                                        Layout.fillWidth: true
                                        implicitHeight: 28
                                        radius: 4
                                        color: isActive
                                            ? Qt.tint(root.cardRaisedBg, Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.22))
                                            : (gStatusMouse.containsMouse ? root.cardHoverBg : root.cardBg)
                                        border.width: 1
                                        border.color: isActive ? root.accentColor : (gStatusMouse.containsMouse ? root.ccStop(8) : root.borderSubtle)

                                        Text {
                                            anchors.centerIn: parent
                                            text: modelData.toUpperCase()
                                            font.family: Appearance.font.family.monospace
                                            font.pixelSize: 9
                                            font.weight: isActive ? Font.Bold : Font.Medium
                                            font.letterSpacing: 0.8
                                            color: isActive ? root.textStrong : root.textSecondary
                                        }
                                        MouseArea {
                                            id: gStatusMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (root.service)
                                                    root.service.updateNoteFrontmatter({ "Status": modelData });
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: root.borderSubtle }

                        // 3. YOUR RATING (`cv-game-rating` — 10 numbered buttons 1..10 matching Game.js renderRating)
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    text: "YOUR RATING"
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: 10
                                    font.weight: Font.Bold
                                    font.letterSpacing: 1.8
                                    color: root.textMuted
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    readonly property real rv: Number(root.dossier.rating || 0)
                                    text: rv > 0 ? (String(rv) + "/10") : "Unrated"
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: 10
                                    color: root.textSecondary
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                Repeater {
                                    model: 10
                                    delegate: Rectangle {
                                        required property int index
                                        readonly property int scoreVal: index + 1
                                        readonly property real curRating: Number(root.dossier.rating || 0)
                                        readonly property bool isActive: scoreVal <= Math.round(curRating)
                                        Layout.fillWidth: true
                                        implicitHeight: 26
                                        radius: 4
                                        color: isActive
                                            ? Qt.tint(root.cardRaisedBg, Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.24))
                                            : (rateBtnMouse.containsMouse ? root.cardHoverBg : root.cardBg)
                                        border.width: 1
                                        border.color: isActive ? root.accentColor : (rateBtnMouse.containsMouse ? root.ccStop(8) : root.borderSubtle)

                                        Text {
                                            anchors.centerIn: parent
                                            text: String(scoreVal)
                                            font.family: Appearance.font.family.monospace
                                            font.pixelSize: 10
                                            font.weight: isActive ? Font.Bold : Font.Medium
                                            color: isActive ? root.textStrong : (rateBtnMouse.containsMouse ? root.textPrimary : root.textMuted)
                                        }

                                        MouseArea {
                                            id: rateBtnMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (!root.service) return;
                                                const nextVal = Math.abs(curRating - scoreVal) < 0.01 ? 0 : scoreVal;
                                                root.service.updateNoteFrontmatter({ "Rating": nextVal });
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: root.borderSubtle }

                        // 4. METADATA Definition List (`cv-game-dl` with platform icon chips `cv-game-dd--icons`)
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            Text {
                                text: "METADATA"
                                font.family: Appearance.font.family.monospace
                                font.pixelSize: 10
                                font.weight: Font.Bold
                                font.letterSpacing: 1.8
                                color: root.textMuted
                            }

                            Repeater {
                                model: {
                                    const rows = [];
                                    const fm = root.doc?.frontmatter ?? ({});
                                    const pushRow = (k, v) => {
                                        const s = String(v ?? "").trim();
                                        if (s.length > 0 && s !== "0") rows.push({ key: k, val: s });
                                    };
                                    pushRow("Platforms", root.dossier.platform || fm.platforms || fm.platform);
                                    pushRow("Developer", root.dossier.developer || fm.developers || fm.developer);
                                    pushRow("Publisher", root.dossier.publisher || fm.publishers || fm.publisher);
                                    pushRow("Genres", root.dossier.genre || fm.genres || fm.genre);
                                    pushRow("Released", root.dossier.releaseDate || root.dossier.year || fm.releasedate);
                                    pushRow("Metacritic", root.dossier.metacritic || fm.metacritic);
                                    pushRow("Store", root.dossier.store || fm.store);
                                    pushRow("Source", root.dossier.source || fm.source);
                                    if (Number(root.dossier.achievementsTotal || 0) > 0) {
                                        pushRow("Achievements", String(Number(root.dossier.achievementsEarned || 0)) + " / " + String(Number(root.dossier.achievementsTotal)));
                                    }
                                    return rows;
                                }
                                delegate: ColumnLayout {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    spacing: 4
                                    readonly property var platIcons: modelData.key === "Platforms" ? root.gamePlatformList(modelData.val) : []
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 10
                                        Text {
                                            Layout.preferredWidth: 88
                                            Layout.alignment: Qt.AlignVCenter
                                            text: modelData.key
                                            font.family: Appearance.font.family.monospace
                                            font.pixelSize: 11
                                            color: root.textMuted
                                        }
                                        Item { Layout.fillWidth: true; visible: platIcons.length > 0 }
                                        Row {
                                            visible: platIcons.length > 0
                                            spacing: 5
                                            Repeater {
                                                model: platIcons
                                                delegate: Rectangle {
                                                    required property var modelData
                                                    width: 24
                                                    height: 24
                                                    radius: 4
                                                    color: root.cardBg
                                                    border.width: 1
                                                    border.color: root.borderSubtle
                                                    MaterialSymbol {
                                                        anchors.centerIn: parent
                                                        text: modelData.icon
                                                        iconSize: 13
                                                        color: root.textSecondary
                                                    }
                                                    MouseArea {
                                                        id: metaPlatHover
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                    }
                                                    ToolTip.visible: metaPlatHover.containsMouse
                                                    ToolTip.text: modelData.label
                                                }
                                            }
                                        }
                                        Text {
                                            visible: platIcons.length === 0
                                            Layout.fillWidth: true
                                            text: modelData.val
                                            font.family: Appearance.font.family.monospace
                                            font.pixelSize: 12
                                            color: root.textPrimary
                                            horizontalAlignment: Text.AlignRight
                                            wrapMode: Text.Wrap
                                        }
                                    }
                                    Rectangle {
                                        Layout.fillWidth: true
                                        implicitHeight: 1
                                        color: Qt.rgba(root.borderSubtle.r, root.borderSubtle.g, root.borderSubtle.b, 0.5)
                                    }
                                }
                            }
                        }

                        // 5. EXTERNAL RECORDS (`cv-game-links`)
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            readonly property var extLinks: {
                                const out = [];
                                const fm = root.doc?.frontmatter ?? ({});
                                const stUrl = String(root.dossier.storeUrl || fm.storeurl || "").trim();
                                const webUrl = String(root.dossier.websiteUrl || fm.website || "").trim();
                                const srcUrl = String(root.dossier.sourceUrl || fm.sourceurl || "").trim();
                                if (stUrl.startsWith("http")) out.push({ label: String(root.dossier.store || "Store") + " ↗", url: stUrl });
                                if (webUrl.startsWith("http")) out.push({ label: "Official website ↗", url: webUrl });
                                if (srcUrl.startsWith("http")) out.push({ label: "Metadata source ↗", url: srcUrl });
                                return out;
                            }
                            visible: extLinks.length > 0

                            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: root.borderSubtle }

                            Text {
                                text: "EXTERNAL RECORDS"
                                font.family: Appearance.font.family.monospace
                                font.pixelSize: 10
                                font.weight: Font.Bold
                                font.letterSpacing: 1.8
                                color: root.textMuted
                            }

                            Repeater {
                                model: parent.extLinks
                                delegate: Rectangle {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    implicitHeight: 26
                                    radius: 4
                                    color: extLinkMouse.containsMouse ? root.cardHoverBg : "transparent"
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.left: parent.left
                                        anchors.leftMargin: 4
                                        text: modelData.label
                                        font.family: Appearance.font.family.monospace
                                        font.pixelSize: 11
                                        color: extLinkMouse.containsMouse ? root.accentColor : root.textSecondary
                                    }
                                    MouseArea {
                                        id: extLinkMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: Qt.openUrlExternally(modelData.url)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // =====================================================================
        // 1. HERO / DOSSIER BANNER (for Media, Place, Book, Clipping, Website, Settings)
        // =====================================================================
        Rectangle {
            id: dossierBannerCard
            objectName: "nexusDocumentDossierBanner"
            Layout.minimumWidth: 0
            visible: root.isDossierBannerNote && root.noteKind !== "game" && root.noteKind !== "exercise"
            Layout.fillWidth: true
            implicitHeight: dossierBannerCol.implicitHeight + 32
            radius: 10
            color: root.cardBg
            border.width: 1
            border.color: root.borderAccent
            clip: true

            Image {
                anchors.fill: parent
                source: String(root.dossier.backdropUrl || root.dossier.posterUrl || "")
                sourceSize: Qt.size(960, 540)
                fillMode: Image.PreserveAspectCrop
                opacity: status === Image.Ready ? 0.18 : 0.0
                visible: String(source).length > 0
                asynchronous: true
                cache: false
            }

            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: Qt.rgba(root.cardDeepBg.r, root.cardDeepBg.g, root.cardDeepBg.b, 0.94) }
                    GradientStop { position: 0.55; color: Qt.rgba(root.cardBg.r, root.cardBg.g, root.cardBg.b, 0.86) }
                    GradientStop { position: 1.0; color: Qt.rgba(root.cardBg.r, root.cardBg.g, root.cardBg.b, 0.95) }
                }
            }

            ColumnLayout {
                id: dossierBannerCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 16
                spacing: 12

                GridLayout {
                    id: dossierHeroGrid
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    columns: width >= 600 ? 3 : 1
                    columnSpacing: 18
                    rowSpacing: 14

                    // Poster / Cover thumbnail
                    Rectangle {
                        visible: String(root.dossier.posterUrl ?? "").length > 0 || root.noteKind === "movie" || root.noteKind === "tvseries" || root.noteKind === "book"
                        Layout.preferredWidth: root.noteKind === "place" || root.noteKind === "clipping" ? 136 : 104
                        Layout.preferredHeight: root.noteKind === "place" || root.noteKind === "clipping" ? 100 : 150
                        Layout.alignment: Qt.AlignTop
                        radius: 7
                        color: root.cardRaisedBg
                        border.width: 1
                        border.color: root.borderSubtle
                        clip: true

                        Image {
                            id: dossierPosterImg
                            anchors.fill: parent
                            source: String(root.dossier.posterUrl ?? "")
                            sourceSize: Qt.size(480, 640)
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: false
                            visible: String(source).length > 0
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: !dossierPosterImg.visible || dossierPosterImg.status !== Image.Ready
                            text: root.noteKind === "book" ? "No Cover" : "No Poster"
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: 10
                            color: root.textMuted
                        }
                    }

                    // Main hero copy column
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignTop
                        spacing: 7

                        Flow {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            spacing: 6

                            Rectangle {
                                radius: 4
                                color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.16)
                                border.width: 1
                                border.color: root.accentColor
                                implicitWidth: kindBadgeText.implicitWidth + 12
                                implicitHeight: 20
                                Text {
                                    id: kindBadgeText
                                    anchors.centerIn: parent
                                    text: root.noteKind === "tvseries" ? "TV SERIES"
                                        : root.noteKind === "book" ? "BOOK DOSSIER"
                                        : root.noteKind === "clipping" ? "WEB CLIPPING"
                                        : root.noteKind.toUpperCase()
                                    font.pixelSize: 9
                                    font.weight: Font.Bold
                                    font.letterSpacing: 1.1
                                    color: root.accentColor
                                }
                            }

                            Rectangle {
                                visible: String(root.dossier.year ?? "").length > 0
                                radius: 4
                                color: root.cardRaisedBg
                                implicitWidth: yearBadgeText.implicitWidth + 10
                                implicitHeight: 20
                                Text {
                                    id: yearBadgeText
                                    anchors.centerIn: parent
                                    text: String(root.dossier.year ?? "")
                                    font.pixelSize: 10
                                    font.family: Appearance.font.family.monospace
                                    color: root.textSecondary
                                }
                            }

                            Rectangle {
                                visible: String(root.dossier.rating ?? "").length > 0
                                radius: 4
                                color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.18)
                                border.width: 1
                                border.color: root.borderAccent
                                implicitWidth: ratingBadgeText.implicitWidth + 12
                                implicitHeight: 20
                                Text {
                                    id: ratingBadgeText
                                    anchors.centerIn: parent
                                    text: "★ " + String(root.dossier.rating ?? "")
                                    font.pixelSize: 10
                                    font.weight: Font.Bold
                                    color: root.accentColor
                                }
                            }

                            Rectangle {
                                visible: String(root.dossier.status ?? "").length > 0
                                radius: 4
                                color: root.cardRaisedBg
                                border.width: 1
                                border.color: root.borderSubtle
                                implicitWidth: statusBadgeText.implicitWidth + 12
                                implicitHeight: 20
                                Text {
                                    id: statusBadgeText
                                    anchors.centerIn: parent
                                    text: String(root.dossier.status ?? "")
                                    font.pixelSize: 10
                                    font.weight: Font.DemiBold
                                    color: root.textPrimary
                                }
                            }

                            Item { Layout.fillWidth: true }

                            // Interactive Auto-Extract / API Fetch button for Media, Games, Books, Places
                            Rectangle {
                                objectName: "nexusDossierSyncApiButton"
                                visible: root.noteKind === "movie" || root.noteKind === "tvseries" || root.noteKind === "game" || root.noteKind === "book" || root.noteKind === "place"
                                radius: 5
                                color: apiFetchHover.containsMouse ? root.cardHoverBg : root.cardRaisedBg
                                border.width: 1
                                border.color: root.borderAccent
                                implicitWidth: apiFetchRow.implicitWidth + 14
                                implicitHeight: 24

                                RowLayout {
                                    id: apiFetchRow
                                    anchors.centerIn: parent
                                    spacing: 4
                                    MaterialSymbol { text: "cloud_download"; iconSize: 13; color: root.accentColor }
                                    Text {
                                        text: root.noteKind === "movie" || root.noteKind === "tvseries" ? "Sync TMDB/OMDb"
                                            : root.noteKind === "game" ? "Sync Steam/RAWG"
                                            : root.noteKind === "book" ? "Sync Book Info"
                                            : root.noteKind === "place" ? "Sync Place Info" : "Sync Metadata"
                                        font.pixelSize: 10
                                        font.weight: Font.DemiBold
                                        color: root.accentColor
                                    }
                                }
                                MouseArea {
                                    id: apiFetchHover
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (root.service)
                                            root.service.fetchMediaMetadataForCurrentNote();
                                    }
                                }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: String(root.doc?.title ?? root.dossier.title ?? "")
                            font.family: root.serifFontFamily
                            font.pixelSize: 24
                            font.weight: Font.Bold
                            color: root.textStrong
                            wrapMode: Text.Wrap
                        }

                        Text {
                            visible: String(root.dossier.subtitle || root.dossier.author || "").length > 0
                            Layout.fillWidth: true
                            text: root.noteKind === "book" && String(root.dossier.author ?? "").length > 0
                                ? ("by " + String(root.dossier.author).replace(/^\[\[|\]\]$/g, ""))
                                : String(root.dossier.subtitle ?? "")
                            font.family: root.serifFontFamily
                            font.pixelSize: 13
                            font.italic: root.noteKind !== "book"
                            color: root.textSecondary
                            wrapMode: Text.Wrap
                        }

                        // Genre chips (Media / Book)
                        Flow {
                            visible: String(root.dossier.genre ?? "").length > 0
                            Layout.fillWidth: true
                            spacing: 6

                            Repeater {
                                model: {
                                    const g = String(root.dossier.genre ?? "");
                                    if (!g.trim().length)
                                        return [];
                                    return g.split(/[,;/]/).map(s => s.replace(/^\[\[|\]\]$/g, "").trim()).filter(s => s.length > 0).slice(0, 6);
                                }
                                delegate: Rectangle {
                                    required property string modelData
                                    radius: 4
                                    color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.1)
                                    border.width: 1
                                    border.color: root.borderAccent
                                    implicitWidth: gChipTxt.implicitWidth + 12
                                    implicitHeight: 20
                                    Text {
                                        id: gChipTxt
                                        anchors.centerIn: parent
                                        text: modelData
                                        font.family: Appearance.font.family.monospace
                                        font.pixelSize: 9
                                        color: root.accentColor
                                    }
                                }
                            }
                        }

                        // Plot / Description callout inside Hero (matching Media.html / Book.html)
                        Rectangle {
                            objectName: "nexusDossierSynopsisBox"
                            visible: String(root.dossier.plot ?? root.doc?.frontmatter?.plot ?? root.doc?.frontmatter?.description ?? "").length > 0
                            Layout.fillWidth: true
                            implicitHeight: plotTxt.implicitHeight + 16
                            radius: 6
                            color: root.cardRaisedBg
                            border.width: 1
                            border.color: root.borderSubtle

                            Rectangle {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                width: 3
                                radius: 2
                                color: root.accentColor
                            }

                            Text {
                                id: plotTxt
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 10
                                anchors.topMargin: 8
                                anchors.bottomMargin: 8
                                text: String(root.dossier.plot ?? root.doc?.frontmatter?.plot ?? root.doc?.frontmatter?.description ?? "")
                                font.family: root.serifFontFamily
                                font.pixelSize: 12
                                font.italic: true
                                color: root.textPrimary
                                wrapMode: Text.Wrap
                            }
                        }

                        // Domain-specific quick controls bar
                        Flow {
                            Layout.fillWidth: true
                            spacing: 6

                            Repeater {
                                model: {
                                    if (root.noteKind === "movie" || root.noteKind === "tvseries")
                                        return ["Queue", "Watching", "Finished", "Watched"];
                                    if (root.noteKind === "game")
                                        return ["Playing", "Completed", "Backlog", "Dropped"];
                                    if (root.noteKind === "book")
                                        return ["Reading", "Completed", "To Read", "Abandoned"];
                                    if (root.noteKind === "place")
                                        return ["Visited", "Bucket List", "Planned"];
                                    return [];
                                }
                                delegate: Rectangle {
                                    required property string modelData
                                    readonly property bool active: String(root.dossier.status ?? "").toLowerCase() === modelData.toLowerCase()
                                                                   || ((modelData === "Watched" || modelData === "Finished") && Boolean(root.dossier.watched))
                                                                   || (modelData === "Visited" && Boolean(root.dossier.visited))
                                    radius: 5
                                    color: active ? root.accentColor : (statusChipMouse.containsMouse ? root.cardHoverBg : root.cardRaisedBg)
                                    border.width: 1
                                    border.color: active ? root.accentColor : root.borderSubtle
                                    implicitWidth: statusChipLbl.implicitWidth + 14
                                    implicitHeight: 22

                                    Text {
                                        id: statusChipLbl
                                        anchors.centerIn: parent
                                        text: modelData
                                        font.pixelSize: 10
                                        font.weight: active ? Font.Bold : Font.Medium
                                        color: active ? root.onAccentColor : root.textSecondary
                                    }
                                    MouseArea {
                                        id: statusChipMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (!root.service)
                                                return;
                                            const patch = { "status": modelData };
                                            if (root.noteKind === "movie" || root.noteKind === "tvseries")
                                                patch["watched"] = (modelData === "Watched" || modelData === "Finished");
                                            if (root.noteKind === "place")
                                                patch["visited"] = (modelData === "Visited");
                                            root.service.updateNoteFrontmatter(patch);
                                        }
                                    }
                                }
                            }

                            // Favorite heart toggle
                            Rectangle {
                                visible: root.noteKind === "movie" || root.noteKind === "tvseries" || root.noteKind === "game" || root.noteKind === "place" || root.noteKind === "book"
                                radius: 5
                                color: Boolean(root.dossier.favorite) ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.22) : root.cardRaisedBg
                                border.width: 1
                                border.color: Boolean(root.dossier.favorite) ? root.accentColor : root.borderSubtle
                                implicitWidth: favRow.implicitWidth + 12
                                implicitHeight: 22

                                RowLayout {
                                    id: favRow
                                    anchors.centerIn: parent
                                    spacing: 4
                                    Text {
                                        text: Boolean(root.dossier.favorite) ? "♥ Favorite" : "♡ Favorite"
                                        font.pixelSize: 10
                                        font.weight: Font.DemiBold
                                        color: Boolean(root.dossier.favorite) ? root.accentColor : root.textSecondary
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (root.service)
                                            root.service.updateNoteFrontmatter({ "favorite": !Boolean(root.dossier.favorite) });
                                    }
                                }
                            }
                        }
                    }

                    // Right Hero Aside Card: Media STATISTICS (`Media.html`)
                    Rectangle {
                        objectName: "nexusMediaStatsCard"
                        Layout.fillWidth: dossierHeroGrid.columns === 1
                        Layout.minimumWidth: 0
                        visible: root.noteKind === "movie" || root.noteKind === "tvseries"
                        Layout.preferredWidth: 230
                        Layout.alignment: Qt.AlignTop
                        implicitHeight: mediaStatsAsideCol.implicitHeight + 24
                        radius: 8
                        color: root.cardSubtleBg
                        border.width: 1
                        border.color: root.borderSubtle

                        ColumnLayout {
                            id: mediaStatsAsideCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 12
                            spacing: 8

                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    text: "STATISTICS"
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: 9
                                    font.weight: Font.Bold
                                    font.letterSpacing: 1.4
                                    color: root.accentColor
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: root.noteKind === "tvseries" ? "Series" : "Movie"
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: 9
                                    color: root.textMuted
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                Text {
                                    text: String(root.dossier.score || root.dossier.onlineRating || root.dossier.rating || "—")
                                    font.family: root.serifFontFamily
                                    font.pixelSize: 28
                                    font.weight: Font.Bold
                                    color: root.accentColor
                                }
                                Text {
                                    text: "/10"
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: 11
                                    color: root.textMuted
                                    Layout.alignment: Qt.AlignBottom
                                    Layout.bottomMargin: 4
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: "Score"
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: 9
                                    color: root.textMuted
                                }
                            }

                            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: root.borderSubtle }

                            GridLayout {
                                Layout.fillWidth: true
                                columns: 2
                                columnSpacing: 8
                                rowSpacing: 6

                                Repeater {
                                    model: {
                                        const fm = root.doc?.frontmatter ?? ({});
                                        if (root.noteKind === "tvseries") {
                                            return [
                                                { label: "AIRED", val: String(root.dossier.year || fm.firstAired || fm.aired || "—") },
                                                { label: "SEASONS", val: String(root.dossier.seasons || fm.seasons || fm.totalSeasons || "—") },
                                                { label: "EPISODES", val: String(root.dossier.episodes || fm.episodes || fm.totalEpisodes || "—") },
                                                { label: "NETWORK", val: String(root.dossier.network || fm.network || fm.studio || root.dossier.status || "—").replace(/^\[\[|\]\]$/g, "") }
                                            ];
                                        }
                                        return [
                                            { label: "RELEASE", val: String(root.dossier.year || fm.released || fm.year || "—") },
                                            { label: "RUNTIME", val: String(root.dossier.runtime || fm.runtime || fm.length || "—") },
                                            { label: "DIRECTOR", val: String(root.dossier.director || fm.director || "—").replace(/^\[\[|\]\]$/g, "") },
                                            { label: "STATUS", val: String(root.dossier.status || (root.dossier.watched ? "Finished" : "Queue")) }
                                        ];
                                    }
                                    delegate: Rectangle {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        implicitHeight: 38
                                        radius: 5
                                        color: root.cardRaisedBg
                                        border.width: 1
                                        border.color: root.borderSubtle

                                        ColumnLayout {
                                            anchors.fill: parent
                                            anchors.margins: 5
                                            spacing: 1
                                            Text {
                                                text: modelData.label
                                                font.family: Appearance.font.family.monospace
                                                font.pixelSize: 8
                                                color: root.textMuted
                                            }
                                            Text {
                                                Layout.fillWidth: true
                                                text: modelData.val
                                                font.pixelSize: 10
                                                font.weight: Font.DemiBold
                                                color: root.textPrimary
                                                elide: Text.ElideRight
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Right Hero Aside Card: Book READING LOG (`Book.html`)
                    Rectangle {
                        objectName: "nexusBookReadingCard"
                        Layout.fillWidth: dossierHeroGrid.columns === 1
                        Layout.minimumWidth: 0
                        visible: root.noteKind === "book"
                        Layout.preferredWidth: 245
                        Layout.alignment: Qt.AlignTop
                        implicitHeight: bookReadingAsideCol.implicitHeight + 24
                        radius: 8
                        color: root.cardSubtleBg
                        border.width: 1
                        border.color: root.borderSubtle

                        ColumnLayout {
                            id: bookReadingAsideCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 12
                            spacing: 8

                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    text: "READING LOG"
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: 9
                                    font.weight: Font.Bold
                                    font.letterSpacing: 1.4
                                    color: root.accentColor
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: String(root.dossier.status || "Queued")
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: 9
                                    color: root.accentColor
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                readonly property int curP: Number(root.dossier.currentPage ?? 0)
                                readonly property int totP: Math.max(1, Number(root.dossier.pages ?? 1))
                                readonly property int pctVal: Number(root.dossier.pages ?? 0) > 0 ? Math.min(100, Math.round((curP / totP) * 100)) : 0
                                Text {
                                    text: parent.pctVal + "%"
                                    font.family: root.serifFontFamily
                                    font.pixelSize: 26
                                    font.weight: Font.Bold
                                    color: root.accentColor
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: parent.curP + " / " + Number(root.dossier.pages ?? 0) + " pages"
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: 10
                                    color: root.textSecondary
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 6
                                radius: 3
                                color: root.cardDeepBg
                                Rectangle {
                                    readonly property real pct: Math.max(0, Math.min(1, Number(root.dossier.currentPage ?? 0) / Math.max(1, Number(root.dossier.pages ?? 1))))
                                    width: parent.width * pct
                                    height: parent.height
                                    radius: 3
                                    color: root.accentColor
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                Rectangle {
                                    radius: 4
                                    color: root.cardRaisedBg
                                    border.width: 1
                                    border.color: root.borderSubtle
                                    implicitWidth: 42
                                    implicitHeight: 20
                                    Text { anchors.centerIn: parent; text: "-10p"; font.family: Appearance.font.family.monospace; font.pixelSize: 9; color: root.textSecondary }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (!root.service)
                                                return;
                                            const cur = Number(root.dossier.currentPage ?? 0);
                                            root.service.updateNoteFrontmatter({ "CurrentPage": Math.max(0, cur - 10) });
                                        }
                                    }
                                }
                                Rectangle {
                                    radius: 4
                                    color: root.cardRaisedBg
                                    border.width: 1
                                    border.color: root.borderSubtle
                                    implicitWidth: 42
                                    implicitHeight: 20
                                    Text { anchors.centerIn: parent; text: "+10p"; font.family: Appearance.font.family.monospace; font.pixelSize: 9; color: root.textPrimary }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (!root.service)
                                                return;
                                            const cur = Number(root.dossier.currentPage ?? 0);
                                            const tot = Number(root.dossier.pages ?? 9999);
                                            root.service.updateNoteFrontmatter({ "CurrentPage": Math.min(tot > 0 ? tot : 9999, cur + 10) });
                                        }
                                    }
                                }
                                Item { Layout.fillWidth: true }
                            }

                            GridLayout {
                                Layout.fillWidth: true
                                columns: 2
                                columnSpacing: 8
                                rowSpacing: 6

                                Repeater {
                                    model: {
                                        const fm = root.doc?.frontmatter ?? ({});
                                        return [
                                            { label: "STARTED", val: String(fm.startDate || fm["Date Started"] || fm.started || "—") },
                                            { label: "FINISHED", val: String(fm.finishDate || fm["Date Finished"] || fm.finished || "—") },
                                            { label: "RATING", val: String(root.dossier.rating || fm.Rating || fm.rating || "—") },
                                            { label: "ISBN", val: String(root.dossier.isbn || fm.ISBN || fm.isbn || "—") }
                                        ];
                                    }
                                    delegate: Rectangle {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        implicitHeight: 36
                                        radius: 5
                                        color: root.cardRaisedBg
                                        border.width: 1
                                        border.color: root.borderSubtle

                                        ColumnLayout {
                                            anchors.fill: parent
                                            anchors.margins: 5
                                            spacing: 1
                                            Text {
                                                text: modelData.label
                                                font.family: Appearance.font.family.monospace
                                                font.pixelSize: 8
                                                color: root.textMuted
                                            }
                                            Text {
                                                Layout.fillWidth: true
                                                text: modelData.val
                                                font.pixelSize: 10
                                                font.weight: Font.DemiBold
                                                color: root.textPrimary
                                                elide: Text.ElideRight
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

        // =====================================================================
        // 1B. FULL 2-COLUMN BODY FOR DOSSIER CUSTOM VIEWS
        //     (Place, Movie, TVSeries, Book, Clipping, Website, Contact, etc.)
        // =====================================================================
        GridLayout {
            id: dossierBodyGrid
            columns: width >= 620 ? 2 : 1
            columnSpacing: 14
            rowSpacing: 14
            Layout.minimumWidth: 0
            visible: root.isDossierBannerNote && root.noteKind !== "settings" && root.noteKind !== "exercise" && root.noteKind !== "game"
            Layout.fillWidth: true

            // Left Column: Editorial / Ruled-Paper Notes & Media Tabs (`Journal`, `Videos`, `Cast`)
            Rectangle {
                id: dossierLeftCard
                objectName: "nexusDossierLeftCard"
                readonly property int minNoteCardHeight: Math.max(200, Math.min(340, root.minDocumentSurfaceHeight - dossierBannerCard.implicitHeight - 24))
                Layout.fillWidth: true
                Layout.preferredWidth: 620
                Layout.minimumWidth: 0
                Layout.alignment: Qt.AlignTop
                implicitHeight: Math.max(minNoteCardHeight, dossierLeftCol.implicitHeight + 36)
                radius: 9
                color: root.cardSubtleBg
                border.width: 1
                border.color: root.borderSubtle
                clip: true

                // Subtle notebook lines for Place / Book / Media review notes
                Canvas {
                    anchors.fill: parent
                    opacity: 0.25
                    readonly property color _ruleColor: root.borderSubtle
                    on_RuleColorChanged: if (visible) requestPaint()
                    onWidthChanged: if (visible) requestPaint()
                    onHeightChanged: if (visible) requestPaint()
                    onVisibleChanged: if (visible) requestPaint()
                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.reset();
                        ctx.strokeStyle = root.borderSubtle;
                        ctx.lineWidth = 1;
                        for (let y = 52; y < height - 12; y += 26) {
                            ctx.beginPath();
                            ctx.moveTo(14, y);
                            ctx.lineTo(width - 14, y);
                            ctx.stroke();
                        }
                    }
                }

                ColumnLayout {
                    id: dossierLeftCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 16
                    spacing: 10

                    // Media Tabs (`Journal` / `Videos` / `Cast` from `Media.html`)
                    RowLayout {
                        visible: root.noteKind === "movie" || root.noteKind === "tvseries"
                        Layout.fillWidth: true
                        spacing: 6

                        Repeater {
                            model: [
                                { id: "journal", label: "Journal" },
                                { id: "videos", label: "Videos" },
                                { id: "cast", label: "Cast" }
                            ]
                            delegate: Rectangle {
                                required property var modelData
                                objectName: "nexusMediaTab_" + modelData.id
                                readonly property bool active: root.mediaActiveTab === modelData.id
                                radius: 5
                                color: active ? root.accentColor : (mTabMouse.containsMouse ? root.cardHoverBg : root.cardRaisedBg)
                                border.width: 1
                                border.color: active ? root.accentColor : root.borderSubtle
                                implicitWidth: mTabLbl.implicitWidth + 18
                                implicitHeight: 24

                                Text {
                                    id: mTabLbl
                                    anchors.centerIn: parent
                                    text: modelData.label
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: 10
                                    font.weight: active ? Font.Bold : Font.Medium
                                    color: active ? root.onAccentColor : root.textSecondary
                                }
                                MouseArea {
                                    id: mTabMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.mediaActiveTab = modelData.id
                                }
                            }
                        }

                        Item { Layout.fillWidth: true }
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        columns: width >= 440 ? 3 : 1
                        columnSpacing: 6
                        rowSpacing: 6
                        Text {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            wrapMode: Text.Wrap
                            text: root.noteKind === "place" ? "TRAVEL LOG & IMPRESSIONS"
                                : root.noteKind === "book" ? "READING NOTES"
                                : root.noteKind === "clipping" ? "ARTICLE READER & ANNOTATIONS"
                                : ((root.noteKind === "movie" || root.noteKind === "tvseries") && root.mediaActiveTab === "videos") ? "TRAILERS & VIDEOS"
                                : ((root.noteKind === "movie" || root.noteKind === "tvseries") && root.mediaActiveTab === "cast") ? "CAST & CREW"
                                : "VIEWING NOTES"
                            font.pixelSize: 10
                            font.weight: Font.Bold
                            font.letterSpacing: 1.4
                            color: root.accentColor
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            visible: !(root.noteKind === "movie" || root.noteKind === "tvseries") || root.mediaActiveTab === "journal"
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            wrapMode: Text.Wrap
                            text: root.editingNoteBody ? "Editing · Esc to finish" : "Click to edit notes"
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: 10
                            color: (dossierEditHintMouse.containsMouse || root.editingNoteBody) ? root.accentColor : root.textMuted
                            MouseArea {
                                id: dossierEditHintMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (root.editingNoteBody) {
                                        if (root.service)
                                            root.service.saveNoteBodyMarkdown(dossierBodyEditor.text);
                                        root.editingNoteBody = false;
                                        root.restoreWorkspaceFocus();
                                    } else {
                                        dossierBodyEditor.text = root.service ? root.service.getNoteBodyMarkdown() : "";
                                        root.editingNoteBody = true;
                                    }
                                }
                            }
                        }
                    }

                    OrnamentalDivider {}

                    // Media Videos Tab (`Media.html`)
                    ColumnLayout {
                        visible: (root.noteKind === "movie" || root.noteKind === "tvseries") && root.mediaActiveTab === "videos"
                        Layout.fillWidth: true
                        spacing: 8

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 96
                            radius: 7
                            color: root.cardRaisedBg
                            border.width: 1
                            border.color: root.borderSubtle

                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: 4
                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: String(root.doc?.frontmatter?.trailer || root.doc?.frontmatter?.videoUrl || "").length > 0
                                        ? ("Trailer: " + String(root.doc?.frontmatter?.trailer || root.doc?.frontmatter?.videoUrl))
                                        : "No trailer URL linked in frontmatter (`trailer:`)"
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: 11
                                    color: root.textSecondary
                                }
                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: "Use Sync TMDB/OMDb in the header to populate media trailers & metadata."
                                    font.pixelSize: 11
                                    font.italic: true
                                    color: root.textMuted
                                }
                            }
                        }
                    }

                    // Media Cast Tab (`Media.html`)
                    Flow {
                        visible: (root.noteKind === "movie" || root.noteKind === "tvseries") && root.mediaActiveTab === "cast"
                        Layout.fillWidth: true
                        spacing: 8

                        Repeater {
                            model: root.mediaCastList
                            delegate: Rectangle {
                                required property string modelData
                                radius: 6
                                color: root.cardRaisedBg
                                border.width: 1
                                border.color: root.borderSubtle
                                implicitWidth: castChipRow.implicitWidth + 18
                                implicitHeight: 32

                                RowLayout {
                                    id: castChipRow
                                    anchors.centerIn: parent
                                    spacing: 6
                                    MaterialSymbol { text: "person"; iconSize: 14; color: root.accentColor }
                                    Text {
                                        text: modelData
                                        font.pixelSize: 11
                                        font.weight: Font.Medium
                                        color: root.textPrimary
                                    }
                                }
                            }
                        }

                        Text {
                            visible: root.mediaCastList.length === 0
                            text: "No cast members listed in frontmatter (`actors:` / `cast:`)."
                            font.pixelSize: 12
                            font.italic: true
                            color: root.textMuted
                        }
                    }

                    // Reading Mode (Default): Render document body markdown with rich HTML
                    Item {
                        id: dossierBodyReadingArea
                        objectName: "nexusDossierBodyReadingArea"
                        visible: !root.editingNoteBody && (!(root.noteKind === "movie" || root.noteKind === "tvseries") || root.mediaActiveTab === "journal")
                        Layout.fillWidth: true
                        implicitHeight: Math.max(160, dossierLeftCard.minNoteCardHeight - 96, dossierReadingBlocksCol.implicitHeight + 12)

                        ColumnLayout {
                            id: dossierReadingBlocksCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            spacing: 6

                            Text {
                                id: dossierRichMarkdownText
                                objectName: "nexusDossierRichMarkdownText"
                                visible: root.cleanNoteBodyMarkdown.length > 0
                                Layout.fillWidth: true
                                text: root.renderMarkdownBlocksHtml(root.cleanNoteBodyMarkdown)
                                textFormat: Text.RichText
                                font.family: root.serifFontFamily
                                font.pixelSize: 13
                                color: root.textPrimary
                                wrapMode: Text.Wrap
                                onLinkActivated: link => {
                                    if (root.service && link.startsWith("wikilink:"))
                                        root.service.followWikilink(decodeURIComponent(link.substring(9)));
                                }
                            }

                            Text {
                                objectName: "nexusDossierBodyEmptyHint"
                                visible: root.cleanNoteBodyMarkdown.length === 0
                                Layout.fillWidth: true
                                Layout.topMargin: 8
                                text: root.noteKind === "book"
                                    ? "Click here to capture thesis, arguments, memorable quotes, and takeaways..."
                                    : "Click here to write your personal review & notes..."
                                font.pixelSize: 12
                                font.italic: true
                                color: root.textMuted
                                wrapMode: Text.Wrap
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            z: -1
                            cursorShape: Qt.IBeamCursor
                            onClicked: {
                                dossierBodyEditor.text = root.service ? root.service.getNoteBodyMarkdown() : "";
                                root.editingNoteBody = true;
                            }
                        }
                    }

                    // Editing Mode (Activated on Click)
                    ColumnLayout {
                        visible: root.editingNoteBody && root.isDossierBannerNote && root.noteKind !== "settings" && root.noteKind !== "exercise" && root.noteKind !== "game"
                        Layout.fillWidth: true
                        spacing: 8

                        TextArea {
                            id: dossierBodyEditor
                            objectName: "nexusDossierBodyEditor"
                            Layout.fillWidth: true
                            Layout.minimumHeight: Math.max(220, dossierLeftCard.minNoteCardHeight - 136)
                            text: root.service ? root.service.getNoteBodyMarkdown() : ""
                            placeholderText: "Write your personal review & notes here..."
                            placeholderTextColor: root.textMuted
                            color: root.textPrimary
                            font.family: Appearance.font.family.main
                            font.pixelSize: 13
                            wrapMode: TextEdit.Wrap
                            background: Item {}
                            onVisibleChanged: {
                                if (visible)
                                    Qt.callLater(() => { if (dossierBodyEditor.visible) dossierBodyEditor.forceActiveFocus(); });
                            }
                            onActiveFocusChanged: {
                                if (!activeFocus && visible && root.editingNoteBody && root.isDossierBannerNote && root.noteKind !== "settings" && root.noteKind !== "exercise" && root.noteKind !== "game" && !dossierCancelBtnMouse.containsMouse && !dossierCancelBtnMouse.pressed) {
                                    if (root.service)
                                        root.service.saveNoteBodyMarkdown(dossierBodyEditor.text);
                                    root.editingNoteBody = false;
                                }
                            }
                            Keys.onEscapePressed: event => {
                                if (root.service)
                                    root.service.saveNoteBodyMarkdown(dossierBodyEditor.text);
                                root.editingNoteBody = false;
                                root.restoreWorkspaceFocus();
                                event.accepted = true;
                            }
                            Keys.onPressed: event => {
                                if (root.forwardWorkspaceShortcut(event))
                                    return;
                                if ((event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_S)) {
                                    if (root.service)
                                        root.service.saveNoteBodyMarkdown(dossierBodyEditor.text);
                                    root.editingNoteBody = false;
                                    root.restoreWorkspaceFocus();
                                    event.accepted = true;
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Item { Layout.fillWidth: true }
                            Rectangle {
                                radius: 5
                                color: root.cardRaisedBg
                                border.width: 1
                                border.color: root.borderSubtle
                                implicitWidth: dossierCancelBtnTxt.implicitWidth + 16
                                implicitHeight: 24
                                Text {
                                    id: dossierCancelBtnTxt
                                    anchors.centerIn: parent
                                    text: "Cancel"
                                    font.pixelSize: 10
                                    color: root.textSecondary
                                }
                                MouseArea {
                                    id: dossierCancelBtnMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.editingNoteBody = false;
                                        root.restoreWorkspaceFocus();
                                    }
                                }
                            }
                            Rectangle {
                                objectName: "nexusDossierBodySaveButton"
                                radius: 5
                                color: root.accentColor
                                implicitWidth: dossierSaveBtnTxt.implicitWidth + 16
                                implicitHeight: 24
                                Text {
                                    id: dossierSaveBtnTxt
                                    anchors.centerIn: parent
                                    text: "Save Notes"
                                    font.pixelSize: 10
                                    font.weight: Font.Bold
                                    color: root.onAccentColor
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (root.service)
                                            root.service.saveNoteBodyMarkdown(dossierBodyEditor.text);
                                        root.editingNoteBody = false;
                                        root.restoreWorkspaceFocus();
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Right Column: YOUR LOG (`Media.html`), EDITION DETAILS + NOTEBOOK MAP (`Book.html`), Coordinates (`Places`)
            Rectangle {
                id: dossierRightCard
                objectName: "nexusDossierRightCard"
                Layout.preferredWidth: 285
                Layout.fillWidth: dossierBodyGrid.columns === 1
                Layout.minimumWidth: 0
                Layout.maximumWidth: dossierBodyGrid.columns === 1 ? Infinity : 325
                Layout.alignment: Qt.AlignTop
                implicitHeight: dossierRightCol.implicitHeight + 28
                radius: 9
                color: root.cardBg
                border.width: 1
                border.color: root.borderSubtle

                ColumnLayout {
                    id: dossierRightCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 14
                    spacing: 10

                    // Media YOUR LOG panel (`Media.html`: Status + 1..10 Star Rating)
                    ColumnLayout {
                        visible: root.noteKind === "movie" || root.noteKind === "tvseries"
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: "YOUR LOG"
                            font.pixelSize: 10
                            font.weight: Font.Bold
                            font.letterSpacing: 1.4
                            color: root.accentColor
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "Rating"
                                font.family: Appearance.font.family.monospace
                                font.pixelSize: 9
                                color: root.textMuted
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: String(root.dossier.rating ?? "").length > 0 ? (String(root.dossier.rating) + " / 10") : "Unrated"
                                font.family: Appearance.font.family.monospace
                                font.pixelSize: 10
                                color: root.accentColor
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Repeater {
                                model: 10
                                delegate: Rectangle {
                                    required property int index
                                    readonly property int starVal: index + 1
                                    readonly property bool filled: Number(root.dossier.rating ?? 0) >= starVal
                                    Layout.fillWidth: true
                                    implicitHeight: 22
                                    radius: 3
                                    color: starMouse.containsMouse ? root.cardHoverBg : "transparent"

                                    Text {
                                        anchors.centerIn: parent
                                        text: filled ? "★" : "☆"
                                        font.pixelSize: 13
                                        color: filled ? root.accentColor : root.textMuted
                                    }
                                    MouseArea {
                                        id: starMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (root.service)
                                                root.service.updateNoteFrontmatter({ "rating": starVal, "personalRating": starVal });
                                        }
                                    }
                                }
                            }
                        }

                        OrnamentalDivider {}
                    }

                    Text {
                        text: root.noteKind === "place" ? "LOCATION & COORDINATES"
                            : root.noteKind === "book" ? "EDITION DETAILS"
                            : (root.noteKind === "movie" || root.noteKind === "tvseries") ? "CREDITS & DETAILS"
                            : "DOSSIER SPECIFICATIONS"
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        font.letterSpacing: 1.4
                        color: root.accentColor
                    }

                    OrnamentalDivider {}

                    // Place mini-map coordinate visualizer
                    Rectangle {
                        visible: root.noteKind === "place"
                        Layout.fillWidth: true
                        implicitHeight: 110
                        radius: 6
                        color: root.cardDeepBg
                        border.width: 1
                        border.color: root.borderAccent
                        clip: true

                        Canvas {
                            anchors.fill: parent
                            readonly property string _themeSig: root.themeSignature
                            on_ThemeSigChanged: if (visible) requestPaint()
                            onVisibleChanged: if (visible) requestPaint()
                            onPaint: {
                                const ctx = getContext("2d");
                                ctx.reset();
                                ctx.strokeStyle = Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.14);
                                ctx.lineWidth = 1;
                                for (let x = 20; x < width; x += 28) {
                                    ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, height); ctx.stroke();
                                }
                                for (let y = 18; y < height; y += 24) {
                                    ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(width, y); ctx.stroke();
                                }
                                const cx = width * 0.52;
                                const cy = height * 0.48;
                                ctx.fillStyle = Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.22);
                                ctx.beginPath(); ctx.arc(cx, cy, 16, 0, Math.PI * 2); ctx.fill();
                                ctx.fillStyle = root.accentColor;
                                ctx.beginPath(); ctx.arc(cx, cy, 5, 0, Math.PI * 2); ctx.fill();
                            }
                        }

                        ColumnLayout {
                            anchors.left: parent.left
                            anchors.bottom: parent.bottom
                            anchors.margins: 8
                            spacing: 2
                            Text {
                                text: String(root.dossier.location || root.doc?.frontmatter?.country || "Coordinates")
                                font.pixelSize: 11
                                font.weight: Font.Bold
                                color: root.textPrimary
                            }
                            Text {
                                text: String(root.dossier.latitude ?? "") + (String(root.dossier.longitude ?? "").length > 0 ? ", " + String(root.dossier.longitude ?? "") : "")
                                font.pixelSize: 9
                                font.family: Appearance.font.family.monospace
                                color: root.accentColor
                            }
                        }
                    }

                    // Key-value metadata rows
                    Repeater {
                        model: {
                            const rows = [];
                            const fm = root.doc?.frontmatter ?? ({});
                            const addRow = (lbl, val) => {
                                const clean = String(val ?? "").replace(/^\[\[|\]\]$/g, "").trim();
                                if (clean.length > 0)
                                    rows.push({ "label": lbl, "value": clean });
                            };
                            addRow("Category", root.dossier.category || fm.category || fm.categories);
                            addRow("Full Name", root.dossier.fullName || fm["full name"]);
                            addRow("Company", root.dossier.company || fm.company);
                            addRow("Phone", root.dossier.phone || fm.phone);
                            addRow("Email", root.dossier.email || fm.email);
                            addRow("Birthday", root.dossier.birthday || fm.birthday);
                            addRow("Course", root.dossier.course || fm.course);
                            addRow("Session", root.dossier.session || fm.session);
                            addRow("Topic", root.dossier.topic || fm.topic);
                            addRow("Schedule", root.dossier.time || fm.time);
                            addRow("Unit", root.dossier.unit || fm.unit);
                            addRow("Source", root.dossier.source || fm.source);
                            addRow("Genre", root.dossier.genre || fm.genre);
                            addRow("Director", root.dossier.director || fm.director);
                            addRow("Writer", fm.writer || fm.writers);
                            addRow("Cast", root.dossier.actors || fm.actors || fm.cast);
                            addRow("Studio", root.dossier.studio || fm.studio || fm.production);
                            addRow("Author", root.dossier.author || fm.author || fm.Author);
                            addRow("Publisher", root.dossier.publisher || fm.Publisher || fm.publisher);
                            addRow("ISBN", root.dossier.isbn || fm.ISBN || fm.isbn);
                            addRow("Language", fm.language || fm.Language);
                            addRow("Developer", root.dossier.developer || fm.developer);
                            addRow("Platform", root.dossier.platform || fm.platforms);
                            addRow("Location", root.dossier.location || fm.city || fm.country);
                            addRow("Runtime", fm.runtime || fm.length);
                            addRow("Released", root.dossier.year || fm.year || fm.released || fm.publishDate);
                            addRow("URL", root.dossier.url || fm.url || fm.url_onion);
                            return rows;
                        }
                        delegate: ColumnLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 2
                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    text: modelData.label.toUpperCase()
                                    font.pixelSize: 9
                                    font.weight: Font.Bold
                                    color: root.textMuted
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    Layout.maximumWidth: 175
                                    text: modelData.value
                                    font.pixelSize: 11
                                    color: root.textPrimary
                                    elide: Text.ElideRight
                                    horizontalAlignment: Text.AlignRight
                                }
                            }
                            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: root.borderSubtle }
                        }
                    }

                    // Book NOTEBOOK MAP (`Book.html`: 01..05 prompts)
                    ColumnLayout {
                        objectName: "nexusBookNotebookMap"
                        visible: root.noteKind === "book"
                        Layout.fillWidth: true
                        Layout.topMargin: 6
                        spacing: 6

                        Text {
                            text: "NOTEBOOK MAP · WHAT TO CAPTURE"
                            font.pixelSize: 9
                            font.weight: Font.Bold
                            font.letterSpacing: 1.2
                            color: root.accentColor
                        }

                        OrnamentalDivider {}

                        Repeater {
                            model: [
                                { num: "01", text: "Core thesis in your own words" },
                                { num: "02", text: "Key arguments & mental models" },
                                { num: "03", text: "Memorable quotes with page numbers" },
                                { num: "04", text: "Questions, critiques, counterexamples" },
                                { num: "05", text: "Actionable takeaways or links to notes" }
                            ]
                            delegate: RowLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: 8
                                Text {
                                    text: modelData.num
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: 10
                                    font.weight: Font.Bold
                                    color: root.accentColor
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.text
                                    font.pixelSize: 11
                                    color: root.textSecondary
                                    wrapMode: Text.Wrap
                                }
                            }
                        }
                    }
                }
            }
        }

        // =====================================================================
        // 1C. EXERCISE CUSTOM VIEW (`90_System/93_Configuration/Custom_Views/Exercise/Exercise.{html,css,js}` + `muscle-map.svg`)
        // =====================================================================
        ColumnLayout {
            id: exerciseCustomView
            objectName: "nexusExerciseCustomView"
            Layout.minimumWidth: 0
            visible: root.noteKind === "exercise"
            Layout.fillWidth: true
            spacing: 14

            readonly property string previewUrlStr: String(root.eView.previewUrl || root.dossier.posterUrl || "")
            readonly property string animUrlStr: String(root.eView.animationUrl || root.dossier.featuredImageUrl || "")
            readonly property bool hasAnimation: animUrlStr.length > 0
            readonly property string activeLevel: root.exerciseActiveLevel
            readonly property color activeLevelCol: root.exerciseLevelColor(activeLevel)
            readonly property string primaryText: root.exerciseListText(
                (root.eView.primaryMuscles && root.eView.primaryMuscles.length > 0) ? root.eView.primaryMuscles : root.dossier.muscleGroup,
                "—"
            )
            readonly property string secondaryText: root.exerciseListText(
                (root.eView.secondaryMuscles && root.eView.secondaryMuscles.length > 0) ? root.eView.secondaryMuscles : root.dossier.secondaryMuscles,
                "No secondary target"
            )
            readonly property string equipmentRawStr: String(root.eView.equipment || root.dossier.equipment || "body only")
            readonly property string equipmentDisplayStr: root.exerciseDisplayText(equipmentRawStr, "Body only")
            readonly property string categoryDisplayStr: root.exerciseDisplayText(root.eView.category || root.dossier.category, "Exercise")
            readonly property string forceDisplayStr: root.exerciseDisplayText(root.eView.force || root.dossier.force, "Neutral")
            readonly property string mechanicDisplayStr: root.exerciseDisplayText(root.eView.mechanic || root.dossier.mechanic, "Unspecified")
            readonly property string exerciseIdStr: String(root.eView.id || root.doc?.title || "—")
            readonly property var livePreviewSteps: {
                if (root.editingNoteBody && root.noteKind === "exercise") {
                    const parsed = root.parseLiveExerciseSteps(exBodyEditor.text);
                    if (parsed.length > 0)
                        return parsed;
                }
                return root.eView.steps ?? [];
            }
            readonly property var livePreviewTips: {
                if (root.editingNoteBody && root.noteKind === "exercise")
                    return root.parseLiveExerciseTips(exBodyEditor.text);
                return root.eView.tips ?? [];
            }
            readonly property int minLowerRowHeight: Math.max(448, root.minDocumentSurfaceHeight - exHeroItem.implicitHeight - 14)

            // ── TOP SECTION: `.cv-exercise-hero` (Compact 2-Column Media Frame + Movement Library Summary) ──
            Item {
                id: exHeroItem
                Layout.fillWidth: true
                implicitHeight: exHeroGrid.implicitHeight + 8

                GridLayout {
                    id: exHeroGrid
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    columns: width >= 720 ? 2 : 1
                    columnSpacing: 22
                    rowSpacing: 12

                    // Left Column: `.cv-exercise-media` (Compact Demo Frame with Level Pill, Play Demo Button & Static First Frame Caption)
                    Rectangle {
                        id: exMediaFrame
                        objectName: "nexusExerciseMediaFrame"
                        Layout.fillWidth: true
                        Layout.preferredWidth: 292
                        Layout.minimumWidth: 220
                        Layout.maximumWidth: 292
                        Layout.preferredHeight: Math.round(Math.max(142, Math.min(160, width * 0.52)))
                        Layout.alignment: Qt.AlignVCenter
                        radius: 12
                        color: root.cardDeepBg
                        border.width: 1
                        border.color: root.borderSubtle
                        clip: true

                        // Static Preview Image (`cv-exercise-preview`)
                        Image {
                            id: exPreviewImg
                            objectName: "nexusExercisePreviewImage"
                            anchors.fill: parent
                            source: exerciseCustomView.previewUrlStr.length > 0
                                ? exerciseCustomView.previewUrlStr
                                : exerciseCustomView.animUrlStr
                            sourceSize: Qt.size(480, 360)
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: false
                            visible: String(source).length > 0
                        }

                        // Animated Technique Demonstration (`cv-exercise-animation`)
                        AnimatedImage {
                            id: exAnimImg
                            objectName: "nexusExerciseAnimatedImage"
                            anchors.fill: parent
                            visible: root.exerciseShowAnimation && exerciseCustomView.hasAnimation
                            source: visible ? exerciseCustomView.animUrlStr : ""
                            fillMode: Image.PreserveAspectCrop
                            playing: visible && status === AnimatedImage.Ready && (root.workspace?.transitionSettled ?? true) && !Boolean(HostServices.GlobalStates?.regionSelectorOpen)
                            asynchronous: true
                            cache: false
                        }

                        // Fallback icon when no media exists
                        MaterialSymbol {
                            anchors.centerIn: parent
                            visible: !exPreviewImg.visible && !exAnimImg.visible
                            text: "fitness_center"
                            iconSize: 42
                            color: root.textMuted
                        }

                        // Top & Bottom Shade Overlays (`cv-exercise-media-shade`)
                        Rectangle {
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            height: Math.round(parent.height * 0.34)
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.56) }
                                GradientStop { position: 1.0; color: "transparent" }
                            }
                        }
                        Rectangle {
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            anchors.right: parent.right
                            height: Math.round(parent.height * 0.34)
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: "transparent" }
                                GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.72) }
                            }
                        }

                        // Top Bar (`cv-exercise-media-top`): Level Pill (Left) + Play Demo Pill Button (Right)
                        RowLayout {
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.topMargin: 10
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 8

                            // `.cv-exercise-level`
                            Rectangle {
                                id: exLevelPill
                                objectName: "nexusExerciseLevelBadge"
                                height: 26
                                implicitWidth: exLevelPillRow.implicitWidth + 16
                                radius: 13
                                color: Qt.rgba(0.03, 0.05, 0.06, 0.80)
                                border.width: 1
                                border.color: Qt.rgba(
                                    exerciseCustomView.activeLevelCol.r,
                                    exerciseCustomView.activeLevelCol.g,
                                    exerciseCustomView.activeLevelCol.b,
                                    0.62
                                )

                                RowLayout {
                                    id: exLevelPillRow
                                    anchors.centerIn: parent
                                    spacing: 6

                                    Rectangle {
                                        width: 6
                                        height: 6
                                        radius: 3
                                        color: exerciseCustomView.activeLevelCol
                                    }

                                    Text {
                                        text: root.exerciseLevelLabel(exerciseCustomView.activeLevel)
                                        font.family: Appearance.font.family.monospace
                                        font.pixelSize: 10
                                        font.weight: Font.Bold
                                        font.letterSpacing: 0.4
                                        color: exerciseCustomView.activeLevelCol
                                    }
                                }
                            }

                            Item { Layout.fillWidth: true }

                            // `.cv-exercise-play` (`Play demo` / `Pause demo`)
                            Rectangle {
                                id: exPlayDemoBtn
                                objectName: "nexusExercisePlayDemoButton"
                                height: 26
                                implicitWidth: exPlayRow.implicitWidth + 16
                                radius: 13
                                color: (exPlayMouse.containsMouse || root.exerciseShowAnimation)
                                    ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.22)
                                    : Qt.rgba(0.03, 0.05, 0.06, 0.80)
                                border.width: 1
                                border.color: (exPlayMouse.containsMouse || root.exerciseShowAnimation)
                                    ? root.accentColor
                                    : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.62)
                                opacity: exerciseCustomView.hasAnimation ? 1.0 : 0.55

                                RowLayout {
                                    id: exPlayRow
                                    anchors.centerIn: parent
                                    spacing: 6

                                    // Circular Play/Pause Icon (`cv-exercise-play-icon`)
                                    Rectangle {
                                        width: 18
                                        height: 18
                                        radius: 9
                                        color: "transparent"
                                        border.width: 1
                                        border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.62)

                                        Canvas {
                                            id: exPlayIconCanvas
                                            anchors.fill: parent
                                            readonly property bool isPlaying: root.exerciseShowAnimation
                                            readonly property color iconColor: (exPlayMouse.containsMouse || root.exerciseShowAnimation)
                                                ? root.textStrong
                                                : root.accentColor
                                            onIsPlayingChanged: if (visible) requestPaint()
                                            onIconColorChanged: if (visible) requestPaint()
                                            onVisibleChanged: if (visible) requestPaint()
                                            onPaint: {
                                                const ctx = getContext("2d");
                                                ctx.clearRect(0, 0, width, height);
                                                ctx.fillStyle = String(iconColor);
                                                if (isPlaying) {
                                                    ctx.fillRect(5.8, 5, 2.2, 8);
                                                    ctx.fillRect(10.0, 5, 2.2, 8);
                                                } else {
                                                    ctx.beginPath();
                                                    ctx.moveTo(7, 5);
                                                    ctx.lineTo(13, 9);
                                                    ctx.lineTo(7, 13);
                                                    ctx.closePath();
                                                    ctx.fill();
                                                }
                                            }
                                        }
                                    }

                                    Text {
                                        id: exPlayLabel
                                        objectName: "nexusExercisePlayDemoLabel"
                                        text: !exerciseCustomView.hasAnimation
                                            ? "No demo"
                                            : (root.exerciseShowAnimation ? "Pause demo" : "Play demo")
                                        font.family: Appearance.font.family.monospace
                                        font.pixelSize: 10
                                        font.weight: Font.Bold
                                        font.letterSpacing: 0.4
                                        color: (exPlayMouse.containsMouse || root.exerciseShowAnimation)
                                            ? root.textStrong
                                            : root.accentColor
                                    }
                                }

                                MouseArea {
                                    id: exPlayMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    enabled: exerciseCustomView.hasAnimation
                                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: root.exerciseShowAnimation = !root.exerciseShowAnimation
                                }
                            }
                        }

                        // Bottom-Left Watermark Caption (`cv-exercise-media-caption`)
                        Text {
                            id: exMediaCaption
                            objectName: "nexusExerciseMediaStateCaption"
                            anchors.left: parent.left
                            anchors.bottom: parent.bottom
                            anchors.leftMargin: 12
                            anchors.bottomMargin: 9
                            text: root.exerciseShowAnimation ? "ANIMATED TECHNIQUE DEMONSTRATION" : "STATIC FIRST FRAME"
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: 9
                            font.letterSpacing: 0.8
                            color: Qt.rgba(root.textStrong.r, root.textStrong.g, root.textStrong.b, 0.82)
                        }
                    }

                    // Right Column: `.cv-exercise-summary` (Movement Library Eyebrow, Title, Subtitle, Fact Pills, Compact Bento Target Grid)
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 460
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 6

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            Text {
                                objectName: "nexusExerciseEyebrow"
                                text: "MOVEMENT LIBRARY"
                                font.family: Appearance.font.family.monospace
                                font.pixelSize: 10
                                font.weight: Font.Bold
                                font.letterSpacing: 1.6
                                color: root.accentColor
                            }

                            Item { Layout.fillWidth: true }

                            // Classification Pill Chips (`cv-exercise-facts`: `[Strength] [Pull] [Isolation]`)
                            RowLayout {
                                spacing: 6

                                Repeater {
                                    model: [
                                        exerciseCustomView.categoryDisplayStr,
                                        exerciseCustomView.forceDisplayStr,
                                        exerciseCustomView.mechanicDisplayStr
                                    ]
                                    delegate: Rectangle {
                                        required property string modelData
                                        height: 22
                                        width: exFactChipTxt.implicitWidth + 16
                                        radius: 11
                                        color: root.journalSubSurfaceBg
                                        border.width: 1
                                        border.color: root.borderSubtle

                                        Text {
                                            id: exFactChipTxt
                                            anchors.centerIn: parent
                                            text: modelData
                                            font.family: Appearance.font.family.monospace
                                            font.pixelSize: 10
                                            color: root.textSecondary
                                        }
                                    }
                                }
                            }
                        }

                        Text {
                            id: exTitleLabel
                            objectName: "nexusExerciseTitleLabel"
                            Layout.fillWidth: true
                            text: String(root.eView.name || root.doc?.title || root.dossier.title || "Exercise")
                            font.pixelSize: 25
                            font.weight: Font.Black
                            font.letterSpacing: -0.7
                            lineHeight: 1.08
                            color: root.textStrong
                            wrapMode: Text.Wrap
                        }

                        Text {
                            Layout.fillWidth: true
                            text: "Technique, target muscles and equipment in one focused training sheet."
                            font.pixelSize: 11
                            color: root.textSecondary
                            wrapMode: Text.Wrap
                        }

                        // `.cv-exercise-target-grid` (Compact 3-Card Row: PRIMARY MUSCLE | SECONDARY MUSCLES | EQUIPMENT)
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: 2
                            spacing: 8

                            // Card 1: PRIMARY MUSCLE
                            Rectangle {
                                objectName: "nexusExercisePrimaryMuscleCard"
                                Layout.fillWidth: true
                                Layout.preferredWidth: 150
                                implicitHeight: 52
                                radius: 9
                                color: root.journalSubSurfaceBg
                                border.width: 1
                                border.color: root.borderSubtle

                                ColumnLayout {
                                    anchors.centerIn: parent
                                    width: parent.width - 14
                                    spacing: 3

                                    Text {
                                        Layout.fillWidth: true
                                        horizontalAlignment: Text.AlignHCenter
                                        text: "PRIMARY MUSCLE"
                                        font.family: Appearance.font.family.monospace
                                        font.pixelSize: 9
                                        font.weight: Font.Bold
                                        font.letterSpacing: 1.2
                                        color: root.accentColor
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        horizontalAlignment: Text.AlignHCenter
                                        text: exerciseCustomView.primaryText
                                        font.pixelSize: 12
                                        font.weight: Font.Bold
                                        color: root.textStrong
                                        elide: Text.ElideRight
                                    }
                                }
                            }

                            // Card 2: SECONDARY MUSCLES
                            Rectangle {
                                objectName: "nexusExerciseSecondaryMuscleCard"
                                Layout.fillWidth: true
                                Layout.preferredWidth: 150
                                implicitHeight: 52
                                radius: 9
                                color: root.journalSubSurfaceBg
                                border.width: 1
                                border.color: root.borderSubtle

                                ColumnLayout {
                                    anchors.centerIn: parent
                                    width: parent.width - 14
                                    spacing: 3

                                    Text {
                                        Layout.fillWidth: true
                                        horizontalAlignment: Text.AlignHCenter
                                        text: "SECONDARY MUSCLES"
                                        font.family: Appearance.font.family.monospace
                                        font.pixelSize: 9
                                        font.weight: Font.Bold
                                        font.letterSpacing: 1.2
                                        color: root.accentColor
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        horizontalAlignment: Text.AlignHCenter
                                        text: exerciseCustomView.secondaryText
                                        font.pixelSize: 12
                                        font.weight: Font.Bold
                                        color: root.textStrong
                                        elide: Text.ElideRight
                                    }
                                }
                            }

                            // Card 3: EQUIPMENT Card with Exact SVG Vector Icon (`cv-exercise-equipment-card`)
                            Rectangle {
                                objectName: "nexusExerciseEquipmentCard"
                                Layout.fillWidth: true
                                Layout.preferredWidth: 160
                                implicitHeight: 52
                                radius: 9
                                color: root.journalSubSurfaceBg
                                border.width: 1
                                border.color: root.borderSubtle

                                RowLayout {
                                    anchors.centerIn: parent
                                    spacing: 8

                                    Canvas {
                                        id: exEquipmentIconCanvas
                                        objectName: "nexusExerciseEquipmentIcon"
                                        Layout.preferredWidth: 28
                                        Layout.preferredHeight: 28
                                        readonly property string eqKey: exerciseCustomView.equipmentRawStr
                                        readonly property color eqCol: root.accentColor
                                        onEqKeyChanged: if (visible) requestPaint()
                                        onEqColChanged: if (visible) requestPaint()
                                        onVisibleChanged: if (visible) requestPaint()
                                        onPaint: {
                                            const ctx = getContext("2d");
                                            ExerciseAnatomyData.paintEquipmentIcon(ctx, width, height, eqKey, String(eqCol));
                                        }
                                    }

                                    ColumnLayout {
                                        spacing: 2
                                        Text {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: "EQUIPMENT"
                                            font.family: Appearance.font.family.monospace
                                            font.pixelSize: 9
                                            font.weight: Font.Bold
                                            font.letterSpacing: 1.2
                                            color: root.accentColor
                                        }
                                        Text {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: exerciseCustomView.equipmentDisplayStr
                                            font.pixelSize: 12
                                            font.weight: Font.Bold
                                            color: root.textStrong
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Bottom Hero Divider (`border-bottom: 1px solid var(--cve-border)`)
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 1
                    color: root.borderSubtle
                }
            }

            // ── BOTTOM SECTION: `.cv-exercise-content` (Left Lined Notebook Sheet + Right Anatomy Map & Profile Sidebar) ──
            GridLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                columns: width >= 720 ? 2 : 1
                columnSpacing: 18
                rowSpacing: 16

                // Left Column: `.cv-exercise-instructions` Lined Notebook Sheet with Corner Tape & Interactive Step Checklist + Live Preview Edit
                Item {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 560
                    Layout.alignment: Qt.AlignTop
                    implicitHeight: exNotebookPaper.implicitHeight

                    Rectangle {
                        id: exNotebookPaper
                        objectName: "nexusExerciseNotebookCard"
                        width: parent.width
                        implicitHeight: Math.max(
                            exerciseCustomView.minLowerRowHeight,
                            exSideCol.implicitHeight,
                            exNotebookCol.implicitHeight + 24
                        )
                        radius: 9
                        color: root.cardSubtleBg
                        border.width: 1
                        border.color: root.borderSubtle
                        clip: true

                        // Subtle notebook lines matching Viewing Notes
                        Canvas {
                            anchors.fill: parent
                            opacity: 0.25
                            readonly property color _ruleColor: root.borderSubtle
                            on_RuleColorChanged: if (visible) requestPaint()
                            onWidthChanged: if (visible) requestPaint()
                            onHeightChanged: if (visible) requestPaint()
                            onVisibleChanged: if (visible) requestPaint()
                            onPaint: {
                                const ctx = getContext("2d");
                                ctx.reset();
                                ctx.strokeStyle = root.borderSubtle;
                                ctx.lineWidth = 1;
                                for (let y = 52; y < height - 12; y += 26) {
                                    ctx.beginPath();
                                    ctx.moveTo(14, y);
                                    ctx.lineTo(width - 14, y);
                                    ctx.stroke();
                                }
                            }
                        }

                        ColumnLayout {
                            id: exNotebookCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            spacing: 0

                            // `.cv-exercise-panel-head` inside Notebook (indented past 44px margin line)
                            Item {
                                Layout.fillWidth: true
                                implicitHeight: exInstructionHeader.implicitHeight + 24

                                GridLayout {
                                    id: exInstructionHeader
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: 18
                                    anchors.topMargin: 12
                                    columns: width >= 440 ? 2 : 1
                                    columnSpacing: 12
                                    rowSpacing: 8

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2

                                        Text {
                                            text: "STEP BY STEP"
                                            font.family: Appearance.font.family.monospace
                                            font.pixelSize: 10
                                            font.weight: Font.Bold
                                            font.letterSpacing: 1.5
                                            color: root.accentColor
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        wrapMode: Text.Wrap
                                        text: "Instructions & personal notes"
                                            font.pixelSize: 18
                                            font.weight: Font.Bold
                                            font.letterSpacing: -0.4
                                            color: root.textStrong
                                        }
                                    }

                                    Text {
                                        id: exEditPromptLabel
                                        objectName: "nexusExerciseEditInstructionsPrompt"
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        wrapMode: Text.Wrap
                                        text: (root.editingNoteBody && root.noteKind === "exercise")
                                            ? "Editing · Esc to finish"
                                            : "Click prose · Edit mode"
                                        font.family: Appearance.font.family.monospace
                                        font.pixelSize: 10
                                        color: (exEditPromptMouse.containsMouse || (root.editingNoteBody && root.noteKind === "exercise"))
                                            ? root.accentColor
                                            : root.textMuted

                                        MouseArea {
                                            id: exEditPromptMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (root.editingNoteBody && root.noteKind === "exercise") {
                                                    if (root.service)
                                                        root.service.saveNoteBodyMarkdown(exBodyEditor.text);
                                                    root.editingNoteBody = false;
                                                    root.restoreWorkspaceFocus();
                                                } else {
                                                    exBodyEditor.text = root.service ? root.service.getNoteBodyMarkdown() : "";
                                                    root.editingNoteBody = true;
                                                }
                                            }
                                        }
                                    }
                                }

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    height: 1
                                    color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.34)
                                }
                            }

                            // `.cv-exercise-note` body (`How to Perform` + interactive steps)
                            ColumnLayout {
                                visible: !(root.editingNoteBody && root.noteKind === "exercise")
                                Layout.fillWidth: true
                                Layout.leftMargin: 18
                                Layout.rightMargin: 18
                                Layout.topMargin: 10
                                spacing: 4

                                Text {
                                    Layout.fillWidth: true
                                    Layout.bottomMargin: 4
                                    horizontalAlignment: Text.AlignHCenter
                                    text: "How to Perform"
                                    font.pixelSize: 18
                                    font.weight: Font.Bold
                                    color: root.textStrong
                                }

                                Repeater {
                                    model: exerciseCustomView.livePreviewSteps
                                    delegate: Item {
                                        id: exStepItem
                                        required property string modelData
                                        required property int index
                                        objectName: "nexusExerciseStep_" + String(index)
                                        readonly property bool isChecked: index < root.exerciseActiveProgress
                                        readonly property bool isLastStep: index === (exerciseCustomView.livePreviewSteps.length - 1)
                                        Layout.fillWidth: true
                                        implicitHeight: Math.max(46, exStepText.implicitHeight + 16)

                                        // Rounded-Square Step Checkbox Control (`.cv-exercise-step-control` / `.cv-exercise-step-marker`)
                                        Rectangle {
                                            id: exStepCheckbox
                                            objectName: "nexusExerciseStepCheckbox_" + String(exStepItem.index)
                                            width: 26
                                            height: 26
                                            x: 0
                                            anchors.verticalCenter: parent.verticalCenter
                                            radius: 8
                                            color: exStepItem.isChecked
                                                ? root.accentColor
                                                : root.journalSubSurfaceBg
                                            border.width: 2
                                            border.color: (exStepCheckMouse.containsMouse || exStepItem.isChecked)
                                                ? root.accentColor
                                                : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.55)

                                            // Checkmark (`cv-exercise-step-check`)
                                            Canvas {
                                                anchors.fill: parent
                                                visible: exStepItem.isChecked
                                                readonly property color markCol: root.onAccentColor
                                                onMarkColChanged: if (visible) requestPaint()
                                                onVisibleChanged: if (visible) requestPaint()
                                                onPaint: {
                                                    const ctx = getContext("2d");
                                                    ctx.clearRect(0, 0, width, height);
                                                    ctx.strokeStyle = String(markCol);
                                                    ctx.lineWidth = 2.2;
                                                    ctx.lineCap = "round";
                                                    ctx.lineJoin = "round";
                                                    ctx.beginPath();
                                                    ctx.moveTo(7, 13.5);
                                                    ctx.lineTo(11.2, 17.8);
                                                    ctx.lineTo(19, 8.5);
                                                    ctx.stroke();
                                                }
                                            }

                                            MouseArea {
                                                id: exStepCheckMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    const targetProg = exStepItem.isChecked ? exStepItem.index : (exStepItem.index + 1);
                                                    root.setExerciseStepProgress(targetProg);
                                                }
                                            }
                                        }

                                        // Step Paragraph Text aligned to ruled paper — click opens inline Live Preview Edit
                                        Text {
                                            id: exStepText
                                            anchors.left: parent.left
                                            anchors.leftMargin: 38
                                            anchors.right: parent.right
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: exStepItem.modelData
                                            font.family: Appearance.font.family.monospace
                                            font.pixelSize: 12
                                            lineHeight: 22
                                            lineHeightMode: Text.FixedHeight
                                            color: exStepItem.isChecked ? root.textSecondary : root.textPrimary
                                            wrapMode: Text.Wrap

                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.IBeamCursor
                                                onClicked: {
                                                    if (!(root.editingNoteBody && root.noteKind === "exercise")) {
                                                        exBodyEditor.text = root.service ? root.service.getNoteBodyMarkdown() : "";
                                                        root.editingNoteBody = true;
                                                    } else {
                                                        exBodyEditor.forceActiveFocus();
                                                    }
                                                }
                                            }
                                        }

                                        Rectangle {
                                            visible: !exStepItem.isLastStep
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.bottom: parent.bottom
                                            height: 1
                                            color: Qt.rgba(root.borderSubtle.r, root.borderSubtle.g, root.borderSubtle.b, 0.72)
                                        }
                                    }
                                }
                            }

                            // Personal Notes & Tips Section (live-updated while editing and persisted after save)
                            ColumnLayout {
                                    id: exTipsSection
                                    objectName: "nexusExerciseTipsSection"
                                    visible: exerciseCustomView.livePreviewTips.length > 0
                                    Layout.fillWidth: true
                                    Layout.topMargin: 8
                                    spacing: 4

                                    Rectangle {
                                        Layout.fillWidth: true
                                        implicitHeight: 1
                                        color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.28)
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        Layout.topMargin: 4
                                        text: "PERSONAL NOTES & TIPS"
                                        font.family: Appearance.font.family.monospace
                                        font.pixelSize: 10
                                        font.weight: Font.Bold
                                        font.letterSpacing: 1.4
                                        color: root.accentColor
                                    }

                                    Repeater {
                                        model: exerciseCustomView.livePreviewTips
                                        delegate: Item {
                                            required property string modelData
                                            required property int index
                                            objectName: "nexusExerciseTip_" + String(index)
                                            Layout.fillWidth: true
                                            implicitHeight: Math.max(24, exTipTxt.implicitHeight + 6)

                                            Text {
                                                id: exTipTxt
                                                anchors.left: parent.left
                                                anchors.right: parent.right
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: "•  " + modelData
                                                font.family: Appearance.font.family.monospace
                                                font.pixelSize: 11
                                                color: root.textSecondary
                                                wrapMode: Text.Wrap
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.IBeamCursor
                                                onClicked: {
                                                    if (!(root.editingNoteBody && root.noteKind === "exercise")) {
                                                        exBodyEditor.text = root.service ? root.service.getNoteBodyMarkdown() : "";
                                                        root.editingNoteBody = true;
                                                    } else {
                                                        exBodyEditor.forceActiveFocus();
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                            // Live Inline Editor (matching Movies Note Journal tab)
                            ColumnLayout {
                                id: exLivePreviewEditBox
                                    objectName: "nexusExerciseLivePreviewEditBox"
                                    visible: root.editingNoteBody && root.noteKind === "exercise"
                                    Layout.fillWidth: true
                                    Layout.leftMargin: 18
                                    Layout.rightMargin: 18
                                    Layout.topMargin: 8
                                    spacing: 8

                                    Rectangle {
                                        Layout.fillWidth: true
                                        implicitHeight: Math.max(220, exBodyEditor.implicitHeight + 16)
                                        radius: 7
                                        color: Qt.rgba(root.cardDeepBg.r, root.cardDeepBg.g, root.cardDeepBg.b, 0.78)
                                        border.width: 1
                                        border.color: root.accentColor

                                        TextArea {
                                            id: exBodyEditor
                                            objectName: "nexusExerciseBodyEditor"
                                            anchors.fill: parent
                                            anchors.margins: 8
                                            text: root.service ? root.service.getNoteBodyMarkdown() : ""
                                            placeholderText: "Write your training notes & instructions here..."
                                            placeholderTextColor: root.textMuted
                                            color: root.textPrimary
                                            font.family: Appearance.font.family.main
                                            font.pixelSize: 13
                                            wrapMode: TextEdit.Wrap
                                            background: Item {}
                                            onVisibleChanged: {
                                                if (visible)
                                                    Qt.callLater(() => { if (exBodyEditor.visible) exBodyEditor.forceActiveFocus(); });
                                            }
                                            onActiveFocusChanged: {
                                                if (!activeFocus && visible && root.editingNoteBody && root.noteKind === "exercise" && !exCancelBtnMouse.containsMouse && !exCancelBtnMouse.pressed) {
                                                    if (root.service)
                                                        root.service.saveNoteBodyMarkdown(exBodyEditor.text);
                                                    root.editingNoteBody = false;
                                                }
                                            }
                                            Keys.onEscapePressed: event => {
                                                if (root.service)
                                                    root.service.saveNoteBodyMarkdown(exBodyEditor.text);
                                                exBodyEditor.focus = false;
                                                root.editingNoteBody = false;
                                                root.restoreWorkspaceFocus();
                                                event.accepted = true;
                                            }
                                            Keys.onPressed: event => {
                                                if (root.forwardWorkspaceShortcut(event))
                                                    return;
                                                if ((event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_S)) {
                                                    if (root.service)
                                                        root.service.saveNoteBodyMarkdown(exBodyEditor.text);
                                                    exBodyEditor.focus = false;
                                                    root.editingNoteBody = false;
                                                    root.restoreWorkspaceFocus();
                                                    event.accepted = true;
                                                }
                                            }
                                        }
                                    }

                                    GridLayout {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        columns: width >= 440 ? 4 : 2
                                        columnSpacing: 8
                                        rowSpacing: 8
                                        Text {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            Layout.columnSpan: parent.columns === 2 ? 2 : 1
                                            wrapMode: Text.Wrap
                                            text: "Live Preview Edit · Steps update in real time"
                                            font.family: Appearance.font.family.monospace
                                            font.pixelSize: 10
                                            color: root.textMuted
                                        }
                                        Item { visible: parent.columns === 4; Layout.fillWidth: true }
                                        Rectangle {
                                            objectName: "nexusExerciseCancelEditButton"
                                            radius: 5
                                            color: root.journalSubSurfaceBg
                                            border.width: 1
                                            border.color: root.borderSubtle
                                            implicitWidth: exCancelBtnTxt.implicitWidth + 16
                                            implicitHeight: 24
                                            Text {
                                                id: exCancelBtnTxt
                                                anchors.centerIn: parent
                                                text: "Cancel"
                                                font.pixelSize: 10
                                                color: root.textSecondary
                                            }
                                            MouseArea {
                                                id: exCancelBtnMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    exBodyEditor.text = root.service ? root.service.getNoteBodyMarkdown() : "";
                                                    root.editingNoteBody = false;
                                                    root.restoreWorkspaceFocus();
                                                }
                                            }
                                        }
                                        Rectangle {
                                            objectName: "nexusExerciseSaveEditButton"
                                            radius: 5
                                            color: root.accentColor
                                            implicitWidth: exSaveBtnTxt.implicitWidth + 16
                                            implicitHeight: 24
                                            Text {
                                                id: exSaveBtnTxt
                                                anchors.centerIn: parent
                                                text: "Save Instructions"
                                                font.pixelSize: 10
                                                font.weight: Font.Bold
                                                color: root.onAccentColor
                                            }
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    if (root.service)
                                                        root.service.saveNoteBodyMarkdown(exBodyEditor.text);
                                                    root.editingNoteBody = false;
                                                    root.restoreWorkspaceFocus();
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                        // Clickable bottom notebook area to enter Live Preview Edit
                        MouseArea {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: exNotebookCol.bottom
                            anchors.bottom: parent.bottom
                            visible: !(root.editingNoteBody && root.noteKind === "exercise")
                            cursorShape: Qt.IBeamCursor
                            onClicked: {
                                exBodyEditor.text = root.service ? root.service.getNoteBodyMarkdown() : "";
                                root.editingNoteBody = true;
                            }
                        }
                    }

                    // Translucent Angled Corner Tape Strip (`.cv-exercise-instructions::before`)
                    Rectangle {
                        id: exPaperTape
                        objectName: "nexusExercisePaperTape"
                        width: 76
                        height: 23
                        x: root.exerciseTapeSide === "right" ? (parent.width - width * 0.52) : (-width * 0.48)
                        y: -height * 0.45
                        rotation: root.exerciseTapeSide === "right" ? 34 : -34
                        color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.14)
                        border.width: 1
                        border.color: Qt.rgba(root.textStrong.r, root.textStrong.g, root.textStrong.b, 0.24)
                        z: 10
                    }
                }

                // Right Column: `.cv-exercise-sidebar` (Target Map Anatomy + Movement Profile)
                ColumnLayout {
                    id: exSideCol
                    Layout.fillWidth: true
                    Layout.preferredWidth: 310
                    Layout.minimumWidth: 270
                    Layout.alignment: Qt.AlignTop
                    spacing: 10

                    // Panel 1: `.cv-exercise-anatomy` (`TARGET MAP` / `Muscle focus` + Front/Back Anatomy SVG Canvas)
                    Rectangle {
                        id: exAnatomyCard
                        objectName: "nexusExerciseAnatomyCard"
                        Layout.fillWidth: true
                        implicitHeight: exAnatomyCol.implicitHeight
                        radius: 12
                        color: root.cardSubtleBg
                        border.width: 1
                        border.color: root.borderSubtle
                        clip: true

                        ColumnLayout {
                            id: exAnatomyCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            spacing: 0

                            // Header (`cv-exercise-panel-head--compact`)
                            Item {
                                Layout.fillWidth: true
                                implicitHeight: 44

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 16
                                    anchors.rightMargin: 16
                                    spacing: 8

                                    ColumnLayout {
                                        Layout.fillWidth: false
                                        spacing: 1
                                        Text {
                                            text: "TARGET MAP"
                                            font.family: Appearance.font.family.monospace
                                            font.pixelSize: 9
                                            font.weight: Font.Bold
                                            font.letterSpacing: 1.4
                                            color: root.accentColor
                                        }
                                        Text {
                                            text: "Muscle focus"
                                            font.pixelSize: 15
                                            font.weight: Font.Bold
                                            color: root.textStrong
                                        }
                                    }

                                    Item { Layout.fillWidth: true }

                                    // `.cv-exercise-map-legend` (`● Primary  ● Secondary`) — Right-aligned in header
                                    RowLayout {
                                        id: exMapLegend
                                        objectName: "nexusExerciseMapLegend"
                                        Layout.fillWidth: false
                                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                                        spacing: 5
                                        Rectangle {
                                            width: 8
                                            height: 8
                                            radius: 4
                                            color: root.accentColor
                                            border.width: 1
                                            border.color: Qt.lighter(root.accentColor, 1.45)
                                        }
                                        Text {
                                            text: "Primary"
                                            font.family: Appearance.font.family.monospace
                                            font.pixelSize: 10
                                            color: root.textSecondary
                                        }
                                        Item { width: 4; height: 1 }
                                        Rectangle {
                                            width: 8
                                            height: 8
                                            radius: 4
                                            color: root.exerciseSecondaryMuscleColor
                                            border.width: 1
                                            border.color: Qt.lighter(root.exerciseSecondaryMuscleColor, 1.4)
                                        }
                                        Text {
                                            text: "Secondary"
                                            font.family: Appearance.font.family.monospace
                                            font.pixelSize: 10
                                            color: root.textSecondary
                                        }
                                    }
                                }

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    height: 1
                                    color: root.borderSubtle
                                }
                            }

                            // `.cv-exercise-bodymap` Front & Back Human Anatomy Vector Map
                            Item {
                                Layout.fillWidth: true
                                implicitHeight: Math.max(
                                    184,
                                    Math.min(226, exerciseCustomView.minLowerRowHeight - 44 - exSideCol.spacing - exProfileCard.implicitHeight)
                                )

                                Canvas {
                                    id: exAnatomyCanvas
                                    objectName: "nexusExerciseBodyMapCanvas"
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    readonly property var primaryMuscles: (root.eView.primaryMuscles && root.eView.primaryMuscles.length > 0)
                                        ? root.eView.primaryMuscles
                                        : (root.dossier.muscleGroup ? String(root.dossier.muscleGroup).split(",") : [])
                                    readonly property var secondaryMuscles: (root.eView.secondaryMuscles && root.eView.secondaryMuscles.length > 0)
                                        ? root.eView.secondaryMuscles
                                        : (root.dossier.secondaryMuscles ? String(root.dossier.secondaryMuscles).split(",") : [])
                                    readonly property color primaryCol: root.accentColor
                                    readonly property color secondaryCol: root.exerciseSecondaryMuscleColor
                                    readonly property color surfaceCol: root.cardBg
                                    readonly property color mutedCol: root.textMuted
                                    readonly property color deepCol: root.cardDeepBg

                                    onPrimaryMusclesChanged: if (visible) requestPaint()
                                    onSecondaryMusclesChanged: if (visible) requestPaint()
                                    onPrimaryColChanged: if (visible) requestPaint()
                                    onSecondaryColChanged: if (visible) requestPaint()
                                    onSurfaceColChanged: if (visible) requestPaint()
                                    onWidthChanged: if (visible) requestPaint()
                                    onHeightChanged: if (visible) requestPaint()
                                    onVisibleChanged: if (visible) requestPaint()

                                    onPaint: {
                                        const ctx = getContext("2d");
                                        const bodyFill = String(Qt.tint(surfaceCol, Qt.rgba(mutedCol.r, mutedCol.g, mutedCol.b, 0.16)));
                                        const bodyStroke = String(Qt.rgba(mutedCol.r, mutedCol.g, mutedCol.b, 0.54));
                                        const muscleFill = String(Qt.tint(surfaceCol, Qt.rgba(mutedCol.r, mutedCol.g, mutedCol.b, 0.24)));
                                        const muscleStroke = String(Qt.tint(deepCol, Qt.rgba(mutedCol.r, mutedCol.g, mutedCol.b, 0.22)));
                                        const secStroke = String(secondaryCol);
                                        const priStroke = String(primaryCol);
                                        const secGlowOuter = String(Qt.rgba(secondaryCol.r, secondaryCol.g, secondaryCol.b, 0.02));
                                        const secGlowInner = String(Qt.rgba(secondaryCol.r, secondaryCol.g, secondaryCol.b, 0.10));
                                        const secRim = String(Qt.rgba(secondaryCol.r, secondaryCol.g, secondaryCol.b, 0.18));
                                        const priGlowOuter = String(Qt.rgba(primaryCol.r, primaryCol.g, primaryCol.b, 0.03));
                                        const priGlowInner = String(Qt.rgba(primaryCol.r, primaryCol.g, primaryCol.b, 0.12));
                                        const priRim = String(Qt.rgba(primaryCol.r, primaryCol.g, primaryCol.b, 0.22));
                                        ExerciseAnatomyData.paintAnatomyMap(
                                            ctx,
                                            width,
                                            height,
                                            primaryMuscles,
                                            secondaryMuscles,
                                            {
                                                bodyFill: bodyFill,
                                                bodyStroke: bodyStroke,
                                                muscleFill: muscleFill,
                                                muscleStroke: muscleStroke,
                                                secondaryFill: String(Qt.rgba(secondaryCol.r, secondaryCol.g, secondaryCol.b, 0.50)),
                                                secondaryStroke: secStroke,
                                                secondaryGlowOuter: secGlowOuter,
                                                secondaryGlowInner: secGlowInner,
                                                secondaryRim: secRim,
                                                primaryFill: String(Qt.rgba(primaryCol.r, primaryCol.g, primaryCol.b, 0.58)),
                                                primaryStroke: priStroke,
                                                primaryGlowOuter: priGlowOuter,
                                                primaryGlowInner: priGlowInner,
                                                primaryRim: priRim,
                                                labelColor: String(mutedCol)
                                            }
                                        );
                                    }
                                }
                            }
                        }
                    }

                    // Panel 2: `.cv-exercise-profile` (`MOVEMENT PROFILE` / `Training details` + Interactive Level Selector)
                    Rectangle {
                        id: exProfileCard
                        objectName: "nexusExerciseProfileCard"
                        Layout.fillWidth: true
                        implicitHeight: exProfileCol.implicitHeight
                        radius: 12
                        color: root.cardSubtleBg
                        border.width: 1
                        border.color: root.borderSubtle
                        clip: true

                        ColumnLayout {
                            id: exProfileCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            spacing: 0

                            // Header
                            Item {
                                Layout.fillWidth: true
                                implicitHeight: 42

                                ColumnLayout {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.leftMargin: 16
                                    anchors.rightMargin: 16
                                    spacing: 1

                                    Text {
                                        text: "MOVEMENT PROFILE"
                                        font.family: Appearance.font.family.monospace
                                        font.pixelSize: 9
                                        font.weight: Font.Bold
                                        font.letterSpacing: 1.4
                                        color: root.accentColor
                                    }
                                    Text {
                                        text: "Training details"
                                        font.pixelSize: 15
                                        font.weight: Font.Bold
                                        color: root.textStrong
                                    }
                                }

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    height: 1
                                    color: root.borderSubtle
                                }
                            }

                            // `.cv-exercise-profile-list` (Force, Mechanic, Category, Exercise ID)
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.leftMargin: 16
                                Layout.rightMargin: 16
                                Layout.topMargin: 2
                                Layout.bottomMargin: 2
                                spacing: 0

                                Repeater {
                                    model: [
                                        { "k": "FORCE", "v": exerciseCustomView.forceDisplayStr },
                                        { "k": "MECHANIC", "v": exerciseCustomView.mechanicDisplayStr },
                                        { "k": "CATEGORY", "v": exerciseCustomView.categoryDisplayStr },
                                        { "k": "EXERCISE ID", "v": exerciseCustomView.exerciseIdStr }
                                    ]
                                    delegate: Item {
                                        required property var modelData
                                        required property int index
                                        Layout.fillWidth: true
                                        implicitHeight: 26

                                        RowLayout {
                                            anchors.fill: parent
                                            spacing: 10
                                            Text {
                                                text: modelData.k
                                                font.family: Appearance.font.family.monospace
                                                font.pixelSize: 9
                                                font.letterSpacing: 0.9
                                                color: root.textMuted
                                            }
                                            Text {
                                                Layout.fillWidth: true
                                                horizontalAlignment: Text.AlignRight
                                                text: modelData.v
                                                font.family: Appearance.font.family.monospace
                                                font.pixelSize: 10
                                                color: root.textSecondary
                                                elide: Text.ElideRight
                                            }
                                        }

                                        Rectangle {
                                            visible: index < 3
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.bottom: parent.bottom
                                            height: 1
                                            color: root.borderSubtle
                                        }
                                    }
                                }
                            }

                            // `.cv-exercise-level-control` (`Beginner | Intermediate | Advanced`)
                            Item {
                                Layout.fillWidth: true
                                implicitHeight: 60

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    height: 1
                                    color: root.borderSubtle
                                }

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 16
                                    anchors.rightMargin: 16
                                    anchors.topMargin: 8
                                    anchors.bottomMargin: 8
                                    spacing: 6

                                    Text {
                                        text: "LEVEL"
                                        font.family: Appearance.font.family.monospace
                                        font.pixelSize: 9
                                        font.weight: Font.Bold
                                        font.letterSpacing: 1.2
                                        color: root.accentColor
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 6

                                        Repeater {
                                            model: [
                                                { "id": "beginner", "label": "Beginner" },
                                                { "id": "intermediate", "label": "Intermediate" },
                                                { "id": "expert", "label": "Advanced" }
                                            ]
                                            delegate: Rectangle {
                                                required property var modelData
                                                objectName: "nexusExerciseLevelButton_" + modelData.id
                                                readonly property bool isActive: exerciseCustomView.activeLevel === modelData.id
                                                readonly property color lvlCol: root.exerciseLevelColor(modelData.id)
                                                Layout.fillWidth: true
                                                Layout.preferredWidth: 80
                                                height: 26
                                                radius: 7
                                                color: isActive
                                                    ? Qt.rgba(lvlCol.r, lvlCol.g, lvlCol.b, 0.16)
                                                    : (exLvlBtnMouse.containsMouse ? root.journalSubSurfaceHoverBg : root.journalSubSurfaceBg)
                                                border.width: 1
                                                border.color: isActive
                                                    ? Qt.rgba(lvlCol.r, lvlCol.g, lvlCol.b, 0.72)
                                                    : root.borderSubtle

                                                Text {
                                                    anchors.centerIn: parent
                                                    text: modelData.label
                                                    font.pixelSize: 10
                                                    font.weight: Font.Bold
                                                    color: isActive ? lvlCol : root.textSecondary
                                                }

                                                MouseArea {
                                                    id: exLvlBtnMouse
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.setExerciseLevel(modelData.id)
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

        // =====================================================================
        // 1D. SETTINGS CUSTOM VIEW (`Settings.html` 6-Section Configuration Grid)
        // =====================================================================
        Rectangle {
            id: settingsCustomView
            objectName: "nexusSettingsCustomView"
            visible: root.noteKind === "settings"
            Layout.fillWidth: true
            implicitHeight: settingsGridCol.implicitHeight + 28
            radius: 10
            color: root.cardBg
            border.width: 1
            border.color: root.borderSubtle

            ColumnLayout {
                id: settingsGridCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 16
                spacing: 12

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: "VAULT CONFIGURATION · API KEYS & SCHEDULE BINDINGS"
                        font.pixelSize: 11
                        font.weight: Font.Bold
                        font.letterSpacing: 1.5
                        color: root.accentColor
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: "90_System/93_Configuration/settings.md"
                        font.pixelSize: 10
                        font.family: Appearance.font.family.monospace
                        color: root.textMuted
                    }
                }

                OrnamentalDivider {}

                GridLayout {
                    Layout.fillWidth: true
                    columns: width > 680 ? 2 : 1
                    rowSpacing: 10
                    columnSpacing: 12

                    Repeater {
                        model: [
                            { "code": "01", "title": "General & Schedule", "keys": ["username", "vault_name", "start_date", "callout_path", "schedule_heading", "exercise_heading", "cardio_heading"] },
                            { "code": "02", "title": "Weather Provider", "keys": ["weather_provider", "weather_location", "weather_units", "openweathermap_key"] },
                            { "code": "03", "title": "Media & Books APIs", "keys": ["tmdb_key", "omdb_key", "mal_client_id", "spoonacular_key", "youtube_key"] },
                            { "code": "04", "title": "Games & Finance", "keys": ["rawg_key", "steam_key", "steam_id", "default_currency", "currency_symbol", "monthly_budget"] }
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignTop
                            implicitHeight: secCardCol.implicitHeight + 20
                            radius: 8
                            color: root.cardRaisedBg
                            border.width: 1
                            border.color: root.borderSubtle

                            ColumnLayout {
                                id: secCardCol
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 10
                                spacing: 6

                                RowLayout {
                                    Text { text: modelData.code; font.pixelSize: 10; font.family: Appearance.font.family.monospace; color: root.accentColor }
                                    Text { text: modelData.title.toUpperCase(); font.pixelSize: 10; font.weight: Font.Bold; color: root.textPrimary }
                                }

                                Repeater {
                                    model: modelData.keys
                                    delegate: RowLayout {
                                        required property string modelData
                                        Layout.fillWidth: true
                                        spacing: 8
                                        Text {
                                            Layout.preferredWidth: 130
                                            text: modelData
                                            font.pixelSize: 10
                                            font.family: Appearance.font.family.monospace
                                            color: root.textSecondary
                                            elide: Text.ElideRight
                                        }
                                        TextField {
                                            Layout.fillWidth: true
                                            implicitHeight: 24
                                            text: String(root.doc?.frontmatter?.[modelData] ?? "")
                                            echoMode: modelData.includes("key") || modelData.includes("token") || modelData.includes("secret") ? TextInput.PasswordEchoOnEdit : TextInput.Normal
                                            font.pixelSize: 10
                                            color: root.textPrimary
                                            background: Rectangle {
                                                radius: 4
                                                color: root.cardDeepBg
                                                border.width: 1
                                                border.color: parent.activeFocus ? root.accentColor : root.borderSubtle
                                            }
                                            onAccepted: root.restoreWorkspaceFocus()
                                            Keys.onEscapePressed: event => {
                                                root.restoreWorkspaceFocus();
                                                event.accepted = true;
                                            }
                                            Keys.onPressed: event => root.forwardWorkspaceShortcut(event)
                                            onEditingFinished: {
                                                if (root.service) {
                                                    const patch = {};
                                                    patch[modelData] = text;
                                                    root.service.updateNoteFrontmatter(patch);
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

        // =====================================================================
        // 2. JOURNAL CUSTOM VIEW (`Journal.html` + Screenshot 2 1:1 Parity)
        // =====================================================================
        Rectangle {
            id: journalCustomView
            objectName: "nexusJournalCustomView"
            Layout.minimumWidth: 0
            visible: root.noteKind === "journal"
            Layout.fillWidth: true
            implicitHeight: Math.max(root.minDocumentSurfaceHeight, journalMainCol.implicitHeight + 36)
            radius: 10
            color: root.cardSubtleBg
            border.width: 1
            border.color: root.borderAccent

            onVisibleChanged: {
                if (visible && root.service) {
                    if (HostServices.Weather && typeof HostServices.Weather.getData === "function")
                        HostServices.Weather.getData();
                    if (String(root.jView.weather ?? "").trim().length === 0 && String(root.service.alisWeatherSummary ?? "").trim().length > 0)
                        Qt.callLater(() => { if (root.service && root.noteKind === "journal") root.service.fetchWeatherForCurrentJournal(); });
                }
            }

            ColumnLayout {
                id: journalMainCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 18
                spacing: 14

                // 2.1 Top Masthead: `JOURNAL` (left) | `NOVEMBER · 2026` (right)
                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: "JOURNAL"
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        font.letterSpacing: 2.4
                        color: root.accentColor
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: String(root.jView.monthName ?? "November").toUpperCase() + "  ·  " + String(root.jView.year ?? "2026")
                        font.pixelSize: 10
                        font.weight: Font.Medium
                        font.letterSpacing: 1.6
                        color: root.textMuted
                    }
                }

                Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: root.borderSubtle }

                // 2.2 Date Lockup (Left) + Thought for the Day & Prev/Today/Next (Right)
                GridLayout {
                    columns: width < 560 ? 1 : 2
                    columnSpacing: 24
                    rowSpacing: 24
                    id: jTopDateRow
                    Layout.fillWidth: true

                    // Left: FRIDAY + Giant 06 + November / 2026
                    ColumnLayout {
                        Layout.alignment: Qt.AlignTop
                        spacing: 2

                        Text {
                            text: String(root.jView.weekday ?? "Friday").toUpperCase()
                            font.pixelSize: 11
                            font.weight: Font.Bold
                            font.letterSpacing: 2.2
                            color: root.accentColor
                        }

                        RowLayout {
                            spacing: 14
                            Text {
                                readonly property int dayNum: Number(root.jView.day ?? 6)
                                text: dayNum < 10 ? ("0" + String(dayNum)) : String(dayNum)
                                font.pixelSize: 56
                                font.weight: Font.Black
                                color: root.textStrong
                            }
                            ColumnLayout {
                                spacing: 2
                                Text {
                                    text: String(root.jView.monthName ?? "November")
                                    font.pixelSize: 15
                                    font.weight: Font.Medium
                                    color: root.textSecondary
                                }
                                Text {
                                    text: String(root.jView.year ?? "2026")
                                    font.pixelSize: 12
                                    font.family: Appearance.font.family.monospace
                                    color: root.textMuted
                                }
                            }
                        }
                    }

                    // Right: Thought for the Day quote + Prev / Today / Next buttons
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignTop
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12

                            Rectangle {
                                Layout.preferredWidth: 2
                                Layout.fillHeight: true
                                Layout.minimumHeight: 48
                                color: root.accentColor
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4

                                Text {
                                    text: "“  THOUGHT FOR THE DAY"
                                    font.pixelSize: 9
                                    font.weight: Font.Bold
                                    font.letterSpacing: 1.5
                                    color: root.accentColor
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: String(root.jView.quoteText || root.jView.quote || "Discipline equals freedom.")
                                    font.pixelSize: 12
                                    font.italic: true
                                    color: root.textPrimary
                                    wrapMode: Text.Wrap
                                }

                                Text {
                                    text: "— " + String(root.jView.quoteAuthor || "Stoic")
                                    font.pixelSize: 10
                                    color: root.textMuted
                                }
                            }
                        }

                        // ‹ Previous | Today | Next › buttons aligned right
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            Item { Layout.fillWidth: true }

                            Repeater {
                                model: [
                                    { "label": "‹ Previous", "action": "prev" },
                                    { "label": "Today", "action": "today" },
                                    { "label": "Next ›", "action": "next" }
                                ]
                                delegate: Rectangle {
                                    required property var modelData
                                    radius: 5
                                    color: jNavMouse.containsMouse ? root.journalSubSurfaceHoverBg : root.journalSubSurfaceBg
                                    border.width: 1
                                    border.color: jNavMouse.containsMouse ? root.accentColor : root.borderSubtle
                                    implicitWidth: jNavTxt.implicitWidth + 16
                                    implicitHeight: 22

                                    Text {
                                        id: jNavTxt
                                        anchors.centerIn: parent
                                        text: modelData.label
                                        font.pixelSize: 10
                                        font.weight: Font.Medium
                                        color: jNavMouse.containsMouse ? root.accentColor : root.textSecondary
                                    }
                                    MouseArea {
                                        id: jNavMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (!root.service)
                                                return;
                                            if (modelData.action === "today") {
                                                root.service.openDailyNote();
                                            } else if (modelData.action === "prev") {
                                                const p = String(root.jView.prevJournalPath ?? "");
                                                if (p.length > 0)
                                                    root.service.openFile(p, true);
                                                else if (String(root.jView.prevDateIso ?? "").length > 0)
                                                    root.service.openOrCreateJournalByDate(String(root.jView.prevDateIso));
                                            } else if (modelData.action === "next") {
                                                const n = String(root.jView.nextJournalPath ?? "");
                                                if (n.length > 0)
                                                    root.service.openFile(n, true);
                                                else if (String(root.jView.nextDateIso ?? "").length > 0)
                                                    root.service.openOrCreateJournalByDate(String(root.jView.nextDateIso));
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // 2.3 DAILY SNAPSHOT: 3 Simultaneous Side-by-Side Columns (SCHEDULE | TRAINING | CARDIO) — Clean Auto-Theming surface without grey backgrounds
                Rectangle {
                    id: jSnapshotCard
                    objectName: "nexusJournalSnapshotCard"
                    Layout.fillWidth: true
                    implicitHeight: snapInnerCol.implicitHeight + 24
                    radius: 8
                    color: root.cardSubtleBg
                    border.width: 1
                    border.color: root.borderSubtle

                    ColumnLayout {
                        id: snapInnerCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 12
                        spacing: 10

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "DAILY SNAPSHOT"
                                font.pixelSize: 10
                                font.weight: Font.Bold
                                font.letterSpacing: 1.6
                                color: root.accentColor
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: "Compact daily context"
                                font.pixelSize: 10
                                font.italic: true
                                color: root.textMuted
                            }
                        }

                        GridLayout {
                    columns: width < 600 ? 1 : 3
                    columnSpacing: 10
                    rowSpacing: 10
                            Layout.fillWidth: true

                            // Pane 1: SCHEDULE
                            Rectangle {
                                id: jSchedulePane
                                objectName: "nexusJournalSchedulePane"
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                Layout.alignment: Qt.AlignTop
                                implicitHeight: schedPaneCol.implicitHeight + 18
                                radius: 6
                                color: "transparent"
                                border.width: 1
                                border.color: root.borderSubtle

                                ColumnLayout {
                                    id: schedPaneCol
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: 9
                                    spacing: 5

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text { text: "SCHEDULE"; font.pixelSize: 9; font.weight: Font.Bold; font.letterSpacing: 1.2; color: root.textSecondary }
                                        Item { Layout.fillWidth: true }
                                        Text {
                                            text: String((root.jPlannerRows ?? []).length) + " items"
                                            font.pixelSize: 9
                                            font.family: Appearance.font.family.monospace
                                            color: root.textMuted
                                        }
                                    }

                                    Repeater {
                                        model: (root.jPlannerRows ?? []).slice(0, 6)
                                        delegate: RowLayout {
                                            required property var modelData
                                            readonly property string timeStr: Array.isArray(modelData)
                                                ? String(modelData[0] ?? "")
                                                : String(modelData?.time ?? modelData?.slot ?? "")
                                            readonly property string activityStr: root.stripPlainMarkdown(Array.isArray(modelData)
                                                ? String(modelData[1] ?? "")
                                                : String(modelData?.activity ?? modelData?.title ?? modelData?.text ?? ""))
                                            Layout.fillWidth: true
                                            spacing: 8
                                            Text {
                                                Layout.preferredWidth: 84
                                                text: timeStr
                                                font.pixelSize: 10
                                                font.family: Appearance.font.family.monospace
                                                color: root.accentColor
                                                elide: Text.ElideRight
                                            }
                                            Text {
                                                Layout.fillWidth: true
                                                text: activityStr
                                                font.pixelSize: 10
                                                color: root.textPrimary
                                                elide: Text.ElideRight
                                            }
                                        }
                                    }

                                    Text {
                                        visible: (root.jPlannerRows ?? []).length === 0
                                        text: "No events scheduled in Weekly Planner"
                                        font.pixelSize: 9
                                        font.italic: true
                                        color: root.textMuted
                                    }

                                    Text {
                                        visible: (root.jPlannerRows ?? []).length > 6
                                        text: "+" + String((root.jPlannerRows ?? []).length - 6) + " more"
                                        font.pixelSize: 9
                                        font.italic: true
                                        color: root.textMuted
                                    }
                                }
                            }

                            // Pane 2: TRAINING
                            Rectangle {
                                id: jTrainingPane
                                objectName: "nexusJournalTrainingPane"
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                Layout.alignment: Qt.AlignTop
                                implicitHeight: trainPaneCol.implicitHeight + 18
                                radius: 6
                                color: "transparent"
                                border.width: 1
                                border.color: root.borderSubtle

                                ColumnLayout {
                                    id: trainPaneCol
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: 9
                                    spacing: 5

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text { text: "TRAINING"; font.pixelSize: 9; font.weight: Font.Bold; font.letterSpacing: 1.2; color: root.textSecondary }
                                        Item { Layout.fillWidth: true }
                                        Text {
                                            text: String((root.jSchedule.exerciseRows ?? []).length) + " items"
                                            font.pixelSize: 9
                                            font.family: Appearance.font.family.monospace
                                            color: root.textMuted
                                        }
                                    }

                                    Repeater {
                                        model: (root.jSchedule.exerciseRows ?? []).slice(0, 6)
                                        delegate: RowLayout {
                                            required property var modelData
                                            required property int index
                                            objectName: "nexusJournalTrainingRow_" + String(index)
                                            readonly property string exName: root.stripPlainMarkdown(Array.isArray(modelData)
                                                ? String(modelData[0] ?? "")
                                                : String(modelData?.exercise ?? modelData?.name ?? ""))
                                            readonly property string exReps: Array.isArray(modelData)
                                                ? String(modelData[1] ?? "")
                                                : String(modelData?.reps ?? "")
                                            readonly property string exSets: Array.isArray(modelData)
                                                ? String(modelData[2] ?? "")
                                                : String(modelData?.sets ?? "")
                                            readonly property string exEquip: root.stripPlainMarkdown(Array.isArray(modelData)
                                                ? String(modelData[3] ?? "")
                                                : String(modelData?.equipment ?? ""))
                                            readonly property string setsRepsLabel: {
                                                if (exSets.length > 0 && exReps.length > 0)
                                                    return exSets + "×" + exReps;
                                                return exReps.length > 0 ? exReps : exSets;
                                            }
                                            Layout.fillWidth: true
                                            spacing: 6
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 1
                                                Text {
                                                    objectName: "nexusJournalTrainingExerciseName_" + String(index)
                                                    Layout.fillWidth: true
                                                    text: exName
                                                    font.pixelSize: 10
                                                    font.weight: Font.DemiBold
                                                    color: root.textPrimary
                                                    elide: Text.ElideRight
                                                }
                                                Text {
                                                    visible: exEquip.length > 0
                                                    text: exEquip
                                                    font.pixelSize: 9
                                                    color: root.textMuted
                                                    elide: Text.ElideRight
                                                }
                                            }
                                            Text {
                                                id: repBadge
                                                objectName: "nexusJournalTrainingSetsReps_" + String(index)
                                                visible: setsRepsLabel.length > 0
                                                text: setsRepsLabel
                                                font.pixelSize: 9
                                                font.family: Appearance.font.family.monospace
                                                font.weight: Font.Bold
                                                color: root.accentColor
                                            }
                                        }
                                    }

                                    Text {
                                        visible: (root.jSchedule.exerciseRows ?? []).length === 0
                                        text: "No training logged"
                                        font.pixelSize: 9
                                        font.italic: true
                                        color: root.textMuted
                                    }
                                }
                            }

                            // Pane 3: CARDIO
                            Rectangle {
                                id: jCardioPane
                                objectName: "nexusJournalCardioPane"
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                Layout.alignment: Qt.AlignTop
                                implicitHeight: cardioPaneCol.implicitHeight + 18
                                radius: 6
                                color: "transparent"
                                border.width: 1
                                border.color: root.borderSubtle

                                ColumnLayout {
                                    id: cardioPaneCol
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: 9
                                    spacing: 5

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text { text: "CARDIO"; font.pixelSize: 9; font.weight: Font.Bold; font.letterSpacing: 1.2; color: root.textSecondary }
                                        Item { Layout.fillWidth: true }
                                        Text {
                                            text: String((root.jSchedule.cardioRows ?? []).length) + " items"
                                            font.pixelSize: 9
                                            font.family: Appearance.font.family.monospace
                                            color: root.textMuted
                                        }
                                    }

                                    Repeater {
                                        model: (root.jSchedule.cardioRows ?? []).slice(0, 6)
                                        delegate: RowLayout {
                                            required property var modelData
                                            required property int index
                                            objectName: "nexusJournalCardioRow_" + String(index)
                                            readonly property string cardioName: root.stripPlainMarkdown(Array.isArray(modelData)
                                                ? String(modelData[0] ?? "")
                                                : String(modelData?.exercise ?? modelData?.activity ?? modelData?.name ?? ""))
                                            readonly property string cardioDuration: Array.isArray(modelData)
                                                ? String(modelData[1] ?? "")
                                                : String(modelData?.duration ?? "")
                                            readonly property string cardioIntensity: Array.isArray(modelData)
                                                ? String(modelData[2] ?? "")
                                                : String(modelData?.intensity ?? "")
                                            Layout.fillWidth: true
                                            spacing: 6
                                            Text {
                                                objectName: "nexusJournalCardioName_" + String(index)
                                                Layout.fillWidth: true
                                                text: cardioName
                                                font.pixelSize: 10
                                                font.weight: Font.DemiBold
                                                color: root.textPrimary
                                                elide: Text.ElideRight
                                            }
                                            Text {
                                                visible: cardioDuration.length > 0
                                                text: cardioDuration
                                                font.pixelSize: 9
                                                font.family: Appearance.font.family.monospace
                                                color: root.accentColor
                                            }
                                            Text {
                                                visible: cardioIntensity.length > 0
                                                text: cardioIntensity
                                                font.pixelSize: 9
                                                color: root.textMuted
                                            }
                                        }
                                    }

                                    Text {
                                        visible: (root.jSchedule.cardioRows ?? []).length === 0
                                        text: "No cardio logged"
                                        font.pixelSize: 9
                                        font.italic: true
                                        color: root.textMuted
                                    }
                                }
                            }
                        }
                    }
                }

                // 2.4 2-Column Body: Left `DAILY FOLIO` Lined Paper Card + Right `STATE / WEATHER / TAGS / REFLECTION / HEALTH / ON THIS DAY / ARCHIVE`
                GridLayout {
                    columns: width < 700 ? 1 : 2
                    columnSpacing: 16
                    rowSpacing: 16
                    id: journalBodyGrid
                    Layout.fillWidth: true

                    // Left: DAILY FOLIO lined notebook card (expands to fill bottom viewport space)
                    Rectangle {
                        id: jDailyFolioCard
                        objectName: "nexusJournalDailyFolioCard"
                        readonly property int minFolioHeight: Math.max(
                            440,
                            root.minDocumentSurfaceHeight - jTopDateRow.implicitHeight - jSnapshotCard.implicitHeight - 96
                        )
                        Layout.fillWidth: true
                        Layout.preferredWidth: 620
                        Layout.alignment: Qt.AlignTop
                        implicitHeight: Math.max(minFolioHeight, jRightRailCard.implicitHeight, folioCol.implicitHeight + 32)
                        radius: 9
                        color: root.cardSubtleBg
                        border.width: 1
                        border.color: root.borderSubtle
                        clip: true

                        // Subtle notebook lines matching Viewing Notes
                        Canvas {
                            anchors.fill: parent
                            opacity: 0.25
                            readonly property color _ruleColor: root.borderSubtle
                            on_RuleColorChanged: if (visible) requestPaint()
                            onWidthChanged: if (visible) requestPaint()
                            onHeightChanged: if (visible) requestPaint()
                            onVisibleChanged: if (visible) requestPaint()
                            onPaint: {
                                const ctx = getContext("2d");
                                ctx.reset();
                                ctx.strokeStyle = root.borderSubtle;
                                ctx.lineWidth = 1;
                                for (let y = 52; y < height - 12; y += 26) {
                                    ctx.beginPath();
                                    ctx.moveTo(14, y);
                                    ctx.lineTo(width - 14, y);
                                    ctx.stroke();
                                }
                            }
                        }

                        ColumnLayout {
                            id: folioCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 16
                            spacing: 10

                            GridLayout {
                    columns: width < 360 ? 1 : 3
                    columnSpacing: 6
                    rowSpacing: 6
                                Layout.fillWidth: true
                                Text {
                                    text: "DAILY FOLIO"
                                    font.pixelSize: 9
                                    font.weight: Font.Bold
                                    font.letterSpacing: 1.6
                                    color: root.textMuted
                                }
                                Item { Layout.fillWidth: true; visible: parent.columns > 1 }
                                Text {
                                    Layout.fillWidth: true
                                    wrapMode: Text.Wrap
                                    text: root.journalEditingDailyLog
                                        ? "Editing · Esc to finish"
                                        : (String(root.jView.weekday ?? "Friday") + " · " + String(root.jView.monthName ?? "November") + " " + String(root.jView.day ?? "6") + " · Click to edit")
                                    font.pixelSize: 10
                                    font.italic: !root.journalEditingDailyLog
                                    color: root.journalEditingDailyLog ? root.accentColor : root.textMuted
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (root.journalEditingDailyLog) {
                                                if (root.service && dailyLogEditor.text !== String(root.jView.dailyLogText ?? ""))
                                                    root.service.saveJournalDailyLog(dailyLogEditor.text);
                                                root.journalEditingDailyLog = false;
                                                if (root.workspace && typeof root.workspace.focusPrimarySurface === "function")
                                                    Qt.callLater(root.workspace.focusPrimarySurface);
                                            } else {
                                                dailyLogEditor.text = String(root.jView.dailyLogText ?? "");
                                                root.journalEditingDailyLog = true;
                                            }
                                        }
                                    }
                                }
                            }

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: "Daily Log"
                                font.pixelSize: 18
                                font.weight: Font.DemiBold
                                color: root.textPrimary
                            }

                            OrnamentalDivider {}

                            // Reading Mode (Default): Click anywhere on the Daily Log prose to switch to Editing Mode
                            Item {
                                id: dailyLogReadingArea
                                objectName: "nexusJournalDailyLogReadingArea"
                                visible: !root.journalEditingDailyLog
                                Layout.fillWidth: true
                                Layout.minimumHeight: Math.max(300, jDailyFolioCard.minFolioHeight - 108, jRightRailCard.implicitHeight - 108)
                                implicitHeight: Math.max(300, jDailyFolioCard.minFolioHeight - 108, jRightRailCard.implicitHeight - 108, dailyLogReadingText.implicitHeight + 24)

                                Text {
                                    id: dailyLogReadingText
                                    objectName: "nexusJournalDailyLogReadingText"
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.topMargin: 4
                                    readonly property string rawLogText: String(root.jView.dailyLogText ?? "")
                                        .replace(/^\s*#{1,6}\s*(?:daily\s+log|notes\s*(?:&|and)\s*log)\s*\n?/i, "")
                                        .trim()
                                    readonly property string renderedLogHtml: {
                                        const _sig = root.themeSignature;
                                        if (rawLogText.length === 0)
                                            return "";
                                        const rustHtml = String(root.jView.dailyLogRichHtml ?? "").trim();
                                        const hasUnparsedBlockSyntax = /(^|>|\n)\s*#{1,6}\s+/m.test(rustHtml)
                                            || /(^|>|\n)\s*[-*+]\s*($|\n|<)/m.test(rustHtml)
                                            || /(^|>|\n)\s*[-*+]\s+\[[ xX]\]/m.test(rustHtml)
                                            || />\s*(?:Notes\s*(?:&amp;|&|and)\s*Log|Daily\s+Log)\s*<\/span>/i.test(rustHtml);
                                        if (rustHtml.length > 0 && !hasUnparsedBlockSyntax)
                                            return root.themeRichHtml(rustHtml);
                                        return root.renderMarkdownBlocksHtml(rawLogText);
                                    }
                                    readonly property bool hasLog: renderedLogHtml.length > 0
                                    text: hasLog ? renderedLogHtml : "Click here to write your daily log..."
                                    textFormat: hasLog ? Text.RichText : Text.PlainText
                                    font.pixelSize: 14
                                    font.italic: !hasLog
                                    lineHeight: 26
                                    lineHeightMode: Text.FixedHeight
                                    color: hasLog ? root.textPrimary : root.textMuted
                                    wrapMode: Text.Wrap
                                    onLinkActivated: link => {
                                        if (root.service && link.startsWith("wikilink:"))
                                            root.service.followWikilink(decodeURIComponent(link.substring(9)));
                                    }
                                }

                                MouseArea {
                                    id: dailyLogReadingMouse
                                    objectName: "nexusJournalDailyLogClickTarget"
                                    anchors.fill: parent
                                    cursorShape: Qt.IBeamCursor
                                    onClicked: {
                                        dailyLogEditor.text = dailyLogReadingText.rawLogText;
                                        root.journalEditingDailyLog = true;
                                    }
                                }
                            }

                            // Editing Mode (Activated only when clicked)
                            ColumnLayout {
                                visible: root.journalEditingDailyLog && root.noteKind === "journal"
                                Layout.fillWidth: true
                                spacing: 8

                                TextArea {
                                    id: dailyLogEditor
                                    objectName: "nexusJournalDailyLogEditor"
                                    Layout.fillWidth: true
                                    Layout.minimumHeight: Math.max(300, jDailyFolioCard.minFolioHeight - 140, jRightRailCard.implicitHeight - 140)
                                    text: String(root.jView.dailyLogText ?? "")
                                    placeholderText: "Write your daily log here..."
                                    placeholderTextColor: root.textMuted
                                    color: root.textPrimary
                                    font.pixelSize: 14
                                    wrapMode: TextEdit.Wrap
                                    background: Item {}
                                    onVisibleChanged: {
                                        if (visible)
                                            Qt.callLater(() => { if (dailyLogEditor.visible) dailyLogEditor.forceActiveFocus(); });
                                    }
                                    onActiveFocusChanged: {
                                        if (!activeFocus && visible && root.journalEditingDailyLog && root.noteKind === "journal" && !cancelLogMouse.containsMouse && !cancelLogMouse.pressed) {
                                            if (root.service && dailyLogEditor.text !== String(root.jView.dailyLogText ?? ""))
                                                root.service.saveJournalDailyLog(dailyLogEditor.text);
                                            root.journalEditingDailyLog = false;
                                        }
                                    }
                                    Keys.onEscapePressed: event => {
                                        if (root.service && dailyLogEditor.text !== String(root.jView.dailyLogText ?? ""))
                                            root.service.saveJournalDailyLog(dailyLogEditor.text);
                                        dailyLogEditor.focus = false;
                                        root.journalEditingDailyLog = false;
                                        root.restoreWorkspaceFocus();
                                        event.accepted = true;
                                    }
                                    Keys.onPressed: event => {
                                        if ((event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_S)) {
                                            if (root.service)
                                                root.service.saveJournalDailyLog(dailyLogEditor.text);
                                            dailyLogEditor.focus = false;
                                            root.journalEditingDailyLog = false;
                                            root.restoreWorkspaceFocus();
                                            event.accepted = true;
                                            return;
                                        }
                                        if ((event.modifiers & (Qt.AltModifier | Qt.ControlModifier | Qt.MetaModifier)) !== 0
                                            && root.service && root.service.handleKeyEvent(event)) {
                                            event.accepted = true;
                                        }
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    Item { Layout.fillWidth: true }
                                    Rectangle {
                                        objectName: "nexusJournalDailyLogCancelButton"
                                        radius: 5
                                        color: root.journalSubSurfaceBg
                                        border.width: 1
                                        border.color: root.borderSubtle
                                        implicitWidth: cancelLogLbl.implicitWidth + 16
                                        implicitHeight: 24
                                        Text {
                                            id: cancelLogLbl
                                            anchors.centerIn: parent
                                            text: "Cancel"
                                            font.pixelSize: 10
                                            color: root.textSecondary
                                        }
                                        MouseArea {
                                            id: cancelLogMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                dailyLogEditor.text = String(root.jView.dailyLogText ?? "");
                                                root.journalEditingDailyLog = false;
                                                if (root.workspace && typeof root.workspace.focusPrimarySurface === "function")
                                                    Qt.callLater(root.workspace.focusPrimarySurface);
                                            }
                                        }
                                    }
                                    Rectangle {
                                        objectName: "nexusJournalDailyLogSaveButton"
                                        radius: 5
                                        color: root.accentColor
                                        implicitWidth: saveLogLbl.implicitWidth + 16
                                        implicitHeight: 24
                                        Text {
                                            id: saveLogLbl
                                            anchors.centerIn: parent
                                            text: "Save Daily Log"
                                            font.pixelSize: 10
                                            font.weight: Font.Bold
                                            color: root.onAccentColor
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (root.service)
                                                    root.service.saveJournalDailyLog(dailyLogEditor.text);
                                                root.journalEditingDailyLog = false;
                                                if (root.workspace && typeof root.workspace.focusPrimarySurface === "function")
                                                    Qt.callLater(root.workspace.focusPrimarySurface);
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Right Context Column: STATE, WEATHER, TAGS, REFLECTION, HEALTH, ON THIS DAY, ARCHIVE
                    // Uses the exact same base background color as Daily Log (`root.cardDeepBg`), with slightly brighter Auto-Theming sub-surfaces (`root.journalSubSurfaceBg`)
                    Rectangle {
                        id: jRightRailCard
                        objectName: "nexusJournalRightRailCard"
                        Layout.fillWidth: journalBodyGrid.columns === 1
                        Layout.preferredWidth: 270
                        Layout.minimumWidth: 0
                        Layout.maximumWidth: journalBodyGrid.columns === 1 ? Infinity : 310
                        Layout.alignment: Qt.AlignTop
                        implicitHeight: jRightRailCol.implicitHeight + 28
                        radius: 8
                        color: root.cardSubtleBg
                        border.width: 1
                        border.color: root.borderSubtle

                        ColumnLayout {
                            id: jRightRailCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 14
                            spacing: 10

                            // STATE: Mood & Energy (Strictly Low-to-High from Left to Right: `thấp đến cao`)
                            RowLayout {
                                Layout.fillWidth: true
                                Text { text: "HOW YOU FELT"; font.pixelSize: 9; font.weight: Font.Bold; font.letterSpacing: 1.5; color: root.accentColor }
                                Item { Layout.fillWidth: true }
                                Text { text: "Low → High"; font.pixelSize: 9; font.family: Appearance.font.family.monospace; color: root.textMuted }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Text { text: "Mood"; font.pixelSize: 10; font.weight: Font.DemiBold; color: root.textSecondary }
                                Item { Layout.fillWidth: true }
                                Text {
                                    objectName: "nexusJournalMoodValueLabel"
                                    text: root.journalMoodDisplayLabel(root.jView.mood)
                                    font.pixelSize: 10
                                    font.family: Appearance.font.family.monospace
                                    color: root.journalCanonicalMood(root.jView.mood).length > 0 ? root.accentColor : root.textMuted
                                }
                            }

                            RowLayout {
                                id: journalMoodRow
                                objectName: "nexusJournalMoodRow"
                                Layout.fillWidth: true
                                spacing: 4
                                Repeater {
                                    model: root.journalMoodOptions
                                    delegate: Rectangle {
                                        required property var modelData
                                        required property int index
                                        objectName: "nexusJournalMoodOption_" + String(index)
                                        readonly property string moodValue: String(modelData.value)
                                        readonly property string moodLabel: String(modelData.label)
                                        readonly property int scaleOrder: index + 1
                                        readonly property bool active: root.journalCanonicalMood(root.jView.mood) === moodValue
                                        Layout.fillWidth: true
                                        implicitHeight: 38
                                        radius: 5
                                        color: active
                                            ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.22)
                                            : (moodOptMouse.containsMouse ? root.journalSubSurfaceHoverBg : root.journalSubSurfaceBg)
                                        border.width: 1
                                        border.color: active ? root.accentColor : root.borderSubtle

                                        ColumnLayout {
                                            anchors.centerIn: parent
                                            spacing: 1
                                            MaterialSymbol {
                                                Layout.alignment: Qt.AlignHCenter
                                                text: modelData.icon
                                                iconSize: 15
                                                color: active ? root.accentColor : root.textSecondary
                                            }
                                            Text {
                                                Layout.alignment: Qt.AlignHCenter
                                                text: modelData.label
                                                font.pixelSize: 8
                                                font.weight: active ? Font.Bold : Font.Medium
                                                color: active ? root.textStrong : root.textMuted
                                            }
                                        }
                                        MouseArea {
                                            id: moodOptMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (!root.service)
                                                    return;
                                                const nextMood = active ? "" : moodValue;
                                                root.service.updateNoteFrontmatter({ "mood": nextMood });
                                            }
                                        }
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Text { text: "Energy"; font.pixelSize: 10; font.weight: Font.DemiBold; color: root.textSecondary }
                                Item { Layout.fillWidth: true }
                                Text {
                                    objectName: "nexusJournalEnergyValueLabel"
                                    text: root.journalEnergyDisplayLabel(root.jView.energy)
                                    font.pixelSize: 10
                                    font.family: Appearance.font.family.monospace
                                    color: root.journalCanonicalEnergy(root.jView.energy).length > 0 ? root.accentColor : root.textMuted
                                }
                            }

                            RowLayout {
                                id: journalEnergyRow
                                objectName: "nexusJournalEnergyRow"
                                Layout.fillWidth: true
                                spacing: 4
                                Repeater {
                                    model: root.journalEnergyOptions
                                    delegate: Rectangle {
                                        required property var modelData
                                        required property int index
                                        objectName: "nexusJournalEnergyOption_" + String(index)
                                        readonly property string energyValue: String(modelData.value)
                                        readonly property string energyLabel: String(modelData.label)
                                        readonly property int scaleOrder: index + 1
                                        readonly property bool active: root.journalCanonicalEnergy(root.jView.energy) === energyValue
                                        Layout.fillWidth: true
                                        implicitHeight: 38
                                        radius: 5
                                        color: active
                                            ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.22)
                                            : (energyOptMouse.containsMouse ? root.journalSubSurfaceHoverBg : root.journalSubSurfaceBg)
                                        border.width: 1
                                        border.color: active ? root.accentColor : root.borderSubtle

                                        ColumnLayout {
                                            anchors.centerIn: parent
                                            spacing: 1
                                            MaterialSymbol {
                                                Layout.alignment: Qt.AlignHCenter
                                                text: modelData.icon
                                                iconSize: 15
                                                color: active ? root.accentColor : root.textSecondary
                                            }
                                            Text {
                                                Layout.alignment: Qt.AlignHCenter
                                                text: modelData.label
                                                font.pixelSize: 8
                                                font.weight: active ? Font.Bold : Font.Medium
                                                color: active ? root.textStrong : root.textMuted
                                            }
                                        }
                                        MouseArea {
                                            id: energyOptMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (!root.service)
                                                    return;
                                                const nextEnergy = active ? "" : energyValue;
                                                root.service.updateNoteFrontmatter({ "energy": nextEnergy });
                                            }
                                        }
                                    }
                                }
                            }

                            OrnamentalDivider {}

                            // WEATHER (Synchronized with Alis Weather Service)
                            RowLayout {
                                Layout.fillWidth: true
                                Text { text: "WEATHER"; font.pixelSize: 9; font.weight: Font.Bold; font.letterSpacing: 1.5; color: root.accentColor }
                                Item { Layout.fillWidth: true }
                                Rectangle {
                                    id: weatherAutoBtn
                                    objectName: "nexusJournalWeatherAutoButton"
                                    radius: 4
                                    color: wAutoMouse.containsMouse ? root.journalSubSurfaceHoverBg : root.journalSubSurfaceBg
                                    border.width: 1
                                    border.color: root.borderAccent
                                    implicitWidth: wAutoTxt.implicitWidth + 10
                                    implicitHeight: 18
                                    Text {
                                        id: wAutoTxt
                                        anchors.centerIn: parent
                                        text: "↻ Auto"
                                        font.pixelSize: 9
                                        color: root.accentColor
                                    }
                                    MouseArea {
                                        id: wAutoMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (root.service)
                                                root.service.fetchWeatherForCurrentJournal();
                                        }
                                    }
                                }
                            }

                            TextField {
                                id: journalWeatherField
                                objectName: "nexusJournalWeatherField"
                                Layout.fillWidth: true
                                implicitHeight: 26
                                text: String(root.jView.weather || root.service?.alisWeatherSummary || "")
                                placeholderText: "Weather not recorded"
                                placeholderTextColor: root.textMuted
                                font.pixelSize: 11
                                color: root.textPrimary
                                background: Rectangle {
                                    objectName: "nexusJournalWeatherFieldBg"
                                    radius: 5
                                    color: root.journalSubSurfaceBg
                                    border.width: 1
                                    border.color: parent.activeFocus ? root.accentColor : root.borderSubtle
                                }
                                onAccepted: root.restoreWorkspaceFocus()
                                Keys.onEscapePressed: event => {
                                    root.restoreWorkspaceFocus();
                                    event.accepted = true;
                                }
                                Keys.onPressed: event => root.forwardWorkspaceShortcut(event)
                                onEditingFinished: {
                                    if (root.service && text !== String(root.jView.weather ?? ""))
                                        root.service.updateNoteFrontmatter({ "weather": text });
                                }
                            }

                            OrnamentalDivider {}

                            // TAGS
                            Text { text: "TAGS"; font.pixelSize: 9; font.weight: Font.Bold; font.letterSpacing: 1.5; color: root.accentColor }
                            Flow {
                                Layout.fillWidth: true
                                spacing: 5
                                Repeater {
                                    model: (root.doc?.tags ?? []).length > 0 ? root.doc.tags : ["Daily-notes"]
                                    delegate: Rectangle {
                                        required property string modelData
                                        objectName: "nexusJournalTagChip"
                                        radius: 4
                                        color: root.journalSubSurfaceBg
                                        border.width: 1
                                        border.color: root.borderAccent
                                        implicitWidth: jTagTxt.implicitWidth + 10
                                        implicitHeight: 20
                                        Text {
                                            id: jTagTxt
                                            anchors.centerIn: parent
                                            text: "#" + modelData.replace(/^#+/, "")
                                            font.pixelSize: 9
                                            color: root.accentColor
                                        }
                                    }
                                }
                            }

                            OrnamentalDivider {}

                            // REFLECTION (Reading mode default, click to edit)
                            Text { text: "DAILY REFLECTION"; font.pixelSize: 9; font.weight: Font.Bold; font.letterSpacing: 1.5; color: root.accentColor }
                            Rectangle {
                                id: journalReflectionCard
                                objectName: "nexusJournalReflectionCard"
                                visible: !root.journalEditingReflection
                                Layout.fillWidth: true
                                implicitHeight: Math.max(28, reflectionReadTxt.implicitHeight + 12)
                                radius: 5
                                color: reflCardMouse.containsMouse ? root.journalSubSurfaceHoverBg : root.journalSubSurfaceBg
                                border.width: 1
                                border.color: root.borderSubtle
                                Text {
                                    id: reflectionReadTxt
                                    anchors.fill: parent
                                    anchors.margins: 6
                                    readonly property bool hasRefl: String(root.jView.reflection ?? "").trim().length > 0
                                    text: hasRefl ? ("“" + String(root.jView.reflection) + "”") : "One sentence for today — click to edit"
                                    font.pixelSize: 11
                                    font.italic: true
                                    color: hasRefl ? root.textPrimary : root.textMuted
                                    wrapMode: Text.Wrap
                                }
                                MouseArea {
                                    id: reflCardMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        reflectionField.text = String(root.jView.reflection ?? "");
                                        root.journalEditingReflection = true;
                                    }
                                }
                            }
                            TextField {
                                id: reflectionField
                                visible: root.journalEditingReflection
                                Layout.fillWidth: true
                                implicitHeight: 28
                                text: String(root.jView.reflection ?? "")
                                placeholderText: "One sentence for today"
                                placeholderTextColor: root.textMuted
                                font.pixelSize: 11
                                font.italic: true
                                color: root.textPrimary
                                background: Rectangle {
                                    radius: 5
                                    color: root.journalSubSurfaceBg
                                    border.width: 1
                                    border.color: parent.activeFocus ? root.accentColor : root.borderSubtle
                                }
                                onVisibleChanged: {
                                    if (visible)
                                        forceActiveFocus();
                                }
                                Keys.onEscapePressed: event => {
                                    root.journalEditingReflection = false;
                                    root.restoreWorkspaceFocus();
                                    event.accepted = true;
                                }
                                Keys.onPressed: event => root.forwardWorkspaceShortcut(event)
                                onAccepted: {
                                    if (root.service && text !== String(root.jView.reflection ?? ""))
                                        root.service.updateNoteFrontmatter({ "reflection": text });
                                    root.journalEditingReflection = false;
                                    root.restoreWorkspaceFocus();
                                }
                                onEditingFinished: {
                                    if (root.service && text !== String(root.jView.reflection ?? ""))
                                        root.service.updateNoteFrontmatter({ "reflection": text });
                                    root.journalEditingReflection = false;
                                }
                            }

                            OrnamentalDivider {}

                            // HEALTH: Editable Weight (`Mục cân nặng của Journal`)
                            RowLayout {
                                Layout.fillWidth: true
                                Text { text: "HEALTH · WEIGHT"; font.pixelSize: 9; font.weight: Font.Bold; font.letterSpacing: 1.5; color: root.accentColor }
                                Item { Layout.fillWidth: true }
                                Rectangle {
                                    id: weightEditBtn
                                    objectName: "nexusJournalWeightEditButton"
                                    visible: !root.journalEditingWeight
                                    radius: 4
                                    color: weightEditBtnMouse.containsMouse ? root.journalSubSurfaceHoverBg : root.journalSubSurfaceBg
                                    border.width: 1
                                    border.color: root.borderAccent
                                    implicitWidth: wEditBtnLbl.implicitWidth + 10
                                    implicitHeight: 18
                                    Text {
                                        id: wEditBtnLbl
                                        anchors.centerIn: parent
                                        text: String(root.jView.weight ?? "").length > 0 ? "✎ Edit" : "+ Log weight"
                                        font.pixelSize: 9
                                        color: root.accentColor
                                    }
                                    MouseArea {
                                        id: weightEditBtnMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            weightInputField.text = root.journalEffectiveWeight;
                                            root.journalEditingWeight = true;
                                        }
                                    }
                                }
                            }

                            // Weight Reading Card (click to edit)
                            Rectangle {
                                id: journalWeightCard
                                objectName: "nexusJournalWeightCard"
                                visible: !root.journalEditingWeight
                                Layout.fillWidth: true
                                implicitHeight: 42
                                radius: 6
                                color: weightCardMouse.containsMouse ? root.journalSubSurfaceHoverBg : root.journalSubSurfaceBg
                                border.width: 1
                                border.color: weightCardMouse.containsMouse ? root.accentColor : root.borderSubtle

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    spacing: 8
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 1
                                        Text {
                                            objectName: "nexusJournalWeightValueLabel"
                                            text: root.journalEffectiveWeight.length > 0 ? (root.journalEffectiveWeight + " kg") : "— kg"
                                            font.pixelSize: 14
                                            font.weight: Font.Bold
                                            color: root.textPrimary
                                        }
                                        Text {
                                            text: root.journalEffectiveWeight.length > 0 ? "Weight logged · click to update" : "Click to enter weight (kg)"
                                            font.pixelSize: 9
                                            color: root.textMuted
                                        }
                                    }
                                    Text {
                                        text: "kg"
                                        font.pixelSize: 10
                                        font.family: Appearance.font.family.monospace
                                        color: root.accentColor
                                    }
                                }

                                MouseArea {
                                    id: weightCardMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        weightInputField.text = root.journalEffectiveWeight;
                                        root.journalEditingWeight = true;
                                    }
                                }
                            }

                            // Weight Inline Editor
                            RowLayout {
                                visible: root.journalEditingWeight
                                Layout.fillWidth: true
                                spacing: 6

                                TextField {
                                    id: weightInputField
                                    objectName: "nexusJournalWeightInput"
                                    property bool _cancelingWeight: false
                                    Layout.fillWidth: true
                                    implicitHeight: 30
                                    text: root.journalEffectiveWeight
                                    placeholderText: "e.g. 68.5"
                                    placeholderTextColor: root.textMuted
                                    font.pixelSize: 12
                                    font.family: Appearance.font.family.monospace
                                    color: root.textPrimary
                                    background: Rectangle {
                                        radius: 5
                                        color: root.journalSubSurfaceBg
                                        border.width: 1
                                        border.color: parent.activeFocus ? root.accentColor : root.borderSubtle
                                    }
                                    onVisibleChanged: {
                                        if (visible) {
                                            _cancelingWeight = false;
                                            Qt.callLater(() => {
                                                if (weightInputField.visible) {
                                                    weightInputField.forceActiveFocus();
                                                    weightInputField.selectAll();
                                                }
                                            });
                                        }
                                    }
                                    function commitWeight() {
                                        if (!root.journalEditingWeight || _cancelingWeight)
                                            return;
                                        const cleaned = String(weightInputField.text ?? "").replace(/kg/gi, "").replace(/,/g, ".").trim();
                                        root.journalWeightOverride = cleaned;
                                        root.journalWeightHasOverride = true;
                                        root.journalEditingWeight = false;
                                        root.restoreWorkspaceFocus();
                                        if (!root.service)
                                            return;
                                        if (cleaned.length === 0) {
                                            root.service.updateNoteFrontmatter({ "weight": "" });
                                        } else {
                                            const numVal = Number(cleaned);
                                            root.service.updateNoteFrontmatter({ "weight": Number.isFinite(numVal) ? numVal : cleaned });
                                        }
                                    }
                                    onActiveFocusChanged: {
                                        if (!activeFocus && visible && root.journalEditingWeight && root.noteKind === "journal" && !_cancelingWeight && !weightCancelMouse.containsMouse && !weightCancelMouse.pressed) {
                                            commitWeight();
                                        }
                                    }
                                    Keys.onEscapePressed: event => {
                                        commitWeight();
                                        event.accepted = true;
                                    }
                                    Keys.onPressed: event => root.forwardWorkspaceShortcut(event)
                                    onAccepted: commitWeight()
                                }

                                Rectangle {
                                    objectName: "nexusJournalWeightSaveButton"
                                    radius: 5
                                    color: root.accentColor
                                    implicitWidth: 46
                                    implicitHeight: 30
                                    Text {
                                        anchors.centerIn: parent
                                        text: "Save"
                                        font.pixelSize: 10
                                        font.weight: Font.Bold
                                        color: root.onAccentColor
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: weightInputField.commitWeight()
                                    }
                                }

                                Rectangle {
                                    objectName: "nexusJournalWeightCancelButton"
                                    radius: 5
                                    color: root.journalSubSurfaceBg
                                    border.width: 1
                                    border.color: root.borderSubtle
                                    implicitWidth: 48
                                    implicitHeight: 30
                                    Text {
                                        anchors.centerIn: parent
                                        text: "Cancel"
                                        font.pixelSize: 10
                                        color: root.textSecondary
                                    }
                                    MouseArea {
                                        id: weightCancelMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            weightInputField._cancelingWeight = true;
                                            root.journalEditingWeight = false;
                                            weightInputField._cancelingWeight = false;
                                        }
                                    }
                                }
                            }

                            OrnamentalDivider {}

                            // ON THIS DAY
                            Text { text: "ON THIS DAY"; font.pixelSize: 9; font.weight: Font.Bold; font.letterSpacing: 1.5; color: root.accentColor }
                            Text {
                                visible: (root.jView.onThisDay ?? []).length === 0
                                Layout.fillWidth: true
                                text: "No memories on this date in other years."
                                font.pixelSize: 10
                                font.italic: true
                                color: root.textMuted
                                wrapMode: Text.Wrap
                            }
                            Repeater {
                                model: root.jView.onThisDay ?? []
                                delegate: Rectangle {
                                    required property var modelData
                                    objectName: "nexusJournalOnThisDayCard"
                                    Layout.fillWidth: true
                                    implicitHeight: otdCol.implicitHeight + 10
                                    radius: 5
                                    color: otdMouse.containsMouse ? root.journalSubSurfaceHoverBg : root.journalSubSurfaceBg
                                    border.width: 1
                                    border.color: root.borderSubtle
                                    ColumnLayout {
                                        id: otdCol
                                        anchors.fill: parent
                                        anchors.margins: 6
                                        spacing: 2
                                        Text { text: String(modelData.title ?? ""); font.pixelSize: 10; font.weight: Font.Bold; color: root.accentColor }
                                        Text {
                                            objectName: "nexusJournalOnThisDaySnippet"
                                            text: root.stripPlainMarkdown(modelData.snippet)
                                            font.pixelSize: 9
                                            color: root.textSecondary
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }
                                    }
                                    MouseArea {
                                        id: otdMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (root.service && modelData.relPath)
                                                root.service.openFile(String(modelData.relPath), true);
                                        }
                                    }
                                }
                            }

                            OrnamentalDivider {}

                            // ARCHIVE
                            Text { text: "ARCHIVE"; font.pixelSize: 9; font.weight: Font.Bold; font.letterSpacing: 1.5; color: root.accentColor }
                            RowLayout {
                                Layout.fillWidth: true
                                Text { text: "Month"; font.pixelSize: 10; color: root.textMuted }
                                Item { Layout.fillWidth: true }
                                Text { text: String(root.jView.monthName ?? ""); font.pixelSize: 10; color: root.textPrimary }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                Text { text: "Day"; font.pixelSize: 10; color: root.textMuted }
                                Item { Layout.fillWidth: true }
                                Text { text: String(root.jView.weekday ?? ""); font.pixelSize: 10; color: root.textPrimary }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                Text { text: "YEAR PROGRESS"; font.pixelSize: 9; font.weight: Font.Bold; color: root.textMuted }
                                Item { Layout.fillWidth: true }
                                Text { text: String(root.jView.yearProgress ?? 0) + "%"; font.pixelSize: 9; font.family: Appearance.font.family.monospace; color: root.accentColor }
                            }
                            Rectangle {
                                id: journalYearProgressTrack
                                objectName: "nexusJournalYearProgressTrack"
                                Layout.fillWidth: true
                                implicitHeight: 4
                                radius: 2
                                color: root.journalSubSurfaceBg
                                Rectangle {
                                    width: parent.width * Math.max(0, Math.min(1, Number(root.jView.yearProgress ?? 0) / 100.0))
                                    height: parent.height
                                    radius: 2
                                    color: root.accentColor
                                }
                            }
                        }
                    }
                }
            }
        }

        // =====================================================================
        // 3. CORNELL NOTE CUSTOM VIEW (`Custom_Views/Cornell/Cornell.{html,js,css}`)
        // =====================================================================
        Rectangle {
            id: cornellCustomView
            objectName: "nexusCornellCustomView"
            Layout.minimumWidth: 0
            visible: root.noteKind === "cornell"
            Layout.fillWidth: true
            implicitHeight: Math.max(root.minDocumentSurfaceHeight, cornellMainCol.implicitHeight + 36)
            radius: 10
            color: root.cardBg
            border.width: 1
            border.color: root.borderAccent

            readonly property string courseText: String(root.cView.course || root.cView.context || root.dossier.course || "")
            readonly property string topicText: String(root.cView.topic || root.dossier.topic || "")
            readonly property string dateText: String(root.cView.date || root.dossier.date || "—")
            readonly property string statusText: String(root.cView.status || root.doc?.frontmatter?.status || "Draft").replace(/^#/, "")
            readonly property string noteTypeText: String(root.cView.noteType || "Cornell")

            ColumnLayout {
                id: cornellMainCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 18
                spacing: 14

                // ── 3.1 Header (`cv-cornell-header`: Heading Left + Metadata & Study Mode Right) ──
                GridLayout {
                    id: cornellHeaderGrid
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    columns: width >= 600 ? 2 : 1
                    columnSpacing: 16
                    rowSpacing: 14

                    // Left: `.cv-cornell-heading`
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignTop
                        spacing: 5

                        Text {
                            text: "CORNELL STUDY SHEET"
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: 11
                            font.weight: Font.Bold
                            font.letterSpacing: 1.8
                            color: root.accentColor
                        }

                        Text {
                            objectName: "nexusCornellTitleLabel"
                            Layout.fillWidth: true
                            text: String(root.doc?.title || root.dossier.title || "Untitled Study Sheet")
                            font.pixelSize: 24
                            font.weight: Font.Bold
                            color: root.textStrong
                            wrapMode: Text.Wrap
                        }

                        Text {
                            objectName: "nexusCornellCourseSubtitle"
                            Layout.fillWidth: true
                            text: {
                                if (cornellCustomView.courseText.length > 0 && cornellCustomView.topicText.length > 0 && cornellCustomView.courseText !== cornellCustomView.topicText)
                                    return cornellCustomView.courseText + "  ·  " + cornellCustomView.topicText;
                                if (cornellCustomView.courseText.length > 0)
                                    return cornellCustomView.courseText;
                                if (cornellCustomView.topicText.length > 0)
                                    return cornellCustomView.topicText;
                                return "Active recall · structured cues · concise synthesis";
                            }
                            font.pixelSize: 13
                            color: root.textSecondary
                            wrapMode: Text.Wrap
                        }
                    }

                    // Right: `.cv-cornell-meta` (4-cell metadata grid + Study mode toggle button)
                    ColumnLayout {
                        Layout.alignment: Qt.AlignTop
                        Layout.preferredWidth: 288
                        Layout.minimumWidth: 0
                        Layout.fillWidth: cornellHeaderGrid.columns === 1
                        spacing: 8

                        GridLayout {
                            Layout.fillWidth: true
                            columns: 2
                            columnSpacing: 8
                            rowSpacing: 6

                            // Date
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 42
                                radius: 6
                                color: root.cardDeepBg
                                border.width: 1
                                border.color: root.borderSubtle
                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 6
                                    spacing: 1
                                    Text { text: "DATE"; font.family: Appearance.font.family.monospace; font.pixelSize: 9; font.weight: Font.Bold; color: root.textMuted }
                                    Text { text: cornellCustomView.dateText.length > 0 ? cornellCustomView.dateText : "—"; font.family: Appearance.font.family.monospace; font.pixelSize: 12; color: root.textPrimary; elide: Text.ElideRight }
                                }
                            }

                            // Context / Course (clickable to follow course wikilink)
                            Rectangle {
                                objectName: "nexusCornellContextCell"
                                Layout.fillWidth: true
                                implicitHeight: 42
                                radius: 6
                                color: cornellContextMouse.containsMouse && cornellCustomView.courseText.length > 0 ? root.cardHoverBg : root.cardDeepBg
                                border.width: 1
                                border.color: cornellContextMouse.containsMouse && cornellCustomView.courseText.length > 0 ? root.accentColor : root.borderSubtle
                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 6
                                    spacing: 1
                                    Text { text: "CONTEXT"; font.family: Appearance.font.family.monospace; font.pixelSize: 9; font.weight: Font.Bold; color: root.textMuted }
                                    Text {
                                        Layout.fillWidth: true
                                        text: cornellCustomView.courseText.length > 0 ? cornellCustomView.courseText : (cornellCustomView.topicText.length > 0 ? cornellCustomView.topicText : "General")
                                        font.family: Appearance.font.family.monospace
                                        font.pixelSize: 12
                                        font.weight: Font.DemiBold
                                        color: cornellCustomView.courseText.length > 0 ? root.accentColor : root.textPrimary
                                        elide: Text.ElideRight
                                    }
                                }
                                MouseArea {
                                    id: cornellContextMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    enabled: cornellCustomView.courseText.length > 0
                                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: {
                                        if (root.service && cornellCustomView.courseText.length > 0)
                                            root.service.followWikilink(cornellCustomView.courseText);
                                    }
                                }
                            }

                            // Status (clickable to cycle Draft -> Review -> Mastered)
                            Rectangle {
                                objectName: "nexusCornellStatusBadge"
                                Layout.fillWidth: true
                                implicitHeight: 42
                                radius: 6
                                color: cornellStatusMouse.containsMouse ? root.cardHoverBg : root.cardDeepBg
                                border.width: 1
                                border.color: cornellStatusMouse.containsMouse ? root.accentColor : root.borderSubtle
                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 6
                                    spacing: 1
                                    Text { text: "STATUS"; font.family: Appearance.font.family.monospace; font.pixelSize: 9; font.weight: Font.Bold; color: root.textMuted }
                                    Text {
                                        text: cornellCustomView.statusText
                                        font.family: Appearance.font.family.monospace
                                        font.pixelSize: 12
                                        font.weight: Font.Bold
                                        color: root.accentColor
                                        elide: Text.ElideRight
                                    }
                                }
                                MouseArea {
                                    id: cornellStatusMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (!root.service)
                                            return;
                                        const cur = cornellCustomView.statusText.toLowerCase();
                                        const next = cur.indexOf("draft") >= 0 ? "Review" : (cur.indexOf("review") >= 0 ? "Mastered" : "Draft");
                                        root.service.updateNoteFrontmatter({ "status": next });
                                    }
                                }
                            }

                            // Type
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 42
                                radius: 6
                                color: root.cardDeepBg
                                border.width: 1
                                border.color: root.borderSubtle
                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 6
                                    spacing: 1
                                    Text { text: "TYPE"; font.family: Appearance.font.family.monospace; font.pixelSize: 9; font.weight: Font.Bold; color: root.textMuted }
                                    Text { text: cornellCustomView.noteTypeText; font.family: Appearance.font.family.monospace; font.pixelSize: 12; color: root.textPrimary; elide: Text.ElideRight }
                                }
                            }
                        }

                        // `.cv-cornell-study-btn` (Active Recall Study Mode toggle)
                        Rectangle {
                            id: cornellStudyModeBtn
                            objectName: "nexusCornellStudyModeButton"
                            Layout.fillWidth: true
                            implicitHeight: 32
                            radius: 6
                            color: root.cornellStudyMode ? root.accentColor : (cornellStudyMouse.containsMouse ? root.cardHoverBg : root.cardRaisedBg)
                            border.width: 1
                            border.color: root.cornellStudyMode ? root.accentColor : root.borderAccent

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 6
                                MaterialSymbol {
                                    text: root.cornellStudyMode ? "visibility_off" : "psychology"
                                    iconSize: 15
                                    color: root.cornellStudyMode ? root.onAccentColor : root.accentColor
                                }
                                Text {
                                    text: root.cornellStudyMode ? "Study mode · On (Recall)" : "Study mode"
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: 12
                                    font.weight: Font.Bold
                                    color: root.cornellStudyMode ? root.onAccentColor : root.accentColor
                                }
                            }
                            MouseArea {
                                id: cornellStudyMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.cornellStudyMode = !root.cornellStudyMode;
                                    root.cornellRevealedRows = ({});
                                }
                            }
                        }
                    }
                }

                OrnamentalDivider {}

                // ── 3.2 Learning Objectives Banner (when present) ──
                Rectangle {
                    visible: (root.cView.objectives ?? []).length > 0
                    Layout.fillWidth: true
                    implicitHeight: objCol.implicitHeight + 20
                    radius: 7
                    color: root.cardSubtleBg
                    border.width: 1
                    border.color: root.borderSubtle

                    ColumnLayout {
                        id: objCol
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 4
                        Text {
                            text: "LEARNING OBJECTIVES"
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: 10
                            font.weight: Font.Bold
                            font.letterSpacing: 1.4
                            color: root.accentColor
                        }
                        Repeater {
                            model: root.cView.objectives ?? []
                            delegate: Text {
                                required property var modelData
                                Layout.fillWidth: true
                                text: root.renderInlineMarkdownHtml("• " + String(modelData ?? ""))
                                textFormat: Text.RichText
                                font.pixelSize: 13
                                color: root.textPrimary
                                wrapMode: Text.Wrap
                                onLinkActivated: link => {
                                    if (root.service && link.startsWith("wikilink:"))
                                        root.service.followWikilink(decodeURIComponent(link.substring(9)));
                                }
                            }
                        }
                    }
                }

                // ── 3.3 Marginalia Cue Filter Bar ──
                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: [
                            { "id": "ALL", "label": "All Cues (" + String((root.cView.cues ?? []).length) + ")" },
                            { "id": "CORNELL_QUESTION", "label": "? Question" },
                            { "id": "CORNELL_IMPORTANT", "label": "! Important" },
                            { "id": "CORNELL_KEYPOINT", "label": "• Key Point" },
                            { "id": "CORNELL_EXAMPLE", "label": "E Example" },
                            { "id": "CORNELL_VERIFIED", "label": "✓ Verified" },
                            { "id": "CORNELL_MISTAKE", "label": "✕ Mistake" },
                            { "id": "CORNELL_RELATED", "label": "↗ Related" },
                            { "id": "CORNELL_FEYNMAN", "label": "★ Feynman" }
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            readonly property bool active: root.cornellTypeFilter === modelData.id
                            radius: 5
                            color: active ? root.accentColor : root.cardRaisedBg
                            border.width: 1
                            border.color: active ? root.accentColor : root.borderSubtle
                            implicitWidth: cfLbl.implicitWidth + 14
                            implicitHeight: 24
                            Text {
                                id: cfLbl
                                anchors.centerIn: parent
                                text: modelData.label
                                font.family: Appearance.font.family.monospace
                                font.pixelSize: 11
                                font.weight: active ? Font.Bold : Font.Medium
                                color: active ? root.onAccentColor : root.textSecondary
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.cornellTypeFilter = modelData.id
                            }
                        }
                    }
                }

                // ── 3.4 Cornell Split Sheet (`cv-cornell-sheet`: 30% Cues & Questions / 70% Notes & Explanations) ──
                Rectangle {
                    id: cornellSheetCard
                    objectName: "nexusCornellSheetCard"
                    Layout.fillWidth: true
                    implicitHeight: Math.max(240, root.minDocumentSurfaceHeight - 280, cornellRowsCol.implicitHeight + 28)
                    radius: 8
                    color: root.cardDeepBg
                    border.width: 1
                    border.color: root.borderSubtle

                    ColumnLayout {
                        id: cornellRowsCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 14
                        spacing: 10

                        readonly property bool stackedCues: width < 560
                        readonly property int cueColWidth: stackedCues ? Math.max(0, width - 24) : Math.max(176, Math.min(280, Math.round((width - 57) * ((Number(root.cView.cueWidth) || 30) / 100.0))))

                        // `.cv-cornell-col-head` (aligned with the 30% / 70% column split inside each cue row card)
                        GridLayout {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            Layout.leftMargin: 12
                            Layout.rightMargin: 12
                            columns: cornellRowsCol.stackedCues ? 1 : 3
                            columnSpacing: 16
                            rowSpacing: 8

                            RowLayout {
                                Layout.fillWidth: false
                                Layout.preferredWidth: cornellRowsCol.cueColWidth
                                Layout.minimumWidth: cornellRowsCol.cueColWidth
                                Layout.maximumWidth: cornellRowsCol.cueColWidth
                                spacing: 8
                                Text {
                                    text: "CUES & QUESTIONS"
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: 11
                                    font.weight: Font.Bold
                                    font.letterSpacing: 1.4
                                    color: root.accentColor
                                }
                                Rectangle {
                                    radius: 4
                                    color: root.cardRaisedBg
                                    implicitWidth: cueCountPillTxt.implicitWidth + 10
                                    implicitHeight: 19
                                    Text {
                                        id: cueCountPillTxt
                                        anchors.centerIn: parent
                                        text: String((root.cView.cues ?? []).length)
                                        font.family: Appearance.font.family.monospace
                                        font.pixelSize: 11
                                        font.weight: Font.Bold
                                        color: root.accentColor
                                    }
                                }
                                Item { Layout.fillWidth: true }
                            }

                            Rectangle {
                                objectName: "nexusCornellColHeadDivider"
                                Layout.fillWidth: cornellRowsCol.stackedCues
                                Layout.preferredWidth: 1
                                implicitHeight: cornellRowsCol.stackedCues ? 1 : 16
                                color: root.borderAccent
                            }

                            GridLayout {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                columns: width >= 440 ? 3 : 1
                                rowSpacing: 6
                                Layout.preferredWidth: cornellRowsCol.stackedCues ? cornellRowsCol.cueColWidth : Math.max(220, cornellRowsCol.width - cornellRowsCol.cueColWidth - 57)
                                Text {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    wrapMode: Text.Wrap
                                    text: "NOTES & EXPLANATIONS"
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: 11
                                    font.weight: Font.Bold
                                    font.letterSpacing: 1.4
                                    color: root.textSecondary
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    wrapMode: Text.Wrap
                                    text: root.editingNoteBody ? "Editing · Esc to finish" : "Click to edit · Markdown supported"
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: 11
                                    color: root.editingNoteBody ? root.accentColor : root.textMuted
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (root.editingNoteBody) {
                                                if (root.service)
                                                    root.service.saveNoteBodyMarkdown(cornellBodyEditor.text);
                                                root.editingNoteBody = false;
                                            } else {
                                                cornellBodyEditor.text = root.service ? root.service.getNoteBodyMarkdown() : "";
                                                root.editingNoteBody = true;
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: root.borderAccent }

                        // `.cv-cornell-rows`
                        Repeater {
                            id: cornellCueRepeater
                            model: {
                                const all = root.cView.cues ?? [];
                                if (root.cornellTypeFilter === "ALL")
                                    return all;
                                return all.filter(c => {
                                    const t = String(c.type ?? "");
                                    if (root.cornellTypeFilter === "CORNELL_KEYPOINT")
                                        return t === "CORNELL_KEYPOINT" || t === "CORNELL_KEY";
                                    if (root.cornellTypeFilter === "CORNELL_VERIFIED")
                                        return t === "CORNELL_VERIFIED" || t === "CORNELL_VOCAB";
                                    if (root.cornellTypeFilter === "CORNELL_MISTAKE")
                                        return t === "CORNELL_MISTAKE" || t === "CORNELL_REF";
                                    if (root.cornellTypeFilter === "CORNELL_RELATED")
                                        return t === "CORNELL_RELATED" || t === "CORNELL_RESEARCH";
                                    if (root.cornellTypeFilter === "CORNELL_FEYNMAN")
                                        return t === "CORNELL_FEYNMAN" || t === "CORNELL_GENERAL";
                                    return t === root.cornellTypeFilter;
                                });
                            }
                            delegate: Rectangle {
                                id: cornellRowCard
                                required property var modelData
                                required property int index
                                objectName: "nexusCornellRow_" + String(index)
                                readonly property bool isHiddenForRecall: root.cornellStudyMode && !Boolean(root.cornellRevealedRows[index])
                                readonly property color cueAccent: root.cornellCueAccentColor(modelData.type)
                                Layout.fillWidth: true
                                implicitHeight: Math.max(68, cornellCueGrid.implicitHeight + 24)
                                radius: 7
                                color: root.cardBg
                                border.width: 1
                                border.color: root.borderSubtle

                                // Semantic 3px left accent bar matching `Cornell.css`
                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    anchors.topMargin: 8
                                    anchors.bottomMargin: 8
                                    width: 3
                                    radius: 2
                                    color: cornellRowCard.cueAccent
                                }

                                GridLayout {
                                    id: cornellCueGrid
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    columns: cornellRowsCol.stackedCues ? 1 : 3
                                    columnSpacing: 16
                                    rowSpacing: 12

                                    // Left 30%: `.cv-cornell-cue-cell`
                                    ColumnLayout {
                                        id: cueLeftCol
                                        objectName: "nexusCornellCueLeftCol_" + String(cornellRowCard.index)
                                        Layout.fillWidth: false
                                        Layout.preferredWidth: cornellRowsCol.cueColWidth
                                        Layout.minimumWidth: cornellRowsCol.cueColWidth
                                        Layout.maximumWidth: cornellRowsCol.cueColWidth
                                        Layout.alignment: Qt.AlignTop
                                        spacing: 6

                                        RowLayout {
                                            Layout.fillWidth: true
                                            Layout.maximumWidth: cornellRowsCol.cueColWidth
                                            spacing: 6
                                            Rectangle {
                                                width: 22
                                                height: 22
                                                radius: 5
                                                color: Qt.rgba(cornellRowCard.cueAccent.r, cornellRowCard.cueAccent.g, cornellRowCard.cueAccent.b, 0.18)
                                                border.width: 1
                                                border.color: cornellRowCard.cueAccent
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: String(modelData.marker || "•")
                                                    font.family: Appearance.font.family.monospace
                                                    font.pixelSize: 11
                                                    font.weight: Font.Bold
                                                    color: cornellRowCard.cueAccent
                                                }
                                            }
                                            Text {
                                                Layout.fillWidth: true
                                                text: String(modelData.label || String(modelData.type ?? "CUE").replace("CORNELL_", "")).toUpperCase()
                                                font.family: Appearance.font.family.monospace
                                                font.pixelSize: 10
                                                font.weight: Font.Bold
                                                font.letterSpacing: 1.1
                                                color: cornellRowCard.cueAccent
                                                elide: Text.ElideRight
                                            }
                                        }

                                        Text {
                                            objectName: "nexusCornellCuePrompt_" + String(cornellRowCard.index)
                                            Layout.fillWidth: true
                                            Layout.preferredWidth: cornellRowsCol.cueColWidth
                                            Layout.maximumWidth: cornellRowsCol.cueColWidth
                                            readonly property string rawPrompt: String(modelData.title || modelData.cue || "Cue")
                                            text: {
                                                const _sig = root.themeSignature;
                                                const cHtml = String(modelData.cueRichHtml ?? "").trim();
                                                if (cHtml.length > 0)
                                                    return root.themeRichHtml(cHtml);
                                                return root.renderInlineMarkdownHtml(rawPrompt);
                                            }
                                            textFormat: Text.RichText
                                            font.pixelSize: 14
                                            font.weight: Font.DemiBold
                                            lineHeight: 1.32
                                            color: root.textStrong
                                            wrapMode: Text.Wrap
                                            onLinkActivated: link => {
                                                if (root.service && link.startsWith("wikilink:"))
                                                    root.service.followWikilink(decodeURIComponent(link.substring(9)));
                                            }
                                        }
                                    }

                                    // Vertical Margin Divider
                                    Rectangle {
                                        objectName: "nexusCornellRowDivider_" + String(cornellRowCard.index)
                                        Layout.preferredWidth: 1
                                        Layout.preferredHeight: 1
                                        Layout.fillWidth: cornellRowsCol.stackedCues
                                        Layout.fillHeight: !cornellRowsCol.stackedCues
                                        color: root.borderAccent
                                    }

                                    // Right 70%: `.cv-cornell-note-cell`
                                    Item {
                                        id: cueRightContainer
                                        objectName: "nexusCornellCueRightContainer_" + String(cornellRowCard.index)
                                        Layout.fillWidth: true
                                        Layout.preferredWidth: cornellRowsCol.stackedCues ? cornellRowsCol.cueColWidth : Math.max(220, cornellRowCard.width - cornellRowsCol.cueColWidth - 57)
                                        Layout.minimumWidth: 0
                                        Layout.alignment: Qt.AlignTop
                                        implicitHeight: cornellRowCard.isHiddenForRecall ? 38 : Math.max(38, cueRightCol.implicitHeight)

                                        // Study Mode Recall Button (when hidden)
                                        Rectangle {
                                            objectName: "nexusCornellRevealButton_" + String(cornellRowCard.index)
                                            visible: cornellRowCard.isHiddenForRecall
                                            anchors.verticalCenter: parent.verticalCenter
                                            anchors.left: parent.left
                                            implicitWidth: revealBtnRow.implicitWidth + 18
                                            implicitHeight: 30
                                            radius: 6
                                            color: revealRowMouse.containsMouse ? root.cardHoverBg : root.cardRaisedBg
                                            border.width: 1
                                            border.color: root.borderAccent

                                            RowLayout {
                                                id: revealBtnRow
                                                anchors.centerIn: parent
                                                spacing: 6
                                                MaterialSymbol { text: "visibility"; iconSize: 14; color: root.accentColor }
                                                Text {
                                                    text: "Reveal explanation"
                                                    font.family: Appearance.font.family.monospace
                                                    font.pixelSize: 12
                                                    font.weight: Font.DemiBold
                                                    color: root.accentColor
                                                }
                                            }
                                            MouseArea {
                                                id: revealRowMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    const nextMap = Object.assign({}, root.cornellRevealedRows);
                                                    nextMap[cornellRowCard.index] = true;
                                                    root.cornellRevealedRows = nextMap;
                                                }
                                            }
                                        }

                                        // Rich HTML Explanation (Default or Revealed)
                                        ColumnLayout {
                                            id: cueRightCol
                                            visible: !cornellRowCard.isHiddenForRecall
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.top: parent.top
                                            spacing: 4

                                            Text {
                                                id: cueRightTxt
                                                objectName: "nexusCornellRowNoteText_" + String(cornellRowCard.index)
                                                Layout.fillWidth: true
                                                readonly property string rawNotes: String(modelData.notes ?? modelData.text ?? "").trim()
                                                readonly property string renderedHtml: {
                                                    const _sig = root.themeSignature;
                                                    const rHtml = String(modelData.richHtml ?? "").trim();
                                                    if (rHtml.length > 0 && !/(^|>|\n)\s*#{1,6}\s+/m.test(rHtml) && !/\[\[/.test(rHtml))
                                                        return root.themeRichHtml(rHtml);
                                                    if (rawNotes.length > 0)
                                                        return root.renderMarkdownBlocksHtml(rawNotes);
                                                    return "<span style='color:" + String(root.textMuted) + ";'><i>Click to add explanation or notes for this cue...</i></span>";
                                                }
                                                text: renderedHtml
                                                textFormat: Text.RichText
                                                font.pixelSize: 14
                                                lineHeight: 1.42
                                                color: root.textPrimary
                                                wrapMode: Text.Wrap
                                                onLinkActivated: link => {
                                                    if (root.service && link.startsWith("wikilink:"))
                                                        root.service.followWikilink(decodeURIComponent(link.substring(9)));
                                                    else if (link.startsWith("http://") || link.startsWith("https://"))
                                                        Qt.openUrlExternally(link);
                                                }
                                            }

                                            Rectangle {
                                                visible: root.cornellStudyMode && Boolean(root.cornellRevealedRows[cornellRowCard.index])
                                                radius: 4
                                                color: root.cardRaisedBg
                                                border.width: 1
                                                border.color: root.borderSubtle
                                                implicitWidth: 50
                                                implicitHeight: 22
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: "Hide"
                                                    font.family: Appearance.font.family.monospace
                                                    font.pixelSize: 10
                                                    color: root.textSecondary
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        const nextMap = Object.assign({}, root.cornellRevealedRows);
                                                        delete nextMap[cornellRowCard.index];
                                                        root.cornellRevealedRows = nextMap;
                                                    }
                                                }
                                            }
                                        }

                                        MouseArea {
                                            visible: !root.cornellStudyMode && !root.editingNoteBody
                                            anchors.fill: parent
                                            acceptedButtons: Qt.LeftButton
                                            cursorShape: Qt.IBeamCursor
                                            onClicked: mouse => {
                                                const linkAt = cueRightTxt.linkAt(mouse.x, mouse.y);
                                                if (linkAt && linkAt.length > 0) {
                                                    if (root.service && linkAt.startsWith("wikilink:"))
                                                        root.service.followWikilink(decodeURIComponent(linkAt.substring(9)));
                                                    else if (linkAt.startsWith("http://") || linkAt.startsWith("https://"))
                                                        Qt.openUrlExternally(linkAt);
                                                    return;
                                                }
                                                cornellBodyEditor.text = root.service ? root.service.getNoteBodyMarkdown() : "";
                                                root.editingNoteBody = true;
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Empty state when a cue filter has 0 matches
                        Rectangle {
                            visible: cornellCueRepeater.count === 0
                            Layout.fillWidth: true
                            implicitHeight: cornellEmptyRow.implicitHeight + 24
                            radius: 7
                            color: root.cardBg
                            border.width: 1
                            border.color: root.borderSubtle
                            RowLayout {
                                id: cornellEmptyRow
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 10
                                Text {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    wrapMode: Text.Wrap
                                    text: (root.cView.cues ?? []).length === 0 ? "No Cornell cues yet — click to add H3 cues (### ? Question, ### ! Key Concept)." : "No cues match this filter."
                                    font.pixelSize: 13
                                    color: root.textMuted
                                }
                                Rectangle {
                                    visible: root.cornellTypeFilter !== "ALL"
                                    radius: 4
                                    color: root.cardRaisedBg
                                    border.width: 1
                                    border.color: root.borderAccent
                                    implicitWidth: resetFilterTxt.implicitWidth + 14
                                    implicitHeight: 24
                                    Text {
                                        id: resetFilterTxt
                                        anchors.centerIn: parent
                                        text: "Show All"
                                        font.family: Appearance.font.family.monospace
                                        font.pixelSize: 11
                                        font.weight: Font.Bold
                                        color: root.accentColor
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.cornellTypeFilter = "ALL"
                                    }
                                }
                            }
                        }
                    }
                }

                // ── 3.5 Summary Callout + Click-to-Edit Study Sheet Editor (`cv-cornell-summary`) ──
                Rectangle {
                    objectName: "nexusCornellSummaryCard"
                    Layout.fillWidth: true
                    implicitHeight: cornellSumCol.implicitHeight + 24
                    radius: 8
                    color: root.cardRaisedBg
                    border.width: 1
                    border.color: root.editingNoteBody ? root.accentColor : root.borderAccent

                    ColumnLayout {
                        id: cornellSumCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 14
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "SUMMARY"
                                font.family: Appearance.font.family.monospace
                                font.pixelSize: 11
                                font.weight: Font.Bold
                                font.letterSpacing: 1.5
                                color: root.accentColor
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                wrapMode: Text.Wrap
                                text: root.editingNoteBody ? "Editing · Esc to finish" : "Key takeaway in 2–3 sentences · Click to edit"
                                font.family: Appearance.font.family.monospace
                                font.pixelSize: 11
                                color: root.editingNoteBody ? root.accentColor : root.textMuted
                            }
                        }

                        Item {
                            id: cornellReadingArea
                            objectName: "nexusCornellBodyReadingArea"
                            visible: !root.editingNoteBody
                            Layout.fillWidth: true
                            implicitHeight: Math.max(42, cornellSumTxt.implicitHeight + 10)

                            Text {
                                id: cornellSumTxt
                                objectName: "nexusCornellSummaryReadingText"
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                readonly property string rawSummary: String(root.cView.summary ?? "").trim()
                                readonly property string renderedSummaryHtml: {
                                    const _sig = root.themeSignature;
                                    if (rawSummary.length === 0)
                                        return "<span style='color:" + String(root.textMuted) + ";'><i>Synthesize the core takeaway of this study sheet in 2–3 sentences. Click to edit.</i></span>";
                                    const sHtml = String(root.cView.summaryRichHtml || root.cView.summaryHtml || "").trim();
                                    if (sHtml.length > 0 && !/(^|>|\n)\s*#{1,6}\s+/m.test(sHtml) && !/\[\[/.test(sHtml) && sHtml.indexOf("<") >= 0)
                                        return root.themeRichHtml(sHtml);
                                    return root.renderMarkdownBlocksHtml(rawSummary);
                                }
                                text: renderedSummaryHtml
                                textFormat: Text.RichText
                                font.pixelSize: 14
                                lineHeight: 1.42
                                color: root.textPrimary
                                wrapMode: Text.Wrap
                                onLinkActivated: link => {
                                    if (root.service && link.startsWith("wikilink:"))
                                        root.service.followWikilink(decodeURIComponent(link.substring(9)));
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.IBeamCursor
                                onClicked: {
                                    cornellBodyEditor.text = root.service ? root.service.getNoteBodyMarkdown() : "";
                                    root.editingNoteBody = true;
                                }
                            }
                        }

                        ColumnLayout {
                            visible: root.editingNoteBody && root.noteKind === "cornell"
                            Layout.fillWidth: true
                            spacing: 6

                            TextArea {
                                id: cornellBodyEditor
                                objectName: "nexusCornellBodyEditor"
                                Layout.fillWidth: true
                                Layout.minimumHeight: 180
                                text: root.service ? root.service.getNoteBodyMarkdown() : ""
                                placeholderText: "Edit Cornell study sheet markdown..."
                                placeholderTextColor: root.textMuted
                                font.pixelSize: 13
                                color: root.textPrimary
                                wrapMode: TextEdit.Wrap
                                background: Item {}
                                onVisibleChanged: if (visible) Qt.callLater(() => { if (cornellBodyEditor.visible) cornellBodyEditor.forceActiveFocus(); })
                                onActiveFocusChanged: {
                                    if (!activeFocus && visible && root.editingNoteBody && root.noteKind === "cornell" && !cornellCancelMouse.containsMouse && !cornellCancelMouse.pressed) {
                                        if (root.service)
                                            root.service.saveNoteBodyMarkdown(cornellBodyEditor.text);
                                        root.editingNoteBody = false;
                                    }
                                }
                                Keys.onEscapePressed: event => {
                                    if (root.service)
                                        root.service.saveNoteBodyMarkdown(cornellBodyEditor.text);
                                    cornellBodyEditor.focus = false;
                                    root.editingNoteBody = false;
                                    root.restoreWorkspaceFocus();
                                    event.accepted = true;
                                }
                                Keys.onPressed: event => {
                                    if ((event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_S)) {
                                        if (root.service)
                                            root.service.saveNoteBodyMarkdown(cornellBodyEditor.text);
                                        cornellBodyEditor.focus = false;
                                        root.editingNoteBody = false;
                                        root.restoreWorkspaceFocus();
                                        event.accepted = true;
                                        return;
                                    }
                                    if ((event.modifiers & (Qt.AltModifier | Qt.ControlModifier | Qt.MetaModifier)) !== 0
                                        && root.service && root.service.handleKeyEvent(event)) {
                                        event.accepted = true;
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Item { Layout.fillWidth: true }
                                Rectangle {
                                    radius: 5
                                    color: root.cardDeepBg
                                    border.width: 1
                                    border.color: root.borderSubtle
                                    implicitWidth: 56
                                    implicitHeight: 26
                                    Text { anchors.centerIn: parent; text: "Cancel"; font.pixelSize: 11; color: root.textSecondary }
                                    MouseArea {
                                        id: cornellCancelMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.editingNoteBody = false;
                                            if (root.workspace && typeof root.workspace.focusPrimarySurface === "function")
                                                Qt.callLater(root.workspace.focusPrimarySurface);
                                        }
                                    }
                                }
                                Rectangle {
                                    objectName: "nexusCornellBodySaveButton"
                                    radius: 5
                                    color: root.accentColor
                                    implicitWidth: 60
                                    implicitHeight: 26
                                    Text { anchors.centerIn: parent; text: "Save"; font.pixelSize: 11; font.weight: Font.Bold; color: root.onAccentColor }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (root.service)
                                                root.service.saveNoteBodyMarkdown(cornellBodyEditor.text);
                                            root.editingNoteBody = false;
                                            if (root.workspace && typeof root.workspace.focusPrimarySurface === "function")
                                                Qt.callLater(root.workspace.focusPrimarySurface);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ── 3.5B Active Recall & Review Schedule Row (when present) ──
                RowLayout {
                    objectName: "nexusCornellRecallScheduleRow"
                    visible: (root.cView.recallQuestions ?? []).length > 0 || (root.cView.reviewSchedule ?? []).length > 0
                    Layout.fillWidth: true
                    spacing: 12

                    Rectangle {
                        visible: (root.cView.recallQuestions ?? []).length > 0
                        Layout.fillWidth: true
                        Layout.preferredWidth: 360
                        Layout.alignment: Qt.AlignTop
                        implicitHeight: cornellRecallCol.implicitHeight + 20
                        radius: 8
                        color: root.cardSubtleBg
                        border.width: 1
                        border.color: root.borderSubtle

                        ColumnLayout {
                            id: cornellRecallCol
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 4
                            Text {
                                text: "ACTIVE RECALL · SELF-TEST"
                                font.family: Appearance.font.family.monospace
                                font.pixelSize: 10
                                font.weight: Font.Bold
                                font.letterSpacing: 1.4
                                color: root.accentColor
                            }
                            Repeater {
                                model: root.cView.recallQuestions ?? []
                                delegate: Text {
                                    required property var modelData
                                    required property int index
                                    Layout.fillWidth: true
                                    text: root.renderInlineMarkdownHtml(String(index + 1) + ". " + String(modelData ?? ""))
                                    textFormat: Text.RichText
                                    font.pixelSize: 13
                                    color: root.textPrimary
                                    wrapMode: Text.Wrap
                                }
                            }
                        }
                    }

                    Rectangle {
                        visible: (root.cView.reviewSchedule ?? []).length > 0
                        Layout.fillWidth: true
                        Layout.preferredWidth: 260
                        Layout.alignment: Qt.AlignTop
                        implicitHeight: cornellReviewCol.implicitHeight + 20
                        radius: 8
                        color: root.cardSubtleBg
                        border.width: 1
                        border.color: root.borderSubtle

                        ColumnLayout {
                            id: cornellReviewCol
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 4
                            Text {
                                text: "REVIEW SCHEDULE"
                                font.family: Appearance.font.family.monospace
                                font.pixelSize: 10
                                font.weight: Font.Bold
                                font.letterSpacing: 1.4
                                color: root.textSecondary
                            }
                            Repeater {
                                model: root.cView.reviewSchedule ?? []
                                delegate: Text {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    text: root.renderInlineMarkdownHtml("• " + String(modelData ?? ""))
                                    textFormat: Text.RichText
                                    font.pixelSize: 13
                                    color: root.textSecondary
                                    wrapMode: Text.Wrap
                                }
                            }
                        }
                    }
                }

                // ── 3.6 Footer (`cv-cornell-footer`) ──
                GridLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    columns: width >= 440 ? 3 : 1
                    rowSpacing: 6
                    Text {
                        text: "Cue · Recall · Summarize · Review"
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: 11
                        color: root.textMuted
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: String((root.cView.cues ?? []).length) + " Cues · " + cornellCustomView.statusText
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: 11
                        color: root.accentColor
                    }
                }
            }
        }

        // =====================================================================
        // 4. ZETTELKASTEN SLIP CARD (`Custom_Views/Zettelkasten/Zettelkasten.{html,js,css}`)
        // =====================================================================
        Rectangle {
            id: zettelkastenCustomView
            objectName: "nexusZettelkastenCustomView"
            Layout.minimumWidth: 0
            visible: root.noteKind === "zettelkasten"
            Layout.fillWidth: true
            implicitHeight: Math.max(root.minDocumentSurfaceHeight, zkCol.implicitHeight + 34)
            radius: 10
            color: root.cardBg
            border.width: 1
            border.color: root.borderAccent

            readonly property string zettelIdText: String(root.zView.zettelId ?? "ZETTEL")
            readonly property string zettelTypeText: String(root.zView.zettelType ?? "Permanent")
            readonly property string zettelDateText: String(root.zView.date || root.dossier.date || "—")
            readonly property string zettelCleanTitle: String(root.zView.cleanTitle || root.doc?.title || "Untitled Slip")
            readonly property int zettelConnectionCount: Number(root.zView.connectionCount ?? 0)
            readonly property color zettelTypeAccent: {
                const low = zettelTypeText.toLowerCase();
                if (low.indexOf("literature") >= 0)
                    return Qt.rgba(0.796, 0.651, 0.969, 1.0); // #cba6f7
                if (low.indexOf("fleeting") >= 0)
                    return Qt.rgba(0.980, 0.702, 0.529, 1.0); // #fab387
                return root.accentColor;
            }

            ColumnLayout {
                id: zkCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 18
                spacing: 14

                readonly property int zkRailWidth: Math.max(230, Math.min(310, Math.round((zkCol.width - 14) * 0.30)))

                // ── 4.1 Slip Header (`cv-zk-header`) ──
                GridLayout {
                    columns: width < 680 ? 1 : 2
                    columnSpacing: 16
                    rowSpacing: 16
                    Layout.fillWidth: true

                    // Left: `.cv-zk-title-wrap`
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignTop
                        spacing: 5

                        RowLayout {
                            spacing: 8
                            Text {
                                text: "ATOMIC SLIP"
                                font.family: Appearance.font.family.monospace
                                font.pixelSize: 11
                                font.weight: Font.Bold
                                font.letterSpacing: 1.8
                                color: zettelkastenCustomView.zettelTypeAccent
                            }
                            Rectangle {
                                objectName: "nexusZettelkastenIdBadge"
                                radius: 4
                                color: Qt.rgba(zettelkastenCustomView.zettelTypeAccent.r, zettelkastenCustomView.zettelTypeAccent.g, zettelkastenCustomView.zettelTypeAccent.b, 0.16)
                                border.width: 1
                                border.color: zettelkastenCustomView.zettelTypeAccent
                                implicitWidth: zkIdTxt.implicitWidth + 12
                                implicitHeight: 22
                                Text {
                                    id: zkIdTxt
                                    anchors.centerIn: parent
                                    text: "ID // " + zettelkastenCustomView.zettelIdText
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: 11
                                    font.weight: Font.Bold
                                    color: zettelkastenCustomView.zettelTypeAccent
                                }
                            }
                        }

                        Text {
                            objectName: "nexusZettelkastenTitleLabel"
                            Layout.fillWidth: true
                            text: zettelkastenCustomView.zettelCleanTitle
                            font.pixelSize: 24
                            font.weight: Font.Bold
                            color: root.textStrong
                            wrapMode: Text.Wrap
                        }

                        Text {
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            text: "One note · one idea · meaningful connections"
                            font.pixelSize: 13
                            color: root.textSecondary
                        }
                    }

                    // Right: `.cv-zk-meta` (3-column metadata: Type, Date, Links)
                    GridLayout {
                    columns: width < 330 ? 2 : 3
                    columnSpacing: 8
                    rowSpacing: 8
                        Layout.alignment: Qt.AlignTop

                        // Type (clickable to cycle Permanent -> Literature -> Fleeting)
                        Rectangle {
                            objectName: "nexusZettelkastenTypeBadge"
                            implicitWidth: 104
                            implicitHeight: 46
                            radius: 6
                            color: zkTypeMouse.containsMouse ? root.cardHoverBg : root.cardDeepBg
                            border.width: 1
                            border.color: zkTypeMouse.containsMouse ? zettelkastenCustomView.zettelTypeAccent : root.borderSubtle
                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 7
                                spacing: 2
                                Text { text: "TYPE"; font.family: Appearance.font.family.monospace; font.pixelSize: 9; font.weight: Font.Bold; color: root.textMuted }
                                Text {
                                    text: zettelkastenCustomView.zettelTypeText
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: 12
                                    font.weight: Font.Bold
                                    color: zettelkastenCustomView.zettelTypeAccent
                                    elide: Text.ElideRight
                                }
                            }
                            MouseArea {
                                id: zkTypeMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (!root.service)
                                        return;
                                    const cur = zettelkastenCustomView.zettelTypeText.toLowerCase();
                                    const next = cur.indexOf("permanent") >= 0 ? "Literature" : (cur.indexOf("literature") >= 0 ? "Fleeting" : "Permanent");
                                    root.service.updateNoteFrontmatter({ "type": next });
                                }
                            }
                        }

                        // Date
                        Rectangle {
                            implicitWidth: 104
                            implicitHeight: 46
                            radius: 6
                            color: root.cardDeepBg
                            border.width: 1
                            border.color: root.borderSubtle
                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 7
                                spacing: 2
                                Text { text: "DATE"; font.family: Appearance.font.family.monospace; font.pixelSize: 9; font.weight: Font.Bold; color: root.textMuted }
                                Text { text: zettelkastenCustomView.zettelDateText; font.family: Appearance.font.family.monospace; font.pixelSize: 12; color: root.textPrimary; elide: Text.ElideRight }
                            }
                        }

                        // Links
                        Rectangle {
                            implicitWidth: 104
                            implicitHeight: 46
                            radius: 6
                            color: root.cardDeepBg
                            border.width: 1
                            border.color: root.borderSubtle
                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 7
                                spacing: 2
                                Text { text: "LINKS"; font.family: Appearance.font.family.monospace; font.pixelSize: 9; font.weight: Font.Bold; color: root.textMuted }
                                Text {
                                    text: zettelkastenCustomView.zettelConnectionCount > 0
                                        ? (String(zettelkastenCustomView.zettelConnectionCount) + " links")
                                        : (String((root.doc?.linkedBacklinks ?? []).length) + " backlinks")
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: 12
                                    color: root.textPrimary
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }
                }

                OrnamentalDivider {}

                // ── 4.2 2-Column Slip Body (`cv-zk-body`: 70% Main Column + 30% Rail Column) ──
                GridLayout {
                    columns: width < 620 ? 1 : 2
                    columnSpacing: 14
                    rowSpacing: 14
                    id: zettelBodyGrid
                    objectName: "nexusZettelkastenBodyReadingArea"
                    visible: !root.editingNoteBody
                    Layout.fillWidth: true

                    // Left 70%: `.cv-zk-main` (Core Idea + Content & Elaboration)
                    ColumnLayout {
                        id: zkMainCol
                        objectName: "nexusZettelkastenMainCol"
                        Layout.fillWidth: true
                        Layout.preferredWidth: Math.max(320, zkCol.width - zkCol.zkRailWidth - 14)
                        Layout.minimumWidth: 0
                        Layout.alignment: Qt.AlignTop
                        spacing: 12

                        // CORE IDEA card
                        Rectangle {
                            objectName: "nexusZettelkastenCoreIdeaCard"
                            Layout.fillWidth: true
                            implicitHeight: zkCoreCol.implicitHeight + 24
                            radius: 8
                            color: root.cardDeepBg
                            border.width: 1
                            border.color: root.borderSubtle

                            // Type-aware 3px left accent bar matching `Zettelkasten.css` (`.cv-zettel-claim`)
                            Rectangle {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                anchors.topMargin: 8
                                anchors.bottomMargin: 8
                                width: 3
                                radius: 2
                                color: zettelkastenCustomView.zettelTypeAccent
                            }

                            ColumnLayout {
                                id: zkCoreCol
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 12
                                spacing: 6

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        text: "CORE IDEA"
                                        font.family: Appearance.font.family.monospace
                                        font.pixelSize: 11
                                        font.weight: Font.Bold
                                        font.letterSpacing: 1.4
                                        color: zettelkastenCustomView.zettelTypeAccent
                                    }
                                    Item { Layout.fillWidth: true }
                                    Text {
                                        text: "Click to edit"
                                        font.family: Appearance.font.family.monospace
                                        font.pixelSize: 10
                                        color: root.textMuted
                                    }
                                }

                                Text {
                                    id: zkCoreTxt
                                    objectName: "nexusZettelkastenCoreIdeaText"
                                    Layout.fillWidth: true
                                    readonly property string rawCore: String(root.zView.coreIdea || root.dossier.subtitle || "").trim()
                                    text: {
                                        const _sig = root.themeSignature;
                                        if (rawCore.length === 0)
                                            return "<span style='color:" + String(root.textMuted) + ";'><i>State the single atomic claim of this slip in 1–2 clear sentences. Click to edit.</i></span>";
                                        const cHtml = String(root.zView.coreIdeaRichHtml ?? "").trim();
                                        if (cHtml.length > 0 && !/(^|>|\n)\s*#{1,6}\s+/m.test(cHtml) && !/\[\[/.test(cHtml))
                                            return root.themeRichHtml(cHtml);
                                        return root.renderMarkdownBlocksHtml(rawCore);
                                    }
                                    textFormat: Text.RichText
                                    font.pixelSize: 15
                                    lineHeight: 1.42
                                    color: root.textStrong
                                    wrapMode: Text.Wrap
                                    onLinkActivated: link => {
                                        if (root.service && link.startsWith("wikilink:"))
                                            root.service.followWikilink(decodeURIComponent(link.substring(9)));
                                        else if (link.startsWith("http://") || link.startsWith("https://"))
                                            Qt.openUrlExternally(link);
                                    }
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.IBeamCursor
                                onClicked: mouse => {
                                    const linkAt = zkCoreTxt.linkAt(mouse.x - 12, mouse.y - 34);
                                    if (linkAt && linkAt.length > 0) {
                                        if (root.service && linkAt.startsWith("wikilink:"))
                                            root.service.followWikilink(decodeURIComponent(linkAt.substring(9)));
                                        else if (linkAt.startsWith("http://") || linkAt.startsWith("https://"))
                                            Qt.openUrlExternally(linkAt);
                                        return;
                                    }
                                    zettelBodyEditor.text = root.service ? root.service.getNoteBodyMarkdown() : "";
                                    root.editingNoteBody = true;
                                }
                            }
                        }

                        // CONTENT & ELABORATION card
                        Rectangle {
                            objectName: "nexusZettelkastenElaborationCard"
                            Layout.fillWidth: true
                            implicitHeight: Math.max(240, root.minDocumentSurfaceHeight - 280, zkElabCol.implicitHeight + 24)
                            radius: 8
                            color: root.cardDeepBg
                            border.width: 1
                            border.color: root.borderSubtle

                            ColumnLayout {
                                id: zkElabCol
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 12
                                spacing: 6

                                Text {
                                    text: "CONTENT & ELABORATION"
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: 11
                                    font.weight: Font.Bold
                                    font.letterSpacing: 1.4
                                    color: root.textSecondary
                                }

                                Text {
                                    id: zkElabTxt
                                    objectName: "nexusZettelkastenElaborationText"
                                    Layout.fillWidth: true
                                    readonly property string rawElab: String(root.zView.contentSection ?? "").trim()
                                    text: {
                                        const _sig = root.themeSignature;
                                        if (rawElab.length === 0)
                                            return "<span style='color:" + String(root.textMuted) + ";'><i>Explain the reasoning, evidence, or examples supporting the core idea in your own words.</i></span>";
                                        const eHtml = String(root.zView.contentRichHtml ?? "").trim();
                                        if (eHtml.length > 0 && !/(^|>|\n)\s*#{1,6}\s+/m.test(eHtml) && !/\[\[/.test(eHtml))
                                            return root.themeRichHtml(eHtml);
                                        return root.renderMarkdownBlocksHtml(rawElab);
                                    }
                                    textFormat: Text.RichText
                                    font.pixelSize: 14
                                    lineHeight: 1.42
                                    color: root.textPrimary
                                    wrapMode: Text.Wrap
                                    onLinkActivated: link => {
                                        if (root.service && link.startsWith("wikilink:"))
                                            root.service.followWikilink(decodeURIComponent(link.substring(9)));
                                        else if (link.startsWith("http://") || link.startsWith("https://"))
                                            Qt.openUrlExternally(link);
                                    }
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.IBeamCursor
                                onClicked: mouse => {
                                    const linkAt = zkElabTxt.linkAt(mouse.x - 12, mouse.y - 34);
                                    if (linkAt && linkAt.length > 0) {
                                        if (root.service && linkAt.startsWith("wikilink:"))
                                            root.service.followWikilink(decodeURIComponent(linkAt.substring(9)));
                                        else if (linkAt.startsWith("http://") || linkAt.startsWith("https://"))
                                            Qt.openUrlExternally(linkAt);
                                        return;
                                    }
                                    zettelBodyEditor.text = root.service ? root.service.getNoteBodyMarkdown() : "";
                                    root.editingNoteBody = true;
                                }
                            }
                        }
                    }

                    // Right 30%: `.cv-zk-rail` (Connections, Sources, Backlinks)
                    ColumnLayout {
                        id: zkRailCol
                        objectName: "nexusZettelkastenRailCol"
                        Layout.fillWidth: zettelBodyGrid.columns === 1
                        Layout.preferredWidth: zkCol.zkRailWidth
                        Layout.minimumWidth: 0
                        Layout.maximumWidth: zettelBodyGrid.columns === 1 ? Infinity : zkCol.zkRailWidth
                        Layout.alignment: Qt.AlignTop
                        spacing: 12

                        // CONNECTIONS & CONTEXT
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: zkConnCol.implicitHeight + 24
                            radius: 8
                            color: root.cardDeepBg
                            border.width: 1
                            border.color: root.borderSubtle

                            ColumnLayout {
                                id: zkConnCol
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 12
                                spacing: 6

                                Text {
                                    text: "CONNECTIONS & CONTEXT"
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: 11
                                    font.weight: Font.Bold
                                    font.letterSpacing: 1.4
                                    color: root.accentColor
                                }

                                Text {
                                    id: zkConnTxt
                                    objectName: "nexusZettelkastenConnectionsText"
                                    Layout.fillWidth: true
                                    readonly property string rawConn: String(root.zView.connections || root.zView.connectionsSection || "").trim()
                                    text: {
                                        const _sig = root.themeSignature;
                                        if (rawConn.length === 0)
                                            return "<span style='color:" + String(root.textMuted) + ";'><i>Link related slips with [[wikilinks]] under ## Connections.</i></span>";
                                        const connHtml = String(root.zView.connectionsRichHtml ?? "").trim();
                                        if (connHtml.length > 0 && !/(^|>|\n)\s*#{1,6}\s+/m.test(connHtml) && !/\[\[/.test(connHtml))
                                            return root.themeRichHtml(connHtml);
                                        return root.renderMarkdownBlocksHtml(rawConn);
                                    }
                                    textFormat: Text.RichText
                                    font.pixelSize: 13
                                    lineHeight: 1.38
                                    color: root.textPrimary
                                    wrapMode: Text.Wrap
                                    onLinkActivated: link => {
                                        if (root.service && link.startsWith("wikilink:"))
                                            root.service.followWikilink(decodeURIComponent(link.substring(9)));
                                        else if (link.startsWith("http://") || link.startsWith("https://"))
                                            Qt.openUrlExternally(link);
                                    }
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.LeftButton
                                cursorShape: Qt.IBeamCursor
                                onClicked: mouse => {
                                    const linkAt = zkConnTxt.linkAt(mouse.x - 12, mouse.y - 34);
                                    if (linkAt && linkAt.length > 0) {
                                        if (root.service && linkAt.startsWith("wikilink:"))
                                            root.service.followWikilink(decodeURIComponent(linkAt.substring(9)));
                                        else if (linkAt.startsWith("http://") || linkAt.startsWith("https://"))
                                            Qt.openUrlExternally(linkAt);
                                        return;
                                    }
                                    zettelBodyEditor.text = root.service ? root.service.getNoteBodyMarkdown() : "";
                                    root.editingNoteBody = true;
                                }
                            }
                        }

                        // SOURCES & REFERENCES
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: zkSrcCol.implicitHeight + 24
                            radius: 8
                            color: root.cardDeepBg
                            border.width: 1
                            border.color: root.borderSubtle

                            ColumnLayout {
                                id: zkSrcCol
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 12
                                spacing: 6

                                Text {
                                    text: "SOURCES & REFERENCES"
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: 11
                                    font.weight: Font.Bold
                                    font.letterSpacing: 1.4
                                    color: root.textSecondary
                                }

                                Text {
                                    id: zkSrcTxt
                                    objectName: "nexusZettelkastenSourcesText"
                                    Layout.fillWidth: true
                                    readonly property string rawSrc: String(root.zView.sources || root.zView.referencesSection || "").trim()
                                    text: {
                                        const _sig = root.themeSignature;
                                        if (rawSrc.length === 0)
                                            return "<span style='color:" + String(root.textMuted) + ";'><i>Cite books, papers, or origin notes under ## Sources.</i></span>";
                                        const srcHtml = String(root.zView.sourcesRichHtml ?? "").trim();
                                        if (srcHtml.length > 0 && !/(^|>|\n)\s*#{1,6}\s+/m.test(srcHtml) && !/\[\[/.test(srcHtml))
                                            return root.themeRichHtml(srcHtml);
                                        return root.renderMarkdownBlocksHtml(rawSrc);
                                    }
                                    textFormat: Text.RichText
                                    font.pixelSize: 13
                                    lineHeight: 1.38
                                    color: root.textSecondary
                                    wrapMode: Text.Wrap
                                    onLinkActivated: link => {
                                        if (root.service && link.startsWith("wikilink:"))
                                            root.service.followWikilink(decodeURIComponent(link.substring(9)));
                                        else if (link.startsWith("http://") || link.startsWith("https://"))
                                            Qt.openUrlExternally(link);
                                    }
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.IBeamCursor
                                onClicked: mouse => {
                                    const linkAt = zkSrcTxt.linkAt(mouse.x - 12, mouse.y - 34);
                                    if (linkAt && linkAt.length > 0) {
                                        if (root.service && linkAt.startsWith("wikilink:"))
                                            root.service.followWikilink(decodeURIComponent(linkAt.substring(9)));
                                        else if (linkAt.startsWith("http://") || linkAt.startsWith("https://"))
                                            Qt.openUrlExternally(linkAt);
                                        return;
                                    }
                                    zettelBodyEditor.text = root.service ? root.service.getNoteBodyMarkdown() : "";
                                    root.editingNoteBody = true;
                                }
                            }
                        }

                        // LINKED BACKLINKS (`.cv-zk-backlinks` — always visible matching `Zettelkasten.js`)
                        Rectangle {
                            objectName: "nexusZettelkastenBacklinksCard"
                            visible: true
                            Layout.fillWidth: true
                            implicitHeight: zkBacklinksCol.implicitHeight + 24
                            radius: 8
                            color: root.cardDeepBg
                            border.width: 1
                            border.color: root.borderSubtle

                            ColumnLayout {
                                id: zkBacklinksCol
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 12
                                spacing: 6

                                Text {
                                    text: "BACKLINKS (" + String((root.doc?.linkedBacklinks ?? []).length) + ")"
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: 11
                                    font.weight: Font.Bold
                                    font.letterSpacing: 1.4
                                    color: root.accentColor
                                }

                                Text {
                                    visible: (root.doc?.linkedBacklinks ?? []).length === 0
                                    Layout.fillWidth: true
                                    text: "No backlinks yet."
                                    font.pixelSize: 12
                                    font.italic: true
                                    color: root.textMuted
                                    wrapMode: Text.Wrap
                                }

                                Repeater {
                                    model: root.doc?.linkedBacklinks ?? []
                                    delegate: Rectangle {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        implicitHeight: 26
                                        radius: 5
                                        color: zkBlMouse.containsMouse ? root.cardHoverBg : root.cardRaisedBg
                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            anchors.left: parent.left
                                            anchors.leftMargin: 8
                                            anchors.right: parent.right
                                            anchors.rightMargin: 8
                                            text: "↗ " + String(modelData.title || modelData.relPath || "")
                                            font.family: Appearance.font.family.monospace
                                            font.pixelSize: 12
                                            color: root.accentColor
                                            elide: Text.ElideRight
                                        }
                                        MouseArea {
                                            id: zkBlMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (root.service && modelData.relPath)
                                                    root.service.openFile(String(modelData.relPath), true);
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ── 4.3 Inline Click-to-Edit Slip Editor ──
                ColumnLayout {
                    visible: root.editingNoteBody && root.noteKind === "zettelkasten"
                    Layout.fillWidth: true
                    spacing: 6

                    TextArea {
                        id: zettelBodyEditor
                        objectName: "nexusZettelkastenBodyEditor"
                        Layout.fillWidth: true
                        Layout.minimumHeight: 180
                        text: root.service ? root.service.getNoteBodyMarkdown() : ""
                        placeholderText: "Write your Zettelkasten atomic idea & connections..."
                        placeholderTextColor: root.textMuted
                        font.pixelSize: 13
                        color: root.textPrimary
                        wrapMode: TextEdit.Wrap
                        background: Rectangle { radius: 6; color: root.cardDeepBg; border.width: 1; border.color: root.accentColor }
                        onVisibleChanged: if (visible) Qt.callLater(() => { if (zettelBodyEditor.visible) zettelBodyEditor.forceActiveFocus(); })
                        onActiveFocusChanged: {
                            if (!activeFocus && visible && root.editingNoteBody && root.noteKind === "zettelkasten" && !zettelCancelMouse.containsMouse && !zettelCancelMouse.pressed) {
                                if (root.service)
                                    root.service.saveNoteBodyMarkdown(zettelBodyEditor.text);
                                root.editingNoteBody = false;
                            }
                        }
                        Keys.onEscapePressed: event => {
                            if (root.service)
                                root.service.saveNoteBodyMarkdown(zettelBodyEditor.text);
                            zettelBodyEditor.focus = false;
                            root.editingNoteBody = false;
                            root.restoreWorkspaceFocus();
                            event.accepted = true;
                        }
                        Keys.onPressed: event => {
                            if ((event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_S)) {
                                if (root.service)
                                    root.service.saveNoteBodyMarkdown(zettelBodyEditor.text);
                                zettelBodyEditor.focus = false;
                                root.editingNoteBody = false;
                                root.restoreWorkspaceFocus();
                                event.accepted = true;
                                return;
                            }
                            if ((event.modifiers & (Qt.AltModifier | Qt.ControlModifier | Qt.MetaModifier)) !== 0
                                && root.service && root.service.handleKeyEvent(event)) {
                                event.accepted = true;
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Item { Layout.fillWidth: true }
                        Rectangle {
                            radius: 5
                            color: root.cardRaisedBg
                            border.width: 1
                            border.color: root.borderSubtle
                            implicitWidth: 56
                            implicitHeight: 26
                            Text { anchors.centerIn: parent; text: "Cancel"; font.pixelSize: 11; color: root.textSecondary }
                            MouseArea {
                                id: zettelCancelMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.editingNoteBody = false;
                                    if (root.workspace && typeof root.workspace.focusPrimarySurface === "function")
                                        Qt.callLater(root.workspace.focusPrimarySurface);
                                }
                            }
                        }
                        Rectangle {
                            objectName: "nexusZettelkastenBodySaveButton"
                            radius: 5
                            color: root.accentColor
                            implicitWidth: 60
                            implicitHeight: 26
                            Text { anchors.centerIn: parent; text: "Save"; font.pixelSize: 11; font.weight: Font.Bold; color: root.onAccentColor }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (root.service)
                                        root.service.saveNoteBodyMarkdown(zettelBodyEditor.text);
                                    root.editingNoteBody = false;
                                    if (root.workspace && typeof root.workspace.focusPrimarySurface === "function")
                                        Qt.callLater(root.workspace.focusPrimarySurface);
                                }
                            }
                        }
                    }
                }

                // ── 4.4 Slip Footer (`cv-zk-footer`) ──
                GridLayout {
                    columns: width < 620 ? 1 : 3
                    columnSpacing: 6
                    rowSpacing: 6
                    objectName: "nexusZettelkastenFooter"
                    Layout.fillWidth: true
                    Text {
                        Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            text: "Zettelkasten · Atomic Note · ID // " + zettelkastenCustomView.zettelIdText
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: 11
                        color: root.textMuted
                    }
                    Item { Layout.fillWidth: true; visible: parent.columns > 1 }
                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: zettelkastenCustomView.zettelTypeText + " · " + String(zettelkastenCustomView.zettelConnectionCount) + " connections · " + String((root.doc?.linkedBacklinks ?? []).length) + " backlinks"
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: 11
                        color: zettelkastenCustomView.zettelTypeAccent
                    }
                }
            }
        }

        // =====================================================================
        // 5. RECIPE CUSTOM VIEW (`Custom_Views/Recipe/Recipe.{html,js,css}` adapted to Alis Auto-theming)
        // =====================================================================
        Rectangle {
            id: recipeCustomView
            objectName: "nexusRecipeCustomView"
            Layout.minimumWidth: 0
            visible: root.noteKind === "recipe"
            Layout.fillWidth: true
            implicitHeight: Math.max(root.minDocumentSurfaceHeight, recipeSheetCol.implicitHeight + 48)
            radius: 22
            color: root.cardSubtleBg
            border.width: 1
            border.color: root.borderAccent
            clip: true

            // Top 5px gradient highlight bar (`.cv-recipe-sheet::before`)
            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 5
                color: root.accentColor
                opacity: 0.85
            }

            ColumnLayout {
                id: recipeSheetCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 24
                anchors.topMargin: 26
                spacing: 22

                // -------------------------------------------------------------
                // 5.1 HERO (`.cv-recipe-hero`: Left Polaroid Photo Card + Right Title & Section Nav)
                // -------------------------------------------------------------
                GridLayout {
                    id: nexusRecipeHero
                    columns: width >= 740 ? 3 : 1
                    columnSpacing: 24
                    rowSpacing: 16
                    Layout.minimumWidth: 0
                    objectName: "nexusRecipeHero"
                    Layout.fillWidth: true

                    // Left: Tilted Polaroid Photo Card (`.cv-recipe-photo-card`)
                    Item {
                        Layout.preferredWidth: 270
                        Layout.minimumWidth: 0
                        Layout.maximumWidth: 300
                        Layout.fillWidth: nexusRecipeHero.columns === 1
                        Layout.preferredHeight: 280
                        Layout.alignment: Qt.AlignTop

                        Rectangle {
                            id: recipePhotoCard
                            objectName: "nexusRecipePhotoCard"
                            anchors.fill: parent
                            anchors.topMargin: 8
                            radius: 16
                            rotation: -1.1
                            color: root.journalSubSurfaceBg
                            border.width: 1
                            border.color: root.borderSubtle

                            // Inner photo frame
                            Rectangle {
                                id: recipePhotoFrame
                                anchors.fill: parent
                                anchors.margins: 12
                                radius: 12
                                color: root.cardDeepBg
                                border.width: 1
                                border.color: root.borderSubtle
                                clip: true

                                Image {
                                    id: recipeHeroImg
                                    objectName: "nexusRecipeHeroImage"
                                    anchors.fill: parent
                                    source: String(root.rView.coverUrl || root.dossier.posterUrl || "")
                                    sourceSize: Qt.size(960, 540)
                                    fillMode: Image.PreserveAspectCrop
                                    scale: String(source).indexOf("spoonacular-") !== -1 ? 1.18 : 1.02
                                    asynchronous: true
                                    cache: false
                                    visible: status === Image.Ready
                                }

                                // Placeholder when image is missing or loading
                                ColumnLayout {
                                    anchors.centerIn: parent
                                    visible: recipeHeroImg.status !== Image.Ready
                                    spacing: 6
                                    MaterialSymbol {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: "restaurant"
                                        iconSize: 34
                                        color: root.accentColor
                                    }
                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: "Add dish photo"
                                        font.pixelSize: 10
                                        font.weight: Font.Bold
                                        font.letterSpacing: 1.2
                                        color: root.textMuted
                                    }
                                }

                                // Bottom gradient vignette for badge/action legibility
                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    height: 68
                                    gradient: Gradient {
                                        GradientStop { position: 0.0; color: "transparent" }
                                        GradientStop { position: 1.0; color: Qt.rgba(root.cardDeepBg.r, root.cardDeepBg.g, root.cardDeepBg.b, 0.86) }
                                    }
                                }

                                // Top-left Pennant Category Ribbon Badge (`.cv-recipe-photo-label` / `.cv-recipe-badge`)
                                Rectangle {
                                    id: recipeCategoryBadge
                                    objectName: "nexusRecipeCategoryBadge"
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    anchors.leftMargin: 16
                                    topLeftRadius: 0
                                    topRightRadius: 0
                                    bottomLeftRadius: 8
                                    bottomRightRadius: 8
                                    color: root.accentColor
                                    implicitWidth: Math.min(165, Math.max(82, recipeBadgeTxt.implicitWidth + 24))
                                    implicitHeight: 32

                                    Text {
                                        id: recipeBadgeTxt
                                        anchors.centerIn: parent
                                        width: parent.width - 14
                                        horizontalAlignment: Text.AlignHCenter
                                        text: String(root.rView.recipeCategory || root.dossier.category || "RECIPE").toUpperCase()
                                        font.pixelSize: 9
                                        font.weight: Font.Bold
                                        font.letterSpacing: 1.4
                                        color: root.onAccentColor
                                        elide: Text.ElideRight
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.recipeDraftTextA = String(root.rView.recipeCategory || root.dossier.category || "");
                                            root.recipeEditingField = "recipe_category";
                                            root.recipeEditingIndex = -1;
                                        }
                                    }
                                }

                                // Bottom-right Favorite & Bookmark circular action buttons (`.cv-recipe-photo-actions`)
                                RowLayout {
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    anchors.rightMargin: 12
                                    anchors.bottomMargin: 12
                                    spacing: 8

                                    // Favorite Heart Button (`data-recipe-toggle="favorite"`)
                                    Rectangle {
                                        id: recipeFavBtn
                                        objectName: "nexusRecipeFavoriteButton"
                                        width: 36
                                        height: 36
                                        radius: 18
                                        color: root.recipeIsFavorite ? root.accentColor : Qt.rgba(root.cardBg.r, root.cardBg.g, root.cardBg.b, 0.88)
                                        border.width: 1
                                        border.color: root.recipeIsFavorite ? root.accentColor : root.borderSubtle

                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: root.recipeIsFavorite ? "favorite" : "favorite_border"
                                            iconSize: 17
                                            color: root.recipeIsFavorite ? root.onAccentColor : root.textPrimary
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                const nextFav = !root.recipeIsFavorite;
                                                root.recipeFavoriteOverride = nextFav ? 1 : 0;
                                                if (root.service)
                                                    root.service.updateNoteFrontmatter({ "favorite": nextFav });
                                            }
                                        }
                                    }

                                    // Bookmark Button (`data-recipe-toggle="bookmarked"`)
                                    Rectangle {
                                        id: recipeBookmarkBtn
                                        objectName: "nexusRecipeBookmarkButton"
                                        width: 36
                                        height: 36
                                        radius: 18
                                        color: root.recipeIsBookmarked ? root.accentColor : Qt.rgba(root.cardBg.r, root.cardBg.g, root.cardBg.b, 0.88)
                                        border.width: 1
                                        border.color: root.recipeIsBookmarked ? root.accentColor : root.borderSubtle

                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: root.recipeIsBookmarked ? "bookmark" : "bookmark_border"
                                            iconSize: 17
                                            color: root.recipeIsBookmarked ? root.onAccentColor : root.textPrimary
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                const nextBm = !root.recipeIsBookmarked;
                                                root.recipeBookmarkOverride = nextBm ? 1 : 0;
                                                if (root.service)
                                                    root.service.updateNoteFrontmatter({ "bookmarked": nextBm });
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Top Translucent Tape Strip (`.cv-recipe-photo-card::before`)
                        Rectangle {
                            id: recipeHeroTape
                            objectName: "nexusRecipeHeroTape"
                            width: 112
                            height: 22
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 0
                            rotation: -3
                            radius: 3
                            color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.20)
                            border.width: 1
                            border.color: Qt.rgba(root.textStrong.r, root.textStrong.g, root.textStrong.b, 0.25)
                            z: 5
                        }
                    }

                    // Middle: Title Block (`.cv-recipe-title-block`)
                    ColumnLayout {
                        id: recipeTitleBlock
                        objectName: "nexusRecipeTitleBlock"
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 10

                        // Eyebrow (`RECIPE_CATEGORY · CUISINE`) + Inline editor for category/cuisine
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                id: recipeEyebrowText
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            wrapMode: Text.Wrap
                                objectName: "nexusRecipeEyebrow"
                                visible: root.recipeEditingField !== "recipe_category" && root.recipeEditingField !== "cuisine"
                                text: {
                                    const cat = String(root.rView.recipeCategory || root.dossier.category || "Recipe").trim();
                                    const cui = String(root.rView.cuisine || root.dossier.cuisine || "").trim();
                                    return (cui.length > 0 ? (cat + " · " + cui) : cat).toUpperCase();
                                }
                                font.pixelSize: 10
                                font.weight: Font.Bold
                                font.letterSpacing: 1.8
                                color: root.accentColor

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.recipeDraftTextA = String(root.rView.cuisine || root.dossier.cuisine || "");
                                        root.recipeEditingField = "cuisine";
                                        root.recipeEditingIndex = -1;
                                    }
                                }
                            }

                            Rectangle {
                                objectName: "nexusRecipeSyncApiButton"
                                visible: root.recipeEditingField !== "recipe_category" && root.recipeEditingField !== "cuisine"
                                radius: 5
                                color: recipeApiFetchHover.containsMouse ? root.cardHoverBg : root.cardRaisedBg
                                border.width: 1
                                border.color: root.borderAccent
                                implicitWidth: recipeApiFetchRow.implicitWidth + 14
                                implicitHeight: 24

                                RowLayout {
                                    id: recipeApiFetchRow
                                    anchors.centerIn: parent
                                    spacing: 4
                                    MaterialSymbol { text: "cloud_download"; iconSize: 13; color: root.accentColor }
                                    Text {
                                        text: "Sync Recipe"
                                        font.pixelSize: 10
                                        font.weight: Font.DemiBold
                                        color: root.accentColor
                                    }
                                }
                                MouseArea {
                                    id: recipeApiFetchHover
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (root.service)
                                            root.service.fetchMediaMetadataForCurrentNote();
                                    }
                                }
                            }

                            RowLayout {
                                visible: root.recipeEditingField === "recipe_category" || root.recipeEditingField === "cuisine"
                                Layout.fillWidth: true
                                spacing: 6
                                TextField {
                                    id: recipeEyebrowEditor
                                    Layout.preferredWidth: 180
                                    implicitHeight: 26
                                    text: root.recipeDraftTextA
                                    placeholderText: root.recipeEditingField === "recipe_category" ? "Category (e.g. Street Food)" : "Cuisine (e.g. Vietnamese)"
                                    placeholderTextColor: root.textMuted
                                    font.pixelSize: 11
                                    color: root.textPrimary
                                    background: Rectangle {
                                        radius: 5
                                        color: root.cardDeepBg
                                        border.width: 1
                                        border.color: root.accentColor
                                    }
                                    onVisibleChanged: if (visible) forceActiveFocus()
                                    onAccepted: {
                                        if (root.service) {
                                            const patch = ({});
                                            patch[root.recipeEditingField] = text.trim();
                                            root.service.updateNoteFrontmatter(patch);
                                        }
                                        root.recipeEditingField = "";
                                        root.restoreWorkspaceFocus();
                                    }
                                    Keys.onEscapePressed: event => {
                                        root.recipeEditingField = "";
                                        root.restoreWorkspaceFocus();
                                        event.accepted = true;
                                    }
                                    Keys.onPressed: event => root.forwardWorkspaceShortcut(event)
                                }
                                Rectangle {
                                    radius: 5
                                    color: root.accentColor
                                    implicitWidth: 44
                                    implicitHeight: 26
                                    Text { anchors.centerIn: parent; text: "Save"; font.pixelSize: 10; font.weight: Font.Bold; color: root.onAccentColor }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: recipeEyebrowEditor.accepted()
                                    }
                                }
                            }
                        }

                        // Dish Title (`.cv-recipe-title`)
                        Text {
                            id: recipeTitleText
                            objectName: "nexusRecipeTitle"
                            Layout.fillWidth: true
                            text: String(root.doc?.title || root.dossier.title || "Untitled Recipe")
                            font.pixelSize: 34
                            font.weight: Font.Bold
                            color: root.textStrong
                            wrapMode: Text.Wrap
                        }

                        // Tagline (`.cv-recipe-tagline` — click to edit `tagline` frontmatter)
                        Text {
                            id: recipeTaglineText
                            objectName: "nexusRecipeTagline"
                            visible: root.recipeEditingField !== "tagline"
                            Layout.fillWidth: true
                            readonly property string rawTagline: String(root.rView.tagline || root.dossier.subtitle || "").trim()
                            text: rawTagline.length > 0 ? rawTagline : "Click to add a short culinary tagline..."
                            font.pixelSize: 14
                            font.italic: true
                            color: rawTagline.length > 0 ? root.textSecondary : root.textMuted
                            wrapMode: Text.Wrap

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.IBeamCursor
                                onClicked: {
                                    root.recipeDraftTextA = String(root.rView.tagline || root.dossier.subtitle || "");
                                    root.recipeEditingField = "tagline";
                                    root.recipeEditingIndex = -1;
                                }
                            }
                        }

                        RowLayout {
                            visible: root.recipeEditingField === "tagline"
                            Layout.fillWidth: true
                            spacing: 6
                            TextField {
                                id: recipeTaglineEditor
                                objectName: "nexusRecipeTaglineEditor"
                                Layout.fillWidth: true
                                implicitHeight: 28
                                text: root.recipeDraftTextA
                                placeholderText: "Short tagline for this dish..."
                                placeholderTextColor: root.textMuted
                                font.pixelSize: 12
                                font.italic: true
                                color: root.textPrimary
                                background: Rectangle {
                                    radius: 6
                                    color: root.cardDeepBg
                                    border.width: 1
                                    border.color: root.accentColor
                                }
                                onVisibleChanged: if (visible) forceActiveFocus()
                                onAccepted: {
                                    if (root.service)
                                        root.service.updateNoteFrontmatter({ "tagline": text.trim() });
                                    root.recipeEditingField = "";
                                    root.restoreWorkspaceFocus();
                                }
                                Keys.onEscapePressed: event => {
                                    root.recipeEditingField = "";
                                    root.restoreWorkspaceFocus();
                                    event.accepted = true;
                                }
                                Keys.onPressed: event => root.forwardWorkspaceShortcut(event)
                            }
                            Rectangle {
                                radius: 5
                                color: root.accentColor
                                implicitWidth: 46
                                implicitHeight: 28
                                Text { anchors.centerIn: parent; text: "Save"; font.pixelSize: 10; font.weight: Font.Bold; color: root.onAccentColor }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: recipeTaglineEditor.accepted()
                                }
                            }
                        }

                        // Edit-state hint caption (`.cv-recipe-edit-state`)
                        Text {
                            objectName: "nexusRecipeEditStateHint"
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            wrapMode: Text.Wrap
                            text: "Click text to edit · Click active section pill again to show all"
                            font.pixelSize: 10
                            font.family: Appearance.font.family.monospace
                            color: root.textMuted
                        }
                    }

                    // Right: Vertical Section Navigation Pills (`Overview`, `Method`, `Personal note` — `.cv-recipe-section-nav`)
                    ColumnLayout {
                        id: recipeSectionNav
                        objectName: "nexusRecipeSectionNav"
                        Layout.preferredWidth: 158
                        Layout.fillWidth: nexusRecipeHero.columns === 1
                        Layout.minimumWidth: 0
                        Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                        spacing: 10

                        Repeater {
                            model: [
                                { "id": "overview", "label": "Overview" },
                                { "id": "method",   "label": "Method" },
                                { "id": "notes",    "label": "Personal note" }
                            ]
                            delegate: Rectangle {
                                required property var modelData
                                required property int index
                                objectName: "nexusRecipeSectionPill_" + String(modelData.id)
                                readonly property bool isActive: root.recipeActiveSection === modelData.id
                                Layout.fillWidth: true
                                implicitHeight: 38
                                radius: 19
                                color: isActive
                                    ? root.accentColor
                                    : (secPillMouse.containsMouse ? root.cardHoverBg : root.cardRaisedBg)
                                border.width: 1
                                border.color: isActive ? root.accentColor : root.borderSubtle

                                Text {
                                    id: secPillLbl
                                    anchors.centerIn: parent
                                    text: modelData.label
                                    font.pixelSize: 11
                                    font.weight: Font.Bold
                                    color: isActive ? root.onAccentColor : root.textPrimary
                                }

                                MouseArea {
                                    id: secPillMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.recipeActiveSection = (root.recipeActiveSection === modelData.id ? "all" : modelData.id);
                                    }
                                }
                            }
                        }
                    }
                }

                // -------------------------------------------------------------
                // 5.2 OVERVIEW SECTION (`Stats Bar` + `Description` + `Ingredients`)
                // -------------------------------------------------------------
                ColumnLayout {
                    id: recipeOverviewSection
                    objectName: "nexusRecipeOverviewSection"
                    visible: root.recipeActiveSection === "all" || root.recipeActiveSection === "overview"
                    Layout.fillWidth: true
                    spacing: 18

                    // 4-Column Stats Bar (`SERVINGS`, `PREP TIME`, `COOK TIME`, `DIFFICULTY` — `.cv-recipe-stats`)
                    Rectangle {
                        id: recipeStatsBar
                        objectName: "nexusRecipeStatsBar"
                        Layout.fillWidth: true
                        implicitHeight: recipeStatsGrid.implicitHeight + 20
                        radius: 14
                        color: root.cardBg
                        border.width: 1
                        border.color: root.borderSubtle

                        GridLayout {
                            id: recipeStatsGrid
                            anchors.fill: parent
                            anchors.margins: 10
                            columns: width >= 480 ? 4 : 2
                            columnSpacing: 10
                            rowSpacing: 10

                            Repeater {
                                model: [
                                    { "key": "servings",   "label": "SERVINGS",   "raw": String(root.rView.servings || root.dossier.servings || ""),     "value": root.formatRecipeScalar("servings", root.rView.servings || root.dossier.servings) },
                                    { "key": "prep_time",  "label": "PREP TIME",  "raw": String(root.rView.prepTime || root.dossier.prepTime || ""),     "value": root.formatRecipeScalar("prep_time", root.rView.prepTime || root.dossier.prepTime) },
                                    { "key": "cook_time",  "label": "COOK TIME",  "raw": String(root.rView.cookTime || root.dossier.cookTime || ""),     "value": root.formatRecipeScalar("cook_time", root.rView.cookTime || root.dossier.cookTime) },
                                    { "key": "difficulty", "label": "DIFFICULTY", "raw": String(root.rView.difficulty || root.dossier.difficulty || ""), "value": root.formatRecipeScalar("difficulty", root.rView.difficulty || root.dossier.difficulty) }
                                ]
                                delegate: Rectangle {
                                    required property var modelData
                                    required property int index
                                    objectName: "nexusRecipeStatCard_" + String(modelData.key)
                                    Layout.minimumWidth: 0
                                    Layout.preferredHeight: 54
                                    readonly property bool isEditingThisStat: root.recipeEditingField === modelData.key
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    radius: 10
                                    color: statCardMouse.containsMouse || isEditingThisStat ? root.cardRaisedBg : root.cardDeepBg
                                    border.width: 1
                                    border.color: isEditingThisStat ? root.accentColor : root.borderSubtle

                                    ColumnLayout {
                                        visible: !isEditingThisStat
                                        anchors.centerIn: parent
                                        spacing: 3
                                        Text {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: modelData.label
                                            font.pixelSize: 9
                                            font.weight: Font.Bold
                                            font.letterSpacing: 1.5
                                            color: root.textMuted
                                        }
                                        Text {
                                            objectName: "nexusRecipeStatValue_" + String(modelData.key)
                                            Layout.alignment: Qt.AlignHCenter
                                            text: modelData.value
                                            font.pixelSize: 15
                                            font.weight: Font.Bold
                                            color: root.textStrong
                                        }
                                    }

                                    MouseArea {
                                        id: statCardMouse
                                        visible: !isEditingThisStat
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.recipeDraftTextA = modelData.raw || (modelData.value === "—" ? "" : modelData.value);
                                            root.recipeEditingField = modelData.key;
                                            root.recipeEditingIndex = -1;
                                        }
                                    }

                                    RowLayout {
                                        visible: isEditingThisStat
                                        anchors.fill: parent
                                        anchors.margins: 6
                                        spacing: 4
                                        TextField {
                                            id: statInput
                                            objectName: "nexusRecipeStatInput_" + String(modelData.key)
                                            Layout.fillWidth: true
                                            implicitHeight: 28
                                            text: root.recipeDraftTextA
                                            placeholderText: modelData.label
                                            placeholderTextColor: root.textMuted
                                            font.pixelSize: 12
                                            color: root.textPrimary
                                            background: Rectangle {
                                                radius: 5
                                                color: root.cardBg
                                                border.width: 1
                                                border.color: root.accentColor
                                            }
                                            onVisibleChanged: {
                                                if (visible) {
                                                    forceActiveFocus();
                                                    selectAll();
                                                }
                                            }
                                            function commitStat() {
                                                if (root.service) {
                                                    const patch = ({});
                                                    patch[modelData.key] = statInput.text.trim();
                                                    root.service.updateNoteFrontmatter(patch);
                                                }
                                                root.recipeEditingField = "";
                                                root.restoreWorkspaceFocus();
                                            }
                                            onAccepted: commitStat()
                                            Keys.onEscapePressed: event => {
                                                root.recipeEditingField = "";
                                                root.restoreWorkspaceFocus();
                                                event.accepted = true;
                                            }
                                            Keys.onPressed: event => root.forwardWorkspaceShortcut(event)
                                        }
                                        Rectangle {
                                            objectName: "nexusRecipeStatSave_" + String(modelData.key)
                                            radius: 5
                                            color: root.accentColor
                                            implicitWidth: 38
                                            implicitHeight: 28
                                            Text { anchors.centerIn: parent; text: "OK"; font.pixelSize: 9; font.weight: Font.Bold; color: root.onAccentColor }
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: statInput.commitStat()
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // 2-Column Side-by-Side Overview Grid (`Description` on left, `Ingredients` card on right — `.cv-recipe-overview-grid`)
                    GridLayout {
                        id: recipeOverviewGrid
                        objectName: "nexusRecipeOverviewGrid"
                        Layout.fillWidth: true
                        columns: width >= 680 ? 2 : 1
                        columnSpacing: 22
                        rowSpacing: 18

                        // Left Column: Description Prose Card + Nutrition & Macros Breakdown Card
                        ColumnLayout {
                            id: recipeOverviewLeftCol
                            Layout.fillWidth: true
                            Layout.preferredWidth: 560
                            Layout.alignment: Qt.AlignTop
                            spacing: 16

                            readonly property var nutritionInfo: root.extractRecipeNutrition()

                            Rectangle {
                                id: recipeDescriptionBox
                                objectName: "nexusRecipeDescriptionBox"
                                Layout.fillWidth: true
                                readonly property int minOverviewDescHeight: root.recipeActiveSection === "overview"
                                    ? Math.max(180, root.minDocumentSurfaceHeight - nexusRecipeHero.implicitHeight - recipeStatsBar.implicitHeight - recipeNutritionCard.implicitHeight - 110)
                                    : 96
                                implicitHeight: Math.max(
                                    minOverviewDescHeight,
                                    (root.recipeEditingField === "description" ? recipeDescEditCol.implicitHeight : recipeDescTxt.implicitHeight) + 32
                                )
                                radius: 12
                                color: root.cardBg
                                border.width: 1
                                border.color: root.recipeEditingField === "description" ? root.accentColor : root.borderSubtle

                                // Left 3px accent bar (`.cv-recipe-description` border-left)
                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    width: 3
                                    radius: 1.5
                                    color: root.accentColor
                                }

                                Text {
                                    id: recipeDescTxt
                                    objectName: "nexusRecipeDescriptionText"
                                    visible: root.recipeEditingField !== "description"
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: 16
                                    anchors.leftMargin: 20
                                    readonly property string rawDesc: String(root.rView.description || root.dossier.plot || "").trim()
                                    text: rawDesc.length > 0 ? rawDesc : "Click to add a description of this recipe..."
                                    font.pixelSize: 13
                                    font.italic: rawDesc.length === 0
                                    lineHeight: 1.45
                                    color: rawDesc.length > 0 ? root.textPrimary : root.textMuted
                                    wrapMode: Text.Wrap

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.IBeamCursor
                                        onClicked: {
                                            root.recipeDraftTextA = String(root.rView.description || root.dossier.plot || "");
                                            root.recipeEditingField = "description";
                                            root.recipeEditingIndex = -1;
                                        }
                                    }
                                }

                                ColumnLayout {
                                    id: recipeDescEditCol
                                    visible: root.recipeEditingField === "description"
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: 12
                                    anchors.leftMargin: 16
                                    spacing: 8

                                    TextArea {
                                        id: recipeDescEditor
                                        objectName: "nexusRecipeDescriptionEditor"
                                        Layout.fillWidth: true
                                        Layout.minimumHeight: 72
                                        text: root.recipeDraftTextA
                                        placeholderText: "Describe the dish, flavor profile, or origin..."
                                        placeholderTextColor: root.textMuted
                                        font.pixelSize: 13
                                        color: root.textPrimary
                                        wrapMode: TextEdit.Wrap
                                        background: Item {}
                                        onVisibleChanged: if (visible) Qt.callLater(() => { if (recipeDescEditor.visible) recipeDescEditor.forceActiveFocus(); })
                                        onActiveFocusChanged: {
                                            if (!activeFocus && visible && root.recipeEditingField === "description" && root.noteKind === "recipe" && !recipeDescCancelMouse.containsMouse && !recipeDescCancelMouse.pressed) {
                                                if (root.service)
                                                    root.service.updateNoteFrontmatter({ "description": recipeDescEditor.text.trim() });
                                                root.recipeEditingField = "";
                                            }
                                        }
                                        Keys.onEscapePressed: event => {
                                            if (root.service)
                                                root.service.updateNoteFrontmatter({ "description": recipeDescEditor.text.trim() });
                                            root.recipeEditingField = "";
                                            root.restoreWorkspaceFocus();
                                            event.accepted = true;
                                        }
                                        Keys.onPressed: event => {
                                            if ((event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_S)) {
                                                if (root.service)
                                                    root.service.updateNoteFrontmatter({ "description": recipeDescEditor.text.trim() });
                                                root.recipeEditingField = "";
                                                root.restoreWorkspaceFocus();
                                                event.accepted = true;
                                                return;
                                            }
                                            root.forwardWorkspaceShortcut(event);
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Item { Layout.fillWidth: true }
                                        Rectangle {
                                            radius: 5
                                            color: root.cardRaisedBg
                                            border.width: 1
                                            border.color: root.borderSubtle
                                            implicitWidth: 52
                                            implicitHeight: 24
                                            Text { anchors.centerIn: parent; text: "Cancel"; font.pixelSize: 10; color: root.textSecondary }
                                            MouseArea {
                                                id: recipeDescCancelMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    root.recipeEditingField = "";
                                                    root.restoreWorkspaceFocus();
                                                }
                                            }
                                        }
                                        Rectangle {
                                            objectName: "nexusRecipeDescriptionSaveButton"
                                            radius: 5
                                            color: root.accentColor
                                            implicitWidth: 52
                                            implicitHeight: 24
                                            Text { anchors.centerIn: parent; text: "Save"; font.pixelSize: 10; font.weight: Font.Bold; color: root.onAccentColor }
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    if (root.service)
                                                        root.service.updateNoteFrontmatter({ "description": recipeDescEditor.text.trim() });
                                                    root.recipeEditingField = "";
                                                    root.restoreWorkspaceFocus();
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // Nutrition & Macros Breakdown Card (Auto-Themed 4-Tile Macro Card)
                            Rectangle {
                                id: recipeNutritionCard
                                objectName: "nexusRecipeNutritionCard"
                                Layout.fillWidth: true
                                implicitHeight: recipeNutritionCol.implicitHeight + 28
                                radius: 14
                                color: root.cardBg
                                border.width: 1
                                border.color: root.borderSubtle

                                ColumnLayout {
                                    id: recipeNutritionCol
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: 14
                                    spacing: 10

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8

                                        ColumnLayout {
                                            spacing: 1
                                            Text {
                                                text: "NUTRITION & MACROS"
                                                font.family: Appearance.font.family.monospace
                                                font.pixelSize: 9
                                                font.weight: Font.Bold
                                                font.letterSpacing: 1.5
                                                color: root.accentColor
                                            }
                                            Text {
                                                text: "Per serving breakdown"
                                                font.pixelSize: 15
                                                font.weight: Font.Bold
                                                color: root.textStrong
                                            }
                                        }

                                        Item { Layout.fillWidth: true }

                                        Rectangle {
                                            visible: String(recipeOverviewLeftCol.nutritionInfo.costPerServing ?? "").length > 0
                                            radius: 10
                                            implicitHeight: 22
                                            implicitWidth: costBadgeTxt.implicitWidth + 14
                                            color: root.journalSubSurfaceBg
                                            border.width: 1
                                            border.color: root.borderSubtle
                                            Text {
                                                id: costBadgeTxt
                                                objectName: "nexusRecipeCostBadgeText"
                                                anchors.centerIn: parent
                                                text: String(recipeOverviewLeftCol.nutritionInfo.costPerServing ?? "")
                                                font.family: Appearance.font.family.monospace
                                                font.pixelSize: 10
                                                color: root.textSecondary
                                            }
                                        }

                                        Rectangle {
                                            visible: String(recipeOverviewLeftCol.nutritionInfo.scoreLabel ?? "").length > 0
                                            radius: 10
                                            implicitHeight: 22
                                            implicitWidth: scoreBadgeTxt.implicitWidth + 14
                                            color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.14)
                                            border.width: 1
                                            border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.45)
                                            Text {
                                                id: scoreBadgeTxt
                                                objectName: "nexusRecipeScoreBadgeText"
                                                anchors.centerIn: parent
                                                text: "Score " + String(recipeOverviewLeftCol.nutritionInfo.scoreLabel ?? "")
                                                font.family: Appearance.font.family.monospace
                                                font.pixelSize: 10
                                                font.weight: Font.Bold
                                                color: root.accentColor
                                            }
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8

                                        Repeater {
                                            model: [
                                                {
                                                    "key": "calories",
                                                    "label": "CALORIES",
                                                    "value": String(recipeOverviewLeftCol.nutritionInfo.calories ?? "—"),
                                                    "ratio": recipeOverviewLeftCol.nutritionInfo.caloriesNum > 0 ? Math.min(1, recipeOverviewLeftCol.nutritionInfo.caloriesNum / 850.0) : 0,
                                                    "barColor": root.accentColor
                                                },
                                                {
                                                    "key": "protein",
                                                    "label": "PROTEIN",
                                                    "value": String(recipeOverviewLeftCol.nutritionInfo.protein ?? "—"),
                                                    "ratio": Number(recipeOverviewLeftCol.nutritionInfo.proteinRatio ?? 0),
                                                    "barColor": root.accentColor
                                                },
                                                {
                                                    "key": "fat",
                                                    "label": "FAT",
                                                    "value": String(recipeOverviewLeftCol.nutritionInfo.fat ?? "—"),
                                                    "ratio": Number(recipeOverviewLeftCol.nutritionInfo.fatRatio ?? 0),
                                                    "barColor": root.exerciseSecondaryMuscleColor
                                                },
                                                {
                                                    "key": "carbs",
                                                    "label": "CARBS",
                                                    "value": String(recipeOverviewLeftCol.nutritionInfo.carbs ?? "—"),
                                                    "ratio": Number(recipeOverviewLeftCol.nutritionInfo.carbsRatio ?? 0),
                                                    "barColor": Qt.lighter(root.accentColor, 1.25)
                                                }
                                            ]
                                            delegate: Rectangle {
                                                required property var modelData
                                                objectName: "nexusRecipeMacroTile_" + String(modelData.key)
                                                Layout.fillWidth: true
                                                Layout.preferredWidth: 1
                                                implicitHeight: 62
                                                radius: 10
                                                color: root.cardDeepBg
                                                border.width: 1
                                                border.color: root.borderSubtle

                                                ColumnLayout {
                                                    anchors.fill: parent
                                                    anchors.margins: 9
                                                    spacing: 3

                                                    Text {
                                                        text: modelData.label
                                                        font.family: Appearance.font.family.monospace
                                                        font.pixelSize: 9
                                                        font.weight: Font.Bold
                                                        font.letterSpacing: 1.2
                                                        color: root.textMuted
                                                    }

                                                    Text {
                                                        objectName: "nexusRecipeMacroValue_" + String(modelData.key)
                                                        Layout.fillWidth: true
                                                        text: modelData.value
                                                        font.family: Appearance.font.family.monospace
                                                        font.pixelSize: 14
                                                        font.weight: Font.Bold
                                                        color: modelData.value === "—" ? root.textMuted : root.textStrong
                                                        elide: Text.ElideRight
                                                    }

                                                    Rectangle {
                                                        Layout.fillWidth: true
                                                        implicitHeight: 4
                                                        radius: 2
                                                        color: root.journalSubSurfaceBg

                                                        Rectangle {
                                                            width: parent.width * Math.max(0, Math.min(1, Number(modelData.ratio ?? 0)))
                                                            height: parent.height
                                                            radius: 2
                                                            color: modelData.barColor
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Right Column: Ingredients Card (`.cv-recipe-card--ingredients` with `Name | Amount` split rows + `+ Ingredient`)
                        Rectangle {
                            id: recipeIngredientsCard
                            objectName: "nexusRecipeIngredientsCard"
                            Layout.fillWidth: true
                            Layout.preferredWidth: 410
                            Layout.alignment: Qt.AlignTop
                            implicitHeight: recipeIngredientsCol.implicitHeight + 36
                            radius: 16
                            color: root.cardBg
                            border.width: 1
                            border.color: root.borderSubtle

                            ColumnLayout {
                                id: recipeIngredientsCol
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 18
                                spacing: 12

                                // Header (`WHAT YOU NEED` / `Ingredients` + `+ Ingredient`)
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10
                                    ColumnLayout {
                                        spacing: 2
                                        Text {
                                            text: "WHAT YOU NEED"
                                            font.pixelSize: 9
                                            font.weight: Font.Bold
                                            font.letterSpacing: 1.6
                                            color: root.accentColor
                                        }
                                        Text {
                                            text: "Ingredients"
                                            font.pixelSize: 20
                                            font.weight: Font.Bold
                                            color: root.textStrong
                                        }
                                    }
                                    Item { Layout.fillWidth: true }
                                    Rectangle {
                                        id: addIngredientBtn
                                        objectName: "nexusRecipeAddIngredientButton"
                                        radius: 14
                                        implicitHeight: 28
                                        implicitWidth: addIngLbl.implicitWidth + 22
                                        color: addIngMouse.containsMouse ? root.accentColor : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.14)
                                        border.width: 1
                                        border.color: root.accentColor
                                        Text {
                                            id: addIngLbl
                                            anchors.centerIn: parent
                                            text: "+ Ingredient"
                                            font.pixelSize: 10
                                            font.weight: Font.Bold
                                            color: addIngMouse.containsMouse ? root.onAccentColor : root.accentColor
                                        }
                                        MouseArea {
                                            id: addIngMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                root.appendRecipeListItem("ingredients", root.rView.ingredients, "New ingredient | 1 tbsp", "ingredient");
                                            }
                                        }
                                    }
                                }

                                Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: root.borderSubtle }

                                // Ingredients List (`Name` on left, optional `Amount` on right when `|` present, matching `.cv-recipe-ingredients`)
                                ColumnLayout {
                                    id: recipeIngredientList
                                    objectName: "nexusRecipeIngredientList"
                                    Layout.fillWidth: true
                                    spacing: 0

                                    Repeater {
                                        model: root.rView.ingredients ?? []
                                        delegate: Item {
                                            id: ingRowItem
                                            required property string modelData
                                            required property int index
                                            objectName: "nexusRecipeIngredientRow_" + String(index)
                                            readonly property var splitParts: root.splitRecipeIngredient(modelData)
                                            readonly property bool hasAmount: String(splitParts.amount ?? "").length > 0
                                            readonly property bool isChecked: root.isRecipeIngredientChecked(index)
                                            readonly property bool isEditingThisRow: root.recipeEditingField === "ingredient" && root.recipeEditingIndex === index
                                            Layout.fillWidth: true
                                            implicitHeight: isEditingThisRow ? 44 : Math.max(40, ingNameTxt.implicitHeight + 16)

                                            // Reading Row
                                            RowLayout {
                                                visible: !ingRowItem.isEditingThisRow
                                                anchors.fill: parent
                                                spacing: 10

                                                // Checkbox
                                                Rectangle {
                                                    objectName: "nexusRecipeIngredientCheckbox_" + String(ingRowItem.index)
                                                    width: 18
                                                    height: 18
                                                    radius: 5
                                                    color: ingRowItem.isChecked ? root.accentColor : "transparent"
                                                    border.width: 1.5
                                                    border.color: ingRowItem.isChecked ? root.accentColor : root.borderAccent

                                                    MaterialSymbol {
                                                        visible: ingRowItem.isChecked
                                                        anchors.centerIn: parent
                                                        text: "check"
                                                        iconSize: 13
                                                        color: root.onAccentColor
                                                    }

                                                    MouseArea {
                                                        anchors.fill: parent
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            const next = Object.assign({}, root.checkedIngredients);
                                                            next[ingRowItem.index] = !ingRowItem.isChecked;
                                                            root.checkedIngredients = next;
                                                            const ingList = root.rView?.ingredients ?? [];
                                                            const doneIndices = [];
                                                            for (let i = 0; i < ingList.length; ++i) {
                                                                if (root.isRecipeIngredientChecked(i))
                                                                    doneIndices.push(i);
                                                            }
                                                            if (root.service)
                                                                root.service.updateNoteFrontmatter({ "ingredients_done": doneIndices });
                                                        }
                                                    }
                                                }

                                                // Ingredient Name (`.cv-recipe-ingredient-name`)
                                                Text {
                                                    id: ingNameTxt
                                                    objectName: "nexusRecipeIngredientName_" + String(ingRowItem.index)
                                                    Layout.fillWidth: true
                                                    text: String(ingRowItem.splitParts.name || ingRowItem.modelData)
                                                    font.pixelSize: 13
                                                    font.weight: Font.Medium
                                                    font.strikeout: ingRowItem.isChecked
                                                    color: ingRowItem.isChecked ? root.textMuted : root.textPrimary
                                                    wrapMode: Text.Wrap

                                                    MouseArea {
                                                        anchors.fill: parent
                                                        cursorShape: Qt.IBeamCursor
                                                        onClicked: {
                                                            root.recipeDraftTextA = String(ingRowItem.splitParts.name || "");
                                                            root.recipeDraftTextB = String(ingRowItem.splitParts.amount || "");
                                                            root.recipeEditingField = "ingredient";
                                                            root.recipeEditingIndex = ingRowItem.index;
                                                        }
                                                    }
                                                }

                                                // Ingredient Amount (`.cv-recipe-ingredient-amount` — only shown when `|` amount exists)
                                                Text {
                                                    id: ingAmountTxt
                                                    objectName: "nexusRecipeIngredientAmount_" + String(ingRowItem.index)
                                                    visible: ingRowItem.hasAmount
                                                    text: String(ingRowItem.splitParts.amount ?? "")
                                                    font.pixelSize: 12
                                                    font.family: Appearance.font.family.monospace
                                                    font.weight: Font.DemiBold
                                                    font.strikeout: ingRowItem.isChecked
                                                    color: ingRowItem.isChecked ? root.textMuted : root.accentColor

                                                    MouseArea {
                                                        anchors.fill: parent
                                                        cursorShape: Qt.IBeamCursor
                                                        onClicked: {
                                                            root.recipeDraftTextA = String(ingRowItem.splitParts.name || "");
                                                            root.recipeDraftTextB = String(ingRowItem.splitParts.amount || "");
                                                            root.recipeEditingField = "ingredient";
                                                            root.recipeEditingIndex = ingRowItem.index;
                                                        }
                                                    }
                                                }
                                            }

                                            // Inline Split Editor (`Name` + `Amount`)
                                            RowLayout {
                                                visible: ingRowItem.isEditingThisRow
                                                anchors.fill: parent
                                                anchors.topMargin: 4
                                                anchors.bottomMargin: 4
                                                spacing: 6

                                                TextField {
                                                    id: ingNameInput
                                                    objectName: "nexusRecipeIngredientNameInput_" + String(ingRowItem.index)
                                                    Layout.fillWidth: true
                                                    implicitHeight: 30
                                                    text: root.recipeDraftTextA
                                                    placeholderText: "Ingredient name"
                                                    placeholderTextColor: root.textMuted
                                                    font.pixelSize: 12
                                                    color: root.textPrimary
                                                    background: Rectangle {
                                                        radius: 5
                                                        color: root.cardDeepBg
                                                        border.width: 1
                                                        border.color: root.accentColor
                                                    }
                                                    onVisibleChanged: if (visible) forceActiveFocus()
                                                    onAccepted: ingSaveBtn.commitIng()
                                                    Keys.onEscapePressed: event => {
                                                        root.recipeEditingField = "";
                                                        root.recipeEditingIndex = -1;
                                                        root.restoreWorkspaceFocus();
                                                        event.accepted = true;
                                                    }
                                                    Keys.onPressed: event => root.forwardWorkspaceShortcut(event)
                                                }

                                                TextField {
                                                    id: ingAmountInput
                                                    objectName: "nexusRecipeIngredientAmountInput_" + String(ingRowItem.index)
                                                    Layout.preferredWidth: 130
                                                    implicitHeight: 30
                                                    text: root.recipeDraftTextB
                                                    placeholderText: "Amount (optional)"
                                                    placeholderTextColor: root.textMuted
                                                    font.pixelSize: 12
                                                    font.family: Appearance.font.family.monospace
                                                    color: root.textPrimary
                                                    background: Rectangle {
                                                        radius: 5
                                                        color: root.cardDeepBg
                                                        border.width: 1
                                                        border.color: root.accentColor
                                                    }
                                                    onAccepted: ingSaveBtn.commitIng()
                                                    Keys.onEscapePressed: event => {
                                                        root.recipeEditingField = "";
                                                        root.recipeEditingIndex = -1;
                                                        root.restoreWorkspaceFocus();
                                                        event.accepted = true;
                                                    }
                                                    Keys.onPressed: event => root.forwardWorkspaceShortcut(event)
                                                }

                                                Rectangle {
                                                    id: ingSaveBtn
                                                    objectName: "nexusRecipeIngredientSave_" + String(ingRowItem.index)
                                                    radius: 5
                                                    color: root.accentColor
                                                    implicitWidth: 44
                                                    implicitHeight: 30
                                                    function commitIng() {
                                                        const joined = root.joinRecipeIngredient(ingNameInput.text, ingAmountInput.text);
                                                        root.updateRecipeListItem("ingredients", root.rView.ingredients, ingRowItem.index, joined);
                                                    }
                                                    Text { anchors.centerIn: parent; text: "Save"; font.pixelSize: 10; font.weight: Font.Bold; color: root.onAccentColor }
                                                    MouseArea {
                                                        anchors.fill: parent
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: ingSaveBtn.commitIng()
                                                    }
                                                }
                                            }

                                            Rectangle {
                                                visible: ingRowItem.index < ((root.rView.ingredients ?? []).length - 1)
                                                anchors.left: parent.left
                                                anchors.right: parent.right
                                                anchors.bottom: parent.bottom
                                                height: 1
                                                color: Qt.rgba(root.borderSubtle.r, root.borderSubtle.g, root.borderSubtle.b, 0.55)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // -------------------------------------------------------------
                // 5.3 METHOD SECTION (`Instructions` Connected Step Rail + `Tips` & `Pairs Well With`)
                // -------------------------------------------------------------
                ColumnLayout {
                    id: recipeMethodSection
                    objectName: "nexusRecipeMethodSection"
                    visible: root.recipeActiveSection === "all" || root.recipeActiveSection === "method"
                    Layout.fillWidth: true
                    spacing: 18

                    // Instructions Card (`.cv-recipe-card--instructions`)
                    Rectangle {
                        id: recipeInstructionsCard
                        objectName: "nexusRecipeInstructionsCard"
                        Layout.fillWidth: true
                        readonly property int minMethodCardHeight: root.recipeActiveSection === "method"
                            ? Math.max(260, root.minDocumentSurfaceHeight - nexusRecipeHero.implicitHeight - 210)
                            : 0
                        implicitHeight: Math.max(minMethodCardHeight, recipeInstructionsCol.implicitHeight + 36)
                        radius: 16
                        color: root.cardBg
                        border.width: 1
                        border.color: root.borderSubtle

                        ColumnLayout {
                            id: recipeInstructionsCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 18
                            spacing: 14

                            // Header (`STEP BY STEP` / `Instructions` + Step Progress Counter + `+ Step`)
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10
                                Item {
                                    implicitWidth: recipeInstTitleCol.implicitWidth
                                    implicitHeight: recipeInstTitleCol.implicitHeight
                                    ColumnLayout {
                                        id: recipeInstTitleCol
                                        spacing: 2
                                        Text {
                                            text: "STEP BY STEP"
                                            font.pixelSize: 9
                                            font.weight: Font.Bold
                                            font.letterSpacing: 1.6
                                            color: root.accentColor
                                        }
                                        Text {
                                            objectName: "nexusRecipeInstructionsHeaderTitle"
                                            text: "Instructions"
                                            font.pixelSize: 20
                                            font.weight: Font.Bold
                                            color: recipeInstTitleMouse.containsMouse ? root.accentColor : root.textStrong
                                        }
                                    }
                                    MouseArea {
                                        id: recipeInstTitleMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            const steps = root.rView?.instructions ?? [];
                                            if (steps.length > 0) {
                                                const idx = Math.min(steps.length - 1, Math.max(0, root.recipeActiveStepProgress));
                                                root.recipeDraftTextA = String(steps[idx] ?? "");
                                                root.recipeEditingField = "instruction";
                                                root.recipeEditingIndex = idx;
                                            } else {
                                                root.appendRecipeListItem("instructions", steps, "Describe the next cooking step.", "instruction");
                                            }
                                        }
                                    }
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    id: recipeStepCounter
                                    objectName: "nexusRecipeStepCounter"
                                    readonly property int totalSteps: (root.rView.instructions ?? []).length
                                    readonly property int doneSteps: root.recipeActiveStepProgress
                                    text: totalSteps <= 0
                                        ? "No steps yet"
                                        : (doneSteps >= totalSteps ? ("All " + String(totalSteps) + " steps complete") : (String(doneSteps) + " of " + String(totalSteps) + " complete"))
                                    font.pixelSize: 10
                                    font.family: Appearance.font.family.monospace
                                    font.weight: Font.Bold
                                    color: doneSteps > 0 ? root.accentColor : root.textMuted
                                }
                                Rectangle {
                                    id: addStepBtn
                                    objectName: "nexusRecipeAddStepButton"
                                    radius: 14
                                    implicitHeight: 28
                                    implicitWidth: addStepLbl.implicitWidth + 22
                                    color: addStepMouse.containsMouse ? root.accentColor : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.14)
                                    border.width: 1
                                    border.color: root.accentColor
                                    Text {
                                        id: addStepLbl
                                        anchors.centerIn: parent
                                        text: "+ Step"
                                        font.pixelSize: 10
                                        font.weight: Font.Bold
                                        color: addStepMouse.containsMouse ? root.onAccentColor : root.accentColor
                                    }
                                    MouseArea {
                                        id: addStepMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.appendRecipeListItem("instructions", root.rView.instructions, "Describe the next cooking step.", "instruction");
                                        }
                                    }
                                }
                            }

                            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: root.borderSubtle }

                            // Connected Sequential Step Checklist (`.cv-recipe-steps`)
                            ColumnLayout {
                                id: recipeInstructionList
                                objectName: "nexusRecipeInstructionList"
                                Layout.fillWidth: true
                                spacing: 0

                                Repeater {
                                    model: root.rView.instructions ?? []
                                    delegate: Item {
                                        id: stepRowItem
                                        required property string modelData
                                        required property int index
                                        objectName: "nexusRecipeStepRow_" + String(index)
                                        readonly property bool isStepDone: index < root.recipeActiveStepProgress
                                        readonly property bool isNextConnectorFilled: (index + 1) < root.recipeActiveStepProgress
                                        readonly property bool isLastStep: index === ((root.rView.instructions ?? []).length - 1)
                                        readonly property bool isEditingThisStep: root.recipeEditingField === "instruction" && root.recipeEditingIndex === index
                                        Layout.fillWidth: true
                                        implicitHeight: isEditingThisStep
                                            ? Math.max(72, stepEditRow.implicitHeight + 20)
                                            : Math.max(60, stepBodyTxt.implicitHeight + 26)

                                        // Vertical 8px Connector Rail between rounded-square step buttons (`.cv-recipe-step-check::after`)
                                        Rectangle {
                                            id: stepConnectorRail
                                            objectName: "nexusRecipeStepRail_" + String(stepRowItem.index)
                                            visible: !stepRowItem.isLastStep
                                            width: 8
                                            x: 11 // Centered under 30px button (15 - 4)
                                            anchors.top: stepCircleBtn.bottom
                                            anchors.bottom: parent.bottom
                                            anchors.bottomMargin: -13
                                            color: stepRowItem.isNextConnectorFilled
                                                ? root.accentColor
                                                : Qt.rgba(root.borderAccent.r, root.borderAccent.g, root.borderAccent.b, 0.35)
                                            z: 1
                                        }

                                        // 30x30 Rounded-Square Step Checkbox (`.cv-recipe-step-check` in `Recipe.css`)
                                        Rectangle {
                                            id: stepCircleBtn
                                            objectName: "nexusRecipeStepButton_" + String(stepRowItem.index)
                                            width: 30
                                            height: 30
                                            x: 0
                                            y: 13
                                            radius: 10
                                            z: 2
                                            color: stepRowItem.isStepDone
                                                ? root.accentColor
                                                : (stepCircleMouse.containsMouse ? root.cardHoverBg : root.cardDeepBg)
                                            border.width: 2
                                            border.color: stepRowItem.isStepDone || stepCircleMouse.containsMouse
                                                ? root.accentColor
                                                : root.borderAccent

                                            Text {
                                                anchors.centerIn: parent
                                                text: stepRowItem.isStepDone ? "✓" : String(stepRowItem.index + 1)
                                                font.pixelSize: 13
                                                font.weight: Font.Bold
                                                color: stepRowItem.isStepDone ? root.onAccentColor : root.accentColor
                                            }

                                            MouseArea {
                                                id: stepCircleMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    const nextProg = stepRowItem.isStepDone ? stepRowItem.index : (stepRowItem.index + 1);
                                                    root.setRecipeStepProgress(nextProg);
                                                }
                                            }
                                        }

                                        // Step Text in Reading mode (click to edit)
                                        Text {
                                            id: stepBodyTxt
                                            objectName: "nexusRecipeStepText_" + String(stepRowItem.index)
                                            visible: !stepRowItem.isEditingThisStep
                                            anchors.left: parent.left
                                            anchors.leftMargin: 46
                                            anchors.right: parent.right
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: stepRowItem.modelData
                                            font.pixelSize: 13
                                            lineHeight: 1.35
                                            font.strikeout: stepRowItem.isStepDone
                                            color: stepRowItem.isStepDone ? root.textMuted : root.textPrimary
                                            wrapMode: Text.Wrap

                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.IBeamCursor
                                                onClicked: {
                                                    root.recipeDraftTextA = stepRowItem.modelData;
                                                    root.recipeEditingField = "instruction";
                                                    root.recipeEditingIndex = stepRowItem.index;
                                                }
                                            }
                                        }

                                        // Step Inline Editor
                                        RowLayout {
                                            id: stepEditRow
                                            visible: stepRowItem.isEditingThisStep
                                            anchors.left: parent.left
                                            anchors.leftMargin: 46
                                            anchors.right: parent.right
                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: 6

                                            TextArea {
                                                id: stepInput
                                                objectName: "nexusRecipeStepInput_" + String(stepRowItem.index)
                                                Layout.fillWidth: true
                                                Layout.minimumHeight: 54
                                                text: root.recipeDraftTextA
                                                font.pixelSize: 13
                                                color: root.textPrimary
                                                wrapMode: TextEdit.Wrap
                                                background: Rectangle {
                                                    radius: 6
                                                    color: root.cardDeepBg
                                                    border.width: 1
                                                    border.color: root.accentColor
                                                }
                                                onVisibleChanged: if (visible) forceActiveFocus()
                                                Keys.onEscapePressed: event => {
                                                    root.recipeEditingField = "";
                                                    root.recipeEditingIndex = -1;
                                                    root.restoreWorkspaceFocus();
                                                    event.accepted = true;
                                                }
                                                Keys.onPressed: event => {
                                                    if ((event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_S)) {
                                                        root.updateRecipeListItem("instructions", root.rView.instructions, stepRowItem.index, stepInput.text);
                                                        event.accepted = true;
                                                        return;
                                                    }
                                                    root.forwardWorkspaceShortcut(event);
                                                }
                                            }

                                            Rectangle {
                                                objectName: "nexusRecipeStepSave_" + String(stepRowItem.index)
                                                radius: 5
                                                color: root.accentColor
                                                implicitWidth: 46
                                                implicitHeight: 30
                                                Text { anchors.centerIn: parent; text: "Save"; font.pixelSize: 10; font.weight: Font.Bold; color: root.onAccentColor }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        root.updateRecipeListItem("instructions", root.rView.instructions, stepRowItem.index, stepInput.text);
                                                    }
                                                }
                                            }
                                        }

                                        Rectangle {
                                            visible: !stepRowItem.isLastStep
                                            anchors.left: parent.left
                                            anchors.leftMargin: 46
                                            anchors.right: parent.right
                                            anchors.bottom: parent.bottom
                                            height: 1
                                            color: Qt.rgba(root.borderSubtle.r, root.borderSubtle.g, root.borderSubtle.b, 0.5)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // 2-Column Taped Lined-Paper Support Grid (`Tips` & `Pairs Well With` — `.cv-recipe-support-grid`)
                    GridLayout {
                        columns: width >= 600 ? 2 : 1
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        columnSpacing: 16
                        rowSpacing: 16

                        // Left: KITCHEN NOTES / Tips (`.cv-recipe-card--tips`)
                        Item {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            Layout.alignment: Qt.AlignTop
                            implicitHeight: tipsCardRect.implicitHeight + 10

                            Rectangle {
                                id: tipsCardRect
                                objectName: "nexusRecipeTipsCard"
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.topMargin: 8
                                implicitHeight: Math.max(170, tipsCol.implicitHeight + 32)
                                radius: 9
                                color: root.cardSubtleBg
                                border.width: 1
                                border.color: root.borderSubtle
                                clip: true

                                // Subtle notebook lines matching Viewing Notes
                                Canvas {
                                    anchors.fill: parent
                                    opacity: 0.25
                                    readonly property color _ruleColor: root.borderSubtle
                                    on_RuleColorChanged: if (visible) requestPaint()
                                    onWidthChanged: if (visible) requestPaint()
                                    onHeightChanged: if (visible) requestPaint()
                                    onVisibleChanged: if (visible) requestPaint()
                                    onPaint: {
                                        const ctx = getContext("2d");
                                        ctx.reset();
                                        ctx.strokeStyle = root.borderSubtle;
                                        ctx.lineWidth = 1;
                                        for (let y = 52; y < height - 12; y += 26) {
                                            ctx.beginPath();
                                            ctx.moveTo(14, y);
                                            ctx.lineTo(width - 14, y);
                                            ctx.stroke();
                                        }
                                    }
                                }

                                ColumnLayout {
                                    id: tipsCol
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: 16
                                    spacing: 8

                                    RowLayout {
                                        Layout.fillWidth: true
                                        ColumnLayout {
                                            spacing: 1
                                            Text { text: "KITCHEN NOTES"; font.pixelSize: 9; font.weight: Font.Bold; font.letterSpacing: 1.5; color: root.accentColor }
                                            Text { text: "Tips"; font.pixelSize: 17; font.weight: Font.Bold; color: root.textStrong }
                                        }
                                        Item { Layout.fillWidth: true }
                                        Rectangle {
                                            objectName: "nexusRecipeAddTipButton"
                                            radius: 12
                                            implicitHeight: 24
                                            implicitWidth: addTipTxt.implicitWidth + 16
                                            color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.14)
                                            border.width: 1
                                            border.color: root.accentColor
                                            Text { id: addTipTxt; anchors.centerIn: parent; text: "+ Tip"; font.pixelSize: 9; font.weight: Font.Bold; color: root.accentColor }
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.appendRecipeListItem("tips", root.rView.tips, "New kitchen tip.", "tip")
                                            }
                                        }
                                    }

                                    Repeater {
                                        model: root.rView.tips ?? []
                                        delegate: Item {
                                            required property string modelData
                                            required property int index
                                            readonly property bool isEditingTip: root.recipeEditingField === "tip" && root.recipeEditingIndex === index
                                            Layout.fillWidth: true
                                            implicitHeight: isEditingTip ? 34 : Math.max(24, tipTxt.implicitHeight + 6)

                                            Text {
                                                id: tipTxt
                                                visible: !parent.isEditingTip
                                                anchors.fill: parent
                                                text: "•  " + modelData
                                                font.pixelSize: 12
                                                color: root.textPrimary
                                                wrapMode: Text.Wrap
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.IBeamCursor
                                                    onClicked: {
                                                        root.recipeDraftTextA = modelData;
                                                        root.recipeEditingField = "tip";
                                                        root.recipeEditingIndex = index;
                                                    }
                                                }
                                            }

                                            RowLayout {
                                                visible: parent.isEditingTip
                                                anchors.fill: parent
                                                spacing: 4
                                                TextField {
                                                    id: tipEditField
                                                    Layout.fillWidth: true
                                                    implicitHeight: 28
                                                    text: root.recipeDraftTextA
                                                    font.pixelSize: 11
                                                    color: root.textPrimary
                                                    background: Rectangle { radius: 4; color: root.cardBg; border.width: 1; border.color: root.accentColor }
                                                    onVisibleChanged: if (visible) forceActiveFocus()
                                                    onAccepted: root.updateRecipeListItem("tips", root.rView.tips, index, text)
                                                    Keys.onEscapePressed: event => { root.recipeEditingField = ""; root.recipeEditingIndex = -1; root.restoreWorkspaceFocus(); event.accepted = true; }
                                                    Keys.onPressed: event => root.forwardWorkspaceShortcut(event)
                                                }
                                                Rectangle {
                                                    radius: 4
                                                    color: root.accentColor
                                                    implicitWidth: 42
                                                    implicitHeight: 26
                                                    Text { anchors.centerIn: parent; text: "Save"; font.pixelSize: 10; font.weight: Font.Bold; color: root.onAccentColor }
                                                    MouseArea {
                                                        anchors.fill: parent
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: root.updateRecipeListItem("tips", root.rView.tips, index, tipEditField.text)
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    Text {
                                        visible: (root.rView.tips ?? []).length === 0
                                        text: "Add prep shortcuts, heat control notes, or storage advice."
                                        font.pixelSize: 11
                                        font.italic: true
                                        color: root.textMuted
                                        wrapMode: Text.Wrap
                                        Layout.fillWidth: true
                                    }
                                }
                            }

                            // Top-right angled corner tape strip (`.cv-recipe-card--tips::before`)
                            Rectangle {
                                width: 88
                                height: 18
                                anchors.right: parent.right
                                anchors.rightMargin: 18
                                y: 2
                                rotation: 26
                                radius: 3
                                color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.20)
                                border.width: 1
                                border.color: Qt.rgba(root.textStrong.r, root.textStrong.g, root.textStrong.b, 0.22)
                            }
                        }

                        // Right: SERVE IT WITH / Pairs Well With (`.cv-recipe-card--pairings`)
                        Item {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            Layout.alignment: Qt.AlignTop
                            implicitHeight: pairingsCardRect.implicitHeight + 10

                            Rectangle {
                                id: pairingsCardRect
                                objectName: "nexusRecipePairingsCard"
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.topMargin: 8
                                implicitHeight: Math.max(170, pairingsCol.implicitHeight + 32)
                                radius: 9
                                color: root.cardSubtleBg
                                border.width: 1
                                border.color: root.borderSubtle
                                clip: true

                                // Subtle notebook lines matching Viewing Notes
                                Canvas {
                                    anchors.fill: parent
                                    opacity: 0.25
                                    readonly property color _ruleColor: root.borderSubtle
                                    on_RuleColorChanged: if (visible) requestPaint()
                                    onWidthChanged: if (visible) requestPaint()
                                    onHeightChanged: if (visible) requestPaint()
                                    onVisibleChanged: if (visible) requestPaint()
                                    onPaint: {
                                        const ctx = getContext("2d");
                                        ctx.reset();
                                        ctx.strokeStyle = root.borderSubtle;
                                        ctx.lineWidth = 1;
                                        for (let y = 52; y < height - 12; y += 26) {
                                            ctx.beginPath();
                                            ctx.moveTo(14, y);
                                            ctx.lineTo(width - 14, y);
                                            ctx.stroke();
                                        }
                                    }
                                }

                                ColumnLayout {
                                    id: pairingsCol
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: 16
                                    spacing: 8

                                    RowLayout {
                                        Layout.fillWidth: true
                                        ColumnLayout {
                                            spacing: 1
                                            Text { text: "SERVE IT WITH"; font.pixelSize: 9; font.weight: Font.Bold; font.letterSpacing: 1.5; color: root.accentColor }
                                            Text { text: "Pairs Well With"; font.pixelSize: 17; font.weight: Font.Bold; color: root.textStrong }
                                        }
                                        Item { Layout.fillWidth: true }
                                        Rectangle {
                                            objectName: "nexusRecipeAddPairingButton"
                                            radius: 12
                                            implicitHeight: 24
                                            implicitWidth: addPairTxt.implicitWidth + 16
                                            color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.14)
                                            border.width: 1
                                            border.color: root.accentColor
                                            Text { id: addPairTxt; anchors.centerIn: parent; text: "+ Pairing"; font.pixelSize: 9; font.weight: Font.Bold; color: root.accentColor }
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.appendRecipeListItem("pairs_well_with", root.rView.pairings, "New pairing suggestion.", "pairing")
                                            }
                                        }
                                    }

                                    Repeater {
                                        model: root.rView.pairings ?? []
                                        delegate: Item {
                                            required property string modelData
                                            required property int index
                                            readonly property bool isEditingPairing: root.recipeEditingField === "pairing" && root.recipeEditingIndex === index
                                            Layout.fillWidth: true
                                            implicitHeight: isEditingPairing ? 34 : Math.max(24, pairTxt.implicitHeight + 6)

                                            Text {
                                                id: pairTxt
                                                visible: !parent.isEditingPairing
                                                anchors.fill: parent
                                                text: "•  " + modelData
                                                font.pixelSize: 12
                                                color: root.textPrimary
                                                wrapMode: Text.Wrap
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.IBeamCursor
                                                    onClicked: {
                                                        root.recipeDraftTextA = modelData;
                                                        root.recipeEditingField = "pairing";
                                                        root.recipeEditingIndex = index;
                                                    }
                                                }
                                            }

                                            RowLayout {
                                                visible: parent.isEditingPairing
                                                anchors.fill: parent
                                                spacing: 4
                                                TextField {
                                                    id: pairingEditField
                                                    Layout.fillWidth: true
                                                    implicitHeight: 28
                                                    text: root.recipeDraftTextA
                                                    font.pixelSize: 11
                                                    color: root.textPrimary
                                                    background: Rectangle { radius: 4; color: root.cardBg; border.width: 1; border.color: root.accentColor }
                                                    onVisibleChanged: if (visible) forceActiveFocus()
                                                    onAccepted: root.updateRecipeListItem("pairs_well_with", root.rView.pairings, index, text)
                                                    Keys.onEscapePressed: event => { root.recipeEditingField = ""; root.recipeEditingIndex = -1; root.restoreWorkspaceFocus(); event.accepted = true; }
                                                    Keys.onPressed: event => root.forwardWorkspaceShortcut(event)
                                                }
                                                Rectangle {
                                                    radius: 4
                                                    color: root.accentColor
                                                    implicitWidth: 42
                                                    implicitHeight: 26
                                                    Text { anchors.centerIn: parent; text: "Save"; font.pixelSize: 10; font.weight: Font.Bold; color: root.onAccentColor }
                                                    MouseArea {
                                                        anchors.fill: parent
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: root.updateRecipeListItem("pairs_well_with", root.rView.pairings, index, pairingEditField.text)
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    Text {
                                        visible: (root.rView.pairings ?? []).length === 0
                                        text: "Add side dishes, drinks, or condiments that complement this dish."
                                        font.pixelSize: 11
                                        font.italic: true
                                        color: root.textMuted
                                        wrapMode: Text.Wrap
                                        Layout.fillWidth: true
                                    }
                                }
                            }

                            // Top-left angled corner tape strip (`.cv-recipe-card--pairings::before`)
                            Rectangle {
                                width: 88
                                height: 18
                                anchors.left: parent.left
                                anchors.leftMargin: 18
                                y: 2
                                rotation: -26
                                radius: 3
                                color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.20)
                                border.width: 1
                                border.color: Qt.rgba(root.textStrong.r, root.textStrong.g, root.textStrong.b, 0.22)
                            }
                        }
                    }
                }

                // -------------------------------------------------------------
                // 5.4 PERSONAL NOTE SECTION (`YOUR VARIATION` / `Personal Note` Lined Paper Card)
                // -------------------------------------------------------------
                Item {
                    id: recipeNotesSection
                    objectName: "nexusRecipeNotesSection"
                    visible: root.recipeActiveSection === "all" || root.recipeActiveSection === "notes"
                    Layout.fillWidth: true
                    implicitHeight: recipePersonalNoteCard.implicitHeight + 10

                    Rectangle {
                        id: recipePersonalNoteCard
                        objectName: "nexusRecipePersonalNoteCard"
                        readonly property int minPersonalNoteHeight: Math.max(
                            220,
                            root.minDocumentSurfaceHeight
                                - nexusRecipeHero.implicitHeight
                                - (recipeOverviewSection.visible ? recipeOverviewSection.implicitHeight + 22 : 0)
                                - (recipeMethodSection.visible ? recipeMethodSection.implicitHeight + 22 : 0)
                                - 84
                        )
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.topMargin: 8
                        implicitHeight: Math.max(minPersonalNoteHeight, recipePersonalNoteCol.implicitHeight + 36)
                        radius: 9
                        color: root.cardSubtleBg
                        border.width: 1
                        border.color: root.recipeEditingPersonalNote ? root.accentColor : root.borderSubtle
                        clip: true

                        // Subtle notebook lines matching Viewing Notes
                        Canvas {
                            anchors.fill: parent
                            opacity: 0.25
                            readonly property color _ruleColor: root.borderSubtle
                            on_RuleColorChanged: if (visible) requestPaint()
                            onWidthChanged: if (visible) requestPaint()
                            onHeightChanged: if (visible) requestPaint()
                            onVisibleChanged: if (visible) requestPaint()
                            onPaint: {
                                const ctx = getContext("2d");
                                ctx.reset();
                                ctx.strokeStyle = root.borderSubtle;
                                ctx.lineWidth = 1;
                                for (let y = 52; y < height - 12; y += 26) {
                                    ctx.beginPath();
                                    ctx.moveTo(14, y);
                                    ctx.lineTo(width - 14, y);
                                    ctx.stroke();
                                }
                            }
                        }

                        ColumnLayout {
                            id: recipePersonalNoteCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 18
                            spacing: 10

                            RowLayout {
                                Layout.fillWidth: true
                                ColumnLayout {
                                    spacing: 1
                                    Text { text: "YOUR VARIATION"; font.pixelSize: 9; font.weight: Font.Bold; font.letterSpacing: 1.5; color: root.accentColor }
                                    Text { text: "Personal Note"; font.pixelSize: 19; font.weight: Font.Bold; color: root.textStrong }
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    objectName: "nexusRecipeEditPersonalNotePrompt"
                                    text: root.recipeEditingPersonalNote ? "Editing · Esc to finish" : "Click note to edit"
                                    font.pixelSize: 10
                                    font.family: Appearance.font.family.monospace
                                    color: (recipePersonalNoteHeaderMouse.containsMouse || root.recipeEditingPersonalNote) ? root.accentColor : root.textMuted
                                    MouseArea {
                                        id: recipePersonalNoteHeaderMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (root.recipeEditingPersonalNote) {
                                                if (root.service)
                                                    root.service.saveRecipePersonalNotes(recipePersonalNoteEditor.text);
                                                root.recipeEditingPersonalNote = false;
                                                root.restoreWorkspaceFocus();
                                            } else {
                                                recipePersonalNoteEditor.text = String(root.rView.personalNotes ?? "");
                                                root.recipeEditingPersonalNote = true;
                                            }
                                        }
                                    }
                                }
                            }

                            // Reading Mode (Default): Click to switch to Editing Mode
                            Item {
                                id: recipePersonalNoteReadingArea
                                objectName: "nexusRecipePersonalNoteReadingArea"
                                visible: !root.recipeEditingPersonalNote
                                Layout.fillWidth: true
                                implicitHeight: Math.max(90, recipePersonalNoteCard.minPersonalNoteHeight - 86, recipePersonalNoteTxt.implicitHeight + 16)

                                Text {
                                    id: recipePersonalNoteTxt
                                    objectName: "nexusRecipePersonalNoteText"
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    readonly property bool hasNote: String(root.rView.personalNotes ?? "").trim().length > 0
                                    text: hasNote
                                        ? (String(root.rView.personalNotesHtml ?? "").length > 0
                                            ? root.themeRichHtml(root.rView.personalNotesHtml)
                                            : root.renderMarkdownBlocksHtml(root.rView.personalNotes ?? ""))
                                        : "Click to record how your batch turned out, adjustments to seasoning, or what you want to try next time..."
                                    textFormat: hasNote ? Text.RichText : Text.PlainText
                                    font.pixelSize: 13
                                    font.italic: !hasNote
                                    lineHeight: 28
                                    lineHeightMode: Text.FixedHeight
                                    color: hasNote ? root.textPrimary : root.textMuted
                                    wrapMode: Text.Wrap
                                    onLinkActivated: link => {
                                        if (root.service && link.startsWith("wikilink:"))
                                            root.service.followWikilink(decodeURIComponent(link.substring(9)));
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    z: -1
                                    cursorShape: Qt.IBeamCursor
                                    onClicked: {
                                        recipePersonalNoteEditor.text = String(root.rView.personalNotes ?? "");
                                        root.recipeEditingPersonalNote = true;
                                    }
                                }
                            }

                            // Editing Mode (Activated on Click)
                            ColumnLayout {
                                visible: root.recipeEditingPersonalNote && root.noteKind === "recipe"
                                Layout.fillWidth: true
                                spacing: 8

                                TextArea {
                                    id: recipePersonalNoteEditor
                                    objectName: "nexusRecipePersonalNoteEditor"
                                    property bool _cancelingPersonalNote: false
                                    Layout.fillWidth: true
                                    Layout.minimumHeight: 110
                                    text: String(root.rView.personalNotes ?? "")
                                    placeholderText: "Write your personal cooking notes here..."
                                    placeholderTextColor: root.textMuted
                                    font.pixelSize: 13
                                    color: root.textPrimary
                                    wrapMode: TextEdit.Wrap
                                    background: Item {}
                                    onVisibleChanged: if (visible) Qt.callLater(() => { if (recipePersonalNoteEditor.visible) recipePersonalNoteEditor.forceActiveFocus(); })
                                    onActiveFocusChanged: {
                                        if (!activeFocus && visible && root.recipeEditingPersonalNote && root.noteKind === "recipe" && !_cancelingPersonalNote && !recipePersonalNoteCancelMouse.containsMouse && !recipePersonalNoteCancelMouse.pressed) {
                                            if (root.service && recipePersonalNoteEditor.text !== String(root.rView.personalNotes ?? ""))
                                                root.service.saveRecipePersonalNotes(recipePersonalNoteEditor.text);
                                            root.recipeEditingPersonalNote = false;
                                        }
                                    }
                                    Keys.onEscapePressed: event => {
                                        if (root.service)
                                            root.service.saveRecipePersonalNotes(recipePersonalNoteEditor.text);
                                        root.recipeEditingPersonalNote = false;
                                        root.restoreWorkspaceFocus();
                                        event.accepted = true;
                                    }
                                    Keys.onPressed: event => {
                                        if (root.forwardWorkspaceShortcut(event))
                                            return;
                                        if ((event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_S)) {
                                            if (root.service)
                                                root.service.saveRecipePersonalNotes(recipePersonalNoteEditor.text);
                                            root.recipeEditingPersonalNote = false;
                                            root.restoreWorkspaceFocus();
                                            event.accepted = true;
                                        }
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    Item { Layout.fillWidth: true }
                                    Rectangle {
                                        objectName: "nexusRecipePersonalNoteCancelButton"
                                        radius: 5
                                        color: root.cardRaisedBg
                                        border.width: 1
                                        border.color: root.borderSubtle
                                        implicitWidth: 54
                                        implicitHeight: 24
                                        Text { anchors.centerIn: parent; text: "Cancel"; font.pixelSize: 10; color: root.textSecondary }
                                        MouseArea {
                                            id: recipePersonalNoteCancelMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                recipePersonalNoteEditor._cancelingPersonalNote = true;
                                                recipePersonalNoteEditor.text = String(root.rView.personalNotes ?? "");
                                                root.recipeEditingPersonalNote = false;
                                                recipePersonalNoteEditor._cancelingPersonalNote = false;
                                                root.restoreWorkspaceFocus();
                                            }
                                        }
                                    }
                                    Rectangle {
                                        objectName: "nexusRecipePersonalNoteSaveButton"
                                        radius: 5
                                        color: root.accentColor
                                        implicitWidth: 68
                                        implicitHeight: 24
                                        Text { anchors.centerIn: parent; text: "Save Note"; font.pixelSize: 10; font.weight: Font.Bold; color: root.onAccentColor }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (root.service)
                                                    root.service.saveRecipePersonalNotes(recipePersonalNoteEditor.text);
                                                root.recipeEditingPersonalNote = false;
                                                root.restoreWorkspaceFocus();
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Top translucent tape strip
                    Rectangle {
                        width: 104
                        height: 19
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 0
                        rotation: -1.6
                        radius: 3
                        color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.20)
                        border.width: 1
                        border.color: Qt.rgba(root.textStrong.r, root.textStrong.g, root.textStrong.b, 0.22)
                    }
                }
            }
        }

        // =====================================================================
        // 6. FINANCE REPORT CUSTOM VIEW (`Custom_Views/Finance/Finance.{html,js,css}`)
        // =====================================================================
        Rectangle {
            id: financeCustomView
            objectName: "nexusFinanceCustomView"
            Layout.minimumWidth: 0
            visible: root.noteKind === "finance"
            Layout.fillWidth: true
            implicitHeight: Math.max(root.minDocumentSurfaceHeight, finCol.implicitHeight + 36)
            radius: 10
            color: root.cardBg
            border.width: 1
            border.color: root.borderAccent

            function parseIsoDayMs(dateStr): real {
                const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(dateStr ?? "").trim());
                if (!m)
                    return NaN;
                return Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3]));
            }

            readonly property var allTransactions: root.fSummary.transactions ?? []
            readonly property var activeTransactions: {
                const all = allTransactions;
                if (!Array.isArray(all) || all.length === 0)
                    return [];
                let anchorMs = NaN;
                for (let i = 0; i < all.length; ++i) {
                    const ms = parseIsoDayMs(all[i]?.date);
                    if (Number.isFinite(ms) && (!Number.isFinite(anchorMs) || ms > anchorMs))
                        anchorMs = ms;
                }
                if (!Number.isFinite(anchorMs))
                    return all;
                const rng = String(root.financeActiveRange || "monthly").toLowerCase();
                const windowDays = rng === "weekly" ? 7 : (rng === "quarterly" ? 92 : (rng === "yearly" ? 366 : 31));
                const filtered = [];
                for (let i = 0; i < all.length; ++i) {
                    const ms = parseIsoDayMs(all[i]?.date);
                    if (!Number.isFinite(ms)) {
                        filtered.push(all[i]);
                        continue;
                    }
                    const diffDays = (anchorMs - ms) / 86400000;
                    if (diffDays >= -1 && diffDays <= windowDays)
                        filtered.push(all[i]);
                }
                return filtered.length > 0 ? filtered : all;
            }

            readonly property string currencyStr: String(root.fSummary.currency || root.doc?.frontmatter?.BookCurrency || root.doc?.frontmatter?.currency || "VND")
            readonly property real totalIncomeVal: {
                const txs = activeTransactions;
                if (txs.length === 0)
                    return Number(root.fSummary.totalIncome ?? 0);
                let sum = 0;
                for (let i = 0; i < txs.length; ++i) {
                    if (String(txs[i]?.type ?? "").toLowerCase() === "income")
                        sum += Number(txs[i]?.amount ?? 0);
                }
                return sum;
            }
            readonly property real totalExpenseVal: {
                const txs = activeTransactions;
                if (txs.length === 0)
                    return Number(root.fSummary.totalExpense ?? 0);
                let sum = 0;
                for (let i = 0; i < txs.length; ++i) {
                    if (String(txs[i]?.type ?? "").toLowerCase() !== "income")
                        sum += Number(txs[i]?.amount ?? 0);
                }
                return sum;
            }
            readonly property real netCashflowVal: activeTransactions.length > 0
                ? (totalIncomeVal - totalExpenseVal)
                : Number(root.fSummary.netCashflow ?? (totalIncomeVal - totalExpenseVal))
            readonly property real accountsBalanceVal: {
                const accts = root.fSummary.accounts ?? [];
                if (accts.length > 0) {
                    let sum = 0;
                    for (let i = 0; i < accts.length; ++i)
                        sum += Number(accts[i]?.balance ?? 0);
                    return sum;
                }
                return Number(root.fSummary.openingBalance ?? 0);
            }
            readonly property real closingBalanceVal: accountsBalanceVal + netCashflowVal
            readonly property int savingsRatePct: totalIncomeVal > 0
                ? Math.round(((totalIncomeVal - totalExpenseVal) / totalIncomeVal) * 100)
                : 0
            readonly property var activeCategories: {
                const txs = activeTransactions;
                if (txs.length > 0) {
                    const byCat = ({});
                    for (let i = 0; i < txs.length; ++i) {
                        if (String(txs[i]?.type ?? "").toLowerCase() === "income")
                            continue;
                        const cat = String(txs[i]?.category || "General");
                        const amt = Number(txs[i]?.amount ?? 0);
                        if (amt > 0)
                            byCat[cat] = (byCat[cat] || 0) + amt;
                    }
                    const keys = Object.keys(byCat);
                    if (keys.length > 0) {
                        const list = keys.map(k => ({ "category": k, "amount": byCat[k] }));
                        list.sort((a, b) => b.amount - a.amount);
                        return list;
                    }
                }
                return root.fSummary.categories ?? root.fSummary.categoryBreakdown ?? [];
            }
            readonly property color incomeColor: Qt.tint(Qt.color("#73daca"), Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.25))
            readonly property color expenseColor: Qt.tint(Qt.color("#f7768e"), Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.18))

            ColumnLayout {
                id: finCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 18
                spacing: 16

                // ── 6.1 Header (`cv-finance-header`: Eyebrow + Title + Range Switcher) ──
                GridLayout {
                    columns: width < 660 ? 1 : 2
                    columnSpacing: 14
                    rowSpacing: 14
                    // finance responsive header
                    Layout.fillWidth: true

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        RowLayout {
                            spacing: 8
                            Text {
                                text: "PERSONAL FINANCE"
                                font.family: Appearance.font.family.monospace
                                font.pixelSize: 10
                                font.weight: Font.Bold
                                font.letterSpacing: 1.8
                                color: root.accentColor
                            }
                            Rectangle {
                                objectName: "nexusFinanceCurrencyBadge"
                                radius: 4
                                color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.16)
                                border.width: 1
                                border.color: root.accentColor
                                implicitWidth: finCurTxt.implicitWidth + 10
                                implicitHeight: 18
                                Text {
                                    id: finCurTxt
                                    anchors.centerIn: parent
                                    text: financeCustomView.currencyStr
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: 9
                                    font.weight: Font.Bold
                                    color: root.accentColor
                                }
                            }
                        }

                        Text {
                            objectName: "nexusFinanceTitleLabel"
                            Layout.fillWidth: true
                            text: String(root.doc?.title || "Financial Overview")
                            font.pixelSize: 22
                            font.weight: Font.Bold
                            color: root.textStrong
                            elide: Text.ElideRight
                        }

                        Text {
                            Layout.fillWidth: true
                            text: String(root.fSummary.subtitle || "Balance trajectory · cash flow · category breakdown · ledger")
                            font.pixelSize: 12
                            color: root.textSecondary
                            elide: Text.ElideRight
                        }
                    }

                    // Range Switcher (`Weekly`, `Monthly`, `Quarterly`, `Yearly`)
                    Rectangle {
                        objectName: "nexusFinanceRangeGroup"
                        Layout.alignment: Qt.AlignTop
                        implicitWidth: finRangeRow.implicitWidth + 8
                        implicitHeight: 32
                        radius: 7
                        color: root.cardDeepBg
                        border.width: 1
                        border.color: root.borderSubtle

                        RowLayout {
                            id: finRangeRow
                            anchors.centerIn: parent
                            spacing: 4

                            Repeater {
                                model: [
                                    { "id": "weekly", "label": "Weekly" },
                                    { "id": "monthly", "label": "Monthly" },
                                    { "id": "quarterly", "label": "Quarterly" },
                                    { "id": "yearly", "label": "Yearly" }
                                ]
                                delegate: Rectangle {
                                    required property var modelData
                                    objectName: "nexusFinanceRangeBtn_" + modelData.id
                                    readonly property bool active: root.financeActiveRange === modelData.id
                                    implicitWidth: rangeBtnTxt.implicitWidth + 14
                                    implicitHeight: 24
                                    radius: 5
                                    color: active ? root.accentColor : (rangeBtnMouse.containsMouse ? root.cardHoverBg : "transparent")
                                    Text {
                                        id: rangeBtnTxt
                                        anchors.centerIn: parent
                                        text: modelData.label
                                        font.family: Appearance.font.family.monospace
                                        font.pixelSize: 10
                                        font.weight: active ? Font.Bold : Font.Medium
                                        color: active ? root.onAccentColor : root.textSecondary
                                    }
                                    MouseArea {
                                        id: rangeBtnMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.financeActiveRange = modelData.id;
                                            if (root.service)
                                                root.service.updateNoteFrontmatter({ "period": modelData.label });
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ── 6.2 4 KPI Cards (`cv-finance-kpi-grid`) ──
                GridLayout {
                    columns: width < 600 ? 2 : 4
                    columnSpacing: 10
                    rowSpacing: 10
                    objectName: "nexusFinanceKpiGrid"
                    Layout.fillWidth: true

                    Repeater {
                        model: [
                            {
                                "label": "CLOSING BALANCE",
                                "value": financeCustomView.closingBalanceVal.toLocaleString() + " " + financeCustomView.currencyStr,
                                "sub": "Net " + (financeCustomView.netCashflowVal >= 0 ? "+" : "") + financeCustomView.netCashflowVal.toLocaleString(),
                                "color": root.textStrong
                            },
                            {
                                "label": "INCOME",
                                "value": financeCustomView.totalIncomeVal.toLocaleString() + " " + financeCustomView.currencyStr,
                                "sub": root.financeActiveRange.toUpperCase() + " INFLOW",
                                "color": financeCustomView.incomeColor
                            },
                            {
                                "label": "EXPENSES",
                                "value": financeCustomView.totalExpenseVal.toLocaleString() + " " + financeCustomView.currencyStr,
                                "sub": String(financeCustomView.activeTransactions.length) + " transactions",
                                "color": financeCustomView.expenseColor
                            },
                            {
                                "label": "SAVINGS RATE",
                                "value": String(financeCustomView.savingsRatePct) + "%",
                                "sub": financeCustomView.savingsRatePct >= 20 ? "On target (≥20%)" : "Below 20% target",
                                "color": root.accentColor
                            }
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            implicitHeight: 68
                            radius: 8
                            color: root.cardDeepBg
                            border.width: 1
                            border.color: root.borderSubtle

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 2
                                Text {
                                    text: modelData.label
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: 9
                                    font.weight: Font.Bold
                                    font.letterSpacing: 1.2
                                    color: root.textMuted
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.value
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: 15
                                    font.weight: Font.Bold
                                    color: modelData.color
                                    elide: Text.ElideRight
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.sub
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: 9
                                    color: root.textSecondary
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }
                }

                // ── 6.3 Balance Movement Area+Line Chart (`cv-finance-chart-panel`) ──
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 196
                    radius: 8
                    color: root.cardDeepBg
                    border.width: 1
                    border.color: root.borderSubtle

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            ColumnLayout {
                                spacing: 1
                                Text {
                                    text: "REPORT"
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: 9
                                    font.weight: Font.Bold
                                    font.letterSpacing: 1.4
                                    color: root.accentColor
                                }
                                Text {
                                    text: "Balance movement"
                                    font.pixelSize: 15
                                    font.weight: Font.Bold
                                    color: root.textStrong
                                }
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: "Delta " + (financeCustomView.netCashflowVal >= 0 ? "+" : "") + financeCustomView.netCashflowVal.toLocaleString() + " " + financeCustomView.currencyStr
                                font.family: Appearance.font.family.monospace
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                                color: financeCustomView.netCashflowVal >= 0 ? financeCustomView.incomeColor : financeCustomView.expenseColor
                            }
                        }

                        Canvas {
                            id: finBalanceCanvas
                            objectName: "nexusFinanceBalanceCanvas"
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            readonly property string _themeSig: root.themeSignature
                            readonly property var txList: financeCustomView.activeTransactions
                            on_ThemeSigChanged: if (visible) requestPaint()
                            onTxListChanged: if (visible) requestPaint()
                            onWidthChanged: if (visible) requestPaint()
                            onHeightChanged: if (visible) requestPaint()
                            onVisibleChanged: if (visible) requestPaint()
                            onPaint: {
                                const ctx = getContext("2d");
                                ctx.reset();
                                const w = width;
                                const h = height;
                                if (w <= 10 || h <= 10)
                                    return;

                                // Subtle horizontal grid lines
                                ctx.strokeStyle = Qt.rgba(root.borderSubtle.r, root.borderSubtle.g, root.borderSubtle.b, 0.45);
                                ctx.lineWidth = 1;
                                for (let g = 0; g < 4; ++g) {
                                    const gy = 10 + ((h - 24) * g) / 3;
                                    ctx.beginPath();
                                    ctx.moveTo(8, gy);
                                    ctx.lineTo(w - 8, gy);
                                    ctx.stroke();
                                }

                                // Compute cumulative balance points from transactions (oldest to newest)
                                const rawTxs = (txList ?? []).slice().reverse();
                                const pts = [];
                                let running = financeCustomView.accountsBalanceVal;
                                pts.push(running);
                                for (let i = 0; i < rawTxs.length; ++i) {
                                    const tx = rawTxs[i];
                                    const amt = Number(tx?.amount ?? 0);
                                    const isInc = String(tx?.type ?? "").toLowerCase() === "income";
                                    running += isInc ? amt : -amt;
                                    pts.push(running);
                                }
                                if (pts.length < 2) {
                                    pts.push(running + financeCustomView.netCashflowVal);
                                }

                                let minV = pts[0];
                                let maxV = pts[0];
                                for (let i = 1; i < pts.length; ++i) {
                                    if (pts[i] < minV) minV = pts[i];
                                    if (pts[i] > maxV) maxV = pts[i];
                                }
                                const span = Math.max(1, maxV - minV);
                                const padX = 14;
                                const padY = 14;
                                const plotW = Math.max(1, w - padX * 2);
                                const plotH = Math.max(1, h - padY * 2);

                                const coords = [];
                                for (let i = 0; i < pts.length; ++i) {
                                    const cx = padX + (plotW * i) / Math.max(1, pts.length - 1);
                                    const cy = padY + plotH * (1 - (pts[i] - minV) / span);
                                    coords.push({ "x": cx, "y": cy });
                                }

                                // Area fill
                                const grad = ctx.createLinearGradient(0, padY, 0, h - padY);
                                grad.addColorStop(0.0, Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.34));
                                grad.addColorStop(1.0, Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.02));
                                ctx.fillStyle = grad;
                                ctx.beginPath();
                                ctx.moveTo(coords[0].x, h - padY);
                                for (let i = 0; i < coords.length; ++i)
                                    ctx.lineTo(coords[i].x, coords[i].y);
                                ctx.lineTo(coords[coords.length - 1].x, h - padY);
                                ctx.closePath();
                                ctx.fill();

                                // Line stroke
                                ctx.strokeStyle = root.accentColor;
                                ctx.lineWidth = 2.2;
                                ctx.beginPath();
                                for (let i = 0; i < coords.length; ++i) {
                                    if (i === 0) ctx.moveTo(coords[i].x, coords[i].y);
                                    else ctx.lineTo(coords[i].x, coords[i].y);
                                }
                                ctx.stroke();

                                // Point markers
                                ctx.fillStyle = root.textStrong;
                                for (let i = 0; i < coords.length; ++i) {
                                    ctx.beginPath();
                                    ctx.arc(coords[i].x, coords[i].y, 3, 0, Math.PI * 2);
                                    ctx.fill();
                                }
                            }
                        }
                    }
                }

                // ── 6.4 2-Column Analysis Grid (`Cash flow` & `Expense categories`) ──
                GridLayout {
                    columns: width < 600 ? 1 : 2
                    columnSpacing: 12
                    rowSpacing: 12
                    Layout.fillWidth: true

                    // Left: Cash Flow (Income vs Expense Comparison)
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.alignment: Qt.AlignTop
                        implicitHeight: Math.max(170, finCashflowCol.implicitHeight + 24)
                        radius: 8
                        color: root.cardDeepBg
                        border.width: 1
                        border.color: root.borderSubtle

                        ColumnLayout {
                            id: finCashflowCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 12
                            spacing: 8

                            Text {
                                text: "ANALYSIS · CASH FLOW"
                                font.family: Appearance.font.family.monospace
                                font.pixelSize: 9
                                font.weight: Font.Bold
                                font.letterSpacing: 1.4
                                color: root.accentColor
                            }
                            Text {
                                text: "Income vs Expenses"
                                font.pixelSize: 14
                                font.weight: Font.Bold
                                color: root.textStrong
                            }

                            Repeater {
                                model: [
                                    {
                                        "label": "Income",
                                        "amount": financeCustomView.totalIncomeVal,
                                        "ratio": financeCustomView.totalIncomeVal / Math.max(1, Math.max(financeCustomView.totalIncomeVal, financeCustomView.totalExpenseVal)),
                                        "color": financeCustomView.incomeColor
                                    },
                                    {
                                        "label": "Expenses",
                                        "amount": financeCustomView.totalExpenseVal,
                                        "ratio": financeCustomView.totalExpenseVal / Math.max(1, Math.max(financeCustomView.totalIncomeVal, financeCustomView.totalExpenseVal)),
                                        "color": financeCustomView.expenseColor
                                    }
                                ]
                                delegate: ColumnLayout {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    spacing: 4
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text { text: modelData.label; font.family: Appearance.font.family.monospace; font.pixelSize: 11; color: root.textPrimary }
                                        Item { Layout.fillWidth: true }
                                        Text { text: Number(modelData.amount).toLocaleString() + " " + financeCustomView.currencyStr; font.family: Appearance.font.family.monospace; font.pixelSize: 11; font.weight: Font.Bold; color: modelData.color }
                                    }
                                    Rectangle {
                                        Layout.fillWidth: true
                                        implicitHeight: 8
                                        radius: 4
                                        color: root.cardRaisedBg
                                        Rectangle {
                                            width: parent.width * Math.max(0.04, Math.min(1, Number(modelData.ratio || 0)))
                                            height: parent.height
                                            radius: 4
                                            color: modelData.color
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Right: Expense Categories Breakdown
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.alignment: Qt.AlignTop
                        implicitHeight: Math.max(170, finCatCol.implicitHeight + 24)
                        radius: 8
                        color: root.cardDeepBg
                        border.width: 1
                        border.color: root.borderSubtle

                        ColumnLayout {
                            id: finCatCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 12
                            spacing: 8

                            Text {
                                text: "ANALYSIS · BREAKDOWN"
                                font.family: Appearance.font.family.monospace
                                font.pixelSize: 9
                                font.weight: Font.Bold
                                font.letterSpacing: 1.4
                                color: root.accentColor
                            }
                            Text {
                                text: "Expense categories"
                                font.pixelSize: 14
                                font.weight: Font.Bold
                                color: root.textStrong
                            }

                            Repeater {
                                model: financeCustomView.activeCategories.slice(0, 6)
                                delegate: ColumnLayout {
                                    required property var modelData
                                    objectName: "nexusFinanceCategoryRow_" + String(modelData.category || "General")
                                    Layout.fillWidth: true
                                    spacing: 3
                                    readonly property real catAmt: Number(modelData.amount ?? 0)
                                    readonly property int catPct: financeCustomView.totalExpenseVal > 0
                                        ? Math.round((catAmt / financeCustomView.totalExpenseVal) * 100)
                                        : 0
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text {
                                            text: String(modelData.category || "General")
                                            font.family: Appearance.font.family.monospace
                                            font.pixelSize: 11
                                            color: root.textPrimary
                                        }
                                        Item { Layout.fillWidth: true }
                                        Text {
                                            text: catAmt.toLocaleString() + " (" + String(catPct) + "%)"
                                            font.family: Appearance.font.family.monospace
                                            font.pixelSize: 10
                                            color: root.accentColor
                                        }
                                    }
                                    Rectangle {
                                        Layout.fillWidth: true
                                        implicitHeight: 6
                                        radius: 3
                                        color: root.cardRaisedBg
                                        Rectangle {
                                            width: parent.width * Math.max(0.04, Math.min(1, catPct / 100.0))
                                            height: parent.height
                                            radius: 3
                                            color: root.accentColor
                                        }
                                    }
                                }
                            }

                            Text {
                                visible: financeCustomView.activeCategories.length === 0
                                text: "No categorized expenses recorded yet."
                                font.pixelSize: 11
                                font.italic: true
                                color: root.textMuted
                            }
                        }
                    }
                }

                // ── 6.5 Transactions Ledger Table (`cv-finance-ledger-panel`) ──
                Rectangle {
                    objectName: "nexusFinanceLedgerCard"
                    Layout.fillWidth: true
                    implicitHeight: finLedgerCol.implicitHeight + 24
                    radius: 8
                    color: root.cardDeepBg
                    border.width: 1
                    border.color: root.borderSubtle

                    ColumnLayout {
                        id: finLedgerCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 12
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            ColumnLayout {
                                spacing: 1
                                Text {
                                    text: "LEDGER"
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: 9
                                    font.weight: Font.Bold
                                    font.letterSpacing: 1.4
                                    color: root.accentColor
                                }
                                Text {
                                    text: "Transactions"
                                    font.pixelSize: 15
                                    font.weight: Font.Bold
                                    color: root.textStrong
                                }
                            }
                            Item { Layout.fillWidth: true }
                            Rectangle {
                                radius: 4
                                color: root.cardRaisedBg
                                implicitWidth: txCountLbl.implicitWidth + 12
                                implicitHeight: 20
                                Text {
                                    id: txCountLbl
                                    objectName: "nexusFinanceTxCountLabel"
                                    anchors.centerIn: parent
                                    text: String(financeCustomView.activeTransactions.length) + " entries"
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: 10
                                    color: root.textSecondary
                                }
                            }
                        }

                        Flickable {
                            id: financeLedgerScroll
                            objectName: "nexusFinanceLedgerScroll"
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            implicitHeight: financeLedgerTable.implicitHeight
                            contentWidth: Math.max(width, 650)
                            contentHeight: financeLedgerTable.implicitHeight
                            flickableDirection: Flickable.HorizontalFlick
                            clip: true
                            ScrollBar.horizontal: ScrollBar {}
                            ColumnLayout {
                                id: financeLedgerTable
                                width: financeLedgerScroll.contentWidth
                                spacing: 8
                        // Table Header
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Text { Layout.preferredWidth: 90; text: "DATE"; font.family: Appearance.font.family.monospace; font.pixelSize: 9; font.weight: Font.Bold; color: root.textMuted }
                            Text { Layout.fillWidth: true; text: "DESCRIPTION"; font.family: Appearance.font.family.monospace; font.pixelSize: 9; font.weight: Font.Bold; color: root.textMuted }
                            Text { Layout.preferredWidth: 110; text: "CATEGORY"; font.family: Appearance.font.family.monospace; font.pixelSize: 9; font.weight: Font.Bold; color: root.textMuted }
                            Text { Layout.preferredWidth: 70; text: "TYPE"; font.family: Appearance.font.family.monospace; font.pixelSize: 9; font.weight: Font.Bold; color: root.textMuted }
                            Text { objectName: "nexusFinanceLedgerAmountHeader"; Layout.preferredWidth: 110; horizontalAlignment: Text.AlignRight; text: "AMOUNT"; font.family: Appearance.font.family.monospace; font.pixelSize: 9; font.weight: Font.Bold; color: root.textMuted }
                        }

                        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: root.borderSubtle }

                        Repeater {
                            model: financeCustomView.activeTransactions.slice(0, root.financeVisibleTransactionCount)
                            delegate: Rectangle {
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: 28
                                radius: 5
                                color: txRowMouse.containsMouse ? root.cardHoverBg : "transparent"

                                readonly property bool isIncome: String(modelData.type ?? "").toLowerCase() === "income"

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 4
                                    anchors.rightMargin: 4
                                    spacing: 8
                                    Text {
                                        Layout.preferredWidth: 90
                                        text: String(modelData.date || "—")
                                        font.family: Appearance.font.family.monospace
                                        font.pixelSize: 11
                                        color: root.textSecondary
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: String(modelData.title || modelData.merchant || "Transaction")
                                        font.pixelSize: 12
                                        font.weight: Font.Medium
                                        color: root.textPrimary
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        Layout.preferredWidth: 110
                                        text: String(modelData.category || "General")
                                        font.family: Appearance.font.family.monospace
                                        font.pixelSize: 11
                                        color: root.textSecondary
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        Layout.preferredWidth: 70
                                        text: isIncome ? "Income" : "Expense"
                                        font.family: Appearance.font.family.monospace
                                        font.pixelSize: 10
                                        color: isIncome ? financeCustomView.incomeColor : financeCustomView.expenseColor
                                    }
                                    Text {
                                        Layout.preferredWidth: 110
                                        horizontalAlignment: Text.AlignRight
                                        text: (isIncome ? "+" : "-") + Number(modelData.amount ?? 0).toLocaleString()
                                        font.family: Appearance.font.family.monospace
                                        font.pixelSize: 11
                                        font.weight: Font.Bold
                                        color: isIncome ? financeCustomView.incomeColor : financeCustomView.expenseColor
                                    }
                                }

                                MouseArea {
                                    id: txRowMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    enabled: String(modelData.relPath ?? "").length > 0
                                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: {
                                        if (root.service && modelData.relPath)
                                            root.service.openFile(String(modelData.relPath), true);
                                    }
                                }
                            }
                        }
                            }
                        }

                        Rectangle {
                            objectName: "nexusFinanceShowMoreTransactions"
                            Layout.fillWidth: true
                            implicitHeight: 32
                            visible: financeCustomView.activeTransactions.length > root.financeVisibleTransactionCount
                            radius: 5
                            color: moreTransactionsMouse.containsMouse ? root.cardHoverBg : root.cardDeepBg
                            border.width: 1
                            border.color: root.borderSubtle
                            Text {
                                anchors.centerIn: parent
                                text: "Show " + Math.min(12, financeCustomView.activeTransactions.length - root.financeVisibleTransactionCount) + " more transactions"
                                font.pixelSize: 11
                                color: root.textPrimary
                            }
                            MouseArea {
                                id: moreTransactionsMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.financeVisibleTransactionCount += 12
                            }
                        }
                    }
                }

                // ── 6.6 Financial Notes (`cv-finance-notes-panel` with Click-to-Edit Rich Markdown) ──
                Rectangle {
                    objectName: "nexusFinanceNotesCard"
                    Layout.fillWidth: true
                    implicitHeight: Math.max(180, finNotesCol.implicitHeight + 24)
                    radius: 8
                    color: root.cardDeepBg
                    border.width: 1
                    border.color: root.editingNoteBody ? root.accentColor : root.borderSubtle

                    ColumnLayout {
                        id: finNotesCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 12
                        spacing: 8

                        GridLayout {
                    columns: width < 360 ? 1 : 3
                    columnSpacing: 6
                    rowSpacing: 6
                            Layout.fillWidth: true
                            ColumnLayout {
                                spacing: 1
                                Text {
                                    text: "REVIEW"
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: 9
                                    font.weight: Font.Bold
                                    font.letterSpacing: 1.4
                                    color: root.accentColor
                                }
                                Text {
                                    text: "Financial notes"
                                    font.pixelSize: 15
                                    font.weight: Font.Bold
                                    color: root.textStrong
                                }
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: root.editingNoteBody ? "Editing · Esc to finish" : "Click to edit · Markdown supported"
                                font.family: Appearance.font.family.monospace
                                font.pixelSize: 10
                                color: root.editingNoteBody ? root.accentColor : root.textMuted
                            }
                        }

                        Item {
                            id: financeBodyReadingArea
                            objectName: "nexusFinanceBodyReadingArea"
                            visible: !root.editingNoteBody
                            Layout.fillWidth: true
                            implicitHeight: Math.max(44, finNotesTxt.implicitHeight + 10)

                            Text {
                                id: finNotesTxt
                                objectName: "nexusFinanceNotesReadingText"
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                readonly property string rawNotes: String(root.fSummary.notesText || root.cleanNoteBodyMarkdown || "").trim()
                                text: {
                                    const _sig = root.themeSignature;
                                    if (rawNotes.length === 0)
                                        return "<span style='color:" + String(root.textMuted) + ";'><i>Click to add monthly financial review notes, budget reflections, or goals...</i></span>";
                                    const nHtml = String(root.fSummary.notesRichHtml ?? "").trim();
                                    if (nHtml.length > 0 && !/(^|>|\n)\s*#{1,6}\s+/m.test(nHtml) && !/\[\[/.test(nHtml))
                                        return root.themeRichHtml(nHtml);
                                    return root.renderMarkdownBlocksHtml(rawNotes);
                                }
                                textFormat: Text.RichText
                                font.pixelSize: 13
                                color: root.textPrimary
                                wrapMode: Text.Wrap
                                onLinkActivated: link => {
                                    if (root.service && link.startsWith("wikilink:"))
                                        root.service.followWikilink(decodeURIComponent(link.substring(9)));
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.IBeamCursor
                                onClicked: {
                                    financeBodyEditor.text = root.service ? root.service.getNoteBodyMarkdown() : "";
                                    root.editingNoteBody = true;
                                }
                            }
                        }

                        ColumnLayout {
                            visible: root.editingNoteBody && root.noteKind === "finance"
                            Layout.fillWidth: true
                            spacing: 6

                            TextArea {
                                id: financeBodyEditor
                                objectName: "nexusFinanceBodyEditor"
                                Layout.fillWidth: true
                                Layout.minimumHeight: 160
                                text: root.service ? root.service.getNoteBodyMarkdown() : ""
                                placeholderText: "Write your financial review notes & markdown tables..."
                                placeholderTextColor: root.textMuted
                                font.pixelSize: 12
                                color: root.textPrimary
                                wrapMode: TextEdit.Wrap
                                background: Rectangle { radius: 6; color: root.cardBg; border.width: 1; border.color: root.accentColor }
                                onVisibleChanged: if (visible) Qt.callLater(() => { if (financeBodyEditor.visible) financeBodyEditor.forceActiveFocus(); })
                                Keys.onEscapePressed: event => {
                                    if (root.service)
                                        root.service.saveNoteBodyMarkdown(financeBodyEditor.text);
                                    financeBodyEditor.focus = false;
                                    root.editingNoteBody = false;
                                    root.restoreWorkspaceFocus();
                                    event.accepted = true;
                                }
                                Keys.onPressed: event => {
                                    if ((event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_S)) {
                                        if (root.service)
                                            root.service.saveNoteBodyMarkdown(financeBodyEditor.text);
                                        financeBodyEditor.focus = false;
                                        root.editingNoteBody = false;
                                        root.restoreWorkspaceFocus();
                                        event.accepted = true;
                                        return;
                                    }
                                    if ((event.modifiers & (Qt.AltModifier | Qt.ControlModifier | Qt.MetaModifier)) !== 0
                                        && root.service && root.service.handleKeyEvent(event)) {
                                        event.accepted = true;
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Item { Layout.fillWidth: true }
                                Rectangle {
                                    radius: 5
                                    color: root.cardRaisedBg
                                    border.width: 1
                                    border.color: root.borderSubtle
                                    implicitWidth: 52
                                    implicitHeight: 24
                                    Text { anchors.centerIn: parent; text: "Cancel"; font.pixelSize: 10; color: root.textSecondary }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.editingNoteBody = false;
                                            if (root.workspace && typeof root.workspace.focusPrimarySurface === "function")
                                                Qt.callLater(root.workspace.focusPrimarySurface);
                                        }
                                    }
                                }
                                Rectangle {
                                    objectName: "nexusFinanceBodySaveButton"
                                    radius: 5
                                    color: root.accentColor
                                    implicitWidth: 56
                                    implicitHeight: 24
                                    Text { anchors.centerIn: parent; text: "Save"; font.pixelSize: 10; font.weight: Font.Bold; color: root.onAccentColor }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (root.service)
                                                root.service.saveNoteBodyMarkdown(financeBodyEditor.text);
                                            root.editingNoteBody = false;
                                            if (root.workspace && typeof root.workspace.focusPrimarySurface === "function")
                                                Qt.callLater(root.workspace.focusPrimarySurface);
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
