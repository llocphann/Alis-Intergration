import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

Rectangle {
    id: findBarRoot
    property var nexus: null
    property var settledColors: null
    property string targetText: ""
    property int currentMatchIndex: 0
    property bool caseSensitive: false
    property bool useRegex: false

    signal navigateMatch(int matchIndex, int startPos, int endPos, string queryText)
    signal applyReplacedText(string newContent)
    signal closed()

    visible: Boolean(nexus?.findBarOpen ?? false)
    Layout.fillWidth: true
    implicitHeight: (nexus?.findBarReplaceMode ?? false) ? 74 : 40
    radius: 10
    color: settledColors?.colLayer1 ?? Appearance.colors.colLayer1

    readonly property var matches: computeMatches()

    function focusInput(): void {
        findField.forceActiveFocus();
        findField.selectAll();
    }

    function computeMatches(): var {
        const q = String(findField.text ?? "");
        const src = String(targetText ?? "");
        if (!q || !src)
            return [];
        const list = [];
        try {
            if (useRegex) {
                const flags = caseSensitive ? "g" : "gi";
                const re = new RegExp(q, flags);
                let m;
                let safety = 0;
                while ((m = re.exec(src)) !== null && safety++ < 2000) {
                    if (m[0].length === 0) {
                        re.lastIndex += 1;
                        continue;
                    }
                    list.push({ "start": m.index, "end": m.index + m[0].length });
                }
            } else {
                const hay = caseSensitive ? src : src.toLowerCase();
                const needle = caseSensitive ? q : q.toLowerCase();
                let pos = 0;
                while (list.length < 2000) {
                    const idx = hay.indexOf(needle, pos);
                    if (idx === -1)
                        break;
                    list.push({ "start": idx, "end": idx + needle.length });
                    pos = idx + Math.max(1, needle.length);
                }
            }
        } catch (e) {}
        return list;
    }

    function stepMatch(delta: int): void {
        if (matches.length === 0)
            return;
        currentMatchIndex = (currentMatchIndex + delta + matches.length) % matches.length;
        const m = matches[currentMatchIndex];
        navigateMatch(currentMatchIndex, m.start, m.end, String(findField.text ?? ""));
    }

    function replaceOne(): void {
        if (matches.length === 0)
            return;
        const idx = Math.max(0, Math.min(matches.length - 1, currentMatchIndex));
        const m = matches[idx];
        const src = String(targetText ?? "");
        const rep = String(replaceField.text ?? "");
        const nextStr = src.slice(0, m.start) + rep + src.slice(m.end);
        applyReplacedText(nextStr);
    }

    function replaceAll(): void {
        const q = String(findField.text ?? "");
        const src = String(targetText ?? "");
        const rep = String(replaceField.text ?? "");
        if (!q || matches.length === 0)
            return;
        try {
            let nextStr = src;
            if (useRegex) {
                const re = new RegExp(q, caseSensitive ? "g" : "gi");
                nextStr = src.replace(re, rep);
            } else if (caseSensitive) {
                nextStr = src.split(q).join(rep);
            } else {
                let out = "";
                let cursor = 0;
                for (let i = 0; i < matches.length; ++i) {
                    out += src.slice(cursor, matches[i].start) + rep;
                    cursor = matches[i].end;
                }
                nextStr = out + src.slice(cursor);
            }
            applyReplacedText(nextStr);
        } catch (e) {}
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 6
        spacing: 4

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            MaterialSymbol {
                text: "search"
                iconSize: 15
                color: findBarRoot.settledColors?.colSubtext ?? Appearance.colors.colSubtext
            }

            TextField {
                id: findField
                Layout.fillWidth: true
                Layout.minimumWidth: 100
                implicitHeight: 28
                placeholderText: "Find in note..."
                color: findBarRoot.settledColors?.colOnLayer1 ?? Appearance.colors.colOnLayer1
                font.pixelSize: Appearance.font.pixelSize.smaller
                background: Rectangle {
                    radius: 6
                    color: findBarRoot.settledColors?.colLayer0 ?? Appearance.colors.colLayer0
                }
                onTextChanged: findBarRoot.currentMatchIndex = 0
                Keys.onReturnPressed: findBarRoot.stepMatch(1)
                Keys.onEscapePressed: {
                    if (findBarRoot.nexus)
                        findBarRoot.nexus.findBarOpen = false;
                    findBarRoot.closed();
                }
            }

            StyledText {
                text: findBarRoot.matches.length > 0
                    ? ((findBarRoot.currentMatchIndex % findBarRoot.matches.length + 1) + "/" + findBarRoot.matches.length)
                    : (findField.text.length > 0 ? "0/0" : "")
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: findBarRoot.settledColors?.colSubtext ?? Appearance.colors.colSubtext
            }

            Rectangle {
                height: 26; width: 28; radius: 6
                color: findBarRoot.caseSensitive
                    ? (findBarRoot.settledColors?.colPrimary ?? Appearance.colors.colPrimary)
                    : (findBarRoot.settledColors?.colLayer0 ?? Appearance.colors.colLayer0)
                StyledText {
                    anchors.centerIn: parent
                    text: "Aa"
                    horizontalAlignment: Text.AlignHCenter
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: findBarRoot.caseSensitive
                        ? (findBarRoot.settledColors?.colOnPrimary ?? Appearance.colors.colOnPrimary)
                        : (findBarRoot.settledColors?.colOnLayer1 ?? Appearance.colors.colOnLayer1)
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: findBarRoot.caseSensitive = !findBarRoot.caseSensitive }
            }

            Rectangle {
                height: 26; width: 28; radius: 6
                color: findBarRoot.useRegex
                    ? (findBarRoot.settledColors?.colPrimary ?? Appearance.colors.colPrimary)
                    : (findBarRoot.settledColors?.colLayer0 ?? Appearance.colors.colLayer0)
                StyledText {
                    anchors.centerIn: parent
                    text: ".*"
                    horizontalAlignment: Text.AlignHCenter
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: findBarRoot.useRegex
                        ? (findBarRoot.settledColors?.colOnPrimary ?? Appearance.colors.colOnPrimary)
                        : (findBarRoot.settledColors?.colOnLayer1 ?? Appearance.colors.colOnLayer1)
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: findBarRoot.useRegex = !findBarRoot.useRegex }
            }

            Rectangle {
                height: 26; width: 28; radius: 6
                color: findBarRoot.settledColors?.colLayer0 ?? Appearance.colors.colLayer0
                MaterialSymbol { anchors.centerIn: parent; text: "keyboard_arrow_up"; iconSize: 16; color: findBarRoot.settledColors?.colOnLayer1 ?? Appearance.colors.colOnLayer1 }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: findBarRoot.stepMatch(-1) }
            }

            Rectangle {
                height: 26; width: 28; radius: 6
                color: findBarRoot.settledColors?.colLayer0 ?? Appearance.colors.colLayer0
                MaterialSymbol { anchors.centerIn: parent; text: "keyboard_arrow_down"; iconSize: 16; color: findBarRoot.settledColors?.colOnLayer1 ?? Appearance.colors.colOnLayer1 }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: findBarRoot.stepMatch(1) }
            }

            Rectangle {
                height: 26; width: 56; radius: 6
                color: (findBarRoot.nexus?.findBarReplaceMode ?? false)
                    ? (findBarRoot.settledColors?.colSecondaryContainer ?? Appearance.colors.colSecondaryContainer)
                    : (findBarRoot.settledColors?.colLayer0 ?? Appearance.colors.colLayer0)
                StyledText {
                    anchors.centerIn: parent
                    text: "Replace"
                    horizontalAlignment: Text.AlignHCenter
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: findBarRoot.settledColors?.colOnLayer1 ?? Appearance.colors.colOnLayer1
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (findBarRoot.nexus) findBarRoot.nexus.findBarReplaceMode = !findBarRoot.nexus.findBarReplaceMode
                }
            }

            Rectangle {
                height: 26; width: 26; radius: 6
                color: findBarRoot.settledColors?.colLayer0 ?? Appearance.colors.colLayer0
                MaterialSymbol { anchors.centerIn: parent; text: "close"; iconSize: 15; color: findBarRoot.settledColors?.colSubtext ?? Appearance.colors.colSubtext }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (findBarRoot.nexus)
                            findBarRoot.nexus.findBarOpen = false;
                        findBarRoot.closed();
                    }
                }
            }
        }

        RowLayout {
            visible: Boolean(findBarRoot.nexus?.findBarReplaceMode ?? false)
            Layout.fillWidth: true
            spacing: 6

            MaterialSymbol {
                text: "find_replace"
                iconSize: 15
                color: findBarRoot.settledColors?.colSubtext ?? Appearance.colors.colSubtext
            }

            TextField {
                id: replaceField
                Layout.fillWidth: true
                Layout.minimumWidth: 100
                implicitHeight: 28
                placeholderText: "Replace with..."
                color: findBarRoot.settledColors?.colOnLayer1 ?? Appearance.colors.colOnLayer1
                font.pixelSize: Appearance.font.pixelSize.smaller
                background: Rectangle {
                    radius: 6
                    color: findBarRoot.settledColors?.colLayer0 ?? Appearance.colors.colLayer0
                }
                Keys.onReturnPressed: findBarRoot.replaceOne()
                Keys.onEscapePressed: {
                    if (findBarRoot.nexus)
                        findBarRoot.nexus.findBarOpen = false;
                    findBarRoot.closed();
                }
            }

            Rectangle {
                height: 26; width: 64; radius: 6
                color: findBarRoot.settledColors?.colSecondaryContainer ?? Appearance.colors.colSecondaryContainer
                StyledText {
                    anchors.centerIn: parent
                    text: "Replace"
                    horizontalAlignment: Text.AlignHCenter
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: findBarRoot.settledColors?.colPrimary ?? Appearance.colors.colPrimary
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: findBarRoot.replaceOne() }
            }

            Rectangle {
                height: 26; width: 48; radius: 6
                color: findBarRoot.settledColors?.colPrimary ?? Appearance.colors.colPrimary
                StyledText {
                    anchors.centerIn: parent
                    text: "All"
                    horizontalAlignment: Text.AlignHCenter
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.DemiBold
                    color: findBarRoot.settledColors?.colOnPrimary ?? Appearance.colors.colOnPrimary
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: findBarRoot.replaceAll() }
            }
        }
    }
}
