import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import "NexusRichRenderers.js" as Rich

Rectangle {
    id: diagramRoot
    property var settledColors: null
    property string mermaidSource: ""
    property bool showSource: false
    readonly property var parsed: Rich.parseMermaid(mermaidSource)

    onMermaidSourceChanged: diagramCanvas.requestPaint()
    onShowSourceChanged: {
        if (!showSource)
            diagramCanvas.requestPaint();
    }

    radius: 10
    color: settledColors?.colLayer0 ?? Appearance.colors.colLayer0
    implicitHeight: showSource ? Math.max(110, sourceText.implicitHeight + 68) : (parsed.supported ? computedDiagramHeight : 140)
    Layout.fillWidth: true

    readonly property int computedDiagramHeight: {
        if (!parsed.supported)
            return 140;
        if (parsed.kind === "sequence")
            return Math.max(180, 96 + (parsed.messages?.length ?? 0) * 42);
        const horizontal = parsed.direction === "LR" || parsed.direction === "RL";
        const count = Math.max(1, parsed.nodes?.length ?? 1);
        return horizontal ? Math.max(170, Math.min(340, 120 + count * 34)) : Math.max(180, Math.min(440, 80 + count * 58));
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            MaterialSymbol {
                text: "account_tree"
                iconSize: 15
                color: diagramRoot.settledColors?.colPrimary ?? Appearance.colors.colPrimary
            }

            StyledText {
                text: parsed.supported ? ("Mermaid · " + parsed.kind) : "Mermaid Source"
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.DemiBold
                color: diagramRoot.settledColors?.colOnLayer1 ?? Appearance.colors.colOnLayer1
            }

            Item { Layout.fillWidth: true }

            Rectangle {
                height: 24
                width: Math.max(66, modeLabel.implicitWidth + 18)
                radius: 12
                color: diagramRoot.settledColors?.colLayer1 ?? Appearance.colors.colLayer1
                StyledText {
                    id: modeLabel
                    anchors.centerIn: parent
                    text: diagramRoot.showSource ? "Diagram" : "Source"
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    horizontalAlignment: Text.AlignHCenter
                    color: diagramRoot.settledColors?.colPrimary ?? Appearance.colors.colPrimary
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: diagramRoot.showSource = !diagramRoot.showSource
                }
            }
        }

        Canvas {
            id: diagramCanvas
            visible: !diagramRoot.showSource && diagramRoot.parsed.supported
            Layout.fillWidth: true
            Layout.fillHeight: true
            renderStrategy: Canvas.Threaded
            renderTarget: Canvas.Image
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()

            onPaint: {
                const ctx = getContext("2d");
                const w = width;
                const h = height;
                ctx.clearRect(0, 0, w, h);
                const p = diagramRoot.parsed;
                if (!p || !p.supported || w < 40 || h < 40)
                    return;

                const colCard = String(diagramRoot.settledColors?.colLayer1 ?? Appearance.colors.colLayer1);
                const colPrimary = String(diagramRoot.settledColors?.colPrimary ?? Appearance.colors.colPrimary);
                const colText = String(diagramRoot.settledColors?.colOnLayer1 ?? Appearance.colors.colOnLayer1);
                const colSub = String(diagramRoot.settledColors?.colSubtext ?? Appearance.colors.colSubtext);

                ctx.font = "12px sans-serif";
                ctx.textBaseline = "middle";
                ctx.textAlign = "center";

                if (p.kind === "sequence") {
                    const parts = p.participants || [];
                    const msgs = p.messages || [];
                    const count = Math.max(1, parts.length);
                    const stepX = (w - 40) / count;
                    const posX = {};
                    for (let i = 0; i < parts.length; ++i) {
                        const cx = 20 + stepX * (i + 0.5);
                        posX[parts[i].id] = cx;
                        const boxW = Math.min(stepX - 10, Math.max(76, ctx.measureText(parts[i].label).width + 20));
                        ctx.fillStyle = colCard;
                        ctx.strokeStyle = colPrimary;
                        ctx.lineWidth = 1.5;
                        ctx.beginPath();
                        ctx.roundedRect(cx - boxW * 0.5, 8, boxW, 28, 7, 7);
                        ctx.fill();
                        ctx.stroke();
                        ctx.fillStyle = colText;
                        ctx.fillText(parts[i].label, cx, 22);

                        ctx.strokeStyle = colSub;
                        ctx.globalAlpha = 0.45;
                        ctx.setLineDash([4, 4]);
                        ctx.beginPath();
                        ctx.moveTo(cx, 38);
                        ctx.lineTo(cx, h - 12);
                        ctx.stroke();
                        ctx.setLineDash([]);
                        ctx.globalAlpha = 1.0;
                    }
                    for (let m = 0; m < msgs.length; ++m) {
                        const msg = msgs[m];
                        const x1 = posX[msg.from] ?? 40;
                        const x2 = posX[msg.to] ?? (w - 40);
                        const y = 60 + m * 38;
                        ctx.strokeStyle = colPrimary;
                        ctx.lineWidth = 1.5;
                        if (msg.dashed)
                            ctx.setLineDash([5, 4]);
                        ctx.beginPath();
                        ctx.moveTo(x1, y);
                        ctx.lineTo(x2, y);
                        ctx.stroke();
                        ctx.setLineDash([]);
                        const dir = x2 >= x1 ? 1 : -1;
                        ctx.fillStyle = colPrimary;
                        ctx.beginPath();
                        ctx.moveTo(x2, y);
                        ctx.lineTo(x2 - dir * 8, y - 4);
                        ctx.lineTo(x2 - dir * 8, y + 4);
                        ctx.closePath();
                        ctx.fill();
                        if (msg.label) {
                            ctx.fillStyle = colSub;
                            ctx.fillText(msg.label, (x1 + x2) * 0.5, y - 10);
                        }
                    }
                    return;
                }

                // Flowchart layout (topological depth layers)
                const nodes = p.nodes || [];
                const edges = p.edges || [];
                const depth = {};
                for (let i = 0; i < nodes.length; ++i)
                    depth[nodes[i].id] = 0;
                for (let pass = 0; pass < nodes.length; ++pass) {
                    for (let e = 0; e < edges.length; ++e) {
                        const ed = edges[e];
                        if ((depth[ed.to] ?? 0) <= (depth[ed.from] ?? 0))
                            depth[ed.to] = (depth[ed.from] ?? 0) + 1;
                    }
                }
                let maxD = 0;
                const layers = {};
                for (let i = 0; i < nodes.length; ++i) {
                    const d = depth[nodes[i].id] ?? 0;
                    if (d > maxD) maxD = d;
                    if (!layers[d]) layers[d] = [];
                    layers[d].push(nodes[i]);
                }

                const horizontal = p.direction === "LR" || p.direction === "RL";
                const coords = {};
                for (let d = 0; d <= maxD; ++d) {
                    const layer = layers[d] || [];
                    for (let idx = 0; idx < layer.length; ++idx) {
                        const n = layer[idx];
                        const bw = Math.min(180, Math.max(78, ctx.measureText(n.label).width + 26));
                        const bh = n.shape === "diamond" ? 44 : 34;
                        let cx, cy;
                        if (horizontal) {
                            const fracX = maxD === 0 ? 0.5 : (p.direction === "RL" ? (1 - d / maxD) : (d / maxD));
                            cx = 75 + fracX * Math.max(60, w - 150);
                            cy = ((idx + 0.5) / Math.max(1, layer.length)) * (h - 24) + 12;
                        } else {
                            const fracY = maxD === 0 ? 0.5 : (p.direction === "BT" ? (1 - d / maxD) : (d / maxD));
                            cy = 34 + fracY * Math.max(40, h - 68);
                            cx = ((idx + 0.5) / Math.max(1, layer.length)) * (w - 30) + 15;
                        }
                        coords[n.id] = { cx: cx, cy: cy, bw: bw, bh: bh, node: n };
                    }
                }

                // Draw edges
                for (let e = 0; e < edges.length; ++e) {
                    const ed = edges[e];
                    const a = coords[ed.from];
                    const b = coords[ed.to];
                    if (!a || !b) continue;
                    ctx.strokeStyle = colPrimary;
                    ctx.lineWidth = ed.thick ? 2.4 : 1.5;
                    ctx.globalAlpha = 0.72;
                    if (ed.dashed) ctx.setLineDash([5, 4]);
                    ctx.beginPath();
                    ctx.moveTo(a.cx, a.cy);
                    if (horizontal) {
                        const mx = (a.cx + b.cx) * 0.5;
                        ctx.bezierCurveTo(mx, a.cy, mx, b.cy, b.cx, b.cy);
                    } else {
                        const my = (a.cy + b.cy) * 0.5;
                        ctx.bezierCurveTo(a.cx, my, b.cx, my, b.cx, b.cy);
                    }
                    ctx.stroke();
                    ctx.setLineDash([]);
                    ctx.globalAlpha = 1.0;
                    if (ed.label) {
                        ctx.fillStyle = colSub;
                        ctx.fillText(ed.label, (a.cx + b.cx) * 0.5, (a.cy + b.cy) * 0.5 - 8);
                    }
                }

                // Draw nodes on top
                for (let i = 0; i < nodes.length; ++i) {
                    const c = coords[nodes[i].id];
                    if (!c) continue;
                    const x0 = c.cx - c.bw * 0.5;
                    const y0 = c.cy - c.bh * 0.5;
                    ctx.fillStyle = colCard;
                    ctx.strokeStyle = colPrimary;
                    ctx.lineWidth = 1.5;
                    ctx.beginPath();
                    if (c.node.shape === "circle") {
                        const rad = Math.max(c.bw, c.bh) * 0.45;
                        ctx.arc(c.cx, c.cy, rad, 0, Math.PI * 2);
                    } else if (c.node.shape === "diamond") {
                        ctx.moveTo(c.cx, y0);
                        ctx.lineTo(x0 + c.bw, c.cy);
                        ctx.lineTo(c.cx, y0 + c.bh);
                        ctx.lineTo(x0, c.cy);
                        ctx.closePath();
                    } else {
                        const rad = c.node.shape === "round" ? 16 : 7;
                        ctx.roundedRect(x0, y0, c.bw, c.bh, rad, rad);
                    }
                    ctx.fill();
                    ctx.stroke();
                    ctx.fillStyle = colText;
                    ctx.fillText(c.node.label, c.cx, c.cy);
                }
            }
        }

        StyledText {
            id: sourceText
            visible: diagramRoot.showSource || !diagramRoot.parsed.supported
            Layout.fillWidth: true
            text: diagramRoot.mermaidSource
            font.family: Appearance.font.family.monospace
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: diagramRoot.settledColors?.colOnLayer1 ?? Appearance.colors.colOnLayer1
            wrapMode: Text.WrapAnywhere
        }
    }
}
