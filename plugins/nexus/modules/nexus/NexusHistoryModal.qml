import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

Rectangle {
    id: historyRoot
    property var nexus: null
    property var settledColors: null

    visible: Boolean(nexus?.historyModalOpen ?? false)
    anchors.fill: parent
    color: Qt.rgba(0, 0, 0, 0.52)
    z: 96

    MouseArea {
        anchors.fill: parent
        onClicked: if (historyRoot.nexus) historyRoot.nexus.historyModalOpen = false
    }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width - 48, 860)
        height: Math.min(parent.height - 48, 560)
        radius: 14
        color: historyRoot.settledColors?.colLayer1 ?? Appearance.colors.colLayer1

        MouseArea { anchors.fill: parent }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                MaterialSymbol {
                    text: "history"
                    iconSize: 18
                    color: historyRoot.settledColors?.colPrimary ?? Appearance.colors.colPrimary
                }

                StyledText {
                    Layout.fillWidth: true; Layout.minimumWidth: 0
                    text: "Version History · " + String(historyRoot.nexus?.currentPath ?? "")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: historyRoot.settledColors?.colOnLayer1 ?? Appearance.colors.colOnLayer1
                    elide: Text.ElideRight
                }

                Rectangle {
                    height: 28; width: 108; radius: 8
                    color: historyRoot.settledColors?.colSecondaryContainer ?? Appearance.colors.colSecondaryContainer
                    StyledText {
                        anchors.centerIn: parent
                        text: "Take Snapshot"
                        horizontalAlignment: Text.AlignHCenter
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: historyRoot.settledColors?.colPrimary ?? Appearance.colors.colPrimary
                    }
                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: if (historyRoot.nexus) historyRoot.nexus.snapshotCurrentNote("Manual snapshot")
                    }
                }

                Rectangle {
                    visible: String(historyRoot.nexus?.historySelectedRevId ?? "").length > 0
                    height: 28; width: 112; radius: 8
                    color: historyRoot.settledColors?.colPrimary ?? Appearance.colors.colPrimary
                    StyledText {
                        anchors.centerIn: parent
                        text: "Restore Revision"
                        horizontalAlignment: Text.AlignHCenter
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: Font.DemiBold
                        color: historyRoot.settledColors?.colOnPrimary ?? Appearance.colors.colOnPrimary
                    }
                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: if (historyRoot.nexus) historyRoot.nexus.restoreNoteRevision(historyRoot.nexus.historySelectedRevId)
                    }
                }

                Rectangle {
                    height: 28; width: 28; radius: 8
                    color: historyRoot.settledColors?.colLayer0 ?? Appearance.colors.colLayer0
                    MaterialSymbol { anchors.centerIn: parent; text: "close"; iconSize: 16; color: historyRoot.settledColors?.colSubtext ?? Appearance.colors.colSubtext }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (historyRoot.nexus) historyRoot.nexus.historyModalOpen = false }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 10

                // Revision List
                Rectangle {
                    Layout.preferredWidth: 260
                    Layout.fillHeight: true
                    radius: 8
                    color: historyRoot.settledColors?.colLayer0 ?? Appearance.colors.colLayer0

                    ListView {
                        anchors.fill: parent; anchors.margins: 6
                        clip: true
                        spacing: 4
                        model: historyRoot.nexus?.historyRevisions ?? []
                        delegate: Rectangle {
                            required property var modelData
                            readonly property bool selected: String(historyRoot.nexus?.historySelectedRevId ?? "") === String(modelData.revId ?? "")
                            width: ListView.view.width
                            height: 50; radius: 6
                            color: selected
                                ? (historyRoot.settledColors?.colSecondaryContainer ?? Appearance.colors.colSecondaryContainer)
                                : (historyRoot.settledColors?.colLayer1 ?? Appearance.colors.colLayer1)
                            ColumnLayout {
                                anchors.fill: parent; anchors.margins: 6; spacing: 2
                                RowLayout {
                                    Layout.fillWidth: true; spacing: 6
                                    StyledText {
                                        text: String(modelData.source ?? "") === "git" ? "GIT" : "SNAP"
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        font.weight: Font.Bold
                                        color: historyRoot.settledColors?.colPrimary ?? Appearance.colors.colPrimary
                                    }
                                    StyledText {
                                        Layout.fillWidth: true; Layout.minimumWidth: 0
                                        text: String(modelData.displayTime ?? modelData.timestamp ?? "")
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: historyRoot.settledColors?.colSubtext ?? Appearance.colors.colSubtext
                                        elide: Text.ElideRight
                                    }
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: String(modelData.summary ?? "")
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: historyRoot.settledColors?.colOnLayer1 ?? Appearance.colors.colOnLayer1
                                    elide: Text.ElideRight
                                }
                            }
                            MouseArea {
                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: if (historyRoot.nexus && modelData.revId) historyRoot.nexus.diffNoteRevision(String(modelData.revId))
                            }
                        }
                    }
                }

                // Unified Diff Viewer
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 8
                    color: historyRoot.settledColors?.colLayer0 ?? Appearance.colors.colLayer0

                    ScrollView {
                        anchors.fill: parent; anchors.margins: 8
                        clip: true
                        TextArea {
                            readOnly: true
                            selectByMouse: true
                            wrapMode: TextEdit.NoWrap
                            text: String(historyRoot.nexus?.historyDiffText || (historyRoot.nexus?.historyLoading ? "Loading revision diff..." : "Select a snapshot or commit on the left to inspect diff."))
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: historyRoot.settledColors?.colOnLayer1 ?? Appearance.colors.colOnLayer1
                            background: Item {}
                        }
                    }
                }
            }
        }
    }
}
