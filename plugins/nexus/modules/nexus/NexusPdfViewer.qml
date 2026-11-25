import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

Rectangle {
    id: pdfRoot
    property var nexus: null
    property var settledColors: null

    property bool showTextDrawer: false
    property bool searchOpen: false
    property string searchQuery: ""
    readonly property int totalPages: Math.max(1, Number(nexus?.pdfInfo?.pages ?? 1))
    readonly property int curPage: Math.max(1, Number(nexus?.pdfCurrentPage ?? 1))

    onCurPageChanged: {
        if (pdfRoot.showTextDrawer && pdfRoot.nexus)
            pdfRoot.nexus.pdfExtractPageText(pdfRoot.curPage);
    }

    focus: true
    Keys.onPressed: event => {
        if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_F) {
            pdfRoot.searchOpen = !pdfRoot.searchOpen;
            if (pdfRoot.searchOpen) {
                pdfRoot.showTextDrawer = true;
                if (pdfRoot.nexus) pdfRoot.nexus.pdfExtractPageText(pdfRoot.curPage);
                Qt.callLater(() => pdfSearchField.forceActiveFocus());
            }
            event.accepted = true;
        } else if (event.key === Qt.Key_Escape && pdfRoot.searchOpen) {
            pdfRoot.searchOpen = false;
            pdfRoot.searchQuery = "";
            event.accepted = true;
        } else if (!pdfSearchField.activeFocus && (event.key === Qt.Key_Left || event.key === Qt.Key_PageUp)) {
            if (pdfRoot.nexus && pdfRoot.curPage > 1) pdfRoot.nexus.pdfLoadPage(pdfRoot.curPage - 1);
            event.accepted = true;
        } else if (!pdfSearchField.activeFocus && (event.key === Qt.Key_Right || event.key === Qt.Key_PageDown)) {
            if (pdfRoot.nexus && pdfRoot.curPage < pdfRoot.totalPages) pdfRoot.nexus.pdfLoadPage(pdfRoot.curPage + 1);
            event.accepted = true;
        }
    }

    color: settledColors?.colLayer0 ?? Appearance.colors.colLayer0
    radius: 10
    clip: true

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 8

        // PDF Controls bar
        Rectangle {
            Layout.fillWidth: true
            height: 40
            radius: 8
            color: pdfRoot.settledColors?.colLayer1 ?? Appearance.colors.colLayer1

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 8

                MaterialSymbol {
                    text: "picture_as_pdf"
                    iconSize: 18
                    color: pdfRoot.settledColors?.colPrimary ?? Appearance.colors.colPrimary
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: String(pdfRoot.nexus?.pdfInfo?.title ?? pdfRoot.nexus?.currentDoc?.title ?? "PDF Document")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: pdfRoot.settledColors?.colOnLayer1 ?? Appearance.colors.colOnLayer1
                    elide: Text.ElideRight
                }

                Rectangle {
                    height: 26; width: 28; radius: 6
                    color: pdfRoot.settledColors?.colLayer0 ?? Appearance.colors.colLayer0
                    MaterialSymbol { anchors.centerIn: parent; text: "chevron_left"; iconSize: 16; color: pdfRoot.settledColors?.colOnLayer1 ?? Appearance.colors.colOnLayer1 }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (pdfRoot.nexus && pdfRoot.curPage > 1) pdfRoot.nexus.pdfLoadPage(pdfRoot.curPage - 1)
                    }
                }

                StyledText {
                    text: pdfRoot.curPage + " / " + pdfRoot.totalPages
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: pdfRoot.settledColors?.colOnLayer1 ?? Appearance.colors.colOnLayer1
                }

                Rectangle {
                    height: 26; width: 28; radius: 6
                    color: pdfRoot.settledColors?.colLayer0 ?? Appearance.colors.colLayer0
                    MaterialSymbol { anchors.centerIn: parent; text: "chevron_right"; iconSize: 16; color: pdfRoot.settledColors?.colOnLayer1 ?? Appearance.colors.colOnLayer1 }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (pdfRoot.nexus && pdfRoot.curPage < pdfRoot.totalPages) pdfRoot.nexus.pdfLoadPage(pdfRoot.curPage + 1)
                    }
                }

                Rectangle {
                    height: 26; width: 26; radius: 6
                    color: pdfRoot.settledColors?.colLayer0 ?? Appearance.colors.colLayer0
                    StyledText { anchors.centerIn: parent; text: "-"; horizontalAlignment: Text.AlignHCenter; font.pixelSize: Appearance.font.pixelSize.normal; color: pdfRoot.settledColors?.colOnLayer1 ?? Appearance.colors.colOnLayer1 }
                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: if (pdfRoot.nexus) pdfRoot.nexus.pdfLoadPage(pdfRoot.curPage, Math.max(90, pdfRoot.nexus.pdfDpi - 30))
                    }
                }

                StyledText {
                    text: String(Math.round((pdfRoot.nexus?.pdfDpi ?? 150) / 1.5)) + "%"
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: pdfRoot.settledColors?.colSubtext ?? Appearance.colors.colSubtext
                }

                Rectangle {
                    height: 26; width: 26; radius: 6
                    color: pdfRoot.settledColors?.colLayer0 ?? Appearance.colors.colLayer0
                    StyledText { anchors.centerIn: parent; text: "+"; horizontalAlignment: Text.AlignHCenter; font.pixelSize: Appearance.font.pixelSize.normal; color: pdfRoot.settledColors?.colOnLayer1 ?? Appearance.colors.colOnLayer1 }
                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: if (pdfRoot.nexus) pdfRoot.nexus.pdfLoadPage(pdfRoot.curPage, Math.min(270, pdfRoot.nexus.pdfDpi + 30))
                    }
                }

                Rectangle {
                    height: 26; width: 92; radius: 6
                    color: pdfRoot.showTextDrawer
                        ? (pdfRoot.settledColors?.colPrimary ?? Appearance.colors.colPrimary)
                        : (pdfRoot.settledColors?.colSecondaryContainer ?? Appearance.colors.colSecondaryContainer)
                    StyledText {
                        anchors.centerIn: parent
                        text: "Highlight Text"
                        horizontalAlignment: Text.AlignHCenter
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: pdfRoot.showTextDrawer
                            ? (pdfRoot.settledColors?.colOnPrimary ?? Appearance.colors.colOnPrimary)
                            : (pdfRoot.settledColors?.colPrimary ?? Appearance.colors.colPrimary)
                    }
                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            pdfRoot.showTextDrawer = !pdfRoot.showTextDrawer;
                            if (pdfRoot.showTextDrawer && pdfRoot.nexus)
                                pdfRoot.nexus.pdfExtractPageText(pdfRoot.curPage);
                        }
                    }
                }

                Rectangle {
                    height: 26; width: 64; radius: 6
                    color: pdfRoot.settledColors?.colLayer0 ?? Appearance.colors.colLayer0
                    StyledText {
                        anchors.centerIn: parent
                        text: "External"
                        horizontalAlignment: Text.AlignHCenter
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: pdfRoot.settledColors?.colSubtext ?? Appearance.colors.colSubtext
                    }
                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: if (pdfRoot.nexus && pdfRoot.nexus.currentDoc?.absPath) pdfRoot.nexus.openExternally(String(pdfRoot.nexus.currentDoc.absPath))
                    }
                }
            }
        }

        // Page image + optional Highlight drawer
        SplitView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            orientation: Qt.Horizontal

            ScrollView {
                id: pdfScroll
                SplitView.fillWidth: true
                SplitView.fillHeight: true
                clip: true

                Item {
                    readonly property real viewportW: Math.max(200, pdfScroll.availableWidth)
                    readonly property real viewportH: Math.max(200, pdfScroll.availableHeight)
                    readonly property real targetPageW: {
                        const dpi = Math.max(60, Math.min(360, Number(pdfRoot.nexus?.pdfDpi ?? 150)))
                        const baseFitW = Math.max(200, viewportW - 24)
                        return Math.max(200, Math.round(baseFitW * (dpi / 150.0)))
                    }
                    readonly property real targetPageH: (pageImage.sourceSize.width > 0 && pageImage.sourceSize.height > 0)
                        ? Math.round(targetPageW * (pageImage.sourceSize.height / pageImage.sourceSize.width))
                        : Math.max(200, pageImage.implicitHeight)
                    width: Math.max(viewportW, targetPageW + 24)
                    height: Math.max(viewportH, targetPageH + 24)

                    WheelHandler {
                        acceptedModifiers: Qt.ControlModifier
                        onWheel: wheel => {
                            if (!pdfRoot.nexus) return;
                            const curDpi = Number(pdfRoot.nexus.pdfDpi ?? 150);
                            const nextDpi = wheel.angleDelta.y > 0
                                ? Math.min(270, curDpi + 30)
                                : Math.max(90, curDpi - 30);
                            if (nextDpi !== curDpi)
                                pdfRoot.nexus.pdfLoadPage(pdfRoot.curPage, nextDpi);
                            wheel.accepted = true;
                        }
                    }

                    Image {
                        id: pageImage
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.top
                        anchors.topMargin: 12
                        source: String(pdfRoot.nexus?.pdfPageImageUrl ?? "")
                        asynchronous: true
                        cache: false
                        smooth: true
                        fillMode: Image.PreserveAspectFit
                        width: parent.targetPageW
                        height: parent.targetPageH
                    }

                    StyledText {
                        visible: Boolean(pdfRoot.nexus?.pdfBusy) && !pdfRoot.nexus?.pdfPageImageUrl
                        anchors.centerIn: parent
                        text: "Rendering PDF page…"
                        color: pdfRoot.settledColors?.colSubtext ?? Appearance.colors.colSubtext
                    }
                }
            }

            Rectangle {
                visible: pdfRoot.showTextDrawer
                SplitView.preferredWidth: 320
                SplitView.minimumWidth: 220
                SplitView.fillHeight: true
                radius: 8
                color: pdfRoot.settledColors?.colLayer1 ?? Appearance.colors.colLayer1

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 6

                    StyledText {
                        text: "Page " + pdfRoot.curPage + " Text · Select & Capture Highlight"
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: Font.DemiBold
                        color: pdfRoot.settledColors?.colOnLayer1 ?? Appearance.colors.colOnLayer1
                    }

                    TextField {
                        id: pdfSearchField
                        visible: pdfRoot.searchOpen
                        Layout.fillWidth: true
                        implicitHeight: 28
                        placeholderText: "Find in page text (Ctrl+F)..."
                        color: pdfRoot.settledColors?.colOnLayer1 ?? Appearance.colors.colOnLayer1
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        onTextChanged: pdfRoot.searchQuery = text
                        background: Rectangle { radius: 6; color: pdfRoot.settledColors?.colLayer0 ?? Appearance.colors.colLayer0 }
                    }

                    ScrollView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        TextArea {
                            id: extractedArea
                            readOnly: true
                            selectByMouse: true
                            wrapMode: TextEdit.Wrap
                            text: {
                                const raw = String(pdfRoot.nexus?.pdfExtractedText ?? "");
                                const q = String(pdfRoot.searchQuery ?? "").trim().toLowerCase();
                                if (!q) return raw;
                                const matched = raw.split("\n").filter(ln => ln.toLowerCase().includes(q));
                                return matched.length > 0 ? matched.join("\n") : ("No matches for \"" + pdfRoot.searchQuery + "\" on page " + pdfRoot.curPage);
                            }
                            color: pdfRoot.settledColors?.colOnLayer1 ?? Appearance.colors.colOnLayer1
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            background: Rectangle { radius: 6; color: pdfRoot.settledColors?.colLayer0 ?? Appearance.colors.colLayer0 }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 30; radius: 8
                        color: pdfRoot.settledColors?.colPrimary ?? Appearance.colors.colPrimary
                        StyledText {
                            anchors.centerIn: parent
                            text: "Highlight -> Note"
                            horizontalAlignment: Text.AlignHCenter
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.DemiBold
                            color: pdfRoot.settledColors?.colOnPrimary ?? Appearance.colors.colOnPrimary
                        }
                        MouseArea {
                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (!pdfRoot.nexus) return;
                                const sel = extractedArea.selectedText.trim() || extractedArea.text.trim().slice(0, 320);
                                if (sel)
                                    pdfRoot.nexus.capturePdfHighlight(sel, "", pdfRoot.curPage);
                            }
                        }
                    }
                }
            }
        }
    }
}
