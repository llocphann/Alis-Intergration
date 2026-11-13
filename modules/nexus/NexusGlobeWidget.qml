import QtQuick
import QtQuick.Layouts
import qs
import qs.modules.common
import qs.modules.common.widgets
import "NexusGlobeData.js" as GlobeData

Item {
    id: root
    objectName: "nexusGlobeWidget"
    clip: true

    property var nexus: null
    property var workspace: null
    property var placesModel: root.nexus?.collections?.places ?? []
    property var places: placesModel
    property bool active: true

    // Interactive state matching `90_System/92_Scripts/Dataview/homepage/globe-widget.js`
    readonly property real baseScale: 0.84
    property real minZoom: 0.72
    property real maxZoom: 32.0
    property real defaultZoom: 0.92
    property real zoom: defaultZoom
    property bool autoRotate: true

    readonly property var initialCenter: root.sphericalCenter(root.places)
    property real centerLon: initialCenter.lon
    property real centerLat: initialCenter.lat
    property bool _userMoved: false
    property double pauseUntilMs: 0

    property var hoveredCluster: null
    property real hoverMouseX: 0
    property real hoverMouseY: 0
    property var visibleClusters: []

    readonly property real degToRad: Math.PI / 180.0
    readonly property var landData: GlobeData.LAND_POLYGONS ?? []
    readonly property var lakesData: GlobeData.LAKES_POLYGONS ?? []
    readonly property var riversData: GlobeData.RIVERS_LINES ?? []
    readonly property var bordersData: GlobeData.BORDERS_LINES ?? []

    function _compileSeq3D(seq): var {
        if (!Array.isArray(seq) || seq.length === 0)
            return null;
        const pts = new Array(seq.length);
        let sx = 0.0, sy = 0.0, sz = 0.0;
        const d2r = Math.PI / 180.0;
        for (let i = 0; i < seq.length; ++i) {
            const lonR = Number(seq[i][0]) * d2r;
            const latR = Number(seq[i][1]) * d2r;
            const cosLat = Math.cos(latR);
            const ux = cosLat * Math.sin(lonR);
            const uy = Math.sin(latR);
            const uz = cosLat * Math.cos(lonR);
            pts[i] = [ux, uy, uz];
            sx += ux;
            sy += uy;
            sz += uz;
        }
        const len = Math.hypot(sx, sy, sz);
        if (len < 1e-5) {
            return { pts: pts, bx: 0.0, by: 0.0, bz: 0.0, cullLimit: -2.0 };
        }
        const bx = sx / len;
        const by = sy / len;
        const bz = sz / len;
        let minDot = 1.0;
        for (let i = 0; i < pts.length; ++i) {
            const p = pts[i];
            const dot = p[0] * bx + p[1] * by + p[2] * bz;
            if (dot < minDot)
                minDot = dot;
        }
        // If minDot <= 0, the ring spans > 90 deg from its centroid; disable single-dot culling for that ring
        const cullLimit = minDot > 0.05 ? (-Math.sqrt(Math.max(0.0, 1.0 - minDot * minDot)) - 0.03) : -2.0;
        return { pts: pts, bx: bx, by: by, bz: bz, cullLimit: cullLimit };
    }

    function _compileMultiPolygons3D(polys): var {
        const out = [];
        const src = polys ?? [];
        for (let m = 0; m < src.length; ++m) {
            const poly = src[m];
            if (!Array.isArray(poly))
                continue;
            for (let r = 0; r < poly.length; ++r) {
                const compiled = root._compileSeq3D(poly[r]);
                if (compiled && compiled.pts.length >= 3)
                    out.push(compiled);
            }
        }
        return out;
    }

    function _compileLines3D(lines): var {
        const out = [];
        const src = lines ?? [];
        for (let i = 0; i < src.length; ++i) {
            const compiled = root._compileSeq3D(src[i]);
            if (compiled && compiled.pts.length >= 2)
                out.push(compiled);
        }
        return out;
    }

    readonly property var landRings3D: root._compileMultiPolygons3D(root.landData)
    readonly property var lakesRings3D: root._compileMultiPolygons3D(root.lakesData)
    readonly property var riversLines3D: root._compileLines3D(root.riversData)
    readonly property var bordersLines3D: root._compileLines3D(root.bordersData)
    readonly property var graticuleLines3D: {
        const rawLines = [];
        for (let lon = -180; lon < 180; lon += 10) {
            const line = [];
            for (let lat = -80; lat <= 80; lat += 5)
                line.push([lon, lat]);
            rawLines.push(line);
        }
        for (let lat = -80; lat <= 80; lat += 10) {
            const line = [];
            for (let lon = -180; lon <= 180; lon += 5)
                line.push([lon, lat]);
            rawLines.push(line);
        }
        return root._compileLines3D(rawLines);
    }

    readonly property var landStipplePoints: {
        const pts = [];
        const step = 3.6;
        const d2r = Math.PI / 180.0;
        // Precompute land stipple grid points inside major continental bounding boxes
        const boxes = [
            [-10, 35, 145, 70],   // Eurasia
            [95, -10, 142, 24],   // SE Asia & Maritime
            [68, 8, 90, 32],      // India
            [35, 13, 58, 32],     // Arabia
            [-17, -34, 50, 36],   // Africa
            [-165, 15, -55, 70],  // North America
            [-80, -54, -35, 11],  // South America
            [114, -38, 153, -12]  // Australia
        ];
        for (let b = 0; b < boxes.length; ++b) {
            const bx = boxes[b];
            for (let lat = bx[1]; lat <= bx[3]; lat += step) {
                const latR = lat * d2r;
                const cosLat = Math.cos(latR);
                const sinLat = Math.sin(latR);
                const lonStep = step / Math.max(0.32, cosLat);
                for (let lon = bx[0]; lon <= bx[2]; lon += lonStep) {
                    const lonR = lon * d2r;
                    pts.push([cosLat * Math.sin(lonR), sinLat, cosLat * Math.cos(lonR)]);
                }
            }
        }
        return pts;
    }

    function ccStop(idx: int): color {
        if (root.workspace && typeof root.workspace.ccStop === "function")
            return Qt.color(root.workspace.ccStop(idx));
        const l0 = Appearance.colors.colLayer0 ?? "#0a0e10";
        const l1 = Appearance.colors.colLayer1 ?? "#10181b";
        const l2 = Appearance.colors.colLayer2 ?? "#162024";
        const acc = Appearance.colors.colPrimary ?? "#a0cddf";
        const sub = Appearance.colors.colSubtext ?? "#7da0b0";
        const txt = Appearance.colors.colOnLayer1 ?? "#c6d6dc";
        switch (idx) {
        case 0: return Qt.darker(l0, 1.18);
        case 1: return l0;
        case 2: return l1;
        case 3: return l2;
        case 4: return Qt.lighter(l2, 1.15);
        case 5: return Qt.lighter(l2, 1.28);
        case 6: return Qt.tint(l2, Qt.rgba(acc.r, acc.g, acc.b, 0.25));
        case 7: return Qt.tint(l2, Qt.rgba(acc.r, acc.g, acc.b, 0.38));
        case 8: return Qt.tint(l2, Qt.rgba(acc.r, acc.g, acc.b, 0.50));
        case 9: return Qt.rgba(sub.r, sub.g, sub.b, 0.72);
        case 10: return Qt.rgba(sub.r, sub.g, sub.b, 0.86);
        case 11: return sub;
        case 12: return txt;
        case 13: return Appearance.colors.colOnLayer0 ?? Qt.lighter(txt, 1.12);
        default: return l1;
        }
    }

    readonly property color accentCol: root.workspace ? Qt.color(root.workspace._settledPrimary) : (Appearance.colors.colPrimary ?? "#a0cddf")

    function wrapLon(lon: real): real {
        let out = lon % 360.0;
        if (out > 180.0) out -= 360.0;
        if (out < -180.0) out += 360.0;
        return out;
    }

    function sphericalCenter(placeList): var {
        const list = placeList ?? [];
        let x = 0.0, y = 0.0, z = 0.0, count = 0;
        for (let i = 0; i < list.length; ++i) {
            const p = list[i];
            const lat = Number(p.lat);
            const lon = Number(p.lon);
            if (!Number.isFinite(lat) || !Number.isFinite(lon) || (!p.hasCoordinates && lat === 0 && lon === 0))
                continue;
            const latR = lat * (Math.PI / 180.0);
            const lonR = lon * (Math.PI / 180.0);
            const c = Math.cos(latR);
            x += c * Math.cos(lonR);
            y += Math.sin(latR);
            z += c * Math.sin(lonR);
            count++;
        }
        if (count === 0)
            return { lon: 105.0, lat: 16.0 };
        const lonDeg = Math.atan2(z, x) * (180.0 / Math.PI);
        const hyp = Math.hypot(x, z);
        const latDeg = Math.atan2(y, hyp) * (180.0 / Math.PI);
        return { lon: lonDeg, lat: Math.max(-72.0, Math.min(72.0, latDeg)) };
    }

    onPlacesChanged: {
        if (!root._userMoved) {
            const c = root.sphericalCenter(root.places);
            root.centerLon = c.lon;
            root.centerLat = c.lat;
        }
        root.requestPaint();
    }

    function resetGlobe() {
        const c = root.sphericalCenter(root.places);
        root._userMoved = false;
        root.centerLon = c.lon;
        root.centerLat = c.lat;
        root.zoom = root.defaultZoom;
        root.hoveredCluster = null;
        root.pauseUntilMs = Date.now() + 900;
        root.requestPaint();
    }

    function resetView() {
        root.resetGlobe();
    }

    function focusCluster(cluster) {
        if (!cluster)
            return;
        root._userMoved = true;
        root.centerLon = root.wrapLon(Number(cluster.lon));
        root.centerLat = Math.max(-78.0, Math.min(78.0, Number(cluster.lat)));
        root.zoom = Math.min(root.maxZoom, Math.max(2.4, Number((root.zoom * 2.1).toFixed(2))));
        root.hoveredCluster = null;
        root.pauseUntilMs = Date.now() + 2880;
        root.requestPaint();
    }

    // Orthographic 3D sphere projection matching `projectLonLat` in `globe-widget.js`
    function projectLonLat(lon: real, lat: real, cx: real, cy: real, R: real, cLon: real, cLat: real): var {
        const dlon = (lon - cLon) * root.degToRad;
        const latRad = lat * root.degToRad;
        const lat0 = cLat * root.degToRad;
        const sinLat0 = Math.sin(lat0);
        const cosLat0 = Math.cos(lat0);
        const sinLat = Math.sin(latRad);
        const cosLat = Math.cos(latRad);
        const x = cosLat * Math.sin(dlon);
        const y = cosLat0 * sinLat - sinLat0 * cosLat * Math.cos(dlon);
        const z = sinLat0 * sinLat + cosLat0 * cosLat * Math.cos(dlon);
        return {
            x: x,
            y: y,
            z: z,
            visible: z >= 0.0,
            onHorizon: false,
            sx: cx + x * R,
            sy: cy - y * R,
            angle: 0.0
        };
    }

    function _projectUnit3D(u, cx: real, cy: real, R: real, sinLon0: real, cosLon0: real, sinLat0: real, cosLat0: real): var {
        const ux = u[0];
        const uy = u[1];
        const uz = u[2];
        const x = ux * cosLon0 - uz * sinLon0;
        const rz = uz * cosLon0 + ux * sinLon0;
        const y = cosLat0 * uy - sinLat0 * rz;
        const z = sinLat0 * uy + cosLat0 * rz;
        return {
            x: x,
            y: y,
            z: z,
            visible: z >= 0.0,
            onHorizon: false,
            sx: cx + x * R,
            sy: cy - y * R,
            angle: 0.0
        };
    }

    function interpHorizon(a, b, cx: real, cy: real, R: real): var {
        const dz = a.z - b.z;
        const t = Math.abs(dz) < 1e-6 ? 0.5 : (a.z / dz);
        const ix = a.x + (b.x - a.x) * t;
        const iy = a.y + (b.y - a.y) * t;
        const len = Math.hypot(ix, iy) || 1.0;
        const nx = ix / len;
        const ny = iy / len;
        return {
            x: nx,
            y: ny,
            z: 0.0,
            visible: true,
            onHorizon: true,
            sx: cx + nx * R,
            sy: cy - ny * R,
            angle: Math.atan2(-ny, nx)
        };
    }

    // Clip precompiled closed polygon ring to the z >= 0 front hemisphere with fast bounding-sphere back-hemisphere culling
    function drawCompiledRing3D(ctx, compiledRing, cx: real, cy: real, R: real, sinLon0: real, cosLon0: real, sinLat0: real, cosLat0: real, vx: real, vy: real, vz: real) {
        if (!compiledRing)
            return false;
        const centerDot = compiledRing.bx * vx + compiledRing.by * vy + compiledRing.bz * vz;
        if (centerDot < compiledRing.cullLimit)
            return false;
        const ring = compiledRing.pts;
        const n = ring.length;
        if (n < 3)
            return false;
        const clipped = [];
        let prev = root._projectUnit3D(ring[n - 1], cx, cy, R, sinLon0, cosLon0, sinLat0, cosLat0);
        for (let i = 0; i < n; ++i) {
            const curr = root._projectUnit3D(ring[i], cx, cy, R, sinLon0, cosLon0, sinLat0, cosLat0);
            if (prev.visible && curr.visible) {
                clipped.push(curr);
            } else if (prev.visible && !curr.visible) {
                clipped.push(root.interpHorizon(prev, curr, cx, cy, R));
            } else if (!prev.visible && curr.visible) {
                clipped.push(root.interpHorizon(prev, curr, cx, cy, R));
                clipped.push(curr);
            }
            prev = curr;
        }
        if (clipped.length < 3)
            return false;

        ctx.moveTo(clipped[0].sx, clipped[0].sy);
        for (let i = 1; i <= clipped.length; ++i) {
            const pPrev = clipped[i - 1];
            const pCurr = clipped[i % clipped.length];
            if (pPrev.onHorizon && pCurr.onHorizon) {
                let dAng = pCurr.angle - pPrev.angle;
                while (dAng > Math.PI) dAng -= Math.PI * 2.0;
                while (dAng < -Math.PI) dAng += Math.PI * 2.0;
                const steps = Math.max(4, Math.ceil(Math.abs(dAng) / 0.14));
                for (let s = 1; s <= steps; ++s) {
                    const ang = pPrev.angle + (dAng * s) / steps;
                    ctx.lineTo(cx + Math.cos(ang) * R, cy + Math.sin(ang) * R);
                }
            } else {
                ctx.lineTo(pCurr.sx, pCurr.sy);
            }
        }
        ctx.closePath();
        return true;
    }

    // Clip precompiled polyline to z >= 0 front hemisphere with fast bounding-sphere culling
    function strokeCompiledLine3D(ctx, compiledLine, cx: real, cy: real, R: real, sinLon0: real, cosLon0: real, sinLat0: real, cosLat0: real, vx: real, vy: real, vz: real, closeLoop: bool) {
        if (!compiledLine)
            return;
        const centerDot = compiledLine.bx * vx + compiledLine.by * vy + compiledLine.bz * vz;
        if (centerDot < compiledLine.cullLimit)
            return;
        const line = compiledLine.pts;
        const n = line.length;
        if (n < 2)
            return;
        const total = closeLoop ? n + 1 : n;
        let prev = root._projectUnit3D(line[0], cx, cy, R, sinLon0, cosLon0, sinLat0, cosLat0);
        let inSeg = false;
        if (prev.visible) {
            ctx.moveTo(prev.sx, prev.sy);
            inSeg = true;
        }
        for (let i = 1; i < total; ++i) {
            const pt = line[i % n];
            const curr = root._projectUnit3D(pt, cx, cy, R, sinLon0, cosLon0, sinLat0, cosLat0);
            if (prev.visible && curr.visible) {
                if (!inSeg) {
                    ctx.moveTo(prev.sx, prev.sy);
                    inSeg = true;
                }
                ctx.lineTo(curr.sx, curr.sy);
            } else if (prev.visible && !curr.visible) {
                const h = root.interpHorizon(prev, curr, cx, cy, R);
                if (!inSeg)
                    ctx.moveTo(prev.sx, prev.sy);
                ctx.lineTo(h.sx, h.sy);
                inSeg = false;
            } else if (!prev.visible && curr.visible) {
                const h = root.interpHorizon(prev, curr, cx, cy, R);
                ctx.moveTo(h.sx, h.sy);
                ctx.lineTo(curr.sx, curr.sy);
                inSeg = true;
            }
            prev = curr;
        }
    }

    // Auto-rotation timer (~25 FPS smooth spin when autoRotate === true, transition settled, and not taking screenshot)
    Timer {
        id: spinTimer
        objectName: "nexusGlobeSpinTimer"
        interval: 40
        repeat: true
        running: root.visible && root.active && root.autoRotate && !globeMouse.pressed && Boolean(root.nexus ? root.nexus.isOpen : true) && root.hostSettled && Boolean(root.workspace ? root.workspace.surfaceActive : true) && !Boolean(GlobalStates.regionSelectorOpen) && !Boolean(GlobalStates.annotationEditorOpen)
        onTriggered: {
            const now = Date.now();
            if (now < root.pauseUntilMs)
                return;
            const speedFactor = 1.0 / Math.pow(Math.max(1.0, root.zoom), 0.72);
            root.centerLon = root.wrapLon(root.centerLon + 40.0 * 0.0019 * 4.5 * speedFactor);
            root.requestPaint();
        }
    }

    property int revealStaggerMs: 0
    property bool _needsStaggeredReveal: true
    property bool _paintPending: true
    property int paintCount: 0

    Timer {
        id: staggerGlobePaintTimer
        interval: Math.max(1, root.revealStaggerMs)
        repeat: false
        onTriggered: {
            if (root.canRepaintTheme) {
                root._needsStaggeredReveal = false;
                globeCanvas.requestPaint();
            }
        }
    }

    function requestPaint(): void {
        root._paintPending = true;
        if (!root.canRepaintTheme)
            return;
        if (root.revealStaggerMs > 0 && root._needsStaggeredReveal && !globeMouse.pressed) {
            if (!staggerGlobePaintTimer.running)
                staggerGlobePaintTimer.start();
            return;
        }
        staggerGlobePaintTimer.stop();
        globeCanvas.requestPaint();
    }
    property string lastPaintedAccentHex: ""
    property string lastPaintedThemeSignature: ""
    readonly property bool hostOpen: Boolean(root.nexus?.isOpen ?? root.workspace?.nexus?.isOpen ?? true)
    readonly property bool hostSettled: root.workspace ? Boolean(root.workspace.transitionSettled) : true
    readonly property bool hostSurfaceActive: Boolean(root.workspace ? root.workspace.surfaceActive : true)
    readonly property bool canRepaintTheme: root.visible && root.hostOpen && root.hostSurfaceActive && root.hostSettled
    readonly property string themeSignature: root.workspace ? root.workspace.themeSignature : [
        String(root.accentCol),
        String(Appearance.colors?.colPrimary ?? ""),
        String(Appearance.colors?.colSecondary ?? ""),
        String(Appearance.colors?.colTertiary ?? ""),
        String(Appearance.colors?.colLayer0 ?? ""),
        String(Appearance.colors?.colLayer1 ?? ""),
        String(Appearance.colors?.colLayer2 ?? ""),
        String(Appearance.colors?.colOnLayer1 ?? ""),
        String(Appearance.colors?.colOnLayer0 ?? ""),
        String(Appearance.colors?.colSubtext ?? "")
    ].join("|")

    function _triggerThemeRepaint(): void {
        if (!root.canRepaintTheme) {
            deferredGlobeThemeRepaintTimer.stop();
            return;
        }
        root.requestPaint();
        deferredGlobeThemeRepaintTimer.restart();
    }

    function _flushPendingPaintOnResume(): void {
        if (!root.canRepaintTheme) {
            deferredGlobeThemeRepaintTimer.stop();
            staggerGlobePaintTimer.stop();
            return;
        }
        if (root._paintPending || root.lastPaintedThemeSignature !== root.themeSignature)
            root.requestPaint();
    }

    Timer {
        id: deferredGlobeThemeRepaintTimer
        interval: 24
        repeat: false
        onTriggered: {
            if (root.canRepaintTheme)
                root.requestPaint();
        }
    }

    onThemeSignatureChanged: {
        const _sig = root.themeSignature;
        root._triggerThemeRepaint();
    }
    onHostOpenChanged: {
        if (!root.hostOpen) {
            root._needsStaggeredReveal = true;
            staggerGlobePaintTimer.stop();
        }
    }
    onCanRepaintThemeChanged: {
        root._flushPendingPaintOnResume();
    }
    onHostSettledChanged: {
        if (!hostSettled) {
            root._needsStaggeredReveal = true;
            staggerGlobePaintTimer.stop();
        } else {
            root._flushPendingPaintOnResume();
        }
    }

    Canvas {
        id: globeCanvas
        anchors.fill: parent
        antialiasing: true
        onWidthChanged: root.requestPaint()
        onHeightChanged: root.requestPaint()
        onVisibleChanged: {
            if (visible)
                root.requestPaint();
        }
        onAvailableChanged: {
            if (available)
                root.requestPaint();
        }

        onPaint: {
            // Ignore frames queued before the workspace paused; redraw on resume.
            if (!root.canRepaintTheme) {
                root._paintPending = true;
                return;
            }
            if (width < 20 || height < 20)
                return;
            const ctx = getContext("2d");
            if (!ctx)
                return;
            const w = width;
            const h = height;
            root._paintPending = false;
            root._needsStaggeredReveal = false;
            ctx.clearRect(0, 0, w, h);

            const cx = w * 0.5;
            const cy = h * 0.5 - 6;
            const baseR = Math.min(w, h - 18) * 0.5 * root.baseScale;
            const R = Math.max(24, baseR * root.zoom);
            const cLon = root.centerLon;
            const cLat = root.centerLat;
            const lon0R = cLon * root.degToRad;
            const lat0R = cLat * root.degToRad;
            const sinLon0 = Math.sin(lon0R);
            const cosLon0 = Math.cos(lon0R);
            const sinLat0 = Math.sin(lat0R);
            const cosLat0 = Math.cos(lat0R);
            const vx = cosLat0 * sinLon0;
            const vy = sinLat0;
            const vz = cosLat0 * cosLon0;

            const p00 = root.ccStop(0);
            const p01 = root.ccStop(1);
            const p02 = root.ccStop(2);
            const p03 = root.ccStop(3);
            const p04 = root.ccStop(4);
            const p07 = root.ccStop(7);
            const p08 = root.ccStop(8);
            const p09 = root.ccStop(9);
            const p10 = root.ccStop(10);
            const p11 = root.ccStop(11);
            const p12 = root.ccStop(12);
            const acc = root.accentCol;
            root.paintCount += 1;
            root.lastPaintedAccentHex = String(acc);
            root.lastPaintedThemeSignature = root.themeSignature;

            // 1. Outer Atmosphere Glow (`radius * 1.045`, `alpha = 0.08` in `globe-widget.js`)
            const haloGrad = ctx.createRadialGradient(cx, cy, R * 0.94, cx, cy, R * 1.06);
            haloGrad.addColorStop(0.0, Qt.rgba(acc.r, acc.g, acc.b, 0.10));
            haloGrad.addColorStop(0.65, Qt.rgba(acc.r, acc.g, acc.b, 0.04));
            haloGrad.addColorStop(1.0, Qt.rgba(acc.r, acc.g, acc.b, 0.0));
            ctx.beginPath();
            ctx.arc(cx, cy, R * 1.06, 0, Math.PI * 2);
            ctx.fillStyle = haloGrad;
            ctx.fill();

            // 2. Ocean Sphere with directional lighting matching `renderSphereImage` (`z * 0.78 + p.y * 0.14 - p.x * 0.08`)
            const oceanGrad = ctx.createRadialGradient(cx - R * 0.14, cy - R * 0.22, R * 0.04, cx, cy, R);
            oceanGrad.addColorStop(0.0, Qt.rgba(p02.r, p02.g, p02.b, 0.98));
            oceanGrad.addColorStop(0.58, Qt.rgba(p01.r, p01.g, p01.b, 0.98));
            oceanGrad.addColorStop(1.0, Qt.rgba(p00.r, p00.g, p00.b, 1.0));
            ctx.beginPath();
            ctx.arc(cx, cy, R, 0, Math.PI * 2);
            ctx.fillStyle = oceanGrad;
            ctx.fill();

            ctx.save();
            ctx.beginPath();
            ctx.arc(cx, cy, R, 0, Math.PI * 2);
            ctx.clip();

            // 3. 10° Graticule Grid (`step = 10`, `lineWidth = 0.52`, `alpha = 0.30` in `globe-widget.js`)
            ctx.strokeStyle = Qt.rgba(p04.r, p04.g, p04.b, 0.32);
            ctx.lineWidth = 0.52;
            ctx.beginPath();
            const grats = root.graticuleLines3D;
            for (let g = 0; g < grats.length; ++g) {
                root.strokeCompiledLine3D(ctx, grats[g], cx, cy, R, sinLon0, cosLon0, sinLat0, cosLat0, vx, vy, vz, false);
            }
            ctx.stroke();

            // 4. Land Polygons (`land = p03` + `landLift = p04` at `0.22` alpha)
            ctx.beginPath();
            const lRings = root.landRings3D;
            for (let r = 0; r < lRings.length; ++r) {
                root.drawCompiledRing3D(ctx, lRings[r], cx, cy, R, sinLon0, cosLon0, sinLat0, cosLat0, vx, vy, vz);
            }
            ctx.fillStyle = Qt.rgba(p03.r, p03.g, p03.b, 0.96);
            ctx.fill();
            ctx.fillStyle = Qt.rgba(p04.r, p04.g, p04.b, 0.22);
            ctx.fill();

            // 4B. Land Stipple (`addLandStipple` in `globe-widget.js`: `p10`, `alpha = 0.15`, `r = 0.62` when `zoom <= 2.35`)
            if (root.zoom <= 2.35) {
                ctx.fillStyle = Qt.rgba(p10.r, p10.g, p10.b, 0.15);
                ctx.beginPath();
                const stipple = root.landStipplePoints;
                for (let s = 0; s < stipple.length; ++s) {
                    const u = stipple[s];
                    const rz = u[2] * cosLon0 + u[0] * sinLon0;
                    const z = sinLat0 * u[1] + cosLat0 * rz;
                    if (z < 0.14)
                        continue;
                    const x = u[0] * cosLon0 - u[2] * sinLon0;
                    const y = cosLat0 * u[1] - sinLat0 * rz;
                    const sx = cx + x * R;
                    const sy = cy - y * R;
                    ctx.moveTo(sx + 0.65, sy);
                    ctx.arc(sx, sy, 0.65, 0, Math.PI * 2);
                }
                ctx.fill();
            }

            // 5. Lakes Polygons (`lake = p02` at `0.84` alpha + `lakeStroke = p08` at `0.42` alpha)
            const lkRings = root.lakesRings3D;
            if (lkRings.length > 0) {
                ctx.beginPath();
                for (let r = 0; r < lkRings.length; ++r) {
                    root.drawCompiledRing3D(ctx, lkRings[r], cx, cy, R, sinLon0, cosLon0, sinLat0, cosLat0, vx, vy, vz);
                }
                ctx.fillStyle = Qt.rgba(p02.r, p02.g, p02.b, 0.84);
                ctx.fill();
                ctx.strokeStyle = Qt.rgba(p08.r, p08.g, p08.b, 0.42);
                ctx.lineWidth = 0.55;
                ctx.stroke();
            }

            // 6. Rivers (`river = p08`, `lineWidth = zoom > 2.2 ? 0.72 : 0.55`, `alpha = zoom > 1.35 ? 0.50 : 0.34`)
            const rvLines = root.riversLines3D;
            if (rvLines.length > 0) {
                ctx.beginPath();
                for (let i = 0; i < rvLines.length; ++i) {
                    root.strokeCompiledLine3D(ctx, rvLines[i], cx, cy, R, sinLon0, cosLon0, sinLat0, cosLat0, vx, vy, vz, false);
                }
                ctx.strokeStyle = Qt.rgba(p08.r, p08.g, p08.b, root.zoom > 1.35 ? 0.50 : 0.34);
                ctx.lineWidth = root.zoom > 2.2 ? 0.72 : 0.55;
                ctx.stroke();
            }

            // 7. Country Borders (`border = p07`, `lineWidth = zoom > 2.2 ? 0.58 : 0.45`, `alpha = zoom > 1.35 ? 0.44 : 0.28`)
            const bdLines = root.bordersLines3D;
            if (bdLines.length > 0) {
                ctx.beginPath();
                for (let i = 0; i < bdLines.length; ++i) {
                    root.strokeCompiledLine3D(ctx, bdLines[i], cx, cy, R, sinLon0, cosLon0, sinLat0, cosLat0, vx, vy, vz, false);
                }
                ctx.strokeStyle = Qt.rgba(p07.r, p07.g, p07.b, root.zoom > 1.35 ? 0.44 : 0.28);
                ctx.lineWidth = root.zoom > 2.2 ? 0.58 : 0.45;
                ctx.stroke();
            }

            // 8. Coastline Stroke (`coast = p09`, `lineWidth = 0.78`, `alpha = 0.62` via `strokeCompiledLine3D` so horizon chords are never stroked)
            ctx.beginPath();
            for (let r = 0; r < lRings.length; ++r) {
                root.strokeCompiledLine3D(ctx, lRings[r], cx, cy, R, sinLon0, cosLon0, sinLat0, cosLat0, vx, vy, vz, true);
            }
            ctx.strokeStyle = Qt.rgba(p09.r, p09.g, p09.b, 0.62);
            ctx.lineWidth = 0.78;
            ctx.stroke();

            // 9. 3D Limb Shading + Specular Highlight (`renderSphereImage` rim & light in `globe-widget.js`)
            const limbGrad = ctx.createRadialGradient(cx - R * 0.12, cy - R * 0.20, R * 0.12, cx, cy, R);
            limbGrad.addColorStop(0.0, Qt.rgba(acc.r, acc.g, acc.b, 0.05));
            limbGrad.addColorStop(0.68, "transparent");
            limbGrad.addColorStop(0.90, Qt.rgba(p00.r, p00.g, p00.b, 0.24));
            limbGrad.addColorStop(1.0, Qt.rgba(acc.r, acc.g, acc.b, 0.14));
            ctx.fillStyle = limbGrad;
            ctx.fillRect(cx - R, cy - R, R * 2, R * 2);

            ctx.restore();

            // Outer Globe Rim Stroke (`rim = p07`, `lineWidth = 1`, `alpha = 0.68`)
            ctx.beginPath();
            ctx.arc(cx, cy, R, 0, Math.PI * 2);
            ctx.strokeStyle = Qt.rgba(p07.r, p07.g, p07.b, 0.68);
            ctx.lineWidth = 1.0;
            ctx.stroke();

            // 10. Place Markers: Greedy Screen-Space Clustering (`clusterMarkers`) + Radial T-Cap Callouts (`drawLineTarget`)
            const rawMarkers = [];
            const plist = root.places ?? [];
            for (let i = 0; i < plist.length; ++i) {
                const pl = plist[i];
                const lat = Number(pl.lat);
                const lon = Number(pl.lon);
                if (!Number.isFinite(lat) || !Number.isFinite(lon) || (!pl.hasCoordinates && lat === 0 && lon === 0))
                    continue;
                const pr = root.projectLonLat(lon, lat, cx, cy, R, cLon, cLat);
                if (!pr.visible || pr.z < 0.05)
                    continue;
                const vis = Boolean(pl.visited);
                const wtv = !vis && (Boolean(pl.wantToVisit) || String(pl.status || "").toLowerCase().includes("want") || String(pl.status || "").toLowerCase().includes("plan") || String(pl.status || "").toLowerCase().includes("bucket"));
                rawMarkers.push({
                    title: String(pl.title || "Place"),
                    relPath: String(pl.relPath || ""),
                    category: String(pl.placeType || pl.category || "place"),
                    visited: vis,
                    wantToVisit: wtv,
                    status: wtv ? "planned" : (vis ? "visited" : "saved"),
                    lat: lat,
                    lon: lon,
                    x: pr.sx,
                    y: pr.sy,
                    z: pr.z
                });
            }

            rawMarkers.sort((a, b) => b.z - a.z);
            const clusterDist = root.zoom < 1.3 ? 11.0 : (root.zoom < 2.2 ? 9.0 : (root.zoom < 4.0 ? 7.0 : 5.0));
            const clusters = [];
            for (let i = 0; i < rawMarkers.length; ++i) {
                const m = rawMarkers[i];
                let merged = false;
                for (let j = 0; j < clusters.length; ++j) {
                    const c = clusters[j];
                    if (Math.hypot(m.x - c.x, m.y - c.y) <= clusterDist) {
                        c.items.push(m);
                        c.x = (c.x * (c.items.length - 1) + m.x) / c.items.length;
                        c.y = (c.y * (c.items.length - 1) + m.y) / c.items.length;
                        c.lat = (c.lat * (c.items.length - 1) + m.lat) / c.items.length;
                        c.lon = (c.lon * (c.items.length - 1) + m.lon) / c.items.length;
                        if (m.visited) c.visited = true;
                        if (m.wantToVisit) c.wantToVisit = true;
                        merged = true;
                        break;
                    }
                }
                if (!merged) {
                    clusters.push({
                        x: m.x,
                        y: m.y,
                        z: m.z,
                        lat: m.lat,
                        lon: m.lon,
                        visited: m.visited,
                        wantToVisit: m.wantToVisit,
                        primary: m,
                        items: [m]
                    });
                }
            }
            root.visibleClusters = clusters;

            for (let i = 0; i < clusters.length; ++i) {
                const cl = clusters[i];
                const isHov = (root.hoveredCluster === cl);
                const count = cl.items.length;
                const planned = !cl.visited && cl.wantToVisit;
                const visited = cl.visited;

                // Exact marker color from `markerColor` in `globe-widget.js`: visited -> accent, planned -> p11, saved -> p09
                const pinCol = visited ? acc : (planned ? p11 : p09);
                const dx = cl.x - cx;
                const dy = cl.y - cy;
                const radialLen = Math.hypot(dx, dy);
                const nx = radialLen > 4.0 ? (dx / radialLen) : 0.0;
                const ny = radialLen > 4.0 ? (dy / radialLen) : -1.0;
                const tx = -ny;
                const ty = nx;

                const length = (planned ? 9.0 : (visited ? 7.5 : 6.2))
                    + Math.min(4.5, Math.max(0, count - 1) * 0.45)
                    + (isHov ? 1.5 : 0.0);
                const startX = cl.x + nx * 1.2;
                const startY = cl.y + ny * 1.2;
                const endX = cl.x + nx * length;
                const endY = cl.y + ny * length;
                const cap = isHov ? 2.4 : 1.8;

                // Radial stem (dashed for `want to visit` / `planned`)
                ctx.save();
                ctx.strokeStyle = Qt.rgba(pinCol.r, pinCol.g, pinCol.b, isHov ? 1.0 : 0.90);
                ctx.fillStyle = Qt.rgba(pinCol.r, pinCol.g, pinCol.b, isHov ? 1.0 : 0.92);
                ctx.lineWidth = isHov ? 1.35 : 1.0;
                if (planned && typeof ctx.setLineDash === "function")
                    ctx.setLineDash([2.5, 1.7]);
                ctx.beginPath();
                ctx.moveTo(startX, startY);
                ctx.lineTo(endX, endY);
                ctx.stroke();

                // Single perpendicular T-cap at tip (`drawLineTarget` in `globe-widget.js`)
                if (typeof ctx.setLineDash === "function")
                    ctx.setLineDash([]);
                ctx.beginPath();
                ctx.moveTo(endX - tx * cap, endY - ty * cap);
                ctx.lineTo(endX + tx * cap, endY + ty * cap);
                ctx.stroke();

                // Small surface anchor dot
                ctx.beginPath();
                ctx.arc(cl.x, cl.y, isHov ? 1.35 : 0.9, 0, Math.PI * 2);
                ctx.fill();

                // Cluster multiplier label `×N`
                if (count > 1) {
                    ctx.font = "600 8px monospace";
                    ctx.fillStyle = Qt.rgba(p12.r, p12.g, p12.b, 0.92);
                    ctx.fillText("×" + String(count), endX + nx * 4.5 - 4, endY + ny * 4.5 + 3);
                }
                ctx.restore();
            }
        }
    }

    // Drag-to-rotate, wheel-to-zoom, hover-to-inspect, click-to-focus/open
    MouseArea {
        id: globeMouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        cursorShape: pressed ? Qt.ClosedHandCursor : (root.hoveredCluster !== null ? Qt.PointingHandCursor : Qt.OpenHandCursor)

        property real pressX: 0
        property real pressY: 0
        property real dragStartLon: 0
        property real dragStartLat: 0
        property bool dragged: false

        onPressed: mouse => {
            pressX = mouse.x;
            pressY = mouse.y;
            dragStartLon = root.centerLon;
            dragStartLat = root.centerLat;
            dragged = false;
            root.pauseUntilMs = Date.now() + 1800;
        }

        onPositionChanged: mouse => {
            if (pressed) {
                const dx = mouse.x - pressX;
                const dy = mouse.y - pressY;
                if (Math.hypot(dx, dy) > 3)
                    dragged = true;
                if (dragged) {
                    root._userMoved = true;
                    const degPerPx = 0.28 / Math.pow(Math.max(1.0, root.zoom), 0.92);
                    root.centerLon = root.wrapLon(dragStartLon - dx * degPerPx);
                    root.centerLat = Math.max(-78.0, Math.min(78.0, dragStartLat + dy * degPerPx));
                    root.hoveredCluster = null;
                    root.pauseUntilMs = Date.now() + 1800;
                    root.requestPaint();
                }
                return;
            }

            // Hit-test visible place clusters (`hitTolerance = 8.5` in `globe-widget.js`)
            const cx = root.width * 0.5;
            const cy = root.height * 0.5 - 6;
            let best = null;
            let bestD = 9.5;
            for (let i = 0; i < root.visibleClusters.length; ++i) {
                const cl = root.visibleClusters[i];
                const dx = cl.x - cx;
                const dy = cl.y - cy;
                const rLen = Math.hypot(dx, dy);
                const nx = rLen > 4.0 ? (dx / rLen) : 0.0;
                const ny = rLen > 4.0 ? (dy / rLen) : -1.0;
                const dBase = Math.hypot(mouse.x - cl.x, mouse.y - cl.y);
                const dTip = Math.hypot(mouse.x - (cl.x + nx * 7.5), mouse.y - (cl.y + ny * 7.5));
                const d = Math.min(dBase, dTip);
                if (d < bestD) {
                    bestD = d;
                    best = cl;
                }
            }
            if (best !== root.hoveredCluster) {
                root.hoveredCluster = best;
                root.requestPaint();
            }
            if (best) {
                root.hoverMouseX = mouse.x;
                root.hoverMouseY = mouse.y;
            }
        }

        onReleased: mouse => {
            root.pauseUntilMs = Date.now() + 1800;
            if (!dragged && root.hoveredCluster) {
                if (root.hoveredCluster.items.length > 1) {
                    root.focusCluster(root.hoveredCluster);
                } else if (root.hoveredCluster.primary?.relPath && root.nexus) {
                    root.nexus.openFile(root.hoveredCluster.primary.relPath, true);
                }
            }
        }

        onExited: {
            if (root.hoveredCluster !== null) {
                root.hoveredCluster = null;
                root.requestPaint();
            }
        }

        onWheel: wheel => {
            const factor = wheel.angleDelta.y > 0 ? 1.13 : (1.0 / 1.13);
            root.zoom = Math.max(root.minZoom, Math.min(root.maxZoom, Number((root.zoom * factor).toFixed(2))));
            root.pauseUntilMs = Date.now() + 1800;
            root.requestPaint();
            wheel.accepted = true;
        }
    }

    // Hover Tooltip (`.globe-tip` from `globe-widget.js`)
    Rectangle {
        id: globeTooltip
        visible: root.hoveredCluster !== null && !globeMouse.pressed
        x: Math.max(6, Math.min(root.width - width - 6, root.hoverMouseX + 10))
        y: Math.max(6, Math.min(root.height - height - 6, root.hoverMouseY - height - 8))
        width: Math.min(200, tipCol.implicitWidth + 14)
        height: tipCol.implicitHeight + 10
        radius: 5
        color: Qt.rgba(root.ccStop(1).r, root.ccStop(1).g, root.ccStop(1).b, 0.94)
        border.width: 1
        border.color: Qt.alpha(root.accentCol, 0.42)
        z: 10

        ColumnLayout {
            id: tipCol
            anchors.centerIn: parent
            spacing: 2

            StyledText {
                Layout.maximumWidth: 184
                text: {
                    if (!root.hoveredCluster)
                        return "";
                    const n = root.hoveredCluster.items.length;
                    if (n > 1) {
                        const names = root.hoveredCluster.items.slice(0, 3).map(it => it.title).join(", ");
                        return String(n) + " places · " + names + (n > 3 ? " +" + String(n - 3) + " more" : "");
                    }
                    return String(root.hoveredCluster.primary?.title ?? "");
                }
                font.family: Appearance.font.family.monospace
                font.pixelSize: 10
                font.weight: Font.Bold
                color: root.ccStop(12)
                elide: Text.ElideRight
            }

            StyledText {
                text: {
                    if (!root.hoveredCluster)
                        return "";
                    if (root.hoveredCluster.items.length > 1)
                        return "click to zoom cluster";
                    const p = root.hoveredCluster.primary;
                    const st = p?.visited ? "visited" : (p?.wantToVisit ? "want to visit" : "saved");
                    return st + " · click to open";
                }
                font.family: Appearance.font.family.monospace
                font.pixelSize: 9
                color: root.accentCol
            }
        }
    }

    // Bottom-Left Footer Legend (`.hd-globe-footer` with line swatches from `globe-widget.js`)
    Row {
        objectName: "nexusGlobeFooterLegend"
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.leftMargin: 12
        anchors.bottomMargin: 7
        spacing: 9
        z: 6

        // visited
        Row {
            spacing: 4
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 10
                height: 1.5
                color: root.accentCol
            }
            StyledText {
                text: "visited"
                font.family: Appearance.font.family.monospace
                font.pixelSize: 8
                color: root.ccStop(9)
            }
        }

        // want to visit
        Row {
            spacing: 4
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1.5
                Repeater {
                    model: 3
                    delegate: Rectangle {
                        width: 2.5
                        height: 1.5
                        color: root.ccStop(11)
                    }
                }
            }
            StyledText {
                text: "want to visit"
                font.family: Appearance.font.family.monospace
                font.pixelSize: 8
                color: root.ccStop(9)
            }
        }

        // saved
        Row {
            spacing: 4
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 10
                height: 1.5
                color: root.ccStop(9)
            }
            StyledText {
                text: "saved"
                font.family: Appearance.font.family.monospace
                font.pixelSize: 8
                color: root.ccStop(9)
            }
        }
    }

    // Bottom-Right Hover-Revealed Controls (`.globe-ctrl`: `reset` & `auto:on` / `auto:off` at `right: 12px; bottom: 8px` in `globe-widget.js`)
    Row {
        id: globeCtrlRow
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 10
        anchors.bottomMargin: 6
        spacing: 4
        z: 8
        opacity: (globeMouse.containsMouse || resetBtnMouse.containsMouse || autoBtnMouse.containsMouse) ? 1.0 : 0.0
        Behavior on opacity {
            NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
        }

        Rectangle {
            objectName: "nexusGlobeResetButton"
            height: 18
            width: resetTxt.implicitWidth + 10
            radius: 4
            color: resetBtnMouse.containsMouse
                ? Qt.rgba(root.ccStop(3).r, root.ccStop(3).g, root.ccStop(3).b, 0.92)
                : Qt.rgba(root.ccStop(1).r, root.ccStop(1).g, root.ccStop(1).b, 0.84)
            border.width: 1
            border.color: resetBtnMouse.containsMouse ? root.accentCol : root.ccStop(5)

            StyledText {
                id: resetTxt
                anchors.centerIn: parent
                text: "reset"
                font.family: Appearance.font.family.monospace
                font.pixelSize: 8
                color: resetBtnMouse.containsMouse ? root.accentCol : root.ccStop(11)
            }

            MouseArea {
                id: resetBtnMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.resetGlobe()
            }
        }

        Rectangle {
            objectName: "nexusGlobeAutoButton"
            height: 18
            width: autoTxt.implicitWidth + 10
            radius: 4
            color: autoBtnMouse.containsMouse
                ? Qt.rgba(root.ccStop(3).r, root.ccStop(3).g, root.ccStop(3).b, 0.92)
                : Qt.rgba(root.ccStop(1).r, root.ccStop(1).g, root.ccStop(1).b, 0.84)
            border.width: 1
            border.color: (root.autoRotate || autoBtnMouse.containsMouse) ? root.accentCol : root.ccStop(5)

            StyledText {
                id: autoTxt
                anchors.centerIn: parent
                text: root.autoRotate ? "auto:on" : "auto:off"
                font.family: Appearance.font.family.monospace
                font.pixelSize: 8
                color: root.autoRotate ? root.accentCol : root.ccStop(10)
            }

            MouseArea {
                id: autoBtnMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    root.autoRotate = !root.autoRotate;
                    if (root.autoRotate)
                        root.pauseUntilMs = 0;
                }
            }
        }
    }
}
