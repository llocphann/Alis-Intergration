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
    property bool notePickerOpen: false
    property string notePickerQuery: ""
    readonly property var pickerNotes: {
        const q = String(canvasRoot.notePickerQuery ?? "").trim().toLowerCase();
        const seen = {};
        const out = [];
        const addItem = item => {
            if (!item)
                return;
            const rel = String(item.relPath ?? "").trim();
            if (!rel || seen[rel])
                return;
            const cat = String(item.category ?? "markdown");
            if (cat === "canvas" || rel.toLowerCase().endsWith(".canvas"))
                return;
            const title = String(item.title || rel.split("/").pop().replace(/\.md$/i, ""));
            if (q.length > 0 && title.toLowerCase().indexOf(q) === -1 && rel.toLowerCase().indexOf(q) === -1)
                return;
            seen[rel] = true;
            out.push({ "relPath": rel, "title": title });
        };
        const recent = canvasRoot.nexus?.recentNotes ?? [];
        for (let i = 0; i < recent.length; ++i)
            addItem(recent[i]);
        const flat = canvasRoot.nexus?.flatFiles ?? [];
        for (let i = 0; i < flat.length && out.length < 80; ++i)
            addItem(flat[i]);
        return out;
    }

    Timer {
        id: canvasAutosaveTimer
        interval: 1200
        repeat: false
        onTriggered: canvasRoot.saveCanvas()
    }

    Timer {
        id: dotGridRepaintTimer
        interval: 32
        repeat: false
        onTriggered: dotGridCanvas.requestPaint()
    }

    Timer {
        id: edgeRepaintTimer
        interval: 16
        repeat: false
        onTriggered: edgeCanvas.requestPaint()
    }

    focus: true
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape && canvasRoot.notePickerOpen) {
            canvasRoot.notePickerOpen = false;
            canvasRoot.notePickerQuery = "";
            event.accepted = true;
            return;
        }
        if ((event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace)
            && canvasRoot.selectedNodeId.length > 0
            && canvasRoot.editingNodeId.length === 0) {
            canvasRoot.deleteSelectedNode();
            canvasAutosaveTimer.restart();
            event.accepted = true;
        }
    }

    color: settledColors?.colLayer0 ?? Appearance.colors.colLayer0
    radius: 12
    clip: true

    readonly property var doc: nexus?.currentDoc ?? null
    property string loadedCanvasPath: ""

    onDocChanged: reloadFromDoc()
    Component.onCompleted: reloadFromDoc()

    function reloadFromDoc(): void {
        canvasAutosaveTimer.stop();
        selectedNodeId = "";
        editingNodeId = "";
        linkSourceNodeId = "";
        if (!doc || String(doc.category ?? "") !== "canvas") {
            loadedCanvasPath = "";
            return;
        }
        loadedCanvasPath = String(doc.relPath ?? nexus?.currentPath ?? "");
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
            dirty = false;
        }
    }

    function updateNodeFields(nodeId: string, patch: var, repaintEdges = true): void {
        const idStr = String(nodeId ?? "");
        if (!idStr || !patch || typeof patch !== "object")
            return;
        const keys = Object.keys(patch);
        for (let i = 0; i < canvasNodes.length; ++i) {
            if (String(canvasNodes[i]?.id ?? "") === idStr) {
                for (let k = 0; k < keys.length; ++k)
                    canvasNodes[i][keys[k]] = patch[keys[k]];
                break;
            }
        }
        dirty = true;
        if (repaintEdges)
            edgeCanvas.requestPaint();
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

    function addNoteCard(relPath: string): void {
        const cleaned = String(relPath ?? "").trim();
        if (!cleaned)
            return;
        const cx = (viewport.width * 0.5 - panX) / zoom - 110 + (canvasNodes.length % 5) * 24;
        const cy = (viewport.height * 0.5 - panY) / zoom - 55 + (canvasNodes.length % 4) * 24;
        const nid = "node-" + Date.now() + "-" + (_nodeSeq++);
        const obj = { "id": nid, "type": "file", "file": cleaned, "x": cx, "y": cy, "width": 240, "height": 110, "color": "4" };
        const next = canvasNodes.slice();
        next.push(obj);
        canvasNodes = next;
        selectedNodeId = nid;
        notePickerOpen = false;
        notePickerQuery = "";
        dirty = true;
        canvasAutosaveTimer.restart();
        edgeCanvas.requestPaint();
    }

    function addCard(kind: string, filePath = ""): void {
        if (kind === "file") {
            const explicit = String(filePath ?? "").trim();
            if (explicit.length > 0) {
                addNoteCard(explicit);
                return;
            }
            notePickerOpen = !notePickerOpen;
            if (notePickerOpen) {
                notePickerQuery = "";
                Qt.callLater(() => {
                    if (notePickerSearchField && notePickerPopup.visible)
                        notePickerSearchField.forceActiveFocus();
                });
            }
            return;
        }
        const cx = (viewport.width * 0.5 - panX) / zoom - 110 + (canvasNodes.length % 5) * 24;
        const cy = (viewport.height * 0.5 - panY) / zoom - 55 + (canvasNodes.length % 4) * 24;
        const nid = "node-" + Date.now() + "-" + (_nodeSeq++);
        let obj;
        if (kind === "group") {
            obj = { "id": nid, "type": "group", "label": "Group", "x": cx - 40, "y": cy - 30, "width": 360, "height": 220, "color": "5" };
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
        if (linkSourceNodeId === rm)
            linkSourceNodeId = "";
        if (editingNodeId === rm)
            editingNodeId = "";
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
        if (!nexus)
            return;
        const cur = String(nexus.currentPath ?? "");
        const target = cur.toLowerCase().endsWith(".canvas")
            ? cur
            : (loadedCanvasPath.toLowerCase().endsWith(".canvas") ? loadedCanvasPath : "");
        if (!target)
            return;
        nexus.saveCanvasFile(target, { "nodes": canvasNodes, "edges": canvasEdges });
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

                Repeater {
                    model: ["#ef4444", "#f59e0b", "#10b981", "#3b82f6", "#8b5cf6", "#ec4899"]
                    delegate: Rectangle {
                        required property string modelData
                        visible: canvasRoot.selectedNodeId.length > 0
                        height: 18; width: 18; radius: 9
                        color: modelData
                        border.width: 1
                        border.color: "#ffffff"
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                const nodes = canvasRoot.canvasNodes.slice();
                                for (let i = 0; i < nodes.length; ++i) {
                                    if (nodes[i].id === canvasRoot.selectedNodeId) {
                                        nodes[i] = Object.assign({}, nodes[i], { "color": modelData });
                                        break;
                                    }
                                }
                                canvasRoot.canvasNodes = nodes;
                                canvasRoot.dirty = true;
                                canvasAutosaveTimer.restart();
                            }
                        }
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
                    canvasRoot.notePickerOpen = false;
                }
                onDoubleClicked: canvasRoot.addCard("text")
                onPositionChanged: mouse => {
                    if (pressed) {
                        canvasRoot.panX += mouse.x - lastX;
                        canvasRoot.panY += mouse.y - lastY;
                        lastX = mouse.x;
                        lastY = mouse.y;
                        if (!edgeRepaintTimer.running)
                            edgeRepaintTimer.start();
                    }
                }
                onReleased: edgeCanvas.requestPaint()
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
                        if (!edgeRepaintTimer.running)
                            edgeRepaintTimer.start();
                    }
                    wheel.accepted = true;
                }
            }

            // Cached dot-grid layer: painted once per zoom/size/theme change (throttled)
            // and GPU-translated on panX/panY so panning never repaints thousands of dots.
            Canvas {
                id: dotGridCanvas
                readonly property real dotStep: Math.max(12, 32 * canvasRoot.zoom)
                readonly property bool showDots: (32 * canvasRoot.zoom) >= 12
                visible: showDots
                x: ((canvasRoot.panX % dotStep) + dotStep) % dotStep - dotStep
                y: ((canvasRoot.panY % dotStep) + dotStep) % dotStep - dotStep
                width: Math.ceil(viewport.width + dotStep * 2)
                height: Math.ceil(viewport.height + dotStep * 2)
                renderStrategy: Canvas.Threaded
                renderTarget: Canvas.Image
                readonly property real _zoom: canvasRoot.zoom
                readonly property color _dotColor: canvasRoot.settledColors?.colSubtext ?? "#64748b"
                on_ZoomChanged: dotGridRepaintTimer.restart()
                on_DotColorChanged: dotGridRepaintTimer.restart()
                onWidthChanged: dotGridRepaintTimer.restart()
                onHeightChanged: dotGridRepaintTimer.restart()
                Component.onCompleted: requestPaint()
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.clearRect(0, 0, width, height);
                    const step = 32 * canvasRoot.zoom;
                    if (step < 12)
                        return;
                    ctx.fillStyle = String(_dotColor);
                    ctx.globalAlpha = 0.22;
                    for (let gx = 0; gx < width; gx += step) {
                        for (let gy = 0; gy < height; gy += step) {
                            ctx.fillRect(gx, gy, 1.5, 1.5);
                        }
                    }
                    ctx.globalAlpha = 1.0;
                }
            }

            // Dynamic edge arrows layer (repaints on node/edge updates without redrawing dots)
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
                                canvasRoot.forceActiveFocus();
                                if (canvasRoot.linkSourceNodeId && canvasRoot.linkSourceNodeId !== cardItem.modelData.id) {
                                    canvasRoot.connectNodes(canvasRoot.linkSourceNodeId, cardItem.modelData.id);
                                    canvasRoot.linkSourceNodeId = "";
                                }
                                canvasRoot.selectedNodeId = String(cardItem.modelData.id);
                                startX = mouse.x;
                                startY = mouse.y;
                            }
                            onDoubleClicked: {
                                const nodeKind = String(cardItem.modelData.type ?? "text");
                                if (nodeKind === "text") {
                                    canvasRoot.editingNodeId = String(cardItem.modelData.id);
                                } else if (nodeKind === "file" && cardItem.modelData.file) {
                                    canvasRoot.nexus?.openFile(String(cardItem.modelData.file), true);
                                } else if (nodeKind === "link") {
                                    const linkUrl = String(cardItem.modelData.url ?? "").trim();
                                    if (/^https?:\/\//i.test(linkUrl))
                                        Qt.openUrlExternally(linkUrl);
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
                                    canvasRoot.updateNodeFields(String(cardItem.modelData?.id ?? ""), { "x": nextX, "y": nextY });
                                }
                            }
                            onReleased: {
                                if (canvasRoot.dirty)
                                    canvasAutosaveTimer.restart();
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
                                visible: String(cardItem.modelData.type ?? "") === "link"
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                text: String(cardItem.modelData.url ?? "")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: cardItem.accentCol
                                wrapMode: Text.WrapAnywhere
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
                                    if (visible && cardItem.modelData && cardPreviewText.text !== text) {
                                        cardItem.modelData.text = text;
                                        cardPreviewText.text = text;
                                        canvasRoot.updateNodeFields(String(cardItem.modelData.id), { "text": text }, false);
                                        canvasAutosaveTimer.restart();
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
                                        canvasRoot.updateNodeFields(String(cardItem.modelData?.id ?? ""), { "width": nw, "height": nh });
                                    }
                                }
                                onReleased: {
                                    if (canvasRoot.dirty)
                                        canvasAutosaveTimer.restart();
                                }
                            }
                        }
                    }
                }
            }

            // Inline Vault Note Picker popup for `+ Note`
            Rectangle {
                id: notePickerPopup
                objectName: "canvasNotePickerPopup"
                visible: canvasRoot.notePickerOpen
                z: 40
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: 12
                width: Math.min(340, Math.max(220, viewport.width - 24))
                height: Math.min(320, Math.max(120, notePickerCol.implicitHeight + 16))
                radius: 10
                color: canvasRoot.settledColors?.colLayer1 ?? Appearance.colors.colLayer1
                border.width: 1
                border.color: canvasRoot.settledColors?.colLayer0Border ?? Appearance.colors.colLayer0Border

                ColumnLayout {
                    id: notePickerCol
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 6

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        TextField {
                            id: notePickerSearchField
                            objectName: "canvasNotePickerSearch"
                            Layout.fillWidth: true
                            implicitHeight: 30
                            placeholderText: "Pick a vault note..."
                            color: canvasRoot.settledColors?.colOnLayer1 ?? Appearance.colors.colOnLayer1
                            placeholderTextColor: canvasRoot.settledColors?.colSubtext ?? Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            background: Rectangle {
                                radius: 6
                                color: canvasRoot.settledColors?.colLayer0 ?? Appearance.colors.colLayer0
                                border.width: 1
                                border.color: notePickerSearchField.activeFocus
                                    ? (canvasRoot.settledColors?.colPrimary ?? Appearance.colors.colPrimary)
                                    : (canvasRoot.settledColors?.colLayer0Border ?? Appearance.colors.colLayer0Border)
                            }
                            onTextChanged: {
                                if (canvasRoot.notePickerQuery !== text)
                                    canvasRoot.notePickerQuery = text;
                            }
                            Connections {
                                target: canvasRoot
                                function onNotePickerQueryChanged(): void {
                                    if (notePickerSearchField.text !== canvasRoot.notePickerQuery)
                                        notePickerSearchField.text = canvasRoot.notePickerQuery;
                                }
                            }
                            Keys.onEscapePressed: {
                                canvasRoot.notePickerOpen = false;
                                canvasRoot.notePickerQuery = "";
                            }
                            Keys.onReturnPressed: {
                                if (canvasRoot.pickerNotes.length > 0)
                                    canvasRoot.addNoteCard(canvasRoot.pickerNotes[0].relPath);
                            }
                        }

                        Rectangle {
                            width: 26
                            height: 26
                            radius: 6
                            color: canvasRoot.settledColors?.colLayer2 ?? Appearance.colors.colLayer2
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "close"
                                iconSize: 15
                                color: canvasRoot.settledColors?.colSubtext ?? Appearance.colors.colSubtext
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    canvasRoot.notePickerOpen = false;
                                    canvasRoot.notePickerQuery = "";
                                }
                            }
                        }
                    }

                    ListView {
                        id: notePickerList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        implicitHeight: Math.min(250, Math.max(40, contentHeight))
                        clip: true
                        spacing: 3
                        model: canvasRoot.pickerNotes
                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            width: notePickerList.width
                            height: 38
                            radius: 6
                            color: pickerRowMouse.containsMouse
                                ? (canvasRoot.settledColors?.colSecondaryContainer ?? Appearance.colors.colSecondaryContainer)
                                : "transparent"

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                spacing: 1
                                StyledText {
                                    Layout.fillWidth: true
                                    text: String(modelData.title ?? "")
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.weight: Font.Medium
                                    color: canvasRoot.settledColors?.colOnLayer1 ?? Appearance.colors.colOnLayer1
                                    elide: Text.ElideRight
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: String(modelData.relPath ?? "")
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: canvasRoot.settledColors?.colSubtext ?? Appearance.colors.colSubtext
                                    elide: Text.ElideMiddle
                                }
                            }

                            MouseArea {
                                id: pickerRowMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: canvasRoot.addNoteCard(modelData.relPath)
                            }
                        }
                    }

                    StyledText {
                        visible: canvasRoot.pickerNotes.length === 0
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: "No matching notes"
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: canvasRoot.settledColors?.colSubtext ?? Appearance.colors.colSubtext
                    }
                }
            }
        }
    }
}
