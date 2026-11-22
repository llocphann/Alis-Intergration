import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import "NexusRichRenderers.js" as Rich

Rectangle {
    id: secondaryRoot
    property var nexus: null
    property var settledColors: null

    readonly property var doc: nexus?.secondaryDoc ?? null
    visible: Boolean(nexus?.splitPaneOpen ?? false)
    radius: 12
    color: settledColors?.colLayer1 ?? Appearance.colors.colLayer1

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            MaterialSymbol {
                text: "vertical_split"
                iconSize: 16
                color: secondaryRoot.settledColors?.colPrimary ?? Appearance.colors.colPrimary
            }

            StyledText {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                text: String(secondaryRoot.doc?.title ?? secondaryRoot.nexus?.secondaryPath ?? "Secondary Pane")
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.DemiBold
                color: secondaryRoot.settledColors?.colOnLayer1 ?? Appearance.colors.colOnLayer1
                elide: Text.ElideRight
            }

            Rectangle {
                height: 24; width: 48; radius: 6
                color: secondaryRoot.settledColors?.colLayer0 ?? Appearance.colors.colLayer0
                StyledText {
                    anchors.centerIn: parent
                    text: "Swap"
                    horizontalAlignment: Text.AlignHCenter
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: secondaryRoot.settledColors?.colPrimary ?? Appearance.colors.colPrimary
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (secondaryRoot.nexus) secondaryRoot.nexus.swapPanes() }
            }

            Rectangle {
                height: 24; width: 24; radius: 6
                color: secondaryRoot.settledColors?.colLayer0 ?? Appearance.colors.colLayer0
                MaterialSymbol { anchors.centerIn: parent; text: "close"; iconSize: 15; color: secondaryRoot.settledColors?.colSubtext ?? Appearance.colors.colSubtext }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (secondaryRoot.nexus) secondaryRoot.nexus.closeSecondaryPane() }
            }
        }

        ListView {
            id: secondaryBlocksList
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 6
            boundsBehavior: Flickable.StopAtBounds
            model: Array.isArray(secondaryRoot.doc?.blocks) ? secondaryRoot.doc.blocks : []
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            delegate: Rectangle {
                required property var modelData
                width: secondaryBlocksList.width - 6
                implicitHeight: blkText.implicitHeight + 10
                height: implicitHeight
                radius: 6
                color: secondaryRoot.settledColors?.colLayer0 ?? Appearance.colors.colLayer0

                StyledText {
                    id: blkText
                    anchors.fill: parent
                    anchors.margins: 6
                    textFormat: Text.RichText
                    text: {
                        const b = modelData || {};
                        const colTxt = String(secondaryRoot.settledColors?.colOnLayer1 ?? Appearance.colors.colOnLayer1);
                        const colAcc = String(secondaryRoot.settledColors?.colPrimary ?? Appearance.colors.colPrimary);
                        const colMut = String(secondaryRoot.settledColors?.colSubtext ?? Appearance.colors.colSubtext);
                        if (b.kind === "math")
                            return Rich.renderLatexToHtml(String(b.text ?? ""), true, colAcc, colTxt);
                        return Rich.renderInlineMarkdownToHtml(String(b.text ?? ""), colTxt, colAcc, colMut);
                    }
                    font.pixelSize: modelData.kind === "heading"
                        ? Math.max(13, 20 - Number(modelData.level ?? 1) * 2)
                        : Appearance.font.pixelSize.smaller
                    font.weight: modelData.kind === "heading" ? Font.Bold : Font.Normal
                    wrapMode: Text.WordWrap
                    onLinkActivated: link => {
                        if (link.startsWith("wikilink://") && secondaryRoot.nexus) {
                            secondaryRoot.nexus.openInSecondaryPane(link.slice("wikilink://".length));
                        } else if (secondaryRoot.nexus) {
                            secondaryRoot.nexus.openExternalUrl(link);
                        }
                    }
                }
            }
        }
    }
}
