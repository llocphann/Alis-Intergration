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
    property var clusterPalette: []

    signal nodeActivated(var nodeData)

    // Viewport transform state (deep zoom up to 32x)
    property real zoom: 1.0
    property real panX: 0.0
    property real panY: 0.0

    // 3D orbital camera angles & inertia (used when renderMode === "3d")
    property real rotYaw: 0.42
    property real rotPitch: 0.28
    property real _velYaw: 0.0
    property real _velPitch: 0.0
    property bool autoRotate3D: false
    property int lastElectricArcCount: 0

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
    property var _norm3DXBuf: null
    property var _norm3DYBuf: null
    property var _norm3DZBuf: null
    property var _clusterEdgeBuckets: [] // [{ clusterId: int, edges: Int32Array }]
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

    // Generate distinct per-cluster colors strictly within Alis's Auto-Theming tonal gradient palette
    // (e.g., green tonal spot -> distinct light/deep/sage/jade green shades; never foreign yellow/red hues)
    function _autoThemedClusterColor(clusterId: int): color {
        const acc = root.accentColor;
        const cid = Math.max(0, Number(clusterId) || 0);
        const baseH = (acc.hslHue >= 0 ? acc.hslHue : 0.55);
        const baseS = Math.max(0.32, Math.min(0.84, acc.hslSaturation > 0.08 ? acc.hslSaturation : 0.56));
        const baseL = root.isDarkSurface
            ? Math.max(0.50, Math.min(0.72, acc.hslLightness > 0.25 ? acc.hslLightness : 0.62))
            : Math.max(0.32, Math.min(0.52, acc.hslLightness < 0.75 ? acc.hslLightness : 0.42));

        // 12 well-separated tonal gradient stops strictly anchored on Alis's primary hue (±8° max drift)
        // [lightnessDelta, saturationDelta, hueDeltaFrac]
        const tonalRamp = [
            [ 0.00,  0.04,  0.000], // 0: Primary tonal anchor
            [ 0.16,  0.06,  0.010], // 1: Bright luminous tint
            [-0.15,  0.08, -0.010], // 2: Deep rich shade
            [ 0.08, -0.14,  0.016], // 3: Soft muted tint
            [-0.08, -0.10, -0.016], // 4: Calm deep shade
            [ 0.22, -0.04, -0.008], // 5: Crisp high-lightness mist
            [-0.21,  0.04,  0.014], // 6: Deep velvet shade
            [ 0.12,  0.12, -0.020], // 7: Vivid bright tone
            [-0.04,  0.14,  0.020], // 8: Vivid mid-deep tone
            [ 0.18, -0.20,  0.006], // 9: Pale airy tint
            [-0.18, -0.16, -0.014], // 10: Deep muted shade
            [ 0.04, -0.22, -0.006]  // 11: Soft neutral-tinted mid
        ];
        const cycle = Math.floor(cid / tonalRamp.length);
        const stop = tonalRamp[cid % tonalRamp.length];
        const lMin = root.isDarkSurface ? 0.34 : 0.20;
        const lMax = root.isDarkSurface ? 0.86 : 0.66;
        const cycleL = (cycle % 2 === 1) ? 0.045 : ((cycle > 0) ? -0.045 : 0.0);
        const hue = (baseH + stop[2] + 1.0) % 1.0;
        const sat = Math.max(0.22, Math.min(0.90, baseS + stop[1]));
        const lig = Math.max(lMin, Math.min(lMax, baseL + stop[0] + cycleL));
        const raw = Qt.hsla(hue, sat, lig, 1.0);
        return root._mixColor(raw, acc, 0.90);
    }

    // Shared zoom-responsive radius multiplier (synchronized across paint, hit-test, and electric arcs)
    function _zoomRadiusScale(z: real): real {
        const zz = Math.max(0.35, Number(z) || 1.0);
        if (zz <= 1.0)
            return Math.max(0.65, Math.pow(zz, 0.55));
        return Math.min(12.0, Math.pow(zz, 0.80));
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
        root._velYaw = 0.0;
        root._velPitch = 0.0;
        root._syncPositionsFromData();
        root.requestPaint();
    }

    Timer {
        id: orbitMotionTimer
        interval: 24
        repeat: true
        running: root.is3D && root.visible && (
            (root.autoRotate3D && !graphMouse.pressed)
            || Math.abs(root._velYaw) > 0.00035
            || Math.abs(root._velPitch) > 0.00035
        )
        onTriggered: {
            if (root.autoRotate3D && !graphMouse.pressed) {
                root.rotYaw += 0.0038;
            }
            if (Math.abs(root._velYaw) > 0.00035 || Math.abs(root._velPitch) > 0.00035) {
                root.rotYaw += root._velYaw;
                root.rotPitch = Math.max(-1.42, Math.min(1.42, root.rotPitch + root._velPitch));
                root._velYaw *= 0.84;
                root._velPitch *= 0.84;
                if (Math.abs(root._velYaw) <= 0.00035) root._velYaw = 0.0;
                if (Math.abs(root._velPitch) <= 0.00035) root._velPitch = 0.0;
            }
            root.requestPaint();
        }
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
                return root.compact ? 3.8 : 5.0;
            if (n.hop === 1)
                return root.compact ? 2.5 : 3.3;
            return root.compact ? 1.8 : 2.4;
        }
        const isTag = Boolean(n?.isTagNode);
        const deg = Number(n.degree ?? 0);
        if (root.compact) {
            if (isTag)
                return Math.min(3.2, 2.0 + Math.log(deg + 1) * 0.24);
            if (deg >= 14)
                return Math.min(2.7, 1.75 + Math.log(deg + 1) * 0.18);
            if (deg >= 5)
                return 1.50;
            if (deg >= 2)
                return 1.24;
            if (deg === 1)
                return 1.08;
            return 0.88;
        }
        if (isTag)
            return Math.min(4.6, 2.75 + Math.log(deg + 1) * 0.30);
        if (deg >= 14)
            return Math.min(4.0, 2.25 + Math.log(deg + 1) * 0.26);
        if (deg >= 5)
            return 2.00;
        if (deg >= 2)
            return 1.62;
        if (deg === 1)
            return 1.38;
        return 1.12;
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
            root._norm3DXBuf = null;
            root._norm3DYBuf = null;
            root._norm3DZBuf = null;
            root._clusterEdgeBuckets = [];
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
        const clusterEdgeMap = Object.create(null);
        for (let e = 0; e < resEdges.length; ++e) {
            eSrcBuf[e] = resEdges[e].s;
            eDstBuf[e] = resEdges[e].t;
            const ec = clusterIdBuf[resEdges[e].s] >= 0 ? clusterIdBuf[resEdges[e].s] : clusterIdBuf[resEdges[e].t];
            eClustBuf[e] = ec;
            if (ec >= 0) {
                if (!clusterEdgeMap[ec]) clusterEdgeMap[ec] = [];
                clusterEdgeMap[ec].push(e);
            }
        }
        const clusterEdgeKeys = Object.keys(clusterEdgeMap).sort((a, b) => Number(a) - Number(b));
        const clusterBuckets = new Array(clusterEdgeKeys.length);
        for (let k = 0; k < clusterEdgeKeys.length; ++k) {
            const cidKey = clusterEdgeKeys[k];
            clusterBuckets[k] = {
                "clusterId": Number(cidKey),
                "edges": new Int32Array(clusterEdgeMap[cidKey])
            };
        }

        // Build true volumetric 3D spherical constellation coordinates (Obsidian 3D-Graph inspired):
        // connected clusters distributed across a 3D golden-spiral shell with 3D spherical sub-constellations
        // and spring relaxation, while orphans frame the outer celestial shell.
        const nx3 = new Float32Array(nLen);
        const ny3 = new Float32Array(nLen);
        const nz3 = new Float32Array(nLen);
        const goldenAngle = 2.399963229728653;
        const clusterNodesMap = Object.create(null);
        const orphanIndices = [];
        for (let i = 0; i < nLen; ++i) {
            const cid = clusterIdBuf[i];
            if (isOrphanBuf[i] === 1 || cid < 0) {
                orphanIndices.push(i);
            } else {
                if (!clusterNodesMap[cid]) clusterNodesMap[cid] = [];
                clusterNodesMap[cid].push(i);
            }
        }
        const clusterList = Object.keys(clusterNodesMap)
            .map(k => ({ cid: Number(k), members: clusterNodesMap[k] }))
            .sort((a, b) => b.members.length - a.members.length || a.cid - b.cid);
        const cCount = clusterList.length;
        for (let c = 0; c < cCount; ++c) {
            const mem = clusterList[c].members;
            const mLen = mem.length;
            // Cluster center on volumetric 3D Fibonacci shell (largest cluster near core)
            let cx = 0.0, cy = 0.0, cz = 0.0;
            if (cCount > 1) {
                const shellR = (c === 0) ? 0.14 : (0.34 + 0.34 * Math.sqrt((c) / Math.max(1, cCount - 1)));
                const phi = Math.acos(1.0 - 2.0 * ((c + 0.5) / cCount));
                const theta = c * goldenAngle;
                cx = shellR * Math.sin(phi) * Math.cos(theta);
                cy = shellR * Math.cos(phi);
                cz = shellR * Math.sin(phi) * Math.sin(theta);
            }
            const subR = Math.min(0.32, Math.max(0.08, 0.075 + 0.022 * Math.sqrt(mLen)));
            // Pick virtual tag hub or highest-degree node as exact 3D cluster center
            let hubIdx = mem[0];
            let hubScore = -1;
            for (let j = 0; j < mLen; ++j) {
                const u = mem[j];
                const sc = (Boolean(nodes[u]?.isTagNode) ? 10000 : 0) + degBuf[u];
                if (sc > hubScore) {
                    hubScore = sc;
                    hubIdx = u;
                }
            }
            nx3[hubIdx] = cx;
            ny3[hubIdx] = cy;
            nz3[hubIdx] = cz;
            let rank = 0;
            const satTotal = Math.max(1, mLen - 1);
            for (let j = 0; j < mLen; ++j) {
                const u = mem[j];
                if (u === hubIdx) continue;
                const frac = (rank + 0.5) / satTotal;
                const phi = Math.acos(1.0 - 2.0 * frac);
                const theta = rank * goldenAngle + c * 0.73;
                const degFactor = degBuf[u] >= 4 ? (0.42 + 0.25 * Math.sqrt(frac)) : (0.62 + 0.38 * Math.sqrt(frac));
                const r = subR * degFactor;
                nx3[u] = cx + r * Math.sin(phi) * Math.cos(theta);
                ny3[u] = cy + r * Math.cos(phi);
                nz3[u] = cz + r * Math.sin(phi) * Math.sin(theta);
                rank += 1;
            }
        }
        // Orphans gently placed on an outer spherical halo (never blocking cluster cores)
        const oLen = orphanIndices.length;
        for (let k = 0; k < oLen; ++k) {
            const u = orphanIndices[k];
            const frac = (k + 0.5) / Math.max(1, oLen);
            const phi = Math.acos(1.0 - 2.0 * frac);
            const theta = k * goldenAngle + 1.1;
            const r = 0.84 + 0.10 * ((k % 3) * 0.5);
            nx3[u] = r * Math.sin(phi) * Math.cos(theta);
            ny3[u] = r * Math.cos(phi);
            nz3[u] = r * Math.sin(phi) * Math.sin(theta);
        }
        // 6 fast 3D spring-cohesion + gentle anti-collapse relaxation passes along edges
        if (resEdges.length > 0 && nLen > 2) {
            const sumX = new Float32Array(nLen);
            const sumY = new Float32Array(nLen);
            const sumZ = new Float32Array(nLen);
            const cnt = new Int32Array(nLen);
            for (let step = 0; step < 6; ++step) {
                sumX.fill(0); sumY.fill(0); sumZ.fill(0); cnt.fill(0);
                for (let e = 0; e < resEdges.length; ++e) {
                    const s = eSrcBuf[e], t = eDstBuf[e];
                    sumX[s] += nx3[t]; sumY[s] += ny3[t]; sumZ[s] += nz3[t]; cnt[s] += 1;
                    sumX[t] += nx3[s]; sumY[t] += ny3[s]; sumZ[t] += nz3[s]; cnt[t] += 1;
                }
                for (let i = 0; i < nLen; ++i) {
                    if (cnt[i] > 0 && !Boolean(nodes[i]?.isTagNode)) {
                        const inv = 1.0 / cnt[i];
                        const tx = sumX[i] * inv;
                        const ty = sumY[i] * inv;
                        const tz = sumZ[i] * inv;
                        nx3[i] = nx3[i] * 0.84 + tx * 0.16;
                        ny3[i] = ny3[i] * 0.84 + ty * 0.16;
                        nz3[i] = nz3[i] * 0.84 + tz * 0.16;
                    }
                }
            }
        }
        // Normalize 3D coordinates cleanly to [0.06, 0.94] centered at (0.5, 0.5, 0.5)
        let maxAbs3 = 0.05;
        for (let i = 0; i < nLen; ++i) {
            const r3 = Math.sqrt(nx3[i] * nx3[i] + ny3[i] * ny3[i] + nz3[i] * nz3[i]);
            if (r3 > maxAbs3) maxAbs3 = r3;
        }
        const invScale3 = 0.44 / maxAbs3;
        for (let i = 0; i < nLen; ++i) {
            nx3[i] = 0.5 + nx3[i] * invScale3;
            ny3[i] = 0.5 + ny3[i] * invScale3;
            nz3[i] = 0.5 + nz3[i] * invScale3;
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
        root._norm3DXBuf = nx3;
        root._norm3DYBuf = ny3;
        root._norm3DZBuf = nz3;
        root._clusterEdgeBuckets = clusterBuckets;
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
        const focal = 3.15;
        const persp = focal / Math.max(0.55, focal - rz);
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
            const x3 = (root._norm3DXBuf && idx < root._norm3DXBuf.length) ? root._norm3DXBuf[idx] : p.x;
            const y3 = (root._norm3DYBuf && idx < root._norm3DYBuf.length) ? root._norm3DYBuf[idx] : p.y;
            const z3 = (root._norm3DZBuf && idx < root._norm3DZBuf.length) ? root._norm3DZBuf[idx] : (p.z ?? 0.5);
            const pr = root._project3D(x3, y3, z3, m);
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
            if (n.hop === 0) return (root.compact ? 3.8 : 5.0) * s;
            if (n.hop === 1) return (root.compact ? 2.5 : 3.3) * s;
            return (root.compact ? 1.8 : 2.4) * s;
        }
        const isTag = Boolean(n?.isTagNode);
        const deg = Number(n.degree ?? 0);
        const isCur = root.currentPath.length > 0 && n.relPath === root.currentPath;
        if (root.compact) {
            if (isCur) return 2.8 * s;
            if (isTag) return Math.min(3.2, 2.0 + Math.log(deg + 1) * 0.24) * s;
            if (deg >= 14) return Math.min(2.7, 1.75 + Math.log(deg + 1) * 0.18) * s;
            if (deg >= 5) return 1.50 * s;
            if (deg >= 2) return 1.24 * s;
            if (deg === 1) return 1.08 * s;
            return 0.88 * s;
        }
        if (isCur) return 4.0 * s;
        if (isTag) return Math.min(4.6, 2.75 + Math.log(deg + 1) * 0.30) * s;
        if (deg >= 14) return Math.min(4.0, 2.25 + Math.log(deg + 1) * 0.26) * s;
        if (deg >= 5) return 2.00 * s;
        if (deg >= 2) return 1.62 * s;
        if (deg === 1) return 1.38 * s;
        return 1.12 * s;
    }

    function findNodeAtScreen(sx: real, sy: real): int {
        const g = root.graphData;
        if (!g || !Array.isArray(g.nodes) || root.nodePositions.length !== g.nodes.length)
            return -1;
        const nodes = g.nodes;
        const nLen = nodes.length;
        const m = root._viewportMetrics();
        const zoomFactor = root._zoomRadiusScale(root.zoom);
        const hitSlack = root.compact ? 5.5 : 8.5;
        const scaleMul = m.sizeScale * zoomFactor;
        const maxHitR = 5.5 * scaleMul + hitSlack;
        const mulX = m.spanX * root.zoom;
        const addX = m.originX * root.zoom + root.panX;
        const mulY = m.spanY * root.zoom;
        const addY = m.originY * root.zoom + root.panY;
        const nxBuf = root._normXBuf;
        const nyBuf = root._normYBuf;
        const nx3Buf = root._norm3DXBuf;
        const ny3Buf = root._norm3DYBuf;
        const nz3Buf = root._norm3DZBuf;
        const baseRadBuf = root._baseRadBuf;
        const hasTyped = Boolean(nxBuf && nyBuf && baseRadBuf && nxBuf.length >= nLen && baseRadBuf.length >= nLen);
        const has3DBuf = Boolean(nx3Buf && ny3Buf && nz3Buf && nx3Buf.length >= nLen);
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
                    has3DBuf ? nx3Buf[i] : root.nodePositions[i].x,
                    has3DBuf ? ny3Buf[i] : root.nodePositions[i].y,
                    has3DBuf ? nz3Buf[i] : (root.nodePositions[i].z ?? 0.5),
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
            const nx3Buf = root._norm3DXBuf || nxBuf;
            const ny3Buf = root._norm3DYBuf || nyBuf;
            const nz3Buf = root._norm3DZBuf || root._normZBuf;
            const focal3D = 3.15;
            if (mode3D) {
                const cyaw = Math.cos(root.rotYaw);
                const syaw = Math.sin(root.rotYaw);
                const cpitch = Math.cos(root.rotPitch);
                const spitch = Math.sin(root.rotPitch);
                for (let i = 0; i < nLen; ++i) {
                    const x0 = (nx3Buf[i] - 0.5) * 2.0;
                    const y0 = (ny3Buf[i] - 0.5) * 2.0;
                    const z0 = (nz3Buf[i] - 0.5) * 2.0;
                    const rx = x0 * cyaw - z0 * syaw;
                    const rz1 = x0 * syaw + z0 * cyaw;
                    const ry = y0 * cpitch - rz1 * spitch;
                    const rz = y0 * spitch + rz1 * cpitch;
                    const persp = focal3D / Math.max(0.55, focal3D - rz);
                    sxBuf[i] = (m.cx + rx * m.radius3D * persp) * root.zoom + root.panX;
                    syBuf[i] = (m.cy + ry * m.radius3D * persp) * root.zoom + root.panY;
                    scBuf[i] = persp;
                    zdBuf[i] = rz;
                    zOrder[i] = i;
                }
                // Subtle 3D spatial depth backdrop + ultra-clean equatorial horizon guide (hidden when zoomed deep)
                ctx.save();
                const gcx = m.cx * root.zoom + root.panX;
                const gcy = m.cy * root.zoom + root.panY;
                const gr = m.radius3D * 0.96 * root.zoom;
                if (gr > 18 && gr < Math.max(width, height) * 4) {
                    const bgGlow = ctx.createRadialGradient(gcx, gcy, gr * 0.06, gcx, gcy, gr * 1.18);
                    bgGlow.addColorStop(0.0, Qt.rgba(acc.r, acc.g, acc.b, 0.055));
                    bgGlow.addColorStop(0.72, Qt.rgba(acc.r, acc.g, acc.b, 0.018));
                    bgGlow.addColorStop(1.0, Qt.rgba(acc.r, acc.g, acc.b, 0.0));
                    ctx.fillStyle = bgGlow;
                    ctx.beginPath();
                    ctx.arc(gcx, gcy, gr * 1.18, 0, Math.PI * 2);
                    ctx.fill();

                    if (root.zoom < 2.2) {
                        const ringFade = Math.max(0.0, Math.min(1.0, (2.2 - root.zoom) / 1.2));
                        const steps = 64;
                        for (let half = 0; half < 2; ++half) {
                            ctx.strokeStyle = half === 0
                                ? Qt.rgba(acc.r, acc.g, acc.b, 0.045 * ringFade)
                                : Qt.rgba(acc.r, acc.g, acc.b, 0.11 * ringFade);
                            ctx.lineWidth = half === 0 ? 0.65 : 0.9;
                            ctx.beginPath();
                            let penDown = false;
                            for (let s = 0; s <= steps; ++s) {
                                const a = (s / steps) * Math.PI * 2;
                                const px0 = Math.cos(a) * 0.94;
                                const pz0 = Math.sin(a) * 0.94;
                                const rrx = px0 * cyaw - pz0 * syaw;
                                const rrz1 = px0 * syaw + pz0 * cyaw;
                                const rry = -rrz1 * spitch;
                                const rrz = rrz1 * cpitch;
                                const isFront = rrz >= 0;
                                if ((half === 0 && isFront) || (half === 1 && !isFront)) {
                                    penDown = false;
                                    continue;
                                }
                                const rp = focal3D / Math.max(0.55, focal3D - rrz);
                                const rsx = (m.cx + rrx * m.radius3D * rp) * root.zoom + root.panX;
                                const rsy = (m.cy + rry * m.radius3D * rp) * root.zoom + root.panY;
                                if (!penDown) {
                                    ctx.moveTo(rsx, rsy);
                                    penDown = true;
                                } else {
                                    ctx.lineTo(rsx, rsy);
                                }
                            }
                            ctx.stroke();
                        }
                    }
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

            // 1. Draw base edges (3 depth strata with cluster-tinted depth fog in 3D; fast batched in 2D)
            if (mode3D) {
                const bg = root.bgSurface;
                const eClust = root._edgeClusterBuf;
                const strata = [
                    { "minZ": -9.0, "maxZ": -0.22, "lw": 0.45, "alpha": activeIdx >= 0 ? 0.04 : 0.14, "fog": 0.42 },
                    { "minZ": -0.22, "maxZ": 0.28, "lw": 0.68, "alpha": activeIdx >= 0 ? 0.06 : 0.24, "fog": 0.72 },
                    { "minZ": 0.28, "maxZ": 9.0, "lw": 0.98, "alpha": activeIdx >= 0 ? 0.09 : 0.38, "fog": 0.96 }
                ];
                for (let st = 0; st < strata.length; ++st) {
                    const layer = strata[st];
                    ctx.lineWidth = layer.lw;
                    // Group edges in this depth stratum by cluster color so 3D links inherit cluster gradient identity
                    const colorBatches = Object.create(null);
                    for (let e = 0; e < eLen; ++e) {
                        const sIdx = eSrc[e];
                        const tIdx = eDst[e];
                        if (activeIdx >= 0 && (sIdx === activeIdx || tIdx === activeIdx))
                            continue;
                        const avgZ = (zdBuf[sIdx] + zdBuf[tIdx]) * 0.5;
                        if (avgZ < layer.minZ || avgZ >= layer.maxZ)
                            continue;
                        const x0 = sxBuf[sIdx];
                        const y0 = syBuf[sIdx];
                        const x1 = sxBuf[tIdx];
                        const y1 = syBuf[tIdx];
                        if ((x0 < -24 && x1 < -24) || (x0 > width + 24 && x1 > width + 24)
                                || (y0 < -24 && y1 < -24) || (y0 > height + 24 && y1 > height + 24))
                            continue;
                        const edx = x1 - x0;
                        const edy = y1 - y0;
                        if (edx * edx + edy * edy < 0.6)
                            continue;
                        const cid = (eClust && e < eClust.length) ? eClust[e] : -1;
                        const bKey = cid >= 0 ? String(cid % 12) : "m";
                        if (!colorBatches[bKey]) {
                            const rawCol = (cid >= 0 && root.resolvedNodeColors[sIdx]) ? root.resolvedNodeColors[sIdx].base : acc;
                            const fogged = root._mixColor(rawCol, bg, layer.fog);
                            colorBatches[bKey] = {
                                "stroke": Qt.rgba(fogged.r, fogged.g, fogged.b, layer.alpha),
                                "pts": []
                            };
                        }
                        colorBatches[bKey].pts.push(x0, y0, x1, y1);
                    }
                    const batchKeys = Object.keys(colorBatches);
                    for (let bk = 0; bk < batchKeys.length; ++bk) {
                        const b = colorBatches[batchKeys[bk]];
                        const pts = b.pts;
                        ctx.strokeStyle = b.stroke;
                        ctx.beginPath();
                        let segs = 0;
                        for (let p = 0; p < pts.length; p += 4) {
                            ctx.moveTo(pts[p], pts[p + 1]);
                            ctx.lineTo(pts[p + 2], pts[p + 3]);
                            segs += 1;
                            if (segs === 256) {
                                ctx.stroke();
                                ctx.beginPath();
                                segs = 0;
                            }
                        }
                        if (segs > 0)
                            ctx.stroke();
                    }
                }
            } else {
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
            }

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

            // 3. Draw nodes (depth-sorted lit 3D spheres in 3D, fast color-bucketed in 2D)
            const scaleR = root._zoomRadiusScale(root.zoom);
            const scaleMul = m.sizeScale * scaleR;
            const baseRadBuf = root._baseRadBuf;
            const curPath = root.currentPath;
            const hasCurPath = curPath.length > 0;
            const cullPad = Math.max(32, Math.min(120, 20 * scaleR));

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
                            if (px < -cullPad || px > width + cullPad || py < -cullPad || py > height + cullPad)
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
                    if (ptx < -cullPad || ptx > width + cullPad || pty < -cullPad || pty > height + cullPad)
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
                    const depthNorm = mode3D ? Math.max(0.0, Math.min(1.0, (zdBuf[i] + 1.0) * 0.5)) : 1.0;
                    const depthFade = mode3D ? (0.30 + depthNorm * 0.70) : 1.0;
                    const r = root._nodeRadius(n, m.sizeScale) * scaleR * depthScale * (isHovered ? 1.22 : 1.0);
                    const cached = root.resolvedNodeColors[i] || {
                        "base": acc,
                        "deg2": Qt.rgba(acc.r, acc.g, acc.b, 0.90),
                        "leaf": Qt.rgba(acc.r, acc.g, acc.b, 0.72),
                        "isOrphan": false
                    };
                    const rawNodeColor = cached.base;
                    // True 3D atmospheric depth fog (far nodes smoothly blend toward bgSurface)
                    const nodeColor = (mode3D && !isHovered && !isCurrent)
                        ? root._mixColor(rawNodeColor, root.bgSurface, 0.36 + depthNorm * 0.64)
                        : rawNodeColor;

                    // Soft glow halo for tag hubs, hovered, current, local center, or major hubs
                    const showHalo = !dimmed && (isHovered || isCurrent || isCenter || isTagHub || (!root.compact && deg >= 14));
                    if (showHalo) {
                        ctx.beginPath();
                        ctx.arc(ptx, pty, r + (isHovered ? 3.0 : (isTagHub ? 2.4 : 1.8)) * Math.min(2.2, Math.sqrt(scaleR)) * depthScale, 0, Math.PI * 2);
                        ctx.fillStyle = Qt.rgba(nodeColor.r, nodeColor.g, nodeColor.b,
                            (isHovered ? 0.34 : (isTagHub ? 0.24 : 0.18)) * depthFade);
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

                    let useSphereGrad = mode3D && !isTagHub && !dimmed && r >= 3.4;
                    if (useSphereGrad) {
                        const baseFill = isHovered ? root.textColor : (isCurrent ? acc : nodeColor);
                        const hiCol = Qt.lighter(baseFill, 1.48);
                        const loCol = Qt.darker(baseFill, 1.55);
                        const sg = ctx.createRadialGradient(
                            ptx - r * 0.32, pty - r * 0.32, Math.max(0.4, r * 0.08),
                            ptx, pty, r
                        );
                        sg.addColorStop(0.0, Qt.rgba(hiCol.r, hiCol.g, hiCol.b, depthFade));
                        sg.addColorStop(0.58, Qt.rgba(baseFill.r, baseFill.g, baseFill.b, depthFade));
                        sg.addColorStop(1.0, Qt.rgba(loCol.r, loCol.g, loCol.b, depthFade));
                        ctx.fillStyle = sg;
                    } else if (isHovered) {
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
                            : Qt.rgba(nodeColor.r, nodeColor.g, nodeColor.b, 0.62 * depthFade);
                    } else {
                        ctx.fillStyle = dimmed
                            ? Qt.rgba(muted.r, muted.g, muted.b, 0.15 * depthFade)
                            : (isNeighbor ? root.textColor : Qt.rgba(nodeColor.r, nodeColor.g, nodeColor.b, (deg >= 2 ? 0.94 : 0.80) * depthFade));
                    }
                    ctx.fill();

                    // Soft specular glint on smaller 3D spheres where radial gradient isn't needed
                    if (mode3D && !useSphereGrad && !isTagHub && !dimmed && r >= 1.8) {
                        ctx.beginPath();
                        ctx.arc(ptx - r * 0.26, pty - r * 0.26, r * 0.28, 0, Math.PI * 2);
                        ctx.fillStyle = Qt.rgba(1.0, 1.0, 1.0, 0.22 * depthFade);
                        ctx.fill();
                    }

                    if (isHovered || isCurrent || isTagHub) {
                        ctx.lineWidth = (isTagHub ? 1.25 : 1.0) * Math.min(2.0, Math.sqrt(scaleR));
                        ctx.strokeStyle = isHovered
                            ? nodeColor
                            : (isTagHub ? Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.85 * depthFade) : root.textColor);
                        ctx.stroke();
                    }
                }
            }

            // 4. Draw labels (front-to-back with screen-space collision avoidance in 3D)
            const placedLabels = mode3D ? [] : null;
            for (let step = 0; step < nLen; ++step) {
                const i = renderOrder ? renderOrder[nLen - 1 - step] : step;
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
                if (mode3D && !isHovered && !isCurrent && zdBuf[i] < -0.55)
                    continue;

                const depthScale = mode3D ? scBuf[i] : 1.0;
                const depthFade = mode3D ? Math.max(0.38, Math.min(1.0, 0.78 + zdBuf[i] * 0.34)) : 1.0;
                const r = root._nodeRadius(n, m.sizeScale) * scaleR * depthScale;
                const rawTitle = String(n.title ?? "");
                const maxLen = isHovered ? 42 : (root.compact ? 22 : (root.zoom >= 5.0 ? 36 : 26));
                const label = rawTitle.length > maxLen ? (rawTitle.substring(0, maxLen - 1) + "…") : rawTitle;

                const zoomFontBoost = root.zoom > 1.5 ? Math.min(3.5, Math.log2(root.zoom) * 0.9) : 0.0;
                const fontPx = Math.round(Math.max(10, Math.min(16, ((isTagHub || isHovered ? 12 : 11) + zoomFontBoost) * (mode3D ? Math.max(0.84, Math.min(1.18, depthScale)) : 1.0))));
                ctx.font = (isHovered || isCurrent || isTagHub || (root.isLocal && n.hop === 0) || isHub)
                    ? ("bold " + fontPx + "px sans-serif")
                    : (fontPx + "px sans-serif");
                const textW = ctx.measureText(label).width;
                const lx = Math.max(4, Math.min(width - textW - 4, ptx - textW * 0.5));
                const rawLy = pty + r + 13;
                const ly = (rawLy > height - 6)
                    ? Math.max(14, pty - r - 6)
                    : Math.max(14, Math.min(height - 6, rawLy));

                if (placedLabels && !isHovered && !isCurrent) {
                    const bx0 = lx - 4;
                    const by0 = ly - fontPx - 2;
                    const bx1 = lx + textW + 4;
                    const by1 = ly + 4;
                    let collides = false;
                    for (let pl = 0; pl < placedLabels.length; ++pl) {
                        const pb = placedLabels[pl];
                        if (!(bx1 < pb.x0 || bx0 > pb.x1 || by1 < pb.y0 || by0 > pb.y1)) {
                            collides = true;
                            break;
                        }
                    }
                    if (collides)
                        continue;
                    placedLabels.push({ "x0": bx0, "y0": by0, "x1": bx1, "y1": by1 });
                } else if (placedLabels) {
                    placedLabels.push({ "x0": lx - 4, "y0": ly - fontPx - 2, "x1": lx + textW + 4, "y1": ly + 4 });
                }

                if (isHovered || isTagHub) {
                    ctx.fillStyle = Qt.rgba(root.bgSurface.r, root.bgSurface.g, root.bgSurface.b, isHovered ? 0.92 : 0.76);
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

    // ─── Delicate Electric Current Overlay Canvas (Strictly 1 arc in Local Graph, 1 arc per cluster in Vault Graph, sized smaller than notes) ───
    Canvas {
        id: electricCanvas
        anchors.fill: parent
        antialiasing: true
        visible: root.electricCurrentActive

        function _drawElectricArc(ctx, rawX0, rawY0, rawX1, rawY1, rA, rB, col, now, seed, phaseT, compactScale, fadeAlpha) {
            const alpha = Math.max(0.0, Math.min(1.0, fadeAlpha));
            if (alpha < 0.04) return false;
            const fullDx = rawX1 - rawX0;
            const fullDy = rawY1 - rawY0;
            const fullDist = Math.sqrt(fullDx * fullDx + fullDy * fullDy);
            const padA = Math.max(1.2, rA + 1.4);
            const padB = Math.max(1.2, rB + 1.4);
            const span = fullDist - padA - padB;
            if (span < 6.0) return false;

            const ux = fullDx / fullDist;
            const uy = fullDy / fullDist;
            const x0 = rawX0 + ux * padA;
            const y0 = rawY0 + uy * padA;
            const x1 = rawX1 - ux * padB;
            const y1 = rawY1 - uy * padB;
            const dx = x1 - x0;
            const dy = y1 - y0;
            const nx = -uy;
            const ny = ux;

            const minNoteR = Math.max(0.55, Math.min(rA, rB));
            const outerW = Math.min(minNoteR * 0.42, 1.45 * compactScale);
            const midW = Math.min(minNoteR * 0.24, 0.80 * compactScale);
            const coreW = Math.min(minNoteR * 0.12, 0.42 * compactScale);
            const baseAmp = Math.min(minNoteR * 0.34, Math.max(0.40, span * 0.015)) * compactScale;
            const segs = Math.max(5, Math.min(10, Math.floor(span / 18)));

            function plasmaOffset(t, strokeIdx, ampScale) {
                if (t <= 0.001 || t >= 0.999) return 0;
                const env = Math.sin(t * Math.PI);
                const sPos = t * segs;
                return Math.sin(now * (6.2 + strokeIdx * 1.1) + seed * 1.9 + sPos * 2.1)
                    * Math.cos(now * 4.8 - seed + sPos * 1.5)
                    * baseAmp * env * ampScale;
            }

            // Delicate 3-layer filament strictly thinner than the connected note circles
            for (let stroke = 0; stroke < 3; ++stroke) {
                const ampScale = stroke === 0 ? 1.0 : (stroke === 1 ? 0.68 : 0.32);
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
                    ctx.strokeStyle = Qt.rgba(col.r, col.g, col.b, 0.16 * alpha);
                    ctx.lineWidth = Math.max(0.32, outerW);
                } else if (stroke === 1) {
                    const mid = Qt.lighter(col, 1.15);
                    ctx.strokeStyle = Qt.rgba(mid.r, mid.g, mid.b, 0.44 * alpha);
                    ctx.lineWidth = Math.max(0.22, midW);
                } else {
                    ctx.strokeStyle = Qt.rgba(1.0, 1.0, 1.0, 0.64 * alpha);
                    ctx.lineWidth = Math.max(0.16, coreW);
                }
                ctx.lineCap = "round";
                ctx.lineJoin = "round";
                ctx.stroke();
            }

            // Single refined traveling charge spark strictly smaller than the note radius
            const pos = phaseT % 1.0;
            const tailT = Math.max(0.0, pos - 0.12);
            const midT = (pos + tailT) * 0.5;
            const pJ = plasmaOffset(pos, 2, 0.32);
            const mJ = plasmaOffset(midT, 2, 0.32);
            const tJ = plasmaOffset(tailT, 2, 0.32);
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
            ctx.strokeStyle = Qt.rgba(1.0, 1.0, 1.0, 0.58 * alpha);
            ctx.lineWidth = Math.max(0.22, midW);
            ctx.stroke();

            const sparkOuterR = Math.max(0.28, Math.min(minNoteR * 0.28, 1.05 * compactScale));
            const sparkInnerR = Math.max(0.18, Math.min(minNoteR * 0.15, 0.56 * compactScale));
            ctx.beginPath();
            ctx.arc(px, py, sparkOuterR, 0, Math.PI * 2);
            ctx.fillStyle = Qt.rgba(col.r, col.g, col.b, 0.34 * alpha);
            ctx.fill();
            ctx.beginPath();
            ctx.arc(px, py, sparkInnerR, 0, Math.PI * 2);
            ctx.fillStyle = Qt.rgba(1.0, 1.0, 1.0, 0.84 * alpha);
            ctx.fill();
            return true;
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
            const scBuf = root._screenScaleBuf;
            const baseRadBuf = root._baseRadBuf;
            const eSrc = root._edgeSrcBuf;
            const eDst = root._edgeDstBuf;
            const isOrph = root._isOrphanBuf;
            const eLen = root.resolvedEdges.length;
            if (!sxBuf || !syBuf || !eSrc || !eDst || eLen <= 0) {
                root.lastElectricArcCount = 0;
                return;
            }

            const now = root._electricPhase * 2.7;
            const compactScale = root.compact ? 0.72 : 0.95;
            const activeIdx = root.draggedIndex >= 0 ? root.draggedIndex : root.hoveredIndex;
            const acc = root.accentColor;
            const m = root._viewportMetrics();
            const scaleMul = m.sizeScale * root._zoomRadiusScale(root.zoom);
            const mode3D = root.is3D;

            const zdBuf = root._screenDepthBuf;
            const nodeScreenRadius = function(idx) {
                const b = (baseRadBuf && idx < baseRadBuf.length) ? baseRadBuf[idx] : 1.4;
                const d = (mode3D && scBuf && idx < scBuf.length) ? scBuf[idx] : 1.0;
                return Math.max(0.55, b * scaleMul * d);
            };
            const depthAttenuation = function(sIdx, tIdx) {
                if (!mode3D || !zdBuf) return 1.0;
                const avgZ = (zdBuf[sIdx] + zdBuf[tIdx]) * 0.5;
                return Math.max(0.22, Math.min(1.0, 0.65 + avgZ * 0.45));
            };
            const edgeVisible = function(e) {
                const sIdx = eSrc[e];
                const tIdx = eDst[e];
                if (isOrph && (isOrph[sIdx] === 1 || isOrph[tIdx] === 1)) return false;
                const x0 = sxBuf[sIdx], y0 = syBuf[sIdx];
                const x1 = sxBuf[tIdx], y1 = syBuf[tIdx];
                if ((x0 < -16 && x1 < -16) || (x0 > width + 16 && x1 > width + 16)
                        || (y0 < -16 && y1 < -16) || (y0 > height + 16 && y1 > height + 16))
                    return false;
                const rA = nodeScreenRadius(sIdx);
                const rB = nodeScreenRadius(tIdx);
                const dx = x1 - x0;
                const dy = y1 - y0;
                return Math.sqrt(dx * dx + dy * dy) > (rA + rB + 8.0);
            };

            let drawn = 0;
            if (root.isLocal) {
                // Local Graph: strictly 1 electric current arc total
                let chosenEdge = -1;
                let phaseT = (root._electricPhase * 0.42) % 1.0;
                let fadeAlpha = 0.94;

                if (activeIdx >= 0) {
                    const inc = [];
                    for (let e = 0; e < eLen; ++e) {
                        if ((eSrc[e] === activeIdx || eDst[e] === activeIdx) && edgeVisible(e))
                            inc.push(e);
                    }
                    if (inc.length > 0) {
                        const cycle = root._electricPhase * 0.36;
                        const gen = Math.floor(cycle);
                        const localT = cycle - gen;
                        chosenEdge = inc[gen % inc.length];
                        phaseT = localT;
                        fadeAlpha = Math.max(0.25, Math.sin(localT * Math.PI));
                    }
                }
                if (chosenEdge < 0) {
                    const cycle = root._electricPhase * 0.32;
                    const gen = Math.floor(cycle);
                    const localT = cycle - gen;
                    fadeAlpha = Math.sin(localT * Math.PI);
                    phaseT = localT;
                    for (let off = 0; off < eLen; ++off) {
                        const cand = (gen + off) % eLen;
                        if (edgeVisible(cand)) {
                            chosenEdge = cand;
                            break;
                        }
                    }
                }
                if (chosenEdge >= 0) {
                    const sIdx = eSrc[chosenEdge];
                    const tIdx = eDst[chosenEdge];
                    const col = root.resolvedNodeColors[sIdx]?.base ?? acc;
                    if (_drawElectricArc(ctx, sxBuf[sIdx], syBuf[sIdx], sxBuf[tIdx], syBuf[tIdx],
                            nodeScreenRadius(sIdx), nodeScreenRadius(tIdx),
                            col, now, chosenEdge + 1, phaseT, compactScale, fadeAlpha)) {
                        drawn = 1;
                    }
                }
            } else {
                // Vault Graph: strictly 1 electric current arc per note cluster
                const buckets = root._clusterEdgeBuckets;
                for (let b = 0; b < buckets.length; ++b) {
                    const bEdges = buckets[b].edges;
                    if (!bEdges || bEdges.length === 0)
                        continue;
                    let chosenEdge = -1;
                    let phaseT = 0.0;
                    let fadeAlpha = 0.9;

                    if (activeIdx >= 0) {
                        for (let k = 0; k < bEdges.length; ++k) {
                            const e = bEdges[k];
                            if ((eSrc[e] === activeIdx || eDst[e] === activeIdx) && edgeVisible(e)) {
                                chosenEdge = e;
                                phaseT = (root._electricPhase * 0.45 + b * 0.19) % 1.0;
                                fadeAlpha = 0.96;
                                break;
                            }
                        }
                    }
                    if (chosenEdge < 0) {
                        const cycle = root._electricPhase * 0.28 + b * 0.31;
                        const gen = Math.floor(cycle);
                        const localT = cycle - gen;
                        fadeAlpha = Math.sin(localT * Math.PI);
                        if (fadeAlpha < 0.05)
                            continue;
                        phaseT = localT;
                        const bLen = bEdges.length;
                        for (let off = 0; off < bLen; ++off) {
                            const cand = bEdges[(gen + off * 3) % bLen];
                            if (edgeVisible(cand)) {
                                chosenEdge = cand;
                                break;
                            }
                        }
                    }
                    if (chosenEdge >= 0) {
                        const sIdx = eSrc[chosenEdge];
                        const tIdx = eDst[chosenEdge];
                        const col = root.resolvedNodeColors[sIdx]?.base ?? acc;
                        if (_drawElectricArc(ctx, sxBuf[sIdx], syBuf[sIdx], sxBuf[tIdx], syBuf[tIdx],
                                nodeScreenRadius(sIdx), nodeScreenRadius(tIdx),
                                col, now, chosenEdge + 1 + b * 11, phaseT, compactScale, fadeAlpha * depthAttenuation(sIdx, tIdx))) {
                            drawn += 1;
                        }
                    }
                }
            }
            root.lastElectricArcCount = drawn;
        }
    }

    MouseArea {
        id: graphMouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
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
            panOverride = (mouse.button === Qt.MiddleButton || mouse.button === Qt.RightButton) || Boolean(mouse.modifiers & Qt.ShiftModifier);
            root._velYaw = 0.0;
            root._velPitch = 0.0;
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
                // Viewport-calibrated zoom-compensated 3D orbit (calm, controllable pixel speed at every zoom level)
                if (root.autoRotate3D && movedSignificantly)
                    root.autoRotate3D = false;
                const m3 = root._viewportMetrics();
                const orbitSpeed = 1.0 / Math.max(150.0, m3.radius3D * 1.45 * Math.max(1.0, root.zoom));
                const dYaw = stepDx * orbitSpeed;
                const dPitch = stepDy * orbitSpeed;
                root.rotYaw += dYaw;
                root.rotPitch = Math.max(-1.42, Math.min(1.42, root.rotPitch + dPitch));
                root._velYaw = dYaw * 0.48;
                root._velPitch = dPitch * 0.48;
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
                // Exact 1:1 screen-pixel pan (stays locked to pointer at any zoom level, zero speed explosion)
                root.panX += stepDx;
                root.panY += stepDy;
                root.requestPaint();
            }
        }

        onReleased: mouse => {
            const wasDraggingNode = root.draggedIndex;
            root.draggedIndex = -1;
            if (!movedSignificantly) {
                root._velYaw = 0.0;
                root._velPitch = 0.0;
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
            const delta = Math.max(-180, Math.min(180, wheel.angleDelta.y));
            if (delta === 0)
                return;
            const factor = Math.pow(1.0018, delta);
            root.zoomBy(factor, wheel.x, wheel.y);
            wheel.accepted = true;
        }
    }

    // Floating 2D/3D Switcher (Expanded Vault Graph) + Auto Orbit + Deep Zoom Controls
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

        // Optional 3D slow auto-orbit pill
        Rectangle {
            id: autoOrbitToggle
            objectName: "nexusGraphAutoOrbitToggle"
            visible: root.allow3D && root.is3D
            implicitWidth: autoOrbitRow.implicitWidth + 12
            implicitHeight: 24
            radius: 6
            color: root.autoRotate3D
                ? root.accentColor
                : Qt.rgba(root.bgSurface.r, root.bgSurface.g, root.bgSurface.b, 0.90)
            border.width: root.autoRotate3D ? 0 : 1
            border.color: root.borderSubtle

            Row {
                id: autoOrbitRow
                anchors.centerIn: parent
                spacing: 4
                MaterialSymbol {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "360"
                    iconSize: 12
                    color: root.autoRotate3D
                        ? (Appearance.colors?.colOnPrimary ?? "#0b1114")
                        : root.subtextColor
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Auto"
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                    color: root.autoRotate3D
                        ? (Appearance.colors?.colOnPrimary ?? "#0b1114")
                        : root.subtextColor
                }
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    root.autoRotate3D = !root.autoRotate3D;
                    if (!root.autoRotate3D) {
                        root._velYaw = 0.0;
                        root._velPitch = 0.0;
                    }
                    root.requestPaint();
                }
            }
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
