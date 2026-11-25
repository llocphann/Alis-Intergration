import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.services as HostServices

Item {
    id: root
    property bool _live: true
    Component.onDestruction: {
        root._live = false;
        serveWatchdog.stop();
        plannerRangeTimer.stop();
        root._servePending = ({});
        root._serveSendQueue = [];
        const procs = [serveProc, scanProc, docProc, calendarProc, searchProc, apiSearchProc,
            secondaryDocProc, previewProc, queryProc, historyProc, assetProc, pdfProc, conflictCheckProc, preWriteProbeProc,
            plannerRangeProc, plannerTaskToggleProc];
        for (const p of procs) {
            if (p && p.running) {
                try { p.signal(15); } catch (_e) { p.running = false; }
            }
        }
    }

    readonly property string binaryPath: decodeURIComponent(String(Qt.resolvedUrl("../assets/bin/alis-nexus")).replace(/^(?:file:\/\/|qs:)/, ""))
    readonly property string pdfHelperPath: decodeURIComponent(String(Qt.resolvedUrl("../scripts/notes/pdf_helper.py")).replace(/^(?:file:\/\/|qs:)/, ""))
    readonly property string assetHelperPath: decodeURIComponent(String(Qt.resolvedUrl("../scripts/notes/asset_helper.py")).replace(/^(?:file:\/\/|qs:)/, ""))
    readonly property string historyHelperPath: decodeURIComponent(String(Qt.resolvedUrl("../scripts/notes/history_helper.py")).replace(/^(?:file:\/\/|qs:)/, ""))
    readonly property string _dailyTodoHelperPath: decodeURIComponent(String(Qt.resolvedUrl("../scripts/todo/nexus_daily_todo.py")).replace(/^(?:file:\/\/|qs:)/, ""))
    readonly property string configuredVaultPath: {
        void Config.ready;
        void Config.revision;
        const shared = String(HostServices.Todo.sharedVaultPath ?? "").trim();
        if (shared.length > 0)
            return root._expandHome(shared);
        const nx = String(Config.options?.todo?.nexus?.vaultPath ?? "").trim();
        if (nx.length > 0)
            return root._expandHome(nx);
        const obs = String(Config.options?.todo?.obsidian?.vaultPath ?? "").trim();
        if (obs.length > 0)
            return root._expandHome(obs);
        const zk = String(Config.options?.notes?.zettelkasten?.vaultPath ?? "").trim();
        if (zk.length > 0)
            return root._expandHome(zk);
        const cfgDir = String(Config.options?.integrations?.nexus?.configPath ?? "").trim().replace(/\/+\.(obsidian|nexus)\/?$/, "");
        return root._expandHome(cfgDir);
    }
    readonly property bool vaultConfigured: configuredVaultPath.length > 0
    readonly property string dailyFolder: {
        void Config.ready;
        void Config.revision;
        const dn = String(Config.options?.todo?.nexus?.dailyNote?.folder ?? "").trim();
        if (dn.length > 0)
            return dn;
        const legacy = String(Config.options?.todo?.nexus?.daily?.folder ?? "").trim();
        return legacy.length > 0 ? legacy : "00_Capture/01_Journal";
    }
    readonly property string dailyFormat: {
        void Config.ready;
        void Config.revision;
        const dn = String(Config.options?.todo?.nexus?.dailyNote?.format ?? "").trim();
        if (dn.length > 0)
            return dn;
        const legacy = String(Config.options?.todo?.nexus?.daily?.format ?? "").trim();
        return legacy.length > 0 ? legacy : "YYYY/MMMM/DD-MM-YYYY-dddd";
    }

    // Workspace & presentation state
    property bool isOpen: false
    property bool overlayMode: true
    property bool _restoreOverlayAfterWindowClose: false
    property string activeView: "homepage" // "homepage" | "document" | "graph" | "collection" | "canvas" | "database"
    property var openTabs: [] // [{ relPath, title, category, pinned }]
    property string secondaryPath: ""
    property var secondaryDoc: null
    property bool splitPaneOpen: false
    property int scrollToLineRequest: -1
    property int scrollToLineSerial: 0
    property var docUndoStack: ({}) // relPath -> [{ content, ts }]
    property var docRedoStack: ({}) // relPath -> [{ content, ts }]
    property bool findBarOpen: false
    property bool findBarReplaceMode: false
    property bool propertiesPanelExpanded: false
    property int localGraphDepth: 1
    property var savedGraphPresets: []
    property var supertagSchemas: ({})
    property var savedDatabaseViews: []
    property string databasePath: ""
    property var queryResults: ({ "ok": false, "total": 0, "rows": [], "schemaKeys": [], "groups": [], "aggregations": ({}) })
    property bool queryLoading: false
    property var hoverPreviewCache: ({})
    property var _hoverPreviewOrder: []
    property var hoverPreviewData: null
    property bool hoverPreviewLoading: false
    property string _pendingPreviewTarget: ""
    property bool historyModalOpen: false
    property var historyRevisions: []
    property string historySelectedRevId: ""
    property string historyDiffText: ""
    property bool historyLoading: false
    property var pdfInfo: null
    property int pdfCurrentPage: 1
    property int pdfDpi: 150
    property string pdfPageImageUrl: ""
    property string pdfExtractedText: ""
    property bool pdfBusy: false
    property string pdfLastTarget: ""
    property string activeCollection: "movies" // "movies" | "tvseries" | "games" | "websites" | "cornell" | "zettelkasten" | "places"
    property string collectionFilterQuery: ""
    property string editorMode: "hybrid" // "hybrid" | "raw" | "split"
    property bool leftSidebarOpen: true
    property bool rightSidebarOpen: true
    property string leftSidebarTab: "files" // "files" | "tags" | "recent" | "search"
    property string rightBottomTab: "schedule" // "schedule" | "outline" | "flashcards"
    property string activeTagFilter: ""
    property string tagSearchQuery: ""
    property string tagSortMode: "countDesc" // "countDesc" | "countAsc" | "nameAsc" | "nameDesc"
    property bool calendarShowWeeklyNote: false
    property int calendarWordsPerDot: 250
    property string calendarWeekStart: "monday"
    property string fileFilterQuery: ""
    property bool commandPaletteOpen: false
    property string commandPaletteMode: "commands" // "commands" | "files" | "quickNote" | "quickTask"
    property string commandPaletteSearch: ""
    property bool newNoteModalOpen: false
    property string newNoteModalKind: "standard"
    property string newNoteModalFolder: ""
    property var searchApiResults: []
    property bool searchApiLoading: false
    property int _searchApiGeneration: 0
    property var _pendingApiSearch: null
    property bool layoutEditMode: false

    // Customizable & persistent layout state (persisted to state/user/nexus_workspace.json)
    property string workspaceStatePath: `${Directories.state}/user/nexus_workspace.json`
    property int leftSidebarWidth: 268
    property int rightSidebarWidth: 288
    property real leftSplitRatio: 0.62
    property real rightTopRatio: 0.34
    property real rightMidRatio: 0.32
    property int homepageHeroHeight: 270
    property int homepageScheduleHeight: 216
    readonly property var defaultCardOrder: ["explorer", "localGraph", "calendar", "vaultGraph", "context"]
    property var cardOrder: ["explorer", "localGraph", "calendar", "vaultGraph", "context"]
    property var userShortcuts: ({})
    property bool _workspacePrefsLoaded: false

    function _saveWorkspacePrefs(): void {
        if (!root._workspacePrefsLoaded)
            return;
        try {
            const payload = JSON.stringify({
                "version": 3,
                "layout": {
                    "leftSidebarWidth": root.leftSidebarWidth,
                    "rightSidebarWidth": root.rightSidebarWidth,
                    "leftSplitRatio": root.leftSplitRatio,
                    "rightTopRatio": root.rightTopRatio,
                    "rightMidRatio": root.rightMidRatio,
                    "homepageHeroHeight": root.homepageHeroHeight,
                    "homepageScheduleHeight": root.homepageScheduleHeight,
                    "cardOrder": root.cardOrder
                },
                "shortcuts": root.userShortcuts ?? ({}),
                "workspaceExtras": {
                    "openTabs": root.openTabs ?? [],
                    "localGraphDepth": root.localGraphDepth,
                    "savedGraphPresets": root.savedGraphPresets ?? [],
                    "supertagSchemas": root.supertagSchemas ?? ({}),
                    "savedDatabaseViews": root.savedDatabaseViews ?? []
                }
            }, null, 2);
            workspacePrefsFileView.setText(payload);
        } catch (e) {}
    }

    function setLeftSidebarWidth(w: real): void {
        root.leftSidebarWidth = Math.round(Math.max(160, Math.min(540, w)));
        root._saveWorkspacePrefs();
    }
    function setRightSidebarWidth(w: real): void {
        root.rightSidebarWidth = Math.round(Math.max(180, Math.min(540, w)));
        root._saveWorkspacePrefs();
    }
    function setLeftSplitRatio(r: real): void {
        root.leftSplitRatio = Math.round(Math.max(0.18, Math.min(0.84, r)) * 1000) / 1000;
        root._saveWorkspacePrefs();
    }
    function setRightTopRatio(r: real): void {
        root.rightTopRatio = Math.round(Math.max(0.16, Math.min(0.65, r)) * 1000) / 1000;
        root._saveWorkspacePrefs();
    }
    function setRightMidRatio(r: real): void {
        root.rightMidRatio = Math.round(Math.max(0.15, Math.min(0.62, r)) * 1000) / 1000;
        root._saveWorkspacePrefs();
    }
    function setHomepageHeroHeight(h: real): void {
        root.homepageHeroHeight = Math.round(Math.max(170, Math.min(440, h)));
        root._saveWorkspacePrefs();
    }
    function setHomepageScheduleHeight(h: real): void {
        root.homepageScheduleHeight = Math.round(Math.max(130, Math.min(440, h)));
        root._saveWorkspacePrefs();
    }
    function swapCards(cardA: string, cardB: string): bool {
        if (!cardA || !cardB || cardA === cardB)
            return false;
        const order = root.cardOrder.slice();
        const idxA = order.indexOf(cardA);
        const idxB = order.indexOf(cardB);
        if (idxA === -1 || idxB === -1)
            return false;
        order[idxA] = cardB;
        order[idxB] = cardA;
        root.cardOrder = order;
        root._saveWorkspacePrefs();
        root.vimStatusMessage = "Swapped cards: " + cardA + " ↔ " + cardB;
        return true;
    }
    function moveCardStep(cardId: string, delta: int): bool {
        const order = root.cardOrder.slice();
        const idx = order.indexOf(cardId);
        if (idx === -1)
            return false;
        const targetIdx = (idx + delta + order.length) % order.length;
        return root.swapCards(cardId, order[targetIdx]);
    }
    function resetLayout(): void {
        root.leftSidebarWidth = 268;
        root.rightSidebarWidth = 288;
        root.leftSplitRatio = 0.62;
        root.rightTopRatio = 0.34;
        root.rightMidRatio = 0.32;
        root.homepageHeroHeight = 270;
        root.homepageScheduleHeight = 216;
        root.cardOrder = ["explorer", "localGraph", "calendar", "vaultGraph", "context"];
        root.leftSidebarOpen = true;
        root.rightSidebarOpen = true;
        root._saveWorkspacePrefs();
        root.vimStatusMessage = "Reset workspace layout to defaults";
    }

    // Obsidian-Vault adapted shortcut definitions & custom overrides
    property var vaultHotkeys: ({})
    readonly property var shortcutCatalog: [
        { "id": "commandPalette", "obsidianId": "command-palette:open", "obsidianCommand": "command-palette:open", "title": "Command Palette", "category": "Navigation", "defaultKey": "Alt+Enter", "description": "Open interactive command palette" },
        { "id": "quickSwitcher", "obsidianId": "omnisearch:show-modal", "obsidianCommand": "omnisearch:show-modal", "title": "Quick Switcher / Search", "category": "Navigation", "defaultKey": "Alt+Escape", "description": "Jump to any note or search vault" },
        { "id": "cycleView", "obsidianId": "workspace:next-tab", "obsidianCommand": "workspace:next-tab", "title": "Cycle Active View", "category": "Navigation", "defaultKey": "Alt+Space", "description": "Cycle Homepage → Outliner → Graph" },
        { "id": "gotoTab1", "obsidianId": "workspace:goto-tab-1", "obsidianCommand": "workspace:goto-tab-1", "title": "Go to Homepage", "category": "Navigation", "defaultKey": "Alt+1", "description": "Switch center pane to Homepage dashboard" },
        { "id": "gotoTab2", "obsidianId": "workspace:goto-tab-2", "obsidianCommand": "workspace:goto-tab-2", "title": "Go to Note Outliner", "category": "Navigation", "defaultKey": "Alt+2", "description": "Switch center pane to active document" },
        { "id": "gotoTab3", "obsidianId": "workspace:goto-tab-3", "obsidianCommand": "workspace:goto-tab-3", "title": "Go to Vault Graph", "category": "Navigation", "defaultKey": "Alt+3", "description": "Switch center pane to interactive Vault Graph" },
        { "id": "gotoTab4", "obsidianId": "workspace:goto-tab-4", "obsidianCommand": "workspace:goto-tab-4", "title": "Open Today's Journal", "category": "Navigation", "defaultKey": "Alt+4", "description": "Open or create today's daily journal note" },
        { "id": "gotoTab5", "obsidianId": "workspace:goto-tab-5", "obsidianCommand": "workspace:goto-tab-5", "title": "Open Recent Note #1", "category": "Navigation", "defaultKey": "Alt+5", "description": "Jump to the first recent note" },
        { "id": "gotoTab6", "obsidianId": "workspace:goto-tab-6", "obsidianCommand": "workspace:goto-tab-6", "title": "Open Recent Note #2", "category": "Navigation", "defaultKey": "Alt+6", "description": "Jump to the second recent note" },
        { "id": "gotoTab7", "obsidianId": "workspace:goto-tab-7", "obsidianCommand": "workspace:goto-tab-7", "title": "Open Recent Note #3", "category": "Navigation", "defaultKey": "Alt+7", "description": "Jump to the third recent note" },
        { "id": "gotoTab8", "obsidianId": "workspace:goto-tab-8", "obsidianCommand": "workspace:goto-tab-8", "title": "Open Recent Note #4", "category": "Navigation", "defaultKey": "Alt+8", "description": "Jump to the fourth recent note" },
        { "id": "navigateBack", "obsidianId": "app:go-back", "obsidianCommand": "app:go-back", "title": "Navigate Back", "category": "Navigation", "defaultKey": "Alt+H", "description": "Go back in note history (also Ctrl+Alt+Left)" },
        { "id": "navigateForward", "obsidianId": "app:go-forward", "obsidianCommand": "app:go-forward", "title": "Navigate Forward", "category": "Navigation", "defaultKey": "Alt+L", "description": "Go forward in note history (also Ctrl+Alt+Right)" },
        { "id": "toggleLeftSidebar", "obsidianId": "app:toggle-left-sidebar", "obsidianCommand": "app:toggle-left-sidebar", "title": "Toggle Left Sidebar", "category": "Workspace", "defaultKey": "Alt+Q", "description": "Show or hide the left Explorer & Local Graph column" },
        { "id": "toggleRightSidebar", "obsidianId": "app:toggle-right-sidebar", "obsidianCommand": "app:toggle-right-sidebar", "title": "Toggle Right Sidebar", "category": "Workspace", "defaultKey": "Alt+E", "description": "Show or hide the right Calendar, Graph & Context column" },
        { "id": "toggleWindowMode", "obsidianId": "workspaces:save-and-load", "obsidianCommand": "workspaces:save-and-load", "title": "Toggle Overlay / Window Mode", "category": "Workspace", "defaultKey": "Alt+P", "description": "Switch between bottom Screen Edge overlay and floating window" },
        { "id": "resetWorkspaceLayout", "obsidianId": "workspaces:open-modal", "obsidianCommand": "workspaces:open-modal", "title": "Reset Workspace Layout", "category": "Workspace", "defaultKey": "Alt+Shift+P", "description": "Reset sidebar widths and card positions to defaults" },
        { "id": "closeNexus", "obsidianId": "workspace:close", "obsidianCommand": "workspace:close", "title": "Close Note / Close Nexus", "category": "Workspace", "defaultKey": "Alt+W", "description": "Return to Homepage from note, or close Nexus" },
        { "id": "openSettings", "obsidianId": "app:open-settings", "obsidianCommand": "app:open-settings", "title": "Open Nexus Settings", "category": "Workspace", "defaultKey": "Alt+,", "description": "Open Alis Settings on the Nexus & Shortcuts page" },
        { "id": "newNote", "obsidianId": "workspace:new-tab", "obsidianCommand": "workspace:new-tab", "title": "Create New Note", "category": "Notes", "defaultKey": "Ctrl+T", "description": "Create a new Markdown note (also Alt+Shift+N)" },
        { "id": "newZettelkasten", "obsidianId": "zk-prefixer", "obsidianCommand": "zk-prefixer", "title": "New Zettelkasten Note", "category": "Notes", "defaultKey": "Ctrl+N", "description": "Create a timestamped Zettelkasten note" },
        { "id": "quickAddTask", "obsidianId": "quickadd:choice:e26ead52-86bc-4f2e-a0e4-d144cb7f3c4b", "obsidianCommand": "quickadd:choice:e26ead52-86bc-4f2e-a0e4-d144cb7f3c4b", "title": "Quick Add Task", "category": "Notes", "defaultKey": "Alt+T", "description": "Quickly capture a task to Todo / Daily Note" },
        { "id": "saveNote", "obsidianId": "workspaces:save", "obsidianCommand": "workspaces:save", "title": "Save Current Note", "category": "Notes", "defaultKey": "Alt+S", "description": "Save current document atomically (also Ctrl+S)" },
        { "id": "deleteNote", "obsidianId": "app:delete-file", "obsidianCommand": "app:delete-file", "title": "Move Note to Trash", "category": "Notes", "defaultKey": "Alt+Shift+D", "description": "Move the active note into vault .trash/" },
        { "id": "togglePreviewMode", "obsidianId": "markdown:toggle-preview", "obsidianCommand": "markdown:toggle-preview", "title": "Toggle Outliner / Raw Vim", "category": "Editor", "defaultKey": "Alt+R", "description": "Switch between Hybrid Outliner and Raw Vim editor" },
        { "id": "toggleSourceSplit", "obsidianId": "editor:toggle-source", "obsidianCommand": "editor:toggle-source", "title": "Toggle Split Editor", "category": "Editor", "defaultKey": "Alt+Shift+R", "description": "Toggle side-by-side Outliner + Raw Vim split view" },
        { "id": "searchInNote", "obsidianId": "editor:open-search", "obsidianCommand": "editor:open-search", "title": "Filter Explorer Files", "category": "Search", "defaultKey": "Alt+F", "description": "Focus the file filter in the Explorer card" },
        { "id": "searchInVault", "obsidianId": "cornell-marginalia:cornell-search-explorer", "obsidianCommand": "cornell-marginalia:cornell-search-explorer", "title": "Search Across Vault", "category": "Search", "defaultKey": "Alt+Shift+F", "description": "Open full-text vault search tab" },
        { "id": "heading1", "obsidianId": "editing-toolbar:header1-text", "obsidianCommand": "editing-toolbar:header1-text", "title": "Heading 1", "category": "Formatting", "defaultKey": "Ctrl+1", "description": "Format active block or line as # Heading 1" },
        { "id": "heading2", "obsidianId": "editing-toolbar:header2-text", "obsidianCommand": "editing-toolbar:header2-text", "title": "Heading 2", "category": "Formatting", "defaultKey": "Ctrl+2", "description": "Format active block or line as ## Heading 2" },
        { "id": "heading3", "obsidianId": "editing-toolbar:header3-text", "obsidianCommand": "editing-toolbar:header3-text", "title": "Heading 3", "category": "Formatting", "defaultKey": "Ctrl+3", "description": "Format active block or line as ### Heading 3" },
        { "id": "heading4", "obsidianId": "editing-toolbar:header4-text", "obsidianCommand": "editing-toolbar:header4-text", "title": "Heading 4", "category": "Formatting", "defaultKey": "Ctrl+4", "description": "Format active block or line as #### Heading 4" },
        { "id": "heading5", "obsidianId": "editing-toolbar:header5-text", "obsidianCommand": "editing-toolbar:header5-text", "title": "Heading 5", "category": "Formatting", "defaultKey": "Ctrl+5", "description": "Format active block or line as ##### Heading 5" },
        { "id": "heading6", "obsidianId": "editing-toolbar:header6-text", "obsidianCommand": "editing-toolbar:header6-text", "title": "Heading 6", "category": "Formatting", "defaultKey": "Ctrl+6", "description": "Format active block or line as ###### Heading 6" },
        { "id": "findInNote", "obsidianId": "editor:open-search-note", "obsidianCommand": "editor:open-search-note", "title": "Find in Note", "category": "Editor", "defaultKey": "Ctrl+F", "description": "Open find bar in active document" },
        { "id": "replaceInNote", "obsidianId": "editor:open-search-replace", "obsidianCommand": "editor:open-search-replace", "title": "Find & Replace in Note", "category": "Editor", "defaultKey": "Ctrl+H", "description": "Open find and replace bar in active document" },
        { "id": "undoDocument", "obsidianId": "editor:undo", "obsidianCommand": "editor:undo", "title": "Undo Document Edit", "category": "Editor", "defaultKey": "Ctrl+Z", "description": "Undo recent edit in active note" },
        { "id": "redoDocument", "obsidianId": "editor:redo", "obsidianCommand": "editor:redo", "title": "Redo Document Edit", "category": "Editor", "defaultKey": "Ctrl+Shift+Z", "description": "Redo reverted edit in active note" },
        { "id": "toggleSplitPane", "obsidianId": "workspace:split-vertical", "obsidianCommand": "workspace:split-vertical", "title": "Toggle Split Pane", "category": "Workspace", "defaultKey": "Alt+\\", "description": "Toggle side-by-side secondary note pane" },
        { "id": "openHistory", "obsidianId": "version-history:open", "obsidianCommand": "version-history:open", "title": "Note History & Diffs", "category": "Notes", "defaultKey": "Alt+Shift+H", "description": "Inspect snapshot and Git version history" },
        { "id": "openDatabase", "obsidianId": "bases:open", "obsidianCommand": "bases:open", "title": "Open Vault Database", "category": "Workspace", "defaultKey": "Alt+B", "description": "Open dynamic Table / Kanban / Gallery / Timeline query view" },
        { "id": "openCanvas", "obsidianId": "canvas:new-file", "obsidianCommand": "canvas:new-file", "title": "Open / Create Spatial Canvas", "category": "Notes", "defaultKey": "Alt+Shift+C", "description": "Open infinite spatial canvas whiteboard" }
    ]

    property int _shortcutRevision: 0

    function _resolveActionId(actionId: string): string {
        const aliases = {
            "quick_switcher": "quickSwitcher",
            "command_palette": "commandPalette",
            "quick_add_task": "quickAddTask",
            "new_note": "newZettelkasten",
            "close_nexus": "closeNexus",
            "save_note": "saveNote"
        };
        return aliases[actionId] || actionId;
    }

    function _lookupVaultHotkeyEntry(obsidianId: string): var {
        if (!root.vaultHotkeys || !obsidianId)
            return null;
        if (root.vaultHotkeys[obsidianId])
            return root.vaultHotkeys[obsidianId];
        if (obsidianId.startsWith("quickadd:choice:")) {
            const keys = Object.keys(root.vaultHotkeys);
            for (let i = 0; i < keys.length; ++i) {
                if (keys[i].startsWith("quickadd:choice:"))
                    return root.vaultHotkeys[keys[i]];
            }
        }
        return null;
    }

    function vaultDefaultShortcutFor(actionId: string): string {
        const resolved = root._resolveActionId(actionId);
        for (let i = 0; i < root.shortcutCatalog.length; ++i) {
            const item = root.shortcutCatalog[i];
            if (item.id === resolved) {
                const obsEntry = root._lookupVaultHotkeyEntry(item.obsidianId);
                if (obsEntry && typeof obsEntry.primary === "string" && obsEntry.primary.length > 0)
                    return obsEntry.primary;
                if (typeof obsEntry === "string" && obsEntry.length > 0)
                    return obsEntry;
                return item.defaultKey;
            }
        }
        return "";
    }

    function shortcutFor(actionId: string): string {
        const resolved = root._resolveActionId(actionId);
        const userMap = root.userShortcuts ?? ({});
        if (userMap && typeof userMap[resolved] === "string" && userMap[resolved].trim().length > 0)
            return userMap[resolved].trim();
        return root.vaultDefaultShortcutFor(resolved);
    }

    function setShortcut(actionId: string, keyCombo: string): void {
        const resolved = root._resolveActionId(actionId);
        const cleaned = String(keyCombo ?? "").trim();
        if (!resolved || cleaned.length === 0)
            return;
        const current = Object.assign({}, root.userShortcuts ?? ({}));
        current[resolved] = cleaned;
        root.userShortcuts = current;
        root._shortcutRevision += 1;
        root._saveWorkspacePrefs();
        root.vimStatusMessage = "Shortcut updated: " + resolved + " → " + cleaned;
    }

    function resetShortcut(actionId: string): void {
        const resolved = root._resolveActionId(actionId);
        if (!resolved)
            return;
        const current = Object.assign({}, root.userShortcuts ?? ({}));
        delete current[resolved];
        root.userShortcuts = current;
        root._shortcutRevision += 1;
        root._saveWorkspacePrefs();
    }

    function resetAllShortcuts(): void {
        root.userShortcuts = ({});
        root._shortcutRevision += 1;
        root._saveWorkspacePrefs();
        root.vimStatusMessage = "Reset all shortcuts to Obsidian-Vault defaults";
    }

    function syncShortcutsFromVault(): int {
        const next = Object.assign({}, root.userShortcuts ?? ({}));
        let count = 0;
        for (let i = 0; i < root.shortcutCatalog.length; ++i) {
            const item = root.shortcutCatalog[i];
            const obsEntry = root._lookupVaultHotkeyEntry(item.obsidianId);
            if (obsEntry && typeof obsEntry.primary === "string" && obsEntry.primary.length > 0) {
                next[item.id] = obsEntry.primary;
                count += 1;
            }
        }
        root.userShortcuts = next;
        root._shortcutRevision += 1;
        root._saveWorkspacePrefs();
        root.vimStatusMessage = "Synced " + count + " shortcuts from .obsidian/hotkeys.json";
        return count;
    }

    // Vim engine state
    property bool vimEnabled: true
    property string vimMode: "NORMAL" // "NORMAL" | "INSERT" | "VISUAL" | "VISUAL_LINE" | "COMMAND" | "SEARCH"
    property string vimCommandBuffer: ""
    property string vimKeyBuffer: ""
    property string vimCountBuffer: ""
    property int vimVisualAnchor: -1
    property string vimRegister: ""
    property string vimSearchQuery: ""
    property string vimStatusMessage: "READY"
    property var vimUndoStack: []
    property var vimRedoStack: []

    // Persistent alis-nexus --serve JSON-RPC transport (lazy-started on first hot op)
    property bool _serveDisabled: false
    property int _serveFailures: 0
    property int _serveNextId: 1
    property var _servePending: ({})
    property var _serveSendQueue: []
    property bool _serveStarted: false
    property int _activeDocServeId: 0
    property bool _calendarServeInFlight: false
    property bool _searchServeInFlight: false
    property int _conflictCheckServeId: 0

    // External file modification conflict tracking
    property bool externalConflictDetected: false
    property string externalConflictPath: ""
    property string externalConflictDiskContent: ""
    property string externalConflictDiskSha: ""
    property double externalConflictDiskMtime: 0
    property string _loadedDocPath: ""
    property string _loadedDocSha: ""
    property double _loadedDocMtime: 0

    // Vault scan state
    readonly property alias scanBusy: scanProc.running
    readonly property bool docBusy: docProc.running || preWriteProbeProc.running || root._activeDocServeId > 0
    readonly property bool busy: scanProc.running || root.docBusy || calendarProc.running || root._calendarServeInFlight || searchProc.running || root._searchServeInFlight
    property bool vaultLoaded: false
    property string errorMessage: ""
    property string vaultName: "Vault"
    property var tree: ({
            "name": "Vault",
            "relPath": "",
            "isDir": true,
            "children": []
        })
    property var flatFiles: []
    property var tagsList: []
    property var vaultGraph: ({
            "nodes": [],
            "edges": [],
            "groups": []
        })
    property var homepageLocalGraph: ({
            "nodes": [],
            "edges": []
        })
    property var recentNotes: []
    property var topFolders: []
    property var dailySchedule: ({
            "available": false,
            "weekday": "",
            "relPath": "",
            "sections": [],
            "scheduleRows": [],
            "exerciseRows": [],
            "cardioRows": []
        })
    property var allWeekdaysSchedule: ({})
    property var plannerTasks: []
    property int plannerTasksRevision: 0
    property string _plannerRangeStart: ""
    property string _plannerRangeEnd: ""
    property string _pendingRangeStart: ""
    property string _pendingRangeEnd: ""
    property var financeSummary: ({
            "available": false,
            "totalIncome": 0,
            "totalExpense": 0,
            "netCashflow": 0,
            "accounts": [],
            "subscriptions": [],
            "transactions": [],
            "categories": []
        })
    property string homepageCoverUrl: ""
    property string homepagePhotoUrl: ""
    property string weatherLocation: "Can Tho, VN"
    property var globeSettings: ({})
    property var collections: ({
            "movies": [],
            "tvSeries": [],
            "tvseries": [],
            "games": [],
            "books": [],
            "recipes": [],
            "exercises": [],
            "clippings": [],
            "finance": [],
            "websites": [],
            "cornell": [],
            "zettelkasten": [],
            "places": [],
            "contacts": []
        })
    property var stats: ({
            "userHost": "user@vault",
            "noteCount": 0,
            "journalCount": 0,
            "bookCount": 0,
            "tagCount": 0,
            "openTasks": 0,
            "doneTasks": 0,
            "imageCount": 0,
            "codeCount": 0,
            "externalCount": 0,
            "vaultAgeDays": 0,
            "vaultAgeFormatted": "0 days",
            "activityHeatmap": [],
            "activityHeatmapExtended": []
        })
    property var todayJournalInfo: ({
            "date": "",
            "exists": false,
            "relPath": "",
            "mood": "",
            "energy": "",
            "weight": ""
        })
    property string vaultCachePath: `${Directories.state}/user/nexus_vault_cache.json`
    readonly property string vaultCacheFsPath: decodeURIComponent(String(root.vaultCachePath ?? "").replace(/^file:\/\//, ""))
    property bool _useLegacyVaultCacheFallback: false
    onVaultCachePathChanged: root._useLegacyVaultCacheFallback = false
    property var expandedFolders: ({})
    property var expandedParentTags: ({})

    function toggleTagGroupExpanded(parentTag: string): void {
        const key = String(parentTag ?? "").trim().replace(/^#+/, "");
        if (!key)
            return;
        const next = Object.assign({}, root.expandedParentTags);
        next[key] = !Boolean(next[key]);
        root.expandedParentTags = next;
    }

    function expandAllTagGroups(): void {
        const rawList = Array.isArray(root.tagsList) ? root.tagsList : [];
        const next = {};
        for (let i = 0; i < rawList.length; ++i) {
            const rawName = String(rawList[i]?.name ?? rawList[i]?.tag ?? "").trim().replace(/^#+/, "");
            const parts = rawName.split("/").filter(p => p.length > 0);
            for (let d = 0; d < parts.length - 1; ++d)
                next[parts.slice(0, d + 1).join("/")] = true;
        }
        root.expandedParentTags = next;
    }

    function collapseAllTagGroups(): void {
        root.expandedParentTags = {};
    }

    function cycleTagSortMode(): void {
        const order = ["countDesc", "countAsc", "nameAsc", "nameDesc"];
        const idx = order.indexOf(root.tagSortMode);
        root.tagSortMode = order[(idx + 1) % order.length];
    }

    readonly property var hierarchicalTagsList: {
        const rawList = Array.isArray(root.tagsList) ? root.tagsList : [];
        const q = String(root.tagSearchQuery ?? "").trim().replace(/^#+/, "").toLowerCase();
        const sortMode = String(root.tagSortMode ?? "countDesc");
        const nodes = Object.create(null);
        const roots = [];
        for (let i = 0; i < rawList.length; ++i) {
            const item = rawList[i];
            if (!item)
                continue;
            const rawName = String(item.name ?? item.tag ?? "").trim().replace(/^#+/, "");
            if (rawName.length === 0)
                continue;
            const parts = rawName.split("/").filter(p => p.length > 0);
            const count = Number(item.count ?? 0);
            const notes = Array.isArray(item.notes) ? item.notes : [];
            for (let depth = 0; depth < parts.length; ++depth) {
                const name = parts.slice(0, depth + 1).join("/");
                const parentTag = depth > 0 ? parts.slice(0, depth).join("/") : name;
                if (!nodes[name]) {
                    nodes[name] = {
                        "name": name,
                        "label": parts[depth],
                        "parentTag": parentTag,
                        "depth": depth,
                        "directCount": 0,
                        "totalCount": 0,
                        "noteSet": Object.create(null),
                        "children": []
                    };
                    if (depth === 0)
                        roots.push(nodes[name]);
                    else
                        nodes[parentTag].children.push(nodes[name]);
                }
                const node = nodes[name];
                node.totalCount += count;
                if (depth === parts.length - 1)
                    node.directCount += count;
                for (let nIdx = 0; nIdx < notes.length; ++nIdx)
                    node.noteSet[String(notes[nIdx])] = true;
            }
        }
        function nodeCount(n) {
            const uniq = Object.keys(n.noteSet).length;
            return uniq > 0 ? uniq : (n.directCount > 0 ? n.directCount : n.totalCount);
        }
        function matchesQuery(node) {
            if (q.length === 0)
                return true;
            if (node.name.toLowerCase().includes(q))
                return true;
            for (let i = 0; i < node.children.length; ++i) {
                if (matchesQuery(node.children[i]))
                    return true;
            }
            return false;
        }
        function sortNodes(list) {
            list.sort((a, b) => {
                if (sortMode === "countAsc")
                    return nodeCount(a) - nodeCount(b) || a.name.localeCompare(b.name);
                if (sortMode === "nameAsc")
                    return a.name.localeCompare(b.name);
                if (sortMode === "nameDesc")
                    return b.name.localeCompare(a.name);
                return nodeCount(b) - nodeCount(a) || a.name.localeCompare(b.name);
            });
        }
        const out = [];
        function appendNode(node) {
            if (!matchesQuery(node))
                return;
            const expanded = q.length > 0 ? true : Boolean(root.expandedParentTags[node.name]);
            const uniqueNotesCount = Object.keys(node.noteSet).length;
            out.push({
                "name": node.name,
                "displayLabel": "#" + (node.depth > 0 ? node.label : node.name),
                "fullTag": "#" + node.name,
                "subtagLabel": node.depth > 0 ? node.label : "",
                "count": uniqueNotesCount > 0 ? uniqueNotesCount : (node.directCount > 0 ? node.directCount : node.totalCount),
                "directCount": node.directCount,
                "totalCount": node.totalCount,
                "hasChildren": node.children.length > 0,
                "childrenCount": node.children.length,
                "expanded": expanded,
                "isSubtag": node.depth > 0,
                "parentTag": node.parentTag,
                "depth": node.depth
            });
            if (expanded) {
                sortNodes(node.children);
                for (let i = 0; i < node.children.length; ++i)
                    appendNode(node.children[i]);
            }
        }
        sortNodes(roots);
        for (let i = 0; i < roots.length; ++i)
            appendNode(roots[i]);
        return out;
    }

    // Flattened visible tree rows for the left file explorer
    property var visibleTreeRows: []

    // Current document state
    property string currentPath: ""
    property var currentDoc: null
    property string draftContent: ""
    property bool isDirty: false
    property var foldedBlocks: ({})
    property int editingBlockId: -1
    property string editingBlockText: ""
    property var historyBack: []
    property var historyForward: []
    property string lastExternalOpenedPath: ""

    // Calendar state
    property int calendarYear: (new Date()).getFullYear()
    property int calendarMonth: (new Date()).getMonth() + 1
    property string calendarHeader: ""
    property var calendarCells: []
    property string selectedDateStr: Qt.formatDate(new Date(), "yyyy-MM-dd")

    // Search state
    property string searchQuery: ""
    property var searchResults: []
    property int _searchGeneration: 0
    property var _pendingSearch: null

    // Queued document operations & sleep-resume tracking
    property var _docQueue: []
    property var _activeDocReq: null
    property bool _rescanAfterDoc: false
    property bool _rescanQueued: false
    property var _deleteRollbackSnapshots: ({})
    property string _loadedVaultPath: ""
    property bool _calendarLoadedFromCli: false
    property double _lastScanDoneMs: 0
    property string _lastAppliedScanDigest: ""
    property bool _forceFreshScan: false
    property double _scanStartedAtMs: 0
    property double _docStartedAtMs: 0
    property double _lastHeartbeatMs: Date.now()
    property bool _syncingCheckInGuard: false

    signal fileOpened(string relPath, string category)
    signal fileRead(string relPath)
    signal externalFileDispatched(string absPath)
    signal noteSaved(string relPath)
    signal focusFileFilterRequested()
    signal focusVaultSearchRequested()
    signal clipboardImagePasted(string markdownEmbed, string relPath)
    signal pdfHighlightCaptured(string noteRelPath, int page)
    signal noteHistoryRestored(string relPath)

    Component.onCompleted: {
        root._ensureFallbackCalendar(root.calendarYear, root.calendarMonth);
        if (root.vaultConfigured) {
            prewarmTimer.restart();
        }
    }

    Connections {
        target: Persistent.states?.aquaCheckIn ?? null
        function onMoodChanged() { root._onCompanionCheckInChanged("mood", Persistent.states?.aquaCheckIn); }
        function onEnergyChanged() { root._onCompanionCheckInChanged("energy", Persistent.states?.aquaCheckIn); }
        function onWeightChanged() { root._onCompanionCheckInChanged("weight", Persistent.states?.aquaCheckIn); }
        function onDateChanged() { root._onCompanionCheckInChanged("", Persistent.states?.aquaCheckIn); }
    }

    Connections {
        target: (Persistent.states?.companionCheckIn && Persistent.states?.companionCheckIn !== Persistent.states?.aquaCheckIn)
            ? Persistent.states.companionCheckIn
            : null
        function onMoodChanged() { root._onCompanionCheckInChanged("mood", Persistent.states?.companionCheckIn); }
        function onEnergyChanged() { root._onCompanionCheckInChanged("energy", Persistent.states?.companionCheckIn); }
        function onWeightChanged() { root._onCompanionCheckInChanged("weight", Persistent.states?.companionCheckIn); }
        function onDateChanged() { root._onCompanionCheckInChanged("", Persistent.states?.companionCheckIn); }
    }

    Connections {
        target: Config
        function onReadyChanged() {
            if (Config.ready && root.vaultConfigured && (!root.vaultLoaded || root._loadedVaultPath !== root.configuredVaultPath))
                prewarmTimer.restart();
        }
        function onConfigChanged() {
            if (root.vaultConfigured && (!root.vaultLoaded || root._loadedVaultPath !== root.configuredVaultPath))
                prewarmTimer.restart();
        }
    }

    Connections {
        target: Persistent
        function onReadyChanged() {
            if (!Persistent.ready)
                return;
            if (root._lastScanDoneMs > 0 && root._loadedVaultPath === root.configuredVaultPath)
                root._syncScannedJournalCheckIn(root.todayJournalInfo);
            else if (root.vaultConfigured && !scanProc.running)
                prewarmTimer.restart();
        }
    }

    function _activeCompanionCheckInObj(sourceObj = null) {
        if (sourceObj)
            return sourceObj;
        const todayIso = Qt.formatDate(new Date(), "yyyy-MM-dd");
        const c1 = Persistent.states?.companionCheckIn;
        const c2 = Persistent.states?.aquaCheckIn;
        if (c1 && String(c1.date ?? "").trim() === todayIso
                && (String(c1.mood ?? "").trim().length > 0
                    || String(c1.energy ?? "").trim().length > 0
                    || (("weight" in c1) && String(c1.weight ?? "").trim().length > 0)))
            return c1;
        if (c2 && String(c2.date ?? "").trim() === todayIso)
            return c2;
        return c1 ?? c2 ?? null;
    }

    function _syncScannedJournalCheckIn(journal): void {
        if (!Persistent.ready)
            return;
        if (!Boolean(journal?.exists)) {
            root._onCompanionCheckInChanged();
            return;
        }
        const mood = String(journal.mood ?? "").trim();
        const energy = String(journal.energy ?? "").trim();
        const weight = String(journal.weight ?? "").trim();
        const hasMood = journal.hasMood === undefined ? mood.length > 0 : Boolean(journal.hasMood);
        const hasEnergy = journal.hasEnergy === undefined ? energy.length > 0 : Boolean(journal.hasEnergy);
        const hasWeight = journal.hasWeight === undefined ? weight.length > 0 : Boolean(journal.hasWeight);
        if (hasMood || hasEnergy || hasWeight)
            root._syncJournalToCompanion(String(journal.date ?? ""), hasMood ? mood : undefined, hasEnergy ? energy : undefined, hasWeight ? weight : undefined);
        else
            root._onCompanionCheckInChanged();
    }

    function _onCompanionCheckInChanged(changedField = "", sourceObj = null): void {
        if (root._syncingCheckInGuard || !Persistent.ready || !root.vaultConfigured)
            return;
        if (root._lastScanDoneMs === 0 || root._loadedVaultPath !== root.configuredVaultPath) {
            if (!scanProc.running)
                root.refreshVault();
            return;
        }
        const ci = root._activeCompanionCheckInObj(sourceObj);
        if (!ci)
            return;
        const todayIso = Qt.formatDate(new Date(), "yyyy-MM-dd");
        const ciDate = String(ci.date ?? "").trim();
        if (ciDate !== todayIso)
            return;
        const mood = String(ci.mood ?? "").trim();
        const energy = String(ci.energy ?? "").trim();
        const weight = ("weight" in ci) ? String(ci.weight ?? "").trim() : "";
        if (changedField === "mood") {
            root.syncCompanionCheckIn(todayIso, mood, undefined, undefined);
            return;
        }
        if (changedField === "energy") {
            root.syncCompanionCheckIn(todayIso, undefined, energy, undefined);
            return;
        }
        if (changedField === "weight") {
            root.syncCompanionCheckIn(todayIso, undefined, undefined, weight);
            return;
        }
        // Startup/date discovery has no explicit clear intent.
        if (mood.length === 0 && energy.length === 0 && weight.length === 0)
            return;
        root.syncCompanionCheckIn(todayIso, mood.length > 0 ? mood : undefined, energy.length > 0 ? energy : undefined, weight.length > 0 ? weight : undefined);
    }

    function syncCompanionCheckIn(dateStr: string, mood, energy, weight = undefined): bool {
        if (!root.vaultConfigured)
            return false;
        const targetDate = String(dateStr ?? "").trim() || Qt.formatDate(new Date(), "yyyy-MM-dd");
        const hasMood = mood !== undefined && mood !== null;
        const hasEnergy = energy !== undefined && energy !== null;
        const hasWeight = weight !== undefined && weight !== null;
        const cleanMood = String(mood ?? "").trim();
        const cleanEnergy = String(energy ?? "").trim();
        const cleanWeight = String(weight ?? "").trim();
        if (!hasMood && !hasEnergy && !hasWeight)
            return false;
        const tj = root.todayJournalInfo ?? ({});
        if (Boolean(tj.exists) && String(tj.date ?? "") === targetDate
                && (!hasMood || (tj.hasMood !== false && String(tj.mood ?? "") === cleanMood))
                && (!hasEnergy || (tj.hasEnergy !== false && String(tj.energy ?? "") === cleanEnergy))
                && (!hasWeight || (tj.hasWeight !== false && String(tj.weight ?? "") === cleanWeight))) {
            return false;
        }
        // Keep this readback authoritative: a failed queued write must remain retryable.
        const args = [
            root.binaryPath,
            "daily",
            "--vault",
            root.configuredVaultPath,
            "--date",
            targetDate,
            "--folder",
            root.dailyFolder,
            "--format",
            root.dailyFormat
        ];
        if (hasMood) {
            args.push("--mood");
            args.push(cleanMood);
        }
        if (hasEnergy) {
            args.push("--energy");
            args.push(cleanEnergy);
        }
        if (hasWeight) {
            args.push("--weight");
            args.push(cleanWeight);
        }
        root._rescanAfterDoc = true;
        root._enqueueDocOp({
            "kind": "daily-checkin",
            "relPath": String(tj.relPath ?? ""),
            "recordHistory": false,
            "useStdin": false,
            "args": args
        });
        return true;
    }

    function _syncJournalToCompanion(dateIso: string, moodVal, energyVal, weightVal = undefined): void {
        const cleanDate = String(dateIso ?? "").trim();
        const todayIso = Qt.formatDate(new Date(), "yyyy-MM-dd");
        if (!cleanDate || cleanDate !== todayIso)
            return;
        const targets = [];
        if (Persistent.states?.aquaCheckIn)
            targets.push(Persistent.states.aquaCheckIn);
        if (Persistent.states?.companionCheckIn && Persistent.states.companionCheckIn !== Persistent.states?.aquaCheckIn)
            targets.push(Persistent.states.companionCheckIn);
        if (targets.length === 0)
            return;
        const primary = targets[0];
        const sameDay = primary.date === todayIso;
        const nextMood = moodVal !== undefined && moodVal !== null ? String(moodVal).trim() : String(sameDay ? primary.mood : "");
        const nextEnergy = energyVal !== undefined && energyVal !== null ? String(energyVal).trim() : String(sameDay ? primary.energy : "");
        const nextWeight = weightVal !== undefined && weightVal !== null ? String(weightVal).trim() : String((sameDay && ("weight" in primary)) ? primary.weight : "");
        root.todayJournalInfo = Object.assign({}, root.todayJournalInfo, {
            "date": todayIso,
            "exists": true,
            "mood": nextMood,
            "energy": nextEnergy,
            "weight": nextWeight
        });
        const allSynced = targets.every(t => t.date === todayIso && t.mood === nextMood && t.energy === nextEnergy && (!("weight" in t) || t.weight === nextWeight));
        if (allSynced)
            return;
        root._syncingCheckInGuard = true;
        for (let i = 0; i < targets.length; ++i) {
            const ci = targets[i];
            const ciSameDay = ci.date === todayIso;
            ci.date = todayIso;
            if (!ciSameDay || (moodVal !== undefined && moodVal !== null))
                ci.mood = nextMood;
            if (!ciSameDay || (energyVal !== undefined && energyVal !== null))
                ci.energy = nextEnergy;
            if (("weight" in ci) && (!ciSameDay || (weightVal !== undefined && weightVal !== null)))
                ci.weight = nextWeight;
        }
        root._syncingCheckInGuard = false;
    }

    function _ensureFallbackCalendar(year: int, month: int): void {
        const y = year > 0 ? year : (new Date()).getFullYear();
        const m = (month >= 1 && month <= 12) ? month : ((new Date()).getMonth() + 1);
        const monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
        if (!root.calendarHeader)
            root.calendarHeader = monthNames[m - 1] + " " + String(y);
        if (Array.isArray(root.calendarCells) && root.calendarCells.length === 42)
            return;
        const firstDate = new Date(y, m - 1, 1);
        const firstWd = (firstDate.getDay() + 6) % 7; // Mon=0 .. Sun=6
        const daysInCur = new Date(y, m, 0).getDate();
        const prevY = m === 1 ? y - 1 : y;
        const prevM = m === 1 ? 12 : m - 1;
        const nextY = m === 12 ? y + 1 : y;
        const nextM = m === 12 ? 1 : m + 1;
        const daysInPrev = new Date(prevY, prevM, 0).getDate();
        const todayIso = Qt.formatDate(new Date(), "yyyy-MM-dd");
        const pad2 = n => (n < 10 ? "0" + String(n) : String(n));
        const cells = [];
        for (let i = 0; i < firstWd; ++i) {
            const d = daysInPrev - firstWd + 1 + i;
            const ds = String(prevY) + "-" + pad2(prevM) + "-" + pad2(d);
            cells.push({ "day": d, "month": prevM, "year": prevY, "dateStr": ds, "inMonth": false, "isToday": ds === todayIso, "hasJournal": false, "journalPath": "", "openTasks": 0, "doneTasks": 0, "wordCount": 0, "solidDots": 0, "hasOpenTasks": false, "weekNumber": 0 });
        }
        for (let d = 1; d <= daysInCur; ++d) {
            const ds = String(y) + "-" + pad2(m) + "-" + pad2(d);
            cells.push({ "day": d, "month": m, "year": y, "dateStr": ds, "inMonth": true, "isToday": ds === todayIso, "hasJournal": false, "journalPath": "", "openTasks": 0, "doneTasks": 0, "wordCount": 0, "solidDots": 0, "hasOpenTasks": false, "weekNumber": 0 });
        }
        let nextD = 1;
        while (cells.length < 42) {
            const ds = String(nextY) + "-" + pad2(nextM) + "-" + pad2(nextD);
            cells.push({ "day": nextD, "month": nextM, "year": nextY, "dateStr": ds, "inMonth": false, "isToday": ds === todayIso, "hasJournal": false, "journalPath": "", "openTasks": 0, "doneTasks": 0, "wordCount": 0, "solidDots": 0, "hasOpenTasks": false, "weekNumber": 0 });
            nextD += 1;
        }
        root.calendarCells = cells;
    }

    function open(): void {
        root.isOpen = true;
        if (treeRebuildTimer.running) {
            treeRebuildTimer.stop();
            root._rebuildVisibleTreeRowsImmediate();
        }
        root._ensureFallbackCalendar(root.calendarYear, root.calendarMonth);
        if (root.vaultConfigured) {
            const now = Date.now();
            if (scanProc.running && (now - root._scanStartedAtMs > 9000)) {
                scanProc.running = false;
            }
            if (!root.vaultLoaded || root._loadedVaultPath !== root.configuredVaultPath) {
                root._lastAppliedScanDigest = "";
                openRefreshTimer.restart();
            } else if (now - root._lastScanDoneMs > 180000) {
                openRefreshTimer.restart();
            }
        }
    }

    Timer {
        id: openRefreshTimer
        interval: Quickshell.env("ALIS_NEXUS_HEADLESS_SERVICE_ONLY") === "1" ? 1 : 720
        repeat: false
        onTriggered: {
            if (!root.isOpen || !root.vaultConfigured)
                return;
            root.refreshVault();
            root.refreshCalendar(root.calendarYear, root.calendarMonth);
        }
    }

    function openOverlay(): void {
        root.setOverlayMode(true);
        root.open();
    }

    function openWindow(): void {
        const wasOverlay = root.overlayMode;
        root.setOverlayMode(false);
        if (wasOverlay)
            root._restoreOverlayAfterWindowClose = true;
        root.open();
    }

    function close(): void {
        root.isOpen = false;
        root.commandPaletteOpen = false;
        root.vimMode = "NORMAL";
        root.vimCommandBuffer = "";
        root.vimKeyBuffer = "";
        root.vimCountBuffer = "";
        root.vimVisualAnchor = -1;
        if (root._restoreOverlayAfterWindowClose) {
            root._restoreOverlayAfterWindowClose = false;
            root.overlayMode = true;
        }
    }

    function toggle(): void {
        if (root.isOpen)
            root.close();
        else
            root.open();
    }

    function setOverlayMode(enabled: bool): void {
        root._restoreOverlayAfterWindowClose = false;
        root.overlayMode = Boolean(enabled);
    }

    function toggleOverlayMode(): void {
        root.setOverlayMode(!root.overlayMode);
        root.vimStatusMessage = root.overlayMode ? "Switched to Overlay Mode" : "Switched to Window Mode";
    }

    function setEditorMode(mode: string): void {
        if (mode !== "hybrid" && mode !== "raw" && mode !== "split")
            return;
        root.editorMode = mode;
    }

    function setVimEnabled(enabled: bool): void {
        root.vimEnabled = Boolean(enabled);
        if (!root.vimEnabled)
            root.vimMode = "INSERT";
        else
            root.vimMode = "NORMAL";
        root.vimCountBuffer = "";
        root.vimKeyBuffer = "";
        root.vimVisualAnchor = -1;
    }

    function openHomepage(): void {
        root.activeView = "homepage";
        root.editingBlockId = -1;
        root.vimMode = "NORMAL";
        root.vimCountBuffer = "";
        root.vimKeyBuffer = "";
        root.vimVisualAnchor = -1;
        root.vimStatusMessage = "Homepage";
    }

    function openGraphView(): void {
        root.activeView = "graph";
        root.editingBlockId = -1;
        root.vimMode = "NORMAL";
        root.vimCountBuffer = "";
        root.vimKeyBuffer = "";
        root.vimVisualAnchor = -1;
        root.vimStatusMessage = "Vault Graph";
    }

    function _normalizeCollectionId(collectionId: string): string {
        const clean = String(collectionId ?? "").trim().toLowerCase();
        if (!clean)
            return "";
        if (clean === "tv" || clean === "tv-series" || clean === "series" || clean === "tvseries")
            return "tvseries";
        if (clean === "movie")
            return "movies";
        if (clean === "game")
            return "games";
        if (clean === "book")
            return "books";
        if (clean === "recipe")
            return "recipes";
        if (clean === "exercise" || clean === "workout")
            return "exercises";
        if (clean === "clipping")
            return "clippings";
        if (clean === "website" || clean === "onion")
            return "websites";
        if (clean === "zk")
            return "zettelkasten";
        if (clean === "place")
            return "places";
        if (clean === "contact")
            return "contacts";
        return clean;
    }

    function openCollection(collectionId: string): void {
        const clean = root._normalizeCollectionId(collectionId);
        if (!clean)
            return;
        root.activeCollection = clean;
        root.collectionFilterQuery = "";
        root.activeView = "collection";
        root.editingBlockId = -1;
        root.vimMode = "NORMAL";
        root.vimCountBuffer = "";
        root.vimKeyBuffer = "";
        root.vimVisualAnchor = -1;
        root.vimStatusMessage = "Collection: " + clean;
    }

    function openDatabaseView(baseRelPath = ""): void {
        const cleaned = String(baseRelPath ?? "").trim();
        root.databasePath = cleaned;
        root.activeView = "database";
        root.editingBlockId = -1;
        root.vimMode = "NORMAL";
        root.vimCountBuffer = "";
        root.vimKeyBuffer = "";
        root.vimVisualAnchor = -1;
        root.vimStatusMessage = cleaned.length > 0 ? ("Database: " + cleaned) : "Vault Database Explorer";
        if (root.vaultConfigured) {
            let folderHint = "";
            if (cleaned.indexOf("/") !== -1)
                folderHint = cleaned.slice(0, cleaned.lastIndexOf("/"));
            root.runDatabaseQuery({ "folder": folderHint });
        }
    }

    function openCanvasView(canvasRelPath = ""): void {
        const target = String(canvasRelPath ?? "").trim();
        if (target.length > 0) {
            root.openFile(target, true);
            return;
        }
        if (root.currentDoc && String(root.currentDoc.category ?? "") === "canvas") {
            root.activeView = "canvas";
            return;
        }
        const files = Array.isArray(root.flatFiles) ? root.flatFiles : [];
        for (let i = 0; i < files.length; ++i) {
            if (String(files[i]?.relPath ?? "").toLowerCase().endsWith(".canvas")) {
                root.openFile(String(files[i].relPath), true);
                return;
            }
        }
        root.createCanvasNote("00_Capture/Untitled Canvas.canvas");
    }

    function createCanvasNote(relPath = "00_Capture/Untitled Canvas.canvas"): void {
        if (!root.vaultConfigured)
            return;
        let cleaned = String(relPath ?? "").trim().replace(/^\/+/, "");
        if (!cleaned)
            cleaned = "00_Capture/Untitled Canvas.canvas";
        if (!cleaned.toLowerCase().endsWith(".canvas"))
            cleaned += ".canvas";
        const starter = JSON.stringify({
            "nodes": [
                { "id": "n-start", "type": "text", "text": "# New Canvas\nDouble-click to add nodes or drag edges between handles.", "x": -140, "y": -60, "width": 280, "height": 120, "color": "4" }
            ],
            "edges": []
        }, null, 2);
        root._rescanAfterDoc = true;
        root._enqueueDocOp({
            "kind": "write",
            "relPath": cleaned,
            "recordHistory": true,
            "useStdin": true,
            "stdinPayload": starter,
            "args": [root.binaryPath, "write", "--vault", root.configuredVaultPath, "--path", cleaned]
        });
    }

    function saveCanvasFile(relPath: string, canvasObj): void {
        const cleaned = String(relPath ?? root.currentPath ?? "").trim();
        if (!root.vaultConfigured || cleaned.length === 0 || !canvasObj || typeof canvasObj !== "object")
            return;
        const jsonStr = JSON.stringify({
            "nodes": Array.isArray(canvasObj.nodes) ? canvasObj.nodes : [],
            "edges": Array.isArray(canvasObj.edges) ? canvasObj.edges : []
        }, null, 2);
        root.draftContent = jsonStr;
        root._rescanAfterDoc = false;
        root._enqueueDocOp({
            "kind": "write",
            "relPath": cleaned,
            "recordHistory": false,
            "useStdin": true,
            "stdinPayload": jsonStr,
            "args": [root.binaryPath, "write", "--vault", root.configuredVaultPath, "--path", cleaned]
        });
    }

    function requestScrollToLine(line1Based: int): void {
        const ln = Math.max(1, Number(line1Based) || 1);
        root.scrollToLineRequest = ln;
        root.scrollToLineSerial += 1;
    }

    function _registerOpenTab(relPath: string, title = "", category = "markdown"): void {
        const clean = String(relPath ?? "").trim();
        if (!clean || category === "external")
            return;
        const next = [];
        let existingPinned = false;
        const list = Array.isArray(root.openTabs) ? root.openTabs : [];
        for (let i = 0; i < list.length; ++i) {
            const t = list[i];
            if (!t || !t.relPath)
                continue;
            if (String(t.relPath) === clean) {
                existingPinned = Boolean(t.pinned);
                continue;
            }
            next.push(t);
        }
        const fallbackTitle = clean.split("/").pop().replace(/\.md$/i, "");
        const tabObj = {
            "relPath": clean,
            "title": String(title ?? "").trim() || fallbackTitle,
            "category": String(category ?? "markdown"),
            "pinned": existingPinned
        };
        if (existingPinned) {
            next.unshift(tabObj);
        } else {
            next.push(tabObj);
        }
        while (next.length > 16) {
            let dropIdx = -1;
            for (let i = 0; i < next.length; ++i) {
                if (!next[i].pinned && next[i].relPath !== clean) {
                    dropIdx = i;
                    break;
                }
            }
            if (dropIdx === -1)
                break;
            next.splice(dropIdx, 1);
        }
        root.openTabs = next;
        root._saveWorkspacePrefs();
    }

    function activateTab(relPath: string): void {
        const clean = String(relPath ?? "").trim();
        if (!clean)
            return;
        if (clean === root.currentPath && root.currentDoc) {
            root.activeView = String(root.currentDoc.category ?? "") === "canvas" ? "canvas" : "document";
            return;
        }
        root.openFile(clean, true);
    }

    function closeTab(relPath: string): void {
        const clean = String(relPath ?? "").trim();
        const list = Array.isArray(root.openTabs) ? root.openTabs : [];
        const idx = list.findIndex(t => String(t?.relPath ?? "") === clean);
        if (idx === -1)
            return;
        const next = list.slice();
        next.splice(idx, 1);
        root.openTabs = next;
        root._saveWorkspacePrefs();
        if (root.currentPath === clean) {
            if (next.length > 0) {
                const neighbor = next[Math.min(idx, next.length - 1)];
                if (neighbor && neighbor.relPath) {
                    root.openFile(String(neighbor.relPath), false);
                    return;
                }
            }
            root.currentPath = "";
            root.currentDoc = null;
            root.draftContent = "";
            root.isDirty = false;
            root.openHomepage();
        }
    }

    function togglePinTab(relPath: string): void {
        const clean = String(relPath ?? "").trim();
        const list = Array.isArray(root.openTabs) ? root.openTabs : [];
        let changed = false;
        const next = list.map(t => {
            if (String(t?.relPath ?? "") === clean) {
                changed = true;
                return Object.assign({}, t, { "pinned": !Boolean(t.pinned) });
            }
            return t;
        });
        if (changed) {
            next.sort((a, b) => (Boolean(b.pinned) ? 1 : 0) - (Boolean(a.pinned) ? 1 : 0));
            root.openTabs = next;
            root._saveWorkspacePrefs();
        }
    }

    function cycleTab(delta = 1): void {
        const list = Array.isArray(root.openTabs) ? root.openTabs : [];
        if (list.length === 0)
            return;
        let idx = list.findIndex(t => String(t?.relPath ?? "") === root.currentPath);
        if (idx === -1)
            idx = 0;
        const target = list[(idx + delta + list.length) % list.length];
        if (target && target.relPath)
            root.activateTab(String(target.relPath));
    }

    function _resolveVaultFileRelPath(targetOrWikilink: string): string {
        let raw = String(targetOrWikilink ?? "").trim();
        if (!raw)
            return "";
        const pipeIdx = raw.indexOf("|");
        if (pipeIdx !== -1)
            raw = raw.substring(0, pipeIdx).trim();
        const hashIdx = raw.indexOf("#");
        if (hashIdx !== -1)
            raw = raw.substring(0, hashIdx).trim();
        if (!raw)
            return "";
        const lower = raw.replace(/\.md$/i, "").toLowerCase();
        const files = Array.isArray(root.flatFiles) ? root.flatFiles : [];
        for (let i = 0; i < files.length; ++i) {
            const f = files[i];
            if (!f) continue;
            const relLower = String(f.relPath ?? "").toLowerCase();
            const relNoExt = relLower.replace(/\.md$/i, "");
            const stemLower = String(f.stem ?? "").toLowerCase();
            if (relLower === raw.toLowerCase() || relLower === lower || relNoExt === lower || stemLower === lower)
                return String(f.relPath);
        }
        return raw;
    }

    function openInSecondaryPane(relPath: string): void {
        const cleaned = root._resolveVaultFileRelPath(relPath);
        if (!root.vaultConfigured || cleaned.length === 0)
            return;
        root.secondaryPath = cleaned;
        root.splitPaneOpen = true;
        if (secondaryDocProc.running)
            secondaryDocProc.running = false;
        secondaryDocProc.command = [root.binaryPath, "read", "--vault", root.configuredVaultPath, "--path", cleaned];
        secondaryDocProc.running = true;
        secondaryDocTimeout.restart();
    }

    function toggleSplitPane(): void {
        if (root.splitPaneOpen) {
            root.closeSecondaryPane();
            return;
        }
        let target = root.secondaryPath;
        if (!target) {
            const list = Array.isArray(root.openTabs) ? root.openTabs : [];
            for (let i = list.length - 1; i >= 0; --i) {
                if (list[i] && list[i].relPath && list[i].relPath !== root.currentPath) {
                    target = String(list[i].relPath);
                    break;
                }
            }
        }
        if (!target && root.currentPath.length > 0)
            target = root.currentPath;
        if (target)
            root.openInSecondaryPane(target);
        else
            root.splitPaneOpen = true;
    }

    function closeSecondaryPane(): void {
        if (secondaryDocProc.running)
            secondaryDocProc.running = false;
        secondaryDocTimeout.stop();
        root.splitPaneOpen = false;
        root.secondaryPath = "";
        root.secondaryDoc = null;
    }

    function swapPanes(): void {
        const secRel = String(root.secondaryPath ?? "").trim();
        const curRel = String(root.currentPath ?? "").trim();
        if (!secRel)
            return;
        if (curRel.length > 0 && curRel !== secRel)
            root.openInSecondaryPane(curRel);
        root.openFile(secRel, true);
    }

    function openExternalUrl(url: string): bool {
        const raw = String(url ?? "").trim();
        if (!/^https?:\/\/[^\s"'<>]+$/i.test(raw))
            return false;
        root.vimStatusMessage = "Opening URL: " + raw;
        if (Quickshell.env("ALIS_NEXUS_DISABLE_XDG_OPEN") === "1")
            return true;
        Quickshell.execDetached(["xdg-open", raw]);
        return true;
    }

    function toggleFolderExpanded(relPath: string): void {
        if (!relPath)
            return;
        const next = Object.assign({}, root.expandedFolders);
        next[relPath] = !Boolean(next[relPath]);
        root.expandedFolders = next;
        root._rebuildVisibleTreeRows();
    }

    Timer {
        id: treeRebuildTimer
        interval: 24
        repeat: false
        onTriggered: root._rebuildVisibleTreeRowsImmediate()
    }

    function _rebuildVisibleTreeRows(): void {
        if (!root.isOpen && root._live && Quickshell.env("ALIS_NEXUS_HEADLESS_SERVICE_ONLY") !== "1") {
            treeRebuildTimer.restart();
            return;
        }
        treeRebuildTimer.stop();
        root._rebuildVisibleTreeRowsImmediate();
    }

    function _rebuildVisibleTreeRowsImmediate(): void {
        const rows = [];
        const filter = root.fileFilterQuery.trim().toLowerCase();

        function childMatchesFilter(child) {
            if (!child) return false;
            if (filter.length === 0) return true;
            const matchName = String(child.name ?? "").toLowerCase().indexOf(filter) !== -1;
            const matchPath = String(child.relPath ?? "").toLowerCase().indexOf(filter) !== -1;
            if (matchName || matchPath) return true;
            if (child.isDir && Array.isArray(child.children)) {
                for (let k = 0; k < child.children.length; ++k) {
                    if (childMatchesFilter(child.children[k]))
                        return true;
                }
            }
            return false;
        }

        function walk(node, depth, inheritedColor, inheritedTextColor, inheritedPrefix, parentRelPath, ancestorContinues, ancestorPaths) {
            if (!node || !Array.isArray(node.children))
                return;
            const visibleKids = [];
            for (let i = 0; i < node.children.length; ++i) {
                const c = node.children[i];
                if (!c) continue;
                if (filter.length > 0 && !c.isDir && !childMatchesFilter(c))
                    continue;
                visibleKids.push(c);
            }
            for (let i = 0; i < visibleKids.length; ++i) {
                const child = visibleKids[i];
                const isLastChild = (i === visibleKids.length - 1);
                const hasNextSibling = !isLastChild;
                const folderColor = (child.colorHex && String(child.colorHex).length > 0) ? String(child.colorHex) : (inheritedColor || "");
                const folderText = (child.textColorHex && String(child.textColorHex).length > 0) ? String(child.textColorHex) : (inheritedTextColor || "");
                const folderPrefix = (child.prefixCode && String(child.prefixCode).length > 0) ? String(child.prefixCode) : (inheritedPrefix || "");
                const nextAncestors = depth > 0 ? ancestorContinues.concat([hasNextSibling]) : ancestorContinues.slice();
                const childPath = String(child.relPath ?? "");
                if (child.isDir) {
                    const isExp = filter.length > 0 ? true : Boolean(root.expandedFolders[childPath]);
                    rows.push({
                        "name": child.name,
                        "relPath": childPath,
                        "parentRelPath": parentRelPath,
                        "isDir": true,
                        "depth": depth,
                        "expanded": isExp,
                        "isLastChild": isLastChild,
                        "siblingIndex": i,
                        "siblingCount": visibleKids.length,
                        "ancestorContinues": ancestorContinues.slice(),
                        "ancestorPaths": ancestorPaths.slice(),
                        "category": "folder",
                        "ext": "",
                        "noteCount": child.noteCount ?? 0,
                        "prefixCode": folderPrefix,
                        "colorHex": folderColor,
                        "textColorHex": folderText,
                        "iconName": child.iconName ?? "folder"
                    });
                    if (isExp) {
                        const childAncestorPaths = ancestorPaths.concat([childPath]);
                        walk(child, depth + 1, folderColor, folderText, folderPrefix, childPath, nextAncestors, childAncestorPaths);
                    }
                } else {
                    rows.push({
                        "name": child.name,
                        "relPath": childPath,
                        "parentRelPath": parentRelPath,
                        "isDir": false,
                        "depth": depth,
                        "expanded": false,
                        "isLastChild": isLastChild,
                        "siblingIndex": i,
                        "siblingCount": visibleKids.length,
                        "ancestorContinues": ancestorContinues.slice(),
                        "ancestorPaths": ancestorPaths.slice(),
                        "category": child.category ?? "markdown",
                        "ext": child.ext ?? "",
                        "noteCount": 0,
                        "prefixCode": folderPrefix,
                        "colorHex": folderColor,
                        "textColorHex": folderText,
                        "iconName": ""
                    });
                }
            }
        }

        walk(root.tree, 0, "", "", "", "", [], []);
        root.visibleTreeRows = rows;
    }

    function refreshVault(): void {
        if (!root.vaultConfigured)
            return;
        if (scanProc.running) {
            root._rescanQueued = true;
            return;
        }
        root._rescanQueued = false;
        const forceFresh = root._forceFreshScan;
        root._forceFreshScan = false;
        if (forceFresh)
            root._lastAppliedScanDigest = "";
        root.errorMessage = "";
        root._scanStartedAtMs = Date.now();
        scanProc.response = "";
        const todayIso = Qt.formatDate(new Date(), "yyyy-MM-dd");
        const cmd = [root.binaryPath, "scan", "--vault", root.configuredVaultPath, "--date", todayIso];
        if (root.vaultCacheFsPath.length > 0
                && Quickshell.env("ALIS_NEXUS_DISABLE_SCAN_CACHE") !== "1"
                && Quickshell.env("ALIS_NEXUS_HEADLESS_SERVICE_ONLY") !== "1") {
            cmd.push("--cache-file");
            cmd.push(root.vaultCacheFsPath);
            if (!forceFresh
                    && root.vaultLoaded
                    && root._loadedVaultPath === root.configuredVaultPath
                    && String(root.todayJournalInfo?.date ?? "") === todayIso) {
                cmd.push("--skip-if-unchanged");
            }
        }
        scanProc.command = cmd;
        scanProc.running = true;
        scanTimeout.restart();
    }

    function duplicateNote(relPath: string): bool {
        const cleaned = String(relPath ?? root.currentPath ?? "").trim();
        if (!root.vaultConfigured || cleaned.length === 0)
            return false;
        root._rescanAfterDoc = true;
        root._enqueueDocOp({
            "kind": "duplicate",
            "relPath": cleaned,
            "recordHistory": true,
            "useStdin": false,
            "args": [root.binaryPath, "duplicate", "--vault", root.configuredVaultPath, "--path", cleaned]
        });
        return true;
    }

    function copyToClipboard(text: string, label = "Copied"): void {
        const s = String(text ?? "");
        if (!s)
            return;
        Quickshell.clipboardText = s;
        if (Quickshell.env("ALIS_NEXUS_DISABLE_WL_COPY") !== "1") {
            const nd = String(Quickshell.shellPath("scripts/native-dispatch") ?? "").replace(/^(?:file:\/\/|qs:)/, "");
            Quickshell.execDetached([
                "/usr/bin/bash",
                "-c",
                "if [ -x \"$1\" ]; then exec \"$1\" clipboard copy -- \"$2\"; elif command -v wl-copy >/dev/null 2>&1; then exec wl-copy -- \"$2\"; fi",
                "alis-nexus-copy",
                nd,
                s
            ]);
        }
        root.vimStatusMessage = label + ": " + s;
    }

    function copyRelativePath(relPath: string): void {
        const cleaned = String(relPath ?? root.currentPath ?? "").trim();
        if (!cleaned)
            return;
        root.copyToClipboard(cleaned, "Copied path");
    }

    function openExternally(absPath: string, statusLabel = ""): void {
        const target = String(absPath ?? "").trim();
        if (!target)
            return;
        if (statusLabel.length > 0)
            root.vimStatusMessage = statusLabel;
        if (Quickshell.env("ALIS_NEXUS_DISABLE_XDG_OPEN") === "1")
            return;
        Quickshell.execDetached(["xdg-open", target]);
    }

    function revealInFileManager(relPath: string, isFolder = false): void {
        if (!root.vaultConfigured)
            return;
        const cleaned = String(relPath ?? root.currentPath ?? "").trim().replace(/^\/+|\/+$/g, "");
        let folderRel = "";
        if (Boolean(isFolder)) {
            folderRel = cleaned;
        } else if (cleaned.length > 0) {
            const slashIdx = cleaned.lastIndexOf("/");
            if (slashIdx !== -1)
                folderRel = cleaned.slice(0, slashIdx);
        }
        const absDir = folderRel.length > 0 ? (root.configuredVaultPath + "/" + folderRel) : root.configuredVaultPath;
        root.openExternally(absDir, "Revealed in File Manager: " + (folderRel.length > 0 ? folderRel : root.vaultName));
    }

    function openInDefaultApp(relPath: string): void {
        if (!root.vaultConfigured)
            return;
        const cleaned = String(relPath ?? root.currentPath ?? "").trim().replace(/^\/+/, "");
        if (!cleaned)
            return;
        const absFile = root.configuredVaultPath + "/" + cleaned;
        root.openExternally(absFile, "Opened in default app: " + cleaned);
    }

    function _collectFolderPaths(node, setObj): void {
        if (!node || typeof node !== "object")
            return;
        const rel = String(node.relPath ?? "").trim();
        if (node.isDir && rel.length > 0)
            setObj[rel] = true;
        const children = Array.isArray(node.children) ? node.children : [];
        for (let i = 0; i < children.length; ++i)
            root._collectFolderPaths(children[i], setObj);
    }

    function nextAvailableFolderRelPath(parentRelPath: string, baseName = "New Folder"): string {
        const parentClean = String(parentRelPath ?? "").trim().replace(/^\/+|\/+$/g, "");
        const cleanBase = String(baseName ?? "New Folder").trim() || "New Folder";
        const existing = {};
        root._collectFolderPaths(root.tree, existing);
        const files = Array.isArray(root.flatFiles) ? root.flatFiles : [];
        for (let i = 0; i < files.length; ++i) {
            const fRel = String(files[i]?.relPath ?? "");
            const parts = fRel.split("/");
            for (let d = 1; d < parts.length; ++d)
                existing[parts.slice(0, d).join("/")] = true;
        }
        let idx = 0;
        while (idx < 500) {
            const candName = idx === 0 ? cleanBase : (cleanBase + " " + String(idx + 1));
            const candRel = parentClean.length > 0 ? (parentClean + "/" + candName) : candName;
            if (!existing[candRel])
                return candRel;
            idx += 1;
        }
        const fallbackName = cleanBase + " " + String(Date.now());
        return parentClean.length > 0 ? (parentClean + "/" + fallbackName) : fallbackName;
    }

    function _insertOptimisticFolderNode(node, folderRel): var {
        if (!node || typeof node !== "object")
            return node;
        const slashIdx = folderRel.lastIndexOf("/");
        const parentRel = slashIdx === -1 ? "" : folderRel.slice(0, slashIdx);
        const folderName = slashIdx === -1 ? folderRel : folderRel.slice(slashIdx + 1);
        const curRel = String(node.relPath ?? "");
        const children = Array.isArray(node.children) ? node.children : [];
        if (curRel === parentRel) {
            for (let i = 0; i < children.length; ++i) {
                if (String(children[i]?.relPath ?? "") === folderRel)
                    return node;
            }
            const nextChildren = [{
                "name": folderName,
                "relPath": folderRel,
                "isDir": true,
                "noteCount": 0,
                "iconName": "folder",
                "children": []
            }].concat(children);
            return Object.assign({}, node, { "children": nextChildren });
        }
        if (curRel.length === 0 || parentRel === curRel || parentRel.startsWith(curRel + "/")) {
            let changed = false;
            const nextChildren = [];
            for (let i = 0; i < children.length; ++i) {
                const c = children[i];
                const cRel = String(c?.relPath ?? "");
                if (c && c.isDir && (parentRel === cRel || parentRel.startsWith(cRel + "/"))) {
                    const updated = root._insertOptimisticFolderNode(c, folderRel);
                    if (updated !== c)
                        changed = true;
                    nextChildren.push(updated);
                } else {
                    nextChildren.push(c);
                }
            }
            if (changed)
                return Object.assign({}, node, { "children": nextChildren });
        }
        return node;
    }

    function createUniqueSubfolder(parentRelPath: string, baseName = "New Folder"): string {
        if (!root.vaultConfigured)
            return "";
        const parentClean = String(parentRelPath ?? "").trim().replace(/^\/+|\/+$/g, "");
        const candRel = root.nextAvailableFolderRelPath(parentClean, baseName);
        if (!candRel)
            return "";
        if (parentClean.length > 0) {
            const nextExp = Object.assign({}, root.expandedFolders);
            nextExp[parentClean] = true;
            root.expandedFolders = nextExp;
        }
        if (!root.createFolder(candRel))
            return "";
        root.tree = root._insertOptimisticFolderNode(root.tree, candRel);
        root._rebuildVisibleTreeRows();
        return candRel;
    }

    function createNoteInFolder(folderRelPath: string, baseTitle = "Untitled"): void {
        if (!root.vaultConfigured)
            return;
        const folderClean = String(folderRelPath ?? "").trim().replace(/^\/+|\/+$/g, "");
        const existingSet = {};
        const files = Array.isArray(root.flatFiles) ? root.flatFiles : [];
        for (let i = 0; i < files.length; ++i) {
            existingSet[String(files[i]?.relPath ?? "")] = true;
        }
        const cleanBase = String(baseTitle ?? "Untitled").trim().replace(/[\/\\:*?"<>|]/g, " ").replace(/\.\./g, " ").replace(/\s+/g, " ").trim().slice(0, 80) || "Untitled";
        let idx = 0;
        let candRel = "";
        let candTitle = cleanBase;
        while (idx < 500) {
            candTitle = idx === 0 ? cleanBase : (cleanBase + " " + String(idx));
            const fname = candTitle + ".md";
            candRel = folderClean.length > 0 ? (folderClean + "/" + fname) : fname;
            if (!existingSet[candRel])
                break;
            idx += 1;
        }
        if (folderClean.length > 0) {
            const nextExp = Object.assign({}, root.expandedFolders);
            nextExp[folderClean] = true;
            root.expandedFolders = nextExp;
        }
        root.createNote(candRel, candTitle, "standard");
    }

    function createNoteWithContent(folderRelPath: string, baseTitle: string, markdownBody: string): string {
        if (!root.vaultConfigured)
            return "";
        const folderClean = String(folderRelPath ?? "").trim().replace(/^\/+|\/+$/g, "");
        const existingSet = {};
        const files = Array.isArray(root.flatFiles) ? root.flatFiles : [];
        for (let i = 0; i < files.length; ++i) {
            existingSet[String(files[i]?.relPath ?? "")] = true;
        }
        const cleanBase = String(baseTitle ?? "Companion Note").trim().replace(/[\/\\:*?"<>|]/g, " ").replace(/\s+/g, " ").trim().slice(0, 64) || "Companion Note";
        let idx = 0;
        let candRel = "";
        let candTitle = cleanBase;
        while (idx < 500) {
            candTitle = idx === 0 ? cleanBase : (cleanBase + " " + String(idx));
            const fname = candTitle + ".md";
            candRel = folderClean.length > 0 ? (folderClean + "/" + fname) : fname;
            if (!existingSet[candRel])
                break;
            idx += 1;
        }
        if (folderClean.length > 0) {
            const nextExp = Object.assign({}, root.expandedFolders);
            nextExp[folderClean] = true;
            root.expandedFolders = nextExp;
        }
        const bodyText = String(markdownBody ?? "");
        const hasFrontmatter = bodyText.replace(/^\s+/, "").startsWith("---\n");
        const finalDoc = hasFrontmatter
            ? bodyText
            : (`---\ntitle: "${candTitle.replace(/"/g, '\\"')}"\nsource: alis-companion\n---\n\n# ${candTitle}\n\n${bodyText.trim()}\n`);
        root._rescanAfterDoc = true;
        const preserveDirtyBuffer = Boolean(root.isDirty && root.currentPath.length > 0);
        root._enqueueDocOp({
            "kind": "write",
            "relPath": candRel,
            "recordHistory": !preserveDirtyBuffer,
            "openCreated": !preserveDirtyBuffer,
            "backgroundCreate": preserveDirtyBuffer,
            "useStdin": true,
            "stdinPayload": finalDoc,
            "args": [root.binaryPath, "write", "--vault", root.configuredVaultPath, "--path", candRel]
        });
        return candRel;
    }

    function refreshCalendar(year: int, month: int): void {
        if (!root.vaultConfigured || calendarProc.running || root._calendarServeInFlight)
            return;
        const y = year > 0 ? year : root.calendarYear;
        const m = (month >= 1 && month <= 12) ? month : root.calendarMonth;
        root.calendarYear = y;
        root.calendarMonth = m;
        const todayIso = Qt.formatDate(new Date(), "yyyy-MM-dd");
        const cliArgs = ["calendar", "--vault", root.configuredVaultPath, "--year", String(y), "--month", String(m), "--today", todayIso];
        const runSingleShot = () => {
            if (!root._live || calendarProc.running)
                return;
            calendarProc.response = "";
            calendarProc.command = [root.binaryPath].concat(cliArgs);
            calendarProc.running = true;
            calendarTimeout.restart();
        };
        if (root._canUseServe()) {
            root._calendarServeInFlight = true;
            const reqId = root._sendServeRequest(cliArgs, null, {
                "onResult": (payload, ok) => {
                    root._calendarServeInFlight = false;
                    if (ok && payload)
                        root._applyCalendarPayload(payload);
                },
                "onFallback": () => {
                    root._calendarServeInFlight = false;
                    runSingleShot();
                }
            });
            if (reqId > 0)
                return;
            root._calendarServeInFlight = false;
        }
        runSingleShot();
    }

    // ─── Tag Wrangler+ Operations (atomic vault-wide rename, merge, remove, tag page) ───
    function renameTag(fromTag: string, toTag: string, includeSubtags = true): bool {
        const cleanFrom = String(fromTag ?? "").trim().replace(/^#+/, "");
        const cleanTo = String(toTag ?? "").trim().replace(/^#+/, "");
        if (!root.vaultConfigured || cleanFrom.length === 0 || cleanTo.length === 0)
            return false;
        root._forceFreshScan = true;
        root._rescanAfterDoc = true;
        root._enqueueDocOp({
            "kind": "tag-rename",
            "fromTag": cleanFrom,
            "toTag": cleanTo,
            "relPath": root.currentPath,
            "recordHistory": false,
            "useStdin": false,
            "args": [
                root.binaryPath, "tag-rename",
                "--vault", root.configuredVaultPath,
                "--from", cleanFrom,
                "--to", cleanTo,
                "--include-subtags", includeSubtags ? "true" : "false"
            ]
        });
        return true;
    }

    function mergeTag(fromTag: string, targetTag: string, includeSubtags = true): bool {
        return root.renameTag(fromTag, targetTag, includeSubtags);
    }

    function removeTag(tagName: string, relPath = "", includeSubtags = false): bool {
        const cleanTag = String(tagName ?? "").trim().replace(/^#+/, "");
        if (!root.vaultConfigured || cleanTag.length === 0)
            return false;
        root._forceFreshScan = true;
        root._rescanAfterDoc = true;
        const args = [
            root.binaryPath, "tag-remove",
            "--vault", root.configuredVaultPath,
            "--tag", cleanTag,
            "--include-subtags", includeSubtags ? "true" : "false"
        ];
        const cleanRel = String(relPath ?? "").trim();
        if (cleanRel.length > 0) {
            args.push("--path");
            args.push(cleanRel);
        }
        root._enqueueDocOp({
            "kind": "tag-remove",
            "tag": cleanTag,
            "relPath": cleanRel || root.currentPath,
            "recordHistory": false,
            "useStdin": false,
            "args": args
        });
        return true;
    }

    function openOrCreateTagPage(tagName: string): bool {
        const cleanTag = String(tagName ?? "").trim().replace(/^#+/, "");
        if (!root.vaultConfigured || cleanTag.length === 0)
            return false;
        root._rescanAfterDoc = true;
        root._enqueueDocOp({
            "kind": "tag-page",
            "tag": cleanTag,
            "relPath": "",
            "recordHistory": true,
            "useStdin": false,
            "args": [
                root.binaryPath, "tag-page",
                "--vault", root.configuredVaultPath,
                "--tag", cleanTag
            ]
        });
        return true;
    }

    function prevCalendarMonth(): void {
        let y = root.calendarYear;
        let m = root.calendarMonth - 1;
        if (m < 1) {
            m = 12;
            y -= 1;
        }
        root.refreshCalendar(y, m);
    }

    function nextCalendarMonth(): void {
        let y = root.calendarYear;
        let m = root.calendarMonth + 1;
        if (m > 12) {
            m = 1;
            y += 1;
        }
        root.refreshCalendar(y, m);
    }

    function jumpCalendarToday(): void {
        const now = new Date();
        root.selectedDateStr = Qt.formatDate(now, "yyyy-MM-dd");
        root.refreshCalendar(now.getFullYear(), now.getMonth() + 1);
    }

    function _canUseServe(): bool {
        return root._live && !root._serveDisabled && root.binaryPath.length > 0;
    }

    function _isServeHotDocOp(req): bool {
        if (!req || !Array.isArray(req.args) || req.args.length < 2)
            return false;
        if (req.args[0] !== root.binaryPath)
            return false;
        const sub = String(req.args[1] ?? "");
        return sub === "read" || sub === "write" || sub === "toggle-todo" || sub === "set-frontmatter" || sub === "history-snapshot";
    }

    function _sendServeRequest(cliArgs, stdinPayload, handlers): int {
        if (!root._canUseServe())
            return 0;
        const reqId = root._serveNextId++;
        const frame = { "id": reqId, "args": cliArgs };
        if (stdinPayload !== null && stdinPayload !== undefined)
            frame.stdin = String(stdinPayload);
        const line = JSON.stringify(frame) + "\n";
        const pending = Object.assign({}, root._servePending);
        pending[String(reqId)] = {
            "id": reqId,
            "sentAtMs": Date.now(),
            "onResult": handlers.onResult,
            "onFallback": handlers.onFallback
        };
        root._servePending = pending;
        if (!serveProc.running) {
            root._serveStarted = false;
            serveProc.command = [root.binaryPath, "--serve"];
            serveProc.stdinEnabled = true;
            root._serveSendQueue.push(line);
            serveProc.running = true;
        } else if (!root._serveStarted) {
            root._serveSendQueue.push(line);
        } else {
            serveProc.write(line);
        }
        serveWatchdog.restart();
        return reqId;
    }

    function _handleServeLine(rawLine: string): void {
        const trimmed = String(rawLine ?? "").trim();
        if (trimmed.length === 0)
            return;
        let resp = null;
        try {
            resp = JSON.parse(trimmed);
        } catch (_e) {
            return;
        }
        const key = String(resp?.id ?? "");
        const entry = root._servePending[key];
        if (!entry)
            return;
        const pending = Object.assign({}, root._servePending);
        delete pending[key];
        root._servePending = pending;
        if (Object.keys(pending).length === 0)
            serveWatchdog.stop();
        root._serveFailures = 0;
        const ok = Boolean(resp?.ok);
        const payload = ok ? resp.result : { "ok": false, "error": String(resp?.error ?? "Operation failed") };
        if (typeof entry.onResult === "function")
            entry.onResult(payload, ok);
    }

    function _failAllServePending(disableNow: bool): void {
        serveWatchdog.stop();
        const pendingMap = root._servePending;
        root._servePending = ({});
        root._serveSendQueue = [];
        root._serveStarted = false;
        const keys = Object.keys(pendingMap);
        if (keys.length > 0 || disableNow) {
            root._serveFailures += 1;
            if (disableNow || root._serveFailures >= 3)
                root._serveDisabled = true;
        }
        for (let i = 0; i < keys.length; ++i) {
            const entry = pendingMap[keys[i]];
            if (entry && typeof entry.onFallback === "function")
                entry.onFallback();
        }
    }

    function _enqueueDocOp(req): void {
        root._docQueue.push(req);
        root._runNextDocOp();
    }

    function _startSingleShotDocOp(req): void {
        if (!root._live || !req)
            return;
        root._activeDocReq = req;
        root._docStartedAtMs = Date.now();
        docProc.response = "";
        docProc.stdinPayload = req.stdinPayload ?? "";
        docProc.stdinEnabled = Boolean(req.useStdin);
        docProc.command = req.args;
        docProc.running = true;
        docTimeout.restart();
    }

    function _handlePreWriteConflict(req, probePayload): bool {
        const expectedSha = String(req?.expectedSha ?? "");
        const diskSha = String(probePayload?.sha256 ?? "");
        if (!probePayload?.ok || expectedSha.length === 0 || diskSha.length === 0 || diskSha === expectedSha)
            return false;
        const targetRel = String(req?.relPath ?? "");
        if (targetRel === root.currentPath && typeof req?.stdinPayload === "string")
            root.draftContent = req.stdinPayload;
        root.externalConflictDetected = true;
        root.externalConflictPath = targetRel;
        root.externalConflictDiskContent = String(probePayload.content ?? "");
        root.externalConflictDiskSha = diskSha;
        root.externalConflictDiskMtime = Number(probePayload.mtimeSecs ?? 0);
        root.isDirty = true;
        root.vimStatusMessage = "External file change detected — Reload or Keep & Save";
        return true;
    }

    function _runNextDocOp(): void {
        if (docProc.running || preWriteProbeProc.running || root._activeDocServeId > 0 || root._docQueue.length === 0)
            return;
        const nextReq = root._docQueue.shift();
        const expectedSha = String(nextReq.expectedSha ?? "");
        const needsConflictProbe = nextReq.kind === "write" && expectedSha.length > 0 && String(nextReq.relPath ?? "").length > 0;
        if (root._canUseServe() && root._isServeHotDocOp(nextReq)) {
            root._activeDocReq = nextReq;
            root._docStartedAtMs = Date.now();
            const dispatchServeWrite = () => {
                const cliArgs = nextReq.args.slice(1);
                const stdinText = nextReq.useStdin ? String(nextReq.stdinPayload ?? "") : null;
                const reqId = root._sendServeRequest(cliArgs, stdinText, {
                    "onResult": (payload, _ok) => {
                        root._activeDocServeId = 0;
                        const finishedReq = root._activeDocReq;
                        root._activeDocReq = null;
                        root._finishDocOp(finishedReq, payload, false);
                    },
                    "onFallback": () => {
                        root._activeDocServeId = 0;
                        const fallbackReq = root._activeDocReq;
                        root._activeDocReq = null;
                        root._startSingleShotDocOp(fallbackReq);
                    }
                });
                if (reqId > 0) {
                    root._activeDocServeId = reqId;
                } else {
                    root._activeDocReq = null;
                    root._startSingleShotDocOp(nextReq);
                }
            };
            // Pre-write external conflict check when expectedSha is present
            if (needsConflictProbe) {
                const probeArgs = ["read", "--vault", root.configuredVaultPath, "--path", String(nextReq.relPath)];
                const probeId = root._sendServeRequest(probeArgs, null, {
                    "onResult": (probePayload, probeOk) => {
                        root._activeDocServeId = 0;
                        if (probeOk && root._handlePreWriteConflict(nextReq, probePayload)) {
                            root._activeDocReq = null;
                            Qt.callLater(() => {
                                if (root._live)
                                    root._runNextDocOp();
                            });
                            return;
                        }
                        dispatchServeWrite();
                    },
                    "onFallback": () => {
                        root._activeDocServeId = 0;
                        const fallbackReq = root._activeDocReq;
                        root._activeDocReq = null;
                        if (fallbackReq) {
                            preWriteProbeProc.pendingReq = fallbackReq;
                            preWriteProbeProc.command = [root.binaryPath, "read", "--vault", root.configuredVaultPath, "--path", String(fallbackReq.relPath)];
                            preWriteProbeProc.running = true;
                        }
                    }
                });
                if (probeId > 0) {
                    root._activeDocServeId = probeId;
                    return;
                }
            }
            dispatchServeWrite();
            return;
        }
        if (needsConflictProbe) {
            preWriteProbeProc.pendingReq = nextReq;
            preWriteProbeProc.command = [root.binaryPath, "read", "--vault", root.configuredVaultPath, "--path", String(nextReq.relPath)];
            preWriteProbeProc.running = true;
            return;
        }
        root._startSingleShotDocOp(nextReq);
    }

    function _expandHome(p: string): string {
        const trimmed = String(p ?? "").trim();
        const home = String(Quickshell.env("HOME") ?? "").trim();
        if (home.length === 0)
            return trimmed;
        if (trimmed === "~")
            return home;
        if (trimmed.startsWith("~/"))
            return home + trimmed.substring(1);
        return trimmed;
    }

    function _toVaultRelativePath(pathOrRel: string): string {
        let raw = String(pathOrRel ?? "").trim();
        if (raw.length === 0)
            return "";
        if (raw.startsWith("file://"))
            raw = decodeURIComponent(raw.replace(/^file:\/\//, ""));
        const expandedRaw = root._expandHome(raw).replace(/\/+$/, "");
        const expandedVault = root._expandHome(root.configuredVaultPath).replace(/\/+$/, "");
        if (expandedVault.length > 0 && expandedRaw.startsWith(expandedVault + "/")) {
            return expandedRaw.substring(expandedVault.length + 1);
        }
        const rawVault = root.configuredVaultPath.replace(/\/+$/, "");
        if (rawVault.length > 0 && raw.startsWith(rawVault + "/")) {
            return raw.substring(rawVault.length + 1);
        }
        return raw;
    }

    function openNote(pathOrRel: string): bool {
        if (!root.vaultConfigured)
            return false;
        const rel = root._toVaultRelativePath(pathOrRel);
        if (rel.length === 0)
            return false;
        root.open();
        root.openFile(rel, true);
        return true;
    }

    function openExternalPath(absPath: string): bool {
        let raw = String(absPath ?? "").trim();
        if (raw.length === 0)
            return false;
        if (raw.startsWith("file://")) {
            const stripped = raw.replace(/^file:\/\//, "");
            try { raw = decodeURIComponent(stripped); } catch (_e) { raw = stripped; }
        }
        if (!root.vaultConfigured) {
            root.open();
            return false;
        }
        const expandedRaw = root._expandHome(raw).replace(/\/+$/, "");
        const expandedVault = root._expandHome(root.configuredVaultPath).replace(/\/+$/, "");
        if (expandedVault.length > 0 && expandedRaw.startsWith(expandedVault + "/")) {
            return root.openNote(expandedRaw);
        }
        // Outside vault: safely copy into 00_Capture/Inbox without overwriting existing files, then open in Nexus.
        root.open();
        if (!externalImportProc.running) {
            externalImportProc.command = [
                "/usr/bin/python3",
                "-c",
                "import os, pathlib, shutil, sys\n"
                + "src = pathlib.Path(sys.argv[1]).expanduser().resolve()\n"
                + "vault = pathlib.Path(sys.argv[2]).expanduser().resolve()\n"
                + "if not src.is_file() or not vault.is_dir(): sys.exit(1)\n"
                + "inbox = vault / '00_Capture' / 'Inbox'\n"
                + "inbox.mkdir(parents=True, exist_ok=True)\n"
                + "dst = inbox / src.name\n"
                + "i = 1\n"
                + "while dst.exists():\n"
                + "    dst = inbox / f'{src.stem} ({i}){src.suffix}'\n"
                + "    i += 1\n"
                + "shutil.copy2(src, dst)\n"
                + "print(dst.relative_to(vault).as_posix())\n",
                expandedRaw,
                expandedVault
            ];
            externalImportProc.running = true;
        }
        return true;
    }

    Process {
        id: externalImportProc
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const rel = String(text ?? "").trim();
                if (rel.length > 0) {
                    root.refreshVault();
                    root.openFile(rel, true);
                }
            }
        }
    }

    function openFile(relPath: string, recordHistory = true): void {
        const cleaned = String(relPath ?? "").trim();
        if (!root.vaultConfigured || cleaned.length === 0)
            return;
        const lower = cleaned.toLowerCase();
        if (lower === "homepage.md" || lower.endsWith("/homepage.md")) {
            root.openHomepage();
            return;
        }
        if (lower.endsWith(".base")) {
            root.currentPath = cleaned;
            if (lower.indexOf("book") !== -1) {
                root.openCollection("books");
            } else if (lower.indexOf("game") !== -1) {
                root.openCollection("games");
            } else if (lower.indexOf("food") !== -1 || lower.indexOf("recipe") !== -1) {
                root.openCollection("recipes");
            } else if (lower.indexOf("bodybuilding") !== -1 || lower.indexOf("exercise") !== -1) {
                root.openCollection("exercises");
            } else if (lower.indexOf("place") !== -1 || lower.indexOf("map.base") !== -1 || lower.indexOf("local.base") !== -1) {
                root.openCollection("places");
            } else if (lower.indexOf("contact") !== -1) {
                root.openCollection("contacts");
            } else if (lower.indexOf("finance") !== -1) {
                root.openCollection("finance");
            } else if (lower.indexOf("media_tracker") !== -1 || lower.indexOf("movie") !== -1 || lower.indexOf("tv") !== -1) {
                root.openCollection("movies");
            } else {
                root.openDatabaseView(cleaned);
            }
            return;
        }
        root._enqueueDocOp({
            "kind": "read",
            "relPath": cleaned,
            "recordHistory": Boolean(recordHistory),
            "useStdin": false,
            "args": [root.binaryPath, "read", "--vault", root.configuredVaultPath, "--path", cleaned]
        });
    }

    function followWikilink(target: string): void {
        const raw = String(target ?? "").trim();
        if (raw.length === 0)
            return;
        const pipeIdx = raw.indexOf("|");
        const hashIdx = raw.indexOf("#");
        let endIdx = raw.length;
        if (pipeIdx !== -1)
            endIdx = Math.min(endIdx, pipeIdx);
        if (hashIdx !== -1)
            endIdx = Math.min(endIdx, hashIdx);
        const cleanTarget = raw.substring(0, endIdx).trim();
        if (cleanTarget.length === 0)
            return;

        const lowerTarget = cleanTarget.replace(/\.md$/i, "").toLowerCase();
        // Look up in flatFiles first
        for (let i = 0; i < root.flatFiles.length; ++i) {
            const f = root.flatFiles[i];
            if (!f)
                continue;
            const relLower = String(f.relPath ?? "").toLowerCase();
            const relNoExt = relLower.replace(/\.md$/i, "");
            const stemLower = String(f.stem ?? "").toLowerCase();
            if (relLower === lowerTarget || relNoExt === lowerTarget || stemLower === lowerTarget) {
                root.openFile(f.relPath, true);
                return;
            }
        }
        // If not found in existing files, create the new note in the current note's folder or root
        let targetRel = cleanTarget;
        if (!targetRel.endsWith(".md") && targetRel.indexOf(".") === -1)
            targetRel += ".md";
        root.createNote(targetRel, cleanTarget, "standard");
    }

    function _currentHistoryMarker(): string {
        if (root.activeView === "homepage")
            return "__homepage__";
        if (root.activeView === "graph")
            return "__graph__";
        if (root.activeView === "collection")
            return "__collection__:" + root.activeCollection;
        return root.currentPath;
    }

    function _restoreHistoryMarker(marker: string): void {
        if (marker === "__homepage__") {
            root.openHomepage();
        } else if (marker === "__graph__") {
            root.openGraphView();
        } else if (marker.startsWith("__collection__:")) {
            root.openCollection(marker.substring("__collection__:".length));
        } else {
            root.openFile(marker, false);
        }
    }

    function navigateBack(): void {
        if (root.historyBack.length === 0)
            return;
        const backStack = root.historyBack.slice();
        const prevPath = backStack.pop();
        root.historyBack = backStack;
        const curMarker = root._currentHistoryMarker();
        if (curMarker.length > 0) {
            const fwd = root.historyForward.slice();
            fwd.push(curMarker);
            root.historyForward = fwd;
        }
        root._restoreHistoryMarker(prevPath);
    }

    function navigateForward(): void {
        if (root.historyForward.length === 0)
            return;
        const fwdStack = root.historyForward.slice();
        const nextPath = fwdStack.pop();
        root.historyForward = fwdStack;
        const curMarker = root._currentHistoryMarker();
        if (curMarker.length > 0) {
            const back = root.historyBack.slice();
            back.push(curMarker);
            root.historyBack = back;
        }
        root._restoreHistoryMarker(nextPath);
    }

    function pushDocUndo(relPath: string, prevContent: string, nextContent = undefined): void {
        const clean = String(relPath ?? root.currentPath ?? "").trim();
        if (!clean)
            return;
        const prev = String(prevContent ?? "");
        if (nextContent !== undefined && prev === String(nextContent))
            return;
        const uMap = Object.assign({}, root.docUndoStack ?? ({}));
        const stack = Array.isArray(uMap[clean]) ? uMap[clean].slice() : [];
        if (stack.length > 0 && stack[stack.length - 1] === prev)
            return;
        stack.push(prev);
        if (stack.length > 30)
            stack.shift();
        uMap[clean] = stack;
        root.docUndoStack = uMap;
        const rMap = Object.assign({}, root.docRedoStack ?? ({}));
        rMap[clean] = [];
        root.docRedoStack = rMap;
    }

    function canUndoDocument(relPath = ""): bool {
        const clean = String(relPath || root.currentPath || "").trim();
        const stack = clean ? root.docUndoStack?.[clean] : null;
        return Array.isArray(stack) && stack.length > 0;
    }

    function canRedoDocument(relPath = ""): bool {
        const clean = String(relPath || root.currentPath || "").trim();
        const stack = clean ? root.docRedoStack?.[clean] : null;
        return Array.isArray(stack) && stack.length > 0;
    }

    function undoDocument(): bool {
        const clean = String(root.currentPath ?? "").trim();
        if (!clean || !root.canUndoDocument(clean))
            return false;
        const uMap = Object.assign({}, root.docUndoStack ?? ({}));
        const stack = uMap[clean].slice();
        const prev = String(stack.pop());
        uMap[clean] = stack;
        root.docUndoStack = uMap;

        const rMap = Object.assign({}, root.docRedoStack ?? ({}));
        const redoStack = Array.isArray(rMap[clean]) ? rMap[clean].slice() : [];
        const curText = String(root.draftContent ?? root.currentDoc?.content ?? "");
        if (redoStack.length === 0 || redoStack[redoStack.length - 1] !== curText)
            redoStack.push(curText);
        if (redoStack.length > 30)
            redoStack.shift();
        rMap[clean] = redoStack;
        root.docRedoStack = rMap;

        root.draftContent = prev;
        root.isDirty = prev !== String(root.currentDoc?.content ?? "");
        if (root.editorMode !== "raw")
            root.saveCurrentNote(prev, true);
        root.vimStatusMessage = "Undo (" + stack.length + " steps remaining)";
        return true;
    }

    function redoDocument(): bool {
        const clean = String(root.currentPath ?? "").trim();
        if (!clean || !root.canRedoDocument(clean))
            return false;
        const rMap = Object.assign({}, root.docRedoStack ?? ({}));
        const redoStack = rMap[clean].slice();
        const nextVal = String(redoStack.pop());
        rMap[clean] = redoStack;
        root.docRedoStack = rMap;

        const uMap = Object.assign({}, root.docUndoStack ?? ({}));
        const stack = Array.isArray(uMap[clean]) ? uMap[clean].slice() : [];
        const curText = String(root.draftContent ?? root.currentDoc?.content ?? "");
        if (stack.length === 0 || stack[stack.length - 1] !== curText)
            stack.push(curText);
        if (stack.length > 30)
            stack.shift();
        uMap[clean] = stack;
        root.docUndoStack = uMap;

        root.draftContent = nextVal;
        root.isDirty = nextVal !== String(root.currentDoc?.content ?? "");
        if (root.editorMode !== "raw")
            root.saveCurrentNote(nextVal, true);
        root.vimStatusMessage = "Redo (" + redoStack.length + " remaining)";
        return true;
    }

    function checkExternalModification(): void {
        if (!root._live || !root.vaultConfigured || root.currentPath.length === 0)
            return;
        if (!root.currentDoc || String(root.currentDoc.relPath ?? "") !== root.currentPath)
            return;
        const cat = String(root.currentDoc.category ?? "markdown");
        if (cat === "pdf" || cat === "image" || cat === "external")
            return;
        if (root._loadedDocPath !== root.currentPath || (root._loadedDocSha.length === 0 && root._loadedDocMtime <= 0))
            return;
        const targetPath = root.currentPath;
        const expectedSha = root._loadedDocSha;
        const expectedMtime = root._loadedDocMtime;
        const handleProbe = (payload) => {
            if (!root._live || !payload || !payload.ok || root.currentPath !== targetPath)
                return;
            const diskSha = String(payload.sha256 ?? "");
            const diskMtime = Number(payload.mtimeSecs ?? 0);
            const changed = (expectedSha.length > 0 && diskSha.length > 0)
                ? (diskSha !== expectedSha)
                : (expectedMtime > 0 && diskMtime > 0 && diskMtime !== expectedMtime);
            if (changed) {
                root.externalConflictDetected = true;
                root.externalConflictPath = targetPath;
                root.externalConflictDiskContent = String(payload.content ?? "");
                root.externalConflictDiskSha = diskSha;
                root.externalConflictDiskMtime = diskMtime;
            }
        };
        const cliArgs = ["read", "--vault", root.configuredVaultPath, "--path", targetPath];
        if (root._canUseServe()) {
            const reqId = root._sendServeRequest(cliArgs, null, {
                "onResult": (payload, ok) => {
                    if (root._conflictCheckServeId === reqId)
                        root._conflictCheckServeId = 0;
                    if (ok)
                        handleProbe(payload);
                },
                "onFallback": () => {
                    if (root._conflictCheckServeId === reqId)
                        root._conflictCheckServeId = 0;
                }
            });
            if (reqId > 0) {
                root._conflictCheckServeId = reqId;
                return;
            }
        }
        if (!conflictCheckProc.running) {
            conflictCheckProc.targetPath = targetPath;
            conflictCheckProc.expectedSha = expectedSha;
            conflictCheckProc.expectedMtime = expectedMtime;
            conflictCheckProc.command = [root.binaryPath].concat(cliArgs);
            conflictCheckProc.running = true;
        }
    }

    function resolveExternalConflictReload(): void {
        const target = root.externalConflictPath || root.currentPath;
        root.externalConflictDetected = false;
        root.externalConflictPath = "";
        root.externalConflictDiskContent = "";
        root.externalConflictDiskSha = "";
        root.externalConflictDiskMtime = 0;
        if (target.length > 0)
            root.openFile(target, false);
    }

    function resolveExternalConflictKeep(saveNow = true): void {
        if (root.externalConflictDiskSha.length > 0)
            root._loadedDocSha = root.externalConflictDiskSha;
        if (root.externalConflictDiskMtime > 0)
            root._loadedDocMtime = root.externalConflictDiskMtime;
        root.externalConflictDetected = false;
        root.externalConflictPath = "";
        root.externalConflictDiskContent = "";
        root.externalConflictDiskSha = "";
        root.externalConflictDiskMtime = 0;
        if (saveNow && root.currentPath.length > 0)
            root.saveCurrentNote(root.draftContent, false, true);
    }

    function saveCurrentNote(newContent = null, skipSnapshot = false, forceOverwrite = false): void {
        if (!root.vaultConfigured || root.currentPath.length === 0)
            return;
        const body = newContent !== null ? String(newContent) : root.draftContent;
        if (!forceOverwrite && root.externalConflictDetected && root.externalConflictPath === root.currentPath) {
            root.draftContent = body;
            root.isDirty = true;
            root.vimStatusMessage = "External file change detected — Reload or Keep & Save";
            return;
        }
        const prevOnDisk = String(root.currentDoc?.content ?? "");
        if (!skipSnapshot)
            root.pushDocUndo(root.currentPath, prevOnDisk, body);
        root.draftContent = body;
        root._rescanAfterDoc = false;
        if (!skipSnapshot && root._live && root.currentDoc
                && String(root.currentDoc.relPath ?? "") === root.currentPath
                && prevOnDisk !== body
                && String(root.currentDoc.category ?? "markdown") !== "pdf"
                && Quickshell.env("ALIS_NEXUS_DISABLE_SNAPSHOT") !== "1"
                && Quickshell.env("ALIS_NEXUS_HEADLESS_SERVICE_ONLY") !== "1") {
            root._enqueueDocOp({
                "kind": "history-snapshot",
                "relPath": root.currentPath,
                "recordHistory": false,
                "useStdin": false,
                "args": [root.binaryPath, "history-snapshot", "--vault", root.configuredVaultPath, "--path", root.currentPath, "--label", "Auto-save snapshot"]
            });
        }
        const docCategory = String(root.currentDoc?.category ?? "markdown");
        const expectedSha = (!forceOverwrite && !skipSnapshot
                && root._loadedDocPath === root.currentPath
                && root._loadedDocSha.length > 0
                && docCategory !== "pdf" && docCategory !== "canvas")
            ? root._loadedDocSha : "";
        root._enqueueDocOp({
            "kind": "write",
            "relPath": root.currentPath,
            "recordHistory": false,
            "useStdin": true,
            "stdinPayload": body,
            "expectedSha": expectedSha,
            "args": [root.binaryPath, "write", "--vault", root.configuredVaultPath, "--path", root.currentPath]
        });
    }

    function fetchHoverPreview(targetWikilink: string): void {
        const clean = String(targetWikilink ?? "").trim();
        if (!root.vaultConfigured || clean.length === 0) {
            root.hoverPreviewData = null;
            root.hoverPreviewLoading = false;
            return;
        }
        if (root.hoverPreviewCache && root.hoverPreviewCache[clean]) {
            root.hoverPreviewData = root.hoverPreviewCache[clean];
            root.hoverPreviewLoading = false;
            return;
        }
        root._pendingPreviewTarget = clean;
        root.hoverPreviewLoading = true;
        if (previewProc.running)
            return;
        root._startPendingPreview();
    }

    function _startPendingPreview(): void {
        const target = String(root._pendingPreviewTarget ?? "").trim();
        root._pendingPreviewTarget = "";
        if (!target || !root.vaultConfigured) {
            root.hoverPreviewLoading = false;
            return;
        }
        if (root.hoverPreviewCache && root.hoverPreviewCache[target]) {
            root.hoverPreviewData = root.hoverPreviewCache[target];
            root.hoverPreviewLoading = false;
            return;
        }
        previewProc.targetKey = target;
        previewProc.command = [root.binaryPath, "preview", "--vault", root.configuredVaultPath, "--target", target];
        previewProc.running = true;
        previewTimeout.restart();
    }

    function clearHoverPreview(): void {
        root._pendingPreviewTarget = "";
        root.hoverPreviewData = null;
        root.hoverPreviewLoading = false;
    }

    function runDatabaseQuery(querySpec): void {
        if (!root.vaultConfigured)
            return;
        const spec = querySpec && typeof querySpec === "object" ? querySpec : ({});
        const args = [root.binaryPath, "query", "--vault", root.configuredVaultPath];
        if (spec.folder && String(spec.folder).trim().length > 0) {
            args.push("--folder");
            args.push(String(spec.folder).trim());
        }
        if (spec.tag && String(spec.tag).trim().length > 0) {
            args.push("--tag");
            args.push(String(spec.tag).trim());
        }
        if (Array.isArray(spec.whereFilters)) {
            for (let i = 0; i < spec.whereFilters.length; ++i) {
                const w = String(spec.whereFilters[i] ?? "").trim();
                if (w.length > 0) {
                    args.push("--where");
                    args.push(w);
                }
            }
        }
        if (spec.sort && String(spec.sort).trim().length > 0) {
            args.push("--sort");
            args.push(String(spec.sort).trim());
        }
        if (spec.groupBy && String(spec.groupBy).trim().length > 0) {
            args.push("--group-by");
            args.push(String(spec.groupBy).trim());
        }
        if (spec.limit && Number(spec.limit) > 0) {
            args.push("--limit");
            args.push(String(Math.round(Number(spec.limit))));
        }
        root.queryLoading = true;
        if (queryProc.running)
            queryProc.running = false;
        queryProc.command = args;
        queryProc.running = true;
        queryTimeout.restart();
    }

    function saveDatabaseView(viewObj): void {
        if (!viewObj || !viewObj.name)
            return;
        const name = String(viewObj.name).trim();
        if (!name)
            return;
        const list = (Array.isArray(root.savedDatabaseViews) ? root.savedDatabaseViews : []).filter(v => String(v?.name ?? "") !== name);
        list.unshift(Object.assign({}, viewObj, { "name": name }));
        root.savedDatabaseViews = list.slice(0, 24);
        root._saveWorkspacePrefs();
        root.vimStatusMessage = "Saved view: " + name;
    }

    function deleteDatabaseView(name: string): void {
        const clean = String(name ?? "").trim();
        root.savedDatabaseViews = (Array.isArray(root.savedDatabaseViews) ? root.savedDatabaseViews : []).filter(v => String(v?.name ?? "") !== clean);
        root._saveWorkspacePrefs();
    }

    function setLocalGraphDepth(depth: int): void {
        const clamped = Math.max(1, Math.min(3, Math.round(Number(depth) || 1)));
        if (root.localGraphDepth !== clamped) {
            root.localGraphDepth = clamped;
            root._saveWorkspacePrefs();
        }
    }

    function saveGraphPreset(presetObj): void {
        if (!presetObj || !presetObj.name)
            return;
        const name = String(presetObj.name).trim();
        if (!name)
            return;
        const list = (Array.isArray(root.savedGraphPresets) ? root.savedGraphPresets : []).filter(p => String(p?.name ?? "") !== name);
        list.unshift(Object.assign({}, presetObj, { "name": name }));
        root.savedGraphPresets = list.slice(0, 16);
        root._saveWorkspacePrefs();
        root.vimStatusMessage = "Saved graph preset: " + name;
    }

    function deleteGraphPreset(name: string): void {
        const clean = String(name ?? "").trim();
        root.savedGraphPresets = (Array.isArray(root.savedGraphPresets) ? root.savedGraphPresets : []).filter(p => String(p?.name ?? "") !== clean);
        root._saveWorkspacePrefs();
    }

    function saveSupertagSchema(tagName: string, fieldsArray): void {
        const key = String(tagName ?? "").trim().replace(/^#+/, "").toLowerCase();
        if (!key)
            return;
        const next = Object.assign({}, root.supertagSchemas ?? ({}));
        next[key] = Array.isArray(fieldsArray) ? fieldsArray.slice() : [];
        root.supertagSchemas = next;
        root._saveWorkspacePrefs();
        root.vimStatusMessage = "Updated schema for #" + key;
    }

    function applySupertag(relPath: string, tagName: string): bool {
        const target = String(relPath ?? root.currentPath ?? "").trim();
        const tag = String(tagName ?? "").trim().replace(/^#+/, "");
        if (!root.vaultConfigured || !target || !tag)
            return false;
        const schema = root.supertagSchemas?.[tag.toLowerCase()] ?? [];
        const docFm = root.currentDoc?.frontmatter ?? ({});
        const existingTags = Array.isArray(docFm.tags) ? docFm.tags.slice() : [];
        const updates = {};
        if (!existingTags.some(t => String(t).replace(/^#+/, "").toLowerCase() === tag.toLowerCase()))
            existingTags.push(tag);
        updates["tags"] = existingTags;
        if (Array.isArray(schema)) {
            for (let i = 0; i < schema.length; ++i) {
                const f = schema[i];
                if (f && f.key && docFm[f.key] === undefined)
                    updates[f.key] = f.defaultVal !== undefined ? String(f.defaultVal) : "";
            }
        }
        return root.setFrontmatter(target, updates);
    }

    function pasteClipboardImage(fromFile = ""): void {
        if (!root.vaultConfigured)
            return;
        const args = ["python3", root.assetHelperPath, "paste-image", "--vault", root.configuredVaultPath];
        const dispatchPath = String(Quickshell.shellPath("scripts/native-dispatch") ?? "").trim();
        if (dispatchPath.length > 0) {
            args.push("--native-dispatch");
            args.push(dispatchPath);
        }
        if (root.currentPath.length > 0) {
            args.push("--current-rel");
            args.push(root.currentPath);
        }
        if (fromFile && String(fromFile).trim().length > 0) {
            args.push("--from-file");
            args.push(String(fromFile).trim());
        }
        if (assetProc.running)
            assetProc.running = false;
        assetProc.command = args;
        assetProc.running = true;
        assetTimeout.restart();
    }

    function openHistoryModal(): void {
        if (!root.vaultConfigured || root.currentPath.length === 0)
            return;
        root.historyModalOpen = true;
        root.loadNoteHistory(root.currentPath);
    }

    function snapshotCurrentNote(label = "Manual snapshot"): void {
        const target = String(root.currentPath ?? "").trim();
        if (!root.vaultConfigured || !target)
            return;
        root.historyLoading = true;
        if (historyProc.running)
            historyProc.running = false;
        historyProc.opKind = "snapshot";
        historyProc.targetPath = target;
        historyProc.command = [root.binaryPath, "history-snapshot", "--vault", root.configuredVaultPath, "--path", target, "--label", String(label || "Manual snapshot")];
        historyProc.running = true;
        historyTimeout.restart();
    }

    function loadNoteHistory(relPath = ""): void {
        const target = String(relPath || root.currentPath || "").trim();
        if (!root.vaultConfigured || !target)
            return;
        root.historyLoading = true;
        root.historyRevisions = [];
        root.historySelectedRevId = "";
        root.historyDiffText = "";
        if (historyProc.running)
            historyProc.running = false;
        historyProc.opKind = "list";
        historyProc.targetPath = target;
        historyProc.command = [root.binaryPath, "history-list", "--vault", root.configuredVaultPath, "--path", target];
        historyProc.running = true;
        historyTimeout.restart();
    }

    function diffNoteRevision(revId: string, relPath = ""): void {
        const target = String(relPath || root.currentPath || "").trim();
        const rev = String(revId ?? "").trim();
        if (!root.vaultConfigured || !target || !rev)
            return;
        root.historySelectedRevId = rev;
        root.historyLoading = true;
        if (historyProc.running)
            historyProc.running = false;
        historyProc.opKind = "diff";
        historyProc.targetPath = target;
        historyProc.command = [root.binaryPath, "history-diff", "--vault", root.configuredVaultPath, "--path", target, "--rev", rev];
        historyProc.running = true;
        historyTimeout.restart();
    }

    function restoreNoteRevision(revId: string, relPath = ""): void {
        const target = String(relPath || root.currentPath || "").trim();
        const rev = String(revId ?? "").trim();
        if (!root.vaultConfigured || !target || !rev)
            return;
        root.historyLoading = true;
        if (historyProc.running)
            historyProc.running = false;
        historyProc.opKind = "restore";
        historyProc.targetPath = target;
        historyProc.command = [root.binaryPath, "history-restore", "--vault", root.configuredVaultPath, "--path", target, "--rev", rev];
        historyProc.running = true;
        historyTimeout.restart();
    }

    function pdfLoadInfo(absPath: string): void {
        const clean = String(absPath ?? "").trim();
        if (!clean)
            return;
        root.pdfLastTarget = clean;
        root.pdfInfo = null;
        root.pdfPageImageUrl = "";
        root.pdfExtractedText = "";
        root.pdfCurrentPage = 1;
        root.pdfBusy = true;
        if (pdfProc.running)
            pdfProc.running = false;
        pdfProc.opKind = "info";
        pdfProc.command = ["python3", root.pdfHelperPath, "info", "--pdf", clean];
        pdfProc.running = true;
        pdfTimeout.restart();
    }

    function pdfLoadPage(page = 1, dpi = -1): void {
        const target = String(root.pdfLastTarget || root.currentDoc?.absPath || "").trim();
        if (!target)
            return;
        const maxPages = Math.max(1, Number(root.pdfInfo?.pages ?? 9999));
        const p = Math.max(1, Math.min(maxPages, Math.round(Number(page) || 1)));
        const d = dpi > 0 ? Math.max(72, Math.min(288, Math.round(Number(dpi)))) : root.pdfDpi;
        root.pdfCurrentPage = p;
        root.pdfDpi = d;
        root.pdfBusy = true;
        if (pdfProc.running)
            pdfProc.running = false;
        pdfProc.opKind = "render";
        pdfProc.command = ["python3", root.pdfHelperPath, "render", "--pdf", target, "--page", String(p), "--dpi", String(d)];
        pdfProc.running = true;
        pdfTimeout.restart();
    }

    function pdfExtractPageText(page = -1): void {
        const target = String(root.pdfLastTarget || root.currentDoc?.absPath || "").trim();
        if (!target)
            return;
        const p = page > 0 ? Math.round(Number(page)) : root.pdfCurrentPage;
        if (pdfTextProc.running)
            pdfTextProc.running = false;
        pdfTextProc._requestTarget = target;
        pdfTextProc._requestPage = p;
        pdfTextProc.command = ["python3", root.pdfHelperPath, "extract-text", "--pdf", target, "--page", String(p)];
        pdfTextProc.running = true;
        pdfTextTimeout.restart();
    }

    function capturePdfHighlight(quoteText: string, noteRelPath = "", page = -1): void {
        const pdfRel = String(root.currentPath ?? root.currentDoc?.relPath ?? "").trim();
        const quote = String(quoteText ?? "").trim();
        if (!root.vaultConfigured || !pdfRel || !quote)
            return;
        const p = page > 0 ? Math.round(Number(page)) : root.pdfCurrentPage;
        root.pdfBusy = true;
        if (pdfProc.running)
            pdfProc.running = false;
        pdfProc.opKind = "capture-highlight";
        const args = ["python3", root.pdfHelperPath, "capture-highlight", "--vault", root.configuredVaultPath, "--pdf-rel", pdfRel, "--page", String(p), "--quote", quote];
        if (noteRelPath && String(noteRelPath).trim().length > 0) {
            args.push("--note-rel");
            args.push(String(noteRelPath).trim());
        }
        pdfProc.command = args;
        pdfProc.running = true;
        pdfTimeout.restart();
    }

    function createNote(relPath: string, title = "", template = "standard"): void {
        const cleaned = String(relPath ?? "").trim();
        if (!root.vaultConfigured || cleaned.length === 0)
            return;
        root._rescanAfterDoc = true;
        const args = [root.binaryPath, "create", "--vault", root.configuredVaultPath, "--path", cleaned, "--template", template];
        if (String(title).trim().length > 0) {
            args.push("--title");
            args.push(String(title).trim());
        }
        root._enqueueDocOp({
            "kind": "create",
            "relPath": cleaned,
            "recordHistory": true,
            "useStdin": false,
            "args": args
        });
    }

    function inferFolderForKind(kind: string): string {
        const k = String(kind ?? "standard").trim().toLowerCase();
        const defaults = {
            "movie": { col: "movies", dir: "20_Personal_Life/25_Media_Tracker/Movies" },
            "movies": { col: "movies", dir: "20_Personal_Life/25_Media_Tracker/Movies" },
            "tv": { col: "tvseries", dir: "20_Personal_Life/25_Media_Tracker/TV_Series" },
            "tvseries": { col: "tvseries", dir: "20_Personal_Life/25_Media_Tracker/TV_Series" },
            "game": { col: "games", dir: "20_Personal_Life/27_Game_Tracker/Games" },
            "games": { col: "games", dir: "20_Personal_Life/27_Game_Tracker/Games" },
            "book": { col: "books", dir: "20_Personal_Life/24_Book_Tracker/Books" },
            "books": { col: "books", dir: "20_Personal_Life/24_Book_Tracker/Books" },
            "recipe": { col: "recipes", dir: "20_Personal_Life/26_Food_&_Drinks/Recipes" },
            "recipes": { col: "recipes", dir: "20_Personal_Life/26_Food_&_Drinks/Recipes" },
            "place": { col: "places", dir: "20_Personal_Life/23_Places/Tourist" },
            "places": { col: "places", dir: "20_Personal_Life/23_Places/Tourist" },
            "exercise": { col: "exercises", dir: "20_Personal_Life/33_Bodybuilding/Gym_n_Calisthenics_Exercises" },
            "exercises": { col: "exercises", dir: "20_Personal_Life/33_Bodybuilding/Gym_n_Calisthenics_Exercises" },
            "clipping": { col: "clippings", dir: "00_Capture/09_Clippings" },
            "clippings": { col: "clippings", dir: "00_Capture/09_Clippings" },
            "website": { col: "websites", dir: "70_Interests_&_Research/78_Onion_Sites/OTH" },
            "websites": { col: "websites", dir: "70_Interests_&_Research/78_Onion_Sites/OTH" },
            "cornell": { col: "cornell", dir: "00_Capture/02_Cornell" },
            "contact": { col: "contacts", dir: "20_Personal_Life/29_Contact" },
            "contacts": { col: "contacts", dir: "20_Personal_Life/29_Contact" },
            "finance": { col: "finance", dir: "30_Resources/32_Finance" },
            "zettelkasten": { col: "zettelkasten", dir: String(Config.options?.notes?.zettelkasten?.folder ?? "00_Capture/03_Zettelkasten") },
            "journal": { col: "", dir: root.dailyFolder },
            "daily": { col: "", dir: root.dailyFolder }
        };
        const spec = defaults[k];
        if (spec && spec.col.length > 0) {
            const items = Array.isArray(root.collections?.[spec.col]) ? root.collections[spec.col] : [];
            if (items.length > 0) {
                const counts = {};
                let bestDir = "";
                let bestCount = 0;
                for (let i = 0; i < items.length; ++i) {
                    const rel = String(items[i]?.relPath ?? "").trim();
                    const slash = rel.lastIndexOf("/");
                    const dir = slash !== -1 ? rel.slice(0, slash) : "";
                    if (dir.length === 0)
                        continue;
                    counts[dir] = (counts[dir] || 0) + 1;
                    if (counts[dir] > bestCount) {
                        bestCount = counts[dir];
                        bestDir = dir;
                    }
                }
                if (bestDir.length > 0)
                    return bestDir;
            }
            return spec.dir;
        }
        if (spec)
            return spec.dir;
        if (root.currentPath.length > 0 && root.activeView === "document") {
            const slash = root.currentPath.lastIndexOf("/");
            if (slash !== -1)
                return root.currentPath.slice(0, slash);
        }
        const existingFolders = {};
        root._collectFolderPaths(root.tree, existingFolders);
        if (existingFolders["00_Capture"])
            return "00_Capture";
        return "";
    }

    function isApiBackedKind(kind: string): bool {
        const k = String(kind ?? "").trim().toLowerCase();
        return k === "movie" || k === "movies" || k === "tv" || k === "tvseries"
            || k === "book" || k === "books" || k === "game" || k === "games"
            || k === "recipe" || k === "recipes" || k === "place" || k === "places";
    }

    function openNewNoteModal(kind = "standard", customFolder = ""): void {
        const kRaw = String(kind ?? "standard").trim().toLowerCase() || "standard";
        const normalized = (kRaw === "movies") ? "movie"
            : (kRaw === "tvseries" || kRaw === "tv-series" || kRaw === "series") ? "tv"
            : (kRaw === "books") ? "book"
            : (kRaw === "games") ? "game"
            : (kRaw === "recipes") ? "recipe"
            : (kRaw === "places") ? "place"
            : (kRaw === "exercises") ? "exercise"
            : (kRaw === "contacts") ? "contact"
            : (kRaw === "websites" || kRaw === "web-sites") ? "website"
            : (kRaw === "clippings") ? "clipping"
            : (kRaw === "zk") ? "zettelkasten"
            : (kRaw === "daily") ? "journal"
            : kRaw;
        root.newNoteModalKind = normalized;
        const cleanFolder = String(customFolder ?? "").trim().replace(/^\/+|\/+$/g, "");
        root.newNoteModalFolder = cleanFolder.length > 0 ? cleanFolder : root.inferFolderForKind(normalized);
        root.searchApiResults = [];
        root.searchApiLoading = false;
        root._searchApiGeneration += 1;
        root.newNoteModalOpen = true;
    }

    function closeNewNoteModal(): void {
        root.newNoteModalOpen = false;
        root.searchApiLoading = false;
        root._pendingApiSearch = null;
        if (apiSearchProc.running)
            apiSearchProc.running = false;
    }

    function _startApiSearchReq(req): void {
        if (!req)
            return;
        apiSearchProc.request = req;
        apiSearchProc.response = "";
        apiSearchProc.started = false;
        apiSearchProc.inFlight = true;
        apiSearchProc.command = req.args;
        apiSearchProc.running = true;
        apiSearchTimeout.restart();
    }

    function _startPendingApiSearch(): void {
        if (apiSearchProc.running || apiSearchProc.inFlight || !root._pendingApiSearch)
            return;
        const req = root._pendingApiSearch;
        root._pendingApiSearch = null;
        root._startApiSearchReq(req);
    }

    function searchExternalApi(kind: string, query: string): bool {
        const kRaw = String(kind ?? "").trim().toLowerCase();
        const k = (kRaw === "movies") ? "movie"
            : (kRaw === "tvseries" || kRaw === "tv-series" || kRaw === "series") ? "tv"
            : (kRaw === "books") ? "book"
            : (kRaw === "games") ? "game"
            : (kRaw === "recipes") ? "recipe"
            : (kRaw === "places") ? "place"
            : kRaw;
        const q = String(query ?? "").trim();
        root._searchApiGeneration += 1;
        const gen = root._searchApiGeneration;
        if (!["movie", "tv", "book", "game", "recipe", "place"].includes(k) || q.length < 2) {
            root.searchApiResults = [];
            root.searchApiLoading = false;
            root._pendingApiSearch = null;
            if (apiSearchProc.running)
                apiSearchProc.running = false;
            return false;
        }
        root.searchApiLoading = true;
        const args = [root.binaryPath, "search-api", "--kind", k, "--query", q, "--limit", "8"];
        if (root.vaultConfigured) {
            args.push("--vault");
            args.push(root.configuredVaultPath);
        }
        const req = {
            "generation": gen,
            "kind": k,
            "query": q,
            "args": args
        };
        if (apiSearchProc.running || apiSearchProc.inFlight) {
            root._pendingApiSearch = req;
            if (apiSearchProc.running)
                apiSearchProc.running = false;
            return true;
        }
        root._startApiSearchReq(req);
        return true;
    }

    function _dedupeNewNotePath(folderClean: string, baseTitle: string): string {
        const safeName = String(baseTitle ?? "Untitled").replace(/[\/\\:*?"<>|]+/g, "-").trim() || "Untitled";
        const existingSet = {};
        const files = Array.isArray(root.flatFiles) ? root.flatFiles : [];
        for (let i = 0; i < files.length; ++i)
            existingSet[String(files[i]?.relPath ?? "")] = true;
        let idx = 0;
        let relPath = "";
        while (idx < 250) {
            const stem = idx === 0 ? safeName : (safeName + " (" + String(idx + 1) + ")");
            relPath = folderClean.length > 0 ? (folderClean + "/" + stem + ".md") : (stem + ".md");
            if (!existingSet[relPath])
                return relPath;
            idx += 1;
        }
        return folderClean.length > 0 ? (folderClean + "/" + safeName + "-" + String(Date.now()) + ".md") : (safeName + "-" + String(Date.now()) + ".md");
    }

    function createNoteFromApiCandidate(kind: string, candidate, customFolder = ""): string {
        if (!root.vaultConfigured || !candidate || typeof candidate !== "object")
            return "";
        const rawTitle = String(candidate.title ?? "").trim();
        if (rawTitle.length === 0)
            return "";
        const kRaw = String(kind ?? "standard").trim().toLowerCase();
        const tpl = (kRaw === "movies" || kRaw === "movie") ? "movie"
            : (kRaw === "tv" || kRaw === "tvseries" || kRaw === "tv-series" || kRaw === "series") ? "tvseries"
            : (kRaw === "books" || kRaw === "book") ? "book"
            : (kRaw === "games" || kRaw === "game") ? "game"
            : (kRaw === "recipes" || kRaw === "recipe") ? "recipe"
            : (kRaw === "places" || kRaw === "place") ? "place"
            : kRaw;
        const folder = (String(customFolder ?? "").trim() || root.inferFolderForKind(tpl)).replace(/^\/+|\/+$/g, "");
        const relPath = root._dedupeNewNotePath(folder, rawTitle);
        root.closeNewNoteModal();
        root._rescanAfterDoc = true;
        root._enqueueDocOp({
            "kind": "create",
            "relPath": relPath,
            "recordHistory": true,
            "useStdin": false,
            "args": [
                root.binaryPath,
                "create",
                "--vault",
                root.configuredVaultPath,
                "--path",
                relPath,
                "--title",
                rawTitle,
                "--template",
                tpl,
                "--candidate-json",
                JSON.stringify(candidate)
            ]
        });
        return relPath;
    }

    function createManualModalNote(kind: string, rawTitle: string, customFolder = ""): bool {
        if (!root.vaultConfigured)
            return false;
        const kRaw = String(kind ?? "standard").trim().toLowerCase();
        if (kRaw === "journal" || kRaw === "daily") {
            root.closeNewNoteModal();
            root.openDailyNote();
            return true;
        }
        const cleanTitle = String(rawTitle ?? "").trim() || "Untitled";
        if (kRaw === "zettelkasten" || kRaw === "zk") {
            root.closeNewNoteModal();
            return root.captureZettelkastenNote(cleanTitle, "");
        }
        const tpl = (kRaw === "movies" || kRaw === "movie") ? "movie"
            : (kRaw === "tv" || kRaw === "tvseries" || kRaw === "tv-series" || kRaw === "series") ? "tvseries"
            : (kRaw === "books" || kRaw === "book") ? "book"
            : (kRaw === "games" || kRaw === "game") ? "game"
            : (kRaw === "recipes" || kRaw === "recipe") ? "recipe"
            : (kRaw === "places" || kRaw === "place") ? "place"
            : (kRaw === "exercises" || kRaw === "exercise") ? "exercise"
            : (kRaw === "contacts" || kRaw === "contact") ? "contact"
            : (kRaw === "websites" || kRaw === "web-sites" || kRaw === "website") ? "website"
            : (kRaw === "clippings" || kRaw === "clipping") ? "clipping"
            : kRaw;
        const folder = (String(customFolder ?? "").trim() || root.inferFolderForKind(tpl)).replace(/^\/+|\/+$/g, "");
        const relPath = root._dedupeNewNotePath(folder, cleanTitle);
        root.closeNewNoteModal();
        root.createNote(relPath, cleanTitle, tpl);
        return true;
    }

    function createCollectionEntry(collectionId: string, rawTitle: string): bool {
        const cleanTitle = String(rawTitle ?? "").trim();
        if (!root.vaultConfigured || cleanTitle.length === 0)
            return false;
        const safeName = cleanTitle.replace(/[\/\\:*?"<>|]+/g, "-").trim();
        if (safeName.length === 0)
            return false;
        const cid = root._normalizeCollectionId(collectionId);
        if (cid === "zettelkasten")
            return root.captureZettelkastenNote(cleanTitle, "");
        const tplMap = {
            "movies": "movie",
            "tvseries": "tvseries",
            "games": "game",
            "books": "book",
            "recipes": "recipe",
            "exercises": "exercise",
            "clippings": "clipping",
            "websites": "website",
            "cornell": "cornell",
            "places": "place",
            "contacts": "contact",
            "finance": "finance"
        };
        const tpl = tplMap[cid] ?? "standard";
        const folder = root.inferFolderForKind(cid || "standard").replace(/^\/+|\/+$/g, "") || "00_Capture";
        const relPath = root._dedupeNewNotePath(folder, cleanTitle);
        root.createNote(relPath, cleanTitle, tpl);
        return true;
    }

    function setFrontmatter(relPath: string, updatesObj): bool {
        const target = String(relPath ?? root.currentPath ?? "").trim();
        if (!root.vaultConfigured || target.length === 0 || !updatesObj || typeof updatesObj !== "object")
            return false;
        const keys = Object.keys(updatesObj);
        if (keys.length === 0)
            return false;
        if (target.toLowerCase().endsWith("settings.md")) {
            let nextGlobe = null;
            for (let gi = 0; gi < keys.length; ++gi) {
                const gk = keys[gi];
                if (gk.startsWith("globe_") || gk === "location_pins") {
                    if (!nextGlobe)
                        nextGlobe = Object.assign({}, root.globeSettings || {});
                    const gv = updatesObj[gk];
                    nextGlobe[gk] = (gv === undefined || gv === null) ? "" : String(gv);
                }
            }
            if (nextGlobe)
                root.globeSettings = nextGlobe;
        }
        // Publish Journal check-ins only from the successful write/readback
        // below, so failed or interrupted writes cannot persist an unsaved choice.
        const args = [
            root.binaryPath,
            "set-frontmatter",
            "--vault",
            root.configuredVaultPath,
            "--path",
            target,
            "--updates",
            JSON.stringify(updatesObj)
        ];
        root._rescanAfterDoc = true;
        root._enqueueDocOp({
            "kind": "set-frontmatter",
            "relPath": target,
            "recordHistory": false,
            "useStdin": false,
            "args": args
        });
        return true;
    }

    function syncNoteApi(relPath: string, apiKind: string): bool {
        const target = String(relPath ?? root.currentPath ?? "").trim();
        const kind = String(apiKind ?? "").trim();
        if (!root.vaultConfigured || target.length === 0 || kind.length === 0)
            return false;
        root.vimStatusMessage = "Syncing " + kind + " metadata for " + target + "…";
        root._rescanAfterDoc = true;
        root._enqueueDocOp({
            "kind": "sync-api",
            "relPath": target,
            "recordHistory": false,
            "useStdin": false,
            "args": [root.binaryPath, "sync-api", "--vault", root.configuredVaultPath, "--path", target, "--kind", kind]
        });
        return true;
    }

    function updateNoteFrontmatter(updatesObj, relPath = ""): bool {
        return root.setFrontmatter(String(relPath ?? "").trim() || root.currentPath, updatesObj);
    }

    function apiKindForNoteKind(noteKind: string): string {
        const nk = String(noteKind ?? "").trim().toLowerCase();
        if (nk === "movie" || nk === "movies")
            return "movie";
        if (nk === "tvseries" || nk === "tv" || nk === "tv-series" || nk === "series")
            return "tv";
        if (nk === "book" || nk === "books")
            return "book";
        if (nk === "game" || nk === "games")
            return "game";
        if (nk === "recipe" || nk === "recipes")
            return "recipe";
        if (nk === "place" || nk === "places")
            return "place";
        if (nk === "journal" || nk === "daily" || nk === "weather")
            return "weather";
        return "";
    }

    function syncNoteMetadataByKind(relPath: string, rawKind: string): bool {
        const target = String(relPath ?? root.currentPath ?? "").trim();
        let resolvedKind = root.apiKindForNoteKind(rawKind);
        if (!resolvedKind && target.length > 0) {
            const files = Array.isArray(root.flatFiles) ? root.flatFiles : [];
            for (let i = 0; i < files.length; ++i) {
                if (String(files[i]?.relPath ?? "") === target) {
                    resolvedKind = root.apiKindForNoteKind(String(files[i]?.noteKind ?? ""));
                    break;
                }
            }
        }
        if (!resolvedKind)
            return false;
        return root.syncNoteApi(target, resolvedKind);
    }

    function fetchMediaMetadataForCurrentNote(): bool {
        const nk = String(root.currentDoc?.noteKind ?? "");
        const kind = root.apiKindForNoteKind(nk);
        if (kind.length === 0)
            return false;
        return root.syncNoteApi(root.currentPath, kind);
    }

    property bool _weatherSubscribed: false
    readonly property var hostWeatherData: (root.isOpen || root._weatherSubscribed || root._pendingWeatherSyncPath.length > 0)
        ? (HostServices.Weather?.data ?? null)
        : null
    readonly property bool hasAlisWeather: {
        const d = hostWeatherData;
        if (!d)
            return false;
        const t = String(d.temp ?? "").trim();
        return t.length > 0 && !t.startsWith("--") && t !== "0" && t !== "0°C" && t !== "0°F";
    }
    readonly property string alisWeatherSummary: {
        const d = hostWeatherData;
        if (!d || !hasAlisWeather)
            return "";
        const desc = String(d.description ?? d.wDesc ?? "").trim();
        const temp = String(d.temp ?? "").trim();
        const hum = String(d.humidity ?? "").trim();
        const parts = [];
        if (desc.length > 0)
            parts.push(desc);
        if (temp.length > 0)
            parts.push(temp);
        if (hum.length > 0 && hum !== "0%" && hum !== "0" && !hum.startsWith("--"))
            parts.push(hum + (hum.endsWith("%") ? " RH" : "% RH"));
        return parts.join(", ");
    }
    property string _pendingWeatherSyncPath: ""
    property var _autoSyncedWeatherPaths: ({})
    property var _weatherSyncInFlight: ({})

    function formatAlisWeatherSummary(): string {
        if (!root._weatherSubscribed)
            root._weatherSubscribed = true;
        const d = HostServices.Weather?.data;
        if (!d)
            return "";
        const temp = String(d.temp ?? "").trim();
        if (temp.length === 0 || temp.startsWith("--") || temp === "0" || temp === "0°C" || temp === "0°F")
            return "";
        const desc = String(d.description ?? d.wDesc ?? "").trim();
        const hum = String(d.humidity ?? "").trim();
        const parts = [];
        if (desc.length > 0)
            parts.push(desc);
        parts.push(temp);
        if (hum.length > 0 && hum !== "0%" && hum !== "0" && !hum.startsWith("--"))
            parts.push(hum + (hum.endsWith("%") ? " RH" : "% RH"));
        return parts.join(", ");
    }

    function _queueJournalWeather(target: string, summary: string, replaceExisting = false): bool {
        if (!root.vaultConfigured || target.length === 0 || summary.trim().length === 0)
            return false;
        if (!replaceExisting && Number(root._weatherSyncInFlight[target] ?? 0) > 0)
            return false;
        const pending = Object.assign({}, root._weatherSyncInFlight);
        pending[target] = Number(pending[target] ?? 0) + 1;
        root._weatherSyncInFlight = pending;
        const args = [root.binaryPath, "journal-weather", "--vault", root.configuredVaultPath, "--path", target, "--summary", summary];
        if (replaceExisting)
            args.push("--replace");
        root._enqueueDocOp({ "kind": "journal-weather", "relPath": target, "recordHistory": false, "useStdin": false, "args": args });
        return true;
    }

    function _syncAvailableJournalWeather(target: string): bool {
        if (target !== root.currentPath || String(root.currentDoc?.relPath ?? "") !== target
                || String(root.currentDoc?.noteKind ?? "") !== "journal" || root.isDirty)
            return false;
        if (String(root.currentDoc?.journalView?.weather ?? "").trim().length > 0)
            return false;
        return root._queueJournalWeather(target, root.alisWeatherSummary);
    }

    onAlisWeatherSummaryChanged: {
        if (root._pendingWeatherSyncPath.length > 0 && root._pendingWeatherSyncPath !== root.currentPath)
            root._pendingWeatherSyncPath = "";
        if (root._pendingWeatherSyncPath === root.currentPath && root.currentPath.length > 0) {
            if (root._queueJournalWeather(root.currentPath, root.alisWeatherSummary, true))
                root._pendingWeatherSyncPath = "";
        } else {
            root._syncAvailableJournalWeather(root.currentPath);
        }
    }

    function fetchWeatherForCurrentJournal(): bool {
        const target = String(root.currentPath ?? "").trim();
        if (!root.vaultConfigured || target.length === 0)
            return false;
        const summary = root.formatAlisWeatherSummary();
        if (summary.length > 0) {
            root.vimStatusMessage = "Weather synced from Alis Weather: " + summary;
            return root._queueJournalWeather(target, summary, true);
        }
        root._pendingWeatherSyncPath = target;
        if (typeof HostServices.Weather?.getData === "function")
            HostServices.Weather.getData();
        return root.syncNoteApi(target, "weather");
    }

    function openOrCreateJournalByDate(dateIso: string): void {
        root.openDailyNote(dateIso);
    }

    function saveJournalDailyLog(newLogText: string): void {
        if (!root.currentDoc || !root.currentDoc.journalView)
            return;
        const startLine = Number(root.currentDoc.journalView.dailyLogLineStart ?? 1);
        const endLine = Number(root.currentDoc.journalView.dailyLogLineEnd ?? startLine);
        const cleaned = String(newLogText ?? "")
            .replace(/^\s*#{1,6}\s*(?:Notes\s*(?:&|and)\s*Log|Daily\s*Log)\s*(?:\r?\n|$)/i, "");
        root.updateBlockContent(startLine, Math.max(startLine, endLine), cleaned);
    }

    function getNoteBodyMarkdown(): string {
        if (!root.currentDoc)
            return "";
        const raw = String(root.currentDoc.content ?? root.draftContent ?? "").replace(/\r\n/g, "\n");
        const lines = raw.split("\n");
        const startIdx = Math.max(0, Number(root.currentDoc.bodyStartLine ?? 1) - 1);
        const filtered = [];
        for (let i = startIdx; i < lines.length; ++i) {
            const t = lines[i].trim();
            if (t.startsWith("![[") && t.indexOf("Custom_Views/") !== -1)
                continue;
            filtered.push(lines[i]);
        }
        return filtered.join("\n").replace(/^\n+/, "").replace(/\n+$/, "");
    }

    function saveNoteBodyMarkdown(newBodyText: string, targetRelPath = "", rawDocSnapshot = "", startLineSnapshot = -1): void {
        const destPath = String(targetRelPath ?? "").trim() || root.currentPath;
        if (!root.vaultConfigured || destPath.length === 0)
            return;
        if (destPath === root.currentPath && !root.currentDoc)
            return;
        const isCurrent = destPath === root.currentPath;
        const raw = isCurrent
            ? String(root.currentDoc.content ?? root.draftContent ?? "").replace(/\r\n/g, "\n")
            : String(rawDocSnapshot ?? "").replace(/\r\n/g, "\n");
        const lines = raw.split("\n");
        const startIdx = (!isCurrent && startLineSnapshot > 0)
            ? Math.max(0, startLineSnapshot - 1)
            : Math.max(0, Number((isCurrent ? root.currentDoc?.bodyStartLine : 1) ?? 1) - 1);
        const prefixLines = lines.slice(0, startIdx);
        // Preserve any Obsidian Custom_Views embed line at the top of the body
        for (let i = startIdx; i < lines.length; ++i) {
            const t = lines[i].trim();
            if (t.startsWith("![[") && t.indexOf("Custom_Views/") !== -1) {
                prefixLines.push("");
                prefixLines.push(lines[i]);
                break;
            }
        }
        const cleanBody = String(newBodyText ?? "").replace(/\r\n/g, "\n").trim();
        let combined = "";
        if (prefixLines.length > 0) {
            combined = prefixLines.join("\n") + (cleanBody.length > 0 ? ("\n\n" + cleanBody) : "\n");
        } else {
            combined = cleanBody;
        }
        if (!combined.endsWith("\n"))
            combined += "\n";
        if (isCurrent) {
            root.saveCurrentNote(combined);
            return;
        }
        root.pushDocUndo(destPath, raw, combined);
        root._rescanAfterDoc = false;
        if (root._live && raw !== combined
                && Quickshell.env("ALIS_NEXUS_DISABLE_SNAPSHOT") !== "1"
                && Quickshell.env("ALIS_NEXUS_HEADLESS_SERVICE_ONLY") !== "1") {
            root._enqueueDocOp({
                "kind": "history-snapshot",
                "relPath": destPath,
                "recordHistory": false,
                "useStdin": false,
                "args": [root.binaryPath, "history-snapshot", "--vault", root.configuredVaultPath, "--path", destPath, "--label", "Auto-save snapshot"]
            });
        }
        root._enqueueDocOp({
            "kind": "write",
            "relPath": destPath,
            "recordHistory": false,
            "useStdin": true,
            "stdinPayload": combined,
            "args": [root.binaryPath, "write", "--vault", root.configuredVaultPath, "--path", destPath]
        });
    }

    function saveRecipePersonalNotes(newNotesText: string): void {
        if (!root.vaultConfigured || root.currentPath.length === 0 || !root.currentDoc)
            return;
        const raw = String(root.currentDoc.content ?? root.draftContent ?? "").replace(/\r\n/g, "\n");
        const lines = raw.split("\n");
        const startIdx = Math.max(0, Number(root.currentDoc.bodyStartLine ?? 1) - 1);
        const nextNote = String(newNotesText ?? "").replace(/\r\n/g, "\n").trim();

        let pnHeadingIdx = -1;
        let pnEndIdx = lines.length;
        for (let i = startIdx; i < lines.length; ++i) {
            const t = lines[i].trim();
            if (t.startsWith("## ")) {
                const h = t.replace(/^#+\s*/, "").trim().toLowerCase();
                if (h === "personal notes" || h === "personal note" || h === "notes") {
                    pnHeadingIdx = i;
                    continue;
                } else if (pnHeadingIdx !== -1) {
                    pnEndIdx = i;
                    break;
                }
            }
        }

        let updatedLines = [];
        if (pnHeadingIdx !== -1) {
            updatedLines = lines.slice(0, pnHeadingIdx + 1);
            updatedLines.push("");
            if (nextNote.length > 0)
                updatedLines.push(nextNote);
            if (pnEndIdx < lines.length) {
                updatedLines.push("");
                updatedLines = updatedLines.concat(lines.slice(pnEndIdx));
            }
        } else {
            updatedLines = lines.slice();
            while (updatedLines.length > 0 && updatedLines[updatedLines.length - 1].trim() === "")
                updatedLines.pop();
            updatedLines.push("");
            updatedLines.push("## Personal Notes");
            updatedLines.push("");
            if (nextNote.length > 0)
                updatedLines.push(nextNote);
        }
        let combined = updatedLines.join("\n");
        if (!combined.endsWith("\n"))
            combined += "\n";
        root.saveCurrentNote(combined);
    }

    function addFinanceRecord(recordType: string, title: string, amount: string, txType = "Expense", category = "General", account = "Bank"): bool {
        const cleanTitle = String(title ?? "").trim();
        if (!root.vaultConfigured || cleanTitle.length === 0)
            return false;
        const rType = String(recordType ?? "transaction").trim() || "transaction";
        const amt = String(amount ?? "0").trim() || "0";
        root._rescanAfterDoc = true;
        root._enqueueDocOp({
            "kind": "finance-add",
            "relPath": root.currentPath,
            "recordHistory": false,
            "useStdin": false,
            "args": [
                root.binaryPath,
                "finance-add",
                "--vault",
                root.configuredVaultPath,
                "--record-type",
                rType,
                "--title",
                cleanTitle,
                "--amount",
                amt,
                "--tx-type",
                String(txType ?? "Expense"),
                "--category",
                String(category ?? "General"),
                "--account",
                String(account ?? "Bank")
            ]
        });
        return true;
    }

    function openDailyNote(dateStr = ""): void {
        if (!root.vaultConfigured)
            return;
        const targetDate = String(dateStr ?? "").trim() || Qt.formatDate(new Date(), "yyyy-MM-dd");
        root.selectedDateStr = targetDate;
        root._rescanAfterDoc = true;
        root._enqueueDocOp({
            "kind": "daily",
            "relPath": "",
            "recordHistory": true,
            "useStdin": false,
            "args": [root.binaryPath, "daily", "--vault", root.configuredVaultPath, "--date", targetDate, "--folder", root.dailyFolder, "--format", root.dailyFormat]
        });
    }

    function toggleBlockTodo(line1Based: int): void {
        if (!root.vaultConfigured || root.currentPath.length === 0 || line1Based < 1)
            return;
        root._rescanAfterDoc = true;
        root._enqueueDocOp({
            "kind": "toggle-todo",
            "relPath": root.currentPath,
            "recordHistory": false,
            "useStdin": false,
            "args": [root.binaryPath, "toggle-todo", "--vault", root.configuredVaultPath, "--path", root.currentPath, "--line", String(line1Based)]
        });
    }

    function updateBlockContent(lineStart1Based: int, lineEnd1Based: int, replacement: string): void {
        if (!root.vaultConfigured || root.currentPath.length === 0 || lineStart1Based < 1)
            return;
        root.editingBlockId = -1;
        root._rescanAfterDoc = true;
        root._enqueueDocOp({
            "kind": "update-block",
            "relPath": root.currentPath,
            "recordHistory": false,
            "useStdin": false,
            "args": [root.binaryPath, "update-block", "--vault", root.configuredVaultPath, "--path", root.currentPath, "--start", String(lineStart1Based), "--end", String(Math.max(lineStart1Based, lineEnd1Based)), "--content", String(replacement)]
        });
    }

    function linkUnlinkedMention(sourceRelPath: string, line1Based: int, targetTitle: string): void {
        if (!root.vaultConfigured || !sourceRelPath || line1Based < 1 || !targetTitle)
            return;
        root._rescanAfterDoc = true;
        root._enqueueDocOp({
            "kind": "link-mention",
            "relPath": root.currentPath,
            "recordHistory": false,
            "useStdin": false,
            "args": [root.binaryPath, "link-mention", "--vault", root.configuredVaultPath, "--source", sourceRelPath, "--line", String(line1Based), "--target", targetTitle]
        });
    }

    function searchVault(query: string): void {
        root.searchQuery = String(query ?? "");
        const trimmed = root.searchQuery.trim();
        root._searchGeneration += 1;
        root._pendingSearch = root.vaultConfigured && trimmed.length > 0
            ? { "generation": root._searchGeneration, "vault": root.configuredVaultPath, "query": trimmed }
            : null;
        searchTimeout.stop();
        if (!root._pendingSearch)
            root.searchResults = [];
        if (searchProc.inFlight) {
            if (searchProc.running)
                searchProc.running = false;
            return;
        }
        root._startPendingSearch();
    }

    function _startPendingSearch(): void {
        if (searchProc.inFlight || root._searchServeInFlight || !root._pendingSearch)
            return;
        const request = root._pendingSearch;
        root._pendingSearch = null;
        const cliArgs = ["search", "--vault", request.vault, "--query", request.query];
        const runSingleShot = () => {
            if (!root._live || searchProc.inFlight)
                return;
            searchProc.request = request;
            searchProc.response = "";
            searchProc.command = [root.binaryPath].concat(cliArgs);
            searchProc.started = false;
            searchProc.inFlight = true;
            searchProc.running = true;
            searchTimeout.restart();
        };
        if (root._canUseServe()) {
            root._searchServeInFlight = true;
            const reqId = root._sendServeRequest(cliArgs, null, {
                "onResult": (payload, ok) => {
                    root._searchServeInFlight = false;
                    root._applySearchPayload(request, ok, payload);
                    Qt.callLater(root._startPendingSearch);
                },
                "onFallback": () => {
                    root._searchServeInFlight = false;
                    runSingleShot();
                }
            });
            if (reqId > 0)
                return;
            root._searchServeInFlight = false;
        }
        runSingleShot();
    }

    // Block folding operations (Logseq-style outliner folding)
    function toggleBlockFold(blockId: int): void {
        const next = Object.assign({}, root.foldedBlocks);
        next[blockId] = !Boolean(next[blockId]);
        root.foldedBlocks = next;
    }

    function foldAllBlocks(): void {
        if (!root.currentDoc || !Array.isArray(root.currentDoc.blocks))
            return;
        const next = {};
        for (let i = 0; i < root.currentDoc.blocks.length; ++i) {
            const b = root.currentDoc.blocks[i];
            if (b && b.foldable)
                next[b.id] = true;
        }
        root.foldedBlocks = next;
        root.vimStatusMessage = "Folded all blocks (zM)";
    }

    function unfoldAllBlocks(): void {
        root.foldedBlocks = ({});
        root.vimStatusMessage = "Unfolded all blocks (zR)";
    }

    function isBlockHiddenByFold(blockIndex: int): bool {
        if (!root.currentDoc || !Array.isArray(root.currentDoc.blocks))
            return false;
        const blocks = root.currentDoc.blocks;
        if (blockIndex < 0 || blockIndex >= blocks.length)
            return false;
        const targetLine = blocks[blockIndex].lineStart;
        for (let i = 0; i < blockIndex; ++i) {
            const b = blocks[i];
            if (b && b.foldable && Boolean(root.foldedBlocks[b.id])) {
                if (targetLine > b.lineEnd && targetLine <= b.foldEndLine)
                    return true;
            }
        }
        return false;
    }

    // Vim Ex command processor (:w, :q, :wq, :daily, :home, :graph, :e <path>, :split, :hybrid, :raw)
    function executeVimExCommand(rawCmd: string): bool {
        const cmd = String(rawCmd ?? "").trim().replace(/^:/, "").trim();
        root.vimMode = "NORMAL";
        root.vimCommandBuffer = "";
        root.vimCountBuffer = "";
        root.vimVisualAnchor = -1;
        if (cmd.length === 0)
            return false;

        if (cmd === "w" || cmd === "write") {
            root.saveCurrentNote();
            root.vimStatusMessage = "\"" + (root.currentPath || "Homepage") + "\" written";
            return true;
        }
        if (cmd === "q" || cmd === "quit") {
            root.close();
            return true;
        }
        if (cmd === "wq" || cmd === "x") {
            if (root.currentPath.length > 0)
                root.saveCurrentNote();
            root.close();
            return true;
        }
        if (cmd === "daily" || cmd === "journal") {
            root.openDailyNote();
            root.vimStatusMessage = "Opened Today's Journal";
            return true;
        }
        if (cmd === "home" || cmd === "homepage") {
            root.openHomepage();
            return true;
        }
        if (cmd === "graph") {
            root.openGraphView();
            return true;
        }
        if (cmd === "movies" || cmd === "movie") {
            root.openCollection("movies");
            return true;
        }
        if (cmd === "tv" || cmd === "tvseries" || cmd === "series") {
            root.openCollection("tvseries");
            return true;
        }
        if (cmd === "games" || cmd === "game") {
            root.openCollection("games");
            return true;
        }
        if (cmd === "books" || cmd === "book") {
            root.openCollection("books");
            return true;
        }
        if (cmd === "recipes" || cmd === "recipe") {
            root.openCollection("recipes");
            return true;
        }
        if (cmd === "exercises" || cmd === "exercise") {
            root.openCollection("exercises");
            return true;
        }
        if (cmd === "clippings" || cmd === "clipping") {
            root.openCollection("clippings");
            return true;
        }
        if (cmd === "finance") {
            root.openCollection("finance");
            return true;
        }
        if (cmd === "websites" || cmd === "onion") {
            root.openCollection("websites");
            return true;
        }
        if (cmd === "cornell") {
            root.openCollection("cornell");
            return true;
        }
        if (cmd === "places" || cmd === "place") {
            root.openCollection("places");
            return true;
        }
        if (cmd === "settings") {
            root.openFile("90_System/93_Configuration/settings.md", true);
            return true;
        }
        if (cmd === "hybrid") {
            root.setEditorMode("hybrid");
            root.vimStatusMessage = "Mode: Hybrid Outliner";
            return true;
        }
        if (cmd === "raw") {
            root.setEditorMode("raw");
            root.vimStatusMessage = "Mode: Raw Vim Editor";
            return true;
        }
        if (cmd === "split") {
            root.setEditorMode("split");
            root.vimStatusMessage = "Mode: Split Outliner + Vim";
            return true;
        }
        if (cmd === "zM") {
            root.foldAllBlocks();
            return true;
        }
        if (cmd === "zR") {
            root.unfoldAllBlocks();
            return true;
        }
        if (cmd.startsWith("e ") || cmd.startsWith("edit ")) {
            const arg = cmd.replace(/^(e|edit)\s+/, "").trim();
            if (arg.length > 0) {
                root.followWikilink(arg);
                return true;
            }
        }
        if (cmd.startsWith("new ")) {
            const arg = cmd.replace(/^new\s+/, "").trim();
            if (arg.length > 0) {
                root.createNote(arg, "", "standard");
                return true;
            }
        }
        if (cmd.startsWith("zk ")) {
            const arg = cmd.replace(/^zk\s+/, "").trim();
            if (arg.length > 0) {
                const slug = arg.replace(/[^A-Za-z0-9_-]+/g, "-");
                root.createNote("00_Capture/03_Zettelkasten/" + slug + ".md", arg, "zettelkasten");
                return true;
            }
        }
        root.vimStatusMessage = "E492: Not an editor command: " + cmd;
        return false;
    }

    // Cross-service integrations (Quick Notes, Spaced Repetition, Todo)
    function captureZettelkastenNote(title: string, body: string): bool {
        const cleanTitle = String(title ?? "").trim();
        if (cleanTitle.length === 0)
            return false;
        const zk = HostServices.AlisIntergration.session?.zettelkasten ?? null;
        if (zk && typeof zk.capture === "function") {
            const ok = zk.capture(cleanTitle, String(body ?? ""));
            if (ok) {
                root.vimStatusMessage = "Captured Zettelkasten note: " + cleanTitle;
                Qt.callLater(() => {
                    if (root._live)
                        root.refreshVault();
                });
                return true;
            }
        }
        const folder = String(Config.options?.notes?.zettelkasten?.folder ?? "00_Capture/03_Zettelkasten");
        const safeName = cleanTitle.replace(/[\/\\:*?"<>|]+/g, "-");
        root.createNote(folder + "/" + safeName + ".md", cleanTitle, "zettelkasten");
        return true;
    }

    function syncDocumentFlashcardsToSpacedRepetition(): int {
        if (!root.currentDoc)
            return 0;
        const sr = HostServices.AlisIntergration?.spacedRepetition ?? HostServices.AlisIntergration?.session?.spacedRepetition ?? null;
        const existingBasic = Object.create(null);
        const existingCloze = Object.create(null);
        const curCards = Array.isArray(sr?.cards) ? sr.cards : [];
        for (let i = 0; i < curCards.length; ++i) {
            const c = curCards[i];
            if (!c)
                continue;
            const fk = String(c.front ?? "").trim() + "||" + String(c.back ?? "").trim();
            if (fk !== "||")
                existingBasic[fk] = true;
            const ck = String(c.clozeText ?? "").trim();
            if (ck.length > 0)
                existingCloze[ck] = true;
        }
        const basicLines = [];
        const clozeLines = [];
        const docCards = Array.isArray(root.currentDoc.flashcards) ? root.currentDoc.flashcards : [];
        for (let i = 0; i < docCards.length; ++i) {
            const card = docCards[i];
            if (!card)
                continue;
            const rawFront = String(card.front ?? "").trim();
            const rawBack = String(card.back ?? "").trim();
            const rawCloze = String(card.clozeText ?? (rawFront.indexOf("{{c") !== -1 ? rawFront : "")).trim();
            if (rawCloze.indexOf("{{c") !== -1) {
                if (!existingCloze[rawCloze]) {
                    existingCloze[rawCloze] = true;
                    clozeLines.push(rawCloze);
                }
            } else if (rawFront.length > 0 && rawBack.length > 0) {
                const key = rawFront + "||" + rawBack;
                if (!existingBasic[key]) {
                    existingBasic[key] = true;
                    basicLines.push(rawFront + " :: " + rawBack);
                }
            }
        }
        const contentLines = String(root.currentDoc.content ?? "").split(/\r?\n/);
        for (let i = 0; i < contentLines.length; ++i) {
            const trimmed = contentLines[i].trim().replace(/^[-*+]\s+/, "");
            if (/\{\{c\d+::[^}]+\}\}/.test(trimmed) && !existingCloze[trimmed]) {
                existingCloze[trimmed] = true;
                clozeLines.push(trimmed);
            }
        }
        if (basicLines.length === 0 && clozeLines.length === 0) {
            root.vimStatusMessage = docCards.length > 0 ? "Flashcards already synced to Spaced Repetition" : "No flashcards found in current note";
            return 0;
        }
        if (sr && typeof sr.importQuickText === "function") {
            const deckName = String(root.currentDoc.title ?? "Nexus").trim() || "Nexus";
            const lang = String(sr.options?.defaultLanguage ?? "en").trim() || "en";
            let count = 0;
            if (basicLines.length > 0)
                count += Number(sr.importQuickText(basicLines.join("\n"), deckName, lang, "knowledge") || 0);
            if (clozeLines.length > 0)
                count += Number(sr.importQuickText(clozeLines.join("\n"), deckName, lang, "cloze") || 0);
            root.vimStatusMessage = "Synced " + count + " new flashcards to Spaced Repetition";
            return count;
        }
        root.vimStatusMessage = "Enable Spaced Repetition integration to sync flashcards";
        return 0;
    }

    function createFlashcardInCurrentNote(frontOrCloze: string, back = "", isCloze = false): bool {
        if (!root.vaultConfigured || root.currentPath.length === 0 || !root.currentDoc)
            return false;
        const cleanFront = String(frontOrCloze ?? "").trim();
        const cleanBack = String(back ?? "").trim();
        if (cleanFront.length === 0)
            return false;
        let lineToAppend = "";
        if (isCloze) {
            lineToAppend = cleanFront.indexOf("{{c") !== -1 ? cleanFront : ("{{c1::" + cleanFront + "}}");
        } else {
            if (cleanBack.length === 0)
                return false;
            lineToAppend = cleanFront + " :: " + cleanBack;
        }
        const existing = String(root.draftContent || root.currentDoc.content || "").replace(/\s+$/, "");
        const updated = existing + "\n" + lineToAppend + "\n";
        root.saveCurrentNote(updated);
        root.vimStatusMessage = "Added flashcard to " + root.currentPath;
        return true;
    }

    function addQuickTodoTask(text: string): bool {
        const cleaned = String(text ?? "").trim();
        if (cleaned.length === 0)
            return false;
        const ok = HostServices.Todo.addTask(cleaned);
        if (ok)
            root.vimStatusMessage = "Added task to Todo";
        return ok;
    }

    function deleteCurrentNote(): bool {
        return root.deletePath(root.currentPath);
    }

    function _pruneTreeNode(node, target: string): var {
        if (!node || typeof node !== "object")
            return node;
        const children = Array.isArray(node.children) ? node.children : [];
        const nextChildren = [];
        let changed = false;
        for (let i = 0; i < children.length; ++i) {
            const c = children[i];
            const cRel = String(c?.relPath ?? "");
            if (cRel === target || cRel.startsWith(target + "/")) {
                changed = true;
                continue;
            }
            if (c && c.isDir && target.startsWith(cRel + "/")) {
                const updatedChild = root._pruneTreeNode(c, target);
                if (updatedChild !== c)
                    changed = true;
                nextChildren.push(updatedChild);
            } else {
                nextChildren.push(c);
            }
        }
        if (!changed)
            return node;
        return Object.assign({}, node, { "children": nextChildren });
    }

    function _restoreDeleteSnapshot(target: string): void {
        const snap = root._deleteRollbackSnapshots?.[target];
        if (!snap)
            return;
        const nextSnaps = Object.assign({}, root._deleteRollbackSnapshots);
        delete nextSnaps[target];
        root._deleteRollbackSnapshots = nextSnaps;
        root.flatFiles = snap.flatFiles;
        root.tree = snap.tree;
        root.recentNotes = snap.recentNotes;
        root.collections = snap.collections;
        root.historyBack = snap.historyBack;
        root.currentPath = snap.currentPath;
        root.currentDoc = snap.currentDoc;
        root.draftContent = snap.draftContent;
        root.isDirty = snap.isDirty;
        root.activeView = snap.activeView;
        root._rebuildVisibleTreeRows();
    }

    function deletePath(relPath: string): bool {
        if (!root.vaultConfigured)
            return false;
        const target = String(relPath ?? "").trim().replace(/^\/+|\/+$/g, "");
        if (target.length === 0)
            return false;
        const isMatch = p => {
            const s = String(p ?? "");
            return s === target || (s.length > target.length && s.startsWith(target + "/"));
        };
        const snap = {
            "flatFiles": root.flatFiles,
            "tree": root.tree,
            "recentNotes": root.recentNotes,
            "collections": root.collections,
            "historyBack": root.historyBack,
            "currentPath": root.currentPath,
            "currentDoc": root.currentDoc,
            "draftContent": root.draftContent,
            "isDirty": root.isDirty,
            "activeView": root.activeView
        };
        const nextSnaps = Object.assign({}, root._deleteRollbackSnapshots);
        nextSnaps[target] = snap;
        root._deleteRollbackSnapshots = nextSnaps;

        root.flatFiles = (Array.isArray(root.flatFiles) ? root.flatFiles : []).filter(f => !isMatch(f?.relPath));
        root.recentNotes = (Array.isArray(root.recentNotes) ? root.recentNotes : []).filter(f => !isMatch(f?.relPath));
        root.historyBack = (Array.isArray(root.historyBack) ? root.historyBack : []).filter(m => !isMatch(m));
        const prevCols = root.collections ?? ({});
        const nextCols = {};
        const colKeys = Object.keys(prevCols);
        for (let k = 0; k < colKeys.length; ++k) {
            const key = colKeys[k];
            const arr = prevCols[key];
            nextCols[key] = Array.isArray(arr) ? arr.filter(item => !isMatch(item?.relPath)) : arr;
        }
        root.collections = nextCols;
        root.tree = root._pruneTreeNode(root.tree, target);
        root._rebuildVisibleTreeRows();
        if (isMatch(root.currentPath)) {
            root.currentPath = "";
            root.currentDoc = null;
            root.draftContent = "";
            root.isDirty = false;
            root.openHomepage();
        }
        root.vimStatusMessage = "Moved to .trash: " + target;

        const args = [root.binaryPath, "delete", "--vault", root.configuredVaultPath, "--path", target];
        if (root.vaultCacheFsPath.length > 0
                && Quickshell.env("ALIS_NEXUS_DISABLE_SCAN_CACHE") !== "1"
                && Quickshell.env("ALIS_NEXUS_HEADLESS_SERVICE_ONLY") !== "1") {
            args.push("--cache-file");
            args.push(root.vaultCacheFsPath);
        }
        root._rescanAfterDoc = false;
        root._enqueueDocOp({
            "kind": "delete",
            "relPath": target,
            "recordHistory": false,
            "useStdin": false,
            "args": args
        });
        return true;
    }

    function renamePath(oldRel: string, newRel: string): bool {
        if (!root.vaultConfigured)
            return false;
        const from = (oldRel || "").trim();
        const to = (newRel || "").trim();
        if (from.length === 0 || to.length === 0 || from === to)
            return false;
        root._rescanAfterDoc = true;
        root._enqueueDocOp({
            "kind": "rename",
            "relPath": to,
            "recordHistory": false,
            "useStdin": false,
            "args": [root.binaryPath, "rename", "--vault", root.configuredVaultPath, "--from", from, "--to", to]
        });
        return true;
    }

    function createFolder(relPath: string): bool {
        if (!root.vaultConfigured)
            return false;
        const target = (relPath || "").trim();
        if (target.length === 0)
            return false;
        root._rescanAfterDoc = true;
        root._enqueueDocOp({
            "kind": "create-folder",
            "relPath": target,
            "recordHistory": false,
            "useStdin": false,
            "args": [root.binaryPath, "create-folder", "--vault", root.configuredVaultPath, "--path", target]
        });
        return true;
    }


    function formatHeadingLevel(level: int): bool {
        if (level < 1 || level > 6 || !root.currentDoc || root.currentPath.length === 0)
            return false;
        const prefix = "#".repeat(level) + " ";
        const blocks = root.currentDoc.blocks ?? [];
        let targetBlock = null;
        if (root.editingBlockId >= 0) {
            for (let i = 0; i < blocks.length; ++i) {
                if (blocks[i] && blocks[i].id === root.editingBlockId) {
                    targetBlock = blocks[i];
                    break;
                }
            }
        }
        if (!targetBlock && blocks.length > 0)
            targetBlock = blocks[0];
        if (targetBlock) {
            const stripped = String(targetBlock.rawText ?? targetBlock.text ?? "").replace(/^#{1,6}\s+/, "").trim();
            root.updateBlockContent(targetBlock.lineStart, targetBlock.lineEnd, prefix + (stripped || "Heading"));
        }
        root.vimStatusMessage = "Formatted block as Heading " + String(level);
        return true;
    }

    function formatKeyEvent(event): string {
        if (!event)
            return "";
        const k = event.key;
        if (k === Qt.Key_Control || k === Qt.Key_Shift || k === Qt.Key_Alt || k === Qt.Key_Meta || k === Qt.Key_Super_L || k === Qt.Key_Super_R || k === Qt.Key_AltGr)
            return "";
        const mods = event.modifiers ?? 0;
        const parts = [];
        if (mods & Qt.ControlModifier)
            parts.push("Ctrl");
        if (mods & Qt.AltModifier)
            parts.push("Alt");
        if (mods & Qt.ShiftModifier)
            parts.push("Shift");
        if (mods & Qt.MetaModifier)
            parts.push("Meta");

        const shiftedDigitMap = {
            "!": "1",
            "@": "2",
            "#": "3",
            "$": "4",
            "%": "5",
            "^": "6",
            "&": "7",
            "*": "8",
            "(": "9",
            ")": "0"
        };

        let keyName = "";
        if (k === Qt.Key_Return || k === Qt.Key_Enter)
            keyName = "Enter";
        else if (k === Qt.Key_Escape)
            keyName = "Escape";
        else if (k === Qt.Key_Space)
            keyName = "Space";
        else if (k === Qt.Key_Tab || k === Qt.Key_Backtab)
            keyName = "Tab";
        else if (k === Qt.Key_Backspace)
            keyName = "Backspace";
        else if (k === Qt.Key_Delete)
            keyName = "Delete";
        else if (k === Qt.Key_Left)
            keyName = "Left";
        else if (k === Qt.Key_Right)
            keyName = "Right";
        else if (k === Qt.Key_Up)
            keyName = "Up";
        else if (k === Qt.Key_Down)
            keyName = "Down";
        else if (k === Qt.Key_Comma)
            keyName = ",";
        else if (k === Qt.Key_Period)
            keyName = ".";
        else if (k === Qt.Key_Slash)
            keyName = "/";
        else if (k === Qt.Key_Semicolon)
            keyName = ";";
        else if (k === Qt.Key_Minus)
            keyName = "-";
        else if (k === Qt.Key_Equal)
            keyName = "=";
        else if (k === Qt.Key_Exclam)
            keyName = "1";
        else if (k === Qt.Key_At)
            keyName = "2";
        else if (k === Qt.Key_NumberSign)
            keyName = "3";
        else if (k === Qt.Key_Dollar)
            keyName = "4";
        else if (k === Qt.Key_Percent)
            keyName = "5";
        else if (k === Qt.Key_AsciiCircum)
            keyName = "6";
        else if (k === Qt.Key_Ampersand)
            keyName = "7";
        else if (k === Qt.Key_Asterisk)
            keyName = "8";
        else if (k === Qt.Key_ParenLeft)
            keyName = "9";
        else if (k === Qt.Key_ParenRight)
            keyName = "0";
        else if (k >= Qt.Key_0 && k <= Qt.Key_9)
            keyName = String.fromCharCode(48 + (k - Qt.Key_0));
        else if (k >= Qt.Key_A && k <= Qt.Key_Z)
            keyName = String.fromCharCode(65 + (k - Qt.Key_A));
        else if (k >= Qt.Key_F1 && k <= Qt.Key_F12)
            keyName = "F" + String(1 + (k - Qt.Key_F1));
        else if (typeof event.text === "string" && event.text.trim().length === 1) {
            const rawCh = event.text.trim();
            keyName = shiftedDigitMap[rawCh] ? shiftedDigitMap[rawCh] : rawCh.toUpperCase();
        }

        if (!keyName)
            return "";
        parts.push(keyName);
        return parts.join("+");
    }

    readonly property var activeWindowShortcuts: {
        const _u = root.userShortcuts;
        const _v = root.vaultHotkeys;
        const seen = ({});
        const list = [];
        const digitToShiftedSymbol = {
            "1": "!",
            "2": "@",
            "3": "#",
            "4": "$",
            "5": "%",
            "6": "^",
            "7": "&",
            "8": "*",
            "9": "(",
            "0": ")"
        };
        const addSeq = (comboRaw, actionId) => {
            const c = String(comboRaw ?? "").trim();
            if (!c || !actionId)
                return;
            // Expand +Enter into both +Return (main keyboard Enter) and +Enter (numpad Enter), and normalize +Esc to +Escape
            const normalized = c.endsWith("+Esc") ? (c.slice(0, c.length - 4) + "+Escape") : c;
            const variants = [normalized];
            if (normalized.endsWith("+Enter"))
                variants.unshift(normalized.slice(0, normalized.length - 6) + "+Return");
            // Also register XKB shifted-symbol variant for Shift+<Digit> (e.g. Alt+Shift+1 -> Alt+Shift+!)
            const shiftDigitMatch = c.match(/^(.*Shift\+)(0|1|2|3|4|5|6|7|8|9)$/i);
            if (shiftDigitMatch) {
                const sym = digitToShiftedSymbol[shiftDigitMatch[2]];
                if (sym)
                    variants.push(shiftDigitMatch[1] + sym);
            }
            for (let i = 0; i < variants.length; ++i) {
                const seq = variants[i];
                const key = seq.toLowerCase();
                if (seen[key])
                    continue;
                seen[key] = true;
                list.push({ "sequence": seq, "actionId": actionId });
            }
        };

        // 1. Primary configured shortcuts
        for (let i = 0; i < root.shortcutCatalog.length; ++i) {
            const item = root.shortcutCatalog[i];
            addSeq(root.shortcutFor(item.id), item.id);
        }

        // 2. Secondary vault hotkeys & built-in defaultKey fallbacks when not user-overridden
        const userMap = root.userShortcuts ?? ({});
        for (let i = 0; i < root.shortcutCatalog.length; ++i) {
            const item = root.shortcutCatalog[i];
            if (userMap && typeof userMap[item.id] === "string" && userMap[item.id].trim().length > 0)
                continue;
            const obsEntry = root._lookupVaultHotkeyEntry(item.obsidianId);
            if (obsEntry && Array.isArray(obsEntry.all)) {
                for (let j = 0; j < obsEntry.all.length; ++j)
                    addSeq(obsEntry.all[j], item.id);
            }
            if (item.defaultKey)
                addSeq(item.defaultKey, item.id);
        }

        // 3. Secondary aliases (Alt+Left/Right, Alt+C, Alt+G, Alt+N, Alt+D, Alt+Shift+1..6, Ctrl+P, Ctrl+O, Ctrl+S)
        addSeq("Ctrl+S", "saveNote");
        addSeq("Ctrl+Alt+Left", "navigateBack");
        addSeq("Alt+Left", "navigateBack");
        addSeq("Alt+H", "navigateBack");
        addSeq("Ctrl+Alt+Right", "navigateForward");
        addSeq("Alt+Right", "navigateForward");
        addSeq("Alt+L", "navigateForward");
        addSeq("Alt+C", "toggleRightSidebar");
        addSeq("Alt+G", "gotoTab3");
        addSeq("Alt+D", "gotoTab4");
        addSeq("Alt+N", "newNote");
        addSeq("Alt+Shift+N", "newNote");
        addSeq("Alt+Shift+1", "heading1");
        addSeq("Alt+Shift+2", "heading2");
        addSeq("Alt+Shift+3", "heading3");
        addSeq("Alt+Shift+4", "heading4");
        addSeq("Alt+Shift+5", "heading5");
        addSeq("Alt+Shift+6", "heading6");
        addSeq("Ctrl+P", "commandPalette");
        addSeq("Ctrl+K", "commandPalette");
        addSeq("Ctrl+O", "quickSwitcher");
        return list;
    }

    function _openRecentNoteByIndex(index: int): bool {
        if (root.recentNotes && index >= 0 && index < root.recentNotes.length) {
            const note = root.recentNotes[index];
            if (note && note.relPath) {
                root.openFile(String(note.relPath), true);
                return true;
            }
        }
        root.openHomepage();
        return true;
    }

    function cardSlotIndex(cardId: string): int {
        return Array.isArray(root.cardOrder) ? root.cardOrder.indexOf(cardId) : -1;
    }

    function _ensureExplorerSidebarVisible(): void {
        const slot = root.cardSlotIndex("explorer");
        if (slot >= 2)
            root.rightSidebarOpen = true;
        else
            root.leftSidebarOpen = true;
    }

    function triggerShortcutAction(actionId: string): bool {
        const resolved = root._resolveActionId(actionId);
        switch (resolved) {
        case "commandPalette":
            if (root.commandPaletteOpen && root.commandPaletteMode !== "commands") {
                root.commandPaletteMode = "commands";
            } else {
                root.commandPaletteMode = "commands";
                root.commandPaletteOpen = !root.commandPaletteOpen;
            }
            return true;
        case "quickSwitcher":
            root.commandPaletteMode = "switcher";
            root.commandPaletteOpen = true;
            return true;
        case "cycleView":
            if (root.activeView === "homepage")
                root.activeView = root.currentDoc ? "document" : "graph";
            else if (root.activeView === "document")
                root.openGraphView();
            else
                root.openHomepage();
            return true;
        case "gotoTab1":
            root.openHomepage();
            return true;
        case "gotoTab2":
            if (root.currentDoc) {
                root.activeView = "document";
                root.vimStatusMessage = root.currentPath;
            } else {
                root.openDailyNote();
            }
            return true;
        case "gotoTab3":
            root.openGraphView();
            return true;
        case "gotoTab4":
            root.openDailyNote();
            return true;
        case "gotoTab5":
            return root._openRecentNoteByIndex(0);
        case "gotoTab6":
            return root._openRecentNoteByIndex(1);
        case "gotoTab7":
            return root._openRecentNoteByIndex(2);
        case "gotoTab8":
            return root._openRecentNoteByIndex(3);
        case "navigateBack":
            root.navigateBack();
            return true;
        case "navigateForward":
            root.navigateForward();
            return true;
        case "toggleLeftSidebar":
            root.leftSidebarOpen = !root.leftSidebarOpen;
            root.vimStatusMessage = root.leftSidebarOpen ? "Left Sidebar shown" : "Left Sidebar hidden";
            return true;
        case "toggleRightSidebar":
            root.rightSidebarOpen = !root.rightSidebarOpen;
            root.vimStatusMessage = root.rightSidebarOpen ? "Right Sidebar shown" : "Right Sidebar hidden";
            return true;
        case "toggleWindowMode":
            root.toggleOverlayMode();
            return true;
        case "resetWorkspaceLayout":
            root.resetLayout();
            return true;
        case "closeNexus":
            if (root.commandPaletteOpen) {
                root.commandPaletteOpen = false;
            } else if (root.activeView !== "homepage") {
                root.openHomepage();
            } else {
                root.close();
            }
            return true;
        case "openSettings":
            HostServices.SettingsNavigation.openSection("alis-intergration", "Alis Nexus", "");
            return true;
        case "newNote": {
            const stamp = Qt.formatDateTime(new Date(), "yyyyMMdd-hhmmss");
            root.createNote("00_Capture/Note-" + stamp + ".md", "Note " + stamp, "standard");
            return true;
        }
        case "newZettelkasten": {
            const stamp = Qt.formatDateTime(new Date(), "yyyyMMddhhmm");
            root.captureZettelkastenNote(stamp + " Zettelkasten", "");
            return true;
        }
        case "quickAddTask":
            root.commandPaletteMode = "task";
            root.commandPaletteOpen = true;
            return true;
        case "saveNote":
            root.saveCurrentNote();
            return true;
        case "deleteNote":
            return root.deleteCurrentNote();
        case "togglePreviewMode":
            root.setEditorMode(root.editorMode === "raw" ? "hybrid" : "raw");
            root.vimStatusMessage = "Editor Mode: " + root.editorMode;
            return true;
        case "toggleSourceSplit":
            root.setEditorMode(root.editorMode === "split" ? "hybrid" : "split");
            root.vimStatusMessage = "Editor Mode: " + root.editorMode;
            return true;
        case "searchInNote":
            root._ensureExplorerSidebarVisible();
            root.leftSidebarTab = "files";
            root.focusFileFilterRequested();
            return true;
        case "searchInVault":
            root._ensureExplorerSidebarVisible();
            root.leftSidebarTab = "search";
            root.focusVaultSearchRequested();
            return true;
        case "heading1":
            return root.formatHeadingLevel(1);
        case "heading2":
            return root.formatHeadingLevel(2);
        case "heading3":
            return root.formatHeadingLevel(3);
        case "heading4":
            return root.formatHeadingLevel(4);
        case "heading5":
            return root.formatHeadingLevel(5);
        case "heading6":
            return root.formatHeadingLevel(6);
        case "findInNote":
            root.findBarReplaceMode = false;
            root.findBarOpen = true;
            return true;
        case "replaceInNote":
            root.findBarReplaceMode = true;
            root.findBarOpen = true;
            return true;
        case "undoDocument":
            return root.undoDocument();
        case "redoDocument":
            return root.redoDocument();
        case "toggleSplitPane":
            root.toggleSplitPane();
            return true;
        case "openHistory":
            root.openHistoryModal();
            return true;
        case "openDatabase":
            root.openDatabaseView("");
            return true;
        case "openCanvas":
            root.openCanvasView("");
            return true;
        default:
            return false;
        }
    }

    function handleKeyEvent(event): bool {
        if (!event || event.key === 0 || event.key === Qt.Key_unknown)
            return false;
        const combo = root.formatKeyEvent(event);
        if (!combo)
            return false;
        const lower = combo.toLowerCase();
        // Check all configured primary shortcuts first
        for (let i = 0; i < root.shortcutCatalog.length; ++i) {
            const item = root.shortcutCatalog[i];
            if (root.shortcutFor(item.id).toLowerCase() === lower) {
                return root.triggerShortcutAction(item.id);
            }
        }
        // Check secondary hotkeys from .obsidian/hotkeys.json and built-in defaultKey fallbacks (when not custom-overridden)
        const userMap = root.userShortcuts ?? ({});
        for (let i = 0; i < root.shortcutCatalog.length; ++i) {
            const item = root.shortcutCatalog[i];
            if (userMap && typeof userMap[item.id] === "string" && userMap[item.id].trim().length > 0)
                continue;
            const obsEntry = root._lookupVaultHotkeyEntry(item.obsidianId);
            if (obsEntry && Array.isArray(obsEntry.all)) {
                for (let j = 0; j < obsEntry.all.length; ++j) {
                    if (String(obsEntry.all[j]).toLowerCase() === lower)
                        return root.triggerShortcutAction(item.id);
                }
            }
            if (String(item.defaultKey ?? "").toLowerCase() === lower)
                return root.triggerShortcutAction(item.id);
        }
        // Secondary standard/Obsidian aliases
        if (lower === "ctrl+s")
            return root.triggerShortcutAction("saveNote");
        if (lower === "ctrl+alt+left" || lower === "alt+left" || lower === "alt+h")
            return root.triggerShortcutAction("navigateBack");
        if (lower === "ctrl+alt+right" || lower === "alt+right" || lower === "alt+l")
            return root.triggerShortcutAction("navigateForward");
        if (lower === "alt+c")
            return root.triggerShortcutAction("toggleRightSidebar");
        if (lower === "alt+g")
            return root.triggerShortcutAction("gotoTab3");
        if (lower === "alt+d")
            return root.triggerShortcutAction("gotoTab4");
        if (lower === "alt+n" || lower === "alt+shift+n")
            return root.triggerShortcutAction("newNote");
        if (lower === "alt+shift+1")
            return root.triggerShortcutAction("heading1");
        if (lower === "alt+shift+2")
            return root.triggerShortcutAction("heading2");
        if (lower === "alt+shift+3")
            return root.triggerShortcutAction("heading3");
        if (lower === "alt+shift+4")
            return root.triggerShortcutAction("heading4");
        if (lower === "alt+shift+5")
            return root.triggerShortcutAction("heading5");
        if (lower === "alt+shift+6")
            return root.triggerShortcutAction("heading6");
        if (lower === "ctrl+p" || lower === "ctrl+k")
            return root.triggerShortcutAction("commandPalette");
        if (lower === "ctrl+o")
            return root.triggerShortcutAction("quickSwitcher");
        return false;
    }

    Timer {
        id: prewarmTimer
        interval: 4500
        repeat: false
        onTriggered: {
            if (root._live && root.vaultConfigured) {
                // When closed and vaultCacheFileView already hydrated the index,
                // defer live CLI scanning until the user opens Nexus so startup stays 100% silent & stutter-free.
                if (!root.vaultLoaded || root._loadedVaultPath !== root.configuredVaultPath) {
                    root.refreshVault();
                }
                if (root.isOpen && (!root._calendarLoadedFromCli || root._loadedVaultPath !== root.configuredVaultPath)) {
                    root.refreshCalendar(root.calendarYear, root.calendarMonth);
                }
            }
        }
    }

    onConfiguredVaultPathChanged: {
        if (root.configuredVaultPath !== root._loadedVaultPath) {
            root.vaultLoaded = false;
            root._calendarLoadedFromCli = false;
        }
        if (root.vaultConfigured) {
            if (root.isOpen) {
                root.refreshVault();
                root.refreshCalendar(root.calendarYear, root.calendarMonth);
            } else {
                prewarmTimer.restart();
            }
        }
    }

    onFileFilterQueryChanged: root._rebuildVisibleTreeRows()

    Timer {
        id: scanTimeout
        interval: 10000
        repeat: false
        onTriggered: {
            if (scanProc.running) {
                scanProc.running = false;
                root.errorMessage = "Vault scan timed out";
            }
        }
    }

    function _computeScanDigest(payload): string {
        if (!payload || typeof payload !== "object")
            return "";
        const files = Array.isArray(payload.files) ? payload.files : [];
        const tags = Array.isArray(payload.tags) ? payload.tags : [];
        const gNodes = Array.isArray(payload.graph?.nodes) ? payload.graph.nodes.length : 0;
        const gEdges = Array.isArray(payload.graph?.edges) ? payload.graph.edges.length : 0;
        const lNodes = Array.isArray(payload.homepageLocalGraph?.nodes) ? payload.homepageLocalGraph.nodes.length : 0;
        const lEdges = Array.isArray(payload.homepageLocalGraph?.edges) ? payload.homepageLocalGraph.edges.length : 0;
        let sample = "";
        if (files.length > 0) {
            const parts = [];
            for (let i = 0; i < files.length; ++i) {
                const f = files[i];
                if (f)
                    parts.push(String(f.relPath ?? "") + ":" + String(f.mtimeSecs ?? f.mtimeMs ?? 0) + ":" + String(f.sizeBytes ?? f.size ?? 0));
            }
            sample = parts.join(",");
        }
        return [
            root.configuredVaultPath,
            String(payload.vaultName ?? ""),
            files.length,
            tags.length,
            gNodes,
            gEdges,
            lNodes,
            lEdges,
            sample,
            JSON.stringify(payload.todayJournal ?? null),
            String(payload.homepageCoverUrl ?? "")
        ].join("|");
    }

    function _applyScanPayload(payload, fromCache = false): void {
        if (!payload || !payload.ok)
            return;
        const nextDigest = root._computeScanDigest(payload);
        if (!fromCache && root.vaultLoaded && root._loadedVaultPath === root.configuredVaultPath
                && nextDigest.length > 0 && nextDigest === root._lastAppliedScanDigest) {
            root._lastScanDoneMs = Date.now();
            root.errorMessage = "";
            root._syncScannedJournalCheckIn(root.todayJournalInfo);
            return;
        }
        root._lastAppliedScanDigest = nextDigest;
        root.vaultName = String(payload.vaultName ?? "Vault");
        root.tree = payload.tree ?? {
            "name": "Vault",
            "relPath": "",
            "isDir": true,
            "children": []
        };
        root.flatFiles = payload.files ?? [];
        root.tagsList = payload.tags ?? [];
        root.vaultGraph = payload.graph ?? {
            "nodes": [],
            "edges": [],
            "groups": []
        };
        root.homepageLocalGraph = payload.homepageLocalGraph ?? {
            "nodes": [],
            "edges": []
        };
        root.recentNotes = payload.recentNotes ?? [];
        root.topFolders = payload.topFolders ?? [];
        root.dailySchedule = payload.dailySchedule ?? root.dailySchedule;
        root.allWeekdaysSchedule = payload.allWeekdaysSchedule ?? ({});
        if (payload.todayJournal && typeof payload.todayJournal === "object") {
            root.todayJournalInfo = payload.todayJournal;
        }
        root.financeSummary = payload.financeSummary ?? root.financeSummary;
        root.vaultHotkeys = payload.vaultHotkeys ?? root.vaultHotkeys;
        root.homepageCoverUrl = String(payload.homepageCoverUrl ?? "");
        root.homepagePhotoUrl = String(payload.homepagePhotoUrl ?? payload.homepageCoverUrl ?? "");
        root.weatherLocation = String(payload.weatherLocation ?? "Can Tho, VN");
        root.globeSettings = payload.globeSettings ?? root.globeSettings;
        root.collections = payload.collections ?? root.collections;
        root.stats = payload.stats ?? root.stats;
        root._loadedVaultPath = root.configuredVaultPath;
        root.vaultLoaded = true;
        root.errorMessage = "";
        root._rebuildVisibleTreeRows();
        if (!fromCache) {
            root._lastScanDoneMs = Date.now();
            root._syncScannedJournalCheckIn(root.todayJournalInfo);
            if (root._plannerRangeStart.length > 0 && root._plannerRangeEnd.length > 0)
                root.refreshPlannerRange(root._plannerRangeStart, root._plannerRangeEnd);
        }
    }

    Timer {
        id: sleepResumeWatchdog
        interval: (scanProc.running || docProc.running || calendarProc.running) ? 5000 : 60000
        repeat: true
        running: root._live && Quickshell.env("ALIS_NEXUS_HEADLESS_SERVICE_ONLY") !== "1"
        onTriggered: {
            const now = Date.now();
            const prevHeartbeatMs = root._lastHeartbeatMs;
            const delta = now - prevHeartbeatMs;
            root._lastHeartbeatMs = now;
            if (scanProc.running && (now - root._scanStartedAtMs > 11000)) {
                scanProc.running = false;
            }
            if (docProc.running && (now - root._docStartedAtMs > 11000)) {
                docProc.running = false;
            }
            // If wall clock jumped >35s past the active timer interval (suspend/sleep), refresh cleanly in background
            const expectedIntervalMs = Math.max(5000, sleepResumeWatchdog.interval);
            const suspendJumpThresholdMs = expectedIntervalMs + 35000;
            if (prevHeartbeatMs > 0 && delta > suspendJumpThresholdMs && root.vaultConfigured) {
                root.refreshVault();
                root.refreshCalendar(root.calendarYear, root.calendarMonth);
            }
        }
    }

    FileView {
        id: vaultCacheFileView
        path: Qt.resolvedUrl(root._useLegacyVaultCacheFallback ? root.vaultCachePath : `${root.vaultCachePath}.ui.json`)
        watchChanges: false
        printErrors: false
        onLoadFailed: {
            if (!root._useLegacyVaultCacheFallback)
                root._useLegacyVaultCacheFallback = true;
        }
        onLoaded: {
            if (root.vaultLoaded || !root.vaultConfigured)
                return;
            try {
                const raw = vaultCacheFileView.text();
                if (!raw || raw.trim().length === 0) {
                    if (!root._useLegacyVaultCacheFallback)
                        root._useLegacyVaultCacheFallback = true;
                    return;
                }
                const parsed = JSON.parse(raw);
                if (parsed && parsed.ok && String(parsed.vaultPath ?? "") === root.configuredVaultPath) {
                    root._applyScanPayload(parsed, true);
                }
            } catch (e) {
                if (!root._useLegacyVaultCacheFallback)
                    root._useLegacyVaultCacheFallback = true;
            }
        }
    }

    Process {
        id: scanProc
        property string response: ""
        stdout: StdioCollector {
            id: scanStdoutCollector
        }
        onExited: (code, status) => {
            scanTimeout.stop();
            try {
                const payload = JSON.parse(scanStdoutCollector.text);
                if (payload && payload.ok) {
                    if (payload.unchanged === true) {
                        root._lastScanDoneMs = Date.now();
                        root.errorMessage = "";
                        root._syncScannedJournalCheckIn(root.todayJournalInfo);
                    } else {
                        root._applyScanPayload(payload, false);
                    }
                } else {
                    root.errorMessage = String(payload?.error ?? "Could not scan vault");
                }
            } catch (e) {
                root.errorMessage = "Could not parse vault index";
            }
            if (root._rescanQueued && root._live) {
                root._rescanQueued = false;
                Qt.callLater(() => {
                    if (root._live)
                        root.refreshVault();
                });
            }
        }
    }

    Timer {
        id: serveWatchdog
        interval: 10000
        repeat: false
        onTriggered: {
            if (Object.keys(root._servePending).length > 0) {
                if (serveProc.running) {
                    try { serveProc.signal(15); } catch (_e) {}
                    serveProc.running = false;
                }
                root._failAllServePending(false);
            }
        }
    }

    Process {
        id: serveProc
        stdinEnabled: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => root._handleServeLine(line)
        }
        onStarted: {
            root._serveStarted = true;
            const queued = root._serveSendQueue.slice();
            root._serveSendQueue = [];
            for (let i = 0; i < queued.length; ++i)
                serveProc.write(queued[i]);
        }
        onRunningChanged: {
            if (!running && !root._serveStarted && Object.keys(root._servePending).length > 0) {
                Qt.callLater(() => {
                    if (!serveProc.running && !root._serveStarted && Object.keys(root._servePending).length > 0)
                        root._failAllServePending(true);
                });
            }
        }
        onExited: (code, status) => {
            root._serveStarted = false;
            if (root._live && Object.keys(root._servePending).length > 0)
                root._failAllServePending(false);
        }
    }

    Timer {
        id: preWriteProbeTimeout
        interval: 4000
        repeat: false
        onTriggered: {
            if (preWriteProbeProc.running) {
                try { preWriteProbeProc.signal(15); } catch (_e) {}
                preWriteProbeProc.running = false;
            }
            if (!preWriteProbeProc._finalized && preWriteProbeProc.pendingReq) {
                preWriteProbeProc._exited = true;
                preWriteProbeProc._exitCode = 1;
                preWriteProbeProc._stdoutDone = true;
                preWriteProbeProc._maybeFinalize();
            }
        }
    }

    Timer {
        id: preWriteProbeFlushTimer
        interval: 60
        repeat: false
        onTriggered: {
            if (preWriteProbeProc._exited && !preWriteProbeProc._finalized) {
                preWriteProbeProc._stdoutDone = true;
                preWriteProbeProc._maybeFinalize();
            }
        }
    }

    Process {
        id: preWriteProbeProc
        property var pendingReq: null
        property bool _startObserved: false
        property bool _exited: false
        property int _exitCode: 0
        property bool _stdoutDone: false
        property bool _finalized: false
        stdout: StdioCollector {
            id: preWriteProbeStdout
            onStreamFinished: {
                preWriteProbeProc._stdoutDone = true;
                preWriteProbeProc._maybeFinalize();
            }
        }
        onStarted: {
            preWriteProbeProc._startObserved = true;
            preWriteProbeProc._exited = false;
            preWriteProbeProc._exitCode = 0;
            preWriteProbeProc._stdoutDone = false;
            preWriteProbeProc._finalized = false;
            preWriteProbeFlushTimer.stop();
            preWriteProbeTimeout.restart();
        }
        onRunningChanged: {
            if (running) {
                preWriteProbeProc._startObserved = false;
                return;
            }
            if (!preWriteProbeProc._startObserved && preWriteProbeProc.pendingReq && !preWriteProbeProc._finalized) {
                preWriteProbeProc._exited = true;
                preWriteProbeProc._exitCode = 1;
                preWriteProbeProc._stdoutDone = true;
                preWriteProbeProc._maybeFinalize();
            }
        }
        onExited: (code, status) => {
            preWriteProbeProc._exited = true;
            preWriteProbeProc._exitCode = code;
            if (preWriteProbeProc._stdoutDone)
                preWriteProbeProc._maybeFinalize();
            else
                preWriteProbeFlushTimer.restart();
        }
        function _maybeFinalize(): void {
            if (!preWriteProbeProc._exited || preWriteProbeProc._finalized || !preWriteProbeProc._stdoutDone)
                return;
            preWriteProbeProc._finalized = true;
            preWriteProbeFlushTimer.stop();
            preWriteProbeTimeout.stop();
            const code = preWriteProbeProc._exitCode;
            const req = preWriteProbeProc.pendingReq;
            preWriteProbeProc.pendingReq = null;
            if (!root._live || !req)
                return;
            if (code === 0) {
                try {
                    const payload = JSON.parse(preWriteProbeStdout.text);
                    if (root._handlePreWriteConflict(req, payload)) {
                        Qt.callLater(() => {
                            if (root._live)
                                root._runNextDocOp();
                        });
                        return;
                    }
                } catch (_e) {}
            }
            root._startSingleShotDocOp(req);
        }
    }

    Timer {
        id: conflictCheckFlushTimer
        interval: 60
        repeat: false
        onTriggered: {
            if (conflictCheckProc._exited && !conflictCheckProc._finalized) {
                conflictCheckProc._stdoutDone = true;
                conflictCheckProc._maybeFinalize();
            }
        }
    }

    Process {
        id: conflictCheckProc
        property string targetPath: ""
        property string expectedSha: ""
        property double expectedMtime: 0
        property bool _exited: false
        property int _exitCode: 0
        property bool _stdoutDone: false
        property bool _finalized: false
        stdout: StdioCollector {
            id: conflictCheckStdout
            onStreamFinished: {
                conflictCheckProc._stdoutDone = true;
                conflictCheckProc._maybeFinalize();
            }
        }
        onStarted: {
            conflictCheckProc._exited = false;
            conflictCheckProc._exitCode = 0;
            conflictCheckProc._stdoutDone = false;
            conflictCheckProc._finalized = false;
            conflictCheckFlushTimer.stop();
        }
        onExited: (code, status) => {
            conflictCheckProc._exited = true;
            conflictCheckProc._exitCode = code;
            if (conflictCheckProc._stdoutDone)
                conflictCheckProc._maybeFinalize();
            else
                conflictCheckFlushTimer.restart();
        }
        function _maybeFinalize(): void {
            if (!conflictCheckProc._exited || conflictCheckProc._finalized || !conflictCheckProc._stdoutDone)
                return;
            conflictCheckProc._finalized = true;
            conflictCheckFlushTimer.stop();
            const code = conflictCheckProc._exitCode;
            if (!root._live || code !== 0 || root.currentPath !== conflictCheckProc.targetPath)
                return;
            try {
                const payload = JSON.parse(conflictCheckStdout.text);
                if (!payload || !payload.ok)
                    return;
                const diskSha = String(payload.sha256 ?? "");
                const diskMtime = Number(payload.mtimeSecs ?? 0);
                const changed = (conflictCheckProc.expectedSha.length > 0 && diskSha.length > 0)
                    ? (diskSha !== conflictCheckProc.expectedSha)
                    : (conflictCheckProc.expectedMtime > 0 && diskMtime > 0 && diskMtime !== conflictCheckProc.expectedMtime);
                if (changed) {
                    root.externalConflictDetected = true;
                    root.externalConflictPath = conflictCheckProc.targetPath;
                    root.externalConflictDiskContent = String(payload.content ?? "");
                    root.externalConflictDiskSha = diskSha;
                    root.externalConflictDiskMtime = diskMtime;
                }
            } catch (_e) {}
        }
    }

    function _finishDocOp(req, payload, parseFailed: bool): void {
        if (req && req.kind === "journal-weather") {
            const pending = Object.assign({}, root._weatherSyncInFlight);
            const remaining = Math.max(0, Number(pending[req.relPath] ?? 0) - 1);
            if (remaining > 0) pending[req.relPath] = remaining;
            else delete pending[req.relPath];
            root._weatherSyncInFlight = pending;
        }
        if (parseFailed) {
            if (!(req && req.kind === "history-snapshot")) {
                if (req && req.kind === "delete" && req.relPath)
                    root._restoreDeleteSnapshot(String(req.relPath));
                root.errorMessage = "Could not parse document response";
                root.vimStatusMessage = root.errorMessage;
            }
        } else if (!(req && req.kind === "history-snapshot")) {
            if (payload && payload.ok) {
                if (req && req.kind === "delete") {
                    const delPath = String(payload.deletedPath ?? req.relPath ?? "");
                    if (root._deleteRollbackSnapshots?.[delPath] || root._deleteRollbackSnapshots?.[req.relPath]) {
                        const nextSnaps = Object.assign({}, root._deleteRollbackSnapshots);
                        delete nextSnaps[delPath];
                        delete nextSnaps[req.relPath];
                        root._deleteRollbackSnapshots = nextSnaps;
                    }
                    root.vimStatusMessage = "Moved to .trash: " + delPath;
                    if (root.currentPath === delPath || (root.currentPath.length > delPath.length && root.currentPath.startsWith(delPath + "/"))) {
                        root.currentPath = "";
                        root.currentDoc = null;
                        root.draftContent = "";
                        root.isDirty = false;
                        root._loadedDocPath = "";
                        root._loadedDocSha = "";
                        root._loadedDocMtime = 0;
                        root.externalConflictDetected = false;
                        root.openHomepage();
                    }
                } else if (req && req.kind === "rename") {
                    const newPath = String(payload.newPath ?? "");
                    root.vimStatusMessage = "Renamed: " + newPath;
                    const oldPath = String(payload.oldPath ?? "");
                    if (oldPath.length > 0) {
                        const retarget = path => (path === oldPath || path.startsWith(oldPath + "/")) ? newPath + path.slice(oldPath.length) : path;
                        root._docQueue = root._docQueue.map(op => {
                            const next = Object.assign({}, op);
                            next.relPath = retarget(String(op.relPath ?? ""));
                            if (Array.isArray(op.args)) {
                                next.args = op.args.map((arg, index, args) => ["--path", "--from", "--to", "--source"].includes(args[index - 1])
                                    ? retarget(String(arg)) : arg);
                            }
                            return next;
                        });
                    }
                    if (oldPath.length > 0 && (root.currentPath === oldPath || root.currentPath.startsWith(oldPath + "/"))) {
                        const renamedCurrentPath = newPath + root.currentPath.slice(oldPath.length);
                        root.currentPath = renamedCurrentPath;
                        if (root._loadedDocPath === oldPath || root._loadedDocPath.startsWith(oldPath + "/"))
                            root._loadedDocPath = renamedCurrentPath;
                        if (root.isDirty) {
                            root.currentDoc = Object.assign({}, root.currentDoc, {
                                "relPath": renamedCurrentPath,
                                "absPath": root.configuredVaultPath + "/" + renamedCurrentPath
                            });
                        } else {
                            root.openFile(renamedCurrentPath, false);
                        }
                    }
                } else if (req && req.kind === "create-folder") {
                    const fol = String(payload.relPath ?? "");
                    root.vimStatusMessage = "Created folder: " + fol;
                } else if (req && req.kind === "duplicate") {
                    const dup = String(payload.relPath ?? "");
                    root.vimStatusMessage = "Duplicated: " + dup;
                    root.openFile(dup, true);
                } else if (req && req.kind === "daily-checkin") {
                    const newRel = String(payload.relPath ?? "");
                    const jv = payload.journalView ?? ({});
                    root.todayJournalInfo = {
                        "date": String(jv.dateIso ?? Qt.formatDate(new Date(), "yyyy-MM-dd")),
                        "exists": true,
                        "relPath": newRel,
                        "mood": String(jv.mood ?? root.todayJournalInfo?.mood ?? ""),
                        "energy": String(jv.energy ?? root.todayJournalInfo?.energy ?? ""),
                        "weight": String(jv.weight ?? root.todayJournalInfo?.weight ?? ""),
                        "hasMood": jv.hasMood,
                        "hasEnergy": jv.hasEnergy,
                        "hasWeight": jv.hasWeight
                    };
                    root._syncJournalToCompanion(root.todayJournalInfo.date,
                        jv.hasMood !== false ? root.todayJournalInfo.mood : undefined,
                        jv.hasEnergy !== false ? root.todayJournalInfo.energy : undefined,
                        jv.hasWeight !== false ? root.todayJournalInfo.weight : undefined);
                    if (newRel.length > 0 && String(jv.weather ?? "").trim().length === 0) {
                        const liveSummary = root.alisWeatherSummary || root.formatAlisWeatherSummary();
                        if (liveSummary.length > 0)
                            Qt.callLater(() => root._queueJournalWeather(newRel, liveSummary, false));
                    }
                    if (root.currentPath === newRel && newRel.length > 0) {
                        root.currentDoc = payload;
                        root.draftContent = String(payload.content ?? "");
                        root.isDirty = false;
                        root._loadedDocPath = newRel;
                        root._loadedDocSha = String(payload.sha256 ?? "");
                        root._loadedDocMtime = Number(payload.mtimeSecs ?? 0);
                        root.externalConflictDetected = false;
                    }
                    root.noteSaved(newRel);
                } else if (req && req.kind === "journal-weather") {
                    const target = String(payload.relPath ?? "");
                    if (String(payload.journalView?.weather ?? "").trim().length > 0) {
                        const recorded = Object.assign({}, root._autoSyncedWeatherPaths);
                        recorded[target] = true;
                        root._autoSyncedWeatherPaths = recorded;
                    }
                    if (root.currentPath === target && String(root.currentDoc?.relPath ?? "") === target) {
                        root.currentDoc = payload;
                        if (!root.isDirty) {
                            root.draftContent = String(payload.content ?? "");
                            root._loadedDocPath = target;
                            root._loadedDocSha = String(payload.sha256 ?? "");
                            root._loadedDocMtime = Number(payload.mtimeSecs ?? 0);
                        }
                    }
                    if (Boolean(payload.weatherWriteApplied)) {
                        root.noteSaved(target);
                        root.vimStatusMessage = "Weather synced from Alis Weather";
                    }
                } else if (req && req.kind === "finance-add") {
                    root.vimStatusMessage = "Added finance entry: " + String(payload.createdPath ?? "");
                    if (payload.financeSummary)
                        root.financeSummary = payload.financeSummary;
                    if (root.currentPath.length > 0 && root.activeView === "document")
                        root.openFile(root.currentPath, false);
                } else if (req && req.kind === "link-mention") {
                    root.vimStatusMessage = "Linked mention in " + String(payload.sourcePath ?? "");
                    if (root.currentPath.length > 0)
                        root.openFile(root.currentPath, false);
                } else if (req && req.kind === "tag-rename") {
                    const cnt = Number(payload.filesUpdated ?? 0);
                    root.vimStatusMessage = "Tag #" + String(payload.from ?? "") + " → #" + String(payload.to ?? "") + " (" + String(cnt) + " notes)";
                    if (root.activeTagFilter.toLowerCase() === String(payload.from ?? "").toLowerCase())
                        root.activeTagFilter = String(payload.to ?? "");
                    if (root.currentPath.length > 0 && root.activeView === "document")
                        root.openFile(root.currentPath, false);
                } else if (req && req.kind === "tag-remove") {
                    const cnt = Number(payload.filesUpdated ?? 0);
                    root.vimStatusMessage = "Removed #" + String(payload.tag ?? "") + " from " + String(cnt) + " notes";
                    if (root.activeTagFilter.toLowerCase() === String(payload.tag ?? "").toLowerCase())
                        root.activeTagFilter = "";
                    if (root.currentPath.length > 0 && root.activeView === "document")
                        root.openFile(root.currentPath, false);
                } else if (req && req.kind === "tag-page") {
                    const relP = String(payload.relPath ?? "");
                    if (relP.length > 0) {
                        root.vimStatusMessage = (payload.created ? "Created tag page: " : "Opened tag page: ") + relP;
                        root.openFile(relP, true);
                    }
                } else if (payload.category === "external") {
                    const absPath = String(payload.absPath ?? "");
                    root.lastExternalOpenedPath = absPath;
                    root.openExternally(absPath, "Opened externally: " + String(payload.title ?? "") + "." + String(payload.ext ?? ""));
                    root.externalFileDispatched(absPath);
                    root.fileOpened(String(payload.relPath ?? ""), "external");
                } else if (req && req.backgroundCreate) {
                    const createdRel = String(payload.relPath ?? req.relPath ?? "");
                    if (createdRel.length > 0) {
                        root.noteSaved(createdRel);
                        root.vimStatusMessage = "Saved " + createdRel;
                    }
                } else {
                    const prevPath = root._currentHistoryMarker();
                    const newRel = String(payload.relPath ?? "");
                    if (req && req.recordHistory && prevPath.length > 0 && prevPath !== newRel) {
                        const back = root.historyBack.slice();
                        back.push(prevPath);
                        if (back.length > 50)
                            back.shift();
                        root.historyBack = back;
                        root.historyForward = [];
                    }
                    const switchingFile = root.currentPath !== newRel;
                    const isSaveOnly = Boolean(req && !req.openCreated && (req.kind === "write" || req.kind === "toggle-todo" || req.kind === "update-block" || req.kind === "set-frontmatter" || req.kind === "sync-api"));
                    if (String(payload.noteKind ?? "") === "journal" && payload.journalView) {
                        const jDateIso = String(payload.journalView.dateIso ?? "").trim();
                        const jMood = String(payload.journalView.mood ?? "").trim();
                        const jEnergy = String(payload.journalView.energy ?? "").trim();
                        const jWeight = String(payload.journalView.weight ?? "").trim();
                        if (jDateIso === Qt.formatDate(new Date(), "yyyy-MM-dd")) {
                            root.todayJournalInfo = {
                                "date": jDateIso,
                                "exists": true,
                                "relPath": newRel,
                                "mood": jMood,
                                "energy": jEnergy,
                                "weight": jWeight,
                                "hasMood": payload.journalView.hasMood,
                                "hasEnergy": payload.journalView.hasEnergy,
                                "hasWeight": payload.journalView.hasWeight
                            };
                            const hasMood = payload.journalView.hasMood === undefined ? jMood.length > 0 || isSaveOnly : Boolean(payload.journalView.hasMood);
                            const hasEnergy = payload.journalView.hasEnergy === undefined ? jEnergy.length > 0 || isSaveOnly : Boolean(payload.journalView.hasEnergy);
                            const hasWeight = payload.journalView.hasWeight === undefined ? jWeight.length > 0 || isSaveOnly : Boolean(payload.journalView.hasWeight);
                            if (hasMood || hasEnergy || hasWeight) {
                                root._syncJournalToCompanion(jDateIso, hasMood ? jMood : undefined, hasEnergy ? jEnergy : undefined, hasWeight ? jWeight : undefined);
                            }
                        }
                        const existingWeather = String(payload.journalView.weather ?? "").trim();
                        if (existingWeather.length === 0) {
                            const liveSummary = root.formatAlisWeatherSummary();
                            Qt.callLater(() => root._syncAvailableJournalWeather(newRel));
                            if (liveSummary.length === 0 && Quickshell.env("ALIS_NEXUS_DISABLE_XDG_OPEN") !== "1" && typeof HostServices.Weather?.getData === "function") {
                                HostServices.Weather.getData();
                            }
                        }
                    }
                    root.currentPath = newRel;
                    root.currentDoc = payload;
                    root.draftContent = String(payload.content ?? "");
                    root.isDirty = false;
                    root._loadedDocPath = newRel;
                    root._loadedDocSha = String(payload.sha256 ?? "");
                    root._loadedDocMtime = Number(payload.mtimeSecs ?? 0);
                    root.externalConflictDetected = false;
                    root.externalConflictPath = "";
                    root.externalConflictDiskContent = "";
                    root.externalConflictDiskSha = "";
                    root.externalConflictDiskMtime = 0;
                    const docCategory = String(payload.category ?? "markdown");
                    if (!isSaveOnly)
                        root.activeView = (docCategory === "canvas") ? "canvas" : "document";
                    root._registerOpenTab(newRel, String(payload.title ?? ""), docCategory);
                    if (!isSaveOnly && docCategory === "pdf" && String(payload.absPath ?? "").length > 0) {
                        const absPdf = String(payload.absPath);
                        Qt.callLater(() => {
                            if (root._live)
                                root.pdfLoadInfo(absPdf);
                        });
                    }
                    if (switchingFile) {
                        root.foldedBlocks = ({});
                        root.editingBlockId = -1;
                        root.editorMode = "hybrid";
                        root.vimMode = "NORMAL";
                        root.vimCountBuffer = "";
                        root.vimKeyBuffer = "";
                        root.vimVisualAnchor = -1;
                    }
                    if (req && (req.kind === "write" || req.kind === "toggle-todo" || req.kind === "update-block" || req.kind === "set-frontmatter" || req.kind === "sync-api")) {
                        root.noteSaved(newRel);
                        root.vimStatusMessage = req.kind === "sync-api" ? ("Synced metadata: " + newRel) : ("Saved " + newRel);
                    } else {
                        root.vimStatusMessage = newRel;
                    }
                    root.fileOpened(newRel, docCategory);
                    if (req && req.kind === "read")
                        root.fileRead(newRel);
                }
            } else {
                if (req && req.kind === "delete" && req.relPath)
                    root._restoreDeleteSnapshot(String(req.relPath));
                root.errorMessage = String(payload?.error ?? "Document operation failed");
                root.vimStatusMessage = root.errorMessage;
            }
        }

        if (root._rescanAfterDoc) {
            root._rescanAfterDoc = false;
            root._forceFreshScan = true;
            root._lastAppliedScanDigest = "";
            if (root._live) {
                root.refreshVault();
                root.refreshCalendar(root.calendarYear, root.calendarMonth);
            }
        }
        Qt.callLater(() => {
            if (root._live)
                root._runNextDocOp();
        });
    }

    function _applyCalendarPayload(payload): void {
        if (payload && payload.ok) {
            root.calendarHeader = String(payload.headerLabel ?? "");
            root.calendarCells = payload.cells ?? [];
            root.calendarShowWeeklyNote = Boolean(payload.showWeeklyNote ?? false);
            root.calendarWordsPerDot = Math.max(1, Number(payload.wordsPerDot ?? 250));
            root.calendarWeekStart = String(payload.weekStart ?? "monday");
            root._calendarLoadedFromCli = true;
        }
    }

    function _applySearchPayload(request, ok: bool, payload): void {
        if (ok && payload?.ok && request
            && request.generation === root._searchGeneration
            && request.vault === root.configuredVaultPath
            && request.query === root.searchQuery.trim()
            && String(payload.query ?? "") === request.query) {
            root.searchResults = payload.results ?? [];
        }
    }

    Timer {
        id: docTimeout
        interval: 10000
        repeat: false
        onTriggered: {
            if (docProc.running) {
                docProc.running = false;
                root.errorMessage = "Document operation timed out";
            }
        }
    }

    Process {
        id: docProc
        property string response: ""
        property string stdinPayload: ""
        onStarted: {
            if (docProc.stdinEnabled) {
                docProc.write(docProc.stdinPayload);
                docProc.stdinEnabled = false;
            }
        }
        stdout: StdioCollector {
            id: docStdoutCollector
        }
        onExited: (code, status) => {
            docTimeout.stop();
            const req = root._activeDocReq;
            root._activeDocReq = null;
            let payload = null;
            let parseFailed = false;
            if (!(req && req.kind === "history-snapshot")) {
                try {
                    payload = JSON.parse(docStdoutCollector.text);
                } catch (_e) {
                    parseFailed = true;
                }
            }
            root._finishDocOp(req, payload, parseFailed);
        }
    }

    Timer {
        id: calendarTimeout
        interval: 8000
        repeat: false
        onTriggered: {
            if (calendarProc.running)
                calendarProc.running = false;
        }
    }

    Process {
        id: calendarProc
        property string response: ""
        stdout: StdioCollector {
            id: calendarStdoutCollector
        }
        onExited: (code, status) => {
            calendarTimeout.stop();
            try {
                root._applyCalendarPayload(JSON.parse(calendarStdoutCollector.text));
            } catch (e) {}
        }
    }

    Timer {
        id: searchTimeout
        interval: 8000
        repeat: false
        onTriggered: {
            if (searchProc.running)
                searchProc.running = false;
        }
    }

    Process {
        id: searchProc
        property string response: ""
        property bool inFlight: false
        property bool started: false
        property var request: null
        onStarted: searchProc.started = true
        onRunningChanged: if (!running && inFlight && !started) {
            // FailedToStart has no onExited. A deferred cleanup must still own
            // this exact unstarted request before releasing the queue.
            const request = searchProc.request;
            Qt.callLater(() => {
                if (!searchProc.running && searchProc.inFlight && !searchProc.started
                    && searchProc.request === request) {
                    searchTimeout.stop();
                    searchProc.inFlight = false;
                    searchProc.request = null;
                    Qt.callLater(root._startPendingSearch);
                }
            });
        }
        stdout: StdioCollector {
            id: searchStdoutCollector
        }
        onExited: (code, status) => {
            searchTimeout.stop();
            const request = searchProc.request;
            searchProc.inFlight = false;
            searchProc.request = null;
            try {
                root._applySearchPayload(request, code === 0, JSON.parse(searchStdoutCollector.text));
            } catch (e) {}
            Qt.callLater(root._startPendingSearch);
        }
    }

    Timer {
        id: apiSearchTimeout
        interval: 9000
        repeat: false
        onTriggered: {
            if (apiSearchProc.running) {
                apiSearchProc.running = false;
                root.searchApiLoading = false;
            }
        }
    }

    Process {
        id: apiSearchProc
        property string response: ""
        property bool inFlight: false
        property bool started: false
        property var request: null
        onStarted: apiSearchProc.started = true
        onRunningChanged: if (!running && inFlight && !started) {
            const request = apiSearchProc.request;
            Qt.callLater(() => {
                if (!apiSearchProc.running && apiSearchProc.inFlight && !apiSearchProc.started
                    && apiSearchProc.request === request) {
                    apiSearchTimeout.stop();
                    apiSearchProc.inFlight = false;
                    apiSearchProc.request = null;
                    root.searchApiLoading = false;
                    Qt.callLater(root._startPendingApiSearch);
                }
            });
        }
        stdout: StdioCollector {
            id: apiSearchStdoutCollector
        }
        onExited: (code, status) => {
            apiSearchTimeout.stop();
            const request = apiSearchProc.request;
            apiSearchProc.inFlight = false;
            apiSearchProc.request = null;
            if (!root._pendingApiSearch) {
                try {
                    const payload = JSON.parse(apiSearchStdoutCollector.text);
                    if (code === 0 && payload?.ok && request && request.generation === root._searchApiGeneration) {
                        root.searchApiResults = Array.isArray(payload.results) ? payload.results : [];
                    } else if (request && request.generation === root._searchApiGeneration) {
                        root.searchApiResults = [];
                    }
                } catch (e) {
                    if (request && request.generation === root._searchApiGeneration)
                        root.searchApiResults = [];
                }
                if (request && request.generation === root._searchApiGeneration)
                    root.searchApiLoading = false;
            }
            Qt.callLater(root._startPendingApiSearch);
        }
    }

    Timer {
        id: secondaryDocTimeout
        interval: 8000
        repeat: false
        onTriggered: {
            if (secondaryDocProc.running)
                secondaryDocProc.running = false;
            secondaryDocFlushTimer.stop();
        }
    }

    Timer {
        id: secondaryDocFlushTimer
        interval: 60
        repeat: false
        onTriggered: {
            if (secondaryDocProc._exited && !secondaryDocProc._finalized) {
                secondaryDocProc._stdoutDone = true;
                secondaryDocProc._maybeFinalize();
            }
        }
    }

    Process {
        id: secondaryDocProc
        property bool _exited: false
        property int _exitCode: 0
        property bool _stdoutDone: false
        property bool _finalized: false
        stdout: StdioCollector {
            id: secondaryDocStdout
            onStreamFinished: {
                secondaryDocProc._stdoutDone = true;
                secondaryDocProc._maybeFinalize();
            }
        }
        onStarted: {
            secondaryDocProc._exited = false;
            secondaryDocProc._exitCode = 0;
            secondaryDocProc._stdoutDone = false;
            secondaryDocProc._finalized = false;
            secondaryDocFlushTimer.stop();
        }
        onExited: (code, status) => {
            secondaryDocProc._exited = true;
            secondaryDocProc._exitCode = code;
            if (secondaryDocProc._stdoutDone)
                secondaryDocProc._maybeFinalize();
            else
                secondaryDocFlushTimer.restart();
        }
        function _maybeFinalize(): void {
            if (!secondaryDocProc._exited || secondaryDocProc._finalized || !secondaryDocProc._stdoutDone)
                return;
            secondaryDocProc._finalized = true;
            secondaryDocFlushTimer.stop();
            secondaryDocTimeout.stop();
            const code = secondaryDocProc._exitCode;
            try {
                const payload = JSON.parse(secondaryDocStdout.text);
                if (code === 0 && payload && payload.ok) {
                    root.secondaryDoc = payload;
                } else {
                    root.errorMessage = String(payload?.error ?? "Could not open secondary note");
                }
            } catch (e) {}
        }
    }

    Timer {
        id: previewTimeout
        interval: 5000
        repeat: false
        onTriggered: {
            if (previewProc.running)
                previewProc.running = false;
            previewFlushTimer.stop();
            root.hoverPreviewLoading = false;
        }
    }

    Timer {
        id: previewFlushTimer
        interval: 60
        repeat: false
        onTriggered: {
            if (previewProc._exited && !previewProc._finalized) {
                previewProc._stdoutDone = true;
                previewProc._maybeFinalize();
            }
        }
    }

    Process {
        id: previewProc
        property string targetKey: ""
        property bool _exited: false
        property int _exitCode: 0
        property bool _stdoutDone: false
        property bool _finalized: false
        stdout: StdioCollector {
            id: previewStdout
            onStreamFinished: {
                previewProc._stdoutDone = true;
                previewProc._maybeFinalize();
            }
        }
        onStarted: {
            previewProc._exited = false;
            previewProc._exitCode = 0;
            previewProc._stdoutDone = false;
            previewProc._finalized = false;
            previewFlushTimer.stop();
        }
        onExited: (code, status) => {
            previewProc._exited = true;
            previewProc._exitCode = code;
            if (previewProc._stdoutDone)
                previewProc._maybeFinalize();
            else
                previewFlushTimer.restart();
        }
        function _maybeFinalize(): void {
            if (!previewProc._exited || previewProc._finalized || !previewProc._stdoutDone)
                return;
            previewProc._finalized = true;
            previewFlushTimer.stop();
            previewTimeout.stop();
            const code = previewProc._exitCode;
            const key = previewProc.targetKey;
            try {
                const payload = JSON.parse(previewStdout.text);
                if (code === 0 && payload && payload.ok && key) {
                    const nextCache = Object.assign({}, root.hoverPreviewCache ?? ({}));
                    const order = (Array.isArray(root._hoverPreviewOrder) ? root._hoverPreviewOrder : []).filter(k => k !== key);
                    order.push(key);
                    nextCache[key] = payload;
                    while (order.length > 32) {
                        const oldest = order.shift();
                        delete nextCache[oldest];
                    }
                    root._hoverPreviewOrder = order;
                    root.hoverPreviewCache = nextCache;
                    root.hoverPreviewData = payload;
                }
            } catch (e) {}
            root.hoverPreviewLoading = false;
            if (root._pendingPreviewTarget.length > 0 && root._live)
                Qt.callLater(root._startPendingPreview);
        }
    }

    Timer {
        id: queryTimeout
        interval: 10000
        repeat: false
        onTriggered: {
            if (queryProc.running)
                queryProc.running = false;
            queryFlushTimer.stop();
            root.queryLoading = false;
        }
    }

    Timer {
        id: queryFlushTimer
        interval: 60
        repeat: false
        onTriggered: {
            if (queryProc._exited && !queryProc._finalized) {
                queryProc._stdoutDone = true;
                queryProc._maybeFinalize();
            }
        }
    }

    Process {
        id: queryProc
        property bool _exited: false
        property int _exitCode: 0
        property bool _stdoutDone: false
        property bool _finalized: false
        stdout: StdioCollector {
            id: queryStdout
            onStreamFinished: {
                queryProc._stdoutDone = true;
                queryProc._maybeFinalize();
            }
        }
        onStarted: {
            queryProc._exited = false;
            queryProc._exitCode = 0;
            queryProc._stdoutDone = false;
            queryProc._finalized = false;
            queryFlushTimer.stop();
        }
        onExited: (code, status) => {
            queryProc._exited = true;
            queryProc._exitCode = code;
            if (queryProc._stdoutDone)
                queryProc._maybeFinalize();
            else
                queryFlushTimer.restart();
        }
        function _maybeFinalize(): void {
            if (!queryProc._exited || queryProc._finalized || !queryProc._stdoutDone)
                return;
            queryProc._finalized = true;
            queryFlushTimer.stop();
            queryTimeout.stop();
            root.queryLoading = false;
            const code = queryProc._exitCode;
            try {
                const payload = JSON.parse(queryStdout.text);
                if (code === 0 && payload && payload.ok) {
                    root.queryResults = payload;
                } else {
                    root.errorMessage = String(payload?.error ?? "Database query failed");
                }
            } catch (e) {}
        }
    }

    Timer {
        id: historyTimeout
        interval: 8000
        repeat: false
        onTriggered: {
            if (historyProc.running)
                historyProc.running = false;
            historyFlushTimer.stop();
            root.historyLoading = false;
        }
    }

    Timer {
        id: historyFlushTimer
        interval: 60
        repeat: false
        onTriggered: {
            if (historyProc._exited && !historyProc._finalized) {
                historyProc._stdoutDone = true;
                historyProc._maybeFinalize();
            }
        }
    }

    Process {
        id: historyProc
        property string opKind: ""
        property string targetPath: ""
        property bool _exited: false
        property int _exitCode: 0
        property bool _stdoutDone: false
        property bool _finalized: false
        stdout: StdioCollector {
            id: historyStdout
            onStreamFinished: {
                historyProc._stdoutDone = true;
                historyProc._maybeFinalize();
            }
        }
        onStarted: {
            historyProc._exited = false;
            historyProc._exitCode = 0;
            historyProc._stdoutDone = false;
            historyProc._finalized = false;
            historyFlushTimer.stop();
        }
        onExited: (code, status) => {
            historyProc._exited = true;
            historyProc._exitCode = code;
            if (historyProc._stdoutDone)
                historyProc._maybeFinalize();
            else
                historyFlushTimer.restart();
        }
        function _maybeFinalize(): void {
            if (!historyProc._exited || historyProc._finalized || !historyProc._stdoutDone)
                return;
            historyProc._finalized = true;
            historyFlushTimer.stop();
            historyTimeout.stop();
            root.historyLoading = false;
            try {
                const payload = JSON.parse(historyStdout.text);
                if (!payload || !payload.ok) {
                    root.vimStatusMessage = String(payload?.error ?? "History operation failed");
                    return;
                }
                if (historyProc.opKind === "snapshot") {
                    root.vimStatusMessage = "Snapshot saved for " + historyProc.targetPath;
                    root.loadNoteHistory(historyProc.targetPath);
                } else if (historyProc.opKind === "list") {
                    const revs = Array.isArray(payload.revisions) ? payload.revisions : [];
                    root.historyRevisions = revs;
                    if (revs.length > 0 && revs[0]?.revId)
                        Qt.callLater(() => root.diffNoteRevision(String(revs[0].revId), historyProc.targetPath));
                } else if (historyProc.opKind === "diff") {
                    root.historyDiffText = String(payload.diff ?? "");
                } else if (historyProc.opKind === "restore") {
                    const target = String(payload.relPath ?? historyProc.targetPath);
                    root.vimStatusMessage = "Restored revision for " + target;
                    root.noteHistoryRestored(target);
                    root.openFile(target, false);
                    root.loadNoteHistory(target);
                }
            } catch (e) {}
        }
    }

    Timer {
        id: assetTimeout
        interval: 8000
        repeat: false
        onTriggered: {
            if (assetProc.running)
                assetProc.running = false;
            assetFlushTimer.stop();
        }
    }

    Timer {
        id: assetFlushTimer
        interval: 60
        repeat: false
        onTriggered: {
            if (assetProc._exited && !assetProc._finalized) {
                assetProc._stdoutDone = true;
                assetProc._maybeFinalize();
            }
        }
    }

    Process {
        id: assetProc
        property bool _exited: false
        property int _exitCode: 0
        property bool _stdoutDone: false
        property bool _finalized: false
        stdout: StdioCollector {
            id: assetStdout
            onStreamFinished: {
                assetProc._stdoutDone = true;
                assetProc._maybeFinalize();
            }
        }
        onStarted: {
            assetProc._exited = false;
            assetProc._exitCode = 0;
            assetProc._stdoutDone = false;
            assetProc._finalized = false;
            assetFlushTimer.stop();
        }
        onExited: (code, status) => {
            assetProc._exited = true;
            assetProc._exitCode = code;
            if (assetProc._stdoutDone)
                assetProc._maybeFinalize();
            else
                assetFlushTimer.restart();
        }
        function _maybeFinalize(): void {
            if (!assetProc._exited || assetProc._finalized || !assetProc._stdoutDone)
                return;
            assetProc._finalized = true;
            assetFlushTimer.stop();
            assetTimeout.stop();
            try {
                const payload = JSON.parse(assetStdout.text);
                if (payload && payload.ok && payload.hasImage && payload.markdownEmbed) {
                    const embedStr = String(payload.markdownEmbed);
                    const relOut = String(payload.relPath ?? "");
                    root.vimStatusMessage = "Saved image: " + String(payload.filename ?? relOut);
                    root.clipboardImagePasted(embedStr, relOut);
                } else if (payload && payload.ok && !payload.hasImage) {
                    root.vimStatusMessage = "Clipboard does not contain an image";
                } else if (payload?.error) {
                    root.errorMessage = String(payload.error);
                }
            } catch (e) {}
        }
    }

    Timer {
        id: pdfTimeout
        interval: 12000
        repeat: false
        onTriggered: {
            if (pdfProc.running)
                pdfProc.running = false;
            pdfFlushTimer.stop();
            root.pdfBusy = false;
        }
    }

    Timer {
        id: pdfFlushTimer
        interval: 60
        repeat: false
        onTriggered: {
            if (pdfProc._exited && !pdfProc._finalized) {
                pdfProc._stdoutDone = true;
                pdfProc._maybeFinalize();
            }
        }
    }

    Process {
        id: pdfProc
        property string opKind: ""
        property bool _exited: false
        property int _exitCode: 0
        property bool _stdoutDone: false
        property bool _finalized: false
        stdout: StdioCollector {
            id: pdfStdout
            onStreamFinished: {
                pdfProc._stdoutDone = true;
                pdfProc._maybeFinalize();
            }
        }
        onStarted: {
            pdfProc._exited = false;
            pdfProc._exitCode = 0;
            pdfProc._stdoutDone = false;
            pdfProc._finalized = false;
            pdfFlushTimer.stop();
        }
        onExited: (code, status) => {
            pdfProc._exited = true;
            pdfProc._exitCode = code;
            if (pdfProc._stdoutDone)
                pdfProc._maybeFinalize();
            else
                pdfFlushTimer.restart();
        }
        function _maybeFinalize(): void {
            if (!pdfProc._exited || pdfProc._finalized || !pdfProc._stdoutDone)
                return;
            pdfProc._finalized = true;
            pdfFlushTimer.stop();
            pdfTimeout.stop();
            root.pdfBusy = false;
            try {
                const payload = JSON.parse(pdfStdout.text);
                if (!payload || !payload.ok) {
                    if (payload?.error)
                        root.vimStatusMessage = String(payload.error);
                    return;
                }
                if (pdfProc.opKind === "info") {
                    root.pdfInfo = payload;
                    Qt.callLater(() => {
                        if (root._live)
                            root.pdfLoadPage(1, root.pdfDpi);
                    });
                } else if (pdfProc.opKind === "render") {
                    root.pdfPageImageUrl = String(payload.fileUrl ?? ("file://" + String(payload.imagePath ?? "")));
                } else if (pdfProc.opKind === "extract-text") {
                    root.pdfExtractedText = String(payload.text ?? "");
                } else if (pdfProc.opKind === "capture-highlight") {
                    const noteRel = String(payload.relPath ?? "");
                    root.vimStatusMessage = "Saved PDF highlight to " + noteRel;
                    root._rescanAfterDoc = false;
                    root.refreshVault();
                    root.pdfHighlightCaptured(noteRel, Number(payload.page ?? root.pdfCurrentPage));
                }
            } catch (e) {}
        }
    }

    Timer {
        id: pdfTextTimeout
        interval: 12000
        repeat: false
        onTriggered: {
            if (pdfTextProc.running)
                pdfTextProc.running = false;
            pdfTextFlushTimer.stop();
        }
    }

    Timer {
        id: pdfTextFlushTimer
        interval: 120
        repeat: false
        onTriggered: {
            if (pdfTextProc._exited && !pdfTextProc._finalized) {
                pdfTextProc._stdoutDone = true;
                pdfTextProc._maybeFinalize();
            }
        }
    }

    Process {
        id: pdfTextProc
        property string _requestTarget: ""
        property int _requestPage: 1
        property bool _exited: false
        property int _exitCode: 0
        property bool _stdoutDone: false
        property bool _finalized: false
        stdout: StdioCollector {
            id: pdfTextStdout
            onStreamFinished: {
                pdfTextProc._stdoutDone = true;
                pdfTextProc._maybeFinalize();
            }
        }
        onStarted: {
            pdfTextProc._exited = false;
            pdfTextProc._exitCode = 0;
            pdfTextProc._stdoutDone = false;
            pdfTextProc._finalized = false;
            pdfTextFlushTimer.stop();
        }
        onExited: (code, status) => {
            pdfTextProc._exited = true;
            pdfTextProc._exitCode = code;
            if (pdfTextProc._stdoutDone)
                pdfTextProc._maybeFinalize();
            else
                pdfTextFlushTimer.restart();
        }
        function _maybeFinalize(): void {
            if (!pdfTextProc._exited || pdfTextProc._finalized || !pdfTextProc._stdoutDone)
                return;
            pdfTextProc._finalized = true;
            pdfTextFlushTimer.stop();
            pdfTextTimeout.stop();
            const curTarget = String(root.pdfLastTarget || root.currentDoc?.absPath || "").trim();
            if (pdfTextProc._requestTarget !== curTarget || pdfTextProc._requestPage !== root.pdfCurrentPage)
                return;
            try {
                const payload = JSON.parse(pdfTextStdout.text);
                if (payload && payload.ok)
                    root.pdfExtractedText = String(payload.text ?? "");
            } catch (e) {}
        }
    }

    FileView {
        id: workspacePrefsFileView
        path: Qt.resolvedUrl(root.workspaceStatePath)
        watchChanges: false
        printErrors: false
        onLoaded: {
            try {
                const raw = workspacePrefsFileView.text();
                if (!raw || raw.trim().length === 0)
                    return;
                const parsed = JSON.parse(raw);
                if (parsed && typeof parsed === "object") {
                    const schemaVer = Number(parsed.version ?? 1);
                    const lay = parsed.layout;
                    if (lay && typeof lay === "object") {
                        if (schemaVer >= 3) {
                            if (typeof lay.leftSidebarWidth === "number")
                                root.leftSidebarWidth = Math.round(Math.max(160, Math.min(540, lay.leftSidebarWidth)));
                            if (typeof lay.rightSidebarWidth === "number")
                                root.rightSidebarWidth = Math.round(Math.max(180, Math.min(540, lay.rightSidebarWidth)));
                            if (typeof lay.leftSplitRatio === "number")
                                root.leftSplitRatio = Math.max(0.18, Math.min(0.84, lay.leftSplitRatio));
                            if (typeof lay.rightTopRatio === "number")
                                root.rightTopRatio = Math.max(0.16, Math.min(0.65, lay.rightTopRatio));
                            if (typeof lay.rightMidRatio === "number")
                                root.rightMidRatio = Math.max(0.15, Math.min(0.62, lay.rightMidRatio));
                            if (typeof lay.homepageHeroHeight === "number")
                                root.homepageHeroHeight = Math.round(Math.max(170, Math.min(440, lay.homepageHeroHeight)));
                            if (typeof lay.homepageScheduleHeight === "number")
                                root.homepageScheduleHeight = Math.round(Math.max(130, Math.min(440, lay.homepageScheduleHeight)));
                        } else {
                            // Heal legacy pre-v3 dimensions that were saved while sidebar Layout.minimumWidth/maximumWidth or delta resize was missing
                            root.leftSidebarWidth = 268;
                            root.rightSidebarWidth = 288;
                            root.leftSplitRatio = 0.62;
                            root.rightTopRatio = 0.34;
                            root.rightMidRatio = 0.32;
                            root.homepageHeroHeight = 270;
                            root.homepageScheduleHeight = 216;
                        }
                        if (Array.isArray(lay.cardOrder) && lay.cardOrder.length === 5) {
                            const valid = root.defaultCardOrder.every(id => lay.cardOrder.indexOf(id) !== -1);
                            if (valid)
                                root.cardOrder = lay.cardOrder.slice();
                        }
                    }
                    if (parsed.shortcuts && typeof parsed.shortcuts === "object") {
                        root.userShortcuts = Object.assign({}, parsed.shortcuts);
                        root._shortcutRevision += 1;
                    }
                    if (parsed.workspaceExtras && typeof parsed.workspaceExtras === "object") {
                        const ex = parsed.workspaceExtras;
                        if (Array.isArray(ex.openTabs))
                            root.openTabs = ex.openTabs.slice(0, 24);
                        if (typeof ex.localGraphDepth === "number")
                            root.localGraphDepth = Math.max(1, Math.min(3, Math.round(ex.localGraphDepth)));
                        if (Array.isArray(ex.savedGraphPresets))
                            root.savedGraphPresets = ex.savedGraphPresets.slice(0, 16);
                        if (ex.supertagSchemas && typeof ex.supertagSchemas === "object")
                            root.supertagSchemas = Object.assign({}, ex.supertagSchemas);
                        if (Array.isArray(ex.savedDatabaseViews))
                            root.savedDatabaseViews = ex.savedDatabaseViews.slice(0, 24);
                    }
                    root._workspacePrefsLoaded = true;
                    if (schemaVer < 3)
                        root._saveWorkspacePrefs();
                }
            } catch (e) {}
            root._workspacePrefsLoaded = true;
        }
        onLoadFailed: _err => {
            root._workspacePrefsLoaded = true;
        }
    }

    property bool hostLoaded: false
    property bool workspaceLoaded: false

    Connections {
        target: hostWindowLoader.item
        ignoreUnknownSignals: true
        function onWorkspaceLoadedChanged(): void {
            root.workspaceLoaded = Boolean(hostWindowLoader.item && hostWindowLoader.item.workspaceLoaded);
        }
    }

    IpcHandler {
        target: "nexusService"
        enabled: root._live
        function status(): string {
            return JSON.stringify({
                isOpen: root.isOpen,
                overlayMode: root.overlayMode,
                hostLoaded: root.hostLoaded,
                workspaceLoaded: root.workspaceLoaded,
                activeView: root.activeView,
                activeCollection: root.activeCollection,
                vaultConfigured: root.vaultConfigured,
                vaultLoaded: root.vaultLoaded,
                configuredVaultPath: root.configuredVaultPath,
                noteCount: Number(root.stats?.noteCount ?? 0),
                journalCount: Number(root.stats?.journalCount ?? 0),
                openTasks: Number(root.stats?.openTasks ?? 0),
                doneTasks: Number(root.stats?.doneTasks ?? 0),
                vaultAgeFormatted: String(root.stats?.vaultAgeFormatted ?? ""),
                localGraphNodes: Number(root.homepageLocalGraph?.nodes?.length ?? 0),
                vaultGraphEdges: Number(root.vaultGraph?.edges?.length ?? 0),
                calendarCellsCount: Number(root.calendarCells?.length ?? 0),
                dailyScheduleAvailable: Boolean(root.dailySchedule?.available ?? false),
                dailyScheduleRows: Number(root.dailySchedule?.scheduleRows?.length ?? 0),
                moviesCount: Number(root.collections?.movies?.length ?? 0),
                tvSeriesCount: Number(root.collections?.tvseries?.length ?? 0),
                gamesCount: Number(root.collections?.games?.length ?? 0),
                booksCount: Number(root.collections?.books?.length ?? 0),
                recipesCount: Number(root.collections?.recipes?.length ?? 0),
                exercisesCount: Number(root.collections?.exercises?.length ?? 0),
                clippingsCount: Number(root.collections?.clippings?.length ?? 0),
                financeCount: Number(root.collections?.finance?.length ?? 0),
                websitesCount: Number(root.collections?.websites?.length ?? 0),
                cornellCount: Number(root.collections?.cornell?.length ?? 0),
                zettelkastenCount: Number(root.collections?.zettelkasten?.length ?? 0),
                placesCount: Number(root.collections?.places?.length ?? 0),
                contactsCount: Number(root.collections?.contacts?.length ?? 0),
                vaultHotkeysCount: Object.keys(root.vaultHotkeys ?? {}).length,
                shortcutCatalogCount: Number(root.shortcutCatalog?.length ?? 0),
                cardOrder: root.cardOrder,
                leftSidebarWidth: root.leftSidebarWidth,
                rightSidebarWidth: root.rightSidebarWidth,
                homepageHeroHeight: root.homepageHeroHeight,
                homepageScheduleHeight: root.homepageScheduleHeight,
                errorMessage: root.errorMessage
            });
        }
    }

    Timer {
        id: plannerRangeTimer
        interval: 120
        repeat: false
        onTriggered: root._runPlannerRangeScan()
    }

    Process {
        id: plannerRangeProc
        running: false
        stdout: StdioCollector { id: plannerRangeOut }
        onExited: exitCode => {
            try {
                const payload = JSON.parse(String(plannerRangeOut.text ?? "").trim());
                if (exitCode === 0 && payload && payload.ok === true && Array.isArray(payload.events)) {
                    root.plannerTasks = payload.events;
                    root.plannerTasksRevision++;
                }
            } catch (_err) {}
            if (root._pendingRangeStart.length > 0 && root._pendingRangeEnd.length > 0)
                root._runPlannerRangeScan();
        }
    }

    Process {
        id: plannerTaskToggleProc
        running: false
        onExited: exitCode => {
            if (exitCode === 0) {
                if (root._plannerRangeStart.length > 0 && root._plannerRangeEnd.length > 0)
                    root.refreshPlannerRange(root._plannerRangeStart, root._plannerRangeEnd);
                if (HostServices.Todo && typeof HostServices.Todo.refresh === "function")
                    HostServices.Todo.refresh();
            }
        }
    }

    function refreshPlannerRange(startIso: string, endIso: string): void {
        const cleanStart = String(startIso ?? "").trim();
        const cleanEnd = String(endIso ?? "").trim();
        if (!cleanStart.length || !cleanEnd.length)
            return;
        root._plannerRangeStart = cleanStart;
        root._plannerRangeEnd = cleanEnd;
        if (!root.vaultConfigured || !root._dailyTodoHelperPath.length) {
            if (root.plannerTasks.length > 0) {
                root.plannerTasks = [];
                root.plannerTasksRevision++;
            }
            return;
        }
        root._pendingRangeStart = cleanStart;
        root._pendingRangeEnd = cleanEnd;
        plannerRangeTimer.restart();
    }

    function _runPlannerRangeScan(): void {
        if (!root._live || !root.vaultConfigured || !root._dailyTodoHelperPath.length)
            return;
        const startIso = root._pendingRangeStart || root._plannerRangeStart;
        const endIso = root._pendingRangeEnd || root._plannerRangeEnd;
        if (!startIso.length || !endIso.length || plannerRangeProc.running)
            return;
        const heading = String(Config.options?.todo?.nexus?.dailyNote?.plannerHeading ?? "Tasks").trim() || "Tasks";
        const headingLevel = Math.max(1, Math.min(6, Number(Config.options?.todo?.nexus?.dailyNote?.plannerHeadingLevel ?? 2)));
        const defaultDur = Math.max(5, Math.min(240, Number(Config.options?.todo?.nexus?.dailyNote?.defaultDurationMinutes ?? 30)));
        root._pendingRangeStart = "";
        root._pendingRangeEnd = "";
        plannerRangeProc.command = [
            "/usr/bin/python3",
            root._dailyTodoHelperPath,
            "scan-range",
            "--vault", root.configuredVaultPath,
            "--folder", root.dailyFolder,
            "--format", root.dailyFormat,
            "--start-date", startIso,
            "--end-date", endIso,
            "--heading", heading,
            "--heading-level", String(headingLevel),
            "--default-duration", String(defaultDur)
        ];
        plannerRangeProc.running = true;
    }

    function togglePlannerTask(taskEvent): bool {
        if (!taskEvent || !root.vaultConfigured || !root._dailyTodoHelperPath.length || plannerTaskToggleProc.running)
            return false;
        const taskId = String(taskEvent.taskId ?? "").trim();
        const srcDate = String(taskEvent.sourceDate ?? "").trim();
        const docSha = String(taskEvent.documentSha ?? "").trim();
        if (!taskId.length || !srcDate.length || !docSha.length)
            return false;
        const heading = String(Config.options?.todo?.nexus?.dailyNote?.plannerHeading ?? "Tasks").trim() || "Tasks";
        const headingLevel = Math.max(1, Math.min(6, Number(Config.options?.todo?.nexus?.dailyNote?.plannerHeadingLevel ?? 2)));
        const defaultDur = Math.max(5, Math.min(240, Number(Config.options?.todo?.nexus?.dailyNote?.defaultDurationMinutes ?? 30)));
        plannerTaskToggleProc.command = [
            "/usr/bin/python3",
            root._dailyTodoHelperPath,
            "toggle",
            "--vault", root.configuredVaultPath,
            "--folder", root.dailyFolder,
            "--format", root.dailyFormat,
            "--date", srcDate,
            "--heading", heading,
            "--heading-level", String(headingLevel),
            "--default-duration", String(defaultDur),
            "--id", taskId,
            "--expected-document-sha", docSha
        ];
        plannerTaskToggleProc.running = true;
        return true;
    }

    Loader {
        id: hostWindowLoader
        active: root._live && Quickshell.env("ALIS_NEXUS_HEADLESS_SERVICE_ONLY") !== "1"
        source: "../modules/nexus/NexusHost.qml"
        onItemChanged: {
            root.hostLoaded = status === Loader.Ready && item !== null;
            root.workspaceLoaded = Boolean(item && item.workspaceLoaded);
        }
        onStatusChanged: {
            root.hostLoaded = status === Loader.Ready && item !== null;
        }
        onLoaded: {
            if (item) {
                item.nexus = root;
                root.hostLoaded = true;
                root.workspaceLoaded = Boolean(item.workspaceLoaded);
            }
        }
    }
}
