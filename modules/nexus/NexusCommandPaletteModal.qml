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

Rectangle {
    id: commandPaletteOverlay
    objectName: "nexusCommandPaletteModal"
    required property var workspace
    readonly property var root: workspace
    readonly property var settledColors: workspace ? workspace.settledColors : null
    readonly property var searchInput: commandPaletteSearchInput
    anchors.fill: parent
    visible: Boolean(root?.nexus?.commandPaletteOpen ?? false)
    color: Qt.rgba(0, 0, 0, 0.45)
    z: 99

    property string query: ""
    property int selectedIndex: 0
    readonly property var switcherModel: computeSwitcherResults()
    readonly property var commandsModel: computeCommandResults()

    function _liveInputText(): string {
        const inp = commandPaletteSearchInput;
        if (!inp)
            return "";
        if (inp.inputMethodComposing)
            return String((inp.displayText && inp.displayText.length > 0) ? inp.displayText : ((inp.text || "") + (inp.preeditText || "")));
        return String((inp.text && inp.text.length > 0) ? inp.text : (inp.displayText || ""));
    }

    function syncLiveQuery(): void {
        const nextQ = commandPaletteOverlay._liveInputText().trim().toLowerCase();
        if (commandPaletteOverlay.query !== nextQ)
            commandPaletteOverlay.query = nextQ;
    }

    Timer {
        id: preeditQueryTimer
        interval: 35
        repeat: false
        onTriggered: commandPaletteOverlay.syncLiveQuery()
    }

    function _extOf(name: string): string {
        const s = String(name ?? "");
        const dot = s.lastIndexOf(".");
        if (dot <= 0 || dot >= s.length - 1)
            return "";
        return s.substring(dot + 1).toLowerCase();
    }

    function _folderOf(relPath: string): string {
        const s = String(relPath ?? "");
        const slash = s.lastIndexOf("/");
        return slash > 0 ? s.substring(0, slash) : "";
    }

    function _fuzzyScore(needle: string, haystack: string): int {
        if (needle.length === 0)
            return 1;
        let hi = 0;
        let streak = 0;
        let score = 0;
        for (let ni = 0; ni < needle.length; ++ni) {
            const ch = needle.charAt(ni);
            const found = haystack.indexOf(ch, hi);
            if (found < 0)
                return -1;
            if (found === hi) {
                streak += 1;
                score += 6 + streak * 3;
            } else {
                streak = 0;
                const prevCh = found > 0 ? haystack.charAt(found - 1) : " ";
                const isBoundary = (prevCh === " " || prevCh === "/" || prevCh === "-" || prevCh === "_" || prevCh === ".");
                score += isBoundary ? 10 : 2;
            }
            hi = found + 1;
        }
        return score;
    }

    function _fileIcon(ext: string): string {
        if (ext === "md")
            return "description";
        if (ext === "png" || ext === "jpg" || ext === "jpeg" || ext === "webp" || ext === "gif" || ext === "svg")
            return "image";
        if (ext === "pdf")
            return "picture_as_pdf";
        if (ext === "canvas" || ext === "base")
            return "dashboard";
        if (ext === "css" || ext === "js" || ext === "ts" || ext === "json" || ext === "py" || ext === "rs" || ext === "qml" || ext === "html")
            return "code";
        return "draft";
    }

    function computeSwitcherResults(): var {
        const rows = root?.nexus?.flatFiles ?? root?.nexus?.visibleTreeRows ?? [];
        const q = String(commandPaletteOverlay.query ?? "").trim().toLowerCase();
        const curPath = String(root?.nexus?.currentPath ?? "");
        const openTabs = root?.nexus?.openTabs ?? [];
        const recentSet = Object.create(null);
        if (curPath.length > 0)
            recentSet[curPath] = 200;
        if (Array.isArray(openTabs)) {
            for (let t = 0; t < openTabs.length; ++t) {
                const tp = String(openTabs[t]?.relPath ?? openTabs[t] ?? "");
                if (tp.length > 0 && !recentSet[tp])
                    recentSet[tp] = 120 - Math.min(80, t * 5);
            }
        }
        const tokens = (q.indexOf(" ") >= 0) ? q.split(/\s+/).filter(Boolean) : null;
        const multiToken = Boolean(tokens && tokens.length > 1);
        const scored = [];
        for (let i = 0; i < rows.length; ++i) {
            const r = rows[i];
            if (!r || r.isDir)
                continue;
            const rawName = String(r.name ?? "");
            const relPath = String(r.relPath ?? "");
            const ext = (r.ext !== undefined) ? String(r.ext).toLowerCase() : _extOf(rawName);
            const isMd = (ext === "md");
            const stem = (r.stem !== undefined && String(r.stem).length > 0)
                ? String(r.stem)
                : (isMd ? rawName.substring(0, rawName.length - 3) : rawName);
            const folder = (r.folder !== undefined) ? String(r.folder) : _folderOf(relPath);
            const stemLower = stem.toLowerCase();
            const nameLower = rawName.toLowerCase();
            const pathLower = relPath.toLowerCase();

            let matchScore = 0;
            if (q.length === 0) {
                matchScore = 100 + (recentSet[relPath] ?? 0);
            } else if (multiToken) {
                let matchedAll = true;
                let stemHits = 0;
                for (let ti = 0; ti < tokens.length; ++ti) {
                    const tk = tokens[ti];
                    const sIdx = stemLower.indexOf(tk);
                    if (sIdx >= 0) {
                        stemHits += 1;
                        const prevCh = sIdx > 0 ? stemLower.charAt(sIdx - 1) : " ";
                        const boundary = (sIdx === 0 || prevCh === " " || prevCh === "-" || prevCh === "_" || prevCh === ".");
                        matchScore += (boundary ? 900 : 650) - Math.min(120, sIdx * 2);
                    } else {
                        const pIdx = pathLower.indexOf(tk);
                        if (pIdx >= 0) {
                            matchScore += 280 - Math.min(100, pIdx);
                        } else {
                            const fStem = _fuzzyScore(tk, stemLower);
                            if (fStem >= 0) {
                                stemHits += 1;
                                matchScore += 260 + Math.min(160, fStem);
                            } else {
                                const fPath = _fuzzyScore(tk, pathLower);
                                if (fPath >= 0)
                                    matchScore += 80 + Math.min(100, fPath);
                                else {
                                    matchedAll = false;
                                    break;
                                }
                            }
                        }
                    }
                }
                if (!matchedAll)
                    continue;
                matchScore += stemHits * 220 - Math.min(80, stemLower.length) + Math.round((recentSet[relPath] ?? 0) * 0.35);
            } else if (stemLower === q || nameLower === q) {
                matchScore = 2400;
            } else if (stemLower.startsWith(q)) {
                matchScore = 1600 - Math.min(200, stemLower.length);
            } else {
                const subIdx = stemLower.indexOf(q);
                if (subIdx >= 0) {
                    const prevCh = subIdx > 0 ? stemLower.charAt(subIdx - 1) : " ";
                    const boundary = (prevCh === " " || prevCh === "-" || prevCh === "_" || prevCh === ".");
                    matchScore = (boundary ? 1150 : 850) - Math.min(180, subIdx * 4 + stemLower.length);
                } else {
                    const fStem = _fuzzyScore(q, stemLower);
                    if (fStem >= 0) {
                        matchScore = 500 + Math.min(280, fStem) - Math.min(100, stemLower.length);
                    } else {
                        const pathIdx = pathLower.indexOf(q);
                        if (pathIdx >= 0) {
                            matchScore = 320 - Math.min(120, pathIdx);
                        } else {
                            const fPath = _fuzzyScore(q, pathLower);
                            if (fPath >= 0)
                                matchScore = 120 + Math.min(140, fPath);
                            else
                                continue;
                        }
                    }
                }
                matchScore += Math.round((recentSet[relPath] ?? 0) * 0.35);
            }

            // Strictly prioritize .md notes before all other extensions (Obsidian Quick Switcher parity)
            const tierScore = isMd ? 100000 : 0;
            scored.push({
                "row": r,
                "score": tierScore + matchScore,
                "isMd": isMd,
                "ext": ext,
                "stem": stem,
                "folder": folder,
                "sortKey": stemLower
            });
        }
        scored.sort((a, b) => {
            if (b.score !== a.score)
                return b.score - a.score;
            return a.sortKey < b.sortKey ? -1 : (a.sortKey > b.sortKey ? 1 : 0);
        });
        const limit = Math.min(50, scored.length);
        const out = new Array(limit);
        let hasExactMd = false;
        for (let k = 0; k < limit; ++k) {
            const it = scored[k];
            if (it.isMd && q.length > 0 && (it.sortKey === q || (it.sortKey + ".md") === q))
                hasExactMd = true;
            out[k] = {
                "name": it.row.name,
                "relPath": it.row.relPath,
                "stem": it.stem,
                "folder": it.folder,
                "ext": it.ext,
                "isMd": it.isMd,
                "isCreateAction": false,
                "icon": _fileIcon(it.ext)
            };
        }
        const liveRaw = commandPaletteOverlay._liveInputText();
        const rawTrim = String(liveRaw || commandPaletteOverlay.query || "").trim();
        if (rawTrim.length > 0 && !hasExactMd) {
            const cleanName = rawTrim.endsWith(".md") ? rawTrim : (rawTrim + ".md");
            out.push({
                "name": cleanName,
                "relPath": cleanName,
                "stem": "Create note \"" + rawTrim.replace(/\.md$/i, "") + "\"",
                "folder": "New Markdown note",
                "ext": "md",
                "isMd": true,
                "isCreateAction": true,
                "icon": "note_add"
            });
        }
        return out;
    }

    function computeCommandResults(): var {
        const extra = [
            {
                "id": "__new_note_api_modal__",
                "title": "New Note / Search External API...",
                "description": "Create note or search Movie, TV, Book, Game, Recipe & Place APIs",
                "obsidianCommand": "nexus:new-note-api",
                "defaultKey": ""
            },
            {
                "id": "__paste_clipboard_image__",
                "title": "Paste Clipboard Image to Note",
                "description": "Save image from clipboard into vault attachments and embed",
                "obsidianCommand": "nexus:paste-clipboard-image",
                "defaultKey": "Ctrl+Shift+V"
            }
        ];
        const catalog = extra.concat(root?.nexus?.shortcutCatalog ?? []);
        const q = String(commandPaletteOverlay.query ?? "").trim().toLowerCase();
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

    function activateSelected(inNewTab: bool): void {
        if (!root?.nexus)
            return;
        const m = root.nexus.commandPaletteMode ?? "commands";
        if (m === "task") {
            const txt = commandPaletteOverlay._liveInputText().trim();
            if (txt.length > 0) {
                root.nexus.addQuickTodoTask(txt);
                preeditQueryTimer.stop();
                commandPaletteSearchInput.text = "";
                commandPaletteSearchInput.focus = false;
                root.nexus.commandPaletteOpen = false;
                root.restoreWorkspaceFocus();
                Qt.callLater(root.restoreWorkspaceFocus);
            }
            return;
        }
        if (m === "switcher") {
            const list = switcherModel;
            if (!Array.isArray(list) || list.length === 0)
                return;
            const idx = Math.max(0, Math.min(list.length - 1, selectedIndex));
            const picked = list[idx];
            if (picked && picked.relPath) {
                if (picked.isCreateAction === true && typeof root.nexus.createNote === "function")
                    root.nexus.createNote(picked.relPath);
                else
                    root.nexus.openFile(picked.relPath, true);
                preeditQueryTimer.stop();
                commandPaletteSearchInput.focus = false;
                root.nexus.commandPaletteOpen = false;
                root.restoreWorkspaceFocus();
                Qt.callLater(root.restoreWorkspaceFocus);
            }
            return;
        }
        if (m === "commands") {
            const list = commandsModel;
            if (!Array.isArray(list) || list.length === 0)
                return;
            const idx = Math.max(0, Math.min(list.length - 1, selectedIndex));
            const cmd = list[idx];
            if (cmd && cmd.id) {
                preeditQueryTimer.stop();
                commandPaletteSearchInput.focus = false;
                root.nexus.commandPaletteOpen = false;
                if (cmd.id === "__new_note_api_modal__") {
                    root.nexus.openNewNoteModal("movie", "");
                } else if (cmd.id === "__paste_clipboard_image__") {
                    root.nexus.pasteClipboardImage();
                } else {
                    root.nexus.triggerShortcutAction(cmd.id);
                }
                if (!root.nexus.commandPaletteOpen && !root.nexus.newNoteModalOpen) {
                    root.restoreWorkspaceFocus();
                    Qt.callLater(root.restoreWorkspaceFocus);
                }
            }
        }
    }

    onQueryChanged: selectedIndex = 0

    function _syncOnShow(): void {
        if (!visible)
            return;
        preeditQueryTimer.stop();
        const initSearch = String(root?.nexus?.commandPaletteSearch ?? "");
        commandPaletteSearchInput.text = initSearch;
        query = initSearch.trim().toLowerCase();
        selectedIndex = 0;
        if (root?.nexus && String(root.nexus.commandPaletteSearch ?? "").length > 0)
            root.nexus.commandPaletteSearch = "";
        commandPaletteSearchInput.focus = true;
        commandPaletteSearchInput.forceActiveFocus();
    }

    Component.onCompleted: _syncOnShow()

    onVisibleChanged: {
        if (visible) {
            _syncOnShow();
        } else {
            preeditQueryTimer.stop();
            commandPaletteSearchInput.focus = false;
            if (root) {
                root.restoreWorkspaceFocus();
                Qt.callLater(root.restoreWorkspaceFocus);
            }
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
                                    commandPaletteOverlay.selectedIndex = 0;
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
                                return "Find or open a note (.md first)...";
                            if (m === "task")
                                return "Type task and press Enter to add to Todo...";
                            return "Type a Nexus command or Obsidian shortcut...";
                        }
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: settledColors.colOnLayer1
                        background: null
                        onTextChanged: {
                            if (inputMethodComposing) {
                                preeditQueryTimer.restart();
                                return;
                            }
                            preeditQueryTimer.stop();
                            commandPaletteOverlay.syncLiveQuery();
                        }
                        onDisplayTextChanged: {
                            if (inputMethodComposing) {
                                preeditQueryTimer.restart();
                                return;
                            }
                            preeditQueryTimer.stop();
                            commandPaletteOverlay.syncLiveQuery();
                        }
                        onPreeditTextChanged: preeditQueryTimer.restart()
                        onInputMethodComposingChanged: {
                            if (!inputMethodComposing) {
                                preeditQueryTimer.stop();
                                commandPaletteOverlay.syncLiveQuery();
                            }
                        }
                        Keys.onEscapePressed: event => {
                            if (inputMethodComposing) {
                                event.accepted = false;
                                return;
                            }
                            preeditQueryTimer.stop();
                            commandPaletteSearchInput.focus = false;
                            if (root.nexus)
                                root.nexus.commandPaletteOpen = false;
                            root.restoreWorkspaceFocus();
                            Qt.callLater(root.restoreWorkspaceFocus);
                            event.accepted = true;
                        }
                        Keys.onPressed: event => {
                            if (inputMethodComposing || event.key === 0 || event.key === Qt.Key_unknown) {
                                event.accepted = false;
                                return;
                            }
                            const mode = root.nexus?.commandPaletteMode ?? "commands";
                            const activeList = (mode === "switcher") ? commandPaletteResultsList : commandPaletteCommandsList;
                            const count = (mode === "switcher") ? commandPaletteOverlay.switcherModel.length : commandPaletteOverlay.commandsModel.length;
                            if (mode !== "task" && count > 0) {
                                if (event.key === Qt.Key_Down || ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_N)) {
                                    commandPaletteOverlay.selectedIndex = (commandPaletteOverlay.selectedIndex + 1) % count;
                                    activeList.positionViewAtIndex(commandPaletteOverlay.selectedIndex, ListView.Contain);
                                    event.accepted = true;
                                    return;
                                }
                                if (event.key === Qt.Key_Up || ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_P)) {
                                    commandPaletteOverlay.selectedIndex = (commandPaletteOverlay.selectedIndex - 1 + count) % count;
                                    activeList.positionViewAtIndex(commandPaletteOverlay.selectedIndex, ListView.Contain);
                                    event.accepted = true;
                                    return;
                                }
                            }
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
                            if (inputMethodComposing)
                                return;
                            commandPaletteOverlay.activateSelected(false);
                        }
                    }
                }
            }

            // Quick Switcher File Results (Obsidian-style: .md prioritized first, fuzzy basename ranking, folder subtitle, extension badges)
            ListView {
                id: commandPaletteResultsList
                objectName: "nexusQuickSwitcherResultsList"
                visible: (root.nexus?.commandPaletteMode ?? "commands") === "switcher"
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 3
                model: commandPaletteOverlay.switcherModel
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    readonly property bool isSelected: commandPaletteOverlay.selectedIndex === index
                    width: ListView.view.width
                    height: modelData.folder && modelData.folder.length > 0 ? 44 : 36
                    radius: 7
                    color: (isSelected || switcherRowMouse.containsMouse)
                        ? settledColors.colSecondaryContainer
                        : settledColors.colLayer0
                    border.width: isSelected ? 1 : 0
                    border.color: settledColors.colPrimary

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 8

                        MaterialSymbol {
                            text: String(modelData.icon ?? "description")
                            iconSize: 15
                            color: modelData.isMd ? settledColors.colPrimary : settledColors.colSubtext
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            spacing: 1
                            StyledText {
                                Layout.fillWidth: true
                                text: String(modelData.stem ?? modelData.name ?? "")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: isSelected ? Font.Bold : Font.DemiBold
                                color: isSelected ? settledColors.colOnSecondaryContainer : settledColors.colOnLayer1
                                elide: Text.ElideRight
                            }
                            StyledText {
                                visible: Boolean(modelData.folder && modelData.folder.length > 0)
                                Layout.fillWidth: true
                                text: String(modelData.folder ?? "")
                                font.family: Appearance.font.family.monospace
                                font.pixelSize: Appearance.font.pixelSize.smallest - 1
                                color: isSelected ? settledColors.colOnSecondaryContainer : settledColors.colSubtext
                                opacity: isSelected ? 0.82 : 0.78
                                elide: Text.ElideMiddle
                            }
                        }

                        Rectangle {
                            visible: !modelData.isMd && String(modelData.ext ?? "").length > 0
                            implicitWidth: extTagText.implicitWidth + 10
                            implicitHeight: 18
                            radius: 4
                            color: settledColors.colLayer2
                            StyledText {
                                id: extTagText
                                anchors.centerIn: parent
                                text: String(modelData.ext ?? "").toUpperCase()
                                font.family: Appearance.font.family.monospace
                                font.pixelSize: 9
                                font.weight: Font.Bold
                                color: settledColors.colSubtext
                            }
                        }
                    }
                    MouseArea {
                        id: switcherRowMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: commandPaletteOverlay.selectedIndex = index
                        onClicked: {
                            if (root.nexus) {
                                if (modelData.isCreateAction === true && typeof root.nexus.createNote === "function")
                                    root.nexus.createNote(modelData.relPath);
                                else
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
                model: commandPaletteOverlay.commandsModel
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    readonly property bool isSelected: commandPaletteOverlay.selectedIndex === index
                    width: ListView.view.width
                    height: 38
                    radius: 7
                    color: (isSelected || cmdRowMouse.containsMouse)
                        ? settledColors.colSecondaryContainer
                        : settledColors.colLayer0
                    border.width: isSelected ? 1 : 0
                    border.color: settledColors.colPrimary

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 8

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            spacing: 1
                            StyledText {
                                Layout.fillWidth: true
                                text: String(modelData.title ?? "")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: isSelected ? Font.Bold : Font.DemiBold
                                color: isSelected ? settledColors.colOnSecondaryContainer : settledColors.colOnLayer1
                                elide: Text.ElideRight
                            }
                            StyledText {
                                Layout.fillWidth: true
                                readonly property string obsLabel: String(modelData.obsidianCommand ?? modelData.obsidianId ?? "")
                                text: String(modelData.description ?? "") + (obsLabel.length > 0 ? ("  ·  " + obsLabel) : "")
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: isSelected ? settledColors.colOnSecondaryContainer : settledColors.colSubtext
                                elide: Text.ElideRight
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
                        onEntered: commandPaletteOverlay.selectedIndex = index
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
