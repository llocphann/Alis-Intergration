import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
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
    // Tag Wrangler+ modal state (Rename / Merge tag atomically across vault)
    property bool tagDialogOpen: false
    property string tagDialogMode: "rename" // "rename" | "merge"
    property string tagDialogSourceTag: ""
    property string tagDialogTargetTag: ""
    property bool tagDialogIncludeSubtags: true
    // Calendar optional ISO week numbers toggle (synced with Obsidian calendar plugin setting, overridable via hover tab)
    property bool calendarShowWeekNumbersOverride: false
    property bool calendarWeekNumbersUserToggled: false
    readonly property bool showCalendarWeekNumbers: root.calendarWeekNumbersUserToggled
        ? root.calendarShowWeekNumbersOverride
        : Boolean(root.nexus?.calendarShowWeeklyNote ?? false)
    // Soft Folder Tree hover/focus ancestor path + 1s interval EQ-DSP electric current state
    property string hoveredTreeRowPath: ""
    property var hoveredTreeAncestorPaths: []
    readonly property string activeTreeTargetPath: root.hoveredTreeRowPath.length > 0
        ? root.hoveredTreeRowPath
        : ((root.nexus?.activeView === "document" && String(root.nexus?.currentPath ?? "").length > 0)
            ? String(root.nexus.currentPath)
            : "")
    readonly property var activeTreeAncestorPaths: {
        if (root.hoveredTreeRowPath.length > 0)
            return root.hoveredTreeAncestorPaths ?? [];
        const p = root.activeTreeTargetPath;
        if (!p || !p.includes("/"))
            return [];
        const parts = p.split("/");
        const out = [];
        for (let i = 0; i < parts.length - 1; ++i)
            out.push(parts.slice(0, i + 1).join("/"));
        return out;
    }
    // Exact 01_Core.css Soft Folder Tree active chain: maps each ancestor folder path on the
    // hovered/active chain to its visible row range (parentIdx -> nextHopIdx) so siblings below
    // any active turn and outer trunks passing past an active folder stay strictly DIM.
    readonly property var activeTreeChainInfo: {
        const target = root.activeTreeTargetPath;
        const rows = root.nexus?.visibleTreeRows ?? [];
        if (!target || target.length === 0 || !rows || rows.length === 0)
            return { hops: ({}), firstParentIdx: -1, targetIdx: -1, totalSteps: 1 };
        const idxByPath = {};
        let targetIdx = -1;
        for (let i = 0; i < rows.length; ++i) {
            const rp = String(rows[i]?.relPath ?? "");
            if (rp.length > 0) {
                idxByPath[rp] = i;
                if (rp === target)
                    targetIdx = i;
            }
        }
        if (targetIdx < 0)
            return { hops: ({}), firstParentIdx: -1, targetIdx: -1, totalSteps: 1 };
        const chain = (root.activeTreeAncestorPaths ?? []).slice();
        chain.push(target);
        const hops = {};
        let firstParentIdx = targetIdx;
        for (let k = 0; k < chain.length - 1; ++k) {
            const parentPath = String(chain[k] ?? "");
            const nextPath = String(chain[k + 1] ?? "");
            const pIdx = idxByPath[parentPath] !== undefined ? idxByPath[parentPath] : -1;
            const nIdx = idxByPath[nextPath] !== undefined ? idxByPath[nextPath] : -1;
            if (parentPath.length > 0 && nIdx >= 0) {
                hops[parentPath] = { parentIdx: pIdx, nextHopIdx: nIdx, hopOrder: k };
                if (pIdx >= 0 && pIdx < firstParentIdx)
                    firstParentIdx = pIdx;
                else if (pIdx < 0 && firstParentIdx === targetIdx)
                    firstParentIdx = -1;
            }
        }
        const totalSteps = Math.max(1, targetIdx - firstParentIdx);
        return { hops: hops, firstParentIdx: firstParentIdx, targetIdx: targetIdx, totalSteps: totalSteps };
    }
    property real treeElectricPhase: 0.0
    property int treeElectricSeq: 0
    readonly property bool treeElectricCanRun: root.visible
        && root.surfaceActive
        && root.transitionSettled
        && Boolean(root.nexus?.isOpen ?? true)
        && Boolean(root.nexus?.leftSidebarOpen ?? true)
        && (root.nexus?.leftSidebarTab ?? "files") === "files"
        && root.activeTreeTargetPath.length > 0
        && !Boolean(GlobalStates?.wallpaperSelectorOpen ?? false)
        && !Boolean(GlobalStates?.screenLocked ?? false)
        && !Boolean(GlobalStates?.regionSelectorOpen ?? false)
        && !Boolean(GlobalStates?.annotationEditorOpen ?? false)
        && !Boolean(Config?.options?.appearance?.reduceAnimations ?? false)
        && !Boolean(Config?.options?.performance?.reduceAnimations ?? false)

    Timer {
        id: treeElectricIntervalTimer
        objectName: "nexusTreeElectricIntervalTimer"
        interval: 1000
        repeat: true
        running: root.treeElectricCanRun
        onTriggered: {
            root.treeElectricSeq += 1;
            root.treeElectricPhase = 0.01;
            treeElectricSweepTimer.restart();
        }
    }

    Timer {
        id: treeElectricSweepTimer
        interval: 28
        repeat: true
        running: false
        onTriggered: {
            if (!root.treeElectricCanRun) {
                root.treeElectricPhase = 0.0;
                stop();
                return;
            }
            const next = root.treeElectricPhase + 0.072;
            if (next >= 1.0) {
                root.treeElectricPhase = 0.0;
                stop();
            } else {
                root.treeElectricPhase = next;
            }
        }
    }

    function activateGraphNode(nodeData): void {
        if (!root.nexus || !nodeData)
            return;
        if (Boolean(nodeData.isTagNode) || String(nodeData.id ?? "").startsWith("tag:")) {
            const rawTag = String(nodeData.tagName || String(nodeData.title || "").replace(/^#+/, "")).trim();
            if (rawTag.length > 0) {
                const tagQ = "#" + rawTag;
                root.nexus.leftSidebarOpen = true;
                root.nexus.leftSidebarTab = "search";
                fileFilterField.text = tagQ;
                root.nexus.searchVault(tagQ);
                root.nexus.vimStatusMessage = "Tag hub: " + tagQ;
            }
            return;
        }
        if (nodeData.id === "__homepage__")
            root.nexus.openHomepage();
        else if (nodeData.relPath)
            root.nexus.openFile(nodeData.relPath, true);
    }

    function openTagActionDialog(mode: string, tagName: string): void {
        root.closeContextMenu();
        root.renameDialogOpen = false;
        const clean = String(tagName || "").trim().replace(/^#+/, "");
        if (clean.length === 0)
            return;
        root.tagDialogMode = (mode === "merge") ? "merge" : "rename";
        root.tagDialogSourceTag = clean;
        root.tagDialogTargetTag = (mode === "merge") ? "" : clean;
        root.tagDialogIncludeSubtags = true;
        root.tagDialogOpen = true;
        Qt.callLater(() => {
            if (root.tagDialogOpen && typeof tagActionInput !== "undefined") {
                tagActionInput.forceActiveFocus();
                tagActionInput.selectAll();
            }
        });
    }

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

    readonly property var _collectionFilterField: collectionViewLoader.item?.collectionFilterField ?? null
    readonly property var _newCollectionEntryInput: collectionViewLoader.item?.newEntryInput ?? null
    readonly property var nexusCustomViewsLoader: documentViewLoader.item?.customViewsLoader ?? null
    readonly property var _docBodyEditor: documentViewLoader.item?.bodyEditor ?? null
    readonly property var _docVimEditor: documentViewLoader.item?.vimEditor ?? null
    readonly property var _docVimPane: documentViewLoader.item?.vimPane ?? null
    readonly property var _commandPaletteSearchInput: commandPaletteOverlay.searchInput ?? null
    readonly property var _newNoteApiSearchInput: newNoteModalLoader.item?.searchInput ?? null

    function setNewNoteSearchDraft(draft: string): void {
        const inp = newNoteModalLoader.item?.searchInput ?? null;
        if (inp)
            inp.text = draft;
    }

    function startStandardNoteInlineEdit(): bool {
        if (!root.nexus || !root.nexus.currentDoc)
            return false;
        if (Boolean(root.nexusCustomViewsLoader?.item?.isCustomViewNote))
            return false;
        root._cancelingStandardInlineEdit = false;
        root.standardNoteInlineDraft = root.nexus.getNoteBodyMarkdown();
        root.standardNoteInlineEditing = true;
        return true;
    }

    function commitStandardNoteInlineEdit(): bool {
        if (!root.standardNoteInlineEditing)
            return false;
        if (root.nexus && root._docBodyEditor) {
            root.nexus.saveNoteBodyMarkdown(root._docBodyEditor.text);
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
            const tagClean = String(d.tag || String(d.fullTag || "").replace(/^#+/, "")).trim();
            const tagFull = "#" + tagClean;
            actions.push({
                "id": "search-tag",
                "icon": "search",
                "label": "Search Notes with " + tagFull,
                "onTrigger": () => {
                    if (root.nexus) {
                        root.nexus.leftSidebarTab = "search";
                        fileFilterField.text = tagFull;
                        root.nexus.searchVault(tagFull);
                    }
                    root.closeContextMenu();
                }
            });
            actions.push({
                "id": "exclude-tag",
                "icon": "filter_alt_off",
                "label": "Exclude -" + tagFull,
                "onTrigger": () => {
                    if (root.nexus) {
                        root.nexus.leftSidebarTab = "search";
                        const excl = "-" + tagFull;
                        fileFilterField.text = excl;
                        root.nexus.searchVault(excl);
                    }
                    root.closeContextMenu();
                }
            });
            actions.push({
                "id": "tag-page",
                "icon": "article",
                "label": "Open / Create Tag Page",
                "onTrigger": () => {
                    if (root.nexus)
                        root.nexus.openOrCreateTagPage(tagClean);
                    root.closeContextMenu();
                }
            });
            actions.push({ "separator": true });
            actions.push({
                "id": "rename-tag",
                "icon": "drive_file_rename_outline",
                "label": "Rename Tag Across Vault...",
                "onTrigger": () => {
                    root.openTagActionDialog("rename", tagClean);
                }
            });
            actions.push({
                "id": "merge-tag",
                "icon": "merge_type",
                "label": "Merge Into Another Tag...",
                "onTrigger": () => {
                    root.openTagActionDialog("merge", tagClean);
                }
            });
            actions.push({
                "id": "copy-tag",
                "icon": "content_copy",
                "label": "Copy Tag",
                "onTrigger": () => {
                    if (root.nexus)
                        root.nexus.copyToClipboard(tagFull, "Copied tag");
                    root.closeContextMenu();
                }
            });
            actions.push({ "separator": true });
            if (root.nexus?.activeView === "document" && String(root.nexus?.currentPath ?? "").length > 0) {
                actions.push({
                    "id": "remove-tag-active",
                    "icon": "label_off",
                    "label": "Remove from Current Note",
                    "onTrigger": () => {
                        if (root.nexus)
                            root.nexus.removeTag(tagClean, root.nexus.currentPath, false);
                        root.closeContextMenu();
                    }
                });
            }
            actions.push({
                "id": "remove-tag-vault",
                "icon": "delete_sweep",
                "label": "Remove Tag from Vault",
                "isDestructive": true,
                "onTrigger": () => {
                    if (root.nexus)
                        root.nexus.removeTag(tagClean, "", true);
                    root.closeContextMenu();
                }
            });
        } else if (t === "calendarDay") {
            const iso = String(d.dateStr || "");
            actions.push({
                "id": "open-daily",
                "icon": "edit_calendar",
                "label": d.hasJournal ? "Open Daily Note" : "Create Daily Note",
                "onTrigger": () => {
                    if (root.nexus && iso.length > 0)
                        root.nexus.openDailyNote(iso);
                    root.closeContextMenu();
                }
            });
            actions.push({
                "id": "show-planner",
                "icon": "calendar_view_week",
                "label": "Show in Weekly Planner",
                "onTrigger": () => {
                    if (root.nexus && iso.length > 0) {
                        root.nexus.selectedDateStr = iso;
                        root.nexus.rightBottomTab = "schedule";
                        if (GlobalStates.dashboardPlannerBrowser) {
                            const nextState = Object.assign({}, GlobalStates.dashboardPlannerBrowser);
                            nextState.selectedDateIso = iso;
                            GlobalStates.dashboardPlannerBrowser = nextState;
                        }
                    }
                    root.closeContextMenu();
                }
            });
            actions.push({
                "id": "copy-date",
                "icon": "content_copy",
                "label": "Copy Date (" + iso + ")",
                "onTrigger": () => {
                    if (root.nexus && iso.length > 0)
                        root.nexus.copyToClipboard(iso, "Copied date");
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

    // ── Exercises Tracker <-> Nexus live bridge (service handle + read-only state.json fallback) ──
    property string exercisesTrackerStatePath: (Directories.stateUserPath ?? "") + "/exercises-tracker/state.json"
    property var _exercisesFallbackState: null
    property int _exercisesBridgeRevision: 0

    readonly property var exercisesTrackerService: HostServices.AlisIntergration?.exercisesTracker
        ?? HostServices.AlisIntergration?.session?.exercisesTracker
        ?? null
    readonly property bool exercisesTrackerEnabled: Boolean(HostServices.AlisIntergration?.exercisesTrackerEnabled)
        || Boolean(root.exercisesTrackerService?.ready)
        || Boolean(root._exercisesFallbackState)

    FileView {
        id: exercisesStateFallbackFile
        path: (!Boolean(root.exercisesTrackerService?.ready) && root.exercisesTrackerStatePath.length > 0)
            ? root.exercisesTrackerStatePath
            : ""
        watchChanges: root.surfaceActive && !Boolean(root.exercisesTrackerService?.ready)
        printErrors: false
        onLoaded: {
            try {
                const raw = exercisesStateFallbackFile.text();
                root._exercisesFallbackState = raw && raw.trim().length > 0 ? JSON.parse(raw) : null;
            } catch (e) {
                root._exercisesFallbackState = null;
            }
            root._exercisesBridgeRevision += 1;
        }
        onFileChanged: exercisesStateFallbackFile.reload()
        onLoadFailed: {
            root._exercisesFallbackState = null;
        }
    }

    Connections {
        target: root.exercisesTrackerService
        ignoreUnknownSignals: true
        function onStateUpdated() {
            root._exercisesBridgeRevision += 1;
        }
        function onRevisionChanged() {
            root._exercisesBridgeRevision += 1;
        }
    }

    readonly property var exercisesTrackerSummary: {
        void root._exercisesBridgeRevision;
        const svc = root.exercisesTrackerService;
        if (svc && svc.ready && svc.todaySummary)
            return svc.todaySummary;
        const fb = root._exercisesFallbackState;
        if (fb && typeof fb === "object") {
            if (fb.summary && typeof fb.summary === "object")
                return fb.summary;
            const todayIso = Qt.formatDate(new Date(), "yyyy-MM-dd");
            const dayRec = fb.days ? fb.days[todayIso] : null;
            const exList = Array.isArray(dayRec?.exercises) ? dayRec.exercises : [];
            let doneCount = 0;
            let volKg = 0;
            for (let i = 0; i < exList.length; ++i) {
                const ex = exList[i];
                if (ex && ex.completed)
                    doneCount += 1;
                const sets = Number(ex?.completedSets ?? (ex?.completed ? ex?.sets : 0)) || 0;
                const reps = parseFloat(String(ex?.reps ?? "0")) || 0;
                const w = Number(ex?.weight ?? 0) || 0;
                if (sets > 0 && reps > 0 && w > 0)
                    volKg += sets * reps * w;
            }
            const checkins = Array.isArray(fb.bodyCheckins) ? fb.bodyCheckins : [];
            const latest = checkins.length > 0 ? checkins[0] : null;
            return {
                todayDate: todayIso,
                todayRoutine: String(dayRec?.routine ?? ""),
                todayTitle: String(dayRec?.title ?? ""),
                todayTotalExercises: exList.length,
                todayCompletedExercises: doneCount,
                todayCompletionPct: exList.length > 0 ? Math.round((doneCount * 100) / exList.length) : 0,
                todayVolumeKg: Math.round(volKg),
                currentStreakDays: Number(fb.currentStreakDays ?? 0),
                totalLoggedWorkouts: fb.days ? Object.keys(fb.days).length : 0,
                totalBodyCheckins: checkins.length,
                latestWeightKg: Number(latest?.weightKg ?? 0),
                latestBodyFatPct: Number(latest?.bodyFatPct ?? 0),
                latestPhotoPath: String(latest?.photoPath ?? "")
            };
        }
        return ({});
    }

    readonly property var exercisesTrackerLatestCheckin: {
        void root._exercisesBridgeRevision;
        const svc = root.exercisesTrackerService;
        if (svc && svc.ready) {
            if (typeof svc.getRecentCheckins === "function") {
                const list = svc.getRecentCheckins(1);
                if (Array.isArray(list) && list.length > 0)
                    return list[0];
            }
            if (Array.isArray(svc.bodyCheckins) && svc.bodyCheckins.length > 0)
                return svc.bodyCheckins[0];
        }
        const checkins = root._exercisesFallbackState?.bodyCheckins;
        return (Array.isArray(checkins) && checkins.length > 0) ? checkins[0] : null;
    }

    readonly property string exercisesTrackerLatestPhotoUrl: {
        const ck = root.exercisesTrackerLatestCheckin;
        const directUrl = String(ck?.photoUrl ?? "").trim();
        if (directUrl.length > 0)
            return directUrl;
        const p = String(ck?.photoPath ?? root.exercisesTrackerSummary?.latestPhotoPath ?? "").trim();
        if (p.length === 0)
            return "";
        return p.startsWith("file://") ? p : ("file://" + p);
    }

    readonly property bool exercisesTrackerShowInNexus: Boolean(
        root.exercisesTrackerService?.preferences?.showInNexus
        ?? (root._exercisesFallbackState?.preferences?.showInNexus !== false)
    )

    readonly property bool exercisesTrackerCardVisible: root.exercisesTrackerEnabled
        && root.exercisesTrackerShowInNexus
        && (Boolean(HostServices.AlisIntergration?.exercisesTrackerEnabled)
            || Number(root.exercisesTrackerSummary?.todayTotalExercises ?? 0) > 0
            || Number(root.exercisesTrackerSummary?.totalLoggedWorkouts ?? 0) > 0
            || Number(root.exercisesTrackerSummary?.totalBodyCheckins ?? 0) > 0)

    function getExercisesDaySummary(dateStr: string): var {
        void root._exercisesBridgeRevision;
        const target = String(dateStr || Qt.formatDate(new Date(), "yyyy-MM-dd"));
        const svc = root.exercisesTrackerService;
        if (svc && svc.ready && typeof svc.getDaySummary === "function")
            return svc.getDaySummary(target) ?? ({});
        const fb = root._exercisesFallbackState;
        const dayRec = fb?.days ? fb.days[target] : null;
        if (!dayRec)
            return ({});
        const exList = Array.isArray(dayRec.exercises) ? dayRec.exercises : [];
        let doneCount = 0;
        for (let i = 0; i < exList.length; ++i) {
            if (exList[i]?.completed)
                doneCount += 1;
        }
        return {
            date: target,
            routine: String(dayRec.routine ?? ""),
            title: String(dayRec.title ?? ""),
            totalExercises: exList.length,
            completedExercises: doneCount,
            completionPct: exList.length > 0 ? Math.round((doneCount * 100) / exList.length) : 0,
            exercises: exList
        };
    }

    function openExercisesTracker(dateStr = ""): void {
        GlobalStates.dashboardPageId = "exercisesTracker";
        if (typeof Config !== "undefined" && Config && typeof Config.setNestedValue === "function")
            Config.setNestedValue("dashboard.lastPageId", "exercisesTracker");
        if (root.nexus && typeof root.nexus.close === "function")
            root.nexus.close();
        GlobalStates.nexusOpen = false;
        const svc = root.exercisesTrackerService;
        if (svc && typeof svc.openDashboardTracker === "function") {
            svc.openDashboardTracker(String(dateStr || ""));
            return;
        }
        GlobalStates.dashboardOpen = true;
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
    readonly property bool surfaceActive: root.visible && Boolean(root.nexus?.isOpen ?? true) && !root.wallpaperTransitionActive && !Boolean(GlobalStates.screenLocked)

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

    readonly property QtObject settledColors: settledColorsObj

    QtObject {
        id: settledColorsObj
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
        const bodyFgHex = root._settledOnLayer1;
        const borderHex = root.ccStop(6);
        const markBgHex = root.mixColorHex(accHex, root.ccStop(2), 0.30);
        const subHex = root._settledSubtext;
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

    // Live Alis Material Theme Palette Swatches (auto-themed to active Alis wallpaper colors, never flat gray)
    readonly property var homepageThemeSwatches: [
        String(settledColors.colLayer2),
        String(settledColors.colSecondaryContainer),
        String(settledColors.colSecondary),
        String(settledColors.colPrimary),
        String(settledColors.colTertiary),
        root.mixColorHex(root._settledPrimary, root._settledTertiary, 0.50),
        String(settledColors.colError),
        String(settledColors.colOnLayer0)
    ]

    readonly property var clusterPalette: [
        String(settledColors.colPrimary),
        String(settledColors.colTertiary),
        String(settledColors.colSecondary),
        root.mixColorHex(root._settledPrimary, root._settledTertiary, 0.45),
        root.mixColorHex(root._settledPrimary, String(settledColors.colError), 0.45),
        root.mixColorHex(root._settledTertiary, String(settledColors.colOnLayer0), 0.30),
        root.mixColorHex(root._settledSecondary, root._settledPrimary, 0.50),
        String(settledColors.colError)
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
        if (root.nexus?.commandPaletteOpen && root._commandPaletteSearchInput) {
            root._commandPaletteSearchInput.focus = true;
            root._commandPaletteSearchInput.forceActiveFocus();
            return;
        }
        if (newNoteBar.visible && newNotePathField) {
            newNotePathField.focus = true;
            newNotePathField.forceActiveFocus();
            return;
        }
        if (root._commandPaletteSearchInput)
            root._commandPaletteSearchInput.focus = false;
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
        if (root._collectionFilterField)
            root._collectionFilterField.focus = false;
        if (root._newCollectionEntryInput)
            root._newCollectionEntryInput.focus = false;
        if ((root.nexus?.activeView ?? "homepage") === "document"
            && ((root.nexus?.editorMode ?? "hybrid") === "raw"
                || (root.nexus?.editorMode ?? "hybrid") === "split"
                || (root.nexus?.currentDoc?.category ?? "") === "code")
            && root._docVimEditor) {
            root.cursorBlinkOn = true;
            root._docVimEditor.forceActiveFocus();
            return;
        }
        workspaceKeyScope.focus = true;
        workspaceKeyScope.forceActiveFocus();
        root.forceActiveFocus();
    }

    function focusPrimarySurface(): void {
        if (root.nexus?.commandPaletteOpen && root._commandPaletteSearchInput) {
            root._commandPaletteSearchInput.focus = true;
            root._commandPaletteSearchInput.forceActiveFocus();
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
            if (root.nexus.commandPaletteOpen && root._commandPaletteSearchInput) {
                root._commandPaletteSearchInput.focus = true;
                root._commandPaletteSearchInput.forceActiveFocus();
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
        if (root.tagDialogOpen) {
            root.tagDialogOpen = false;
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
            if (root._commandPaletteSearchInput)
                root._commandPaletteSearchInput.focus = false;
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
            || Boolean(root._collectionFilterField?.activeFocus)
            || Boolean(root._newCollectionEntryInput?.activeFocus)) {
            root.restoreWorkspaceFocus();
            Qt.callLater(root.restoreWorkspaceFocus);
            return true;
        }
        if (root.nexusCustomViewsLoader?.item && typeof root.nexusCustomViewsLoader.item.finishOrCancelInlineEditing === "function" && root.nexusCustomViewsLoader.item.finishOrCancelInlineEditing()) {
            root.restoreWorkspaceFocus();
            Qt.callLater(root.restoreWorkspaceFocus);
            return true;
        }
        if (root.nexusCustomViewsLoader?.item && (root.nexusCustomViewsLoader.item.editingPlaytime || root.nexusCustomViewsLoader.item.editingCompletion)) {
            root.nexusCustomViewsLoader.item.editingPlaytime = false;
            root.nexusCustomViewsLoader.item.editingCompletion = false;
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
            if (root.nexus.isDirty && root._docVimEditor)
                root.nexus.saveCurrentNote(root._docVimEditor.text);
            root.nexus.vimMode = "NORMAL";
            root.nexus.vimKeyBuffer = "";
            root.nexus.vimCountBuffer = "";
            root.nexus.vimCommandBuffer = "";
            root.nexus.vimVisualAnchor = -1;
            if (root._docVimEditor) {
                root._docVimEditor.deselect();
                root._docVimEditor.focus = false;
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
            if (root.nexusCustomViewsLoader?.active
                && root.nexusCustomViewsLoader?.item
                && root.nexusCustomViewsLoader.item.isCustomViewNote) {
                if (typeof root.nexusCustomViewsLoader.item.finishOrCancelInlineEditing === "function"
                    && root.nexusCustomViewsLoader.item.finishOrCancelInlineEditing()) {
                    root.restoreWorkspaceFocus();
                    Qt.callLater(root.restoreWorkspaceFocus);
                    return true;
                }
                if (typeof root.nexusCustomViewsLoader.item.startPrimaryInlineEdit === "function"
                    && root.nexusCustomViewsLoader.item.startPrimaryInlineEdit()) {
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
            if (root.nexus.commandPaletteOpen && root._commandPaletteSearchInput) {
                root._commandPaletteSearchInput.focus = true;
                root._commandPaletteSearchInput.forceActiveFocus();
                Qt.callLater(() => {
                    if (root.nexus?.commandPaletteOpen && root._commandPaletteSearchInput) {
                        root._commandPaletteSearchInput.focus = true;
                        root._commandPaletteSearchInput.forceActiveFocus();
                        root._commandPaletteSearchInput.selectAll();
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
            const fields = [fileFilterField, newNotePathField, quickPlannerEventInput, zkTitleField, root._collectionFilterField, root._newCollectionEntryInput];
            for (let i = 0; i < fields.length; ++i) {
                const f = fields[i];
                if (f && f.activeFocus && !root._pointInsideItem(f, pt.x, pt.y)) {
                    root.restoreWorkspaceFocus();
                    Qt.callLater(root.restoreWorkspaceFocus);
                    return;
                }
            }
            if ((!root.activeFocus || (!workspaceKeyScope.activeFocus && !(root._docVimEditor?.activeFocus) && !(root._commandPaletteSearchInput?.activeFocus)))
                && !root.standardNoteInlineEditing
                && !Boolean(root.nexus?.newNoteModalOpen)
                && !(root.nexusCustomViewsLoader?.item && root.nexusCustomViewsLoader.item.hasActiveInlineEditor)
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
        ignoreUnknownSignals: true
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
                    if (root.nexus?.newNoteModalOpen && root._newNoteApiSearchInput) {
                        root._newNoteApiSearchInput.forceActiveFocus();
                        root._newNoteApiSearchInput.selectAll();
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
            if (root.nexus?.commandPaletteOpen && root._commandPaletteSearchInput) {
                root._commandPaletteSearchInput.forceActiveFocus();
                Qt.callLater(() => {
                    if (root.nexus?.commandPaletteOpen && root._commandPaletteSearchInput) {
                        root._commandPaletteSearchInput.forceActiveFocus();
                        root._commandPaletteSearchInput.selectAll();
                    }
                });
            } else {
                if (root._commandPaletteSearchInput)
                    root._commandPaletteSearchInput.focus = false;
                root.restoreWorkspaceFocus();
                Qt.callLater(root.restoreWorkspaceFocus);
            }
        }
        function onCommandPaletteModeChanged() {
            if (root.nexus?.commandPaletteOpen && root._commandPaletteSearchInput) {
                root._commandPaletteSearchInput.forceActiveFocus();
                Qt.callLater(() => {
                    if (root.nexus?.commandPaletteOpen && root._commandPaletteSearchInput) {
                        root._commandPaletteSearchInput.forceActiveFocus();
                        root._commandPaletteSearchInput.selectAll();
                    }
                });
            }
        }
        function onEditorModeChanged() {
            const mode = root.nexus?.editorMode ?? "hybrid";
            if (mode === "raw" || mode === "split") {
                if (root._docVimEditor) {
                    root.cursorBlinkOn = true;
                    root._docVimEditor.forceActiveFocus();
                    root._docVimEditor.cursorVisible = true;
                }
                Qt.callLater(() => {
                    if (root._docVimPane?.visible && root._docVimEditor) {
                        root._docVimEditor.forceActiveFocus();
                        root._docVimEditor.cursorVisible = true;
                    }
                });
            } else {
                if (root._docVimEditor)
                    root._docVimEditor.focus = false;
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
            if (root.nexusCustomViewsLoader?.active && root.nexusCustomViewsLoader?.item && typeof root.nexusCustomViewsLoader.item.startPrimaryInlineEdit === "function") {
                if (root.nexusCustomViewsLoader.item.startPrimaryInlineEdit()) {
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

    // Obsidian-style top-edge hover slide-down icon tab bar for sidebar mini-workspaces
    // Stays completely collapsed (height 0, zero click blocking) until the top edge is hovered.
    component WorkspaceHoverTabBar: Item {
        id: hoverTabRoot
        property string tabBarObjectName: ""
        property var tabs: [] // [{ id, icon, label, active }]
        property string trailingText: ""
        property var actions: [] // [{ icon, tip, active, onClick }]
        signal tabSelected(string tabId)

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: hoverTabRoot.revealed ? 30 : 16
        z: 30

        readonly property bool _directHovered: topEdgeHover.hovered || barHover.hovered
        property bool _graceHold: false
        readonly property bool revealed: _directHovered || _graceHold

        on_DirectHoveredChanged: {
            if (_directHovered) {
                leaveGraceTimer.stop();
                _graceHold = true;
            } else {
                leaveGraceTimer.restart();
            }
        }

        Timer {
            id: leaveGraceTimer
            interval: 140
            repeat: false
            onTriggered: hoverTabRoot._graceHold = false
        }

        // Passive top-edge hover trigger (16px strip, never intercepts clicks/drags)
        Item {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 16
            HoverHandler {
                id: topEdgeHover
            }
        }

        // Clip viewport for genuine top-edge slide-down animation (bar keeps full 28px height, zero squishing)
        Item {
            id: slideViewport
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 30
            clip: true

            Rectangle {
                id: barBody
                objectName: hoverTabRoot.tabBarObjectName
                anchors.left: parent.left
                anchors.right: parent.right
                height: 28
                y: hoverTabRoot.revealed ? 0 : -height
                opacity: hoverTabRoot.revealed ? 1.0 : 0.0
                topLeftRadius: Math.max(0, (Appearance.rounding.normal ?? 12) - 1)
                topRightRadius: Math.max(0, (Appearance.rounding.normal ?? 12) - 1)
                color: Qt.rgba(settledColors.colLayer0.r, settledColors.colLayer0.g, settledColors.colLayer0.b, 0.94)

                Behavior on y {
                    enabled: Appearance.animationsEnabled
                    NumberAnimation {
                        duration: 180
                        easing.type: Easing.OutCubic
                    }
                }
                Behavior on opacity {
                    enabled: Appearance.animationsEnabled
                    NumberAnimation {
                        duration: 140
                        easing.type: Easing.OutCubic
                    }
                }

                HoverHandler {
                    id: barHover
                    enabled: hoverTabRoot.revealed
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 1
                    color: settledColors.colLayer0Border
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 6
                    anchors.rightMargin: 6
                    spacing: 4

                    Repeater {
                        model: hoverTabRoot.tabs
                        delegate: Rectangle {
                            required property var modelData
                            readonly property bool isTabActive: Boolean(modelData.active)
                            Layout.preferredHeight: 22
                            Layout.preferredWidth: tabRowInner.implicitWidth + 10
                            radius: 6
                            color: isTabActive
                                ? settledColors.colSecondaryContainer
                                : (tabItemMouse.containsMouse ? settledColors.colLayer2Hover : "transparent")
                            border.width: isTabActive ? 1 : 0
                            border.color: Qt.alpha(settledColors.colPrimary, 0.36)

                            RowLayout {
                                id: tabRowInner
                                anchors.centerIn: parent
                                spacing: 4

                                MaterialSymbol {
                                    text: String(modelData.icon ?? "tab")
                                    iconSize: 13
                                    color: parent.parent.isTabActive ? settledColors.colPrimary : settledColors.colSubtext
                                }
                                StyledText {
                                    visible: String(modelData.label ?? "").length > 0 && hoverTabRoot.tabs.length <= 2
                                    text: String(modelData.label ?? "")
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    font.weight: parent.parent.isTabActive ? Font.DemiBold : Font.Normal
                                    color: parent.parent.isTabActive ? settledColors.colOnSecondaryContainer : settledColors.colSubtext
                                }
                            }

                            MouseArea {
                                id: tabItemMouse
                                anchors.fill: parent
                                enabled: hoverTabRoot.revealed
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: hoverTabRoot.tabSelected(String(modelData.id ?? ""))
                            }
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    StyledText {
                        visible: hoverTabRoot.trailingText.length > 0
                        text: hoverTabRoot.trailingText
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: settledColors.colSubtext
                    }

                    Repeater {
                        model: hoverTabRoot.actions
                        delegate: Rectangle {
                            required property var modelData
                            readonly property bool isActActive: Boolean(modelData.active)
                            Layout.preferredWidth: 22
                            Layout.preferredHeight: 22
                            radius: 5
                            color: isActActive
                                ? settledColors.colSecondaryContainer
                                : (actMouse.containsMouse ? settledColors.colLayer2Hover : "transparent")

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: String(modelData.icon ?? "")
                                iconSize: 13
                                color: parent.isActActive ? settledColors.colPrimary : settledColors.colSubtext
                            }

                            MouseArea {
                                id: actMouse
                                anchors.fill: parent
                                enabled: hoverTabRoot.revealed
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (typeof modelData.onClick === "function")
                                        modelData.onClick();
                                }
                            }
                        }
                    }
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

            // Left Sidebar Icon Tabs Rail — sits OUTSIDE the Workspace Card in a strictly horizontal single row (never wraps, all actions reachable)
            Flickable {
                id: nexusLeftTabRail
                objectName: "nexusLeftTabRail"
                Layout.fillWidth: true
                Layout.preferredHeight: 30
                Layout.minimumHeight: 30
                Layout.maximumHeight: 30
                clip: true
                interactive: contentWidth > width + 1
                flickableDirection: Flickable.HorizontalFlick
                boundsBehavior: Flickable.StopAtBounds
                contentWidth: Math.max(width, nexusLeftTabRow.implicitWidth + 4)
                contentHeight: height

                RowLayout {
                    id: nexusLeftTabRow
                    objectName: "nexusExplorerToolbar"
                    x: 2
                    y: 0
                    width: Math.max(nexusLeftTabRail.width - 4, implicitWidth)
                    height: nexusLeftTabRail.height
                    spacing: 2

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
                            Layout.preferredWidth: nexusLeftColumn.width < 208 ? 22 : 26
                            Layout.preferredHeight: 26
                            radius: 7
                            color: active
                                ? settledColors.colSecondaryContainer
                                : (leftTabMouse.containsMouse ? settledColors.colLayer2Hover : "transparent")
                            border.width: active ? 1 : 0
                            border.color: Qt.alpha(settledColors.colPrimary, 0.35)

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: modelData.icon
                                iconSize: nexusLeftColumn.width < 208 ? 14 : 15
                                color: parent.active ? settledColors.colPrimary : settledColors.colSubtext
                            }
                            MouseArea {
                                id: leftTabMouse
                                anchors.fill: parent
                                hoverEnabled: true
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

                    Item {
                        Layout.fillWidth: true
                    }

                    // New Note button
                    Rectangle {
                        Layout.preferredWidth: nexusLeftColumn.width < 208 ? 20 : 22
                        Layout.preferredHeight: 24
                        radius: 6
                        color: newNoteMouse.containsMouse ? settledColors.colLayer2Hover : "transparent"
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "note_add"
                            iconSize: 14
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
                        Layout.preferredWidth: nexusLeftColumn.width < 208 ? 20 : 22
                        Layout.preferredHeight: 24
                        radius: 6
                        color: newNoteModalMouse.containsMouse ? settledColors.colLayer2Hover : "transparent"
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "travel_explore"
                            iconSize: 14
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

                    // Today's Journal button (always accessible on the single horizontal rail)
                    Rectangle {
                        Layout.preferredWidth: nexusLeftColumn.width < 208 ? 20 : 22
                        Layout.preferredHeight: 24
                        radius: 6
                        color: dailyMouse.containsMouse ? settledColors.colLayer2Hover : "transparent"
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "today"
                            iconSize: 14
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

                    // Rescan Vault button (always accessible on the single horizontal rail)
                    Rectangle {
                        Layout.preferredWidth: nexusLeftColumn.width < 208 ? 20 : 22
                        Layout.preferredHeight: 24
                        radius: 6
                        color: refreshMouse.containsMouse ? settledColors.colLayer2Hover : "transparent"
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "refresh"
                            iconSize: 14
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
                }
            }

            Item {
                id: leftSlot0
                objectName: "nexusLeftSlot0"
                readonly property int targetHeight: Math.max(120, Math.round(Math.max(320, nexusLeftColumn.height - 44) * (root.nexus?.leftSplitRatio ?? 0.62)))
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
                border.width: 1
                border.color: settledColors.colLayer0Border
                clip: true

                HoverHandler {
                    id: explorerCardHover
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 8

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
                            required property int index
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

                            // 100% Obsidian 01_Core.css Soft Folder Tree Lines + 1s Interval Music EQ-DSP Electric Current
                            Canvas {
                                id: treeGuideCanvas
                                objectName: "nexusSoftTreeGuideCanvas"
                                visible: (treeRowDelegate.modelData.depth ?? 0) > 0
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                width: Math.max(16, 10 + (treeRowDelegate.modelData.depth ?? 0) * 14)
                                antialiasing: true

                                readonly property int rowIdx: treeRowDelegate.index
                                readonly property int rowDepth: Number(treeRowDelegate.modelData.depth ?? 0)
                                readonly property bool rowIsDir: Boolean(treeRowDelegate.modelData.isDir)
                                readonly property bool rowIsLast: Boolean(treeRowDelegate.modelData.isLastChild)
                                readonly property string rowRelPath: String(treeRowDelegate.modelData.relPath ?? "")
                                readonly property var rowAncestorContinues: treeRowDelegate.modelData.ancestorContinues ?? []
                                readonly property var rowAncestorPaths: treeRowDelegate.modelData.ancestorPaths ?? []
                                readonly property bool isTargetRow: root.activeTreeTargetPath.length > 0 && root.activeTreeTargetPath === rowRelPath
                                // Exact 01_Core.css row-ordered active-segment predicate:
                                // True ONLY for rows strictly between an active ancestor and its next hop
                                // OR rows that ARE the next hop (intermediate ancestor folder or final target).
                                readonly property bool hasActiveAncestorTrail: {
                                    const info = root.activeTreeChainInfo;
                                    const hops = info?.hops;
                                    if (!hops || info.targetIdx < 0 || rowIdx > info.targetIdx)
                                        return false;
                                    for (let col = 0; col < rowDepth; ++col) {
                                        const anc = String(rowAncestorPaths[col] ?? "");
                                        const hop = anc.length > 0 ? hops[anc] : null;
                                        if (hop && rowIdx > hop.parentIdx && rowIdx <= hop.nextHopIdx)
                                            return true;
                                    }
                                    return false;
                                }
                                readonly property real electricPulse: hasActiveAncestorTrail ? root.treeElectricPhase : 0.0

                                onRowIdxChanged: requestPaint()
                                onRowDepthChanged: requestPaint()
                                onRowIsLastChanged: requestPaint()
                                onIsTargetRowChanged: requestPaint()
                                onHasActiveAncestorTrailChanged: requestPaint()
                                onElectricPulseChanged: {
                                    if (hasActiveAncestorTrail)
                                        requestPaint();
                                }
                                Connections {
                                    target: root
                                    function onThemeSignatureChanged() {
                                        if (treeGuideCanvas.visible)
                                            treeGuideCanvas.requestPaint();
                                    }
                                    function onActiveTreeChainInfoChanged() {
                                        if (treeGuideCanvas.visible)
                                            treeGuideCanvas.requestPaint();
                                    }
                                }

                                onPaint: {
                                    const ctx = getContext("2d");
                                    if (!ctx)
                                        return;
                                    const w = width;
                                    const h = height;
                                    ctx.clearRect(0, 0, w, h);
                                    const d = rowDepth;
                                    if (d <= 0)
                                        return;

                                    const depthAlphas = [1.0, 0.60, 0.40, 0.30, 0.24, 0.19, 0.15];
                                    const baseCol = treeRowDelegate.folderColor.length > 0
                                        ? treeRowDelegate.folderTintBase
                                        : settledColors.colSubtext;
                                    const hiCol = settledColors.colPrimary;
                                    const chainInfo = root.activeTreeChainInfo;
                                    const hops = chainInfo?.hops ?? ({});
                                    const firstParentIdx = chainInfo?.firstParentIdx ?? -1;
                                    const totalSteps = Math.max(1, Number(chainInfo?.totalSteps ?? 1));
                                    const rowStepStart = Math.max(0.0, Math.min(0.92, (rowIdx - firstParentIdx - 1) / totalSteps));
                                    const rowStepEnd = Math.max(rowStepStart + 0.08, Math.min(1.0, (rowIdx - firstParentIdx) / totalSteps));
                                    const cy = h * 0.5;
                                    const elbowR = 7.0;
                                    const pulse = electricPulse;
                                    const pulseOn = pulse > 0.005 && pulse < 0.995;

                                    // Helper to draw Music EQ-DSP 3-stroke glowing electric current along a path
                                    function strokeElectric(pathFn, segPhaseStart, segPhaseEnd) {
                                        if (!pulseOn)
                                            return;
                                        const localP = (pulse - segPhaseStart) / Math.max(0.08, segPhaseEnd - segPhaseStart);
                                        if (localP < -0.22 || localP > 1.22)
                                            return;
                                        const env = Math.max(0.0, 1.0 - Math.abs(localP - 0.5) * 1.45);
                                        if (env <= 0.02)
                                            return;
                                        ctx.save();
                                        if (typeof ctx.setLineDash === "function")
                                            ctx.setLineDash([]);
                                        ctx.lineCap = "round";
                                        ctx.lineJoin = "round";
                                        // 1. Wide outer plasma glow
                                        ctx.strokeStyle = Qt.rgba(hiCol.r, hiCol.g, hiCol.b, 0.24 * env);
                                        ctx.lineWidth = 4.2;
                                        ctx.beginPath();
                                        pathFn(true);
                                        ctx.stroke();
                                        // 2. Bright mid plasma stroke
                                        ctx.strokeStyle = Qt.rgba(hiCol.r, hiCol.g, hiCol.b, 0.78 * env);
                                        ctx.lineWidth = 1.9;
                                        ctx.beginPath();
                                        pathFn(true);
                                        ctx.stroke();
                                        // 3. White-hot core filament
                                        ctx.strokeStyle = Qt.rgba(
                                            Math.min(1.0, hiCol.r * 0.35 + 0.65),
                                            Math.min(1.0, hiCol.g * 0.35 + 0.65),
                                            Math.min(1.0, hiCol.b * 0.35 + 0.65),
                                            0.92 * env
                                        );
                                        ctx.lineWidth = 0.85;
                                        ctx.beginPath();
                                        pathFn(false);
                                        ctx.stroke();
                                        ctx.restore();
                                    }

                                    // 1. Ancestor vertical trunks (cols 0 .. d - 2)
                                    // Strictly lit ONLY when this row lies between hop.parentIdx and hop.nextHopIdx!
                                    // Outer trunks passing past an active folder (rowIdx > hop.nextHopIdx) stay DIM.
                                    for (let col = 0; col < d - 1; ++col) {
                                        const continues = Boolean(rowAncestorContinues[col]);
                                        if (!continues)
                                            continue;
                                        const x = 10.5 + col * 14;
                                        const ancPath = String(rowAncestorPaths[col] ?? "");
                                        const hop = ancPath.length > 0 ? hops[ancPath] : null;
                                        const onActivePassThrough = Boolean(hop && rowIdx > hop.parentIdx && rowIdx < hop.nextHopIdx);
                                        const tierAlpha = depthAlphas[Math.min(depthAlphas.length - 1, col)] * 0.38;

                                        ctx.save();
                                        if (typeof ctx.setLineDash === "function")
                                            ctx.setLineDash([]);
                                        ctx.strokeStyle = onActivePassThrough
                                            ? Qt.rgba(hiCol.r, hiCol.g, hiCol.b, 0.85)
                                            : Qt.rgba(baseCol.r, baseCol.g, baseCol.b, tierAlpha);
                                        ctx.lineWidth = onActivePassThrough ? 1.5 : 1.0;
                                        ctx.beginPath();
                                        ctx.moveTo(x, 0);
                                        ctx.lineTo(x, h);
                                        ctx.stroke();
                                        ctx.restore();

                                        if (onActivePassThrough && pulseOn) {
                                            const jitterAmp = 1.35;
                                            const freq = 0.38;
                                            const phaseShift = pulse * 14.0 + col * 1.9 + root.treeElectricSeq * 0.7;
                                            strokeElectric((jitter) => {
                                                ctx.moveTo(x, 0);
                                                const steps = 6;
                                                for (let s = 1; s < steps; ++s) {
                                                    const yy = (h * s) / steps;
                                                    const jx = jitter ? Math.sin(yy * freq + phaseShift) * jitterAmp : 0.0;
                                                    ctx.lineTo(x + jx, yy);
                                                }
                                                ctx.lineTo(x, h);
                                            }, rowStepStart, rowStepEnd);
                                        }
                                    }

                                    // 2. Direct parent connector (col = d - 1): 01_Core.css Soft Folder Tree
                                    // Folders = solid 1px + 7px rounded elbow on last child
                                    // Files   = dotted [2, 3] + 7px rounded dotted elbow on last child
                                    const cIdx = d - 1;
                                    const px = 10.5 + cIdx * 14;
                                    const branchEndX = px + 10.5;
                                    const parentPath = String(rowAncestorPaths[cIdx] ?? "");
                                    const parentHop = parentPath.length > 0 ? hops[parentPath] : null;
                                    // Exact 3-way classification matching Obsidian 01_Core.css:
                                    // - isActiveTurn: this row IS hop.nextHopIdx (intermediate ancestor folder OR hovered target)
                                    // - isActivePassThrough: this row is a sibling strictly ABOVE hop.nextHopIdx
                                    // - otherwise (including siblings BELOW hop.nextHopIdx): 100% DIM!
                                    const isActiveTurn = Boolean(parentHop && rowIdx === parentHop.nextHopIdx);
                                    const isActivePassThrough = Boolean(parentHop && rowIdx > parentHop.parentIdx && rowIdx < parentHop.nextHopIdx);
                                    const highlightUpper = isActiveTurn || isActivePassThrough;
                                    const highlightBranch = isActiveTurn;
                                    const highlightLower = !rowIsLast && isActivePassThrough;
                                    const baseAlpha = depthAlphas[Math.min(depthAlphas.length - 1, cIdx)] * (rowIsDir ? 0.44 : 0.38);

                                    ctx.save();
                                    ctx.lineCap = "round";
                                    ctx.lineJoin = "round";
                                    if (!rowIsDir && typeof ctx.setLineDash === "function")
                                        ctx.setLineDash([2.0, 3.0]);
                                    else if (typeof ctx.setLineDash === "function")
                                        ctx.setLineDash([]);

                                    if (rowIsLast) {
                                        // Smooth 7px bottom-left rounded elbow (no downward overhang)
                                        const r = Math.min(elbowR, cy - 1.0, branchEndX - px - 1.0);
                                        ctx.strokeStyle = isActiveTurn
                                            ? Qt.rgba(hiCol.r, hiCol.g, hiCol.b, isTargetRow ? 0.94 : 0.86)
                                            : Qt.rgba(baseCol.r, baseCol.g, baseCol.b, baseAlpha);
                                        ctx.lineWidth = isActiveTurn ? 1.6 : 1.0;
                                        ctx.beginPath();
                                        ctx.moveTo(px, 0);
                                        ctx.lineTo(px, Math.max(0, cy - r));
                                        ctx.quadraticCurveTo(px, cy, px + r, cy);
                                        ctx.lineTo(branchEndX, cy);
                                        ctx.stroke();
                                    } else {
                                        // Upper trunk (top -> cy)
                                        ctx.strokeStyle = highlightUpper
                                            ? Qt.rgba(hiCol.r, hiCol.g, hiCol.b, isActiveTurn ? 0.92 : 0.82)
                                            : Qt.rgba(baseCol.r, baseCol.g, baseCol.b, baseAlpha);
                                        ctx.lineWidth = highlightUpper ? 1.55 : 1.0;
                                        ctx.beginPath();
                                        ctx.moveTo(px, 0);
                                        ctx.lineTo(px, cy);
                                        ctx.stroke();

                                        // Horizontal branch (px -> branchEndX): lit for BOTH intermediate ancestor turn AND final target
                                        ctx.strokeStyle = highlightBranch
                                            ? Qt.rgba(hiCol.r, hiCol.g, hiCol.b, isTargetRow ? 0.94 : 0.86)
                                            : Qt.rgba(baseCol.r, baseCol.g, baseCol.b, baseAlpha);
                                        ctx.lineWidth = highlightBranch ? 1.6 : 1.0;
                                        ctx.beginPath();
                                        ctx.moveTo(px, cy);
                                        ctx.lineTo(branchEndX, cy);
                                        ctx.stroke();

                                        // Lower trunk (cy -> bottom): strictly DIM once path turns into this row or below target!
                                        ctx.strokeStyle = highlightLower
                                            ? Qt.rgba(hiCol.r, hiCol.g, hiCol.b, 0.80)
                                            : Qt.rgba(baseCol.r, baseCol.g, baseCol.b, baseAlpha * 0.85);
                                        ctx.lineWidth = highlightLower ? 1.45 : 1.0;
                                        ctx.beginPath();
                                        ctx.moveTo(px, cy);
                                        ctx.lineTo(px, h);
                                        ctx.stroke();
                                    }
                                    ctx.restore();

                                    // 3. Sequential Top-to-Bottom Electric Current (1s interval EQ-DSP surge)
                                    if (isActiveTurn && pulseOn) {
                                        const r = Math.min(elbowR, cy - 1.0, branchEndX - px - 1.0);
                                        const pShift = pulse * 18.0 + root.treeElectricSeq * 1.1 + cIdx * 1.3;
                                        strokeElectric((jitter) => {
                                            ctx.moveTo(px, 0);
                                            const midY = Math.max(2.0, (cy - r) * 0.5);
                                            ctx.lineTo(px + (jitter ? Math.sin(pShift) * 1.3 : 0.0), midY);
                                            ctx.lineTo(px, Math.max(0, cy - r));
                                            ctx.quadraticCurveTo(px, cy, px + r, cy);
                                            ctx.lineTo(branchEndX, cy + (jitter ? Math.cos(pShift * 1.3) * 0.9 : 0.0));
                                        }, rowStepStart, rowStepEnd);
                                        // Bright plasma spark tip arriving at the hovered/focused folder or note
                                        if (isTargetRow) {
                                            const sparkT = Math.max(0.0, Math.min(1.0, (pulse - rowStepStart) / Math.max(0.12, rowStepEnd - rowStepStart)));
                                            if (sparkT > 0.0 && sparkT < 1.0) {
                                                const sx = px + (branchEndX - px) * sparkT;
                                                ctx.save();
                                                ctx.beginPath();
                                                ctx.arc(sx, cy, 3.0, 0, Math.PI * 2);
                                                ctx.fillStyle = Qt.rgba(hiCol.r, hiCol.g, hiCol.b, 0.35 * (1.0 - sparkT * 0.5));
                                                ctx.fill();
                                                ctx.beginPath();
                                                ctx.arc(sx, cy, 1.4, 0, Math.PI * 2);
                                                ctx.fillStyle = Qt.rgba(1.0, 1.0, 1.0, 0.92 * (1.0 - sparkT * 0.4));
                                                ctx.fill();
                                                ctx.restore();
                                            }
                                        }
                                    } else if (isActivePassThrough && pulseOn) {
                                        const pShift = pulse * 15.0 + cIdx * 1.7 + root.treeElectricSeq * 0.7;
                                        strokeElectric((jitter) => {
                                            ctx.moveTo(px, 0);
                                            ctx.lineTo(px + (jitter ? Math.sin(pShift) * 1.2 : 0.0), cy);
                                            ctx.lineTo(px, h);
                                        }, rowStepStart, rowStepEnd);
                                    }
                                }
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
                                onEntered: {
                                    root.hoveredTreeRowPath = String(treeRowDelegate.modelData.relPath ?? "");
                                    root.hoveredTreeAncestorPaths = treeRowDelegate.modelData.ancestorPaths ?? [];
                                }
                                onExited: {
                                    if (root.hoveredTreeRowPath === String(treeRowDelegate.modelData.relPath ?? "")) {
                                        root.hoveredTreeRowPath = "";
                                        root.hoveredTreeAncestorPaths = [];
                                    }
                                }
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

                    // Tab 2: Tag Wrangler+ Sidebar (Filter, Sort, Expand/Collapse, Atomic Vault Rename/Merge/Remove & Tag Pages)
                    ColumnLayout {
                        id: nexusTagWranglerPane
                        objectName: "nexusTagWranglerPane"
                        visible: (root.nexus?.leftSidebarTab ?? "files") === "tags"
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 6

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 4

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 26
                                radius: 6
                                color: settledColors.colLayer0
                                border.width: 1
                                border.color: tagFilterInput.activeFocus ? settledColors.colPrimary : settledColors.colLayer0Border

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 6
                                    anchors.rightMargin: 4
                                    spacing: 4

                                    MaterialSymbol {
                                        text: "tag"
                                        iconSize: 13
                                        color: tagFilterInput.activeFocus ? settledColors.colPrimary : settledColors.colSubtext
                                    }
                                    TextField {
                                        id: tagFilterInput
                                        objectName: "nexusTagFilterInput"
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 24
                                        topPadding: 0
                                        bottomPadding: 0
                                        verticalAlignment: TextInput.AlignVCenter
                                        placeholderText: "Filter tags..."
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: settledColors.colOnLayer0
                                        background: null
                                        onTextChanged: {
                                            if (root.nexus)
                                                root.nexus.tagSearchQuery = text;
                                        }
                                        Keys.onEscapePressed: event => {
                                            text = "";
                                            focus = false;
                                            root.restoreWorkspaceFocus();
                                            event.accepted = true;
                                        }
                                    }
                                }
                            }

                            // Sort cycle button (Count ↓ / Count ↑ / A→Z / Z→A)
                            Rectangle {
                                objectName: "nexusTagSortButton"
                                Layout.preferredHeight: 26
                                Layout.preferredWidth: tagSortLbl.implicitWidth + 10
                                radius: 6
                                color: tagSortMouse.containsMouse ? settledColors.colLayer2Hover : settledColors.colLayer0
                                border.width: 1
                                border.color: settledColors.colLayer0Border

                                StyledText {
                                    id: tagSortLbl
                                    anchors.centerIn: parent
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: 9
                                    font.weight: Font.DemiBold
                                    color: settledColors.colPrimary
                                    text: {
                                        const m = root.nexus?.tagSortMode ?? "countDesc";
                                        if (m === "countAsc") return "#↑";
                                        if (m === "nameAsc") return "A-Z";
                                        if (m === "nameDesc") return "Z-A";
                                        return "#↓";
                                    }
                                }
                                MouseArea {
                                    id: tagSortMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (root.nexus)
                                            root.nexus.cycleTagSortMode();
                                    }
                                }
                            }

                            // Expand All subtag groups
                            Rectangle {
                                Layout.preferredWidth: 24
                                Layout.preferredHeight: 26
                                radius: 6
                                color: tagExpAllMouse.containsMouse ? settledColors.colLayer2Hover : settledColors.colLayer0
                                border.width: 1
                                border.color: settledColors.colLayer0Border
                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "unfold_more"
                                    iconSize: 13
                                    color: settledColors.colSubtext
                                }
                                MouseArea {
                                    id: tagExpAllMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (root.nexus)
                                            root.nexus.expandAllTagGroups();
                                    }
                                }
                            }

                            // Collapse All subtag groups
                            Rectangle {
                                Layout.preferredWidth: 24
                                Layout.preferredHeight: 26
                                radius: 6
                                color: tagColAllMouse.containsMouse ? settledColors.colLayer2Hover : settledColors.colLayer0
                                border.width: 1
                                border.color: settledColors.colLayer0Border
                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "unfold_less"
                                    iconSize: 13
                                    color: settledColors.colSubtext
                                }
                                MouseArea {
                                    id: tagColAllMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (root.nexus)
                                            root.nexus.collapseAllTagGroups();
                                    }
                                }
                            }
                        }

                        ListView {
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
                                color: (tagMouse.containsMouse || tagRenameQuickMouse.containsMouse || tagPageQuickMouse.containsMouse || tagMenuQuickMouse.containsMouse)
                                    ? settledColors.colLayer2Hover
                                    : "transparent"

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 6 + (tagRowDelegate.modelData.depth ?? 0) * 14
                                    anchors.rightMargin: 6
                                    z: 2
                                    spacing: 4

                                    // Chevron dropdown toggle for parent tags with subtags
                                    Rectangle {
                                        visible: Boolean(tagRowDelegate.modelData.hasChildren)
                                        Layout.preferredWidth: 18
                                        Layout.preferredHeight: 18
                                        radius: 4
                                        color: chevronMouse.containsMouse ? settledColors.colLayer2 : "transparent"

                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: tagRowDelegate.modelData.expanded ? "expand_more" : "chevron_right"
                                            iconSize: 14
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

                                    Item {
                                        visible: !Boolean(tagRowDelegate.modelData.hasChildren) && (tagRowDelegate.modelData.depth ?? 0) === 0
                                        Layout.preferredWidth: 4
                                    }

                                    MaterialSymbol {
                                        visible: Boolean(tagRowDelegate.modelData.isSubtag)
                                        text: "subdirectory_arrow_right"
                                        iconSize: 12
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

                                    // Hover quick Tag Wrangler+ action: Rename Tag
                                    Rectangle {
                                        visible: tagMouse.containsMouse || tagRenameQuickMouse.containsMouse || tagPageQuickMouse.containsMouse || tagMenuQuickMouse.containsMouse
                                        Layout.preferredWidth: 20
                                        Layout.preferredHeight: 20
                                        radius: 4
                                        color: tagRenameQuickMouse.containsMouse ? settledColors.colSecondaryContainer : "transparent"
                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: "edit"
                                            iconSize: 12
                                            color: settledColors.colPrimary
                                        }
                                        MouseArea {
                                            id: tagRenameQuickMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.openTagActionDialog("rename", tagRowDelegate.modelData.name)
                                        }
                                    }

                                    // Hover quick Tag Wrangler+ action: Open/Create Tag Page
                                    Rectangle {
                                        visible: tagMouse.containsMouse || tagRenameQuickMouse.containsMouse || tagPageQuickMouse.containsMouse || tagMenuQuickMouse.containsMouse
                                        Layout.preferredWidth: 20
                                        Layout.preferredHeight: 20
                                        radius: 4
                                        color: tagPageQuickMouse.containsMouse ? settledColors.colSecondaryContainer : "transparent"
                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: "article"
                                            iconSize: 12
                                            color: settledColors.colSubtext
                                        }
                                        MouseArea {
                                            id: tagPageQuickMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (root.nexus)
                                                    root.nexus.openOrCreateTagPage(tagRowDelegate.modelData.name);
                                            }
                                        }
                                    }

                                    // Hover quick Tag Wrangler+ action: More menu (Merge / Exclude / Remove)
                                    Rectangle {
                                        visible: tagMouse.containsMouse || tagRenameQuickMouse.containsMouse || tagPageQuickMouse.containsMouse || tagMenuQuickMouse.containsMouse
                                        Layout.preferredWidth: 20
                                        Layout.preferredHeight: 20
                                        radius: 4
                                        color: tagMenuQuickMouse.containsMouse ? settledColors.colSecondaryContainer : "transparent"
                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: "more_vert"
                                            iconSize: 12
                                            color: settledColors.colSubtext
                                        }
                                        MouseArea {
                                            id: tagMenuQuickMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: mouse => {
                                                const pt = mapToItem(root, mouse.x, mouse.y);
                                                root.openContextMenu(pt.x, pt.y, {
                                                    "type": "tag",
                                                    "title": tagRowDelegate.modelData.fullTag || ("#" + tagRowDelegate.modelData.name),
                                                    "tag": tagRowDelegate.modelData.name,
                                                    "fullTag": tagRowDelegate.modelData.fullTag || ("#" + tagRowDelegate.modelData.name)
                                                });
                                            }
                                        }
                                    }

                                    Rectangle {
                                        Layout.preferredWidth: Math.max(24, tagCountTxt.implicitWidth + 10)
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
                    if ((activeLocalGraph?.nodes?.length ?? 0) > 0 && !_graphSettledOnce)
                        Qt.callLater(() => {
                            if (nexusLocalGraphCard && !nexusLocalGraphCard._graphSettledOnce)
                                nexusLocalGraphCard._graphSettledOnce = true;
                        });
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
                    onNodeActivated: nodeData => root.activateGraphNode(nodeData)
                }

                // Obsidian-style top-edge hover slide-down icon tab bar (collapsed height 0 until top edge hovered)
                WorkspaceHoverTabBar {
                    tabBarObjectName: "nexusLocalGraphStatusBar"
                    tabs: [
                        {
                            "id": "localGraph",
                            "icon": "hub",
                            "label": "Local Graph",
                            "active": true
                        }
                    ]
                    trailingText: String((nexusLocalGraphCard.activeLocalGraph?.nodes ?? []).length) + " nodes"
                    actions: [
                        {
                            "icon": "center_focus_strong",
                            "tip": "Reset View",
                            "active": false,
                            "onClick": () => localGraphCanvas.resetView()
                        }
                    ]
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
                                        return settledColors.colTertiary;
                                    if (vimState === "VISUAL")
                                        return settledColors.colSecondary;
                                    if (vimState === "COMMAND" || vimState === "SEARCH")
                                        return root.mixColorHex(settledColors.colPrimary, settledColors.colTertiary, 0.50);
                                    return settledColors.colPrimary;
                                }

                                RowLayout {
                                    id: vimBadgeRow
                                    anchors.centerIn: parent
                                    spacing: 5
                                    MaterialSymbol {
                                        text: vimBadge.inEditMode ? "terminal" : "menu_book"
                                        iconSize: 14
                                        color: (vimBadge.inEditMode && vimBadge.vimOn) ? settledColors.colOnPrimary : settledColors.colPrimary
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
                                        color: (vimBadge.inEditMode && vimBadge.vimOn) ? settledColors.colOnPrimary : settledColors.colOnLayer1
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
                                                Connections {
                                                    target: root
                                                    function onTransitionSettledChanged() {
                                                        if (emblemCanvas.visible && root.surfaceActive && root.transitionSettled)
                                                            emblemCanvas.requestPaint();
                                                    }
                                                }
                                                onAccentColChanged: {
                                                    if (visible && root.surfaceActive && root.transitionSettled)
                                                        requestPaint();
                                                }
                                                on_ThemeSigChanged: {
                                                    if (visible && root.surfaceActive && root.transitionSettled)
                                                        requestPaint();
                                                }
                                                onVisibleChanged: {
                                                    if (visible && root.surfaceActive && root.transitionSettled)
                                                        requestPaint();
                                                }
                                                onWidthChanged: {
                                                    if (visible && root.transitionSettled)
                                                        requestPaint();
                                                }
                                                onHeightChanged: {
                                                    if (visible && root.transitionSettled)
                                                        requestPaint();
                                                }
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
                                                    : (heroPillMouse.containsMouse
                                                        ? settledColors.colSecondaryContainer
                                                        : settledColors.colLayer2)
                                                border.width: 1
                                                border.color: modelData.primary
                                                    ? settledColors.colPrimary
                                                    : (heroPillMouse.containsMouse
                                                        ? Qt.alpha(settledColors.colPrimary, 0.65)
                                                        : Qt.alpha(settledColors.colPrimary, 0.28))

                                                StyledText {
                                                    id: pillLabel
                                                    anchors.centerIn: parent
                                                    horizontalAlignment: Text.AlignHCenter
                                                    text: modelData.label
                                                    font.family: Appearance.font.family.monospace
                                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                                    font.weight: modelData.primary ? Font.Bold : Font.DemiBold
                                                    color: modelData.primary
                                                        ? settledColors.colOnPrimary
                                                        : (heroPillMouse.containsMouse ? settledColors.colOnSecondaryContainer : settledColors.colPrimary)
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

                            // Ornamental Diamond Divider (`─── ◇ ───`) — auto-themed to Alis
                            RowLayout {
                                objectName: "nexusOrnamentalSeparator"
                                Layout.fillWidth: true
                                spacing: 10
                                Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Qt.alpha(settledColors.colPrimary, 0.28) }
                                StyledText { text: "◇"; font.pixelSize: 10; color: settledColors.colPrimary }
                                Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Qt.alpha(settledColors.colPrimary, 0.28) }
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
                                                        cache: false
                                                        mipmap: false
                                                        sourceSize: Qt.size(512, 512)
                                                        layer.enabled: root.surfaceActive && homepagePhotoImage.visible && homepagePhotoImage.status === Image.Ready
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
                                                        active: root.transitionSettled || _globeSettledOnce
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

                                            // Live Exercises & Body Tracker Bridge Card (synced from DashboardExercisesTracker / state.json)
                                            Rectangle {
                                                id: nexusExercisesTrackerCard
                                                objectName: "nexusExercisesTrackerCard"
                                                visible: root.exercisesTrackerCardVisible
                                                Layout.fillWidth: true
                                                implicitHeight: exercisesBridgeCol.implicitHeight + 18
                                                radius: 8
                                                color: settledColors.colLayer1
                                                border.width: 1
                                                border.color: settledColors.colLayer0Border

                                                ColumnLayout {
                                                    id: exercisesBridgeCol
                                                    anchors.fill: parent
                                                    anchors.margins: 10
                                                    spacing: 6

                                                    RowLayout {
                                                        Layout.fillWidth: true
                                                        spacing: 6

                                                        Rectangle {
                                                            width: 3
                                                            height: 14
                                                            radius: 1.5
                                                            color: settledColors.colTertiary ?? settledColors.colPrimary
                                                        }

                                                        StyledText {
                                                            Layout.fillWidth: true
                                                            Layout.minimumWidth: 0
                                                            text: {
                                                                const t = String(root.exercisesTrackerSummary?.todayTitle || root.exercisesTrackerSummary?.todayRoutine || "").trim();
                                                                return t.length > 0 ? ("Workout · " + t) : "Exercises & Body Tracker";
                                                            }
                                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                                            font.weight: Font.Bold
                                                            color: settledColors.colPrimary
                                                            elide: Text.ElideRight
                                                        }

                                                        Rectangle {
                                                            id: openExercisesTrackerBtn
                                                            objectName: "nexusOpenExercisesTrackerButton"
                                                            implicitHeight: 22
                                                            implicitWidth: openExBtnRow.implicitWidth + 14
                                                            height: 22
                                                            width: openExBtnRow.implicitWidth + 14
                                                            radius: 6
                                                            color: openExMouse.containsMouse ? settledColors.colPrimary : settledColors.colLayer2
                                                            border.width: 1
                                                            border.color: settledColors.colLayer0Border

                                                            Row {
                                                                id: openExBtnRow
                                                                anchors.centerIn: parent
                                                                spacing: 4

                                                                MaterialSymbol {
                                                                    anchors.verticalCenter: parent.verticalCenter
                                                                    text: "fitness_center"
                                                                    iconSize: 13
                                                                    color: openExMouse.containsMouse ? settledColors.colOnPrimary : settledColors.colPrimary
                                                                }

                                                                StyledText {
                                                                    anchors.verticalCenter: parent.verticalCenter
                                                                    text: "Tracker"
                                                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                                                    font.weight: Font.Bold
                                                                    color: openExMouse.containsMouse ? settledColors.colOnPrimary : settledColors.colPrimary
                                                                }
                                                            }

                                                            MouseArea {
                                                                id: openExMouse
                                                                anchors.fill: parent
                                                                hoverEnabled: true
                                                                cursorShape: Qt.PointingHandCursor
                                                                onClicked: root.openExercisesTracker(String(root.exercisesTrackerSummary?.todayDate ?? ""))
                                                            }
                                                        }
                                                    }

                                                    RowLayout {
                                                        Layout.fillWidth: true
                                                        spacing: 8

                                                        Rectangle {
                                                            visible: root.exercisesTrackerLatestPhotoUrl.length > 0
                                                            Layout.preferredWidth: 40
                                                            Layout.preferredHeight: 40
                                                            width: 40
                                                            height: 40
                                                            radius: 6
                                                            color: settledColors.colLayer0
                                                            border.width: 1
                                                            border.color: settledColors.colLayer0Border
                                                            clip: true

                                                            Image {
                                                                anchors.fill: parent
                                                                source: root.exercisesTrackerLatestPhotoUrl
                                                                fillMode: Image.PreserveAspectCrop
                                                                asynchronous: true
                                                                cache: false
                                                                mipmap: false
                                                                sourceSize: Qt.size(96, 96)
                                                            }
                                                        }

                                                        ColumnLayout {
                                                            Layout.fillWidth: true
                                                            Layout.minimumWidth: 0
                                                            spacing: 2

                                                            StyledText {
                                                                Layout.fillWidth: true
                                                                Layout.minimumWidth: 0
                                                                text: {
                                                                    const done = Number(root.exercisesTrackerSummary?.todayCompletedExercises ?? 0);
                                                                    const total = Number(root.exercisesTrackerSummary?.todayTotalExercises ?? 0);
                                                                    const pct = Number(root.exercisesTrackerSummary?.todayCompletionPct ?? 0);
                                                                    const streak = Number(root.exercisesTrackerSummary?.currentStreakDays ?? 0);
                                                                    const parts = [String(done) + "/" + String(total) + " done (" + String(pct) + "%)"];
                                                                    if (streak > 0)
                                                                        parts.push(String(streak) + "d streak");
                                                                    const vol = Number(root.exercisesTrackerSummary?.todayVolumeKg ?? 0);
                                                                    if (vol > 0)
                                                                        parts.push(String(Math.round(vol)) + " kg vol");
                                                                    return parts.join(" · ");
                                                                }
                                                                font.family: Appearance.font.family.monospace
                                                                font.pixelSize: 10
                                                                color: settledColors.colOnLayer1
                                                                elide: Text.ElideRight
                                                            }

                                                            StyledText {
                                                                visible: Number(root.exercisesTrackerSummary?.latestWeightKg ?? 0) > 0
                                                                    || Number(root.exercisesTrackerSummary?.totalBodyCheckins ?? 0) > 0
                                                                Layout.fillWidth: true
                                                                Layout.minimumWidth: 0
                                                                text: {
                                                                    const metrics = [];
                                                                    const wt = Number(root.exercisesTrackerSummary?.latestWeightKg ?? 0);
                                                                    const bf = Number(root.exercisesTrackerSummary?.latestBodyFatPct ?? 0);
                                                                    const ckCount = Number(root.exercisesTrackerSummary?.totalBodyCheckins ?? 0);
                                                                    if (wt > 0)
                                                                        metrics.push(wt.toFixed(1) + " kg");
                                                                    if (bf > 0)
                                                                        metrics.push(bf.toFixed(1) + "% BF");
                                                                    if (ckCount > 0)
                                                                        metrics.push(String(ckCount) + " check-ins");
                                                                    return "Body · " + metrics.join(" · ");
                                                                }
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
                                            "accent": String(settledColors.colPrimary),
                                            "count": (root.nexus?.collections?.movies ?? []).length,
                                            "subtitle": "Posters · IMDb · Cast · Plot"
                                        },
                                        {
                                            "id": "tvSeries",
                                            "title": "TV-Series Tracker",
                                            "icon": "live_tv",
                                            "accent": root.mixColorHex(settledColors.colPrimary, settledColors.colSecondary, 0.55),
                                            "count": (root.nexus?.collections?.tvseries ?? root.nexus?.collections?.tvSeries ?? []).length,
                                            "subtitle": "Seasons · Status · Ratings"
                                        },
                                        {
                                            "id": "games",
                                            "title": "Games Library",
                                            "icon": "sports_esports",
                                            "accent": String(settledColors.colSecondary),
                                            "count": (root.nexus?.collections?.games ?? []).length,
                                            "subtitle": "Play status · Genres · Steam"
                                        },
                                        {
                                            "id": "books",
                                            "title": "Books & Reading",
                                            "icon": "menu_book",
                                            "accent": root.mixColorHex(settledColors.colPrimary, settledColors.colTertiary, 0.50),
                                            "count": (root.nexus?.collections?.books ?? []).length,
                                            "subtitle": "Authors · Progress · Notes"
                                        },
                                        {
                                            "id": "recipes",
                                            "title": "Cooking & Recipes",
                                            "icon": "restaurant",
                                            "accent": String(settledColors.colTertiary),
                                            "count": (root.nexus?.collections?.recipes ?? []).length,
                                            "subtitle": "Macros · Ingredients · Steps"
                                        },
                                        {
                                            "id": "exercises",
                                            "title": "Gym & Calisthenics",
                                            "icon": "fitness_center",
                                            "accent": root.mixColorHex(settledColors.colTertiary, settledColors.colSecondary, 0.50),
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
                                            "accent": String(settledColors.colPrimary),
                                            "count": (root.nexus?.collections?.websites ?? []).length,
                                            "subtitle": ".onion directory · Categories"
                                        },
                                        {
                                            "id": "cornell",
                                            "title": "Cornell Study Notes",
                                            "icon": "school",
                                            "accent": root.mixColorHex(settledColors.colPrimary, root.ccStop(11), 0.65),
                                            "count": (root.nexus?.collections?.cornell ?? []).length,
                                            "subtitle": "Cues (? ! .) · Marginalia"
                                        },
                                        {
                                            "id": "zettelkasten",
                                            "title": "Zettelkasten Hub",
                                            "icon": "psychology",
                                            "accent": String(settledColors.colSecondary),
                                            "count": (root.nexus?.collections?.zettelkasten ?? []).length,
                                            "subtitle": "Literature · Permanent · MOCs"
                                        },
                                        {
                                            "id": "finance",
                                            "title": "Finance & Ledger",
                                            "icon": "account_balance_wallet",
                                            "accent": String(settledColors.colTertiary),
                                            "count": (root.nexus?.collections?.finance ?? []).length,
                                            "subtitle": "Income · Spending · Reports"
                                        },
                                        {
                                            "id": "clippings",
                                            "title": "Web Clippings",
                                            "icon": "bookmark",
                                            "accent": root.mixColorHex(settledColors.colSecondary, root.ccStop(11), 0.55),
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
                                                color: root.mixColorHex(modelData.accent, settledColors.colLayer1, 0.16)
                                                border.width: 1
                                                border.color: Qt.alpha(Qt.color(modelData.accent), 0.65)

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
                    Loader {
                        id: fullGraphLoader
                        objectName: "nexusFullGraphLoader"
                        anchors.fill: parent
                        anchors.margins: 14
                        asynchronous: status !== Loader.Ready && Quickshell.env("QT_QUICK_BACKEND") !== "software"
                        readonly property bool shouldLoad: (root.nexus?.activeView ?? "homepage") === "graph"
                        visible: shouldLoad
                        active: false
                        function _syncActive(): void {
                            if (shouldLoad && !active)
                                active = true;
                        }
                        Component.onCompleted: _syncActive()
                        onShouldLoadChanged: _syncActive()
                        sourceComponent: Component {
                            Item {
                                objectName: "nexusFullGraphView"
                                anchors.fill: parent

                                NexusGraphCanvas {
                                    id: fullGraphCanvas
                                    objectName: "nexusFullGraphCanvas"
                                    anchors.fill: parent
                                    workspace: root
                                    isLocal: false
                                    compact: false
                                    allow3D: true
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
                                    onNodeActivated: nodeData => root.activateGraphNode(nodeData)
                                }
                            }
                        }
                    }

                    // ───────────────────────────────────────────────────────
                    // VIEW 2B: COLLECTION / BASES BROWSER VIEW (Movies, TV Series, Games, Books, Recipes, Exercises, Places, Contacts, Onion Sites, Cornell, Zettelkasten, Finance, Clippings)
                    // ───────────────────────────────────────────────────────
                    Loader {
                        id: collectionViewLoader
                        objectName: "nexusCollectionViewLoader"
                        anchors.fill: parent
                        anchors.margins: 16
                        asynchronous: status !== Loader.Ready && Quickshell.env("QT_QUICK_BACKEND") !== "software"
                        readonly property bool shouldLoad: (root.nexus?.activeView ?? "homepage") === "collection"
                        visible: shouldLoad
                        function _syncSource(): void {
                            if (shouldLoad && source.toString().length === 0)
                                setSource(Qt.resolvedUrl("NexusCollectionsView.qml"), { workspace: root });
                        }
                        Component.onCompleted: _syncSource()
                        onShouldLoadChanged: _syncSource()
                    }

                    // ───────────────────────────────────────────────────────
                    // VIEW 3: DOCUMENT VIEW (Markdown Outliner / Vim / Code / Image)
                    // ───────────────────────────────────────────────────────
                    Loader {
                        id: documentViewLoader
                        objectName: "nexusDocumentViewLoader"
                        anchors.fill: parent
                        anchors.margins: 16
                        asynchronous: status !== Loader.Ready && Quickshell.env("QT_QUICK_BACKEND") !== "software"
                        readonly property bool shouldLoad: (root.nexus?.activeView ?? "homepage") === "document" && Boolean(root.nexus?.currentDoc)
                        visible: shouldLoad
                        function _syncSource(): void {
                            if (shouldLoad && source.toString().length === 0)
                                setSource(Qt.resolvedUrl("NexusDocumentView.qml"), { workspace: root });
                        }
                        Component.onCompleted: _syncSource()
                        onShouldLoadChanged: _syncSource()
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
                                    if (root._docVimEditor && text.length > 0) {
                                        const idx = root._docVimEditor.text.toLowerCase().indexOf(text.toLowerCase());
                                        if (idx !== -1)
                                            root._docVimEditor.cursorPosition = idx;
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

            // Top Right Card: Mini Calendar & Daily Journal (100% Obsidian Calendar Plugin Parity + Full Alis Auto-Theming)
            Rectangle {
                id: nexusCalendarCard
                objectName: "nexusCalendarCard"
                anchors.fill: parent
                radius: Appearance.rounding.normal ?? 12
                color: settledColors.colLayer1
                border.width: 1
                border.color: settledColors.colLayer0Border
                clip: true

                HoverHandler {
                    id: calendarCardHover
                }

                WheelHandler {
                    onWheel: event => {
                        if (!root.nexus)
                            return;
                        if (event.angleDelta.y > 0)
                            root.nexus.prevCalendarMonth();
                        else if (event.angleDelta.y < 0)
                            root.nexus.nextCalendarMonth();
                    }
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
                readonly property string activeDailyDateIso: {
                    if ((root.nexus?.activeView ?? "") !== "document")
                        return "";
                    const cur = String(root.nexus?.currentPath ?? "");
                    if (cur.length === 0)
                        return "";
                    // Match YYYY-MM-DD anywhere in filename stem (e.g. 2026-11-13.md)
                    const iso = cur.match(/(\d{4})-(\d{2})-(\d{2})(?:[^/]*)\.md$/i);
                    if (iso)
                        return iso[1] + "-" + iso[2] + "-" + iso[3];
                    // Match DD-MM-YYYY-DayName.md (Obsidian daily note format, e.g. 13-11-2026-Friday.md)
                    const dmy = cur.match(/(?:^|\/)(\d{2})-(\d{2})-(\d{4})(?:[^/]*)\.md$/i);
                    if (dmy)
                        return dmy[3] + "-" + dmy[2] + "-" + dmy[1];
                    return "";
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 5

                    // Calendar Header: Month (text-normal) + Year (colPrimary) + < TODAY >
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
                                color: todayCalMouse.containsMouse ? settledColors.colPrimary : settledColors.colSubtext
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
                    }

                    // Weekday Names Row (optional W column + MON..SUN)
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        StyledText {
                            visible: root.showCalendarWeekNumbers
                            Layout.preferredWidth: 20
                            horizontalAlignment: Text.AlignHCenter
                            text: "W"
                            font.pixelSize: 9
                            font.weight: Font.Bold
                            color: Qt.alpha(settledColors.colSubtext, 0.72)
                        }

                        GridLayout {
                            Layout.fillWidth: true
                            columns: 7
                            columnSpacing: 2

                            Repeater {
                                model: (root.nexus?.calendarWeekStart ?? "monday") === "sunday"
                                    ? ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]
                                    : ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]
                                delegate: StyledText {
                                    required property string modelData
                                    required property int index
                                    readonly property bool isWeekend: (root.nexus?.calendarWeekStart ?? "monday") === "sunday"
                                        ? (index === 0 || index === 6)
                                        : (index >= 5)
                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignHCenter
                                    text: modelData
                                    font.pixelSize: 9
                                    font.weight: Font.Bold
                                    font.letterSpacing: 0.5
                                    color: isWeekend ? Qt.alpha(settledColors.colPrimary, 0.78) : settledColors.colSubtext
                                }
                            }
                        }
                    }

                    // 42-cell Calendar Day Grid — 100% Obsidian Calendar Plugin Parity:
                    // - Indicator Type 1: 1..5 filled word-count dots (`•`)
                    // - Indicator Type 2: hollow open-task circle (`○`)
                    // - 100% Alis auto-themed borders, active daily note highlight, hover tooltip & right-click menu
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.minimumHeight: 132
                        spacing: 2

                        // Optional ISO Week Numbers Column
                        ColumnLayout {
                            visible: root.showCalendarWeekNumbers
                            Layout.preferredWidth: 20
                            Layout.fillHeight: true
                            spacing: 2

                            Repeater {
                                model: 6
                                delegate: Item {
                                    required property int index
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    readonly property var weekCell: {
                                        const arr = root.nexus?.calendarCells ?? [];
                                        const idx = index * 7;
                                        return idx < arr.length ? arr[idx] : null;
                                    }
                                    StyledText {
                                        anchors.centerIn: parent
                                        text: weekCell && Number(weekCell.weekNumber ?? 0) > 0
                                            ? String(weekCell.weekNumber)
                                            : ""
                                        font.family: Appearance.font.family.monospace
                                        font.pixelSize: 9
                                        color: Qt.alpha(settledColors.colSubtext, 0.65)
                                    }
                                }
                            }
                        }

                        GridLayout {
                            id: calendarGrid
                            objectName: "nexusCalendarGrid"
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            columns: 7
                            columnSpacing: 2
                            rowSpacing: 2

                            Repeater {
                                model: root.nexus?.calendarCells ?? []
                                delegate: Rectangle {
                                    id: calDayCell
                                    required property var modelData
                                    readonly property bool isToday: Boolean(modelData.isToday)
                                    readonly property bool isActiveDoc: (root.nexus?.activeView === "document") && (
                                        (String(modelData.journalPath ?? "").length > 0 && String(modelData.journalPath ?? "") === String(root.nexus?.currentPath ?? ""))
                                        || (nexusCalendarCard.activeDailyDateIso.length > 0 && nexusCalendarCard.activeDailyDateIso === String(modelData.dateStr ?? ""))
                                    )
                                    readonly property bool isSelected: (root.nexus?.selectedDateStr ?? "") === String(modelData.dateStr ?? "")
                                    readonly property int solidDotCount: {
                                        const raw = Number(modelData.solidDots ?? -1);
                                        if (raw >= 0)
                                            return Math.min(5, raw);
                                        return Boolean(modelData.hasJournal) ? 1 : 0;
                                    }
                                    readonly property bool hasOpenTasks: Boolean(modelData.hasOpenTasks) || Number(modelData.openTasks ?? 0) > 0
                                    implicitWidth: 28
                                    implicitHeight: 22
                                    Layout.minimumWidth: 20
                                    Layout.minimumHeight: 18
                                    Layout.preferredHeight: Math.max(18, Math.floor((calendarGrid.height - 10) / 6))
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    radius: 6
                                    color: {
                                        if (isActiveDoc)
                                            return settledColors.colSecondaryContainer;
                                        if (isToday)
                                            return Qt.alpha(settledColors.colPrimary, 0.14);
                                        if (isSelected)
                                            return Qt.alpha(settledColors.colPrimary, 0.12);
                                        if (dayCellMouse.containsMouse)
                                            return settledColors.colLayer2Hover;
                                        return "transparent";
                                    }
                                    border.width: (isToday || isSelected || isActiveDoc || dayCellMouse.containsMouse) ? 1 : 0
                                    border.color: {
                                        if (isToday)
                                            return settledColors.colPrimary;
                                        if (isActiveDoc)
                                            return Qt.alpha(settledColors.colPrimary, 0.78);
                                        if (isSelected)
                                            return Qt.alpha(settledColors.colPrimary, 0.52);
                                        if (dayCellMouse.containsMouse)
                                            return settledColors.colLayer0Border;
                                        return "transparent";
                                    }
                                    opacity: modelData.inMonth ? 1.0 : 0.30

                                    ColumnLayout {
                                        anchors.centerIn: parent
                                        spacing: 1

                                        StyledText {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: String(calDayCell.modelData.day ?? "")
                                            font.pixelSize: 11
                                            font.weight: (calDayCell.isToday || calDayCell.isActiveDoc || calDayCell.modelData.hasJournal || calDayCell.isSelected) ? Font.DemiBold : Font.Normal
                                            color: calDayCell.isToday
                                                ? settledColors.colPrimary
                                                : (calDayCell.isActiveDoc ? settledColors.colOnSecondaryContainer : settledColors.colOnLayer1)
                                        }

                                        // Dual Obsidian Calendar Plugin Indicators:
                                        // 1) Filled dots (`•`, 1..5 proportional to word count)
                                        // 2) Hollow circle (`○`) when the daily note has open/incomplete tasks
                                        Row {
                                            objectName: "nexusCalendarDualIndicators"
                                            Layout.alignment: Qt.AlignHCenter
                                            spacing: 2
                                            height: 5

                                            Repeater {
                                                model: calDayCell.solidDotCount
                                                delegate: Rectangle {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: 3.5
                                                    height: 3.5
                                                    radius: 2
                                                    color: calDayCell.isActiveDoc ? settledColors.colOnSecondaryContainer : settledColors.colPrimary
                                                }
                                            }

                                            Rectangle {
                                                objectName: "nexusCalendarHollowTaskDot"
                                                visible: calDayCell.hasOpenTasks
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: 4.5
                                                height: 4.5
                                                radius: 2.25
                                                color: "transparent"
                                                border.width: 1.15
                                                border.color: calDayCell.isActiveDoc
                                                    ? settledColors.colOnSecondaryContainer
                                                    : settledColors.colTertiary
                                            }
                                        }
                                    }

                                    ToolTip.visible: dayCellMouse.containsMouse && (calDayCell.solidDotCount > 0 || calDayCell.hasOpenTasks)
                                    ToolTip.delay: 260
                                    ToolTip.text: {
                                        const parts = [String(calDayCell.modelData.dateStr ?? "")];
                                        const wc = Number(calDayCell.modelData.wordCount ?? 0);
                                        if (wc > 0)
                                            parts.push(String(wc) + " words");
                                        else if (calDayCell.modelData.hasJournal)
                                            parts.push("Daily note");
                                        const openT = Number(calDayCell.modelData.openTasks ?? 0);
                                        const doneT = Number(calDayCell.modelData.doneTasks ?? 0);
                                        if (openT > 0 || doneT > 0)
                                            parts.push(String(openT) + " open / " + String(doneT) + " done tasks");
                                        return parts.join(" · ");
                                    }

                                    MouseArea {
                                        id: dayCellMouse
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
                                                    "type": "calendarDay",
                                                    "title": String(calDayCell.modelData.dateStr ?? ""),
                                                    "dateStr": String(calDayCell.modelData.dateStr ?? ""),
                                                    "hasJournal": Boolean(calDayCell.modelData.hasJournal)
                                                });
                                                return;
                                            }
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

                // Obsidian-style top-edge hover slide-down icon tab bar
                WorkspaceHoverTabBar {
                    tabBarObjectName: "nexusCalendarHoverTabBar"
                    tabs: [
                        {
                            "id": "calendar",
                            "icon": "calendar_month",
                            "label": "Calendar",
                            "active": true
                        }
                    ]
                    actions: [
                        {
                            "icon": "view_week",
                            "tip": "Toggle ISO Week Numbers",
                            "active": root.showCalendarWeekNumbers,
                            "onClick": () => {
                                root.calendarShowWeekNumbersOverride = !root.showCalendarWeekNumbers;
                                root.calendarWeekNumbersUserToggled = true;
                            }
                        },
                        {
                            "icon": "today",
                            "tip": "Jump to Today",
                            "active": false,
                            "onClick": () => {
                                if (root.nexus) {
                                    root.nexus.jumpCalendarToday();
                                    root.nexus.openDailyNote();
                                }
                            }
                        }
                    ]
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
                    if ((graphData?.nodes?.length ?? 0) > 0 && !_graphSettledOnce)
                        Qt.callLater(() => {
                            if (nexusVaultGraphCard && !nexusVaultGraphCard._graphSettledOnce)
                                nexusVaultGraphCard._graphSettledOnce = true;
                        });
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
                    onNodeActivated: nodeData => root.activateGraphNode(nodeData)
                }

                // Obsidian-style top-edge hover slide-down icon tab bar
                WorkspaceHoverTabBar {
                    tabBarObjectName: "nexusVaultGraphHoverTabBar"
                    tabs: [
                        {
                            "id": "vaultGraph",
                            "icon": "scatter_plot",
                            "label": "Vault Graph",
                            "active": true
                        }
                    ]
                    actions: [
                        {
                            "icon": "center_focus_strong",
                            "tip": "Reset View",
                            "active": false,
                            "onClick": () => vaultGraphCanvas.resetView()
                        },
                        {
                            "icon": "open_in_full",
                            "tip": "Open Full 2D/3D Graph",
                            "active": false,
                            "onClick": () => {
                                if (root.nexus)
                                    root.nexus.openGraphView();
                            }
                        }
                    ]
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

                // Obsidian-style top-edge hover slide-down icon tab bar for Planner / Outline / ZK
                WorkspaceHoverTabBar {
                    tabBarObjectName: "nexusContextHoverTabBar"
                    tabs: [
                        {
                            "id": "schedule",
                            "icon": "calendar_view_week",
                            "label": "",
                            "active": (root.nexus?.rightBottomTab ?? "schedule") === "schedule"
                        },
                        {
                            "id": "outline",
                            "icon": "format_list_bulleted",
                            "label": "",
                            "active": (root.nexus?.rightBottomTab ?? "schedule") === "outline"
                        },
                        {
                            "id": "flashcards",
                            "icon": "style",
                            "label": "",
                            "active": (root.nexus?.rightBottomTab ?? "schedule") === "flashcards"
                        }
                    ]
                    onTabSelected: tabId => {
                        if (root.nexus)
                            root.nexus.rightBottomTab = tabId;
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
    NexusCommandPaletteModal {
        id: commandPaletteOverlay
        workspace: root
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
        visible: root.contextMenuOpen || root.renameDialogOpen || root.tagDialogOpen
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: {
            root.closeContextMenu();
            if (root.renameDialogOpen)
                root.renameDialogOpen = false;
            if (root.tagDialogOpen)
                root.tagDialogOpen = false;
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

    // Tag Wrangler+ Modal Dialog (Atomic Vault-Wide Tag Rename / Merge)
    Rectangle {
        id: nexusTagActionDialog
        objectName: "nexusTagActionDialog"
        visible: root.tagDialogOpen
        z: 752
        anchors.centerIn: parent
        width: 400
        implicitHeight: tagActionCol.implicitHeight + 28
        height: implicitHeight
        radius: 10
        color: settledColors.colLayer1
        border.width: 1
        border.color: settledColors.colPrimary

        ColumnLayout {
            id: tagActionCol
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                MaterialSymbol {
                    text: root.tagDialogMode === "merge" ? "merge_type" : "drive_file_rename_outline"
                    iconSize: 18
                    color: settledColors.colPrimary
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.tagDialogMode === "merge" ? "Merge Tag Across Vault" : "Rename Tag Across Vault"
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.Bold
                    color: settledColors.colPrimary
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: (root.tagDialogMode === "merge" ? "Merge #" : "Rename #") + root.tagDialogSourceTag + " into:"
                font.family: Appearance.font.family.monospace
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: settledColors.colSubtext
                elide: Text.ElideMiddle
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 36
                radius: 6
                color: settledColors.colLayer0
                border.width: 1
                border.color: tagActionInput.activeFocus ? settledColors.colPrimary : settledColors.colLayer0Border

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 4
                    StyledText {
                        text: "#"
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.Bold
                        color: settledColors.colPrimary
                    }
                    TextInput {
                        id: tagActionInput
                        objectName: "nexusTagActionInput"
                        Layout.fillWidth: true
                        verticalAlignment: TextInput.AlignVCenter
                        text: root.tagDialogTargetTag
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: settledColors.colOnLayer1
                        selectByMouse: true
                        focus: root.tagDialogOpen
                        onAccepted: {
                            const nextTag = text.trim().replace(/^#+/, "");
                            if (nextTag.length > 0 && nextTag !== root.tagDialogSourceTag && root.nexus) {
                                if (root.tagDialogMode === "merge")
                                    root.nexus.mergeTag(root.tagDialogSourceTag, nextTag, root.tagDialogIncludeSubtags);
                                else
                                    root.nexus.renameTag(root.tagDialogSourceTag, nextTag, root.tagDialogIncludeSubtags);
                            }
                            root.tagDialogOpen = false;
                            root.restoreWorkspaceFocus();
                        }
                        Keys.onEscapePressed: {
                            root.tagDialogOpen = false;
                            root.restoreWorkspaceFocus();
                        }
                    }
                }
            }

            // Existing Tag Quick-Pick Suggestions when Merging
            Flow {
                id: tagMergeSuggestions
                objectName: "nexusTagMergeSuggestions"
                visible: root.tagDialogMode === "merge" && mergeCandidateTags.length > 0
                Layout.fillWidth: true
                spacing: 5
                readonly property var mergeCandidateTags: {
                    if (root.tagDialogMode !== "merge")
                        return [];
                    const srcLow = root.tagDialogSourceTag.toLowerCase();
                    const q = tagActionInput.text.trim().replace(/^#+/, "").toLowerCase();
                    const all = root.nexus?.tags ?? [];
                    const out = [];
                    for (let i = 0; i < all.length && out.length < 8; ++i) {
                        const rawName = String(all[i]?.tag ?? all[i]?.name ?? "").replace(/^#+/, "").trim();
                        if (rawName.length === 0 || rawName.toLowerCase() === srcLow)
                            continue;
                        if (q.length > 0 && rawName.toLowerCase().indexOf(q) === -1)
                            continue;
                        out.push(rawName);
                    }
                    return out;
                }

                Repeater {
                    model: tagMergeSuggestions.mergeCandidateTags
                    delegate: Rectangle {
                        required property string modelData
                        height: 22
                        width: sugTxt.implicitWidth + 12
                        radius: 11
                        color: sugMouse.containsMouse ? settledColors.colSecondaryContainer : settledColors.colLayer2
                        border.width: 1
                        border.color: sugMouse.containsMouse ? settledColors.colPrimary : settledColors.colLayer0Border
                        StyledText {
                            id: sugTxt
                            anchors.centerIn: parent
                            text: "#" + modelData
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: 10
                            color: sugMouse.containsMouse ? settledColors.colPrimary : settledColors.colOnLayer1
                        }
                        MouseArea {
                            id: sugMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                tagActionInput.text = modelData;
                                root.tagDialogTargetTag = modelData;
                            }
                        }
                    }
                }
            }

            // Include nested subtags checkbox
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Rectangle {
                    Layout.preferredWidth: 16
                    Layout.preferredHeight: 16
                    radius: 4
                    color: root.tagDialogIncludeSubtags ? settledColors.colPrimary : settledColors.colLayer0
                    border.width: 1
                    border.color: root.tagDialogIncludeSubtags ? settledColors.colPrimary : settledColors.colLayer0Border
                    MaterialSymbol {
                        visible: root.tagDialogIncludeSubtags
                        anchors.centerIn: parent
                        text: "check"
                        iconSize: 12
                        color: settledColors.colOnPrimary
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.tagDialogIncludeSubtags = !root.tagDialogIncludeSubtags
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    text: "Include nested subtags (#" + root.tagDialogSourceTag + "/...)"
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: settledColors.colOnLayer1
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Item { Layout.fillWidth: true }
                Rectangle {
                    implicitWidth: 80
                    implicitHeight: 30
                    radius: 6
                    color: cancelTagBtnMouse.containsMouse ? settledColors.colLayer2Hover : settledColors.colLayer2
                    StyledText {
                        anchors.centerIn: parent
                        text: "Cancel"
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: settledColors.colSubtext
                    }
                    MouseArea {
                        id: cancelTagBtnMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.tagDialogOpen = false;
                            root.restoreWorkspaceFocus();
                        }
                    }
                }
                Rectangle {
                    implicitWidth: 92
                    implicitHeight: 30
                    radius: 6
                    color: applyTagBtnMouse.containsMouse ? settledColors.colPrimary : settledColors.colSecondaryContainer
                    StyledText {
                        anchors.centerIn: parent
                        text: root.tagDialogMode === "merge" ? "Merge Tag" : "Rename Tag"
                        font.weight: Font.DemiBold
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: applyTagBtnMouse.containsMouse ? settledColors.colOnPrimary : settledColors.colOnSecondaryContainer
                    }
                    MouseArea {
                        id: applyTagBtnMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: tagActionInput.accepted()
                    }
                }
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INTERACTIVE NEW NOTE & EXTERNAL API SEARCH MODAL (`A2`)
    // ═══════════════════════════════════════════════════════════════════════
    Loader {
        id: newNoteModalLoader
        objectName: "nexusNewNoteModalLoader"
        anchors.fill: parent
        z: 760
        asynchronous: status !== Loader.Ready && Quickshell.env("QT_QUICK_BACKEND") !== "software"
        readonly property bool shouldLoad: Boolean(root.nexus?.newNoteModalOpen ?? false)
        visible: shouldLoad
        function _syncSource(): void {
            if (shouldLoad && source.toString().length === 0)
                setSource(Qt.resolvedUrl("NexusNewNoteModal.qml"), { workspace: root });
        }
        Component.onCompleted: _syncSource()
        onShouldLoadChanged: _syncSource()
    }
}
