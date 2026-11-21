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
    property var nexus: null

    readonly property bool open: Boolean(root.nexus && root.nexus.isOpen)
    readonly property bool overlayOpen: Boolean(root.open && root.nexus.overlayMode)
    readonly property bool hostedByAbyssPerimeter: (Config.options?.panelFamily ?? "abyss") === "abyss"
        && Boolean(GlobalStates.abyssPerimeterActive)
    property bool _workspaceWarmed: false
    property bool _overlayWarmed: false
    property bool _floatingWarmed: false
    property bool _closeAnimRunning: false
    property real _surfaceReveal: 0
    Component.onCompleted: {
        if (root.open)
            root._workspaceWarmed = true;
        if (overlayOpen) {
            _overlayWarmed = true;
            _surfaceReveal = 1;
        }
        if (floatingOpen)
            _floatingWarmed = true;
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
        if (overlayOpen) {
            _workspaceWarmed = true;
            _overlayWarmed = true;
            _closeAnimRunning = false;
            closeAnimTimer.stop();
            _surfaceReveal = 0;
            Qt.callLater(() => {
                if (root.overlayOpen)
                    root._surfaceReveal = 1;
            });
        } else if (_overlayWarmed) {
            _surfaceReveal = 0;
            _closeAnimRunning = true;
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
            WlrLayershell.namespace: "quickshell:nexusOverlay"
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

            // Dim only the workspace inside the Screen Edge perimeter, with a cutout for the bottom-docked Nexus card
            SettingsWorkspaceScrim {
                id: scrimBg
                anchors.fill: parent
                outputName: String(overlayWindow.screen?.name ?? "")
                cardRect: Qt.rect(overlayCard.x, overlayCard.y, overlayCard.width, overlayCard.height)
                cardRadius: overlayCard.radius
                dim: root.overlayOpen
                    ? (Config.options?.settingsUi?.overlayAppearance?.scrimDim ?? 35) / 100 : 0
            }

            // Click-outside-to-close hit area
            MouseArea {
                anchors.fill: parent
                visible: root.overlayOpen
                enabled: !GlobalStates.settingsNativeDialogOpen && !GlobalStates.regionSelectorOpen && !GlobalStates.annotationEditorOpen && !PolkitService.active
                onClicked: {
                    if (root.nexus)
                        root.nexus.close();
                }
            }

            // Bottom-connected Screen Edge surface with concave fillets (matches SettingsOverlay)
            ConnectedSurfaceAbyssEdgeSurface {
                id: nexusAbyssSurface
                objectName: "nexusBottomEdgeSurface"
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
                objectName: "nexusOverlayCard"
                z: 2
                readonly property real waffleBarReserve: (Config.options?.panelFamily === "waffle"
                    && (GlobalStates.barOpen ?? true)) ? 48 : 0
                readonly property real waffleWorkTop: (overlayCard.waffleBarReserve > 0
                    && !(Config.options?.waffles?.bar?.bottom ?? true)) ? overlayCard.waffleBarReserve : 0
                readonly property real waffleWorkHeight: Math.max(0, overlayWindow.height - overlayCard.waffleBarReserve)

                readonly property real targetWidth: Math.round(Math.min(
                    1600,
                    Math.max(900, overlayWindow.width * 0.90),
                    Math.max(400, overlayWindow.width - 48)))
                readonly property real targetHeight: Math.round(Math.min(
                    1080,
                    Math.max(720, overlayWindow.height * 0.88),
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
                    anchors.topMargin: 8
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    anchors.bottomMargin: 8
                    function _syncOverlaySource(): void {
                        if (shouldLoad) {
                            if (source.toString().length === 0) {
                                setSource(Qt.resolvedUrl("NexusWorkspace.qml"), {
                                    transitionSettled: root.overlayOpen && Math.abs(root._surfaceReveal - 1) < 0.02
                                });
                            }
                        } else if (source.toString().length > 0) {
                            source = "";
                        }
                    }
                    Component.onCompleted: _syncOverlaySource()
                    onShouldLoadChanged: _syncOverlaySource()
                    onLoaded: {
                        if (item) {
                            item.nexus = Qt.binding(() => root.nexus);
                            if (item.bottomDocked !== undefined)
                                item.bottomDocked = Qt.binding(() => Config.options?.panelFamily !== "waffle");
                            if (item.transitionSettled !== undefined)
                                item.transitionSettled = Qt.binding(() => root.overlayOpen && Math.abs(root._surfaceReveal - 1) < 0.02);
                            item.forceActiveFocus();
                        }
                    }
                }

                AlisLoadingScreen {
                    objectName: "nexusOverlayLoadingScreen"
                    anchors.fill: parent
                    anchors.margins: 8
                    z: 20
                    loading: root.overlayOpen && overlayWorkspaceLoader.status !== Loader.Ready
                    title: Translation.tr("Nexus")
                    icon: "hub"
                    fillSurface: true
                    backdropOpacity: 0.88
                    surfaceRadius: Math.max(0, overlayCard.radius - 4)
                }
            }
            readonly property bool workspaceLoaded: overlayWorkspaceLoader.status === Loader.Ready && overlayWorkspaceLoader.item !== null
        }
    }

    readonly property bool floatingOpen: Boolean(root.open && !root.nexus.overlayMode)
    onFloatingOpenChanged: {
        if (floatingOpen) {
            _workspaceWarmed = true;
            _floatingWarmed = true;
        }
    }

    Loader {
        id: floatingHostLoader
        active: Boolean(root.floatingOpen || root._floatingWarmed)
        sourceComponent: FloatingWindow {
            id: floatingWindow
            objectName: "nexusFloatingWindow"
            visible: root.floatingOpen
            title: "Alis Nexus"
            color: Appearance.m3colors.m3background
            readonly property int screenWidth: Screen.width > 0 ? Screen.width : 1920
            readonly property int screenHeight: Screen.height > 0 ? Screen.height : 1080
            implicitWidth: Math.min(1600, Math.max(900, Math.round(screenWidth * 0.90)))
            implicitHeight: Math.min(1080, Math.max(720, Math.round(screenHeight * 0.92)))
            minimumSize: Qt.size(750, 500)

            onClosed: {
                if (root.nexus)
                    root.nexus.close();
            }

            Rectangle {
                anchors.fill: parent
                color: Appearance.m3colors.m3background

                Loader {
                    id: floatingWorkspaceLoader
                    active: (root.open || root._workspaceWarmed) && (root.floatingOpen || root._floatingWarmed)
                    asynchronous: Quickshell.env("QT_QUICK_BACKEND") !== "software"
                    anchors.fill: parent
                    anchors.margins: 10
                    source: Qt.resolvedUrl("NexusWorkspace.qml")
                    onLoaded: {
                        if (item) {
                            item.nexus = Qt.binding(() => root.nexus);
                            if (item.bottomDocked !== undefined)
                                item.bottomDocked = false;
                            item.forceActiveFocus();
                        }
                    }
                }

                AlisLoadingScreen {
                    objectName: "nexusFloatingLoadingScreen"
                    anchors.fill: parent
                    anchors.margins: 10
                    z: 20
                    loading: root.floatingOpen && floatingWorkspaceLoader.status !== Loader.Ready
                    title: Translation.tr("Nexus")
                    icon: "hub"
                    fillSurface: true
                    backdropOpacity: 0.90
                }
            }
            readonly property bool workspaceLoaded: floatingWorkspaceLoader.status === Loader.Ready && floatingWorkspaceLoader.item !== null
        }
    }

    readonly property bool workspaceLoaded: Boolean(
        (root.hostedByAbyssPerimeter && root.overlayOpen)
        || (overlayHostLoader.item && overlayHostLoader.item.workspaceLoaded)
        || (floatingHostLoader.item && floatingHostLoader.item.workspaceLoaded)
    )
}
