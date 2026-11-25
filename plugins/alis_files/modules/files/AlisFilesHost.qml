import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Wayland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.perimeter
import qs.modules.settings

Item {
    id: root
    property var files: null

    readonly property bool open: Boolean(root.files && root.files.isOpen)
    readonly property bool overlayOpen: Boolean(root.open && root.files.overlayMode)
    readonly property bool hostedByAbyssPerimeter: (Config.options?.panelFamily ?? "abyss") === "abyss"
        && Boolean(GlobalStates.abyssPerimeterActive)
    property bool _workspaceWarmed: false
    property bool _overlayWarmed: false
    property bool _closeAnimRunning: false
    property real _surfaceReveal: 0

    Component.onCompleted: {
        if (root.open)
            root._workspaceWarmed = true;
        if (root.overlayOpen) {
            root._overlayWarmed = true;
            root._surfaceReveal = 1;
        }
    }

    onOpenChanged: {
        if (root.open)
            root._workspaceWarmed = true;
    }

    readonly property real _screenEdgeThickness: Config.options?.panelFamily === "abyss"
        ? Math.max(1, Math.min(32, Math.round(Config.options?.abyss?.perimeter?.thickness ?? Config.options?.appearance?.screenEdge?.width ?? 10)))
        : Math.max(1, Math.min(32, Math.round(Config.options?.appearance?.screenEdge?.width ?? 10)))

    Behavior on _surfaceReveal {
        enabled: Appearance.animationsEnabled
        NumberAnimation {
            duration: SurfaceMotion.duration
            easing.type: SurfaceMotion.easingType
        }
    }

    onOverlayOpenChanged: {
        if (root.overlayOpen) {
            root._workspaceWarmed = true;
            root._overlayWarmed = true;
            root._closeAnimRunning = false;
            closeAnimTimer.stop();
            root._surfaceReveal = 0;
            Qt.callLater(() => {
                if (root.overlayOpen)
                    root._surfaceReveal = 1;
            });
        } else if (root._overlayWarmed) {
            root._surfaceReveal = 0;
            root._closeAnimRunning = true;
            closeAnimTimer.restart();
        }
    }

    Timer {
        id: closeAnimTimer
        interval: SurfaceMotion.duration + 40
        repeat: false
        onTriggered: root._closeAnimRunning = false
    }

    Loader {
        id: overlayHostLoader
        active: !root.hostedByAbyssPerimeter && (root._overlayWarmed || root.overlayOpen || root._closeAnimRunning)
        sourceComponent: PanelWindow {
            id: overlayWindow
            visible: root.overlayOpen || root._closeAnimRunning
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:alisFilesOverlay"
            WlrLayershell.layer: (GlobalStates.settingsNativeDialogOpen || GlobalStates.regionSelectorOpen || GlobalStates.annotationEditorOpen || PolkitService.active) ? WlrLayer.Bottom : WlrLayer.Overlay
            WlrLayershell.keyboardFocus: root.overlayOpen
                && !GlobalStates.settingsNativeDialogOpen && !GlobalStates.regionSelectorOpen && !GlobalStates.annotationEditorOpen && !PolkitService.active
                ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
            color: "transparent"
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            SettingsWorkspaceScrim {
                id: scrimBg
                anchors.fill: parent
                outputName: String(overlayWindow.screen?.name ?? "")
                cardRect: Qt.rect(overlayCard.x, overlayCard.y, overlayCard.width, overlayCard.height)
                cardRadius: overlayCard.radius
                dim: root.overlayOpen
                    ? (Config.options?.settingsUi?.overlayAppearance?.scrimDim ?? 35) / 100 : 0
            }

            MouseArea {
                anchors.fill: parent
                visible: root.overlayOpen
                enabled: !GlobalStates.settingsNativeDialogOpen && !GlobalStates.regionSelectorOpen && !GlobalStates.annotationEditorOpen && !PolkitService.active
                onClicked: {
                    if (root.files)
                        root.files.close();
                }
            }

            ConnectedSurfaceAbyssEdgeSurface {
                id: filesAbyssSurface
                objectName: "alisFilesBottomEdgeSurface"
                visible: Config.options?.panelFamily !== "waffle"
                z: 1
                anchors.fill: parent
                edge: "bottom"
                ownerThickness: root._screenEdgeThickness
                outputRect: Qt.rect(0, 0, overlayWindow.width, overlayWindow.height)
                bodyRect: Qt.rect(overlayCard.x, overlayCard.y, overlayCard.width, overlayCard.height)
                bodyRadius: overlayCard.radius
                fillColor: overlayCard.surfaceFillColor
                progress: root.overlayOpen || root._closeAnimRunning ? 1 : 0
                shadowEnabled: Config.options?.appearance?.screenEdge?.physicalShadow?.enabled ?? true
                shadowExtent: Math.max(0, Math.min(32,
                    Math.round(Config.options?.appearance?.screenEdge?.physicalShadow?.size ?? 15)))
                shadowColor: Qt.alpha(Appearance.m3colors.m3shadow,
                    Math.max(0, Math.min(1.0,
                        Number(Config.options?.appearance?.screenEdge?.physicalShadow?.opacity ?? 0.70))))
            }

            Rectangle {
                id: overlayCard
                objectName: "alisFilesOverlayCard"
                z: 2
                readonly property real waffleBarReserve: (Config.options?.panelFamily === "waffle"
                    && (GlobalStates.barOpen ?? true)) ? 48 : 0
                readonly property real waffleWorkTop: (overlayCard.waffleBarReserve > 0
                    && !(Config.options?.waffles?.bar?.bottom ?? true)) ? overlayCard.waffleBarReserve : 0
                readonly property real waffleWorkHeight: Math.max(0, overlayWindow.height - overlayCard.waffleBarReserve)

                readonly property real targetWidth: Math.round(Math.min(
                    1600,
                    Math.max(880, overlayWindow.width * 0.88),
                    Math.max(400, overlayWindow.width - 48)))
                readonly property real targetHeight: Math.round(Math.min(
                    1000,
                    Math.max(660, overlayWindow.height * 0.84),
                    Math.max(400, (Config.options?.panelFamily === "waffle"
                        ? overlayCard.waffleWorkHeight : overlayWindow.height) - 64)))
                readonly property color surfaceFillColor: Appearance.colors.colLayer0

                width: targetWidth
                height: targetHeight
                anchors.horizontalCenter: parent.horizontalCenter
                y: Config.options?.panelFamily === "waffle"
                    ? overlayCard.waffleWorkTop + Math.round((overlayCard.waffleWorkHeight - height) / 2)
                    : overlayWindow.height - root._screenEdgeThickness - height
                        + (1 - root._surfaceReveal) * height
                radius: Appearance.rounding.windowRounding ?? 16
                bottomLeftRadius: Config.options?.panelFamily === "waffle" ? radius : 0
                bottomRightRadius: Config.options?.panelFamily === "waffle" ? radius : 0
                color: Config.options?.panelFamily === "waffle" ? surfaceFillColor : "transparent"
                border.width: 0
                border.color: "transparent"
                clip: true

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.AllButtons
                    onPressed: mouse => mouse.accepted = true
                }

                Loader {
                    id: overlayWorkspaceLoader
                    readonly property bool shouldLoad: (root.open || root._workspaceWarmed) && (root.overlayOpen || root._overlayWarmed)
                    asynchronous: Quickshell.env("QT_QUICK_BACKEND") !== "software"
                    anchors.fill: parent
                    anchors.margins: 8
                    function _syncSource(): void {
                        if (shouldLoad) {
                            if (source.toString().length === 0) {
                                setSource(Qt.resolvedUrl("AlisFilesOverlayWorkspace.qml"), {
                                    transitionSettled: root.overlayOpen && Math.abs(root._surfaceReveal - 1) < 0.02
                                });
                            }
                        } else if (source.toString().length > 0) {
                            source = "";
                        }
                    }
                    Component.onCompleted: _syncSource()
                    onShouldLoadChanged: _syncSource()
                    onLoaded: {
                        if (item) {
                            item.files = Qt.binding(() => root.files);
                            if (item.bottomDocked !== undefined)
                                item.bottomDocked = Qt.binding(() => Config.options?.panelFamily !== "waffle");
                            if (item.transitionSettled !== undefined)
                                item.transitionSettled = Qt.binding(() => root.overlayOpen && Math.abs(root._surfaceReveal - 1) < 0.02);
                            if (typeof item.focusPrimarySurface === "function")
                                item.focusPrimarySurface();
                            else
                                item.forceActiveFocus();
                        }
                    }
                }
            }
        }
    }
}
