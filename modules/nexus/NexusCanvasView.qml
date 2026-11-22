import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

Rectangle {
    id: canvasRoot
    property var nexus: null
    property var settledColors: null

    property var canvasNodes: []
    property var canvasEdges: []
    property real panX: 0
    property real panY: 0
    property real zoom: 1.0
    property string selectedNodeId: ""
    property string editingNodeId: ""
    property string linkSourceNodeId: ""
    property bool dirty: false
    property int _nodeSeq: 1

    color: settledColors?.colLayer0 ?? Appearance.colors.colLayer0
    radius: 12
    clip: true

    readonly property var doc: nexus?.currentDoc ?? null

    onDocChanged: reloadFromDoc()
    Component.onCompleted: reloadFromDoc()

    function reloadFromDoc(): void {
        if (!doc || String(doc.category ?? "") !== "canvas")
            return;
        try {
            const parsed = JSON.parse(String(doc.content || "{}"));
            canvasNodes = Array.isArray(parsed.nodes) ? parsed.nodes.map(n => Object.assign({}, n)) : [];
            canvasEdges = Array.isArray(parsed.edges) ? parsed.edges.map(e => Object.assign({}, e)) : [];
            dirty = false;
            fitView();
            edgeCanvas.requestPaint();
        } catch (e) {
            canvasNodes = [];
            canvasEdges = [];
        }
    }

    function fitView(): void {
        if (canvasNodes.length === 0) {
            panX = viewport.width * 0.5;
            panY = viewport.height * 0.5;
            zoom = 1.0;
            return;
        }
        let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
        for (let i = 0; i < canvasNodes.length; ++i) {
            const n = canvasNodes[i];
            const nx = Number(n.x || 0), ny = Number(n.y || 0);
            const nw = Number(n.width || 220), nh = Number(n.height || 100);
            minX = Math.min(minX, nx);
            minY = Math.min(minY, ny);
            maxX = Math.max(maxX, nx + nw);
            maxY = Math.max(maxY, ny + nh);
        }
        const cw = Math.max(100, maxX - minX + 80);
        const ch = Math.max(100, maxY - minY + 80);
        const fitZ = Math.max(0.25, Math.min(1.25, Math.min(viewport.width / cw, viewport.height / ch)));
        zoom = fitZ;
        panX = viewport.width * 0.5 - ((minX + maxX) * 0.5) * zoom;
        panY = viewport.height * 0.5 - ((minY + maxY) * 0.5) * zoom;
        edgeCanvas.requestPaint();
    }

    function addCard(kind: string): void {
        const cx = (viewport.width * 0.5 - panX) / zoom - 110 + (canvasNodes.length % 5) * 24;
        const cy = (viewport.height * 0.5 - panY) / zoom - 55 + (canvasNodes.length % 4) * 24;
        const nid = "node-" + Date.now() + "-" + (_nodeSeq++);
        let obj;
        if (kind === "group") {
            obj = { "id": nid, "type": "group", "label": "Group", "x": cx - 40, "y": cy - 30, "width": 360, "height": 220, "color": "5" };
        } else if (kind === "file") {
            const firstNote = (nexus?.recentNotes?.[0]?.relPath) ?? (nexus?.flatFiles?.[0]?.relPath) ?? "";
            obj = { "id": nid, "type": "file", "file": String(firstNote), "x": cx, "y": cy, "width": 240, "height": 110, "color": "4" };
        } else {
            obj = { "id": nid, "type": "text", "text": "New idea...", "x": cx, "y": cy, "width": 220, "height": 110, "color": "4" };
        }
        const next = canvasNodes.slice();
        next.push(obj);
        canvasNodes = next;
        selectedNodeId = nid;
        dirty = true;
        edgeCanvas.requestPaint();
    }

    function deleteSelectedNode(): void {
        if (!selectedNodeId)
            return;
        const rm = selectedNodeId;
        canvasNodes = canvasNodes.filter(n => n.id !== rm);
        canvasEdges = canvasEdges.filter(e => e.fromNode !== rm && e.toNode !== rm);
        selectedNodeId = "";
        dirty = true;
        edgeCanvas.requestPaint();
    }

    function connectNodes(fromId: string, toId: string): void {
        if (!fromId || !toId || fromId === toId)
            return;
        const dup = canvasEdges.some(e => e.fromNode === fromId && e.toNode === toId);
        if (dup)
            return;
        const next = canvasEdges.slice();
        next.push({
            "id": "edge-" + Date.now() + "-" + (_nodeSeq++),
            "fromNode": fromId,
            "fromSide": "right",
            "toNode": toId,
            "toSide": "left"
        });
        canvasEdges = next;
        dirty = true;
        edgeCanvas.requestPaint();
    }

    function saveCanvas(): void {
        if (!nexus || !nexus.currentPath)
            return;
        nexus.saveCanvasFile(nexus.currentPath, { "nodes": canvasNodes, "edges": canvasEdges });
        dirty = false;
    }

    function nodeAccent(colorCode: string): color {
        switch (String(colorCode ?? "")) {
        case "1": return "#f87171";
        case "2": return "#fb923c";
        case "3": return "#facc15";
        case "4": return settledColors?.colPrimary ?? Appearance.colors.colPrimary;
        case "5": return "#38bdf8";
        case "6": return "#c084fc";
        default: return settledColors?.colPrimary ?? Appearance.colors.colPrimary;
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // Top toolbar
        Rectangle {
            Layout.fillWidth: true
            height: 44
            color: settledColors?.colLayer1 ?? Appearance.colors.colLayer1

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 8

                MaterialSymbol {
                    text: "dashboard_customize"
                    iconSize: 18
                    color: canvasRoot.settledColors?.colPrimary ?? Appearance.colors.colPrimary
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: (doc?.title ?? "Canvas") + (canvasRoot.dirty ? " *" : "") + " · " + canvasRoot.canvasNodes.length + " nodes"
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: canvasRoot.settledColors?.colOnLayer1 ?? Appearance.colors.colOnLayer1
                    elide: Text.ElideRight
                }

                Repeater {
                    model: [
                        { "label": "+ Card", "kind": "text" },
                        { "label": "+ Note", "kind": "file" },
                        { "label": "+ Group", "kind": "group" }
                    ]
                    delegate: Rectangle {
                        required property var modelData
                        height: 28; width: 68; radius: 8
                        color: canvasRoot.settledColors?.colSecondaryContainer ?? Appearance.colors.colSecondaryContainer
                        StyledText {
                            anchors.centerIn: parent
                            text: modelData.label
                            horizontalAlignment: Text.AlignHCenter
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: canvasRoot.settledColors?.colPrimary ?? Appearance.colors.colPrimary
                        }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: canvasRoot.addCard(modelData.kind) }
                    }
                }

                Rectangle {
                    visible: canvasRoot.selectedNodeId.length > 0
                    height: 28; width: 64; radius: 8
                    color: canvasRoot.settledColors?.colLayer2 ?? Appearance.colors.colLayer2
                    StyledText {
                        anchors.centerIn: parent
                        text: canvasRoot.linkSourceNodeId === canvasRoot.selectedNodeId ? "Pick Target" : "Link Edge"
                        horizontalAlignment: Text.AlignHCenter
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: canvasRoot.settledColors?.colOnLayer1 ?? Appearance.colors.colOnLayer1
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: canvasRoot.linkSourceNodeId = canvasRoot.linkSourceNodeId ? "" : canvasRoot.selectedNodeId
                    }
                }

                Rectangle {
                    visible: canvasRoot.selectedNodeId.length > 0
                    height: 28; width: 52; radius: 8
                    color: canvasRoot.settledColors?.colLayer0 ?? Appearance.colors.colLayer0
                    StyledText {
                        anchors.centerIn: parent
                        text: "Delete"
                        horizontalAlignment: Text.AlignHCenter
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: canvasRoot.settledColors?.colError ?? "#ef4444"
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: canvasRoot.deleteSelectedNode() }
                }

                Rectangle {
                    height: 28; width: 44; radius: 8
                    color: canvasRoot.settledColors?.colLayer0 ?? Appearance.colors.colLayer0
                    StyledText {
                        anchors.centerIn: parent
                        text: "Fit"
                        horizontalAlignment: Text.AlignHCenter
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: canvasRoot.settledColors?.colOnLayer1 ?? Appearance.colors.colOnLayer1
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: canvasRoot.fitView() }
                }

                Rectangle {
                    height: 28; width: 62; radius: 8
                    color: canvasRoot.settledColors?.colPrimary ?? Appearance.colors.colPrimary
                    StyledText {
                        anchors.centerIn: parent
                        text: "Save"
                        horizontalAlignment: Text.AlignHCenter
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: Font.DemiBold
                        color: canvasRoot.settledColors?.colOnPrimary ?? Appearance.colors.colOnPrimary
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: canvasRoot.saveCanvas() }
                }
            }
        }

        // Infinite viewport
        Item {
            id: viewport
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            MouseArea {
                anchors.fill: parent
                property real lastX: 0
                property real lastY: 0
                onPressed: mouse => {
                    lastX = mouse.x;
                    lastY = mouse.y;
                    canvasRoot.selectedNodeId = "";
                    canvasRoot.editingNodeId = "";
                }
                onDoubleClicked: canvasRoot.addCard("text")
                onPositionChanged: mouse => {
                    if (pressed) {
                        canvasRoot.panX += mouse.x - lastX;
                        canvasRoot.panY += mouse.y - lastY;
                        lastX = mouse.x;
                        lastY = mouse.y;
                        edgeCanvas.requestPaint();
                    }
                }
                onWheel: wheel => {
                    const factor = wheel.angleDelta.y > 0 ? 1.12 : 0.89;
                    const oldZ = canvasRoot.zoom;
                    const newZ = Math.max(0.25, Math.min(2.5, oldZ * factor));
                    if (Math.abs(newZ - oldZ) > 0.001) {
                        const wx = (wheel.x - canvasRoot.panX) / oldZ;
                        const wy = (wheel.y - canvasRoot.panY) / oldZ;
                        canvasRoot.zoom = newZ;
                        canvasRoot.panX = wheel.x - wx * newZ;
                        canvasRoot.panY = wheel.y - wy * newZ;
                        edgeCanvas.requestPaint();
                    }
                    wheel.accepted = true;
                }
            }

            // Grid + edge arrows layer
            Canvas {
                id: edgeCanvas
                anchors.fill: parent
                renderStrategy: Canvas.Threaded
                renderTarget: Canvas.Image
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.clearRect(0, 0, width, height);
                    const z = canvasRoot.zoom;
                    const px = canvasRoot.panX;
                    const py = canvasRoot.panY;

                    // Subtle dotted grid
                    const step = 32 * z;
                    if (step >= 12) {
                        ctx.fillStyle = String(canvasRoot.settledColors?.colSubtext ?? "#64748b");
                        ctx.globalAlpha = 0.22;
                        const ox = ((px % step) + step) % step;
                        const oy = ((py % step) + step) % step;
                        for (let x = ox; x < width; x += step) {
                            for (let y = oy; y < height; y += step) {
                                ctx.fillRect(x, y, 1.5, 1.5);
                            }
                        }
                        ctx.globalAlpha = 1.0;
                    }

                    const byId = {};
                    for (let i = 0; i < canvasRoot.canvasNodes.length; ++i)
                        byId[canvasRoot.canvasNodes[i].id] = canvasRoot.canvasNodes[i];

                    ctx.strokeStyle = String(canvasRoot.settledColors?.colPrimary ?? Appearance.colors.colPrimary);
                    ctx.fillStyle = ctx.strokeStyle;
                    ctx.lineWidth = Math.max(1.2, 1.8 * z);
                    for (let e = 0; e < canvasRoot.canvasEdges.length; ++e) {
                        const ed = canvasRoot.canvasEdges[e];
                        const a = byId[ed.fromNode];
                        const b = byId[ed.toNode];
                        if (!a || !b) continue;
                        const ax = px + (Number(a.x || 0) + Number(a.width || 220) * 0.5) * z;
                        const ay = py + (Number(a.y || 0) + Number(a.height || 100) * 0.5) * z;
                        const bx = px + (Number(b.x || 0) + Number(b.width || 220) * 0.5) * z;
                        const by = py + (Number(b.y || 0) + Number(b.height || 100) * 0.5) * z;
                        const mx = (ax + bx) * 0.5;
                        ctx.beginPath();
                        ctx.moveTo(ax, ay);
                        ctx.bezierCurveTo(mx, ay, mx, by, bx, by);
                        ctx.stroke();

                        const angle = Math.atan2(by - ay, bx - mx);
                        ctx.beginPath();
                        ctx.arc(bx, by, 4 * Math.max(0.7, z), 0, Math.PI * 2);
                        ctx.fill();
                        if (ed.label) {
                            ctx.font = "11px sans-serif";
                            ctx.textAlign = "center";
                            ctx.fillText(String(ed.label), mx, (ay + by) * 0.5 - 8);
                        }
                    }
                }
            }

            // Nodes layer
            Item {
                x: canvasRoot.panX
                y: canvasRoot.panY
                scale: canvasRoot.zoom
                transformOrigin: Item.TopLeft

                Repeater {
                    model: canvasRoot.canvasNodes
                    delegate: Rectangle {
                        id: cardItem
                        required property var modelData
                        required property int index
                        readonly property bool isGroup: String(modelData.type ?? "") === "group"
                        readonly property bool isSelected: canvasRoot.selectedNodeId === modelData.id
                        readonly property bool isEditing: canvasRoot.editingNodeId === modelData.id
                        readonly property color accentCol: canvasRoot.nodeAccent(modelData.color)

                        x: Number(modelData.x ?? 0)
                        y: Number(modelData.y ?? 0)
                        width: Math.max(120, Number(modelData.width ?? 220))
                        height: Math.max(70, Number(modelData.height ?? 110))
                        z: isGroup ? 1 : (isSelected ? 10 : 5)
                        radius: 10
                        color: isGroup
                            ? Qt.rgba(accentCol.r, accentCol.g, accentCol.b, 0.08)
                            : (canvasRoot.settledColors?.colLayer1 ?? Appearance.colors.colLayer1)
                        border.width: isSelected ? 2 : 1.2
                        border.color: isSelected
                            ? accentCol
                            : Qt.rgba(accentCol.r, accentCol.g, accentCol.b, 0.48)

                        MouseArea {
                            anchors.fill: parent
                            enabled: !cardItem.isEditing
                            property real startX: 0
                            property real startY: 0
                            onPressed: mouse => {
                                if (canvasRoot.linkSourceNodeId && canvasRoot.linkSourceNodeId !== cardItem.modelData.id) {
                                    canvasRoot.connectNodes(canvasRoot.linkSourceNodeId, cardItem.modelData.id);
                                    canvasRoot.linkSourceNodeId = "";
                                }
                                canvasRoot.selectedNodeId = String(cardItem.modelData.id);
                                startX = mouse.x;
                                startY = mouse.y;
                            }
                            onDoubleClicked: {
                                if (String(cardItem.modelData.type ?? "text") === "text") {
                                    canvasRoot.editingNodeId = String(cardItem.modelData.id);
                                } else if (String(cardItem.modelData.type ?? "") === "file" && cardItem.modelData.file) {
                                    canvasRoot.nexus.openFile(String(cardItem.modelData.file), true);
                                }
                            }
                            onPositionChanged: mouse => {
                                if (pressed) {
                                    const nextX = Math.round(cardItem.x + (mouse.x - startX));
                                    const nextY = Math.round(cardItem.y + (mouse.y - startY));
                                    cardItem.x = nextX;
                                    cardItem.y = nextY;
                                    if (cardItem.modelData) {
                                        cardItem.modelData.x = nextX;
                                        cardItem.modelData.y = nextY;
                                    }
                                    canvasRoot.dirty = true;
                                    edgeCanvas.requestPaint();
                                }
                            }
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 6

                            StyledText {
                                visible: cardItem.isGroup
                                text: String(cardItem.modelData.label ?? "Group")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.Bold
                                color: cardItem.accentCol
                            }

                            StyledText {
                                visible: String(cardItem.modelData.type ?? "") === "file"
                                Layout.fillWidth: true
                                text: "[[ " + String(cardItem.modelData.file ?? "") + " ]]"
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.DemiBold
                                color: cardItem.accentCol
                                wrapMode: Text.WordWrap
                            }

                            StyledText {
                                id: cardPreviewText
                                visible: !cardItem.isGroup && String(cardItem.modelData.type ?? "text") === "text" && !cardItem.isEditing
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                text: String(cardItem.modelData.text ?? "")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: canvasRoot.settledColors?.colOnLayer1 ?? Appearance.colors.colOnLayer1
                                wrapMode: Text.WordWrap
                            }

                            TextArea {
                                id: cardInlineArea
                                visible: cardItem.isEditing
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                color: canvasRoot.settledColors?.colOnLayer1 ?? Appearance.colors.colOnLayer1
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                wrapMode: TextEdit.Wrap
                                background: Rectangle {
                                    radius: 6
                                    color: canvasRoot.settledColors?.colLayer0 ?? Appearance.colors.colLayer0
                                }
                                onVisibleChanged: {
                                    if (visible) {
                                        text = String(cardItem.modelData?.text ?? "");
                                        forceActiveFocus();
                                    }
                                }
                                onTextChanged: {
                                    if (visible && cardItem.modelData && cardItem.modelData.text !== text) {
                                        cardItem.modelData.text = text;
                                        cardPreviewText.text = text;
                                        canvasRoot.dirty = true;
                                    }
                                }
                            }
                        }

                        // Resize handle bottom-right
                        Rectangle {
                            visible: cardItem.isSelected
                            width: 12; height: 12; radius: 3
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.margins: 3
                            color: cardItem.accentCol
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.SizeFDiagCursor
                                property real sx: 0
                                property real sy: 0
                                onPressed: m => { sx = m.x; sy = m.y; }
                                onPositionChanged: m => {
                                    if (pressed) {
                                        const nw = Math.max(120, Math.round(cardItem.width + (m.x - sx)));
                                        const nh = Math.max(70, Math.round(cardItem.height + (m.y - sy)));
                                        cardItem.width = nw;
                                        cardItem.height = nh;
                                        if (cardItem.modelData) {
                                            cardItem.modelData.width = nw;
                                            cardItem.modelData.height = nh;
                                        }
                                        canvasRoot.dirty = true;
                                        edgeCanvas.requestPaint();
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
