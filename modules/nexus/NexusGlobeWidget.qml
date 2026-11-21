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
    // and `globe-vector-map-overlay.js` (smooth cross-fade from 3D Globe -> Detailed Map).
    readonly property real baseScale: 0.84
    property real minZoom: 0.72
    property real maxZoom: 64.0
    property real defaultZoom: 0.92
    property real zoom: defaultZoom
    property bool autoRotate: true
    // Smooth Globe -> Detailed Interactive Map cross-fade thresholds (`START = 1.42`, `FULL = 2.18`)
    // matching `globe-vector-map-overlay.js`. Users can also pin "globe" or "map".
    property string viewModePreference: "auto" // "auto" | "globe" | "map"
    property string mapStyle: "themed" // "themed" (Alis auto-themed) | "color" (Voyager full-color)
    property bool onlineTilesEnabled: true
    readonly property real mapFadeStartZoom: 1.42
    readonly property real mapFadeFullZoom: 2.18
    readonly property real mapBlend: {
        if (root.viewModePreference === "map")
            return 1.0;
        if (root.viewModePreference === "globe")
            return 0.0;
        const t = Math.max(0.0, Math.min(1.0, (root.zoom - root.mapFadeStartZoom) / (root.mapFadeFullZoom - root.mapFadeStartZoom)));
        return t * t * (3.0 - 2.0 * t);
    }
    readonly property bool isMapMode: root.mapBlend >= 0.48
    readonly property real effectiveMapZoom: root.mapZoom(root.zoom)
    property real hoverGeoLat: NaN
    property real hoverGeoLon: NaN

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

    // Curated offline world + Southeast Asia / Vietnam cities for progressive zoom detail & Map mode
    // Format: [name, lon, lat, rank] (rank 1 = mega/capital, 2 = major, 3 = regional)
    readonly property var worldCities: [
        ["Hanoi", 105.854, 21.028, 1],
        ["Ho Chi Minh City", 106.660, 10.777, 1],
        ["Da Nang", 108.202, 16.054, 2],
        ["Hue", 107.590, 16.463, 3],
        ["Hai Phong", 106.688, 20.844, 3],
        ["Nha Trang", 109.196, 12.238, 3],
        ["Da Lat", 108.458, 11.940, 3],
        ["Can Tho", 105.747, 10.045, 3],
        ["Phu Quoc", 103.984, 10.227, 3],
        ["Sapa", 103.844, 22.336, 3],
        ["Tokyo", 139.691, 35.689, 1],
        ["Osaka", 135.502, 34.693, 2],
        ["Kyoto", 135.768, 35.011, 3],
        ["Sapporo", 141.354, 43.062, 3],
        ["Seoul", 126.978, 37.566, 1],
        ["Busan", 129.075, 35.179, 2],
        ["Beijing", 116.407, 39.904, 1],
        ["Shanghai", 121.473, 31.230, 1],
        ["Hong Kong", 114.169, 22.319, 1],
        ["Taipei", 121.565, 25.033, 2],
        ["Guangzhou", 113.264, 23.129, 2],
        ["Chengdu", 104.066, 30.572, 2],
        ["Bangkok", 100.501, 13.756, 1],
        ["Chiang Mai", 98.985, 18.788, 3],
        ["Phuket", 98.392, 7.880, 3],
        ["Singapore", 103.820, 1.352, 1],
        ["Kuala Lumpur", 101.686, 3.139, 1],
        ["Jakarta", 106.845, -6.208, 1],
        ["Bali", 115.188, -8.409, 2],
        ["Manila", 120.984, 14.599, 1],
        ["Phnom Penh", 104.928, 11.556, 2],
        ["Vientiane", 102.633, 17.975, 2],
        ["Yangon", 96.195, 16.866, 2],
        ["New Delhi", 77.209, 28.613, 1],
        ["Mumbai", 72.877, 19.076, 1],
        ["Bengaluru", 77.594, 12.971, 2],
        ["Dubai", 55.270, 25.204, 1],
        ["Riyadh", 46.675, 24.713, 2],
        ["Istanbul", 28.978, 41.008, 1],
        ["Cairo", 31.235, 30.044, 1],
        ["London", -0.127, 51.507, 1],
        ["Paris", 2.352, 48.856, 1],
        ["Berlin", 13.405, 52.520, 1],
        ["Madrid", -3.703, 40.416, 1],
        ["Rome", 12.496, 41.902, 1],
        ["Amsterdam", 4.904, 52.367, 2],
        ["Zurich", 8.541, 47.376, 2],
        ["Vienna", 16.373, 48.208, 2],
        ["Prague", 14.437, 50.075, 2],
        ["Stockholm", 18.068, 59.329, 2],
        ["Athens", 23.727, 37.983, 2],
        ["Lisbon", -9.139, 38.722, 2],
        ["Moscow", 37.617, 55.755, 1],
        ["Reykjavik", -21.942, 64.146, 2],
        ["New York", -74.006, 40.712, 1],
        ["Los Angeles", -118.243, 34.052, 1],
        ["San Francisco", -122.419, 37.774, 2],
        ["Chicago", -87.629, 41.878, 2],
        ["Seattle", -122.332, 47.606, 2],
        ["Toronto", -79.383, 43.653, 1],
        ["Vancouver", -123.120, 49.282, 2],
        ["Mexico City", -99.133, 19.432, 1],
        ["Sao Paulo", -46.633, -23.550, 1],
        ["Rio de Janeiro", -43.172, -22.906, 2],
        ["Buenos Aires", -58.381, -34.603, 1],
        ["Lima", -77.042, -12.046, 2],
        ["Bogota", -74.072, 4.711, 2],
        ["Sydney", 151.209, -33.868, 1],
        ["Melbourne", 144.963, -37.813, 2],
        ["Auckland", 174.763, -36.848, 2],
        ["Cape Town", 18.424, -33.924, 1],
        ["Nairobi", 36.821, -1.292, 2],
        ["Lagos", 3.379, 6.524, 2],
        ["Casablanca", -7.589, 33.573, 2]
    ]

    // Exact Web Mercator zoom curve from `globe-vector-map-overlay.js` (reaches street/building zoom 18)
    function mapZoom(z: real): real {
        const base = Math.log2(Math.max(0.15, root.baseScale * z)) + 1.0;
        const deep = Math.max(0.0, Math.log2(Math.max(1.0, z / root.mapFadeStartZoom)));
        return Math.max(0.35, Math.min(18.0, base + deep * 2.18));
    }

    // Precision drag curve matching `globe-vector-map-overlay.js` (`DRAG_CURVE`)
    function dragSensitivity(z: real): real {
        const zz = Math.max(1.0, z);
        if (zz <= root.mapFadeFullZoom)
            return 0.28 / Math.pow(zz, 0.92);
        const refDrag = 0.28 / Math.pow(root.mapFadeFullZoom, 0.92);
        const curve = [
            [root.mapFadeFullZoom, 1.0],
            [4.0, 0.8],
            [8.0, 0.45],
            [16.0, 0.2],
            [32.0, 0.1]
        ];
        let mult = 0.1;
        for (let i = 1; i < curve.length; ++i) {
            const fz = curve[i - 1][0], fm = curve[i - 1][1];
            const tz = curve[i][0], tm = curve[i][1];
            if (zz <= tz) {
                const t = Math.max(0.0, Math.min(1.0, Math.log(zz / fz) / Math.log(tz / fz)));
                const eased = t * t * (3.0 - 2.0 * t);
                mult = fm + (tm - fm) * eased;
                break;
            }
        }
        return refDrag * mult * Math.pow(2.0, root.mapZoom(root.mapFadeFullZoom) - root.mapZoom(zz));
    }

    // Exact Web Mercator (EPSG:3857) helpers shared by offline base, live street tiles, and place pins
    function _mercatorY(latDeg: real): real {
        const clamped = Math.max(-85.0, Math.min(85.0, latDeg));
        const rad = clamped * root.degToRad;
        return Math.log(Math.tan(Math.PI * 0.25 + rad * 0.5));
    }

    function _invMercatorY(my: real): real {
        const lat = (2.0 * Math.atan(Math.exp(my)) - Math.PI * 0.5) / root.degToRad;
        return Math.max(-85.0, Math.min(85.0, lat));
    }

    function _mapPixelsPerRad(w: real, h: real): real {
        const worldPx = 256.0 * Math.pow(2.0, root.effectiveMapZoom);
        return Math.max(36.0, worldPx / (2.0 * Math.PI));
    }

    function projectMapLonLat(lon: real, lat: real, cx: real, cy: real, pxPerRad: real, cLon: real, cMercY: real): var {
        let dLon = lon - cLon;
        while (dLon > 180.0) dLon -= 360.0;
        while (dLon < -180.0) dLon += 360.0;
        const sx = cx + (dLon * root.degToRad) * pxPerRad;
        const sy = cy - (root._mercatorY(lat) - cMercY) * pxPerRad;
        return { sx: sx, sy: sy, visible: true, z: 1.0 };
    }

    function screenToMapLonLat(sx: real, sy: real, w: real, h: real): var {
        const cx = w * 0.5;
        const cy = h * 0.5;
        const pxPerRad = root._mapPixelsPerRad(w, h);
        const cMercY = root._mercatorY(root.centerLat);
        const lon = root.wrapLon(root.centerLon + ((sx - cx) / pxPerRad) / root.degToRad);
        const lat = root._invMercatorY(cMercY - (sy - cy) / pxPerRad);
        return { lon: lon, lat: lat };
    }

    function toggleViewMode(): void {
        if (root.isMapMode) {
            root.viewModePreference = "globe";
            if (root.zoom >= root.mapFadeStartZoom)
                root.zoom = Math.min(root.zoom, 1.35);
        } else {
            root.viewModePreference = "map";
            if (root.zoom < root.mapFadeFullZoom)
                root.zoom = 2.6;
        }
        root.hoveredCluster = null;
        root.pauseUntilMs = Date.now() + 1800;
        root.requestPaint();
    }

    function toggleMapStyle(): void {
        root.mapStyle = (root.mapStyle === "themed") ? "color" : "themed";
        root.requestPaint();
    }

    function adjustZoom(factor: real): void {
        const next = Math.max(root.minZoom, Math.min(root.maxZoom, Number((root.zoom * factor).toFixed(3))));
        if (Math.abs(next - root.zoom) < 0.0005)
            return;
        if (factor > 1.0 && root.viewModePreference === "globe" && next >= root.mapFadeFullZoom)
            root.viewModePreference = "auto";
        else if (factor < 1.0 && root.viewModePreference === "map" && next <= 1.15)
            root.viewModePreference = "auto";
        root.zoom = next;
        root.pauseUntilMs = Date.now() + 1800;
        root.requestPaint();
    }

    function adjustZoomAt(factor: real, sx: real, sy: real): void {
        if (!root.isMapMode || root.width < 20 || root.height < 20) {
            root.adjustZoom(factor);
            return;
        }
        const anchor = root.screenToMapLonLat(sx, sy, root.width, root.height);
        const next = Math.max(root.minZoom, Math.min(root.maxZoom, Number((root.zoom * factor).toFixed(3))));
        if (Math.abs(next - root.zoom) < 0.0005)
            return;
        if (factor < 1.0 && root.viewModePreference === "map" && next <= 1.15)
            root.viewModePreference = "auto";
        root._userMoved = true;
        root.zoom = next;
        if (root.isMapMode) {
            const cx = root.width * 0.5;
            const cy = root.height * 0.5;
            const pxPerRad = root._mapPixelsPerRad(root.width, root.height);
            const anchorMercY = root._mercatorY(anchor.lat);
            root.centerLon = root.wrapLon(anchor.lon - ((sx - cx) / pxPerRad) / root.degToRad);
            root.centerLat = Math.max(-84.0, Math.min(84.0, root._invMercatorY(anchorMercY + (sy - cy) / pxPerRad)));
        }
        root.pauseUntilMs = Date.now() + 1800;
        root.requestPaint();
    }

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
        case 9: return Qt.tint(l2, Qt.rgba(sub.r, sub.g, sub.b, 0.72));
        case 10: return Qt.tint(l2, Qt.rgba(sub.r, sub.g, sub.b, 0.86));
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

    onMapBlendChanged: root.requestPaint()

    function resetGlobe() {
        const c = root.sphericalCenter(root.places);
        root._userMoved = false;
        root.viewModePreference = "auto";
        root.centerLon = c.lon;
        root.centerLat = c.lat;
        root.zoom = root.defaultZoom;
        root.hoveredCluster = null;
        root.hoverGeoLat = NaN;
        root.hoverGeoLon = NaN;
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
        root.centerLat = Math.max(-84.0, Math.min(84.0, Number(cluster.lat)));
        root.zoom = Math.min(root.maxZoom, Math.max(2.6, Number((root.zoom * 2.1).toFixed(3))));
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

    // Reusable typed-array ring clip scratch buffers (eliminates ~50,000 JS object allocations/sec during 25 FPS spin)
    property var _ringClipSx: new Float64Array(512)
    property var _ringClipSy: new Float64Array(512)
    property var _ringClipAng: new Float64Array(512)
    property var _ringClipHor: new Uint8Array(512)

    function _ensureRingScratchCapacity(minCap: int): void {
        if (root._ringClipSx && root._ringClipSx.length >= minCap)
            return;
        const cap = Math.max(512, minCap * 2);
        root._ringClipSx = new Float64Array(cap);
        root._ringClipSy = new Float64Array(cap);
        root._ringClipAng = new Float64Array(cap);
        root._ringClipHor = new Uint8Array(cap);
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
        root._ensureRingScratchCapacity(n * 2 + 4);
        const clipSx = root._ringClipSx;
        const clipSy = root._ringClipSy;
        const clipAng = root._ringClipAng;
        const clipHor = root._ringClipHor;
        let clipLen = 0;

        const lastU = ring[n - 1];
        let prevX = lastU[0] * cosLon0 - lastU[2] * sinLon0;
        const lastRz = lastU[2] * cosLon0 + lastU[0] * sinLon0;
        let prevY = cosLat0 * lastU[1] - sinLat0 * lastRz;
        let prevZ = sinLat0 * lastU[1] + cosLat0 * lastRz;
        let prevVis = prevZ >= 0.0;

        for (let i = 0; i < n; ++i) {
            const u = ring[i];
            const ux = u[0];
            const uy = u[1];
            const uz = u[2];
            const currX = ux * cosLon0 - uz * sinLon0;
            const rz = uz * cosLon0 + ux * sinLon0;
            const currY = cosLat0 * uy - sinLat0 * rz;
            const currZ = sinLat0 * uy + cosLat0 * rz;
            const currVis = currZ >= 0.0;

            if (prevVis && currVis) {
                clipSx[clipLen] = cx + currX * R;
                clipSy[clipLen] = cy - currY * R;
                clipAng[clipLen] = 0.0;
                clipHor[clipLen] = 0;
                clipLen += 1;
            } else if (prevVis && !currVis) {
                const dz = prevZ - currZ;
                const t = Math.abs(dz) < 1e-6 ? 0.5 : (prevZ / dz);
                const ix = prevX + (currX - prevX) * t;
                const iy = prevY + (currY - prevY) * t;
                const len = Math.hypot(ix, iy) || 1.0;
                const nx = ix / len;
                const ny = iy / len;
                clipSx[clipLen] = cx + nx * R;
                clipSy[clipLen] = cy - ny * R;
                clipAng[clipLen] = Math.atan2(-ny, nx);
                clipHor[clipLen] = 1;
                clipLen += 1;
            } else if (!prevVis && currVis) {
                const dz = prevZ - currZ;
                const t = Math.abs(dz) < 1e-6 ? 0.5 : (prevZ / dz);
                const ix = prevX + (currX - prevX) * t;
                const iy = prevY + (currY - prevY) * t;
                const len = Math.hypot(ix, iy) || 1.0;
                const nx = ix / len;
                const ny = iy / len;
                clipSx[clipLen] = cx + nx * R;
                clipSy[clipLen] = cy - ny * R;
                clipAng[clipLen] = Math.atan2(-ny, nx);
                clipHor[clipLen] = 1;
                clipLen += 1;

                clipSx[clipLen] = cx + currX * R;
                clipSy[clipLen] = cy - currY * R;
                clipAng[clipLen] = 0.0;
                clipHor[clipLen] = 0;
                clipLen += 1;
            }
            prevX = currX;
            prevY = currY;
            prevZ = currZ;
            prevVis = currVis;
        }
        if (clipLen < 3)
            return false;

        ctx.moveTo(clipSx[0], clipSy[0]);
        for (let i = 1; i <= clipLen; ++i) {
            const prevIdx = i - 1;
            const currIdx = i === clipLen ? 0 : i;
            if (clipHor[prevIdx] === 1 && clipHor[currIdx] === 1) {
                const pPrevAng = clipAng[prevIdx];
                let dAng = clipAng[currIdx] - pPrevAng;
                while (dAng > Math.PI) dAng -= Math.PI * 2.0;
                while (dAng < -Math.PI) dAng += Math.PI * 2.0;
                const steps = Math.max(4, Math.ceil(Math.abs(dAng) / 0.14));
                for (let s = 1; s <= steps; ++s) {
                    const ang = pPrevAng + (dAng * s) / steps;
                    ctx.lineTo(cx + Math.cos(ang) * R, cy + Math.sin(ang) * R);
                }
            } else {
                ctx.lineTo(clipSx[currIdx], clipSy[currIdx]);
            }
        }
        ctx.closePath();
        return true;
    }

    // Clip precompiled polyline to z >= 0 front hemisphere with fast bounding-sphere culling (zero object allocations)
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
        const u0 = line[0];
        let prevX = u0[0] * cosLon0 - u0[2] * sinLon0;
        const rz0 = u0[2] * cosLon0 + u0[0] * sinLon0;
        let prevY = cosLat0 * u0[1] - sinLat0 * rz0;
        let prevZ = sinLat0 * u0[1] + cosLat0 * rz0;
        let prevVis = prevZ >= 0.0;
        let prevSx = cx + prevX * R;
        let prevSy = cy - prevY * R;
        let inSeg = false;
        if (prevVis) {
            ctx.moveTo(prevSx, prevSy);
            inSeg = true;
        }
        for (let i = 1; i < total; ++i) {
            const pt = line[i === n ? 0 : i];
            const ux = pt[0];
            const uy = pt[1];
            const uz = pt[2];
            const currX = ux * cosLon0 - uz * sinLon0;
            const rz = uz * cosLon0 + ux * sinLon0;
            const currY = cosLat0 * uy - sinLat0 * rz;
            const currZ = sinLat0 * uy + cosLat0 * rz;
            const currVis = currZ >= 0.0;
            const currSx = cx + currX * R;
            const currSy = cy - currY * R;
            if (prevVis && currVis) {
                if (!inSeg) {
                    ctx.moveTo(prevSx, prevSy);
                    inSeg = true;
                }
                ctx.lineTo(currSx, currSy);
            } else if (prevVis && !currVis) {
                const dz = prevZ - currZ;
                const t = Math.abs(dz) < 1e-6 ? 0.5 : (prevZ / dz);
                const ix = prevX + (currX - prevX) * t;
                const iy = prevY + (currY - prevY) * t;
                const len = Math.hypot(ix, iy) || 1.0;
                if (!inSeg)
                    ctx.moveTo(prevSx, prevSy);
                ctx.lineTo(cx + (ix / len) * R, cy - (iy / len) * R);
                inSeg = false;
            } else if (!prevVis && currVis) {
                const dz = prevZ - currZ;
                const t = Math.abs(dz) < 1e-6 ? 0.5 : (prevZ / dz);
                const ix = prevX + (currX - prevX) * t;
                const iy = prevY + (currY - prevY) * t;
                const len = Math.hypot(ix, iy) || 1.0;
                ctx.moveTo(cx + (ix / len) * R, cy - (iy / len) * R);
                ctx.lineTo(currSx, currSy);
                inSeg = true;
            }
            prevX = currX;
            prevY = currY;
            prevZ = currZ;
            prevVis = currVis;
            prevSx = currSx;
            prevSy = currSy;
        }
    }

    // Auto-rotation timer (~25 FPS smooth spin when autoRotate === true in Globe mode, transition settled, and not taking screenshot)
    Timer {
        id: spinTimer
        objectName: "nexusGlobeSpinTimer"
        interval: 40
        repeat: true
        running: root.visible && root.active && root.autoRotate && !root.isMapMode && !globeMouse.pressed && Boolean(root.nexus ? root.nexus.isOpen : true) && root.hostSettled && Boolean(root.workspace ? root.workspace.surfaceActive : true) && !Boolean(GlobalStates.screenLocked) && !Boolean(GlobalStates.regionSelectorOpen) && !Boolean(GlobalStates.annotationEditorOpen) && (root.Window.window?.visible ?? true)
        onTriggered: {
            const now = Date.now();
            if (now < root.pauseUntilMs)
                return;
            const speedFactor = 1.0 / Math.pow(Math.max(1.0, root.zoom), 0.72);
            root.centerLon = root.wrapLon(root.centerLon + 40.0 * 0.0019 * 4.5 * speedFactor);
            root.requestPaint();
        }
    }

    // Draw closed polygon rings or open polylines in flat Mercator Map mode with antimeridian continuity
    function _traceMapSeq(ctx, seq, cx: real, cy: real, pxPerRad: real, cLon: real, cMercY: real, w: real, h: real, closeRing: bool, lonOffset: real): bool {
        if (!Array.isArray(seq) || seq.length < 2)
            return false;
        const margin = 48.0;
        let anyInBounds = false;
        let prevLon = null;
        let started = false;
        const ptsX = [];
        const ptsY = [];
        const breaks = [];
        for (let i = 0; i < seq.length; ++i) {
            const pt = seq[i];
            const rawLon = Number(pt[0]);
            const lat = Number(pt[1]);
            if (!Number.isFinite(rawLon) || !Number.isFinite(lat))
                continue;
            let adjLon = rawLon;
            let jump = false;
            if (prevLon !== null) {
                if (closeRing) {
                    // Continuously unwrap closed rings across +/-180 so closePath never streaks across the map
                    while (adjLon - prevLon > 180.0) adjLon -= 360.0;
                    while (adjLon - prevLon < -180.0) adjLon += 360.0;
                } else {
                    jump = Math.abs(rawLon - prevLon) > 180.0;
                }
            }
            const dLon = (adjLon + lonOffset) - cLon;
            const sx = cx + (dLon * root.degToRad) * pxPerRad;
            const sy = cy - (root._mercatorY(lat) - cMercY) * pxPerRad;
            if (sx >= -margin && sx <= w + margin && sy >= -margin && sy <= h + margin)
                anyInBounds = true;
            ptsX.push(sx);
            ptsY.push(sy);
            breaks.push(!started || jump);
            started = true;
            prevLon = adjLon;
        }
        if (!anyInBounds || ptsX.length < 2)
            return false;
        for (let i = 0; i < ptsX.length; ++i) {
            if (breaks[i])
                ctx.moveTo(ptsX[i], ptsY[i]);
            else
                ctx.lineTo(ptsX[i], ptsY[i]);
        }
        if (closeRing)
            ctx.closePath();
        return true;
    }

    function _drawCitiesAndLabels(ctx, w: real, h: real, mapMode: bool, cx: real, cy: real, R: real, pxPerRad: real, cLon: real, cLat: real, cMercY: real, p10: color, p12: color, p00: color, acc: color): void {
        if (!mapMode && root.zoom < 1.75)
            return;
        const maxRank = mapMode
            ? (root.zoom >= 6.0 ? 3 : (root.zoom >= 3.2 ? 2 : 1))
            : (root.zoom >= 4.2 ? 3 : (root.zoom >= 2.4 ? 2 : 1));
        const showLabels = mapMode || root.zoom >= 2.1;
        const occupied = [];
        const cities = root.worldCities;
        ctx.save();
        ctx.font = (root.zoom >= 6.5 ? "600 9px monospace" : "600 8px monospace");
        ctx.textBaseline = "middle";
        for (let i = 0; i < cities.length; ++i) {
            const c = cities[i];
            if (c[3] > maxRank)
                continue;
            const name = c[0];
            const lon = c[1];
            const lat = c[2];
            let sx = 0, sy = 0, visAlpha = 0.86;
            if (mapMode) {
                const pm = root.projectMapLonLat(lon, lat, cx, cy, pxPerRad, cLon, cMercY);
                sx = pm.sx;
                sy = pm.sy;
                if (sx < -16 || sx > w + 16 || sy < -16 || sy > h + 16)
                    continue;
            } else {
                const pg = root.projectLonLat(lon, lat, cx, cy, R, cLon, cLat);
                if (!pg.visible || pg.z < 0.12)
                    continue;
                sx = pg.sx;
                sy = pg.sy;
                if (sx < -16 || sx > w + 16 || sy < -16 || sy > h + 16)
                    continue;
                visAlpha = 0.42 + Math.min(1.0, pg.z) * 0.44;
            }
            // City marker dot (ringed for rank 1 capitals/megacities)
            ctx.fillStyle = Qt.rgba(p10.r, p10.g, p10.b, visAlpha);
            ctx.beginPath();
            ctx.arc(sx, sy, c[3] === 1 ? 1.85 : 1.25, 0, Math.PI * 2);
            ctx.fill();
            if (c[3] === 1 && mapMode) {
                ctx.strokeStyle = Qt.rgba(acc.r, acc.g, acc.b, 0.48);
                ctx.lineWidth = 0.8;
                ctx.beginPath();
                ctx.arc(sx, sy, 3.2, 0, Math.PI * 2);
                ctx.stroke();
            }
            if (!showLabels)
                continue;
            const labelW = name.length * (root.zoom >= 6.5 ? 5.6 : 5.0) + 6;
            const lx = sx + 5.5;
            const ly = sy;
            if (lx + labelW > w - 6 || ly < 16 || ly > h - 22)
                continue;
            const bx1 = lx - 2, by1 = ly - 6, bx2 = lx + labelW, by2 = ly + 6;
            let collides = false;
            for (let k = 0; k < occupied.length; ++k) {
                const o = occupied[k];
                if (!(bx2 < o[0] || bx1 > o[2] || by2 < o[1] || by1 > o[3])) {
                    collides = true;
                    break;
                }
            }
            if (collides)
                continue;
            occupied.push([bx1, by1, bx2, by2]);
            ctx.fillStyle = Qt.rgba(p00.r, p00.g, p00.b, 0.72);
            ctx.fillText(name, lx + 0.8, ly + 0.8);
            ctx.fillStyle = Qt.rgba(p12.r, p12.g, p12.b, mapMode ? 0.84 : visAlpha * 0.85);
            ctx.fillText(name, lx, ly);
        }
        ctx.restore();
    }

    function _paintDetailedMap(ctx, w: real, h: real, p00: color, p01: color, p02: color, p03: color, p04: color, p07: color, p08: color, p09: color, p10: color, p11: color, p12: color, acc: color): void {
        const cx = w * 0.5;
        const cy = h * 0.5;
        const pxPerRad = root._mapPixelsPerRad(w, h);
        const cLon = root.centerLon;
        const cLat = Math.max(-84.0, Math.min(84.0, root.centerLat));
        const cMercY = root._mercatorY(cLat);

        // 1. Ocean Bathymetry Canvas Fill
        const oceanGrad = ctx.createRadialGradient(cx, cy, Math.min(w, h) * 0.08, cx, cy, Math.max(w, h) * 0.75);
        oceanGrad.addColorStop(0.0, Qt.rgba(p02.r, p02.g, p02.b, 0.98));
        oceanGrad.addColorStop(0.68, Qt.rgba(p01.r, p01.g, p01.b, 0.99));
        oceanGrad.addColorStop(1.0, Qt.rgba(p00.r, p00.g, p00.b, 1.0));
        ctx.fillStyle = oceanGrad;
        ctx.fillRect(0, 0, w, h);

        // 2. Adaptive Cartographic Lat/Lon Graticule Grid (refines automatically with zoom)
        const degSpan = (w / pxPerRad) / root.degToRad;
        const gridStep = degSpan > 110 ? 20 : (degSpan > 48 ? 10 : (degSpan > 22 ? 5 : (degSpan > 9 ? 2 : 1)));
        ctx.save();
        ctx.strokeStyle = Qt.rgba(p04.r, p04.g, p04.b, 0.36);
        ctx.lineWidth = 0.6;
        ctx.beginPath();
        const lonStart = Math.floor((cLon - degSpan * 0.65) / gridStep) * gridStep;
        const lonEnd = Math.ceil((cLon + degSpan * 0.65) / gridStep) * gridStep;
        for (let lon = lonStart; lon <= lonEnd; lon += gridStep) {
            const sx = cx + ((lon - cLon) * root.degToRad) * pxPerRad;
            if (sx < -2 || sx > w + 2)
                continue;
            ctx.moveTo(sx, 0);
            ctx.lineTo(sx, h);
        }
        const minLat = Math.max(-80, Math.floor((cLat - degSpan * 0.6) / gridStep) * gridStep);
        const maxLat = Math.min(80, Math.ceil((cLat + degSpan * 0.6) / gridStep) * gridStep);
        for (let lat = minLat; lat <= maxLat; lat += gridStep) {
            const sy = cy - (root._mercatorY(lat) - cMercY) * pxPerRad;
            if (sy < -2 || sy > h + 2)
                continue;
            ctx.moveTo(0, sy);
            ctx.lineTo(w, sy);
        }
        ctx.stroke();

        // Subtle graticule degree labels along left & top edges
        ctx.font = "500 7.5px monospace";
        ctx.fillStyle = Qt.rgba(p09.r, p09.g, p09.b, 0.56);
        ctx.textBaseline = "middle";
        for (let lat = minLat; lat <= maxLat; lat += gridStep) {
            const sy = cy - (root._mercatorY(lat) - cMercY) * pxPerRad;
            if (sy < 26 || sy > h - 26)
                continue;
            const ns = lat === 0 ? "0°" : (Math.abs(lat) + "°" + (lat > 0 ? "N" : "S"));
            ctx.fillText(ns, 6, sy - 6);
        }
        for (let lon = lonStart; lon <= lonEnd; lon += gridStep) {
            const sx = cx + ((lon - cLon) * root.degToRad) * pxPerRad;
            if (sx < 168 || sx > w - 42)
                continue;
            const wl = root.wrapLon(lon);
            const ew = wl === 0 ? "0°" : (Math.abs(Math.round(wl)) + "°" + (wl > 0 ? "E" : "W"));
            ctx.fillText(ew, sx + 3, 12);
        }
        ctx.restore();

        // Determine longitude wrap offsets needed for seamless pan across +/-180
        const offsets = [0];
        if (cLon + degSpan * 0.65 > 180)
            offsets.push(360);
        if (cLon - degSpan * 0.65 < -180)
            offsets.push(-360);

        // 3. Land Polygons + Subtle Elevation Lift + Coastline
        const lPolys = root.landData;
        ctx.beginPath();
        for (let oi = 0; oi < offsets.length; ++oi) {
            const off = offsets[oi];
            for (let m = 0; m < lPolys.length; ++m) {
                const poly = lPolys[m];
                if (!Array.isArray(poly))
                    continue;
                for (let r = 0; r < poly.length; ++r)
                    root._traceMapSeq(ctx, poly[r], cx, cy, pxPerRad, cLon, cMercY, w, h, true, off);
            }
        }
        ctx.fillStyle = Qt.rgba(p03.r, p03.g, p03.b, 0.96);
        ctx.fill();
        ctx.fillStyle = Qt.rgba(p04.r, p04.g, p04.b, 0.24);
        ctx.fill();
        ctx.strokeStyle = Qt.rgba(p09.r, p09.g, p09.b, 0.78);
        ctx.lineWidth = Math.min(1.6, 0.85 + Math.log2(Math.max(1.5, root.zoom)) * 0.16);
        ctx.stroke();

        // 4. Lakes
        const lkPolys = root.lakesData;
        if (lkPolys.length > 0) {
            ctx.beginPath();
            for (let oi = 0; oi < offsets.length; ++oi) {
                const off = offsets[oi];
                for (let m = 0; m < lkPolys.length; ++m) {
                    const poly = lkPolys[m];
                    if (!Array.isArray(poly))
                        continue;
                    for (let r = 0; r < poly.length; ++r)
                        root._traceMapSeq(ctx, poly[r], cx, cy, pxPerRad, cLon, cMercY, w, h, true, off);
                }
            }
            ctx.fillStyle = Qt.rgba(p02.r, p02.g, p02.b, 0.90);
            ctx.fill();
            ctx.strokeStyle = Qt.rgba(p08.r, p08.g, p08.b, 0.54);
            ctx.lineWidth = 0.7;
            ctx.stroke();
        }

        // 5. Rivers
        const rvLines = root.riversData;
        if (rvLines.length > 0) {
            ctx.beginPath();
            for (let oi = 0; oi < offsets.length; ++oi) {
                const off = offsets[oi];
                for (let i = 0; i < rvLines.length; ++i)
                    root._traceMapSeq(ctx, rvLines[i], cx, cy, pxPerRad, cLon, cMercY, w, h, false, off);
            }
            ctx.strokeStyle = Qt.rgba(p08.r, p08.g, p08.b, 0.64);
            ctx.lineWidth = Math.min(1.35, 0.72 + Math.log2(Math.max(2.0, root.zoom)) * 0.12);
            ctx.stroke();
        }

        // 6. Country Borders (crisp dashed cartographic boundary)
        const bdLines = root.bordersData;
        if (bdLines.length > 0) {
            ctx.save();
            ctx.beginPath();
            for (let oi = 0; oi < offsets.length; ++oi) {
                const off = offsets[oi];
                for (let i = 0; i < bdLines.length; ++i)
                    root._traceMapSeq(ctx, bdLines[i], cx, cy, pxPerRad, cLon, cMercY, w, h, false, off);
            }
            ctx.strokeStyle = Qt.rgba(p07.r, p07.g, p07.b, 0.62);
            ctx.lineWidth = 0.82;
            if (typeof ctx.setLineDash === "function")
                ctx.setLineDash([4.0, 2.5]);
            ctx.stroke();
            ctx.restore();
        }

        // 7. Progressive Offline World Cities & Labels (shown when offline / before live street tiles load)
        if (!tileLayerHost.hasReadyTile)
            root._drawCitiesAndLabels(ctx, w, h, true, cx, cy, 0, pxPerRad, cLon, cLat, cMercY, p10, p12, p00, acc);
    }

    // Separate top overlay painter for Map place pins, nearest-neighbor links, clusters & metric scale bar
    // (always rendered crisply above live high-detail street tiles, unaffected by tile theming shader).
    function _paintMapOverlayPins(ctx, w: real, h: real, p00: color, p07: color, p09: color, p10: color, p11: color, p12: color, acc: color): void {
        const cx = w * 0.5;
        const cy = h * 0.5;
        const pxPerRad = root._mapPixelsPerRad(w, h);
        const cLon = root.centerLon;
        const cLat = Math.max(-84.0, Math.min(84.0, root.centerLat));
        const cMercY = root._mercatorY(cLat);

        // 1. Place Markers & Nearest-Neighbor Connections (matches `globe-vector-map-overlay.js`)
        const rawMarkers = [];
        const plist = root.places ?? [];
        for (let i = 0; i < plist.length; ++i) {
            const pl = plist[i];
            const lat = Number(pl.lat);
            const lon = Number(pl.lon);
            if (!Number.isFinite(lat) || !Number.isFinite(lon) || (!pl.hasCoordinates && lat === 0 && lon === 0))
                continue;
            const pm = root.projectMapLonLat(lon, lat, cx, cy, pxPerRad, cLon, cMercY);
            if (pm.sx < -28 || pm.sx > w + 28 || pm.sy < -28 || pm.sy > h + 28)
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
                x: pm.sx,
                y: pm.sy,
                z: 1.0
            });
        }

        // Uncluster cleanly at street-level zoom (>= 13, matching `clusterMaxZoom: 13`)
        const mz = root.effectiveMapZoom;
        const clusterDist = mz >= 13.0 ? 0.0 : (mz >= 9.0 ? 12.0 : (mz >= 5.0 ? 18.0 : 24.0));
        const clusters = [];
        for (let i = 0; i < rawMarkers.length; ++i) {
            const m = rawMarkers[i];
            let merged = false;
            if (clusterDist > 0.0) {
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
            }
            if (!merged) {
                clusters.push({
                    x: m.x,
                    y: m.y,
                    z: 1.0,
                    lat: m.lat,
                    lon: m.lon,
                    visited: m.visited,
                    wantToVisit: m.wantToVisit,
                    primary: m,
                    items: [m]
                });
            }
        }
        if (root.isMapMode)
            root.visibleClusters = clusters;

        // Subtle nearest-neighbor place links (`cdata` style) when >= 2 clusters visible
        if (clusters.length >= 2 && clusters.length <= 64) {
            ctx.save();
            ctx.strokeStyle = Qt.rgba(p07.r, p07.g, p07.b, 0.34);
            ctx.lineWidth = 0.85;
            ctx.beginPath();
            for (let i = 0; i < clusters.length; ++i) {
                let bestJ = -1;
                let bestD = 220.0;
                for (let j = 0; j < clusters.length; ++j) {
                    if (i === j) continue;
                    const d = Math.hypot(clusters[i].x - clusters[j].x, clusters[i].y - clusters[j].y);
                    if (d < bestD) {
                        bestD = d;
                        bestJ = j;
                    }
                }
                if (bestJ > i) {
                    ctx.moveTo(clusters[i].x, clusters[i].y);
                    ctx.lineTo(clusters[bestJ].x, clusters[bestJ].y);
                }
            }
            ctx.stroke();
            ctx.restore();
        }

        for (let i = 0; i < clusters.length; ++i) {
            const cl = clusters[i];
            const isHov = (root.hoveredCluster === cl);
            const count = cl.items.length;
            const planned = !cl.visited && cl.wantToVisit;
            const visited = cl.visited;
            const pinCol = visited ? acc : (planned ? p11 : p09);
            const r = isHov ? 5.6 : (count > 1 ? (count >= 10 ? 8.5 : (count >= 4 ? 7.0 : 5.5)) : 4.0);

            ctx.save();
            // Soft radar halo
            ctx.beginPath();
            ctx.arc(cl.x, cl.y, r + (isHov ? 5.5 : 3.2), 0, Math.PI * 2);
            ctx.fillStyle = Qt.rgba(pinCol.r, pinCol.g, pinCol.b, isHov ? 0.30 : 0.18);
            ctx.fill();

            if (count > 1) {
                // Cluster badge matching `hd-clusters` / `hd-cluster-count` in `globe-vector-map-overlay.js`
                ctx.beginPath();
                ctx.arc(cl.x, cl.y, r, 0, Math.PI * 2);
                ctx.fillStyle = Qt.rgba(p00.r, p00.g, p00.b, 0.90);
                ctx.fill();
                ctx.strokeStyle = Qt.rgba(acc.r, acc.g, acc.b, 0.96);
                ctx.lineWidth = isHov ? 1.8 : 1.3;
                ctx.stroke();

                ctx.font = "700 8.5px monospace";
                ctx.textAlign = "center";
                ctx.textBaseline = "middle";
                ctx.fillStyle = Qt.rgba(p12.r, p12.g, p12.b, 0.96);
                ctx.fillText(String(count), cl.x, cl.y + 0.4);
            } else {
                // Individual place pin (solid for visited/saved, dashed ring for planned)
                ctx.beginPath();
                ctx.arc(cl.x, cl.y, r, 0, Math.PI * 2);
                if (planned) {
                    ctx.fillStyle = Qt.rgba(p00.r, p00.g, p00.b, 0.88);
                    ctx.fill();
                    ctx.strokeStyle = Qt.rgba(pinCol.r, pinCol.g, pinCol.b, 0.98);
                    ctx.lineWidth = isHov ? 1.8 : 1.4;
                    if (typeof ctx.setLineDash === "function")
                        ctx.setLineDash([2.4, 1.8]);
                    ctx.stroke();
                } else {
                    ctx.fillStyle = Qt.rgba(pinCol.r, pinCol.g, pinCol.b, 0.98);
                    ctx.fill();
                    ctx.strokeStyle = Qt.rgba(p00.r, p00.g, p00.b, 0.90);
                    ctx.lineWidth = 1.3;
                    ctx.stroke();
                }
                if (typeof ctx.setLineDash === "function")
                    ctx.setLineDash([]);

                // Readable street-level place callout with crisp halo
                if (mz >= 6.5 || isHov) {
                    const lbl = String(cl.primary?.title ?? "");
                    if (lbl.length > 0) {
                        ctx.font = "600 8.5px monospace";
                        ctx.textAlign = "left";
                        ctx.textBaseline = "middle";
                        ctx.fillStyle = Qt.rgba(p00.r, p00.g, p00.b, 0.88);
                        ctx.fillText(lbl, cl.x + r + 5.8, cl.y + 0.8);
                        ctx.fillText(lbl, cl.x + r + 4.4, cl.y - 0.5);
                        ctx.fillStyle = Qt.rgba(pinCol.r, pinCol.g, pinCol.b, 0.98);
                        ctx.fillText(lbl, cl.x + r + 5.0, cl.y);
                    }
                }
            }
            ctx.restore();
        }

        // 2. Dynamic Metric Scale Bar (supports meters at street zoom AND kilometers at regional zoom)
        const mPerRad = 6371000.0 * Math.max(0.12, Math.cos(cLat * root.degToRad));
        const mPerPx = mPerRad / pxPerRad;
        const targetM = mPerPx * 64.0;
        const niceMeters = [10, 20, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000, 50000, 100000, 200000, 500000, 1000000, 2000000, 5000000];
        let barM = niceMeters[niceMeters.length - 1];
        for (let i = 0; i < niceMeters.length; ++i) {
            if (niceMeters[i] >= targetM * 0.65) {
                barM = niceMeters[i];
                break;
            }
        }
        const barPx = Math.max(24, Math.min(110, barM / Math.max(0.01, mPerPx)));
        const sbX = 12;
        const sbY = h - 25;
        const scaleLabel = barM >= 1000 ? (String(Math.round(barM / 1000)) + " km") : (String(barM) + " m");
        ctx.save();
        ctx.strokeStyle = Qt.rgba(p00.r, p00.g, p00.b, 0.72);
        ctx.lineWidth = 2.6;
        ctx.beginPath();
        ctx.moveTo(sbX, sbY - 3);
        ctx.lineTo(sbX, sbY);
        ctx.lineTo(sbX + barPx, sbY);
        ctx.lineTo(sbX + barPx, sbY - 3);
        ctx.stroke();
        ctx.strokeStyle = Qt.rgba(p11.r, p11.g, p11.b, 0.88);
        ctx.lineWidth = 1.2;
        ctx.stroke();
        ctx.font = "600 7.5px monospace";
        ctx.textAlign = "left";
        ctx.textBaseline = "bottom";
        ctx.fillStyle = Qt.rgba(p00.r, p00.g, p00.b, 0.82);
        ctx.fillText(scaleLabel, sbX + barPx + 5.8, sbY + 1.8);
        ctx.fillStyle = Qt.rgba(p12.r, p12.g, p12.b, 0.90);
        ctx.fillText(scaleLabel, sbX + barPx + 5.0, sbY + 1.0);
        ctx.restore();
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
                if (root.mapBlend > 0.005) {
                    offlineMapCanvas.requestPaint();
                    mapPinsCanvas.requestPaint();
                }
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
        if (root.mapBlend > 0.005) {
            offlineMapCanvas.requestPaint();
            mapPinsCanvas.requestPaint();
        }
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
        z: 1
        opacity: Math.max(0.0, 1.0 - root.mapBlend)
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

            // Fully zoomed into Detailed Map mode: skip redundant 3D sphere rasterization.
            if (root.mapBlend >= 0.995)
                return;

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

            // 9B. Progressive World Cities & Collision-Avoided Labels on Zoomed 3D Globe
            root._drawCitiesAndLabels(ctx, w, h, false, cx, cy, R, 0, cLon, cLat, 0, p10, p12, p00, acc);

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
            if (!root.isMapMode)
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

    // ─── Detailed Interactive Map Layer (Smooth Globe -> Street Map Cross-Fade) ───
    // Adapts & improves `90_System/92_Scripts/Dataview/homepage/globe-vector-map-overlay.js`:
    //   1) Instant offline Web Mercator vector base (`offlineMapCanvas`) aligned sub-pixel to EPSG:3857
    //   2) Live high-detail street/road/building/park/label slippy tiles (`tileLayerHost`, CartoDB @2x)
    //      auto-themed live on the GPU to Alis `ccStop(0..13)` + `accent` via `NexusMapTheme.frag.qsb`
    //      (plus instant toggle to full-color Voyager street map, with graceful offline & software fallback)
    //   3) Top crisp place pins, clusters, nearest-neighbor links & m/km scale bar (`mapPinsCanvas`)
    Item {
        id: detailedMapLayer
        objectName: "nexusGlobeDetailedMapLayer"
        anchors.fill: parent
        z: 2
        clip: true
        visible: root.mapBlend > 0.005
        opacity: root.mapBlend

        Canvas {
            id: offlineMapCanvas
            anchors.fill: parent
            z: 1
            antialiasing: true
            onWidthChanged: if (detailedMapLayer.visible) requestPaint()
            onHeightChanged: if (detailedMapLayer.visible) requestPaint()
            onVisibleChanged: if (visible) requestPaint()
            onPaint: {
                if (!root.canRepaintTheme || !detailedMapLayer.visible || width < 20 || height < 20)
                    return;
                const ctx = getContext("2d");
                if (!ctx)
                    return;
                ctx.clearRect(0, 0, width, height);
                root._paintDetailedMap(
                    ctx, width, height,
                    root.ccStop(0), root.ccStop(1), root.ccStop(2), root.ccStop(3), root.ccStop(4),
                    root.ccStop(7), root.ccStop(8), root.ccStop(9), root.ccStop(10), root.ccStop(11), root.ccStop(12),
                    root.accentCol
                );
            }
        }

        Item {
            id: tileLayerHost
            objectName: "nexusGlobeMapTileLayer"
            anchors.fill: parent
            z: 2
            clip: true

            readonly property bool tilesActive: root.onlineTilesEnabled && root.mapBlend > 0.01 && root.canRepaintTheme && width >= 20 && height >= 20
            readonly property int tileZ: Math.max(1, Math.min(18, Math.floor(root.effectiveMapZoom + 0.35)))
            readonly property int underlayZ: tileZ >= 3 ? Math.max(1, tileZ - 2) : 0
            readonly property real tilePx: 256.0 * Math.pow(2.0, root.effectiveMapZoom - tileZ)
            readonly property real underlayTilePx: underlayZ > 0 ? 256.0 * Math.pow(2.0, root.effectiveMapZoom - underlayZ) : 256.0
            readonly property real halfW: width * 0.5
            readonly property real halfH: height * 0.5

            function _lonToTileX(lon: real, z: int): real {
                return ((lon + 180.0) / 360.0) * Math.pow(2.0, z);
            }
            function _latToTileY(lat: real, z: int): real {
                const clamped = Math.max(-85.0511, Math.min(85.0511, lat));
                const rad = clamped * root.degToRad;
                return (1.0 - Math.log(Math.tan(rad) + 1.0 / Math.cos(rad)) / Math.PI) * 0.5 * Math.pow(2.0, z);
            }
            function tileUrl(z: int, wx: int, ty: int): string {
                const subs = ["a", "b", "c", "d"];
                const sub = subs[(wx + ty) & 3];
                if (root.mapStyle === "color")
                    return "https://" + sub + ".basemaps.cartocdn.com/rastertiles/voyager/" + z + "/" + wx + "/" + ty + "@2x.png";
                return "https://" + sub + ".basemaps.cartocdn.com/dark_all/" + z + "/" + wx + "/" + ty + "@2x.png";
            }

            readonly property real centerTileX: _lonToTileX(root.centerLon, tileZ)
            readonly property real centerTileY: _latToTileY(root.centerLat, tileZ)
            readonly property real underlayCenterX: underlayZ > 0 ? _lonToTileX(root.centerLon, underlayZ) : 0
            readonly property real underlayCenterY: underlayZ > 0 ? _latToTileY(root.centerLat, underlayZ) : 0

            readonly property int txMin: tilesActive ? Math.floor(centerTileX - (halfW + 16) / Math.max(16, tilePx)) : 0
            readonly property int txMax: tilesActive ? Math.floor(centerTileX + (halfW + 16) / Math.max(16, tilePx)) : -1
            readonly property int tyMin: tilesActive ? Math.max(0, Math.floor(centerTileY - (halfH + 16) / Math.max(16, tilePx))) : 0
            readonly property int tyMax: tilesActive ? Math.min(Math.pow(2, tileZ) - 1, Math.floor(centerTileY + (halfH + 16) / Math.max(16, tilePx))) : -1

            readonly property int uxMin: (tilesActive && underlayZ > 0) ? Math.floor(underlayCenterX - (halfW + 16) / Math.max(16, underlayTilePx)) : 0
            readonly property int uxMax: (tilesActive && underlayZ > 0) ? Math.floor(underlayCenterX + (halfW + 16) / Math.max(16, underlayTilePx)) : -1
            readonly property int uyMin: (tilesActive && underlayZ > 0) ? Math.max(0, Math.floor(underlayCenterY - (halfH + 16) / Math.max(16, underlayTilePx))) : 0
            readonly property int uyMax: (tilesActive && underlayZ > 0) ? Math.min(Math.pow(2, underlayZ) - 1, Math.floor(underlayCenterY + (halfH + 16) / Math.max(16, underlayTilePx))) : -1

            readonly property var primaryTiles: {
                if (!tilesActive || txMax < txMin || tyMax < tyMin)
                    return [];
                const n = Math.pow(2, tileZ);
                const list = [];
                for (let ty = tyMin; ty <= tyMax; ++ty) {
                    for (let tx = txMin; tx <= txMax; ++tx) {
                        const wx = ((tx % n) + n) % n;
                        const u = tileUrl(tileZ, wx, ty);
                        list.push({
                            tileKey: tileZ + "/" + tx + "/" + ty + "/" + root.mapStyle,
                            tx: tx,
                            ty: ty,
                            wx: wx,
                            z: tileZ,
                            url: u
                        });
                        if (list.length >= 84)
                            return list;
                    }
                }
                return list;
            }

            readonly property var underlayTiles: {
                if (!tilesActive || underlayZ <= 0 || uxMax < uxMin || uyMax < uyMin)
                    return [];
                const n = Math.pow(2, underlayZ);
                const list = [];
                for (let ty = uyMin; ty <= uyMax; ++ty) {
                    for (let tx = uxMin; tx <= uxMax; ++tx) {
                        const wx = ((tx % n) + n) % n;
                        const u = tileUrl(underlayZ, wx, ty);
                        list.push({
                            tileKey: underlayZ + "/" + tx + "/" + ty + "/" + root.mapStyle,
                            tx: tx,
                            ty: ty,
                            wx: wx,
                            z: underlayZ,
                            url: u
                        });
                        if (list.length >= 24)
                            return list;
                    }
                }
                return list;
            }

            // Key-diffed ListModels keep surviving tile Image delegates alive across
            // pan/tile-boundary transitions (zero reload flicker or ready-count drop).
            ListModel { id: primaryTileModel }
            ListModel { id: underlayTileModel }

            function _syncTileModel(model, descriptors): void {
                if (!descriptors || descriptors.length === 0) {
                    if (model.count > 0)
                        model.clear();
                    return;
                }
                const desired = {};
                for (let i = 0; i < descriptors.length; ++i)
                    desired[descriptors[i].tileKey] = true;
                const existing = {};
                for (let i = model.count - 1; i >= 0; --i) {
                    const k = model.get(i).tileKey;
                    if (!desired[k])
                        model.remove(i);
                    else
                        existing[k] = true;
                }
                for (let i = 0; i < descriptors.length; ++i) {
                    const d = descriptors[i];
                    if (!existing[d.tileKey])
                        model.append(d);
                }
            }

            onPrimaryTilesChanged: _syncTileModel(primaryTileModel, primaryTiles)
            onUnderlayTilesChanged: _syncTileModel(underlayTileModel, underlayTiles)
            Component.onCompleted: {
                _syncTileModel(primaryTileModel, primaryTiles);
                _syncTileModel(underlayTileModel, underlayTiles);
            }

            property int readyTileCount: 0
            property int readyUnderlayCount: 0
            readonly property bool hasReadyTile: (readyTileCount + readyUnderlayCount) > 0
            onTilesActiveChanged: {
                if (!tilesActive) {
                    readyTileCount = 0;
                    readyUnderlayCount = 0;
                }
            }
            onHasReadyTileChanged: {
                if (detailedMapLayer.visible)
                    offlineMapCanvas.requestPaint();
            }

            readonly property bool mapShaderSupported: GraphicsInfo.api !== GraphicsInfo.Software && GraphicsInfo.api !== GraphicsInfo.Null
            layer.enabled: mapShaderSupported && root.mapStyle === "themed" && hasReadyTile
            layer.effect: ShaderEffect {
                fragmentShader: Qt.resolvedUrl("NexusMapTheme.frag.qsb")
                readonly property color colWater: root.ccStop(1)
                readonly property color colLand: root.ccStop(3)
                readonly property color colUrban: root.ccStop(5)
                readonly property color colRoad: root.ccStop(7)
                readonly property color colMajor: Qt.tint(root.ccStop(9), Qt.rgba(root.accentCol.r, root.accentCol.g, root.accentCol.b, 0.24))
                readonly property color colLabel: root.ccStop(13)
                readonly property vector4d params: Qt.vector4d(1.0, 0.0, 0.0, 0.0)
            }

            // Coarse parent-level underlay tiles (eliminates flicker during fast zoom transitions)
            Repeater {
                id: underlayTileRepeater
                objectName: "nexusGlobeUnderlayTileRepeater"
                model: underlayTileModel
                delegate: Image {
                    required property int tx
                    required property int ty
                    required property string url
                    property bool _countedReady: false
                    function _syncReadyCount(): void {
                        const isR = (status === Image.Ready);
                        if (isR === _countedReady)
                            return;
                        _countedReady = isR;
                        tileLayerHost.readyUnderlayCount = Math.max(0, tileLayerHost.readyUnderlayCount + (isR ? 1 : -1));
                    }
                    x: tileLayerHost.halfW + (tx - tileLayerHost.underlayCenterX) * tileLayerHost.underlayTilePx
                    y: tileLayerHost.halfH + (ty - tileLayerHost.underlayCenterY) * tileLayerHost.underlayTilePx
                    width: tileLayerHost.underlayTilePx + 0.75
                    height: tileLayerHost.underlayTilePx + 0.75
                    z: 1
                    source: url
                    asynchronous: true
                    cache: true
                    smooth: true
                    mipmap: true
                    fillMode: Image.Stretch
                    opacity: status === Image.Ready ? 1.0 : 0.0
                    onStatusChanged: _syncReadyCount()
                    Component.onCompleted: _syncReadyCount()
                    Component.onDestruction: {
                        if (_countedReady) {
                            _countedReady = false;
                            tileLayerHost.readyUnderlayCount = Math.max(0, tileLayerHost.readyUnderlayCount - 1);
                        }
                    }
                }
            }

            // Sharp current-zoom street/building/park/label tiles
            Repeater {
                id: primaryTileRepeater
                objectName: "nexusGlobePrimaryTileRepeater"
                model: primaryTileModel
                delegate: Image {
                    required property int tx
                    required property int ty
                    required property string url
                    property bool _countedReady: false
                    function _syncReadyCount(): void {
                        const isR = (status === Image.Ready);
                        if (isR === _countedReady)
                            return;
                        _countedReady = isR;
                        tileLayerHost.readyTileCount = Math.max(0, tileLayerHost.readyTileCount + (isR ? 1 : -1));
                    }
                    x: tileLayerHost.halfW + (tx - tileLayerHost.centerTileX) * tileLayerHost.tilePx
                    y: tileLayerHost.halfH + (ty - tileLayerHost.centerTileY) * tileLayerHost.tilePx
                    width: tileLayerHost.tilePx + 0.75
                    height: tileLayerHost.tilePx + 0.75
                    z: 2
                    source: url
                    asynchronous: true
                    cache: true
                    smooth: true
                    mipmap: true
                    fillMode: Image.Stretch
                    opacity: status === Image.Ready ? 1.0 : 0.0
                    Behavior on opacity {
                        NumberAnimation { duration: 120; easing.type: Easing.OutQuad }
                    }
                    onStatusChanged: _syncReadyCount()
                    Component.onCompleted: _syncReadyCount()
                    Component.onDestruction: {
                        if (_countedReady) {
                            _countedReady = false;
                            tileLayerHost.readyTileCount = Math.max(0, tileLayerHost.readyTileCount - 1);
                        }
                    }
                }
            }
        }

        Canvas {
            id: mapPinsCanvas
            anchors.fill: parent
            z: 3
            antialiasing: true
            onWidthChanged: if (detailedMapLayer.visible) requestPaint()
            onHeightChanged: if (detailedMapLayer.visible) requestPaint()
            onVisibleChanged: if (visible) requestPaint()
            onPaint: {
                if (!root.canRepaintTheme || !detailedMapLayer.visible || width < 20 || height < 20)
                    return;
                const ctx = getContext("2d");
                if (!ctx)
                    return;
                ctx.clearRect(0, 0, width, height);
                root._paintMapOverlayPins(
                    ctx, width, height,
                    root.ccStop(0), root.ccStop(7), root.ccStop(9), root.ccStop(10), root.ccStop(11), root.ccStop(12),
                    root.accentCol
                );
            }
        }
    }

    // Drag-to-rotate, wheel-to-zoom, hover-to-inspect, click-to-focus/open
    MouseArea {
        id: globeMouse
        anchors.fill: parent
        z: 4
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        cursorShape: pressed ? Qt.ClosedHandCursor : (root.hoveredCluster !== null ? Qt.PointingHandCursor : Qt.OpenHandCursor)

        property real pressX: 0
        property real pressY: 0
        property real dragStartLon: 0
        property real dragStartLat: 0
        property real dragStartMercY: 0
        property bool dragged: false

        onDoubleClicked: root.resetGlobe()

        onPressed: mouse => {
            pressX = mouse.x;
            pressY = mouse.y;
            dragStartLon = root.centerLon;
            dragStartLat = root.centerLat;
            dragStartMercY = root._mercatorY(root.centerLat);
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
                    if (root.isMapMode) {
                        const pxPerRad = root._mapPixelsPerRad(root.width, root.height);
                        const dLon = -(dx / pxPerRad) / root.degToRad;
                        const nextMercY = dragStartMercY + (dy / pxPerRad);
                        root.centerLon = root.wrapLon(dragStartLon + dLon);
                        root.centerLat = Math.max(-84.0, Math.min(84.0, root._invMercatorY(nextMercY)));
                    } else {
                        const degPerPx = root.dragSensitivity(root.zoom);
                        root.centerLon = root.wrapLon(dragStartLon - dx * degPerPx);
                        root.centerLat = Math.max(-78.0, Math.min(78.0, dragStartLat + dy * degPerPx));
                    }
                    root.hoveredCluster = null;
                    root.pauseUntilMs = Date.now() + 1800;
                    root.requestPaint();
                }
                return;
            }

            if (root.isMapMode) {
                const g = root.screenToMapLonLat(mouse.x, mouse.y, root.width, root.height);
                root.hoverGeoLat = g.lat;
                root.hoverGeoLon = g.lon;
            } else {
                root.hoverGeoLat = NaN;
                root.hoverGeoLon = NaN;
            }

            // Hit-test visible place clusters (`hitTolerance = 8.5` in `globe-widget.js`)
            const cx = root.width * 0.5;
            const cy = root.isMapMode ? (root.height * 0.5) : (root.height * 0.5 - 6);
            let best = null;
            let bestD = root.isMapMode ? 12.0 : 9.5;
            for (let i = 0; i < root.visibleClusters.length; ++i) {
                const cl = root.visibleClusters[i];
                let d = Math.hypot(mouse.x - cl.x, mouse.y - cl.y);
                if (!root.isMapMode) {
                    const dx = cl.x - cx;
                    const dy = cl.y - cy;
                    const rLen = Math.hypot(dx, dy);
                    const nx = rLen > 4.0 ? (dx / rLen) : 0.0;
                    const ny = rLen > 4.0 ? (dy / rLen) : -1.0;
                    const dTip = Math.hypot(mouse.x - (cl.x + nx * 7.5), mouse.y - (cl.y + ny * 7.5));
                    d = Math.min(d, dTip);
                }
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
            root.hoverGeoLat = NaN;
            root.hoverGeoLon = NaN;
            if (root.hoveredCluster !== null) {
                root.hoveredCluster = null;
                root.requestPaint();
            }
        }

        onWheel: wheel => {
            const factor = wheel.angleDelta.y > 0 ? 1.15 : (1.0 / 1.15);
            root.adjustZoomAt(factor, wheel.x, wheel.y);
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

    // Top-Left Subtle Cartographic Status Pill (mode + zoom + live coordinates in Map mode)
    Rectangle {
        id: mapStatusBadge
        objectName: "nexusGlobeModeBadge"
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.leftMargin: 10
        anchors.topMargin: 8
        height: 18
        width: modeBadgeText.implicitWidth + 12
        radius: 4
        z: 7
        visible: root.isMapMode || root.zoom >= 1.4 || globeMouse.containsMouse
        color: Qt.rgba(root.ccStop(1).r, root.ccStop(1).g, root.ccStop(1).b, 0.84)
        border.width: 1
        border.color: root.isMapMode ? Qt.alpha(root.accentCol, 0.45) : root.ccStop(5)

        StyledText {
            id: modeBadgeText
            anchors.centerIn: parent
            font.family: Appearance.font.family.monospace
            font.pixelSize: 8
            font.weight: Font.DemiBold
            color: root.isMapMode ? root.accentCol : root.ccStop(11)
            text: {
                const modeLbl = root.isMapMode ? "MAP" : "GLOBE";
                if (root.isMapMode) {
                    const zLbl = "Z" + Number(root.effectiveMapZoom).toFixed(1);
                    const latVal = Number.isFinite(root.hoverGeoLat) ? root.hoverGeoLat : root.centerLat;
                    const lonVal = Number.isFinite(root.hoverGeoLon) ? root.hoverGeoLon : root.centerLon;
                    const latStr = Math.abs(latVal).toFixed(2) + "°" + (latVal >= 0 ? "N" : "S");
                    const lonStr = Math.abs(lonVal).toFixed(2) + "°" + (lonVal >= 0 ? "E" : "W");
                    return modeLbl + " · " + zLbl + " · " + latStr + ", " + lonStr;
                }
                const zLbl = Number(root.zoom).toFixed(1) + "×";
                return modeLbl + " · " + zLbl;
            }
        }
    }

    // Top-Right Subtle Cartographic Attribution (matching `globe-vector-map-overlay.js`)
    StyledText {
        objectName: "nexusGlobeMapAttribution"
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.rightMargin: 8
        anchors.topMargin: 7
        z: 7
        visible: opacity > 0.01
        opacity: root.mapBlend > 0.45 ? 0.54 : 0.0
        Behavior on opacity {
            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
        }
        text: tileLayerHost.hasReadyTile ? "CARTO · OSM" : "Offline Vector"
        font.family: Appearance.font.family.monospace
        font.pixelSize: 7
        color: root.ccStop(10)
    }

    // Bottom-Right Hover-Revealed Controls (`theme|color`, `map|globe`, `-`, `+`, `reset`, `auto:on/off`)
    Row {
        id: globeCtrlRow
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 10
        anchors.bottomMargin: 6
        spacing: 4
        z: 8
        opacity: (globeMouse.containsMouse || styleBtnMouse.containsMouse || modeBtnMouse.containsMouse || zoomOutBtnMouse.containsMouse || zoomInBtnMouse.containsMouse || resetBtnMouse.containsMouse || autoBtnMouse.containsMouse) ? 1.0 : 0.0
        Behavior on opacity {
            NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
        }

        Rectangle {
            objectName: "nexusGlobeMapStyleButton"
            visible: root.isMapMode
            height: 18
            width: styleBtnTxt.implicitWidth + 10
            radius: 4
            color: styleBtnMouse.containsMouse
                ? Qt.rgba(root.ccStop(3).r, root.ccStop(3).g, root.ccStop(3).b, 0.94)
                : Qt.rgba(root.ccStop(1).r, root.ccStop(1).g, root.ccStop(1).b, 0.84)
            border.width: 1
            border.color: (root.mapStyle === "color" || styleBtnMouse.containsMouse) ? root.accentCol : root.ccStop(5)

            StyledText {
                id: styleBtnTxt
                anchors.centerIn: parent
                text: root.mapStyle === "themed" ? "alis" : "color"
                font.family: Appearance.font.family.monospace
                font.pixelSize: 8
                color: (root.mapStyle === "color" || styleBtnMouse.containsMouse) ? root.accentCol : root.ccStop(11)
            }

            MouseArea {
                id: styleBtnMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggleMapStyle()
            }
        }

        Rectangle {
            objectName: "nexusGlobeModeButton"
            height: 18
            width: modeBtnTxt.implicitWidth + 10
            radius: 4
            color: (root.isMapMode || modeBtnMouse.containsMouse)
                ? Qt.rgba(root.ccStop(3).r, root.ccStop(3).g, root.ccStop(3).b, 0.94)
                : Qt.rgba(root.ccStop(1).r, root.ccStop(1).g, root.ccStop(1).b, 0.84)
            border.width: 1
            border.color: (root.isMapMode || modeBtnMouse.containsMouse) ? root.accentCol : root.ccStop(5)

            StyledText {
                id: modeBtnTxt
                anchors.centerIn: parent
                text: root.isMapMode ? "map" : "globe"
                font.family: Appearance.font.family.monospace
                font.pixelSize: 8
                color: (root.isMapMode || modeBtnMouse.containsMouse) ? root.accentCol : root.ccStop(11)
            }

            MouseArea {
                id: modeBtnMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggleViewMode()
            }
        }

        Rectangle {
            objectName: "nexusGlobeZoomOutButton"
            height: 18
            width: 18
            radius: 4
            color: zoomOutBtnMouse.containsMouse
                ? Qt.rgba(root.ccStop(3).r, root.ccStop(3).g, root.ccStop(3).b, 0.92)
                : Qt.rgba(root.ccStop(1).r, root.ccStop(1).g, root.ccStop(1).b, 0.84)
            border.width: 1
            border.color: zoomOutBtnMouse.containsMouse ? root.accentCol : root.ccStop(5)

            StyledText {
                anchors.centerIn: parent
                text: "−"
                font.family: Appearance.font.family.monospace
                font.pixelSize: 10
                font.weight: Font.Bold
                color: zoomOutBtnMouse.containsMouse ? root.accentCol : root.ccStop(11)
            }

            MouseArea {
                id: zoomOutBtnMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.adjustZoom(1.0 / 1.45)
            }
        }

        Rectangle {
            objectName: "nexusGlobeZoomInButton"
            height: 18
            width: 18
            radius: 4
            color: zoomInBtnMouse.containsMouse
                ? Qt.rgba(root.ccStop(3).r, root.ccStop(3).g, root.ccStop(3).b, 0.92)
                : Qt.rgba(root.ccStop(1).r, root.ccStop(1).g, root.ccStop(1).b, 0.84)
            border.width: 1
            border.color: zoomInBtnMouse.containsMouse ? root.accentCol : root.ccStop(5)

            StyledText {
                anchors.centerIn: parent
                text: "+"
                font.family: Appearance.font.family.monospace
                font.pixelSize: 10
                font.weight: Font.Bold
                color: zoomInBtnMouse.containsMouse ? root.accentCol : root.ccStop(11)
            }

            MouseArea {
                id: zoomInBtnMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.adjustZoom(1.45)
            }
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
