import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

Item {
    id: root
    property bool isOpen: false
    property bool overlayMode: true
    property bool _hostWarmed: false

    // Navigation & listing state
    property string homePath: Quickshell.env("HOME") || "/"
    property string configHomePath: Quickshell.env("XDG_CONFIG_HOME") || (homePath + "/.config")
    property string trashPath: (Quickshell.env("XDG_DATA_HOME") || (homePath + "/.local/share")) + "/Trash/files"
    property string currentPath: homePath
    property string parentPath: ""
    property bool isTrash: false
    property var dirEntry: null
    property var entries: []
    property var tabs: [] // [{ path, title, backStack, forwardStack, split: null | { path, title, backStack, forwardStack } }]
    property int activeTab: 0
    readonly property var currentTabObj: (root.tabs.length > 0)
        ? root.tabs[Math.max(0, Math.min(root.activeTab, root.tabs.length - 1))]
        : null
    readonly property bool splitOpen: Boolean(root.currentTabObj && root.currentTabObj.split)
    property bool activeIsSecondary: false
    property real splitRatio: 0.5
    property string secondaryPath: homePath
    property string secondaryParentPath: ""
    property bool secondaryIsTrash: false
    property var secondaryDirEntry: null
    property var secondaryEntries: []
    property var secondarySelectedPaths: []
    property string secondaryGitBranch: ""
    property var secondaryGitBadges: ({})
    readonly property bool _useSec: root.splitOpen && root.activeIsSecondary
    readonly property string activePath: _useSec ? root.secondaryPath : root.currentPath
    readonly property string activeParentPath: _useSec ? root.secondaryParentPath : root.parentPath
    readonly property bool activeIsTrash: _useSec ? root.secondaryIsTrash : root.isTrash
    readonly property var activeDirEntry: _useSec ? root.secondaryDirEntry : root.dirEntry
    readonly property var activeEntries: _useSec ? root.secondaryEntries : root.entries
    readonly property var activeTabs: root.tabs
    readonly property int activeTabIndex: root.activeTab
    readonly property var activeTabNode: (root.splitOpen && root.activeIsSecondary)
        ? (root.currentTabObj?.split ?? null)
        : root.currentTabObj
    readonly property var activeSelectedPaths: _useSec ? root.secondarySelectedPaths : root.selectedPaths
    readonly property string activeGitBranch: _useSec ? root.secondaryGitBranch : root.gitBranch
    readonly property var activeGitBadges: _useSec ? root.secondaryGitBadges : root.gitBadges
    property string _lastSessionJson: ""
    property var places: []
    property var bookmarks: []
    property var drives: []
    property var recentFolders: []

    // View & preference state
    property string viewMode: "grid"
    property bool showHidden: false
    property bool railOpen: true
    property bool inspectorOpen: false
    property int railWidth: 228
    property int inspectorWidth: 296
    property real inspectorPreviewRatio: 0.38
    property var propsData: null
    property bool propsLoading: false
    property string propsTargetPath: ""
    property var propsDirTotals: null
    property bool propsDirLoading: false
    property var propsChecksums: ({})
    property var propsChecksumBusy: ({})
    property int _propsGen: 0
    property bool dirsFirst: true
    property bool gitBadgesEnabled: true
    property bool thumbnailsEnabled: true
    property bool vimKeybindings: true
    property bool confirmPermanentDelete: true
    property string sortField: "name"
    property string sortOrder: "asc"
    property int gridIconSize: 72
    property int listZoom: 1

    // Filter / Search / Selection / Clipboard
    property string filterText: ""
    property bool recursiveSearch: false
    property bool searchBusy: false
    property var selectedPaths: []
    property var clipboardPaths: []
    property string clipboardOp: "" // "" | "copy" | "cut"

    // Git / Thumbnails / Disk / Undo / Toast
    property string gitBranch: ""
    property var gitBadges: ({})
    property var thumbMap: ({})
    readonly property var _thumbInFlight: ({})
    readonly property var _thumbPendingBatch: ({})
    property int _thumbPendingCount: 0
    readonly property int _thumbMapMaxEntries: 480
    property real totalBytes: 0
    property real freeBytes: 0
    property string freeLabel: ""
    property int trashCount: 0
    property bool canUndo: false
    property bool canRedo: false
    property string toastMessage: ""
    property bool toastUndoable: false
    property bool toastIsError: false
    property string errorMessage: ""

    // QuickLook state inside Overlay
    property var quickLookEntry: null
    property string quickLookText: ""
    property bool quickLookLoading: false

    // Daemon state
    property string binaryPath: ""
    property bool daemonReady: false
    property bool _daemonStarted: false
    property bool _live: true
    property int _reqSeq: 1
    readonly property var _pendingReqs: ({})
    property var _queuedCalls: []
    property string _pendingOpenPathAfterInit: ""
    property string _configPath: (Quickshell.env("XDG_CONFIG_HOME") || (homePath + "/.config")) + "/alis/alis-files.json"

    Component.onCompleted: {
        root.tabs = [{ path: root.homePath, title: "Home", backStack: [], forwardStack: [], split: null }];
        binaryResolver.running = true;
    }

    onIsOpenChanged: {
        if (root.isOpen) {
            root._hostWarmed = true;
            root.errorMessage = "";
            root._ensureDaemonRunning();
            if (root.daemonReady) {
                root._sendRpc("sync_config", {}, data => {
                    if (!data)
                        return;
                    if (Array.isArray(data.bookmarks))
                        root.bookmarks = data.bookmarks;
                    if (Array.isArray(data.recent))
                        root.recentFolders = data.recent;
                    if (typeof data.trash_count === "number")
                        root.trashCount = data.trash_count;
                    if (data.config && typeof data.config === "object") {
                        root._applyConfigJsonText(JSON.stringify(data.config));
                        if (data.config.session && typeof data.config.session === "object") {
                            const incomingJson = JSON.stringify(data.config.session);
                            if (incomingJson !== root._lastSessionJson)
                                root._applySessionData(data.config.session, true);
                        }
                    }
                });
                root._loadDirFor(root.currentPath, false, "primary");
                if (root.splitOpen)
                    root._loadDirFor(root.secondaryPath, false, "secondary");
                root._sendRpc("drives", {}, null);
            }
        } else {
            root.quickLookEntry = null;
            if (root.daemonReady)
                root.saveSessionNow();
        }
    }

    Timer {
        id: thumbFlushTimer
        interval: 32
        repeat: false
        onTriggered: root._flushThumbBatch()
    }

    function _flushThumbBatch(): void {
        if (root._thumbPendingCount <= 0)
            return;
        const batch = root._thumbPendingBatch;
        const next = Object.assign({}, root.thumbMap);
        for (const k in batch) {
            next[k] = batch[k];
            delete batch[k];
        }
        root._thumbPendingCount = 0;
        const keys = Object.keys(next);
        if (keys.length > root._thumbMapMaxEntries) {
            const keep = Object.create(null);
            for (const e of (root.entries ?? []))
                keep[String(e?.path ?? "")] = true;
            for (const e of (root.secondaryEntries ?? []))
                keep[String(e?.path ?? "")] = true;
            let excess = keys.length - root._thumbMapMaxEntries;
            for (let i = 0; i < keys.length && excess > 0; ++i) {
                if (!keep[keys[i]]) {
                    delete next[keys[i]];
                    excess--;
                }
            }
        }
        root.thumbMap = next;
    }

    Timer {
        id: sessionSaveTimer
        interval: 250
        repeat: false
        onTriggered: root.saveSessionNow()
    }

    Timer {
        id: prefsReloadTimer
        interval: 80
        repeat: false
        onTriggered: prefsView.reload()
    }

    Timer {
        id: paneSizeSaveTimer
        interval: 180
        repeat: false
        onTriggered: root._saveConfigFields({
            rail_width: root.railWidth,
            inspector_width: root.inspectorWidth,
            inspector_preview_ratio_milli: Math.max(220, Math.min(720, Math.round(root.inspectorPreviewRatio * 1000)))
        })
    }

    FileView {
        id: prefsView
        path: "file://" + root._configPath
        preload: true
        watchChanges: root._live
        printErrors: false
        onLoaded: root._applyConfigJsonText(prefsView.text())
        onFileChanged: prefsReloadTimer.restart()
        onLoadFailed: {}
    }

    function _applyConfigJsonText(raw): void {
        try {
            const doc = JSON.parse(String(raw ?? "").trim() || "{}");
            if (!doc || typeof doc !== "object")
                return;
            const prevShowHidden = root.showHidden;
            const prevDirsFirst = root.dirsFirst;
            const prevSortField = root.sortField;
            const prevSortOrder = root.sortOrder;

            if (Array.isArray(doc.bookmarks)) {
                const nextBm = doc.bookmarks
                    .map(b => ({ name: String(b?.name ?? ""), path: String(b?.path ?? "") }))
                    .filter(b => b.path.length > 0);
                if (JSON.stringify(nextBm) !== JSON.stringify(root.bookmarks))
                    root.bookmarks = nextBm;
            }
            if (typeof doc.overlay_mode === "boolean")
                root.overlayMode = doc.overlay_mode;
            if (doc.view_mode === "list" || doc.view_mode === "grid" || doc.view_mode === "gallery")
                root.viewMode = doc.view_mode;
            if (typeof doc.show_hidden === "boolean")
                root.showHidden = doc.show_hidden;
            if (typeof doc.rail_open === "boolean")
                root.railOpen = doc.rail_open;
            if (typeof doc.rail_width === "number")
                root.railWidth = Math.max(156, Math.min(460, Math.round(doc.rail_width)));
            if (typeof doc.inspector_open_default === "boolean")
                root.inspectorOpen = doc.inspector_open_default;
            if (typeof doc.inspector_width === "number")
                root.inspectorWidth = Math.max(200, Math.min(560, Math.round(doc.inspector_width)));
            if (typeof doc.inspector_preview_ratio_milli === "number")
                root.inspectorPreviewRatio = Math.max(0.22, Math.min(0.72, doc.inspector_preview_ratio_milli / 1000.0));
            if (typeof doc.directories_first === "boolean")
                root.dirsFirst = doc.directories_first;
            if (typeof doc.git_badges === "boolean")
                root.gitBadgesEnabled = doc.git_badges;
            if (typeof doc.thumbnails_enabled === "boolean")
                root.thumbnailsEnabled = doc.thumbnails_enabled;
            if (typeof doc.vim_keybindings === "boolean")
                root.vimKeybindings = doc.vim_keybindings;
            if (typeof doc.confirm_permanent_delete === "boolean")
                root.confirmPermanentDelete = doc.confirm_permanent_delete;
            if (typeof doc.sort_field === "string")
                root.sortField = doc.sort_field;
            if (typeof doc.sort_order === "string")
                root.sortOrder = doc.sort_order;
            if (typeof doc.grid_icon_size === "number")
                root.gridIconSize = Math.max(40, Math.min(240, Math.round(doc.grid_icon_size)));
            if (typeof doc.list_zoom === "number")
                root.listZoom = Math.max(0, Math.min(2, Math.round(doc.list_zoom)));

            const listingChanged = (root.showHidden !== prevShowHidden)
                || (root.dirsFirst !== prevDirsFirst)
                || (root.sortField !== prevSortField)
                || (root.sortOrder !== prevSortOrder);
            if (listingChanged && root.isOpen && root.daemonReady && root.currentPath.length > 0)
                root._loadDir(root.currentPath, false);
        } catch (_e) {}
    }

    Process {
        id: binaryResolver
        command: ["/bin/sh", "-c", "command -v alis-files || echo \"$HOME/.local/bin/alis-files\""]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const candidate = String(text ?? "").trim().split("\n")[0]?.trim() || "";
                if (candidate.length > 0)
                    root.binaryPath = candidate;
            }
        }
    }

    function _resolveBin(): string {
        if (root.binaryPath.length > 0)
            return root.binaryPath;
        return root.homePath + "/.local/bin/alis-files";
    }

    function _ensureDaemonRunning(): void {
        if (daemonProc.running)
            return;
        root.daemonReady = false;
        root._daemonStarted = false;
        daemonProc.command = [root._resolveBin(), "--overlay-daemon"];
        daemonProc.running = true;
    }

    function _makeTabNode(p: string): var {
        const clean = String(p ?? "").trim() || root.homePath;
        return { path: clean, title: root._tabTitleForPath(clean), backStack: [], forwardStack: [] };
    }

    function _makeTabSlot(p: string, splitPath = ""): var {
        const slot = root._makeTabNode(p);
        const sp = String(splitPath ?? "").trim();
        slot.split = sp.length > 0 ? root._makeTabNode(sp) : null;
        return slot;
    }

    function _applySessionData(sess: var, reloadListings: bool): void {
        if (!sess || typeof sess !== "object")
            return;
        root._lastSessionJson = JSON.stringify(sess);
        const built = [];
        if (Array.isArray(sess.tab_entries) && sess.tab_entries.length > 0) {
            for (const entry of sess.tab_entries) {
                const p = String(entry?.path ?? "").trim();
                if (p.length > 0)
                    built.push(root._makeTabSlot(p, String(entry?.split_path ?? "")));
            }
        } else if (Array.isArray(sess.tabs) && sess.tabs.length > 0) {
            for (const raw of sess.tabs) {
                const p = String(raw ?? "").trim();
                if (p.length > 0)
                    built.push(root._makeTabSlot(p, ""));
            }
        }
        if (built.length === 0)
            built.push(root._makeTabSlot(root.homePath, ""));

        const act = Math.max(0, Math.min(Number(sess.active_tab ?? 0), built.length - 1));
        if (!(Array.isArray(sess.tab_entries) && sess.tab_entries.length > 0) && sess.split_open === true) {
            const secTabs = Array.isArray(sess.secondary_tabs) ? sess.secondary_tabs : [];
            const secIdx = Math.max(0, Math.min(Number(sess.secondary_active_tab ?? 0), Math.max(0, secTabs.length - 1)));
            const secPath = String(secTabs[secIdx] ?? built[act].path);
            built[act].split = root._makeTabNode(secPath);
        }

        root.tabs = built;
        root.activeTab = act;
        root.currentPath = built[act].path;
        root.secondaryPath = built[act].split ? built[act].split.path : root.currentPath;

        if (typeof sess.split_ratio_milli === "number")
            root.splitRatio = Math.max(0.20, Math.min(0.80, Number(sess.split_ratio_milli) / 1000.0));
        root.activeIsSecondary = Boolean(built[act].split) && Boolean(sess.active_is_secondary);

        if (reloadListings && root.daemonReady) {
            root._loadDirFor(root.currentPath, false, "primary");
            if (root.splitOpen)
                root._loadDirFor(root.secondaryPath, false, "secondary");
        }
    }

    function saveSessionNow(): void {
        if (!root.daemonReady)
            return;
        const curSlot = root.currentTabObj;
        const payload = {
            tabs: root.tabs.map(t => String(t.path)),
            active_tab: root.activeTab,
            split_open: root.splitOpen,
            split_ratio_milli: Math.max(200, Math.min(800, Math.round(root.splitRatio * 1000))),
            secondary_tabs: curSlot?.split ? [String(curSlot.split.path)] : [],
            secondary_active_tab: 0,
            active_is_secondary: root.splitOpen && root.activeIsSecondary,
            tab_entries: root.tabs.map(t => ({
                path: String(t.path),
                split_path: t.split ? String(t.split.path) : null
            }))
        };
        root._lastSessionJson = JSON.stringify(payload);
        root._sendRpc("save_session", payload, null, null);
    }

    function _sendInitRpc(): void {
        root._sendRpc("init", {}, data => {
            root.daemonReady = true;
            root.homePath = String(data.home ?? root.homePath);
            root.trashPath = String(data.trash ?? root.trashPath);
            root.places = Array.isArray(data.places) ? data.places : [];
            root.bookmarks = Array.isArray(data.bookmarks) ? data.bookmarks : [];
            root.drives = Array.isArray(data.drives) ? data.drives : [];
            root.recentFolders = Array.isArray(data.recent) ? data.recent : [];
            root.trashCount = Number(data.trash_count ?? 0);
            root.canUndo = Boolean(data.can_undo);
            root.canRedo = Boolean(data.can_redo);
            if (data.config && typeof data.config === "object") {
                root._applyConfigJsonText(JSON.stringify(data.config));
                if (data.config.session && typeof data.config.session === "object")
                    root._applySessionData(data.config.session, false);
            }
            const explicitOpen = root._pendingOpenPathAfterInit.trim();
            root._pendingOpenPathAfterInit = "";
            if (explicitOpen.length > 0) {
                root.activeIsSecondary = false;
                root._loadDirFor(explicitOpen, false, "primary");
            } else {
                root._loadDirFor(root.currentPath || root.homePath, false, "primary");
            }
            if (root.splitOpen)
                root._loadDirFor(root.secondaryPath || root.homePath, false, "secondary");
        });
    }

    Process {
        id: daemonProc
        running: false
        stdinEnabled: true
        onStarted: {
            root._daemonStarted = true;
            const queued = root._queuedCalls.slice();
            root._queuedCalls = [];
            root._sendInitRpc();
            for (const line of queued)
                daemonProc.write(line);
        }
        stdout: SplitParser {
            onRead: line => root._handleDaemonLine(line)
        }
        stderr: StdioCollector {
            id: daemonStderr
        }
        onExited: (exitCode, _exitStatus) => {
            root.daemonReady = false;
            root._daemonStarted = false;
            const keys = Object.keys(root._pendingReqs);
            for (let i = 0; i < keys.length; ++i) {
                const entry = root._pendingReqs[keys[i]];
                delete root._pendingReqs[keys[i]];
                if (typeof entry?.cb === "function") {
                    try {
                        entry.cb(null, "Daemon exited");
                    } catch (_e) {}
                }
            }
            if (exitCode !== 0 && root.isOpen) {
                const err = String(daemonStderr.text ?? "").trim();
                root.errorMessage = err.length > 0 ? err : "Alis Files daemon stopped unexpectedly";
            }
        }
    }

    function _sendRpc(cmd: string, params: var, cb: var, meta = null): void {
        const id = root._reqSeq++;
        const payload = JSON.stringify({ id: id, cmd: cmd, params: params ?? ({}) }) + "\n";
        root._pendingReqs[String(id)] = { cmd: cmd, cb: cb, meta: meta };

        if (!daemonProc.running || !root._daemonStarted) {
            if (cmd !== "init")
                root._queuedCalls = root._queuedCalls.concat([payload]);
            if (!daemonProc.running)
                root._ensureDaemonRunning();
            return;
        }
        daemonProc.write(payload);
    }

    function _handleDaemonLine(line: string): void {
        const trimmed = String(line ?? "").trim();
        if (trimmed.length === 0)
            return;
        let msg = null;
        try {
            msg = JSON.parse(trimmed);
        } catch (_e) {
            return;
        }
        if (!msg || typeof msg !== "object")
            return;
        const idKey = String(msg.id ?? "");
        const handler = root._pendingReqs[idKey];
        if (handler !== undefined) {
            delete root._pendingReqs[idKey];
        }

        if (msg.ok !== true) {
            const err = String(msg.error ?? "Operation failed");
            if (handler?.meta?.silentError !== true)
                root.showToast(err, false, true);
            if (handler && typeof handler.cb === "function" && handler.cb.length >= 2)
                handler.cb(null, err);
            return;
        }

        const data = msg.data ?? ({});
        const cmd = handler?.cmd ?? "";
        const meta = handler?.meta ?? null;
        if (cmd === "list")
            root._applyListResult(data, meta);
        else if (cmd === "drives")
            root.drives = Array.isArray(data.drives) ? data.drives : root.drives;
        else if (cmd === "git_status")
            root._applyGitResult(data, meta);
        else if (cmd === "search")
            root._applySearchResult(data, meta);
        else if (cmd === "thumb")
            root._applyThumbResult(data);

        if (handler && typeof handler.cb === "function")
            handler.cb(data, null);
    }

    function _tabTitleForPath(p: string): string {
        if (p === root.trashPath)
            return "Trash";
        if (p === "/")
            return "/";
        if (p === root.homePath)
            return "Home";
        const parts = p.split("/").filter(Boolean);
        return parts.length > 0 ? parts[parts.length - 1] : p;
    }

    function _applyListResult(data, meta = null): void {
        const isSec = meta?.pane === "secondary";
        const fallbackPath = isSec ? root.secondaryPath : root.currentPath;
        const path = String(data.path ?? fallbackPath);
        const parent = String(data.parent ?? "");
        const trashFlag = Boolean(data.is_trash);
        const dirObj = (data.dir_entry && typeof data.dir_entry === "object") ? data.dir_entry : null;
        const listArr = Array.isArray(data.entries) ? data.entries : [];

        root.trashCount = Number(data.trash_count ?? root.trashCount);
        root.canUndo = Boolean(data.can_undo);
        root.canRedo = Boolean(data.can_redo);
        for (const k in root._thumbInFlight)
            delete root._thumbInFlight[k];
        root.errorMessage = "";

        if (data.recovered_from)
            root.showToast("Folder moved or unavailable; opened " + path, false);

        const validSet = ({});
        for (const e of listArr)
            validSet[String(e.path)] = true;

        if (isSec) {
            root.secondaryPath = path;
            root.secondaryParentPath = parent;
            root.secondaryIsTrash = trashFlag;
            root.secondaryDirEntry = dirObj;
            root.secondaryEntries = listArr;
            root.secondaryGitBranch = "";
            root.secondaryGitBadges = ({});

            const t = root.tabs.slice();
            const idx = Math.max(0, Math.min(root.activeTab, t.length - 1));
            if (t.length > 0 && t[idx].split) {
                const updatedSplit = Object.assign({}, t[idx].split, { path: path, title: root._tabTitleForPath(path) });
                t[idx] = Object.assign({}, t[idx], { split: updatedSplit });
                root.tabs = t;
            }
            root.secondarySelectedPaths = root.secondarySelectedPaths.filter(p => validSet[p] === true);
        } else {
            root.currentPath = path;
            root.parentPath = parent;
            root.isTrash = trashFlag;
            root.dirEntry = dirObj;
            root.entries = listArr;
            root.totalBytes = Number(data.total_bytes ?? 0);
            root.freeBytes = Number(data.free_bytes ?? 0);
            root.freeLabel = String(data.free_label ?? "");
            root.gitBranch = "";
            root.gitBadges = ({});

            const t = root.tabs.slice();
            const idx = Math.max(0, Math.min(root.activeTab, t.length - 1));
            if (t.length > 0) {
                t[idx] = Object.assign({}, t[idx], { path: path, title: root._tabTitleForPath(path) });
                root.tabs = t;
            }
            root.selectedPaths = root.selectedPaths.filter(p => validSet[p] === true);
        }

        if (isSec && root._useSec) {
            root.totalBytes = Number(data.total_bytes ?? root.totalBytes);
            root.freeBytes = Number(data.free_bytes ?? root.freeBytes);
            root.freeLabel = String(data.free_label ?? root.freeLabel);
        }

        if (root.gitBadgesEnabled && !trashFlag) {
            root._sendRpc("git_status", { path: path }, null, { pane: isSec ? "secondary" : "primary" });
        }
        sessionSaveTimer.restart();
    }

    function _applyGitResult(data, meta = null): void {
        const isSec = meta?.pane === "secondary";
        const expected = isSec ? root.secondaryPath : root.currentPath;
        if (String(data.path ?? "") !== expected)
            return;
        const br = String(data.branch ?? "");
        const bg = (data.badges && typeof data.badges === "object") ? data.badges : ({});
        if (isSec) {
            root.secondaryGitBranch = br;
            root.secondaryGitBadges = bg;
        } else {
            root.gitBranch = br;
            root.gitBadges = bg;
        }
    }

    function _applySearchResult(data, meta = null): void {
        root.searchBusy = false;
        if (!root.recursiveSearch || String(data.query ?? "") !== root.filterText)
            return;
        if (data.cancelled === true)
            return;
        const resArr = Array.isArray(data.entries) ? data.entries : [];
        if (meta?.pane === "secondary") {
            root.secondaryEntries = resArr;
            root.secondarySelectedPaths = [];
        } else {
            root.entries = resArr;
            root.selectedPaths = [];
        }
    }

    function _applyThumbResult(data): void {
        const p = String(data.path ?? "");
        if (p.length === 0)
            return;
        delete root._thumbInFlight[p];
        const tp = String(data.thumb_path ?? "");
        if (tp.length > 0) {
            root._thumbPendingBatch[p] = tp;
            root._thumbPendingCount++;
            if (root._thumbPendingCount >= 8) {
                thumbFlushTimer.stop();
                root._flushThumbBatch();
            } else if (!thumbFlushTimer.running) {
                thumbFlushTimer.start();
            }
        }
    }

    function _loadDirFor(path: string, clearSel: bool, pane: string): void {
        const isSec = pane === "secondary";
        const isActive = (isSec && root._useSec) || (!isSec && !root._useSec);
        if (clearSel) {
            if (isSec) root.secondarySelectedPaths = [];
            else root.selectedPaths = [];
        }
        root._sendRpc("list", {
            path: path,
            show_hidden: root.showHidden,
            sort_field: root.sortField,
            sort_order: root.sortOrder,
            dirs_first: root.dirsFirst,
            filter: (!isActive || root.recursiveSearch) ? "" : root.filterText
        }, null, { pane: isSec ? "secondary" : "primary" });
    }

    function _loadDir(path: string, clearSel: bool): void {
        root._loadDirFor(path, clearSel, root._targetPaneName());
    }

    // ── Public Lifecycle & IPC Methods (matching NexusService API) ────────

    function open(path = ""): void {
        if (!root.overlayMode) {
            root.openWindow(path);
            return;
        }
        root.openOverlay(path);
    }

    function openOverlay(path = ""): void {
        root.overlayMode = true;
        const cleaned = String(path ?? "").trim();
        if (cleaned.length > 0) {
            if (!root.daemonReady)
                root._pendingOpenPathAfterInit = cleaned;
            else
                root.navigate(cleaned);
        }
        root.isOpen = true;
    }

    function openWindow(path = ""): void {
        const target = String(path ?? "").trim() || root.activePath || root.homePath;
        Quickshell.execDetached([root._resolveBin(), "--new", target]);
    }

    function popOutToWindow(path = ""): void {
        const target = String(path ?? "").trim() || root.activePath || root.homePath;
        root.close();
        Quickshell.execDetached([root._resolveBin(), "--new", target]);
    }

    function openExternalPath(absPath: string): void {
        const cleaned = String(absPath ?? "").trim();
        if (cleaned.length === 0) {
            root.openOverlay("");
            return;
        }
        if (root.overlayMode)
            root.openOverlay(cleaned);
        else
            Quickshell.execDetached([root._resolveBin(), "--select", cleaned]);
    }

    function close(): void {
        root.isOpen = false;
    }

    function toggle(): void {
        if (root.isOpen)
            root.close();
        else if (root.overlayMode)
            root.openOverlay("");
        else
            root.openWindow("");
    }

    function setOverlayMode(enabled: bool): void {
        root.overlayMode = Boolean(enabled);
        root._saveConfigFields({ overlay_mode: root.overlayMode });
    }

    // ── Split View & Pane Routing ─────────────────────────────────────────

    function _targetPaneName(): string {
        return root._useSec ? "secondary" : "primary";
    }

    function setActivePane(isSecondary: bool): void {
        const target = Boolean(isSecondary) && root.splitOpen;
        if (root.activeIsSecondary === target)
            return;
        root.activeIsSecondary = target;
        sessionSaveTimer.restart();
    }

    function switchSplitPane(): void {
        if (!root.splitOpen)
            return;
        root.setActivePane(!root.activeIsSecondary);
    }

    function setSplitOpen(enabled: bool): void {
        const next = Boolean(enabled);
        const t = root.tabs.slice();
        if (t.length === 0)
            return;
        const idx = Math.max(0, Math.min(root.activeTab, t.length - 1));
        const cur = t[idx];

        if (next) {
            if (cur.split)
                return;
            if (idx + 1 < t.length && !t[idx + 1].split) {
                const neighbor = t.splice(idx + 1, 1)[0];
                const merged = Object.assign({}, cur, { split: { path: neighbor.path, title: neighbor.title, backStack: neighbor.backStack.slice(), forwardStack: neighbor.forwardStack.slice() } });
                t[idx] = merged;
                root.tabs = t;
                root.activeIsSecondary = false;
                root.secondaryPath = merged.split.path;
                if (root.daemonReady)
                    root._loadDirFor(root.secondaryPath, true, "secondary");
            } else if (idx > 0 && !t[idx - 1].split) {
                const prev = t[idx - 1];
                const curHalf = { path: cur.path, title: cur.title, backStack: cur.backStack.slice(), forwardStack: cur.forwardStack.slice() };
                t.splice(idx, 1);
                t[idx - 1] = Object.assign({}, prev, { split: curHalf });
                root.tabs = t;
                root.activeTab = idx - 1;
                root.currentPath = prev.path;
                root.secondaryPath = curHalf.path;
                root.activeIsSecondary = true;
                if (root.daemonReady) {
                    root._loadDirFor(root.currentPath, true, "primary");
                    root._loadDirFor(root.secondaryPath, true, "secondary");
                }
            } else {
                const dupHalf = root._makeTabNode(cur.path || root.currentPath || root.homePath);
                t[idx] = Object.assign({}, cur, { split: dupHalf });
                root.tabs = t;
                root.activeIsSecondary = false;
                root.secondaryPath = dupHalf.path;
                if (root.daemonReady)
                    root._loadDirFor(root.secondaryPath, true, "secondary");
            }
        } else {
            if (!cur.split)
                return;
            const wasSec = root.activeIsSecondary;
            const rightNode = cur.split;
            const leftTab = Object.assign({}, cur, { split: null });
            const rightTab = Object.assign({}, rightNode, { split: null });
            t.splice(idx, 1, leftTab, rightTab);
            const nextIdx = wasSec ? (idx + 1) : idx;
            root.tabs = t;
            root.activeTab = nextIdx;
            root.activeIsSecondary = false;
            root.currentPath = t[nextIdx].path;
            if (root.daemonReady && wasSec)
                root._loadDirFor(root.currentPath, true, "primary");
        }
        sessionSaveTimer.restart();
    }

    function toggleSplitView(): void {
        root.setSplitOpen(!root.splitOpen);
    }

    function setSplitRatio(ratio: real): void {
        const clamped = Math.max(0.20, Math.min(0.80, Number(ratio)));
        if (Math.abs(root.splitRatio - clamped) < 0.002)
            return;
        root.splitRatio = clamped;
        sessionSaveTimer.restart();
    }

    function setPaneSelectedPaths(isSecondary: bool, paths: var): void {
        const arr = Array.isArray(paths) ? paths : [];
        if (isSecondary && root.splitOpen)
            root.secondarySelectedPaths = arr;
        else
            root.selectedPaths = arr;
    }

    // ── Navigation & Tabs ─────────────────────────────────────────────────

    function navigate(path: string): void {
        const dest = String(path ?? "").trim() || root.homePath;
        const isSec = root._useSec;
        const t = root.tabs.slice();
        const idx = Math.max(0, Math.min(root.activeTab, t.length - 1));
        if (t.length > 0) {
            if (isSec && t[idx].split) {
                const cur = t[idx].split;
                if (cur.path !== dest) {
                    const bs = cur.backStack.slice();
                    bs.push(cur.path);
                    const nextSec = { path: dest, title: root._tabTitleForPath(dest), backStack: bs, forwardStack: [] };
                    t[idx] = Object.assign({}, t[idx], { split: nextSec });
                    root.tabs = t;
                }
            } else if (t[idx].path !== dest) {
                const cur = t[idx];
                const bs = cur.backStack.slice();
                bs.push(cur.path);
                t[idx] = Object.assign({}, cur, { path: dest, title: root._tabTitleForPath(dest), backStack: bs, forwardStack: [] });
                root.tabs = t;
            }
        }
        root.filterText = "";
        root.recursiveSearch = false;
        root._loadDirFor(dest, true, isSec ? "secondary" : "primary");
    }

    function goBack(): void {
        const isSec = root._useSec;
        const t = root.tabs.slice();
        const idx = Math.max(0, Math.min(root.activeTab, t.length - 1));
        if (t.length === 0)
            return;
        const cur = (isSec && t[idx].split) ? t[idx].split : t[idx];
        if (!cur || cur.backStack.length === 0)
            return;
        const bs = cur.backStack.slice();
        const prev = bs.pop();
        const fs = cur.forwardStack.slice();
        fs.push(cur.path);
        const updatedNode = { path: prev, title: root._tabTitleForPath(prev), backStack: bs, forwardStack: fs };
        if (isSec && t[idx].split)
            t[idx] = Object.assign({}, t[idx], { split: updatedNode });
        else
            t[idx] = Object.assign({}, t[idx], updatedNode);
        root.tabs = t;
        root._loadDirFor(prev, true, isSec ? "secondary" : "primary");
    }

    function goForward(): void {
        const isSec = root._useSec;
        const t = root.tabs.slice();
        const idx = Math.max(0, Math.min(root.activeTab, t.length - 1));
        if (t.length === 0)
            return;
        const cur = (isSec && t[idx].split) ? t[idx].split : t[idx];
        if (!cur || cur.forwardStack.length === 0)
            return;
        const fs = cur.forwardStack.slice();
        const next = fs.pop();
        const bs = cur.backStack.slice();
        bs.push(cur.path);
        const updatedNode = { path: next, title: root._tabTitleForPath(next), backStack: bs, forwardStack: fs };
        if (isSec && t[idx].split)
            t[idx] = Object.assign({}, t[idx], { split: updatedNode });
        else
            t[idx] = Object.assign({}, t[idx], updatedNode);
        root.tabs = t;
        root._loadDirFor(next, true, isSec ? "secondary" : "primary");
    }

    function goParent(): void {
        const p = root.activeParentPath;
        if (p.length > 0 && p !== root.activePath)
            root.navigate(p);
    }

    function refresh(): void {
        root._loadDirFor(root.currentPath, false, "primary");
        if (root.splitOpen)
            root._loadDirFor(root.secondaryPath, false, "secondary");
        root._sendRpc("drives", {}, null);
    }

    function newTab(path = ""): void {
        const p = String(path ?? "").trim() || root.activePath || root.homePath;
        const t = root.tabs.slice();
        t.push(root._makeTabSlot(p, ""));
        root.tabs = t;
        root.activeTab = t.length - 1;
        root.activeIsSecondary = false;
        root._loadDirFor(p, true, "primary");
    }

    function switchTab(idx: int, focusSecondary = false): void {
        const t = root.tabs;
        if (idx < 0 || idx >= t.length)
            return;
        const slot = t[idx];
        const hasSplit = Boolean(slot.split);
        root.activeTab = idx;
        root.activeIsSecondary = Boolean(focusSecondary) && hasSplit;
        root.filterText = "";
        root.recursiveSearch = false;
        root._loadDirFor(slot.path, true, "primary");
        if (hasSplit)
            root._loadDirFor(slot.split.path, true, "secondary");
        sessionSaveTimer.restart();
    }

    function nextTab(): void {
        if (root.tabs.length > 1)
            root.switchTab((root.activeTab + 1) % root.tabs.length, false);
    }

    function prevTab(): void {
        if (root.tabs.length > 1)
            root.switchTab((root.activeTab - 1 + root.tabs.length) % root.tabs.length, false);
    }

    function closeTabHalf(idx: int, side: string): void {
        const t = root.tabs.slice();
        if (idx < 0 || idx >= t.length || !t[idx].split)
            return;
        const slot = t[idx];
        if (side === "left") {
            const rightNode = slot.split;
            t[idx] = Object.assign({}, rightNode, { split: null });
        } else {
            t[idx] = Object.assign({}, slot, { split: null });
        }
        root.tabs = t;
        if (idx === root.activeTab) {
            root.activeIsSecondary = false;
            root.currentPath = t[idx].path;
            root._loadDirFor(t[idx].path, true, "primary");
        }
        sessionSaveTimer.restart();
    }

    function closeTab(idx: int): void {
        if (idx < 0 || idx >= root.tabs.length)
            return;
        if (idx === root.activeTab && root.splitOpen) {
            root.closeTabHalf(idx, root.activeIsSecondary ? "right" : "left");
            return;
        }
        if (root.tabs.length <= 1)
            return;
        const t = root.tabs.slice();
        t.splice(idx, 1);
        const curActive = root.activeTab;
        const nextIdx = Math.max(0, Math.min(idx < curActive ? curActive - 1 : curActive, t.length - 1));
        root.tabs = t;
        root.activeTab = nextIdx;
        const nextSlot = t[nextIdx];
        root.activeIsSecondary = false;
        root._loadDirFor(nextSlot.path, true, "primary");
        if (nextSlot.split)
            root._loadDirFor(nextSlot.split.path, true, "secondary");
        sessionSaveTimer.restart();
    }

    // ── View & Filter & Preferences ───────────────────────────────────────

    function _saveConfigFields(fields: var): void {
        if (root.daemonReady)
            root._sendRpc("save_config", fields, null);
    }

    function setViewMode(mode: string): void {
        if (root.viewMode === mode)
            return;
        root.viewMode = mode;
        root._saveConfigFields({ view_mode: mode });
    }

    function setSort(field: string): void {
        if (root.sortField === field)
            root.sortOrder = root.sortOrder === "asc" ? "desc" : "asc";
        else {
            root.sortField = field;
            root.sortOrder = "asc";
        }
        root._saveConfigFields({ sort_field: root.sortField, sort_order: root.sortOrder });
        root.refresh();
    }

    function toggleDirsFirst(): void {
        root.dirsFirst = !root.dirsFirst;
        root._saveConfigFields({ directories_first: root.dirsFirst });
        root.refresh();
    }

    function toggleHidden(): void {
        root.showHidden = !root.showHidden;
        root._saveConfigFields({ show_hidden: root.showHidden });
        root.refresh();
    }

    function toggleRail(): void {
        root.railOpen = !root.railOpen;
        root._saveConfigFields({ rail_open: root.railOpen });
    }

    function toggleInspector(): void {
        root.setInspectorOpen(!root.inspectorOpen);
    }

    function setInspectorOpen(open: bool): void {
        const next = Boolean(open);
        if (root.inspectorOpen === next)
            return;
        root.inspectorOpen = next;
        root._saveConfigFields({ inspector_open_default: root.inspectorOpen });
    }

    function setRailWidth(px: int): void {
        const clamped = Math.max(156, Math.min(460, Math.round(px)));
        if (root.railWidth === clamped)
            return;
        root.railWidth = clamped;
        paneSizeSaveTimer.restart();
    }

    function setInspectorWidth(px: int): void {
        const clamped = Math.max(200, Math.min(560, Math.round(px)));
        if (root.inspectorWidth === clamped)
            return;
        root.inspectorWidth = clamped;
        paneSizeSaveTimer.restart();
    }

    function setInspectorPreviewRatio(ratio: real): void {
        const clamped = Math.max(0.22, Math.min(0.72, Number(ratio)));
        if (Math.abs(root.inspectorPreviewRatio - clamped) < 0.002)
            return;
        root.inspectorPreviewRatio = clamped;
        paneSizeSaveTimer.restart();
    }

    function loadProperties(path: string, gitStatus: string): void {
        const clean = String(path ?? "").trim();
        const seq = ++root._propsGen;
        if (clean.length === 0) {
            root.propsTargetPath = "";
            root.propsData = null;
            root.propsLoading = false;
            root.propsDirTotals = null;
            root.propsDirLoading = false;
            root.propsChecksums = ({});
            root.propsChecksumBusy = ({});
            return;
        }
        root.propsTargetPath = clean;
        root.propsLoading = true;
        root.propsDirTotals = null;
        root.propsDirLoading = false;
        root.propsChecksums = ({});
        root.propsChecksumBusy = ({});

        const gs = String(gitStatus ?? "").trim();
        root._sendRpc("properties", {
            path: clean,
            git_status: gs.length > 0 ? gs : null
        }, (data, err) => {
            if (seq !== root._propsGen)
                return;
            root.propsLoading = false;
            if (err || !data?.properties) {
                root.propsData = null;
                return;
            }
            root.propsData = data.properties;
            if (Boolean(data.properties.is_dir) && !Boolean(data.properties.is_broken_symlink)) {
                root.propsDirLoading = true;
                root._sendRpc("properties_dir_size", { path: clean }, (d2, e2) => {
                    if (seq !== root._propsGen)
                        return;
                    root.propsDirLoading = false;
                    if (!e2 && d2 && !d2.cancelled)
                        root.propsDirTotals = d2;
                }, { silentError: true });
            }
        }, { silentError: true });
    }

    function setItemPermissions(path: string, mode: int): void {
        const target = String(path ?? "").trim();
        if (target.length === 0)
            return;
        const seq = root._propsGen;
        root._sendRpc("set_permissions", { path: target, mode: mode }, (data, err) => {
            if (err)
                return;
            if (seq === root._propsGen && data?.properties) {
                const prevGit = root.propsData?.git_status ?? null;
                const nextProps = Object.assign({}, data.properties);
                if (prevGit && !nextProps.git_status)
                    nextProps.git_status = prevGit;
                root.propsData = nextProps;
            }
            root.refresh();
        });
    }

    function setDefaultApp(mimeType: string, appId: string, appName: string): void {
        const mime = String(mimeType ?? "").trim();
        const aid = String(appId ?? "").trim();
        if (mime.length === 0 || aid.length === 0)
            return;
        root._sendRpc("set_default_app", { mime_type: mime, app_id: aid }, (_data, err) => {
            if (err)
                return;
            if (root.propsData && String(root.propsData.mime_type ?? "") === mime) {
                root.propsData = Object.assign({}, root.propsData, {
                    default_app_id: aid,
                    default_app_name: String(appName ?? aid)
                });
            }
            root.showToast("Default app set to " + String(appName ?? aid), false);
        });
    }

    function computeChecksum(path: string, algo: string): void {
        const target = String(path ?? "").trim();
        const key = String(algo ?? "").toLowerCase();
        if (target.length === 0 || key.length === 0)
            return;
        const seq = root._propsGen;
        const busy0 = Object.assign({}, root.propsChecksumBusy);
        busy0[key] = true;
        root.propsChecksumBusy = busy0;
        root._sendRpc("checksum", { path: target, algo: key }, (data, err) => {
            if (seq !== root._propsGen)
                return;
            const busy1 = Object.assign({}, root.propsChecksumBusy);
            busy1[key] = false;
            root.propsChecksumBusy = busy1;
            if (err)
                return;
            if (data?.digest) {
                const sums = Object.assign({}, root.propsChecksums);
                sums[key] = String(data.digest);
                root.propsChecksums = sums;
            }
        });
    }

    function setGridIconSize(px: int): void {
        const clamped = Math.max(40, Math.min(240, Math.round(px)));
        if (root.gridIconSize === clamped)
            return;
        root.gridIconSize = clamped;
        root._saveConfigFields({ grid_icon_size: clamped });
    }

    function setListZoom(level: int): void {
        const clamped = Math.max(0, Math.min(2, Math.round(level)));
        if (root.listZoom === clamped)
            return;
        root.listZoom = clamped;
        root._saveConfigFields({ list_zoom: clamped });
    }

    function setFilter(text: string, recursive: bool): void {
        root.filterText = String(text ?? "");
        root.recursiveSearch = Boolean(recursive);
        const targetPane = root._targetPaneName();
        if (root.recursiveSearch && root.filterText.trim().length > 0) {
            root.searchBusy = true;
            root._sendRpc("search", {
                path: root.activePath,
                query: root.filterText.trim(),
                show_hidden: root.showHidden,
                max_results: 300
            }, null, { pane: targetPane });
        } else {
            root.searchBusy = false;
            root._loadDirFor(root.activePath, false, targetPane);
        }
    }

    // ── File Operations ───────────────────────────────────────────────────

    function copyPaths(paths: var): void {
        const arr = Array.isArray(paths) ? paths : root.activeSelectedPaths;
        if (arr.length === 0) return;
        root.clipboardPaths = arr.slice();
        root.clipboardOp = "copy";
        root.showToast("Copied " + arr.length + " item(s)", false);
    }

    function cutPaths(paths: var): void {
        const arr = Array.isArray(paths) ? paths : root.activeSelectedPaths;
        if (arr.length === 0) return;
        root.clipboardPaths = arr.slice();
        root.clipboardOp = "cut";
        root.showToast("Cut " + arr.length + " item(s)", false);
    }

    function paste(): void {
        if (root.clipboardPaths.length === 0) {
            root.showToast("Clipboard is empty", false);
            return;
        }
        const cmd = root.clipboardOp === "cut" ? "move" : "copy";
        const sources = root.clipboardPaths.slice();
        root._sendRpc(cmd, { paths: sources, dest_dir: root.activePath }, (data, err) => {
            if (err) return;
            if (cmd === "move") {
                root.clipboardPaths = [];
                root.clipboardOp = "";
            }
            root.canUndo = Boolean(data.can_undo);
            root.canRedo = Boolean(data.can_redo);
            root.refresh();
            root.showToast(String(data.message ?? "Done"), root.canUndo);
        });
    }

    function trashPaths(paths: var): void {
        const arr = Array.isArray(paths) ? paths : root.activeSelectedPaths;
        if (arr.length === 0) return;
        root._sendRpc("trash", { paths: arr }, (data, err) => {
            if (err) return;
            root.trashCount = Number(data.trash_count ?? root.trashCount);
            root.canUndo = Boolean(data.can_undo);
            root.canRedo = Boolean(data.can_redo);
            root.refresh();
            root.showToast(String(data.message ?? "Moved to Trash"), root.canUndo);
        });
    }

    function deletePaths(paths: var): void {
        const arr = Array.isArray(paths) ? paths : root.activeSelectedPaths;
        if (arr.length === 0) return;
        root._sendRpc("delete_permanent", { paths: arr }, (data, err) => {
            if (err) return;
            root.trashCount = Number(data.trash_count ?? root.trashCount);
            root.refresh();
            root.showToast(String(data.message ?? "Deleted permanently"), false);
        });
    }

    function restorePaths(paths: var): void {
        const arr = Array.isArray(paths) ? paths : root.activeSelectedPaths;
        if (arr.length === 0) return;
        root._sendRpc("restore", { paths: arr }, (data, err) => {
            if (err) return;
            root.trashCount = Number(data.trash_count ?? root.trashCount);
            root.refresh();
            root.showToast(String(data.message ?? "Restored"), false);
        });
    }

    function emptyTrash(): void {
        root._sendRpc("empty_trash", {}, (data, err) => {
            if (err) return;
            root.trashCount = 0;
            root.refresh();
            root.showToast(String(data.message ?? "Trash emptied"), false);
        });
    }

    function renamePath(path: string, newName: string): void {
        root._sendRpc("rename", { path: path, new_name: newName }, (data, err) => {
            if (err) return;
            root.refresh();
            root.showToast(String(data.message ?? "Renamed"), true);
        });
    }

    function createFolder(name: string): void {
        root._sendRpc("mkdir", { dir: root.activePath, name: name }, (data, err) => {
            if (err) return;
            root.refresh();
            root.showToast(String(data.message ?? "Created folder"), true);
        });
    }

    function createFile(name: string): void {
        root._sendRpc("mkfile", { dir: root.activePath, name: name }, (data, err) => {
            if (err) return;
            root.refresh();
            root.showToast(String(data.message ?? "Created file"), true);
        });
    }

    function createEntry(spec: string): void {
        const clean = String(spec ?? "").trim().replace(/\/+$/, "");
        root._sendRpc("create", { dir: root.activePath, name: spec }, (data, err) => {
            if (err) return;
            root.refresh();
            const isDir = Boolean(data?.is_dir);
            const fallback = isDir ? ("Created folder '" + clean + "'") : ("Created '" + clean + "'");
            root.showToast(String(data?.message ?? fallback), true);
        });
    }

    function undo(): void {
        root._sendRpc("undo", {}, (data, err) => {
            if (err) return;
            root.trashCount = Number(data.trash_count ?? root.trashCount);
            root.canUndo = Boolean(data.can_undo);
            root.canRedo = Boolean(data.can_redo);
            root.refresh();
            root.showToast(String(data.message ?? "Undid action"), false);
        });
    }

    function redo(): void {
        root._sendRpc("redo", {}, (data, err) => {
            if (err) return;
            root.trashCount = Number(data.trash_count ?? root.trashCount);
            root.canUndo = Boolean(data.can_undo);
            root.canRedo = Boolean(data.can_redo);
            root.refresh();
            root.showToast(String(data.message ?? "Redid action"), root.canUndo);
        });
    }

    function extractArchive(path: string, intoSubfolder: bool): void {
        root.showToast("Extracting archive…", false);
        root._sendRpc("extract", { path: path, into_subfolder: intoSubfolder }, (data, err) => {
            if (err) return;
            root.refresh();
            root.showToast(String(data.message ?? "Extracted"), intoSubfolder);
        });
    }

    function compressPaths(paths: var, name: string, fmt: string): void {
        root.showToast("Compressing…", false);
        root._sendRpc("compress", {
            paths: paths,
            dest_dir: root.activePath,
            name: name,
            format: fmt
        }, (data, err) => {
            if (err) return;
            root.refresh();
            root.showToast(String(data.message ?? "Archive created"), true);
        });
    }

    function openExternal(path: string): void {
        root._sendRpc("open", { path: path }, null);
    }

    function runAlisAction(action: string, paths: var): void {
        root._sendRpc("alis_action", { action: action, paths: paths }, (data, err) => {
            if (err) return;
            root.showToast(String(data.message ?? "Done"), false);
        });
    }

    function addBookmark(path: string): void {
        root._sendRpc("bookmark_add", { path: path }, (data, err) => {
            if (err) return;
            root.bookmarks = Array.isArray(data.bookmarks) ? data.bookmarks : root.bookmarks;
            if (data.added)
                root.showToast("Added bookmark", false);
        });
    }

    function removeBookmark(path: string): void {
        root._sendRpc("bookmark_remove", { path: path }, (data, err) => {
            if (err) return;
            root.bookmarks = Array.isArray(data.bookmarks) ? data.bookmarks : root.bookmarks;
            root.showToast("Removed bookmark", false);
        });
    }

    function mountDrive(dev: string): void {
        root._sendRpc("mount", { block_device: dev }, (data, err) => {
            if (err) return;
            root.drives = Array.isArray(data.drives) ? data.drives : root.drives;
            const mp = String(data.mount_point ?? "");
            if (mp.length > 0)
                root.navigate(mp);
        });
    }

    function unmountDrive(mp: string, dev: string, removable: bool): void {
        root._sendRpc("unmount", {
            mount_point: mp,
            block_device: dev,
            is_removable: removable
        }, (data, err) => {
            if (err) return;
            root.drives = Array.isArray(data.drives) ? data.drives : root.drives;
            if (root.currentPath.startsWith(mp))
                root._loadDirFor(root.homePath, true, "primary");
            if (root.splitOpen && root.secondaryPath.startsWith(mp))
                root._loadDirFor(root.homePath, true, "secondary");
            root.showToast(String(data.message ?? "Unmounted"), false);
        });
    }

    function requestThumb(path: string, kind: string): void {
        if (!root.thumbnailsEnabled)
            return;
        if (root.thumbMap[path] !== undefined || root._thumbPendingBatch[path] !== undefined || root._thumbInFlight[path] === true)
            return;
        if (!["Image", "Pdf", "Video"].includes(kind))
            return;
        root._thumbInFlight[path] = true;
        root._sendRpc("thumb", { path: path, kind: kind, size: 192 }, null, { silentError: true });
    }

    function openQuickLook(entry: var): void {
        if (!entry) return;
        root.quickLookEntry = entry;
        root.quickLookText = "";
        root.quickLookLoading = false;
        const k = String(entry.kind ?? "");
        if (k === "Text" || k === "Code" || k === "Markdown") {
            root.quickLookLoading = true;
            root._sendRpc("read_text_preview", { path: String(entry.path) }, (data, _err) => {
                root.quickLookLoading = false;
                if (data && root.quickLookEntry?.path === data.path)
                    root.quickLookText = String(data.text ?? "");
            }, { silentError: true });
        } else if (k === "Pdf" || k === "Video" || k === "Image") {
            root.requestThumb(String(entry.path), k);
        }
    }

    function closeQuickLook(): void {
        root.quickLookEntry = null;
        root.quickLookText = "";
    }

    function stepQuickLook(delta: int): void {
        const list = root.activeEntries;
        if (!root.quickLookEntry || list.length === 0)
            return;
        const curPath = String(root.quickLookEntry.path ?? "");
        let idx = list.findIndex(e => String(e.path) === curPath);
        if (idx < 0) idx = 0;
        const nextIdx = Math.max(0, Math.min(list.length - 1, idx + delta));
        const next = list[nextIdx];
        if (next) {
            root.setPaneSelectedPaths(root._useSec, [String(next.path)]);
            root.openQuickLook(next);
        }
    }

    function showToast(msg: string, undoable: bool, isError = false): void {
        root.toastMessage = String(msg ?? "");
        root.toastUndoable = Boolean(undoable) && root.canUndo;
        root.toastIsError = Boolean(isError);
        toastClearTimer.interval = root.toastIsError ? 5500 : 4200;
        toastClearTimer.restart();
    }

    Timer {
        id: toastClearTimer
        interval: 4200
        repeat: false
        onTriggered: {
            root.toastMessage = "";
            root.toastUndoable = false;
            root.toastIsError = false;
        }
    }

    Loader {
        id: hostWindowLoader
        active: root._live && Quickshell.env("ALIS_FILES_HEADLESS_SERVICE_ONLY") !== "1"
        source: "../modules/files/AlisFilesHost.qml"
        onLoaded: {
            if (item)
                item.files = root;
        }
    }
}
