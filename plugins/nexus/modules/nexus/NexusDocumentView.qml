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
import "NexusRichRenderers.js" as Rich

ColumnLayout {
    id: documentViewRoot
    objectName: "nexusDocumentView"
    required property var workspace
    readonly property var root: workspace
    readonly property var settledColors: workspace ? workspace.settledColors : null
    readonly property var customViewsLoader: nexusCustomViewsLoader
    readonly property var bodyEditor: standardNoteBodyEditor
    readonly property var vimEditor: vimEditorArea
    readonly property var vimPane: vimEditorPane
    anchors.fill: parent
    spacing: 10

    property var _activeSlashEditor: null
    property int _slashStartPos: -1
    property string _hoveredPreviewTarget: ""

    function _insertAtEditor(editor, textStr: string, replaceStart: int, replaceEnd: int, cursorBackOffset: int): void {
        if (!editor)
            return;
        const cur = String(editor.text ?? "");
        const s = Math.max(0, Math.min(cur.length, replaceStart));
        const e = Math.max(s, Math.min(cur.length, replaceEnd));
        if (typeof editor.remove === "function" && typeof editor.insert === "function") {
            if (e > s)
                editor.remove(s, e);
            if (textStr.length > 0)
                editor.insert(s, textStr);
        } else {
            editor.text = cur.slice(0, s) + textStr + cur.slice(e);
        }
        const nextPos = Math.max(s, s + textStr.length - Math.max(0, cursorBackOffset));
        editor.cursorPosition = nextPos;
        editor.forceActiveFocus();
    }

    function _handleSlashTyping(editor): void {
        if (!editor || editor.readOnly) {
            slashMenu.isOpen = false;
            return;
        }
        const pos = editor.cursorPosition;
        const txt = String(editor.text ?? "");
        if (pos <= 0 || pos > txt.length) {
            slashMenu.isOpen = false;
            return;
        }
        // Scan backwards up to 24 chars on the current line for a `/` preceded by line start or whitespace
        const lineStart = txt.lastIndexOf("\n", pos - 1) + 1;
        const slice = txt.slice(Math.max(lineStart, pos - 24), pos);
        const relSlash = slice.lastIndexOf("/");
        if (relSlash === -1) {
            slashMenu.isOpen = false;
            return;
        }
        const absSlash = Math.max(lineStart, pos - 24) + relSlash;
        const beforeChar = absSlash > 0 ? txt.charAt(absSlash - 1) : "\n";
        if (beforeChar !== "\n" && beforeChar !== " " && beforeChar !== "\t") {
            slashMenu.isOpen = false;
            return;
        }
        const queryPart = txt.slice(absSlash + 1, pos);
        if (/[\s]/.test(queryPart)) {
            slashMenu.isOpen = false;
            return;
        }
        documentViewRoot._activeSlashEditor = editor;
        documentViewRoot._slashStartPos = absSlash;
        slashMenu.filterText = queryPart;
        slashMenu.isOpen = true;
    }

    function _wrapSelection(editor, prefix: string, suffix: string, placeholder: string): void {
        if (!editor || editor.readOnly)
            return;
        const txt = String(editor.text ?? "");
        const s = Math.min(editor.selectionStart, editor.selectionEnd);
        const e = Math.max(editor.selectionStart, editor.selectionEnd);
        const canSplice = typeof editor.remove === "function" && typeof editor.insert === "function";
        if (s !== e) {
            const selected = txt.slice(s, e);
            // Toggle off if already wrapped by exact prefix/suffix
            if (s >= prefix.length
                    && txt.slice(s - prefix.length, s) === prefix
                    && txt.slice(e, e + suffix.length) === suffix) {
                if (canSplice) {
                    editor.remove(s - prefix.length, e + suffix.length);
                    editor.insert(s - prefix.length, selected);
                } else {
                    editor.text = txt.slice(0, s - prefix.length) + selected + txt.slice(e + suffix.length);
                }
                editor.select(s - prefix.length, e - prefix.length);
            } else {
                const wrapped = prefix + selected + suffix;
                if (canSplice) {
                    editor.remove(s, e);
                    editor.insert(s, wrapped);
                } else {
                    editor.text = txt.slice(0, s) + wrapped + txt.slice(e);
                }
                editor.select(s + prefix.length, e + prefix.length);
            }
        } else {
            const pos = Math.max(0, Math.min(txt.length, editor.cursorPosition));
            const wrapped = prefix + placeholder + suffix;
            if (canSplice) {
                editor.insert(pos, wrapped);
            } else {
                editor.text = txt.slice(0, pos) + wrapped + txt.slice(pos);
            }
            editor.select(pos + prefix.length, pos + prefix.length + placeholder.length);
        }
        editor.forceActiveFocus();
    }

    function _handleSmartListEnter(editor): bool {
        if (!editor || editor.readOnly || editor.selectionStart !== editor.selectionEnd)
            return false;
        const txt = String(editor.text ?? "");
        const pos = Math.max(0, Math.min(txt.length, editor.cursorPosition));
        const lineStart = pos > 0 ? (txt.lastIndexOf("\n", pos - 1) + 1) : 0;
        const beforeCursor = txt.slice(lineStart, pos);

        // 1. Checkbox task item: "  - [ ] text" or "  - [x] text"
        let m = /^([ \t]*)([-*+])[ \t]+\[[ xX]\][ \t]*(.*)$/.exec(beforeCursor);
        if (m) {
            if (m[3].length === 0 && (pos === txt.length || txt.charAt(pos) === "\n")) {
                documentViewRoot._insertAtEditor(editor, "", lineStart, pos, 0);
            } else {
                documentViewRoot._insertAtEditor(editor, "\n" + m[1] + m[2] + " [ ] ", pos, pos, 0);
            }
            return true;
        }
        // 2. Unordered bullet item: "  - text" / "  * text" / "  + text"
        m = /^([ \t]*)([-*+])[ \t]+(.*)$/.exec(beforeCursor);
        if (m) {
            if (m[3].length === 0 && (pos === txt.length || txt.charAt(pos) === "\n")) {
                documentViewRoot._insertAtEditor(editor, "", lineStart, pos, 0);
            } else {
                documentViewRoot._insertAtEditor(editor, "\n" + m[1] + m[2] + " ", pos, pos, 0);
            }
            return true;
        }
        // 3. Ordered numbered item: "  1. text" or "  1) text"
        m = /^([ \t]*)(\d+)([.)])[ \t]+(.*)$/.exec(beforeCursor);
        if (m) {
            if (m[4].length === 0 && (pos === txt.length || txt.charAt(pos) === "\n")) {
                documentViewRoot._insertAtEditor(editor, "", lineStart, pos, 0);
            } else {
                const nextNum = parseInt(m[2], 10) + 1;
                documentViewRoot._insertAtEditor(editor, "\n" + m[1] + String(nextNum) + m[3] + " ", pos, pos, 0);
            }
            return true;
        }
        // 4. Blockquote line: "> text"
        m = /^([ \t]*>[ \t]?)(.*)$/.exec(beforeCursor);
        if (m) {
            if (m[2].length === 0 && (pos === txt.length || txt.charAt(pos) === "\n")) {
                documentViewRoot._insertAtEditor(editor, "", lineStart, pos, 0);
            } else {
                documentViewRoot._insertAtEditor(editor, "\n" + m[1], pos, pos, 0);
            }
            return true;
        }
        return false;
    }

    function _handleEditorPreKey(editor, event): bool {
        if (slashMenu.isOpen && documentViewRoot._activeSlashEditor === editor) {
            if (event.key === Qt.Key_Down) {
                slashMenu.moveSelection(1);
                return true;
            }
            if (event.key === Qt.Key_Up) {
                slashMenu.moveSelection(-1);
                return true;
            }
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Tab) {
                if (slashMenu.acceptSelected())
                    return true;
            }
            if (event.key === Qt.Key_Escape) {
                slashMenu.close();
                return true;
            }
        }
        const ctrlOnly = (event.modifiers & Qt.ControlModifier) !== 0
            && (event.modifiers & (Qt.AltModifier | Qt.ShiftModifier | Qt.MetaModifier)) === 0;
        if (ctrlOnly && !editor.readOnly) {
            if (event.key === Qt.Key_B) {
                documentViewRoot._wrapSelection(editor, "**", "**", "bold");
                return true;
            }
            if (event.key === Qt.Key_I) {
                documentViewRoot._wrapSelection(editor, "*", "*", "italic");
                return true;
            }
            if (event.key === Qt.Key_K) {
                documentViewRoot._wrapSelection(editor, "[", "](url)", "text");
                return true;
            }
        }
        const noMod = (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.ShiftModifier | Qt.MetaModifier)) === 0;
        if (noMod && !editor.readOnly && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
            if (documentViewRoot._handleSmartListEnter(editor))
                return true;
        }
        if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_V) {
            const isShift = (event.modifiers & Qt.ShiftModifier) !== 0;
            if ((isShift || !editor.canPaste) && root.nexus) {
                documentViewRoot._activeSlashEditor = editor;
                root.nexus.pasteClipboardImage();
                return true;
            }
        }
        return false;
    }

    function _scrollToRequestedLine(targetLine: int): void {
        const blocks = root.nexus?.currentDoc?.blocks ?? [];
        if (vimEditorArea.visible) {
            const raw = String(vimEditorArea.text ?? "");
            let line = 1;
            let idx = 0;
            while (line < targetLine && idx < raw.length) {
                const nl = raw.indexOf("\n", idx);
                if (nl === -1) break;
                idx = nl + 1;
                line += 1;
            }
            vimEditorArea.cursorPosition = idx;
            vimEditorArea.forceActiveFocus();
        }
        if (outlinerFlickable.visible && Array.isArray(blocks) && blocks.length > 0) {
            let matchIdx = 0;
            for (let i = 0; i < blocks.length; ++i) {
                const b = blocks[i];
                if (b && Number(b.lineStart ?? 0) >= targetLine) {
                    matchIdx = i;
                    break;
                }
            }
            const item = blocksRepeater.itemAt(matchIdx);
            if (item) {
                const pt = item.mapToItem(outlinerColumn, 0, 0);
                outlinerFlickable.contentY = Math.max(0, Math.min(Math.max(0, outlinerFlickable.contentHeight - outlinerFlickable.height), pt.y - 16));
            }
        }
    }

    Timer {
        id: hoverPreviewDelayTimer
        interval: 280
        repeat: false
        onTriggered: {
            if (documentViewRoot._hoveredPreviewTarget && root.nexus) {
                hoverPreviewPopup.openRequested = true;
                root.nexus.fetchHoverPreview(documentViewRoot._hoveredPreviewTarget);
            }
        }
    }

    Timer {
        id: hoverPreviewHideTimer
        interval: 220
        repeat: false
        onTriggered: {
            if (!hoverPreviewPopup.hovered && !documentViewRoot._hoveredPreviewTarget)
                hoverPreviewPopup.openRequested = false;
        }
    }

    onVisibleChanged: {
        if (visible && root.nexus)
            root.nexus.checkExternalModification();
    }

    Connections {
        target: root.nexus
        function onIsOpenChanged(): void {
            if (root.nexus?.isOpen && documentViewRoot.visible)
                root.nexus.checkExternalModification();
        }
        function onScrollToLineSerialChanged(): void {
            if (root.nexus)
                documentViewRoot._scrollToRequestedLine(root.nexus.scrollToLineRequest);
        }
        function onFindBarOpenChanged(): void {
            if (root.nexus?.findBarOpen)
                Qt.callLater(() => findReplaceBar.focusInput());
        }
        function onClipboardImagePasted(markdownEmbed: string, relPath: string): void {
            const targetEd = documentViewRoot._activeSlashEditor
                || (vimEditorPane.visible ? vimEditorArea : (standardNoteBodyEditor.visible ? standardNoteBodyEditor : null));
            if (targetEd) {
                const pos = Math.max(0, Math.min(String(targetEd.text ?? "").length, targetEd.cursorPosition));
                documentViewRoot._insertAtEditor(targetEd, markdownEmbed, pos, pos, 0);
            } else if (root.nexus && root.nexus.currentDoc) {
                const existing = String(root.nexus.draftContent || root.nexus.currentDoc.content || "").replace(/\s+$/, "");
                root.nexus.saveCurrentNote(existing + "\n\n" + markdownEmbed + "\n");
            }
        }
    }

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
                horizontalAlignment: Text.AlignHCenter
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

        Rectangle {
            visible: (root.nexus?.currentDoc?.category === "markdown")
            height: 24
            width: 48
            radius: 6
            color: (root.nexus?.propertiesPanelExpanded ?? false) ? settledColors.colSecondaryContainer : settledColors.colLayer0
            StyledText {
                anchors.centerIn: parent
                text: "Props"
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: (root.nexus?.propertiesPanelExpanded ?? false) ? settledColors.colPrimary : settledColors.colSubtext
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: if (root.nexus) root.nexus.propertiesPanelExpanded = !root.nexus.propertiesPanelExpanded
            }
        }

        Rectangle {
            visible: (root.nexus?.currentDoc?.category === "markdown") || (root.nexus?.currentDoc?.category === "code")
            height: 24
            width: 42
            radius: 6
            color: (root.nexus?.findBarOpen ?? false) ? settledColors.colSecondaryContainer : settledColors.colLayer0
            StyledText {
                anchors.centerIn: parent
                text: "Find"
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: (root.nexus?.findBarOpen ?? false) ? settledColors.colPrimary : settledColors.colSubtext
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: if (root.nexus) {
                    root.nexus.findBarReplaceMode = false;
                    root.nexus.findBarOpen = !root.nexus.findBarOpen;
                }
            }
        }

        Rectangle {
            visible: Boolean(root.nexus?.canUndoDocument())
            height: 24
            width: 44
            radius: 6
            color: settledColors.colLayer0
            StyledText {
                anchors.centerIn: parent
                text: "Undo"
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: settledColors.colPrimary
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: if (root.nexus) root.nexus.undoDocument()
            }
        }

        Rectangle {
            visible: Boolean(root.nexus?.canRedoDocument())
            height: 24
            width: 44
            radius: 6
            color: settledColors.colLayer0
            StyledText {
                anchors.centerIn: parent
                text: "Redo"
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: settledColors.colPrimary
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: if (root.nexus) root.nexus.redoDocument()
            }
        }

        Rectangle {
            visible: (root.nexus?.currentDoc?.category === "markdown") || (root.nexus?.currentDoc?.category === "code")
            height: 24
            width: 54
            radius: 6
            color: settledColors.colLayer0
            StyledText {
                anchors.centerIn: parent
                text: "History"
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: settledColors.colSubtext
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: if (root.nexus) root.nexus.openHistoryModal()
            }
        }
    }

    // Non-destructive external file modification conflict banner
    Rectangle {
        id: externalConflictBanner
        objectName: "nexusExternalConflictBanner"
        visible: Boolean(root.nexus?.externalConflictDetected && root.nexus?.externalConflictPath === root.nexus?.currentPath)
        Layout.fillWidth: true
        implicitHeight: visible ? Math.max(38, conflictBannerRow.implicitHeight + 12) : 0
        radius: 8
        color: settledColors.colLayer2
        border.width: 1
        border.color: settledColors.colPrimary

        RowLayout {
            id: conflictBannerRow
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 10
            spacing: 8

            MaterialSymbol {
                text: "warning"
                iconSize: 16
                color: settledColors.colPrimary
            }

            StyledText {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                text: "File modified externally on disk"
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.Medium
                color: settledColors.colOnLayer1
                elide: Text.ElideRight
            }

            Rectangle {
                objectName: "nexusConflictReloadButton"
                height: 26
                width: reloadConflictTxt.implicitWidth + 16
                radius: 6
                color: settledColors.colSecondaryContainer
                StyledText {
                    id: reloadConflictTxt
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    text: "Reload"
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.DemiBold
                    color: settledColors.colPrimary
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (root.nexus) root.nexus.resolveExternalConflictReload()
                }
            }

            Rectangle {
                objectName: "nexusConflictKeepButton"
                height: 26
                width: keepConflictTxt.implicitWidth + 16
                radius: 6
                color: settledColors.colPrimary
                StyledText {
                    id: keepConflictTxt
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    text: "Keep & Save"
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.DemiBold
                    color: settledColors.colOnPrimary
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (root.nexus) root.nexus.resolveExternalConflictKeep(true)
                }
            }
        }
    }

    NexusFindReplaceBar {
        id: findReplaceBar
        nexus: root.nexus
        settledColors: documentViewRoot.settledColors
        targetText: standardNoteBodyEditor.visible ? standardNoteBodyEditor.text : (root.nexus?.draftContent ?? "")
        onNavigateMatch: (matchIndex, startPos, endPos, queryText) => {
            if (vimEditorPane.visible && vimEditorArea) {
                vimEditorArea.cursorPosition = startPos;
                vimEditorArea.select(startPos, endPos);
                vimEditorArea.forceActiveFocus();
            } else if (standardNoteBodyEditor.visible) {
                standardNoteBodyEditor.cursorPosition = startPos;
                standardNoteBodyEditor.select(startPos, endPos);
                standardNoteBodyEditor.forceActiveFocus();
            }
        }
        onApplyReplacedText: newContent => {
            if (vimEditorPane.visible && vimEditorArea) {
                vimEditorArea.text = newContent;
                if (root.nexus)
                    root.nexus.saveCurrentNote(newContent);
            } else if (standardNoteBodyEditor.visible) {
                standardNoteBodyEditor.text = newContent;
            } else if (root.nexus) {
                root.nexus.saveCurrentNote(newContent);
            }
        }
    }

    NexusPropertiesPanel {
        id: propertiesPanel
        nexus: root.nexus
        settledColors: documentViewRoot.settledColors
    }

    // Floating zero-height slot anchoring Slash Menu & Hover Preview Popup inside DocumentView
    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: 0
        z: 60

        NexusSlashMenu {
            id: slashMenu
            settledColors: documentViewRoot.settledColors
            x: 16
            y: 8
            onInsertSnippet: (snippet, backOffset, actionKind) => {
                const ed = documentViewRoot._activeSlashEditor;
                if (actionKind === "paste-image") {
                    if (ed && documentViewRoot._slashStartPos >= 0) {
                        documentViewRoot._insertAtEditor(ed, "", documentViewRoot._slashStartPos, ed.cursorPosition, 0);
                    }
                    if (root.nexus)
                        root.nexus.pasteClipboardImage();
                    return;
                }
                if (ed && documentViewRoot._slashStartPos >= 0) {
                    documentViewRoot._insertAtEditor(ed, snippet, documentViewRoot._slashStartPos, ed.cursorPosition, backOffset);
                }
            }
        }

        NexusHoverPreviewPopup {
            id: hoverPreviewPopup
            nexus: root.nexus
            settledColors: documentViewRoot.settledColors
            x: Math.max(12, Math.min(parent.width - width - 12, parent.width - width - 24))
            y: 12
            onOpenTargetRequested: relPath => {
                if (root.nexus)
                    root.nexus.openFile(relPath, true);
            }
            onSplitTargetRequested: relPath => {
                if (root.nexus)
                    root.nexus.openInSecondaryPane(relPath);
            }
        }
    }

    // CASE A0: Built-in PDF Viewer (.pdf)
    Loader {
        id: pdfViewerLoader
        objectName: "nexusPdfViewerLoader"
        Layout.fillWidth: true
        Layout.fillHeight: true
        asynchronous: status !== Loader.Ready && Quickshell.env("QT_QUICK_BACKEND") !== "software"
        readonly property bool shouldLoad: (root.nexus?.currentDoc?.category ?? "") === "pdf"
        visible: shouldLoad
        function _syncSource(): void {
            if (shouldLoad && source.toString().length === 0)
                setSource(Qt.resolvedUrl("NexusPdfViewer.qml"), { nexus: root.nexus, settledColors: documentViewRoot.settledColors });
        }
        onShouldLoadChanged: _syncSource()
        Component.onCompleted: _syncSource()
        onLoaded: {
            if (item) {
                item.nexus = Qt.binding(() => root.nexus);
                item.settledColors = Qt.binding(() => documentViewRoot.settledColors);
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
                    cache: false
                    sourceSize: Qt.size(Math.max(1, Math.min(2048, Math.round(parent.width * 2))), Math.max(1, Math.min(2048, Math.round(parent.height * 2))))
                }
            }
        }
    }

    // CASE B & C: Markdown Outliner + Vim Editor Split/Toggle Container
    RowLayout {
        visible: (root.nexus?.currentDoc?.category ?? "") !== "image" && (root.nexus?.currentDoc?.category ?? "") !== "pdf"
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
                            wrapMode: TextEdit.Wrap
                            font.family: Appearance.font.family.main
                            font.pixelSize: Appearance.font.pixelSize.small + 1
                            color: settledColors.colOnLayer1
                            selectionColor: settledColors.colSecondaryContainer
                            selectedTextColor: settledColors.colOnSecondaryContainer
                            selectByMouse: true
                            inputMethodHints: Qt.ImhMultiLine
                            background: null
                            onVisibleChanged: {
                                if (visible) {
                                    text = root.standardNoteInlineDraft;
                                    forceActiveFocus();
                                    cursorPosition = text.length;
                                } else {
                                    if (inputMethodComposing)
                                        Qt.inputMethod.commit();
                                    focus = false;
                                }
                            }
                            onActiveFocusChanged: {
                                if (!activeFocus
                                    && visible
                                    && !inputMethodComposing
                                    && root.standardNoteInlineEditing
                                    && !root._cancelingStandardInlineEdit
                                    && !(root.nexus?.findBarOpen)
                                    && !standardCancelMouse.containsMouse
                                    && !standardCancelMouse.pressed) {
                                    root.commitStandardNoteInlineEdit();
                                }
                            }
                            Keys.onEscapePressed: event => {
                                if (inputMethodComposing) {
                                    event.accepted = false;
                                    return;
                                }
                                Qt.inputMethod.commit();
                                root.commitStandardNoteInlineEdit();
                                focus = false;
                                root.restoreWorkspaceFocus();
                                Qt.callLater(root.restoreWorkspaceFocus);
                                event.accepted = true;
                            }
                            Keys.onPressed: event => {
                                if (inputMethodComposing || event.key === 0 || event.key === Qt.Key_unknown) {
                                    event.accepted = false;
                                    return;
                                }
                                if (documentViewRoot._handleEditorPreKey(standardNoteBodyEditor, event)) {
                                    event.accepted = true;
                                    return;
                                }
                                if ((event.modifiers & Qt.ControlModifier)
                                    && (event.key === Qt.Key_S || event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
                                    Qt.inputMethod.commit();
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
                            onTextChanged: {
                                if (visible && activeFocus && !inputMethodComposing)
                                    documentViewRoot._handleSlashTyping(standardNoteBodyEditor);
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
                    id: blocksRepeater
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
                        property bool blockCollapsed: Boolean(modelData?.defaultCollapsed ?? false)

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
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: settledColors.colOnLayer1
                                    inputMethodHints: Qt.ImhMultiLine
                                    background: null
                                    onVisibleChanged: {
                                        if (visible) {
                                            text = String(root.nexus?.editingBlockText ?? blockDelegate.modelData.rawText ?? "");
                                            forceActiveFocus();
                                            cursorPosition = text.length;
                                        } else {
                                            if (inputMethodComposing)
                                                Qt.inputMethod.commit();
                                            inlineBlockEditor.focus = false;
                                            root.restoreWorkspaceFocus();
                                            Qt.callLater(root.restoreWorkspaceFocus);
                                        }
                                    }
                                    Keys.onEscapePressed: event => {
                                        if (inputMethodComposing) {
                                            event.accepted = false;
                                            return;
                                        }
                                        Qt.inputMethod.commit();
                                        if (root.nexus)
                                            root.nexus.editingBlockId = -1;
                                        inlineBlockEditor.focus = false;
                                        root.restoreWorkspaceFocus();
                                        Qt.callLater(root.restoreWorkspaceFocus);
                                        event.accepted = true;
                                    }
                                    Keys.onPressed: event => {
                                        if (inputMethodComposing || event.key === 0 || event.key === Qt.Key_unknown) {
                                            event.accepted = false;
                                            return;
                                        }
                                        if ((event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_S)) {
                                            Qt.inputMethod.commit();
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

                                    // Callout / Collapsible Toggle title header
                                    Item {
                                        visible: blockDelegate.modelData.kind === "callout" || blockDelegate.modelData.kind === "toggle"
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: visible ? calloutHdrRow.implicitHeight : 0

                                        RowLayout {
                                            id: calloutHdrRow
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: 6
                                            MaterialSymbol {
                                                text: blockDelegate.modelData.collapsible
                                                    ? (blockDelegate.blockCollapsed ? "chevron_right" : "expand_more")
                                                    : (blockDelegate.modelData.kind === "toggle" ? "arrow_right" : "info")
                                                iconSize: 15
                                                color: settledColors.colPrimary
                                            }
                                            StyledText {
                                                Layout.fillWidth: true
                                                text: (blockDelegate.modelData.kind === "toggle" || blockDelegate.modelData.calloutType === "TOGGLE")
                                                    ? String(blockDelegate.modelData.title ?? "Toggle")
                                                    : ("[" + String(blockDelegate.modelData.calloutType ?? "NOTE") + "] " + String(blockDelegate.modelData.title ?? ""))
                                                font.weight: Font.Bold
                                                font.pixelSize: Appearance.font.pixelSize.smaller
                                                color: settledColors.colPrimary
                                                elide: Text.ElideRight
                                            }
                                        }

                                        MouseArea {
                                            visible: Boolean(blockDelegate.modelData.collapsible || blockDelegate.modelData.kind === "toggle")
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: blockDelegate.blockCollapsed = !blockDelegate.blockCollapsed
                                        }
                                    }

                                    // Mermaid Diagram Block (kind === "code" && lang === "mermaid")
                                    NexusDiagramView {
                                        visible: blockDelegate.modelData.kind === "code"
                                            && String(blockDelegate.modelData.lang ?? "").toLowerCase() === "mermaid"
                                            && !blockDelegate.blockCollapsed
                                        settledColors: documentViewRoot.settledColors
                                        mermaidSource: String(blockDelegate.modelData.text ?? "")
                                    }

                                    // Non-Mermaid Code Header + Copy Pill
                                    RowLayout {
                                        visible: blockDelegate.modelData.kind === "code"
                                            && String(blockDelegate.modelData.lang ?? "").toLowerCase() !== "mermaid"
                                        Layout.fillWidth: true
                                        spacing: 6
                                        StyledText {
                                            text: String(blockDelegate.modelData.lang || "code")
                                            font.family: Appearance.font.family.monospace
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            color: settledColors.colSubtext
                                        }
                                        Item { Layout.fillWidth: true }
                                        Rectangle {
                                            height: 20; width: 46; radius: 5
                                            color: settledColors.colLayer1
                                            StyledText {
                                                anchors.centerIn: parent
                                                text: "Copy"
                                                horizontalAlignment: Text.AlignHCenter
                                                font.pixelSize: Appearance.font.pixelSize.smallest
                                                color: settledColors.colPrimary
                                            }
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    if (root.nexus)
                                                        root.nexus.copyToClipboard(String(blockDelegate.modelData.text ?? ""), "Copied code block");
                                                }
                                            }
                                        }
                                    }

                                    // Transcluded Embed Card (kind === "embed", ![[Note#Subpath]])
                                    Rectangle {
                                        visible: blockDelegate.modelData.kind === "embed"
                                        Layout.fillWidth: true
                                        implicitHeight: embedCol.implicitHeight + 16
                                        radius: 8
                                        color: settledColors.colLayer0
                                        border.width: 1
                                        border.color: settledColors.colPrimary

                                        ColumnLayout {
                                            id: embedCol
                                            anchors.fill: parent
                                            anchors.margins: 8
                                            spacing: 4
                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 6
                                                MaterialSymbol { text: "post_add"; iconSize: 15; color: settledColors.colPrimary }
                                                StyledText {
                                                    Layout.fillWidth: true
                                                    text: String(blockDelegate.modelData.embedTitle || blockDelegate.modelData.embedTarget || "Embed")
                                                        + (blockDelegate.modelData.embedSubpath ? (" › " + String(blockDelegate.modelData.embedSubpath)) : "")
                                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                                    font.weight: Font.DemiBold
                                                    color: settledColors.colPrimary
                                                    elide: Text.ElideRight
                                                }
                                                Rectangle {
                                                    visible: String(blockDelegate.modelData.embedRelPath ?? "").length > 0
                                                    height: 20; width: 46; radius: 5
                                                    color: settledColors.colSecondaryContainer
                                                    StyledText {
                                                        anchors.centerIn: parent
                                                        text: "Open"
                                                        horizontalAlignment: Text.AlignHCenter
                                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                                        color: settledColors.colPrimary
                                                    }
                                                    MouseArea {
                                                        anchors.fill: parent
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: if (root.nexus) root.nexus.openFile(String(blockDelegate.modelData.embedRelPath || blockDelegate.modelData.embedTarget || ""), true)
                                                    }
                                                }
                                            }
                                            StyledText {
                                                Layout.fillWidth: true
                                                text: String(blockDelegate.modelData.embedExcerpt || blockDelegate.modelData.text || "")
                                                font.pixelSize: Appearance.font.pixelSize.smaller
                                                color: settledColors.colOnLayer1
                                                wrapMode: Text.WordWrap
                                            }
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

                                    // Horizontal Rule / Divider Block (100% parity with Obsidian 03_Compatibility.css hr)
                                    NexusSeparator {
                                        visible: blockDelegate.modelData.kind === "divider" || blockDelegate.modelData.kind === "hr"
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: visible ? 34 : 0
                                        Layout.topMargin: visible ? 6 : 0
                                        Layout.bottomMargin: visible ? 6 : 0
                                        accentColor: settledColors.colPrimary
                                        mutedColor: settledColors.colSubtext
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
                                            cache: false
                                            sourceSize: Qt.size(1200, 900)
                                        }
                                    }

                                    // Rich Text for Heading / Bullet / Todo / Paragraph / Quote / Collapsible / Code / Math
                                    Text {
                                        visible: blockDelegate.modelData.kind !== "table"
                                            && blockDelegate.modelData.kind !== "divider"
                                            && blockDelegate.modelData.kind !== "hr"
                                            && blockDelegate.modelData.kind !== "image"
                                            && blockDelegate.modelData.kind !== "embed"
                                            && !(blockDelegate.modelData.kind === "code" && String(blockDelegate.modelData.lang ?? "").toLowerCase() === "mermaid")
                                            && !(blockDelegate.modelData.kind === "heading" && Boolean(blockDelegate.modelData.calloutType))
                                            && !blockDelegate.blockCollapsed
                                        Layout.fillWidth: true
                                        textFormat: Text.RichText
                                        text: {
                                            const b = blockDelegate.modelData || {};
                                            if (b.kind === "math")
                                                return Rich.renderLatexToHtml(String(b.text ?? ""), true, settledColors.colPrimary, settledColors.colOnLayer1);
                                            if (b.kind === "code") {
                                                return Rich.highlightCodeToHtml(String(b.text ?? ""), String(b.lang ?? ""), {
                                                    text: settledColors.colOnLayer1,
                                                    keyword: settledColors.colPrimary,
                                                    comment: settledColors.colSubtext
                                                });
                                            }
                                            if (b.richHtml)
                                                return root.themeRichHtml(b.richHtml);
                                            return Rich.renderInlineMarkdownToHtml(String(b.text ?? ""), settledColors.colOnLayer1, settledColors.colPrimary, settledColors.colSubtext);
                                        }
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
                                        function _safeDecodeUriComponent(raw) {
                                            const str = String(raw ?? "");
                                            try {
                                                return decodeURIComponent(str);
                                            } catch (_e) {
                                                return str;
                                            }
                                        }
                                        onLinkActivated: link => {
                                            if (!root.nexus)
                                                return;
                                            if (link.startsWith("wikilink:")) {
                                                let wl = link.substring("wikilink:".length);
                                                if (wl.startsWith("//")) wl = wl.substring(2);
                                                root.nexus.followWikilink(_safeDecodeUriComponent(wl));
                                            } else if (link.startsWith("tag:")) {
                                                const tag = _safeDecodeUriComponent(link.substring("tag:".length));
                                                root.nexus.leftSidebarTab = "search";
                                                root.nexus.searchVault("#" + tag);
                                            } else if (/^https?:\/\//i.test(link)) {
                                                root.nexus.openExternalUrl(link);
                                            }
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.IBeamCursor
                                            onPositionChanged: mouse => {
                                                const la = String(parent.linkAt ? (parent.linkAt(mouse.x, mouse.y) || "") : "");
                                                if (la.startsWith("wikilink:")) {
                                                    let tgt = la.substring("wikilink:".length);
                                                    if (tgt.startsWith("//")) tgt = tgt.substring(2);
                                                    tgt = parent._safeDecodeUriComponent(tgt);
                                                    if (documentViewRoot._hoveredPreviewTarget !== tgt) {
                                                        documentViewRoot._hoveredPreviewTarget = tgt;
                                                        hoverPreviewDelayTimer.restart();
                                                    }
                                                } else if (documentViewRoot._hoveredPreviewTarget.length > 0) {
                                                    documentViewRoot._hoveredPreviewTarget = "";
                                                    hoverPreviewHideTimer.restart();
                                                }
                                            }
                                            onExited: {
                                                documentViewRoot._hoveredPreviewTarget = "";
                                                hoverPreviewDelayTimer.stop();
                                                hoverPreviewHideTimer.restart();
                                            }
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
                        implicitHeight: backlinkCol.implicitHeight + 16
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
                                id: backlinkCol
                                Layout.fillWidth: true
                                spacing: 2
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6
                                    StyledText {
                                        text: String(modelData.title ?? "") + "  (L" + String(modelData.line ?? 1) + ")"
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        font.weight: Font.DemiBold
                                        color: settledColors.colOnLayer1
                                    }
                                    StyledText {
                                        visible: String(modelData.heading ?? "").length > 0
                                        text: "› " + String(modelData.heading ?? "")
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: settledColors.colPrimary
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                }
                                StyledText {
                                    visible: String(modelData.contextBefore ?? "").length > 0
                                    Layout.fillWidth: true
                                    text: String(modelData.contextBefore ?? "")
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: Qt.alpha(settledColors.colSubtext, 0.72)
                                    elide: Text.ElideRight
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: String(modelData.snippet ?? "")
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: settledColors.colOnLayer1
                                    wrapMode: Text.WordWrap
                                }
                                StyledText {
                                    visible: String(modelData.contextAfter ?? "").length > 0
                                    Layout.fillWidth: true
                                    text: String(modelData.contextAfter ?? "")
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: Qt.alpha(settledColors.colSubtext, 0.72)
                                    elide: Text.ElideRight
                                }
                            }
                            Rectangle {
                                height: 24; width: 46; radius: 6
                                color: settledColors.colSecondaryContainer
                                StyledText {
                                    anchors.centerIn: parent
                                    text: "Split"
                                    horizontalAlignment: Text.AlignHCenter
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: settledColors.colPrimary
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: if (root.nexus) root.nexus.openInSecondaryPane(modelData.relPath)
                                }
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            anchors.rightMargin: 58
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
                    property bool _syncingFromEditor: false
                    font.family: Appearance.font.family.monospace
                    font.pixelSize: Appearance.font.pixelSize.small + 1
                    color: settledColors.colOnLayer1
                    selectionColor: settledColors.colPrimary
                    selectedTextColor: settledColors.colOnPrimary
                    wrapMode: TextEdit.Wrap
                    inputMethodHints: Qt.ImhMultiLine
                    background: null
                    cursorVisible: vimEditorPane.visible
                    readOnly: (root.nexus?.vimEnabled ?? true) && (root.nexus?.vimMode ?? "NORMAL") !== "INSERT"

                    function syncFromService(forceSync: bool): void {
                        if (!root.nexus)
                            return;
                        if (_syncingFromEditor)
                            return;
                        if (!forceSync && inputMethodComposing)
                            return;
                        const nextText = String(root.nexus.draftContent ?? "");
                        if (text !== nextText) {
                            const prevCursor = cursorPosition;
                            _syncingFromEditor = true;
                            text = nextText;
                            cursorPosition = Math.max(0, Math.min(nextText.length, prevCursor));
                            _syncingFromEditor = false;
                        }
                    }

                    Component.onCompleted: syncFromService(true)

                    Connections {
                        target: root.nexus
                        function onDraftContentChanged(): void {
                            vimEditorArea.syncFromService(false);
                        }
                        function onCurrentDocChanged(): void {
                            vimEditorArea.syncFromService(true);
                        }
                    }

                    onActiveFocusChanged: {
                        if (activeFocus && vimEditorPane.visible)
                            cursorVisible = true;
                    }
                    onReadOnlyChanged: {
                        if (readOnly && inputMethodComposing)
                            Qt.inputMethod.commit();
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

                    function _syncEditorTextToService(): void {
                        if (_syncingFromEditor || inputMethodComposing)
                            return;
                        if (root.nexus && text !== root.nexus.draftContent) {
                            _syncingFromEditor = true;
                            root.nexus.draftContent = text;
                            root.nexus.isDirty = (text !== String(root.nexus.currentDoc?.content ?? ""));
                            _syncingFromEditor = false;
                        }
                    }

                    onTextChanged: {
                        _syncEditorTextToService();
                        if (visible && activeFocus && !inputMethodComposing && !readOnly)
                            documentViewRoot._handleSlashTyping(vimEditorArea);
                    }
                    onInputMethodComposingChanged: {
                        if (!inputMethodComposing)
                            _syncEditorTextToService();
                    }

                    Keys.onPressed: event => {
                        if (inputMethodComposing || event.key === 0 || event.key === Qt.Key_unknown) {
                            event.accepted = false;
                            return;
                        }
                        if (documentViewRoot._handleEditorPreKey(vimEditorArea, event)) {
                            event.accepted = true;
                            return;
                        }
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
