import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

Rectangle {
    id: slashMenuRoot
    property var settledColors: null
    property bool isOpen: false
    property string filterText: ""
    property int selectedIndex: 0

    signal insertSnippet(string snippet, int backOffset, string actionKind)
    signal closed()

    visible: isOpen && filteredItems.length > 0
    radius: 10
    color: settledColors?.colLayer2 ?? Appearance.colors.colLayer2
    border.width: 1
    border.color: settledColors?.colPrimary ?? Appearance.colors.colPrimary
    width: 280
    height: Math.min(280, Math.max(48, filteredItems.length * 32 + 12))
    z: 45

    readonly property var catalog: [
        { "id": "h1", "label": "Heading 1", "hint": "# Title", "snippet": "# ", "back": 0, "icon": "title", "action": "insert" },
        { "id": "h2", "label": "Heading 2", "hint": "## Section", "snippet": "## ", "back": 0, "icon": "title", "action": "insert" },
        { "id": "h3", "label": "Heading 3", "hint": "### Subsection", "snippet": "### ", "back": 0, "icon": "title", "action": "insert" },
        { "id": "todo", "label": "Task Checkbox", "hint": "- [ ] Task", "snippet": "- [ ] ", "back": 0, "icon": "check_box", "action": "insert" },
        { "id": "callout-note", "label": "Note Callout", "hint": "> [!NOTE]", "snippet": "> [!NOTE] ", "back": 0, "icon": "info", "action": "insert" },
        { "id": "callout-tip", "label": "Tip Callout", "hint": "> [!TIP]", "snippet": "> [!TIP] ", "back": 0, "icon": "lightbulb", "action": "insert" },
        { "id": "callout-warn", "label": "Warning Callout", "hint": "> [!WARNING]", "snippet": "> [!WARNING] ", "back": 0, "icon": "warning", "action": "insert" },
        { "id": "toggle", "label": "Toggle Details", "hint": "<details>", "snippet": "<details>\n<summary>Toggle Title</summary>\n\n\n</details>", "back": 11, "icon": "unfold_more", "action": "insert" },
        { "id": "code", "label": "Code Block", "hint": "```lang", "snippet": "```\n\n```", "back": 4, "icon": "code", "action": "insert" },
        { "id": "math", "label": "Math Block", "hint": "$$ LaTeX $$", "snippet": "$$\n\n$$", "back": 3, "icon": "functions", "action": "insert" },
        { "id": "mermaid", "label": "Mermaid Diagram", "hint": "flowchart LR", "snippet": "```mermaid\nflowchart LR\n    A[Start] --> B[Done]\n```", "back": 0, "icon": "account_tree", "action": "insert" },
        { "id": "table", "label": "Markdown Table", "hint": "| Col |", "snippet": "| Column A | Column B |\n| --- | --- |\n|  |  |", "back": 5, "icon": "table_chart", "action": "insert" },
        { "id": "wikilink", "label": "Wikilink", "hint": "[[Note]]", "snippet": "[[]]", "back": 2, "icon": "link", "action": "insert" },
        { "id": "embed", "label": "Embed / Transclude", "hint": "![[Note]]", "snippet": "![[]]", "back": 2, "icon": "post_add", "action": "insert" },
        { "id": "image", "label": "Paste Image", "hint": "Clipboard", "snippet": "", "back": 0, "icon": "image", "action": "paste-image" },
        { "id": "flashcard", "label": "Q/A Flashcard", "hint": "Q :: A", "snippet": "Question :: Answer", "back": 0, "icon": "style", "action": "insert" },
        { "id": "cloze", "label": "Cloze Flashcard", "hint": "{{c1::term}}", "snippet": "{{c1::}}", "back": 2, "icon": "psychology", "action": "insert" },
        { "id": "date", "label": "Today's Date", "hint": Qt.formatDate(new Date(), "yyyy-MM-dd"), "snippet": Qt.formatDate(new Date(), "yyyy-MM-dd"), "back": 0, "icon": "today", "action": "insert" },
        { "id": "divider", "label": "Divider Line", "hint": "---", "snippet": "\n---\n", "back": 0, "icon": "horizontal_rule", "action": "insert" }
    ]

    readonly property var filteredItems: {
        const q = String(filterText ?? "").trim().toLowerCase();
        if (!q)
            return catalog;
        const out = [];
        for (let i = 0; i < catalog.length; ++i) {
            const it = catalog[i];
            if (it.id.indexOf(q) !== -1 || it.label.toLowerCase().indexOf(q) !== -1 || it.hint.toLowerCase().indexOf(q) !== -1)
                out.push(it);
        }
        return out;
    }

    onFilteredItemsChanged: {
        if (selectedIndex >= filteredItems.length)
            selectedIndex = Math.max(0, filteredItems.length - 1);
    }

    function moveSelection(delta: int): void {
        if (filteredItems.length === 0)
            return;
        selectedIndex = (selectedIndex + delta + filteredItems.length) % filteredItems.length;
    }

    function acceptSelected(): bool {
        if (!isOpen || filteredItems.length === 0)
            return false;
        const idx = Math.max(0, Math.min(filteredItems.length - 1, selectedIndex));
        const item = filteredItems[idx];
        isOpen = false;
        insertSnippet(String(item.snippet), Number(item.back || 0), String(item.action || "insert"));
        return true;
    }

    function close(): void {
        isOpen = false;
        closed();
    }

    ListView {
        id: slashList
        anchors.fill: parent
        anchors.margins: 6
        clip: true
        spacing: 2
        currentIndex: slashMenuRoot.selectedIndex
        model: slashMenuRoot.filteredItems
        delegate: Rectangle {
            required property var modelData
            required property int index
            width: slashList.width
            height: 30
            radius: 6
            color: index === slashMenuRoot.selectedIndex
                ? (slashMenuRoot.settledColors?.colSecondaryContainer ?? Appearance.colors.colSecondaryContainer)
                : (rowHover.containsMouse ? (slashMenuRoot.settledColors?.colLayer1 ?? Appearance.colors.colLayer1) : "transparent")

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 8

                MaterialSymbol {
                    text: String(modelData.icon ?? "edit")
                    iconSize: 15
                    color: slashMenuRoot.settledColors?.colPrimary ?? Appearance.colors.colPrimary
                }

                StyledText {
                    Layout.fillWidth: true
                    text: String(modelData.label ?? "")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: slashMenuRoot.settledColors?.colOnLayer1 ?? Appearance.colors.colOnLayer1
                    elide: Text.ElideRight
                }

                StyledText {
                    text: String(modelData.hint ?? "")
                    font.family: Appearance.font.family.monospace
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: slashMenuRoot.settledColors?.colSubtext ?? Appearance.colors.colSubtext
                }
            }

            MouseArea {
                id: rowHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: slashMenuRoot.selectedIndex = index
                onClicked: {
                    slashMenuRoot.selectedIndex = index;
                    slashMenuRoot.acceptSelected();
                }
            }
        }
    }
}
