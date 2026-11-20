import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.services as HostServices

Item {
    id: root
    property bool _live: true
    Component.onDestruction: root._live = false

    readonly property string binaryPath: decodeURIComponent(String(Qt.resolvedUrl("../assets/bin/alis-nexus")).replace(/^(?:file:\/\/|qs:)/, ""))
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
    property string activeView: "homepage" // "homepage" | "document" | "graph" | "collection"
    property string activeCollection: "movies" // "movies" | "tvseries" | "games" | "websites" | "cornell" | "zettelkasten" | "places"
    property string collectionFilterQuery: ""
    property string editorMode: "hybrid" // "hybrid" | "raw" | "split"
    property bool leftSidebarOpen: true
    property bool rightSidebarOpen: true
    property string leftSidebarTab: "files" // "files" | "tags" | "recent" | "search"
    property string rightBottomTab: "schedule" // "schedule" | "outline" | "flashcards"
    property string activeTagFilter: ""
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

    function _saveWorkspacePrefs(): void {
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
                "shortcuts": root.userShortcuts ?? ({})
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
        { "id": "heading6", "obsidianId": "editing-toolbar:header6-text", "obsidianCommand": "editing-toolbar:header6-text", "title": "Heading 6", "category": "Formatting", "defaultKey": "Ctrl+6", "description": "Format active block or line as ###### Heading 6" }
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

    // Vault scan state
    readonly property alias scanBusy: scanProc.running
    readonly property alias docBusy: docProc.running
    readonly property bool busy: scanProc.running || docProc.running || calendarProc.running || searchProc.running
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

    readonly property var hierarchicalTagsList: {
        const rawList = Array.isArray(root.tagsList) ? root.tagsList : [];
        const nodes = Object.create(null);
        const roots = [];
        for (let i = 0; i < rawList.length; ++i) {
            const item = rawList[i];
            if (!item)
                continue;
            const rawName = String(item.name ?? item.tag ?? "").trim().replace(/^#+/, "");
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
        function sortNodes(list) {
            list.sort((a, b) => b.totalCount - a.totalCount || a.name.localeCompare(b.name));
        }
        const out = [];
        function appendNode(node) {
            const expanded = Boolean(root.expandedParentTags[node.name]);
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
            cells.push({ "day": d, "month": prevM, "year": prevY, "dateStr": ds, "inMonth": false, "isToday": ds === todayIso, "hasJournal": false, "journalPath": "", "openTasks": 0, "doneTasks": 0 });
        }
        for (let d = 1; d <= daysInCur; ++d) {
            const ds = String(y) + "-" + pad2(m) + "-" + pad2(d);
            cells.push({ "day": d, "month": m, "year": y, "dateStr": ds, "inMonth": true, "isToday": ds === todayIso, "hasJournal": false, "journalPath": "", "openTasks": 0, "doneTasks": 0 });
        }
        let nextD = 1;
        while (cells.length < 42) {
            const ds = String(nextY) + "-" + pad2(nextM) + "-" + pad2(nextD);
            cells.push({ "day": nextD, "month": nextM, "year": nextY, "dateStr": ds, "inMonth": false, "isToday": ds === todayIso, "hasJournal": false, "journalPath": "", "openTasks": 0, "doneTasks": 0 });
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
        root.setOverlayMode(false);
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
    }

    function toggle(): void {
        if (root.isOpen)
            root.close();
        else
            root.open();
    }

    function setOverlayMode(enabled: bool): void {
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

        function walk(node, depth, inheritedColor, inheritedTextColor, inheritedPrefix) {
            if (!node || !Array.isArray(node.children))
                return;
            for (let i = 0; i < node.children.length; ++i) {
                const child = node.children[i];
                if (!child)
                    continue;
                const folderColor = (child.colorHex && String(child.colorHex).length > 0) ? String(child.colorHex) : (inheritedColor || "");
                const folderText = (child.textColorHex && String(child.textColorHex).length > 0) ? String(child.textColorHex) : (inheritedTextColor || "");
                const folderPrefix = (child.prefixCode && String(child.prefixCode).length > 0) ? String(child.prefixCode) : (inheritedPrefix || "");
                if (child.isDir) {
                    if (filter.length > 0) {
                        rows.push({
                            "name": child.name,
                            "relPath": child.relPath,
                            "isDir": true,
                            "depth": depth,
                            "expanded": true,
                            "category": "folder",
                            "ext": "",
                            "noteCount": child.noteCount ?? 0,
                            "prefixCode": folderPrefix,
                            "colorHex": folderColor,
                            "textColorHex": folderText,
                            "iconName": child.iconName ?? "folder"
                        });
                        walk(child, depth + 1, folderColor, folderText, folderPrefix);
                    } else {
                        const isExp = Boolean(root.expandedFolders[child.relPath]);
                        rows.push({
                            "name": child.name,
                            "relPath": child.relPath,
                            "isDir": true,
                            "depth": depth,
                            "expanded": isExp,
                            "category": "folder",
                            "ext": "",
                            "noteCount": child.noteCount ?? 0,
                            "prefixCode": folderPrefix,
                            "colorHex": folderColor,
                            "textColorHex": folderText,
                            "iconName": child.iconName ?? "folder"
                        });
                        if (isExp)
                            walk(child, depth + 1, folderColor, folderText, folderPrefix);
                    }
                } else {
                    if (filter.length > 0) {
                        const matchName = String(child.name ?? "").toLowerCase().indexOf(filter) !== -1;
                        const matchPath = String(child.relPath ?? "").toLowerCase().indexOf(filter) !== -1;
                        if (!matchName && !matchPath)
                            continue;
                    }
                    rows.push({
                        "name": child.name,
                        "relPath": child.relPath,
                        "isDir": false,
                        "depth": depth,
                        "expanded": false,
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

        walk(root.tree, 0, "", "", "");
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
            Quickshell.execDetached(["wl-copy", s]);
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
        const cleanBase = String(baseTitle ?? "Untitled").trim() || "Untitled";
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

    function refreshCalendar(year: int, month: int): void {
        if (!root.vaultConfigured || calendarProc.running)
            return;
        const y = year > 0 ? year : root.calendarYear;
        const m = (month >= 1 && month <= 12) ? month : root.calendarMonth;
        root.calendarYear = y;
        root.calendarMonth = m;
        calendarProc.response = "";
        calendarProc.command = [root.binaryPath, "calendar", "--vault", root.configuredVaultPath, "--year", String(y), "--month", String(m)];
        calendarProc.running = true;
        calendarTimeout.restart();
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

    function _enqueueDocOp(req): void {
        root._docQueue.push(req);
        root._runNextDocOp();
    }

    function _runNextDocOp(): void {
        if (docProc.running || root._docQueue.length === 0)
            return;
        const nextReq = root._docQueue.shift();
        root._activeDocReq = nextReq;
        root._docStartedAtMs = Date.now();
        docProc.response = "";
        docProc.stdinPayload = nextReq.stdinPayload ?? "";
        docProc.stdinEnabled = Boolean(nextReq.useStdin);
        docProc.command = nextReq.args;
        docProc.running = true;
        docTimeout.restart();
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
            } else {
                root.openCollection("movies");
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

    function saveCurrentNote(newContent = null): void {
        if (!root.vaultConfigured || root.currentPath.length === 0)
            return;
        const body = newContent !== null ? String(newContent) : root.draftContent;
        root.draftContent = body;
        root._rescanAfterDoc = false;
        root._enqueueDocOp({
            "kind": "write",
            "relPath": root.currentPath,
            "recordHistory": false,
            "useStdin": true,
            "stdinPayload": body,
            "args": [root.binaryPath, "write", "--vault", root.configuredVaultPath, "--path", root.currentPath]
        });
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

    function updateNoteFrontmatter(updatesObj): bool {
        return root.setFrontmatter(root.currentPath, updatesObj);
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

    function saveNoteBodyMarkdown(newBodyText: string): void {
        if (!root.vaultConfigured || root.currentPath.length === 0 || !root.currentDoc)
            return;
        const raw = String(root.currentDoc.content ?? root.draftContent ?? "").replace(/\r\n/g, "\n");
        const lines = raw.split("\n");
        const startIdx = Math.max(0, Number(root.currentDoc.bodyStartLine ?? 1) - 1);
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
        root.saveCurrentNote(combined);
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
        if (searchProc.inFlight || !root._pendingSearch)
            return;
        searchProc.request = root._pendingSearch;
        root._pendingSearch = null;
        searchProc.response = "";
        searchProc.command = [root.binaryPath, "search", "--vault", searchProc.request.vault, "--query", searchProc.request.query];
        searchProc.started = false;
        searchProc.inFlight = true;
        searchProc.running = true;
        searchTimeout.restart();
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
        if (!root.currentDoc || !Array.isArray(root.currentDoc.flashcards) || root.currentDoc.flashcards.length === 0)
            return 0;
        const sr = HostServices.AlisIntergration?.spacedRepetition ?? HostServices.AlisIntergration?.session?.spacedRepetition ?? null;
        const lines = [];
        for (let i = 0; i < root.currentDoc.flashcards.length; ++i) {
            const card = root.currentDoc.flashcards[i];
            if (card && card.front && card.back)
                lines.push(card.front + " :: " + card.back);
        }
        if (lines.length === 0)
            return 0;
        if (sr && typeof sr.importQuickText === "function") {
            const count = sr.importQuickText(lines.join("\n"), root.currentDoc.title ?? "Nexus", root.currentDoc.tags ?? ["nexus"]);
            root.vimStatusMessage = "Synced " + count + " flashcards to Spaced Repetition";
            return count;
        }
        root.vimStatusMessage = "Enable Spaced Repetition integration to sync flashcards";
        return 0;
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
        default:
            return false;
        }
    }

    function handleKeyEvent(event): bool {
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
                    parts.push(String(f.relPath ?? "") + ":" + String(f.mtimeMs ?? 0) + ":" + String(f.size ?? 0));
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
        root.collections = payload.collections ?? root.collections;
        root.stats = payload.stats ?? root.stats;
        root._loadedVaultPath = root.configuredVaultPath;
        root.vaultLoaded = true;
        root.errorMessage = "";
        root._rebuildVisibleTreeRows();
        if (!fromCache) {
            root._lastScanDoneMs = Date.now();
            root._syncScannedJournalCheckIn(root.todayJournalInfo);
        }
    }

    Timer {
        id: sleepResumeWatchdog
        interval: 15000
        repeat: true
        running: root._live && Quickshell.env("ALIS_NEXUS_HEADLESS_SERVICE_ONLY") !== "1"
        onTriggered: {
            const now = Date.now();
            const delta = now - root._lastHeartbeatMs;
            root._lastHeartbeatMs = now;
            if (scanProc.running && (now - root._scanStartedAtMs > 11000)) {
                scanProc.running = false;
            }
            if (docProc.running && (now - root._docStartedAtMs > 11000)) {
                docProc.running = false;
            }
            // If wall clock jumped >35s (woke up from system suspend/sleep), refresh cleanly in background
            if (delta > 35000 && root.vaultConfigured) {
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
            if (req && req.kind === "journal-weather") {
                const pending = Object.assign({}, root._weatherSyncInFlight);
                const remaining = Math.max(0, Number(pending[req.relPath] ?? 0) - 1);
                if (remaining > 0) pending[req.relPath] = remaining;
                else delete pending[req.relPath];
                root._weatherSyncInFlight = pending;
            }
            try {
                const payload = JSON.parse(docStdoutCollector.text);
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
                            if (!root.isDirty)
                                root.draftContent = String(payload.content ?? "");
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
                    } else if (payload.category === "external") {
                        const absPath = String(payload.absPath ?? "");
                        root.lastExternalOpenedPath = absPath;
                        root.openExternally(absPath, "Opened externally: " + String(payload.title ?? "") + "." + String(payload.ext ?? ""));
                        root.externalFileDispatched(absPath);
                        root.fileOpened(String(payload.relPath ?? ""), "external");
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
                        const isSaveOnly = Boolean(req && (req.kind === "write" || req.kind === "toggle-todo" || req.kind === "update-block" || req.kind === "set-frontmatter" || req.kind === "sync-api"));
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
                        if (!isSaveOnly)
                            root.activeView = "document";
                        if (switchingFile) {
                            root.foldedBlocks = ({});
                            root.editingBlockId = -1;
                            root.editorMode = "hybrid";
                            root.vimMode = "NORMAL";
                            root.vimUndoStack = [];
                            root.vimRedoStack = [];
                        }
                        if (req && (req.kind === "write" || req.kind === "toggle-todo" || req.kind === "update-block" || req.kind === "set-frontmatter" || req.kind === "sync-api")) {
                            root.noteSaved(newRel);
                            root.vimStatusMessage = req.kind === "sync-api" ? ("Synced metadata: " + newRel) : ("Saved " + newRel);
                        } else {
                            root.vimStatusMessage = newRel;
                        }
                        root.fileOpened(newRel, String(payload.category ?? "markdown"));
                        if (req && req.kind === "read")
                            root.fileRead(newRel);
                    }
                } else {
                    if (req && req.kind === "delete" && req.relPath)
                        root._restoreDeleteSnapshot(String(req.relPath));
                    root.errorMessage = String(payload?.error ?? "Document operation failed");
                    root.vimStatusMessage = root.errorMessage;
                }
            } catch (e) {
                if (req && req.kind === "delete" && req.relPath)
                    root._restoreDeleteSnapshot(String(req.relPath));
                root.errorMessage = "Could not parse document response";
                root.vimStatusMessage = root.errorMessage;
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
                const payload = JSON.parse(calendarStdoutCollector.text);
                if (payload && payload.ok) {
                    root.calendarHeader = String(payload.headerLabel ?? "");
                    root.calendarCells = payload.cells ?? [];
                    root._calendarLoadedFromCli = true;
                }
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
                const payload = JSON.parse(searchStdoutCollector.text);
                if (code === 0 && payload?.ok && request
                    && request.generation === root._searchGeneration
                    && request.vault === root.configuredVaultPath
                    && request.query === root.searchQuery.trim()
                    && String(payload.query ?? "") === request.query) {
                    root.searchResults = payload.results ?? [];
                }
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
                    if (schemaVer < 3)
                        root._saveWorkspacePrefs();
                }
            } catch (e) {}
        }
    }

    readonly property bool hostLoaded: hostWindowLoader.status === Loader.Ready && hostWindowLoader.item !== null
    readonly property bool workspaceLoaded: Boolean(hostWindowLoader.item?.workspaceLoaded ?? false)

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

    Loader {
        id: hostWindowLoader
        active: root._live && Quickshell.env("ALIS_NEXUS_HEADLESS_SERVICE_ONLY") !== "1"
        source: "../modules/nexus/NexusHost.qml"
        onLoaded: {
            if (item)
                item.nexus = root;
        }
    }
}
