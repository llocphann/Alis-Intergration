import QtQuick
import QtQuick.Layouts
import Quickshell
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
    property string currentPath: ""
    property var clusterPalette: ["#7dcfff", "#bb9af7", "#9ece6a", "#e0af68", "#f7768e", "#73daca", "#ff9e64", "#2ac3de"]

    signal nodeActivated(var nodeData)

    // Viewport transform state
    property real zoom: 1.0
    property real panX: 0.0
    property real panY: 0.0

    // Interactive state
    property int hoveredIndex: -1
    property int draggedIndex: -1
    readonly property string hoveredId: (root.hoveredIndex >= 0 && root.graphData?.nodes && root.hoveredIndex < root.graphData.nodes.length)
        ? String(root.graphData.nodes[root.hoveredIndex]?.id ?? "")
        : ""
    property bool canvasHovered: graphMouse.containsMouse
    property var nodePositions: [] // [{ x: 0..1, y: 0..1 }]
    property var resolvedEdges: [] // [{ s: int, t: int }]
    property var resolvedNodeColors: [] // [{ base: color, deg2: color, leaf: color, hex: string }]
    property var adjacencyMap: ({}) // index -> { neighborIdx: true } (populated lazily)
    property int revealStaggerMs: 0
    property var _screenXBuf: null
    property var _screenYBuf: null
    property var _normXBuf: null
    property var _normYBuf: null
    property var _baseRadBuf: null
    property var _nodeDegBuf: null
    property var _edgeSrcBuf: null
    property var _edgeDstBuf: null
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
    property string lastPaintedAccentHex: ""
    property string lastPaintedNodeHex: ""
    property string lastPaintedThemeSignature: ""

    readonly property color accentColor: root.workspace ? Qt.color(root.workspace._settledPrimary) : (Appearance.colors?.colPrimary ?? "#82c2cf")
    readonly property color textColor: root.workspace ? Qt.color(root.workspace._settledOnLayer1) : (Appearance.colors?.colOnLayer1 ?? "#d9e1e3")
    readonly property color subtextColor: root.workspace ? Qt.color(root.workspace._settledSubtext) : (Appearance.colors?.colSubtext ?? "#8f9d9f")
    readonly property color mutedTextColor: root.workspace ? Qt.color(root.workspace._settledSubtext) : (Appearance.colors?.colSubtext ?? "#8f9d9f")
    readonly property color borderSubtle: root.workspace ? Qt.color(root.workspace._settledBorder) : (Appearance.colors?.colLayer0Border ?? "#2a3439")
    readonly property color bgSurface: root.workspace ? Qt.color(root.workspace._settledLayer1) : (Appearance.colors?.colLayer1 ?? "#10181b")
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

    function _isDefaultStaticGraphHex(hexStr: string): bool {
        const h = String(hexStr || "").trim().toLowerCase();
        return h === ""
            || h === "#8dc9d6"
            || h === "#87c2d0"
            || h === "#81be99"
            || h === "#7ac1e2"
            || h === "#6cc0e4"
            || h === "#5fa1c6"
            || h === "#4a93ba"
            || h === "#3c81a3"
            || h === "#344145"
            || h === "#3d484b"
            || h === "#353d3f"
            || h === "#7bb5c1"
            || h === "#73a7b3"
            || h === "#6c9da8"
            || h === "#638d97"
            || h === "#577980"
            || h === "#516f75"
            || h === "#43595e"
            || h === "#82c2cf";
    }

    function _extractPrefixCode(n: var): string {
        const candidates = [n?.group, n?.folder, n?.relPath];
        for (let i = 0; i < candidates.length; ++i) {
            const s = String(candidates[i] ?? "").trim();
            if (s.length >= 2 && s.charCodeAt(0) >= 48 && s.charCodeAt(0) <= 57 && s.charCodeAt(1) >= 48 && s.charCodeAt(1) <= 57) {
                return s.substring(0, 2);
            }
        }
        return "";
    }

    function _resolveNodeBaseColor(n: var): color {
        const acc = root.accentColor;
        const muted = root.mutedTextColor;
        if (root.isLocal) {
            const hop = Number(n?.hop ?? 1);
            if (hop === 0)
                return acc;
            if (hop === 1)
                return root._mixColor(acc, muted, 0.72);
            return root._mixColor(acc, muted, 0.45);
        }
        const prefix = root._extractPrefixCode(n);
        if (prefix.length === 2) {
            if (root.workspace && typeof root.workspace.autoThemedFolderColor === "function") {
                const wsHex = String(root.workspace.autoThemedFolderColor(prefix, n?.colorHex ?? ""));
                if (wsHex.length > 0 && !root._isDefaultStaticGraphHex(wsHex))
                    return Qt.color(wsHex);
                if (wsHex.length > 0 && (prefix === "00" || prefix === "99" || prefix[1] === "0"))
                    return Qt.color(wsHex);
            }
            const weights = {
                "00": 1.00,
                "10": 0.85,
                "20": 0.72,
                "30": 0.62,
                "40": 0.55,
                "50": 0.48,
                "60": 0.40,
                "70": 0.28,
                "80": 0.20,
                "90": 0.14,
                "99": 0.08
            };
            const bucket = prefix === "99" ? "99" : (prefix[0] + "0");
            if (weights[bucket] !== undefined)
                return root._mixColor(acc, muted, weights[bucket]);
        }
        if (Boolean(n?.isJournal))
            return acc;
        const rawHex = String(n?.colorHex ?? "").trim();
        if (!root._isDefaultStaticGraphHex(rawHex)) {
            return Qt.tint(Qt.color(rawHex), Qt.rgba(acc.r, acc.g, acc.b, 0.42));
        }
        return root._mixColor(acc, muted, 0.72);
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
        const prefixCache = {};
        const useWsPrefix = root.workspace && typeof root.workspace.autoThemedFolderColor === "function" && !root.isLocal;
        const bucketMap = !root.isLocal ? Object.create(null) : null;
        for (let i = 0; i < nodes.length; ++i) {
            const n = nodes[i];
            let tc;
            if (useWsPrefix) {
                const prefix = root._extractPrefixCode(n);
                const cHex = String(n?.colorHex ?? "");
                if (prefix.length === 2 && cHex.length === 0) {
                    if (prefixCache[prefix] === undefined)
                        prefixCache[prefix] = root._resolveNodeBaseColor(n);
                    tc = prefixCache[prefix];
                } else {
                    tc = root._resolveNodeBaseColor(n);
                }
            } else {
                tc = root._resolveNodeBaseColor(n);
            }
            const deg2 = Qt.rgba(tc.r, tc.g, tc.b, 0.90);
            const leaf = Qt.rgba(
                tc.r * 0.86 + muted.r * 0.14,
                tc.g * 0.86 + muted.g * 0.14,
                tc.b * 0.86 + muted.b * 0.14,
                0.74
            );
            const hex = tc.toString();
            out[i] = {
                "base": tc,
                "deg2": deg2,
                "leaf": leaf,
                "hex": hex
            };
            if (bucketMap) {
                const deg = Number(n.degree ?? 0);
                if (deg < 14) {
                    const useDeg2 = deg >= 2;
                    const bKey = (useDeg2 ? "d:" : "l:") + hex;
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
        const pal = (Array.isArray(root.clusterPalette) && root.clusterPalette.length > 0)
            ? root.clusterPalette
            : ["#7dcfff", "#bb9af7", "#9ece6a", "#e0af68", "#f7768e", "#73daca", "#ff9e64", "#2ac3de"];
        const idx = Math.abs(Number(groupIdx || 0)) % pal.length;
        return pal[idx];
    }

    function resetView(): void {
        root.zoom = 1.0;
        root.panX = 0.0;
        root.panY = 0.0;
        root._syncPositionsFromData();
        root.requestPaint();
    }

    function zoomBy(factor: real, centerX: real, centerY: real): void {
        const oldZoom = root.zoom;
        const newZoom = Math.max(0.45, Math.min(6.0, oldZoom * factor));
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
        root.zoomBy(1.25, root.width * 0.5, root.height * 0.5);
    }

    function zoomOut(): void {
        root.zoomBy(0.8, root.width * 0.5, root.height * 0.5);
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
    }

    function _baseRadiusFactor(n: var): real {
        if (root.isLocal) {
            if (n.hop === 0)
                return root.compact ? 3.0 : 4.2;
            if (n.hop === 1)
                return root.compact ? 1.9 : 2.7;
            return root.compact ? 1.35 : 1.85;
        }
        const deg = Number(n.degree ?? 0);
        if (root.compact) {
            if (deg >= 14)
                return Math.min(2.2, 1.40 + Math.log(deg + 1) * 0.16);
            if (deg >= 5)
                return 1.18;
            if (deg >= 2)
                return 0.94;
            if (deg === 1)
                return 0.78;
            return 0.65;
        }
        if (deg >= 14)
            return Math.min(3.2, 1.80 + Math.log(deg + 1) * 0.22);
        if (deg >= 5)
            return 1.55;
        if (deg >= 2)
            return 1.20;
        if (deg === 1)
            return 0.98;
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
            root._baseRadBuf = null;
            root._nodeDegBuf = null;
            root._edgeSrcBuf = null;
            root._edgeDstBuf = null;
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
        const baseRadBuf = new Float32Array(nLen);
        const degBuf = new Int32Array(nLen);
        const resEdges = [];
        const idToIdx = Object.create(null);
        let minX = 1.0, maxX = 0.0, minY = 1.0, maxY = 0.0, maxRad = 0.0;
        for (let i = 0; i < nLen; ++i) {
            const n = nodes[i];
            const nx = Number(n.x ?? 0.5);
            const ny = Number(n.y ?? 0.5);
            if (nx < minX) minX = nx;
            if (nx > maxX) maxX = nx;
            if (ny < minY) minY = ny;
            if (ny > maxY) maxY = ny;
            const rad = Math.max(Math.abs(nx - 0.5), Math.abs(ny - 0.5));
            if (rad > maxRad) maxRad = rad;
            nxBuf[i] = nx;
            nyBuf[i] = ny;
            degBuf[i] = Number(n.degree ?? 0);
            baseRadBuf[i] = root._baseRadiusFactor(n);
            pos[i] = {
                "x": nx,
                "y": ny
            };
            if (n.id !== undefined)
                idToIdx[n.id] = i;
        }
        for (let e = 0; e < edges.length; ++e) {
            const edge = edges[e];
            const sIdx = (edge.sourceIndex !== undefined) ? Number(edge.sourceIndex) : idToIdx[edge.source];
            const tIdx = (edge.targetIndex !== undefined) ? Number(edge.targetIndex) : idToIdx[edge.target];
            if (sIdx !== undefined && tIdx !== undefined && sIdx >= 0 && tIdx >= 0 && sIdx < nLen && tIdx < nLen) {
                resEdges.push({
                    "s": sIdx,
                    "t": tIdx
                });
            }
        }
        const eSrcBuf = new Int32Array(resEdges.length);
        const eDstBuf = new Int32Array(resEdges.length);
        for (let e = 0; e < resEdges.length; ++e) {
            eSrcBuf[e] = resEdges[e].s;
            eDstBuf[e] = resEdges[e].t;
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
        root._baseRadBuf = baseRadBuf;
        root._nodeDegBuf = degBuf;
        root._edgeSrcBuf = eSrcBuf;
        root._edgeDstBuf = eDstBuf;
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
        const spanX = isFewLocal
            ? uniformFit
            : (uniformFit * 0.74 + fitW * 0.26);
        const spanY = isFewLocal
            ? uniformFit
            : (uniformFit * 0.74 + fitH * 0.26);
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
            "sizeScale": sizeScale
        };
    }

    function _screenPosForNode(idx: int, metricsOverride = null): var {
        if (idx < 0 || idx >= root.nodePositions.length)
            return { "x": 0, "y": 0 };
        const p = root.nodePositions[idx];
        const m = metricsOverride || root._viewportMetrics();
        const baseX = m.originX + p.x * m.spanX;
        const baseY = m.originY + p.y * m.spanY;
        return {
            "x": baseX * root.zoom + root.panX,
            "y": baseY * root.zoom + root.panY
        };
    }

    function _normalizedFromScreen(sx: real, sy: real): var {
        const m = root._viewportMetrics();
        const baseX = (sx - root.panX) / Math.max(0.1, root.zoom);
        const baseY = (sy - root.panY) / Math.max(0.1, root.zoom);
        return {
            "x": Math.max(0.02, Math.min(0.98, (baseX - m.originX) / Math.max(1.0, m.spanX))),
            "y": Math.max(0.02, Math.min(0.98, (baseY - m.originY) / Math.max(1.0, m.spanY)))
        };
    }

    function _nodeRadius(n: var, a1 = undefined, a2 = undefined, a3 = undefined, a4 = undefined): real {
        const s = (typeof a1 === "number")
            ? a1
            : ((typeof a4 === "number") ? a4 : root._viewportMetrics().sizeScale);
        if (root.isLocal) {
            if (n.hop === 0)
                return (root.compact ? 3.0 : 4.2) * s;
            if (n.hop === 1)
                return (root.compact ? 1.9 : 2.7) * s;
            return (root.compact ? 1.35 : 1.85) * s;
        }
        const deg = Number(n.degree ?? 0);
        const isCur = root.currentPath.length > 0 && n.relPath === root.currentPath;
        if (root.compact) {
            if (isCur)
                return 2.15 * s;
            if (deg >= 14)
                return Math.min(2.2, 1.40 + Math.log(deg + 1) * 0.16) * s;
            if (deg >= 5)
                return 1.18 * s;
            if (deg >= 2)
                return 0.94 * s;
            if (deg === 1)
                return 0.78 * s;
            return 0.65 * s;
        }
        if (isCur)
            return 3.2 * s;
        if (deg >= 14)
            return Math.min(3.2, 1.80 + Math.log(deg + 1) * 0.22) * s;
        if (deg >= 5)
            return 1.55 * s;
        if (deg >= 2)
            return 1.20 * s;
        if (deg === 1)
            return 0.98 * s;
        return 0.82 * s;
    }

    function findNodeAtScreen(sx: real, sy: real): int {
        const g = root.graphData;
        if (!g || !Array.isArray(g.nodes) || root.nodePositions.length !== g.nodes.length)
            return -1;
        const nodes = g.nodes;
        const nLen = nodes.length;
        const m = root._viewportMetrics();
        const zoomFactor = Math.min(1.38, Math.max(0.75, Math.pow(root.zoom, 0.32)));
        const hitSlack = root.compact ? 5.5 : 8.5;
        const scaleMul = m.sizeScale * zoomFactor;
        const maxHitR = 4.4 * scaleMul + hitSlack;
        const mulX = m.spanX * root.zoom;
        const addX = m.originX * root.zoom + root.panX;
        const mulY = m.spanY * root.zoom;
        const addY = m.originY * root.zoom + root.panY;
        const nxBuf = root._normXBuf;
        const nyBuf = root._normYBuf;
        const baseRadBuf = root._baseRadBuf;
        const hasTyped = Boolean(nxBuf && nyBuf && baseRadBuf && nxBuf.length >= nLen && baseRadBuf.length >= nLen);
        const curPath = root.currentPath;
        const hasCurPath = !root.isLocal && curPath.length > 0;
        const curBaseR = root.compact ? 2.15 : 3.2;

        let bestIdx = -1;
        let bestDist2 = 999999;
        for (let i = nLen - 1; i >= 0; --i) {
            const px = hasTyped
                ? (nxBuf[i] * mulX + addX)
                : ((m.originX + root.nodePositions[i].x * m.spanX) * root.zoom + root.panX);
            const dx = px - sx;
            if (dx > maxHitR || dx < -maxHitR)
                continue;
            const py = hasTyped
                ? (nyBuf[i] * mulY + addY)
                : ((m.originY + root.nodePositions[i].y * m.spanY) * root.zoom + root.panY);
            const dy = py - sy;
            if (dy > maxHitR || dy < -maxHitR)
                continue;
            let baseR;
            if (hasTyped) {
                baseR = (hasCurPath && nodes[i].relPath === curPath) ? curBaseR : baseRadBuf[i];
            } else {
                baseR = root._nodeRadius(nodes[i], 1.0);
            }
            const r = baseR * scaleMul + hitSlack;
            const d2 = dx * dx + dy * dy;
            if (d2 <= r * r && d2 < bestDist2) {
                bestDist2 = d2;
                bestIdx = i;
            }
        }
        return bestIdx;
    }

    readonly property bool hostOpen: Boolean(root.workspace?.nexus?.isOpen ?? true)
    readonly property bool hostSettled: root.workspace ? Boolean(root.workspace.transitionSettled) : true
    readonly property bool hostSurfaceActive: Boolean(root.workspace ? root.workspace.surfaceActive : true)
    readonly property bool canRepaintTheme: root.visible && root.hostOpen && root.hostSurfaceActive && root.hostSettled

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

    onGraphDataChanged: {
        root._syncPositionsFromData();
        root.requestPaint();
    }
    onCurrentPathChanged: {
        root.requestPaint();
    }
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
    onCanRepaintThemeChanged: {
        root._flushPendingPaintOnResume();
    }
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
            // A frame queued before the host paused can still arrive afterward.
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

            // Precompute screen coordinates into reusable typed arrays (zero per-frame JS objects)
            if (!root._screenXBuf || root._screenXBuf.length < nLen) {
                root._screenXBuf = new Float32Array(Math.max(16, nLen));
                root._screenYBuf = new Float32Array(Math.max(16, nLen));
            }
            const sxBuf = root._screenXBuf;
            const syBuf = root._screenYBuf;
            const nxBuf = root._normXBuf;
            const nyBuf = root._normYBuf;
            const mulX = m.spanX * root.zoom;
            const addX = m.originX * root.zoom + root.panX;
            const mulY = m.spanY * root.zoom;
            const addY = m.originY * root.zoom + root.panY;
            for (let i = 0; i < nLen; ++i) {
                sxBuf[i] = nxBuf[i] * mulX + addX;
                syBuf[i] = nyBuf[i] * mulY + addY;
            }

            const eSrc = root._edgeSrcBuf;
            const eDst = root._edgeDstBuf;

            // 1. Draw non-highlighted edges first (batched & culled)
            if (root.isLocal) {
                ctx.lineWidth = root.compact ? 0.65 : 0.85;
                ctx.strokeStyle = activeIdx >= 0
                    ? Qt.rgba(acc.r, acc.g, acc.b, 0.08)
                    : Qt.rgba(acc.r * 0.82 + muted.r * 0.18, acc.g * 0.82 + muted.g * 0.18, acc.b * 0.82 + muted.b * 0.18, root.compact ? 0.22 : 0.28);
            } else {
                ctx.lineWidth = root.compact ? 0.32 : 0.46;
                ctx.strokeStyle = activeIdx >= 0
                    ? Qt.rgba(acc.r, acc.g, acc.b, 0.03)
                    : Qt.rgba(acc.r * 0.78 + muted.r * 0.22, acc.g * 0.78 + muted.g * 0.22, acc.b * 0.78 + muted.b * 0.22, root.compact ? 0.085 : 0.115);
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

            // 2. Draw highlighted incident edges when hovering/dragging a node
            if (activeIdx >= 0) {
                ctx.lineWidth = root.compact ? 0.90 : 1.25;
                ctx.strokeStyle = Qt.rgba(acc.r, acc.g, acc.b, 0.78);
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

            // 3. Draw nodes (pass 0: regular leaf nodes, pass 1: hubs / current / hovered on top)
            const scaleR = Math.min(1.32, Math.max(0.75, Math.pow(root.zoom, 0.30)));
            const scaleMul = m.sizeScale * scaleR;
            const baseRadBuf = root._baseRadBuf;
            const curPath = root.currentPath;
            const hasCurPath = curPath.length > 0;
            for (let pass = 0; pass < 2; ++pass) {
                if (pass === 0 && !root.isLocal && activeIdx < 0) {
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
                for (let i = 0; i < nodes.length; ++i) {
                    const n = nodes[i];
                    const ptx = sxBuf[i];
                    const pty = syBuf[i];
                    if (ptx < -24 || ptx > width + 24 || pty < -24 || pty > height + 24)
                        continue;

                    const isHovered = (i === activeIdx);
                    const isNeighbor = Boolean(activeNeighbors && activeNeighbors[i]);
                    const isCurrent = (root.currentPath.length > 0 && n.relPath === root.currentPath);
                    const isCenter = Boolean(root.isLocal && n.hop === 0);
                    const deg = Number(n.degree ?? 0);
                    const isHub = (!root.isLocal && deg >= 14);
                    const isForeground = (isHovered || isCurrent || isCenter || isHub);
                    if ((pass === 0 && isForeground) || (pass === 1 && !isForeground))
                        continue;

                    const dimmed = (activeIdx >= 0 && !isHovered && !isNeighbor && !isCurrent);
                    const r = root._nodeRadius(n, m.sizeScale) * scaleR * (isHovered ? 1.25 : 1.0);
                    const cached = root.resolvedNodeColors[i] || {
                        "base": acc,
                        "deg2": Qt.rgba(acc.r, acc.g, acc.b, 0.90),
                        "leaf": Qt.rgba(acc.r, acc.g, acc.b, 0.72)
                    };
                    const nodeColor = cached.base;

                    // Tight glow halo only for hovered, current, local-center, or major hubs in full view
                    const showHalo = !dimmed && (isHovered || isCurrent || isCenter || (!root.compact && deg >= 22));
                    if (showHalo) {
                        ctx.beginPath();
                        ctx.arc(ptx, pty, r + (isHovered ? 2.8 : 1.5), 0, Math.PI * 2);
                        ctx.fillStyle = isHovered
                            ? Qt.rgba(acc.r, acc.g, acc.b, 0.32)
                            : (isCurrent
                                ? Qt.rgba(acc.r, acc.g, acc.b, 0.24)
                                : Qt.rgba(acc.r, acc.g, acc.b, 0.14));
                        ctx.fill();
                    }

                    ctx.beginPath();
                    ctx.arc(ptx, pty, r, 0, Math.PI * 2);
                    if (isHovered) {
                        ctx.fillStyle = root.textColor;
                    } else if (isCurrent) {
                        ctx.fillStyle = acc;
                    } else if (root.isLocal) {
                        ctx.fillStyle = n.hop === 0
                            ? (dimmed ? Qt.rgba(acc.r, acc.g, acc.b, 0.35) : acc)
                            : (dimmed
                                ? Qt.rgba(muted.r, muted.g, muted.b, 0.18)
                                : (isNeighbor
                                    ? root.textColor
                                    : (n.hop === 1 ? cached.deg2 : cached.leaf)));
                    } else if (isHub) {
                        ctx.fillStyle = dimmed ? Qt.rgba(acc.r, acc.g, acc.b, 0.26) : nodeColor;
                    } else {
                        ctx.fillStyle = dimmed
                            ? Qt.rgba(muted.r, muted.g, muted.b, 0.15)
                            : (isNeighbor ? root.textColor : (deg >= 2 ? cached.deg2 : cached.leaf));
                    }
                    ctx.fill();

                    if (isHovered || isCurrent) {
                        ctx.lineWidth = 1.0;
                        ctx.strokeStyle = isHovered ? acc : root.textColor;
                        ctx.stroke();
                    }
                }
            }

            // 4. Draw labels (in compact Vault Graph: ONLY on hover or when closely zoomed in >= 2.2)
            for (let i = 0; i < nodes.length; ++i) {
                const n = nodes[i];
                const ptx = sxBuf[i];
                const pty = syBuf[i];
                if (ptx < -20 || ptx > width + 20 || pty < -20 || pty > height + 20)
                    continue;

                const isHovered = (i === activeIdx);
                const isNeighbor = Boolean(activeNeighbors && activeNeighbors[i]);
                const isCurrent = (root.currentPath.length > 0 && n.relPath === root.currentPath);
                const deg = Number(n.degree ?? 0);
                const isHub = Boolean(n.isHub) || deg >= 8;

                let showLabel = false;
                if (root.isLocal) {
                    showLabel = root.compact
                        ? (isHovered || isCurrent || n.hop === 0 || nodes.length <= 5 || root.zoom >= 1.65)
                        : (isHovered || isCurrent || n.hop === 0 || n.hop === 1 || root.zoom >= 1.35);
                } else if (root.compact) {
                    showLabel = isHovered || (root.zoom >= 2.2 && (isCurrent || isNeighbor || isHub));
                } else {
                    if (activeIdx >= 0) {
                        showLabel = isHovered || isNeighbor || deg >= 15;
                    } else {
                        showLabel = (isCurrent || deg >= 15 || nodes.length <= 36 || (root.zoom >= 1.75 && isHub) || (root.zoom >= 2.15 && deg >= 2) || root.zoom >= 2.8);
                    }
                }

                if (!showLabel)
                    continue;

                const r = root._nodeRadius(n, m.sizeScale) * scaleR;
                const rawTitle = String(n.title ?? "");
                const maxLen = isHovered ? 38 : (root.compact ? 22 : 26);
                const label = rawTitle.length > maxLen ? (rawTitle.substring(0, maxLen - 1) + "…") : rawTitle;

                ctx.font = (isHovered || isCurrent || (root.isLocal && n.hop === 0) || isHub)
                    ? "bold 12px sans-serif"
                    : "11px sans-serif";
                const textW = ctx.measureText(label).width;
                const lx = Math.max(4, Math.min(width - textW - 4, ptx - textW * 0.5));
                const rawLy = pty + r + 13;
                const ly = (rawLy > height - 6)
                    ? Math.max(14, pty - r - 6)
                    : Math.max(14, Math.min(height - 6, rawLy));

                if (isHovered) {
                    ctx.fillStyle = Qt.rgba(root.bgSurface.r, root.bgSurface.g, root.bgSurface.b, 0.92);
                    ctx.fillRect(lx - 5, ly - 11, textW + 10, 16);
                }

                ctx.fillStyle = isHovered ? root.textColor : (isCurrent ? acc : root.textColor);
                ctx.fillText(label, lx, ly);
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

            onPressed: mouse => {
                pressX = mouse.x;
                pressY = mouse.y;
                lastX = mouse.x;
                lastY = mouse.y;
                movedSignificantly = false;
                const hit = root.findNodeAtScreen(mouse.x, mouse.y);
                root.draggedIndex = hit;
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

                if (root.draggedIndex >= 0 && root.draggedIndex < root.nodePositions.length) {
                    // Dragging a specific node updates its normalized position and gently tugs 1-hop satellite neighbors
                    const norm = root._normalizedFromScreen(mouse.x, mouse.y);
                    const prev = root.nodePositions[root.draggedIndex];
                    const ndx = norm.x - prev.x;
                    const ndy = norm.y - prev.y;
                    root.nodePositions[root.draggedIndex] = norm;
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
                                root.nodePositions[nIdx] = { "x": nx, "y": ny };
                                if (root._normXBuf && nIdx < root._normXBuf.length) {
                                    root._normXBuf[nIdx] = nx;
                                    root._normYBuf[nIdx] = ny;
                                }
                            }
                        }
                    }
                    root.requestPaint();
                } else {
                    // Panning the canvas
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
                const factor = wheel.angleDelta.y > 0 ? 1.16 : 0.86;
                root.zoomBy(factor, wheel.x, wheel.y);
                wheel.accepted = true;
            }
        }
    }

    // Floating Zoom / Reset Controls
    RowLayout {
        id: zoomControlsBar
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: root.compact ? 4 : 10
        spacing: 3
        visible: root.width > 120 && root.height > 90
        opacity: (!root.compact || root.canvasHovered || zoomOutMouse.containsMouse || zoomResetMouse.containsMouse || zoomInMouse.containsMouse) ? 1.0 : 0.0
        Behavior on opacity {
            NumberAnimation { duration: 150 }
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
