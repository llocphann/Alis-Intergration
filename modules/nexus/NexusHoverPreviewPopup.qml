import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

Rectangle {
    id: previewPopupRoot
    property var nexus: null
    property var settledColors: null
    property bool hovered: popupHover.containsMouse
    property bool openRequested: false

    signal openTargetRequested(string relPath)
    signal splitTargetRequested(string relPath)
    signal closed()

    readonly property var dataObj: nexus?.hoverPreviewData ?? null
    readonly property bool loading: Boolean(nexus?.hoverPreviewLoading ?? false)
    visible: openRequested && (loading || dataObj !== null)

    width: 340
    height: Math.min(260, Math.max(96, contentCol.implicitHeight + 24))
    radius: 12
    color: settledColors?.colLayer2 ?? Appearance.colors.colLayer2
    border.width: 1
    border.color: settledColors?.colPrimary ?? Appearance.colors.colPrimary
    z: 60

    MouseArea {
        id: popupHover
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
    }

    ColumnLayout {
        id: contentCol
        anchors.fill: parent
        anchors.margins: 12
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            MaterialSymbol {
                text: "article"
                iconSize: 16
                color: previewPopupRoot.settledColors?.colPrimary ?? Appearance.colors.colPrimary
            }

            StyledText {
                Layout.fillWidth: true
                text: previewPopupRoot.loading
                    ? "Loading preview…"
                    : String(previewPopupRoot.dataObj?.title ?? previewPopupRoot.dataObj?.relPath ?? "")
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.DemiBold
                color: previewPopupRoot.settledColors?.colOnLayer1 ?? Appearance.colors.colOnLayer1
                elide: Text.ElideRight
            }

            StyledText {
                visible: !previewPopupRoot.loading && Number(previewPopupRoot.dataObj?.wordCount ?? 0) > 0
                text: String(previewPopupRoot.dataObj?.wordCount ?? 0) + "w"
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: previewPopupRoot.settledColors?.colSubtext ?? Appearance.colors.colSubtext
            }
        }

        StyledText {
            visible: !previewPopupRoot.loading && String(previewPopupRoot.dataObj?.folder ?? "").length > 0
            Layout.fillWidth: true
            text: String(previewPopupRoot.dataObj?.folder ?? "")
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: previewPopupRoot.settledColors?.colSubtext ?? Appearance.colors.colSubtext
            elide: Text.ElideMiddle
        }

        ScrollView {
            visible: !previewPopupRoot.loading
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: Math.min(130, excerptLbl.implicitHeight + 4)
            clip: true

            StyledText {
                id: excerptLbl
                width: 310
                text: {
                    const lines = previewPopupRoot.dataObj?.excerptLines;
                    if (Array.isArray(lines) && lines.length > 0)
                        return lines.slice(0, 12).join("\n");
                    return "(Empty note)";
                }
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: previewPopupRoot.settledColors?.colOnLayer1 ?? Appearance.colors.colOnLayer1
                wrapMode: Text.WordWrap
            }
        }

        RowLayout {
            visible: !previewPopupRoot.loading && String(previewPopupRoot.dataObj?.relPath ?? "").length > 0
            Layout.fillWidth: true
            spacing: 6

            Item { Layout.fillWidth: true }

            Rectangle {
                height: 24; width: 64; radius: 6
                color: previewPopupRoot.settledColors?.colLayer1 ?? Appearance.colors.colLayer1
                StyledText {
                    anchors.centerIn: parent
                    text: "Split"
                    horizontalAlignment: Text.AlignHCenter
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: previewPopupRoot.settledColors?.colOnLayer1 ?? Appearance.colors.colOnLayer1
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        const rel = String(previewPopupRoot.dataObj?.relPath ?? "");
                        previewPopupRoot.openRequested = false;
                        if (rel)
                            previewPopupRoot.splitTargetRequested(rel);
                    }
                }
            }

            Rectangle {
                height: 24; width: 64; radius: 6
                color: previewPopupRoot.settledColors?.colPrimary ?? Appearance.colors.colPrimary
                StyledText {
                    anchors.centerIn: parent
                    text: "Open"
                    horizontalAlignment: Text.AlignHCenter
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.DemiBold
                    color: previewPopupRoot.settledColors?.colOnPrimary ?? Appearance.colors.colOnPrimary
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        const rel = String(previewPopupRoot.dataObj?.relPath ?? "");
                        previewPopupRoot.openRequested = false;
                        if (rel)
                            previewPopupRoot.openTargetRequested(rel);
                    }
                }
            }
        }
    }
}
