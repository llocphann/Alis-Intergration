pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

FocusScope {
    id: root
    objectName: "alisFilesOverlayWorkspace"
    focus: true

    // Always-visible leaf focus target inside FocusScope so hiding promptField/pathField/filterField
    // never leaves FocusScope's scopedFocusItem pointing at an invisible TextField.
    Item {
        id: surfaceKeyTarget
        objectName: "alisFilesSurfaceKeyTarget"
        focus: true
    }

    property var files: null
    property bool embeddedSurface: false
    property bool bottomDocked: true
    property bool transitionSettled: true

    // Local UI modal / transient state
    property bool pathEditActive: false
    property bool filterBarOpen: false
    property bool sortMenuOpen: false
    property bool contextMenuOpen: false
    property real contextMenuX: 0
    property real contextMenuY: 0
    property var contextEntry: null
    property string promptMode: "" // "" | "mkdir" | "mkfile" | "create" | "rename" | "compress" | "confirmDelete" | "confirmEmptyTrash"
    property string promptTargetPath: ""
    property string promptInputText: ""
    property string compressFormat: "zip"
    property int focusIndex: -1
    property bool markMode: false
    property string _pendingVimKey: ""
    property bool railExpanded: true
    property bool placesExpanded: true
    property bool bookmarksExpanded: true
    property bool drivesExpanded: true
    property string activePropsTab: "general" // "general" | "permissions" | "checksums" | "details"
    property bool openWithPickerOpen: false
    property string verifyHashInput: ""
    property string focusedRegion: "primary" // "rail" | "primary" | "secondary" | "preview" | "properties"
    property string lastInspectorRegion: "preview"
    property int railFocusIndex: 0

    onPromptModeChanged: {
        if (root.promptMode.length === 0)
            root.focusPrimarySurface();
    }
    onPathEditActiveChanged: {
        if (!root.pathEditActive)
            root.focusPrimarySurface();
    }
    onFilterBarOpenChanged: {
        if (!root.filterBarOpen)
            root.focusPrimarySurface();
    }

    Connections {
        target: root.files
        function onRailOpenChanged(): void {
            if (root.files && !root.files.railOpen && root.focusedRegion === "rail")
                root.focusRegion(root.activeIsSecondary ? "secondary" : "primary");
        }
        function onInspectorOpenChanged(): void {
            if (root.files && !root.files.inspectorOpen && (root.focusedRegion === "preview" || root.focusedRegion === "properties"))
                root.focusRegion(root.activeIsSecondary ? "secondary" : "primary");
        }
        function onSplitOpenChanged(): void {
            if (root.files && !root.files.splitOpen && root.focusedRegion === "secondary")
                root.focusRegion("primary");
        }
    }

    Timer {
        id: propsLoadTimer
        interval: 60
        repeat: false
        onTriggered: root.refreshInspectorProperties()
    }
    readonly property var gridZoomSteps: [40, 56, 72, 96, 128, 176, 240]

    function closestGridStepIndex(px: int): int {
        let bestIdx = 2;
        let bestDiff = 9999;
        for (let i = 0; i < root.gridZoomSteps.length; ++i) {
            const diff = Math.abs(root.gridZoomSteps[i] - px);
            if (diff < bestDiff) {
                bestDiff = diff;
                bestIdx = i;
            }
        }
        return bestIdx;
    }

    component HeadToolButton: RippleButton {
        id: headBtn
        property string iconName: ""
        property int btnIconSize: 18
        implicitWidth: 32
        implicitHeight: 32
        buttonRadius: 9
        colBackground: "transparent"
        colBackgroundHover: Qt.alpha(Appearance.colors.colOnSurface, 0.09)
        colBackgroundToggled: Appearance.colors.colSecondaryContainer
        colBackgroundToggledHover: Qt.alpha(Appearance.colors.colSecondaryContainer, 0.86)
        colRipple: Qt.alpha(Appearance.colors.colOnSurface, 0.14)
        colRippleToggled: Qt.alpha(Appearance.colors.colOnSecondaryContainer, 0.16)
        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            text: headBtn.iconName
            iconSize: headBtn.btnIconSize
            color: headBtn.toggled
                ? Appearance.colors.colOnSecondaryContainer
                : (headBtn.buttonHovered ? Appearance.colors.colOnSurface : Appearance.colors.colOnSurfaceVariant)
            opacity: headBtn.enabled ? 1.0 : 0.35
        }
    }

    component AlisFileArt: Item {
        id: art
        property var entry: null
        property int artSize: 72
        property string kindIcon: "draft"

        readonly property bool isBroken: Boolean(art.entry?.is_broken_symlink)
        readonly property bool isDir: !art.isBroken && Boolean(art.entry ? art.entry.is_dir : true)
        readonly property string entryName: String(art.entry?.name ?? "")
        readonly property string entryPath: String(art.entry?.path ?? "")
        readonly property string roleIcon: {
            if (!art.isDir) return "";
            const n = art.entryName;
            const p = art.entryPath;
            if (p.endsWith("/.local/share/Trash/files")) return "delete";
            if (n === "Home" || p === String(Quickshell.env("HOME") || "")) return "home";
            if (n === "Downloads") return "download";
            if (n === "Documents") return "description";
            if (n === "Pictures") return "photo_library";
            if (n === "Music") return "library_music";
            if (n === "Videos") return "video_library";
            return "";
        }
        readonly property string shortExt: {
            if (art.isDir || art.isBroken) return "";
            const dot = art.entryName.lastIndexOf(".");
            if (dot <= 0 || dot >= art.entryName.length - 1) return "";
            const ext = art.entryName.slice(dot + 1).toUpperCase();
            return ext.length <= 5 ? ext : "";
        }

        implicitWidth: art.artSize
        implicitHeight: art.artSize

        MaterialSymbol {
            anchors.centerIn: parent
            visible: art.isBroken
            text: "link_off"
            textRenderType: Text.CurveRendering
            iconSize: Math.max(20, Math.round(art.artSize * 0.56))
            color: Appearance.colors.colError
        }

        // Layered vector Folder matching inir-files / Window mode file_art.rs
        Item {
            anchors.fill: parent
            visible: art.isDir && !art.isBroken

            Rectangle {
                x: Math.round(art.artSize * 0.06)
                y: Math.round(art.artSize * 0.13)
                width: Math.round(art.artSize * 0.40)
                height: Math.round(art.artSize * 0.18)
                radius: Math.max(3, Math.round(art.artSize * 0.07))
                color: Qt.darker(Appearance.colors.colPrimary, 1.38)
                antialiasing: true
            }
            Rectangle {
                x: Math.round(art.artSize * 0.06)
                y: Math.round(art.artSize * 0.20)
                width: Math.round(art.artSize * 0.88)
                height: Math.round(art.artSize * 0.67)
                radius: Math.max(4, Math.round(art.artSize * 0.11))
                color: Qt.darker(Appearance.colors.colPrimary, 1.38)
                antialiasing: true
            }
            Rectangle {
                visible: art.artSize >= 26
                x: Math.round(art.artSize * 0.13)
                y: Math.round(art.artSize * 0.22)
                width: Math.round(art.artSize * 0.74)
                height: Math.round(art.artSize * 0.34)
                radius: Math.max(2, Math.round(art.artSize * 0.06))
                rotation: -2.6
                color: Qt.alpha(Appearance.colors.colOnSurface, 0.24)
                antialiasing: true
            }
            Rectangle {
                x: Math.round(art.artSize * 0.06)
                y: Math.round(art.artSize * 0.31)
                width: Math.round(art.artSize * 0.88)
                height: Math.round(art.artSize * 0.56)
                radius: Math.max(3, Math.round(art.artSize * 0.11))
                color: Appearance.colors.colPrimary
                antialiasing: true
                clip: true

                Rectangle {
                    visible: art.artSize >= 26
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 1
                    color: Qt.rgba(1, 1, 1, 0.28)
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    visible: art.roleIcon.length > 0 && art.artSize >= 40
                    text: art.roleIcon
                    textRenderType: Text.CurveRendering
                    iconSize: Math.max(16, Math.round(art.artSize * 0.28))
                    color: Appearance.colors.colOnPrimary
                    opacity: 0.82
                }
            }
        }

        // Vector File page + kind symbol + extension badge matching file_art.rs
        Item {
            anchors.fill: parent
            visible: !art.isDir && !art.isBroken

            Rectangle {
                anchors.centerIn: parent
                width: Math.round(art.artSize * 0.72)
                height: Math.round(art.artSize * 0.88)
                radius: Math.max(3, Math.round(art.artSize * 0.09))
                color: Appearance.colors.colLayer3
                border.width: 1
                border.color: Qt.alpha(Appearance.colors.colOutlineVariant, 0.45)
                antialiasing: true

                MaterialSymbol {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: art.shortExt.length > 0 && art.artSize >= 48 ? -Math.round(art.artSize * 0.06) : 0
                    text: art.kindIcon
                    textRenderType: Text.CurveRendering
                    iconSize: Math.max(11, Math.round(art.artSize * (art.artSize >= 26 ? 0.34 : 0.46)))
                    color: Appearance.colors.colPrimary
                }
            }

            Rectangle {
                visible: art.artSize >= 48 && art.shortExt.length > 0
                x: Math.round(art.artSize * 0.10)
                y: Math.round(art.artSize * 0.65)
                width: extLbl.implicitWidth + Math.max(8, Math.round(art.artSize * 0.12))
                height: Math.max(14, Math.round(art.artSize * 0.18))
                radius: Math.max(3, Math.round(height * 0.34))
                color: Appearance.colors.colSecondaryContainer
                antialiasing: true

                StyledText {
                    id: extLbl
                    anchors.centerIn: parent
                    text: art.shortExt
                    font.pixelSize: Math.max(8, Math.round(art.artSize * 0.105))
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }
        }
    }

    component OverlayFilePane: Item {
        id: paneRoot
        property var files: null
        property bool isSecondary: false
        property bool isActivePane: true
        property bool isFocusedPane: true
        property bool splitOpen: false
        property string viewMode: "grid"
        property int gridIconSize: 72
        property int listZoom: 1
        property var entriesList: []
        property var selectedList: []
        property var gitBadgesMap: ({})
        property var thumbMap: ({})
        property bool thumbnailsEnabled: true
        property var clipboardPaths: []
        property string clipboardOp: ""
        property string sortField: "name"
        property string sortOrder: "asc"
        property string filterText: ""
        property string errorMessage: ""
        property var iconForEntryFn: null
        property int focusIdx: -1

        signal paneFocused()
        signal selectionRequested(int idx, bool toggle, bool range)
        signal itemActivated(var entry)
        signal contextRequested(var entry, Item sourceItem, real localX, real localY)
        signal clearSelectionRequested()
        signal sortRequested(string field)

        readonly property bool showKindCol: paneRoot.width >= 470
        readonly property bool showModCol: paneRoot.width >= 350
        readonly property bool showSizeCol: paneRoot.width >= 250

        function ensureIndexVisible(idx: int): void {
            if (idx < 0 || idx >= paneRoot.entriesList.length)
                return;
            if (paneRoot.viewMode === "list")
                paneListView.positionViewAtIndex(idx, ListView.Contain);
            else
                paneGridView.positionViewAtIndex(idx, GridView.Contain);
        }

        readonly property var _selectedSet: {
            const set = Object.create(null);
            const list = paneRoot.selectedList ?? [];
            for (let i = 0; i < list.length; ++i)
                set[String(list[i])] = true;
            return set;
        }
        readonly property var _cutSet: {
            if (paneRoot.clipboardOp !== "cut")
                return null;
            const set = Object.create(null);
            const list = paneRoot.clipboardPaths ?? [];
            for (let i = 0; i < list.length; ++i)
                set[String(list[i])] = true;
            return set;
        }

        function isSelected(path: string): bool {
            return Boolean(paneRoot._selectedSet[path]);
        }

        function isCut(path: string): bool {
            return Boolean(paneRoot._cutSet && paneRoot._cutSet[path]);
        }

        clip: true

        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            z: 20
            visible: paneRoot.splitOpen
            color: paneRoot.isFocusedPane
                ? Qt.alpha(Appearance.colors.colOnSurface, 0.18)
                : (paneRoot.isActivePane
                    ? Qt.alpha(Appearance.colors.colOnSurface, 0.09)
                    : Qt.alpha(Appearance.colors.colOutlineVariant, 0.18))
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.topMargin: paneRoot.splitOpen ? 2 : 0
            spacing: 0
            opacity: (!paneRoot.splitOpen || paneRoot.isActivePane) ? 1.0 : 0.88

            // Responsive List column header
            Rectangle {
                visible: paneRoot.viewMode === "list" && paneRoot.entriesList.length > 0
                Layout.fillWidth: true
                height: 28
                color: "transparent"
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    spacing: 10
                    Item {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 80
                        Layout.fillHeight: true
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Name" + (paneRoot.sortField === "name" ? (paneRoot.sortOrder === "asc" ? " ▲" : " ▼") : "")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colSubtext
                        }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: paneRoot.sortRequested("name") }
                    }
                    Item {
                        visible: paneRoot.showModCol
                        Layout.preferredWidth: 142
                        Layout.fillHeight: true
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Modified" + (paneRoot.sortField === "modified" ? (paneRoot.sortOrder === "asc" ? " ▲" : " ▼") : "")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colSubtext
                        }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: paneRoot.sortRequested("modified") }
                    }
                    Item {
                        visible: paneRoot.showSizeCol
                        Layout.preferredWidth: 86
                        Layout.fillHeight: true
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Size" + (paneRoot.sortField === "size" ? (paneRoot.sortOrder === "asc" ? " ▲" : " ▼") : "")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colSubtext
                        }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: paneRoot.sortRequested("size") }
                    }
                    Item {
                        visible: paneRoot.showKindCol
                        Layout.preferredWidth: 112
                        Layout.fillHeight: true
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Kind" + (paneRoot.sortField === "kind" ? (paneRoot.sortOrder === "asc" ? " ▲" : " ▼") : "")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colSubtext
                        }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: paneRoot.sortRequested("kind") }
                    }
                }
            }

            // Content Viewport (Grid/Gallery | List | Empty)
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                MouseArea {
                    id: bgMouse
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: mouse => {
                        paneRoot.paneFocused();
                        if (mouse.button === Qt.RightButton)
                            paneRoot.contextRequested(null, bgMouse, mouse.x, mouse.y);
                        else
                            paneRoot.clearSelectionRequested();
                    }
                }

                // Grid / Gallery View
                GridView {
                    id: paneGridView
                    visible: paneRoot.viewMode !== "list" && paneRoot.entriesList.length > 0
                    anchors.fill: parent
                    anchors.margins: 10
                    clip: true
                    readonly property bool isGallery: paneRoot.viewMode === "gallery"
                    readonly property int iconPx: paneRoot.gridIconSize
                    cellWidth: isGallery ? Math.min(260, iconPx + 48) : (iconPx + 44)
                    cellHeight: isGallery ? Math.min(260, iconPx + 48) : (iconPx + 66)
                    cacheBuffer: 240
                    model: visible ? paneRoot.entriesList : []

                    delegate: Item {
                        id: gridTile
                        required property int index
                        required property var modelData
                        readonly property string itemPath: String(modelData.path ?? "")
                        readonly property bool sel: paneRoot.isSelected(itemPath)
                        readonly property bool isCursor: paneRoot.isFocusedPane && gridTile.index === paneRoot.focusIdx
                        readonly property string thumbPath: String(paneRoot.thumbMap?.[itemPath] ?? "")
                        readonly property var gitBadge: paneRoot.gitBadgesMap?.[itemPath] ?? null
                        width: paneGridView.cellWidth - 6
                        height: paneGridView.cellHeight - 6
                        opacity: paneRoot.isCut(itemPath) ? 0.48 : (modelData.is_hidden ? 0.65 : 1.0)

                        Component.onCompleted: {
                            if (paneRoot.files && paneRoot.thumbnailsEnabled) {
                                const k = String(modelData.kind ?? "");
                                if (k === "Image" || k === "Pdf" || k === "Video")
                                    paneRoot.files.requestThumb(itemPath, k);
                            }
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 4

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                radius: 12
                                color: gridTile.sel
                                    ? Appearance.colors.colSecondaryContainer
                                    : ((gridHover.containsMouse || gridTile.isCursor) ? Qt.alpha(Appearance.colors.colLayer2, 0.85) : Qt.alpha(Appearance.colors.colLayer2, paneGridView.isGallery ? 0.5 : 0.25))
                                clip: true

                                Image {
                                    anchors.fill: parent
                                    anchors.margins: paneGridView.isGallery ? 0 : 6
                                    visible: gridTile.thumbPath.length > 0
                                    source: gridTile.thumbPath.length > 0 ? ("file://" + gridTile.thumbPath) : ""
                                    sourceSize.width: Math.max(128, Math.round(paneGridView.iconPx * 2))
                                    sourceSize.height: Math.max(128, Math.round(paneGridView.iconPx * 2))
                                    fillMode: paneGridView.isGallery ? Image.PreserveAspectCrop : Image.PreserveAspectFit
                                    asynchronous: true
                                    cache: false
                                }

                                AlisFileArt {
                                    anchors.centerIn: parent
                                    visible: gridTile.thumbPath.length === 0
                                    entry: gridTile.modelData
                                    artSize: Math.max(36, Math.round(paneGridView.iconPx * 0.82))
                                    kindIcon: paneRoot.iconForEntryFn ? paneRoot.iconForEntryFn(gridTile.modelData) : "draft"
                                }

                                Rectangle {
                                    visible: gridTile.gitBadge !== null
                                    anchors.top: parent.top
                                    anchors.right: parent.right
                                    anchors.margins: 5
                                    width: 18; height: 18; radius: 5
                                    color: {
                                        const k = String(gridTile.gitBadge?.kind ?? "");
                                        if (k === "deleted" || k === "conflict") return Appearance.colors.colError;
                                        if (k === "added" || k === "untracked") return Appearance.colors.colPrimary;
                                        return Appearance.colors.colSecondary;
                                    }
                                    StyledText {
                                        anchors.centerIn: parent
                                        text: String(gridTile.gitBadge?.short ?? "")
                                        font.pixelSize: 10
                                        font.weight: Font.Bold
                                        color: Appearance.colors.colOnPrimary
                                    }
                                }
                            }

                            Rectangle {
                                visible: !paneGridView.isGallery
                                Layout.fillWidth: true
                                height: 22
                                radius: 7
                                color: gridTile.sel ? Appearance.colors.colSecondaryContainer : "transparent"
                                StyledText {
                                    anchors.fill: parent
                                    anchors.leftMargin: 4
                                    anchors.rightMargin: 4
                                    text: String(gridTile.modelData.name ?? "")
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    elide: Text.ElideMiddle
                                    color: gridTile.sel ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurface
                                }
                            }
                        }

                        MouseArea {
                            id: gridHover
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: mouse => {
                                paneRoot.paneFocused();
                                if (mouse.button === Qt.RightButton)
                                    paneRoot.contextRequested(gridTile.modelData, gridTile, mouse.x, mouse.y);
                                else
                                    paneRoot.selectionRequested(gridTile.index, Boolean(mouse.modifiers & Qt.ControlModifier), Boolean(mouse.modifiers & Qt.ShiftModifier));
                            }
                            onDoubleClicked: paneRoot.itemActivated(gridTile.modelData)
                        }
                    }
                }

                // Virtualized List View
                ListView {
                    id: paneListView
                    visible: paneRoot.viewMode === "list" && paneRoot.entriesList.length > 0
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    clip: true
                    spacing: 2
                    cacheBuffer: 240
                    model: visible ? paneRoot.entriesList : []

                    delegate: Rectangle {
                        id: listRow
                        required property int index
                        required property var modelData
                        readonly property string itemPath: String(modelData.path ?? "")
                        readonly property bool sel: paneRoot.isSelected(itemPath)
                        readonly property bool isCursor: paneRoot.isFocusedPane && listRow.index === paneRoot.focusIdx
                        readonly property var gitBadge: paneRoot.gitBadgesMap?.[itemPath] ?? null
                        readonly property int lz: paneRoot.listZoom
                        width: paneListView.width
                        height: lz === 0 ? 28 : (lz === 2 ? 42 : 34)
                        radius: 9
                        color: sel
                            ? Appearance.colors.colSecondaryContainer
                            : ((rowHover.containsMouse || listRow.isCursor) ? Qt.alpha(Appearance.colors.colLayer2, 0.75) : "transparent")
                        opacity: paneRoot.isCut(itemPath) ? 0.48 : (modelData.is_hidden ? 0.65 : 1.0)

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 10

                            AlisFileArt {
                                entry: listRow.modelData
                                artSize: listRow.lz === 0 ? 16 : (listRow.lz === 2 ? 22 : 18)
                                kindIcon: paneRoot.iconForEntryFn ? paneRoot.iconForEntryFn(listRow.modelData) : "draft"
                            }
                            StyledText {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                text: String(listRow.modelData.name ?? "")
                                font.pixelSize: Appearance.font.pixelSize.small
                                elide: Text.ElideMiddle
                                color: listRow.sel ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurface
                            }
                            Rectangle {
                                visible: listRow.gitBadge !== null
                                width: 20; height: 18; radius: 5
                                color: Appearance.colors.colPrimary
                                StyledText {
                                    anchors.centerIn: parent
                                    text: String(listRow.gitBadge?.short ?? "")
                                    font.pixelSize: 10
                                    font.weight: Font.Bold
                                    color: Appearance.colors.colOnPrimary
                                }
                            }
                            StyledText {
                                visible: paneRoot.showModCol
                                Layout.preferredWidth: 142
                                text: String(listRow.modelData.modified_label ?? "—")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                            }
                            StyledText {
                                visible: paneRoot.showSizeCol
                                Layout.preferredWidth: 86
                                horizontalAlignment: Text.AlignRight
                                text: String(listRow.modelData.size_label ?? "—")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                            }
                            StyledText {
                                visible: paneRoot.showKindCol
                                Layout.preferredWidth: 112
                                text: String(listRow.modelData.kind_label ?? "File")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                                elide: Text.ElideRight
                            }
                        }

                        MouseArea {
                            id: rowHover
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: mouse => {
                                paneRoot.paneFocused();
                                if (mouse.button === Qt.RightButton)
                                    paneRoot.contextRequested(listRow.modelData, listRow, mouse.x, mouse.y);
                                else
                                    paneRoot.selectionRequested(listRow.index, Boolean(mouse.modifiers & Qt.ControlModifier), Boolean(mouse.modifiers & Qt.ShiftModifier));
                            }
                            onDoubleClicked: paneRoot.itemActivated(listRow.modelData)
                        }
                    }
                }

                // Empty Folder / Loading Placeholder
                ColumnLayout {
                    visible: paneRoot.entriesList.length === 0
                    anchors.centerIn: parent
                    spacing: 8
                    MaterialSymbol {
                        Layout.alignment: Qt.AlignHCenter
                        text: paneRoot.errorMessage.length > 0 ? "error" : "folder_open"
                        iconSize: 42
                        color: Appearance.colors.colSubtext
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: paneRoot.errorMessage.length > 0
                            ? paneRoot.errorMessage
                            : (paneRoot.filterText.length > 0 ? Translation.tr("No matching items") : Translation.tr("This folder is empty"))
                        color: Appearance.colors.colSubtext
                    }
                }
            }
        }
    }

    readonly property real paneExpansionScale: {
        const leftOpen = root.files?.railOpen ?? true;
        const rightOpen = root.files?.inspectorOpen ?? false;
        const left = Math.max(156, Math.min(460, root.files?.railWidth ?? 228));
        const right = Math.max(200, Math.min(560, root.files?.inspectorWidth ?? 296));
        const minimum = (leftOpen ? 156 : 0) + (rightOpen ? 200 : 0);
        const expansion = (leftOpen ? left - 156 : 0) + (rightOpen ? right - 200 : 0);
        const available = Math.max(minimum, root.width - 360);
        return expansion > 0 ? Math.max(0, Math.min(1, (available - minimum) / expansion)) : 1;
    }
    readonly property int railTargetWidth: Math.round(156 + (Math.max(156, Math.min(460, root.files?.railWidth ?? 228)) - 156) * root.paneExpansionScale)
    readonly property int inspectorTargetWidth: Math.round(200 + (Math.max(200, Math.min(560, root.files?.inspectorWidth ?? 296)) - 200) * root.paneExpansionScale)

    readonly property bool activeIsSecondary: root.files?.activeIsSecondary ?? false
    onActiveIsSecondaryChanged: root.markMode = false
    readonly property string activePath: String(root.files?.activePath ?? "")
    onActivePathChanged: {
        root.markMode = false;
        root.focusIndex = -1;
    }
    readonly property var entries: root.files?.activeEntries ?? []
    readonly property var selectedPaths: root.files?.activeSelectedPaths ?? []
    readonly property var cursorEntry: (root.focusIndex >= 0 && root.focusIndex < root.entries.length)
        ? root.entries[root.focusIndex]
        : null
    readonly property var activeEntry: {
        if (root.selectedPaths.length === 1) {
            const target = root.selectedPaths[0];
            for (const e of root.entries) {
                if (String(e.path) === target)
                    return e;
            }
        } else if (root.selectedPaths.length === 0) {
            return root.cursorEntry;
        }
        return null;
    }

    function actionPaths(): var {
        if (root.selectedPaths.length > 0)
            return root.selectedPaths;
        return root.cursorEntry ? [String(root.cursorEntry.path)] : [];
    }

    function ensureActiveIndexVisible(idx: int): void {
        (root.activeIsSecondary ? secondaryPane : primaryPane).ensureIndexVisible(idx);
    }
    component MenuActionRow: RippleButton {
        id: menuRowBtn
        property string labelText: ""
        property color textColor: Appearance.colors.colOnSurface
        Layout.fillWidth: true
        implicitHeight: 30
        buttonRadius: 8
        colBackground: "transparent"
        colBackgroundHover: Appearance.colors.colLayer1Hover
        contentItem: StyledText {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 8
            width: parent.width - 14
            elide: Text.ElideRight
            text: menuRowBtn.labelText
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: menuRowBtn.textColor
        }
    }

    component PropsRow: RowLayout {
        id: prRow
        property string labelText: ""
        property string valueText: ""
        property bool copyable: false
        property string copyValue: ""
        property var filesRef: null
        Layout.fillWidth: true
        spacing: 6
        StyledText {
            Layout.preferredWidth: 58
            Layout.alignment: Qt.AlignTop
            text: prRow.labelText
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            elide: Text.ElideRight
        }
        StyledText {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            wrapMode: Text.WrapAnywhere
            text: prRow.valueText
            font.pixelSize: Appearance.font.pixelSize.smaller
        }
        HeadToolButton {
            visible: prRow.copyable && prRow.copyValue.length > 0
            implicitWidth: 22
            implicitHeight: 22
            buttonRadius: 6
            iconName: "content_copy"
            btnIconSize: 13
            StyledToolTip { text: Translation.tr("Copy path") }
            onClicked: {
                Quickshell.clipboardText = prRow.copyValue;
                if (prRow.filesRef) prRow.filesRef.showToast("Copied path", false);
            }
        }
    }

    readonly property var inspectEntry: root.activeEntry ?? (root.selectedPaths.length === 0 ? (root.files?.activeDirEntry ?? null) : null)
    readonly property string inspectPath: root.selectedPaths.length <= 1 && root.inspectEntry ? String(root.inspectEntry.path ?? "") : ""
    readonly property var liveProps: (root.files && root.inspectPath.length > 0 && root.files.propsTargetPath === root.inspectPath) ? root.files.propsData : null

    onInspectPathChanged: propsLoadTimer.restart()

    function refreshInspectorProperties(): void {
        if (!root.files || !(root.files.inspectorOpen ?? false))
            return;
        root.openWithPickerOpen = false;
        root.verifyHashInput = "";
        if (root.inspectPath.length === 0) {
            root.files.loadProperties("", "");
            return;
        }
        const gb = root.files.activeGitBadges?.[root.inspectPath] ?? null;
        root.files.loadProperties(root.inspectPath, String(gb?.desc ?? ""));
    }

    function openPropertiesForSelection(): void {
        if (!root.files) return;
        root.contextMenuOpen = false;
        root.activePropsTab = "general";
        if (!(root.files.inspectorOpen ?? false))
            root.files.setInspectorOpen(true);
        root.refreshInspectorProperties();
        root.focusPrimarySurface();
    }

    function isSelected(path: string): bool {
        return root.selectedPaths.includes(path);
    }

    function isCut(path: string): bool {
        return root.files?.clipboardOp === "cut"
            && (root.files?.clipboardPaths ?? []).includes(path);
    }

    function setActiveSelectedPaths(paths: var): void {
        if (root.files)
            root.files.setPaneSelectedPaths(root.activeIsSecondary, paths);
    }

    function selectPaneIndex(isSecondary: bool, idx: int, toggle: bool, range: bool): void {
        if (!root.files)
            return;
        if (root.files.activeIsSecondary !== isSecondary)
            root.files.setActivePane(isSecondary);
        root.selectIndex(idx, toggle, range);
    }

    function selectIndex(idx: int, toggle: bool, range: bool): void {
        if (!root.files || root.entries.length === 0)
            return;
        const clamped = Math.max(0, Math.min(root.entries.length - 1, idx));
        const item = root.entries[clamped];
        if (!item) return;
        const p = String(item.path);
        if (range && root.focusIndex >= 0 && root.focusIndex < root.entries.length) {
            root.markMode = false;
            const lo = Math.min(root.focusIndex, clamped);
            const hi = Math.max(root.focusIndex, clamped);
            const next = [];
            for (let i = lo; i <= hi; ++i)
                next.push(String(root.entries[i].path));
            root.setActiveSelectedPaths(next);
        } else if (toggle) {
            const cur = root.selectedPaths.slice();
            const existing = cur.indexOf(p);
            if (existing >= 0) cur.splice(existing, 1);
            else cur.push(p);
            root.setActiveSelectedPaths(cur);
            root.markMode = cur.length > 0;
        } else {
            root.markMode = false;
            root.setActiveSelectedPaths([p]);
        }
        root.focusIndex = clamped;
        root.ensureActiveIndexVisible(clamped);
    }

    function toggleSelectAndAdvance(): void {
        if (!root.files || root.entries.length === 0)
            return;
        const curIdx = (root.focusIndex >= 0 && root.focusIndex < root.entries.length) ? root.focusIndex : 0;
        const item = root.entries[curIdx];
        if (!item) return;
        const p = String(item.path);
        const cur = root.selectedPaths.slice();
        const existing = cur.indexOf(p);
        const implicitCursorOnly = !root.markMode && existing >= 0 && cur.length === 1;
        if (!implicitCursorOnly) {
            if (existing >= 0) cur.splice(existing, 1);
            else cur.push(p);
        }
        root.setActiveSelectedPaths(cur);
        root.markMode = cur.length > 0;
        const nextIdx = Math.min(root.entries.length - 1, curIdx + 1);
        root.focusIndex = nextIdx;
        root.ensureActiveIndexVisible(nextIdx);
    }

    function moveCursor(delta: int): void {
        if (!root.files || root.entries.length === 0)
            return;
        const curIdx = root.focusIndex >= 0 ? root.focusIndex : (delta > 0 ? -1 : 1);
        const nextIdx = Math.max(0, Math.min(root.entries.length - 1, curIdx + delta));
        if (root.markMode) {
            root.focusIndex = nextIdx;
            root.ensureActiveIndexVisible(nextIdx);
        } else {
            root.selectIndex(nextIdx, false, false);
        }
    }

    function jumpCursor(idx: int): void {
        if (!root.files || root.entries.length === 0)
            return;
        const clamped = Math.max(0, Math.min(root.entries.length - 1, idx));
        if (root.markMode) {
            root.focusIndex = clamped;
            root.ensureActiveIndexVisible(clamped);
        } else {
            root.selectIndex(clamped, false, false);
        }
    }

    function gotoPreset(kind: string): void {
        if (!root.files)
            return;
        const home = String(root.files.homePath || "/");
        const cfg = String(root.files.configHomePath || (home + "/.config"));
        const trash = String(root.files.trashPath || (home + "/.local/share/Trash/files"));
        let dest = "";
        if (kind === "home") dest = home;
        else if (kind === "config") dest = cfg;
        else if (kind === "downloads") dest = home + "/Downloads";
        else if (kind === "documents") dest = home + "/Documents";
        else if (kind === "desktop") dest = home + "/Desktop";
        else if (kind === "pictures") dest = home + "/Pictures";
        else if (kind === "videos") dest = home + "/Videos";
        else if (kind === "music") dest = home + "/Music";
        else if (kind === "trash") dest = trash;
        else if (kind === "root") dest = "/";
        if (dest.length === 0)
            return;
        if (root.focusedRegion === "rail" || root.focusedRegion === "preview" || root.focusedRegion === "properties")
            root.focusRegion(root.activeIsSecondary ? "secondary" : "primary");
        root.files.navigate(dest);
    }

    function activateItem(entry): void {
        if (!entry || !root.files) return;
        if (entry.is_broken_symlink) {
            root.files.showToast("Broken symbolic link: " + entry.name, false);
            return;
        }
        if (entry.is_dir)
            root.files.navigate(String(entry.path));
        else
            root.files.openExternal(String(entry.path));
    }

    function openContextFor(entry, sceneX: real, sceneY: real): void {
        if (!root.files) return;
        if (entry && !root.isSelected(String(entry.path))) {
            root.setActiveSelectedPaths([String(entry.path)]);
        }
        root.contextEntry = entry;
        root.contextMenuX = Math.max(8, Math.min(root.width - 244, sceneX));
        root.contextMenuY = Math.max(8, Math.min(root.height - 320, sceneY));
        root.contextMenuOpen = true;
    }

    function beginPrompt(mode: string, targetPath: string, initialText: string): void {
        root.contextMenuOpen = false;
        root.sortMenuOpen = false;
        root.promptMode = mode;
        root.promptTargetPath = targetPath;
        root.promptInputText = initialText;
        Qt.callLater(() => {
            if (promptField.visible) {
                promptField.forceActiveFocus();
                if (mode === "rename") {
                    const dot = initialText.lastIndexOf(".");
                    if (dot > 0 && !(root.activeEntry?.is_dir ?? false))
                        promptField.select(0, dot);
                    else
                        promptField.selectAll();
                } else {
                    promptField.selectAll();
                }
            }
        });
    }

    function submitPrompt(): void {
        if (!root.files) return;
        const mode = root.promptMode;
        const val = root.promptInputText.trim();
        const target = root.promptTargetPath;
        root.promptMode = "";
        if (mode === "confirmDelete") {
            root.files.deletePaths(root.actionPaths());
        } else if (mode === "confirmEmptyTrash") {
            root.files.emptyTrash();
        } else if (mode === "mkdir" && val.length > 0) {
            root.files.createFolder(val);
        } else if (mode === "mkfile" && val.length > 0) {
            root.files.createFile(val);
        } else if (mode === "create" && val.length > 0) {
            root.files.createEntry(val);
        } else if (mode === "rename" && val.length > 0 && target.length > 0) {
            root.files.renamePath(target, val);
        } else if (mode === "compress" && val.length > 0) {
            root.files.compressPaths(root.actionPaths(), val, root.compressFormat);
        }
        root.focusPrimarySurface();
    }

    function iconForEntry(entry): string {
        if (!entry) return "draft";
        if (entry.is_broken_symlink) return "link_off";
        if (entry.is_dir) {
            const n = String(entry.name ?? "");
            if (n === "Downloads") return "download";
            if (n === "Documents") return "description";
            if (n === "Pictures") return "photo_library";
            if (n === "Music") return "library_music";
            if (n === "Videos") return "video_library";
            return "folder";
        }
        const k = String(entry.kind ?? "");
        if (k === "Image") return "image";
        if (k === "Audio") return "audio_file";
        if (k === "Video") return "movie";
        if (k === "Pdf") return "picture_as_pdf";
        if (k === "Archive") return "folder_zip";
        if (k === "Markdown" || k === "Document") return "article";
        if (k === "Code") return "code";
        if (k === "Executable") return "terminal";
        return "draft";
    }

    function breadcrumbSegments(): var {
        const cur = root.activePath;
        const home = String(root.files?.homePath ?? "");
        const trash = String(root.files?.trashPath ?? "");
        if (cur === trash)
            return [{ label: "Trash", path: trash }];
        const segs = [];
        if (home.length > 0 && (cur === home || cur.startsWith(home + "/"))) {
            segs.push({ label: "Home", path: home });
            const rel = cur.slice(home.length).split("/").filter(Boolean);
            let acc = home;
            for (const part of rel) {
                acc += "/" + part;
                segs.push({ label: part, path: acc });
            }
            return segs;
        }
        segs.push({ label: "Computer", path: "/" });
        let acc = "";
        for (const part of cur.split("/").filter(Boolean)) {
            acc += "/" + part;
            segs.push({ label: part, path: acc });
        }
        return segs;
    }

    function focusPrimarySurface(): void {
        if (root.promptMode.length > 0 && promptField.visible) {
            promptField.forceActiveFocus();
        } else if (root.pathEditActive && pathField.visible) {
            pathField.forceActiveFocus();
        } else if (root.filterBarOpen && filterField.visible) {
            filterField.forceActiveFocus();
        } else {
            promptField.focus = false;
            pathField.focus = false;
            filterField.focus = false;
            verifyHashField.focus = false;
            quickLookTextArea.focus = false;
            surfaceKeyTarget.forceActiveFocus();
        }
    }

    function focusRegion(region: string): void {
        if (!root.files)
            return;
        let next = region;
        if (next === "rail" && !(root.files.railOpen ?? true))
            next = "primary";
        if (next === "secondary" && !(root.files.splitOpen ?? false))
            next = "primary";
        if ((next === "preview" || next === "properties") && !(root.files.inspectorOpen ?? false))
            next = (root.files.splitOpen && root.files.activeIsSecondary) ? "secondary" : "primary";

        root.focusedRegion = next;
        if (next === "preview" || next === "properties")
            root.lastInspectorRegion = next;
        if (next === "primary")
            root.files.setActivePane(false);
        else if (next === "secondary")
            root.files.setActivePane(true);
        root.focusPrimarySurface();
    }

    function movePaneFocus(dir: string): void {
        if (!root.files)
            return;
        const cur = root.focusedRegion;
        const railOpen = Boolean(root.files.railOpen ?? true);
        const splitOpen = Boolean(root.files.splitOpen ?? false);
        const inspOpen = Boolean(root.files.inspectorOpen ?? false);
        let next = cur;

        if (dir === "left") {
            if (cur === "preview" || cur === "properties")
                next = splitOpen ? "secondary" : "primary";
            else if (cur === "secondary")
                next = "primary";
            else if (cur === "primary" && railOpen)
                next = "rail";
        } else if (dir === "right") {
            if (cur === "rail")
                next = "primary";
            else if (cur === "primary")
                next = splitOpen ? "secondary" : (inspOpen ? root.lastInspectorRegion : cur);
            else if (cur === "secondary" && inspOpen)
                next = root.lastInspectorRegion;
        } else if (dir === "down") {
            if (cur === "preview" && inspOpen)
                next = "properties";
        } else if (dir === "up") {
            if (cur === "properties" && inspOpen)
                next = "preview";
        }
        if (next !== cur)
            root.focusRegion(next);
    }

    function railFlatItems(): var {
        const out = [];
        if (root.placesExpanded) {
            for (const p of (root.files?.places ?? []))
                out.push({ kind: "place", path: String(p.path ?? ""), item: p });
        }
        if (root.bookmarksExpanded) {
            for (const b of (root.files?.bookmarks ?? []))
                out.push({ kind: "bookmark", path: String(b.path ?? ""), item: b });
        }
        if (root.drivesExpanded) {
            for (const d of (root.files?.drives ?? []))
                out.push({ kind: "drive", path: String(d.mount_point ?? ""), item: d });
        }
        return out;
    }

    function stepRailFocus(delta: int): void {
        const items = root.railFlatItems();
        if (items.length === 0)
            return;
        const cur = Math.max(0, Math.min(items.length - 1, root.railFocusIndex));
        root.railFocusIndex = Math.max(0, Math.min(items.length - 1, cur + delta));
    }

    function activateFocusedRailItem(): void {
        const items = root.railFlatItems();
        if (items.length === 0 || !root.files)
            return;
        const idx = Math.max(0, Math.min(items.length - 1, root.railFocusIndex));
        const entry = items[idx];
        if (entry.kind === "drive" && !Boolean(entry.item?.is_mounted)) {
            const dev = String(entry.item?.block_device ?? "");
            if (dev.length > 0)
                root.files.mountDrive(dev);
        } else if (entry.path.length > 0) {
            root.files.navigate(entry.path);
        }
        root.focusRegion(root.activeIsSecondary ? "secondary" : "primary");
    }

    function cyclePropsTab(delta: int): void {
        const order = ["general", "permissions", "checksums", "details"];
        const idx = Math.max(0, order.indexOf(root.activePropsTab));
        const next = (idx + delta + order.length) % order.length;
        root.activePropsTab = order[next];
    }

    function scrollOverlayFlick(flick, deltaPx: real): void {
        if (!flick)
            return;
        const maxY = Math.max(0, flick.contentHeight - flick.height);
        flick.contentY = Math.max(0, Math.min(maxY, flick.contentY + deltaPx));
    }

    function moveFocusedRegion(deltaRows: int, scrollPx: real): void {
        if (root.focusedRegion === "rail") root.stepRailFocus(deltaRows);
        else if (root.focusedRegion === "preview") root.scrollOverlayFlick(previewFlick, scrollPx);
        else if (root.focusedRegion === "properties") root.scrollOverlayFlick(propsScroll, scrollPx);
        else root.moveCursor(deltaRows);
    }

    function handleEscape(): bool {
        if (root._pendingVimKey.length > 0) {
            root._pendingVimKey = "";
            return true;
        }
        if (root.files?.quickLookEntry) {
            root.files.closeQuickLook();
            root.focusPrimarySurface();
            return true;
        }
        if (root.openWithPickerOpen) {
            root.openWithPickerOpen = false;
            root.focusPrimarySurface();
            return true;
        }
        if (root.promptMode.length > 0) {
            root.promptMode = "";
            root.focusPrimarySurface();
            return true;
        }
        if (root.contextMenuOpen) {
            root.contextMenuOpen = false;
            root.focusPrimarySurface();
            return true;
        }
        if (root.sortMenuOpen) {
            root.sortMenuOpen = false;
            root.focusPrimarySurface();
            return true;
        }
        if (root.pathEditActive) {
            root.pathEditActive = false;
            root.focusPrimarySurface();
            return true;
        }
        if (root.filterBarOpen) {
            root.filterBarOpen = false;
            if (root.files) root.files.setFilter("", false);
            root.focusPrimarySurface();
            return true;
        }
        if (verifyHashField.activeFocus) {
            verifyHashField.focus = false;
            root.focusPrimarySurface();
            return true;
        }
        if ((root.selectedPaths.length > 0 || root.markMode) && root.files) {
            root.markMode = false;
            root.setActiveSelectedPaths([]);
            root.focusIndex = -1;
            if (root.files.clipboardOp === "cut") {
                root.files.clipboardPaths = [];
                root.files.clipboardOp = "";
            }
            return true;
        }
        return false;
    }

    function forwardKeyEvent(event): bool {
        if (!event || !root.files)
            return false;
        const key = event.key;
        if (key === Qt.Key_Shift || key === Qt.Key_Control || key === Qt.Key_Alt || key === Qt.Key_Meta)
            return false;
        const mods = event.modifiers ?? Qt.NoModifier;
        const ctrl = Boolean(mods & Qt.ControlModifier);
        const shift = Boolean(mods & Qt.ShiftModifier);
        const alt = Boolean(mods & Qt.AltModifier);

        if (key === Qt.Key_Escape)
            return root.handleEscape();

        if (root.files.quickLookEntry) {
            if (key === Qt.Key_Space) { root.files.closeQuickLook(); return true; }
            if (key === Qt.Key_Left || key === Qt.Key_Up) { root.files.stepQuickLook(-1); return true; }
            if (key === Qt.Key_Right || key === Qt.Key_Down) { root.files.stepQuickLook(1); return true; }
            return false;
        }

        const editing = root.pathEditActive || root.filterBarOpen || root.promptMode.length > 0;

        if (ctrl && !alt) {
            root._pendingVimKey = "";
            if (key === Qt.Key_L) {
                root.pathEditActive = true;
                Qt.callLater(() => { pathField.text = root.activePath; pathField.forceActiveFocus(); pathField.selectAll(); });
                return true;
            }
            if (key === Qt.Key_F) {
                root.filterBarOpen = true;
                Qt.callLater(() => filterField.forceActiveFocus());
                return true;
            }
            if (key === Qt.Key_T) { root.files.newTab(""); return true; }
            if (key === Qt.Key_W) { root.files.closeTab(root.files.activeTabIndex); return true; }
            if (key === Qt.Key_Backtab) { root.files.prevTab(); return true; }
            if (key === Qt.Key_Tab) { root.files.nextTab(); return true; }
            if (key === Qt.Key_H) { root.files.toggleHidden(); return true; }
            if (key === Qt.Key_1) { root.files.setViewMode("grid"); return true; }
            if (key === Qt.Key_2) { root.files.setViewMode("list"); return true; }
            if (key === Qt.Key_3) { root.files.setViewMode("gallery"); return true; }
            if (key === Qt.Key_I && !editing) { root.files.toggleInspector(); return true; }
            if (!editing) {
                if (key === Qt.Key_C) { const ps = root.actionPaths(); if (ps.length > 0) root.files.copyPaths(ps); return true; }
                if (key === Qt.Key_X) { const ps = root.actionPaths(); if (ps.length > 0) root.files.cutPaths(ps); return true; }
                if (key === Qt.Key_V) { root.files.paste(); return true; }
                if (key === Qt.Key_Z && !shift) { root.files.undo(); return true; }
                if ((key === Qt.Key_Z && shift) || key === Qt.Key_Y || (key === Qt.Key_R && root.files.vimKeybindings)) { root.files.redo(); return true; }
                if (key === Qt.Key_D && root.files.vimKeybindings) { root.moveFocusedRegion(10, 320); return true; }
                if (key === Qt.Key_U && root.files.vimKeybindings) { root.moveFocusedRegion(-10, -320); return true; }
                if (key === Qt.Key_A) { root.setActiveSelectedPaths(root.entries.map(e => String(e.path))); return true; }
                if (key === Qt.Key_N && shift) { root.beginPrompt("mkdir", "", "New Folder"); return true; }
            }
        }

        if (alt && !ctrl) {
            root._pendingVimKey = "";
            if (key === Qt.Key_Left) { root.files.goBack(); return true; }
            if (key === Qt.Key_Right) { root.files.goForward(); return true; }
            if (key === Qt.Key_Up) { root.files.goParent(); return true; }
            if (key === Qt.Key_H) { root.movePaneFocus("left"); return true; }
            if (key === Qt.Key_J) { root.movePaneFocus("down"); return true; }
            if (key === Qt.Key_K) { root.movePaneFocus("up"); return true; }
            if (key === Qt.Key_L) { root.movePaneFocus("right"); return true; }
            if (key === Qt.Key_I) { root.files.toggleInspector(); return true; }
            if (key === Qt.Key_Space && !editing) {
                const target = (root.focusedRegion === "preview" || root.focusedRegion === "properties")
                    ? root.inspectEntry
                    : (root.cursorEntry ?? root.activeEntry ?? root.inspectEntry);
                if (target) {
                    root.files.openQuickLook(target);
                    return true;
                }
            }
            if (key === Qt.Key_Return || key === Qt.Key_Enter) { root.openPropertiesForSelection(); return true; }
            if (key === Qt.Key_T) { root.files.newTab(""); return true; }
            if (key === Qt.Key_W) { root.files.closeTab(root.files.activeTabIndex); return true; }
            if (key >= Qt.Key_1 && key <= Qt.Key_9) {
                root.files.switchTab(key - Qt.Key_1);
                return true;
            }
        }

        if (key === Qt.Key_F3) { root.files.toggleSplitView(); return true; }
        if (key === Qt.Key_F9) { root.files.toggleRail(); return true; }
        if (key === Qt.Key_F5) { root.files.refresh(); return true; }

        if (editing)
            return false;

        // Pending Yazi two-key chords: gg, g<place>, zh (handled before Space/nav/actions)
        if (!ctrl && !alt && root.files.vimKeybindings && root._pendingVimKey.length > 0) {
            const first = root._pendingVimKey;
            root._pendingVimKey = "";
            if (first === "g") {
                if (key === Qt.Key_G && !shift) { root.jumpCursor(0); return true; }
                if (key === Qt.Key_H && !shift) { root.gotoPreset("home"); return true; }
                if (key === Qt.Key_C && !shift) { root.gotoPreset("config"); return true; }
                if (key === Qt.Key_D && !shift) { root.gotoPreset("downloads"); return true; }
                if (key === Qt.Key_D && shift) { root.gotoPreset("documents"); return true; }
                if (key === Qt.Key_E && !shift) { root.gotoPreset("desktop"); return true; }
                if (key === Qt.Key_P && !shift) { root.gotoPreset("pictures"); return true; }
                if (key === Qt.Key_V && !shift) { root.gotoPreset("videos"); return true; }
                if (key === Qt.Key_M && !shift) { root.gotoPreset("music"); return true; }
                if (key === Qt.Key_T && !shift) { root.gotoPreset("trash"); return true; }
                if (key === Qt.Key_Slash) { root.gotoPreset("root"); return true; }
                if (key === Qt.Key_Space) {
                    root.pathEditActive = true;
                    Qt.callLater(() => { pathField.text = root.activePath; pathField.forceActiveFocus(); pathField.selectAll(); });
                    return true;
                }
                return true;
            }
            if (first === "z") {
                if (key === Qt.Key_H && !shift) { root.files.toggleHidden(); return true; }
                return true;
            }
        }

        if (key === Qt.Key_Tab && (root.files?.splitOpen ?? false)) {
            root.focusRegion(root.activeIsSecondary ? "primary" : "secondary");
            return true;
        }

        if (root.files.vimKeybindings && !ctrl && !alt && shift) {
            if (key === Qt.Key_J) { root.moveFocusedRegion(5, 180); return true; }
            if (key === Qt.Key_K) { root.moveFocusedRegion(-5, -180); return true; }
        }

        if (root.focusedRegion === "rail") {
            if (key === Qt.Key_Down || (root.files.vimKeybindings && !shift && key === Qt.Key_J)) { root.stepRailFocus(1); return true; }
            if (key === Qt.Key_Up || (root.files.vimKeybindings && !shift && key === Qt.Key_K)) { root.stepRailFocus(-1); return true; }
            if (key === Qt.Key_Return || key === Qt.Key_Enter || (root.files.vimKeybindings && !shift && (key === Qt.Key_L || key === Qt.Key_O))) { root.activateFocusedRailItem(); return true; }
        } else if (root.focusedRegion === "preview") {
            if (key === Qt.Key_Down || (root.files.vimKeybindings && !shift && key === Qt.Key_J)) { root.scrollOverlayFlick(previewFlick, 48); return true; }
            if (key === Qt.Key_Up || (root.files.vimKeybindings && !shift && key === Qt.Key_K)) { root.scrollOverlayFlick(previewFlick, -48); return true; }
            if ((key === Qt.Key_Return || key === Qt.Key_Enter || (root.files.vimKeybindings && !shift && key === Qt.Key_O)) && root.inspectEntry) { root.activateItem(root.inspectEntry); return true; }
        } else if (root.focusedRegion === "properties") {
            if (key === Qt.Key_Left || (root.files.vimKeybindings && !shift && key === Qt.Key_H)) { root.cyclePropsTab(-1); return true; }
            if (key === Qt.Key_Right || (root.files.vimKeybindings && !shift && key === Qt.Key_L)) { root.cyclePropsTab(1); return true; }
            if (key === Qt.Key_Down || (root.files.vimKeybindings && !shift && key === Qt.Key_J)) { root.scrollOverlayFlick(propsScroll, 48); return true; }
            if (key === Qt.Key_Up || (root.files.vimKeybindings && !shift && key === Qt.Key_K)) { root.scrollOverlayFlick(propsScroll, -48); return true; }
        }
        const renameEntry = root.cursorEntry ?? root.activeEntry;
        if (key === Qt.Key_F2 && renameEntry) {
            root.beginPrompt("rename", String(renameEntry.path), String(renameEntry.name));
            return true;
        }
        if (key === Qt.Key_Delete) {
            const ps = root.actionPaths();
            if (ps.length > 0) {
                if (shift || (root.files?.activeIsTrash ?? false)) {
                    if (root.files.confirmPermanentDelete)
                        root.beginPrompt("confirmDelete", "", "");
                    else
                        root.files.deletePaths(ps);
                } else {
                    root.files.trashPaths(ps);
                }
                return true;
            }
        }
        if (key === Qt.Key_Backspace) { root.files.goParent(); return true; }
        if (key === Qt.Key_Space && (root.focusedRegion === "primary" || root.focusedRegion === "secondary")) {
            root.toggleSelectAndAdvance();
            return true;
        }
        if ((key === Qt.Key_Return || key === Qt.Key_Enter) && renameEntry) { root.activateItem(renameEntry); return true; }
        if (key === Qt.Key_Down || (root.files.vimKeybindings && !shift && key === Qt.Key_J)) { root.moveCursor(1); return true; }
        if (key === Qt.Key_Up || (root.files.vimKeybindings && !shift && key === Qt.Key_K)) { root.moveCursor(-1); return true; }

        if (!root.files.vimKeybindings)
            return false;

        // Yazi/Vim single-key commands & chord starters
        if (key === Qt.Key_G && !shift) { root._pendingVimKey = "g"; return true; }
        if (key === Qt.Key_Z && !shift) { root._pendingVimKey = "z"; return true; }
        if (key === Qt.Key_G && shift) { root.jumpCursor(root.entries.length - 1); return true; }
        if (key === Qt.Key_H && shift) { root.files.goBack(); return true; }
        if (key === Qt.Key_L && shift) { root.files.goForward(); return true; }
        if (key === Qt.Key_BracketLeft) { root.files.prevTab(); return true; }
        if (key === Qt.Key_BracketRight) { root.files.nextTab(); return true; }
        if (key === Qt.Key_T && !shift) { root.files.newTab(""); return true; }
        if (!shift && key >= Qt.Key_1 && key <= Qt.Key_9) { root.files.switchTab(key - Qt.Key_1); return true; }
        if (key === Qt.Key_Y && !shift) { const ps = root.actionPaths(); if (ps.length > 0) root.files.copyPaths(ps); return true; }
        if (key === Qt.Key_X && !shift) { const ps = root.actionPaths(); if (ps.length > 0) root.files.cutPaths(ps); return true; }
        if (key === Qt.Key_D && !shift) {
            const ps = root.actionPaths();
            if (ps.length > 0) {
                if (root.files?.activeIsTrash ?? false) {
                    if (root.files.confirmPermanentDelete)
                        root.beginPrompt("confirmDelete", "", "");
                    else
                        root.files.deletePaths(ps);
                } else {
                    root.files.trashPaths(ps);
                }
            }
            return true;
        }
        if (key === Qt.Key_D && shift) {
            const ps = root.actionPaths();
            if (ps.length > 0) {
                if (root.files.confirmPermanentDelete)
                    root.beginPrompt("confirmDelete", "", "");
                else
                    root.files.deletePaths(ps);
            }
            return true;
        }
        if (key === Qt.Key_A && !shift) { root.beginPrompt("create", "", ""); return true; }
        if ((key === Qt.Key_H && !shift) || key === Qt.Key_Minus) { root.files.goParent(); return true; }
        if (((key === Qt.Key_L && !shift) || key === Qt.Key_O) && renameEntry) { root.activateItem(renameEntry); return true; }
        if (key === Qt.Key_P) { root.files.paste(); return true; }
        if (key === Qt.Key_U) { root.files.undo(); return true; }
        if (key === Qt.Key_R && renameEntry) { root.beginPrompt("rename", String(renameEntry.path), String(renameEntry.name)); return true; }
        if (key === Qt.Key_Period) { root.files.toggleHidden(); return true; }
        if (key === Qt.Key_Slash) {
            root.filterBarOpen = true;
            Qt.callLater(() => filterField.forceActiveFocus());
            return true;
        }
        return false;
    }

    Keys.onPressed: event => {
        if (root.forwardKeyEvent(event))
            event.accepted = true;
    }

    MouseArea {
        anchors.fill: parent
        visible: root.contextMenuOpen || root.sortMenuOpen
        z: 40
        onClicked: {
            root.contextMenuOpen = false;
            root.sortMenuOpen = false;
        }
    }

    // ── Main 3-Column inir-files Layout (Rail | Rounded Canvas Card | Aside) ─
    RowLayout {
        anchors.fill: parent
        spacing: 0

        // 1. Left Smoked Rail
        Rectangle {
            id: railPanel
            visible: root.files?.railOpen ?? true
            Layout.fillHeight: true
            Layout.preferredWidth: root.railTargetWidth
            Layout.minimumWidth: root.railTargetWidth
            Layout.maximumWidth: root.railTargetWidth
            radius: 16
            color: Appearance.colors.colLayer1
            border.width: 1
            border.color: root.focusedRegion === "rail"
                ? Qt.alpha(Appearance.colors.colOnSurface, 0.14)
                : "transparent"
            clip: true

            readonly property int bmFlatOffset: root.placesExpanded ? (root.files?.places ?? []).length : 0
            readonly property int drvFlatOffset: bmFlatOffset + (root.bookmarksExpanded ? (root.files?.bookmarks ?? []).length : 0)

            TapHandler {
                onTapped: root.focusRegion("rail")
            }

            Flickable {
                anchors.fill: parent
                anchors.margins: 8
                contentHeight: railCol.implicitHeight
                clip: true

                ColumnLayout {
                    id: railCol
                    width: parent.width
                    spacing: 4

                    Rectangle {
                        Layout.fillWidth: true
                        height: 26
                        radius: 8
                        Layout.topMargin: 2
                        color: placesHdrHov.containsMouse ? Qt.alpha(Appearance.colors.colLayer2, 0.5) : "transparent"
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 6
                            spacing: 4
                            StyledText {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                text: Translation.tr("Places")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colSubtext
                                elide: Text.ElideRight
                            }
                            MaterialSymbol {
                                text: root.placesExpanded ? "expand_more" : "chevron_right"
                                iconSize: 15
                                color: Appearance.colors.colSubtext
                            }
                        }
                        MouseArea {
                            id: placesHdrHov
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.placesExpanded = !root.placesExpanded
                        }
                    }

                    Repeater {
                        model: root.placesExpanded ? (root.files?.places ?? []) : []
                        delegate: Rectangle {
                            id: placeRow
                            required property int index
                            required property var modelData
                            readonly property bool activePlace: root.activePath === String(placeRow.modelData.path ?? "")
                            readonly property bool kbdFocused: root.focusedRegion === "rail" && root.railFocusIndex === placeRow.index
                            Layout.fillWidth: true
                            height: 32
                            radius: 9
                            color: activePlace
                                ? Appearance.colors.colSecondaryContainer
                                : (placeHover.containsMouse ? Qt.alpha(Appearance.colors.colLayer2, 0.7) : "transparent")
                            border.width: placeRow.kbdFocused ? 1 : 0
                            border.color: Qt.alpha(Appearance.colors.colOnSurface, 0.18)

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 8
                                MaterialSymbol {
                                    text: String(placeRow.modelData.icon ?? "folder")
                                    iconSize: 16
                                    color: activePlace ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurfaceVariant
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    text: String(placeRow.modelData.label ?? "")
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.weight: activePlace ? Font.DemiBold : Font.Normal
                                    color: activePlace ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurface
                                    elide: Text.ElideRight
                                }
                                StyledText {
                                    visible: Boolean(placeRow.modelData.is_trash) && (root.files?.trashCount ?? 0) > 0
                                    text: String(root.files?.trashCount ?? 0)
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: Appearance.colors.colSubtext
                                }
                            }
                            MouseArea {
                                id: placeHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.railFocusIndex = placeRow.index;
                                    if (root.files) root.files.navigate(String(placeRow.modelData.path));
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 26
                        radius: 8
                        Layout.topMargin: 8
                        color: bmHdrHov.containsMouse ? Qt.alpha(Appearance.colors.colLayer2, 0.5) : "transparent"
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 6
                            spacing: 4
                            StyledText {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                text: Translation.tr("Bookmarks")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colSubtext
                                elide: Text.ElideRight
                            }
                            MaterialSymbol {
                                text: root.bookmarksExpanded ? "expand_more" : "chevron_right"
                                iconSize: 15
                                color: Appearance.colors.colSubtext
                            }
                        }
                        MouseArea {
                            id: bmHdrHov
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.bookmarksExpanded = !root.bookmarksExpanded
                        }
                    }

                    StyledText {
                        visible: root.bookmarksExpanded && (root.files?.bookmarks ?? []).length === 0
                        text: Translation.tr("No bookmarks yet")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        Layout.leftMargin: 10
                    }

                    Repeater {
                        model: root.bookmarksExpanded ? (root.files?.bookmarks ?? []) : []
                        delegate: Rectangle {
                            id: bmRow
                            required property int index
                            required property var modelData
                            readonly property bool activeBm: root.activePath === String(bmRow.modelData.path ?? "")
                            readonly property bool kbdFocused: root.focusedRegion === "rail" && root.railFocusIndex === (railPanel.bmFlatOffset + bmRow.index)
                            Layout.fillWidth: true
                            height: 30
                            radius: 9
                            color: activeBm
                                ? Appearance.colors.colSecondaryContainer
                                : ((bmRowHover.hovered || bmRemoveBtn.buttonHovered) ? Qt.alpha(Appearance.colors.colLayer2, 0.7) : "transparent")
                            border.width: bmRow.kbdFocused ? 1 : 0
                            border.color: Qt.alpha(Appearance.colors.colOnSurface, 0.18)

                            HoverHandler {
                                id: bmRowHover
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 6
                                spacing: 6
                                MaterialSymbol {
                                    text: "star"
                                    iconSize: 15
                                    color: activeBm ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colPrimary
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    text: String(modelData.name ?? "")
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: activeBm ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurface
                                    elide: Text.ElideRight
                                }
                                RippleButton {
                                    id: bmRemoveBtn
                                    z: 2
                                    implicitWidth: 22
                                    implicitHeight: 22
                                    buttonRadius: 11
                                    colBackground: "transparent"
                                    colBackgroundHover: Qt.alpha(Appearance.colors.colOnSurface, 0.12)
                                    visible: bmRowHover.hovered || bmRemoveBtn.buttonHovered
                                    contentItem: MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "close"
                                        iconSize: 13
                                        color: Appearance.colors.colSubtext
                                    }
                                    onClicked: if (root.files) root.files.removeBookmark(String(modelData.path))
                                }
                            }
                            MouseArea {
                                id: bmClickArea
                                anchors.fill: parent
                                anchors.rightMargin: 28
                                cursorShape: Qt.PointingHandCursor
                                onClicked: if (root.files) root.files.navigate(String(modelData.path))
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 26
                        radius: 8
                        Layout.topMargin: 8
                        color: drvHdrHov.containsMouse ? Qt.alpha(Appearance.colors.colLayer2, 0.5) : "transparent"
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 6
                            spacing: 4
                            StyledText {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                text: Translation.tr("Drives")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colSubtext
                                elide: Text.ElideRight
                            }
                            MaterialSymbol {
                                text: root.drivesExpanded ? "expand_more" : "chevron_right"
                                iconSize: 15
                                color: Appearance.colors.colSubtext
                            }
                        }
                        MouseArea {
                            id: drvHdrHov
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.drivesExpanded = !root.drivesExpanded
                        }
                    }

                    Repeater {
                        model: root.drivesExpanded ? (root.files?.drives ?? []) : []
                        delegate: ColumnLayout {
                            id: drvRow
                            required property int index
                            required property var modelData
                            readonly property string mp: String(drvRow.modelData.mount_point ?? "")
                            readonly property bool activeDrv: mp.length > 0 && root.activePath === mp
                            readonly property bool kbdFocused: root.focusedRegion === "rail" && root.railFocusIndex === (railPanel.drvFlatOffset + drvRow.index)
                            Layout.fillWidth: true
                            spacing: 3

                            Rectangle {
                                Layout.fillWidth: true
                                height: 32
                                radius: 9
                                color: activeDrv
                                    ? Appearance.colors.colSecondaryContainer
                                    : (drvHover.containsMouse ? Qt.alpha(Appearance.colors.colLayer2, 0.7) : "transparent")
                                border.width: drvRow.kbdFocused ? 1 : 0
                                border.color: Qt.alpha(Appearance.colors.colOnSurface, 0.18)
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 6
                                    spacing: 6
                                    MaterialSymbol {
                                        text: String(drvRow.modelData.icon ?? "hard_drive")
                                        iconSize: 16
                                        color: activeDrv ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurfaceVariant
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        text: String(drvRow.modelData.name ?? "")
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        color: activeDrv ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurface
                                        elide: Text.ElideRight
                                    }
                                    StyledText {
                                        visible: !Boolean(drvRow.modelData.is_mounted)
                                        text: Translation.tr("Mount")
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: Appearance.colors.colPrimary
                                    }
                                    RippleButton {
                                        visible: Boolean(drvRow.modelData.can_eject) && Boolean(drvRow.modelData.is_mounted)
                                        implicitWidth: 22
                                        implicitHeight: 22
                                        buttonRadius: 11
                                        colBackground: "transparent"
                                        colBackgroundHover: Qt.alpha(Appearance.colors.colOnSurface, 0.12)
                                        contentItem: MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: "eject"
                                            iconSize: 14
                                            color: Appearance.colors.colSubtext
                                        }
                                        onClicked: if (root.files) root.files.unmountDrive(drvRow.mp, String(drvRow.modelData.block_device ?? ""), Boolean(drvRow.modelData.is_removable))
                                    }
                                }
                                MouseArea {
                                    id: drvHover
                                    anchors.fill: parent
                                    anchors.rightMargin: Boolean(drvRow.modelData.can_eject) ? 28 : 0
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.railFocusIndex = railPanel.drvFlatOffset + drvRow.index;
                                        if (!root.files) return;
                                        if (Boolean(drvRow.modelData.is_mounted) && drvRow.mp.length > 0)
                                            root.files.navigate(drvRow.mp);
                                        else if (String(drvRow.modelData.block_device ?? "").length > 0)
                                            root.files.mountDrive(String(drvRow.modelData.block_device));
                                    }
                                }
                            }

                            Rectangle {
                                visible: Number(drvRow.modelData.total_bytes ?? 0) > 0
                                Layout.fillWidth: true
                                Layout.leftMargin: 10
                                Layout.rightMargin: 10
                                height: 3
                                radius: 2
                                color: Qt.alpha(Appearance.colors.colOutlineVariant, 0.35)
                                Rectangle {
                                    height: parent.height
                                    radius: 2
                                    width: parent.width * Math.max(0, Math.min(1, Number(drvRow.modelData.usage_fraction ?? 0)))
                                    color: Appearance.colors.colPrimary
                                }
                            }
                        }
                    }
                }
            }
        }

        // Left Rail Resize Splitter
        Item {
            id: railSplitter
            visible: root.files?.railOpen ?? true
            Layout.preferredWidth: 8
            Layout.minimumWidth: 8
            Layout.maximumWidth: 8
            Layout.fillHeight: true
            z: 20

            readonly property bool active: railResizeMouse.pressed || railResizeMouse.containsMouse

            Rectangle {
                anchors.centerIn: parent
                width: 3
                height: 48
                radius: 2
                opacity: railSplitter.active ? 1.0 : 0.0
                Behavior on opacity { NumberAnimation { duration: 130 } }
                color: Appearance.colors.colPrimary
            }

            MouseArea {
                id: railResizeMouse
                anchors.fill: parent
                anchors.leftMargin: -3
                anchors.rightMargin: -3
                hoverEnabled: true
                preventStealing: true
                cursorShape: Qt.SplitHCursor
                property real pressRootX: 0
                property int pressWidth: 228
                onPressed: mouse => {
                    const pt = mapToItem(root, mouse.x, 0);
                    pressRootX = pt.x;
                    pressWidth = railPanel.width;
                }
                onPositionChanged: mouse => {
                    if (!pressed || !root.files)
                        return;
                    const pt = mapToItem(root, mouse.x, 0);
                    const inspW = inspectorPanel.visible ? inspectorPanel.width : 0;
                    const maxW = Math.max(156, Math.min(460, Math.round(root.width - 360 - inspW)));
                    root.files.setRailWidth(Math.max(156, Math.min(maxW, Math.round(pressWidth + (pt.x - pressRootX)))));
                }
                onDoubleClicked: if (root.files) root.files.setRailWidth(228)
            }
        }

        // 2. Center Rounded Canvas Card
        Rectangle {
            id: canvasCard
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 18
            color: Appearance.colors.colLayer1
            border.width: 1
            border.color: (root.focusedRegion === "primary" || root.focusedRegion === "secondary")
                ? Qt.alpha(Appearance.colors.colOnSurface, 0.14)
                : "transparent"
            clip: true

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                // Auto-hiding Unified TabStrip (shows single tabs + 2-in-1 merged Split Tabs)
                Rectangle {
                    visible: (root.files?.tabs ?? []).length > 1 || (root.files?.splitOpen ?? false)
                    Layout.fillWidth: true
                    height: 38
                    color: Qt.alpha(Appearance.colors.colLayer0, 0.45)

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 6

                        Flickable {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            contentWidth: tabStripRow.implicitWidth
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            RowLayout {
                                id: tabStripRow
                                height: parent.height
                                spacing: 6

                                Repeater {
                                    model: root.files?.tabs ?? []
                                    delegate: Item {
                                        id: tabSlot
                                        required property int index
                                        required property var modelData
                                        readonly property bool isCur: tabSlot.index === (root.files?.activeTab ?? 0)
                                        readonly property bool isSplit: Boolean(tabSlot.modelData?.split)
                                        Layout.preferredWidth: tabSlot.isSplit ? 286 : 168
                                        Layout.minimumWidth: tabSlot.isSplit ? 176 : 104
                                        Layout.maximumWidth: tabSlot.isSplit ? 340 : 210
                                        height: 30
                                        Layout.alignment: Qt.AlignVCenter

                                        // Single Tab Pill
                                        Rectangle {
                                            visible: !tabSlot.isSplit
                                            anchors.fill: parent
                                            radius: 10
                                            color: tabSlot.isCur
                                                ? Appearance.colors.colSecondaryContainer
                                                : (singleTabHover.containsMouse ? Appearance.colors.colLayer2 : Qt.alpha(Appearance.colors.colLayer2, 0.35))
                                            border.width: 1
                                            border.color: tabSlot.isCur
                                                ? Qt.alpha(Appearance.colors.colPrimary, 0.55)
                                                : Qt.alpha(Appearance.colors.colOutlineVariant, 0.25)

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 10
                                                anchors.rightMargin: 4
                                                spacing: 6
                                                MaterialSymbol {
                                                    text: "folder"
                                                    iconSize: 14
                                                    color: tabSlot.isCur ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colSubtext
                                                }
                                                StyledText {
                                                    Layout.fillWidth: true
                                                    Layout.minimumWidth: 0
                                                    text: String(tabSlot.modelData.title ?? "")
                                                    color: tabSlot.isCur ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurface
                                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                                    font.weight: tabSlot.isCur ? Font.DemiBold : Font.Normal
                                                    elide: Text.ElideRight
                                                }
                                                HeadToolButton {
                                                    visible: (root.files?.tabs ?? []).length > 1
                                                    implicitWidth: 20
                                                    implicitHeight: 20
                                                    buttonRadius: 10
                                                    iconName: "close"
                                                    btnIconSize: 12
                                                    StyledToolTip { text: Translation.tr("Close tab (Alt+W)") }
                                                    onClicked: if (root.files) root.files.closeTab(tabSlot.index)
                                                }
                                            }
                                            MouseArea {
                                                id: singleTabHover
                                                anchors.fill: parent
                                                anchors.rightMargin: (root.files?.tabs ?? []).length > 1 ? 24 : 0
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: if (root.files) {
                                                    root.files.switchTab(tabSlot.index, false);
                                                    root.focusRegion("primary");
                                                }
                                            }
                                            StyledToolTip {
                                                useParentHover: false
                                                externalHoverState: singleTabHover.containsMouse
                                                externalPressedState: singleTabHover.pressed
                                                text: String(tabSlot.modelData.path ?? "")
                                            }
                                        }

                                        // Merged Split Tab Pill: [ Left Half ✕ | Right Half ✕ ]
                                        Rectangle {
                                            visible: tabSlot.isSplit
                                            anchors.fill: parent
                                            radius: 11
                                            color: tabSlot.isCur
                                                ? Qt.alpha(Appearance.colors.colLayer2, 0.65)
                                                : Qt.alpha(Appearance.colors.colLayer2, 0.25)
                                            border.width: tabSlot.isCur ? 1.5 : 1
                                            border.color: tabSlot.isCur
                                                ? Qt.alpha(Appearance.colors.colPrimary, 0.72)
                                                : Qt.alpha(Appearance.colors.colOutlineVariant, 0.35)

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.margins: 2
                                                spacing: 2

                                                // Left Split Half
                                                Rectangle {
                                                    id: leftHalfPill
                                                    readonly property bool halfActive: tabSlot.isCur && !root.activeIsSecondary
                                                    Layout.fillWidth: true
                                                    Layout.fillHeight: true
                                                    Layout.minimumWidth: 0
                                                    radius: 8
                                                    color: leftHalfPill.halfActive
                                                        ? Appearance.colors.colSecondaryContainer
                                                        : (leftHalfHover.containsMouse ? Qt.alpha(Appearance.colors.colLayer2, 0.85) : "transparent")

                                                    RowLayout {
                                                        anchors.fill: parent
                                                        anchors.leftMargin: 7
                                                        anchors.rightMargin: 2
                                                        spacing: 4
                                                        MaterialSymbol {
                                                            text: "folder"
                                                            iconSize: 13
                                                            color: leftHalfPill.halfActive ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colSubtext
                                                        }
                                                        StyledText {
                                                            Layout.fillWidth: true
                                                            Layout.minimumWidth: 0
                                                            text: String(tabSlot.modelData.title ?? "")
                                                            color: leftHalfPill.halfActive ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurface
                                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                                            font.weight: leftHalfPill.halfActive ? Font.DemiBold : Font.Normal
                                                            elide: Text.ElideRight
                                                        }
                                                        HeadToolButton {
                                                            implicitWidth: 18
                                                            implicitHeight: 18
                                                            buttonRadius: 9
                                                            iconName: "close"
                                                            btnIconSize: 11
                                                            StyledToolTip { text: Translation.tr("Close left pane") }
                                                            onClicked: if (root.files) {
                                                                root.files.closeTabHalf(tabSlot.index, "left");
                                                                root.focusRegion("primary");
                                                            }
                                                        }
                                                    }
                                                    MouseArea {
                                                        id: leftHalfHover
                                                        anchors.fill: parent
                                                        anchors.rightMargin: 20
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: if (root.files) {
                                                            root.files.switchTab(tabSlot.index, false);
                                                            root.focusRegion("primary");
                                                        }
                                                    }
                                                    StyledToolTip {
                                                        useParentHover: false
                                                        externalHoverState: leftHalfHover.containsMouse
                                                        externalPressedState: leftHalfHover.pressed
                                                        text: String(tabSlot.modelData.path ?? "")
                                                    }
                                                }

                                                // Subtle vertical divider inside the merged split tab
                                                Rectangle {
                                                    Layout.preferredWidth: 1
                                                    Layout.fillHeight: true
                                                    Layout.topMargin: 4
                                                    Layout.bottomMargin: 4
                                                    color: Qt.alpha(Appearance.colors.colOutlineVariant, 0.5)
                                                }

                                                // Right Split Half
                                                Rectangle {
                                                    id: rightHalfPill
                                                    readonly property bool halfActive: tabSlot.isCur && root.activeIsSecondary
                                                    Layout.fillWidth: true
                                                    Layout.fillHeight: true
                                                    Layout.minimumWidth: 0
                                                    radius: 8
                                                    color: rightHalfPill.halfActive
                                                        ? Appearance.colors.colSecondaryContainer
                                                        : (rightHalfHover.containsMouse ? Qt.alpha(Appearance.colors.colLayer2, 0.85) : "transparent")

                                                    RowLayout {
                                                        anchors.fill: parent
                                                        anchors.leftMargin: 7
                                                        anchors.rightMargin: 2
                                                        spacing: 4
                                                        MaterialSymbol {
                                                            text: "folder"
                                                            iconSize: 13
                                                            color: rightHalfPill.halfActive ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colSubtext
                                                        }
                                                        StyledText {
                                                            Layout.fillWidth: true
                                                            Layout.minimumWidth: 0
                                                            text: String(tabSlot.modelData.split?.title ?? "")
                                                            color: rightHalfPill.halfActive ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurface
                                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                                            font.weight: rightHalfPill.halfActive ? Font.DemiBold : Font.Normal
                                                            elide: Text.ElideRight
                                                        }
                                                        HeadToolButton {
                                                            implicitWidth: 18
                                                            implicitHeight: 18
                                                            buttonRadius: 9
                                                            iconName: "close"
                                                            btnIconSize: 11
                                                            StyledToolTip { text: Translation.tr("Close right pane") }
                                                            onClicked: if (root.files) {
                                                                root.files.closeTabHalf(tabSlot.index, "right");
                                                                root.focusRegion("primary");
                                                            }
                                                        }
                                                    }
                                                    MouseArea {
                                                        id: rightHalfHover
                                                        anchors.fill: parent
                                                        anchors.rightMargin: 20
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: if (root.files) {
                                                            root.files.switchTab(tabSlot.index, true);
                                                            root.focusRegion("secondary");
                                                        }
                                                    }
                                                    StyledToolTip {
                                                        useParentHover: false
                                                        externalHoverState: rightHalfHover.containsMouse
                                                        externalPressedState: rightHalfHover.pressed
                                                        text: String(tabSlot.modelData.split?.path ?? "")
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        HeadToolButton {
                            implicitWidth: 28
                            implicitHeight: 28
                            buttonRadius: 14
                            iconName: "add"
                            btnIconSize: 16
                            StyledToolTip { text: Translation.tr("New tab (Alt+T)") }
                            onClicked: if (root.files) root.files.newTab("")
                        }
                    }
                }

                // Head Toolbar (Back/Forward/Up | Recessed PathBar | Search | View Segments | Sort | Split | Hidden | Inspector | Open Window)
                RowLayout {
                    Layout.fillWidth: true
                    Layout.margins: 10
                    Layout.bottomMargin: 6
                    spacing: 6

                    HeadToolButton {
                        visible: !(root.files?.railOpen ?? true)
                        iconName: "dock_to_left"
                        StyledToolTip { text: Translation.tr("Show Places (F9)") }
                        onClicked: if (root.files) root.files.toggleRail()
                    }
                    HeadToolButton {
                        iconName: "arrow_back"
                        enabled: Boolean(root.files?.activeTabNode?.backStack?.length > 0)
                        StyledToolTip { text: Translation.tr("Back (Alt+Left)") }
                        onClicked: if (root.files) root.files.goBack()
                    }
                    HeadToolButton {
                        iconName: "arrow_forward"
                        enabled: Boolean(root.files?.activeTabNode?.forwardStack?.length > 0)
                        StyledToolTip { text: Translation.tr("Forward (Alt+Right)") }
                        onClicked: if (root.files) root.files.goForward()
                    }
                    HeadToolButton {
                        iconName: "arrow_upward"
                        enabled: String(root.files?.activeParentPath ?? "").length > 0
                        onClicked: if (root.files) root.files.goParent()
                    }

                    // Recessed Inset PathBar
                    Rectangle {
                        Layout.fillWidth: true
                        height: 34
                        radius: 11
                        color: Appearance.colors.colLayer0
                        border.width: root.pathEditActive ? 1.5 : 1
                        border.color: root.pathEditActive ? Appearance.colors.colPrimary : Qt.alpha(Appearance.colors.colOutlineVariant, 0.3)

                        RowLayout {
                            visible: !root.pathEditActive
                            anchors.fill: parent
                            anchors.leftMargin: 6
                            anchors.rightMargin: 6
                            spacing: 2

                            Flickable {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                contentWidth: crumbRow.implicitWidth
                                clip: true
                                Row {
                                    id: crumbRow
                                    height: parent.height
                                    spacing: 2
                                    Repeater {
                                        model: root.breadcrumbSegments()
                                        delegate: Row {
                                            required property int index
                                            required property var modelData
                                            height: parent.height
                                            spacing: 2
                                            StyledText {
                                                visible: index > 0
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: "›"
                                                color: Appearance.colors.colSubtext
                                                font.pixelSize: Appearance.font.pixelSize.small
                                            }
                                            Rectangle {
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: crumbText.implicitWidth + 14
                                                height: 24
                                                radius: 7
                                                color: crumbMouse.containsMouse ? Appearance.colors.colLayer2 : "transparent"
                                                StyledText {
                                                    id: crumbText
                                                    anchors.centerIn: parent
                                                    text: String(modelData.label)
                                                    font.pixelSize: Appearance.font.pixelSize.small
                                                    font.weight: Font.Medium
                                                }
                                                MouseArea {
                                                    id: crumbMouse
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: if (root.files) root.files.navigate(String(modelData.path))
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            Item {
                                Layout.preferredWidth: 18
                                Layout.fillHeight: true
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.IBeamCursor
                                    onClicked: {
                                        root.pathEditActive = true;
                                        Qt.callLater(() => { pathField.text = root.activePath; pathField.forceActiveFocus(); pathField.selectAll(); });
                                    }
                                }
                            }

                            HeadToolButton {
                                implicitWidth: 26
                                implicitHeight: 26
                                buttonRadius: 7
                                iconName: "edit"
                                btnIconSize: 15
                                onClicked: {
                                    root.pathEditActive = true;
                                    Qt.callLater(() => { pathField.text = root.activePath; pathField.forceActiveFocus(); pathField.selectAll(); });
                                }
                            }
                        }

                        TextField {
                            id: pathField
                            objectName: "alisFilesPathInput"
                            visible: root.pathEditActive
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            background: null
                            color: Appearance.colors.colOnSurface
                            font.pixelSize: Appearance.font.pixelSize.small
                            selectByMouse: true
                            Keys.onEscapePressed: event => {
                                if (root.handleEscape())
                                    event.accepted = true;
                            }
                            onAccepted: {
                                const target = text.trim();
                                root.pathEditActive = false;
                                if (root.files && target.length > 0)
                                    root.files.navigate(target);
                                root.focusPrimarySurface();
                            }
                        }
                    }

                    // Filter / Search toggle
                    HeadToolButton {
                        toggled: root.filterBarOpen
                        iconName: "search"
                        onClicked: {
                            root.filterBarOpen = !root.filterBarOpen;
                            if (root.filterBarOpen) Qt.callLater(() => filterField.forceActiveFocus());
                            else if (root.files) root.files.setFilter("", false);
                        }
                    }

                    // Segmented Pill View Switcher (Grid | List | Gallery)
                    Rectangle {
                        height: 32
                        radius: 10
                        color: Appearance.colors.colLayer0
                        Layout.preferredWidth: segRow.implicitWidth + 6
                        Row {
                            id: segRow
                            anchors.centerIn: parent
                            spacing: 2
                            Repeater {
                                model: [
                                    { mode: "grid", icon: "grid_view" },
                                    { mode: "list", icon: "view_list" },
                                    { mode: "gallery", icon: "photo_library" }
                                ]
                                delegate: Rectangle {
                                    required property var modelData
                                    readonly property bool activeMode: (root.files?.viewMode ?? "grid") === modelData.mode
                                    width: 30; height: 26; radius: 8
                                    color: activeMode ? Appearance.colors.colLayer2 : (segHov.containsMouse ? Qt.alpha(Appearance.colors.colLayer2, 0.5) : "transparent")
                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: modelData.icon
                                        iconSize: 17
                                        color: activeMode || segHov.containsMouse ? Appearance.colors.colOnSurface : Appearance.colors.colOnSurfaceVariant
                                    }
                                    MouseArea {
                                        id: segHov
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: if (root.files) root.files.setViewMode(modelData.mode)
                                    }
                                }
                            }
                        }
                    }

                    HeadToolButton {
                        toggled: root.sortMenuOpen
                        iconName: "swap_vert"
                        onClicked: root.sortMenuOpen = !root.sortMenuOpen
                    }

                    HeadToolButton {
                        toggled: root.files?.splitOpen ?? false
                        iconName: "splitscreen_right"
                        StyledToolTip { text: Translation.tr("Split View (F3)") }
                        onClicked: if (root.files) root.files.toggleSplitView()
                    }

                    HeadToolButton {
                        toggled: root.files?.showHidden ?? false
                        iconName: "visibility"
                        onClicked: if (root.files) root.files.toggleHidden()
                    }

                    HeadToolButton {
                        toggled: root.files?.inspectorOpen ?? false
                        iconName: "dock_to_right"
                        onClicked: if (root.files) root.files.toggleInspector()
                    }
                }

                // Inline Filter & Recursive Search Bar
                Rectangle {
                    visible: root.filterBarOpen
                    Layout.fillWidth: true
                    height: 40
                    color: Qt.alpha(Appearance.colors.colLayer0, 0.45)

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 8
                        MaterialSymbol { text: "search"; iconSize: 17; color: Appearance.colors.colSubtext }
                        TextField {
                            id: filterField
                            objectName: "alisFilesFilterInput"
                            Layout.fillWidth: true
                            placeholderText: Translation.tr("Filter folder or toggle Recursive search…")
                            background: null
                            color: Appearance.colors.colOnSurface
                            Keys.onEscapePressed: event => {
                                if (root.handleEscape())
                                    event.accepted = true;
                            }
                            onTextChanged: if (root.files) root.files.setFilter(text, recursiveBtn.toggled)
                        }
                        RippleButton {
                            id: recursiveBtn
                            implicitHeight: 26
                            implicitWidth: 94
                            buttonRadius: 8
                            toggled: root.files?.recursiveSearch ?? false
                            colBackground: Appearance.colors.colLayer2
                            colBackgroundHover: Appearance.colors.colLayer2Hover
                            colBackgroundToggled: Appearance.colors.colSecondaryContainer
                            colBackgroundToggledHover: Qt.lighter(Appearance.colors.colSecondaryContainer, 1.12)
                            contentItem: Item {
                                anchors.fill: parent
                                StyledText {
                                    anchors.centerIn: parent
                                    text: Translation.tr("Recursive")
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.weight: recursiveBtn.toggled ? Font.DemiBold : Font.Normal
                                    color: recursiveBtn.toggled ? Appearance.colors.colPrimary : Appearance.colors.colOnSurface
                                }
                            }
                            onClicked: if (root.files) root.files.setFilter(filterField.text, !root.files.recursiveSearch)
                        }
                        RippleButton {
                            implicitWidth: 26; implicitHeight: 26; buttonRadius: 13
                            colBackground: "transparent"
                            colBackgroundHover: Appearance.colors.colLayer2Hover
                            contentItem: MaterialSymbol { anchors.centerIn: parent; text: "close"; iconSize: 15; color: Appearance.colors.colOnSurface }
                            onClicked: {
                                root.filterBarOpen = false;
                                filterField.text = "";
                                if (root.files) root.files.setFilter("", false);
                                root.focusPrimarySurface();
                            }
                        }
                    }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: Qt.alpha(Appearance.colors.colOutlineVariant, 0.25) }

                // Dual/Single Content Viewport (Grid/Gallery | List | Empty + Split Divider + Toast Pill)
                Item {
                    id: bodyArea
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true

                    Row {
                        anchors.fill: parent
                        spacing: 0

                        OverlayFilePane {
                            id: primaryPane
                            width: (root.files?.splitOpen ?? false)
                                ? Math.max(120, Math.round((bodyArea.width - splitDivider.width) * (root.files?.splitRatio ?? 0.5)))
                                : bodyArea.width
                            height: bodyArea.height
                            files: root.files
                            isSecondary: false
                            splitOpen: root.files?.splitOpen ?? false
                            isActivePane: !root.activeIsSecondary
                            isFocusedPane: root.focusedRegion === "primary"
                            focusIdx: !root.activeIsSecondary ? root.focusIndex : -1
                            viewMode: root.files?.viewMode ?? "grid"
                            gridIconSize: root.files?.gridIconSize ?? 72
                            listZoom: root.files?.listZoom ?? 1
                            entriesList: root.files?.entries ?? []
                            selectedList: root.files?.selectedPaths ?? []
                            gitBadgesMap: root.files?.gitBadges ?? ({})
                            thumbMap: root.files?.thumbMap ?? ({})
                            thumbnailsEnabled: root.files?.thumbnailsEnabled ?? true
                            clipboardPaths: root.files?.clipboardPaths ?? []
                            clipboardOp: root.files?.clipboardOp ?? ""
                            sortField: root.files?.sortField ?? "name"
                            sortOrder: root.files?.sortOrder ?? "asc"
                            filterText: root.files?.filterText ?? ""
                            errorMessage: root.files?.errorMessage ?? ""
                            iconForEntryFn: root.iconForEntry
                            onPaneFocused: root.focusRegion("primary")
                            onSelectionRequested: (idx, toggle, range) => {
                                root.selectPaneIndex(false, idx, toggle, range);
                                root.focusedRegion = "primary";
                            }
                            onItemActivated: entry => {
                                root.focusRegion("primary");
                                root.activateItem(entry);
                            }
                            onContextRequested: (entry, sourceItem, localX, localY) => {
                                root.focusRegion("primary");
                                const pt = sourceItem.mapToItem(root, localX, localY);
                                root.openContextFor(entry, pt.x, pt.y);
                            }
                            onClearSelectionRequested: {
                                root.focusRegion("primary");
                                root.markMode = false;
                                root.focusIndex = -1;
                                if (root.files) root.files.setPaneSelectedPaths(false, []);
                            }
                            onSortRequested: field => {
                                root.focusRegion("primary");
                                if (root.files) root.files.setSort(field);
                            }
                        }

                        Item {
                            id: splitDivider
                            visible: root.files?.splitOpen ?? false
                            width: visible ? 6 : 0
                            height: bodyArea.height
                            z: 15

                            Rectangle {
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 1
                                color: Qt.alpha(Appearance.colors.colOutlineVariant, 0.35)
                            }
                            Rectangle {
                                anchors.centerIn: parent
                                width: 3
                                height: 48
                                radius: 2
                                opacity: (splitDragMouse.containsMouse || splitDragMouse.pressed) ? 1.0 : 0.0
                                Behavior on opacity { NumberAnimation { duration: 130 } }
                                color: Appearance.colors.colPrimary
                            }
                            MouseArea {
                                id: splitDragMouse
                                anchors.fill: parent
                                anchors.leftMargin: -3
                                anchors.rightMargin: -3
                                hoverEnabled: true
                                cursorShape: Qt.SplitHCursor
                                property real _startRatio: 0.5
                                property real _startX: 0
                                onPressed: mouse => {
                                    _startRatio = root.files?.splitRatio ?? 0.5;
                                    _startX = mapToItem(bodyArea, mouse.x, 0).x;
                                }
                                onPositionChanged: mouse => {
                                    if (!pressed || !root.files || bodyArea.width <= 120)
                                        return;
                                    const curX = mapToItem(bodyArea, mouse.x, 0).x;
                                    const avail = Math.max(120, bodyArea.width - splitDivider.width);
                                    root.files.setSplitRatio(_startRatio + (curX - _startX) / avail);
                                }
                                onDoubleClicked: {
                                    if (root.files)
                                        root.files.setSplitRatio(0.5);
                                }
                            }
                        }

                        OverlayFilePane {
                            id: secondaryPane
                            visible: root.files?.splitOpen ?? false
                            width: visible ? Math.max(120, bodyArea.width - primaryPane.width - splitDivider.width) : 0
                            height: bodyArea.height
                            files: root.files
                            isSecondary: true
                            splitOpen: root.files?.splitOpen ?? false
                            isActivePane: root.activeIsSecondary
                            isFocusedPane: root.focusedRegion === "secondary"
                            focusIdx: root.activeIsSecondary ? root.focusIndex : -1
                            viewMode: root.files?.viewMode ?? "grid"
                            gridIconSize: root.files?.gridIconSize ?? 72
                            listZoom: root.files?.listZoom ?? 1
                            entriesList: root.files?.secondaryEntries ?? []
                            selectedList: root.files?.secondarySelectedPaths ?? []
                            gitBadgesMap: root.files?.secondaryGitBadges ?? ({})
                            thumbMap: root.files?.thumbMap ?? ({})
                            thumbnailsEnabled: root.files?.thumbnailsEnabled ?? true
                            clipboardPaths: root.files?.clipboardPaths ?? []
                            clipboardOp: root.files?.clipboardOp ?? ""
                            sortField: root.files?.sortField ?? "name"
                            sortOrder: root.files?.sortOrder ?? "asc"
                            filterText: root.files?.filterText ?? ""
                            errorMessage: ""
                            iconForEntryFn: root.iconForEntry
                            onPaneFocused: root.focusRegion("secondary")
                            onSelectionRequested: (idx, toggle, range) => {
                                root.selectPaneIndex(true, idx, toggle, range);
                                root.focusedRegion = "secondary";
                            }
                            onItemActivated: entry => {
                                root.focusRegion("secondary");
                                root.activateItem(entry);
                            }
                            onContextRequested: (entry, sourceItem, localX, localY) => {
                                root.focusRegion("secondary");
                                const pt = sourceItem.mapToItem(root, localX, localY);
                                root.openContextFor(entry, pt.x, pt.y);
                            }
                            onClearSelectionRequested: {
                                root.focusRegion("secondary");
                                root.markMode = false;
                                root.focusIndex = -1;
                                if (root.files) root.files.setPaneSelectedPaths(true, []);
                            }
                            onSortRequested: field => {
                                root.focusRegion("secondary");
                                if (root.files) root.files.setSort(field);
                            }
                        }
                    }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: Qt.alpha(Appearance.colors.colOutlineVariant, 0.25) }

                // Bottom Status Bar (inline transient notification replaces item count temporarily)
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 14
                    Layout.rightMargin: 14
                    height: 34
                    spacing: 10

                    StyledText {
                        visible: (root.files?.toastMessage ?? "").length === 0
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        elide: Text.ElideMiddle
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        text: {
                            const total = root.entries.length;
                            const nSel = root.selectedPaths.length;
                            if (nSel === 0)
                                return total + (total === 1 ? " item" : " items");
                            if (nSel === 1 && root.activeEntry)
                                return String(root.activeEntry.name) + " · " + (root.activeEntry.is_dir ? "Folder" : String(root.activeEntry.size_label));
                            return nSel + " of " + total + " chosen";
                        }
                    }

                    RowLayout {
                        visible: (root.files?.toastMessage ?? "").length > 0
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        spacing: 8

                        Item {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            implicitHeight: 22

                            StyledText {
                                anchors.fill: parent
                                verticalAlignment: Text.AlignVCenter
                                elide: Text.ElideRight
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: (root.files?.toastIsError ?? false) ? Font.Medium : Font.Normal
                                color: (root.files?.toastIsError ?? false) ? Appearance.colors.colError : Appearance.colors.colOnSurface
                                text: String(root.files?.toastMessage ?? "")
                            }
                            MouseArea {
                                id: statusToastHover
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.NoButton
                            }
                            StyledToolTip {
                                useParentHover: false
                                externalHoverState: statusToastHover.containsMouse
                                text: String(root.files?.toastMessage ?? "")
                            }
                        }

                        RippleButton {
                            visible: Boolean(root.files?.toastUndoable)
                            implicitHeight: 20
                            implicitWidth: 48
                            buttonRadius: 10
                            colBackground: Appearance.colors.colPrimary
                            colBackgroundHover: Qt.lighter(Appearance.colors.colPrimary, 1.12)
                            colRipple: Qt.alpha(Appearance.colors.colOnPrimary, 0.2)
                            contentItem: StyledText {
                                anchors.centerIn: parent
                                text: Translation.tr("Undo")
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnPrimary
                            }
                            onClicked: if (root.files) root.files.undo()
                        }
                    }

                    StyledText {
                        visible: (root.files?.activeGitBranch ?? "").length > 0
                        text: "git:" + String(root.files?.activeGitBranch ?? "")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colPrimary
                    }

                    Rectangle {
                        visible: root.files?.vimKeybindings ?? false
                        height: 18; width: 32; radius: 9
                        color: Qt.alpha(Appearance.colors.colPrimary, 0.16)
                        StyledText {
                            anchors.centerIn: parent
                            text: root._pendingVimKey.length > 0 ? (root._pendingVimKey + "…") : "VIM"
                            font.pixelSize: 10
                            font.weight: Font.Bold
                            color: Appearance.colors.colPrimary
                        }
                    }

                    Rectangle {
                        visible: (root.files?.totalBytes ?? 0) > 0
                        Layout.preferredWidth: 44
                        height: 3
                        radius: 2
                        color: Qt.alpha(Appearance.colors.colOutlineVariant, 0.35)
                        Rectangle {
                            height: parent.height
                            radius: 2
                            width: parent.width * Math.max(0, Math.min(1, ((root.files?.totalBytes ?? 0) - (root.files?.freeBytes ?? 0)) / Math.max(1, root.files?.totalBytes ?? 1)))
                            color: Appearance.colors.colPrimary
                        }
                    }

                    StyledText {
                        visible: (root.files?.freeLabel ?? "").length > 0
                        text: String(root.files?.freeLabel ?? "") + " free"
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }

                    Slider {
                        id: zoomSlider
                        readonly property bool isListView: (root.files?.viewMode ?? "grid") === "list"
                        Layout.preferredWidth: 92
                        implicitHeight: 22
                        from: 0
                        to: isListView ? 2 : 6
                        stepSize: 1
                        snapMode: Slider.SnapAlways
                        value: isListView ? (root.files?.listZoom ?? 1) : root.closestGridStepIndex(root.files?.gridIconSize ?? 72)
                        onMoved: {
                            if (!root.files) return;
                            const step = Math.round(value);
                            if (isListView)
                                root.files.setListZoom(step);
                            else
                                root.files.setGridIconSize(root.gridZoomSteps[Math.max(0, Math.min(root.gridZoomSteps.length - 1, step))]);
                        }
                        background: Rectangle {
                            x: zoomSlider.leftPadding
                            y: zoomSlider.topPadding + zoomSlider.availableHeight / 2 - height / 2
                            width: zoomSlider.availableWidth
                            height: 4
                            radius: 2
                            color: Qt.alpha(Appearance.colors.colOnSurface, 0.14)
                            Rectangle {
                                width: Math.max(0, Math.min(parent.width, zoomSlider.visualPosition * parent.width))
                                height: parent.height
                                radius: 2
                                color: Appearance.colors.colPrimary
                            }
                        }
                        handle: Rectangle {
                            x: zoomSlider.leftPadding + zoomSlider.visualPosition * (zoomSlider.availableWidth - width)
                            y: zoomSlider.topPadding + zoomSlider.availableHeight / 2 - height / 2
                            width: 14
                            height: 14
                            radius: 7
                            color: zoomSlider.pressed
                                ? Appearance.colors.colPrimary
                                : Appearance.colors.colLayer3
                            border.width: zoomSlider.hovered || zoomSlider.pressed ? 1.5 : 1
                            border.color: zoomSlider.hovered || zoomSlider.pressed
                                ? Appearance.colors.colPrimary
                                : Qt.alpha(Appearance.colors.colOnSurface, 0.28)
                            antialiasing: true
                        }
                    }
                }
            }
        }

        // Right Preview Inspector Resize Splitter
        Item {
            id: inspectorSplitter
            visible: root.files?.inspectorOpen ?? false
            Layout.preferredWidth: 8
            Layout.minimumWidth: 8
            Layout.maximumWidth: 8
            Layout.fillHeight: true
            z: 20

            readonly property bool active: inspectorResizeMouse.pressed || inspectorResizeMouse.containsMouse

            Rectangle {
                anchors.centerIn: parent
                width: 3
                height: 48
                radius: 2
                opacity: inspectorSplitter.active ? 1.0 : 0.0
                Behavior on opacity { NumberAnimation { duration: 130 } }
                color: Appearance.colors.colPrimary
            }

            MouseArea {
                id: inspectorResizeMouse
                anchors.fill: parent
                anchors.leftMargin: -3
                anchors.rightMargin: -3
                hoverEnabled: true
                preventStealing: true
                cursorShape: Qt.SplitHCursor
                property real pressRootX: 0
                property int pressWidth: 296
                onPressed: mouse => {
                    const pt = mapToItem(root, mouse.x, 0);
                    pressRootX = pt.x;
                    pressWidth = inspectorPanel.width;
                }
                onPositionChanged: mouse => {
                    if (!pressed || !root.files)
                        return;
                    const pt = mapToItem(root, mouse.x, 0);
                    const rW = railPanel.visible ? railPanel.width : 0;
                    const maxW = Math.max(200, Math.min(560, Math.round(root.width - 360 - rW)));
                    root.files.setInspectorWidth(Math.max(200, Math.min(maxW, Math.round(pressWidth - (pt.x - pressRootX)))));
                }
                onDoubleClicked: if (root.files) root.files.setInspectorWidth(296)
            }
        }

        // 3. Right Independent Preview Card (Top) + Live Properties Card (Bottom)
        Item {
            id: inspectorPanel
            visible: root.files?.inspectorOpen ?? false
            Layout.fillHeight: true
            Layout.preferredWidth: root.inspectorTargetWidth
            Layout.minimumWidth: root.inspectorTargetWidth
            Layout.maximumWidth: root.inspectorTargetWidth

            onVisibleChanged: {
                if (visible)
                    propsLoadTimer.restart();
            }

            Item {
                id: inspSplitCol
                anchors.fill: parent

                // Top Independent Card: Preview Pane
                Rectangle {
                    id: previewHalf
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    radius: 16
                    color: Appearance.colors.colLayer1
                    border.width: 1
                    border.color: root.focusedRegion === "preview"
                        ? Qt.alpha(Appearance.colors.colOnSurface, 0.14)
                        : "transparent"
                    clip: true

                    TapHandler {
                        onTapped: root.focusRegion("preview")
                    }
                    readonly property int minTopH: 164
                    readonly property int minBotH: 180
                    readonly property int availH: Math.max(minTopH + minBotH, inspSplitCol.height - inspVertDivider.height)
                    readonly property int maxTopH: Math.max(minTopH, availH - minBotH)
                    height: Math.max(minTopH, Math.min(maxTopH, Math.round(availH * (root.files?.inspectorPreviewRatio ?? 0.38))))

                    Flickable {
                        id: previewFlick
                        anchors.fill: parent
                        anchors.margins: 10
                        contentHeight: previewCol.implicitHeight
                        clip: true

                        ColumnLayout {
                            id: previewCol
                            width: previewFlick.width
                            spacing: 6

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Math.max(72, Math.min(144, previewHalf.height - 108))
                                radius: 12
                                color: Appearance.colors.colLayer2
                                clip: true
                                readonly property string previewPath: root.activeEntry ? String(root.files?.thumbMap?.[String(root.activeEntry.path)] ?? "") : ""

                                Image {
                                    anchors.fill: parent
                                    visible: parent.previewPath.length > 0
                                    source: parent.previewPath.length > 0 ? ("file://" + parent.previewPath) : ""
                                    sourceSize.width: 512
                                    sourceSize.height: 512
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                    cache: false
                                }
                                AlisFileArt {
                                    anchors.centerIn: parent
                                    visible: parent.previewPath.length === 0
                                    entry: root.activeEntry ?? ({
                                        is_dir: true,
                                        is_broken_symlink: false,
                                        name: root._tabTitleForInspector(),
                                        path: root.activePath
                                    })
                                    artSize: Math.max(44, Math.min(92, Math.round(parent.height * 0.72)))
                                    kindIcon: root.activeEntry ? root.iconForEntry(root.activeEntry) : "folder"
                                }
                            }

                            StyledText {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                text: root.activeEntry ? String(root.activeEntry.name)
                                    : (root.selectedPaths.length > 1 ? (root.selectedPaths.length + " items selected") : root._tabTitleForInspector())
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.DemiBold
                                wrapMode: Text.Wrap
                            }
                            StyledText {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                text: root.activeEntry
                                    ? (String(root.activeEntry.kind_label) + (root.activeEntry.is_dir ? "" : (" · " + String(root.activeEntry.size_label))))
                                    : (root.selectedPaths.length > 1
                                        ? (root.selectedPaths.length + " items selected")
                                        : ("Folder  •  " + root.entries.length + (root.entries.length === 1 ? " item" : " items")))
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                                elide: Text.ElideRight
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                enabled: root.inspectEntry !== null

                                Repeater {
                                    model: [
                                        { label: Translation.tr("Open"), action: "open" },
                                        { label: Translation.tr("Preview"), action: "preview" }
                                    ]
                                    delegate: RippleButton {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        implicitHeight: 28
                                        buttonRadius: 14
                                        colBackground: Appearance.colors.colLayer2
                                        colBackgroundHover: Appearance.colors.colLayer2Hover
                                        contentItem: Item {
                                            anchors.fill: parent
                                            StyledText {
                                                anchors.centerIn: parent
                                                width: parent.width - 8
                                                horizontalAlignment: Text.AlignHCenter
                                                verticalAlignment: Text.AlignVCenter
                                                text: modelData.label
                                                font.pixelSize: 12
                                                font.weight: Font.Medium
                                                color: Appearance.colors.colOnSurface
                                                elide: Text.ElideRight
                                            }
                                        }
                                        onClicked: {
                                            if (!root.inspectEntry) return;
                                            if (modelData.action === "open")
                                                root.activateItem(root.inspectEntry);
                                            else if (modelData.action === "preview" && root.files)
                                                root.files.openQuickLook(root.inspectEntry);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Clean Card Gap & Vertical Drag Handle
                Item {
                    id: inspVertDivider
                    anchors.top: previewHalf.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 8
                    z: 15

                    Rectangle {
                        anchors.centerIn: parent
                        width: 42
                        height: 3
                        radius: 2
                        opacity: (inspVertMouse.containsMouse || inspVertMouse.pressed) ? 1.0 : 0.0
                        Behavior on opacity { NumberAnimation { duration: 130 } }
                        color: Appearance.colors.colPrimary
                    }
                    MouseArea {
                        id: inspVertMouse
                        anchors.fill: parent
                        anchors.topMargin: -3
                        anchors.bottomMargin: -3
                        hoverEnabled: true
                        cursorShape: Qt.SplitVCursor
                        property real _startRatio: 0.38
                        property real _startY: 0
                        onPressed: mouse => {
                            _startRatio = root.files?.inspectorPreviewRatio ?? 0.38;
                            _startY = mapToItem(inspSplitCol, 0, mouse.y).y;
                        }
                        onPositionChanged: mouse => {
                            if (!pressed || !root.files || inspSplitCol.height <= 120)
                                return;
                            const curY = mapToItem(inspSplitCol, 0, mouse.y).y;
                            const avail = Math.max(120, inspSplitCol.height - inspVertDivider.height);
                            root.files.setInspectorPreviewRatio(_startRatio + (curY - _startY) / avail);
                        }
                        onDoubleClicked: {
                            if (root.files)
                                root.files.setInspectorPreviewRatio(0.38);
                        }
                    }
                }

                // Bottom Independent Card: Always-Visible Live Properties Pane
                Rectangle {
                    id: propsHalf
                    anchors.top: inspVertDivider.bottom
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    radius: 16
                    color: Appearance.colors.colLayer1
                    border.width: 1
                    border.color: root.focusedRegion === "properties"
                        ? Qt.alpha(Appearance.colors.colOnSurface, 0.14)
                        : "transparent"
                    clip: true

                    TapHandler {
                        onTapped: root.focusRegion("properties")
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 8

                        // Responsive 4-tab bar
                        Rectangle {
                            Layout.fillWidth: true
                            height: 30
                            radius: 10
                            color: Appearance.colors.colLayer0

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 3
                                spacing: 2

                                Repeater {
                                    model: [
                                        { id: "general", full: "General", short: "General", icon: "info" },
                                        { id: "permissions", full: "Permissions", short: "Perms", icon: "lock" },
                                        { id: "checksums", full: "Checksums", short: "Hash", icon: "fingerprint" },
                                        { id: "details", full: "Details", short: "Details", icon: "list_alt" }
                                    ]
                                    delegate: Rectangle {
                                        id: propsTabBtn
                                        required property var modelData
                                        readonly property bool isTabActive: root.activePropsTab === propsTabBtn.modelData.id
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        Layout.minimumWidth: 0
                                        radius: 7
                                        color: propsTabBtn.isTabActive
                                            ? Appearance.colors.colLayer2
                                            : (propsTabMouse.containsMouse ? Qt.alpha(Appearance.colors.colLayer2, 0.5) : "transparent")

                                        MaterialSymbol {
                                            visible: propsHalf.width < 245
                                            anchors.centerIn: parent
                                            text: propsTabBtn.modelData.icon
                                            iconSize: 15
                                            color: propsTabBtn.isTabActive ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
                                        }
                                        StyledText {
                                            visible: propsHalf.width >= 245
                                            anchors.centerIn: parent
                                            width: parent.width - 4
                                            horizontalAlignment: Text.AlignHCenter
                                            text: propsHalf.width >= 330 ? Translation.tr(propsTabBtn.modelData.full) : Translation.tr(propsTabBtn.modelData.short)
                                            font.pixelSize: 11
                                            font.weight: propsTabBtn.isTabActive ? Font.DemiBold : Font.Normal
                                            elide: Text.ElideRight
                                            color: propsTabBtn.isTabActive ? Appearance.colors.colOnSurface : Appearance.colors.colOnSurfaceVariant
                                        }
                                        MouseArea {
                                            id: propsTabMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.activePropsTab = propsTabBtn.modelData.id
                                        }
                                        StyledToolTip {
                                            useParentHover: false
                                            externalHoverState: propsTabMouse.containsMouse
                                            externalPressedState: propsTabMouse.pressed
                                            text: Translation.tr(propsTabBtn.modelData.full)
                                        }
                                    }
                                }
                            }
                        }

                        Flickable {
                            id: propsScroll
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            contentHeight: propsBodyCol.implicitHeight
                            clip: true

                            ColumnLayout {
                                id: propsBodyCol
                                width: propsScroll.width
                                spacing: 8

                                // Multi-selection fallback note for Perms / Checksums / Details
                                StyledText {
                                    visible: root.selectedPaths.length > 1 && root.activePropsTab !== "general"
                                    Layout.fillWidth: true
                                    wrapMode: Text.Wrap
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colSubtext
                                    text: Translation.tr("Select a single item to view this tab.")
                                }

                                // Multi-selection summary in General
                                ColumnLayout {
                                    visible: root.selectedPaths.length > 1 && root.activePropsTab === "general"
                                    Layout.fillWidth: true
                                    spacing: 6
                                    StyledText {
                                        text: Translation.tr("Selection")
                                        font.pixelSize: 11
                                        font.weight: Font.Bold
                                        color: Appearance.colors.colSubtext
                                    }
                                    PropsRow {
                                        labelText: Translation.tr("Items")
                                        valueText: String(root.selectedPaths.length)
                                    }
                                }

                                // ── GENERAL TAB ────────────────────────────────────
                                ColumnLayout {
                                    visible: root.selectedPaths.length <= 1 && root.activePropsTab === "general" && root.inspectEntry !== null
                                    Layout.fillWidth: true
                                    spacing: 6

                                    PropsRow {
                                        labelText: Translation.tr("Type")
                                        valueText: String(root.liveProps?.type_description ?? root.inspectEntry?.kind_label ?? "—")
                                    }
                                    PropsRow {
                                        visible: Boolean(root.liveProps?.mime_type)
                                        labelText: Translation.tr("Content")
                                        valueText: String(root.liveProps?.mime_type ?? "")
                                    }

                                    // Open with + inline Change... app picker
                                    RowLayout {
                                        visible: Boolean(root.liveProps) && !Boolean(root.liveProps?.is_dir) && !Boolean(root.liveProps?.is_broken_symlink)
                                        Layout.fillWidth: true
                                        spacing: 6
                                        StyledText {
                                            Layout.preferredWidth: 58
                                            text: Translation.tr("Open with")
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                            color: Appearance.colors.colSubtext
                                            elide: Text.ElideRight
                                        }
                                        StyledText {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            text: String(root.liveProps?.default_app_name ?? Translation.tr("Not set"))
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                            elide: Text.ElideRight
                                        }
                                        RippleButton {
                                            visible: (root.liveProps?.available_apps ?? []).length > 0
                                            implicitHeight: 24
                                            implicitWidth: changeLbl.implicitWidth + 14
                                            buttonRadius: 12
                                            toggled: root.openWithPickerOpen
                                            colBackground: Appearance.colors.colLayer2
                                            colBackgroundHover: Appearance.colors.colLayer2Hover
                                            colBackgroundToggled: Appearance.colors.colSecondaryContainer
                                            colBackgroundToggledHover: Qt.lighter(Appearance.colors.colSecondaryContainer, 1.12)
                                            contentItem: Item {
                                                anchors.fill: parent
                                                StyledText {
                                                    id: changeLbl
                                                    anchors.centerIn: parent
                                                    text: Translation.tr("Change…")
                                                    font.pixelSize: 11
                                                    font.weight: root.openWithPickerOpen ? Font.DemiBold : Font.Normal
                                                    color: root.openWithPickerOpen ? Appearance.colors.colPrimary : Appearance.colors.colOnSurface
                                                }
                                            }
                                            onClicked: root.openWithPickerOpen = !root.openWithPickerOpen
                                        }
                                    }

                                    Rectangle {
                                        visible: root.openWithPickerOpen && (root.liveProps?.available_apps ?? []).length > 0
                                        Layout.fillWidth: true
                                        implicitHeight: appPickerCol.implicitHeight + 10
                                        radius: 10
                                        color: Appearance.colors.colLayer2
                                        border.width: 1
                                        border.color: Qt.alpha(Appearance.colors.colOutlineVariant, 0.35)

                                        ColumnLayout {
                                            id: appPickerCol
                                            anchors.fill: parent
                                            anchors.margins: 5
                                            spacing: 2
                                            Repeater {
                                                model: root.liveProps?.available_apps ?? []
                                                delegate: RippleButton {
                                                    id: appChoiceBtn
                                                    required property var modelData
                                                    readonly property bool isDefApp: String(root.liveProps?.default_app_id ?? "") === String(appChoiceBtn.modelData.id ?? "")
                                                    Layout.fillWidth: true
                                                    implicitHeight: 26
                                                    buttonRadius: 7
                                                    toggled: appChoiceBtn.isDefApp
                                                    colBackground: "transparent"
                                                    colBackgroundHover: Appearance.colors.colLayer2Hover
                                                    colBackgroundToggled: Appearance.colors.colSecondaryContainer
                                                    colBackgroundToggledHover: Qt.lighter(Appearance.colors.colSecondaryContainer, 1.12)
                                                    contentItem: StyledText {
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        anchors.left: parent.left
                                                        anchors.leftMargin: 8
                                                        width: parent.width - 14
                                                        elide: Text.ElideRight
                                                        text: (appChoiceBtn.isDefApp ? "✓ " : "") + String(appChoiceBtn.modelData.name ?? "")
                                                        font.pixelSize: 11
                                                        font.weight: appChoiceBtn.isDefApp ? Font.DemiBold : Font.Normal
                                                        color: appChoiceBtn.isDefApp ? Appearance.colors.colPrimary : Appearance.colors.colOnSurface
                                                    }
                                                    onClicked: {
                                                        root.openWithPickerOpen = false;
                                                        if (root.files && root.liveProps) {
                                                            root.files.setDefaultApp(
                                                                String(root.liveProps.mime_type ?? ""),
                                                                String(appChoiceBtn.modelData.id ?? ""),
                                                                String(appChoiceBtn.modelData.name ?? "")
                                                            );
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    PropsRow {
                                        labelText: Translation.tr("Location")
                                        valueText: String(root.liveProps?.location ?? root.activePath)
                                        copyable: true
                                        copyValue: root.inspectPath
                                        filesRef: root.files
                                    }
                                    PropsRow {
                                        labelText: Translation.tr("Size")
                                        valueText: {
                                            if (Boolean(root.inspectEntry?.is_dir)) {
                                                if (root.files?.propsDirLoading)
                                                    return Translation.tr("Calculating…");
                                                const tot = root.files?.propsDirTotals;
                                                if (tot)
                                                    return String(tot.size_label ?? "—") + " (" + String(tot.item_count ?? 0) + " items)";
                                                return Translation.tr("Calculating…");
                                            }
                                            const sLabel = String(root.liveProps?.size_label ?? root.inspectEntry?.size_label ?? "—");
                                            const sBytes = Number(root.liveProps?.size ?? root.inspectEntry?.size ?? 0);
                                            return sLabel + " (" + sBytes + " B)";
                                        }
                                    }
                                    PropsRow {
                                        visible: Boolean(root.liveProps)
                                        labelText: Translation.tr("On disk")
                                        valueText: {
                                            if (Boolean(root.inspectEntry?.is_dir)) {
                                                if (root.files?.propsDirLoading)
                                                    return Translation.tr("Calculating…");
                                                const tot = root.files?.propsDirTotals;
                                                if (tot)
                                                    return String(tot.size_on_disk_label ?? "—") + " (" + String(tot.size_on_disk ?? 0) + " B)";
                                                return "—";
                                            }
                                            return String(root.liveProps?.size_on_disk_label ?? "—") + " (" + String(root.liveProps?.size_on_disk ?? 0) + " B)";
                                        }
                                    }

                                    StyledText {
                                        Layout.topMargin: 4
                                        text: Translation.tr("Dates")
                                        font.pixelSize: 11
                                        font.weight: Font.Bold
                                        color: Appearance.colors.colSubtext
                                    }
                                    PropsRow {
                                        visible: Boolean(root.liveProps?.created_label)
                                        labelText: Translation.tr("Created")
                                        valueText: String(root.liveProps?.created_label ?? "—")
                                    }
                                    PropsRow {
                                        labelText: Translation.tr("Modified")
                                        valueText: String(root.liveProps?.modified_label ?? root.inspectEntry?.modified_label ?? "—")
                                    }
                                    PropsRow {
                                        visible: Boolean(root.liveProps?.accessed_label)
                                        labelText: Translation.tr("Accessed")
                                        valueText: String(root.liveProps?.accessed_label ?? "—")
                                    }
                                }

                                // ── PERMISSIONS TAB ────────────────────────────────
                                ColumnLayout {
                                    visible: root.selectedPaths.length <= 1 && root.activePropsTab === "permissions" && root.inspectEntry !== null
                                    Layout.fillWidth: true
                                    spacing: 8

                                    Rectangle {
                                        Layout.fillWidth: true
                                        implicitHeight: permSummaryCol.implicitHeight + 14
                                        radius: 10
                                        color: Appearance.colors.colLayer2
                                        ColumnLayout {
                                            id: permSummaryCol
                                            anchors.fill: parent
                                            anchors.margins: 7
                                            spacing: 4
                                            PropsRow {
                                                labelText: Translation.tr("Owner")
                                                valueText: root.liveProps ? (String(root.liveProps.owner ?? "—") + ":" + String(root.liveProps.group ?? "—")) : "—"
                                            }
                                            PropsRow {
                                                labelText: Translation.tr("Mode")
                                                valueText: String(root.liveProps?.permissions_label ?? root.inspectEntry?.permissions ?? "—")
                                            }
                                        }
                                    }

                                    Repeater {
                                        model: [
                                            { name: "Owner", r: 256, w: 128, x: 64 },
                                            { name: "Group", r: 32, w: 16, x: 8 },
                                            { name: "Others", r: 4, w: 2, x: 1 }
                                        ]
                                        delegate: RowLayout {
                                            id: permRoleRow
                                            required property var modelData
                                            Layout.fillWidth: true
                                            spacing: 4
                                            StyledText {
                                                Layout.preferredWidth: 46
                                                text: Translation.tr(permRoleRow.modelData.name)
                                                font.pixelSize: Appearance.font.pixelSize.smaller
                                                color: Appearance.colors.colSubtext
                                                elide: Text.ElideRight
                                            }
                                            Repeater {
                                                model: [
                                                    { ch: "R", bit: permRoleRow.modelData.r, tip: "Read" },
                                                    { ch: "W", bit: permRoleRow.modelData.w, tip: "Write" },
                                                    { ch: "X", bit: permRoleRow.modelData.x, tip: "Execute" }
                                                ]
                                                delegate: RippleButton {
                                                    id: permBitBtn
                                                    required property var modelData
                                                    readonly property int bitMask: Number(permBitBtn.modelData.bit)
                                                    readonly property int curMode: Number(root.liveProps?.mode ?? 0) & 511
                                                    readonly property bool bitOn: (curMode & bitMask) !== 0
                                                    Layout.fillWidth: true
                                                    Layout.minimumWidth: 0
                                                    implicitHeight: 26
                                                    buttonRadius: 7
                                                    enabled: Boolean(root.liveProps?.can_chmod)
                                                    toggled: permBitBtn.bitOn
                                                    colBackground: Appearance.colors.colLayer2
                                                    colBackgroundHover: Appearance.colors.colLayer2Hover
                                                    colBackgroundToggled: Appearance.colors.colSecondaryContainer
                                                    colBackgroundToggledHover: Qt.lighter(Appearance.colors.colSecondaryContainer, 1.15)
                                                    contentItem: Item {
                                                        anchors.fill: parent
                                                        StyledText {
                                                            anchors.centerIn: parent
                                                            horizontalAlignment: Text.AlignHCenter
                                                            verticalAlignment: Text.AlignVCenter
                                                            text: String(permBitBtn.modelData.ch)
                                                            font.pixelSize: 11
                                                            font.weight: Font.DemiBold
                                                            color: permBitBtn.bitOn ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
                                                        }
                                                    }
                                                    StyledToolTip { text: Translation.tr(permBitBtn.modelData.tip) }
                                                    onClicked: {
                                                        if (!root.files || !root.liveProps) return;
                                                        const nextMode = permBitBtn.bitOn
                                                            ? (permBitBtn.curMode & ~permBitBtn.bitMask)
                                                            : (permBitBtn.curMode | permBitBtn.bitMask);
                                                        root.files.setItemPermissions(String(root.liveProps.path), nextMode);
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    RippleButton {
                                        id: execToggleBtn
                                        visible: Boolean(root.liveProps) && !Boolean(root.liveProps?.is_dir)
                                        Layout.fillWidth: true
                                        implicitHeight: 30
                                        buttonRadius: 8
                                        enabled: Boolean(root.liveProps?.can_chmod)
                                        toggled: Boolean(root.liveProps?.is_executable)
                                        colBackground: Appearance.colors.colLayer2
                                        colBackgroundHover: Appearance.colors.colLayer2Hover
                                        colBackgroundToggled: Appearance.colors.colSecondaryContainer
                                        colBackgroundToggledHover: Qt.lighter(Appearance.colors.colSecondaryContainer, 1.15)
                                        contentItem: Item {
                                            anchors.fill: parent
                                            Row {
                                                anchors.centerIn: parent
                                                spacing: 6
                                                MaterialSymbol {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: "terminal"
                                                    iconSize: 15
                                                    color: execToggleBtn.toggled ? Appearance.colors.colPrimary : Appearance.colors.colOnSurface
                                                }
                                                StyledText {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: Translation.tr("Executable")
                                                    font.pixelSize: 12
                                                    font.weight: Font.Medium
                                                    color: execToggleBtn.toggled ? Appearance.colors.colPrimary : Appearance.colors.colOnSurface
                                                }
                                            }
                                        }
                                        onClicked: {
                                            if (!root.files || !root.liveProps) return;
                                            const cur = Number(root.liveProps.mode ?? 0) & 511;
                                            const next = Boolean(root.liveProps.is_executable) ? (cur & ~73) : (cur | 73);
                                            root.files.setItemPermissions(String(root.liveProps.path), next);
                                        }
                                    }

                                    StyledText {
                                        visible: Boolean(root.liveProps) && !Boolean(root.liveProps?.can_chmod)
                                        Layout.fillWidth: true
                                        wrapMode: Text.Wrap
                                        font.pixelSize: 11
                                        color: Appearance.colors.colSubtext
                                        text: Boolean(root.liveProps?.is_symlink)
                                            ? Translation.tr("Permissions are managed on the link target.")
                                            : Translation.tr("Only the file owner can modify permissions.")
                                    }
                                }

                                // ── CHECKSUMS TAB ──────────────────────────────────
                                ColumnLayout {
                                    visible: root.selectedPaths.length <= 1 && root.activePropsTab === "checksums" && root.inspectEntry !== null
                                    Layout.fillWidth: true
                                    spacing: 6

                                    StyledText {
                                        visible: Boolean(root.inspectEntry?.is_dir) || Boolean(root.inspectEntry?.is_broken_symlink)
                                        Layout.fillWidth: true
                                        wrapMode: Text.Wrap
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: Appearance.colors.colSubtext
                                        text: Translation.tr("Checksums are available for regular files.")
                                    }

                                    Repeater {
                                        model: (!Boolean(root.inspectEntry?.is_dir) && !Boolean(root.inspectEntry?.is_broken_symlink)) ? [
                                            { label: "MD5", algo: "md5" },
                                            { label: "SHA-1", algo: "sha1" },
                                            { label: "SHA-256", algo: "sha256" },
                                            { label: "SHA-512", algo: "sha512" }
                                        ] : []
                                        delegate: Rectangle {
                                            id: sumCard
                                            required property var modelData
                                            readonly property string digest: String(root.files?.propsChecksums?.[sumCard.modelData.algo] ?? "")
                                            readonly property bool busy: Boolean(root.files?.propsChecksumBusy?.[sumCard.modelData.algo])
                                            Layout.fillWidth: true
                                            implicitHeight: sumCol.implicitHeight + 12
                                            radius: 10
                                            color: Appearance.colors.colLayer2

                                            ColumnLayout {
                                                id: sumCol
                                                anchors.fill: parent
                                                anchors.margins: 6
                                                spacing: 4

                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 4
                                                    StyledText {
                                                        Layout.fillWidth: true
                                                        text: sumCard.modelData.label
                                                        font.pixelSize: 11
                                                        font.weight: Font.DemiBold
                                                    }
                                                    HeadToolButton {
                                                        visible: sumCard.digest.length > 0
                                                        implicitWidth: 22
                                                        implicitHeight: 22
                                                        buttonRadius: 6
                                                        iconName: "content_copy"
                                                        btnIconSize: 13
                                                        onClicked: {
                                                            Quickshell.clipboardText = sumCard.digest;
                                                            if (root.files) root.files.showToast("Copied " + sumCard.modelData.label + " checksum", false);
                                                        }
                                                    }
                                                    RippleButton {
                                                        implicitHeight: 24
                                                        implicitWidth: calcTxt.implicitWidth + 14
                                                        buttonRadius: 12
                                                        enabled: !sumCard.busy
                                                        colBackground: Appearance.colors.colLayer1
                                                        colBackgroundHover: Appearance.colors.colLayer1Hover
                                                        contentItem: Item {
                                                            anchors.fill: parent
                                                            StyledText {
                                                                id: calcTxt
                                                                anchors.centerIn: parent
                                                                text: sumCard.busy ? "…" : (sumCard.digest.length > 0 ? Translation.tr("Re-calc") : Translation.tr("Calculate"))
                                                                font.pixelSize: 11
                                                                color: Appearance.colors.colOnSurface
                                                            }
                                                        }
                                                        onClicked: if (root.files && root.inspectPath.length > 0) root.files.computeChecksum(root.inspectPath, sumCard.modelData.algo)
                                                    }
                                                }

                                                StyledText {
                                                    Layout.fillWidth: true
                                                    Layout.minimumWidth: 0
                                                    wrapMode: Text.WrapAnywhere
                                                    font.family: Appearance.font.family.monospace
                                                    font.pixelSize: 10
                                                    color: sumCard.digest.length > 0 ? Appearance.colors.colOnSurface : Appearance.colors.colSubtext
                                                    text: sumCard.busy ? Translation.tr("Calculating…") : (sumCard.digest.length > 0 ? sumCard.digest : Translation.tr("Not calculated"))
                                                }
                                            }
                                        }
                                    }

                                    Rectangle {
                                        visible: !Boolean(root.inspectEntry?.is_dir) && !Boolean(root.inspectEntry?.is_broken_symlink)
                                        Layout.fillWidth: true
                                        height: 30
                                        radius: 8
                                        color: Appearance.colors.colLayer0
                                        border.width: 1
                                        border.color: Qt.alpha(Appearance.colors.colOutlineVariant, 0.35)
                                        TextField {
                                            id: verifyHashField
                                            objectName: "alisFilesVerifyHashInput"
                                            anchors.fill: parent
                                            anchors.leftMargin: 8
                                            anchors.rightMargin: 8
                                            background: null
                                            placeholderText: Translation.tr("Verify hash…")
                                            color: Appearance.colors.colOnSurface
                                            font.pixelSize: 11
                                            text: root.verifyHashInput
                                            Keys.onEscapePressed: event => {
                                                if (root.handleEscape())
                                                    event.accepted = true;
                                            }
                                            onTextChanged: root.verifyHashInput = text
                                        }
                                    }

                                    StyledText {
                                        id: verifyResultText
                                        readonly property string needle: root.verifyHashInput.trim().toLowerCase()
                                        readonly property string matchedAlgo: {
                                            if (verifyResultText.needle.length === 0 || !root.files) return "";
                                            const map = root.files.propsChecksums ?? ({});
                                            for (const k in map) {
                                                if (String(map[k]).toLowerCase() === verifyResultText.needle)
                                                    return k.toUpperCase();
                                            }
                                            return "";
                                        }
                                        readonly property bool hasAnySum: {
                                            const map = root.files?.propsChecksums ?? ({});
                                            return Object.keys(map).length > 0;
                                        }
                                        visible: verifyResultText.needle.length > 0 && !Boolean(root.inspectEntry?.is_dir)
                                        Layout.fillWidth: true
                                        wrapMode: Text.Wrap
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                        color: verifyResultText.matchedAlgo.length > 0 ? Appearance.colors.colPrimary : (verifyResultText.hasAnySum ? Appearance.colors.colError : Appearance.colors.colSubtext)
                                        text: verifyResultText.matchedAlgo.length > 0
                                            ? Translation.tr("Matches %1").arg(verifyResultText.matchedAlgo)
                                            : (verifyResultText.hasAnySum ? Translation.tr("No computed hash matches") : Translation.tr("Calculate a checksum first"))
                                    }
                                }

                                // ── DETAILS TAB ────────────────────────────────────
                                ColumnLayout {
                                    visible: root.selectedPaths.length <= 1 && root.activePropsTab === "details" && root.inspectEntry !== null
                                    Layout.fillWidth: true
                                    spacing: 6

                                    PropsRow {
                                        labelText: Translation.tr("MIME")
                                        valueText: String(root.liveProps?.mime_type ?? root.inspectEntry?.kind_label ?? "—")
                                    }
                                    PropsRow {
                                        visible: Boolean(root.liveProps?.image_dimensions)
                                        labelText: Translation.tr("Dims")
                                        valueText: String(root.liveProps?.image_dimensions ?? "")
                                    }
                                    PropsRow {
                                        visible: Boolean(root.liveProps?.trash_original_path)
                                        labelText: Translation.tr("From")
                                        valueText: String(root.liveProps?.trash_original_path ?? "")
                                    }
                                    PropsRow {
                                        visible: Boolean(root.liveProps?.symlink_target)
                                        labelText: Translation.tr("Target")
                                        valueText: String(root.liveProps?.symlink_target ?? "")
                                    }
                                    PropsRow {
                                        id: gitDetailRow
                                        readonly property var gb: root.inspectEntry ? (root.files?.activeGitBadges?.[String(root.inspectEntry.path)] ?? null) : null
                                        visible: gitDetailRow.gb !== null || Boolean(root.liveProps?.git_status)
                                        labelText: Translation.tr("Git")
                                        valueText: String(root.liveProps?.git_status ?? gitDetailRow.gb?.desc ?? "")
                                    }
                                    PropsRow {
                                        visible: root.liveProps?.direct_children !== null && root.liveProps?.direct_children !== undefined
                                        labelText: Translation.tr("Direct")
                                        valueText: String(root.liveProps?.direct_children ?? 0) + " items"
                                    }
                                    PropsRow {
                                        visible: Boolean(root.liveProps)
                                        labelText: Translation.tr("Inode")
                                        valueText: String(root.liveProps?.inode ?? 0) + " (" + String(root.liveProps?.hard_links ?? 1) + " links)"
                                    }
                                    PropsRow {
                                        visible: Boolean(root.liveProps)
                                        labelText: Translation.tr("Device")
                                        valueText: String(root.liveProps?.device_id ?? 0)
                                    }
                                    PropsRow {
                                        labelText: Translation.tr("Path")
                                        valueText: root.inspectPath
                                        copyable: true
                                        copyValue: root.inspectPath
                                        filesRef: root.files
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    function _tabTitleForInspector(): string {
        const cur = root.activePath;
        const parts = cur.split("/").filter(Boolean);
        return parts.length > 0 ? parts[parts.length - 1] : "/";
    }

    // ── Sort Menu Popover ───────────────────────────────────────────────────
    Rectangle {
        visible: root.sortMenuOpen
        z: 50
        x: Math.max(8, root.width - 240 - (root.files?.inspectorOpen ? (inspectorPanel.width + 8) : 0))
        y: 52
        width: 204
        height: sortCol.implicitHeight + 12
        radius: 14
        color: Appearance.colors.colLayer2
        border.width: 1
        border.color: Qt.alpha(Appearance.colors.colOutlineVariant, 0.4)

        ColumnLayout {
            id: sortCol
            anchors.fill: parent
            anchors.margins: 6
            spacing: 2
            Repeater {
                model: [
                    { label: "Name", field: "name" },
                    { label: "Modified", field: "modified" },
                    { label: "Size", field: "size" },
                    { label: "Kind", field: "kind" }
                ]
                delegate: MenuActionRow {
                    required property var modelData
                    labelText: ((root.files?.sortField ?? "name") === modelData.field ? "✓  " : "    ") + Translation.tr(modelData.label)
                    onClicked: {
                        root.sortMenuOpen = false;
                        if (root.files) root.files.setSort(modelData.field);
                    }
                }
            }
            Rectangle { Layout.fillWidth: true; height: 1; color: Qt.alpha(Appearance.colors.colOutlineVariant, 0.25) }
            MenuActionRow {
                labelText: ((root.files?.dirsFirst ?? true) ? "✓  " : "    ") + Translation.tr("Folders first")
                onClicked: { root.sortMenuOpen = false; if (root.files) root.files.toggleDirsFirst(); }
            }
        }
    }

    // ── Context Menu Popup (Standard + Archive + 4 Alis Actions) ────────────
    Rectangle {
        visible: root.contextMenuOpen
        z: 50
        x: root.contextMenuX
        y: root.contextMenuY
        width: 232
        height: Math.min(root.height - 24, ctxCol.implicitHeight + 12)
        radius: 14
        color: Appearance.colors.colLayer2
        border.width: 1
        border.color: Qt.alpha(Appearance.colors.colOutlineVariant, 0.45)

        Flickable {
            anchors.fill: parent
            anchors.margins: 6
            contentHeight: ctxCol.implicitHeight
            clip: true

            ColumnLayout {
                id: ctxCol
                width: parent.width
                spacing: 2

                // Background actions
                MenuActionRow {
                    visible: !root.contextEntry && !(root.files?.activeIsTrash ?? false)
                    labelText: Translation.tr("New Folder")
                    onClicked: root.beginPrompt("mkdir", "", "New Folder")
                }
                MenuActionRow {
                    visible: !root.contextEntry && !(root.files?.activeIsTrash ?? false)
                    labelText: Translation.tr("New File")
                    onClicked: root.beginPrompt("mkfile", "", "untitled.txt")
                }
                MenuActionRow {
                    visible: !root.contextEntry && !(root.files?.activeIsTrash ?? false) && (root.files?.clipboardPaths ?? []).length > 0
                    labelText: Translation.tr("Paste Here")
                    onClicked: { root.contextMenuOpen = false; if (root.files) root.files.paste(); }
                }
                MenuActionRow {
                    visible: !root.contextEntry && !(root.files?.activeIsTrash ?? false)
                    labelText: Translation.tr("Open Terminal Here")
                    onClicked: { root.contextMenuOpen = false; if (root.files) root.files.runAlisAction("terminal", [root.activePath]); }
                }
                MenuActionRow {
                    visible: !root.contextEntry && !(root.files?.activeIsTrash ?? false)
                    labelText: Translation.tr("Add Folder to Bookmarks")
                    onClicked: { root.contextMenuOpen = false; if (root.files) root.files.addBookmark(root.activePath); }
                }
                MenuActionRow {
                    visible: !root.contextEntry
                    labelText: Translation.tr("Properties (Alt+Enter)")
                    onClicked: root.openPropertiesForSelection()
                }
                MenuActionRow {
                    visible: !root.contextEntry && (root.files?.activeIsTrash ?? false)
                    labelText: Translation.tr("Empty Trash")
                    textColor: Appearance.colors.colError
                    onClicked: root.beginPrompt("confirmEmptyTrash", "", "")
                }

                // Item actions
                MenuActionRow {
                    visible: root.contextEntry !== null
                    labelText: (root.contextEntry?.is_dir ?? false) ? Translation.tr("Open") : Translation.tr("Open with Default App")
                    onClicked: { root.contextMenuOpen = false; root.activateItem(root.contextEntry); }
                }
                MenuActionRow {
                    visible: Boolean(root.contextEntry?.is_dir)
                    labelText: Translation.tr("Open in New Tab")
                    onClicked: { root.contextMenuOpen = false; if (root.files) root.files.newTab(String(root.contextEntry.path)); }
                }
                MenuActionRow {
                    visible: root.contextEntry !== null && !Boolean(root.contextEntry?.is_dir)
                    labelText: Translation.tr("Quick Look (Alt+Space)")
                    onClicked: { root.contextMenuOpen = false; if (root.files) root.files.openQuickLook(root.contextEntry); }
                }
                MenuActionRow {
                    visible: root.contextEntry !== null
                    labelText: Translation.tr("Properties (Alt+Enter)")
                    onClicked: root.openPropertiesForSelection()
                }

                // Exclusive Alis Actions
                MenuActionRow {
                    visible: Boolean(root.contextEntry?.supports_wallpaper)
                    labelText: Translation.tr("Set as Alis Wallpaper")
                    onClicked: { root.contextMenuOpen = false; if (root.files) root.files.runAlisAction("wallpaper", [String(root.contextEntry.path)]); }
                }
                MenuActionRow {
                    visible: Boolean(root.contextEntry?.supports_local_music)
                    labelText: Translation.tr("Play in Alis Local Music")
                    onClicked: { root.contextMenuOpen = false; if (root.files) root.files.runAlisAction("local_music", root.selectedPaths); }
                }
                MenuActionRow {
                    visible: Boolean(root.contextEntry?.is_dir)
                    labelText: Translation.tr("Open Terminal Here")
                    onClicked: { root.contextMenuOpen = false; if (root.files) root.files.runAlisAction("terminal", [String(root.contextEntry.path)]); }
                }
                MenuActionRow {
                    visible: Boolean(root.contextEntry?.supports_nexus)
                    labelText: Translation.tr("Open / Send to Nexus")
                    onClicked: { root.contextMenuOpen = false; if (root.files) root.files.runAlisAction("nexus", [String(root.contextEntry.path)]); }
                }
                MenuActionRow {
                    visible: root.contextEntry !== null && !Boolean(root.contextEntry?.is_dir)
                    labelText: Translation.tr("Send to Alis Companion")
                    onClicked: { root.contextMenuOpen = false; if (root.files) root.files.runAlisAction("companion", root.selectedPaths); }
                }

                // File ops
                MenuActionRow {
                    visible: root.contextEntry !== null && !(root.files?.activeIsTrash ?? false)
                    labelText: Translation.tr("Cut")
                    onClicked: { root.contextMenuOpen = false; if (root.files) root.files.cutPaths(root.selectedPaths); }
                }
                MenuActionRow {
                    visible: root.contextEntry !== null && !(root.files?.activeIsTrash ?? false)
                    labelText: Translation.tr("Copy")
                    onClicked: { root.contextMenuOpen = false; if (root.files) root.files.copyPaths(root.selectedPaths); }
                }
                MenuActionRow {
                    visible: root.contextEntry !== null && !(root.files?.activeIsTrash ?? false)
                    labelText: Translation.tr("Rename (F2)")
                    onClicked: root.beginPrompt("rename", String(root.contextEntry.path), String(root.contextEntry.name))
                }
                MenuActionRow {
                    visible: root.contextEntry !== null && !(root.files?.activeIsTrash ?? false)
                    labelText: Translation.tr("Compress…")
                    onClicked: root.beginPrompt("compress", "", String(root.contextEntry.name || "archive"))
                }
                MenuActionRow {
                    visible: Boolean(root.contextEntry?.is_extractable) && !(root.files?.activeIsTrash ?? false)
                    labelText: Translation.tr("Extract Here")
                    onClicked: { root.contextMenuOpen = false; if (root.files) root.files.extractArchive(String(root.contextEntry.path), true); }
                }
                MenuActionRow {
                    visible: root.contextEntry !== null && !(root.files?.activeIsTrash ?? false)
                    labelText: Translation.tr("Move to Trash")
                    onClicked: { root.contextMenuOpen = false; if (root.files) root.files.trashPaths(root.selectedPaths); }
                }
                MenuActionRow {
                    visible: root.contextEntry !== null && (root.files?.activeIsTrash ?? false)
                    labelText: Translation.tr("Restore from Trash")
                    onClicked: { root.contextMenuOpen = false; if (root.files) root.files.restorePaths(root.selectedPaths); }
                }
                MenuActionRow {
                    visible: root.contextEntry !== null
                    labelText: Translation.tr("Delete Permanently")
                    textColor: Appearance.colors.colError
                    onClicked: {
                        if (root.files?.confirmPermanentDelete ?? true)
                            root.beginPrompt("confirmDelete", "", "");
                        else {
                            root.contextMenuOpen = false;
                            if (root.files) root.files.deletePaths(root.selectedPaths);
                        }
                    }
                }
            }
        }
    }

    // ── Inline Prompt / Confirmation Sheet ─────────────────────────────────
    Item {
        visible: root.promptMode.length > 0
        anchors.fill: parent
        z: 60

        MouseArea {
            anchors.fill: parent
            onClicked: {
                root.promptMode = "";
                root.focusPrimarySurface();
            }
        }

        Rectangle {
            anchors.fill: promptCard
            anchors.margins: -3
            anchors.topMargin: -1
            anchors.bottomMargin: -6
            radius: 19
            color: Qt.alpha("#000000", 0.22)
        }

        Rectangle {
            id: promptCard
            anchors.centerIn: parent
            width: Math.min(420, parent.width - 40)
            height: promptCol.implicitHeight + 32
            radius: 16
            color: Appearance.colors.colLayer2
            border.width: 1
            border.color: Qt.alpha(Appearance.colors.colOutlineVariant, 0.65)

            MouseArea { anchors.fill: parent }

            ColumnLayout {
                id: promptCol
                anchors.fill: parent
                anchors.margins: 16
                spacing: 12

                StyledText {
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    text: {
                        if (root.promptMode === "mkdir") return Translation.tr("New Folder");
                        if (root.promptMode === "mkfile") return Translation.tr("New File");
                        if (root.promptMode === "create") return Translation.tr("Create (end with / for folder)");
                        if (root.promptMode === "rename") return Translation.tr("Rename");
                        if (root.promptMode === "compress") return Translation.tr("Compress");
                        if (root.promptMode === "confirmEmptyTrash") return Translation.tr("Empty Trash");
                        return Translation.tr("Delete Permanently");
                    }
                }

                StyledText {
                    visible: root.promptMode === "confirmDelete" || root.promptMode === "confirmEmptyTrash"
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: root.promptMode === "confirmEmptyTrash"
                        ? Translation.tr("Permanently delete every item in the Trash?")
                        : Translation.tr("Permanently delete %1 selected item(s)? This cannot be undone.").arg(root.actionPaths().length)
                }

                Rectangle {
                    visible: root.promptMode !== "confirmDelete" && root.promptMode !== "confirmEmptyTrash"
                    Layout.fillWidth: true
                    height: 36
                    radius: 10
                    color: Appearance.colors.colLayer0
                    border.width: 1
                    border.color: Appearance.colors.colPrimary
                    TextField {
                        id: promptField
                        objectName: "alisFilesPromptInput"
                        anchors.fill: parent
                        anchors.leftMargin: 8; anchors.rightMargin: 8
                        background: null
                        color: Appearance.colors.colOnSurface
                        placeholderText: root.promptMode === "create" ? Translation.tr("notes.txt or folder/") : ""
                        placeholderTextColor: Appearance.colors.colSubtext
                        text: root.promptInputText
                        Keys.onEscapePressed: event => {
                            if (root.handleEscape())
                                event.accepted = true;
                        }
                        onTextChanged: root.promptInputText = text
                        onAccepted: root.submitPrompt()
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Item { Layout.fillWidth: true }
                    DialogButton {
                        buttonText: Translation.tr("Cancel")
                        onClicked: { root.promptMode = ""; root.focusPrimarySurface(); }
                    }
                    DialogButton {
                        buttonText: (root.promptMode === "confirmDelete" || root.promptMode === "confirmEmptyTrash")
                            ? Translation.tr("Delete") : Translation.tr("Confirm")
                        onClicked: root.submitPrompt()
                    }
                }
            }
        }
    }

    // ── Instant Quick Look Dark #0b0b0d Cinema Overlay (Space) ───────────────
    Rectangle {
        visible: root.files?.quickLookEntry !== null
        anchors.fill: parent
        z: 70
        radius: 18
        color: "#f20b0b0d"

        MouseArea { anchors.fill: parent }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    StyledText {
                        text: String(root.files?.quickLookEntry?.name ?? "")
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.DemiBold
                        color: "#f4f5f7"
                        elide: Text.ElideMiddle
                    }
                    StyledText {
                        text: String(root.files?.quickLookEntry?.kind_label ?? "") + "  •  " + String(root.files?.quickLookEntry?.size_label ?? "")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: "#b8bac2"
                    }
                }
                DialogButton {
                    buttonText: Translation.tr("Open")
                    onClicked: {
                        const p = String(root.files?.quickLookEntry?.path ?? "");
                        if (root.files) {
                            root.files.closeQuickLook();
                            root.files.openExternal(p);
                        }
                    }
                }
                RippleButton {
                    implicitWidth: 32; implicitHeight: 32; buttonRadius: 16
                    colBackground: Qt.alpha("#ffffff", 0.08)
                    colBackgroundHover: Qt.alpha("#ffffff", 0.16)
                    contentItem: MaterialSymbol { anchors.centerIn: parent; text: "close"; iconSize: 18; color: "#f4f5f7" }
                    onClicked: if (root.files) root.files.closeQuickLook()
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                readonly property string qlPath: String(root.files?.quickLookEntry?.path ?? "")
                readonly property string qlKind: String(root.files?.quickLookEntry?.kind ?? "")
                readonly property string qlThumb: String(root.files?.thumbMap?.[qlPath] ?? "")

                Image {
                    anchors.fill: parent
                    anchors.margins: 28
                    visible: parent.qlKind === "Image" || parent.qlThumb.length > 0
                    source: parent.qlKind === "Image" ? ("file://" + parent.qlPath)
                        : (parent.qlThumb.length > 0 ? ("file://" + parent.qlThumb) : "")
                    sourceSize.width: 1600
                    sourceSize.height: 1200
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    cache: false
                }

                ScrollView {
                    anchors.fill: parent
                    anchors.margins: 24
                    visible: parent.qlKind === "Text" || parent.qlKind === "Code" || parent.qlKind === "Markdown"
                    TextArea {
                        id: quickLookTextArea
                        readOnly: true
                        text: String(root.files?.quickLookText ?? "")
                        color: "#f4f5f7"
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: 13
                        wrapMode: TextArea.Wrap
                        background: Rectangle { radius: 12; color: "#15161a" }
                    }
                }

                ColumnLayout {
                    anchors.centerIn: parent
                    visible: parent.qlKind !== "Image" && parent.qlKind !== "Text" && parent.qlKind !== "Code" && parent.qlKind !== "Markdown" && parent.qlThumb.length === 0
                    spacing: 10
                    AlisFileArt {
                        Layout.alignment: Qt.AlignHCenter
                        entry: root.files?.quickLookEntry
                        artSize: 88
                        kindIcon: root.iconForEntry(root.files?.quickLookEntry)
                    }
                    StyledText { Layout.alignment: Qt.AlignHCenter; text: String(root.files?.quickLookEntry?.name ?? ""); color: "#f4f5f7"; font.weight: Font.DemiBold }
                }

                RippleButton {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: 36; implicitHeight: 36; buttonRadius: 18
                    colBackground: Qt.alpha("#ffffff", 0.08)
                    colBackgroundHover: Qt.alpha("#ffffff", 0.16)
                    contentItem: MaterialSymbol { anchors.centerIn: parent; text: "chevron_left"; iconSize: 22; color: "#f4f5f7" }
                    onClicked: if (root.files) root.files.stepQuickLook(-1)
                }
                RippleButton {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: 36; implicitHeight: 36; buttonRadius: 18
                    colBackground: Qt.alpha("#ffffff", 0.08)
                    colBackgroundHover: Qt.alpha("#ffffff", 0.16)
                    contentItem: MaterialSymbol { anchors.centerIn: parent; text: "chevron_right"; iconSize: 22; color: "#f4f5f7" }
                    onClicked: if (root.files) root.files.stepQuickLook(1)
                }
            }
        }
    }
}
