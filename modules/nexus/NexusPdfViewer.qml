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
    readonly property int totalPages: Math.max(1, Number(nexus?.pdfInfo?.pages ?? 1))
    readonly property int curPage: Math.max(1, Number(nexus?.pdfCurrentPage ?? 1))

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
                SplitView.fillWidth: true
                SplitView.fillHeight: true
                clip: true

                Item {
                    width: Math.max(parent.width, pageImage.implicitWidth)
                    height: Math.max(parent.height, pageImage.implicitHeight + 24)

                    Image {
                        id: pageImage
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.top
                        anchors.topMargin: 12
                        source: String(pdfRoot.nexus?.pdfPageImageUrl ?? "")
                        asynchronous: true
                        smooth: true
                        fillMode: Image.PreserveAspectFit
                        width: Math.min(sourceSize.width > 0 ? sourceSize.width : 800, parent.width - 24)
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

                    ScrollView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        TextArea {
                            id: extractedArea
                            readOnly: true
                            selectByMouse: true
                            wrapMode: TextEdit.Wrap
                            text: String(pdfRoot.nexus?.pdfExtractedText ?? "")
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
