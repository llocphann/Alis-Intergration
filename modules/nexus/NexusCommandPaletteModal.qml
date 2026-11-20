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

    function _syncOnShow(): void {
        if (!visible)
            return;
        const initSearch = String(root?.nexus?.commandPaletteSearch ?? "");
        commandPaletteSearchInput.text = initSearch;
        query = initSearch.trim().toLowerCase();
        if (root?.nexus && root.nexus.commandPaletteSearch.length > 0)
            root.nexus.commandPaletteSearch = "";
        commandPaletteSearchInput.focus = true;
        commandPaletteSearchInput.forceActiveFocus();
    }

    Component.onCompleted: _syncOnShow()

    onVisibleChanged: {
        if (visible) {
            _syncOnShow();
        } else {
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
