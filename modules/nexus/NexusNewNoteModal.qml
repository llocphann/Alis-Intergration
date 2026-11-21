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
    id: nexusNewNoteApiModal
    objectName: "nexusNewNoteApiModal"
    required property var workspace
    readonly property var root: workspace
    readonly property var settledColors: workspace ? workspace.settledColors : null
    readonly property var searchInput: newNoteApiSearchInput
    anchors.fill: parent
    visible: Boolean(root?.nexus?.newNoteModalOpen ?? false)
    color: Qt.alpha(settledColors.colLayer0, 0.72)
    z: 760

    readonly property string activeKind: String(root.nexus?.newNoteModalKind ?? "standard")
    readonly property bool apiBacked: Boolean(root.nexus && root.nexus.isApiBackedKind(activeKind))
    property string openedCustomKind: ""
    readonly property var extraKindMetaMap: ({
        "exercise": { "id": "exercise", "label": "Exercise", "icon": "fitness_center" },
        "contact": { "id": "contact", "label": "Contact", "icon": "contacts" },
        "website": { "id": "website", "label": "Web-Site", "icon": "language" },
        "cornell": { "id": "cornell", "label": "Cornell", "icon": "school" },
        "zettelkasten": { "id": "zettelkasten", "label": "Zettelkasten", "icon": "psychology" },
        "finance": { "id": "finance", "label": "Finance", "icon": "account_balance_wallet" },
        "clipping": { "id": "clipping", "label": "Clipping", "icon": "bookmark" }
    })

    Timer {
        id: apiModalDebounce
        interval: 280
        repeat: false
        onTriggered: {
            if (root.nexus && nexusNewNoteApiModal.visible && nexusNewNoteApiModal.apiBacked) {
                root.nexus.searchExternalApi(nexusNewNoteApiModal.activeKind, newNoteApiSearchInput.text);
            }
        }
    }

    function _syncOnShow(): void {
        if (!visible)
            return;
        openedCustomKind = extraKindMetaMap[activeKind] ? activeKind : "";
        newNoteModalFolderInput.text = String(root?.nexus?.newNoteModalFolder ?? "");
        if (!newNoteApiSearchInput.text)
            newNoteApiSearchInput.text = "";
        newNoteApiSearchInput.forceActiveFocus();
    }

    Component.onCompleted: _syncOnShow()

    onVisibleChanged: {
        if (visible) {
            _syncOnShow();
        } else {
            openedCustomKind = "";
            apiModalDebounce.stop();
            newNoteApiSearchInput.text = "";
            newNoteApiSearchInput.focus = false;
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: {
            if (root.nexus)
                root.nexus.closeNewNoteModal();
        }
    }

    Rectangle {
        objectName: "nexusNewNoteApiModalCard"
        width: Math.min(parent.width - 48, 680)
        height: nexusNewNoteApiModal.apiBacked
            ? Math.min(parent.height - 64, 560)
            : Math.min(parent.height - 64, 300)
        anchors.centerIn: parent
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
            anchors.margins: 16
            spacing: 12

            // Title Header
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                MaterialSymbol {
                    text: nexusNewNoteApiModal.apiBacked ? "travel_explore" : "note_add"
                    iconSize: 18
                    color: settledColors.colPrimary
                }
                StyledText {
                    Layout.fillWidth: true
                    text: nexusNewNoteApiModal.apiBacked
                        ? "New Note · Search & Pick Metadata"
                        : "Create New Vault Note"
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.Bold
                    color: settledColors.colOnLayer1
                }
                Rectangle {
                    width: 26
                    height: 26
                    radius: 6
                    color: closeModalMouse.containsMouse ? settledColors.colLayer2Hover : settledColors.colLayer0
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "close"
                        iconSize: 14
                        color: settledColors.colSubtext
                    }
                    MouseArea {
                        id: closeModalMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (root.nexus)
                                root.nexus.closeNewNoteModal();
                        }
                    }
                }
            }

            // Kind Pills
            Flow {
                Layout.fillWidth: true
                spacing: 6

                Repeater {
                    model: {
                        const base = [
                            { "id": "standard", "label": "Standard Note", "icon": "description" },
                            { "id": "movie", "label": "Movie", "icon": "movie" },
                            { "id": "tv", "label": "TV Series", "icon": "live_tv" },
                            { "id": "book", "label": "Book", "icon": "menu_book" },
                            { "id": "game", "label": "Game", "icon": "sports_esports" },
                            { "id": "recipe", "label": "Recipe", "icon": "restaurant" },
                            { "id": "place", "label": "Place", "icon": "place" },
                            { "id": "journal", "label": "Daily Journal", "icon": "today" }
                        ];
                        const customKey = nexusNewNoteApiModal.extraKindMetaMap[nexusNewNoteApiModal.activeKind]
                            ? nexusNewNoteApiModal.activeKind
                            : nexusNewNoteApiModal.openedCustomKind;
                        if (customKey && nexusNewNoteApiModal.extraKindMetaMap[customKey])
                            base.push(nexusNewNoteApiModal.extraKindMetaMap[customKey]);
                        return base;
                    }
                    delegate: Rectangle {
                        required property var modelData
                        objectName: "nexusNewNoteKindPill_" + modelData.id
                        readonly property bool selected: nexusNewNoteApiModal.activeKind === modelData.id
                        implicitWidth: kindPillRow.implicitWidth + 16
                        implicitHeight: 28
                        radius: 7
                        color: selected
                            ? settledColors.colPrimary
                            : (kindPillMouse.containsMouse ? settledColors.colLayer2Hover : settledColors.colLayer0)
                        border.width: 1
                        border.color: selected ? settledColors.colPrimary : settledColors.colLayer0Border

                        RowLayout {
                            id: kindPillRow
                            anchors.centerIn: parent
                            spacing: 5
                            MaterialSymbol {
                                text: modelData.icon
                                iconSize: 14
                                color: selected ? settledColors.colOnPrimary : settledColors.colPrimary
                            }
                            StyledText {
                                text: modelData.label
                                font.pixelSize: Appearance.font.pixelSize.smallest + 1
                                font.weight: selected ? Font.Bold : Font.DemiBold
                                color: selected ? settledColors.colOnPrimary : settledColors.colOnLayer1
                            }
                        }

                        MouseArea {
                            id: kindPillMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (!root.nexus)
                                    return;
                                root.nexus.newNoteModalKind = modelData.id;
                                const inferred = root.nexus.inferFolderForKind(modelData.id);
                                root.nexus.newNoteModalFolder = inferred;
                                newNoteModalFolderInput.text = inferred;
                                root.nexus.searchApiResults = [];
                                if (root.nexus.isApiBackedKind(modelData.id) && newNoteApiSearchInput.text.trim().length >= 2) {
                                    apiModalDebounce.restart();
                                }
                                newNoteApiSearchInput.forceActiveFocus();
                            }
                        }
                    }
                }
            }

            // Target Folder Row
            RowLayout {
                visible: nexusNewNoteApiModal.activeKind !== "journal"
                Layout.fillWidth: true
                spacing: 8

                StyledText {
                    text: "FOLDER"
                    font.family: Appearance.font.family.monospace
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    color: settledColors.colSubtext
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 30
                    radius: 7
                    color: settledColors.colLayer0
                    border.width: 1
                    border.color: newNoteModalFolderInput.activeFocus ? settledColors.colPrimary : settledColors.colLayer0Border

                    TextField {
                        id: newNoteModalFolderInput
                        objectName: "nexusNewNoteModalFolderInput"
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        placeholderText: "Vault root (or e.g. 20_Personal_Life/25_Media_Tracker/Movies)"
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.smallest + 1
                        color: settledColors.colOnLayer1
                        background: null
                        Keys.onEscapePressed: event => {
                            if (inputMethodComposing) {
                                event.accepted = false;
                                return;
                            }
                            if (root.nexus)
                                root.nexus.closeNewNoteModal();
                            event.accepted = true;
                        }
                        Keys.onPressed: event => {
                            if (inputMethodComposing || event.key === 0 || event.key === Qt.Key_unknown) {
                                event.accepted = false;
                                return;
                            }
                        }
                    }
                }
            }

            // Title / Live API Search Input
            Rectangle {
                visible: nexusNewNoteApiModal.activeKind !== "journal"
                Layout.fillWidth: true
                Layout.preferredHeight: 38
                radius: 8
                color: settledColors.colLayer0
                border.width: 1
                border.color: newNoteApiSearchInput.activeFocus ? settledColors.colPrimary : settledColors.colLayer0Border

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 8

                    MaterialSymbol {
                        text: nexusNewNoteApiModal.apiBacked ? "search" : "edit"
                        iconSize: 16
                        color: settledColors.colPrimary
                    }

                    TextField {
                        id: newNoteApiSearchInput
                        objectName: "nexusNewNoteModalSearchInput"
                        Layout.fillWidth: true
                        placeholderText: nexusNewNoteApiModal.apiBacked
                            ? ("Search " + nexusNewNoteApiModal.activeKind.toUpperCase() + " title to auto-fetch metadata, or press Enter for manual note...")
                            : "Enter note title and press Enter..."
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: settledColors.colOnLayer1
                        background: null
                        onTextChanged: {
                            if (!nexusNewNoteApiModal.visible || !root.nexus || inputMethodComposing)
                                return;
                            if (nexusNewNoteApiModal.apiBacked) {
                                if (text.trim().length >= 2)
                                    apiModalDebounce.restart();
                                else {
                                    apiModalDebounce.stop();
                                    root.nexus.searchApiResults = [];
                                    root.nexus.searchApiLoading = false;
                                }
                            }
                        }
                        onAccepted: {
                            if (!root.nexus || inputMethodComposing)
                                return;
                            root.nexus.createManualModalNote(
                                nexusNewNoteApiModal.activeKind,
                                text.trim() || "Untitled",
                                newNoteModalFolderInput.text
                            );
                        }
                        Keys.onEscapePressed: event => {
                            if (inputMethodComposing) {
                                event.accepted = false;
                                return;
                            }
                            if (root.nexus)
                                root.nexus.closeNewNoteModal();
                            event.accepted = true;
                        }
                    }
                }
            }

            // Live Selectable API Results List
            Rectangle {
                visible: nexusNewNoteApiModal.apiBacked
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 10
                color: settledColors.colLayer0
                border.width: 1
                border.color: settledColors.colLayer0Border
                clip: true

                StyledText {
                    anchors.centerIn: parent
                    visible: !Boolean(root.nexus?.searchApiLoading) && (root.nexus?.searchApiResults ?? []).length === 0
                    text: newNoteApiSearchInput.text.trim().length < 2
                        ? "Type at least 2 characters to search live metadata (works keyless out-of-the-box)..."
                        : "No external matches found — click 'Create Manual Note' below to create offline."
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: settledColors.colSubtext
                }

                StyledText {
                    anchors.centerIn: parent
                    visible: Boolean(root.nexus?.searchApiLoading) && (root.nexus?.searchApiResults ?? []).length === 0
                    text: "Searching external metadata providers..."
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: settledColors.colPrimary
                }

                ListView {
                    id: newNoteModalResultsList
                    objectName: "nexusNewNoteModalResultsList"
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 6
                    clip: true
                    model: root.nexus?.searchApiResults ?? []

                    delegate: Rectangle {
                        id: candCard
                        required property var modelData
                        required property int index
                        objectName: "nexusApiCandidateCard_" + String(index)
                        width: ListView.view.width
                        height: 82
                        radius: 8
                        color: candMouse.containsMouse ? settledColors.colSecondaryContainer : settledColors.colLayer1
                        border.width: 1
                        border.color: candMouse.containsMouse ? settledColors.colPrimary : settledColors.colLayer0Border

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 10

                            Rectangle {
                                Layout.preferredWidth: 48
                                Layout.preferredHeight: 66
                                radius: 5
                                color: settledColors.colLayer2
                                clip: true

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    visible: String(candCard.modelData.cover ?? "").length === 0
                                    text: "image"
                                    iconSize: 18
                                    color: settledColors.colSubtext
                                }

                                Image {
                                    anchors.fill: parent
                                    visible: String(candCard.modelData.cover ?? "").length > 0
                                    source: String(candCard.modelData.cover ?? "")
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                spacing: 2

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: String(candCard.modelData.title ?? "")
                                            + (String(candCard.modelData.year ?? "").length > 0 ? (" (" + String(candCard.modelData.year) + ")") : "")
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        font.weight: Font.Bold
                                        color: settledColors.colOnLayer1
                                        elide: Text.ElideRight
                                    }

                                    Rectangle {
                                        visible: String(candCard.modelData.source ?? "").length > 0
                                        implicitWidth: srcBadgeTxt.implicitWidth + 10
                                        implicitHeight: 18
                                        radius: 4
                                        color: settledColors.colLayer2
                                        border.width: 1
                                        border.color: settledColors.colPrimary
                                        StyledText {
                                            id: srcBadgeTxt
                                            anchors.centerIn: parent
                                            text: String(candCard.modelData.source ?? "")
                                            font.family: Appearance.font.family.monospace
                                            font.pixelSize: 9
                                            font.weight: Font.Bold
                                            color: settledColors.colPrimary
                                        }
                                    }
                                }

                                StyledText {
                                    visible: String(candCard.modelData.creator || candCard.modelData.subtitle || "").length > 0
                                    Layout.fillWidth: true
                                    text: [String(candCard.modelData.creator ?? ""), String(candCard.modelData.subtitle ?? "")].filter(s => s.length > 0).join(" · ")
                                    font.pixelSize: Appearance.font.pixelSize.smallest + 1
                                    font.weight: Font.DemiBold
                                    color: settledColors.colPrimary
                                    elide: Text.ElideRight
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    text: String(candCard.modelData.overview ?? "")
                                    font.pixelSize: Appearance.font.pixelSize.smallest + 1
                                    color: settledColors.colSubtext
                                    wrapMode: Text.WordWrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        MouseArea {
                            id: candMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (root.nexus) {
                                    root.nexus.createNoteFromApiCandidate(
                                        nexusNewNoteApiModal.activeKind,
                                        candCard.modelData,
                                        newNoteModalFolderInput.text
                                    );
                                }
                            }
                        }
                    }
                }
            }

            // Bottom Action Bar
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                StyledText {
                    Layout.fillWidth: true
                    text: nexusNewNoteApiModal.activeKind === "journal"
                        ? ("Opens or creates today's Journal note in " + String(root.nexus?.dailyFolder ?? ""))
                        : nexusNewNoteApiModal.apiBacked
                            ? (Boolean(root.nexus?.searchApiLoading) ? "Fetching candidates..." : "Click any result card to populate frontmatter & sections automatically")
                            : "Enter note title and press Enter or click Create Note"
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: settledColors.colSubtext
                    elide: Text.ElideRight
                }

                Rectangle {
                    implicitWidth: 74
                    implicitHeight: 30
                    radius: 7
                    color: cancelModalBtnMouse.containsMouse ? settledColors.colLayer2Hover : settledColors.colLayer2
                    StyledText {
                        anchors.centerIn: parent
                        text: "Cancel"
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: settledColors.colSubtext
                    }
                    MouseArea {
                        id: cancelModalBtnMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (root.nexus)
                                root.nexus.closeNewNoteModal();
                        }
                    }
                }

                Rectangle {
                    objectName: "nexusCreateManualNoteButton"
                    implicitWidth: manualCreateLbl.implicitWidth + 22
                    implicitHeight: 30
                    radius: 7
                    color: settledColors.colPrimary
                    StyledText {
                        id: manualCreateLbl
                        anchors.centerIn: parent
                        text: nexusNewNoteApiModal.activeKind === "journal"
                            ? "Open Today's Journal"
                            : (nexusNewNoteApiModal.apiBacked ? "Create Blank / Manual Note" : "Create Note")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.Bold
                        color: settledColors.colOnPrimary
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (root.nexus) {
                                root.nexus.createManualModalNote(
                                    nexusNewNoteApiModal.activeKind,
                                    newNoteApiSearchInput.text.trim() || "Untitled",
                                    newNoteModalFolderInput.text
                                );
                            }
                        }
                    }
                }
            }
        }
    }
}
