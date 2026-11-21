import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root
    clip: true

    property var workspace: null
    property var graphData: ({
        "nodes": [],
        "edges": [],
        "groups": []
    })
    property bool isLocal: false
    property bool compact: false
    property bool allow3D: false
    property string renderMode: "2d" // "2d" | "3d"
    property bool electricCurrentEnabled: true
    property string currentPath: ""
    property var clusterPalette: ["#7dcfff", "#bb9af7", "#9ece6a", "#e0af68", "#f7768e", "#73daca", "#ff9e64", "#2ac3de"]

    signal nodeActivated(var nodeData)

    // Viewport transform state (deep zoom up to 32x)
    property real zoom: 1.0
    property real panX: 0.0
    property real panY: 0.0

    // 3D orbital camera angles (used when renderMode === "3d")
    property real rotYaw: 0.42
    property real rotPitch: 0.28

    // Interactive state
    property int hoveredIndex: -1
    property int draggedIndex: -1
    readonly property string hoveredId: (root.hoveredIndex >= 0 && root.graphData?.nodes && root.hoveredIndex < root.graphData.nodes.length)
        ? String(root.graphData.nodes[root.hoveredIndex]?.id ?? "")
        : ""
    property bool canvasHovered: graphMouse.containsMouse
    property var nodePositions: [] // [{ x: 0..1, y: 0..1, z: 0..1 }]
    property var resolvedEdges: [] // [{ s: int, t: int, clusterId: int }]
    property var resolvedNodeColors: [] // [{ base: color, deg2: color, leaf: color, hex: string, clusterId: int, isOrphan: bool }]
    property var adjacencyMap: ({}) // index -> { neighborIdx: true } (populated lazily)
    property int revealStaggerMs: 0
    property var _screenXBuf: null
    property var _screenYBuf: null
    property var _screenScaleBuf: null
    property var _screenDepthBuf: null
    property var _zOrderBuf: null
    property var _normXBuf: null
    property var _normYBuf: null
    property var _normZBuf: null
    property var _baseRadBuf: null
    property var _nodeDegBuf: null
    property var _clusterIdBuf: null
    property var _isOrphanBuf: null
    property var _edgeSrcBuf: null
    property var _edgeDstBuf: null
    property var _edgeClusterBuf: null
    property var _staticColorBuckets: []
    property string _colorsThemeSig: ""
    property bool _needsStaggeredReveal: true
    property real boundsMinX: 0.05
    property real boundsMaxX: 0.95
    property real boundsMinY: 0.05
    property real boundsMaxY: 0.95
    property real rawSpanX: 0.0
    property real rawSpanY: 0.0
    property real maxRadiusFromCenter: 0.0
    property bool _paintPending: true
    property int paintCount: 0
    property int electricPaintCount: 0
    property real _electricPhase: 0.0
    property string lastPaintedAccentHex: ""
    property string lastPaintedNodeHex: ""
    property string lastPaintedThemeSignature: ""

    readonly property bool is3D: root.allow3D && root.renderMode === "3d"
    readonly property color accentColor: root.workspace ? Qt.color(root.workspace._settledPrimary) : (Appearance.colors?.colPrimary ?? "#82c2cf")
    readonly property color secondaryColor: Appearance.colors?.colSecondary ?? root.accentColor
    readonly property color tertiaryColor: Appearance.colors?.colTertiary ?? root.accentColor
    readonly property color textColor: root.workspace ? Qt.color(root.workspace._settledOnLayer1) : (Appearance.colors?.colOnLayer1 ?? "#d9e1e3")
    readonly property color subtextColor: root.workspace ? Qt.color(root.workspace._settledSubtext) : (Appearance.colors?.colSubtext ?? "#8f9d9f")
    readonly property color mutedTextColor: root.workspace ? Qt.color(root.workspace._settledSubtext) : (Appearance.colors?.colSubtext ?? "#8f9d9f")
    readonly property color borderSubtle: root.workspace ? Qt.color(root.workspace._settledBorder) : (Appearance.colors?.colLayer0Border ?? "#2a3439")
    readonly property color bgSurface: root.workspace ? Qt.color(root.workspace._settledLayer1) : (Appearance.colors?.colLayer1 ?? "#10181b")
    readonly property bool isDarkSurface: root.bgSurface.hslLightness < 0.5
    readonly property string themeSignature: root.workspace ? root.workspace.themeSignature : [
        root.accentColor,
        root.textColor,
        root.mutedTextColor,
        root.borderSubtle,
        root.bgSurface,
        Appearance.colors?.colPrimary ?? "",
        Appearance.colors?.colSecondary ?? "",
        Appearance.colors?.colTertiary ?? "",
        Appearance.colors?.colLayer0 ?? "",
        Appearance.colors?.colLayer1 ?? "",
        Appearance.colors?.colOnLayer1 ?? "",
        Appearance.colors?.colOnLayer0 ?? "",
        Appearance.colors?.colSubtext ?? ""
    ].join("|")

    function _mixColor(cA: color, cB: color, weightA: real): color {
        const w = Math.max(0.0, Math.min(1.0, Number(weightA)));
        return Qt.rgba(
            cA.r * w + cB.r * (1.0 - w),
            cA.g * w + cB.g * (1.0 - w),
            cA.b * w + cB.b * (1.0 - w),
            1.0
        );
    }

    // Generate distinct, harmonious per-cluster colors anchored to Alis's live auto-theme
    function _autoThemedClusterColor(clusterId: int): color {
        const acc = root.accentColor;
        const sec = root.secondaryColor;
        const ter = root.tertiaryColor;
        const cid = Math.max(0, Number(clusterId) || 0);
        if (cid === 0)
            return acc;
        if (cid === 1 && String(ter) !== String(acc))
            return ter;
        if (cid === 2 && String(sec) !== String(acc))
            return sec;
        // Golden-angle hue rotation from Alis colPrimary while preserving theme-coherent saturation & lightness
        const baseH = (acc.hslHue >= 0 ? acc.hslHue : 0.55);
        const baseS = Math.max(0.46, Math.min(0.82, acc.hslSaturation > 0.08 ? acc.hslSaturation : 0.62));
        const baseL = root.isDarkSurface
            ? Math.max(0.56, Math.min(0.74, acc.hslLightness > 0.25 ? acc.hslLightness : 0.66))
            : Math.max(0.34, Math.min(0.52, acc.hslLightness < 0.75 ? acc.hslLightness : 0.42));
        const goldenFrac = 0.38196601125; // 137.5° / 360°
        const hue = (baseH + cid * goldenFrac) % 1.0;
        const lShift = ((cid % 3) - 1) * 0.04;
        const satShift = ((cid % 2) === 0 ? 0.04 : -0.04);
        const raw = Qt.hsla(
            hue,
            Math.max(0.40, Math.min(0.86, baseS + satShift)),
            Math.max(0.30, Math.min(0.78, baseL + lShift)),
            1.0
        );
        // Subtle 14% tint toward Alis colPrimary so every cluster belongs to the active wallpaper harmony
        return root._mixColor(raw, acc, 0.86);
    }

    // Unified single color for all orphan notes (calm, theme-matched, clearly distinct from clusters)
    readonly property color orphanNodeColor: root._mixColor(root.mutedTextColor, root.accentColor, 0.80)

    function _resolveNodeBaseColor(n: var, idx: int): color {
        const acc = root.accentColor;
        const muted = root.mutedTextColor;
        if (root.isLocal) {
            const hop = Number(n?.hop ?? 1);
            if (hop === 0)
                return acc;
            if (hop === 1)
                return root._mixColor(acc, root.tertiaryColor, 0.65);
            return root._mixColor(acc, muted, 0.52);
        }
        const isOrph = root._isOrphanBuf && idx >= 0 && idx < root._isOrphanBuf.length
            ? (root._isOrphanBuf[idx] === 1)
            : (Boolean(n?.isOrphan) || Number(n?.degree ?? 0) === 0);
        if (isOrph)
            return root.orphanNodeColor;
        const cid = root._clusterIdBuf && idx >= 0 && idx < root._clusterIdBuf.length
            ? root._clusterIdBuf[idx]
            : Number(n?.clusterId ?? -1);
        if (cid >= 0)
            return root._autoThemedClusterColor(cid);
        return acc;
    }

    function _neighborsFor(idx: int): var {
        if (idx < 0 || !root._edgeSrcBuf || !root._edgeDstBuf)
            return null;
        if (!root.adjacencyMap[idx]) {
            const map = {};
            const sArr = root._edgeSrcBuf;
            const tArr = root._edgeDstBuf;
            const len = root.resolvedEdges.length;
            for (let e = 0; e < len; ++e) {
                const s = sArr[e];
                const t = tArr[e];
                if (s === idx)
                    map[t] = true;
                else if (t === idx)
                    map[s] = true;
            }
            root.adjacencyMap[idx] = map;
        }
        return root.adjacencyMap[idx];
    }

    function _rebuildNodeColors(): void {
        const g = root.graphData;
        if (!g || !Array.isArray(g.nodes) || g.nodes.length === 0) {
            root.resolvedNodeColors = [];
            root._staticColorBuckets = [];
            root._colorsThemeSig = "";
            return;
        }
        const nodes = g.nodes;
        const muted = root.mutedTextColor;
        const out = new Array(nodes.length);
        const bucketMap = !root.isLocal ? Object.create(null) : null;
        for (let i = 0; i < nodes.length; ++i) {
            const n = nodes[i];
            const isOrph = root._isOrphanBuf && i < root._isOrphanBuf.length ? (root._isOrphanBuf[i] === 1) : (Number(n?.degree ?? 0) === 0);
            const cid = root._clusterIdBuf && i < root._clusterIdBuf.length ? root._clusterIdBuf[i] : Number(n?.clusterId ?? -1);
            const tc = root._resolveNodeBaseColor(n, i);
            const deg2 = Qt.rgba(tc.r, tc.g, tc.b, isOrph ? 0.62 : 0.94);
            const leaf = isOrph
                ? Qt.rgba(tc.r, tc.g, tc.b, 0.58)
                : Qt.rgba(
                    tc.r * 0.90 + muted.r * 0.10,
                    tc.g * 0.90 + muted.g * 0.10,
                    tc.b * 0.90 + muted.b * 0.10,
                    0.82
                );
            const hex = tc.toString();
            out[i] = {
                "base": tc,
                "deg2": deg2,
                "leaf": leaf,
                "hex": hex,
                "clusterId": cid,
                "isOrphan": isOrph
            };
            if (bucketMap) {
                const deg = Number(n.degree ?? 0);
                const isTag = Boolean(n?.isTagNode);
                if (!isTag && deg < 10) {
                    const useDeg2 = !isOrph && deg >= 2;
                    const bKey = (useDeg2 ? "d:" : (isOrph ? "o:" : "l:")) + hex;
                    if (!bucketMap[bKey])
                        bucketMap[bKey] = { "color": useDeg2 ? deg2 : leaf, "arr": [] };
                    bucketMap[bKey].arr.push(i);
                }
            }
        }
        root.resolvedNodeColors = out;
        root._colorsThemeSig = root.themeSignature;
        if (bucketMap) {
            const keys = Object.keys(bucketMap);
            const packed = new Array(keys.length);
            for (let k = 0; k < keys.length; ++k) {
                const entry = bucketMap[keys[k]];
                packed[k] = {
                    "color": entry.color,
                    "indices": new Int32Array(entry.arr)
                };
            }
            root._staticColorBuckets = packed;
        } else {
            root._staticColorBuckets = [];
        }
    }

    function clusterColor(groupIdx: int): color {
        return root._autoThemedClusterColor(groupIdx);
    }

    function resetView(): void {
        root.zoom = 1.0;
        root.panX = 0.0;
        root.panY = 0.0;
        root.rotYaw = 0.42;
        root.rotPitch = 0.28;
        root._syncPositionsFromData();
        root.requestPaint();
    }

    function setRenderMode(mode: string): void {
        const clean = (mode === "3d" && root.allow3D) ? "3d" : "2d";
        if (root.renderMode !== clean) {
            root.renderMode = clean;
            root.requestPaint();
        }
    }

    function zoomBy(factor: real, centerX: real, centerY: real): void {
        const oldZoom = root.zoom;
        const maxZoom = root.compact ? 14.0 : 32.0;
        const newZoom = Math.max(0.35, Math.min(maxZoom, oldZoom * factor));
        if (Math.abs(newZoom - oldZoom) < 0.001)
            return;
        const cx = (centerX !== undefined && centerX > 0) ? centerX : (root.width * 0.5);
        const cy = (centerY !== undefined && centerY > 0) ? centerY : (root.height * 0.5);
        root.panX = cx - (cx - root.panX) * (newZoom / oldZoom);
        root.panY = cy - (cy - root.panY) * (newZoom / oldZoom);
        root.zoom = newZoom;
        root.requestPaint();
    }

    function zoomIn(): void {
        root.zoomBy(1.32, root.width * 0.5, root.height * 0.5);
    }

    function zoomOut(): void {
        root.zoomBy(0.76, root.width * 0.5, root.height * 0.5);
    }

    Timer {
        id: staggerPaintTimer
        interval: Math.max(1, root.revealStaggerMs)
        repeat: false
        onTriggered: {
            if (root.canRepaintTheme) {
                root._needsStaggeredReveal = false;
                graphCanvas.requestPaint();
            }
        }
    }

    function requestPaint(): void {
        root._paintPending = true;
        if (!root.canRepaintTheme)
            return;
        if (root.revealStaggerMs > 0 && root._needsStaggeredReveal && root.draggedIndex < 0 && root.hoveredIndex < 0) {
            if (!staggerPaintTimer.running)
                staggerPaintTimer.start();
            return;
        }
        staggerPaintTimer.stop();
        graphCanvas.requestPaint();
        if (root.electricCurrentActive)
            electricCanvas.requestPaint();
    }

    function _baseRadiusFactor(n: var): real {
        if (root.isLocal) {
            if (n.hop === 0)
                return root.compact ? 3.2 : 4.4;
            if (n.hop === 1)
                return root.compact ? 2.0 : 2.8;
            return root.compact ? 1.4 : 1.9;
        }
        const isTag = Boolean(n?.isTagNode);
        const deg = Number(n.degree ?? 0);
        if (root.compact) {
            if (isTag)
                return Math.min(2.6, 1.65 + Math.log(deg + 1) * 0.22);
            if (deg >= 14)
                return Math.min(2.2, 1.40 + Math.log(deg + 1) * 0.16);
            if (deg >= 5)
                return 1.18;
            if (deg >= 2)
                return 0.94;
            if (deg === 1)
                return 0.80;
            return 0.65;
        }
        if (isTag)
            return Math.min(3.8, 2.25 + Math.log(deg + 1) * 0.26);
        if (deg >= 14)
            return Math.min(3.2, 1.80 + Math.log(deg + 1) * 0.22);
        if (deg >= 5)
            return 1.55;
        if (deg >= 2)
            return 1.22;
        if (deg === 1)
            return 1.00;
        return 0.82;
    }

    function _syncPositionsFromData(): void {
        const g = root.graphData;
        if (!g || !Array.isArray(g.nodes) || g.nodes.length === 0) {
            root.nodePositions = [];
            root.resolvedEdges = [];
            root.resolvedNodeColors = [];
            root._staticColorBuckets = [];
            root._colorsThemeSig = "";
            root._normXBuf = null;
            root._normYBuf = null;
            root._normZBuf = null;
            root._baseRadBuf = null;
            root._nodeDegBuf = null;
            root._clusterIdBuf = null;
            root._isOrphanBuf = null;
            root._edgeSrcBuf = null;
            root._edgeDstBuf = null;
            root._edgeClusterBuf = null;
            root.adjacencyMap = ({});
            root.hoveredIndex = -1;
            root.draggedIndex = -1;
            root.boundsMinX = 0.05;
            root.boundsMaxX = 0.95;
            root.boundsMinY = 0.05;
            root.boundsMaxY = 0.95;
            root.rawSpanX = 0.0;
            root.rawSpanY = 0.0;
            root.maxRadiusFromCenter = 0.0;
            return;
        }
        const nodes = g.nodes;
        const edges = g.edges ?? [];
        const nLen = nodes.length;
        const pos = new Array(nLen);
        const nxBuf = new Float32Array(nLen);
        const nyBuf = new Float32Array(nLen);
        const nzBuf = new Float32Array(nLen);
        const baseRadBuf = new Float32Array(nLen);
        const degBuf = new Int32Array(nLen);
        const clusterIdBuf = new Int32Array(nLen);
        const isOrphanBuf = new Uint8Array(nLen);
        const resEdges = [];
        const idToIdx = Object.create(null);
        let minX = 1.0, maxX = 0.0, minY = 1.0, maxY = 0.0, maxRad = 0.0;
        let hasBackendClusters = false;
        for (let i = 0; i < nLen; ++i) {
            const n = nodes[i];
            const nx = Number(n.x ?? 0.5);
            const ny = Number(n.y ?? 0.5);
            const nz = (n.z !== undefined && Number.isFinite(Number(n.z)))
                ? Number(n.z)
                : (0.5 + 0.34 * Math.sin(i * 2.399963) * Math.cos((nx - 0.5) * 3.14));
            if (nx < minX) minX = nx;
            if (nx > maxX) maxX = nx;
            if (ny < minY) minY = ny;
            if (ny > maxY) maxY = ny;
            const rad = Math.max(Math.abs(nx - 0.5), Math.abs(ny - 0.5));
            if (rad > maxRad) maxRad = rad;
            nxBuf[i] = nx;
            nyBuf[i] = ny;
            nzBuf[i] = nz;
            degBuf[i] = Number(n.degree ?? 0);
            if (n.clusterId !== undefined) {
                hasBackendClusters = true;
                clusterIdBuf[i] = Number(n.clusterId);
                isOrphanBuf[i] = (n.isOrphan === true || Number(n.clusterId) < 0) ? 1 : 0;
            } else {
                clusterIdBuf[i] = -1;
                isOrphanBuf[i] = 1;
            }
            baseRadBuf[i] = root._baseRadiusFactor(n);
            pos[i] = { "x": nx, "y": ny, "z": nz };
            if (n.id !== undefined)
                idToIdx[n.id] = i;
        }
        const adj = !hasBackendClusters ? new Array(nLen) : null;
        if (adj) {
            for (let i = 0; i < nLen; ++i) adj[i] = [];
        }
        for (let e = 0; e < edges.length; ++e) {
            const edge = edges[e];
            const sIdx = (edge.sourceIndex !== undefined) ? Number(edge.sourceIndex) : idToIdx[edge.source];
            const tIdx = (edge.targetIndex !== undefined) ? Number(edge.targetIndex) : idToIdx[edge.target];
            if (sIdx !== undefined && tIdx !== undefined && sIdx >= 0 && tIdx >= 0 && sIdx < nLen && tIdx < nLen && sIdx !== tIdx) {
                resEdges.push({ "s": sIdx, "t": tIdx });
                if (adj) {
                    adj[sIdx].push(tIdx);
                    adj[tIdx].push(sIdx);
                }
            }
        }
        // Fallback BFS connected components when test fixtures omit clusterId
        if (!hasBackendClusters && adj) {
            const seen = new Uint8Array(nLen);
            let nextCluster = 0;
            for (let start = 0; start < nLen; ++start) {
                if (seen[start]) continue;
                const comp = [];
                const q = [start];
                seen[start] = 1;
                while (q.length > 0) {
                    const curr = q.shift();
                    comp.push(curr);
                    const nbs = adj[curr];
                    for (let k = 0; k < nbs.length; ++k) {
                        const nb = nbs[k];
                        if (!seen[nb]) {
                            seen[nb] = 1;
                            q.push(nb);
                        }
                    }
                }
                if (comp.length >= 2) {
                    for (let k = 0; k < comp.length; ++k) {
                        clusterIdBuf[comp[k]] = nextCluster;
                        isOrphanBuf[comp[k]] = 0;
                        if (degBuf[comp[k]] === 0) degBuf[comp[k]] = adj[comp[k]].length;
                    }
                    nextCluster += 1;
                } else {
                    clusterIdBuf[start] = -1;
                    isOrphanBuf[start] = 1;
                }
            }
        }
        const eSrcBuf = new Int32Array(resEdges.length);
        const eDstBuf = new Int32Array(resEdges.length);
        const eClustBuf = new Int32Array(resEdges.length);
        for (let e = 0; e < resEdges.length; ++e) {
            eSrcBuf[e] = resEdges[e].s;
            eDstBuf[e] = resEdges[e].t;
            eClustBuf[e] = clusterIdBuf[resEdges[e].s] >= 0 ? clusterIdBuf[resEdges[e].s] : clusterIdBuf[resEdges[e].t];
        }
        const isFewLocal = root.isLocal || nLen <= 8;
        const minBoundFloor = isFewLocal ? 0.22 : 0.40;
        const maxBoundCeil = isFewLocal ? 0.78 : 0.60;
        root.boundsMinX = Math.min(minBoundFloor, minX);
        root.boundsMaxX = Math.max(maxBoundCeil, maxX);
        root.boundsMinY = Math.min(minBoundFloor, minY);
        root.boundsMaxY = Math.max(maxBoundCeil, maxY);
        root.rawSpanX = Math.max(0.0, maxX - minX);
        root.rawSpanY = Math.max(0.0, maxY - minY);
        root.maxRadiusFromCenter = maxRad;
        root._normXBuf = nxBuf;
        root._normYBuf = nyBuf;
        root._normZBuf = nzBuf;
        root._baseRadBuf = baseRadBuf;
        root._nodeDegBuf = degBuf;
        root._clusterIdBuf = clusterIdBuf;
        root._isOrphanBuf = isOrphanBuf;
        root._edgeSrcBuf = eSrcBuf;
        root._edgeDstBuf = eDstBuf;
        root._edgeClusterBuf = eClustBuf;
        root.nodePositions = pos;
        root.resolvedEdges = resEdges;
        root.adjacencyMap = ({});
        if (root.hoveredIndex >= nLen)
            root.hoveredIndex = -1;
        if (root.draggedIndex >= nLen)
            root.draggedIndex = -1;
        root._rebuildNodeColors();
    }

    function _viewportMetrics(): var {
        const isFewLocal = root.isLocal || root.nodePositions.length <= 8;
        const pad = isFewLocal ? (root.compact ? 28 : 34) : (root.compact ? 8 : 18);
        const availW = Math.max(40, graphCanvas.width - pad * 2);
        const availH = Math.max(40, graphCanvas.height - pad * 2);
        const geomDim = Math.sqrt(availW * availH);
        const minDataSpan = isFewLocal ? 0.56 : 0.22;
        const dataW = Math.max(minDataSpan, root.boundsMaxX - root.boundsMinX);
        const dataH = Math.max(minDataSpan, root.boundsMaxY - root.boundsMinY);
        const fitW = availW / dataW;
        const fitH = availH / dataH;
        let uniformFit = Math.min(fitW, fitH);
        if (isFewLocal) {
            const minCanvasDim = Math.max(80, Math.min(graphCanvas.width, graphCanvas.height));
            const maxAllowedPxSpan = minCanvasDim * (root.nodePositions.length <= 2 ? 0.36 : 0.44);
            const actualNormSpan = Math.max(0.18, root.rawSpanX, root.rawSpanY, root.maxRadiusFromCenter * 2.0);
            uniformFit = Math.min(uniformFit, maxAllowedPxSpan / actualNormSpan);
        }
        const spanX = isFewLocal ? uniformFit : (uniformFit * 0.74 + fitW * 0.26);
        const spanY = isFewLocal ? uniformFit : (uniformFit * 0.74 + fitH * 0.26);
        const dataCenterX = isFewLocal ? 0.5 : (root.boundsMinX + root.boundsMaxX) * 0.5;
        const dataCenterY = isFewLocal ? 0.5 : (root.boundsMinY + root.boundsMaxY) * 0.5;
        const originX = graphCanvas.width * 0.5 - dataCenterX * spanX;
        const originY = graphCanvas.height * 0.5 - dataCenterY * spanY;
        const refDim = root.compact ? 260.0 : 640.0;
        const nodeCount = Math.max(1, root.nodePositions.length);
        const densityFactor = (!root.isLocal && nodeCount > 150)
            ? Math.max(0.54, Math.min(1.0, Math.pow(150.0 / nodeCount, 0.24)))
            : 1.0;
        const sizeScale = Math.max(0.52, Math.min(1.08, Math.sqrt(geomDim / refDim))) * densityFactor;
        return {
            "spanX": spanX,
            "spanY": spanY,
            "originX": originX,
            "originY": originY,
            "sizeScale": sizeScale,
            "cx": graphCanvas.width * 0.5,
            "cy": graphCanvas.height * 0.5,
            "radius3D": Math.min(availW, availH) * 0.48
        };
    }

    function _project3D(nx: real, ny: real, nz: real, m: var): var {
        const x0 = (nx - 0.5) * 2.0;
        const y0 = (ny - 0.5) * 2.0;
        const z0 = (nz - 0.5) * 2.0;
        const cyaw = Math.cos(root.rotYaw);
        const syaw = Math.sin(root.rotYaw);
        const cpitch = Math.cos(root.rotPitch);
        const spitch = Math.sin(root.rotPitch);
        const rx = x0 * cyaw - z0 * syaw;
        const rz1 = x0 * syaw + z0 * cyaw;
        const ry = y0 * cpitch - rz1 * spitch;
        const rz = y0 * spitch + rz1 * cpitch;
        const focal = 2.75;
        const persp = focal / Math.max(0.45, focal - rz);
        const sx = (m.cx + rx * m.radius3D * persp) * root.zoom + root.panX;
        const sy = (m.cy + ry * m.radius3D * persp) * root.zoom + root.panY;
        return { "x": sx, "y": sy, "scale": persp, "depth": rz };
    }

    function _screenPosForNode(idx: int, metricsOverride = null): var {
        if (idx < 0 || idx >= root.nodePositions.length)
            return { "x": 0, "y": 0 };
        const p = root.nodePositions[idx];
        const m = metricsOverride || root._viewportMetrics();
        if (root.is3D) {
            const pr = root._project3D(p.x, p.y, p.z ?? 0.5, m);
            return { "x": pr.x, "y": pr.y, "scale": pr.scale, "depth": pr.depth };
        }
        const baseX = m.originX + p.x * m.spanX;
        const baseY = m.originY + p.y * m.spanY;
        return {
            "x": baseX * root.zoom + root.panX,
            "y": baseY * root.zoom + root.panY,
            "scale": 1.0,
            "depth": 0.0
        };
    }

    function _normalizedFromScreen(sx: real, sy: real): var {
        const m = root._viewportMetrics();
        const baseX = (sx - root.panX) / Math.max(0.1, root.zoom);
        const baseY = (sy - root.panY) / Math.max(0.1, root.zoom);
        return {
            "x": Math.max(0.02, Math.min(0.98, (baseX - m.originX) / Math.max(1.0, m.spanX))),
            "y": Math.max(0.02, Math.min(0.98, (baseY - m.originY) / Math.max(1.0, m.spanY))),
            "z": 0.5
        };
    }

    function _nodeRadius(n: var, a1 = undefined, a2 = undefined, a3 = undefined, a4 = undefined): real {
        const s = (typeof a1 === "number")
            ? a1
            : ((typeof a4 === "number") ? a4 : root._viewportMetrics().sizeScale);
        if (root.isLocal) {
            if (n.hop === 0) return (root.compact ? 3.2 : 4.4) * s;
            if (n.hop === 1) return (root.compact ? 2.0 : 2.8) * s;
            return (root.compact ? 1.4 : 1.9) * s;
        }
        const isTag = Boolean(n?.isTagNode);
        const deg = Number(n.degree ?? 0);
        const isCur = root.currentPath.length > 0 && n.relPath === root.currentPath;
        if (root.compact) {
            if (isCur) return 2.25 * s;
            if (isTag) return Math.min(2.6, 1.65 + Math.log(deg + 1) * 0.22) * s;
            if (deg >= 14) return Math.min(2.2, 1.40 + Math.log(deg + 1) * 0.16) * s;
            if (deg >= 5) return 1.18 * s;
            if (deg >= 2) return 0.94 * s;
            if (deg === 1) return 0.80 * s;
            return 0.65 * s;
        }
        if (isCur) return 3.3 * s;
        if (isTag) return Math.min(3.8, 2.25 + Math.log(deg + 1) * 0.26) * s;
        if (deg >= 14) return Math.min(3.2, 1.80 + Math.log(deg + 1) * 0.22) * s;
        if (deg >= 5) return 1.55 * s;
        if (deg >= 2) return 1.22 * s;
        if (deg === 1) return 1.00 * s;
        return 0.82 * s;
    }

    function findNodeAtScreen(sx: real, sy: real): int {
        const g = root.graphData;
        if (!g || !Array.isArray(g.nodes) || root.nodePositions.length !== g.nodes.length)
            return -1;
        const nodes = g.nodes;
        const nLen = nodes.length;
        const m = root._viewportMetrics();
        const zoomFactor = Math.min(1.65, Math.max(0.75, Math.pow(root.zoom, 0.26)));
        const hitSlack = root.compact ? 5.5 : 8.5;
        const scaleMul = m.sizeScale * zoomFactor;
        const maxHitR = 5.0 * scaleMul + hitSlack;
        const mulX = m.spanX * root.zoom;
        const addX = m.originX * root.zoom + root.panX;
        const mulY = m.spanY * root.zoom;
        const addY = m.originY * root.zoom + root.panY;
        const nxBuf = root._normXBuf;
        const nyBuf = root._normYBuf;
        const nzBuf = root._normZBuf;
        const baseRadBuf = root._baseRadBuf;
        const hasTyped = Boolean(nxBuf && nyBuf && baseRadBuf && nxBuf.length >= nLen && baseRadBuf.length >= nLen);
        const curPath = root.currentPath;
        const hasCurPath = !root.isLocal && curPath.length > 0;
        const curBaseR = root.compact ? 2.25 : 3.3;
        const mode3D = root.is3D;

        let bestIdx = -1;
        let bestScore = 9999999;
        for (let i = nLen - 1; i >= 0; --i) {
            let px, py, depthScale = 1.0, depthVal = 0.0;
            if (mode3D) {
                const pr = root._project3D(
                    hasTyped ? nxBuf[i] : root.nodePositions[i].x,
                    hasTyped ? nyBuf[i] : root.nodePositions[i].y,
                    (nzBuf && i < nzBuf.length) ? nzBuf[i] : 0.5,
                    m
                );
                px = pr.x; py = pr.y; depthScale = pr.scale; depthVal = pr.depth;
            } else {
                px = hasTyped ? (nxBuf[i] * mulX + addX) : ((m.originX + root.nodePositions[i].x * m.spanX) * root.zoom + root.panX);
                py = hasTyped ? (nyBuf[i] * mulY + addY) : ((m.originY + root.nodePositions[i].y * m.spanY) * root.zoom + root.panY);
            }
            const dx = px - sx;
            if (dx > maxHitR * depthScale || dx < -maxHitR * depthScale)
                continue;
            const dy = py - sy;
            if (dy > maxHitR * depthScale || dy < -maxHitR * depthScale)
                continue;
            const baseR = hasTyped
                ? ((hasCurPath && nodes[i].relPath === curPath) ? curBaseR : baseRadBuf[i])
                : root._nodeRadius(nodes[i], 1.0);
            const r = baseR * scaleMul * depthScale + hitSlack;
            const d2 = dx * dx + dy * dy;
            // In 3D mode, prefer closer-to-camera nodes when overlapping
            const score = mode3D ? (d2 - depthVal * 28.0) : d2;
            if (d2 <= r * r && score < bestScore) {
                bestScore = score;
                bestIdx = i;
            }
        }
        return bestIdx;
    }

    readonly property bool hostOpen: Boolean(root.workspace?.nexus?.isOpen ?? true)
    readonly property bool hostSettled: root.workspace ? Boolean(root.workspace.transitionSettled) : true
    readonly property bool hostSurfaceActive: Boolean(root.workspace ? root.workspace.surfaceActive : true)
    readonly property bool canRepaintTheme: root.visible && root.hostOpen && root.hostSurfaceActive && root.hostSettled
    readonly property bool electricCurrentActive: root.electricCurrentEnabled
        && root.canRepaintTheme
        && root.resolvedEdges.length > 0
        && root.width > 10 && root.height > 10
        && !(Config.options?.performance?.reduceAnimations ?? false)
        && !(Config.options?.appearance?.reduceAnimations ?? false)
        && !(GlobalStates?.wallpaperSelectorOpen ?? false)
        && !(GlobalStates?.screenLocked ?? false)
        && !(GlobalStates?.regionSelectorOpen ?? false)
        && !(GlobalStates?.annotationEditorOpen ?? false)

    function _triggerThemeRepaint(): void {
        if (!root.canRepaintTheme) {
            deferredThemeRepaintTimer.stop();
            return;
        }
        root._rebuildNodeColors();
        root.requestPaint();
        deferredThemeRepaintTimer.restart();
    }

    function _flushPendingPaintOnResume(): void {
        if (!root.canRepaintTheme) {
            deferredThemeRepaintTimer.stop();
            staggerPaintTimer.stop();
            return;
        }
        const nLen = root.graphData?.nodes?.length ?? 0;
        if (root.resolvedNodeColors.length !== nLen || root._colorsThemeSig !== root.themeSignature) {
            root._rebuildNodeColors();
        }
        if (root._paintPending || root.lastPaintedThemeSignature !== root.themeSignature) {
            root.requestPaint();
        }
    }

    Timer {
        id: deferredThemeRepaintTimer
        interval: 24
        repeat: false
        onTriggered: {
            if (!root.canRepaintTheme)
                return;
            if (root._colorsThemeSig !== root.themeSignature)
                root._rebuildNodeColors();
            root.requestPaint();
        }
    }

    // Calm 24fps EQ-DSP electric pulse driver (ONLY runs on separate lightweight electricCanvas,
    // strictly paused when hidden/closed/unsettled/reduced-motion/wallpaper-preview)
    Timer {
        id: electricAnimTimer
        interval: (Config.options?.performance?.lowPower ?? false) ? 75 : 42
        repeat: true
        running: root.electricCurrentActive
        onTriggered: {
            if (!root.electricCurrentActive) {
                stop();
                return;
            }
            root._electricPhase = (root._electricPhase + 0.042) % 1000.0;
            electricCanvas.requestPaint();
        }
    }

    onGraphDataChanged: {
        root._syncPositionsFromData();
        root.requestPaint();
    }
    onCurrentPathChanged: root.requestPaint()
    onRenderModeChanged: root.requestPaint()
    onThemeSignatureChanged: {
        const _sig = root.themeSignature;
        root._triggerThemeRepaint();
    }
    onHostOpenChanged: {
        if (!root.hostOpen) {
            root._needsStaggeredReveal = true;
            staggerPaintTimer.stop();
        }
    }
    onCanRepaintThemeChanged: root._flushPendingPaintOnResume()
    onHostSettledChanged: {
        if (!hostSettled) {
            root._needsStaggeredReveal = true;
            staggerPaintTimer.stop();
        } else {
            root._flushPendingPaintOnResume();
        }
    }

    Component.onCompleted: {
        root._syncPositionsFromData();
        root.requestPaint();
    }

    Canvas {
        id: graphCanvas
        anchors.fill: parent
        antialiasing: true
        onWidthChanged: root.requestPaint()
        onHeightChanged: root.requestPaint()
        onVisibleChanged: if (visible) root.requestPaint()
        onAvailableChanged: if (available) root.requestPaint()

        onPaint: {
            if (!root.canRepaintTheme) {
                root._paintPending = true;
                return;
            }
            if (width < 10 || height < 10)
                return;
            const ctx = getContext("2d");
            if (!ctx)
                return;
            root._paintPending = false;
            root._needsStaggeredReveal = false;
            ctx.clearRect(0, 0, width, height);

            const acc = root.accentColor;
            const muted = root.mutedTextColor;
            root.paintCount += 1;
            root.lastPaintedAccentHex = acc.toString();

            const g = root.graphData;
            if (!g || !Array.isArray(g.nodes) || g.nodes.length === 0) {
                root.lastPaintedThemeSignature = root.themeSignature;
                return;
            }
            if (root.nodePositions.length !== g.nodes.length || !root._normXBuf || root._normXBuf.length < g.nodes.length)
                root._syncPositionsFromData();
            if (root.resolvedNodeColors.length !== g.nodes.length || root._colorsThemeSig !== root.themeSignature)
                root._rebuildNodeColors();
            root.lastPaintedThemeSignature = root.themeSignature;
            if (root.resolvedNodeColors.length > 0)
                root.lastPaintedNodeHex = String(root.resolvedNodeColors[0].hex);

            const nodes = g.nodes;
            const nLen = nodes.length;
            const eLen = root.resolvedEdges.length;
            const activeIdx = root.draggedIndex >= 0 ? root.draggedIndex : root.hoveredIndex;
            const activeNeighbors = activeIdx >= 0 ? root._neighborsFor(activeIdx) : null;
            const m = root._viewportMetrics();
            const mode3D = root.is3D;

            // Precompute screen coordinates into reusable typed arrays
            if (!root._screenXBuf || root._screenXBuf.length < nLen) {
                root._screenXBuf = new Float32Array(Math.max(16, nLen));
                root._screenYBuf = new Float32Array(Math.max(16, nLen));
                root._screenScaleBuf = new Float32Array(Math.max(16, nLen));
                root._screenDepthBuf = new Float32Array(Math.max(16, nLen));
                root._zOrderBuf = new Int32Array(Math.max(16, nLen));
            }
            const sxBuf = root._screenXBuf;
            const syBuf = root._screenYBuf;
            const scBuf = root._screenScaleBuf;
            const zdBuf = root._screenDepthBuf;
            const zOrder = root._zOrderBuf;
            const nxBuf = root._normXBuf;
            const nyBuf = root._normYBuf;
            const nzBuf = root._normZBuf;
            if (mode3D) {
                const cyaw = Math.cos(root.rotYaw);
                const syaw = Math.sin(root.rotYaw);
                const cpitch = Math.cos(root.rotPitch);
                const spitch = Math.sin(root.rotPitch);
                const focal = 2.75;
                for (let i = 0; i < nLen; ++i) {
                    const x0 = (nxBuf[i] - 0.5) * 2.0;
                    const y0 = (nyBuf[i] - 0.5) * 2.0;
                    const z0 = (nzBuf[i] - 0.5) * 2.0;
                    const rx = x0 * cyaw - z0 * syaw;
                    const rz1 = x0 * syaw + z0 * cyaw;
                    const ry = y0 * cpitch - rz1 * spitch;
                    const rz = y0 * spitch + rz1 * cpitch;
                    const persp = focal / Math.max(0.45, focal - rz);
                    sxBuf[i] = (m.cx + rx * m.radius3D * persp) * root.zoom + root.panX;
                    syBuf[i] = (m.cy + ry * m.radius3D * persp) * root.zoom + root.panY;
                    scBuf[i] = persp;
                    zdBuf[i] = rz;
                    zOrder[i] = i;
                }
                // Draw subtle 3D spherical horizon guide rings
                ctx.save();
                ctx.strokeStyle = Qt.rgba(acc.r, acc.g, acc.b, 0.08);
                ctx.lineWidth = 1.0;
                const gcx = m.cx * root.zoom + root.panX;
                const gcy = m.cy * root.zoom + root.panY;
                const gr = m.radius3D * 0.92 * root.zoom;
                if (gr > 20 && gr < Math.max(width, height) * 4) {
                    ctx.beginPath();
                    ctx.arc(gcx, gcy, gr, 0, Math.PI * 2);
                    ctx.stroke();
                    ctx.beginPath();
                    ctx.ellipse(gcx - gr, gcy - gr * Math.abs(Math.sin(root.rotPitch)) * 0.45, gr * 2, gr * Math.abs(Math.sin(root.rotPitch)) * 0.9 + 2);
                    ctx.stroke();
                }
                ctx.restore();
            } else {
                const mulX = m.spanX * root.zoom;
                const addX = m.originX * root.zoom + root.panX;
                const mulY = m.spanY * root.zoom;
                const addY = m.originY * root.zoom + root.panY;
                for (let i = 0; i < nLen; ++i) {
                    sxBuf[i] = nxBuf[i] * mulX + addX;
                    syBuf[i] = nyBuf[i] * mulY + addY;
                    scBuf[i] = 1.0;
                    zdBuf[i] = 0.0;
                    zOrder[i] = i;
                }
            }

            const eSrc = root._edgeSrcBuf;
            const eDst = root._edgeDstBuf;

            // 1. Draw base edges (tinted gently by cluster color in non-compact / local views)
            if (root.isLocal) {
                ctx.lineWidth = root.compact ? 0.70 : 0.95;
                ctx.strokeStyle = activeIdx >= 0
                    ? Qt.rgba(acc.r, acc.g, acc.b, 0.10)
                    : Qt.rgba(acc.r * 0.85 + muted.r * 0.15, acc.g * 0.85 + muted.g * 0.15, acc.b * 0.85 + muted.b * 0.15, root.compact ? 0.26 : 0.34);
            } else {
                ctx.lineWidth = root.compact ? 0.36 : 0.54;
                ctx.strokeStyle = activeIdx >= 0
                    ? Qt.rgba(acc.r, acc.g, acc.b, 0.04)
                    : Qt.rgba(acc.r * 0.78 + muted.r * 0.22, acc.g * 0.78 + muted.g * 0.22, acc.b * 0.78 + muted.b * 0.22, root.compact ? 0.11 : 0.15);
            }
            ctx.beginPath();
            let edgeSegs = 0;
            for (let e = 0; e < eLen; ++e) {
                const sIdx = eSrc[e];
                const tIdx = eDst[e];
                if (activeIdx >= 0 && (sIdx === activeIdx || tIdx === activeIdx))
                    continue;
                const x0 = sxBuf[sIdx];
                const y0 = syBuf[sIdx];
                const x1 = sxBuf[tIdx];
                const y1 = syBuf[tIdx];
                if ((x0 < -16 && x1 < -16) || (x0 > width + 16 && x1 > width + 16)
                        || (y0 < -16 && y1 < -16) || (y0 > height + 16 && y1 > height + 16))
                    continue;
                const edx = x1 - x0;
                const edy = y1 - y0;
                if (edx * edx + edy * edy < 0.6)
                    continue;
                ctx.moveTo(x0, y0);
                ctx.lineTo(x1, y1);
                edgeSegs += 1;
                if (edgeSegs === 256) {
                    ctx.stroke();
                    ctx.beginPath();
                    edgeSegs = 0;
                }
            }
            if (edgeSegs > 0)
                ctx.stroke();

            // 2. Highlighted incident edges on hover/drag
            if (activeIdx >= 0) {
                const activeColor = root.resolvedNodeColors[activeIdx]?.base ?? acc;
                ctx.lineWidth = root.compact ? 1.0 : 1.45;
                ctx.strokeStyle = Qt.rgba(activeColor.r, activeColor.g, activeColor.b, 0.85);
                ctx.beginPath();
                let hiSegs = 0;
                for (let e = 0; e < eLen; ++e) {
                    const sIdx = eSrc[e];
                    const tIdx = eDst[e];
                    if (sIdx === activeIdx || tIdx === activeIdx) {
                        ctx.moveTo(sxBuf[sIdx], syBuf[sIdx]);
                        ctx.lineTo(sxBuf[tIdx], syBuf[tIdx]);
                        hiSegs += 1;
                    }
                }
                if (hiSegs > 0)
                    ctx.stroke();
            }

            // 3. Draw nodes (depth-sorted in 3D, fast color-bucketed in 2D)
            const scaleR = Math.min(1.65, Math.max(0.75, Math.pow(root.zoom, 0.25)));
            const scaleMul = m.sizeScale * scaleR;
            const baseRadBuf = root._baseRadBuf;
            const curPath = root.currentPath;
            const hasCurPath = curPath.length > 0;

            let renderOrder = null;
            if (mode3D) {
                renderOrder = Array.from(zOrder.subarray(0, nLen));
                renderOrder.sort((a, b) => zdBuf[a] - zdBuf[b]);
            }

            for (let pass = 0; pass < 2; ++pass) {
                if (pass === 0 && !mode3D && !root.isLocal && activeIdx < 0) {
                    const buckets = root._staticColorBuckets;
                    for (let bk = 0; bk < buckets.length; ++bk) {
                        const bucket = buckets[bk];
                        const idxs = bucket.indices;
                        const bLen = idxs.length;
                        ctx.fillStyle = bucket.color;
                        ctx.beginPath();
                        let queued = 0;
                        for (let j = 0; j < bLen; ++j) {
                            const ni = idxs[j];
                            if (hasCurPath && nodes[ni].relPath === curPath)
                                continue;
                            const px = sxBuf[ni];
                            const py = syBuf[ni];
                            if (px < -16 || px > width + 16 || py < -16 || py > height + 16)
                                continue;
                            const r = baseRadBuf[ni] * scaleMul;
                            if (r <= 1.15) {
                                ctx.rect(px - r, py - r, r * 2.0, r * 2.0);
                            } else {
                                ctx.moveTo(px + r, py);
                                ctx.arc(px, py, r, 0, Math.PI * 2);
                            }
                            queued += 1;
                        }
                        if (queued > 0)
                            ctx.fill();
                    }
                    continue;
                }
                for (let oi = 0; oi < nLen; ++oi) {
                    const i = renderOrder ? renderOrder[oi] : oi;
                    const n = nodes[i];
                    const ptx = sxBuf[i];
                    const pty = syBuf[i];
                    if (ptx < -28 || ptx > width + 28 || pty < -28 || pty > height + 28)
                        continue;

                    const isHovered = (i === activeIdx);
                    const isNeighbor = Boolean(activeNeighbors && activeNeighbors[i]);
                    const isCurrent = (root.currentPath.length > 0 && n.relPath === root.currentPath);
                    const isCenter = Boolean(root.isLocal && n.hop === 0);
                    const isTagHub = Boolean(n.isTagNode);
                    const deg = Number(n.degree ?? 0);
                    const isHub = (!root.isLocal && (isTagHub || deg >= 10));
                    const isForeground = (isHovered || isCurrent || isCenter || isHub);
                    if (!mode3D && ((pass === 0 && isForeground) || (pass === 1 && !isForeground)))
                        continue;
                    if (mode3D && pass === 1)
                        continue;

                    const dimmed = (activeIdx >= 0 && !isHovered && !isNeighbor && !isCurrent);
                    const depthScale = mode3D ? scBuf[i] : 1.0;
                    const depthFade = mode3D ? Math.max(0.32, Math.min(1.0, 0.72 + zdBuf[i] * 0.34)) : 1.0;
                    const r = root._nodeRadius(n, m.sizeScale) * scaleR * depthScale * (isHovered ? 1.25 : 1.0);
                    const cached = root.resolvedNodeColors[i] || {
                        "base": acc,
                        "deg2": Qt.rgba(acc.r, acc.g, acc.b, 0.90),
                        "leaf": Qt.rgba(acc.r, acc.g, acc.b, 0.72),
                        "isOrphan": false
                    };
                    const nodeColor = cached.base;

                    // Soft glow halo for tag hubs, hovered, current, local center, or major hubs
                    const showHalo = !dimmed && (isHovered || isCurrent || isCenter || isTagHub || (!root.compact && deg >= 16));
                    if (showHalo) {
                        ctx.beginPath();
                        ctx.arc(ptx, pty, r + (isHovered ? 3.2 : (isTagHub ? 2.6 : 1.6)) * depthScale, 0, Math.PI * 2);
                        ctx.fillStyle = Qt.rgba(nodeColor.r, nodeColor.g, nodeColor.b,
                            (isHovered ? 0.34 : (isTagHub ? 0.24 : 0.16)) * depthFade);
                        ctx.fill();
                    }

                    ctx.beginPath();
                    if (isTagHub) {
                        // Crisp faceted diamond badge for virtual #Tag hub nodes
                        const dr = r * 1.18;
                        ctx.moveTo(ptx, pty - dr);
                        ctx.lineTo(ptx + dr, pty);
                        ctx.lineTo(ptx, pty + dr);
                        ctx.lineTo(ptx - dr, pty);
                        ctx.closePath();
                    } else {
                        ctx.arc(ptx, pty, r, 0, Math.PI * 2);
                    }

                    if (isHovered) {
                        ctx.fillStyle = root.textColor;
                    } else if (isCurrent) {
                        ctx.fillStyle = acc;
                    } else if (root.isLocal) {
                        ctx.fillStyle = n.hop === 0
                            ? (dimmed ? Qt.rgba(acc.r, acc.g, acc.b, 0.35) : acc)
                            : (dimmed
                                ? Qt.rgba(muted.r, muted.g, muted.b, 0.18)
                                : (isNeighbor ? root.textColor : (n.hop === 1 ? cached.deg2 : cached.leaf)));
                    } else if (isHub) {
                        ctx.fillStyle = dimmed
                            ? Qt.rgba(nodeColor.r, nodeColor.g, nodeColor.b, 0.24 * depthFade)
                            : Qt.rgba(nodeColor.r, nodeColor.g, nodeColor.b, depthFade);
                    } else if (cached.isOrphan) {
                        ctx.fillStyle = dimmed
                            ? Qt.rgba(muted.r, muted.g, muted.b, 0.14 * depthFade)
                            : Qt.rgba(nodeColor.r, nodeColor.g, nodeColor.b, 0.58 * depthFade);
                    } else {
                        ctx.fillStyle = dimmed
                            ? Qt.rgba(muted.r, muted.g, muted.b, 0.15 * depthFade)
                            : (isNeighbor ? root.textColor : Qt.rgba(nodeColor.r, nodeColor.g, nodeColor.b, (deg >= 2 ? 0.92 : 0.78) * depthFade));
                    }
                    ctx.fill();

                    if (isHovered || isCurrent || isTagHub) {
                        ctx.lineWidth = isTagHub ? 1.25 : 1.0;
                        ctx.strokeStyle = isHovered
                            ? nodeColor
                            : (isTagHub ? Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.85 * depthFade) : root.textColor);
                        ctx.stroke();
                    }
                }
            }

            // 4. Draw labels (virtual tag hubs show prominently as cluster centers; deeper zoom reveals all labels cleanly)
            for (let oi = 0; oi < nLen; ++oi) {
                const i = renderOrder ? renderOrder[oi] : oi;
                const n = nodes[i];
                const ptx = sxBuf[i];
                const pty = syBuf[i];
                if (ptx < -20 || ptx > width + 20 || pty < -20 || pty > height + 20)
                    continue;

                const isHovered = (i === activeIdx);
                const isNeighbor = Boolean(activeNeighbors && activeNeighbors[i]);
                const isCurrent = (root.currentPath.length > 0 && n.relPath === root.currentPath);
                const isTagHub = Boolean(n.isTagNode);
                const deg = Number(n.degree ?? 0);
                const isHub = isTagHub || Boolean(n.isHub) || deg >= 8;

                let showLabel = false;
                if (root.isLocal) {
                    showLabel = root.compact
                        ? (isHovered || isCurrent || n.hop === 0 || nodes.length <= 5 || root.zoom >= 1.65)
                        : (isHovered || isCurrent || n.hop === 0 || n.hop === 1 || root.zoom >= 1.35);
                } else if (root.compact) {
                    showLabel = isHovered || (isTagHub && root.zoom >= 1.35) || (root.zoom >= 2.2 && (isCurrent || isNeighbor || isHub)) || root.zoom >= 4.0;
                } else {
                    if (activeIdx >= 0) {
                        showLabel = isHovered || isNeighbor || isTagHub || deg >= 15;
                    } else {
                        showLabel = (isCurrent || isTagHub || deg >= 15 || nodes.length <= 36
                            || (root.zoom >= 1.65 && isHub)
                            || (root.zoom >= 2.15 && deg >= 2)
                            || root.zoom >= 2.8);
                    }
                }

                if (!showLabel)
                    continue;

                const depthScale = mode3D ? scBuf[i] : 1.0;
                const depthFade = mode3D ? Math.max(0.35, Math.min(1.0, 0.78 + zdBuf[i] * 0.30)) : 1.0;
                const r = root._nodeRadius(n, m.sizeScale) * scaleR * depthScale;
                const rawTitle = String(n.title ?? "");
                const maxLen = isHovered ? 42 : (root.compact ? 22 : (root.zoom >= 5.0 ? 36 : 26));
                const label = rawTitle.length > maxLen ? (rawTitle.substring(0, maxLen - 1) + "…") : rawTitle;

                const fontPx = Math.round(Math.max(10, Math.min(14, (isTagHub || isHovered ? 12 : 11) * (mode3D ? Math.max(0.82, Math.min(1.15, depthScale)) : 1.0))));
                ctx.font = (isHovered || isCurrent || isTagHub || (root.isLocal && n.hop === 0) || isHub)
                    ? ("bold " + fontPx + "px sans-serif")
                    : (fontPx + "px sans-serif");
                const textW = ctx.measureText(label).width;
                const lx = Math.max(4, Math.min(width - textW - 4, ptx - textW * 0.5));
                const rawLy = pty + r + 13;
                const ly = (rawLy > height - 6)
                    ? Math.max(14, pty - r - 6)
                    : Math.max(14, Math.min(height - 6, rawLy));

                if (isHovered || isTagHub) {
                    ctx.fillStyle = Qt.rgba(root.bgSurface.r, root.bgSurface.g, root.bgSurface.b, isHovered ? 0.92 : 0.72);
                    ctx.fillRect(lx - 5, ly - fontPx, textW + 10, fontPx + 5);
                }

                const nodeCol = root.resolvedNodeColors[i]?.base ?? acc;
                ctx.fillStyle = isHovered
                    ? root.textColor
                    : (isTagHub
                        ? Qt.rgba(nodeCol.r, nodeCol.g, nodeCol.b, depthFade)
                        : (isCurrent ? acc : Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, depthFade)));
                ctx.fillText(label, lx, ly);
            }
        }
    }

    // ─── EQ-DSP Electric Current Overlay Canvas (Connected/Clustered Notes ONLY, ZERO animation on orphans) ───
    Canvas {
        id: electricCanvas
        anchors.fill: parent
        antialiasing: true
        visible: root.electricCurrentActive

        function _drawElectricArc(ctx, x0, y0, x1, y1, col, now, seed, bidirPhase, compactScale, fadeAlpha) {
            const alpha = Math.max(0.0, Math.min(1.0, fadeAlpha));
            if (alpha < 0.04) return;
            const dx = x1 - x0;
            const dy = y1 - y0;
            const dist = Math.sqrt(dx * dx + dy * dy);
            if (dist < 8.0) return;
            const nx = -dy / dist;
            const ny = dx / dist;
            const segs = Math.max(5, Math.min(12, Math.floor(dist / 16)));
            const baseAmp = Math.min(4.2, Math.max(1.1, dist * 0.032)) * compactScale;

            function plasmaOffset(t, strokeIdx, ampScale) {
                if (t <= 0.001 || t >= 0.999) return 0;
                const env = Math.sin(t * Math.PI);
                const sPos = t * segs;
                return Math.sin(now * (7.2 + strokeIdx * 1.4) + seed * 1.9 + sPos * 2.3)
                    * Math.cos(now * 5.6 - seed + sPos * 1.7)
                    * baseAmp * env * ampScale;
            }

            // Exact 3-stroke Music EQ DSP plasma language (outer glow -> mid plasma -> white core)
            for (let stroke = 0; stroke < 3; ++stroke) {
                const ampScale = stroke === 0 ? 1.2 : (stroke === 1 ? 0.85 : 0.45);
                ctx.beginPath();
                for (let s = 0; s <= segs; ++s) {
                    const t = s / segs;
                    const jitter = (s === 0 || s === segs) ? 0 : plasmaOffset(t, stroke, ampScale);
                    const px = x0 + dx * t + nx * jitter;
                    const py = y0 + dy * t + ny * jitter;
                    if (s === 0) ctx.moveTo(px, py);
                    else ctx.lineTo(px, py);
                }
                if (stroke === 0) {
                    ctx.strokeStyle = Qt.rgba(col.r, col.g, col.b, 0.24 * alpha);
                    ctx.lineWidth = 4.2 * compactScale;
                } else if (stroke === 1) {
                    const mid = Qt.lighter(col, 1.22);
                    ctx.strokeStyle = Qt.rgba(mid.r, mid.g, mid.b, 0.62 * alpha);
                    ctx.lineWidth = 1.8 * compactScale;
                } else {
                    ctx.strokeStyle = Qt.rgba(1.0, 1.0, 1.0, 0.86 * alpha);
                    ctx.lineWidth = 0.8 * compactScale;
                }
                ctx.lineCap = "round";
                ctx.lineJoin = "round";
                ctx.stroke();
            }

            // Bidirectional traveling charge pulse riding the core plasma curve
            for (let dir = 0; dir < (root.isLocal ? 2 : 1); ++dir) {
                const pos = dir === 0
                    ? ((bidirPhase) % 1.0)
                    : (1.0 - ((bidirPhase + 0.5) % 1.0));
                const tailT = dir === 0 ? Math.max(0.0, pos - 0.16) : Math.min(1.0, pos + 0.16);
                const midT = (pos + tailT) * 0.5;
                const pJ = plasmaOffset(pos, 2, 0.45);
                const mJ = plasmaOffset(midT, 2, 0.45);
                const tJ = plasmaOffset(tailT, 2, 0.45);
                const px = x0 + dx * pos + nx * pJ;
                const py = y0 + dy * pos + ny * pJ;
                const mx = x0 + dx * midT + nx * mJ;
                const my = y0 + dy * midT + ny * mJ;
                const tx = x0 + dx * tailT + nx * tJ;
                const ty = y0 + dy * tailT + ny * tJ;

                ctx.beginPath();
                ctx.moveTo(tx, ty);
                ctx.lineTo(mx, my);
                ctx.lineTo(px, py);
                ctx.strokeStyle = Qt.rgba(1.0, 1.0, 1.0, 0.85 * alpha);
                ctx.lineWidth = 1.7 * compactScale;
                ctx.stroke();

                ctx.beginPath();
                ctx.arc(px, py, 2.3 * compactScale, 0, Math.PI * 2);
                ctx.fillStyle = Qt.rgba(col.r, col.g, col.b, 0.42 * alpha);
                ctx.fill();
                ctx.beginPath();
                ctx.arc(px, py, 1.25 * compactScale, 0, Math.PI * 2);
                ctx.fillStyle = Qt.rgba(1.0, 1.0, 1.0, 0.96 * alpha);
                ctx.fill();
            }
        }

        onPaint: {
            if (!root.electricCurrentActive) return;
            if (width < 10 || height < 10) return;
            const ctx = getContext("2d");
            if (!ctx) return;
            ctx.clearRect(0, 0, width, height);
            root.electricPaintCount += 1;

            const sxBuf = root._screenXBuf;
            const syBuf = root._screenYBuf;
            const eSrc = root._edgeSrcBuf;
            const eDst = root._edgeDstBuf;
            const isOrph = root._isOrphanBuf;
            const eLen = root.resolvedEdges.length;
            if (!sxBuf || !syBuf || !eSrc || !eDst || eLen <= 0) return;

            const now = root._electricPhase * 3.1;
            const compactScale = root.compact ? 0.72 : 1.0;
            const activeIdx = root.draggedIndex >= 0 ? root.draggedIndex : root.hoveredIndex;
            const acc = root.accentColor;

            // Prioritize edges connected to hovered/active node, then smoothly cycle pulses across clustered edges
            const maxActiveArcs = root.isLocal ? Math.min(eLen, 24) : (root.compact ? 14 : 28);
            let drawn = 0;

            // First pass: incident edges of hovered/dragged node at full intensity
            if (activeIdx >= 0) {
                for (let e = 0; e < eLen && drawn < maxActiveArcs; ++e) {
                    const sIdx = eSrc[e];
                    const tIdx = eDst[e];
                    if (sIdx !== activeIdx && tIdx !== activeIdx) continue;
                    if (isOrph && (isOrph[sIdx] === 1 || isOrph[tIdx] === 1)) continue;
                    const x0 = sxBuf[sIdx], y0 = syBuf[sIdx];
                    const x1 = sxBuf[tIdx], y1 = syBuf[tIdx];
                    if ((x0 < -12 && x1 < -12) || (x0 > width + 12 && x1 > width + 12)
                            || (y0 < -12 && y1 < -12) || (y0 > height + 12 && y1 > height + 12)) continue;
                    const col = root.resolvedNodeColors[sIdx]?.base ?? acc;
                    _drawElectricArc(ctx, x0, y0, x1, y1, col, now, e + 1, (root._electricPhase * 0.55 + e * 0.17) % 1.0, compactScale, 1.0);
                    drawn += 1;
                }
            }

            // Second pass: ambient traveling electric current with smooth fade-in/out per slot (zero abrupt strobing/teleporting)
            const remainingSlots = Math.max(0, maxActiveArcs - drawn);
            if (eLen <= remainingSlots) {
                for (let e = 0; e < eLen && drawn < maxActiveArcs; ++e) {
                    const sIdx = eSrc[e];
                    const tIdx = eDst[e];
                    if (activeIdx >= 0 && (sIdx === activeIdx || tIdx === activeIdx)) continue;
                    if (isOrph && (isOrph[sIdx] === 1 || isOrph[tIdx] === 1)) continue;
                    const x0 = sxBuf[sIdx], y0 = syBuf[sIdx];
                    const x1 = sxBuf[tIdx], y1 = syBuf[tIdx];
                    if ((x0 < -12 && x1 < -12) || (x0 > width + 12 && x1 > width + 12)
                            || (y0 < -12 && y1 < -12) || (y0 > height + 12 && y1 > height + 12)) continue;
                    const col = root.resolvedNodeColors[sIdx]?.base ?? acc;
                    _drawElectricArc(ctx, x0, y0, x1, y1, col, now, e + 1, (root._electricPhase * 0.42 + e * 0.23) % 1.0, compactScale, 0.92);
                    drawn += 1;
                }
            } else {
                for (let slot = 0; slot < remainingSlots; ++slot) {
                    const cycle = root._electricPhase * 0.34 + slot * 0.37;
                    const generation = Math.floor(cycle);
                    const localT = cycle - generation;
                    const fadeAlpha = Math.sin(localT * Math.PI);
                    if (fadeAlpha < 0.05) continue;
                    const e = (generation * remainingSlots + slot * 7) % eLen;
                    const sIdx = eSrc[e];
                    const tIdx = eDst[e];
                    if (activeIdx >= 0 && (sIdx === activeIdx || tIdx === activeIdx)) continue;
                    if (isOrph && (isOrph[sIdx] === 1 || isOrph[tIdx] === 1)) continue;
                    const x0 = sxBuf[sIdx], y0 = syBuf[sIdx];
                    const x1 = sxBuf[tIdx], y1 = syBuf[tIdx];
                    if ((x0 < -12 && x1 < -12) || (x0 > width + 12 && x1 > width + 12)
                            || (y0 < -12 && y1 < -12) || (y0 > height + 12 && y1 > height + 12)) continue;
                    const col = root.resolvedNodeColors[sIdx]?.base ?? acc;
                    _drawElectricArc(ctx, x0, y0, x1, y1, col, now, e + 1, localT, compactScale, fadeAlpha);
                    drawn += 1;
                }
            }
        }
    }

    MouseArea {
        id: graphMouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        cursorShape: {
            if (root.draggedIndex >= 0 || pressed)
                return Qt.ClosedHandCursor;
            if (root.hoveredIndex >= 0)
                return Qt.PointingHandCursor;
            return Qt.OpenHandCursor;
        }

        property real pressX: 0
        property real pressY: 0
        property real lastX: 0
        property real lastY: 0
        property bool movedSignificantly: false
        property bool panOverride: false

        onPressed: mouse => {
            pressX = mouse.x;
            pressY = mouse.y;
            lastX = mouse.x;
            lastY = mouse.y;
            movedSignificantly = false;
            panOverride = (mouse.button === Qt.MiddleButton) || Boolean(mouse.modifiers & Qt.ShiftModifier);
            const hit = root.findNodeAtScreen(mouse.x, mouse.y);
            root.draggedIndex = (!root.is3D && !panOverride) ? hit : -1;
            root.hoveredIndex = hit;
            root.requestPaint();
        }

        onPositionChanged: mouse => {
            if (!pressed) {
                const hit = root.findNodeAtScreen(mouse.x, mouse.y);
                if (hit !== root.hoveredIndex) {
                    root.hoveredIndex = hit;
                    root.requestPaint();
                }
                return;
            }

            const totalDx = mouse.x - pressX;
            const totalDy = mouse.y - pressY;
            if (totalDx * totalDx + totalDy * totalDy > 25)
                movedSignificantly = true;

            const stepDx = mouse.x - lastX;
            const stepDy = mouse.y - lastY;
            lastX = mouse.x;
            lastY = mouse.y;

            if (root.is3D && !panOverride) {
                // Orbit 3D constellation smoothly
                root.rotYaw += stepDx * 0.0085;
                root.rotPitch = Math.max(-1.42, Math.min(1.42, root.rotPitch + stepDy * 0.0085));
                root.requestPaint();
            } else if (root.draggedIndex >= 0 && root.draggedIndex < root.nodePositions.length) {
                const norm = root._normalizedFromScreen(mouse.x, mouse.y);
                const prev = root.nodePositions[root.draggedIndex];
                const ndx = norm.x - prev.x;
                const ndy = norm.y - prev.y;
                root.nodePositions[root.draggedIndex] = { "x": norm.x, "y": norm.y, "z": prev.z ?? 0.5 };
                if (root._normXBuf && root.draggedIndex < root._normXBuf.length) {
                    root._normXBuf[root.draggedIndex] = norm.x;
                    root._normYBuf[root.draggedIndex] = norm.y;
                }

                const neighbors = root._neighborsFor(root.draggedIndex);
                if (neighbors) {
                    const nKeys = Object.keys(neighbors);
                    for (let k = 0; k < nKeys.length; ++k) {
                        const nIdx = Number(nKeys[k]);
                        if (nIdx >= 0 && nIdx < root.nodePositions.length && nIdx !== root.draggedIndex) {
                            const np = root.nodePositions[nIdx];
                            const nx = Math.max(0.03, Math.min(0.97, np.x + ndx * 0.22));
                            const ny = Math.max(0.03, Math.min(0.97, np.y + ndy * 0.22));
                            root.nodePositions[nIdx] = { "x": nx, "y": ny, "z": np.z ?? 0.5 };
                            if (root._normXBuf && nIdx < root._normXBuf.length) {
                                root._normXBuf[nIdx] = nx;
                                root._normYBuf[nIdx] = ny;
                            }
                        }
                    }
                }
                root.requestPaint();
            } else {
                root.panX += stepDx;
                root.panY += stepDy;
                root.requestPaint();
            }
        }

        onReleased: mouse => {
            const wasDraggingNode = root.draggedIndex;
            root.draggedIndex = -1;
            if (!movedSignificantly) {
                const hit = wasDraggingNode >= 0 ? wasDraggingNode : root.findNodeAtScreen(mouse.x, mouse.y);
                const g = root.graphData;
                if (hit >= 0 && g && Array.isArray(g.nodes) && hit < g.nodes.length) {
                    root.nodeActivated(g.nodes[hit]);
                }
            }
            root.requestPaint();
        }

        onExited: {
            if (!pressed && root.hoveredIndex !== -1) {
                root.hoveredIndex = -1;
                root.requestPaint();
            }
        }

        onWheel: wheel => {
            const factor = wheel.angleDelta.y > 0 ? 1.22 : 0.82;
            root.zoomBy(factor, wheel.x, wheel.y);
            wheel.accepted = true;
        }
    }

    // Floating 2D/3D Switcher (Expanded Vault Graph) + Deep Zoom Controls
    RowLayout {
        id: zoomControlsBar
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: root.compact ? 4 : 10
        spacing: 4
        visible: root.width > 120 && root.height > 90
        opacity: (!root.compact || root.canvasHovered || zoomOutMouse.containsMouse || zoomResetMouse.containsMouse || zoomInMouse.containsMouse) ? 1.0 : 0.0
        Behavior on opacity {
            NumberAnimation { duration: 150 }
        }

        // 2D | 3D Mode Switcher (only shown on expanded full-page Vault Graph)
        Rectangle {
            id: renderModeSwitcher
            objectName: "nexusGraphRenderModeSwitcher"
            visible: root.allow3D
            implicitWidth: 66
            implicitHeight: 24
            radius: 6
            color: Qt.rgba(root.bgSurface.r, root.bgSurface.g, root.bgSurface.b, 0.90)
            border.width: 1
            border.color: root.borderSubtle

            RowLayout {
                anchors.fill: parent
                anchors.margins: 2
                spacing: 2

                Repeater {
                    model: ["2d", "3d"]
                    delegate: Rectangle {
                        id: modePill
                        required property string modelData
                        readonly property bool active: root.renderMode === modelData
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 4
                        color: active ? root.accentColor : "transparent"

                        StyledText {
                            anchors.centerIn: parent
                            text: modePill.modelData.toUpperCase()
                            font.pixelSize: 10
                            font.weight: Font.Bold
                            color: modePill.active
                                ? (Appearance.colors?.colOnPrimary ?? "#0b1114")
                                : root.subtextColor
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.setRenderMode(modePill.modelData)
                        }
                    }
                }
            }
        }

        // Zoom readout pill when zoomed deep in expanded view
        Rectangle {
            visible: !root.compact && Math.abs(root.zoom - 1.0) > 0.05
            implicitWidth: zoomValTxt.implicitWidth + 10
            implicitHeight: 24
            radius: 5
            color: Qt.rgba(root.bgSurface.r, root.bgSurface.g, root.bgSurface.b, 0.86)
            border.width: 1
            border.color: root.borderSubtle
            StyledText {
                id: zoomValTxt
                anchors.centerIn: parent
                text: `${root.zoom.toFixed(1)}×`
                font.pixelSize: 10
                font.weight: Font.DemiBold
                font.features: ({ "tnum": 1 })
                color: root.subtextColor
            }
        }

        Rectangle {
            implicitWidth: root.compact ? 20 : 24
            implicitHeight: root.compact ? 20 : 24
            width: implicitWidth
            height: implicitHeight
            radius: 5
            color: Qt.rgba(root.bgSurface.r, root.bgSurface.g, root.bgSurface.b, 0.86)
            border.width: 1
            border.color: root.borderSubtle
            StyledText {
                anchors.centerIn: parent
                text: "-"
                font.pixelSize: root.compact ? 11 : 13
                font.weight: Font.Bold
                color: root.textColor
            }
            MouseArea {
                id: zoomOutMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.zoomOut()
            }
        }

        Rectangle {
            implicitWidth: root.compact ? 20 : 24
            implicitHeight: root.compact ? 20 : 24
            width: implicitWidth
            height: implicitHeight
            radius: 5
            color: Qt.rgba(root.bgSurface.r, root.bgSurface.g, root.bgSurface.b, 0.86)
            border.width: 1
            border.color: root.borderSubtle
            MaterialSymbol {
                anchors.centerIn: parent
                text: "center_focus_strong"
                iconSize: root.compact ? 12 : 14
                color: root.accentColor
            }
            MouseArea {
                id: zoomResetMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.resetView()
            }
        }

        Rectangle {
            implicitWidth: root.compact ? 20 : 24
            implicitHeight: root.compact ? 20 : 24
            width: implicitWidth
            height: implicitHeight
            radius: 5
            color: Qt.rgba(root.bgSurface.r, root.bgSurface.g, root.bgSurface.b, 0.86)
            border.width: 1
            border.color: root.borderSubtle
            StyledText {
                anchors.centerIn: parent
                text: "+"
                font.pixelSize: root.compact ? 11 : 13
                font.weight: Font.Bold
                color: root.textColor
            }
            MouseArea {
                id: zoomInMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.zoomIn()
            }
        }
    }
}
