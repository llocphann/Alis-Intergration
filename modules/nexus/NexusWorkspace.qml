import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import qs
import qs.services as HostServices
import qs.modules.common
import qs.modules.common.widgets
import "NexusPlannerProjection.js" as PlannerProjection
import "NexusExerciseAnatomyData.js" as ExerciseAnatomyData

FocusScope {
    id: root
    objectName: "nexusWorkspace"
    focus: true
    property var nexus: null
    property bool bottomDocked: false
    property bool embeddedSurface: false
    property string draggingCardId: ""
    property string dropTargetCardId: ""
    property real dragRootX: 0
    property real dragRootY: 0
    property int plannerRevision: 0
    // Preserve stored sidebar widths while reserving a readable document surface.
    readonly property real sidebarExpansionScale: {
        const leftOpen = Boolean(root.nexus?.leftSidebarOpen ?? true);
        const rightOpen = Boolean(root.nexus?.rightSidebarOpen ?? true);
        const left = Math.max(160, Math.min(540, root.nexus?.leftSidebarWidth ?? 268));
        const right = Math.max(180, Math.min(540, root.nexus?.rightSidebarWidth ?? 288));
        const minimum = (leftOpen ? 160 : 0) + (rightOpen ? 180 : 0);
        const expansion = (leftOpen ? left - 160 : 0) + (rightOpen ? right - 180 : 0);
        const available = Math.max(minimum, root.width - 388);
        return expansion > 0 ? Math.max(0, Math.min(1, (available - minimum) / expansion)) : 1;
    }
    property bool cursorBlinkOn: true
    property bool transitionSettled: true
    property string liveDateTimeStr: root.formatHomepageDateTime(new Date())

    function formatHomepageDateTime(dt): string {
        const d = dt || new Date();
        return Qt.formatDateTime(d, "dddd, MMM dd, yyyy,").toLowerCase() + "\n" + Qt.formatDateTime(d, "HH:mm:ss");
    }

    property bool contextMenuOpen: false
    property real contextMenuX: 0
    property real contextMenuY: 0
    property var contextMenuData: null
    property bool renameDialogOpen: false
    property string renameDialogOldPath: ""
    property string renameDialogNewName: ""
    property bool standardNoteInlineEditing: false
    property string standardNoteInlineDraft: ""
    property bool _cancelingStandardInlineEdit: false

    function plannerAccentColor(swatch): color {
        if (typeof swatch === "string" && swatch.trim().length > 0)
            return Qt.color(swatch.trim());
        if (swatch && swatch.accent)
            return Qt.color(swatch.accent);
        return settledColors.colPrimary;
    }

    function startStandardNoteInlineEdit(): bool {
        if (!root.nexus || !root.nexus.currentDoc)
            return false;
        if (Boolean(nexusCustomViewsLoader.item?.isCustomViewNote))
            return false;
        root._cancelingStandardInlineEdit = false;
        root.standardNoteInlineDraft = root.nexus.getNoteBodyMarkdown();
        root.standardNoteInlineEditing = true;
        return true;
    }

    function commitStandardNoteInlineEdit(): bool {
        if (!root.standardNoteInlineEditing)
            return false;
        if (root.nexus && typeof standardNoteBodyEditor !== "undefined") {
            root.nexus.saveNoteBodyMarkdown(standardNoteBodyEditor.text);
        }
        root.standardNoteInlineEditing = false;
        return true;
    }

    function cancelStandardNoteInlineEdit(): void {
        root._cancelingStandardInlineEdit = true;
        root.standardNoteInlineEditing = false;
        Qt.callLater(() => {
            root._cancelingStandardInlineEdit = false;
        });
    }

    function openContextMenu(x, y, data): void {
        root.renameDialogOpen = false;
        root.contextMenuData = data || ({});
        root.contextMenuX = Number(x || 0);
        root.contextMenuY = Number(y || 0);
        root.contextMenuOpen = true;
    }

    function closeContextMenu(): void {
        root.contextMenuOpen = false;
        root.contextMenuData = null;
    }

    function openRenameDialog(relPath: string): void {
        root.closeContextMenu();
        root.renameDialogOldPath = String(relPath || "");
        const parts = root.renameDialogOldPath.split("/");
        root.renameDialogNewName = parts[parts.length - 1] || "";
        root.renameDialogOpen = true;
        Qt.callLater(() => {
            if (root.renameDialogOpen && typeof renameInput !== "undefined") {
                renameInput.forceActiveFocus();
                renameInput.selectAll();
            }
        });
    }

    function getContextMenuActions(): var {
        const d = root.contextMenuData;
        if (!d) return [];
        const t = d.type || "workspace";
        const actions = [];
        if (t === "file" || t === "base-card") {
            actions.push({
                "id": "open",
                "icon": "open_in_new",
                "label": "Open Note",
                "onTrigger": () => {
                    if (root.nexus) root.nexus.openFile(d.relPath, true);
                    root.closeContextMenu();
                }
            });
            actions.push({
                "id": "open-split",
                "icon": "vertical_split",
                "label": "Open in Split",
                "onTrigger": () => {
                    if (root.nexus) {
                        root.nexus.setEditorMode("split");
                        root.nexus.openFile(d.relPath, true);
                    }
                    root.closeContextMenu();
                }
            });
            if (t === "base-card" && typeof d.onFlip === "function") {
                actions.push({
                    "id": "flip",
                    "icon": "flip",
                    "label": d.flipped ? "Flip to Front" : "Flip to Back",
                    "onTrigger": () => {
                        d.onFlip();
                        root.closeContextMenu();
                    }
                });
            }
            const inferredApiKind = root.nexus
                ? root.nexus.apiKindForNoteKind(String(d.apiKind || d.noteKind || (t === "base-card" ? root.nexus.activeCollection : "") || ""))
                : "";
            if (inferredApiKind.length > 0 && inferredApiKind !== "weather") {
                actions.push({
                    "id": "sync-api",
                    "icon": "cloud_download",
                    "label": "Sync Metadata from API",
                    "onTrigger": () => {
                        if (root.nexus)
                            root.nexus.syncNoteMetadataByKind(String(d.relPath || ""), inferredApiKind);
                        root.closeContextMenu();
                    }
                });
            }
            actions.push({
                "id": "copy-link",
                "icon": "link",
                "label": "Copy Wikilink",
                "onTrigger": () => {
                    const title = (d.title || d.relPath || "").replace(/\.md$/i, "");
                    if (root.nexus)
                        root.nexus.copyToClipboard("[[" + title + "]]", "Copied wikilink");
                    root.closeContextMenu();
                }
            });
            actions.push({
                "id": "copy-path",
                "icon": "content_copy",
                "label": "Copy Relative Path",
                "onTrigger": () => {
                    if (root.nexus)
                        root.nexus.copyToClipboard(String(d.relPath || ""), "Copied path");
                    root.closeContextMenu();
                }
            });
            actions.push({
                "id": "duplicate",
                "icon": "filter_none",
                "label": "Duplicate Note",
                "onTrigger": () => {
                    if (root.nexus) root.nexus.duplicateNote(d.relPath);
                    root.closeContextMenu();
                }
            });
            actions.push({
                "id": "reveal",
                "icon": "folder_open",
                "label": "Reveal in File Manager",
                "onTrigger": () => {
                    if (root.nexus)
                        root.nexus.revealInFileManager(String(d.relPath || ""), false);
                    root.closeContextMenu();
                }
            });
            actions.push({ "separator": true });
            actions.push({
                "id": "rename",
                "icon": "edit",
                "label": "Rename Note...",
                "onTrigger": () => {
                    root.openRenameDialog(d.relPath);
                }
            });
            actions.push({
                "id": "delete",
                "icon": "delete",
                "label": "Move to Trash",
                "isDestructive": true,
                "onTrigger": () => {
                    if (root.nexus) root.nexus.deletePath(d.relPath);
                    root.closeContextMenu();
                }
            });
        } else if (t === "folder") {
            actions.push({
                "id": "new-note",
                "icon": "note_add",
                "label": "New Note in Folder",
                "onTrigger": () => {
                    const f = String(d.relPath || "");
                    if (root.nexus) root.nexus.createNoteInFolder(f);
                    root.closeContextMenu();
                }
            });
            actions.push({
                "id": "new-note-modal",
                "icon": "travel_explore",
                "label": "New Note / Search API...",
                "onTrigger": () => {
                    const f = String(d.relPath || "");
                    root.closeContextMenu();
                    if (root.nexus) root.nexus.openNewNoteModal("standard", f);
                }
            });
            actions.push({
                "id": "new-folder",
                "icon": "create_new_folder",
                "label": "New Subfolder...",
                "onTrigger": () => {
                    const f = String(d.relPath || "");
                    if (root.nexus) {
                        const created = root.nexus.createUniqueSubfolder(f, "New Folder");
                        if (created) {
                            root.openRenameDialog(created);
                            return;
                        }
                    }
                    root.closeContextMenu();
                }
            });
            actions.push({
                "id": "copy-path",
                "icon": "content_copy",
                "label": "Copy Path",
                "onTrigger": () => {
                    if (root.nexus)
                        root.nexus.copyToClipboard(String(d.relPath || ""), "Copied path");
                    root.closeContextMenu();
                }
            });
            actions.push({
                "id": "reveal",
                "icon": "folder_open",
                "label": "Reveal in File Manager",
                "onTrigger": () => {
                    if (root.nexus)
                        root.nexus.revealInFileManager(String(d.relPath || ""), true);
                    root.closeContextMenu();
                }
            });
            actions.push({ "separator": true });
            actions.push({
                "id": "rename-folder",
                "icon": "edit",
                "label": "Rename Folder...",
                "onTrigger": () => {
                    root.openRenameDialog(d.relPath);
                }
            });
            actions.push({
                "id": "delete",
                "icon": "delete",
                "label": "Delete Folder (.trash)",
                "isDestructive": true,
                "onTrigger": () => {
                    if (root.nexus) root.nexus.deletePath(d.relPath);
                    root.closeContextMenu();
                }
            });
        } else if (t === "tag") {
            actions.push({
                "id": "search-tag",
                "icon": "search",
                "label": "Search Notes with Tag",
                "onTrigger": () => {
                    if (root.nexus) {
                        root.nexus.leftSidebarTab = "search";
                        const s = d.fullTag || ("#" + d.tag);
                        root.nexus.searchVault(s);
                    }
                    root.closeContextMenu();
                }
            });
            actions.push({
                "id": "copy-tag",
                "icon": "content_copy",
                "label": "Copy Tag",
                "onTrigger": () => {
                    if (root.nexus)
                        root.nexus.copyToClipboard(d.fullTag || ("#" + d.tag), "Copied tag");
                    root.closeContextMenu();
                }
            });
        } else {
            actions.push({
                "id": "new-note",
                "icon": "note_add",
                "label": "New Note",
                "onTrigger": () => {
                    if (root.nexus) root.nexus.createNoteInFolder("");
                    root.closeContextMenu();
                }
            });
            actions.push({
                "id": "new-note-modal",
                "icon": "travel_explore",
                "label": "New Note / Search API...",
                "onTrigger": () => {
                    root.closeContextMenu();
                    if (root.nexus) root.nexus.openNewNoteModal("standard", "");
                }
            });
            actions.push({
                "id": "new-folder",
                "icon": "create_new_folder",
                "label": "New Folder...",
                "onTrigger": () => {
                    if (root.nexus) {
                        const created = root.nexus.createUniqueSubfolder("", "New Folder");
                        if (created) {
                            root.openRenameDialog(created);
                            return;
                        }
                    }
                    root.closeContextMenu();
                }
            });
            actions.push({
                "id": "daily",
                "icon": "today",
                "label": "Today's Journal Note",
                "onTrigger": () => {
                    if (root.nexus) root.nexus.openDailyNote();
                    root.closeContextMenu();
                }
            });
            actions.push({
                "id": "reveal-vault",
                "icon": "folder_open",
                "label": "Reveal Vault in File Manager",
                "onTrigger": () => {
                    if (root.nexus?.configuredVaultPath) {
                        root.nexus.openExternally(root.nexus.configuredVaultPath, "Revealed Vault in File Manager");
                    }
                    root.closeContextMenu();
                }
            });
            actions.push({
                "id": "switcher",
                "icon": "search",
                "label": "Quick Switcher...",
                "onTrigger": () => {
                    if (root.nexus) {
                        root.nexus.commandPaletteMode = "switcher";
                        root.nexus.commandPaletteSearch = "";
                        root.nexus.commandPaletteOpen = true;
                    }
                    root.closeContextMenu();
                }
            });
            actions.push({
                "id": "command-palette",
                "icon": "terminal",
                "label": "Command Palette...",
                "onTrigger": () => {
                    if (root.nexus) {
                        root.nexus.commandPaletteMode = "commands";
                        root.nexus.commandPaletteSearch = "";
                        root.nexus.commandPaletteOpen = true;
                    }
                    root.closeContextMenu();
                }
            });
            actions.push({ "separator": true });
            actions.push({
                "id": "rescan",
                "icon": "refresh",
                "label": "Rescan Vault",
                "onTrigger": () => {
                    if (root.nexus) root.nexus.refreshVault();
                    root.closeContextMenu();
                }
            });
        }
        return actions;
    }

    Timer {
        id: homepageLiveClockTimer
        objectName: "nexusHomepageLiveClockTimer"
        interval: 1000
        repeat: true
        running: Boolean(root.nexus?.isOpen) && root.visible && root.transitionSettled && !Boolean(GlobalStates.regionSelectorOpen) && !Boolean(GlobalStates.annotationEditorOpen) && (root.nexus?.activeView ?? "homepage") === "homepage"
        onTriggered: {
            root.cursorBlinkOn = !root.cursorBlinkOn;
            root.liveDateTimeStr = root.formatHomepageDateTime(new Date());
        }
    }

    Connections {
        target: HostServices.Events
        function onListChanged() {
            root.plannerRevision += 1;
        }
    }

    Connections {
        target: HostServices.CalendarSync
        function onEventsChanged() {
            root.plannerRevision += 1;
        }
    }

    // Mix two colors by weightA (0.0..1.0) and return #rrggbb hex string (matching CSS color-mix in srgb)
    function mixColorHex(colorA, colorB, weightA: real): string {
        const w = Math.max(0.0, Math.min(1.0, Number(weightA)));
        const cA = Qt.color(colorA || "#82c2cf");
        const cB = Qt.color(colorB || "#141819");
        const r = Math.round((cA.r * w + cB.r * (1.0 - w)) * 255);
        const g = Math.round((cA.g * w + cB.g * (1.0 - w)) * 255);
        const b = Math.round((cA.b * w + cB.b * (1.0 - w)) * 255);
        const toHex = v => Math.max(0, Math.min(255, v)).toString(16).padStart(2, "0");
        return "#" + toHex(r) + toHex(g) + toHex(b);
    }

    // 14-stop Carbon Cyan scale (--cc-p00 .. --cc-p13) adapted from scripts/integrations/nexus_theme.py & 01_Core.css
    readonly property var ccWeights: [0, 0.012, 0.038, 0.073, 0.113, 0.167, 0.228, 0.310, 0.402, 0.506, 0.621, 0.748, 0.886, 1.0]

    readonly property bool wallpaperTransitionActive: Boolean(GlobalStates.wallpaperSelectorOpen) || Boolean(GlobalStates.wallpaperLauncherOpen) || Boolean(GlobalStates.coverflowSelectorOpen) || Boolean(HostServices.MaterialThemeLoader?.previewActive)
    readonly property bool surfaceActive: root.visible && Boolean(root.nexus?.isOpen ?? true) && !root.wallpaperTransitionActive

    function _readLiveThemeSignature(): string {
        return [
            String(Appearance.colors?.colPrimary ?? ""),
            String(Appearance.colors?.colOnPrimary ?? ""),
            String(Appearance.colors?.colSecondary ?? ""),
            String(Appearance.colors?.colSecondaryContainer ?? ""),
            String(Appearance.colors?.colOnSecondaryContainer ?? ""),
            String(Appearance.colors?.colTertiary ?? ""),
            String(Appearance.colors?.colLayer0 ?? ""),
            String(Appearance.colors?.colLayer1 ?? ""),
            String(Appearance.colors?.colLayer2 ?? ""),
            String(Appearance.colors?.colLayer2Hover ?? ""),
            String(Appearance.colors?.colOnLayer1 ?? ""),
            String(Appearance.colors?.colOnLayer0 ?? ""),
            String(Appearance.colors?.colSubtext ?? ""),
            String(Appearance.colors?.colLayer0Border ?? ""),
            String(Appearance.colors?.colError ?? "")
        ].join("|");
    }

    readonly property string rawThemeSignature: (!root.surfaceActive && root.themeCommitCount > 0)
        ? root.themeSignature
        : root._readLiveThemeSignature()

    QtObject {
        id: settledColors
        property color colPrimary: "#82c2cf"
        property color colOnPrimary: "#0c1113"
        property color colSecondary: "#73a7b3"
        property color colSecondaryContainer: "#1f3338"
        property color colOnSecondaryContainer: "#cde7ee"
        property color colTertiary: "#81be99"
        property color colLayer0: "#141819"
        property color colLayer1: "#10181b"
        property color colLayer2: "#162024"
        property color colLayer2Hover: "#1e2b30"
        property color colOnLayer0: "#eaf1f2"
        property color colOnLayer1: "#d9e1e3"
        property color colSubtext: "#8f9d9f"
        property color colLayer0Border: "#2a3439"
        property color colError: "#ffb4ab"
    }

    property string _settledPrimary: "#82c2cf"
    property string _settledOnPrimary: "#0c1113"
    property string _settledSecondary: "#73a7b3"
    property string _settledTertiary: "#81be99"
    property string _settledLayer0: "#141819"
    property string _settledLayer1: "#10181b"
    property string _settledLayer2: "#162024"
    property string _settledOnLayer0: "#eaf1f2"
    property string _settledOnLayer1: "#d9e1e3"
    property string _settledSubtext: "#8f9d9f"
    property string _settledBorder: "#2a3439"
    property var _settledCcStops: []
    property string themeSignature: ""
    property int themeCommitCount: 0

    function _computeCcStops(darkHex, lightHex, accentHex): var {
        const stops = new Array(14);
        const weights = root.ccWeights;
        for (let i = 0; i < 14; ++i) {
            const t = weights[i];
            const baseMix = root.mixColorHex(lightHex, darkHex, t);
            const accentWeight = 0.085 * 4.0 * t * (1.0 - t);
            stops[i] = root.mixColorHex(accentHex, baseMix, accentWeight);
        }
        return stops;
    }

    function _commitSettledTheme(): void {
        const p = String(Appearance.colors?.colPrimary ?? "#82c2cf");
        const onP = String(Appearance.colors?.colOnPrimary ?? "#0c1113");
        const sec = String(Appearance.colors?.colSecondary ?? "#73a7b3");
        const ter = String(Appearance.colors?.colTertiary ?? "#81be99");
        const l0 = String(Appearance.colors?.colLayer0 ?? "#141819");
        const l1 = String(Appearance.colors?.colLayer1 ?? "#10181b");
        const l2 = String(Appearance.colors?.colLayer2 ?? "#162024");
        const onL0 = String(Appearance.colors?.colOnLayer0 ?? "#eaf1f2");
        const onL1 = String(Appearance.colors?.colOnLayer1 ?? "#d9e1e3");
        const sub = String(Appearance.colors?.colSubtext ?? "#8f9d9f");
        const bdr = String(Appearance.colors?.colLayer0Border ?? "#2a3439");
        settledColors.colPrimary = Appearance.colors?.colPrimary ?? "#82c2cf";
        settledColors.colOnPrimary = Appearance.colors?.colOnPrimary ?? "#0c1113";
        settledColors.colSecondary = Appearance.colors?.colSecondary ?? "#73a7b3";
        settledColors.colSecondaryContainer = Appearance.colors?.colSecondaryContainer ?? "#1f3338";
        settledColors.colOnSecondaryContainer = Appearance.colors?.colOnSecondaryContainer ?? "#cde7ee";
        settledColors.colTertiary = Appearance.colors?.colTertiary ?? "#81be99";
        settledColors.colLayer0 = Appearance.colors?.colLayer0 ?? "#141819";
        settledColors.colLayer1 = Appearance.colors?.colLayer1 ?? "#10181b";
        settledColors.colLayer2 = Appearance.colors?.colLayer2 ?? "#162024";
        settledColors.colLayer2Hover = Appearance.colors?.colLayer2Hover ?? "#1e2b30";
        settledColors.colOnLayer0 = Appearance.colors?.colOnLayer0 ?? "#eaf1f2";
        settledColors.colOnLayer1 = Appearance.colors?.colOnLayer1 ?? "#d9e1e3";
        settledColors.colSubtext = Appearance.colors?.colSubtext ?? "#8f9d9f";
        settledColors.colLayer0Border = Appearance.colors?.colLayer0Border ?? "#2a3439";
        settledColors.colError = Appearance.colors?.colError ?? "#ffb4ab";
        root._settledPrimary = p;
        root._settledOnPrimary = onP;
        root._settledSecondary = sec;
        root._settledTertiary = ter;
        root._settledLayer0 = l0;
        root._settledLayer1 = l1;
        root._settledLayer2 = l2;
        root._settledOnLayer0 = onL0;
        root._settledOnLayer1 = onL1;
        root._settledSubtext = sub;
        root._settledBorder = bdr;
        root._settledCcStops = root._computeCcStops(l0, onL0, p);
        root.themeSignature = root._readLiveThemeSignature();
        root.themeCommitCount += 1;
    }

    Timer {
        id: themeSettleTimer
        objectName: "nexusThemeSettleTimer"
        interval: 96
        repeat: false
        onTriggered: {
            if (root.surfaceActive && root.themeSignature !== root._readLiveThemeSignature())
                root._commitSettledTheme();
        }
    }

    onRawThemeSignatureChanged: {
        const _sig = root.rawThemeSignature;
        if (!root.surfaceActive) {
            themeSettleTimer.stop();
            return;
        }
        themeSettleTimer.restart();
    }

    onSurfaceActiveChanged: {
        if (root.surfaceActive) {
            if (root.themeSignature !== root._readLiveThemeSignature()) {
                themeSettleTimer.stop();
                root._commitSettledTheme();
            }
        } else {
            themeSettleTimer.stop();
        }
    }

    function ccStop(index: int): string {
        const idx = Math.max(0, Math.min(13, Number(index)));
        const stops = root._settledCcStops;
        if (Array.isArray(stops) && stops.length > idx && stops[idx])
            return stops[idx];
        const t = root.ccWeights[idx];
        const baseMix = root.mixColorHex(root._settledOnLayer0, root._settledLayer0, t);
        const accentWeight = 0.055 * 4.0 * t * (1.0 - t);
        return root.mixColorHex(root._settledPrimary, baseMix, accentWeight);
    }

    function themeRichHtml(rawHtml): string {
        const s = String(rawHtml ?? "");
        if (s.length === 0)
            return "";
        const accHex = root._settledPrimary;
        const codeBgHex = root.ccStop(3);
        const codeFgHex = root._settledOnLayer0;
        const markBgHex = root.mixColorHex(accHex, root.ccStop(2), 0.30);
        const subHex = root._settledSubtext;
        return s
            .replace(/#38bdf8/gi, accHex)
            .replace(/#7dd3fc/gi, accHex)
            .replace(/#7dcfff/gi, accHex)
            .replace(/#1e293b/gi, codeBgHex)
            .replace(/#f8fafc/gi, codeFgHex)
            .replace(/#422006/gi, markBgHex)
            .replace(/#fde047/gi, accHex)
            .replace(/#c084fc/gi, subHex);
    }

    readonly property color borderSubtle: settledColors.colLayer0Border

    // Auto-themed Colored Sidebar folder tone ladder (--av-nav-tone-00 .. --av-nav-tone-99) from .obsidian/snippets/01_Core.css & 99_Alis_Theme.css
    function autoThemedFolderColor(prefixCode, fallbackHex): string {
        const code = String(prefixCode ?? "").trim();
        const primary = root._settledPrimary;
        const p05 = root.ccStop(5);
        const p04 = root.ccStop(4);
        if (code.length === 2 && code.charCodeAt(0) >= 48 && code.charCodeAt(0) <= 57 && code.charCodeAt(1) >= 48 && code.charCodeAt(1) <= 57) {
            if (code === "00")
                return root.mixColorHex(primary, root.ccStop(9), 0.92);
            if (code === "99")
                return root.mixColorHex(primary, p04, 0.06);
            const bucket = code[0] + "0";
            if (bucket === "00")
                return root.mixColorHex(primary, root.ccStop(9), 0.92);
            if (bucket === "10")
                return root.mixColorHex(primary, p05, 0.86);
            if (bucket === "20")
                return root.mixColorHex(primary, p05, 0.75);
            if (bucket === "30")
                return root.mixColorHex(primary, p05, 0.64);
            if (bucket === "40")
                return root.mixColorHex(primary, p05, 0.53);
            if (bucket === "50")
                return root.mixColorHex(primary, p05, 0.42);
            if (bucket === "60")
                return root.mixColorHex(primary, p05, 0.32);
            if (bucket === "70")
                return root.mixColorHex(primary, p05, 0.24);
            if (bucket === "80")
                return root.mixColorHex(primary, p05, 0.16);
            if (bucket === "90")
                return root.mixColorHex(primary, p05, 0.08);
        }
        return String(fallbackHex ?? "");
    }

    // Hover text color for colored folders: color-mix(in srgb, var(--av-folder-color) 60%, var(--text-normal))
    function autoThemedFolderTextColor(prefixCode, fallbackHex): string {
        const tone = root.autoThemedFolderColor(prefixCode, fallbackHex);
        const textNorm = root._settledOnLayer1;
        if (tone.length > 0)
            return root.mixColorHex(tone, textNorm, 0.65);
        return String(textNorm);
    }

    // 7-stop palette swatches (--cc-p04, --cc-p05, --cc-p06, --cc-p07, --cc-p09, --cc-p11, --cc-p13) ordered dark -> light
    readonly property var homepageThemeSwatches: [
        root.ccStop(4),
        root.ccStop(5),
        root.ccStop(6),
        root.ccStop(7),
        root.ccStop(9),
        root.ccStop(11),
        root.ccStop(13)
    ]

    readonly property var clusterPalette: [
        root.mixColorHex(root._settledPrimary, "#ffffff", 0.88),
        root._settledTertiary || root._settledPrimary,
        "#9ece6a",
        "#e0af68",
        "#f7768e",
        "#73daca",
        "#ff9e64",
        "#2ac3de"
    ]

    function cardItemById(cardId: string): var {
        if (cardId === "explorer")
            return nexusFileTreeCard;
        if (cardId === "localGraph")
            return nexusLocalGraphCard;
        if (cardId === "calendar")
            return nexusCalendarCard;
        if (cardId === "vaultGraph")
            return nexusVaultGraphCard;
        if (cardId === "context")
            return nexusContextCard;
        return null;
    }

    function slotItemByIndex(idx: int): var {
        if (idx === 0)
            return leftSlot0;
        if (idx === 1)
            return leftSlot1;
        if (idx === 2)
            return rightSlot0;
        if (idx === 3)
            return rightSlot1;
        if (idx === 4)
            return rightSlot2;
        return null;
    }

    function syncCardSlots(): void {
        if (!root || typeof root.cardItemById !== "function" || typeof root.slotItemByIndex !== "function")
            return;
        const order = (root.nexus && Array.isArray(root.nexus.cardOrder) && root.nexus.cardOrder.length === 5)
            ? root.nexus.cardOrder
            : ["explorer", "localGraph", "calendar", "vaultGraph", "context"];
        for (let i = 0; i < 5; ++i) {
            const card = root.cardItemById(String(order[i]));
            const slot = root.slotItemByIndex(i);
            if (card && slot && card.parent !== slot) {
                card.parent = slot;
            }
        }
    }

    function cardIdAtRootPos(rx: real, ry: real): string {
        const order = (root.nexus && Array.isArray(root.nexus.cardOrder) && root.nexus.cardOrder.length === 5)
            ? root.nexus.cardOrder
            : ["explorer", "localGraph", "calendar", "vaultGraph", "context"];
        for (let i = 0; i < 5; ++i) {
            const slot = root.slotItemByIndex(i);
            if (!slot || !slot.visible)
                continue;
            const pt = root.mapToItem(slot, rx, ry);
            if (pt.x >= 0 && pt.x <= slot.width && pt.y >= 0 && pt.y <= slot.height) {
                return String(order[i]);
            }
        }
        return "";
    }

    function cardIdAtGlobal(gx: real, gy: real): string {
        const pt = root.mapFromGlobal(gx, gy);
        return root.cardIdAtRootPos(pt.x, pt.y);
    }

    Item {
        id: workspaceKeyScope
        objectName: "nexusWorkspaceKeyScope"
        width: 0
        height: 0
        visible: true
        enabled: true
        focus: true
    }

    function restoreWorkspaceFocus(): void {
        if (root.nexus?.commandPaletteOpen && commandPaletteSearchInput) {
            commandPaletteSearchInput.focus = true;
            commandPaletteSearchInput.forceActiveFocus();
            return;
        }
        if (newNoteBar.visible && newNotePathField) {
            newNotePathField.focus = true;
            newNotePathField.forceActiveFocus();
            return;
        }
        if (commandPaletteSearchInput)
            commandPaletteSearchInput.focus = false;
        if (newNotePathField)
            newNotePathField.focus = false;
        if (root.nexus?.vimMode !== "COMMAND" && root.nexus?.vimMode !== "SEARCH" && vimCommandInput)
            vimCommandInput.focus = false;
        if (fileFilterField)
            fileFilterField.focus = false;
        if (quickPlannerEventInput)
            quickPlannerEventInput.focus = false;
        if (zkTitleField)
            zkTitleField.focus = false;
        if (nexusCollectionFilterField)
            nexusCollectionFilterField.focus = false;
        if (newCollectionEntryInput)
            newCollectionEntryInput.focus = false;
        if ((root.nexus?.activeView ?? "homepage") === "document"
            && ((root.nexus?.editorMode ?? "hybrid") === "raw"
                || (root.nexus?.editorMode ?? "hybrid") === "split"
                || (root.nexus?.currentDoc?.category ?? "") === "code")) {
            root.cursorBlinkOn = true;
            vimEditorArea.forceActiveFocus();
            return;
        }
        workspaceKeyScope.focus = true;
        workspaceKeyScope.forceActiveFocus();
        root.forceActiveFocus();
    }

    function focusPrimarySurface(): void {
        if (root.nexus?.commandPaletteOpen && commandPaletteSearchInput) {
            commandPaletteSearchInput.focus = true;
            commandPaletteSearchInput.forceActiveFocus();
            return;
        }
        root.restoreWorkspaceFocus();
    }

    function forwardKeyEvent(event): bool {
        if (!root.nexus || !event)
            return false;
        if (event.key === Qt.Key_Escape && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.KeypadModifier)) {
            if (root.handleEscape()) {
                event.accepted = true;
                return true;
            }
            return false;
        }
        root.focusPrimarySurface();
        const handled = Boolean(root.nexus.handleKeyEvent(event));
        if (handled) {
            event.accepted = true;
            if (root.nexus.commandPaletteOpen && commandPaletteSearchInput) {
                commandPaletteSearchInput.focus = true;
                commandPaletteSearchInput.forceActiveFocus();
            } else {
                root.restoreWorkspaceFocus();
            }
            return true;
        }
        return false;
    }

    // Two-stage Escape handler:
    // 1. Close open popups/modals/inline inputs first.
    // 2. If in Edit mode (raw / split / inline block edit / custom view inline edit / COMMAND / SEARCH), return to Reading Mode ("hybrid") and consume Escape.
    // 3. Otherwise return false so the host (or fallback) closes Nexus.
    function handleEscape(): bool {
        if (!root.nexus)
            return false;
        if (root.nexus.newNoteModalOpen) {
            root.nexus.closeNewNoteModal();
            root.restoreWorkspaceFocus();
            Qt.callLater(root.restoreWorkspaceFocus);
            return true;
        }
        if (root.renameDialogOpen) {
            root.renameDialogOpen = false;
            root.restoreWorkspaceFocus();
            Qt.callLater(root.restoreWorkspaceFocus);
            return true;
        }
        if (root.contextMenuOpen) {
            root.closeContextMenu();
            root.restoreWorkspaceFocus();
            Qt.callLater(root.restoreWorkspaceFocus);
            return true;
        }
        if (root.nexus.commandPaletteOpen) {
            root.nexus.commandPaletteOpen = false;
            commandPaletteSearchInput.focus = false;
            root.restoreWorkspaceFocus();
            Qt.callLater(root.restoreWorkspaceFocus);
            return true;
        }
        if (newNoteBar.visible) {
            newNoteBar.visible = false;
            newNotePathField.focus = false;
            root.restoreWorkspaceFocus();
            Qt.callLater(root.restoreWorkspaceFocus);
            return true;
        }
        if (root.standardNoteInlineEditing) {
            root.commitStandardNoteInlineEdit();
            root.restoreWorkspaceFocus();
            Qt.callLater(root.restoreWorkspaceFocus);
            return true;
        }
        if (root.nexus.vimMode === "COMMAND" || root.nexus.vimMode === "SEARCH") {
            root.nexus.vimMode = "NORMAL";
            root.nexus.vimCommandBuffer = "";
            vimCommandInput.text = "";
            vimCommandInput.focus = false;
            root.restoreWorkspaceFocus();
            Qt.callLater(root.restoreWorkspaceFocus);
            return true;
        }
        if (fileFilterField.activeFocus
            || quickPlannerEventInput.activeFocus
            || zkTitleField.activeFocus
            || nexusCollectionFilterField.activeFocus
            || newCollectionEntryInput.activeFocus) {
            root.restoreWorkspaceFocus();
            Qt.callLater(root.restoreWorkspaceFocus);
            return true;
        }
        if (nexusCustomViewsLoader.item && typeof nexusCustomViewsLoader.item.finishOrCancelInlineEditing === "function" && nexusCustomViewsLoader.item.finishOrCancelInlineEditing()) {
            root.restoreWorkspaceFocus();
            Qt.callLater(root.restoreWorkspaceFocus);
            return true;
        }
        if (nexusCustomViewsLoader.item && (nexusCustomViewsLoader.item.editingPlaytime || nexusCustomViewsLoader.item.editingCompletion)) {
            nexusCustomViewsLoader.item.editingPlaytime = false;
            nexusCustomViewsLoader.item.editingCompletion = false;
            root.restoreWorkspaceFocus();
            Qt.callLater(root.restoreWorkspaceFocus);
            return true;
        }
        if ((root.nexus.editingBlockId ?? -1) >= 0) {
            root.nexus.editingBlockId = -1;
            root.nexus.editingBlockText = "";
            root.restoreWorkspaceFocus();
            Qt.callLater(root.restoreWorkspaceFocus);
            return true;
        }
        if (root.nexus.activeView === "document" && (root.nexus.editorMode ?? "hybrid") !== "hybrid") {
            if (root.nexus.isDirty && vimEditorArea)
                root.nexus.saveCurrentNote(vimEditorArea.text);
            root.nexus.vimMode = "NORMAL";
            root.nexus.vimKeyBuffer = "";
            root.nexus.vimCountBuffer = "";
            root.nexus.vimCommandBuffer = "";
            root.nexus.vimVisualAnchor = -1;
            if (vimEditorArea) {
                vimEditorArea.deselect();
                vimEditorArea.focus = false;
            }
            root.nexus.setEditorMode("hybrid");
            root.nexus.vimStatusMessage = "Reading Mode";
            root.restoreWorkspaceFocus();
            Qt.callLater(root.restoreWorkspaceFocus);
            return true;
        }
        return false;
    }

    function triggerWindowShortcutAction(actionId: string): bool {
        if (!root.nexus)
            return false;
        const resolved = root.nexus._resolveActionId ? root.nexus._resolveActionId(actionId) : actionId;
        if (resolved === "togglePreviewMode"
            && root.nexus.activeView === "document"
            && (root.nexus.editorMode ?? "hybrid") === "hybrid") {
            if (nexusCustomViewsLoader.active
                && nexusCustomViewsLoader.item
                && nexusCustomViewsLoader.item.isCustomViewNote) {
                if (typeof nexusCustomViewsLoader.item.finishOrCancelInlineEditing === "function"
                    && nexusCustomViewsLoader.item.finishOrCancelInlineEditing()) {
                    root.restoreWorkspaceFocus();
                    Qt.callLater(root.restoreWorkspaceFocus);
                    return true;
                }
                if (typeof nexusCustomViewsLoader.item.startPrimaryInlineEdit === "function"
                    && nexusCustomViewsLoader.item.startPrimaryInlineEdit()) {
                    return true;
                }
            } else if (root.nexus.currentDoc && root.nexus.currentDoc.category === "markdown") {
                if (root.standardNoteInlineEditing) {
                    root.commitStandardNoteInlineEdit();
                    root.restoreWorkspaceFocus();
                    Qt.callLater(root.restoreWorkspaceFocus);
                    return true;
                }
                if (root.startStandardNoteInlineEdit())
                    return true;
            }
        }
        const ok = root.nexus.triggerShortcutAction(actionId);
        if (ok) {
            if (root.nexus.commandPaletteOpen) {
                commandPaletteSearchInput.focus = true;
                commandPaletteSearchInput.forceActiveFocus();
                Qt.callLater(() => {
                    if (root.nexus?.commandPaletteOpen) {
                        commandPaletteSearchInput.focus = true;
                        commandPaletteSearchInput.forceActiveFocus();
                        commandPaletteSearchInput.selectAll();
                    }
                });
            } else if (resolved !== "searchInNote" && resolved !== "searchInVault") {
                root.restoreWorkspaceFocus();
                Qt.callLater(root.restoreWorkspaceFocus);
            }
        }
        return ok;
    }

    Shortcut {
        sequences: ["Escape"]
        context: Qt.ApplicationShortcut
        autoRepeat: false
        enabled: Boolean(root.nexus?.isOpen) && root.visible && (!root.embeddedSurface || !Boolean(GlobalStates.abyssPerimeterActive))
        onActivated: {
            if (!root.handleEscape() && root.nexus) {
                root.nexus.close();
            }
        }
        onActivatedAmbiguously: {
            if (!root.handleEscape() && root.nexus) {
                root.nexus.close();
            }
        }
    }

    Repeater {
        id: nexusWindowShortcutRepeater
        objectName: "nexusWindowShortcutRepeater"
        model: root.nexus?.activeWindowShortcuts ?? []
        delegate: Item {
            id: winShortcutDelegate
            required property var modelData
            visible: false
            width: 0
            height: 0
            Shortcut {
                sequence: String(winShortcutDelegate.modelData?.sequence ?? "")
                context: Qt.ApplicationShortcut
                enabled: Boolean(root.nexus?.isOpen) && root.visible && String(winShortcutDelegate.modelData?.sequence ?? "").length > 0
                onActivated: {
                    root.triggerWindowShortcutAction(String(winShortcutDelegate.modelData?.actionId ?? ""));
                }
                onActivatedAmbiguously: {
                    root.triggerWindowShortcutAction(String(winShortcutDelegate.modelData?.actionId ?? ""));
                }
            }
        }
    }

    function _pointInsideItem(item, rx: real, ry: real): bool {
        if (!item || !item.visible)
            return false;
        const p = root.mapToItem(item, rx, ry);
        return p.x >= 0 && p.x <= item.width && p.y >= 0 && p.y <= item.height;
    }

    TapHandler {
        id: nexusWorkspaceFocusRecoveryTapHandler
        objectName: "nexusWorkspaceFocusRecoveryTapHandler"
        acceptedButtons: Qt.LeftButton
        gesturePolicy: TapHandler.ReleaseWithinBounds
        grabPermissions: PointerHandler.ApprovesTakeOverByAnything
        onTapped: (eventPoint, button) => {
            const pt = eventPoint.position;
            const fields = [fileFilterField, newNotePathField, quickPlannerEventInput, zkTitleField, nexusCollectionFilterField, newCollectionEntryInput];
            for (let i = 0; i < fields.length; ++i) {
                const f = fields[i];
                if (f && f.activeFocus && !root._pointInsideItem(f, pt.x, pt.y)) {
                    root.restoreWorkspaceFocus();
                    Qt.callLater(root.restoreWorkspaceFocus);
                    return;
                }
            }
            if ((!root.activeFocus || (!workspaceKeyScope.activeFocus && !vimEditorArea.activeFocus && !commandPaletteSearchInput.activeFocus))
                && !root.standardNoteInlineEditing
                && !Boolean(root.nexus?.newNoteModalOpen)
                && !(nexusCustomViewsLoader.item && nexusCustomViewsLoader.item.hasActiveInlineEditor)
                && (root.nexus?.editingBlockId ?? -1) < 0) {
                let insideField = false;
                for (let i = 0; i < fields.length; ++i) {
                    if (root._pointInsideItem(fields[i], pt.x, pt.y)) {
                        insideField = true;
                        break;
                    }
                }
                if (!insideField) {
                    root.restoreWorkspaceFocus();
                    Qt.callLater(root.restoreWorkspaceFocus);
                }
            }
        }
    }

    Component.onCompleted: {
        root._commitSettledTheme();
        root.syncCardSlots();
        Qt.callLater(() => {
            if (root && typeof root.syncCardSlots === "function")
                root.syncCardSlots();
        });
    }

    Connections {
        target: root.nexus
        function onIsOpenChanged() {
            if (root.nexus?.isOpen) {
                root.focusPrimarySurface();
                Qt.callLater(root.focusPrimarySurface);
            }
        }
        function onCurrentPathChanged() {
            if (root.standardNoteInlineEditing)
                root.cancelStandardNoteInlineEdit();
        }
        function onNewNoteModalOpenChanged() {
            if (root.nexus?.newNoteModalOpen) {
                Qt.callLater(() => {
                    if (root.nexus?.newNoteModalOpen && typeof newNoteApiSearchInput !== "undefined") {
                        newNoteApiSearchInput.forceActiveFocus();
                        newNoteApiSearchInput.selectAll();
                    }
                });
            } else {
                root.restoreWorkspaceFocus();
                Qt.callLater(root.restoreWorkspaceFocus);
            }
        }
        function onCardOrderChanged() {
            root.syncCardSlots();
        }
        function onFocusFileFilterRequested() {
            fileFilterField.forceActiveFocus();
            fileFilterField.selectAll();
        }
        function onFocusVaultSearchRequested() {
            fileFilterField.forceActiveFocus();
            fileFilterField.selectAll();
        }
        function onCommandPaletteOpenChanged() {
            if (root.nexus?.commandPaletteOpen) {
                commandPaletteSearchInput.forceActiveFocus();
                Qt.callLater(() => {
                    if (root.nexus?.commandPaletteOpen) {
                        commandPaletteSearchInput.forceActiveFocus();
                        commandPaletteSearchInput.selectAll();
                    }
                });
            } else {
                commandPaletteSearchInput.focus = false;
                root.restoreWorkspaceFocus();
                Qt.callLater(root.restoreWorkspaceFocus);
            }
        }
        function onCommandPaletteModeChanged() {
            if (root.nexus?.commandPaletteOpen) {
                commandPaletteSearchInput.forceActiveFocus();
                Qt.callLater(() => {
                    if (root.nexus?.commandPaletteOpen) {
                        commandPaletteSearchInput.forceActiveFocus();
                        commandPaletteSearchInput.selectAll();
                    }
                });
            }
        }
        function onEditorModeChanged() {
            const mode = root.nexus?.editorMode ?? "hybrid";
            if (mode === "raw" || mode === "split") {
                root.cursorBlinkOn = true;
                vimEditorArea.forceActiveFocus();
                vimEditorArea.cursorVisible = true;
                Qt.callLater(() => {
                    if (vimEditorPane.visible) {
                        vimEditorArea.forceActiveFocus();
                        vimEditorArea.cursorVisible = true;
                    }
                });
            } else {
                if (vimEditorArea)
                    vimEditorArea.focus = false;
                root.restoreWorkspaceFocus();
                Qt.callLater(root.restoreWorkspaceFocus);
            }
        }
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape && (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.ShiftModifier | Qt.MetaModifier)) === 0) {
            if (!root.handleEscape() && root.nexus) {
                root.nexus.close();
            }
            event.accepted = true;
            return;
        }
        if (event.key === Qt.Key_I
            && (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.ShiftModifier | Qt.MetaModifier)) === 0
            && root.nexus
            && !root.nexus.commandPaletteOpen
            && !root.nexus.newNoteModalOpen
            && root.nexus.vimMode === "NORMAL"
            && root.nexus.activeView === "document"
            && root.nexus.editorMode === "hybrid") {
            if (nexusCustomViewsLoader.active && nexusCustomViewsLoader.item && typeof nexusCustomViewsLoader.item.startPrimaryInlineEdit === "function") {
                if (nexusCustomViewsLoader.item.startPrimaryInlineEdit()) {
                    event.accepted = true;
                    return;
                }
            }
            if (root.startStandardNoteInlineEdit()) {
                event.accepted = true;
                return;
            }
        }
        if (root.nexus && root.nexus.handleKeyEvent(event)) {
            event.accepted = true;
        }
    }

    component CardReorderPill: RowLayout {
        id: pillRoot
        required property string cardId
        property bool cardHovered: false
        readonly property bool shown: cardHovered
            || prevSlotMouse.containsMouse
            || dragHandleMouse.containsMouse
            || nextSlotMouse.containsMouse
            || dragHandleMouse.pressed
            || root.draggingCardId.length > 0
        Layout.fillWidth: false
        spacing: 2
        opacity: shown ? 1.0 : 0.0
        Behavior on opacity {
            NumberAnimation {
                duration: 150
                easing.type: Easing.OutCubic
            }
        }

        Rectangle {
            implicitWidth: 18
            implicitHeight: 20
            width: 18
            height: 20
            radius: 4
            color: prevSlotMouse.containsMouse ? settledColors.colLayer2Hover : "transparent"
            MaterialSymbol {
                anchors.centerIn: parent
                text: "navigate_before"
                iconSize: 13
                color: settledColors.colSubtext
            }
            MouseArea {
                id: prevSlotMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (root.nexus)
                        root.nexus.moveCardStep(pillRoot.cardId, -1);
                }
            }
        }

        Rectangle {
            objectName: "nexusCardDragHandle_" + pillRoot.cardId
            implicitWidth: 22
            implicitHeight: 20
            width: 22
            height: 20
            radius: 4
            color: (root.draggingCardId === pillRoot.cardId)
                ? settledColors.colPrimary
                : (dragHandleMouse.containsMouse ? settledColors.colLayer2Hover : "transparent")

            MaterialSymbol {
                anchors.centerIn: parent
                text: "drag_indicator"
                iconSize: 14
                color: (root.draggingCardId === pillRoot.cardId) ? settledColors.colOnPrimary : settledColors.colSubtext
            }

            MouseArea {
                id: dragHandleMouse
                anchors.fill: parent
                hoverEnabled: true
                preventStealing: true
                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                onPressed: mouse => {
                    root.draggingCardId = pillRoot.cardId;
                    const p = mapToItem(root, mouse.x, mouse.y);
                    root.dragRootX = p.x;
                    root.dragRootY = p.y;
                    root.dropTargetCardId = root.cardIdAtRootPos(p.x, p.y);
                }
                onPositionChanged: mouse => {
                    if (!pressed || root.draggingCardId !== pillRoot.cardId)
                        return;
                    const p = mapToItem(root, mouse.x, mouse.y);
                    root.dragRootX = p.x;
                    root.dragRootY = p.y;
                    root.dropTargetCardId = root.cardIdAtRootPos(p.x, p.y);
                }
                onReleased: mouse => {
                    const p = mapToItem(root, mouse.x, mouse.y);
                    const targetId = root.cardIdAtRootPos(p.x, p.y) || root.dropTargetCardId;
                    if (root.nexus && root.draggingCardId.length > 0 && targetId.length > 0 && root.draggingCardId !== targetId) {
                        root.nexus.swapCards(root.draggingCardId, targetId);
                    }
                    root.draggingCardId = "";
                    root.dropTargetCardId = "";
                }
                onCanceled: {
                    root.draggingCardId = "";
                    root.dropTargetCardId = "";
                }
            }
        }

        Rectangle {
            implicitWidth: 18
            implicitHeight: 20
            width: 18
            height: 20
            radius: 4
            color: nextSlotMouse.containsMouse ? settledColors.colLayer2Hover : "transparent"
            MaterialSymbol {
                anchors.centerIn: parent
                text: "navigate_next"
                iconSize: 13
                color: settledColors.colSubtext
            }
            MouseArea {
                id: nextSlotMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (root.nexus)
                        root.nexus.moveCardStep(pillRoot.cardId, 1);
                }
            }
        }
    }

    function clusterColor(groupIdx: int): color {
        const idx = Math.abs(Number(groupIdx || 0)) % root.clusterPalette.length;
        return root.clusterPalette[idx];
    }

    // ═══════════════════════════════════════════════════════════════════════
    // BUILT-IN VIM ENGINE (Obsidian / CodeMirror Vim Parity: hjkl, counts,
    // operators d/c/y, motions w/b/e/0/^/$/gg/G, x/X/Delete/Backspace,
    // s/S/C/D/r/J/~, Visual v/V, Insert i/I/a/A/o/O, Undo u / Redo Ctrl+R)
    // ═══════════════════════════════════════════════════════════════════════
    function _vimSyncVisualSelection(area): void {
        if (!area || !root.nexus)
            return;
        const m = root.nexus.vimMode;
        const anchor = root.nexus.vimVisualAnchor;
        if ((m === "VISUAL" || m === "VISUAL_LINE") && anchor >= 0) {
            if (m === "VISUAL_LINE") {
                const b1 = root.vimLineBounds(area.text, anchor);
                const b2 = root.vimLineBounds(area.text, area.cursorPosition);
                const s = Math.min(b1.start, b2.start);
                const e = Math.max(b1.end, b2.end);
                area.select(s, e);
            } else {
                const s = Math.min(anchor, area.cursorPosition);
                const e = Math.min(area.text.length, Math.max(anchor, area.cursorPosition) + 1);
                area.select(s, e);
            }
        }
    }

    function vimMoveCursorLeft(area, count = 1): void {
        if (!area)
            return;
        const steps = Math.max(1, count);
        for (let s = 0; s < steps; ++s) {
            const pos = area.cursorPosition;
            if (pos > 0 && area.text.charAt(pos - 1) !== "\n")
                area.cursorPosition = pos - 1;
            else
                break;
        }
        root._vimSyncVisualSelection(area);
    }

    function vimMoveCursorRight(area, count = 1): void {
        if (!area)
            return;
        const steps = Math.max(1, count);
        for (let s = 0; s < steps; ++s) {
            const pos = area.cursorPosition;
            if (pos < area.text.length && area.text.charAt(pos) !== "\n")
                area.cursorPosition = pos + 1;
            else
                break;
        }
        root._vimSyncVisualSelection(area);
    }

    function vimLineBounds(text: string, pos: int): var {
        const clamped = Math.max(0, Math.min(text.length, pos));
        let start = clamped > 0 ? text.lastIndexOf("\n", clamped - 1) : -1;
        start = start === -1 ? 0 : start + 1;
        let end = text.indexOf("\n", clamped);
        if (end === -1)
            end = text.length;
        return {
            "start": start,
            "end": end,
            "col": clamped - start
        };
    }

    function vimCurrentLineNumber(text: string, pos: int): int {
        const clamped = Math.max(0, Math.min(text.length, pos));
        let line = 1;
        for (let i = 0; i < clamped; ++i) {
            if (text.charAt(i) === "\n")
                line += 1;
        }
        return line;
    }

    function vimMoveCursorVertical(area, delta: int): void {
        if (!area)
            return;
        const steps = Math.abs(delta);
        const dir = delta < 0 ? -1 : 1;
        for (let s = 0; s < steps; ++s) {
            const text = area.text;
            const cur = root.vimLineBounds(text, area.cursorPosition);
            if (dir < 0) {
                if (cur.start === 0)
                    break;
                const prevEnd = cur.start - 1;
                let prevStart = prevEnd > 0 ? text.lastIndexOf("\n", prevEnd - 1) : -1;
                prevStart = prevStart === -1 ? 0 : prevStart + 1;
                const prevLen = prevEnd - prevStart;
                area.cursorPosition = prevStart + Math.min(cur.col, prevLen);
            } else {
                if (cur.end >= text.length)
                    break;
                const nextStart = cur.end + 1;
                let nextEnd = text.indexOf("\n", nextStart);
                if (nextEnd === -1)
                    nextEnd = text.length;
                const nextLen = nextEnd - nextStart;
                area.cursorPosition = nextStart + Math.min(cur.col, nextLen);
            }
        }
        root._vimSyncVisualSelection(area);
    }

    function _vimWordForwardPos(text: string, startPos: int, count = 1): int {
        let i = Math.max(0, Math.min(text.length, startPos));
        const steps = Math.max(1, count);
        for (let s = 0; s < steps; ++s) {
            while (i < text.length && /\S/.test(text.charAt(i)))
                i += 1;
            while (i < text.length && /\s/.test(text.charAt(i)))
                i += 1;
        }
        return i;
    }

    function _vimWordEndPos(text: string, startPos: int, count = 1): int {
        let i = Math.max(0, Math.min(text.length, startPos));
        const steps = Math.max(1, count);
        for (let s = 0; s < steps; ++s) {
            if (i < text.length)
                i += 1;
            while (i < text.length && /\s/.test(text.charAt(i)))
                i += 1;
            while (i + 1 < text.length && /\S/.test(text.charAt(i + 1)))
                i += 1;
        }
        return i;
    }

    function _vimWordBackwardPos(text: string, startPos: int, count = 1): int {
        let i = Math.max(0, Math.min(text.length, startPos));
        const steps = Math.max(1, count);
        for (let s = 0; s < steps; ++s) {
            if (i > 0)
                i -= 1;
            while (i > 0 && /\s/.test(text.charAt(i)))
                i -= 1;
            while (i > 0 && /\S/.test(text.charAt(i - 1)))
                i -= 1;
        }
        return i;
    }

    function vimMoveWordForward(area, count = 1): void {
        if (!area)
            return;
        area.cursorPosition = root._vimWordForwardPos(area.text, area.cursorPosition, count);
        root._vimSyncVisualSelection(area);
    }

    function vimMoveWordEnd(area, count = 1): void {
        if (!area)
            return;
        area.cursorPosition = root._vimWordEndPos(area.text, area.cursorPosition, count);
        root._vimSyncVisualSelection(area);
    }

    function vimMoveWordBackward(area, count = 1): void {
        if (!area)
            return;
        area.cursorPosition = root._vimWordBackwardPos(area.text, area.cursorPosition, count);
        root._vimSyncVisualSelection(area);
    }

    function vimPushUndo(text: string): void {
        if (!root.nexus)
            return;
        const stack = root.nexus.vimUndoStack.slice();
        if (stack.length === 0 || stack[stack.length - 1] !== text) {
            stack.push(text);
            if (stack.length > 80)
                stack.shift();
            root.nexus.vimUndoStack = stack;
        }
    }

    function vimDeleteRange(area, fromPos: int, toPos: int, enterInsert = false, statusMsg = ""): void {
        if (!area || !root.nexus)
            return;
        const text = area.text;
        const s = Math.max(0, Math.min(text.length, Math.min(fromPos, toPos)));
        const e = Math.max(0, Math.min(text.length, Math.max(fromPos, toPos)));
        root.vimPushUndo(text);
        root.nexus.vimRegister = text.substring(s, e);
        const newText = text.substring(0, s) + text.substring(e);
        area.text = newText;
        root.nexus.draftContent = newText;
        root.nexus.isDirty = true;
        area.cursorPosition = Math.min(s, newText.length);
        if (enterInsert) {
            root.nexus.vimMode = "INSERT";
            root.nexus.vimVisualAnchor = -1;
        } else {
            root.nexus.vimMode = "NORMAL";
            root.nexus.vimVisualAnchor = -1;
        }
        if (statusMsg)
            root.nexus.vimStatusMessage = statusMsg;
    }

    function vimDeleteCurrentLine(area, count = 1): void {
        if (!area || !root.nexus)
            return;
        const text = area.text;
        root.vimPushUndo(text);
        const firstBounds = root.vimLineBounds(text, area.cursorPosition);
        let endPos = firstBounds.end;
        for (let i = 1; i < Math.max(1, count); ++i) {
            if (endPos < text.length) {
                const nextB = root.vimLineBounds(text, endPos + 1);
                endPos = nextB.end;
            }
        }
        root.nexus.vimRegister = text.substring(firstBounds.start, endPos);
        let newText = "";
        if (endPos < text.length) {
            newText = text.substring(0, firstBounds.start) + text.substring(endPos + 1);
        } else if (firstBounds.start > 0) {
            newText = text.substring(0, firstBounds.start - 1);
        }
        area.text = newText;
        root.nexus.draftContent = newText;
        root.nexus.isDirty = true;
        area.cursorPosition = Math.min(firstBounds.start, newText.length);
        root.nexus.vimStatusMessage = "Deleted " + String(Math.max(1, count)) + " line(s) (dd)";
    }

    function vimChangeCurrentLine(area): void {
        if (!area || !root.nexus)
            return;
        const text = area.text;
        root.vimPushUndo(text);
        const bounds = root.vimLineBounds(text, area.cursorPosition);
        const lineText = text.substring(bounds.start, bounds.end);
        const indentMatch = lineText.match(/^\s*/);
        const indent = indentMatch ? indentMatch[0] : "";
        root.nexus.vimRegister = lineText;
        const newText = text.substring(0, bounds.start) + indent + text.substring(bounds.end);
        area.text = newText;
        root.nexus.draftContent = newText;
        root.nexus.isDirty = true;
        area.cursorPosition = bounds.start + indent.length;
        root.nexus.vimMode = "INSERT";
        root.nexus.vimStatusMessage = "Change line (cc)";
    }

    function vimYankCurrentLine(area, count = 1): void {
        if (!area || !root.nexus)
            return;
        const text = area.text;
        const firstBounds = root.vimLineBounds(text, area.cursorPosition);
        let endPos = firstBounds.end;
        for (let i = 1; i < Math.max(1, count); ++i) {
            if (endPos < text.length) {
                const nextB = root.vimLineBounds(text, endPos + 1);
                endPos = nextB.end;
            }
        }
        root.nexus.vimRegister = text.substring(firstBounds.start, endPos);
        root.nexus.vimStatusMessage = "Yanked " + String(Math.max(1, count)) + " line(s) (yy)";
    }

    function vimPasteLine(area, after: bool): void {
        if (!area || !root.nexus)
            return;
        const reg = String(root.nexus.vimRegister ?? "");
        const text = area.text;
        root.vimPushUndo(text);
        const bounds = root.vimLineBounds(text, area.cursorPosition);
        let newText = "";
        let newPos = bounds.start;
        if (after) {
            newText = text.substring(0, bounds.end) + "\n" + reg + text.substring(bounds.end);
            newPos = bounds.end + 1;
        } else {
            newText = text.substring(0, bounds.start) + reg + "\n" + text.substring(bounds.start);
            newPos = bounds.start;
        }
        area.text = newText;
        root.nexus.draftContent = newText;
        root.nexus.isDirty = true;
        area.cursorPosition = Math.min(newPos, newText.length);
        root.nexus.vimStatusMessage = "Pasted from register";
    }

    function vimJoinLines(area): void {
        if (!area || !root.nexus)
            return;
        const text = area.text;
        const bounds = root.vimLineBounds(text, area.cursorPosition);
        if (bounds.end >= text.length)
            return;
        root.vimPushUndo(text);
        const nextB = root.vimLineBounds(text, bounds.end + 1);
        const nextTrimmed = text.substring(nextB.start, nextB.end).replace(/^\s+/, "");
        const joinSpace = (bounds.end > bounds.start && nextTrimmed.length > 0) ? " " : "";
        const newText = text.substring(0, bounds.end) + joinSpace + nextTrimmed + text.substring(nextB.end);
        area.text = newText;
        root.nexus.draftContent = newText;
        root.nexus.isDirty = true;
        area.cursorPosition = Math.min(bounds.end, newText.length);
        root.nexus.vimStatusMessage = "Joined lines (J)";
    }

    function vimToggleCaseAtCursor(area): void {
        if (!area || !root.nexus || area.cursorPosition >= area.text.length)
            return;
        const text = area.text;
        const pos = area.cursorPosition;
        const ch = text.charAt(pos);
        if (ch === "\n")
            return;
        root.vimPushUndo(text);
        const toggled = (ch === ch.toLowerCase()) ? ch.toUpperCase() : ch.toLowerCase();
        const newText = text.substring(0, pos) + toggled + text.substring(pos + 1);
        area.text = newText;
        root.nexus.draftContent = newText;
        root.nexus.isDirty = true;
        area.cursorPosition = Math.min(pos + 1, newText.length);
    }

    function vimUndo(area): void {
        if (!area || !root.nexus || root.nexus.vimUndoStack.length === 0)
            return;
        const undoStack = root.nexus.vimUndoStack.slice();
        const prev = undoStack.pop();
        root.nexus.vimUndoStack = undoStack;
        const redoStack = root.nexus.vimRedoStack.slice();
        redoStack.push(area.text);
        root.nexus.vimRedoStack = redoStack;
        area.text = prev;
        root.nexus.draftContent = prev;
        root.nexus.isDirty = true;
        root.nexus.vimStatusMessage = "Undo";
    }

    function vimRedo(area): void {
        if (!area || !root.nexus || root.nexus.vimRedoStack.length === 0)
            return;
        const redoStack = root.nexus.vimRedoStack.slice();
        const next = redoStack.pop();
        root.nexus.vimRedoStack = redoStack;
        root.vimPushUndo(area.text);
        area.text = next;
        root.nexus.draftContent = next;
        root.nexus.isDirty = true;
        root.nexus.vimStatusMessage = "Redo";
    }

    function _vimInnerWordBounds(text: string, pos: int, around = false): var {
        const len = text.length;
        if (len === 0)
            return { "start": 0, "end": 0 };
        const p = Math.max(0, Math.min(len - 1, pos));
        const isWordChar = ch => /[A-Za-z0-9_\u00C0-\u024F\u1E00-\u1EFF]/.test(ch);
        const curIsWord = isWordChar(text.charAt(p));
        let s = p;
        let e = p + 1;
        if (curIsWord) {
            while (s > 0 && isWordChar(text.charAt(s - 1)))
                s -= 1;
            while (e < len && isWordChar(text.charAt(e)))
                e += 1;
            if (around) {
                while (e < len && text.charAt(e) === " ")
                    e += 1;
            }
        } else {
            while (s > 0 && !isWordChar(text.charAt(s - 1)) && text.charAt(s - 1) !== "\n")
                s -= 1;
            while (e < len && !isWordChar(text.charAt(e)) && text.charAt(e) !== "\n")
                e += 1;
        }
        return { "start": s, "end": e };
    }

    function _vimLineStartForLineNumber(text: string, targetLine: int): int {
        const line = Math.max(1, targetLine);
        if (line === 1)
            return 0;
        let curLine = 1;
        for (let i = 0; i < text.length; ++i) {
            if (text.charAt(i) === "\n") {
                curLine += 1;
                if (curLine === line)
                    return i + 1;
            }
        }
        return text.length;
    }

    function vimIndentLines(area, count = 1, outdent = false): void {
        if (!area || !root.nexus)
            return;
        const text = area.text;
        root.vimPushUndo(text);
        const firstB = root.vimLineBounds(text, area.cursorPosition);
        let endPos = firstB.end;
        for (let i = 1; i < Math.max(1, count); ++i) {
            if (endPos < text.length) {
                const nb = root.vimLineBounds(text, endPos + 1);
                endPos = nb.end;
            }
        }
        const block = text.substring(firstB.start, endPos);
        const lines = block.split("\n");
        const updated = lines.map(ln => outdent ? ln.replace(/^(?: {1,2}|\t)/, "") : ("  " + ln)).join("\n");
        const newText = text.substring(0, firstB.start) + updated + text.substring(endPos);
        area.text = newText;
        root.nexus.draftContent = newText;
        root.nexus.isDirty = true;
        area.cursorPosition = Math.min(firstB.start + (outdent ? 0 : 2), newText.length);
        root.nexus.vimStatusMessage = outdent ? "Unindented line(s) (<<)" : "Indented line(s) (>>)";
    }

    function vimHandleNormalKey(event, area): bool {
        if (!root.nexus)
            return false;

        if (event.key === Qt.Key_Escape) {
            if (!root.handleEscape() && root.nexus) {
                root.nexus.close();
            }
            return true;
        }

        // Ctrl+S saves in any mode
        if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_S) {
            root.nexus.saveCurrentNote(area ? area.text : null);
            return true;
        }

        if (!root.nexus.vimEnabled)
            return false;

        if (root.nexus.vimMode === "INSERT") {
            if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_BracketLeft) {
                root.nexus.vimMode = "NORMAL";
                root.nexus.vimCountBuffer = "";
                root.nexus.vimKeyBuffer = "";
                return true;
            }
            return false;
        }

        if (root.nexus.vimMode === "COMMAND" || root.nexus.vimMode === "SEARCH") {
            return false;
        }

        // Ctrl+D / Ctrl+U half-page vertical movement in Normal/Visual mode
        if ((event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_D || event.key === Qt.Key_U)) {
            const delta = event.key === Qt.Key_D ? 12 : -12;
            root.vimMoveCursorVertical(area, delta);
            root.nexus.vimCountBuffer = "";
            root.nexus.vimKeyBuffer = "";
            return true;
        }

        const keyText = String(event.text ?? "");
        const buf = root.nexus.vimKeyBuffer;
        const hasExplicitCount = root.nexus.vimCountBuffer.length > 0;
        const countVal = hasExplicitCount ? Math.max(1, parseInt(root.nexus.vimCountBuffer, 10) || 1) : 1;

        // Replace single character operator: r<char>
        if (buf === "r") {
            root.nexus.vimKeyBuffer = "";
            root.nexus.vimCountBuffer = "";
            if (area && keyText.length === 1 && area.cursorPosition < area.text.length && area.text.charAt(area.cursorPosition) !== "\n") {
                root.vimPushUndo(area.text);
                const pos = area.cursorPosition;
                const newText = area.text.substring(0, pos) + keyText + area.text.substring(pos + 1);
                area.text = newText;
                root.nexus.draftContent = newText;
                root.nexus.isDirty = true;
                area.cursorPosition = pos;
                root.nexus.vimStatusMessage = "Replaced char (r" + keyText + ")";
            }
            return true;
        }

        // Inline char find motions: f<char>, t<char>, F<char>, T<char>
        if (buf === "f" || buf === "t" || buf === "F" || buf === "T") {
            root.nexus.vimKeyBuffer = "";
            root.nexus.vimCountBuffer = "";
            if (area && keyText.length === 1) {
                const b = root.vimLineBounds(area.text, area.cursorPosition);
                if (buf === "f" || buf === "t") {
                    const idx = area.text.indexOf(keyText, area.cursorPosition + 1);
                    if (idx !== -1 && idx <= b.end) {
                        area.cursorPosition = buf === "t" ? Math.max(b.start, idx - 1) : idx;
                        root._vimSyncVisualSelection(area);
                    }
                } else {
                    const lineSlice = area.text.substring(b.start, area.cursorPosition);
                    const relIdx = lineSlice.lastIndexOf(keyText);
                    if (relIdx !== -1) {
                        const absIdx = b.start + relIdx;
                        area.cursorPosition = buf === "T" ? Math.min(b.end, absIdx + 1) : absIdx;
                        root._vimSyncVisualSelection(area);
                    }
                }
            }
            return true;
        }

        // Count prefix digits (1-9, or 0 when countBuffer already non-empty and no operator pending)
        if (buf.length === 0 && ((keyText >= "1" && keyText <= "9") || (keyText === "0" && root.nexus.vimCountBuffer.length > 0))) {
            root.nexus.vimCountBuffer += keyText;
            root.nexus.vimStatusMessage = root.nexus.vimCountBuffer;
            return true;
        }

        // Multi-key sequences: gg, dd, dw, de, db, diw, daw, d$, d0, cc, cw, ce, ciw, caw, c$, yy, yw, yiw, yaw, >>, <<, za, zM, zR
        if (buf.length > 0) {
            const seq = buf + keyText;
            if (seq === "di" || seq === "da" || seq === "ci" || seq === "ca" || seq === "yi" || seq === "ya") {
                root.nexus.vimKeyBuffer = seq;
                return true;
            }
            root.nexus.vimKeyBuffer = "";
            root.nexus.vimCountBuffer = "";
            if (seq === "gg") {
                if (area) {
                    area.cursorPosition = hasExplicitCount
                        ? root._vimLineStartForLineNumber(area.text, countVal)
                        : 0;
                    root._vimSyncVisualSelection(area);
                }
                root.nexus.vimStatusMessage = hasExplicitCount ? ("Line " + String(countVal) + " (gg)") : "Top of document (gg)";
                return true;
            }
            if (seq === "dd") {
                root.vimDeleteCurrentLine(area, countVal);
                return true;
            }
            if (seq === "dw" || seq === "de") {
                if (area) {
                    const target = seq === "dw"
                        ? root._vimWordForwardPos(area.text, area.cursorPosition, countVal)
                        : Math.min(area.text.length, root._vimWordEndPos(area.text, area.cursorPosition, countVal) + 1);
                    root.vimDeleteRange(area, area.cursorPosition, target, false, "Deleted word (" + seq + ")");
                }
                return true;
            }
            if (seq === "diw" || seq === "daw" || seq === "ciw" || seq === "caw" || seq === "yiw" || seq === "yaw") {
                if (area) {
                    const around = seq.charAt(1) === "a";
                    const wb = root._vimInnerWordBounds(area.text, area.cursorPosition, around);
                    if (seq.startsWith("y")) {
                        root.nexus.vimRegister = area.text.substring(wb.start, wb.end);
                        root.nexus.vimStatusMessage = "Yanked inner word (" + seq + ")";
                    } else {
                        const enterIns = seq.startsWith("c");
                        root.vimDeleteRange(area, wb.start, wb.end, enterIns, (enterIns ? "Change" : "Delete") + " word (" + seq + ")");
                    }
                }
                return true;
            }
            if (seq === "db") {
                if (area) {
                    const target = root._vimWordBackwardPos(area.text, area.cursorPosition, countVal);
                    root.vimDeleteRange(area, target, area.cursorPosition, false, "Deleted word backward (db)");
                }
                return true;
            }
            if (seq === "d$") {
                if (area) {
                    const b = root.vimLineBounds(area.text, area.cursorPosition);
                    root.vimDeleteRange(area, area.cursorPosition, b.end, false, "Deleted to end of line (d$)");
                }
                return true;
            }
            if (seq === "d0" || seq === "d^") {
                if (area) {
                    const b = root.vimLineBounds(area.text, area.cursorPosition);
                    root.vimDeleteRange(area, b.start, area.cursorPosition, false, "Deleted to start of line (d0)");
                }
                return true;
            }
            if (seq === "cc") {
                root.vimChangeCurrentLine(area);
                return true;
            }
            if (seq === "cw" || seq === "ce") {
                if (area) {
                    const target = Math.min(area.text.length, root._vimWordEndPos(area.text, area.cursorPosition, countVal) + 1);
                    root.vimDeleteRange(area, area.cursorPosition, target, true, "Change word (" + seq + ")");
                }
                return true;
            }
            if (seq === "c$") {
                if (area) {
                    const b = root.vimLineBounds(area.text, area.cursorPosition);
                    root.vimDeleteRange(area, area.cursorPosition, b.end, true, "Change to end of line (c$)");
                }
                return true;
            }
            if (seq === "yy") {
                root.vimYankCurrentLine(area, countVal);
                return true;
            }
            if (seq === "yw") {
                if (area) {
                    const target = root._vimWordForwardPos(area.text, area.cursorPosition, countVal);
                    root.nexus.vimRegister = area.text.substring(area.cursorPosition, target);
                    root.nexus.vimStatusMessage = "Yanked word (yw)";
                }
                return true;
            }
            if (seq === ">>") {
                root.vimIndentLines(area, countVal, false);
                return true;
            }
            if (seq === "<<") {
                root.vimIndentLines(area, countVal, true);
                return true;
            }
            if (seq === "za") {
                if (root.nexus.currentDoc && Array.isArray(root.nexus.currentDoc.blocks)) {
                    const lineNo = area ? root.vimCurrentLineNumber(area.text, area.cursorPosition) : 1;
                    for (let i = 0; i < root.nexus.currentDoc.blocks.length; ++i) {
                        const b = root.nexus.currentDoc.blocks[i];
                        if (b && b.foldable && lineNo >= b.lineStart && lineNo <= b.foldEndLine) {
                            root.nexus.toggleBlockFold(b.id);
                            root.nexus.vimStatusMessage = "Toggled fold (za)";
                            break;
                        }
                    }
                }
                return true;
            }
            if (seq === "zM") {
                root.nexus.foldAllBlocks();
                return true;
            }
            if (seq === "zR") {
                root.nexus.unfoldAllBlocks();
                return true;
            }
            return true;
        }

        // Visual Mode operators (d, x, y, c, s, >, <)
        if ((root.nexus.vimMode === "VISUAL" || root.nexus.vimMode === "VISUAL_LINE") &&
            (keyText === "d" || keyText === "x" || keyText === "y" || keyText === "c" || keyText === "s" || event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace)) {
            root.nexus.vimCountBuffer = "";
            if (area && area.selectedText.length > 0) {
                const selStart = area.selectionStart;
                const selEnd = area.selectionEnd;
                root.nexus.vimRegister = area.selectedText;
                if (keyText === "y") {
                    area.deselect();
                    root.nexus.vimMode = "NORMAL";
                    root.nexus.vimVisualAnchor = -1;
                    root.nexus.vimStatusMessage = "Yanked selection";
                } else {
                    const toInsert = (keyText === "c" || keyText === "s");
                    root.vimDeleteRange(area, selStart, selEnd, toInsert, toInsert ? "Changed selection" : "Deleted selection");
                }
            } else {
                root.nexus.vimMode = "NORMAL";
                root.nexus.vimVisualAnchor = -1;
            }
            return true;
        }

        if (keyText === "g" || keyText === "d" || keyText === "c" || keyText === "y" || keyText === "z" || keyText === "r" ||
            keyText === "f" || keyText === "t" || keyText === "F" || keyText === "T" || keyText === ">" || keyText === "<") {
            root.nexus.vimKeyBuffer = keyText;
            return true;
        }

        // Consume count buffer for single-key commands below
        root.nexus.vimCountBuffer = "";

        if (keyText === ":") {
            root.nexus.vimMode = "COMMAND";
            root.nexus.vimCommandBuffer = "";
            vimCommandInput.forceActiveFocus();
            return true;
        }
        if (keyText === "/") {
            root.nexus.vimMode = "SEARCH";
            root.nexus.vimCommandBuffer = "";
            vimCommandInput.forceActiveFocus();
            return true;
        }
        if (keyText === "i") {
            if (area)
                root.vimPushUndo(area.text);
            root.nexus.vimMode = "INSERT";
            root.nexus.vimVisualAnchor = -1;
            return true;
        }
        if (keyText === "a") {
            if (area) {
                root.vimPushUndo(area.text);
                root.vimMoveCursorRight(area, 1);
            }
            root.nexus.vimMode = "INSERT";
            root.nexus.vimVisualAnchor = -1;
            return true;
        }
        if (keyText === "I") {
            if (area) {
                root.vimPushUndo(area.text);
                const b = root.vimLineBounds(area.text, area.cursorPosition);
                let firstNonWs = b.start;
                while (firstNonWs < b.end && /\s/.test(area.text.charAt(firstNonWs)))
                    firstNonWs += 1;
                area.cursorPosition = firstNonWs;
            }
            root.nexus.vimMode = "INSERT";
            root.nexus.vimVisualAnchor = -1;
            return true;
        }
        if (keyText === "A") {
            if (area) {
                root.vimPushUndo(area.text);
                const b = root.vimLineBounds(area.text, area.cursorPosition);
                area.cursorPosition = b.end;
            }
            root.nexus.vimMode = "INSERT";
            root.nexus.vimVisualAnchor = -1;
            return true;
        }
        if (keyText === "o") {
            if (area) {
                root.vimPushUndo(area.text);
                const b = root.vimLineBounds(area.text, area.cursorPosition);
                area.insert(b.end, "\n");
                area.cursorPosition = b.end + 1;
                root.nexus.draftContent = area.text;
                root.nexus.isDirty = true;
            }
            root.nexus.vimMode = "INSERT";
            root.nexus.vimVisualAnchor = -1;
            return true;
        }
        if (keyText === "O") {
            if (area) {
                root.vimPushUndo(area.text);
                const b = root.vimLineBounds(area.text, area.cursorPosition);
                area.insert(b.start, "\n");
                area.cursorPosition = b.start;
                root.nexus.draftContent = area.text;
                root.nexus.isDirty = true;
            }
            root.nexus.vimMode = "INSERT";
            root.nexus.vimVisualAnchor = -1;
            return true;
        }
        if (keyText === "s") {
            if (area) {
                const endPos = Math.min(area.text.length, area.cursorPosition + countVal);
                root.vimDeleteRange(area, area.cursorPosition, endPos, true, "Substitute (s)");
            }
            return true;
        }
        if (keyText === "S") {
            root.vimChangeCurrentLine(area);
            return true;
        }
        if (keyText === "C") {
            if (area) {
                const b = root.vimLineBounds(area.text, area.cursorPosition);
                root.vimDeleteRange(area, area.cursorPosition, b.end, true, "Change to end of line (C)");
            }
            return true;
        }
        if (keyText === "D") {
            if (area) {
                const b = root.vimLineBounds(area.text, area.cursorPosition);
                root.vimDeleteRange(area, area.cursorPosition, b.end, false, "Deleted to end of line (D)");
            }
            return true;
        }
        if (keyText === "Y") {
            root.vimYankCurrentLine(area, countVal);
            return true;
        }
        if (keyText === "J") {
            root.vimJoinLines(area);
            return true;
        }
        if (keyText === "~") {
            root.vimToggleCaseAtCursor(area);
            return true;
        }
        if (keyText === "v") {
            if (root.nexus.vimMode === "VISUAL") {
                root.nexus.vimMode = "NORMAL";
                root.nexus.vimVisualAnchor = -1;
                if (area)
                    area.deselect();
            } else {
                root.nexus.vimMode = "VISUAL";
                root.nexus.vimVisualAnchor = area ? area.cursorPosition : 0;
                root._vimSyncVisualSelection(area);
            }
            return true;
        }
        if (keyText === "V") {
            if (root.nexus.vimMode === "VISUAL_LINE") {
                root.nexus.vimMode = "NORMAL";
                root.nexus.vimVisualAnchor = -1;
                if (area)
                    area.deselect();
            } else {
                root.nexus.vimMode = "VISUAL_LINE";
                root.nexus.vimVisualAnchor = area ? area.cursorPosition : 0;
                root._vimSyncVisualSelection(area);
            }
            return true;
        }
        if (keyText === "h" || event.key === Qt.Key_Left) {
            root.vimMoveCursorLeft(area, countVal);
            return true;
        }
        if (keyText === "l" || event.key === Qt.Key_Right) {
            root.vimMoveCursorRight(area, countVal);
            return true;
        }
        if (keyText === "j" || event.key === Qt.Key_Down) {
            root.vimMoveCursorVertical(area, countVal);
            return true;
        }
        if (keyText === "k" || event.key === Qt.Key_Up) {
            root.vimMoveCursorVertical(area, -countVal);
            return true;
        }
        if (keyText === "w") {
            root.vimMoveWordForward(area, countVal);
            return true;
        }
        if (keyText === "e") {
            root.vimMoveWordEnd(area, countVal);
            return true;
        }
        if (keyText === "b") {
            root.vimMoveWordBackward(area, countVal);
            return true;
        }
        if (keyText === "0" || keyText === "^") {
            if (area) {
                const b = root.vimLineBounds(area.text, area.cursorPosition);
                if (keyText === "^") {
                    let p = b.start;
                    while (p < b.end && /\s/.test(area.text.charAt(p)))
                        p += 1;
                    area.cursorPosition = p;
                } else {
                    area.cursorPosition = b.start;
                }
                root._vimSyncVisualSelection(area);
            }
            return true;
        }
        if (keyText === "$") {
            if (area) {
                const b = root.vimLineBounds(area.text, area.cursorPosition);
                area.cursorPosition = b.end;
                root._vimSyncVisualSelection(area);
            }
            return true;
        }
        if (keyText === "G") {
            if (area) {
                area.cursorPosition = hasExplicitCount
                    ? root._vimLineStartForLineNumber(area.text, countVal)
                    : area.text.length;
                root._vimSyncVisualSelection(area);
            }
            return true;
        }
        if (keyText === "x" || event.key === Qt.Key_Delete) {
            if (area && area.cursorPosition < area.text.length) {
                const b = root.vimLineBounds(area.text, area.cursorPosition);
                const endPos = Math.min(b.end > area.cursorPosition ? b.end : area.cursorPosition + 1, area.cursorPosition + countVal);
                root.vimDeleteRange(area, area.cursorPosition, endPos, false, "Deleted char (x)");
            }
            return true;
        }
        if (keyText === "X" || event.key === Qt.Key_Backspace) {
            if (area && area.cursorPosition > 0) {
                const b = root.vimLineBounds(area.text, area.cursorPosition);
                const startPos = Math.max(b.start, area.cursorPosition - countVal);
                if (startPos < area.cursorPosition) {
                    root.vimDeleteRange(area, startPos, area.cursorPosition, false, "Deleted char before cursor (X)");
                } else {
                    root.vimMoveCursorLeft(area, 1);
                }
            }
            return true;
        }
        if (keyText === "p") {
            root.vimPasteLine(area, true);
            return true;
        }
        if (keyText === "P") {
            root.vimPasteLine(area, false);
            return true;
        }
        if (keyText === "u") {
            root.vimUndo(area);
            return true;
        }
        if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_R) {
            root.vimRedo(area);
            return true;
        }
        if (keyText === "n" && root.nexus.vimSearchQuery.length > 0 && area) {
            const q = root.nexus.vimSearchQuery.toLowerCase();
            const idx = area.text.toLowerCase().indexOf(q, area.cursorPosition + 1);
            if (idx !== -1) {
                area.cursorPosition = idx;
            } else {
                const wrapIdx = area.text.toLowerCase().indexOf(q, 0);
                if (wrapIdx !== -1)
                    area.cursorPosition = wrapIdx;
            }
            return true;
        }
        if (keyText === "N" && root.nexus.vimSearchQuery.length > 0 && area) {
            const q = root.nexus.vimSearchQuery.toLowerCase();
            const before = area.cursorPosition > 0 ? area.text.toLowerCase().substring(0, area.cursorPosition) : "";
            const idx = before.lastIndexOf(q);
            if (idx !== -1) {
                area.cursorPosition = idx;
            } else {
                const wrapIdx = area.text.toLowerCase().lastIndexOf(q);
                if (wrapIdx !== -1)
                    area.cursorPosition = wrapIdx;
            }
            return true;
        }
        return true;
    }

    RowLayout {
        anchors.fill: parent
        spacing: 4

        // ═══════════════════════════════════════════════════════════════════
        // LEFT COLUMN: Resizable & Rearrangeable Card Slots (Slot 0 + Slot 1)
        // ═══════════════════════════════════════════════════════════════════
        ColumnLayout {
            id: nexusLeftColumn
            objectName: "nexusLeftColumn"
            visible: Boolean(root.nexus?.leftSidebarOpen ?? true)
            readonly property int targetWidth: Math.round(160 + (Math.max(160, Math.min(540, root.nexus?.leftSidebarWidth ?? 268)) - 160) * root.sidebarExpansionScale)
            Layout.fillWidth: false
            Layout.preferredWidth: targetWidth
            Layout.minimumWidth: targetWidth
            Layout.maximumWidth: targetWidth
            Layout.fillHeight: true
            spacing: 4

            Item {
                id: leftSlot0
                objectName: "nexusLeftSlot0"
                readonly property int targetHeight: Math.max(120, Math.round(Math.max(320, nexusLeftColumn.height - 10) * (root.nexus?.leftSplitRatio ?? 0.62)))
                Layout.fillWidth: true
                Layout.preferredHeight: targetHeight
                Layout.minimumHeight: targetHeight
                Layout.maximumHeight: targetHeight

            // Top Left Card: File Tree / Tags / Recent / Search
            Rectangle {
                id: nexusFileTreeCard
                objectName: "nexusFileTreeCard"
                anchors.fill: parent
                radius: Appearance.rounding.normal ?? 12
                color: settledColors.colLayer1
                border.width: (root.dropTargetCardId === "explorer" && root.draggingCardId !== "" && root.draggingCardId !== "explorer") ? 2 : 1
                border.color: (root.dropTargetCardId === "explorer" && root.draggingCardId !== "" && root.draggingCardId !== "explorer")
                    ? settledColors.colPrimary
                    : settledColors.colLayer0Border
                clip: true

                HoverHandler {
                    id: explorerCardHover
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 8

                    // Keep every explorer action reachable at the supported sidebar minima.
                    Flow {
                        objectName: "nexusExplorerToolbar"
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        spacing: 3

                        Repeater {
                            model: [
                                {
                                    "id": "files",
                                    "icon": "folder",
                                    "tip": "Files"
                                },
                                {
                                    "id": "tags",
                                    "icon": "sell",
                                    "tip": "Tags"
                                },
                                {
                                    "id": "recent",
                                    "icon": "schedule",
                                    "tip": "Recent"
                                },
                                {
                                    "id": "search",
                                    "icon": "search",
                                    "tip": "Search"
                                }
                            ]
                            delegate: Rectangle {
                                required property var modelData
                                readonly property bool active: (root.nexus?.leftSidebarTab ?? "files") === modelData.id
                                width: 26
                                height: 26
                                radius: 7
                                color: active ? settledColors.colSecondaryContainer : "transparent"

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: modelData.icon
                                    iconSize: 15
                                    color: parent.active ? settledColors.colOnSecondaryContainer : settledColors.colSubtext
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (root.nexus) {
                                            root.nexus.leftSidebarTab = modelData.id;
                                            if (modelData.id === "search" && fileFilterField.text.trim().length > 0) {
                                                root.nexus.searchVault(fileFilterField.text.trim());
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // New Note button
                        Rectangle {
                            implicitWidth: 24
                            implicitHeight: 24
                            width: 24
                            height: 24
                            radius: 6
                            color: newNoteMouse.containsMouse ? settledColors.colLayer2Hover : "transparent"
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "note_add"
                                iconSize: 15
                                color: settledColors.colOnLayer1
                            }
                            MouseArea {
                                id: newNoteMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: newNoteBar.visible = !newNoteBar.visible
                            }
                        }

                        // Interactive New Note & API Search Modal button
                        Rectangle {
                            objectName: "nexusOpenNewNoteModalButton"
                            implicitWidth: 24
                            implicitHeight: 24
                            width: 24
                            height: 24
                            radius: 6
                            color: newNoteModalMouse.containsMouse ? settledColors.colLayer2Hover : "transparent"
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "travel_explore"
                                iconSize: 15
                                color: settledColors.colPrimary
                            }
                            MouseArea {
                                id: newNoteModalMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (root.nexus)
                                        root.nexus.openNewNoteModal("standard", "");
                                }
                            }
                        }

                        // Today's Journal button
                        Rectangle {
                            implicitWidth: 24
                            implicitHeight: 24
                            width: 24
                            height: 24
                            radius: 6
                            color: dailyMouse.containsMouse ? settledColors.colLayer2Hover : "transparent"
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "today"
                                iconSize: 15
                                color: settledColors.colPrimary
                            }
                            MouseArea {
                                id: dailyMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (root.nexus)
                                        root.nexus.openDailyNote();
                                }
                            }
                        }

                        // Rescan Vault button
                        Rectangle {
                            implicitWidth: 24
                            implicitHeight: 24
                            width: 24
                            height: 24
                            radius: 6
                            color: refreshMouse.containsMouse ? settledColors.colLayer2Hover : "transparent"
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "refresh"
                                iconSize: 15
                                color: settledColors.colSubtext
                            }
                            MouseArea {
                                id: refreshMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (root.nexus) {
                                        root.nexus.refreshVault();
                                        root.nexus.refreshCalendar(root.nexus.calendarYear, root.nexus.calendarMonth);
                                    }
                                }
                            }
                        }

                        CardReorderPill {
                            cardId: "explorer"
                            cardHovered: explorerCardHover.hovered
                        }
                    }

                    // Filter / Search input (flexible width down to 160px sidebar)
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 80
                        Layout.preferredHeight: 32
                        radius: 8
                        color: settledColors.colLayer0
                        border.width: fileFilterField.activeFocus ? 2 : 1
                        border.color: fileFilterField.activeFocus ? settledColors.colPrimary : settledColors.colLayer0Border
                        clip: true

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 6
                            spacing: 5

                            MaterialSymbol {
                                text: "search"
                                iconSize: 15
                                color: fileFilterField.activeFocus ? settledColors.colPrimary : settledColors.colSubtext
                            }

                            TextField {
                                id: fileFilterField
                                objectName: "nexusFileFilterField"
                                Layout.fillWidth: true
                                Layout.minimumWidth: 36
                                topPadding: 0
                                bottomPadding: 0
                                verticalAlignment: TextInput.AlignVCenter
                                clip: true
                                placeholderText: (root.nexus?.leftSidebarTab === "search")
                                    ? (nexusLeftColumn.width < 210 ? "Search..." : "Search inside vault...")
                                    : (nexusLeftColumn.width < 210 ? "Filter..." : "Filter vault files...")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: settledColors.colOnLayer0
                                background: null
                                onTextChanged: {
                                    if (!root.nexus)
                                        return;
                                    if (root.nexus.leftSidebarTab === "search")
                                        root.nexus.searchVault(text);
                                    else
                                        root.nexus.fileFilterQuery = text;
                                }
                                onAccepted: {
                                    if (root.nexus && text.trim().length > 0) {
                                        root.nexus.leftSidebarTab = "search";
                                        root.nexus.searchVault(text);
                                    }
                                }
                                Keys.onEscapePressed: event => {
                                    fileFilterField.focus = false;
                                    root.restoreWorkspaceFocus();
                                    Qt.callLater(root.restoreWorkspaceFocus);
                                    event.accepted = true;
                                }
                                Keys.onPressed: event => {
                                    if ((event.modifiers & (Qt.AltModifier | Qt.ControlModifier | Qt.MetaModifier)) !== 0
                                        && root.nexus && root.nexus.handleKeyEvent(event)) {
                                        event.accepted = true;
                                    }
                                }
                            }

                            Rectangle {
                                visible: fileFilterField.text.length > 0
                                Layout.preferredWidth: 18
                                Layout.preferredHeight: 18
                                radius: 9
                                color: clearSearchMouse.containsMouse ? settledColors.colLayer2Hover : "transparent"
                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "close"
                                    iconSize: 13
                                    color: settledColors.colSubtext
                                }
                                MouseArea {
                                    id: clearSearchMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        fileFilterField.text = "";
                                        if (root.nexus) {
                                            root.nexus.fileFilterQuery = "";
                                            if (root.nexus.leftSidebarTab === "search")
                                                root.nexus.searchVault("");
                                        }
                                        fileFilterField.focus = false;
                                        root.restoreWorkspaceFocus();
                                        Qt.callLater(root.restoreWorkspaceFocus);
                                    }
                                }
                            }
                        }
                    }

                    // Inline New Note creator bar
                    Rectangle {
                        id: newNoteBar
                        objectName: "nexusNewNoteBar"
                        visible: false
                        Layout.fillWidth: true
                        Layout.preferredHeight: 34
                        radius: 8
                        color: settledColors.colLayer2
                        border.width: 1
                        border.color: settledColors.colPrimary

                        onVisibleChanged: {
                            if (visible) {
                                newNotePathField.forceActiveFocus();
                            } else {
                                newNotePathField.focus = false;
                                root.restoreWorkspaceFocus();
                                Qt.callLater(root.restoreWorkspaceFocus);
                            }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 6
                            spacing: 4

                            TextField {
                                id: newNotePathField
                                objectName: "nexusNewNoteField"
                                Layout.fillWidth: true
                                placeholderText: "Folder/NoteTitle.md"
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: settledColors.colOnLayer1
                                background: null
                                onAccepted: {
                                    if (root.nexus && text.trim().length > 0) {
                                        root.nexus.createNote(text.trim(), "", "standard");
                                        text = "";
                                        newNoteBar.visible = false;
                                        newNotePathField.focus = false;
                                        root.restoreWorkspaceFocus();
                                        Qt.callLater(root.restoreWorkspaceFocus);
                                    }
                                }
                                Keys.onEscapePressed: event => {
                                    newNoteBar.visible = false;
                                    newNotePathField.focus = false;
                                    root.restoreWorkspaceFocus();
                                    Qt.callLater(root.restoreWorkspaceFocus);
                                    event.accepted = true;
                                }
                                Keys.onPressed: event => {
                                    if ((event.modifiers & (Qt.AltModifier | Qt.ControlModifier | Qt.MetaModifier)) !== 0
                                        && root.nexus && root.nexus.handleKeyEvent(event)) {
                                        event.accepted = true;
                                    }
                                }
                            }

                            Rectangle {
                                implicitWidth: 24
                                implicitHeight: 24
                                width: 24
                                height: 24
                                radius: 6
                                color: settledColors.colPrimary
                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "check"
                                    iconSize: 14
                                    color: settledColors.colOnPrimary
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (root.nexus && newNotePathField.text.trim().length > 0) {
                                            root.nexus.createNote(newNotePathField.text.trim(), "", "standard");
                                            newNotePathField.text = "";
                                            newNoteBar.visible = false;
                                            newNotePathField.focus = false;
                                            root.restoreWorkspaceFocus();
                                            Qt.callLater(root.restoreWorkspaceFocus);
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Vault Root Header Row
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        MaterialSymbol {
                            text: "expand_more"
                            iconSize: 15
                            color: settledColors.colSubtext
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: root.nexus?.vaultName ?? "Vault"
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.DemiBold
                            color: settledColors.colOnLayer1
                            elide: Text.ElideRight
                        }
                    }

                    // Tab 1: File & Folder Tree (with 01_Core.css + 99_Alis_Theme.css dynamic auto-themed folder colors & icons)
                    ListView {
                        id: treeListView
                        objectName: "nexusFileTreeList"
                        visible: (root.nexus?.leftSidebarTab ?? "files") === "files"
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 2
                        model: root.nexus?.visibleTreeRows ?? []

                        delegate: Rectangle {
                            id: treeRowDelegate
                            required property var modelData
                            readonly property string folderColor: root.autoThemedFolderColor(modelData.prefixCode, modelData.colorHex)
                            readonly property string folderHoverTextColor: root.autoThemedFolderTextColor(modelData.prefixCode, modelData.colorHex)
                            readonly property bool isCurrent: !modelData.isDir && (root.nexus?.currentPath === modelData.relPath) && (root.nexus?.activeView === "document")
                            readonly property color folderTintBase: folderColor.length > 0 ? Qt.color(folderColor) : Qt.color(root._settledPrimary)
                            width: treeListView.width
                            height: modelData.isDir ? 26 : 24
                            radius: 5
                            color: {
                                if (isCurrent) {
                                    return folderColor.length > 0
                                        ? Qt.rgba(folderTintBase.r, folderTintBase.g, folderTintBase.b, 0.18)
                                        : settledColors.colSecondaryContainer;
                                }
                                if (rowMouse.containsMouse) {
                                    if (folderColor.length > 0)
                                        return Qt.rgba(folderTintBase.r, folderTintBase.g, folderTintBase.b, modelData.isDir ? 0.15 : 0.10);
                                    return settledColors.colLayer2Hover;
                                }
                                return "transparent";
                            }
                            border.width: 0

                            // Colored vertical tree branch line for nested items (matching 01_Core.css 1px solid color-mix(var(--av-folder-color) 20%, transparent))
                            Rectangle {
                                visible: (treeRowDelegate.modelData.depth ?? 0) > 0 && treeRowDelegate.folderColor.length > 0
                                x: Math.max(4, 10 + ((treeRowDelegate.modelData.depth ?? 1) - 1) * 14)
                                width: 1
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                color: treeRowDelegate.folderColor
                                opacity: rowMouse.containsMouse ? 0.40 : 0.22
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 6 + (treeRowDelegate.modelData.depth ?? 0) * 14
                                anchors.rightMargin: 6
                                spacing: 6

                                // Chevron for directories (60% folder color opacity, 90% on hover)
                                MaterialSymbol {
                                    visible: Boolean(treeRowDelegate.modelData.isDir)
                                    text: treeRowDelegate.modelData.expanded ? "expand_more" : "chevron_right"
                                    iconSize: 15
                                    color: treeRowDelegate.folderColor.length > 0
                                        ? Qt.rgba(treeRowDelegate.folderTintBase.r, treeRowDelegate.folderTintBase.g, treeRowDelegate.folderTintBase.b, rowMouse.containsMouse ? 0.90 : 0.60)
                                        : settledColors.colSubtext
                                }

                                // Custom folder icon (from .obsidian/plugins/obsidian-icon-folder/data.json) or file icon
                                MaterialSymbol {
                                    text: {
                                        if (treeRowDelegate.modelData.isDir)
                                            return String(treeRowDelegate.modelData.iconName || "folder");
                                        if (treeRowDelegate.modelData.category === "image")
                                            return "image";
                                        if (treeRowDelegate.modelData.category === "code")
                                            return "code";
                                        if (treeRowDelegate.modelData.category === "external")
                                            return "open_in_new";
                                        return "description";
                                    }
                                    iconSize: 15
                                    color: {
                                        if (treeRowDelegate.modelData.isDir) {
                                            if (treeRowDelegate.folderColor.length > 0)
                                                return rowMouse.containsMouse ? treeRowDelegate.folderHoverTextColor : treeRowDelegate.folderColor;
                                            return settledColors.colOnLayer1;
                                        }
                                        if (treeRowDelegate.isCurrent)
                                            return settledColors.colPrimary;
                                        if (treeRowDelegate.folderColor.length > 0)
                                            return root.mixColorHex(treeRowDelegate.folderColor, settledColors.colSubtext ?? "#8f9d9f", 0.35);
                                        if (treeRowDelegate.modelData.category === "external")
                                            return settledColors.colTertiary ?? settledColors.colSubtext;
                                        return settledColors.colSubtext;
                                    }
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: String(treeRowDelegate.modelData.name ?? "").replace(/\.md$/i, "")
                                    font.pixelSize: Appearance.font.pixelSize.smaller + 1
                                    font.weight: (treeRowDelegate.modelData.isDir || treeRowDelegate.isCurrent) ? Font.DemiBold : Font.Normal
                                    color: {
                                        if (treeRowDelegate.modelData.isDir) {
                                            if (treeRowDelegate.folderColor.length > 0)
                                                return rowMouse.containsMouse ? treeRowDelegate.folderHoverTextColor : treeRowDelegate.folderColor;
                                            return settledColors.colOnLayer1;
                                        }
                                        if (treeRowDelegate.isCurrent)
                                            return settledColors.colPrimary;
                                        if (treeRowDelegate.folderColor.length > 0) {
                                            return root.mixColorHex(
                                                treeRowDelegate.folderColor,
                                                settledColors.colOnLayer1 ?? "#d9e1e3",
                                                rowMouse.containsMouse ? 0.45 : 0.22
                                            );
                                        }
                                        return settledColors.colOnLayer1;
                                    }
                                    elide: Text.ElideRight
                                }
                            }

                            MouseArea {
                                id: rowMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                cursorShape: Qt.PointingHandCursor
                                onClicked: mouse => {
                                    if (!root.nexus)
                                        return;
                                    if (mouse.button === Qt.RightButton) {
                                        const pt = mapToItem(root, mouse.x, mouse.y);
                                        root.openContextMenu(pt.x, pt.y, {
                                            "type": treeRowDelegate.modelData.isDir ? "folder" : "file",
                                            "title": treeRowDelegate.modelData.name,
                                            "relPath": treeRowDelegate.modelData.relPath,
                                            "isDir": Boolean(treeRowDelegate.modelData.isDir)
                                        });
                                        return;
                                    }
                                    if (treeRowDelegate.modelData.isDir)
                                        root.nexus.toggleFolderExpanded(treeRowDelegate.modelData.relPath);
                                    else
                                        root.nexus.openFile(treeRowDelegate.modelData.relPath, true);
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            z: -1
                            acceptedButtons: Qt.RightButton
                            onClicked: mouse => {
                                const pt = mapToItem(root, mouse.x, mouse.y);
                                root.openContextMenu(pt.x, pt.y, {
                                    "type": "workspace",
                                    "title": "Vault Explorer"
                                });
                            }
                        }
                    }

                    // Tab 2: Tags Explorer (with subtag hierarchy & collapsible dropdown)
                    ListView {
                        visible: (root.nexus?.leftSidebarTab ?? "files") === "tags"
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 2
                        model: root.nexus?.hierarchicalTagsList ?? []

                        delegate: Rectangle {
                            id: tagRowDelegate
                            required property var modelData
                            width: ListView.view.width
                            height: 30
                            radius: 6
                            color: tagMouse.containsMouse ? settledColors.colLayer2Hover : "transparent"

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 6 + (tagRowDelegate.modelData.depth ?? 0) * 16
                                anchors.rightMargin: 8
                                z: 1
                                spacing: 4

                                // Chevron dropdown toggle for parent tags with subtags
                                Rectangle {
                                    visible: Boolean(tagRowDelegate.modelData.hasChildren)
                                    Layout.preferredWidth: 20
                                    Layout.preferredHeight: 20
                                    radius: 4
                                    color: chevronMouse.containsMouse ? settledColors.colLayer2 : "transparent"

                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: tagRowDelegate.modelData.expanded ? "expand_more" : "chevron_right"
                                        iconSize: 15
                                        color: settledColors.colSubtext
                                    }
                                    MouseArea {
                                        id: chevronMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (root.nexus)
                                                root.nexus.toggleTagGroupExpanded(tagRowDelegate.modelData.name);
                                        }
                                    }
                                }

                                // Indent spacer if tag has no children but is at depth 0
                                Item {
                                    visible: !Boolean(tagRowDelegate.modelData.hasChildren) && (tagRowDelegate.modelData.depth ?? 0) === 0
                                    Layout.preferredWidth: 6
                                }

                                MaterialSymbol {
                                    visible: Boolean(tagRowDelegate.modelData.isSubtag)
                                    text: "subdirectory_arrow_right"
                                    iconSize: 13
                                    color: settledColors.colSubtext
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: tagRowDelegate.modelData.isSubtag
                                        ? ("/" + String(tagRowDelegate.modelData.subtagLabel ?? ""))
                                        : ("#" + String(tagRowDelegate.modelData.name ?? ""))
                                    font.pixelSize: Appearance.font.pixelSize.smaller + 1
                                    font.weight: tagRowDelegate.modelData.hasChildren ? Font.DemiBold : Font.Normal
                                    color: tagRowDelegate.modelData.isSubtag
                                        ? (settledColors.colTertiary ?? settledColors.colPrimary)
                                        : settledColors.colPrimary
                                    elide: Text.ElideRight
                                }

                                Rectangle {
                                    Layout.preferredWidth: Math.max(26, tagCountTxt.implicitWidth + 10)
                                    Layout.preferredHeight: 18
                                    radius: 9
                                    color: settledColors.colLayer2
                                    StyledText {
                                        id: tagCountTxt
                                        anchors.centerIn: parent
                                        text: String(tagRowDelegate.modelData.count ?? 0)
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: settledColors.colSubtext
                                    }
                                }
                            }
                            MouseArea {
                                id: tagMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                cursorShape: Qt.PointingHandCursor
                                onClicked: mouse => {
                                    if (!root.nexus)
                                        return;
                                    if (mouse.button === Qt.RightButton) {
                                        const pt = mapToItem(root, mouse.x, mouse.y);
                                        root.openContextMenu(pt.x, pt.y, {
                                            "type": "tag",
                                            "title": tagRowDelegate.modelData.fullTag || ("#" + tagRowDelegate.modelData.name),
                                            "tag": tagRowDelegate.modelData.name,
                                            "fullTag": tagRowDelegate.modelData.fullTag || ("#" + tagRowDelegate.modelData.name)
                                        });
                                        return;
                                    }
                                    root.nexus.leftSidebarTab = "search";
                                    const searchStr = tagRowDelegate.modelData.fullTag || ("#" + tagRowDelegate.modelData.name);
                                    fileFilterField.text = searchStr;
                                    root.nexus.searchVault(searchStr);
                                }
                            }
                        }
                    }

                    // Tab 3: Recent Notes
                    ListView {
                        visible: (root.nexus?.leftSidebarTab ?? "files") === "recent"
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 4
                        model: root.nexus?.recentNotes ?? []

                        delegate: Rectangle {
                            id: recentItemDelegate
                            required property var modelData
                            width: ListView.view.width
                            implicitHeight: Math.max(48, recentCol.implicitHeight + 14)
                            height: implicitHeight
                            radius: 7
                            color: recentMouse.containsMouse ? settledColors.colLayer2Hover : settledColors.colLayer0

                            ColumnLayout {
                                id: recentCol
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                spacing: 2

                                StyledText {
                                    Layout.fillWidth: true
                                    text: String(modelData.title ?? "")
                                    font.pixelSize: Appearance.font.pixelSize.smaller + 1
                                    font.weight: Font.DemiBold
                                    color: settledColors.colOnLayer1
                                    elide: Text.ElideRight
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: String(modelData.folder || "/")
                                    font.pixelSize: Appearance.font.pixelSize.smallest + 1
                                    color: settledColors.colSubtext
                                    elide: Text.ElideRight
                                }
                            }
                            MouseArea {
                                id: recentMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                cursorShape: Qt.PointingHandCursor
                                onClicked: mouse => {
                                    if (!root.nexus)
                                        return;
                                    if (mouse.button === Qt.RightButton) {
                                        const pt = mapToItem(root, mouse.x, mouse.y);
                                        root.openContextMenu(pt.x, pt.y, {
                                            "type": "file",
                                            "title": modelData.title || modelData.name || modelData.relPath,
                                            "relPath": modelData.relPath,
                                            "isDir": false
                                        });
                                        return;
                                    }
                                    root.nexus.openFile(modelData.relPath, true);
                                }
                            }
                        }
                    }

                    // Tab 4: Vault Full-Text Search Results
                    ListView {
                        visible: (root.nexus?.leftSidebarTab ?? "files") === "search"
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 4
                        model: root.nexus?.searchResults ?? []

                        delegate: Rectangle {
                            id: searchHitDelegate
                            required property var modelData
                            width: ListView.view.width
                            implicitHeight: Math.max(54, searchHitCol.implicitHeight + 14)
                            height: implicitHeight
                            radius: 7
                            color: searchHitMouse.containsMouse ? settledColors.colLayer2Hover : settledColors.colLayer0

                            ColumnLayout {
                                id: searchHitCol
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                spacing: 2

                                RowLayout {
                                    Layout.fillWidth: true
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: String(modelData.title ?? "")
                                        font.pixelSize: Appearance.font.pixelSize.smaller + 1
                                        font.weight: Font.DemiBold
                                        color: settledColors.colPrimary
                                        elide: Text.ElideRight
                                    }
                                    StyledText {
                                        text: "L" + String(modelData.line ?? 1)
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: settledColors.colSubtext
                                    }
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: String(modelData.snippet ?? "")
                                    font.pixelSize: Appearance.font.pixelSize.smallest + 1
                                    color: settledColors.colSubtext
                                    elide: Text.ElideRight
                                }
                            }
                            MouseArea {
                                id: searchHitMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                cursorShape: Qt.PointingHandCursor
                                onClicked: mouse => {
                                    if (!root.nexus)
                                        return;
                                    if (mouse.button === Qt.RightButton) {
                                        const pt = mapToItem(root, mouse.x, mouse.y);
                                        root.openContextMenu(pt.x, pt.y, {
                                            "type": "file",
                                            "title": modelData.title || modelData.name || modelData.relPath,
                                            "relPath": modelData.relPath,
                                            "isDir": false
                                        });
                                        return;
                                    }
                                    root.nexus.openFile(modelData.relPath, true);
                                }
                            }
                        }
                    }
                }
            }
            }

            // Vertical Splitter between Left Slot 0 and Left Slot 1 (hover-only)
            Rectangle {
                id: nexusLeftCardSplitter
                objectName: "nexusLeftCardSplitter"
                z: 40
                Layout.fillWidth: true
                Layout.preferredHeight: 6
                radius: 3
                readonly property bool active: leftSplitMouse.pressed || leftSplitMouse.containsMouse
                opacity: active ? 1.0 : 0.0
                Behavior on opacity { NumberAnimation { duration: 150 } }
                color: active ? settledColors.colPrimary : "transparent"

                Rectangle {
                    anchors.centerIn: parent
                    width: 36
                    height: 2
                    radius: 1
                    color: nexusLeftCardSplitter.active
                        ? settledColors.colOnPrimary
                        : settledColors.colLayer0Border
                }

                MouseArea {
                    id: leftSplitMouse
                    anchors.fill: parent
                    anchors.topMargin: -5
                    anchors.bottomMargin: -5
                    hoverEnabled: true
                    preventStealing: true
                    cursorShape: Qt.SplitVCursor
                    onPositionChanged: mouse => {
                        if (!pressed || !root.nexus)
                            return;
                        const pt = mapToItem(nexusLeftColumn, 0, mouse.y);
                        const totalH = Math.max(260, nexusLeftColumn.height);
                        root.nexus.setLeftSplitRatio(pt.y / totalH);
                    }
                }
            }

            Item {
                id: leftSlot1
                objectName: "nexusLeftSlot1"
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 110

            // Bottom Left Card: Local Graph (full-bleed with floating hover header)
            Rectangle {
                id: nexusLocalGraphCard
                objectName: "nexusLocalGraphCard"
                anchors.fill: parent
                radius: Appearance.rounding.normal ?? 12
                color: settledColors.colLayer1
                border.width: (root.dropTargetCardId === "localGraph" && root.draggingCardId !== "" && root.draggingCardId !== "localGraph") ? 2 : 1
                border.color: (root.dropTargetCardId === "localGraph" && root.draggingCardId !== "" && root.draggingCardId !== "localGraph")
                    ? settledColors.colPrimary
                    : settledColors.colLayer0Border
                clip: true

                HoverHandler {
                    id: localGraphCardHover
                }

                property bool _graphSettledOnce: false
                Component.onCompleted: {
                    if (root.transitionSettled)
                        _graphSettledOnce = true;
                }
                Connections {
                    target: root
                    function onTransitionSettledChanged() {
                        if (root.transitionSettled && !nexusLocalGraphCard._graphSettledOnce)
                            nexusLocalGraphCard._graphSettledOnce = true;
                    }
                }

                readonly property var activeLocalGraph: {
                    if (!root.transitionSettled && !nexusLocalGraphCard._graphSettledOnce && Boolean(root.nexus?.isOpen))
                        return { "nodes": [], "edges": [] };
                    if (root.nexus?.activeView === "document" && root.nexus?.currentDoc?.localGraph?.nodes?.length > 0) {
                        return root.nexus.currentDoc.localGraph;
                    }
                    return root.nexus?.homepageLocalGraph ?? {
                        "nodes": [],
                        "edges": []
                    };
                }

                onActiveLocalGraphChanged: {
                    if ((activeLocalGraph?.nodes?.length ?? 0) > 0 && !nexusLocalGraphCard._graphSettledOnce)
                        nexusLocalGraphCard._graphSettledOnce = true;
                    localGraphCanvas.requestPaint();
                }

                NexusGraphCanvas {
                    id: localGraphCanvas
                    objectName: "nexusLocalGraphCanvas"
                    anchors.fill: parent
                    anchors.margins: 4
                    workspace: root
                    isLocal: true
                    compact: true
                    revealStaggerMs: 12
                    graphData: nexusLocalGraphCard.activeLocalGraph
                    currentPath: String(root.nexus?.currentPath ?? "")
                    clusterPalette: root.clusterPalette
                    onNodeActivated: nodeData => {
                        if (!root.nexus || !nodeData)
                            return;
                        if (nodeData.id === "__homepage__")
                            root.nexus.openHomepage();
                        else if (nodeData.relPath)
                            root.nexus.openFile(nodeData.relPath, true);
                    }
                }

                Rectangle {
                    objectName: "nexusLocalGraphStatusBar"
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 6
                    height: 26
                    radius: 6
                    color: Qt.rgba(settledColors.colLayer0.r, settledColors.colLayer0.g, settledColors.colLayer0.b, 0.88)
                    border.width: 1
                    border.color: settledColors.colLayer0Border
                    opacity: localGraphCardHover.hovered ? 1.0 : 0.0
                    Behavior on opacity { NumberAnimation { duration: 150 } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 6
                        anchors.rightMargin: 4
                        spacing: 6

                        MaterialSymbol {
                            text: "hub"
                            iconSize: 14
                            color: settledColors.colPrimary
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: "Local Graph"
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.weight: Font.DemiBold
                            color: settledColors.colOnLayer1
                        }
                        StyledText {
                            text: String((nexusLocalGraphCard.activeLocalGraph?.nodes ?? []).length) + " nodes"
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: settledColors.colSubtext
                        }
                        CardReorderPill {
                            cardId: "localGraph"
                            cardHovered: localGraphCardHover.hovered
                        }
                    }
                }
            }
            }
        }

        // Horizontal Splitter between Left Sidebar and Main Center Card (hover-only)
        Rectangle {
            id: nexusLeftSidebarSplitter
            objectName: "nexusLeftSidebarSplitter"
            visible: Boolean(root.nexus?.leftSidebarOpen ?? true)
            Layout.preferredWidth: 6
            Layout.minimumWidth: 6
            Layout.maximumWidth: 6
            Layout.fillHeight: true
            radius: 3
            readonly property bool active: leftSidebarResizeMouse.pressed || leftSidebarResizeMouse.containsMouse || nexusLeftSidebarResizeHandle.pressed || nexusLeftSidebarResizeHandle.containsMouse
            opacity: active ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 150 } }
            color: active ? settledColors.colPrimary : "transparent"

            Rectangle {
                anchors.centerIn: parent
                width: 2
                height: 44
                radius: 1
                color: nexusLeftSidebarSplitter.active
                    ? settledColors.colOnPrimary
                    : settledColors.colLayer0Border
            }

            MouseArea {
                id: leftSidebarResizeMouse
                anchors.fill: parent
                hoverEnabled: true
                preventStealing: true
                cursorShape: Qt.SplitHCursor
                property real pressRootX: 0
                property int pressSidebarWidth: 268
                onPressed: mouse => {
                    const pt = mapToItem(root, mouse.x, 0);
                    pressRootX = pt.x;
                    pressSidebarWidth = root.nexus ? root.nexus.leftSidebarWidth : nexusLeftColumn.width;
                }
                onPositionChanged: mouse => {
                    if (!pressed || !root.nexus)
                        return;
                    const pt = mapToItem(root, mouse.x, 0);
                    root.nexus.setLeftSidebarWidth(Math.round(pressSidebarWidth + (pt.x - pressRootX)));
                }
            }
        }

        // ═══════════════════════════════════════════════════════════════════
        // CENTER COLUMN: Main Card (Homepage / Hybrid Outliner / Vim / Graph)
        // ═══════════════════════════════════════════════════════════════════
        Rectangle {
            id: nexusMainCard
            objectName: "nexusMainCard"
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Appearance.rounding.normal ?? 12
            color: settledColors.colLayer1
            border.width: 1
            border.color: root.borderSubtle
            clip: true

            Rectangle {
                id: nexusMainCardBorderRing
                objectName: "nexusMainCardBorderRing"
                z: 60
                anchors.fill: parent
                radius: nexusMainCard.radius
                color: "transparent"
                border.width: 1
                border.color: root.borderSubtle
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 1
                spacing: 0

                // ── Top Header Bar (no sidebar toggle buttons per user spec) ──
                Rectangle {
                    id: nexusMainHeaderBar
                    objectName: "nexusMainHeaderBar"
                    Layout.fillWidth: true
                    Layout.preferredHeight: nexusHeaderControls.implicitHeight + 18
                    color: "transparent"
                    border.width: 0

                    Rectangle {
                        objectName: "nexusMainHeaderBottomDivider"
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: 1
                        color: root.borderSubtle
                    }

                    GridLayout {
                        id: nexusHeaderControls
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        anchors.topMargin: 9
                        anchors.bottomMargin: 9
                        columns: width >= 560 ? 6 : 3
                        columnSpacing: 6
                        rowSpacing: 6

                        // Homepage pill button
                        Rectangle {
                            Layout.preferredHeight: 28
                            Layout.preferredWidth: homeBtnRow.implicitWidth + 14
                            radius: 7
                            color: (root.nexus?.activeView === "homepage") ? settledColors.colSecondaryContainer : (homeMouse.containsMouse ? settledColors.colLayer2Hover : "transparent")

                            RowLayout {
                                id: homeBtnRow
                                anchors.centerIn: parent
                                spacing: 5
                                MaterialSymbol {
                                    text: "home"
                                    iconSize: 15
                                    color: (root.nexus?.activeView === "homepage") ? settledColors.colPrimary : settledColors.colSubtext
                                }
                                StyledText {
                                    text: "Homepage"
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.weight: Font.DemiBold
                                    color: (root.nexus?.activeView === "homepage") ? settledColors.colOnSecondaryContainer : settledColors.colOnLayer1
                                }
                            }
                            MouseArea {
                                id: homeMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (root.nexus)
                                        root.nexus.openHomepage();
                                }
                            }
                        }

                        // Active Document Breadcrumb / Tab
                        Item {
                            objectName: "nexusActiveTabBreadcrumb"
                            visible: (root.nexus?.activeView === "document") && Boolean(root.nexus?.currentDoc)
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            Layout.preferredHeight: 28

                            StyledText {
                                anchors.fill: parent
                                verticalAlignment: Text.AlignVCenter
                                text: "›  " + String(root.nexus?.currentDoc?.relPath ?? "")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: breadcrumbTabMouse.containsMouse ? settledColors.colOnLayer1 : settledColors.colSubtext
                                elide: Text.ElideMiddle
                            }

                            MouseArea {
                                id: breadcrumbTabMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.RightButton
                                cursorShape: Qt.PointingHandCursor
                                onClicked: mouse => {
                                    if (mouse.button === Qt.RightButton && root.nexus?.currentDoc) {
                                        const pt = mapToItem(root, mouse.x, mouse.y);
                                        root.openContextMenu(pt.x, pt.y, {
                                            "type": "file",
                                            "title": root.nexus.currentDoc.title || root.nexus.currentDoc.relPath,
                                            "relPath": root.nexus.currentDoc.relPath,
                                            "noteKind": root.nexus.currentDoc.noteKind || "",
                                            "isDir": false
                                        });
                                    }
                                }
                            }
                        }

                        Item {
                            visible: (root.nexus?.activeView !== "document")
                            Layout.fillWidth: true
                        }

                        // Unified Reading / Vim Editor Mode Pill + Split Toggle (when in document view)
                        RowLayout {
                            Layout.fillWidth: false
                            spacing: 4

                            Rectangle {
                                id: vimBadge
                                objectName: "nexusVimModeBadge"
                                readonly property bool inEditMode: (root.nexus?.activeView === "document") && ((root.nexus?.editorMode ?? "hybrid") === "raw" || (root.nexus?.editorMode ?? "hybrid") === "split")
                                readonly property bool vimOn: Boolean(root.nexus?.vimEnabled ?? true)
                                readonly property string vimState: String(root.nexus?.vimMode ?? "NORMAL")
                                Layout.preferredHeight: 28
                                Layout.preferredWidth: vimBadgeRow.implicitWidth + 14
                                radius: 7
                                border.width: inEditMode ? 0 : 1
                                border.color: settledColors.colLayer0Border
                                color: {
                                    if (!inEditMode)
                                        return vimBadgeMouse.containsMouse ? settledColors.colSecondaryContainer : settledColors.colLayer2;
                                    if (!vimOn)
                                        return settledColors.colSecondaryContainer;
                                    if (vimState === "INSERT")
                                        return "#9ece6a";
                                    if (vimState === "VISUAL")
                                        return "#bb9af7";
                                    if (vimState === "COMMAND" || vimState === "SEARCH")
                                        return "#e0af68";
                                    return "#7dcfff";
                                }

                                RowLayout {
                                    id: vimBadgeRow
                                    anchors.centerIn: parent
                                    spacing: 5
                                    MaterialSymbol {
                                        text: vimBadge.inEditMode ? "terminal" : "menu_book"
                                        iconSize: 14
                                        color: (vimBadge.inEditMode && vimBadge.vimOn) ? "#1a1b26" : settledColors.colPrimary
                                    }
                                    StyledText {
                                        id: vimBadgeText
                                        text: {
                                            if (!vimBadge.inEditMode)
                                                return "Reading";
                                            if (!vimBadge.vimOn)
                                                return "Editing";
                                            return "Vim · " + vimBadge.vimState;
                                        }
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        font.weight: vimBadge.inEditMode ? Font.Bold : Font.DemiBold
                                        color: (vimBadge.inEditMode && vimBadge.vimOn) ? "#1a1b26" : settledColors.colOnLayer1
                                    }
                                }

                                MouseArea {
                                    id: vimBadgeMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: mouse => {
                                        if (!root.nexus)
                                            return;
                                        if (mouse.button === Qt.RightButton) {
                                            root.nexus.setVimEnabled(!root.nexus.vimEnabled);
                                            return;
                                        }
                                        if (vimBadge.inEditMode) {
                                            root.nexus.setEditorMode("hybrid");
                                        } else {
                                            root.nexus.setEditorMode("raw");
                                            if (root.nexus.activeView !== "document") {
                                                if (root.nexus.currentPath.length > 0)
                                                    root.nexus.activeView = "document";
                                                else if (root.nexus.recentNotes.length > 0)
                                                    root.nexus.openFile(root.nexus.recentNotes[0].relPath, true);
                                            }
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                id: splitModeHeaderBtn
                                objectName: "nexusSplitModeButton"
                                visible: (root.nexus?.activeView ?? "homepage") === "document"
                                readonly property bool selected: (root.nexus?.activeView === "document") && (root.nexus?.editorMode === "split")
                                Layout.preferredHeight: 28
                                Layout.preferredWidth: splitModeRow.implicitWidth + 12
                                radius: 7
                                border.width: selected ? 0 : 1
                                border.color: settledColors.colLayer0Border
                                color: selected ? settledColors.colSecondaryContainer : (splitModeMouse.containsMouse ? settledColors.colLayer2Hover : settledColors.colLayer2)

                                RowLayout {
                                    id: splitModeRow
                                    anchors.centerIn: parent
                                    spacing: 4
                                    MaterialSymbol {
                                        text: "vertical_split"
                                        iconSize: 14
                                        color: splitModeHeaderBtn.selected ? settledColors.colPrimary : settledColors.colSubtext
                                    }
                                    StyledText {
                                        text: "Split"
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        font.weight: splitModeHeaderBtn.selected ? Font.DemiBold : Font.Normal
                                        color: splitModeHeaderBtn.selected ? settledColors.colOnSecondaryContainer : settledColors.colSubtext
                                    }
                                }
                                MouseArea {
                                    id: splitModeMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (!root.nexus)
                                            return;
                                        root.nexus.setEditorMode(splitModeHeaderBtn.selected ? "hybrid" : "split");
                                    }
                                }
                            }
                        }

                        // Window / Overlay Mode Switch Button
                        Rectangle {
                            id: windowModeToggleBtn
                            objectName: "nexusWindowModeToggleButton"
                            Layout.preferredHeight: 28
                            Layout.preferredWidth: winModeRow.implicitWidth + 14
                            radius: 7
                            color: winModeMouse.containsMouse ? settledColors.colSecondaryContainer : settledColors.colLayer2
                            border.width: 1
                            border.color: settledColors.colLayer0Border

                            RowLayout {
                                id: winModeRow
                                anchors.centerIn: parent
                                spacing: 4
                                MaterialSymbol {
                                    text: (root.nexus?.overlayMode ?? true) ? "open_in_new" : "layers"
                                    iconSize: 15
                                    color: settledColors.colPrimary
                                }
                                StyledText {
                                    text: (root.nexus?.overlayMode ?? true) ? "Window" : "Overlay"
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    font.weight: Font.DemiBold
                                    color: settledColors.colOnLayer1
                                }
                            }
                            MouseArea {
                                id: winModeMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (root.nexus)
                                        root.nexus.toggleOverlayMode();
                                }
                            }
                        }

                        // Save Note Button
                        Rectangle {
                            visible: (root.nexus?.activeView === "document") && (root.nexus?.currentDoc?.category === "markdown" || root.nexus?.currentDoc?.category === "code")
                            Layout.preferredHeight: 28
                            Layout.preferredWidth: saveBtnRow.implicitWidth + 12
                            radius: 7
                            color: (root.nexus?.isDirty ?? false) ? settledColors.colPrimary : settledColors.colLayer2

                            RowLayout {
                                id: saveBtnRow
                                anchors.centerIn: parent
                                spacing: 4
                                MaterialSymbol {
                                    text: "save"
                                    iconSize: 14
                                    color: (root.nexus?.isDirty ?? false) ? settledColors.colOnPrimary : settledColors.colOnLayer1
                                }
                                StyledText {
                                    text: (root.nexus?.isDirty ?? false) ? "Save*" : "Saved"
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: (root.nexus?.isDirty ?? false) ? settledColors.colOnPrimary : settledColors.colSubtext
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (root.nexus)
                                        root.nexus.saveCurrentNote();
                                }
                            }
                        }
                    }
                }

                // ── Main Body Content Area ──
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    // ───────────────────────────────────────────────────────
                    // VIEW 1: HOMEPAGE DASHBOARD (matching reference image)
                    // ───────────────────────────────────────────────────────
                    Flickable {
                        id: homepageFlickable
                        objectName: "nexusHomepageView"
                        anchors.fill: parent
                        anchors.margins: 22
                        visible: (root.nexus?.activeView ?? "homepage") === "homepage"
                        contentWidth: width
                        contentHeight: homepageCol.implicitHeight + 24
                        clip: true

                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.RightButton
                            z: -1
                            onClicked: mouse => {
                                const pt = mapToItem(root, mouse.x, mouse.y);
                                root.openContextMenu(pt.x, pt.y, {
                                    "type": "workspace",
                                    "title": "Homepage Actions"
                                });
                            }
                        }

                        ColumnLayout {
                            id: homepageCol
                            width: homepageFlickable.width
                            spacing: 18

                            // Large "Homepage" Title
                            StyledText {
                                text: "Homepage"
                                font.pixelSize: 28
                                font.weight: Font.Bold
                                color: settledColors.colOnLayer1
                            }

                            // Hero Dashboard Card: 3-Column `hd-ff` (18-Node Constellation SVG | Vault Fastfetch Info & Palette | 17-Week Activity Heatmap)
                            Rectangle {
                                id: homepageHeroCard
                                objectName: "nexusHomepageHeroCard"
                                Layout.fillWidth: true
                                Layout.preferredHeight: root.nexus?.homepageHeroHeight ?? 272
                                radius: 12
                                color: settledColors.colLayer0
                                border.width: 1
                                border.color: settledColors.colLayer0Border

                                readonly property string weatherLineText: {
                                    const w = HostServices.Weather?.data;
                                    if (w && (w.temp || w.temperature || w.condition || w.description)) {
                                        const t = String(w.temp ?? w.temperature ?? "27°C");
                                        const cond = String(w.condition ?? w.description ?? "Light rain");
                                        const hum = w.humidity ? (", " + String(w.humidity).replace(/%+$/, "") + "% humid") : ", 94% humid";
                                        return t + ", " + cond + hum;
                                    }
                                    return "27°C, Light rain, 94% humid";
                                }

                                readonly property string greetText: {
                                    const _tick = root.liveDateTimeStr;
                                    const h = (new Date()).getHours();
                                    const userPart = String(root.nexus?.stats?.userHost ?? "llocphann@vault").split("@")[0] || "llocphann";
                                    const g = h < 12 ? "good morning" : (h < 18 ? "good afternoon" : "good evening");
                                    return g + ", " + userPart;
                                }

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 16
                                    spacing: 12

                                    RowLayout {
                                        id: homepageHeroRow
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        spacing: homepageHeroCard.width < 820 ? 16 : 24

                                        // Column 1: Borderless 18-Node Constellation Emblem from `90_System/92_Scripts/Dataview/homepage/info-headers.js`
                                        Item {
                                            id: emblemColItem
                                            Layout.fillWidth: false
                                            Layout.preferredWidth: homepageHeroCard.width < 820 ? 132 : 156
                                            Layout.minimumWidth: 124
                                            Layout.maximumWidth: 164
                                            Layout.preferredHeight: homepageHeroCard.width < 820 ? 136 : 156
                                            Layout.alignment: Qt.AlignVCenter

                                            Canvas {
                                                id: emblemCanvas
                                                anchors.fill: parent
                                                readonly property color accentCol: Qt.color(root._settledPrimary)
                                                readonly property string _themeSig: root.themeSignature
                                                onAccentColChanged: {
                                                    if (visible && root.surfaceActive)
                                                        requestPaint();
                                                }
                                                on_ThemeSigChanged: {
                                                    if (visible && root.surfaceActive)
                                                        requestPaint();
                                                }
                                                onVisibleChanged: {
                                                    if (visible)
                                                        requestPaint();
                                                }
                                                onWidthChanged: requestPaint()
                                                onHeightChanged: requestPaint()
                                                onPaint: {
                                                    const ctx = getContext("2d");
                                                    ctx.clearRect(0, 0, width, height);
                                                    const side = Math.min(width, height);
                                                    const ox = (width - side) * 0.5;
                                                    const oy = (height - side) * 0.5;
                                                    const s = side / 100.0;
                                                    const acc = emblemCanvas.accentCol;
                                                    // Exact 18-node constellation & 21 edges from `info-headers.js`
                                                    const nodes = [
                                                        [50,50,5.5],
                                                        [30,30,4],[68,28,4.5],[26,68,4],[72,70,4],
                                                        [48,20,3],[18,48,3],[82,48,3],[50,80,3],
                                                        [12,22,2],[36,8,2],[88,14,2],[94,36,2],
                                                        [6,62,2],[16,84,2],[40,92,2],[86,86,2],[94,60,2]
                                                    ];
                                                    const edges = [
                                                        [0,1],[0,2],[0,3],[0,4],
                                                        [1,5],[5,2],[1,6],[6,3],[2,7],[7,4],[3,8],[8,4],
                                                        [1,9],[5,10],[2,11],[7,12],[3,13],[3,14],[8,15],[4,16],[7,17]
                                                    ];

                                                    const hx = ox + nodes[0][0] * s;
                                                    const hy = oy + nodes[0][1] * s;
                                                    const grad = ctx.createRadialGradient(hx, hy, 2, hx, hy, side * 0.46);
                                                    grad.addColorStop(0.0, Qt.rgba(acc.r, acc.g, acc.b, 0.22));
                                                    grad.addColorStop(0.55, Qt.rgba(acc.r, acc.g, acc.b, 0.06));
                                                    grad.addColorStop(1.0, Qt.rgba(acc.r, acc.g, acc.b, 0.0));
                                                    ctx.fillStyle = grad;
                                                    ctx.beginPath();
                                                    ctx.arc(hx, hy, side * 0.46, 0, Math.PI * 2);
                                                    ctx.fill();

                                                    // Constellation edges
                                                    for (let i = 0; i < edges.length; ++i) {
                                                        const e = edges[i];
                                                        const n1 = nodes[e[0]];
                                                        const n2 = nodes[e[1]];
                                                        const isCore = (e[0] === 0 || e[1] === 0);
                                                        const isMid = (!isCore && e[0] <= 8 && e[1] <= 8);
                                                        ctx.strokeStyle = Qt.rgba(acc.r, acc.g, acc.b, isCore ? 0.46 : (isMid ? 0.30 : 0.18));
                                                        ctx.lineWidth = isCore ? 1.25 : 0.9;
                                                        ctx.beginPath();
                                                        ctx.moveTo(ox + n1[0] * s, oy + n1[1] * s);
                                                        ctx.lineTo(ox + n2[0] * s, oy + n2[1] * s);
                                                        ctx.stroke();
                                                    }

                                                    // Constellation nodes with glow halos
                                                    for (let i = 0; i < nodes.length; ++i) {
                                                        const nd = nodes[i];
                                                        const nx = ox + nd[0] * s;
                                                        const ny = oy + nd[1] * s;
                                                        const nr = nd[2] * s * 0.92;
                                                        const alpha = i === 0 ? 1.0 : (nd[2] >= 4 ? 0.85 : (nd[2] >= 3 ? 0.62 : 0.36));
                                                        if (nd[2] >= 3) {
                                                            ctx.beginPath();
                                                            ctx.arc(nx, ny, nr * 2.1, 0, Math.PI * 2);
                                                            ctx.fillStyle = Qt.rgba(acc.r, acc.g, acc.b, i === 0 ? 0.24 : 0.12);
                                                            ctx.fill();
                                                        }
                                                        ctx.beginPath();
                                                        ctx.arc(nx, ny, nr, 0, Math.PI * 2);
                                                        ctx.fillStyle = Qt.rgba(acc.r, acc.g, acc.b, alpha);
                                                        ctx.fill();
                                                    }
                                                }
                                            }
                                        }

                                        // Column 2: Fastfetch Vault Metadata (`hd-ff-info`) + Carbon Cyan Palette Swatches (`hd-ff-colors`)
                                        ColumnLayout {
                                            id: infoColLayout
                                            Layout.fillWidth: false
                                            Layout.preferredWidth: homepageHeroCard.width < 820 ? 228 : 254
                                            Layout.minimumWidth: 218
                                            Layout.maximumWidth: 268
                                            Layout.alignment: Qt.AlignVCenter
                                            spacing: 3

                                            GridLayout {
                                                objectName: "nexusHomepageInfoGrid"
                                                Layout.fillWidth: true
                                                columns: 2
                                                columnSpacing: 16
                                                rowSpacing: 2

                                                StyledText { text: "user"; font.family: Appearance.font.family.monospace; font.pixelSize: 11; font.weight: Font.Bold; color: settledColors.colPrimary }
                                                StyledText { text: String(root.nexus?.stats?.userHost ?? "llocphann@vault"); font.family: Appearance.font.family.monospace; font.pixelSize: 11; color: root.ccStop(12) }

                                                StyledText { text: "greet"; font.family: Appearance.font.family.monospace; font.pixelSize: 11; font.weight: Font.Bold; color: settledColors.colPrimary }
                                                RowLayout {
                                                    spacing: 1
                                                    StyledText { text: homepageHeroCard.greetText; font.family: Appearance.font.family.monospace; font.pixelSize: 11; color: root.ccStop(12) }
                                                    StyledText { text: "█"; font.family: Appearance.font.family.monospace; font.pixelSize: 11; color: settledColors.colPrimary; opacity: root.cursorBlinkOn ? 1.0 : 0.0 }
                                                }

                                                StyledText { Layout.alignment: Qt.AlignTop; text: "datetime"; font.family: Appearance.font.family.monospace; font.pixelSize: 11; font.weight: Font.Bold; color: settledColors.colPrimary }
                                                StyledText { text: root.liveDateTimeStr; font.family: Appearance.font.family.monospace; font.pixelSize: 11; color: root.ccStop(12) }

                                                StyledText { text: "weather"; font.family: Appearance.font.family.monospace; font.pixelSize: 11; font.weight: Font.Bold; color: settledColors.colPrimary }
                                                StyledText { text: homepageHeroCard.weatherLineText; font.family: Appearance.font.family.monospace; font.pixelSize: 11; color: root.ccStop(12); elide: Text.ElideRight; Layout.fillWidth: true }

                                                StyledText { text: "v-age"; font.family: Appearance.font.family.monospace; font.pixelSize: 11; font.weight: Font.Bold; color: settledColors.colPrimary }
                                                StyledText {
                                                    text: root.nexus?.stats?.vaultAgeFormatted
                                                        ? String(root.nexus.stats.vaultAgeFormatted)
                                                        : (String(root.nexus?.stats?.vaultAgeDays ?? 0) + " days")
                                                    font.family: Appearance.font.family.monospace
                                                    font.pixelSize: 11
                                                    color: root.ccStop(12)
                                                }

                                                StyledText { text: "note"; font.family: Appearance.font.family.monospace; font.pixelSize: 11; font.weight: Font.Bold; color: settledColors.colPrimary }
                                                StyledText { text: String(root.nexus?.stats?.noteCount ?? 0) + " entries"; font.family: Appearance.font.family.monospace; font.pixelSize: 11; color: root.ccStop(12) }

                                                StyledText { text: "journal"; font.family: Appearance.font.family.monospace; font.pixelSize: 11; font.weight: Font.Bold; color: settledColors.colPrimary }
                                                StyledText { text: String(root.nexus?.stats?.journalCount ?? 0) + " entries"; font.family: Appearance.font.family.monospace; font.pixelSize: 11; color: root.ccStop(12) }

                                                StyledText { text: "book"; font.family: Appearance.font.family.monospace; font.pixelSize: 11; font.weight: Font.Bold; color: settledColors.colPrimary }
                                                StyledText { text: String(root.nexus?.stats?.bookCount ?? 0); font.family: Appearance.font.family.monospace; font.pixelSize: 11; color: root.ccStop(12) }

                                                StyledText { text: "tag"; font.family: Appearance.font.family.monospace; font.pixelSize: 11; font.weight: Font.Bold; color: settledColors.colPrimary }
                                                StyledText { text: String(root.nexus?.stats?.tagCount ?? 0); font.family: Appearance.font.family.monospace; font.pixelSize: 11; color: root.ccStop(12) }
                                            }

                                            // 7 Auto-Themed Carbon Cyan Palette Swatches (`hd-ff-colors`: `--cc-p04` .. `--cc-p13`)
                                            RowLayout {
                                                Layout.topMargin: 6
                                                spacing: 4
                                                Repeater {
                                                    model: root.homepageThemeSwatches
                                                    delegate: Rectangle {
                                                        required property string modelData
                                                        width: 16
                                                        height: 10
                                                        radius: 2
                                                        color: modelData
                                                    }
                                                }
                                            }
                                        }

                                        // Column 3: 17-Week Activity Heatmap (`hd-heat` — 1fr column with 17×7 fluid grid from `info-headers.js` & `04_Configuration.css`)
                                        Item {
                                            id: heatmapCol
                                            objectName: "nexusHomepageHeatmapColumn"
                                            Layout.alignment: Qt.AlignVCenter
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            Layout.minimumWidth: 232
                                            Layout.leftMargin: 4
                                            implicitWidth: Math.max(268, availW)
                                            implicitHeight: heatmapInnerCol.implicitHeight

                                            readonly property int cellW: 11
                                            readonly property int cellH: 11
                                            readonly property int cellGap: 3
                                            readonly property int computedRowW: Math.floor(homepageHeroCard.width - 32 - emblemColItem.width - infoColLayout.width - homepageHeroRow.spacing * 2 - 12)
                                            readonly property int availW: Math.max(232, computedRowW)
                                            readonly property int availH: Math.max(96, Math.floor(homepageHeroCard.height - 134))
                                            readonly property int numWeeks: Math.max(17, Math.min(52, Math.floor((availW + cellGap) / (cellW + cellGap))))
                                            readonly property int gridW: numWeeks * cellW + (numWeeks - 1) * cellGap
                                            readonly property int gridH: 7 * cellH + 6 * cellGap
                                            readonly property var sourceCells: (root.nexus?.stats?.activityHeatmapExtended && root.nexus.stats.activityHeatmapExtended.length >= numWeeks * 7)
                                                ? root.nexus.stats.activityHeatmapExtended
                                                : (root.nexus?.stats?.activityHeatmap ?? [])
                                            readonly property var cellsData: {
                                                const needed = numWeeks * 7;
                                                const cells = sourceCells.slice(Math.max(0, sourceCells.length - needed));
                                                return Array(Math.max(0, needed - cells.length)).fill(null).concat(cells);
                                            }

                                            // Auto-themed 5-level heatmap palette matching `.hd-heat-cell` & `.l1`..`.l4` in `04_Configuration.css`
                                            readonly property string heat0: root.mixColorHex(root.ccStop(2), settledColors.colLayer0 ?? "#10181b", 0.45)
                                            readonly property string heat1: root.mixColorHex(settledColors.colPrimary ?? "#82c2cf", heat0, 0.28)
                                            readonly property string heat2: root.mixColorHex(settledColors.colPrimary ?? "#82c2cf", heat0, 0.50)
                                            readonly property string heat3: root.mixColorHex(settledColors.colPrimary ?? "#82c2cf", heat0, 0.75)
                                            readonly property string heat4: String(settledColors.colPrimary ?? "#82c2cf")

                                            function colorForLevel(lvl: int): string {
                                                if (lvl >= 4) return heatmapCol.heat4;
                                                if (lvl === 3) return heatmapCol.heat3;
                                                if (lvl === 2) return heatmapCol.heat2;
                                                if (lvl === 1) return heatmapCol.heat1;
                                                return heatmapCol.heat0;
                                            }

                                            ColumnLayout {
                                                id: heatmapInnerCol
                                                anchors.verticalCenter: parent.verticalCenter
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                width: heatmapCol.gridW
                                                spacing: 7

                                                // `.hd-heat-label { display: flex; align-items: baseline; gap: 8px; font-size: .88em }`
                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    Layout.preferredWidth: heatmapCol.gridW
                                                    Layout.maximumWidth: heatmapCol.gridW
                                                    spacing: 10

                                                    StyledText {
                                                        text: "activity"
                                                        font.family: Appearance.font.family.monospace
                                                        font.pixelSize: 11
                                                        font.weight: Font.Bold
                                                        color: settledColors.colPrimary
                                                    }
                                                    Item {
                                                        Layout.fillWidth: true
                                                        Layout.minimumWidth: 8
                                                    }
                                                    StyledText {
                                                        text: "latest note edits · " + String(heatmapCol.numWeeks) + " weeks"
                                                        font.family: Appearance.font.family.monospace
                                                        font.pixelSize: 10
                                                        color: settledColors.colSubtext
                                                        elide: Text.ElideRight
                                                        horizontalAlignment: Text.AlignRight
                                                    }
                                                }

                                                // `.hd-heat-grid` — dynamic columns × 7 rows (top-to-bottom per week column)
                                                Grid {
                                                    id: heatmapGrid
                                                    objectName: "nexusHomepageHeatmapGrid"
                                                    Layout.preferredWidth: heatmapCol.gridW
                                                    Layout.preferredHeight: heatmapCol.gridH
                                                    width: heatmapCol.gridW
                                                    height: heatmapCol.gridH
                                                    columns: heatmapCol.numWeeks
                                                    rows: 7
                                                    flow: Grid.TopToBottom
                                                    columnSpacing: heatmapCol.cellGap
                                                    rowSpacing: heatmapCol.cellGap

                                                    Repeater {
                                                        model: heatmapCol.numWeeks * 7
                                                        delegate: Rectangle {
                                                            id: heatCellRect
                                                            required property int index
                                                            readonly property var cellEntry: (index < heatmapCol.cellsData.length) ? heatmapCol.cellsData[index] : null
                                                            readonly property int levelVal: Number(cellEntry?.level ?? 0)
                                                            readonly property int countVal: Number(cellEntry?.count ?? 0)
                                                            readonly property string dateKey: String(cellEntry?.date ?? "")
                                                            width: heatmapCol.cellW
                                                            height: heatmapCol.cellH
                                                            radius: 3
                                                            color: heatmapCol.colorForLevel(levelVal)

                                                            HoverHandler {
                                                                id: heatCellHover
                                                            }

                                                            ToolTip.visible: heatCellHover.hovered && heatCellRect.dateKey.length > 0
                                                            ToolTip.delay: 120
                                                            ToolTip.text: heatCellRect.dateKey + " · " + String(heatCellRect.countVal) + " note" + (heatCellRect.countVal === 1 ? "" : "s") + " last modified"
                                                        }
                                                    }
                                                }

                                                // `.hd-heat-legend` — right-aligned to the 17-week grid width
                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    Layout.preferredWidth: heatmapCol.gridW
                                                    Layout.maximumWidth: heatmapCol.gridW
                                                    spacing: 4

                                                    Item {
                                                        Layout.fillWidth: true
                                                    }
                                                    StyledText {
                                                        text: "less"
                                                        font.family: Appearance.font.family.monospace
                                                        font.pixelSize: 9
                                                        color: settledColors.colSubtext
                                                    }
                                                    Repeater {
                                                        model: [
                                                            heatmapCol.heat0,
                                                            heatmapCol.heat1,
                                                            heatmapCol.heat2,
                                                            heatmapCol.heat3,
                                                            heatmapCol.heat4
                                                        ]
                                                        delegate: Rectangle {
                                                            required property string modelData
                                                            width: 10
                                                            height: 10
                                                            radius: 2
                                                            color: modelData
                                                        }
                                                    }
                                                    StyledText {
                                                        text: "more"
                                                        font.family: Appearance.font.family.monospace
                                                        font.pixelSize: 9
                                                        color: settledColors.colSubtext
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // Quick Action Buttons Bar (`info-headers.js` exact 7 buttons: `/journal`, `/zettelkasten`, `/cornell`, `/movies`, `/tvseries`, `/games`, `/web-site`)
                                    Flow {
                                        objectName: "nexusHomepageActionsRow"
                                        Layout.fillWidth: true
                                        spacing: 6

                                        readonly property var actionButtons: [
                                            { "label": "/journal", "action": "daily", "primary": true },
                                            { "label": "/zettelkasten", "action": "zk", "primary": false },
                                            { "label": "/cornell", "action": "cornell", "primary": false },
                                            { "label": "/movies", "action": "movies", "primary": false },
                                            { "label": "/tvseries", "action": "tvSeries", "primary": false },
                                            { "label": "/games", "action": "games", "primary": false },
                                            { "label": "/web-site", "action": "websites", "primary": false }
                                        ]

                                        Repeater {
                                            model: parent.actionButtons
                                            delegate: Rectangle {
                                                required property var modelData
                                                height: 25
                                                width: pillLabel.implicitWidth + 16
                                                radius: 6
                                                color: modelData.primary
                                                    ? settledColors.colPrimary
                                                    : (heroPillMouse.containsMouse ? Qt.rgba(0.51, 0.76, 0.81, 0.16) : Qt.rgba(0.51, 0.76, 0.81, 0.08))
                                                border.width: 1
                                                border.color: modelData.primary ? settledColors.colPrimary : "#2e82c2cf"

                                                StyledText {
                                                    id: pillLabel
                                                    anchors.centerIn: parent
                                                    text: modelData.label
                                                    font.family: Appearance.font.family.monospace
                                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                                    font.weight: modelData.primary ? Font.Bold : Font.DemiBold
                                                    color: modelData.primary ? "#0d1216" : settledColors.colPrimary
                                                }
                                                MouseArea {
                                                    id: heroPillMouse
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        if (!root.nexus)
                                                            return;
                                                        if (modelData.action === "daily")
                                                            root.nexus.openDailyNote();
                                                        else if (modelData.action === "zk")
                                                            root.nexus.openCollection("zettelkasten");
                                                        else
                                                            root.nexus.openCollection(modelData.action);
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // Ornamental Diamond Divider (`─── ◇ ───`)
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10
                                Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: "#268dc9d6" }
                                StyledText { text: "◇"; font.pixelSize: 10; color: "#8dc9d6" }
                                Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: "#268dc9d6" }
                            }

                            // Vertical Splitter for Hero Dashboard Card Height (hover-only)
                            Rectangle {
                                id: nexusHomepageHeroSplitter
                                objectName: "nexusHomepageHeroSplitter"
                                Layout.fillWidth: true
                                Layout.preferredHeight: 6
                                radius: 3
                                readonly property bool active: heroResizeMouse.pressed || heroResizeMouse.containsMouse
                                opacity: active ? 1.0 : 0.0
                                Behavior on opacity { NumberAnimation { duration: 150 } }
                                color: active ? settledColors.colPrimary : "transparent"

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 48
                                    height: 2
                                    radius: 1
                                    color: nexusHomepageHeroSplitter.active
                                        ? settledColors.colOnPrimary
                                        : settledColors.colLayer0Border
                                }

                                MouseArea {
                                    id: heroResizeMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    preventStealing: true
                                    cursorShape: Qt.SizeVerCursor
                                    onPositionChanged: mouse => {
                                        if (!pressed || !root.nexus)
                                            return;
                                        const pt = mapToItem(homepageHeroCard, 0, mouse.y);
                                        root.nexus.setHomepageHeroHeight(Math.round(pt.y));
                                    }
                                }
                            }

                            // Middle Section: Daily Schedule (exclusively backed by Dashboard Weekly Planner projection) + Right Photo & 3D Abyssal Globe + Workout Tables
                            Rectangle {
                                id: homepageScheduleCard
                                objectName: "nexusHomepageScheduleCard"
                                Layout.fillWidth: true
                                implicitHeight: Math.max(root.nexus?.homepageScheduleHeight ?? 230, scheduleCol.implicitHeight + 28)
                                radius: 12
                                color: settledColors.colLayer0
                                border.width: 1
                                border.color: settledColors.colLayer0Border

                                readonly property string activeScheduleIso: {
                                    const sel = String(root.nexus?.selectedDateStr ?? "");
                                    if (/^\d{4}-\d{2}-\d{2}$/.test(sel))
                                        return sel;
                                    const dashIso = String(GlobalStates.dashboardPlannerBrowser?.selectedDateIso ?? "");
                                    if (/^\d{4}-\d{2}-\d{2}$/.test(dashIso))
                                        return dashIso;
                                    return Qt.formatDate(new Date(), "yyyy-MM-dd");
                                }

                                readonly property string activeWeekdayUpper: {
                                    const parts = homepageScheduleCard.activeScheduleIso.split("-");
                                    const dt = parts.length === 3
                                        ? new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]), 12, 0, 0, 0)
                                        : new Date();
                                    return Qt.formatDate(dt, "dddd").toUpperCase();
                                }

                                readonly property var projectedDayData: {
                                    const _rev = root.plannerRevision;
                                    const parts = homepageScheduleCard.activeScheduleIso.split("-");
                                    const targetDate = parts.length === 3
                                        ? new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]), 12, 0, 0, 0)
                                        : new Date();
                                    return PlannerProjection.projectDay(
                                        HostServices.Events?.list ?? [],
                                        HostServices.CalendarSync?.events ?? [],
                                        targetDate,
                                        1
                                    );
                                }

                                readonly property var plannerAllDayEvents: projectedDayData?.allDayEvents ?? []
                                readonly property var plannerTimedEvents: projectedDayData?.timedEvents ?? []

                                function addPlannerEventFromInput(rawInput: string): void {
                                    const trimmed = String(rawInput ?? "").trim();
                                    if (!trimmed)
                                        return;
                                    const parts = homepageScheduleCard.activeScheduleIso.split("-");
                                    const baseDate = parts.length === 3
                                        ? new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]))
                                        : new Date();
                                    let sh = 9, sm = 0, eh = 10, em = 0;
                                    let title = trimmed;
                                    const m = trimmed.match(/^(\d{1,2}):(\d{2})(?:\s*[-–]\s*(\d{1,2}):(\d{2}))?\s+(.+)$/);
                                    if (m) {
                                        sh = Math.max(0, Math.min(23, Number(m[1])));
                                        sm = Math.max(0, Math.min(59, Number(m[2])));
                                        if (m[3] !== undefined && m[4] !== undefined) {
                                            eh = Math.max(0, Math.min(23, Number(m[3])));
                                            em = Math.max(0, Math.min(59, Number(m[4])));
                                        } else {
                                            eh = Math.min(23, sh + 1);
                                            em = sm;
                                        }
                                        title = String(m[5]).trim();
                                    }
                                    const startDt = new Date(baseDate.getFullYear(), baseDate.getMonth(), baseDate.getDate(), sh, sm, 0, 0);
                                    const endDt = new Date(baseDate.getFullYear(), baseDate.getMonth(), baseDate.getDate(), eh, em, 0, 0);
                                    if (HostServices.Events && typeof HostServices.Events.addEvent === "function") {
                                        HostServices.Events.addEvent(
                                            title,
                                            "",
                                            startDt.toISOString(),
                                            "general",
                                            "normal",
                                            15,
                                            "none",
                                            endDt.toISOString(),
                                            false
                                        );
                                        root.plannerRevision += 1;
                                    }
                                }

                                ColumnLayout {
                                    id: scheduleCol
                                    anchors.fill: parent
                                    anchors.margins: 14
                                    spacing: 12

                                    // 2-Column Split: Left `| Daily Schedule` (backed exclusively by Dashboard Weekly Planner) | Right (Street Photo + 3D Abyssal Globe) + (`| Calisthenics` + `| Cardio`)
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 14

                                        // Left Column: `| Daily Schedule` (Backed Exclusively by Dashboard Weekly Planner)
                                        Rectangle {
                                            Layout.fillWidth: true
                                            Layout.preferredWidth: 320
                                            Layout.alignment: Qt.AlignTop
                                            implicitHeight: schedTableCol.implicitHeight + 20
                                            radius: 8
                                            color: settledColors.colLayer1
                                            border.width: 1
                                            border.color: settledColors.colLayer0Border

                                            ColumnLayout {
                                                id: schedTableCol
                                                anchors.fill: parent
                                                anchors.margins: 12
                                                spacing: 8

                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 8
                                                    Rectangle { width: 3; height: 15; radius: 1.5; color: settledColors.colPrimary }
                                                    StyledText {
                                                        Layout.fillWidth: true
                                                        text: "Daily Schedule"
                                                        font.pixelSize: Appearance.font.pixelSize.normal
                                                        font.weight: Font.Bold
                                                        color: settledColors.colPrimary
                                                    }
                                                    Rectangle {
                                                        objectName: "nexusHomepageOpenDashboardPlannerButton"
                                                        implicitHeight: 22
                                                        implicitWidth: openPlannerTabRow.implicitWidth + 12
                                                        radius: 5
                                                        color: settledColors.colLayer2
                                                        RowLayout {
                                                            id: openPlannerTabRow
                                                            anchors.centerIn: parent
                                                            spacing: 4
                                                            MaterialSymbol { text: "calendar_view_week"; iconSize: 13; color: settledColors.colPrimary }
                                                            StyledText { text: "Weekly Planner"; font.pixelSize: 11; color: settledColors.colOnLayer1 }
                                                        }
                                                        MouseArea {
                                                            anchors.fill: parent
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: {
                                                                if (GlobalStates.dashboardPlannerBrowser) {
                                                                    const nextState = Object.assign({}, GlobalStates.dashboardPlannerBrowser);
                                                                    nextState.selectedDateIso = homepageScheduleCard.activeScheduleIso;
                                                                    GlobalStates.dashboardPlannerBrowser = nextState;
                                                                }
                                                                GlobalStates.dashboardPageId = "weeklyPlanner";
                                                                Config.setNestedValue("dashboard.lastPageId", "weeklyPlanner");
                                                                GlobalStates.nexusOpen = false;
                                                                GlobalStates.dashboardOpen = true;
                                                            }
                                                        }
                                                    }
                                                }

                                                // Table Header (`TIME | <WEEKDAY>`) matching Obsidian Homepage Daily Schedule
                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 10
                                                    StyledText {
                                                        Layout.preferredWidth: 96
                                                        text: "TIME"
                                                        font.family: Appearance.font.family.monospace
                                                        font.pixelSize: 11
                                                        font.weight: Font.Bold
                                                        color: settledColors.colPrimary
                                                    }
                                                    StyledText {
                                                        Layout.fillWidth: true
                                                        text: homepageScheduleCard.activeWeekdayUpper + " (" + homepageScheduleCard.activeScheduleIso + ")"
                                                        font.family: Appearance.font.family.monospace
                                                        font.pixelSize: 11
                                                        font.weight: Font.Bold
                                                        color: settledColors.colPrimary
                                                        elide: Text.ElideRight
                                                    }
                                                }

                                                Rectangle {
                                                    Layout.fillWidth: true
                                                    implicitHeight: 1
                                                    color: settledColors.colLayer0Border
                                                }

                                                // All-day events from Weekly Planner
                                                Repeater {
                                                    model: homepageScheduleCard.plannerAllDayEvents
                                                    delegate: Rectangle {
                                                        required property var modelData
                                                        Layout.fillWidth: true
                                                        Layout.preferredHeight: 28
                                                        radius: 5
                                                        color: modelData.swatch?.bg ?? "#3a2e1d"
                                                        border.width: 1
                                                        border.color: modelData.swatch?.border ?? "#d99b26"

                                                        RowLayout {
                                                            anchors.fill: parent
                                                            anchors.leftMargin: 8
                                                            anchors.rightMargin: 8
                                                            spacing: 10
                                                            StyledText {
                                                                Layout.preferredWidth: 88
                                                                text: "ALL DAY"
                                                                font.family: Appearance.font.family.monospace
                                                                font.pixelSize: 11
                                                                font.weight: Font.Bold
                                                                color: root.plannerAccentColor(modelData.swatch)
                                                            }
                                                            StyledText {
                                                                Layout.fillWidth: true
                                                                text: String(modelData.title ?? "")
                                                                font.pixelSize: 12
                                                                font.weight: Font.DemiBold
                                                                color: settledColors.colOnLayer1
                                                                elide: Text.ElideRight
                                                            }
                                                        }
                                                    }
                                                }

                                                // Timed events from Weekly Planner
                                                Repeater {
                                                    model: homepageScheduleCard.plannerTimedEvents
                                                    delegate: Rectangle {
                                                        required property var modelData
                                                        required property int index
                                                        objectName: "nexusHomepagePlannerEvent_" + String(index)
                                                        Layout.fillWidth: true
                                                        Layout.preferredHeight: 32
                                                        radius: 5
                                                        color: index % 2 === 0 ? "transparent" : Qt.alpha(settledColors.colLayer2, 0.35)

                                                        Rectangle {
                                                            anchors.left: parent.left
                                                            anchors.top: parent.top
                                                            anchors.bottom: parent.bottom
                                                            width: 2
                                                            radius: 1
                                                            color: root.plannerAccentColor(modelData.swatch)
                                                        }

                                                        RowLayout {
                                                            anchors.fill: parent
                                                            anchors.leftMargin: 8
                                                            anchors.rightMargin: 8
                                                            spacing: 10

                                                            StyledText {
                                                                Layout.preferredWidth: 88
                                                                text: String(modelData.timeRange ?? "")
                                                                font.family: Appearance.font.family.monospace
                                                                font.pixelSize: 11
                                                                font.weight: Font.DemiBold
                                                                color: settledColors.colSubtext
                                                                elide: Text.ElideRight
                                                            }
                                                            StyledText {
                                                                Layout.fillWidth: true
                                                                text: String(modelData.title ?? "")
                                                                font.pixelSize: 12
                                                                color: settledColors.colOnLayer1
                                                                elide: Text.ElideRight
                                                            }
                                                        }
                                                    }
                                                }

                                                StyledText {
                                                    visible: homepageScheduleCard.plannerAllDayEvents.length === 0 && homepageScheduleCard.plannerTimedEvents.length === 0
                                                    Layout.fillWidth: true
                                                    text: "No events scheduled for this date in Weekly Planner."
                                                    font.pixelSize: 11
                                                    font.italic: true
                                                    color: settledColors.colSubtext
                                                }

                                                // Inline Quick Add Event to Weekly Planner
                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    Layout.topMargin: 4
                                                    spacing: 6

                                                    Rectangle {
                                                        Layout.fillWidth: true
                                                        Layout.preferredHeight: 28
                                                        radius: 6
                                                        color: settledColors.colLayer0
                                                        border.width: 1
                                                        border.color: settledColors.colLayer0Border

                                                        TextField {
                                                            id: quickPlannerEventInput
                                                            objectName: "nexusHomepagePlannerEventInput"
                                                            anchors.fill: parent
                                                            anchors.leftMargin: 8
                                                            anchors.rightMargin: 8
                                                            placeholderText: "06:15-07:00 Truy Bài..."
                                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                                            color: settledColors.colOnLayer1
                                                            background: null
                                                            onAccepted: {
                                                                if (text.trim().length > 0) {
                                                                    homepageScheduleCard.addPlannerEventFromInput(text.trim());
                                                                    text = "";
                                                                    quickPlannerEventInput.focus = false;
                                                                    root.restoreWorkspaceFocus();
                                                                    Qt.callLater(root.restoreWorkspaceFocus);
                                                                }
                                                            }
                                                            Keys.onEscapePressed: event => {
                                                                quickPlannerEventInput.focus = false;
                                                                root.restoreWorkspaceFocus();
                                                                Qt.callLater(root.restoreWorkspaceFocus);
                                                                event.accepted = true;
                                                            }
                                                            Keys.onPressed: event => {
                                                                if ((event.modifiers & (Qt.AltModifier | Qt.ControlModifier | Qt.MetaModifier)) !== 0
                                                                    && root.nexus && root.nexus.handleKeyEvent(event)) {
                                                                    event.accepted = true;
                                                                }
                                                            }
                                                        }
                                                    }

                                                    Rectangle {
                                                        objectName: "nexusHomepageAddPlannerEventButton"
                                                        Layout.preferredHeight: 28
                                                        Layout.preferredWidth: 64
                                                        radius: 6
                                                        color: settledColors.colPrimary
                                                        StyledText {
                                                            anchors.centerIn: parent
                                                            text: "+ Event"
                                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                                            font.weight: Font.Bold
                                                            color: settledColors.colOnPrimary
                                                        }
                                                        MouseArea {
                                                            anchors.fill: parent
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: {
                                                                if (quickPlannerEventInput.text.trim().length > 0) {
                                                                    homepageScheduleCard.addPlannerEventFromInput(quickPlannerEventInput.text.trim());
                                                                    quickPlannerEventInput.text = "";
                                                                    root.focusPrimarySurface();
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        // Right Column: Top (Photo + 3D Abyssal Globe) + Bottom (4-Col Calisthenics & Cardio Tables)
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.preferredWidth: 340
                                            Layout.alignment: Qt.AlignTop
                                            spacing: 10

                                            // Top Row: Vault Street Photo + Interactive 3D Abyssal Globe (`collections.places`)
                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 10

                                                // Left: Vault Street Photo (`797722956_17919373971425474_540898127545340166_n.jpg`) with Auto-Theming Color Overlay
                                                Rectangle {
                                                    id: homepagePhotoCard
                                                    objectName: "nexusHomepagePhotoCard"
                                                    Layout.fillWidth: true
                                                    Layout.preferredWidth: 1
                                                    Layout.preferredHeight: 204
                                                    radius: 8
                                                    color: root.ccStop(0)
                                                    border.width: 1
                                                    border.color: Qt.rgba(
                                                        (settledColors.colPrimary ?? root.ccStop(6)).r,
                                                        (settledColors.colPrimary ?? root.ccStop(6)).g,
                                                        (settledColors.colPrimary ?? root.ccStop(6)).b,
                                                        0.36
                                                    )
                                                    clip: true

                                                    Image {
                                                        id: homepagePhotoImage
                                                        objectName: "nexusHomepagePhotoImage"
                                                        anchors.fill: parent
                                                        source: String(root.nexus?.homepagePhotoUrl || root.nexus?.homepageCoverUrl || "")
                                                        fillMode: Image.PreserveAspectCrop
                                                        asynchronous: true
                                                        layer.enabled: true
                                                        layer.effect: MultiEffect {
                                                            colorization: 0.72
                                                            colorizationColor: Qt.color(root._settledPrimary)
                                                        }
                                                    }

                                                    // Dynamic Auto-Theming Color Wash Layer (adapts photo tone to Alis active theme)
                                                    Rectangle {
                                                        id: homepagePhotoThemeOverlay
                                                        objectName: "nexusHomepagePhotoThemeOverlay"
                                                        anchors.fill: parent
                                                        readonly property color primaryTone: Qt.color(root._settledPrimary)
                                                        readonly property color themePrimaryColor: primaryTone
                                                        readonly property color secondaryTone: Qt.color(root._settledSecondary)
                                                        readonly property color baseTone: root.ccStop(0)
                                                        readonly property color themeTintColor: Qt.rgba(primaryTone.r, primaryTone.g, primaryTone.b, 0.35)
                                                        color: "transparent"
                                                        gradient: Gradient {
                                                            orientation: Gradient.Vertical
                                                            GradientStop {
                                                                position: 0.0
                                                                color: Qt.rgba(
                                                                    homepagePhotoThemeOverlay.primaryTone.r,
                                                                    homepagePhotoThemeOverlay.primaryTone.g,
                                                                    homepagePhotoThemeOverlay.primaryTone.b,
                                                                    0.40
                                                                )
                                                            }
                                                            GradientStop {
                                                                position: 0.50
                                                                color: Qt.rgba(
                                                                    homepagePhotoThemeOverlay.primaryTone.r,
                                                                    homepagePhotoThemeOverlay.primaryTone.g,
                                                                    homepagePhotoThemeOverlay.primaryTone.b,
                                                                    0.34
                                                                )
                                                            }
                                                            GradientStop {
                                                                position: 1.0
                                                                color: Qt.rgba(
                                                                    homepagePhotoThemeOverlay.secondaryTone.r,
                                                                    homepagePhotoThemeOverlay.secondaryTone.g,
                                                                    homepagePhotoThemeOverlay.secondaryTone.b,
                                                                    0.38
                                                                )
                                                            }
                                                        }
                                                    }
                                                }

                                                // Right: 3D Abyssal Globe Widget (`90_System/92_Scripts/Dataview/homepage/globe-widget.js`)
                                                Rectangle {
                                                    Layout.fillWidth: true
                                                    Layout.preferredWidth: 1
                                                    Layout.preferredHeight: 204
                                                    radius: 8
                                                    color: root.ccStop(0)
                                                    border.width: 1
                                                    border.color: settledColors.colLayer0Border
                                                    clip: true

                                                    Loader {
                                                        id: homepageGlobeLoader
                                                        anchors.fill: parent
                                                        anchors.margins: 4
                                                        asynchronous: Quickshell.env("QT_QUICK_BACKEND") !== "software"
                                                        property bool _globeSettledOnce: false
                                                        readonly property bool hostActiveForGlobe: Boolean(root.nexus && root.nexus.isOpen) && root.visible && root.transitionSettled && ((root.nexus ? root.nexus.activeView : "homepage") === "homepage")
                                                        Component.onCompleted: {
                                                            if (root.transitionSettled)
                                                                _globeSettledOnce = true;
                                                        }
                                                        Connections {
                                                            target: root
                                                            function onTransitionSettledChanged() {
                                                                if (root.transitionSettled && !homepageGlobeLoader._globeSettledOnce)
                                                                    homepageGlobeLoader._globeSettledOnce = true;
                                                            }
                                                        }
                                                        active: root.transitionSettled || _globeSettledOnce || !Boolean(root.nexus?.isOpen)
                                                        onLoaded: {
                                                            _globeSettledOnce = true;
                                                        }
                                                        sourceComponent: Component {
                                                            NexusGlobeWidget {
                                                                id: homepageGlobeWidget
                                                                anchors.fill: parent
                                                                nexus: root.nexus
                                                                workspace: root
                                                                revealStaggerMs: 68
                                                                placesModel: root.nexus?.collections?.places ?? []
                                                                active: homepageGlobeLoader.hostActiveForGlobe
                                                            }
                                                        }
                                                    }
                                                }
                                            }

                                            // Bottom Row: 4-Column Calisthenics (`EXERCISE | EQUIPMENT | SET - REPS | REST`) & 3-Column Cardio (`TIME | WORKOUT | NOTES`)
                                            Rectangle {
                                                visible: ((root.nexus?.dailySchedule?.exerciseRows ?? []).length > 0) || ((root.nexus?.dailySchedule?.cardioRows ?? []).length > 0)
                                                Layout.fillWidth: true
                                                implicitHeight: workoutCol.implicitHeight + 18
                                                radius: 8
                                                color: settledColors.colLayer1
                                                border.width: 1
                                                border.color: settledColors.colLayer0Border

                                                ColumnLayout {
                                                    id: workoutCol
                                                    anchors.fill: parent
                                                    anchors.margins: 10
                                                    spacing: 5

                                                    RowLayout {
                                                        Layout.fillWidth: true
                                                        spacing: 6
                                                        Rectangle { width: 3; height: 14; radius: 1.5; color: settledColors.colPrimary }
                                                        StyledText {
                                                            text: String(root.nexus?.dailySchedule?.exerciseHeading ?? "Calisthenics")
                                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                                            font.weight: Font.Bold
                                                            color: settledColors.colPrimary
                                                        }
                                                    }

                                                    RowLayout {
                                                        Layout.fillWidth: true
                                                        spacing: 6
                                                        StyledText { Layout.fillWidth: true; text: "EXERCISE"; font.family: Appearance.font.family.monospace; font.pixelSize: 9; font.weight: Font.Bold; color: settledColors.colPrimary }
                                                        StyledText { Layout.preferredWidth: 74; text: "EQUIPMENT"; font.family: Appearance.font.family.monospace; font.pixelSize: 9; font.weight: Font.Bold; color: settledColors.colPrimary }
                                                        StyledText { Layout.preferredWidth: 64; text: "SET - REPS"; font.family: Appearance.font.family.monospace; font.pixelSize: 9; font.weight: Font.Bold; color: settledColors.colPrimary }
                                                        StyledText { Layout.preferredWidth: 44; text: "REST"; font.family: Appearance.font.family.monospace; font.pixelSize: 9; font.weight: Font.Bold; color: settledColors.colPrimary }
                                                    }

                                                    Repeater {
                                                        model: root.nexus?.dailySchedule?.exerciseRows ?? []
                                                        delegate: RowLayout {
                                                            required property var modelData
                                                            Layout.fillWidth: true
                                                            spacing: 6
                                                            StyledText {
                                                                Layout.fillWidth: true
                                                                text: String(modelData.exercise ?? modelData[0] ?? "")
                                                                font.pixelSize: 10
                                                                color: settledColors.colOnLayer1
                                                                elide: Text.ElideRight
                                                            }
                                                            StyledText {
                                                                Layout.preferredWidth: 74
                                                                text: String(modelData.equipment ?? modelData.muscleGroup ?? "")
                                                                font.pixelSize: 10
                                                                color: settledColors.colSubtext
                                                                elide: Text.ElideRight
                                                            }
                                                            StyledText {
                                                                Layout.preferredWidth: 64
                                                                text: String(modelData.reps ?? modelData[1] ?? "")
                                                                font.family: Appearance.font.family.monospace
                                                                font.pixelSize: 10
                                                                color: settledColors.colPrimary
                                                                elide: Text.ElideRight
                                                            }
                                                            StyledText {
                                                                Layout.preferredWidth: 44
                                                                text: String(modelData.sets ?? modelData[2] ?? "")
                                                                font.family: Appearance.font.family.monospace
                                                                font.pixelSize: 10
                                                                color: settledColors.colSubtext
                                                                elide: Text.ElideRight
                                                            }
                                                        }
                                                    }

                                                    Rectangle {
                                                        visible: (root.nexus?.dailySchedule?.cardioRows ?? []).length > 0
                                                        Layout.fillWidth: true
                                                        implicitHeight: 1
                                                        color: settledColors.colLayer0Border
                                                    }

                                                    RowLayout {
                                                        visible: (root.nexus?.dailySchedule?.cardioRows ?? []).length > 0
                                                        Layout.fillWidth: true
                                                        spacing: 6
                                                        Rectangle { width: 3; height: 14; radius: 1.5; color: settledColors.colPrimary }
                                                        StyledText {
                                                            text: String(root.nexus?.dailySchedule?.cardioHeading ?? "Cardio")
                                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                                            font.weight: Font.Bold
                                                            color: settledColors.colPrimary
                                                        }
                                                    }

                                                    RowLayout {
                                                        visible: (root.nexus?.dailySchedule?.cardioRows ?? []).length > 0
                                                        Layout.fillWidth: true
                                                        spacing: 6
                                                        StyledText { Layout.preferredWidth: 82; text: "TIME"; font.family: Appearance.font.family.monospace; font.pixelSize: 9; font.weight: Font.Bold; color: settledColors.colPrimary }
                                                        StyledText { Layout.fillWidth: true; text: "WORKOUT"; font.family: Appearance.font.family.monospace; font.pixelSize: 9; font.weight: Font.Bold; color: settledColors.colPrimary }
                                                        StyledText { Layout.preferredWidth: 96; text: "NOTES"; font.family: Appearance.font.family.monospace; font.pixelSize: 9; font.weight: Font.Bold; color: settledColors.colPrimary }
                                                    }

                                                    Repeater {
                                                        model: root.nexus?.dailySchedule?.cardioRows ?? []
                                                        delegate: RowLayout {
                                                            required property var modelData
                                                            Layout.fillWidth: true
                                                            spacing: 6
                                                            StyledText {
                                                                Layout.preferredWidth: 82
                                                                text: String(modelData.duration ?? modelData[0] ?? "")
                                                                font.family: Appearance.font.family.monospace
                                                                font.pixelSize: 10
                                                                color: settledColors.colSubtext
                                                                elide: Text.ElideRight
                                                            }
                                                            StyledText {
                                                                Layout.fillWidth: true
                                                                text: String(modelData.exercise ?? modelData[1] ?? "Cardio")
                                                                font.pixelSize: 10
                                                                color: settledColors.colOnLayer1
                                                                elide: Text.ElideRight
                                                            }
                                                            StyledText {
                                                                Layout.preferredWidth: 96
                                                                text: String(modelData.intensity ?? modelData[2] ?? "")
                                                                font.pixelSize: 10
                                                                color: settledColors.colSubtext
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

                            // Vertical Splitter for Daily Schedule Card Height (hover-only)
                            Rectangle {
                                id: nexusHomepageScheduleSplitter
                                objectName: "nexusHomepageScheduleSplitter"
                                Layout.fillWidth: true
                                Layout.preferredHeight: 6
                                radius: 3
                                readonly property bool active: scheduleResizeMouse.pressed || scheduleResizeMouse.containsMouse
                                opacity: active ? 1.0 : 0.0
                                Behavior on opacity { NumberAnimation { duration: 150 } }
                                color: active ? settledColors.colPrimary : "transparent"

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 48
                                    height: 2
                                    radius: 1
                                    color: nexusHomepageScheduleSplitter.active
                                        ? settledColors.colOnPrimary
                                        : settledColors.colLayer0Border
                                }

                                MouseArea {
                                    id: scheduleResizeMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    preventStealing: true
                                    cursorShape: Qt.SizeVerCursor
                                    onPositionChanged: mouse => {
                                        if (!pressed || !root.nexus)
                                            return;
                                        const pt = mapToItem(homepageScheduleCard, 0, mouse.y);
                                        root.nexus.setHomepageScheduleHeight(Math.round(pt.y));
                                    }
                                }
                            }

                            // Vault Collections & Trackers Strip (Native replacement for Obsidian Homepage Dataview/CustomHTML trackers)
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                StyledText {
                                    Layout.fillWidth: true
                                    text: "Vault Collections & Trackers"
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    font.weight: Font.Bold
                                    color: settledColors.colOnLayer1
                                }

                                StyledText {
                                    text: "Movies · TV · Games · Books · Recipes · Exercises · Places · Cornell · ZK · Finance"
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: settledColors.colSubtext
                                }
                            }

                            GridLayout {
                                id: nexusHomepageCollectionsStrip
                                objectName: "nexusHomepageCollectionsStrip"
                                Layout.fillWidth: true
                                columns: 3
                                columnSpacing: 10
                                rowSpacing: 10

                                Repeater {
                                    model: [
                                        {
                                            "id": "movies",
                                            "title": "Movies Tracker",
                                            "icon": "movie",
                                            "accent": "#f7768e",
                                            "count": (root.nexus?.collections?.movies ?? []).length,
                                            "subtitle": "Posters · IMDb · Cast · Plot"
                                        },
                                        {
                                            "id": "tvSeries",
                                            "title": "TV-Series Tracker",
                                            "icon": "live_tv",
                                            "accent": "#ff9e64",
                                            "count": (root.nexus?.collections?.tvseries ?? root.nexus?.collections?.tvSeries ?? []).length,
                                            "subtitle": "Seasons · Status · Ratings"
                                        },
                                        {
                                            "id": "games",
                                            "title": "Games Library",
                                            "icon": "sports_esports",
                                            "accent": "#73daca",
                                            "count": (root.nexus?.collections?.games ?? []).length,
                                            "subtitle": "Play status · Genres · Steam"
                                        },
                                        {
                                            "id": "books",
                                            "title": "Books & Reading",
                                            "icon": "menu_book",
                                            "accent": "#c0caf5",
                                            "count": (root.nexus?.collections?.books ?? []).length,
                                            "subtitle": "Authors · Progress · Notes"
                                        },
                                        {
                                            "id": "recipes",
                                            "title": "Cooking & Recipes",
                                            "icon": "restaurant",
                                            "accent": "#e0af68",
                                            "count": (root.nexus?.collections?.recipes ?? []).length,
                                            "subtitle": "Macros · Ingredients · Steps"
                                        },
                                        {
                                            "id": "exercises",
                                            "title": "Gym & Calisthenics",
                                            "icon": "fitness_center",
                                            "accent": "#9ece6a",
                                            "count": (root.nexus?.collections?.exercises ?? []).length,
                                            "subtitle": "Muscles · Sets · Form Guide"
                                        },
                                        {
                                            "id": "places",
                                            "title": "Places & Travel",
                                            "icon": "place",
                                            "accent": String(settledColors.colTertiary ?? settledColors.colPrimary),
                                            "count": (root.nexus?.collections?.places ?? []).length,
                                            "subtitle": "Coordinates · Maps · Ratings"
                                        },
                                        {
                                            "id": "websites",
                                            "title": "Onion Web-Sites",
                                            "icon": "language",
                                            "accent": "#2ac3de",
                                            "count": (root.nexus?.collections?.websites ?? []).length,
                                            "subtitle": ".onion directory · Categories"
                                        },
                                        {
                                            "id": "cornell",
                                            "title": "Cornell Study Notes",
                                            "icon": "school",
                                            "accent": "#e0af68",
                                            "count": (root.nexus?.collections?.cornell ?? []).length,
                                            "subtitle": "Cues (? ! .) · Marginalia"
                                        },
                                        {
                                            "id": "zettelkasten",
                                            "title": "Zettelkasten Hub",
                                            "icon": "psychology",
                                            "accent": "#9ece6a",
                                            "count": (root.nexus?.collections?.zettelkasten ?? []).length,
                                            "subtitle": "Literature · Permanent · MOCs"
                                        },
                                        {
                                            "id": "finance",
                                            "title": "Finance & Ledger",
                                            "icon": "account_balance_wallet",
                                            "accent": "#7dcfff",
                                            "count": (root.nexus?.collections?.finance ?? []).length,
                                            "subtitle": "Income · Spending · Reports"
                                        },
                                        {
                                            "id": "clippings",
                                            "title": "Web Clippings",
                                            "icon": "bookmark",
                                            "accent": "#a6adc8",
                                            "count": (root.nexus?.collections?.clippings ?? []).length,
                                            "subtitle": "Saved articles · Sources"
                                        }
                                    ]
                                    delegate: Rectangle {
                                        required property var modelData
                                        objectName: "nexusCollectionCard_" + String(modelData.id)
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 68
                                        radius: 10
                                        color: collCardMouse.containsMouse ? settledColors.colLayer2Hover : settledColors.colLayer0
                                        border.width: 1
                                        border.color: collCardMouse.containsMouse ? modelData.accent : settledColors.colLayer0Border

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 10
                                            spacing: 10

                                            Rectangle {
                                                implicitWidth: 36
                                                implicitHeight: 36
                                                width: 36
                                                height: 36
                                                radius: 8
                                                color: Qt.rgba(0.12, 0.14, 0.20, 0.75)
                                                border.width: 1
                                                border.color: modelData.accent

                                                MaterialSymbol {
                                                    anchors.centerIn: parent
                                                    text: modelData.icon
                                                    iconSize: 18
                                                    color: modelData.accent
                                                }
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 2

                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    StyledText {
                                                        Layout.fillWidth: true
                                                        text: modelData.title
                                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                                        font.weight: Font.Bold
                                                        color: settledColors.colOnLayer1
                                                        elide: Text.ElideRight
                                                    }
                                                    Rectangle {
                                                        implicitHeight: 18
                                                        implicitWidth: collCountText.implicitWidth + 10
                                                        height: 18
                                                        width: collCountText.implicitWidth + 10
                                                        radius: 9
                                                        color: settledColors.colLayer2
                                                        StyledText {
                                                            id: collCountText
                                                            anchors.centerIn: parent
                                                            text: String(modelData.count)
                                                            font.family: Appearance.font.family.monospace
                                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                                            font.weight: Font.Bold
                                                            color: modelData.accent
                                                        }
                                                    }
                                                }

                                                StyledText {
                                                    Layout.fillWidth: true
                                                    text: modelData.subtitle
                                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                                    color: settledColors.colSubtext
                                                    elide: Text.ElideRight
                                                }
                                            }
                                        }

                                        MouseArea {
                                            id: collCardMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (root.nexus)
                                                    root.nexus.openCollection(modelData.id);
                                            }
                                        }

                                        Rectangle {
                                            objectName: "nexusHomepageCollectionAdd_" + String(modelData.id)
                                            z: 2
                                            width: 20
                                            height: 20
                                            radius: 5
                                            anchors.right: parent.right
                                            anchors.bottom: parent.bottom
                                            anchors.rightMargin: 8
                                            anchors.bottomMargin: 8
                                            color: homeCollAddMouse.containsMouse ? settledColors.colPrimary : settledColors.colLayer2
                                            border.width: 1
                                            border.color: settledColors.colLayer0Border

                                            MaterialSymbol {
                                                anchors.centerIn: parent
                                                text: "add"
                                                iconSize: 13
                                                color: homeCollAddMouse.containsMouse ? settledColors.colOnPrimary : settledColors.colPrimary
                                            }
                                            MouseArea {
                                                id: homeCollAddMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    if (root.nexus)
                                                        root.nexus.openNewNoteModal(modelData.id, "");
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // Recent Notes Section
                            StyledText {
                                text: "Recent Knowledge Notes"
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.Bold
                                color: settledColors.colOnLayer1
                            }

                            GridLayout {
                                Layout.fillWidth: true
                                columns: 2
                                columnSpacing: 10
                                rowSpacing: 10

                                Repeater {
                                    model: (root.nexus?.recentNotes ?? []).slice(0, 6)
                                    delegate: Rectangle {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 74
                                        radius: 10
                                        color: homeNoteMouse.containsMouse ? settledColors.colLayer2Hover : settledColors.colLayer0
                                        border.width: 1
                                        border.color: settledColors.colLayer0Border

                                        ColumnLayout {
                                            anchors.fill: parent
                                            anchors.margins: 10
                                            spacing: 4

                                            RowLayout {
                                                Layout.fillWidth: true
                                                StyledText {
                                                    Layout.fillWidth: true
                                                    text: String(modelData.title ?? "")
                                                    font.pixelSize: Appearance.font.pixelSize.small
                                                    font.weight: Font.Bold
                                                    color: settledColors.colPrimary
                                                    elide: Text.ElideRight
                                                }
                                                StyledText {
                                                    text: String(modelData.folder || "/")
                                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                                    color: settledColors.colSubtext
                                                }
                                            }
                                            StyledText {
                                                Layout.fillWidth: true
                                                text: String(modelData.snippet || "Empty note")
                                                font.pixelSize: Appearance.font.pixelSize.smaller
                                                color: settledColors.colSubtext
                                                elide: Text.ElideRight
                                            }
                                        }
                                        MouseArea {
                                            id: homeNoteMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: mouse => {
                                                if (!root.nexus)
                                                    return;
                                                if (mouse.button === Qt.RightButton) {
                                                    const pt = mapToItem(root, mouse.x, mouse.y);
                                                    root.openContextMenu(pt.x, pt.y, {
                                                        "type": "file",
                                                        "title": modelData.title || modelData.name || modelData.relPath,
                                                        "relPath": modelData.relPath,
                                                        "noteKind": modelData.noteKind || "",
                                                        "isDir": false
                                                    });
                                                    return;
                                                }
                                                root.nexus.openFile(modelData.relPath, true);
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ───────────────────────────────────────────────────────
                    // VIEW 2: FULL VAULT GRAPH VIEW
                    // ───────────────────────────────────────────────────────
                    Item {
                        objectName: "nexusFullGraphView"
                        anchors.fill: parent
                        anchors.margins: 14
                        visible: (root.nexus?.activeView ?? "homepage") === "graph"

                        NexusGraphCanvas {
                            id: fullGraphCanvas
                            objectName: "nexusFullGraphCanvas"
                            anchors.fill: parent
                            workspace: root
                            isLocal: false
                            compact: false
                            graphData: ((root.nexus?.activeView ?? "homepage") === "graph")
                                ? (root.nexus?.vaultGraph ?? {
                                    "nodes": [],
                                    "edges": [],
                                    "groups": []
                                })
                                : ({
                                    "nodes": [],
                                    "edges": [],
                                    "groups": []
                                })
                            currentPath: String(root.nexus?.currentPath ?? "")
                            clusterPalette: root.clusterPalette
                            onNodeActivated: nodeData => {
                                if (root.nexus && nodeData && nodeData.relPath)
                                    root.nexus.openFile(nodeData.relPath, true);
                            }
                        }
                    }

                    // ───────────────────────────────────────────────────────
                    // VIEW 2B: COLLECTION / BASES BROWSER VIEW (Movies, TV Series, Games, Books, Recipes, Exercises, Places, Contacts, Onion Sites, Cornell, Zettelkasten, Finance, Clippings)
                    // ───────────────────────────────────────────────────────
                    ColumnLayout {
                        id: collectionViewRoot
                        objectName: "nexusCollectionView"
                        anchors.fill: parent
                        anchors.margins: 16
                        visible: (root.nexus?.activeView ?? "homepage") === "collection"
                        spacing: 12

                        property string newEntryTitleDraft: ""
                        property string viewMode: "cards"
                        property string financeSubTab: "transactions"

                        readonly property var activeCollectionMeta: {
                            const cid = String(root.nexus?.activeCollection ?? "movies").toLowerCase();
                            if (cid === "tvseries" || cid === "tv")
                                return { "id": "tvseries", "title": "TV-Series Tracker", "icon": "live_tv", "accent": "#ff9e64", "placeholder": "New TV series title...", "groupIndex": "02", "groupKicker": "TV SERIES", "groupSub": "EPISODIC STORIES" };
                            if (cid === "games")
                                return { "id": "games", "title": "Games Library", "icon": "sports_esports", "accent": "#73daca", "placeholder": "New game title...", "groupIndex": "01", "groupKicker": "GAMES", "groupSub": "PLAYED & BACKLOG" };
                            if (cid === "books")
                                return { "id": "books", "title": "Books & Reading Library", "icon": "menu_book", "accent": "#c0caf5", "placeholder": "New book title...", "groupIndex": "01", "groupKicker": "BOOKS", "groupSub": "READING ARCHIVE" };
                            if (cid === "recipes")
                                return { "id": "recipes", "title": "Cooking & Recipes", "icon": "restaurant", "accent": "#e0af68", "placeholder": "New recipe title...", "groupIndex": "01", "groupKicker": "FOOD & DRINKS", "groupSub": "RECIPE CARDS" };
                            if (cid === "exercises")
                                return { "id": "exercises", "title": "Gym & Calisthenics Exercises", "icon": "fitness_center", "accent": "#9ece6a", "placeholder": "New exercise title...", "groupIndex": "01", "groupKicker": "BODYBUILDING", "groupSub": "EXERCISE ATLAS" };
                            if (cid === "places")
                                return { "id": "places", "title": "Places & Coordinates", "icon": "place", "accent": String(settledColors.colTertiary ?? settledColors.colPrimary), "placeholder": "New place title...", "groupIndex": "01", "groupKicker": "PLACES", "groupSub": "VISITED & SAVED" };
                            if (cid === "contacts")
                                return { "id": "contacts", "title": "Contact Tracker", "icon": "contacts", "accent": "#f2cdcd", "placeholder": "New contact name...", "groupIndex": "01", "groupKicker": "CONTACTS", "groupSub": "PEOPLE DIRECTORY" };
                            if (cid === "websites")
                                return { "id": "websites", "title": "Onion Web-Sites Directory", "icon": "language", "accent": "#2ac3de", "placeholder": "New website entry...", "groupIndex": "01", "groupKicker": "WEB-SITES", "groupSub": "CURATED LINKS" };
                            if (cid === "cornell")
                                return { "id": "cornell", "title": "Cornell Study Notes", "icon": "school", "accent": "#e0af68", "placeholder": "New Cornell study note...", "groupIndex": "01", "groupKicker": "CORNELL", "groupSub": "STUDY NOTES" };
                            if (cid === "zettelkasten")
                                return { "id": "zettelkasten", "title": "Zettelkasten Knowledge Cards", "icon": "psychology", "accent": "#9ece6a", "placeholder": "New Zettelkasten note...", "groupIndex": "01", "groupKicker": "ZETTELKASTEN", "groupSub": "ATOMIC NOTES" };
                            if (cid === "finance")
                                return { "id": "finance", "title": "Finance & Ledger", "icon": "account_balance_wallet", "accent": "#7dcfff", "placeholder": "New finance note...", "groupIndex": "01", "groupKicker": "FINANCE", "groupSub": "LEDGER" };
                            if (cid === "clippings")
                                return { "id": "clippings", "title": "Web Clippings Archive", "icon": "bookmark", "accent": "#a6adc8", "placeholder": "New clipping title...", "groupIndex": "01", "groupKicker": "CLIPPINGS", "groupSub": "WEB ARCHIVE" };
                            return { "id": "movies", "title": "Movies Tracker", "icon": "movie", "accent": "#80b8c8", "placeholder": "New movie title...", "groupIndex": "01", "groupKicker": "MOVIES", "groupSub": "FEATURE FILMS" };
                        }

                        readonly property var filteredCollectionItems: {
                            const cid = String(root.nexus?.activeCollection ?? "movies").toLowerCase();
                            const all = root.nexus?.collections?.[cid] ?? (cid === "tvseries" ? (root.nexus?.collections?.tvSeries ?? []) : []);
                            const q = String(root.nexus?.collectionFilterQuery ?? "").trim().toLowerCase();
                            if (!q)
                                return all;
                            const out = [];
                            for (let i = 0; i < all.length; ++i) {
                                const it = all[i];
                                const hay = (
                                    String(it.title ?? "") + " " +
                                    String(it.genre ?? "") + " " +
                                    String(it.director ?? "") + " " +
                                    String(it.actors ?? "") + " " +
                                    String(it.category ?? "") + " " +
                                    String(it.muscleGroup ?? "") + " " +
                                    String(it.secondaryMuscles ?? "") + " " +
                                    String(it.equipment ?? "") + " " +
                                    String(it.level ?? "") + " " +
                                    String(it.force ?? "") + " " +
                                    String(it.mechanic ?? "") + " " +
                                    String(it.plot ?? "") + " " +
                                    String(it.status ?? "") + " " +
                                    String(it.location ?? "") + " " +
                                    String(it.url ?? "")
                                ).toLowerCase();
                                if (hay.indexOf(q) !== -1)
                                    out.push(it);
                            }
                            return out;
                        }

                        function _placeCoordinates(item): string {
                            if (!item || item.hasCoordinates === false)
                                return "";
                            const lat = item.lat ?? item.latitude;
                            const lon = item.lon ?? item.longitude;
                            if (lat === null || lat === undefined || lon === null || lon === undefined
                                    || String(lat).trim() === "" || String(lon).trim() === ""
                                    || !Number.isFinite(Number(lat)) || !Number.isFinite(Number(lon)))
                                return "";
                            return String(lat) + ", " + String(lon);
                        }

                        function _starsForScore(rawScore): string {
                            const num = parseFloat(String(rawScore ?? "0").replace(/[^0-9.]/g, ""));
                            if (!Number.isFinite(num) || num <= 0)
                                return "☆☆☆☆☆";
                            const five = num > 5.0 ? Math.round(num / 2.0) : Math.round(num);
                            const clamped = Math.max(1, Math.min(5, five));
                            return "★".repeat(clamped) + "☆".repeat(5 - clamped);
                        }

                        // Top Collection Switcher Tabs
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            MaterialSymbol {
                                text: collectionViewRoot.activeCollectionMeta.icon
                                iconSize: 22
                                color: collectionViewRoot.activeCollectionMeta.accent
                            }

                            StyledText {
                                text: collectionViewRoot.activeCollectionMeta.title
                                font.pixelSize: 20
                                font.weight: Font.Bold
                                color: settledColors.colOnLayer1
                            }

                            Rectangle {
                                height: 22
                                width: activeCollCountLabel.implicitWidth + 14
                                radius: 11
                                color: settledColors.colLayer0
                                border.width: 1
                                border.color: collectionViewRoot.activeCollectionMeta.accent

                                StyledText {
                                    id: activeCollCountLabel
                                    anchors.centerIn: parent
                                    text: String(collectionViewRoot.filteredCollectionItems.length) + " entries"
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    font.weight: Font.Bold
                                    color: collectionViewRoot.activeCollectionMeta.accent
                                }
                            }

                            Flickable {
                                id: collectionTabsFlickable
                                objectName: "nexusCollectionTabsFlickable"
                                Layout.fillWidth: true
                                Layout.preferredHeight: 28
                                clip: true
                                boundsBehavior: Flickable.StopAtBounds
                                flickableDirection: Flickable.HorizontalFlick
                                contentWidth: collectionTabsRow.implicitWidth
                                contentHeight: height

                                WheelHandler {
                                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                                    onWheel: event => {
                                        if (collectionTabsFlickable.contentWidth <= collectionTabsFlickable.width)
                                            return;
                                        const delta = Math.abs(event.angleDelta.x) > Math.abs(event.angleDelta.y)
                                            ? event.angleDelta.x
                                            : event.angleDelta.y;
                                        const maxX = Math.max(0, collectionTabsFlickable.contentWidth - collectionTabsFlickable.width);
                                        collectionTabsFlickable.contentX = Math.max(0, Math.min(maxX, collectionTabsFlickable.contentX - delta * 0.6));
                                        event.accepted = true;
                                    }
                                }

                                Row {
                                    id: collectionTabsRow
                                    objectName: "nexusCollectionTabsRow"
                                    x: Math.max(0, collectionTabsFlickable.width - implicitWidth)
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 4

                                    Repeater {
                                        model: [
                                            { "id": "movies", "label": "Movies", "accent": "#80b8c8" },
                                            { "id": "tvseries", "label": "TV-Series", "accent": "#ff9e64" },
                                            { "id": "games", "label": "Games", "accent": "#73daca" },
                                            { "id": "books", "label": "Books", "accent": "#c0caf5" },
                                            { "id": "recipes", "label": "Recipes", "accent": "#e0af68" },
                                            { "id": "exercises", "label": "Exercises", "accent": "#9ece6a" },
                                            { "id": "places", "label": "Places", "accent": String(settledColors.colTertiary ?? settledColors.colPrimary) },
                                            { "id": "contacts", "label": "Contacts", "accent": "#f2cdcd" },
                                            { "id": "websites", "label": "Web-Sites", "accent": "#2ac3de" },
                                            { "id": "cornell", "label": "Cornell", "accent": "#e0af68" },
                                            { "id": "zettelkasten", "label": "ZK", "accent": "#9ece6a" },
                                            { "id": "finance", "label": "Finance", "accent": "#7dcfff" },
                                            { "id": "clippings", "label": "Clippings", "accent": "#a6adc8" }
                                        ]
                                        delegate: Rectangle {
                                            id: collTabDelegate
                                            required property var modelData
                                            objectName: "nexusCollectionTab_" + modelData.id
                                            readonly property bool isCurrent: String(root.nexus?.activeCollection ?? "movies").toLowerCase() === modelData.id
                                            height: 24
                                            width: collTabText.implicitWidth + 12
                                            radius: 6
                                            color: isCurrent ? settledColors.colSecondaryContainer : settledColors.colLayer0
                                            border.width: 1
                                            border.color: isCurrent ? modelData.accent : settledColors.colLayer0Border

                                            onIsCurrentChanged: {
                                                if (isCurrent && collectionTabsFlickable.contentWidth > collectionTabsFlickable.width) {
                                                    const leftEdge = collTabDelegate.x;
                                                    const rightEdge = leftEdge + collTabDelegate.width;
                                                    const maxX = Math.max(0, collectionTabsFlickable.contentWidth - collectionTabsFlickable.width);
                                                    if (leftEdge < collectionTabsFlickable.contentX)
                                                        collectionTabsFlickable.contentX = Math.max(0, leftEdge - 8);
                                                    else if (rightEdge > collectionTabsFlickable.contentX + collectionTabsFlickable.width)
                                                        collectionTabsFlickable.contentX = Math.min(maxX, rightEdge - collectionTabsFlickable.width + 8);
                                                }
                                            }

                                            StyledText {
                                                id: collTabText
                                                anchors.centerIn: parent
                                                text: modelData.label
                                                font.pixelSize: Appearance.font.pixelSize.smallest
                                                font.weight: isCurrent ? Font.Bold : Font.Normal
                                                color: isCurrent ? modelData.accent : settledColors.colSubtext
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    if (root.nexus)
                                                        root.nexus.openCollection(modelData.id);
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Filter & Quick Create Bar
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 32
                                radius: 8
                                color: settledColors.colLayer0
                                border.width: 1
                                border.color: settledColors.colLayer0Border

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    spacing: 6

                                    MaterialSymbol {
                                        text: "filter_list"
                                        iconSize: 16
                                        color: settledColors.colSubtext
                                    }

                                    TextInput {
                                        id: nexusCollectionFilterField
                                        objectName: "nexusCollectionFilterField"
                                        Layout.fillWidth: true
                                        color: settledColors.colOnLayer1
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        selectByMouse: true
                                        text: String(root.nexus?.collectionFilterQuery ?? "")
                                        onTextEdited: {
                                            if (root.nexus)
                                                root.nexus.collectionFilterQuery = text;
                                        }
                                        Keys.onEscapePressed: event => {
                                            nexusCollectionFilterField.focus = false;
                                            root.restoreWorkspaceFocus();
                                            Qt.callLater(root.restoreWorkspaceFocus);
                                            event.accepted = true;
                                        }
                                        Keys.onPressed: event => {
                                            if ((event.modifiers & (Qt.AltModifier | Qt.ControlModifier | Qt.MetaModifier)) !== 0
                                                && root.nexus && root.nexus.handleKeyEvent(event)) {
                                                event.accepted = true;
                                            }
                                        }

                                        StyledText {
                                            anchors.verticalCenter: parent.verticalCenter
                                            visible: !parent.text
                                            text: "Filter by title, muscle, equipment, genre, director, cast, or category..."
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                            color: settledColors.colSubtext
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                Layout.preferredWidth: 210
                                Layout.preferredHeight: 32
                                radius: 8
                                color: settledColors.colLayer0
                                border.width: 1
                                border.color: settledColors.colLayer0Border

                                TextInput {
                                    id: newCollectionEntryInput
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    verticalAlignment: TextInput.AlignVCenter
                                    color: settledColors.colOnLayer1
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    selectByMouse: true
                                    onTextChanged: collectionViewRoot.newEntryTitleDraft = text
                                    onAccepted: {
                                        if (root.nexus && text.trim().length > 0) {
                                            root.nexus.createCollectionEntry(root.nexus.activeCollection, text.trim());
                                            text = "";
                                            newCollectionEntryInput.focus = false;
                                            root.restoreWorkspaceFocus();
                                            Qt.callLater(root.restoreWorkspaceFocus);
                                        }
                                    }
                                    Keys.onEscapePressed: event => {
                                        newCollectionEntryInput.focus = false;
                                        root.restoreWorkspaceFocus();
                                        Qt.callLater(root.restoreWorkspaceFocus);
                                        event.accepted = true;
                                    }
                                    Keys.onPressed: event => {
                                        if ((event.modifiers & (Qt.AltModifier | Qt.ControlModifier | Qt.MetaModifier)) !== 0
                                            && root.nexus && root.nexus.handleKeyEvent(event)) {
                                            event.accepted = true;
                                        }
                                    }

                                    StyledText {
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: !parent.text
                                        text: collectionViewRoot.activeCollectionMeta.placeholder
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: settledColors.colSubtext
                                    }
                                }
                            }

                            Rectangle {
                                id: nexusNewCollectionEntryButton
                                objectName: "nexusNewCollectionEntryButton"
                                Layout.preferredWidth: addEntryBtnRow.implicitWidth + 20
                                Layout.preferredHeight: 32
                                radius: 8
                                color: settledColors.colPrimary

                                RowLayout {
                                    id: addEntryBtnRow
                                    anchors.centerIn: parent
                                    spacing: 4
                                    MaterialSymbol {
                                        text: "add"
                                        iconSize: 16
                                        color: settledColors.colOnPrimary
                                    }
                                    StyledText {
                                        text: "Add Entry"
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        font.weight: Font.Bold
                                        color: settledColors.colOnPrimary
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (!root.nexus)
                                            return;
                                        const draft = newCollectionEntryInput.text.trim();
                                        const isApi = root.nexus.isApiBackedKind(root.nexus.activeCollection);
                                        if (!isApi && draft.length > 0) {
                                            root.nexus.createCollectionEntry(root.nexus.activeCollection, draft);
                                            newCollectionEntryInput.text = "";
                                            return;
                                        }
                                        root.nexus.openNewNoteModal(root.nexus.activeCollection, "");
                                        if (draft.length > 0 && typeof newNoteApiSearchInput !== "undefined") {
                                            newNoteApiSearchInput.text = draft;
                                            newCollectionEntryInput.text = "";
                                            if (root.nexus.isApiBackedKind(root.nexus.newNoteModalKind) && draft.length >= 2)
                                                root.nexus.searchExternalApi(root.nexus.newNoteModalKind, draft);
                                        }
                                    }
                                }
                            }
                        }

                        // Obsidian Media_Tracker / Bases Section Banner Header ([01] [ MOVIES · FEATURE FILMS ] ───────• + Cards/Table Switcher)
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            Rectangle {
                                width: 34
                                height: 28
                                radius: 6
                                color: Qt.color(root.ccStop(1))
                                border.width: 1
                                border.color: settledColors.colLayer0Border
                                StyledText {
                                    anchors.centerIn: parent
                                    text: collectionViewRoot.activeCollectionMeta.groupIndex
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: 11
                                    font.weight: Font.Bold
                                    color: settledColors.colPrimary
                                }
                            }

                            Rectangle {
                                height: 28
                                implicitWidth: bannerKickerRow.implicitWidth + 24
                                radius: 6
                                color: Qt.color(root.ccStop(1))
                                border.width: 1
                                border.color: settledColors.colLayer0Border

                                RowLayout {
                                    id: bannerKickerRow
                                    anchors.centerIn: parent
                                    spacing: 10

                                    StyledText {
                                        text: collectionViewRoot.activeCollectionMeta.groupKicker
                                        font.pixelSize: 12
                                        font.weight: Font.Black
                                        font.letterSpacing: 2.2
                                        color: settledColors.colOnLayer0
                                    }

                                    Rectangle {
                                        width: 1
                                        height: 12
                                        color: settledColors.colLayer0Border
                                    }

                                    StyledText {
                                        text: collectionViewRoot.activeCollectionMeta.groupSub
                                        font.family: Appearance.font.family.monospace
                                        font.pixelSize: 9
                                        font.letterSpacing: 1.8
                                        color: settledColors.colPrimary
                                    }
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                height: 1
                                color: settledColors.colLayer0Border
                            }

                            // Finance.base sub-view tabs (`Transactions | Accounts | Subscription`)
                            RowLayout {
                                visible: collectionViewRoot.activeCollectionMeta.id === "finance"
                                spacing: 4
                                Repeater {
                                    model: [
                                        { "id": "transactions", "label": "Transactions" },
                                        { "id": "accounts", "label": "Accounts" },
                                        { "id": "subscriptions", "label": "Subscription" }
                                    ]
                                    delegate: Rectangle {
                                        required property var modelData
                                        readonly property bool active: collectionViewRoot.financeSubTab === modelData.id
                                        height: 24
                                        width: finSubTxt.implicitWidth + 14
                                        radius: 5
                                        color: active ? settledColors.colSecondaryContainer : settledColors.colLayer0
                                        border.width: 1
                                        border.color: active ? settledColors.colPrimary : settledColors.colLayer0Border
                                        StyledText {
                                            id: finSubTxt
                                            anchors.centerIn: parent
                                            text: modelData.label
                                            font.family: Appearance.font.family.monospace
                                            font.pixelSize: 10
                                            font.weight: active ? Font.Bold : Font.Normal
                                            color: active ? settledColors.colPrimary : settledColors.colSubtext
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: collectionViewRoot.financeSubTab = modelData.id
                                        }
                                    }
                                }
                            }

                            // Bases View Mode Switcher (`Cards | Table`)
                            RowLayout {
                                spacing: 4
                                Repeater {
                                    model: [
                                        { "id": "cards", "label": "Cards", "icon": "grid_view" },
                                        { "id": "table", "label": "Table", "icon": "table_rows" }
                                    ]
                                    delegate: Rectangle {
                                        required property var modelData
                                        objectName: "nexusBasesViewMode_" + modelData.id
                                        readonly property bool active: collectionViewRoot.viewMode === modelData.id
                                        height: 24
                                        width: viewModeRow.implicitWidth + 12
                                        radius: 5
                                        color: active ? settledColors.colSecondaryContainer : settledColors.colLayer0
                                        border.width: 1
                                        border.color: active ? settledColors.colPrimary : settledColors.colLayer0Border
                                        RowLayout {
                                            id: viewModeRow
                                            anchors.centerIn: parent
                                            spacing: 4
                                            MaterialSymbol {
                                                text: modelData.icon
                                                iconSize: 12
                                                color: active ? settledColors.colPrimary : settledColors.colSubtext
                                            }
                                            StyledText {
                                                text: modelData.label
                                                font.family: Appearance.font.family.monospace
                                                font.pixelSize: 10
                                                font.weight: active ? Font.Bold : Font.Normal
                                                color: active ? settledColors.colPrimary : settledColors.colSubtext
                                            }
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: collectionViewRoot.viewMode = modelData.id
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                width: 7
                                height: 7
                                radius: 3.5
                                color: settledColors.colPrimary
                            }
                        }

                        // Collection / Bases Cards Grid (Virtualized GridView for zero-freeze rendering on 873+ Exercise notes)
                        GridView {
                            id: collectionCardsGrid
                            objectName: "nexusCollectionCardsGrid"
                            visible: collectionViewRoot.viewMode === "cards"
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            cacheBuffer: 480
                            readonly property string activeKind: String(root.nexus?.activeCollection ?? "movies").toLowerCase()
                            readonly property bool isPortraitDeck: activeKind === "movies" || activeKind === "tvseries" || activeKind === "games" || activeKind === "books" || activeKind === "recipes" || activeKind === "exercises" || activeKind === "places"
                            readonly property int columns: isPortraitDeck
                                ? Math.max(2, Math.floor(Math.max(320, width) / 228))
                                : Math.max(2, Math.floor(Math.max(320, width) / 260))
                            readonly property int cardHeight: activeKind === "movies" ? 352
                                : (activeKind === "tvseries" ? 336
                                : (activeKind === "games" ? 324
                                : (activeKind === "books" ? 326
                                : (activeKind === "recipes" ? 324
                                : (activeKind === "exercises" ? 268
                                : (activeKind === "places" ? 268 : 168))))))
                            cellWidth: Math.floor(Math.max(320, width) / columns)
                            cellHeight: cardHeight + 14

                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.RightButton
                                z: -1
                                onClicked: mouse => {
                                    const pt = mapToItem(root, mouse.x, mouse.y);
                                    root.openContextMenu(pt.x, pt.y, {
                                        "type": "workspace",
                                        "title": collectionViewRoot.activeCollectionMeta.title
                                    });
                                }
                            }

                            model: (collectionViewRoot.visible && collectionViewRoot.viewMode === "cards")
                                ? collectionViewRoot.filteredCollectionItems
                                : []

                            delegate: Item {
                                id: baseCardCell
                                required property var modelData
                                required property int index
                                width: collectionCardsGrid.cellWidth
                                height: collectionCardsGrid.cellHeight

                                Item {
                                    id: baseCardDelegate
                                    readonly property var modelData: baseCardCell.modelData
                                    readonly property int index: baseCardCell.index
                                    objectName: "nexusBaseCard_" + String(index)
                                    readonly property string cid: collectionCardsGrid.activeKind
                                    readonly property bool isMovieCard: cid === "movies" || modelData.kind === "movie"
                                    readonly property bool isTvCard: cid === "tvseries" || modelData.kind === "tvseries" || modelData.kind === "tv"
                                    readonly property bool isGameCard: cid === "games" || modelData.kind === "game"
                                    readonly property bool isBookCard: cid === "books" || modelData.kind === "book"
                                    readonly property bool isRecipeCard: cid === "recipes" || modelData.kind === "recipe"
                                    readonly property bool isExerciseCard: cid === "exercises" || modelData.kind === "exercise"
                                    readonly property bool isPlaceCard: cid === "places" || modelData.kind === "place"
                                    property bool flipped: false
                                    readonly property bool showBack: flipped || baseCardHover.hovered
                                    width: Math.max(120, parent.width - 14)
                                    height: collectionCardsGrid.cardHeight
                                    anchors.left: parent.left
                                    anchors.top: parent.top

                                    HoverHandler {
                                        id: baseCardHover
                                    }

                                        // ── 1. MOVIES: "CINEMA TICKET" CARD (Darker Alis Auto-Themed Surface + Concave Keyline Frame + Stub) ──
                                        Rectangle {
                                            id: cinemaTicketCard
                                            objectName: "nexusCinemaTicketCard_" + String(baseCardDelegate.index)
                                            visible: baseCardDelegate.isMovieCard
                                            anchors.fill: parent
                                            radius: 0
                                            readonly property color outerCanvasBg: Qt.color(root.ccStop(0))
                                            readonly property color ticketBg: Qt.darker(Qt.color(root.ccStop(1)), 1.28)
                                            readonly property color ticketInnerBg: Qt.darker(Qt.color(root.ccStop(0)), 1.35)
                                            readonly property color ticketAccent: settledColors.colPrimary
                                            readonly property color ticketKeyline: baseCardHover.hovered ? Qt.alpha(ticketAccent, 0.72) : Qt.alpha(ticketAccent, 0.42)
                                            readonly property color ticketStubBg: Qt.tint(Qt.darker(Qt.color(root.ccStop(2)), 1.18), Qt.alpha(ticketAccent, 0.22))
                                            readonly property color ticketStubInk: settledColors.colOnLayer1
                                            color: ticketBg
                                            border.width: 0
                                            clip: true

                                            // FRONT FACE: Auto-Themed "CINEMA TICKET" Header (below top notch) + Keyline Poster Frame + Dark Auto-Themed Barcode Stub
                                            Item {
                                                id: movieFrontFace
                                                anchors.fill: parent
                                                visible: !baseCardDelegate.showBack

                                                StyledText {
                                                    anchors.top: parent.top
                                                    anchors.topMargin: 21
                                                    anchors.horizontalCenter: parent.horizontalCenter
                                                    text: "CINEMA TICKET"
                                                    font.pixelSize: 12
                                                    font.weight: Font.Bold
                                                    font.letterSpacing: 2.8
                                                    color: cinemaTicketCard.ticketAccent
                                                    z: 4
                                                }

                                                Rectangle {
                                                    anchors.top: parent.top
                                                    anchors.topMargin: 39
                                                    anchors.left: parent.left
                                                    anchors.right: parent.right
                                                    anchors.leftMargin: 10
                                                    anchors.rightMargin: 10
                                                    height: 1
                                                    color: cinemaTicketCard.ticketKeyline
                                                    z: 4
                                                }

                                                // Inner Keyline Poster Frame (`margin: 44px 14px 8px`)
                                                Rectangle {
                                                    id: frontPosterFrame
                                                    anchors.top: parent.top
                                                    anchors.topMargin: 44
                                                    anchors.left: parent.left
                                                    anchors.right: parent.right
                                                    anchors.bottom: frontTicketStub.top
                                                    anchors.leftMargin: 14
                                                    anchors.rightMargin: 14
                                                    anchors.bottomMargin: 8
                                                    color: cinemaTicketCard.ticketInnerBg
                                                    border.width: 1
                                                    border.color: cinemaTicketCard.ticketKeyline
                                                    clip: true

                                                    Image {
                                                        id: moviePosterImg
                                                        anchors.fill: parent
                                                        anchors.margins: 1
                                                        source: String(baseCardDelegate.modelData.posterUrl ?? "")
                                                        fillMode: Image.PreserveAspectCrop
                                                        asynchronous: true
                                                        visible: Boolean(baseCardDelegate.modelData.posterUrl) && status === Image.Ready
                                                    }

                                                    ColumnLayout {
                                                        anchors.centerIn: parent
                                                        visible: !moviePosterImg.visible
                                                        spacing: 6
                                                        MaterialSymbol {
                                                            Layout.alignment: Qt.AlignHCenter
                                                            text: "movie"
                                                            iconSize: 34
                                                            color: cinemaTicketCard.ticketAccent
                                                        }
                                                        StyledText {
                                                            Layout.alignment: Qt.AlignHCenter
                                                            Layout.maximumWidth: 150
                                                            horizontalAlignment: Text.AlignHCenter
                                                            text: String(baseCardDelegate.modelData.title ?? "")
                                                            font.pixelSize: 12
                                                            font.weight: Font.Bold
                                                            color: settledColors.colOnLayer1
                                                            wrapMode: Text.WordWrap
                                                        }
                                                    }
                                                }

                                                // Full-Width Bottom Dark Auto-Themed Ticket Stub with Left-Aligned Barcode/ID + 90deg Rotated Status
                                                Rectangle {
                                                    id: frontTicketStub
                                                    anchors.left: parent.left
                                                    anchors.right: parent.right
                                                    anchors.bottom: parent.bottom
                                                    height: 52
                                                    color: cinemaTicketCard.ticketStubBg
                                                    clip: true

                                                    Rectangle {
                                                        anchors.top: parent.top
                                                        anchors.left: parent.left
                                                        anchors.right: parent.right
                                                        height: 1
                                                        color: cinemaTicketCard.ticketKeyline
                                                    }

                                                    RowLayout {
                                                        anchors.fill: parent
                                                        anchors.leftMargin: 14
                                                        anchors.rightMargin: 12
                                                        spacing: 6

                                                        // Left-Aligned Simulated Code-128 Barcode + numeric IDs (`imdbId-id`)
                                                        ColumnLayout {
                                                            Layout.fillWidth: true
                                                            Layout.fillHeight: true
                                                            spacing: 2

                                                            Row {
                                                                Layout.alignment: Qt.AlignLeft
                                                                Layout.topMargin: 6
                                                                spacing: 1.5
                                                                Repeater {
                                                                    model: [2, 1, 3, 1, 2, 1, 4, 1, 2, 2, 1, 3, 1, 2, 1, 3, 2, 1, 2, 3, 1, 2, 1, 2, 3, 1, 2]
                                                                    delegate: Rectangle {
                                                                        required property int modelData
                                                                        width: modelData
                                                                        height: 24
                                                                        color: Qt.alpha(cinemaTicketCard.ticketAccent, 0.88)
                                                                    }
                                                                }
                                                            }

                                                            StyledText {
                                                                Layout.alignment: Qt.AlignLeft
                                                                text: {
                                                                    const imdb = String(baseCardDelegate.modelData.imdbId || "tt0816711");
                                                                    const tmdb = String(baseCardDelegate.modelData.tmdbId || baseCardDelegate.modelData.year || "72190");
                                                                    return imdb + "-" + tmdb;
                                                                }
                                                                font.family: Appearance.font.family.monospace
                                                                font.pixelSize: 8
                                                                font.letterSpacing: 1.4
                                                                color: settledColors.colSubtext
                                                            }
                                                        }

                                                        // Vertical Rotated Status ("FINISHED" / "QUEUE")
                                                        Item {
                                                            Layout.preferredWidth: 24
                                                            Layout.fillHeight: true
                                                            StyledText {
                                                                anchors.centerIn: parent
                                                                rotation: 90
                                                                text: {
                                                                    const st = String(baseCardDelegate.modelData.status ?? "").toLowerCase();
                                                                    return (st === "watched" || st === "completed" || st === "finished" || st === "done") ? "FINISHED" : "QUEUE";
                                                                }
                                                                font.family: Appearance.font.family.monospace
                                                                font.pixelSize: 9
                                                                font.weight: Font.Black
                                                                font.letterSpacing: 1.5
                                                                color: cinemaTicketCard.ticketAccent
                                                            }
                                                        }
                                                    }
                                                }
                                            }

                                            // BACK FACE: Detailed Movie Dossier (Auto-Themed Labels, Monospace Values, Dashed Dividers, Dark Stub)
                                            Item {
                                                id: movieBackFace
                                                objectName: "nexusCinemaTicketBack_" + String(baseCardDelegate.index)
                                                anchors.fill: parent
                                                visible: baseCardDelegate.showBack

                                                ColumnLayout {
                                                    anchors.top: parent.top
                                                    anchors.topMargin: 22
                                                    anchors.left: parent.left
                                                    anchors.right: parent.right
                                                    anchors.bottom: movieBackStub.top
                                                    anchors.leftMargin: 18
                                                    anchors.rightMargin: 18
                                                    anchors.bottomMargin: 10
                                                    spacing: 3

                                                    Repeater {
                                                        model: [
                                                            { "k": "TITLE", "v": String(baseCardDelegate.modelData.title ?? ""), "bold": true },
                                                            { "k": "GENRE", "v": String(baseCardDelegate.modelData.genre || "Feature Film"), "bold": false },
                                                            { "k": "RUNTIME", "v": String(baseCardDelegate.modelData.runtime || "—"), "bold": false },
                                                            { "k": "YEAR", "v": String(baseCardDelegate.modelData.year || "—"), "bold": false },
                                                            { "k": "RELEASE", "v": String(baseCardDelegate.modelData.releaseDate || baseCardDelegate.modelData.released || baseCardDelegate.modelData.year || "—"), "bold": false },
                                                            { "k": "DIRECTOR", "v": String(baseCardDelegate.modelData.director || "—"), "bold": false },
                                                            { "k": "CAST", "v": String(baseCardDelegate.modelData.actors || "—"), "bold": false }
                                                        ]
                                                        delegate: ColumnLayout {
                                                            required property var modelData
                                                            Layout.fillWidth: true
                                                            spacing: 2
                                                            RowLayout {
                                                                Layout.fillWidth: true
                                                                spacing: 6
                                                                StyledText {
                                                                    Layout.preferredWidth: 58
                                                                    text: modelData.k
                                                                    font.family: Appearance.font.family.monospace
                                                                    font.pixelSize: 9
                                                                    font.weight: Font.Bold
                                                                    color: cinemaTicketCard.ticketAccent
                                                                }
                                                                StyledText {
                                                                    Layout.fillWidth: true
                                                                    horizontalAlignment: Text.AlignLeft
                                                                    text: modelData.v
                                                                    font.family: Appearance.font.family.monospace
                                                                    font.pixelSize: 9
                                                                    font.weight: modelData.bold ? Font.Bold : Font.Normal
                                                                    color: modelData.bold ? settledColors.colOnLayer0 : settledColors.colOnLayer1
                                                                    elide: Text.ElideRight
                                                                }
                                                            }
                                                            // Dashed horizontal row divider
                                                            Row {
                                                                Layout.fillWidth: true
                                                                spacing: 3
                                                                Repeater {
                                                                    model: 28
                                                                    delegate: Rectangle {
                                                                        width: 4
                                                                        height: 1
                                                                        color: Qt.alpha(cinemaTicketCard.ticketAccent, 0.20)
                                                                    }
                                                                }
                                                            }
                                                        }
                                                    }

                                                    StyledText {
                                                        Layout.fillWidth: true
                                                        Layout.fillHeight: true
                                                        Layout.topMargin: 2
                                                        text: String(baseCardDelegate.modelData.plot || "Click to open movie note...")
                                                        font.family: Appearance.font.family.monospace
                                                        font.pixelSize: 9
                                                        color: settledColors.colSubtext
                                                        wrapMode: Text.WordWrap
                                                        elide: Text.ElideRight
                                                        maximumLineCount: 6
                                                    }
                                                }

                                                // Full-Width Bottom Dark Auto-Themed Ticket Stub with ★★★★★ Rating + Horizontal Status
                                                Rectangle {
                                                    id: movieBackStub
                                                    anchors.left: parent.left
                                                    anchors.right: parent.right
                                                    anchors.bottom: parent.bottom
                                                    height: 40
                                                    color: cinemaTicketCard.ticketStubBg

                                                    Rectangle {
                                                        anchors.top: parent.top
                                                        anchors.left: parent.left
                                                        anchors.right: parent.right
                                                        height: 1
                                                        color: cinemaTicketCard.ticketKeyline
                                                    }

                                                    RowLayout {
                                                        anchors.fill: parent
                                                        anchors.leftMargin: 14
                                                        anchors.rightMargin: 14
                                                        spacing: 6

                                                        StyledText {
                                                            Layout.fillWidth: true
                                                            text: collectionViewRoot._starsForScore(baseCardDelegate.modelData.score)
                                                            font.pixelSize: 13
                                                            font.letterSpacing: 2
                                                            color: cinemaTicketCard.ticketAccent
                                                        }

                                                        StyledText {
                                                            text: {
                                                                const st = String(baseCardDelegate.modelData.status ?? "").toLowerCase();
                                                                return (st === "watched" || st === "completed" || st === "finished" || st === "done") ? "FINISHED" : "QUEUE";
                                                            }
                                                            font.family: Appearance.font.family.monospace
                                                            font.pixelSize: 10
                                                            font.weight: Font.Black
                                                            font.letterSpacing: 1.5
                                                            color: settledColors.colOnLayer1
                                                        }
                                                    }
                                                }
                                            }

                                            // Concave corner cutouts, top/bottom semicircular notches, side perforations, and inner keyline frame with concave arcs (`02_Components.css` lines 3311-3347)
                                            Canvas {
                                                id: cinemaTicketFrameCanvas
                                                anchors.fill: parent
                                                z: 9
                                                readonly property color _keyline: cinemaTicketCard.ticketKeyline
                                                readonly property color _outerBg: cinemaTicketCard.outerCanvasBg
                                                readonly property string _themeSig: root.themeSignature
                                                on_KeylineChanged: if (visible) requestPaint()
                                                on_OuterBgChanged: if (visible) requestPaint()
                                                on_ThemeSigChanged: if (visible) requestPaint()
                                                onVisibleChanged: {
                                                    if (visible)
                                                        requestPaint();
                                                }
                                                onWidthChanged: if (visible) requestPaint()
                                                onHeightChanged: if (visible) requestPaint()
                                                onPaint: {
                                                    const ctx = getContext("2d");
                                                    ctx.clearRect(0, 0, width, height);
                                                    const w = width;
                                                    const h = height;
                                                    if (w < 40 || h < 40) return;

                                                    // 1. Inner keyline border with concave corner arcs (r=8) and top-center notch arc (r=9)
                                                    const pad = 10;
                                                    const cr = 8;
                                                    const nr = 9;
                                                    const cx = w * 0.5;
                                                    ctx.strokeStyle = cinemaTicketCard.ticketKeyline;
                                                    ctx.lineWidth = 1;
                                                    ctx.beginPath();
                                                    // Top edge: left corner arc -> top notch arc -> right corner arc
                                                    ctx.moveTo(pad + cr, pad);
                                                    ctx.lineTo(cx - nr, pad);
                                                    ctx.arc(cx, pad, nr, Math.PI, 0, true);
                                                    ctx.lineTo(w - pad - cr, pad);
                                                    ctx.arc(w - pad, pad, cr, Math.PI, Math.PI * 0.5, true);
                                                    // Right edge -> bottom-right corner arc
                                                    ctx.lineTo(w - pad, h - pad - cr);
                                                    ctx.arc(w - pad, h - pad, cr, Math.PI * 1.5, Math.PI, true);
                                                    // Bottom edge -> bottom-left corner arc
                                                    ctx.lineTo(pad + cr, h - pad);
                                                    ctx.arc(pad, h - pad, cr, 0, Math.PI * 1.5, true);
                                                    // Left edge -> top-left corner arc
                                                    ctx.lineTo(pad, pad + cr);
                                                    ctx.arc(pad, pad, cr, Math.PI * 0.5, 0, true);
                                                    ctx.stroke();

                                                    // 2. Outer concave corners (R=11), top/bottom center notches (R=9), and side perforations (r=2.3 every 13px)
                                                    ctx.fillStyle = cinemaTicketCard.outerCanvasBg;
                                                    const outerCornerR = 11;
                                                    const corners = [[0, 0], [w, 0], [w, h], [0, h]];
                                                    for (let i = 0; i < corners.length; ++i) {
                                                        ctx.beginPath();
                                                        ctx.arc(corners[i][0], corners[i][1], outerCornerR, 0, Math.PI * 2);
                                                        ctx.fill();
                                                    }
                                                    // Top-center and bottom-center notches
                                                    ctx.beginPath();
                                                    ctx.arc(cx, 0, 9, 0, Math.PI * 2);
                                                    ctx.fill();
                                                    ctx.beginPath();
                                                    ctx.arc(cx, h, 9, 0, Math.PI * 2);
                                                    ctx.fill();
                                                    // Side perforations
                                                    for (let py = 18; py < h - 16; py += 13) {
                                                        ctx.beginPath();
                                                        ctx.arc(0, py, 2.2, 0, Math.PI * 2);
                                                        ctx.fill();
                                                        ctx.beginPath();
                                                        ctx.arc(w, py, 2.2, 0, Math.PI * 2);
                                                        ctx.fill();
                                                    }
                                                }
                                            }
                                        }

                                        // ── 2. TV SERIES: FULL-BLEED COVER + FILM-STRIP SPROCKET CARD (Media_Tracker.base packed_tv + 02_Components.css) ──
                                        Rectangle {
                                            id: tvSeriesCard
                                            objectName: "nexusTvSeriesCard_" + String(baseCardDelegate.index)
                                            visible: baseCardDelegate.isTvCard && !baseCardDelegate.isMovieCard
                                            anchors.fill: parent
                                            radius: 6
                                            color: Qt.darker(Qt.color(root.ccStop(1)), 1.15)
                                            border.width: 1
                                            border.color: baseCardHover.hovered ? settledColors.colPrimary : Qt.alpha(settledColors.colPrimary, 0.25)
                                            clip: true

                                            // Front Poster: Full-bleed cover image filling 100% of the card without side bars
                                            Item {
                                                anchors.fill: parent
                                                visible: !baseCardDelegate.showBack

                                                Image {
                                                    id: tvPosterImg
                                                    objectName: "nexusTvPosterImg_" + String(baseCardDelegate.index)
                                                    anchors.fill: parent
                                                    source: String(baseCardDelegate.modelData.posterUrl ?? "")
                                                    fillMode: Image.PreserveAspectCrop
                                                    asynchronous: true
                                                    visible: Boolean(baseCardDelegate.modelData.posterUrl) && status === Image.Ready
                                                }

                                                ColumnLayout {
                                                    anchors.centerIn: parent
                                                    visible: !tvPosterImg.visible
                                                    spacing: 6
                                                    MaterialSymbol {
                                                        Layout.alignment: Qt.AlignHCenter
                                                        text: "live_tv"
                                                        iconSize: 34
                                                        color: settledColors.colPrimary
                                                    }
                                                    StyledText {
                                                        Layout.alignment: Qt.AlignHCenter
                                                        Layout.maximumWidth: 150
                                                        horizontalAlignment: Text.AlignHCenter
                                                        text: String(baseCardDelegate.modelData.title ?? "")
                                                        font.pixelSize: 12
                                                        font.weight: Font.Bold
                                                        color: settledColors.colOnLayer1
                                                        wrapMode: Text.WordWrap
                                                    }
                                                }
                                            }

                                            // Circular film-strip sprocket holes (7×7px, radius 3.5, every 22px) matching `02_Components.css` lines 3541-3579 & Screenshot 3
                                            Repeater {
                                                model: Math.max(0, Math.floor((tvSeriesCard.height - 14) / 22))
                                                delegate: Item {
                                                    required property int index
                                                    y: 11 + index * 22
                                                    width: parent.width
                                                    height: 7
                                                    z: 4
                                                    Rectangle {
                                                        x: 9.5
                                                        width: 7
                                                        height: 7
                                                        radius: 3.5
                                                        color: Qt.darker(Qt.color(root.ccStop(0)), 1.25)
                                                        border.width: 1
                                                        border.color: Qt.rgba(0, 0, 0, 0.45)
                                                    }
                                                    Rectangle {
                                                        x: parent.width - 16.5
                                                        width: 7
                                                        height: 7
                                                        radius: 3.5
                                                        color: Qt.darker(Qt.color(root.ccStop(0)), 1.25)
                                                        border.width: 1
                                                        border.color: Qt.rgba(0, 0, 0, 0.45)
                                                    }
                                                }
                                            }

                                            // Back Dossier (Matches packed_tv in Media_Tracker.base)
                                            ColumnLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 20
                                                anchors.rightMargin: 20
                                                anchors.topMargin: 10
                                                anchors.bottomMargin: 10
                                                visible: baseCardDelegate.showBack
                                                spacing: 3

                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    StyledText {
                                                        Layout.fillWidth: true
                                                        text: "TV SERIES"
                                                        font.family: Appearance.font.family.monospace
                                                        font.pixelSize: 9
                                                        font.weight: Font.Bold
                                                        font.letterSpacing: 1.8
                                                        color: settledColors.colPrimary
                                                    }
                                                    StyledText {
                                                        text: String(baseCardDelegate.modelData.status || baseCardDelegate.modelData.airingStatus || "WATCHING").toUpperCase()
                                                        font.family: Appearance.font.family.monospace
                                                        font.pixelSize: 8
                                                        font.weight: Font.Bold
                                                        color: settledColors.colSecondary
                                                    }
                                                }
                                                StyledText {
                                                    Layout.fillWidth: true
                                                    text: String(baseCardDelegate.modelData.title ?? "")
                                                    font.pixelSize: 12
                                                    font.weight: Font.Bold
                                                    color: settledColors.colOnLayer1
                                                    elide: Text.ElideRight
                                                }
                                                StyledText {
                                                    Layout.fillWidth: true
                                                    text: {
                                                        const yr = String(baseCardDelegate.modelData.year || "—");
                                                        const endYr = String(baseCardDelegate.modelData.ended || "");
                                                        const air = String(baseCardDelegate.modelData.airingStatus || baseCardDelegate.modelData.status || "Series");
                                                        return (endYr && endYr !== yr ? (yr + "–" + endYr) : yr) + " · " + air;
                                                    }
                                                    font.family: Appearance.font.family.monospace
                                                    font.pixelSize: 8
                                                    color: settledColors.colSubtext
                                                    elide: Text.ElideRight
                                                }

                                                Repeater {
                                                    model: {
                                                        const s = String(baseCardDelegate.modelData.seasons || "0");
                                                        const ep = String(baseCardDelegate.modelData.episodes || "0");
                                                        return [
                                                            { "k": "Genre:", "v": String(baseCardDelegate.modelData.genre || "—") },
                                                            { "k": "Run:", "v": s + " seasons · " + ep + " eps" },
                                                            { "k": "Episode:", "v": String(baseCardDelegate.modelData.runtime || "—") },
                                                            { "k": "Network:", "v": String(baseCardDelegate.modelData.networks || "—") },
                                                            { "k": "Creator:", "v": String(baseCardDelegate.modelData.creator || baseCardDelegate.modelData.director || "—") },
                                                            { "k": "Cast:", "v": String(baseCardDelegate.modelData.actors || "—") }
                                                        ];
                                                    }
                                                    delegate: RowLayout {
                                                        required property var modelData
                                                        Layout.fillWidth: true
                                                        spacing: 4
                                                        StyledText { text: modelData.k; font.pixelSize: 8; font.weight: Font.Bold; color: settledColors.colOnLayer1 }
                                                        StyledText { Layout.fillWidth: true; horizontalAlignment: Text.AlignRight; text: modelData.v; font.pixelSize: 8; color: settledColors.colSubtext; elide: Text.ElideRight }
                                                    }
                                                }

                                                StyledText {
                                                    Layout.fillWidth: true
                                                    Layout.fillHeight: true
                                                    text: String(baseCardDelegate.modelData.plot || "Click to open TV series dossier...")
                                                    font.pixelSize: 8
                                                    color: settledColors.colSubtext
                                                    wrapMode: Text.WordWrap
                                                    elide: Text.ElideRight
                                                    maximumLineCount: 4
                                                }

                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    StyledText {
                                                        Layout.fillWidth: true
                                                        text: collectionViewRoot._starsForScore(baseCardDelegate.modelData.score)
                                                        font.pixelSize: 11
                                                        color: settledColors.colPrimary
                                                    }
                                                    StyledText {
                                                        text: String(baseCardDelegate.modelData.onlineRating || baseCardDelegate.modelData.score || "")
                                                        font.family: Appearance.font.family.monospace
                                                        font.pixelSize: 9
                                                        font.weight: Font.Bold
                                                        color: settledColors.colSubtext
                                                    }
                                                }
                                            }
                                        }

                                        // ── 3. GAMES: ABYSSAL DOSSIER CARD (Game_Collection.base packed_game + 02_Components.css lines 621–915) ──
                                        Rectangle {
                                            id: gameBaseCard
                                            objectName: "nexusGameBaseCard_" + String(baseCardDelegate.index)
                                            visible: baseCardDelegate.isGameCard
                                            anchors.fill: parent
                                            radius: 8
                                            color: Qt.darker(Qt.color(root.ccStop(1)), 1.15)
                                            border.width: 1
                                            border.color: baseCardHover.hovered ? settledColors.colPrimary : Qt.alpha(settledColors.colPrimary, 0.25)
                                            clip: true

                                            // Face 1: Full-Bleed Cover
                                            Item {
                                                anchors.fill: parent
                                                visible: !baseCardDelegate.showBack

                                                Image {
                                                    id: gameCoverImg
                                                    anchors.fill: parent
                                                    source: String(baseCardDelegate.modelData.posterUrl ?? "")
                                                    fillMode: Image.PreserveAspectCrop
                                                    asynchronous: true
                                                    visible: Boolean(baseCardDelegate.modelData.posterUrl) && status === Image.Ready
                                                }

                                                ColumnLayout {
                                                    anchors.centerIn: parent
                                                    visible: !gameCoverImg.visible
                                                    spacing: 6
                                                    MaterialSymbol {
                                                        Layout.alignment: Qt.AlignHCenter
                                                        text: "sports_esports"
                                                        iconSize: 34
                                                        color: settledColors.colPrimary
                                                    }
                                                    StyledText {
                                                        Layout.alignment: Qt.AlignHCenter
                                                        Layout.maximumWidth: 160
                                                        horizontalAlignment: Text.AlignHCenter
                                                        text: String(baseCardDelegate.modelData.title ?? "")
                                                        font.pixelSize: 12
                                                        font.weight: Font.Bold
                                                        color: settledColors.colOnLayer1
                                                        wrapMode: Text.WordWrap
                                                    }
                                                }
                                            }

                                            // Face 2: Abyssal Dossier Back (Exact match to packed_game in Game_Collection.base + .abyssal-card in 02_Components.css lines 4219–4418)
                                            Item {
                                                anchors.fill: parent
                                                visible: baseCardDelegate.showBack

                                                // Left 2px status accent bar (`.abyssal-card` status indicator)
                                                Rectangle {
                                                    anchors.left: parent.left
                                                    anchors.top: parent.top
                                                    anchors.bottom: parent.bottom
                                                    width: 2
                                                    color: {
                                                        const st = String(baseCardDelegate.modelData.status || "").toLowerCase();
                                                        if (st === "playing" || st === "completed" || st === "finished")
                                                            return settledColors.colPrimary;
                                                        return Qt.color(root.ccStop(8));
                                                    }
                                                }

                                                // Bottom-right corner bracket (`.abyssal-card::after`)
                                                Item {
                                                    anchors.right: parent.right
                                                    anchors.bottom: parent.bottom
                                                    anchors.rightMargin: 7
                                                    anchors.bottomMargin: 7
                                                    width: 11
                                                    height: 11
                                                    Rectangle {
                                                        anchors.right: parent.right
                                                        anchors.top: parent.top
                                                        anchors.bottom: parent.bottom
                                                        width: 1
                                                        color: Qt.alpha(settledColors.colPrimary, 0.36)
                                                    }
                                                    Rectangle {
                                                        anchors.left: parent.left
                                                        anchors.right: parent.right
                                                        anchors.bottom: parent.bottom
                                                        height: 1
                                                        color: Qt.alpha(settledColors.colPrimary, 0.36)
                                                    }
                                                }

                                                ColumnLayout {
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 13
                                                    anchors.rightMargin: 12
                                                    anchors.topMargin: 11
                                                    anchors.bottomMargin: 11
                                                    spacing: 3

                                                    // Header: "GAME DOSSIER · {STORE}" + Status Pill
                                                    RowLayout {
                                                        Layout.fillWidth: true
                                                        spacing: 4
                                                        StyledText {
                                                            Layout.fillWidth: true
                                                            text: "GAME DOSSIER · " + String(baseCardDelegate.modelData.store || "LIBRARY").toUpperCase()
                                                            font.family: Appearance.font.family.monospace
                                                            font.pixelSize: 8
                                                            font.weight: Font.Bold
                                                            font.letterSpacing: 1.1
                                                            color: settledColors.colPrimary
                                                            elide: Text.ElideRight
                                                        }
                                                        Rectangle {
                                                            height: 16
                                                            width: gameStText.implicitWidth + 10
                                                            radius: 3
                                                            color: Qt.alpha(settledColors.colPrimary, 0.16)
                                                            border.width: 1
                                                            border.color: Qt.alpha(settledColors.colPrimary, 0.35)
                                                            StyledText {
                                                                id: gameStText
                                                                anchors.centerIn: parent
                                                                text: String(baseCardDelegate.modelData.status || "BACKLOG").toUpperCase()
                                                                font.family: Appearance.font.family.monospace
                                                                font.pixelSize: 7
                                                                font.weight: Font.Bold
                                                                color: settledColors.colPrimary
                                                            }
                                                        }
                                                    }

                                                    // Title + "{developer} · {year}" byline
                                                    StyledText {
                                                        Layout.fillWidth: true
                                                        text: String(baseCardDelegate.modelData.title ?? "")
                                                        font.pixelSize: 12
                                                        font.weight: Font.Bold
                                                        color: settledColors.colOnLayer0
                                                        elide: Text.ElideRight
                                                    }
                                                    StyledText {
                                                        Layout.fillWidth: true
                                                        text: {
                                                            const dev = String(baseCardDelegate.modelData.developer || "Unknown studio").trim();
                                                            const yr = String(baseCardDelegate.modelData.year || "").trim();
                                                            return yr.length > 0 ? (dev + " · " + yr) : dev;
                                                        }
                                                        font.family: Appearance.font.family.monospace
                                                        font.pixelSize: 8
                                                        color: settledColors.colSubtext
                                                        elide: Text.ElideRight
                                                    }

                                                    // 4 Metadata Rows: Platform, Genre, Publisher, Achievements (`.abyssal-card-meta`)
                                                    Repeater {
                                                        model: {
                                                            const achE = String(baseCardDelegate.modelData.achievementsEarned || "");
                                                            const achT = String(baseCardDelegate.modelData.achievementsTotal || "");
                                                            const achStr = (achE || achT) ? ((achE || "0") + " / " + (achT || "0")) : "—";
                                                            return [
                                                                { "k": "Platform", "v": String(baseCardDelegate.modelData.platform || "—") },
                                                                { "k": "Genre", "v": String(baseCardDelegate.modelData.genre || "—") },
                                                                { "k": "Publisher", "v": String(baseCardDelegate.modelData.publisher || "—") },
                                                                { "k": "Achievements", "v": achStr }
                                                            ];
                                                        }
                                                        delegate: ColumnLayout {
                                                            required property var modelData
                                                            Layout.fillWidth: true
                                                            spacing: 1
                                                            RowLayout {
                                                                Layout.fillWidth: true
                                                                StyledText {
                                                                    text: modelData.k
                                                                    font.family: Appearance.font.family.monospace
                                                                    font.pixelSize: 8
                                                                    color: settledColors.colSubtext
                                                                }
                                                                StyledText {
                                                                    Layout.fillWidth: true
                                                                    horizontalAlignment: Text.AlignRight
                                                                    text: modelData.v
                                                                    font.family: Appearance.font.family.monospace
                                                                    font.pixelSize: 8
                                                                    font.weight: Font.Bold
                                                                    color: settledColors.colOnLayer1
                                                                    elide: Text.ElideRight
                                                                }
                                                            }
                                                            Rectangle {
                                                                Layout.fillWidth: true
                                                                height: 1
                                                                color: Qt.alpha(settledColors.colLayer0Border, 0.38)
                                                            }
                                                        }
                                                    }

                                                    // Synopsis / Description (`.abyssal-card-desc`)
                                                    StyledText {
                                                        Layout.fillWidth: true
                                                        Layout.fillHeight: true
                                                        text: String(baseCardDelegate.modelData.plot || "No description logged yet.")
                                                        font.pixelSize: 8
                                                        color: settledColors.colSubtext
                                                        wrapMode: Text.WordWrap
                                                        elide: Text.ElideRight
                                                        maximumLineCount: 3
                                                    }

                                                    // Completion Progress Bar (`.abyssal-card-progress`)
                                                    ColumnLayout {
                                                        Layout.fillWidth: true
                                                        spacing: 2
                                                        readonly property int compPct: {
                                                            const n = parseFloat(String(baseCardDelegate.modelData.completion || "0").replace(/[^0-9.]/g, ""));
                                                            return Number.isFinite(n) ? Math.max(0, Math.min(100, Math.round(n))) : 0;
                                                        }
                                                        RowLayout {
                                                            Layout.fillWidth: true
                                                            StyledText {
                                                                Layout.fillWidth: true
                                                                text: "COMPLETION"
                                                                font.family: Appearance.font.family.monospace
                                                                font.pixelSize: 7
                                                                font.letterSpacing: 1.0
                                                                color: settledColors.colSubtext
                                                            }
                                                            StyledText {
                                                                text: String(parent.parent.compPct) + "%"
                                                                font.family: Appearance.font.family.monospace
                                                                font.pixelSize: 8
                                                                font.weight: Font.Bold
                                                                color: settledColors.colPrimary
                                                            }
                                                        }
                                                        Rectangle {
                                                            Layout.fillWidth: true
                                                            height: 3
                                                            radius: 1.5
                                                            color: Qt.color(root.ccStop(0))
                                                            Rectangle {
                                                                width: parent.width * (parent.parent.compPct / 100.0)
                                                                height: parent.height
                                                                radius: 1.5
                                                                color: settledColors.colPrimary
                                                            }
                                                        }
                                                    }

                                                    // Top-bordered 3-Column Footer (`.abyssal-card-foot`: Rating /10, Hours Played, Metacritic)
                                                    Rectangle {
                                                        Layout.fillWidth: true
                                                        Layout.topMargin: 2
                                                        height: 1
                                                        color: Qt.alpha(settledColors.colLayer0Border, 0.52)
                                                    }
                                                    RowLayout {
                                                        Layout.fillWidth: true
                                                        spacing: 6
                                                        Repeater {
                                                            model: [
                                                                {
                                                                    "val": (baseCardDelegate.modelData.rating || baseCardDelegate.modelData.score || "0") + "/10",
                                                                    "lbl": "RATING",
                                                                    "align": Text.AlignLeft
                                                                },
                                                                {
                                                                    "val": String(baseCardDelegate.modelData.hoursPlayed || "0") + "h",
                                                                    "lbl": "PLAYED",
                                                                    "align": Text.AlignHCenter
                                                                },
                                                                {
                                                                    "val": String(baseCardDelegate.modelData.metacritic || "—"),
                                                                    "lbl": "METACRITIC",
                                                                    "align": Text.AlignRight
                                                                }
                                                            ]
                                                            delegate: ColumnLayout {
                                                                required property var modelData
                                                                Layout.fillWidth: true
                                                                spacing: 0
                                                                StyledText {
                                                                    Layout.fillWidth: true
                                                                    horizontalAlignment: modelData.align
                                                                    text: modelData.val
                                                                    font.family: Appearance.font.family.monospace
                                                                    font.pixelSize: 9
                                                                    font.weight: Font.Bold
                                                                    color: settledColors.colPrimary
                                                                }
                                                                StyledText {
                                                                    Layout.fillWidth: true
                                                                    horizontalAlignment: modelData.align
                                                                    text: modelData.lbl
                                                                    font.family: Appearance.font.family.monospace
                                                                    font.pixelSize: 6
                                                                    font.letterSpacing: 0.9
                                                                    color: settledColors.colSubtext
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        // ── 4. BOOKS: 3D SPINE + CHEVRON BOOKMARK RIBBON + LINED NOTEBOOK BACK (Book_Tracker.base + 02_Components.css lines 1659–2498) ──
                                        Rectangle {
                                            id: bookBaseCard
                                            objectName: "nexusBookBaseCard_" + String(baseCardDelegate.index)
                                            visible: baseCardDelegate.isBookCard
                                            anchors.fill: parent
                                            radius: 5
                                            color: baseCardDelegate.showBack
                                                ? Qt.color(root.ccStop(2))
                                                : Qt.darker(Qt.color(root.ccStop(1)), 1.15)
                                            border.width: 1
                                            border.color: baseCardHover.hovered ? settledColors.colPrimary : Qt.alpha(settledColors.colLayer0Border, 0.65)
                                            clip: true

                                            // Face 1: Full-Bleed Book Cover + Smooth 0%–22% 3D Spine Lighting + Top-Left Pointed Status Ribbon
                                            Item {
                                                anchors.fill: parent
                                                visible: !baseCardDelegate.showBack

                                                Image {
                                                    id: bookCoverImg
                                                    objectName: "nexusBookCoverImg_" + String(baseCardDelegate.index)
                                                    anchors.fill: parent
                                                    source: String(baseCardDelegate.modelData.posterUrl ?? "")
                                                    fillMode: Image.PreserveAspectCrop
                                                    asynchronous: true
                                                    visible: Boolean(baseCardDelegate.modelData.posterUrl) && status === Image.Ready
                                                }

                                                ColumnLayout {
                                                    anchors.centerIn: parent
                                                    visible: !bookCoverImg.visible
                                                    spacing: 6
                                                    MaterialSymbol {
                                                        Layout.alignment: Qt.AlignHCenter
                                                        text: "menu_book"
                                                        iconSize: 34
                                                        color: settledColors.colPrimary
                                                    }
                                                    StyledText {
                                                        Layout.alignment: Qt.AlignHCenter
                                                        Layout.maximumWidth: 150
                                                        horizontalAlignment: Text.AlignHCenter
                                                        text: String(baseCardDelegate.modelData.title ?? "")
                                                        font.pixelSize: 12
                                                        font.weight: Font.Bold
                                                        color: settledColors.colOnLayer1
                                                        wrapMode: Text.WordWrap
                                                    }
                                                }

                                                // Smooth 3D Book Spine Lighting Overlay (`.bases-cards-cover::before` + `::after` in `02_Components.css` lines 1737–1827, 0%–22% width)
                                                Rectangle {
                                                    id: bookSpineOverlay
                                                    objectName: "nexusBookSpineOverlay_" + String(baseCardDelegate.index)
                                                    anchors.top: parent.top
                                                    anchors.bottom: parent.bottom
                                                    anchors.left: parent.left
                                                    width: Math.max(36, Math.round(parent.width * 0.22))
                                                    z: 3
                                                    gradient: Gradient {
                                                        orientation: Gradient.Horizontal
                                                        GradientStop { position: 0.00; color: Qt.rgba(0, 0, 0, 0.42) }
                                                        GradientStop { position: 0.05; color: Qt.rgba(1, 1, 1, 0.20) }
                                                        GradientStop { position: 0.14; color: Qt.rgba(1, 1, 1, 0.08) }
                                                        GradientStop { position: 0.24; color: Qt.rgba(0, 0, 0, 0.30) }
                                                        GradientStop { position: 0.34; color: Qt.rgba(0, 0, 0, 0.16) }
                                                        GradientStop { position: 0.42; color: Qt.rgba(1, 1, 1, 0.22) }
                                                        GradientStop { position: 0.56; color: Qt.rgba(1, 1, 1, 0.08) }
                                                        GradientStop { position: 0.76; color: Qt.rgba(0, 0, 0, 0.05) }
                                                        GradientStop { position: 1.00; color: "transparent" }
                                                    }
                                                }

                                                // Top-left Pointed Bookmark Status Ribbon (`02_Components.css` lines 2099–2158 & Screenshot 4)
                                                Item {
                                                    id: bookRibbon
                                                    objectName: "nexusBookStatusRibbon_" + String(baseCardDelegate.index)
                                                    x: 9
                                                    y: 0
                                                    width: 32
                                                    height: 84
                                                    z: 6

                                                    readonly property string statusNorm: {
                                                        const raw = String(baseCardDelegate.modelData.status || "to read").trim().toLowerCase();
                                                        if (raw === "finished" || raw === "completed" || raw === "read" || raw === "done")
                                                            return "FINISHED";
                                                        if (raw === "reading" || raw === "in progress" || raw === "current")
                                                            return "READING";
                                                        return "TO READ";
                                                    }

                                                    Canvas {
                                                        id: bookRibbonCanvas
                                                        anchors.fill: parent
                                                        readonly property string _st: bookRibbon.statusNorm
                                                        readonly property string _themeSig: root.themeSignature
                                                        on_StChanged: if (visible) requestPaint()
                                                        on_ThemeSigChanged: if (visible) requestPaint()
                                                        onVisibleChanged: {
                                                            if (visible)
                                                                requestPaint();
                                                        }
                                                        onWidthChanged: if (visible) requestPaint()
                                                        onHeightChanged: if (visible) requestPaint()
                                                        onPaint: {
                                                            const ctx = getContext("2d");
                                                            ctx.clearRect(0, 0, width, height);
                                                            const w = width;
                                                            const h = height;
                                                            const tipH = 10;

                                                            // Pointed ribbon polygon: (0,0) -> (w,0) -> (w, h-tipH) -> (w/2, h) -> (0, h-tipH)
                                                            ctx.beginPath();
                                                            ctx.moveTo(0.5, 0);
                                                            ctx.lineTo(w - 0.5, 0);
                                                            ctx.lineTo(w - 0.5, h - tipH);
                                                            ctx.lineTo(w * 0.5, h - 0.5);
                                                            ctx.lineTo(0.5, h - tipH);
                                                            ctx.closePath();

                                                            const acc = settledColors.colPrimary;
                                                            const l2 = Qt.color(root.ccStop(2));
                                                            const l3 = Qt.color(root.ccStop(3));
                                                            let topCol = l3;
                                                            let botCol = l2;
                                                            if (bookRibbon.statusNorm === "FINISHED") {
                                                                topCol = Qt.tint(l3, Qt.rgba(acc.r, acc.g, acc.b, 0.34));
                                                                botCol = Qt.tint(l2, Qt.rgba(acc.r, acc.g, acc.b, 0.22));
                                                            } else if (bookRibbon.statusNorm === "READING") {
                                                                topCol = Qt.tint(l3, Qt.rgba(acc.r, acc.g, acc.b, 0.50));
                                                                botCol = Qt.tint(l2, Qt.rgba(acc.r, acc.g, acc.b, 0.36));
                                                            } else {
                                                                topCol = Qt.darker(l3, 1.05);
                                                                botCol = Qt.darker(l2, 1.12);
                                                            }

                                                            const grad = ctx.createLinearGradient(0, 0, 0, h);
                                                            grad.addColorStop(0.0, topCol.toString());
                                                            grad.addColorStop(1.0, botCol.toString());
                                                            ctx.fillStyle = grad;
                                                            ctx.fill();

                                                            ctx.strokeStyle = Qt.rgba(acc.r, acc.g, acc.b, 0.38);
                                                            ctx.lineWidth = 1;
                                                            ctx.stroke();
                                                        }
                                                    }

                                                    StyledText {
                                                        anchors.centerIn: parent
                                                        anchors.verticalCenterOffset: -4
                                                        rotation: 90
                                                        text: bookRibbon.statusNorm
                                                        font.family: Appearance.font.family.monospace
                                                        font.pixelSize: 9
                                                        font.weight: Font.Black
                                                        font.letterSpacing: 1.5
                                                        color: bookRibbon.statusNorm === "READING"
                                                            ? settledColors.colPrimary
                                                            : settledColors.colOnLayer0
                                                    }
                                                }
                                            }

                                            // Face 2: Lined Notebook Paper Back (`.book-back` in `Book_Tracker.base` + `02_Components.css` lines 2170–2498)
                                            Item {
                                                id: bookBackFace
                                                objectName: "nexusBookBackFace_" + String(baseCardDelegate.index)
                                                anchors.fill: parent
                                                visible: baseCardDelegate.showBack

                                                // 15 horizontal ruled notebook lines (`22px` line spacing)
                                                Column {
                                                    anchors.fill: parent
                                                    anchors.topMargin: 22
                                                    spacing: 21
                                                    Repeater {
                                                        model: 15
                                                        delegate: Rectangle {
                                                            width: bookBackFace.width
                                                            height: 1
                                                            color: Qt.alpha(settledColors.colOnLayer1, 0.08)
                                                        }
                                                    }
                                                }

                                                // Left vertical margin rule line at x=34
                                                Rectangle {
                                                    x: 34
                                                    y: 0
                                                    width: 1
                                                    height: parent.height
                                                    color: Qt.alpha(settledColors.colPrimary, 0.38)
                                                }

                                                // Left margin hand-jotted symbols (`×`, `↳`, and `-14deg` `keep`) matching `02_Components.css` lines 2274–2305
                                                StyledText {
                                                    x: 12
                                                    y: 112
                                                    text: "×"
                                                    font.family: Appearance.font.family.monospace
                                                    font.pixelSize: 11
                                                    color: Qt.alpha(settledColors.colPrimary, 0.65)
                                                }
                                                StyledText {
                                                    x: 12
                                                    y: 160
                                                    text: "↳"
                                                    font.family: Appearance.font.family.monospace
                                                    font.pixelSize: 11
                                                    color: Qt.alpha(settledColors.colPrimary, 0.65)
                                                }
                                                StyledText {
                                                    x: 4
                                                    y: 224
                                                    rotation: -14
                                                    text: "keep"
                                                    font.family: Appearance.font.family.monospace
                                                    font.pixelSize: 8
                                                    font.italic: true
                                                    color: Qt.alpha(settledColors.colSubtext, 0.72)
                                                }

                                                // Top-right folded dog-ear corner (`.book-back::after`)
                                                Canvas {
                                                    id: bookDogEarCanvas
                                                    anchors.top: parent.top
                                                    anchors.right: parent.right
                                                    width: 22
                                                    height: 22
                                                    readonly property color _foldCol: Qt.color(root.ccStop(4))
                                                    readonly property string _themeSig: root.themeSignature
                                                    on_FoldColChanged: if (visible) requestPaint()
                                                    on_ThemeSigChanged: if (visible) requestPaint()
                                                    onVisibleChanged: {
                                                        if (visible)
                                                            requestPaint();
                                                    }
                                                    onPaint: {
                                                        const ctx = getContext("2d");
                                                        ctx.clearRect(0, 0, width, height);
                                                        ctx.beginPath();
                                                        ctx.moveTo(0, 0);
                                                        ctx.lineTo(width, height);
                                                        ctx.lineTo(0, height);
                                                        ctx.closePath();
                                                        ctx.fillStyle = root.ccStop(4);
                                                        ctx.fill();
                                                    }
                                                }

                                                ColumnLayout {
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 42
                                                    anchors.rightMargin: 12
                                                    anchors.topMargin: 12
                                                    anchors.bottomMargin: 12
                                                    spacing: 4

                                                    StyledText {
                                                        text: "✦ BOOK COLLECTION"
                                                        font.family: Appearance.font.family.monospace
                                                        font.pixelSize: 8
                                                        font.weight: Font.Bold
                                                        font.letterSpacing: 1.4
                                                        color: settledColors.colPrimary
                                                    }

                                                    StyledText {
                                                        Layout.fillWidth: true
                                                        text: String(baseCardDelegate.modelData.title ?? "")
                                                        font.pixelSize: 13
                                                        font.weight: Font.Bold
                                                        font.italic: true
                                                        color: settledColors.colOnLayer0
                                                        wrapMode: Text.WordWrap
                                                        maximumLineCount: 2
                                                        elide: Text.ElideRight
                                                    }

                                                    // Hand-drawn wavy underline under book title (`.book-back-title`)
                                                    Canvas {
                                                        id: bookWavyUnderline
                                                        Layout.fillWidth: true
                                                        Layout.preferredHeight: 5
                                                        readonly property color _waveCol: settledColors.colPrimary
                                                        readonly property string _themeSig: root.themeSignature
                                                        on_WaveColChanged: if (visible) requestPaint()
                                                        on_ThemeSigChanged: if (visible) requestPaint()
                                                        onVisibleChanged: {
                                                            if (visible)
                                                                requestPaint();
                                                        }
                                                        onWidthChanged: if (visible) requestPaint()
                                                        onPaint: {
                                                            const ctx = getContext("2d");
                                                            ctx.clearRect(0, 0, width, height);
                                                            ctx.strokeStyle = Qt.alpha(settledColors.colPrimary, 0.58);
                                                            ctx.lineWidth = 1.1;
                                                            ctx.beginPath();
                                                            for (let wx = 0; wx <= width; wx += 2) {
                                                                const wy = 2.5 + Math.sin(wx * 0.45) * 1.2;
                                                                if (wx === 0) ctx.moveTo(wx, wy);
                                                                else ctx.lineTo(wx, wy);
                                                            }
                                                            ctx.stroke();
                                                        }
                                                    }

                                                    StyledText {
                                                        Layout.fillWidth: true
                                                        text: "by " + String(baseCardDelegate.modelData.author || baseCardDelegate.modelData.director || "Unknown author")
                                                        font.pixelSize: 10
                                                        font.italic: true
                                                        color: settledColors.colSubtext
                                                        elide: Text.ElideRight
                                                    }

                                                    // `.book-back-genres`: GENRES label + slash-separated list (`02_Components.css` lines 2368–2398)
                                                    ColumnLayout {
                                                        Layout.fillWidth: true
                                                        Layout.topMargin: 2
                                                        spacing: 1
                                                        StyledText {
                                                            text: "GENRES"
                                                            font.family: Appearance.font.family.monospace
                                                            font.pixelSize: 7
                                                            font.letterSpacing: 1.2
                                                            color: settledColors.colSubtext
                                                        }
                                                        StyledText {
                                                            Layout.fillWidth: true
                                                            text: {
                                                                const g = String(baseCardDelegate.modelData.genre || "").split(",").map(s => s.trim()).filter(Boolean).slice(0, 3);
                                                                return g.length > 0 ? g.join(" / ") : "untagged";
                                                            }
                                                            font.pixelSize: 9
                                                            font.italic: true
                                                            color: settledColors.colOnLayer1
                                                            wrapMode: Text.WordWrap
                                                            maximumLineCount: 2
                                                            elide: Text.ElideRight
                                                        }
                                                    }

                                                    Item { Layout.fillHeight: true }

                                                    // Reading Status Row (`.book-back-status`)
                                                    RowLayout {
                                                        Layout.fillWidth: true
                                                        StyledText {
                                                            Layout.fillWidth: true
                                                            text: "Reading status"
                                                            font.pixelSize: 9
                                                            font.italic: true
                                                            color: settledColors.colSubtext
                                                        }
                                                        StyledText {
                                                            text: String(baseCardDelegate.modelData.status || "to read")
                                                            font.family: Appearance.font.family.monospace
                                                            font.pixelSize: 9
                                                            font.weight: Font.Bold
                                                            color: settledColors.colPrimary
                                                        }
                                                    }

                                                    // Hatched Book Page Progress Bar (`.book-back-progress` in `02_Components.css` lines 2423–2465)
                                                    ColumnLayout {
                                                        Layout.fillWidth: true
                                                        spacing: 2
                                                        readonly property int curPg: {
                                                            const n = parseInt(String(baseCardDelegate.modelData.currentPage || "0"), 10);
                                                            return Number.isFinite(n) ? Math.max(0, n) : 0;
                                                        }
                                                        readonly property int totPg: {
                                                            const n = parseInt(String(baseCardDelegate.modelData.pages || "0"), 10);
                                                            return Number.isFinite(n) ? Math.max(0, n) : 0;
                                                        }
                                                        readonly property int pct: {
                                                            const st = String(baseCardDelegate.modelData.status || "").toLowerCase();
                                                            if (st === "finished" || st === "completed" || st === "read" || st === "done")
                                                                return 100;
                                                            if (totPg > 0)
                                                                return Math.max(0, Math.min(100, Math.round((curPg / totPg) * 100)));
                                                            return 0;
                                                        }

                                                        Rectangle {
                                                            Layout.fillWidth: true
                                                            height: 8
                                                            radius: 2
                                                            color: Qt.color(root.ccStop(0))
                                                            border.width: 1
                                                            border.color: Qt.alpha(settledColors.colPrimary, 0.42)
                                                            clip: true

                                                            Canvas {
                                                                anchors.left: parent.left
                                                                anchors.top: parent.top
                                                                anchors.bottom: parent.bottom
                                                                width: parent.width * (parent.parent.pct / 100.0)
                                                                readonly property color _barCol: settledColors.colPrimary
                                                                readonly property string _themeSig: root.themeSignature
                                                                on_BarColChanged: if (visible) requestPaint()
                                                                on_ThemeSigChanged: if (visible) requestPaint()
                                                                onVisibleChanged: {
                                                                    if (visible)
                                                                        requestPaint();
                                                                }
                                                                onWidthChanged: if (visible) requestPaint()
                                                                onPaint: {
                                                                    const ctx = getContext("2d");
                                                                    ctx.clearRect(0, 0, width, height);
                                                                    if (width <= 0) return;
                                                                    ctx.fillStyle = Qt.alpha(settledColors.colPrimary, 0.35);
                                                                    ctx.fillRect(0, 0, width, height);
                                                                    ctx.strokeStyle = settledColors.colPrimary;
                                                                    ctx.lineWidth = 1.5;
                                                                    ctx.beginPath();
                                                                    for (let hx = -height; hx < width + height; hx += 5) {
                                                                        ctx.moveTo(hx, height);
                                                                        ctx.lineTo(hx + height, 0);
                                                                    }
                                                                    ctx.stroke();
                                                                }
                                                            }
                                                        }

                                                        RowLayout {
                                                            Layout.fillWidth: true
                                                            StyledText {
                                                                Layout.fillWidth: true
                                                                text: {
                                                                    const st = String(baseCardDelegate.modelData.status || "").toLowerCase();
                                                                    const c = parent.parent.curPg;
                                                                    const t = parent.parent.totPg;
                                                                    if ((st === "finished" || st === "completed") && c === 0 && t > 0)
                                                                        return String(t) + " / " + String(t) + " pages";
                                                                    return String(c) + " / " + String(t) + " pages";
                                                                }
                                                                font.family: Appearance.font.family.monospace
                                                                font.pixelSize: 8
                                                                color: settledColors.colSubtext
                                                            }
                                                            StyledText {
                                                                text: String(parent.parent.pct) + "%"
                                                                font.family: Appearance.font.family.monospace
                                                                font.pixelSize: 8
                                                                font.weight: Font.Bold
                                                                color: settledColors.colPrimary
                                                            }
                                                        }
                                                    }

                                                    // Rating Footer Row (`.book-back-rating` with tilted hand-drawn stars)
                                                    RowLayout {
                                                        Layout.fillWidth: true
                                                        StyledText {
                                                            Layout.fillWidth: true
                                                            text: "Rating"
                                                            font.pixelSize: 9
                                                            font.italic: true
                                                            color: settledColors.colSubtext
                                                        }
                                                        StyledText {
                                                            rotation: -2
                                                            text: {
                                                                const raw = String(baseCardDelegate.modelData.ratingRaw || baseCardDelegate.modelData.score || "");
                                                                if (!raw || raw === "0")
                                                                    return "not rated";
                                                                return collectionViewRoot._starsForScore(baseCardDelegate.modelData.score);
                                                            }
                                                            font.pixelSize: 10
                                                            color: settledColors.colPrimary
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        // ── 5. RECIPES: RIBBON & INGREDIENTS CARD (`FoodnDrinks.base` & `02_Components.css` L319–1075 `.rc-card`) ──
                                        Rectangle {
                                            id: rcBaseCard
                                            objectName: "nexusRecipeBaseCard_" + String(baseCardDelegate.index)
                                            visible: baseCardDelegate.isRecipeCard
                                            anchors.fill: parent
                                            radius: 12
                                            color: Qt.color(root.ccStop(2))
                                            border.width: 1
                                            border.color: baseCardHover.hovered
                                                ? Qt.alpha(settledColors.colPrimary, 0.58)
                                                : settledColors.colLayer0Border
                                            clip: true

                                            readonly property string rcCategoryRaw: String(
                                                baseCardDelegate.modelData.category
                                                || baseCardDelegate.modelData.genre
                                                || "Recipe"
                                            ).trim()
                                            readonly property string rcCategoryLabel: rcCategoryRaw.length > 0 ? rcCategoryRaw.toUpperCase() : "RECIPE"
                                            readonly property string rcCategoryIcon: {
                                                const k = rcCategoryRaw.toLowerCase();
                                                if (k.indexOf("drink") !== -1 || k.indexOf("beverage") !== -1 || k.indexOf("cocktail") !== -1)
                                                    return "local_bar";
                                                if (k.indexOf("dessert") !== -1 || k.indexOf("sweet") !== -1 || k.indexOf("cake") !== -1 || k.indexOf("bake") !== -1)
                                                    return "cake";
                                                if (k.indexOf("soup") !== -1 || k.indexOf("stew") !== -1 || k.indexOf("ramen") !== -1)
                                                    return "soup_kitchen";
                                                if (k.indexOf("salad") !== -1 || k.indexOf("veg") !== -1)
                                                    return "eco";
                                                if (k.indexOf("breakfast") !== -1 || k.indexOf("brunch") !== -1)
                                                    return "bakery_dining";
                                                return "restaurant";
                                            }
                                            readonly property real rcCaloriesNum: {
                                                const mDirect = /(\d+(?:\.\d+)?)/.exec(String(baseCardDelegate.modelData.calories ?? ""));
                                                if (mDirect && parseFloat(mDirect[1]) > 0)
                                                    return parseFloat(mDirect[1]);
                                                const plot = String(baseCardDelegate.modelData.plot ?? "");
                                                const mPlot = /(\d+(?:\.\d+)?)\s*(?:calories|kcal)\b/i.exec(plot);
                                                return mPlot ? parseFloat(mPlot[1]) : 0;
                                            }
                                            readonly property var rcMacroChips: {
                                                const plot = String(baseCardDelegate.modelData.plot ?? "");
                                                const chips = [];
                                                if (rcCaloriesNum > 0)
                                                    chips.push(String(Math.round(rcCaloriesNum)) + " kcal");
                                                const mProt = /(\d+(?:\.\d+)?)\s*g\s+(?:of\s+)?protein\b/i.exec(plot);
                                                const prot = mProt ? parseFloat(mProt[1]) : 0;
                                                if (prot > 0)
                                                    chips.push(String(Math.round(prot)) + "g P");
                                                const mFat = /(\d+(?:\.\d+)?)\s*g\s+(?:of\s+)?fat\b/i.exec(plot);
                                                const fat = mFat ? parseFloat(mFat[1]) : 0;
                                                if (fat > 0)
                                                    chips.push(String(Math.round(fat)) + "g F");
                                                const mCarbs = /(\d+(?:\.\d+)?)\s*g\s+(?:of\s+)?(?:carbs|carbohydrates)\b/i.exec(plot);
                                                if (mCarbs && parseFloat(mCarbs[1]) > 0) {
                                                    chips.push(String(Math.round(parseFloat(mCarbs[1]))) + "g C");
                                                } else if (rcCaloriesNum > 0 && (prot > 0 || fat > 0)) {
                                                    const remCal = rcCaloriesNum - (prot * 4.0 + fat * 9.0);
                                                    if (remCal > 4)
                                                        chips.push("~" + String(Math.round(remCal / 4.0)) + "g C");
                                                }
                                                return chips;
                                            }
                                            readonly property string rcTimeDisplay: {
                                                const parseMin = (v) => {
                                                    const m = /(\d+(?:\.\d+)?)/.exec(String(v ?? ""));
                                                    return m ? parseFloat(m[1]) : 0;
                                                };
                                                const prep = parseMin(baseCardDelegate.modelData.prepTime);
                                                const cook = parseMin(baseCardDelegate.modelData.cookTime);
                                                const total = prep + cook;
                                                if (total > 0)
                                                    return String(Math.round(total)) + " min";
                                                const rt = String(baseCardDelegate.modelData.runtime ?? "").trim();
                                                if (rt.length > 0 && rt !== "0" && rt !== "0 min")
                                                    return /^\d+$/.test(rt) ? (rt + " min") : rt;
                                                const plot = String(baseCardDelegate.modelData.plot ?? "");
                                                const mPlot = /(?:takes?\s+(?:around|about)|in\s+(?:around|about)|ready\s+in)\s+(\d+)\s*(?:minutes|mins|min)\b/i.exec(plot);
                                                if (mPlot && mPlot[1])
                                                    return mPlot[1] + " min";
                                                return "Flexible";
                                            }
                                            readonly property string rcTagline: {
                                                const sub = String(
                                                    baseCardDelegate.modelData.subtitle
                                                    || baseCardDelegate.modelData.tagline
                                                    || baseCardDelegate.modelData.cuisine
                                                    || ""
                                                ).trim();
                                                if (sub.length > 0)
                                                    return sub;
                                                const cat = rcCategoryRaw;
                                                if (rcCaloriesNum > 0)
                                                    return cat + " · " + String(Math.round(rcCaloriesNum)) + " kcal";
                                                return cat + " · Culinary Collection";
                                            }
                                            readonly property string rcDifficulty: {
                                                const raw = String(baseCardDelegate.modelData.difficulty || baseCardDelegate.modelData.status || "Easy").trim();
                                                if (raw.length === 0)
                                                    return "Easy";
                                                return raw.charAt(0).toUpperCase() + raw.slice(1);
                                            }
                                            readonly property color rcDifficultyColor: {
                                                const d = rcDifficulty.toLowerCase();
                                                if (d.indexOf("hard") !== -1 || d.indexOf("challeng") !== -1)
                                                    return Qt.color("#eb6f92");
                                                if (d.indexOf("med") !== -1 || d.indexOf("inter") !== -1)
                                                    return Qt.color("#f6c177");
                                                return settledColors.colTertiary ?? Qt.color("#81be99");
                                            }
                                            readonly property var rcIngredientItems: {
                                                const arr = baseCardDelegate.modelData.ingredients;
                                                if (Array.isArray(arr) && arr.length > 0) {
                                                    const out = [];
                                                    for (let i = 0; i < arr.length && out.length < 9; ++i) {
                                                        const s = String(arr[i] ?? "").trim();
                                                        if (s.length > 0)
                                                            out.push(s);
                                                    }
                                                    if (out.length > 0)
                                                        return out;
                                                }
                                                const plot = String(baseCardDelegate.modelData.plot ?? "").trim();
                                                if (plot.length > 0) {
                                                    const parts = plot.split(/\r?\n|•|·|;/);
                                                    const out = [];
                                                    for (let i = 0; i < parts.length && out.length < 8; ++i) {
                                                        const clean = parts[i].replace(/^[-*]\s*/, "").trim();
                                                        if (clean.length > 0)
                                                            out.push(clean);
                                                    }
                                                    if (out.length > 0)
                                                        return out;
                                                }
                                                return ["Click to open full recipe ingredients & step-by-step instructions"];
                                            }

                                            // ── FRONT FACE (`.rc-front`) ──
                                            ColumnLayout {
                                                anchors.fill: parent
                                                spacing: 0
                                                visible: !baseCardDelegate.showBack

                                                // Cover Media Container (`aspect-ratio: 3 / 2`, clips Spoonacular baked-in white margins)
                                                Rectangle {
                                                    id: rcImageFrame
                                                    objectName: "nexusRecipeBaseCover_" + String(baseCardDelegate.index)
                                                    Layout.fillWidth: true
                                                    Layout.preferredHeight: 162
                                                    color: Qt.color(root.ccStop(1))
                                                    clip: true

                                                    // Fallback culinary icon when image is missing
                                                    ColumnLayout {
                                                        anchors.centerIn: parent
                                                        spacing: 4
                                                        visible: !rcCoverImage.visible
                                                        MaterialSymbol {
                                                            Layout.alignment: Qt.AlignHCenter
                                                            text: rcBaseCard.rcCategoryIcon
                                                            iconSize: 32
                                                            color: Qt.alpha(settledColors.colPrimary, 0.45)
                                                        }
                                                        StyledText {
                                                            Layout.alignment: Qt.AlignHCenter
                                                            text: rcBaseCard.rcCategoryLabel
                                                            font.family: Appearance.font.family.monospace
                                                            font.pixelSize: 9
                                                            color: settledColors.colSubtext
                                                        }
                                                    }

                                                    Image {
                                                        id: rcCoverImage
                                                        objectName: "nexusRecipeBaseCoverImage_" + String(baseCardDelegate.index)
                                                        anchors.fill: parent
                                                        source: String(baseCardDelegate.modelData.posterUrl ?? "")
                                                        fillMode: Image.PreserveAspectCrop
                                                        horizontalAlignment: Image.AlignHCenter
                                                        verticalAlignment: Image.AlignVCenter
                                                        asynchronous: true
                                                        // Spoonacular 556x370 cover JPEGs have 48px solid white sidebars baked into the image file;
                                                        // 1.18x scale inside `clip: true` cleanly crops out the white sidebars on both left & right edges.
                                                        readonly property real baseCropScale: String(source).indexOf("spoonacular-") !== -1 ? 1.18 : 1.02
                                                        scale: baseCropScale * (baseCardHover.hovered ? 1.03 : 1.0)
                                                        Behavior on scale {
                                                            NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
                                                        }
                                                        visible: Boolean(baseCardDelegate.modelData.posterUrl) && status === Image.Ready
                                                    }

                                                    // Subtle bottom vignette for time pill legibility
                                                    Rectangle {
                                                        anchors.left: parent.left
                                                        anchors.right: parent.right
                                                        anchors.bottom: parent.bottom
                                                        height: 44
                                                        gradient: Gradient {
                                                            GradientStop { position: 0.0; color: "transparent" }
                                                            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.52) }
                                                        }
                                                    }

                                                    // Top-left Category Ribbon (`.rc-ribbon`)
                                                    Rectangle {
                                                        x: 12
                                                        y: 0
                                                        width: Math.max(46, rcRibbonCol.implicitWidth + 14)
                                                        height: 36
                                                        radius: 5
                                                        color: settledColors.colPrimary
                                                        border.width: 1
                                                        border.color: Qt.alpha(settledColors.colOnPrimary, 0.16)

                                                        // Top square cover so ribbon drops flush from top edge
                                                        Rectangle {
                                                            anchors.top: parent.top
                                                            anchors.left: parent.left
                                                            anchors.right: parent.right
                                                            height: 5
                                                            color: parent.color
                                                        }

                                                        ColumnLayout {
                                                            id: rcRibbonCol
                                                            anchors.centerIn: parent
                                                            spacing: 1

                                                            MaterialSymbol {
                                                                Layout.alignment: Qt.AlignHCenter
                                                                text: rcBaseCard.rcCategoryIcon
                                                                iconSize: 13
                                                                color: settledColors.colOnPrimary
                                                            }
                                                            StyledText {
                                                                Layout.alignment: Qt.AlignHCenter
                                                                text: rcBaseCard.rcCategoryLabel
                                                                font.family: Appearance.font.family.monospace
                                                                font.pixelSize: 8
                                                                font.weight: Font.Black
                                                                font.letterSpacing: 0.4
                                                                color: settledColors.colOnPrimary
                                                            }
                                                        }
                                                    }

                                                    // Top-right Favorite Heart Badge (`.rc-favorite`)
                                                    Rectangle {
                                                        anchors.top: parent.top
                                                        anchors.right: parent.right
                                                        anchors.margins: 8
                                                        width: 24
                                                        height: 24
                                                        radius: 12
                                                        visible: Boolean(baseCardDelegate.modelData.favorite) || Number(baseCardDelegate.modelData.score ?? 0) >= 8 || baseCardHover.hovered
                                                        color: Boolean(baseCardDelegate.modelData.favorite)
                                                            ? Qt.rgba(0.92, 0.44, 0.57, 0.90)
                                                            : Qt.alpha(Qt.color(root.ccStop(0)), 0.72)
                                                        border.width: 1
                                                        border.color: Boolean(baseCardDelegate.modelData.favorite)
                                                            ? "transparent"
                                                            : Qt.alpha(settledColors.colPrimary, 0.35)

                                                        MaterialSymbol {
                                                            anchors.centerIn: parent
                                                            text: Boolean(baseCardDelegate.modelData.favorite) ? "favorite" : "favorite_border"
                                                            iconSize: 13
                                                            color: Boolean(baseCardDelegate.modelData.favorite) ? "#ffffff" : settledColors.colPrimary
                                                        }
                                                    }

                                                    // Bottom-left Time Pill (`.rc-time`)
                                                    Rectangle {
                                                        anchors.left: parent.left
                                                        anchors.bottom: parent.bottom
                                                        anchors.leftMargin: 10
                                                        anchors.bottomMargin: 8
                                                        height: 22
                                                        width: rcTimeRow.implicitWidth + 14
                                                        radius: 11
                                                        color: Qt.alpha(Qt.color(root.ccStop(2)), 0.92)
                                                        border.width: 1
                                                        border.color: Qt.alpha(settledColors.colPrimary, 0.38)

                                                        RowLayout {
                                                            id: rcTimeRow
                                                            anchors.centerIn: parent
                                                            spacing: 4

                                                            MaterialSymbol {
                                                                text: "schedule"
                                                                iconSize: 11
                                                                color: settledColors.colPrimary
                                                            }
                                                            StyledText {
                                                                text: rcBaseCard.rcTimeDisplay
                                                                font.family: Appearance.font.family.monospace
                                                                font.pixelSize: 10
                                                                font.weight: Font.DemiBold
                                                                color: settledColors.colOnLayer0
                                                            }
                                                        }
                                                    }

                                                    // Bottom-right Calories Pill (when available)
                                                    Rectangle {
                                                        objectName: "nexusRecipeBaseCaloriesPill_" + String(baseCardDelegate.index)
                                                        visible: rcBaseCard.rcCaloriesNum > 0
                                                        anchors.right: parent.right
                                                        anchors.bottom: parent.bottom
                                                        anchors.rightMargin: 10
                                                        anchors.bottomMargin: 8
                                                        height: 22
                                                        width: rcCalRow.implicitWidth + 12
                                                        radius: 11
                                                        color: Qt.alpha(Qt.color(root.ccStop(0)), 0.84)
                                                        border.width: 1
                                                        border.color: settledColors.colLayer0Border

                                                        RowLayout {
                                                            id: rcCalRow
                                                            anchors.centerIn: parent
                                                            spacing: 3

                                                            MaterialSymbol {
                                                                text: "local_fire_department"
                                                                iconSize: 11
                                                                color: settledColors.colPrimary
                                                            }
                                                            StyledText {
                                                                text: String(Math.round(rcBaseCard.rcCaloriesNum)) + " kcal"
                                                                font.family: Appearance.font.family.monospace
                                                                font.pixelSize: 9
                                                                color: settledColors.colSubtext
                                                            }
                                                        }
                                                    }
                                                }

                                                // Body Section (`.rc-body`)
                                                Item {
                                                    Layout.fillWidth: true
                                                    Layout.fillHeight: true

                                                    // Subtle Right Culinary Flourish (`.rc-flourish`)
                                                    MaterialSymbol {
                                                        anchors.right: parent.right
                                                        anchors.bottom: parent.bottom
                                                        anchors.rightMargin: 8
                                                        anchors.bottomMargin: 34
                                                        text: "restaurant_menu"
                                                        iconSize: 48
                                                        color: settledColors.colPrimary
                                                        opacity: 0.07
                                                    }

                                                    ColumnLayout {
                                                        anchors.fill: parent
                                                        anchors.leftMargin: 12
                                                        anchors.rightMargin: 12
                                                        anchors.topMargin: 10
                                                        anchors.bottomMargin: 8
                                                        spacing: 4

                                                        StyledText {
                                                            Layout.fillWidth: true
                                                            text: String(baseCardDelegate.modelData.title ?? "")
                                                            font.family: Appearance.font.family.reading || Appearance.font.family.main
                                                            font.pixelSize: 13
                                                            font.weight: Font.Bold
                                                            color: settledColors.colOnLayer0
                                                            wrapMode: Text.WordWrap
                                                            elide: Text.ElideRight
                                                            maximumLineCount: 2
                                                            lineHeight: 1.15
                                                        }

                                                        StyledText {
                                                            Layout.fillWidth: true
                                                            text: rcBaseCard.rcTagline
                                                            font.family: Appearance.font.family.monospace
                                                            font.pixelSize: 10
                                                            color: settledColors.colPrimary
                                                            elide: Text.ElideRight
                                                            maximumLineCount: 1
                                                        }

                                                        RowLayout {
                                                            objectName: "nexusRecipeBaseMacroRow_" + String(baseCardDelegate.index)
                                                            visible: rcBaseCard.rcMacroChips.length > 0
                                                            Layout.fillWidth: true
                                                            spacing: 4

                                                            Repeater {
                                                                model: rcBaseCard.rcMacroChips.slice(0, 4)
                                                                delegate: Rectangle {
                                                                    required property string modelData
                                                                    height: 17
                                                                    width: rcMacroChipTxt.implicitWidth + 10
                                                                    radius: 8.5
                                                                    color: Qt.alpha(Qt.color(root.ccStop(2)), 0.72)
                                                                    border.width: 1
                                                                    border.color: settledColors.colLayer0Border

                                                                    StyledText {
                                                                        id: rcMacroChipTxt
                                                                        anchors.centerIn: parent
                                                                        text: modelData
                                                                        font.family: Appearance.font.family.monospace
                                                                        font.pixelSize: 8
                                                                        font.weight: Font.DemiBold
                                                                        color: settledColors.colSubtext
                                                                    }
                                                                }
                                                            }
                                                        }

                                                        Item { Layout.fillHeight: true }

                                                        // Top keyline divider above `.rc-footer`
                                                        Rectangle {
                                                            Layout.fillWidth: true
                                                            height: 1
                                                            color: settledColors.colLayer0Border
                                                        }

                                                        // 3-Column Footer Bar (`.rc-footer`: Servings | Difficulty | Bookmark/Rating)
                                                        RowLayout {
                                                            Layout.fillWidth: true
                                                            Layout.topMargin: 4
                                                            spacing: 6

                                                            // Column 1: Servings
                                                            RowLayout {
                                                                spacing: 4
                                                                MaterialSymbol {
                                                                    text: "group"
                                                                    iconSize: 12
                                                                    color: settledColors.colSubtext
                                                                }
                                                                StyledText {
                                                                    text: String(baseCardDelegate.modelData.servings || 2)
                                                                    font.family: Appearance.font.family.monospace
                                                                    font.pixelSize: 10
                                                                    font.weight: Font.DemiBold
                                                                    color: settledColors.colOnLayer1
                                                                }
                                                            }

                                                            Rectangle {
                                                                width: 1
                                                                height: 12
                                                                color: settledColors.colLayer0Border
                                                            }

                                                            // Column 2: Difficulty (centered)
                                                            Item {
                                                                Layout.fillWidth: true
                                                                implicitHeight: 18

                                                                RowLayout {
                                                                    anchors.centerIn: parent
                                                                    spacing: 4
                                                                    MaterialSymbol {
                                                                        text: "equalizer"
                                                                        iconSize: 12
                                                                        color: rcBaseCard.rcDifficultyColor
                                                                    }
                                                                    StyledText {
                                                                        text: rcBaseCard.rcDifficulty
                                                                        font.family: Appearance.font.family.monospace
                                                                        font.pixelSize: 10
                                                                        font.weight: Font.DemiBold
                                                                        color: rcBaseCard.rcDifficultyColor
                                                                    }
                                                                }
                                                            }

                                                            Rectangle {
                                                                width: 1
                                                                height: 12
                                                                color: settledColors.colLayer0Border
                                                            }

                                                            // Column 3: Rating or Bookmark indicator
                                                            RowLayout {
                                                                spacing: 3
                                                                MaterialSymbol {
                                                                    text: Number(baseCardDelegate.modelData.score ?? 0) > 0 ? "star" : "bookmark_border"
                                                                    iconSize: 12
                                                                    color: Number(baseCardDelegate.modelData.score ?? 0) > 0
                                                                        ? settledColors.colPrimary
                                                                        : settledColors.colSubtext
                                                                }
                                                                StyledText {
                                                                    visible: Number(baseCardDelegate.modelData.score ?? 0) > 0
                                                                    text: String(baseCardDelegate.modelData.score ?? "")
                                                                    font.family: Appearance.font.family.monospace
                                                                    font.pixelSize: 10
                                                                    font.weight: Font.Bold
                                                                    color: settledColors.colPrimary
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }

                                            // ── BACK FACE: INGREDIENTS LIST (`.rc-back`) ──
                                            Rectangle {
                                                anchors.fill: parent
                                                anchors.margins: 8
                                                visible: baseCardDelegate.showBack
                                                radius: 8
                                                color: Qt.tint(
                                                    Qt.lighter(Qt.color(root.ccStop(0)), 1.24),
                                                    Qt.rgba(settledColors.colPrimary.r, settledColors.colPrimary.g, settledColors.colPrimary.b, 0.08)
                                                )
                                                border.width: 1
                                                border.color: Qt.alpha(settledColors.colPrimary, 0.32)

                                                ColumnLayout {
                                                    anchors.fill: parent
                                                    anchors.margins: 12
                                                    spacing: 6

                                                    RowLayout {
                                                        Layout.fillWidth: true
                                                        spacing: 6

                                                        MaterialSymbol {
                                                            text: "shopping_basket"
                                                            iconSize: 14
                                                            color: settledColors.colPrimary
                                                        }
                                                        StyledText {
                                                            Layout.fillWidth: true
                                                            text: "Ingredients"
                                                            font.family: Appearance.font.family.reading || Appearance.font.family.main
                                                            font.pixelSize: 12
                                                            font.weight: Font.Bold
                                                            color: settledColors.colPrimary
                                                        }
                                                        StyledText {
                                                            text: rcBaseCard.rcTimeDisplay
                                                            font.family: Appearance.font.family.monospace
                                                            font.pixelSize: 9
                                                            color: settledColors.colSubtext
                                                        }
                                                    }

                                                    Rectangle {
                                                        Layout.fillWidth: true
                                                        height: 1
                                                        color: settledColors.colLayer0Border
                                                    }

                                                    ColumnLayout {
                                                        Layout.fillWidth: true
                                                        Layout.fillHeight: true
                                                        spacing: 4

                                                        Repeater {
                                                            model: rcBaseCard.rcIngredientItems
                                                            delegate: RowLayout {
                                                                required property var modelData
                                                                Layout.fillWidth: true
                                                                spacing: 6

                                                                Rectangle {
                                                                    width: 5
                                                                    height: 5
                                                                    radius: 2.5
                                                                    color: settledColors.colPrimary
                                                                    Layout.alignment: Qt.AlignTop
                                                                    Layout.topMargin: 5
                                                                }
                                                                StyledText {
                                                                    Layout.fillWidth: true
                                                                    text: String(modelData)
                                                                    font.pixelSize: 10
                                                                    color: settledColors.colOnLayer1
                                                                    elide: Text.ElideRight
                                                                    maximumLineCount: 1
                                                                }
                                                            }
                                                        }

                                                        Item { Layout.fillHeight: true }
                                                    }
                                                }
                                            }
                                        }

                                        // ── 6. EXERCISES: BODYBUILDING ATLAS CARD (`Bodybuilding.base` & `02_Components.css` L1332–1620 `.ex-card`) ──
                                        Rectangle {
                                            id: exBaseCard
                                            objectName: "nexusExerciseBaseCard_" + String(baseCardDelegate.index)
                                            visible: baseCardDelegate.isExerciseCard
                                            anchors.fill: parent
                                            radius: 14
                                            color: "#0b0f14"
                                            border.width: 1
                                            border.color: baseCardHover.hovered
                                                ? Qt.rgba(settledColors.colPrimary.r, settledColors.colPrimary.g, settledColors.colPrimary.b, 0.56)
                                                : Qt.rgba(1, 1, 1, 0.10)
                                            clip: true

                                            property bool exDemoPlaying: false
                                            readonly property string rawLevel: String(baseCardDelegate.modelData.level || baseCardDelegate.modelData.difficulty || "intermediate").trim().toLowerCase()
                                            readonly property string normLevel: (rawLevel === "expert" || rawLevel === "advanced")
                                                ? "advanced"
                                                : (rawLevel === "beginner" ? "beginner" : "intermediate")
                                            readonly property string levelBadgeText: normLevel === "advanced"
                                                ? "Advanced"
                                                : (normLevel === "beginner" ? "Beginner" : "Intermediate")
                                            readonly property color levelBadgeColor: normLevel === "advanced"
                                                ? Qt.rgba(0.97, 0.46, 0.56, 1.0)
                                                : (normLevel === "beginner" ? Qt.rgba(0.62, 0.81, 0.42, 1.0) : Qt.rgba(0.88, 0.69, 0.41, 1.0))
                                            readonly property string primaryMuscleText: {
                                                const m = String(baseCardDelegate.modelData.muscleGroup || baseCardDelegate.modelData.genre || "").trim();
                                                if (!m)
                                                    return "Full Body";
                                                return m.replace(/[_-]+/g, " ").replace(/\b\w/g, c => c.toUpperCase());
                                            }
                                            readonly property string equipmentText: {
                                                const eq = String(baseCardDelegate.modelData.equipment || baseCardDelegate.modelData.director || "").trim();
                                                if (!eq)
                                                    return "Body Only";
                                                return eq.replace(/[_-]+/g, " ").replace(/\b\w/g, c => c.toUpperCase());
                                            }
                                            readonly property string animUrl: String(baseCardDelegate.modelData.featuredImageUrl || "")

                                            // Front Face: Full-bleed image + dark top/bottom gradient + .ex-card-top + .ex-card-copy
                                            Item {
                                                anchors.fill: parent
                                                visible: !baseCardDelegate.flipped

                                                Rectangle {
                                                    anchors.fill: parent
                                                    color: "#0b0f14"
                                                }

                                                Image {
                                                    id: exPosterImg
                                                    anchors.fill: parent
                                                    source: baseCardDelegate.isExerciseCard ? String(baseCardDelegate.modelData.posterUrl ?? "") : ""
                                                    sourceSize: Qt.size(320, 268)
                                                    fillMode: Image.PreserveAspectCrop
                                                    asynchronous: true
                                                    cache: true
                                                    visible: Boolean(baseCardDelegate.modelData.posterUrl) && status === Image.Ready && (!exBaseCard.exDemoPlaying || !exCardAnimImg.visible)
                                                }

                                                AnimatedImage {
                                                    id: exCardAnimImg
                                                    anchors.fill: parent
                                                    source: (baseCardDelegate.isExerciseCard && exBaseCard.exDemoPlaying && exBaseCard.animUrl.length > 0) ? exBaseCard.animUrl : ""
                                                    fillMode: Image.PreserveAspectCrop
                                                    asynchronous: true
                                                    playing: exBaseCard. visible && exBaseCard.exDemoPlaying && !root.screenshotOverlayActive
                                                    visible: exBaseCard.exDemoPlaying && exBaseCard.animUrl.length > 0 && status === AnimatedImage.Ready
                                                }

                                                MaterialSymbol {
                                                    anchors.centerIn: parent
                                                    visible: !exPosterImg.visible && !exCardAnimImg.visible
                                                    text: "fitness_center"
                                                    iconSize: 40
                                                    color: Qt.rgba(settledColors.colPrimary.r, settledColors.colPrimary.g, settledColors.colPrimary.b, 0.55)
                                                }

                                                // Top & bottom cinema/fitness dark shade gradient overlay (.ex-card::after)
                                                Rectangle {
                                                    anchors.fill: parent
                                                    gradient: Gradient {
                                                        GradientStop { position: 0.0; color: Qt.rgba(0.03, 0.05, 0.06, 0.72) }
                                                        GradientStop { position: 0.34; color: Qt.rgba(0.03, 0.05, 0.06, 0.10) }
                                                        GradientStop { position: 0.58; color: Qt.rgba(0.03, 0.05, 0.06, 0.16) }
                                                        GradientStop { position: 1.0; color: Qt.rgba(0.03, 0.05, 0.06, 0.92) }
                                                    }
                                                }

                                                // .ex-card-top: Level pill on left + circular Play button on right
                                                RowLayout {
                                                    anchors.top: parent.top
                                                    anchors.left: parent.left
                                                    anchors.right: parent.right
                                                    anchors.margins: 10
                                                    spacing: 8

                                                    Rectangle {
                                                        height: 24
                                                        width: exCardLevelRow.implicitWidth + 16
                                                        radius: 12
                                                        color: Qt.rgba(0.04, 0.06, 0.08, 0.76)
                                                        border.width: 1
                                                        border.color: Qt.rgba(exBaseCard.levelBadgeColor.r, exBaseCard.levelBadgeColor.g, exBaseCard.levelBadgeColor.b, 0.42)

                                                        RowLayout {
                                                            id: exCardLevelRow
                                                            anchors.centerIn: parent
                                                            spacing: 6

                                                            Rectangle {
                                                                width: 6
                                                                height: 6
                                                                radius: 3
                                                                color: exBaseCard.levelBadgeColor
                                                            }

                                                            StyledText {
                                                                text: exBaseCard.levelBadgeText
                                                                font.pixelSize: 10
                                                                font.weight: Font.Bold
                                                                color: Qt.lighter(exBaseCard.levelBadgeColor, 1.18)
                                                            }
                                                        }
                                                    }

                                                    Item { Layout.fillWidth: true }

                                                    Rectangle {
                                                        id: exCardPlayBtn
                                                        objectName: "nexusExerciseBaseCardPlay_" + String(baseCardDelegate.index)
                                                        visible: exBaseCard.animUrl.length > 0
                                                        width: 28
                                                        height: 28
                                                        radius: 14
                                                        color: exBaseCard.exDemoPlaying
                                                            ? Qt.rgba(settledColors.colPrimary.r, settledColors.colPrimary.g, settledColors.colPrimary.b, 0.24)
                                                            : Qt.rgba(0.04, 0.06, 0.08, 0.76)
                                                        border.width: 1
                                                        border.color: exBaseCard.exDemoPlaying
                                                            ? Qt.rgba(settledColors.colPrimary.r, settledColors.colPrimary.g, settledColors.colPrimary.b, 0.62)
                                                            : Qt.rgba(1, 1, 1, 0.16)

                                                        MaterialSymbol {
                                                            anchors.centerIn: parent
                                                            text: exBaseCard.exDemoPlaying ? "pause" : "play_arrow"
                                                            iconSize: 16
                                                            color: exBaseCard.exDemoPlaying ? settledColors.colPrimary : "#f5f7fa"
                                                        }
                                                    }
                                                }

                                                // .ex-card-copy: Bottom title + 2-column primary muscle & equipment row
                                                ColumnLayout {
                                                    anchors.left: parent.left
                                                    anchors.right: parent.right
                                                    anchors.bottom: parent.bottom
                                                    anchors.margins: 12
                                                    spacing: 7

                                                    StyledText {
                                                        Layout.fillWidth: true
                                                        text: String(baseCardDelegate.modelData.title ?? "")
                                                        font.pixelSize: 15
                                                        font.weight: Font.ExtraBold
                                                        color: "#f5f7fa"
                                                        wrapMode: Text.WordWrap
                                                        elide: Text.ElideRight
                                                        maximumLineCount: 2
                                                    }

                                                    RowLayout {
                                                        Layout.fillWidth: true
                                                        spacing: 10

                                                        RowLayout {
                                                            Layout.fillWidth: true
                                                            spacing: 5

                                                            Canvas {
                                                                Layout.preferredWidth: 13
                                                                Layout.preferredHeight: 13
                                                                property string muscleName: exBaseCard.primaryMuscleText
                                                                property color iconColor: settledColors.colPrimary
                                                                onMuscleNameChanged: if (visible) requestPaint()
                                                                onIconColorChanged: if (visible) requestPaint()
                                                                onVisibleChanged: if (visible) requestPaint()
                                                                onPaint: {
                                                                    var ctx = getContext("2d");
                                                                    ExerciseAnatomyData.paintMiniMuscleIcon(ctx, width, height, muscleName, "rgba(210, 224, 230, 0.42)", iconColor.toString());
                                                                }
                                                            }

                                                            StyledText {
                                                                Layout.fillWidth: true
                                                                text: exBaseCard.primaryMuscleText
                                                                font.pixelSize: 11
                                                                font.weight: Font.DemiBold
                                                                color: Qt.rgba(0.89, 0.93, 0.96, 0.86)
                                                                elide: Text.ElideRight
                                                            }
                                                        }

                                                        RowLayout {
                                                            Layout.fillWidth: true
                                                            spacing: 5

                                                            Canvas {
                                                                Layout.preferredWidth: 13
                                                                Layout.preferredHeight: 13
                                                                property string equipName: exBaseCard.equipmentText
                                                                property color iconColor: settledColors.colPrimary
                                                                onEquipNameChanged: if (visible) requestPaint()
                                                                onIconColorChanged: if (visible) requestPaint()
                                                                onVisibleChanged: if (visible) requestPaint()
                                                                onPaint: {
                                                                    var ctx = getContext("2d");
                                                                    ExerciseAnatomyData.paintEquipmentIcon(ctx, width, height, equipName, iconColor.toString());
                                                                }
                                                            }

                                                            StyledText {
                                                                Layout.fillWidth: true
                                                                text: exBaseCard.equipmentText
                                                                font.pixelSize: 11
                                                                font.weight: Font.DemiBold
                                                                color: Qt.rgba(0.89, 0.93, 0.96, 0.86)
                                                                elide: Text.ElideRight
                                                            }
                                                        }
                                                    }
                                                }
                                            }

                                            // Exercise Back Face (`ex-card` right-click flip)
                                            ColumnLayout {
                                                anchors.fill: parent
                                                anchors.margins: 12
                                                visible: baseCardDelegate.flipped
                                                spacing: 4

                                                StyledText {
                                                    text: "MOVEMENT LIBRARY"
                                                    font.family: Appearance.font.family.monospace
                                                    font.pixelSize: 9
                                                    font.weight: Font.Bold
                                                    font.letterSpacing: 1.6
                                                    color: settledColors.colPrimary
                                                }
                                                StyledText {
                                                    Layout.fillWidth: true
                                                    text: String(baseCardDelegate.modelData.title ?? "")
                                                    font.pixelSize: 13
                                                    font.weight: Font.Bold
                                                    color: "#eef3f6"
                                                    elide: Text.ElideRight
                                                }
                                                Repeater {
                                                    model: [
                                                        { "k": "PRIMARY", "v": exBaseCard.primaryMuscleText },
                                                        { "k": "EQUIPMENT", "v": exBaseCard.equipmentText },
                                                        { "k": "LEVEL", "v": exBaseCard.levelBadgeText },
                                                        { "k": "CATEGORY", "v": String(baseCardDelegate.modelData.category || "Strength") }
                                                    ]
                                                    delegate: RowLayout {
                                                        required property var modelData
                                                        Layout.fillWidth: true
                                                        StyledText { Layout.preferredWidth: 68; text: modelData.k; font.family: Appearance.font.family.monospace; font.pixelSize: 9; font.weight: Font.Bold; color: settledColors.colPrimary }
                                                        StyledText { Layout.fillWidth: true; text: modelData.v; font.family: Appearance.font.family.monospace; font.pixelSize: 9; color: "#dde5ea"; elide: Text.ElideRight }
                                                    }
                                                }
                                                StyledText {
                                                    Layout.fillWidth: true
                                                    Layout.fillHeight: true
                                                    text: String(baseCardDelegate.modelData.plot || "Click to open Movement Library exercise view...")
                                                    font.pixelSize: 9
                                                    color: "#c0c8d6"
                                                    wrapMode: Text.WordWrap
                                                    elide: Text.ElideRight
                                                }
                                            }
                                        }

                                        // ── 7. PLACES: MAP & PLACE DOSSIER CARD (`Map.base`, `Places.base` & `02_Components.css` L1899–2269) ──
                                        Rectangle {
                                            objectName: "nexusPlaceBaseCard_" + String(baseCardDelegate.index)
                                            visible: baseCardDelegate.isPlaceCard
                                            anchors.fill: parent
                                            radius: 10
                                            color: settledColors.colLayer1
                                            border.width: 1
                                            border.color: baseCardHover.hovered ? settledColors.colPrimary : settledColors.colLayer0Border
                                            clip: true

                                            ColumnLayout {
                                                anchors.fill: parent
                                                spacing: 0
                                                visible: !baseCardDelegate.showBack

                                                Item {
                                                    Layout.fillWidth: true
                                                    Layout.preferredHeight: 132
                                                    clip: true

                                                    Rectangle {
                                                        anchors.fill: parent
                                                        color: settledColors.colLayer0
                                                    }

                                                    Image {
                                                        id: placePosterImg
                                                        anchors.fill: parent
                                                        source: String(baseCardDelegate.modelData.posterUrl ?? "")
                                                        fillMode: Image.PreserveAspectCrop
                                                        asynchronous: true
                                                        visible: Boolean(baseCardDelegate.modelData.posterUrl) && status === Image.Ready
                                                    }

                                                    MaterialSymbol {
                                                        anchors.centerIn: parent
                                                        visible: !placePosterImg.visible
                                                        text: "place"
                                                        iconSize: 34
                                                        color: settledColors.colPrimary
                                                    }

                                                    Rectangle {
                                                        x: 10
                                                        y: 10
                                                        height: 22
                                                        width: plCatTxt.implicitWidth + 12
                                                        radius: 4
                                                        color: settledColors.colPrimary
                                                        StyledText {
                                                            id: plCatTxt
                                                            anchors.centerIn: parent
                                                            text: String(baseCardDelegate.modelData.category || "PLACE").toUpperCase()
                                                            font.family: Appearance.font.family.monospace
                                                            font.pixelSize: 10
                                                            font.weight: Font.Black
                                                            color: settledColors.colOnPrimary
                                                        }
                                                    }

                                                    Rectangle {
                                                        anchors.right: parent.right
                                                        anchors.bottom: parent.bottom
                                                        anchors.margins: 8
                                                        height: 22
                                                        width: plStatTxt.implicitWidth + 12
                                                        radius: 10
                                                        color: Qt.rgba(settledColors.colLayer0.r, settledColors.colLayer0.g, settledColors.colLayer0.b, 0.90)
                                                        border.width: 1
                                                        border.color: settledColors.colPrimary
                                                        StyledText {
                                                            id: plStatTxt
                                                            anchors.centerIn: parent
                                                            text: String(baseCardDelegate.modelData.status || "VISITED").toUpperCase()
                                                            font.family: Appearance.font.family.monospace
                                                            font.pixelSize: 9
                                                            font.weight: Font.Bold
                                                            color: settledColors.colPrimary
                                                        }
                                                    }
                                                }

                                                ColumnLayout {
                                                    Layout.fillWidth: true
                                                    Layout.fillHeight: true
                                                    Layout.margins: 10
                                                    spacing: 4

                                                    StyledText {
                                                        Layout.fillWidth: true
                                                        text: String(baseCardDelegate.modelData.title ?? "")
                                                        font.pixelSize: 14
                                                        font.weight: Font.Bold
                                                        color: settledColors.colOnLayer1
                                                        elide: Text.ElideRight
                                                    }
                                                    StyledText {
                                                        Layout.fillWidth: true
                                                        text: String(baseCardDelegate.modelData.location || "—")
                                                        font.pixelSize: 11
                                                        color: settledColors.colSubtext
                                                        elide: Text.ElideRight
                                                    }
                                                    RowLayout {
                                                        Layout.fillWidth: true
                                                        StyledText {
                                                            Layout.fillWidth: true
                                                            text: collectionViewRoot._placeCoordinates(baseCardDelegate.modelData)
                                                            font.family: Appearance.font.family.monospace
                                                            font.pixelSize: 10
                                                            color: settledColors.colPrimary
                                                            elide: Text.ElideRight
                                                        }
                                                        StyledText {
                                                            text: collectionViewRoot._starsForScore(baseCardDelegate.modelData.score)
                                                            font.pixelSize: 11
                                                            color: settledColors.colTertiary ?? settledColors.colPrimary
                                                        }
                                                    }
                                                }
                                            }

                                            // Place Back Face (`map-place-back`)
                                            ColumnLayout {
                                                anchors.fill: parent
                                                anchors.margins: 12
                                                visible: baseCardDelegate.showBack
                                                spacing: 4

                                                StyledText {
                                                    text: "PLACE DOSSIER"
                                                    font.family: Appearance.font.family.monospace
                                                    font.pixelSize: 10
                                                    font.weight: Font.Bold
                                                    font.letterSpacing: 1.6
                                                    color: settledColors.colPrimary
                                                }
                                                StyledText {
                                                    Layout.fillWidth: true
                                                    text: String(baseCardDelegate.modelData.title ?? "")
                                                    font.pixelSize: 14
                                                    font.weight: Font.Bold
                                                    color: settledColors.colOnLayer1
                                                    elide: Text.ElideRight
                                                }
                                                Repeater {
                                                    model: [
                                                        { "k": "CATEGORY", "v": String(baseCardDelegate.modelData.category || "Place") },
                                                        { "k": "STATUS", "v": String(baseCardDelegate.modelData.status || "Visited") },
                                                        { "k": "ADDRESS", "v": String(baseCardDelegate.modelData.location || "—") },
                                                        { "k": "COORDS", "v": collectionViewRoot._placeCoordinates(baseCardDelegate.modelData) || "—" }
                                                    ]
                                                    delegate: RowLayout {
                                                        required property var modelData
                                                        Layout.fillWidth: true
                                                        StyledText { Layout.preferredWidth: 64; text: modelData.k; font.family: Appearance.font.family.monospace; font.pixelSize: 10; font.weight: Font.Bold; color: settledColors.colPrimary }
                                                        StyledText { Layout.fillWidth: true; text: modelData.v; font.family: Appearance.font.family.monospace; font.pixelSize: 10; color: settledColors.colOnLayer1; elide: Text.ElideRight }
                                                    }
                                                }
                                                StyledText {
                                                    Layout.fillWidth: true
                                                    Layout.fillHeight: true
                                                    text: String(baseCardDelegate.modelData.plot || "Click to open place note...")
                                                    font.pixelSize: 10
                                                    color: settledColors.colSubtext
                                                    wrapMode: Text.WordWrap
                                                    elide: Text.ElideRight
                                                }
                                            }
                                        }

                                        // ── 8. CONTACTS / CORNELL / ZETTELKASTEN / WEBSITES / CLIPPINGS / FINANCE CARDS ──
                                        Rectangle {
                                            visible: !baseCardDelegate.isMovieCard && !baseCardDelegate.isTvCard && !baseCardDelegate.isGameCard && !baseCardDelegate.isBookCard && !baseCardDelegate.isRecipeCard && !baseCardDelegate.isExerciseCard && !baseCardDelegate.isPlaceCard
                                            anchors.fill: parent
                                            radius: 10
                                            color: baseCardHover.hovered ? settledColors.colLayer2Hover : settledColors.colLayer0
                                            border.width: 1
                                            border.color: baseCardHover.hovered ? collectionViewRoot.activeCollectionMeta.accent : settledColors.colLayer0Border
                                            clip: true

                                            ColumnLayout {
                                                anchors.fill: parent
                                                anchors.margins: 12
                                                spacing: 6

                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 8

                                                    MaterialSymbol {
                                                        text: collectionViewRoot.activeCollectionMeta.icon
                                                        iconSize: 18
                                                        color: collectionViewRoot.activeCollectionMeta.accent
                                                    }

                                                    StyledText {
                                                        Layout.fillWidth: true
                                                        text: String(baseCardDelegate.modelData.title ?? "")
                                                        font.pixelSize: 13
                                                        font.weight: Font.Bold
                                                        color: settledColors.colOnLayer1
                                                        elide: Text.ElideRight
                                                    }

                                                    Rectangle {
                                                        visible: Boolean(baseCardDelegate.modelData.status || baseCardDelegate.modelData.category)
                                                        height: 20
                                                        width: otherBadgeTxt.implicitWidth + 12
                                                        radius: 5
                                                        color: settledColors.colSecondaryContainer
                                                        StyledText {
                                                            id: otherBadgeTxt
                                                            anchors.centerIn: parent
                                                            text: String(baseCardDelegate.modelData.status || baseCardDelegate.modelData.category || "")
                                                            font.pixelSize: 11
                                                            font.weight: Font.Bold
                                                            color: collectionViewRoot.activeCollectionMeta.accent
                                                        }
                                                    }
                                                }

                                                StyledText {
                                                    Layout.fillWidth: true
                                                    visible: Boolean(baseCardDelegate.modelData.genre || baseCardDelegate.modelData.location || baseCardDelegate.modelData.url || baseCardDelegate.modelData.director)
                                                    text: {
                                                        const p = [];
                                                        if (baseCardDelegate.modelData.genre) p.push(String(baseCardDelegate.modelData.genre));
                                                        if (baseCardDelegate.modelData.director) p.push(String(baseCardDelegate.modelData.director));
                                                        if (baseCardDelegate.modelData.location) p.push(String(baseCardDelegate.modelData.location));
                                                        if (baseCardDelegate.modelData.url) p.push(String(baseCardDelegate.modelData.url));
                                                        return p.join("  ·  ");
                                                    }
                                                    font.family: Appearance.font.family.monospace
                                                    font.pixelSize: 11
                                                    color: collectionViewRoot.activeCollectionMeta.accent
                                                    elide: Text.ElideRight
                                                }

                                                StyledText {
                                                    Layout.fillWidth: true
                                                    Layout.fillHeight: true
                                                    text: String(baseCardDelegate.modelData.plot || "Click to open note in Nexus...")
                                                    font.pixelSize: 11
                                                    color: settledColors.colSubtext
                                                    wrapMode: Text.WordWrap
                                                    elide: Text.ElideRight
                                                    maximumLineCount: 4
                                                }
                                            }
                                        }

                                        MouseArea {
                                            id: collEntryMouse
                                            anchors.fill: parent
                                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: mouse => {
                                                if (mouse.button === Qt.RightButton) {
                                                    const pt = mapToItem(root, mouse.x, mouse.y);
                                                    root.openContextMenu(pt.x, pt.y, {
                                                        "type": "base-card",
                                                        "title": baseCardDelegate.modelData.title || baseCardDelegate.modelData.name || baseCardDelegate.modelData.relPath,
                                                        "relPath": baseCardDelegate.modelData.relPath,
                                                        "noteKind": baseCardDelegate.modelData.kind || collectionCardsGrid.activeKind,
                                                        "flipped": baseCardDelegate.flipped,
                                                        "onFlip": () => { baseCardDelegate.flipped = !baseCardDelegate.flipped; }
                                                    });
                                                    return;
                                                }
                                                if (baseCardDelegate.isExerciseCard && exBaseCard.animUrl.length > 0 && !baseCardDelegate.flipped) {
                                                    // Check if top-right circular Play button was clicked
                                                    if (mouse.x >= baseCardDelegate.width - 44 && mouse.y <= 44) {
                                                        exBaseCard.exDemoPlaying = !exBaseCard.exDemoPlaying;
                                                        return;
                                                    }
                                                }
                                                if (root.nexus && baseCardDelegate.modelData.relPath)
                                                    root.nexus.openFile(baseCardDelegate.modelData.relPath, true);
                                            }
                                        }
                                    }
                                }
                            }

                        // ── OBSIDIAN BASES TABLE VIEW (`02_Components.css` L158–277 & `Contact_Tracker.base` / `Finance.base`) ──
                        Rectangle {
                            id: basesTableViewContainer
                            objectName: "nexusBasesTableView"
                            visible: collectionViewRoot.viewMode === "table"
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: 8
                            color: settledColors.colLayer0
                            border.width: 1
                            border.color: settledColors.colLayer0Border
                            clip: true

                            readonly property bool isFinanceLedger: collectionViewRoot.activeCollectionMeta.id === "finance"
                            readonly property var financeRows: {
                                if (!isFinanceLedger)
                                    return [];
                                const fs = root.nexus?.financeSummary ?? {};
                                if (collectionViewRoot.financeSubTab === "accounts")
                                    return fs.accounts ?? [];
                                if (collectionViewRoot.financeSubTab === "subscriptions")
                                    return fs.subscriptions ?? [];
                                return fs.transactions ?? [];
                            }

                            ColumnLayout {
                                anchors.fill: parent
                                spacing: 0

                                // Bases Table Header (`--bases-table-header-background`)
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 34
                                    color: settledColors.colLayer1
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 12
                                        anchors.rightMargin: 12
                                        spacing: 10

                                        StyledText {
                                            Layout.preferredWidth: 190
                                            text: basesTableViewContainer.isFinanceLedger
                                                ? (collectionViewRoot.financeSubTab === "accounts" ? "ACCOUNT" : (collectionViewRoot.financeSubTab === "subscriptions" ? "SERVICE" : "DESCRIPTION"))
                                                : (collectionViewRoot.activeCollectionMeta.id === "contacts" ? "FULL NAME" : "TITLE")
                                            font.family: Appearance.font.family.monospace
                                            font.pixelSize: 11
                                            font.weight: Font.Bold
                                            font.letterSpacing: 0.8
                                            color: settledColors.colSubtext
                                        }
                                        StyledText {
                                            Layout.preferredWidth: 110
                                            text: basesTableViewContainer.isFinanceLedger
                                                ? (collectionViewRoot.financeSubTab === "accounts" ? "TYPE" : (collectionViewRoot.financeSubTab === "subscriptions" ? "CYCLE" : "DATE"))
                                                : (collectionViewRoot.activeCollectionMeta.id === "contacts" ? "COMPANY / ROLE" : "CATEGORY / GENRE")
                                            font.family: Appearance.font.family.monospace
                                            font.pixelSize: 11
                                            font.weight: Font.Bold
                                            font.letterSpacing: 0.8
                                            color: settledColors.colSubtext
                                        }
                                        StyledText {
                                            Layout.preferredWidth: 110
                                            text: basesTableViewContainer.isFinanceLedger
                                                ? (collectionViewRoot.financeSubTab === "accounts" ? "STATUS" : "CATEGORY")
                                                : (collectionViewRoot.activeCollectionMeta.id === "contacts" ? "PHONE / EMAIL" : "CREATOR / AUTHOR")
                                            font.family: Appearance.font.family.monospace
                                            font.pixelSize: 11
                                            font.weight: Font.Bold
                                            font.letterSpacing: 0.8
                                            color: settledColors.colSubtext
                                        }
                                        StyledText {
                                            Layout.fillWidth: true
                                            text: basesTableViewContainer.isFinanceLedger
                                                ? "KIND"
                                                : (collectionViewRoot.activeCollectionMeta.id === "contacts" ? "ADDRESS / LOCATION" : "DETAILS / NOTES")
                                            font.family: Appearance.font.family.monospace
                                            font.pixelSize: 11
                                            font.weight: Font.Bold
                                            font.letterSpacing: 0.8
                                            color: settledColors.colSubtext
                                        }
                                        StyledText {
                                            Layout.preferredWidth: 100
                                            horizontalAlignment: Text.AlignRight
                                            text: basesTableViewContainer.isFinanceLedger ? "AMOUNT" : "STATUS / SCORE"
                                            font.family: Appearance.font.family.monospace
                                            font.pixelSize: 11
                                            font.weight: Font.Bold
                                            font.letterSpacing: 0.8
                                            color: settledColors.colSubtext
                                        }
                                    }
                                    Rectangle {
                                        anchors.bottom: parent.bottom
                                        width: parent.width
                                        height: 1
                                        color: settledColors.colLayer0Border
                                    }
                                }

                                // Bases Table Rows
                                ListView {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    clip: true
                                    cacheBuffer: 480
                                    model: (!collectionViewRoot.visible || collectionViewRoot.viewMode !== "table")
                                        ? []
                                        : (basesTableViewContainer.isFinanceLedger && basesTableViewContainer.financeRows.length > 0
                                            ? basesTableViewContainer.financeRows
                                            : collectionViewRoot.filteredCollectionItems)
                                    delegate: Rectangle {
                                        id: tableRowDel
                                        required property var modelData
                                        required property int index
                                        width: ListView.view.width
                                        height: 34
                                        color: tableRowMouse.containsMouse
                                            ? settledColors.colLayer2Hover
                                            : (index % 2 === 1 ? Qt.alpha(settledColors.colLayer2, 0.28) : "transparent")

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 12
                                            anchors.rightMargin: 12
                                            spacing: 10

                                            StyledText {
                                                Layout.preferredWidth: 190
                                                text: String(tableRowDel.modelData.title ?? tableRowDel.modelData.description ?? tableRowDel.modelData.name ?? "")
                                                font.pixelSize: 12
                                                font.weight: Font.DemiBold
                                                color: settledColors.colPrimary
                                                elide: Text.ElideRight
                                            }
                                            StyledText {
                                                Layout.preferredWidth: 110
                                                text: String(tableRowDel.modelData.genre ?? tableRowDel.modelData.category ?? tableRowDel.modelData.date ?? tableRowDel.modelData.type ?? tableRowDel.modelData.cycle ?? "—")
                                                font.family: Appearance.font.family.monospace
                                                font.pixelSize: 11
                                                color: settledColors.colOnLayer1
                                                elide: Text.ElideRight
                                            }
                                            StyledText {
                                                Layout.preferredWidth: 110
                                                text: String(tableRowDel.modelData.director ?? tableRowDel.modelData.actors ?? tableRowDel.modelData.category ?? tableRowDel.modelData.status ?? "—")
                                                font.family: Appearance.font.family.monospace
                                                font.pixelSize: 11
                                                color: settledColors.colSubtext
                                                elide: Text.ElideRight
                                            }
                                            StyledText {
                                                Layout.fillWidth: true
                                                text: String(tableRowDel.modelData.location ?? tableRowDel.modelData.plot ?? tableRowDel.modelData.kind ?? "")
                                                font.pixelSize: 11
                                                color: settledColors.colSubtext
                                                elide: Text.ElideRight
                                            }
                                            StyledText {
                                                Layout.preferredWidth: 100
                                                horizontalAlignment: Text.AlignRight
                                                text: tableRowDel.modelData.amount !== undefined
                                                    ? String(tableRowDel.modelData.amount)
                                                    : (tableRowDel.modelData.balance !== undefined
                                                        ? String(tableRowDel.modelData.balance)
                                                        : String(tableRowDel.modelData.status || tableRowDel.modelData.score || "—"))
                                                font.family: Appearance.font.family.monospace
                                                font.pixelSize: 11
                                                font.weight: Font.Bold
                                                color: collectionViewRoot.activeCollectionMeta.accent
                                                elide: Text.ElideRight
                                            }
                                        }

                                        Rectangle {
                                            anchors.bottom: parent.bottom
                                            width: parent.width
                                            height: 1
                                            color: Qt.alpha(settledColors.colLayer0Border, 0.45)
                                        }

                                        MouseArea {
                                            id: tableRowMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: mouse => {
                                                if (mouse.button === Qt.RightButton) {
                                                    const pt = mapToItem(root, mouse.x, mouse.y);
                                                    root.openContextMenu(pt.x, pt.y, {
                                                        "type": "file",
                                                        "title": tableRowDel.modelData.title || tableRowDel.modelData.name || tableRowDel.modelData.relPath,
                                                        "relPath": tableRowDel.modelData.relPath,
                                                        "noteKind": tableRowDel.modelData.kind || collectionViewRoot.activeCollectionMeta.id,
                                                        "isDir": false
                                                    });
                                                    return;
                                                }
                                                if (root.nexus && tableRowDel.modelData.relPath)
                                                    root.nexus.openFile(tableRowDel.modelData.relPath, true);
                                            }
                                        }
                                    }
                                }

                                // Bases Summary Footer (`Sum` / `Count` matching `02_Components.css` L245–277 & `Finance.base`)
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 30
                                    color: settledColors.colLayer1
                                    Rectangle {
                                        anchors.top: parent.top
                                        width: parent.width
                                        height: 1
                                        color: settledColors.colLayer0Border
                                    }
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 12
                                        anchors.rightMargin: 12
                                        spacing: 16
                                        StyledText {
                                            text: "COUNT  " + String(collectionViewRoot.filteredCollectionItems.length)
                                            font.family: Appearance.font.family.monospace
                                            font.pixelSize: 10
                                            font.weight: Font.Bold
                                            color: settledColors.colSubtext
                                        }
                                        Item { Layout.fillWidth: true }
                                        StyledText {
                                            visible: basesTableViewContainer.isFinanceLedger
                                            text: "INCOME: " + String(root.nexus?.financeSummary?.totalIncome ?? 0) +
                                                  "   ·   SPENT: " + String(root.nexus?.financeSummary?.totalSpent ?? 0) +
                                                  "   ·   SUM / NET: " + String(root.nexus?.financeSummary?.balance ?? 0)
                                            font.family: Appearance.font.family.monospace
                                            font.pixelSize: 10
                                            font.weight: Font.Bold
                                            color: settledColors.colPrimary
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ───────────────────────────────────────────────────────
                    // VIEW 3: DOCUMENT VIEW (Markdown Outliner / Vim / Code / Image)
                    // ───────────────────────────────────────────────────────
                    ColumnLayout {
                        id: documentViewRoot
                        objectName: "nexusDocumentView"
                        anchors.fill: parent
                        anchors.margins: 16
                        visible: (root.nexus?.activeView ?? "homepage") === "document" && Boolean(root.nexus?.currentDoc)
                        spacing: 10

                        // Document Header (Title + Metadata + Tags + Fold Controls; hidden in hybrid mode for Custom View notes where showInlineTitle: false)
                        RowLayout {
                            visible: !(Boolean(nexusCustomViewsLoader.item?.isCustomViewNote) && (root.nexus?.editorMode ?? "hybrid") === "hybrid")
                            Layout.fillWidth: true
                            spacing: 8

                            StyledText {
                                Layout.fillWidth: true
                                text: String(root.nexus?.currentDoc?.title ?? "")
                                font.pixelSize: 22
                                font.weight: Font.Bold
                                color: settledColors.colOnLayer1
                                elide: Text.ElideRight
                            }

                            // Tag chips
                            Repeater {
                                model: (root.nexus?.currentDoc?.tags ?? []).slice(0, 5)
                                delegate: Rectangle {
                                    required property var modelData
                                    height: 22
                                    width: docTagText.implicitWidth + 12
                                    radius: 11
                                    color: settledColors.colSecondaryContainer
                                    StyledText {
                                        id: docTagText
                                        anchors.centerIn: parent
                                        text: "#" + String(modelData)
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: settledColors.colPrimary
                                    }
                                }
                            }

                            // Fold All / Unfold All buttons (for Hybrid Outliner)
                            Rectangle {
                                visible: (root.nexus?.currentDoc?.category === "markdown") && (root.nexus?.editorMode !== "raw")
                                height: 24
                                width: 58
                                radius: 6
                                color: settledColors.colLayer0
                                StyledText {
                                    anchors.centerIn: parent
                                    text: "Fold zM"
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: settledColors.colSubtext
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (root.nexus)
                                            root.nexus.foldAllBlocks();
                                    }
                                }
                            }

                            Rectangle {
                                visible: (root.nexus?.currentDoc?.category === "markdown") && (root.nexus?.editorMode !== "raw")
                                height: 24
                                width: 66
                                radius: 6
                                color: settledColors.colLayer0
                                StyledText {
                                    anchors.centerIn: parent
                                    text: "Unfold zR"
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: settledColors.colSubtext
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (root.nexus)
                                            root.nexus.unfoldAllBlocks();
                                    }
                                }
                            }
                        }

                        // CASE A: Image Quick Viewer (.png, .jpg, .svg, .webp, .gif)
                        Rectangle {
                            id: imageViewerPane
                            objectName: "nexusImageViewerPane"
                            visible: (root.nexus?.currentDoc?.category ?? "") === "image"
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: 10
                            color: settledColors.colLayer0
                            border.width: 1
                            border.color: settledColors.colLayer0Border
                            clip: true

                            property real zoomFactor: 1.0

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 8

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: String(root.nexus?.currentDoc?.relPath ?? "") + "  (" + Math.round((root.nexus?.currentDoc?.sizeBytes ?? 0) / 1024) + " KB)"
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: settledColors.colSubtext
                                    }

                                    Rectangle {
                                        width: 28
                                        height: 26
                                        radius: 6
                                        color: settledColors.colLayer2
                                        StyledText {
                                            anchors.centerIn: parent
                                            text: "-"
                                            color: settledColors.colOnLayer1
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: imageViewerPane.zoomFactor = Math.max(0.25, imageViewerPane.zoomFactor - 0.25)
                                        }
                                    }
                                    StyledText {
                                        text: Math.round(imageViewerPane.zoomFactor * 100) + "%"
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: settledColors.colOnLayer1
                                    }
                                    Rectangle {
                                        width: 28
                                        height: 26
                                        radius: 6
                                        color: settledColors.colLayer2
                                        StyledText {
                                            anchors.centerIn: parent
                                            text: "+"
                                            color: settledColors.colOnLayer1
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: imageViewerPane.zoomFactor = Math.min(4.0, imageViewerPane.zoomFactor + 0.25)
                                        }
                                    }
                                    Rectangle {
                                        height: 26
                                        width: 110
                                        radius: 6
                                        color: settledColors.colSecondaryContainer
                                        StyledText {
                                            anchors.centerIn: parent
                                            text: "Open External"
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            color: settledColors.colOnSecondaryContainer
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                const abs = String(root.nexus?.currentDoc?.absPath ?? "");
                                                if (root.nexus && abs.length > 0)
                                                    root.nexus.openExternally(abs, "Opened image externally");
                                            }
                                        }
                                    }
                                }

                                Flickable {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    contentWidth: Math.max(width, width * imageViewerPane.zoomFactor)
                                    contentHeight: Math.max(height, height * imageViewerPane.zoomFactor)
                                    clip: true

                                    Image {
                                        width: parent.contentWidth
                                        height: parent.contentHeight
                                        source: (root.nexus?.currentDoc?.category === "image" && root.nexus?.currentDoc?.absPath) ? ("file://" + root.nexus.currentDoc.absPath) : ""
                                        fillMode: Image.PreserveAspectFit
                                        asynchronous: true
                                    }
                                }
                            }
                        }

                        // CASE B & C: Markdown Outliner + Vim Editor Split/Toggle Container
                        RowLayout {
                            visible: (root.nexus?.currentDoc?.category ?? "") !== "image"
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: 12

                            HoverHandler {
                                cursorShape: ((root.nexus?.currentDoc?.category === "code") || (root.nexus?.editorMode ?? "hybrid") === "raw")
                                    ? Qt.IBeamCursor
                                    : Qt.ArrowCursor
                            }

                            // ── Pane 1: Hybrid Block Outliner + Obsidian-Faithful Custom Views ──
                            Flickable {
                                id: outlinerFlickable
                                objectName: "nexusHybridOutlinerPane"
                                visible: (root.nexus?.currentDoc?.category === "markdown") && ((root.nexus?.editorMode ?? "hybrid") === "hybrid" || (root.nexus?.editorMode ?? "hybrid") === "split")
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                contentWidth: width
                                contentHeight: outlinerColumn.implicitHeight + 48
                                clip: true

                                HoverHandler {
                                    cursorShape: Qt.ArrowCursor
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    acceptedButtons: Qt.RightButton
                                    z: -1
                                    onClicked: mouse => {
                                        const pt = mapToItem(root, mouse.x, mouse.y);
                                        if (root.nexus?.currentDoc) {
                                            root.openContextMenu(pt.x, pt.y, {
                                                "type": "file",
                                                "title": root.nexus.currentDoc.title || root.nexus.currentDoc.relPath,
                                                "relPath": root.nexus.currentDoc.relPath,
                                                "isDir": false
                                            });
                                        } else {
                                            root.openContextMenu(pt.x, pt.y, {
                                                "type": "workspace",
                                                "title": "Document Actions"
                                            });
                                        }
                                    }
                                }

                                ColumnLayout {
                                    id: outlinerColumn
                                    width: outlinerFlickable.width
                                    spacing: 6

                                    // All 13 Vault Custom Views (Journal Daily Folio, Movies, TV, Games, Books, Recipes, Exercises, Places, Cornell, Zettelkasten, Finance, Clippings, Settings, Website)
                                    Loader {
                                        id: nexusCustomViewsLoader
                                        objectName: "nexusCustomViewsLoader"
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: item ? item.implicitHeight : 0
                                        Layout.bottomMargin: (item && item.implicitHeight > 0) ? 8 : 0
                                        asynchronous: Quickshell.env("QT_QUICK_BACKEND") !== "software"
                                        active: Boolean(root.nexus?.currentDoc?.category === "markdown")
                                        visible: Boolean(root.nexus?.currentDoc?.category === "markdown")
                                        sourceComponent: Component {
                                            NexusCustomViews {
                                                nexus: root.nexus
                                                workspace: root
                                                viewportHeight: outlinerFlickable.height
                                            }
                                        }
                                    }

                                    Rectangle {
                                        id: standardNotePaperCard
                                        objectName: "nexusStandardNotePaperCard"
                                        readonly property bool isStandardSheet: !Boolean(nexusCustomViewsLoader.item?.isCustomViewNote)
                                        readonly property int minSheetHeight: isStandardSheet ? Math.max(360, outlinerFlickable.height - 32) : 0
                                        visible: isStandardSheet || (root.nexus?.editorMode ?? "hybrid") === "split"
                                        Layout.fillWidth: true
                                        implicitHeight: isStandardSheet
                                            ? Math.max(minSheetHeight, standardNoteInnerCol.implicitHeight + 36)
                                            : outlinerBlocksCol.implicitHeight
                                        Layout.preferredHeight: implicitHeight
                                        radius: isStandardSheet ? 12 : 0
                                        color: isStandardSheet ? settledColors.colLayer1 : "transparent"
                                        border.width: isStandardSheet ? 1 : 0
                                        border.color: (isStandardSheet && root.standardNoteInlineEditing)
                                            ? settledColors.colPrimary
                                            : settledColors.colLayer0Border
                                        clip: isStandardSheet

                                        Canvas {
                                            id: standardNoteRuledCanvas
                                            objectName: "nexusStandardNoteRuledCanvas"
                                            visible: standardNotePaperCard.isStandardSheet
                                            anchors.fill: parent
                                            anchors.topMargin: 46
                                            z: 0
                                            property string themeSig: root.themeSignature
                                            onThemeSigChanged: requestPaint()
                                            onWidthChanged: requestPaint()
                                            onHeightChanged: requestPaint()
                                            onPaint: {
                                                const ctx = getContext("2d");
                                                ctx.clearRect(0, 0, width, height);
                                                const lineCol = settledColors.colLayer0Border;
                                                ctx.strokeStyle = Qt.rgba(lineCol.r, lineCol.g, lineCol.b, 0.34);
                                                ctx.lineWidth = 1;
                                                const pitch = 28;
                                                for (let y = pitch; y < height - 8; y += pitch) {
                                                    ctx.beginPath();
                                                    ctx.moveTo(14, y + 0.5);
                                                    ctx.lineTo(Math.max(14, width - 14), y + 0.5);
                                                    ctx.stroke();
                                                }
                                                const acc = settledColors.colPrimary;
                                                ctx.strokeStyle = Qt.rgba(acc.r, acc.g, acc.b, 0.14);
                                                ctx.beginPath();
                                                ctx.moveTo(22.5, 0);
                                                ctx.lineTo(22.5, height);
                                                ctx.stroke();
                                            }
                                        }

                                        MouseArea {
                                            id: standardNoteSheetBgMouse
                                            visible: standardNotePaperCard.isStandardSheet && !root.standardNoteInlineEditing
                                            anchors.fill: parent
                                            z: 0
                                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                                            cursorShape: Qt.IBeamCursor
                                            onClicked: mouse => {
                                                if (mouse.button === Qt.RightButton) {
                                                    const pt = mapToItem(root, mouse.x, mouse.y);
                                                    if (root.nexus?.currentDoc) {
                                                        root.openContextMenu(pt.x, pt.y, {
                                                            "type": "file",
                                                            "title": root.nexus.currentDoc.title || root.nexus.currentDoc.relPath,
                                                            "relPath": root.nexus.currentDoc.relPath,
                                                            "noteKind": root.nexus.currentDoc.noteKind || "",
                                                            "isDir": false
                                                        });
                                                    }
                                                    return;
                                                }
                                                if ((root.nexus?.editorMode ?? "hybrid") === "hybrid")
                                                    root.startStandardNoteInlineEdit();
                                            }
                                        }

                                        ColumnLayout {
                                            id: standardNoteInnerCol
                                            z: 1
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.top: parent.top
                                            anchors.leftMargin: standardNotePaperCard.isStandardSheet ? 28 : 0
                                            anchors.rightMargin: standardNotePaperCard.isStandardSheet ? 18 : 0
                                            anchors.topMargin: standardNotePaperCard.isStandardSheet ? 14 : 0
                                            spacing: 10

                                            RowLayout {
                                                id: standardNoteSheetHeader
                                                objectName: "nexusStandardNoteSheetHeader"
                                                visible: standardNotePaperCard.isStandardSheet
                                                Layout.fillWidth: true
                                                spacing: 8

                                                MaterialSymbol {
                                                    text: root.standardNoteInlineEditing ? "edit_note" : "notes"
                                                    iconSize: 15
                                                    color: settledColors.colPrimary
                                                }

                                                StyledText {
                                                    Layout.fillWidth: true
                                                    text: root.standardNoteInlineEditing
                                                        ? "LIVE PREVIEW · Editing note body (Esc or Save to finish)"
                                                        : "LIVE PREVIEW · Click any block to edit"
                                                    font.family: Appearance.font.family.monospace
                                                    font.pixelSize: 10
                                                    font.weight: Font.Bold
                                                    font.letterSpacing: 0.9
                                                    color: root.standardNoteInlineEditing ? settledColors.colPrimary : settledColors.colSubtext
                                                    elide: Text.ElideRight
                                                }

                                                Rectangle {
                                                    objectName: "nexusStandardNoteEditPrompt"
                                                    visible: !root.standardNoteInlineEditing
                                                    radius: 5
                                                    color: stdEditPromptMouse.containsMouse ? settledColors.colSecondaryContainer : settledColors.colLayer2
                                                    border.width: 1
                                                    border.color: settledColors.colLayer0Border
                                                    implicitWidth: stdEditPromptTxt.implicitWidth + 14
                                                    implicitHeight: 22

                                                    StyledText {
                                                        id: stdEditPromptTxt
                                                        anchors.centerIn: parent
                                                        text: "Click to edit notes"
                                                        font.pixelSize: 10
                                                        font.weight: Font.DemiBold
                                                        color: stdEditPromptMouse.containsMouse ? settledColors.colPrimary : settledColors.colOnLayer1
                                                    }
                                                    MouseArea {
                                                        id: stdEditPromptMouse
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: root.startStandardNoteInlineEdit()
                                                    }
                                                }

                                                Rectangle {
                                                    id: standardNoteCancelBtn
                                                    objectName: "nexusStandardNoteCancelButton"
                                                    visible: root.standardNoteInlineEditing
                                                    radius: 5
                                                    color: standardCancelMouse.containsMouse ? settledColors.colLayer2Hover : settledColors.colLayer2
                                                    border.width: 1
                                                    border.color: settledColors.colLayer0Border
                                                    implicitWidth: 54
                                                    implicitHeight: 24

                                                    StyledText {
                                                        anchors.centerIn: parent
                                                        text: "Cancel"
                                                        font.pixelSize: 10
                                                        font.weight: Font.DemiBold
                                                        color: settledColors.colSubtext
                                                    }
                                                    MouseArea {
                                                        id: standardCancelMouse
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            root.cancelStandardNoteInlineEdit();
                                                            root.restoreWorkspaceFocus();
                                                            Qt.callLater(root.restoreWorkspaceFocus);
                                                        }
                                                    }
                                                }

                                                Rectangle {
                                                    id: standardNoteSaveBtn
                                                    objectName: "nexusStandardNoteSaveButton"
                                                    visible: root.standardNoteInlineEditing
                                                    radius: 5
                                                    color: settledColors.colPrimary
                                                    implicitWidth: 68
                                                    implicitHeight: 24

                                                    StyledText {
                                                        anchors.centerIn: parent
                                                        text: "Save Notes"
                                                        font.pixelSize: 10
                                                        font.weight: Font.Bold
                                                        color: settledColors.colOnPrimary
                                                    }
                                                    MouseArea {
                                                        anchors.fill: parent
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            root.commitStandardNoteInlineEdit();
                                                            root.restoreWorkspaceFocus();
                                                            Qt.callLater(root.restoreWorkspaceFocus);
                                                        }
                                                    }
                                                }
                                            }

                                            Rectangle {
                                                visible: standardNotePaperCard.isStandardSheet
                                                Layout.fillWidth: true
                                                height: 1
                                                color: settledColors.colLayer0Border
                                                opacity: 0.65
                                            }

                                            StyledText {
                                                visible: standardNotePaperCard.isStandardSheet
                                                    && !root.standardNoteInlineEditing
                                                    && (root.nexus?.currentDoc?.blocks ?? []).length === 0
                                                Layout.fillWidth: true
                                                Layout.topMargin: 6
                                                text: "Click anywhere on this ruled sheet or press i to write notes..."
                                                font.pixelSize: Appearance.font.pixelSize.small
                                                font.italic: true
                                                color: settledColors.colSubtext
                                                wrapMode: Text.Wrap
                                            }

                                            TextArea {
                                                id: standardNoteBodyEditor
                                                objectName: "nexusStandardNoteInlineEditor"
                                                visible: standardNotePaperCard.isStandardSheet && root.standardNoteInlineEditing
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: Math.max(260, contentHeight + 36)
                                                text: root.standardNoteInlineDraft
                                                wrapMode: TextEdit.Wrap
                                                font.family: Appearance.font.family.main
                                                font.pixelSize: Appearance.font.pixelSize.small + 1
                                                color: settledColors.colOnLayer1
                                                selectionColor: settledColors.colSecondaryContainer
                                                selectedTextColor: settledColors.colOnSecondaryContainer
                                                selectByMouse: true
                                                background: null
                                                onVisibleChanged: {
                                                    if (visible) {
                                                        text = root.standardNoteInlineDraft;
                                                        forceActiveFocus();
                                                        cursorPosition = text.length;
                                                    } else {
                                                        focus = false;
                                                    }
                                                }
                                                onActiveFocusChanged: {
                                                    if (!activeFocus
                                                        && visible
                                                        && root.standardNoteInlineEditing
                                                        && !root._cancelingStandardInlineEdit
                                                        && !standardCancelMouse.containsMouse
                                                        && !standardCancelMouse.pressed) {
                                                        root.commitStandardNoteInlineEdit();
                                                    }
                                                }
                                                Keys.onEscapePressed: event => {
                                                    root.commitStandardNoteInlineEdit();
                                                    focus = false;
                                                    root.restoreWorkspaceFocus();
                                                    Qt.callLater(root.restoreWorkspaceFocus);
                                                    event.accepted = true;
                                                }
                                                Keys.onPressed: event => {
                                                    if ((event.modifiers & Qt.ControlModifier)
                                                        && (event.key === Qt.Key_S || event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
                                                        root.commitStandardNoteInlineEdit();
                                                        focus = false;
                                                        root.restoreWorkspaceFocus();
                                                        Qt.callLater(root.restoreWorkspaceFocus);
                                                        event.accepted = true;
                                                        return;
                                                    }
                                                    if ((event.modifiers & (Qt.AltModifier | Qt.ControlModifier | Qt.MetaModifier)) !== 0
                                                        && root.nexus && root.nexus.handleKeyEvent(event)) {
                                                        event.accepted = true;
                                                    }
                                                }
                                            }

                                            ColumnLayout {
                                                id: outlinerBlocksCol
                                                objectName: "nexusOutlinerBlocksCol"
                                                visible: (!standardNotePaperCard.isStandardSheet || !root.standardNoteInlineEditing)
                                                    && (!Boolean(nexusCustomViewsLoader.item?.isCustomViewNote) || (root.nexus?.editorMode ?? "hybrid") === "split")
                                                Layout.fillWidth: true
                                                spacing: 6

                                    Repeater {
                                        model: (Boolean(nexusCustomViewsLoader.item?.isCustomViewNote) && (root.nexus?.editorMode ?? "hybrid") !== "split")
                                            ? []
                                            : (root.nexus?.currentDoc?.blocks ?? [])
                                        delegate: Item {
                                            id: blockDelegate
                                            required property var modelData
                                            required property int index
                                            readonly property bool hiddenByFold: root.nexus ? root.nexus.isBlockHiddenByFold(index) : false
                                            readonly property bool hiddenByCustomView: Boolean(nexusCustomViewsLoader.item?.isCustomViewNote) && (root.nexus?.editorMode ?? "hybrid") !== "split"
                                            readonly property bool isFolded: Boolean(root.nexus?.foldedBlocks?.[modelData.id])
                                            readonly property bool isEditingThisBlock: (root.nexus?.editingBlockId ?? -1) === modelData.id

                                            visible: !hiddenByFold && !hiddenByCustomView
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: (hiddenByFold || hiddenByCustomView) ? 0 : (isEditingThisBlock ? 72 : blockRow.implicitHeight + 8)

                                            Rectangle {
                                                anchors.fill: parent
                                                radius: 7
                                                color: {
                                                    if (blockDelegate.modelData.kind === "callout")
                                                        return Qt.alpha(settledColors.colPrimary, 0.14);
                                                    if (blockDelegate.modelData.kind === "code" || blockDelegate.modelData.kind === "math")
                                                        return settledColors.colLayer0;
                                                    return blockHover.containsMouse ? settledColors.colLayer0 : "transparent";
                                                }
                                                border.width: (blockDelegate.modelData.kind === "callout" || blockDelegate.modelData.kind === "code" || blockDelegate.modelData.kind === "table" || blockDelegate.isEditingThisBlock) ? 1 : 0
                                                border.color: blockDelegate.isEditingThisBlock ? settledColors.colPrimary : settledColors.colLayer0Border

                                                // Inline Block Editor (when clicked in Reading mode)
                                                RowLayout {
                                                    visible: blockDelegate.isEditingThisBlock
                                                    anchors.fill: parent
                                                    anchors.margins: 6
                                                    spacing: 6

                                                    TextArea {
                                                        id: inlineBlockEditor
                                                        objectName: "nexusInlineBlockEditor_" + String(blockDelegate.modelData.id)
                                                        Layout.fillWidth: true
                                                        Layout.fillHeight: true
                                                        text: root.nexus?.editingBlockText ?? blockDelegate.modelData.rawText
                                                        font.family: Appearance.font.family.monospace
                                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                                        color: settledColors.colOnLayer1
                                                        background: null
                                                        onVisibleChanged: {
                                                            if (visible) {
                                                                forceActiveFocus();
                                                            } else {
                                                                inlineBlockEditor.focus = false;
                                                                root.restoreWorkspaceFocus();
                                                                Qt.callLater(root.restoreWorkspaceFocus);
                                                            }
                                                        }
                                                        Keys.onEscapePressed: event => {
                                                            if (root.nexus)
                                                                root.nexus.editingBlockId = -1;
                                                            inlineBlockEditor.focus = false;
                                                            root.restoreWorkspaceFocus();
                                                            Qt.callLater(root.restoreWorkspaceFocus);
                                                            event.accepted = true;
                                                        }
                                                        Keys.onPressed: event => {
                                                            if ((event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_S)) {
                                                                if (root.nexus)
                                                                    root.nexus.updateBlockContent(blockDelegate.modelData.lineStart, blockDelegate.modelData.lineEnd, inlineBlockEditor.text);
                                                                inlineBlockEditor.focus = false;
                                                                root.restoreWorkspaceFocus();
                                                                Qt.callLater(root.restoreWorkspaceFocus);
                                                                event.accepted = true;
                                                                return;
                                                            }
                                                            if ((event.modifiers & (Qt.AltModifier | Qt.ControlModifier | Qt.MetaModifier)) !== 0
                                                                && root.nexus && root.nexus.handleKeyEvent(event)) {
                                                                event.accepted = true;
                                                            }
                                                        }
                                                    }

                                                    Rectangle {
                                                        width: 56
                                                        height: 28
                                                        radius: 6
                                                        color: settledColors.colPrimary
                                                        StyledText {
                                                            anchors.centerIn: parent
                                                            text: "Apply"
                                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                                            color: settledColors.colOnPrimary
                                                        }
                                                        MouseArea {
                                                            anchors.fill: parent
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: {
                                                                if (root.nexus)
                                                                    root.nexus.updateBlockContent(blockDelegate.modelData.lineStart, blockDelegate.modelData.lineEnd, inlineBlockEditor.text);
                                                                inlineBlockEditor.focus = false;
                                                                root.restoreWorkspaceFocus();
                                                                Qt.callLater(root.restoreWorkspaceFocus);
                                                            }
                                                        }
                                                    }
                                                }

                                                // Standard Outliner Block Presentation
                                                RowLayout {
                                                    id: blockRow
                                                    visible: !blockDelegate.isEditingThisBlock
                                                    anchors.left: parent.left
                                                    anchors.right: parent.right
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    anchors.leftMargin: 6 + (blockDelegate.modelData.indent ?? 0) * 18
                                                    anchors.rightMargin: 8
                                                    spacing: 6

                                                    // Fold / Expand chevron for foldable headings & parent bullets
                                                    Rectangle {
                                                        Layout.preferredWidth: 18
                                                        Layout.preferredHeight: 18
                                                        radius: 4
                                                        color: "transparent"
                                                        MaterialSymbol {
                                                            visible: Boolean(blockDelegate.modelData.foldable)
                                                            anchors.centerIn: parent
                                                            text: blockDelegate.isFolded ? "chevron_right" : "expand_more"
                                                            iconSize: 15
                                                            color: blockDelegate.isFolded ? settledColors.colPrimary : settledColors.colSubtext
                                                        }
                                                        MouseArea {
                                                            anchors.fill: parent
                                                            enabled: Boolean(blockDelegate.modelData.foldable)
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: {
                                                                if (root.nexus)
                                                                    root.nexus.toggleBlockFold(blockDelegate.modelData.id);
                                                            }
                                                        }
                                                    }

                                                    // Outliner Bullet Dot or Interactive Task Checkbox
                                                    Item {
                                                        visible: blockDelegate.modelData.kind === "bullet" || blockDelegate.modelData.kind === "todo"
                                                        Layout.preferredWidth: 18
                                                        Layout.preferredHeight: 18

                                                        Rectangle {
                                                            visible: blockDelegate.modelData.kind === "bullet"
                                                            anchors.centerIn: parent
                                                            width: 6
                                                            height: 6
                                                            radius: 3
                                                            color: blockDelegate.isFolded ? settledColors.colPrimary : settledColors.colSubtext
                                                        }

                                                        MaterialSymbol {
                                                            visible: blockDelegate.modelData.kind === "todo"
                                                            anchors.centerIn: parent
                                                            text: blockDelegate.modelData.todoState === "DONE" ? "check_box" : "check_box_outline_blank"
                                                            iconSize: 16
                                                            color: blockDelegate.modelData.todoState === "DONE" ? settledColors.colSecondary : settledColors.colPrimary
                                                        }

                                                        MouseArea {
                                                            anchors.fill: parent
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: {
                                                                if (!root.nexus)
                                                                    return;
                                                                if (blockDelegate.modelData.kind === "todo")
                                                                    root.nexus.toggleBlockTodo(blockDelegate.modelData.lineStart);
                                                                else if (blockDelegate.modelData.foldable)
                                                                    root.nexus.toggleBlockFold(blockDelegate.modelData.id);
                                                            }
                                                        }
                                                    }

                                                    // Block Body Content
                                                    ColumnLayout {
                                                        Layout.fillWidth: true
                                                        spacing: 4

                                                        // Callout title header
                                                        RowLayout {
                                                            visible: blockDelegate.modelData.kind === "callout"
                                                            spacing: 6
                                                            MaterialSymbol {
                                                                text: "info"
                                                                iconSize: 15
                                                                color: settledColors.colPrimary
                                                            }
                                                            StyledText {
                                                                text: "[" + String(blockDelegate.modelData.calloutType ?? "NOTE") + "] " + String(blockDelegate.modelData.title ?? "")
                                                                font.weight: Font.Bold
                                                                font.pixelSize: Appearance.font.pixelSize.smaller
                                                                color: settledColors.colPrimary
                                                            }
                                                        }

                                                        // Cornell Marginalia Cue Badge (?, !, ., E-, V-, X-, R-, *, Summary)
                                                        RowLayout {
                                                            objectName: "nexusCornellCueBadge_" + String(blockDelegate.modelData.id)
                                                            visible: blockDelegate.modelData.kind === "heading" && Boolean(blockDelegate.modelData.calloutType)
                                                            spacing: 6

                                                            Rectangle {
                                                                height: 20
                                                                width: cornellCueLabel.implicitWidth + 12
                                                                radius: 5
                                                                color: {
                                                                    const cue = String(blockDelegate.modelData.title ?? "");
                                                                    if (cue === "?" || cue === "!" || cue === "Summary")
                                                                        return Qt.color(root.ccStop(3));
                                                                    return settledColors.colSecondaryContainer;
                                                                }
                                                                border.width: 1
                                                                border.color: {
                                                                    const cue = String(blockDelegate.modelData.title ?? "");
                                                                    if (cue === "?") return settledColors.colError ?? settledColors.colPrimary;
                                                                    if (cue === "!") return settledColors.colTertiary ?? settledColors.colPrimary;
                                                                    if (cue === "Summary") return settledColors.colSecondary ?? settledColors.colPrimary;
                                                                    return settledColors.colPrimary;
                                                                }

                                                                StyledText {
                                                                    id: cornellCueLabel
                                                                    anchors.centerIn: parent
                                                                    text: {
                                                                        const cue = String(blockDelegate.modelData.title ?? "");
                                                                        if (cue === "?") return "?  CUE QUESTION";
                                                                        if (cue === "!") return "!  KEY INSIGHT";
                                                                        if (cue === ".") return "•  CORE POINT";
                                                                        if (cue === "E-") return "E- EXAMPLE";
                                                                        if (cue === "V-") return "V- VOCAB";
                                                                        if (cue === "X-") return "X- CONTRADICTION";
                                                                        if (cue === "R-") return "R- REFERENCE";
                                                                        if (cue === "*") return "*  CORNELL NOTE";
                                                                        if (cue === "Summary") return "★ CORNELL SUMMARY";
                                                                        return cue;
                                                                    }
                                                                    font.family: Appearance.font.family.monospace
                                                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                                                    font.weight: Font.Bold
                                                                    color: parent.border.color
                                                                }
                                                            }
                                                        }

                                                        // Horizontal Rule / Divider Block (kind === "divider")
                                                        Rectangle {
                                                            visible: blockDelegate.modelData.kind === "divider" || blockDelegate.modelData.kind === "hr"
                                                            Layout.fillWidth: true
                                                            Layout.preferredHeight: 1
                                                            Layout.topMargin: 6
                                                            Layout.bottomMargin: 6
                                                            color: settledColors.colLayer0Border
                                                        }

                                                        // Inline Embedded Image Block (kind === "image")
                                                        Rectangle {
                                                            visible: blockDelegate.modelData.kind === "image" && Boolean(blockDelegate.modelData.lang)
                                                            Layout.fillWidth: true
                                                            Layout.preferredHeight: visible ? 220 : 0
                                                            radius: 8
                                                            color: settledColors.colLayer0
                                                            border.width: 1
                                                            border.color: settledColors.colLayer0Border
                                                            clip: true

                                                            Image {
                                                                anchors.fill: parent
                                                                anchors.margins: 6
                                                                source: blockDelegate.modelData.kind === "image" ? String(blockDelegate.modelData.lang ?? "") : ""
                                                                fillMode: Image.PreserveAspectFit
                                                                asynchronous: true
                                                            }
                                                        }

                                                        // Rich Text for Heading / Bullet / Todo / Paragraph / Quote / Callout / Code / Math
                                                        Text {
                                                            visible: blockDelegate.modelData.kind !== "table"
                                                                && blockDelegate.modelData.kind !== "divider"
                                                                && blockDelegate.modelData.kind !== "hr"
                                                                && blockDelegate.modelData.kind !== "image"
                                                                && !(blockDelegate.modelData.kind === "heading" && Boolean(blockDelegate.modelData.calloutType))
                                                            Layout.fillWidth: true
                                                            textFormat: (blockDelegate.modelData.kind === "code" || blockDelegate.modelData.kind === "math") ? Text.PlainText : Text.RichText
                                                            text: (blockDelegate.modelData.kind === "code" || blockDelegate.modelData.kind === "math")
                                                                ? String(blockDelegate.modelData.text ?? "")
                                                                : (blockDelegate.modelData.richHtml ? root.themeRichHtml(blockDelegate.modelData.richHtml) : String(blockDelegate.modelData.text ?? ""))
                                                            wrapMode: Text.Wrap
                                                            font.family: (blockDelegate.modelData.kind === "code" || blockDelegate.modelData.kind === "math") ? Appearance.font.family.monospace : Appearance.font.family.main
                                                            font.pixelSize: {
                                                                if (blockDelegate.modelData.kind === "heading") {
                                                                    const lvl = blockDelegate.modelData.level ?? 1;
                                                                    if (lvl === 1)
                                                                        return 21;
                                                                    if (lvl === 2)
                                                                        return 18;
                                                                    return 16;
                                                                }
                                                                return Appearance.font.pixelSize.small + 1;
                                                            }
                                                            font.weight: blockDelegate.modelData.kind === "heading" ? Font.Bold : Font.Normal
                                                            font.strikeout: blockDelegate.modelData.todoState === "DONE"
                                                            color: blockDelegate.modelData.todoState === "DONE" ? settledColors.colSubtext : settledColors.colOnLayer1
                                                            onLinkActivated: link => {
                                                                if (!root.nexus)
                                                                    return;
                                                                if (link.startsWith("wikilink:")) {
                                                                    root.nexus.followWikilink(decodeURIComponent(link.substring("wikilink:".length)));
                                                                } else if (link.startsWith("tag:")) {
                                                                    const tag = decodeURIComponent(link.substring("tag:".length));
                                                                    root.nexus.leftSidebarTab = "search";
                                                                    root.nexus.searchVault("#" + tag);
                                                                }
                                                            }

                                                            MouseArea {
                                                                anchors.fill: parent
                                                                cursorShape: Qt.IBeamCursor
                                                                onPressed: mouse => {
                                                                    // Let rich-text links work if clicked on an anchor, otherwise enter inline editing on click
                                                                    const linkAt = parent.linkAt ? parent.linkAt(mouse.x, mouse.y) : "";
                                                                    if (linkAt && String(linkAt).length > 0) {
                                                                        mouse.accepted = false;
                                                                        return;
                                                                    }
                                                                }
                                                                onClicked: {
                                                                    if (standardNotePaperCard.isStandardSheet && (root.nexus?.editorMode ?? "hybrid") === "hybrid") {
                                                                        root.startStandardNoteInlineEdit();
                                                                    }
                                                                }
                                                            }
                                                        }

                                                        // Table Grid rendering
                                                        ColumnLayout {
                                                            visible: blockDelegate.modelData.kind === "table"
                                                            Layout.fillWidth: true
                                                            spacing: 2

                                                            RowLayout {
                                                                Layout.fillWidth: true
                                                                spacing: 8
                                                                Repeater {
                                                                    model: blockDelegate.modelData.tableHeaders ?? []
                                                                    delegate: StyledText {
                                                                        required property var modelData
                                                                        Layout.fillWidth: true
                                                                        text: String(modelData)
                                                                        font.weight: Font.Bold
                                                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                                                        color: settledColors.colPrimary
                                                                    }
                                                                }
                                                            }
                                                            Rectangle {
                                                                Layout.fillWidth: true
                                                                height: 1
                                                                color: settledColors.colLayer0Border
                                                            }
                                                            Repeater {
                                                                model: blockDelegate.modelData.tableRows ?? []
                                                                delegate: RowLayout {
                                                                    required property var modelData
                                                                    Layout.fillWidth: true
                                                                    spacing: 8
                                                                    Repeater {
                                                                        model: modelData
                                                                        delegate: StyledText {
                                                                            required property var modelData
                                                                            Layout.fillWidth: true
                                                                            text: String(modelData)
                                                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                                                            color: settledColors.colOnLayer1
                                                                        }
                                                                    }
                                                                }
                                                            }
                                                        }
                                                    }

                                                    // Folded indicator pill
                                                    Rectangle {
                                                        visible: blockDelegate.isFolded
                                                        height: 18
                                                        width: 54
                                                        radius: 9
                                                        color: settledColors.colSecondaryContainer
                                                        StyledText {
                                                            anchors.centerIn: parent
                                                            text: "⋯ folded"
                                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                                            color: settledColors.colPrimary
                                                        }
                                                    }

                                                    // Inline Edit Block button (disabled: editing now uses unified note editing mode)
                                                    Rectangle {
                                                        visible: false
                                                        width: 22
                                                        height: 22
                                                        radius: 5
                                                        color: settledColors.colLayer2
                                                        MaterialSymbol {
                                                            anchors.centerIn: parent
                                                            text: "edit"
                                                            iconSize: 13
                                                            color: settledColors.colSubtext
                                                        }
                                                        MouseArea {
                                                            anchors.fill: parent
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: {
                                                                if (root.nexus) {
                                                                    root.nexus.editingBlockText = blockDelegate.modelData.rawText;
                                                                    root.nexus.editingBlockId = blockDelegate.modelData.id;
                                                                }
                                                            }
                                                        }
                                                    }
                                                }

                                                MouseArea {
                                                    id: blockHover
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    acceptedButtons: Qt.NoButton
                                                }
                                            }
                                        }
                                    }
                                    }
                                        }
                                    }

                                    // Expand main note area to fill bottom viewport space across all tabs so Linked References only appears on scroll
                                    Item {
                                        id: outlinerBottomViewportFiller
                                        objectName: "nexusOutlinerBottomViewportFiller"
                                        readonly property int contentAboveHeight: (nexusCustomViewsLoader.item ? nexusCustomViewsLoader.item.implicitHeight : 0)
                                            + (standardNotePaperCard.visible ? standardNotePaperCard.implicitHeight : 0)
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: Math.max(0, outlinerFlickable.height - contentAboveHeight)
                                        visible: Layout.preferredHeight > 0

                                        MouseArea {
                                            anchors.fill: parent
                                            enabled: false
                                        }
                                    }

                                    // ── Linked References (Backlinks) & Unlinked Mentions Footer ──
                                    Rectangle {
                                        id: linkedRefsDivider
                                        objectName: "nexusLinkedReferencesDivider"
                                        Layout.fillWidth: true
                                        Layout.topMargin: 16
                                        height: 1
                                        color: settledColors.colLayer0Border
                                    }

                                    StyledText {
                                        id: linkedRefsHeader
                                        objectName: "nexusLinkedReferencesHeader"
                                        Layout.topMargin: 6
                                        text: "Linked References (" + String((root.nexus?.currentDoc?.backlinks ?? []).length) + ")"
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        font.weight: Font.Bold
                                        color: settledColors.colPrimary
                                    }

                                    Repeater {
                                        model: root.nexus?.currentDoc?.backlinks ?? []
                                        delegate: Rectangle {
                                            required property var modelData
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 46
                                            radius: 8
                                            color: settledColors.colLayer0

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.margins: 8
                                                spacing: 8

                                                MaterialSymbol {
                                                    text: "subdirectory_arrow_right"
                                                    iconSize: 15
                                                    color: settledColors.colPrimary
                                                }
                                                ColumnLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 2
                                                    StyledText {
                                                        text: String(modelData.title ?? "") + "  (L" + String(modelData.line ?? 1) + ")"
                                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                                        font.weight: Font.DemiBold
                                                        color: settledColors.colOnLayer1
                                                    }
                                                    StyledText {
                                                        Layout.fillWidth: true
                                                        text: String(modelData.snippet ?? "")
                                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                                        color: settledColors.colSubtext
                                                        elide: Text.ElideRight
                                                    }
                                                }
                                            }
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    if (root.nexus)
                                                        root.nexus.openFile(modelData.relPath, true);
                                                }
                                            }
                                        }
                                    }

                                    StyledText {
                                        visible: (root.nexus?.currentDoc?.unlinkedMentions ?? []).length > 0
                                        Layout.topMargin: 8
                                        text: "Unlinked Mentions (" + String((root.nexus?.currentDoc?.unlinkedMentions ?? []).length) + ")"
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        font.weight: Font.Bold
                                        color: settledColors.colSubtext
                                    }

                                    Repeater {
                                        model: root.nexus?.currentDoc?.unlinkedMentions ?? []
                                        delegate: Rectangle {
                                            required property var modelData
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 46
                                            radius: 8
                                            color: settledColors.colLayer0

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.margins: 8
                                                spacing: 8

                                                ColumnLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 2
                                                    StyledText {
                                                        text: String(modelData.title ?? "") + "  (L" + String(modelData.line ?? 1) + ")"
                                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                                        font.weight: Font.DemiBold
                                                        color: settledColors.colOnLayer1
                                                    }
                                                    StyledText {
                                                        Layout.fillWidth: true
                                                        text: String(modelData.snippet ?? "")
                                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                                        color: settledColors.colSubtext
                                                        elide: Text.ElideRight
                                                    }
                                                }

                                                Rectangle {
                                                    height: 26
                                                    width: 68
                                                    radius: 6
                                                    color: settledColors.colSecondaryContainer
                                                    StyledText {
                                                        anchors.centerIn: parent
                                                        text: "[[Link]]"
                                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                                        font.weight: Font.Bold
                                                        color: settledColors.colPrimary
                                                    }
                                                    MouseArea {
                                                        anchors.fill: parent
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            if (root.nexus)
                                                                root.nexus.linkUnlinkedMention(modelData.relPath, modelData.line, root.nexus.currentDoc.title);
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // ── Pane 2: Raw Vim Markdown / Code Editor ──
                            Rectangle {
                                id: vimEditorPane
                                objectName: "nexusVimEditorPane"
                                visible: (root.nexus?.currentDoc?.category === "code") || ((root.nexus?.editorMode ?? "hybrid") === "raw") || ((root.nexus?.editorMode ?? "hybrid") === "split")
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                radius: 10
                                color: settledColors.colLayer0
                                border.width: 1
                                border.color: (root.nexus?.vimMode === "INSERT") ? settledColors.colPrimary : settledColors.colLayer0Border
                                clip: true

                                onVisibleChanged: {
                                    if (visible) {
                                        root.cursorBlinkOn = true;
                                        vimEditorArea.forceActiveFocus();
                                        vimEditorArea.cursorVisible = true;
                                    }
                                }

                                HoverHandler {
                                    cursorShape: Qt.IBeamCursor
                                }

                                ScrollView {
                                    anchors.fill: parent
                                    anchors.margins: 10
                                    clip: true

                                    TextArea {
                                        id: vimEditorArea
                                        objectName: "nexusVimEditorArea"
                                        text: root.nexus?.draftContent ?? ""
                                        font.family: Appearance.font.family.monospace
                                        font.pixelSize: Appearance.font.pixelSize.small + 1
                                        color: settledColors.colOnLayer1
                                        selectionColor: settledColors.colPrimary
                                        selectedTextColor: settledColors.colOnPrimary
                                        wrapMode: TextEdit.Wrap
                                        background: null
                                        cursorVisible: vimEditorPane.visible
                                        readOnly: (root.nexus?.vimEnabled ?? true) && (root.nexus?.vimMode ?? "NORMAL") !== "INSERT"

                                        onActiveFocusChanged: {
                                            if (activeFocus && vimEditorPane.visible)
                                                cursorVisible = true;
                                        }
                                        onReadOnlyChanged: {
                                            if (vimEditorPane.visible)
                                                cursorVisible = true;
                                        }

                                        cursorDelegate: Rectangle {
                                            readonly property bool isNormalBlock: (root.nexus?.vimEnabled ?? true) && (root.nexus?.vimMode ?? "NORMAL") !== "INSERT"
                                            width: isNormalBlock ? 8 : 2
                                            height: vimEditorArea.cursorRectangle.height > 0 ? vimEditorArea.cursorRectangle.height : 18
                                            radius: isNormalBlock ? 2 : 1
                                            color: isNormalBlock
                                                ? Qt.alpha(settledColors.colPrimary, 0.50)
                                                : settledColors.colPrimary
                                            border.width: isNormalBlock ? 1 : 0
                                            border.color: settledColors.colPrimary
                                            visible: vimEditorPane.visible && !vimImmediateCursorOverlay.visible
                                        }

                                        // Explicit frame-1 Vim block cursor overlay when QQuickTextEdit is readOnly (since Qt6 C++ setReadOnly(true) suppresses cursorDelegate)
                                        Rectangle {
                                            id: vimImmediateCursorOverlay
                                            objectName: "nexusVimCursorOverlay"
                                            readonly property bool isNormalBlock: (root.nexus?.vimEnabled ?? true) && (root.nexus?.vimMode ?? "NORMAL") !== "INSERT"
                                            visible: vimEditorPane.visible && isNormalBlock
                                            x: Math.max(0, vimEditorArea.cursorRectangle.x)
                                            y: Math.max(0, vimEditorArea.cursorRectangle.y)
                                            width: 8
                                            height: vimEditorArea.cursorRectangle.height > 0 ? vimEditorArea.cursorRectangle.height : 18
                                            radius: 2
                                            color: Qt.alpha(settledColors.colPrimary, 0.48)
                                            border.width: 1
                                            border.color: settledColors.colPrimary
                                            z: 5
                                        }

                                        onTextChanged: {
                                            if (root.nexus && text !== root.nexus.draftContent) {
                                                root.nexus.draftContent = text;
                                                root.nexus.isDirty = (text !== String(root.nexus.currentDoc?.content ?? ""));
                                            }
                                        }

                                        Keys.onPressed: event => {
                                            if ((event.modifiers & (Qt.ControlModifier | Qt.AltModifier)) !== 0 && root.nexus && root.nexus.handleKeyEvent(event)) {
                                                event.accepted = true;
                                                return;
                                            }
                                            if (root.vimHandleNormalKey(event, vimEditorArea)) {
                                                event.accepted = true;
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    // Bottom 16px hover strip that reveals the status bar on hover
                    Item {
                        id: statusBarEdgeTrigger
                        objectName: "nexusStatusBarEdgeTrigger"
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: 16
                        z: 30
                        HoverHandler {
                            id: statusBarEdgeHover
                        }
                    }
                }

                // ── Bottom Vim Status & Command Bar (:w, :q, :wq, :daily, /search) — Hover Slide Animation ──
                Rectangle {
                    id: nexusStatusBar
                    objectName: "nexusStatusBar"
                    readonly property bool statusBarShown: statusBarEdgeHover.hovered
                        || statusBarSelfHover.hovered
                        || (root.nexus?.vimMode === "COMMAND")
                        || (root.nexus?.vimMode === "SEARCH")
                    Layout.fillWidth: true
                    Layout.preferredHeight: statusBarShown ? 30 : 0
                    Layout.minimumHeight: statusBarShown ? 30 : 0
                    Layout.maximumHeight: statusBarShown ? 30 : 0
                    opacity: statusBarShown ? 1.0 : 0.0
                    clip: true
                    color: settledColors.colLayer0
                    bottomLeftRadius: Math.max(0, nexusMainCard.radius - 1)
                    bottomRightRadius: Math.max(0, nexusMainCard.radius - 1)
                    Behavior on Layout.preferredHeight {
                        NumberAnimation {
                            duration: 180
                            easing.type: Easing.OutCubic
                        }
                    }
                    Behavior on opacity {
                        NumberAnimation {
                            duration: 160
                            easing.type: Easing.OutCubic
                        }
                    }

                    HoverHandler {
                        id: statusBarSelfHover
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 10

                        StyledText {
                            text: (root.nexus?.vimMode === "COMMAND") ? ":" : ((root.nexus?.vimMode === "SEARCH") ? "/" : String(root.nexus?.vimStatusMessage ?? "READY"))
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: settledColors.colPrimary
                        }

                        TextField {
                            id: vimCommandInput
                            objectName: "nexusVimCommandInput"
                            visible: (root.nexus?.vimMode === "COMMAND") || (root.nexus?.vimMode === "SEARCH")
                            Layout.fillWidth: true
                            placeholderText: (root.nexus?.vimMode === "COMMAND") ? "w | q | wq | daily | home | graph | e <note>" : "Search pattern..."
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: settledColors.colOnLayer1
                            background: null
                            onVisibleChanged: {
                                if (!visible) {
                                    vimCommandInput.focus = false;
                                    root.restoreWorkspaceFocus();
                                    Qt.callLater(root.restoreWorkspaceFocus);
                                }
                            }
                            onAccepted: {
                                if (!root.nexus)
                                    return;
                                if (root.nexus.vimMode === "COMMAND") {
                                    root.nexus.executeVimExCommand(text);
                                } else if (root.nexus.vimMode === "SEARCH") {
                                    root.nexus.vimSearchQuery = text;
                                    root.nexus.vimMode = "NORMAL";
                                    if (vimEditorArea && text.length > 0) {
                                        const idx = vimEditorArea.text.toLowerCase().indexOf(text.toLowerCase());
                                        if (idx !== -1)
                                            vimEditorArea.cursorPosition = idx;
                                    }
                                }
                                text = "";
                                vimCommandInput.focus = false;
                                root.restoreWorkspaceFocus();
                                Qt.callLater(root.restoreWorkspaceFocus);
                            }
                            Keys.onEscapePressed: event => {
                                if (root.nexus) {
                                    root.nexus.vimMode = "NORMAL";
                                    text = "";
                                }
                                vimCommandInput.focus = false;
                                root.restoreWorkspaceFocus();
                                Qt.callLater(root.restoreWorkspaceFocus);
                                event.accepted = true;
                            }
                            Keys.onPressed: event => {
                                if ((event.modifiers & (Qt.AltModifier | Qt.ControlModifier | Qt.MetaModifier)) !== 0
                                    && root.nexus && root.nexus.handleKeyEvent(event)) {
                                    event.accepted = true;
                                }
                            }
                        }

                        Item {
                            visible: !vimCommandInput.visible
                            Layout.fillWidth: true
                        }

                        StyledText {
                            visible: Boolean(root.nexus?.currentDoc)
                            text: String(root.nexus?.currentDoc?.language ?? "markdown").toUpperCase() + "  ·  " + String(root.nexus?.currentDoc?.lineCount ?? 0) + " lines"
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: settledColors.colSubtext
                        }
                    }
                }
            }
        }

        // Horizontal Splitter between Main Center Card and Right Sidebar (Hover-only)
        Rectangle {
            id: nexusRightSidebarSplitter
            objectName: "nexusRightSidebarSplitter"
            visible: Boolean(root.nexus?.rightSidebarOpen ?? true)
            Layout.preferredWidth: 6
            Layout.minimumWidth: 6
            Layout.maximumWidth: 6
            Layout.fillHeight: true
            radius: 3
            readonly property bool active: rightSidebarResizeMouse.pressed || rightSidebarResizeMouse.containsMouse || nexusRightSidebarResizeHandle.pressed || nexusRightSidebarResizeHandle.containsMouse
            opacity: active ? 1.0 : 0.0
            color: active ? settledColors.colPrimary : "transparent"
            Behavior on opacity {
                NumberAnimation { duration: 150 }
            }

            Rectangle {
                anchors.centerIn: parent
                width: 2
                height: 44
                radius: 1
                color: nexusRightSidebarSplitter.active
                    ? settledColors.colOnPrimary
                    : settledColors.colLayer0Border
            }

            MouseArea {
                id: rightSidebarResizeMouse
                anchors.fill: parent
                hoverEnabled: true
                preventStealing: true
                cursorShape: Qt.SplitHCursor
                property real pressRootX: 0
                property int pressSidebarWidth: 288
                onPressed: mouse => {
                    const pt = mapToItem(root, mouse.x, 0);
                    pressRootX = pt.x;
                    pressSidebarWidth = root.nexus ? root.nexus.rightSidebarWidth : nexusRightColumn.width;
                }
                onPositionChanged: mouse => {
                    if (!pressed || !root.nexus)
                        return;
                    const pt = mapToItem(root, mouse.x, 0);
                    root.nexus.setRightSidebarWidth(Math.round(pressSidebarWidth + (pressRootX - pt.x)));
                }
            }
        }

        // ═══════════════════════════════════════════════════════════════════
        // RIGHT COLUMN: Resizable & Rearrangeable Card Slots (Slot 2..4)
        // ═══════════════════════════════════════════════════════════════════
        ColumnLayout {
            id: nexusRightColumn
            objectName: "nexusRightColumn"
            visible: Boolean(root.nexus?.rightSidebarOpen ?? true)
            readonly property int targetWidth: Math.round(180 + (Math.max(180, Math.min(540, root.nexus?.rightSidebarWidth ?? 288)) - 180) * root.sidebarExpansionScale)
            Layout.fillWidth: false
            Layout.preferredWidth: targetWidth
            Layout.minimumWidth: targetWidth
            Layout.maximumWidth: targetWidth
            Layout.fillHeight: true
            spacing: 4

            Item {
                id: rightSlot0
                objectName: "nexusRightSlot0"
                readonly property int targetHeight: Math.max(120, Math.round(Math.max(420, nexusRightColumn.height - 16) * (root.nexus?.rightTopRatio ?? 0.34)))
                Layout.fillWidth: true
                Layout.preferredHeight: targetHeight
                Layout.minimumHeight: targetHeight
                Layout.maximumHeight: targetHeight

            // Top Right Card: Mini Calendar & Daily Journal (Obsidian Calendar visual parity)
            Rectangle {
                id: nexusCalendarCard
                objectName: "nexusCalendarCard"
                anchors.fill: parent
                radius: Appearance.rounding.normal ?? 12
                color: settledColors.colLayer1
                border.width: (root.dropTargetCardId === "calendar" && root.draggingCardId !== "" && root.draggingCardId !== "calendar") ? 2 : 1
                border.color: (root.dropTargetCardId === "calendar" && root.draggingCardId !== "" && root.draggingCardId !== "calendar")
                    ? settledColors.colPrimary
                    : settledColors.colLayer0Border
                clip: true

                HoverHandler {
                    id: calendarCardHover
                }

                readonly property string monthLabel: {
                    const hdr = String(root.nexus?.calendarHeader || "Nov 2026").trim();
                    const parts = hdr.split(/\s+/);
                    return parts.length > 0 ? parts[0].substring(0, 3) : "Nov";
                }
                readonly property string yearLabel: {
                    const hdr = String(root.nexus?.calendarHeader || "Nov 2026").trim();
                    const parts = hdr.split(/\s+/);
                    return parts.length > 1 ? parts[parts.length - 1] : String(root.nexus?.calendarYear || 2026);
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 5

                    // Calendar Header: Month (text-normal) + Year (colPrimary) + < TODAY > + Reorder Pill
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        RowLayout {
                            spacing: 5
                            StyledText {
                                text: nexusCalendarCard.monthLabel
                                font.pixelSize: 15
                                font.weight: Font.Bold
                                color: settledColors.colOnLayer1
                            }
                            StyledText {
                                text: nexusCalendarCard.yearLabel
                                font.pixelSize: 15
                                font.weight: Font.Bold
                                color: settledColors.colPrimary
                            }
                        }

                        Item {
                            Layout.fillWidth: true
                        }

                        Rectangle {
                            width: 20
                            height: 20
                            radius: 5
                            color: prevCalMouse.containsMouse ? settledColors.colLayer2Hover : "transparent"
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "chevron_left"
                                iconSize: 14
                                color: settledColors.colSubtext
                            }
                            MouseArea {
                                id: prevCalMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (root.nexus)
                                        root.nexus.prevCalendarMonth();
                                }
                            }
                        }

                        Rectangle {
                            height: 20
                            width: 42
                            radius: 5
                            color: todayCalMouse.containsMouse ? settledColors.colLayer2Hover : "transparent"
                            StyledText {
                                anchors.centerIn: parent
                                text: "TODAY"
                                font.pixelSize: 10
                                font.weight: Font.Bold
                                font.letterSpacing: 0.6
                                color: settledColors.colSubtext
                            }
                            MouseArea {
                                id: todayCalMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (root.nexus) {
                                        root.nexus.jumpCalendarToday();
                                        root.nexus.openDailyNote();
                                    }
                                }
                            }
                        }

                        Rectangle {
                            width: 20
                            height: 20
                            radius: 5
                            color: nextCalMouse.containsMouse ? settledColors.colLayer2Hover : "transparent"
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "chevron_right"
                                iconSize: 14
                                color: settledColors.colSubtext
                            }
                            MouseArea {
                                id: nextCalMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (root.nexus)
                                        root.nexus.nextCalendarMonth();
                                }
                            }
                        }

                        CardReorderPill {
                            cardId: "calendar"
                            cardHovered: calendarCardHover.hovered
                        }
                    }

                    // Weekday Names Row (MON..SUN — uniform muted subtext matching Obsidian Calendar)
                    GridLayout {
                        Layout.fillWidth: true
                        columns: 7
                        columnSpacing: 2

                        Repeater {
                            model: ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]
                            delegate: StyledText {
                                required property string modelData
                                required property int index
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                text: modelData
                                font.pixelSize: 9
                                font.weight: Font.Bold
                                font.letterSpacing: 0.5
                                color: settledColors.colSubtext
                            }
                        }
                    }

                    // 42-cell Calendar Day Grid (matching Obsidian Calendar: 1px inset border on Today with transparent background, journal dot indicator below date)
                    GridLayout {
                        id: calendarGrid
                        objectName: "nexusCalendarGrid"
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.minimumHeight: 132
                        columns: 7
                        columnSpacing: 2
                        rowSpacing: 2

                        Repeater {
                            model: root.nexus?.calendarCells ?? []
                            delegate: Rectangle {
                                id: calDayCell
                                required property var modelData
                                readonly property bool isSelected: (root.nexus?.selectedDateStr ?? "") === modelData.dateStr
                                implicitWidth: 28
                                implicitHeight: 22
                                Layout.minimumWidth: 22
                                Layout.minimumHeight: 18
                                Layout.preferredHeight: Math.max(18, Math.floor((calendarGrid.height - 10) / 6))
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                radius: 6
                                color: (!modelData.isToday && isSelected)
                                    ? Qt.rgba(0.51, 0.76, 0.81, 0.12)
                                    : (dayCellMouse.containsMouse ? settledColors.colLayer2Hover : "transparent")
                                border.width: (modelData.isToday || isSelected) ? 1 : 0
                                border.color: modelData.isToday
                                    ? settledColors.colPrimary
                                    : (isSelected ? Qt.rgba(0.51, 0.76, 0.81, 0.55) : "transparent")
                                opacity: modelData.inMonth ? 1.0 : 0.30

                                ColumnLayout {
                                    anchors.centerIn: parent
                                    spacing: 1

                                    StyledText {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: String(calDayCell.modelData.day ?? "")
                                        font.pixelSize: 11
                                        font.weight: (calDayCell.modelData.isToday || calDayCell.modelData.hasJournal || calDayCell.isSelected) ? Font.DemiBold : Font.Normal
                                        color: calDayCell.modelData.isToday
                                            ? settledColors.colPrimary
                                            : settledColors.colOnLayer1
                                    }

                                    Item {
                                        Layout.alignment: Qt.AlignHCenter
                                        implicitWidth: 10
                                        implicitHeight: 5
                                        height: 5

                                        Rectangle {
                                            anchors.centerIn: parent
                                            visible: Boolean(calDayCell.modelData.hasJournal)
                                            width: 4
                                            height: 4
                                            radius: 2
                                            color: settledColors.colPrimary
                                        }
                                    }
                                }

                                MouseArea {
                                    id: dayCellMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (root.nexus) {
                                            root.nexus.selectedDateStr = calDayCell.modelData.dateStr;
                                            if (GlobalStates.dashboardPlannerBrowser) {
                                                const nextState = Object.assign({}, GlobalStates.dashboardPlannerBrowser);
                                                nextState.selectedDateIso = calDayCell.modelData.dateStr;
                                                GlobalStates.dashboardPlannerBrowser = nextState;
                                            }
                                            root.nexus.openDailyNote(calDayCell.modelData.dateStr);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            }

            // Vertical Splitter between Right Slot 0 and Right Slot 1 (Hover-only)
            Rectangle {
                id: nexusRightTopCardSplitter
                objectName: "nexusRightTopCardSplitter"
                z: 40
                Layout.fillWidth: true
                Layout.preferredHeight: 6
                radius: 3
                readonly property bool active: rightTopSplitMouse.pressed || rightTopSplitMouse.containsMouse
                opacity: active ? 1.0 : 0.0
                color: active ? settledColors.colPrimary : "transparent"
                Behavior on opacity {
                    NumberAnimation { duration: 150 }
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: 36
                    height: 2
                    radius: 1
                    color: nexusRightTopCardSplitter.active
                        ? settledColors.colOnPrimary
                        : settledColors.colLayer0Border
                }

                MouseArea {
                    id: rightTopSplitMouse
                    anchors.fill: parent
                    anchors.topMargin: -5
                    anchors.bottomMargin: -5
                    hoverEnabled: true
                    preventStealing: true
                    cursorShape: Qt.SplitVCursor
                    onPositionChanged: mouse => {
                        if (!pressed || !root.nexus)
                            return;
                        const pt = mapToItem(nexusRightColumn, 0, mouse.y);
                        const totalH = Math.max(360, nexusRightColumn.height - 12);
                        root.nexus.setRightTopRatio(pt.y / totalH);
                    }
                }
            }

            Item {
                id: rightSlot1
                objectName: "nexusRightSlot1"
                readonly property int targetHeight: Math.max(110, Math.round(Math.max(420, nexusRightColumn.height - 16) * (root.nexus?.rightMidRatio ?? 0.32)))
                Layout.fillWidth: true
                Layout.preferredHeight: targetHeight
                Layout.minimumHeight: targetHeight
                Layout.maximumHeight: targetHeight

            // Middle Right Card: Full-Bleed Vault Graph with Hover-Only Floating Header
            Rectangle {
                id: nexusVaultGraphCard
                objectName: "nexusVaultGraphCard"
                anchors.fill: parent
                radius: Appearance.rounding.normal ?? 12
                color: settledColors.colLayer1
                border.width: (root.dropTargetCardId === "vaultGraph" && root.draggingCardId !== "" && root.draggingCardId !== "vaultGraph") ? 2 : 1
                border.color: (root.dropTargetCardId === "vaultGraph" && root.draggingCardId !== "" && root.draggingCardId !== "vaultGraph")
                    ? settledColors.colPrimary
                    : settledColors.colLayer0Border
                clip: true

                HoverHandler {
                    id: vaultGraphCardHover
                }

                property bool _graphSettledOnce: false
                Component.onCompleted: {
                    if (root.transitionSettled)
                        _graphSettledOnce = true;
                }
                Connections {
                    target: root
                    function onTransitionSettledChanged() {
                        if (root.transitionSettled && !nexusVaultGraphCard._graphSettledOnce)
                            nexusVaultGraphCard._graphSettledOnce = true;
                    }
                }

                readonly property var graphData: (root.transitionSettled || nexusVaultGraphCard._graphSettledOnce || !Boolean(root.nexus?.isOpen))
                    ? (root.nexus?.vaultGraph ?? {
                        "nodes": [],
                        "edges": [],
                        "groups": []
                    })
                    : ({
                        "nodes": [],
                        "edges": [],
                        "groups": []
                    })
                onGraphDataChanged: {
                    if ((graphData?.nodes?.length ?? 0) > 0 && !nexusVaultGraphCard._graphSettledOnce)
                        nexusVaultGraphCard._graphSettledOnce = true;
                    vaultGraphCanvas.requestPaint();
                }

                NexusGraphCanvas {
                    id: vaultGraphCanvas
                    objectName: "nexusVaultGraphCanvas"
                    anchors.fill: parent
                    anchors.margins: 4
                    workspace: root
                    isLocal: false
                    compact: true
                    revealStaggerMs: 36
                    graphData: nexusVaultGraphCard.graphData
                    currentPath: String(root.nexus?.currentPath ?? "")
                    clusterPalette: root.clusterPalette
                    onNodeActivated: nodeData => {
                        if (root.nexus && nodeData && nodeData.relPath)
                            root.nexus.openFile(nodeData.relPath, true);
                    }
                }

                // Floating top header bar (shown on hover)
                RowLayout {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 8
                    spacing: 6
                    z: 10
                    opacity: (vaultGraphCardHover.hovered || root.draggingCardId.length > 0) ? 1.0 : 0.0
                    Behavior on opacity {
                        NumberAnimation { duration: 150 }
                    }

                    MaterialSymbol {
                        text: "scatter_plot"
                        iconSize: 15
                        color: settledColors.colPrimary
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: "Vault Graph"
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.DemiBold
                        color: settledColors.colOnLayer1
                    }
                    Rectangle {
                        width: 20
                        height: 20
                        radius: 5
                        color: settledColors.colLayer0
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "open_in_full"
                            iconSize: 13
                            color: settledColors.colSubtext
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (root.nexus)
                                    root.nexus.openGraphView();
                            }
                        }
                    }
                    CardReorderPill {
                        cardId: "vaultGraph"
                        cardHovered: vaultGraphCardHover.hovered
                    }
                }
            }
            }

            // Vertical Splitter between Right Slot 1 and Right Slot 2 (Hover-only)
            Rectangle {
                id: nexusRightMidCardSplitter
                objectName: "nexusRightMidCardSplitter"
                z: 40
                Layout.fillWidth: true
                Layout.preferredHeight: 6
                radius: 3
                readonly property bool active: rightMidSplitMouse.pressed || rightMidSplitMouse.containsMouse
                opacity: active ? 1.0 : 0.0
                color: active ? settledColors.colPrimary : "transparent"
                Behavior on opacity {
                    NumberAnimation { duration: 150 }
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: 36
                    height: 2
                    radius: 1
                    color: nexusRightMidCardSplitter.active
                        ? settledColors.colOnPrimary
                        : settledColors.colLayer0Border
                }

                MouseArea {
                    id: rightMidSplitMouse
                    anchors.fill: parent
                    anchors.topMargin: -5
                    anchors.bottomMargin: -5
                    hoverEnabled: true
                    preventStealing: true
                    cursorShape: Qt.SplitVCursor
                    onPositionChanged: mouse => {
                        if (!pressed || !root.nexus)
                            return;
                        const pt = mapToItem(nexusRightColumn, 0, mouse.y);
                        const totalH = Math.max(360, nexusRightColumn.height - 12);
                        const topRatio = root.nexus.rightTopRatio ?? 0.34;
                        root.nexus.setRightMidRatio((pt.y / totalH) - topRatio);
                    }
                }
            }

            Item {
                id: rightSlot2
                objectName: "nexusRightSlot2"
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 110

            // Bottom Right Card: Weekly Planner (synced with Dashboard Weekly Planner) / Outline / Flashcards
            Rectangle {
                id: nexusContextCard
                objectName: "nexusContextCard"
                anchors.fill: parent
                radius: Appearance.rounding.normal ?? 12
                color: settledColors.colLayer1
                border.width: (root.dropTargetCardId === "context" && root.draggingCardId !== "" && root.draggingCardId !== "context") ? 2 : 1
                border.color: (root.dropTargetCardId === "context" && root.draggingCardId !== "" && root.draggingCardId !== "context")
                    ? settledColors.colPrimary
                    : settledColors.colLayer0Border
                clip: true

                HoverHandler {
                    id: contextCardHover
                }

                property int weekDayOffset: Number(GlobalStates.dashboardPlannerBrowser?.weekOffset ?? 0)
                onWeekDayOffsetChanged: {
                    if (GlobalStates.dashboardPlannerBrowser && Number(GlobalStates.dashboardPlannerBrowser.weekOffset ?? 0) !== weekDayOffset) {
                        const nextState = Object.assign({}, GlobalStates.dashboardPlannerBrowser);
                        nextState.weekOffset = weekDayOffset;
                        GlobalStates.dashboardPlannerBrowser = nextState;
                    }
                }
                Connections {
                    target: GlobalStates
                    function onDashboardPlannerBrowserChanged() {
                        const extOffset = Number(GlobalStates.dashboardPlannerBrowser?.weekOffset ?? 0);
                        if (nexusContextCard.weekDayOffset !== extOffset)
                            nexusContextCard.weekDayOffset = extOffset;
                        const extIso = String(GlobalStates.dashboardPlannerBrowser?.selectedDateIso ?? "");
                        if (root.nexus && /^\d{4}-\d{2}-\d{2}$/.test(extIso) && root.nexus.selectedDateStr !== extIso)
                            root.nexus.selectedDateStr = extIso;
                    }
                }
                readonly property string activePlannerDateIso: {
                    const sel = String(root.nexus?.selectedDateStr ?? "");
                    if (/^\d{4}-\d{2}-\d{2}$/.test(sel))
                        return sel;
                    const dashIso = String(GlobalStates.dashboardPlannerBrowser?.selectedDateIso ?? "");
                    if (/^\d{4}-\d{2}-\d{2}$/.test(dashIso))
                        return dashIso;
                    return Qt.formatDate(new Date(), "yyyy-MM-dd");
                }
                readonly property var activePlannerDateObj: {
                    const _rev = root.plannerSyncRevision;
                    const raw = nexusContextCard.activePlannerDateIso;
                    const parts = raw.split("-");
                    if (parts.length === 3)
                        return new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]), 12, 0, 0, 0);
                    return new Date();
                }
                readonly property var weekDaysModel: {
                    const names = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"];
                    const raw = nexusContextCard.activePlannerDateIso;
                    let base = new Date();
                    if (/^\d{4}-\d{2}-\d{2}$/.test(raw)) {
                        const parts = raw.split("-");
                        base = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]));
                    }
                    base = new Date(base.getFullYear(), base.getMonth(), base.getDate() + nexusContextCard.weekDayOffset * 7);
                    const wd = (base.getDay() + 6) % 7;
                    const monday = new Date(base.getFullYear(), base.getMonth(), base.getDate() - wd);
                    const todayIso = Qt.formatDate(new Date(), "yyyy-MM-dd");
                    const out = [];
                    for (let i = 0; i < 7; ++i) {
                        const d = new Date(monday.getFullYear(), monday.getMonth(), monday.getDate() + i);
                        const iso = Qt.formatDate(d, "yyyy-MM-dd");
                        out.push({
                            "label": names[i],
                            "day": d.getDate(),
                            "dateStr": iso,
                            "isToday": iso === todayIso,
                            "isSelected": iso === raw
                        });
                    }
                    return out;
                }
                readonly property string weekMonthHeader: {
                    const days = nexusContextCard.weekDaysModel;
                    if (!days || days.length < 4)
                        return root.nexus?.calendarHeader || "Nov 2026";
                    const midParts = String(days[3].dateStr).split("-");
                    if (midParts.length === 3) {
                        const mNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
                        const mIdx = Math.max(0, Math.min(11, Number(midParts[1]) - 1));
                        return mNames[mIdx] + " " + midParts[0];
                    }
                    return root.nexus?.calendarHeader || "Nov 2026";
                }

                function _matchesPlannerDate(ev, targetIso: string): bool {
                    if (!ev || !targetIso)
                        return false;
                    const dayObj = PlannerProjection.projectDay([ev], [], targetIso, 1);
                    return (dayObj.timed && dayObj.timed.length > 0) || (dayObj.allDay && dayObj.allDay.length > 0);
                }

                // Live Dashboard Weekly Planner Projection for the selected date (replaces old 97_Daily_Schedule markdown table)
                readonly property var plannerDayProjection: {
                    const _rev = root.plannerRevision;
                    return PlannerProjection.projectDay(
                        HostServices.Events?.list ?? [],
                        HostServices.CalendarSync?.events ?? [],
                        nexusContextCard.activePlannerDateObj,
                        1
                    );
                }

                readonly property var syncedAllDayItems: plannerDayProjection.allDay ?? []
                readonly property var syncedTimedItems: plannerDayProjection.timed ?? []

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 6

                    // Top Navigation Header: < Today >   Nov 2026   [Dashboard]   ⋮   < :: >
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        Rectangle {
                            visible: (root.nexus?.rightBottomTab ?? "schedule") === "schedule"
                            width: 18
                            height: 20
                            radius: 4
                            color: prevWeekMouse.containsMouse ? settledColors.colLayer2Hover : "transparent"
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "chevron_left"
                                iconSize: 13
                                color: settledColors.colSubtext
                            }
                            MouseArea {
                                id: prevWeekMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: nexusContextCard.weekDayOffset -= 1
                            }
                        }

                        Rectangle {
                            visible: (root.nexus?.rightBottomTab ?? "schedule") === "schedule"
                            height: 20
                            width: 38
                            radius: 4
                            color: todayWeekMouse.containsMouse ? settledColors.colLayer2Hover : "transparent"
                            StyledText {
                                anchors.centerIn: parent
                                text: "Today"
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: settledColors.colOnLayer1
                            }
                            MouseArea {
                                id: todayWeekMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    nexusContextCard.weekDayOffset = 0;
                                    if (root.nexus)
                                        root.nexus.jumpCalendarToday();
                                }
                            }
                        }

                        Rectangle {
                            visible: (root.nexus?.rightBottomTab ?? "schedule") === "schedule"
                            width: 18
                            height: 20
                            radius: 4
                            color: nextWeekMouse.containsMouse ? settledColors.colLayer2Hover : "transparent"
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "chevron_right"
                                iconSize: 13
                                color: settledColors.colSubtext
                            }
                            MouseArea {
                                id: nextWeekMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: nexusContextCard.weekDayOffset += 1
                            }
                        }

                        // Compact mode tabs when switched to Outline or Cards & ZK
                        Repeater {
                            model: (root.nexus?.rightBottomTab ?? "schedule") === "schedule" ? [] : [
                                { "id": "schedule", "label": "Planner" },
                                { "id": "outline", "label": "Outline" },
                                { "id": "flashcards", "label": "ZK" }
                            ]
                            delegate: Rectangle {
                                required property var modelData
                                readonly property bool active: (root.nexus?.rightBottomTab ?? "schedule") === modelData.id
                                Layout.preferredHeight: 20
                                Layout.preferredWidth: tabTxt.implicitWidth + 12
                                radius: 5
                                color: active ? settledColors.colSecondaryContainer : settledColors.colLayer0
                                StyledText {
                                    id: tabTxt
                                    anchors.centerIn: parent
                                    text: modelData.label
                                    font.pixelSize: 10
                                    font.weight: active ? Font.Bold : Font.Normal
                                    color: active ? settledColors.colOnSecondaryContainer : settledColors.colSubtext
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (root.nexus)
                                            root.nexus.rightBottomTab = modelData.id;
                                    }
                                }
                            }
                        }

                        Item {
                            Layout.fillWidth: true
                        }

                        StyledText {
                            visible: (root.nexus?.rightBottomTab ?? "schedule") === "schedule"
                            text: nexusContextCard.weekMonthHeader
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.weight: Font.DemiBold
                            color: settledColors.colOnLayer1
                        }

                        // Open synced Dashboard Weekly Planner button
                        Rectangle {
                            id: nexusOpenDashboardPlannerButton
                            objectName: "nexusOpenDashboardPlannerButton"
                            visible: (root.nexus?.rightBottomTab ?? "schedule") === "schedule"
                            width: 20
                            height: 20
                            radius: 4
                            color: openDashPlannerMouse.containsMouse ? settledColors.colSecondaryContainer : "transparent"
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "calendar_view_week"
                                iconSize: 13
                                color: settledColors.colPrimary
                            }
                            MouseArea {
                                id: openDashPlannerMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (GlobalStates.dashboardPlannerBrowser) {
                                        const nextState = Object.assign({}, GlobalStates.dashboardPlannerBrowser);
                                        nextState.selectedDateIso = nexusContextCard.activePlannerDateIso;
                                        GlobalStates.dashboardPlannerBrowser = nextState;
                                    }
                                    GlobalStates.dashboardPageId = "weeklyPlanner";
                                    Config.setNestedValue("dashboard.lastPageId", "weeklyPlanner");
                                    GlobalStates.nexusOpen = false;
                                    GlobalStates.dashboardOpen = true;
                                }
                            }
                        }

                        // Cycle Planner / Outline / Flashcards menu button (⋮)
                        Rectangle {
                            width: 18
                            height: 20
                            radius: 4
                            color: modeCycleMouse.containsMouse ? settledColors.colLayer2Hover : "transparent"
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "more_vert"
                                iconSize: 13
                                color: settledColors.colSubtext
                            }
                            MouseArea {
                                id: modeCycleMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (!root.nexus)
                                        return;
                                    const cur = root.nexus.rightBottomTab || "schedule";
                                    root.nexus.rightBottomTab = cur === "schedule" ? "outline" : (cur === "outline" ? "flashcards" : "schedule");
                                }
                            }
                        }

                        CardReorderPill {
                            cardId: "context"
                            cardHovered: contextCardHover.hovered
                        }
                    }

                    // Sub-tab 0 (Default): Weekly Planner (7-day strip + synced all-day events + 24h timeline)
                    ColumnLayout {
                        visible: (root.nexus?.rightBottomTab ?? "schedule") === "schedule"
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 4

                        // 7-Day Week Strip (MON..SUN + day numbers)
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            Repeater {
                                model: nexusContextCard.weekDaysModel
                                delegate: ColumnLayout {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    spacing: 2

                                    StyledText {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: modelData.label
                                        font.pixelSize: 9
                                        font.weight: Font.DemiBold
                                        color: settledColors.colSubtext
                                    }

                                    Rectangle {
                                        Layout.alignment: Qt.AlignHCenter
                                        width: 26
                                        height: 18
                                        radius: 4
                                        color: modelData.isToday
                                            ? settledColors.colPrimary
                                            : (modelData.isSelected ? settledColors.colSecondaryContainer : "transparent")
                                        border.width: (!modelData.isToday && modelData.isSelected) ? 1 : 0
                                        border.color: settledColors.colPrimary

                                        StyledText {
                                            anchors.centerIn: parent
                                            text: String(modelData.day)
                                            font.pixelSize: 10
                                            font.weight: (modelData.isToday || modelData.isSelected) ? Font.Bold : Font.Normal
                                            color: modelData.isToday ? settledColors.colOnPrimary : settledColors.colOnLayer1
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (root.nexus) {
                                                    root.nexus.selectedDateStr = modelData.dateStr;
                                                    if (GlobalStates.dashboardPlannerBrowser) {
                                                        const nextState = Object.assign({}, GlobalStates.dashboardPlannerBrowser);
                                                        nextState.selectedDateIso = modelData.dateStr;
                                                        GlobalStates.dashboardPlannerBrowser = nextState;
                                                    }
                                                }
                                            }
                                            onDoubleClicked: {
                                                if (root.nexus)
                                                    root.nexus.openDailyNote(modelData.dateStr);
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Synced All-Day Events Banner (or "No all day events")
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 24
                            color: "transparent"
                            Rectangle {
                                anchors.top: parent.top
                                width: parent.width
                                height: 1
                                color: settledColors.colLayer0Border
                            }
                            StyledText {
                                visible: nexusContextCard.syncedAllDayItems.length === 0
                                anchors.centerIn: parent
                                text: "No all day events"
                                font.pixelSize: 10
                                color: settledColors.colSubtext
                            }
                            RowLayout {
                                visible: nexusContextCard.syncedAllDayItems.length > 0
                                anchors.fill: parent
                                anchors.leftMargin: 4
                                anchors.rightMargin: 4
                                spacing: 4
                                Repeater {
                                    model: nexusContextCard.syncedAllDayItems.slice(0, 2)
                                    delegate: Rectangle {
                                        required property var modelData
                                        readonly property color evAccent: root.plannerAccentColor(modelData.swatch)
                                        Layout.fillWidth: true
                                        height: 18
                                        radius: 4
                                        color: Qt.tint(settledColors.colLayer2, Qt.rgba(evAccent.r, evAccent.g, evAccent.b, 0.22))
                                        border.width: 1
                                        border.color: Qt.alpha(evAccent, 0.55)
                                        StyledText {
                                            anchors.fill: parent
                                            anchors.leftMargin: 6
                                            anchors.rightMargin: 6
                                            verticalAlignment: Text.AlignVCenter
                                            text: String(modelData.title ?? "")
                                            font.pixelSize: 10
                                            font.weight: Font.DemiBold
                                            color: settledColors.colOnLayer1
                                            elide: Text.ElideRight
                                        }
                                    }
                                }
                            }
                            Rectangle {
                                anchors.bottom: parent.bottom
                                width: parent.width
                                height: 1
                                color: settledColors.colLayer0Border
                            }
                        }

                        // Hourly Timeline (0..23 hours) with synced Dashboard Weekly Planner events and glowing current-time line
                        Flickable {
                            id: weeklyTimelineFlick
                            objectName: "nexusWeeklyPlannerTimeline"
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            readonly property int hourRowHeight: 52
                            readonly property int hourSlotHeight: hourRowHeight
                            contentWidth: width
                            contentHeight: 24 * hourRowHeight
                            function centerOnCurrentTime(): void {
                                const curHour = (new Date()).getHours() + (new Date()).getMinutes() / 60.0;
                                const viewH = Math.max(120, weeklyTimelineFlick.height);
                                const targetY = Math.round(curHour * weeklyTimelineFlick.hourRowHeight - viewH * 0.38);
                                weeklyTimelineFlick.contentY = Math.max(0, Math.min(Math.max(0, 24 * weeklyTimelineFlick.hourRowHeight - viewH), targetY));
                            }
                            Component.onCompleted: centerOnCurrentTime()
                            onHeightChanged: {
                                if (!moving && !dragging)
                                    centerOnCurrentTime();
                            }

                            Item {
                                width: weeklyTimelineFlick.width
                                height: 24 * weeklyTimelineFlick.hourRowHeight

                                Rectangle {
                                    objectName: "nexusWeeklyPlannerGutterDivider"
                                    x: 24
                                    y: 0
                                    width: 1
                                    height: parent.height
                                    color: root.borderSubtle
                                }

                                Repeater {
                                    model: 24
                                    delegate: Item {
                                        required property int index
                                        readonly property int hourNum: index
                                        y: index * weeklyTimelineFlick.hourRowHeight
                                        width: parent.width
                                        height: weeklyTimelineFlick.hourRowHeight

                                        StyledText {
                                            x: 2
                                            y: 3
                                            width: 18
                                            horizontalAlignment: Text.AlignRight
                                            text: String(parent.hourNum)
                                            font.pixelSize: 10
                                            color: settledColors.colSubtext
                                        }

                                        Rectangle {
                                            anchors.left: parent.left
                                            anchors.leftMargin: 26
                                            anchors.right: parent.right
                                            anchors.top: parent.top
                                            anchors.topMargin: 10
                                            height: 1
                                            color: root.borderSubtle
                                        }

                                        MouseArea {
                                            anchors.left: parent.left
                                            anchors.leftMargin: 26
                                            anchors.right: parent.right
                                            anchors.top: parent.top
                                            anchors.bottom: parent.bottom
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (typeof quickPlannerEventInput !== "undefined") {
                                                    const hh = String(parent.hourNum).padStart(2, "0");
                                                    quickPlannerEventInput.text = hh + ":00 ";
                                                    quickPlannerEventInput.forceActiveFocus();
                                                    quickPlannerEventInput.cursorPosition = quickPlannerEventInput.text.length;
                                                }
                                            }
                                        }
                                    }
                                }

                                // Synced Timed Event Blocks (from Dashboard Weekly Planner projection)
                                Repeater {
                                    model: nexusContextCard.syncedTimedItems
                                    delegate: Rectangle {
                                        id: timedEventBlock
                                        required property var modelData
                                        required property int index
                                        objectName: "nexusWeeklyPlannerEvent_" + String(index)
                                        readonly property color evAccent: root.plannerAccentColor(modelData.swatch)
                                        readonly property real startHour: Number(modelData.startMinutes ?? 0) / 60.0
                                        readonly property real durationHours: Math.max(0.45, Number(modelData.durationMinutes ?? 45) / 60.0)
                                        readonly property int overlapCols: Math.max(1, Number(modelData.overlapCount ?? 1))
                                        readonly property int overlapIdx: Math.max(0, Math.min(overlapCols - 1, Number(modelData.overlapCol ?? 0)))
                                        readonly property real trackWidth: Math.max(60, parent.width - 32)
                                        readonly property real colWidth: Math.floor((trackWidth - (overlapCols - 1) * 3) / overlapCols)
                                        x: 28 + overlapIdx * (colWidth + 3)
                                        y: Math.round(startHour * weeklyTimelineFlick.hourRowHeight) + 8
                                        width: Math.max(36, colWidth)
                                        height: Math.max(20, Math.round(durationHours * weeklyTimelineFlick.hourRowHeight) - 2)
                                        radius: 4
                                        color: Qt.tint(settledColors.colLayer2, Qt.rgba(evAccent.r, evAccent.g, evAccent.b, 0.20))
                                        border.width: 1
                                        border.color: Qt.alpha(evAccent, 0.52)
                                        clip: true

                                        Rectangle {
                                            anchors.left: parent.left
                                            anchors.top: parent.top
                                            anchors.bottom: parent.bottom
                                            width: 3
                                            radius: 1.5
                                            color: timedEventBlock.evAccent
                                        }

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 7
                                            anchors.rightMargin: 5
                                            spacing: 5

                                            StyledText {
                                                visible: timedEventBlock.width >= 150
                                                text: String(timedEventBlock.modelData.timeRange ?? "")
                                                font.family: Appearance.font.family.monospace
                                                font.pixelSize: 9
                                                color: timedEventBlock.evAccent
                                            }
                                            StyledText {
                                                Layout.fillWidth: true
                                                text: String(timedEventBlock.modelData.title ?? "")
                                                font.pixelSize: 10
                                                font.weight: Font.DemiBold
                                                color: settledColors.colOnLayer1
                                                elide: Text.ElideRight
                                            }
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (root.nexus)
                                                    root.nexus.openDailyNote(nexusContextCard.activePlannerDateIso);
                                            }
                                        }
                                    }
                                }

                                // Glowing current-time line
                                Item {
                                    objectName: "nexusWeeklyPlannerNowLine"
                                    readonly property var nowDate: new Date()
                                    readonly property real fracHour: Math.max(0.0, Math.min(23.98, nowDate.getHours() + nowDate.getMinutes() / 60.0))
                                    y: Math.round(fracHour * weeklyTimelineFlick.hourRowHeight) + 8
                                    width: parent.width
                                    height: 2

                                    Rectangle {
                                        x: 24
                                        y: -2
                                        width: 3
                                        height: 5
                                        radius: 1.5
                                        color: settledColors.colPrimary
                                    }
                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.leftMargin: 26
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        height: 1.5
                                        color: settledColors.colPrimary
                                    }
                                }
                            }
                        }
                    }

                    // Sub-tab 1: Document Outline & Links
                    ListView {
                        visible: (root.nexus?.rightBottomTab ?? "schedule") === "outline"
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 3
                        model: root.nexus?.currentDoc?.outline ?? []

                        delegate: Rectangle {
                            required property var modelData
                            width: ListView.view.width
                            height: 24
                            radius: 5
                            color: settledColors.colLayer0

                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: 6 + Math.max(0, (modelData.level ?? 1) - 1) * 10
                                anchors.rightMargin: 6
                                text: "#".repeat(modelData.level ?? 1) + " " + String(modelData.text ?? "")
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: settledColors.colOnLayer1
                                elide: Text.ElideRight
                            }
                        }
                    }

                    // Sub-tab 2: Spaced Repetition Flashcards & Quick Zettelkasten Note Capture
                    ColumnLayout {
                        visible: (root.nexus?.rightBottomTab ?? "schedule") === "flashcards"
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 6

                        StyledText {
                            text: "Quick Zettelkasten Capture"
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.weight: Font.Bold
                            color: settledColors.colPrimary
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 28
                            radius: 6
                            color: settledColors.colLayer0
                            TextField {
                                id: zkTitleField
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                placeholderText: "Zettel title..."
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: settledColors.colOnLayer1
                                background: null
                                onAccepted: {
                                    if (root.nexus && text.trim().length > 0) {
                                        root.nexus.captureZettelkastenNote(text.trim(), "");
                                        text = "";
                                        zkTitleField.focus = false;
                                        root.restoreWorkspaceFocus();
                                        Qt.callLater(root.restoreWorkspaceFocus);
                                    }
                                }
                                Keys.onEscapePressed: event => {
                                    zkTitleField.focus = false;
                                    root.restoreWorkspaceFocus();
                                    Qt.callLater(root.restoreWorkspaceFocus);
                                    event.accepted = true;
                                }
                                Keys.onPressed: event => {
                                    if ((event.modifiers & (Qt.AltModifier | Qt.ControlModifier | Qt.MetaModifier)) !== 0
                                        && root.nexus && root.nexus.handleKeyEvent(event)) {
                                        event.accepted = true;
                                    }
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 26
                            radius: 6
                            color: settledColors.colSecondaryContainer
                            StyledText {
                                anchors.centerIn: parent
                                text: "Capture Zettel Note"
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                font.weight: Font.DemiBold
                                color: settledColors.colOnSecondaryContainer
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (root.nexus && zkTitleField.text.trim().length > 0) {
                                        root.nexus.captureZettelkastenNote(zkTitleField.text.trim(), "");
                                        zkTitleField.text = "";
                                        root.focusPrimarySurface();
                                    }
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            height: 1
                            color: settledColors.colLayer0Border
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            StyledText {
                                Layout.fillWidth: true
                                text: "Flashcards (" + String((root.nexus?.currentDoc?.flashcards ?? []).length) + ")"
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                font.weight: Font.Bold
                                color: settledColors.colOnLayer1
                            }
                            Rectangle {
                                visible: (root.nexus?.currentDoc?.flashcards ?? []).length > 0
                                height: 22
                                width: 78
                                radius: 5
                                color: settledColors.colPrimary
                                StyledText {
                                    anchors.centerIn: parent
                                    text: "Sync Deck"
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: settledColors.colOnPrimary
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (root.nexus)
                                            root.nexus.syncDocumentFlashcardsToSpacedRepetition();
                                    }
                                }
                            }
                        }

                        ListView {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            spacing: 3
                            model: root.nexus?.currentDoc?.flashcards ?? []
                            delegate: Rectangle {
                                required property var modelData
                                width: ListView.view.width
                                height: 34
                                radius: 5
                                color: settledColors.colLayer0
                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 4
                                    spacing: 1
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: "Q: " + String(modelData.front ?? "")
                                        font.pixelSize: 10
                                        font.weight: Font.DemiBold
                                        color: settledColors.colPrimary
                                        elide: Text.ElideRight
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: "A: " + String(modelData.back ?? "")
                                        font.pixelSize: 10
                                        color: settledColors.colSubtext
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

    // ═══════════════════════════════════════════════════════════════════════
    // TOP-LEVEL SIDEBAR WIDTH RESIZE HANDLES (Unclipped 16px grab zones)
    // ═══════════════════════════════════════════════════════════════════════
    MouseArea {
        id: nexusLeftSidebarResizeHandle
        objectName: "nexusLeftSidebarResizeHandle"
        visible: Boolean(root.nexus?.leftSidebarOpen ?? true) && !Boolean(root.nexus?.commandPaletteOpen ?? false)
        z: 500
        x: nexusLeftColumn.x + nexusLeftColumn.width - 5
        y: 0
        width: 16
        height: root.height
        hoverEnabled: true
        preventStealing: true
        cursorShape: Qt.SplitHCursor
        property real pressRootX: 0
        property int pressSidebarWidth: 268
        onPressed: mouse => {
            const p = mapToItem(root, mouse.x, mouse.y);
            pressRootX = p.x;
            pressSidebarWidth = root.nexus ? root.nexus.leftSidebarWidth : nexusLeftColumn.width;
        }
        onPositionChanged: mouse => {
            if (!pressed || !root.nexus)
                return;
            const p = mapToItem(root, mouse.x, mouse.y);
            root.nexus.setLeftSidebarWidth(Math.round(pressSidebarWidth + (p.x - pressRootX)));
        }
    }

    MouseArea {
        id: nexusRightSidebarResizeHandle
        objectName: "nexusRightSidebarResizeHandle"
        visible: Boolean(root.nexus?.rightSidebarOpen ?? true) && !Boolean(root.nexus?.commandPaletteOpen ?? false)
        z: 500
        x: nexusRightColumn.x - 11
        y: 0
        width: 16
        height: root.height
        hoverEnabled: true
        preventStealing: true
        cursorShape: Qt.SplitHCursor
        property real pressRootX: 0
        property int pressSidebarWidth: 288
        onPressed: mouse => {
            const p = mapToItem(root, mouse.x, mouse.y);
            pressRootX = p.x;
            pressSidebarWidth = root.nexus ? root.nexus.rightSidebarWidth : nexusRightColumn.width;
        }
        onPositionChanged: mouse => {
            if (!pressed || !root.nexus)
                return;
            const p = mapToItem(root, mouse.x, mouse.y);
            root.nexus.setRightSidebarWidth(Math.round(pressSidebarWidth + (pressRootX - p.x)));
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // COMMAND PALETTE / QUICK SWITCHER / QUICK TASK MODAL (Alt+Enter / Alt+Esc / Alt+T)
    // ═══════════════════════════════════════════════════════════════════════
    Rectangle {
        id: commandPaletteOverlay
        objectName: "nexusCommandPaletteModal"
        anchors.fill: parent
        visible: Boolean(root.nexus?.commandPaletteOpen ?? false)
        color: Qt.rgba(0, 0, 0, 0.45)
        z: 99

        property string query: ""

        onVisibleChanged: {
            if (visible) {
                const initSearch = String(root.nexus?.commandPaletteSearch ?? "");
                commandPaletteSearchInput.text = initSearch;
                query = initSearch.trim().toLowerCase();
                if (root.nexus && root.nexus.commandPaletteSearch.length > 0)
                    root.nexus.commandPaletteSearch = "";
                commandPaletteSearchInput.focus = true;
                commandPaletteSearchInput.forceActiveFocus();
            } else {
                commandPaletteSearchInput.focus = false;
                root.restoreWorkspaceFocus();
                Qt.callLater(root.restoreWorkspaceFocus);
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: {
                commandPaletteSearchInput.focus = false;
                if (root.nexus)
                    root.nexus.commandPaletteOpen = false;
                root.restoreWorkspaceFocus();
                Qt.callLater(root.restoreWorkspaceFocus);
            }
        }

        Rectangle {
            width: Math.min(parent.width - 60, 620)
            height: (root.nexus?.commandPaletteMode === "task") ? 170 : Math.min(parent.height - 100, 460)
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 56
            radius: 14
            color: settledColors.colLayer1
            border.width: 1
            border.color: settledColors.colPrimary
            clip: true

            MouseArea {
                anchors.fill: parent
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 10

                // Mode Switch Pills (Quick Switcher | Commands | Quick Task)
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Repeater {
                        model: [
                            { "id": "switcher", "label": "Quick Switcher (" + (root.nexus ? root.nexus.shortcutFor("quick_switcher") : "Alt+Escape") + ")" },
                            { "id": "commands", "label": "Commands (" + (root.nexus ? root.nexus.shortcutFor("command_palette") : "Alt+Enter") + ")" },
                            { "id": "task", "label": "Quick Task (" + (root.nexus ? root.nexus.shortcutFor("quick_add_task") : "Alt+T") + ")" }
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            readonly property bool active: (root.nexus?.commandPaletteMode ?? "commands") === modelData.id
                            Layout.preferredHeight: 26
                            Layout.preferredWidth: cpTabLabel.implicitWidth + 16
                            radius: 6
                            color: active ? settledColors.colSecondaryContainer : settledColors.colLayer0

                            StyledText {
                                id: cpTabLabel
                                anchors.centerIn: parent
                                text: modelData.label
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                font.weight: active ? Font.Bold : Font.Normal
                                color: active ? settledColors.colOnSecondaryContainer : settledColors.colSubtext
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (root.nexus) {
                                        root.nexus.commandPaletteMode = modelData.id;
                                        commandPaletteSearchInput.focus = true;
                                        commandPaletteSearchInput.forceActiveFocus();
                                    }
                                }
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }

                    Rectangle {
                        width: 24
                        height: 24
                        radius: 6
                        color: settledColors.colLayer0
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "close"
                            iconSize: 14
                            color: settledColors.colSubtext
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                commandPaletteSearchInput.focus = false;
                                if (root.nexus)
                                    root.nexus.commandPaletteOpen = false;
                                root.restoreWorkspaceFocus();
                                Qt.callLater(root.restoreWorkspaceFocus);
                            }
                        }
                    }
                }

                // Input Field
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 36
                    radius: 8
                    color: settledColors.colLayer0
                    border.width: 1
                    border.color: settledColors.colLayer0Border

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 8

                        MaterialSymbol {
                            text: (root.nexus?.commandPaletteMode === "task") ? "add_task" : "search"
                            iconSize: 16
                            color: settledColors.colPrimary
                        }

                        TextField {
                            id: commandPaletteSearchInput
                            objectName: "nexusCommandPaletteInput"
                            Layout.fillWidth: true
                            placeholderText: {
                                const m = root.nexus?.commandPaletteMode ?? "commands";
                                if (m === "switcher")
                                    return "Type note name or path to open...";
                                if (m === "task")
                                    return "Type task and press Enter to add to Todo...";
                                return "Type a Nexus command or Obsidian shortcut...";
                            }
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: settledColors.colOnLayer1
                            background: null
                            onTextChanged: commandPaletteOverlay.query = text.trim().toLowerCase()
                            Keys.onEscapePressed: event => {
                                commandPaletteSearchInput.focus = false;
                                if (root.nexus)
                                    root.nexus.commandPaletteOpen = false;
                                root.restoreWorkspaceFocus();
                                Qt.callLater(root.restoreWorkspaceFocus);
                                event.accepted = true;
                            }
                            Keys.onPressed: event => {
                                if (event.key === Qt.Key_Escape && event.modifiers === Qt.NoModifier) {
                                    commandPaletteSearchInput.focus = false;
                                    if (root.nexus)
                                        root.nexus.commandPaletteOpen = false;
                                    root.restoreWorkspaceFocus();
                                    Qt.callLater(root.restoreWorkspaceFocus);
                                    event.accepted = true;
                                    return;
                                }
                                if ((event.modifiers & (Qt.AltModifier | Qt.ControlModifier | Qt.MetaModifier)) !== 0
                                    && root.nexus && root.nexus.handleKeyEvent(event)) {
                                    if (!root.nexus.commandPaletteOpen) {
                                        commandPaletteSearchInput.focus = false;
                                        root.restoreWorkspaceFocus();
                                        Qt.callLater(root.restoreWorkspaceFocus);
                                    }
                                    event.accepted = true;
                                }
                            }
                            onAccepted: {
                                if (!root.nexus)
                                    return;
                                const m = root.nexus.commandPaletteMode ?? "commands";
                                if (m === "task") {
                                    if (text.trim().length > 0) {
                                        root.nexus.addQuickTodoTask(text.trim());
                                        text = "";
                                        commandPaletteSearchInput.focus = false;
                                        root.nexus.commandPaletteOpen = false;
                                        root.restoreWorkspaceFocus();
                                        Qt.callLater(root.restoreWorkspaceFocus);
                                    }
                                    return;
                                }
                                if (m === "switcher" && commandPaletteResultsList.count > 0) {
                                    const firstItem = commandPaletteResultsList.model[0];
                                    if (firstItem && firstItem.relPath) {
                                        root.nexus.openFile(firstItem.relPath, true);
                                        commandPaletteSearchInput.focus = false;
                                        root.nexus.commandPaletteOpen = false;
                                        root.restoreWorkspaceFocus();
                                        Qt.callLater(root.restoreWorkspaceFocus);
                                    }
                                    return;
                                }
                                if (m === "commands" && commandPaletteCommandsList.count > 0) {
                                    const firstCmd = commandPaletteCommandsList.model[0];
                                    if (firstCmd && firstCmd.id) {
                                        commandPaletteSearchInput.focus = false;
                                        root.nexus.commandPaletteOpen = false;
                                        if (firstCmd.id === "__new_note_api_modal__") {
                                            root.nexus.openNewNoteModal("movie", "");
                                        } else {
                                            root.nexus.triggerShortcutAction(firstCmd.id);
                                        }
                                        if (!root.nexus.commandPaletteOpen && !root.nexus.newNoteModalOpen) {
                                            root.restoreWorkspaceFocus();
                                            Qt.callLater(root.restoreWorkspaceFocus);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Quick Switcher File Results
                ListView {
                    id: commandPaletteResultsList
                    visible: (root.nexus?.commandPaletteMode ?? "commands") === "switcher"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 4
                    model: {
                        const rows = root.nexus?.flatFiles ?? root.nexus?.visibleTreeRows ?? [];
                        const q = commandPaletteOverlay.query;
                        const out = [];
                        for (let i = 0; i < rows.length; ++i) {
                            const r = rows[i];
                            if (!r || r.isDir)
                                continue;
                            if (q.length === 0 || String(r.name ?? "").toLowerCase().indexOf(q) !== -1 || String(r.relPath ?? "").toLowerCase().indexOf(q) !== -1) {
                                out.push(r);
                                if (out.length >= 40)
                                    break;
                            }
                        }
                        return out;
                    }
                    delegate: Rectangle {
                        required property var modelData
                        width: ListView.view.width
                        height: 36
                        radius: 7
                        color: switcherRowMouse.containsMouse ? settledColors.colSecondaryContainer : settledColors.colLayer0

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 8

                            MaterialSymbol {
                                text: "description"
                                iconSize: 15
                                color: settledColors.colPrimary
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: String(modelData.name ?? "").replace(/\.md$/i, "")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.DemiBold
                                color: settledColors.colOnLayer1
                                elide: Text.ElideRight
                            }
                            StyledText {
                                text: String(modelData.relPath ?? "")
                                font.family: Appearance.font.family.monospace
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: settledColors.colSubtext
                                elide: Text.ElideLeft
                            }
                        }
                        MouseArea {
                            id: switcherRowMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (root.nexus) {
                                    root.nexus.openFile(modelData.relPath, true);
                                    commandPaletteSearchInput.focus = false;
                                    root.nexus.commandPaletteOpen = false;
                                    root.restoreWorkspaceFocus();
                                    Qt.callLater(root.restoreWorkspaceFocus);
                                }
                            }
                        }
                    }
                }

                // Command Palette Action Results
                ListView {
                    id: commandPaletteCommandsList
                    visible: (root.nexus?.commandPaletteMode ?? "commands") === "commands"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 4
                    model: {
                        const extra = [{
                            "id": "__new_note_api_modal__",
                            "title": "New Note / Search External API...",
                            "description": "Create note or search Movie, TV, Book, Game, Recipe & Place APIs",
                            "obsidianCommand": "nexus:new-note-api",
                            "defaultKey": ""
                        }];
                        const catalog = extra.concat(root.nexus?.shortcutCatalog ?? []);
                        const q = commandPaletteOverlay.query;
                        const out = [];
                        for (let i = 0; i < catalog.length; ++i) {
                            const item = catalog[i];
                            if (!item)
                                continue;
                            const obsCmd = String(item.obsidianCommand ?? item.obsidianId ?? "").toLowerCase();
                            if (q.length === 0
                                || String(item.title ?? "").toLowerCase().indexOf(q) !== -1
                                || String(item.description ?? "").toLowerCase().indexOf(q) !== -1
                                || obsCmd.indexOf(q) !== -1) {
                                out.push(item);
                            }
                        }
                        return out;
                    }
                    delegate: Rectangle {
                        required property var modelData
                        width: ListView.view.width
                        height: 38
                        radius: 7
                        color: cmdRowMouse.containsMouse ? settledColors.colSecondaryContainer : settledColors.colLayer0

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 8

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                StyledText {
                                    text: String(modelData.title ?? "")
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.weight: Font.DemiBold
                                    color: settledColors.colOnLayer1
                                }
                                StyledText {
                                    readonly property string obsLabel: String(modelData.obsidianCommand ?? modelData.obsidianId ?? "")
                                    text: String(modelData.description ?? "") + (obsLabel.length > 0 ? ("  ·  " + obsLabel) : "")
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: settledColors.colSubtext
                                }
                            }

                            Rectangle {
                                height: 22
                                width: cmdKeyText.implicitWidth + 12
                                radius: 5
                                color: settledColors.colLayer2
                                StyledText {
                                    id: cmdKeyText
                                    anchors.centerIn: parent
                                    text: root.nexus ? (root.nexus.shortcutFor(modelData.id) || "Unbound") : String(modelData.defaultKey ?? "")
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: settledColors.colPrimary
                                }
                            }
                        }
                        MouseArea {
                            id: cmdRowMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (root.nexus) {
                                    commandPaletteSearchInput.focus = false;
                                    root.nexus.commandPaletteOpen = false;
                                    if (modelData.id === "__new_note_api_modal__") {
                                        root.nexus.openNewNoteModal("movie", "");
                                    } else {
                                        root.nexus.triggerShortcutAction(modelData.id);
                                    }
                                    if (!root.nexus.commandPaletteOpen && !root.nexus.newNoteModalOpen) {
                                        root.restoreWorkspaceFocus();
                                        Qt.callLater(root.restoreWorkspaceFocus);
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Floating Drag-and-Drop Card Reorder Preview Badge
    Rectangle {
        id: nexusCardDragPreview
        objectName: "nexusCardDragPreview"
        visible: root.draggingCardId.length > 0
        z: 600
        x: Math.max(8, Math.min(root.width - width - 8, root.dragRootX - width / 2))
        y: Math.max(8, Math.min(root.height - height - 8, root.dragRootY - height / 2))
        height: 30
        width: dragPreviewRow.implicitWidth + 20
        radius: 8
        color: settledColors.colPrimary
        border.width: 1
        border.color: settledColors.colOnPrimary
        opacity: 0.94

        RowLayout {
            id: dragPreviewRow
            anchors.centerIn: parent
            spacing: 6
            MaterialSymbol {
                text: "drag_indicator"
                iconSize: 15
                color: settledColors.colOnPrimary
            }
            StyledText {
                text: (root.dropTargetCardId.length > 0 && root.dropTargetCardId !== root.draggingCardId)
                    ? ("Swap " + root.draggingCardId + " ↔ " + root.dropTargetCardId)
                    : ("Move " + root.draggingCardId)
                font.family: Appearance.font.family.monospace
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.Bold
                color: settledColors.colOnPrimary
            }
        }
    }

    MouseArea {
        id: nexusContextBackdrop
        anchors.fill: parent
        z: 699
        visible: root.contextMenuOpen || root.renameDialogOpen
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: {
            root.closeContextMenu();
            if (root.renameDialogOpen)
                root.renameDialogOpen = false;
        }
    }

    Rectangle {
        id: nexusContextMenuPopup
        objectName: "nexusContextMenuPopup"
        visible: root.contextMenuOpen
        z: 701
        x: Math.max(8, Math.min(root.width - width - 8, root.contextMenuX))
        y: Math.max(8, Math.min(root.height - height - 8, root.contextMenuY))
        width: 220
        implicitHeight: contextMenuCol.implicitHeight + 12
        height: implicitHeight
        radius: 9
        color: settledColors.colLayer1
        border.width: 1
        border.color: settledColors.colLayer0Border

        ColumnLayout {
            id: contextMenuCol
            anchors.fill: parent
            anchors.margins: 6
            spacing: 2

            RowLayout {
                visible: Boolean(root.contextMenuData?.title)
                Layout.fillWidth: true
                Layout.preferredHeight: 24
                Layout.leftMargin: 6
                Layout.rightMargin: 6
                spacing: 6
                MaterialSymbol {
                    text: root.contextMenuData?.isDir ? "folder" : (root.contextMenuData?.type === "tag" ? "tag" : "description")
                    iconSize: 13
                    color: settledColors.colSubtext
                }
                StyledText {
                    Layout.fillWidth: true
                    text: String(root.contextMenuData?.title ?? "")
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.DemiBold
                    color: settledColors.colSubtext
                    elide: Text.ElideRight
                }
            }

            Rectangle {
                visible: Boolean(root.contextMenuData?.title)
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                Layout.bottomMargin: 2
                color: settledColors.colLayer0Border
            }

            Repeater {
                model: root.contextMenuOpen ? root.getContextMenuActions() : []
                delegate: Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: modelData.separator ? 7 : 30
                    Rectangle {
                        anchors.fill: parent
                        visible: !modelData.separator
                        radius: 6
                        color: itemMouse.containsMouse
                            ? (modelData.isDestructive ? Qt.rgba(settledColors.colError.r, settledColors.colError.g, settledColors.colError.b, 0.18) : settledColors.colSecondaryContainer)
                            : "transparent"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 8
                            MaterialSymbol {
                                text: String(modelData.icon ?? "")
                                iconSize: 15
                                color: modelData.isDestructive ? settledColors.colError : (itemMouse.containsMouse ? settledColors.colPrimary : settledColors.colSubtext)
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: String(modelData.label ?? "")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.DemiBold
                                color: modelData.isDestructive ? settledColors.colError : (itemMouse.containsMouse ? settledColors.colOnSecondaryContainer : settledColors.colOnLayer1)
                                elide: Text.ElideRight
                            }
                        }
                        MouseArea {
                            id: itemMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (typeof modelData.onTrigger === "function") {
                                    modelData.onTrigger();
                                }
                            }
                        }
                    }
                    Rectangle {
                        visible: Boolean(modelData.separator)
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 4
                        anchors.rightMargin: 4
                        height: 1
                        color: settledColors.colLayer0Border
                    }
                }
            }
        }
    }

    Rectangle {
        id: nexusRenameDialog
        objectName: "nexusRenameDialog"
        visible: root.renameDialogOpen
        z: 750
        anchors.centerIn: parent
        width: 380
        implicitHeight: renameCol.implicitHeight + 28
        height: implicitHeight
        radius: 10
        color: settledColors.colLayer1
        border.width: 1
        border.color: settledColors.colPrimary

        ColumnLayout {
            id: renameCol
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            StyledText {
                text: "Rename"
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.Bold
                color: settledColors.colPrimary
            }
            StyledText {
                text: root.renameDialogOldPath
                font.family: Appearance.font.family.monospace
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: settledColors.colSubtext
                elide: Text.ElideMiddle
                Layout.fillWidth: true
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 36
                radius: 6
                color: settledColors.colLayer0
                border.width: 1
                border.color: renameInput.activeFocus ? settledColors.colPrimary : settledColors.colLayer0Border

                TextInput {
                    id: renameInput
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    verticalAlignment: TextInput.AlignVCenter
                    text: root.renameDialogNewName
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: settledColors.colOnLayer1
                    selectByMouse: true
                    focus: root.renameDialogOpen
                    onAccepted: {
                        const newName = text.trim();
                        if (newName.length > 0 && root.nexus) {
                            const oldP = root.renameDialogOldPath;
                            let newP = newName;
                            if (oldP.includes("/")) {
                                const dir = oldP.substring(0, oldP.lastIndexOf("/"));
                                newP = dir + "/" + newName;
                            }
                            if (!newP.endsWith(".md") && oldP.endsWith(".md")) {
                                newP += ".md";
                            }
                            root.nexus.renamePath(oldP, newP);
                        }
                        root.renameDialogOpen = false;
                    }
                    Keys.onEscapePressed: {
                        root.renameDialogOpen = false;
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignRight
                spacing: 8
                Rectangle {
                    implicitWidth: 80
                    implicitHeight: 30
                    radius: 6
                    color: cancelBtnMouse.containsMouse ? settledColors.colLayer2Hover : settledColors.colLayer2
                    StyledText {
                        anchors.centerIn: parent
                        text: "Cancel"
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: settledColors.colSubtext
                    }
                    MouseArea {
                        id: cancelBtnMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.renameDialogOpen = false
                    }
                }
                Rectangle {
                    implicitWidth: 80
                    implicitHeight: 30
                    radius: 6
                    color: renameBtnMouse.containsMouse ? settledColors.colPrimary : settledColors.colSecondaryContainer
                    StyledText {
                        anchors.centerIn: parent
                        text: "Rename"
                        font.weight: Font.DemiBold
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: renameBtnMouse.containsMouse ? settledColors.colOnPrimary : settledColors.colOnSecondaryContainer
                    }
                    MouseArea {
                        id: renameBtnMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: renameInput.accepted()
                    }
                }
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INTERACTIVE NEW NOTE & EXTERNAL API SEARCH MODAL (`A2`)
    // ═══════════════════════════════════════════════════════════════════════
    Rectangle {
        id: nexusNewNoteApiModal
        objectName: "nexusNewNoteApiModal"
        anchors.fill: parent
        visible: Boolean(root.nexus?.newNoteModalOpen ?? false)
        color: Qt.alpha(settledColors.colLayer0, 0.72)
        z: 760

        readonly property string activeKind: String(root.nexus?.newNoteModalKind ?? "standard")
        readonly property bool apiBacked: Boolean(root.nexus && root.nexus.isApiBackedKind(activeKind))
        property string openedCustomKind: ""
        readonly property var extraKindMetaMap: ({
            "exercise": { "id": "exercise", "label": "Exercise", "icon": "fitness_center" },
            "contact": { "id": "contact", "label": "Contact", "icon": "contacts" },
            "website": { "id": "website", "label": "Web-Site", "icon": "language" },
            "cornell": { "id": "cornell", "label": "Cornell", "icon": "school" },
            "zettelkasten": { "id": "zettelkasten", "label": "Zettelkasten", "icon": "psychology" },
            "finance": { "id": "finance", "label": "Finance", "icon": "account_balance_wallet" },
            "clipping": { "id": "clipping", "label": "Clipping", "icon": "bookmark" }
        })

        Timer {
            id: apiModalDebounce
            interval: 280
            repeat: false
            onTriggered: {
                if (root.nexus && nexusNewNoteApiModal.visible && nexusNewNoteApiModal.apiBacked) {
                    root.nexus.searchExternalApi(nexusNewNoteApiModal.activeKind, newNoteApiSearchInput.text);
                }
            }
        }

        onVisibleChanged: {
            if (visible) {
                openedCustomKind = extraKindMetaMap[activeKind] ? activeKind : "";
                newNoteModalFolderInput.text = String(root.nexus?.newNoteModalFolder ?? "");
                if (!newNoteApiSearchInput.text)
                    newNoteApiSearchInput.text = "";
                newNoteApiSearchInput.forceActiveFocus();
            } else {
                openedCustomKind = "";
                apiModalDebounce.stop();
                newNoteApiSearchInput.text = "";
                newNoteApiSearchInput.focus = false;
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: {
                if (root.nexus)
                    root.nexus.closeNewNoteModal();
            }
        }

        Rectangle {
            objectName: "nexusNewNoteApiModalCard"
            width: Math.min(parent.width - 48, 680)
            height: nexusNewNoteApiModal.apiBacked
                ? Math.min(parent.height - 64, 560)
                : Math.min(parent.height - 64, 300)
            anchors.centerIn: parent
            radius: 14
            color: settledColors.colLayer1
            border.width: 1
            border.color: settledColors.colPrimary
            clip: true

            MouseArea {
                anchors.fill: parent
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 12

                // Title Header
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    MaterialSymbol {
                        text: nexusNewNoteApiModal.apiBacked ? "travel_explore" : "note_add"
                        iconSize: 18
                        color: settledColors.colPrimary
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: nexusNewNoteApiModal.apiBacked
                            ? "New Note · Search & Pick Metadata"
                            : "Create New Vault Note"
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.Bold
                        color: settledColors.colOnLayer1
                    }
                    Rectangle {
                        width: 26
                        height: 26
                        radius: 6
                        color: closeModalMouse.containsMouse ? settledColors.colLayer2Hover : settledColors.colLayer0
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "close"
                            iconSize: 14
                            color: settledColors.colSubtext
                        }
                        MouseArea {
                            id: closeModalMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (root.nexus)
                                    root.nexus.closeNewNoteModal();
                            }
                        }
                    }
                }

                // Kind Pills
                Flow {
                    Layout.fillWidth: true
                    spacing: 6

                    Repeater {
                        model: {
                            const base = [
                                { "id": "standard", "label": "Standard Note", "icon": "description" },
                                { "id": "movie", "label": "Movie", "icon": "movie" },
                                { "id": "tv", "label": "TV Series", "icon": "live_tv" },
                                { "id": "book", "label": "Book", "icon": "menu_book" },
                                { "id": "game", "label": "Game", "icon": "sports_esports" },
                                { "id": "recipe", "label": "Recipe", "icon": "restaurant" },
                                { "id": "place", "label": "Place", "icon": "place" },
                                { "id": "journal", "label": "Daily Journal", "icon": "today" }
                            ];
                            const customKey = nexusNewNoteApiModal.extraKindMetaMap[nexusNewNoteApiModal.activeKind]
                                ? nexusNewNoteApiModal.activeKind
                                : nexusNewNoteApiModal.openedCustomKind;
                            if (customKey && nexusNewNoteApiModal.extraKindMetaMap[customKey])
                                base.push(nexusNewNoteApiModal.extraKindMetaMap[customKey]);
                            return base;
                        }
                        delegate: Rectangle {
                            required property var modelData
                            objectName: "nexusNewNoteKindPill_" + modelData.id
                            readonly property bool selected: nexusNewNoteApiModal.activeKind === modelData.id
                            implicitWidth: kindPillRow.implicitWidth + 16
                            implicitHeight: 28
                            radius: 7
                            color: selected
                                ? settledColors.colPrimary
                                : (kindPillMouse.containsMouse ? settledColors.colLayer2Hover : settledColors.colLayer0)
                            border.width: 1
                            border.color: selected ? settledColors.colPrimary : settledColors.colLayer0Border

                            RowLayout {
                                id: kindPillRow
                                anchors.centerIn: parent
                                spacing: 5
                                MaterialSymbol {
                                    text: modelData.icon
                                    iconSize: 14
                                    color: selected ? settledColors.colOnPrimary : settledColors.colPrimary
                                }
                                StyledText {
                                    text: modelData.label
                                    font.pixelSize: Appearance.font.pixelSize.smallest + 1
                                    font.weight: selected ? Font.Bold : Font.DemiBold
                                    color: selected ? settledColors.colOnPrimary : settledColors.colOnLayer1
                                }
                            }

                            MouseArea {
                                id: kindPillMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (!root.nexus)
                                        return;
                                    root.nexus.newNoteModalKind = modelData.id;
                                    const inferred = root.nexus.inferFolderForKind(modelData.id);
                                    root.nexus.newNoteModalFolder = inferred;
                                    newNoteModalFolderInput.text = inferred;
                                    root.nexus.searchApiResults = [];
                                    if (root.nexus.isApiBackedKind(modelData.id) && newNoteApiSearchInput.text.trim().length >= 2) {
                                        apiModalDebounce.restart();
                                    }
                                    newNoteApiSearchInput.forceActiveFocus();
                                }
                            }
                        }
                    }
                }

                // Target Folder Row
                RowLayout {
                    visible: nexusNewNoteApiModal.activeKind !== "journal"
                    Layout.fillWidth: true
                    spacing: 8

                    StyledText {
                        text: "FOLDER"
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        color: settledColors.colSubtext
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 30
                        radius: 7
                        color: settledColors.colLayer0
                        border.width: 1
                        border.color: newNoteModalFolderInput.activeFocus ? settledColors.colPrimary : settledColors.colLayer0Border

                        TextField {
                            id: newNoteModalFolderInput
                            objectName: "nexusNewNoteModalFolderInput"
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            placeholderText: "Vault root (or e.g. 20_Personal_Life/25_Media_Tracker/Movies)"
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: Appearance.font.pixelSize.smallest + 1
                            color: settledColors.colOnLayer1
                            background: null
                            Keys.onEscapePressed: event => {
                                if (root.nexus)
                                    root.nexus.closeNewNoteModal();
                                event.accepted = true;
                            }
                        }
                    }
                }

                // Title / Live API Search Input
                Rectangle {
                    visible: nexusNewNoteApiModal.activeKind !== "journal"
                    Layout.fillWidth: true
                    Layout.preferredHeight: 38
                    radius: 8
                    color: settledColors.colLayer0
                    border.width: 1
                    border.color: newNoteApiSearchInput.activeFocus ? settledColors.colPrimary : settledColors.colLayer0Border

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 8

                        MaterialSymbol {
                            text: nexusNewNoteApiModal.apiBacked ? "search" : "edit"
                            iconSize: 16
                            color: settledColors.colPrimary
                        }

                        TextField {
                            id: newNoteApiSearchInput
                            objectName: "nexusNewNoteModalSearchInput"
                            Layout.fillWidth: true
                            placeholderText: nexusNewNoteApiModal.apiBacked
                                ? ("Search " + nexusNewNoteApiModal.activeKind.toUpperCase() + " title to auto-fetch metadata, or press Enter for manual note...")
                                : "Enter note title and press Enter..."
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: settledColors.colOnLayer1
                            background: null
                            onTextChanged: {
                                if (!nexusNewNoteApiModal.visible || !root.nexus)
                                    return;
                                if (nexusNewNoteApiModal.apiBacked) {
                                    if (text.trim().length >= 2)
                                        apiModalDebounce.restart();
                                    else {
                                        apiModalDebounce.stop();
                                        root.nexus.searchApiResults = [];
                                        root.nexus.searchApiLoading = false;
                                    }
                                }
                            }
                            onAccepted: {
                                if (!root.nexus)
                                    return;
                                root.nexus.createManualModalNote(
                                    nexusNewNoteApiModal.activeKind,
                                    text.trim() || "Untitled",
                                    newNoteModalFolderInput.text
                                );
                            }
                            Keys.onEscapePressed: event => {
                                if (root.nexus)
                                    root.nexus.closeNewNoteModal();
                                event.accepted = true;
                            }
                        }
                    }
                }

                // Live Selectable API Results List
                Rectangle {
                    visible: nexusNewNoteApiModal.apiBacked
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 10
                    color: settledColors.colLayer0
                    border.width: 1
                    border.color: settledColors.colLayer0Border
                    clip: true

                    StyledText {
                        anchors.centerIn: parent
                        visible: !Boolean(root.nexus?.searchApiLoading) && (root.nexus?.searchApiResults ?? []).length === 0
                        text: newNoteApiSearchInput.text.trim().length < 2
                            ? "Type at least 2 characters to search live metadata (works keyless out-of-the-box)..."
                            : "No external matches found — click 'Create Manual Note' below to create offline."
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: settledColors.colSubtext
                    }

                    StyledText {
                        anchors.centerIn: parent
                        visible: Boolean(root.nexus?.searchApiLoading) && (root.nexus?.searchApiResults ?? []).length === 0
                        text: "Searching external metadata providers..."
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: settledColors.colPrimary
                    }

                    ListView {
                        id: newNoteModalResultsList
                        objectName: "nexusNewNoteModalResultsList"
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 6
                        clip: true
                        model: root.nexus?.searchApiResults ?? []

                        delegate: Rectangle {
                            id: candCard
                            required property var modelData
                            required property int index
                            objectName: "nexusApiCandidateCard_" + String(index)
                            width: ListView.view.width
                            height: 82
                            radius: 8
                            color: candMouse.containsMouse ? settledColors.colSecondaryContainer : settledColors.colLayer1
                            border.width: 1
                            border.color: candMouse.containsMouse ? settledColors.colPrimary : settledColors.colLayer0Border

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 10

                                Rectangle {
                                    Layout.preferredWidth: 48
                                    Layout.preferredHeight: 66
                                    radius: 5
                                    color: settledColors.colLayer2
                                    clip: true

                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        visible: String(candCard.modelData.cover ?? "").length === 0
                                        text: "image"
                                        iconSize: 18
                                        color: settledColors.colSubtext
                                    }

                                    Image {
                                        anchors.fill: parent
                                        visible: String(candCard.modelData.cover ?? "").length > 0
                                        source: String(candCard.modelData.cover ?? "")
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    spacing: 2

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 6

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: String(candCard.modelData.title ?? "")
                                                + (String(candCard.modelData.year ?? "").length > 0 ? (" (" + String(candCard.modelData.year) + ")") : "")
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            font.weight: Font.Bold
                                            color: settledColors.colOnLayer1
                                            elide: Text.ElideRight
                                        }

                                        Rectangle {
                                            visible: String(candCard.modelData.source ?? "").length > 0
                                            implicitWidth: srcBadgeTxt.implicitWidth + 10
                                            implicitHeight: 18
                                            radius: 4
                                            color: settledColors.colLayer2
                                            border.width: 1
                                            border.color: settledColors.colPrimary
                                            StyledText {
                                                id: srcBadgeTxt
                                                anchors.centerIn: parent
                                                text: String(candCard.modelData.source ?? "")
                                                font.family: Appearance.font.family.monospace
                                                font.pixelSize: 9
                                                font.weight: Font.Bold
                                                color: settledColors.colPrimary
                                            }
                                        }
                                    }

                                    StyledText {
                                        visible: String(candCard.modelData.creator || candCard.modelData.subtitle || "").length > 0
                                        Layout.fillWidth: true
                                        text: [String(candCard.modelData.creator ?? ""), String(candCard.modelData.subtitle ?? "")].filter(s => s.length > 0).join(" · ")
                                        font.pixelSize: Appearance.font.pixelSize.smallest + 1
                                        font.weight: Font.DemiBold
                                        color: settledColors.colPrimary
                                        elide: Text.ElideRight
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        text: String(candCard.modelData.overview ?? "")
                                        font.pixelSize: Appearance.font.pixelSize.smallest + 1
                                        color: settledColors.colSubtext
                                        wrapMode: Text.WordWrap
                                        maximumLineCount: 2
                                        elide: Text.ElideRight
                                    }
                                }
                            }

                            MouseArea {
                                id: candMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (root.nexus) {
                                        root.nexus.createNoteFromApiCandidate(
                                            nexusNewNoteApiModal.activeKind,
                                            candCard.modelData,
                                            newNoteModalFolderInput.text
                                        );
                                    }
                                }
                            }
                        }
                    }
                }

                // Bottom Action Bar
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    StyledText {
                        Layout.fillWidth: true
                        text: nexusNewNoteApiModal.activeKind === "journal"
                            ? ("Opens or creates today's Journal note in " + String(root.nexus?.dailyFolder ?? ""))
                            : nexusNewNoteApiModal.apiBacked
                                ? (Boolean(root.nexus?.searchApiLoading) ? "Fetching candidates..." : "Click any result card to populate frontmatter & sections automatically")
                                : "Enter note title and press Enter or click Create Note"
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: settledColors.colSubtext
                        elide: Text.ElideRight
                    }

                    Rectangle {
                        implicitWidth: 74
                        implicitHeight: 30
                        radius: 7
                        color: cancelModalBtnMouse.containsMouse ? settledColors.colLayer2Hover : settledColors.colLayer2
                        StyledText {
                            anchors.centerIn: parent
                            text: "Cancel"
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: settledColors.colSubtext
                        }
                        MouseArea {
                            id: cancelModalBtnMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (root.nexus)
                                    root.nexus.closeNewNoteModal();
                            }
                        }
                    }

                    Rectangle {
                        objectName: "nexusCreateManualNoteButton"
                        implicitWidth: manualCreateLbl.implicitWidth + 22
                        implicitHeight: 30
                        radius: 7
                        color: settledColors.colPrimary
                        StyledText {
                            id: manualCreateLbl
                            anchors.centerIn: parent
                            text: nexusNewNoteApiModal.activeKind === "journal"
                                ? "Open Today's Journal"
                                : (nexusNewNoteApiModal.apiBacked ? "Create Blank / Manual Note" : "Create Note")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.Bold
                            color: settledColors.colOnPrimary
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (root.nexus) {
                                    root.nexus.createManualModalNote(
                                        nexusNewNoteApiModal.activeKind,
                                        newNoteApiSearchInput.text.trim() || "Untitled",
                                        newNoteModalFolderInput.text
                                    );
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
