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
