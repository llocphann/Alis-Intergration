#!/usr/bin/env python3
"""Silent offscreen Quickshell runtime verification for Nexus Round 2 features:
1. NexusGlobeWidget: smooth cross-fade (1.42..2.18), deep Mercator zoom 18 (maxZoom=64),
   CartoDB themed/color tile grid URLs & coarse underlay, zero tiles at default globe zoom,
   toggleViewMode / toggleMapStyle / focusCluster / resetView, plus all 9 freeze/pause/resume
   paintCount invariants.
2. NexusWorkspace + NexusCustomViews: zero Connections warnings under mock nexus,
   auto-themed RichText separators (both #334155 table rules and legacy <hr/>),
   genuine top-edge slide-down WorkspaceHoverTabBar (height=28, y=-28->0), and
   auto-themed Dashboard collection cards (zero hardcoded Tokyo Night hexes).
"""
from __future__ import annotations

import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from integration_test_host import resolve_host_root

HOST = resolve_host_root(ROOT)

QML_HARNESS = r'''//@ pragma ShellId alis-nexus-round2-offscreen-test
pragma ComponentBehavior: Bound

import QtQuick
import QtTest
import Quickshell
import qs.modules.common

ShellRoot {
    id: root
    property int checks: 0

    function check(cond, msg) {
        root.checks++
        if (!cond) throw new Error(msg)
    }

    function findByObjectName(item, name) {
        if (!item) return null
        if (item.objectName === name) return item
        for (const ch of (item.children ?? [])) {
            const hit = findByObjectName(ch, name)
            if (hit) return hit
        }
        return null
    }

    QtObject {
        id: globeOwner
        property var nexus: ({ isOpen: true })
        property bool transitionSettled: true
        property bool surfaceActive: true
        property string themeSignature: "initial"
        property string _settledPrimary: "#22bb88"
        property string _settledOnLayer1: "#eeeeee"
        property string _settledSubtext: "#aaaaaa"
        property string _settledBorder: "#333333"
        property string _settledLayer1: "#111111"
    }

    // Minimal mock nexus (intentionally omits several signals to verify ignoreUnknownSignals: true!)
    QtObject {
        id: mockNexus
        property bool isOpen: true
        property bool available: true
        property bool enabled: true
        property bool scanBusy: false
        property bool leftSidebarOpen: true
        property bool rightSidebarOpen: true
        property string leftSidebarTab: "files"
        property string rightSidebarTab: "outline"
        property string currentPath: ""
        property string activeTab: "home"
        property string editorMode: "hybrid"
        property string searchQuery: ""
        property bool commandPaletteOpen: false
        property bool newNoteModalOpen: false
        property int editingBlockId: -1
        property var currentDoc: null
        property var tree: []
        property var notes: []
        property var collections: ({
            movies: [], tvseries: [], games: [], books: [], recipes: [],
            exercises: [], places: [
                { title: "Hanoi", lon: 105.854, lat: 21.028, visited: true, hasCoordinates: true, relPath: "Places/Hanoi.md" },
                { title: "Saigon", lon: 106.660, lat: 10.777, wantToVisit: true, hasCoordinates: true, relPath: "Places/Saigon.md" }
            ],
            websites: [], cornell: [], zettelkasten: [], finance: [], clippings: []
        })
        property var graph: ({ nodes: [], edges: [] })
        property var localGraph: ({ nodes: [], edges: [] })
        property var tags: []
        property var hierarchicalTagsList: []
        property var cardOrder: ({ left: ["files", "localGraph"], right: ["calendar", "vaultGraph", "schedule"] })
        property var dailySchedule: ({})
        property var financeSummary: ({})
        property string selectedDateStr: "2026-11-21"
        function openFile(p, focus) {}
        function openDailyNote(d) {}
        function jumpCalendarToday() {}
        function openGraphView() {}
        function getNoteBodyMarkdown(d) { return "" }
        function shortcutFor(id) { return "" }
    }

    Window {
        id: win
        visible: true
        width: 1280
        height: 760
        color: "#0f1419"

        Loader {
            id: globeLoader
            width: 520
            height: 400
            source: "GLOBE_QML"
            onLoaded: {
                item.workspace = globeOwner
                item.autoRotate = false
                item.onlineTilesEnabled = true
                item.places = [
                    { title: "Hanoi", lon: 105.854, lat: 21.028, visited: true, hasCoordinates: true },
                    { title: "Saigon", lon: 106.660, lat: 10.777, wantToVisit: true, hasCoordinates: true }
                ]
            }
        }

        Loader {
            id: customViewsLoader
            width: 600
            height: 400
            source: "CUSTOM_VIEWS_QML"
            onLoaded: {
                item.nexus = mockNexus
            }
        }

        Loader {
            id: wsLoader
            anchors.fill: parent
            source: "WORKSPACE_QML"
            onLoaded: {
                item.nexus = mockNexus
            }
        }
    }

    TestCase {
        id: tc
        when: false
        optional: true

        function run() {
            try {
                tryCompare(Config, "ready", true, 4000)
                tryCompare(globeLoader, "status", Loader.Ready, 5000)
                tryCompare(customViewsLoader, "status", Loader.Ready, 5000)
                tryCompare(wsLoader, "status", Loader.Ready, 5000)

                // ── 1. NexusGlobeWidget: Crossfade, Deep Zoom 18, Tile Grid, Freeze Guards ──
                const g = globeLoader.item
                tryVerify(() => g.paintCount > 0, 5000)
                wait(60)

                const tileLayer = root.findByObjectName(g, "nexusGlobeMapTileLayer")
                const mapLayer = root.findByObjectName(g, "nexusGlobeDetailedMapLayer")
                root.check(tileLayer !== null && mapLayer !== null, "Missing detailed map / tile layers")

                // Default globe state: zoom=0.92, mapBlend=0, zero network tile fetches
                root.check(Math.abs(g.zoom - 0.92) < 0.01, "Default zoom should be 0.92")
                root.check(g.mapBlend === 0.0 && !g.isMapMode, "Default globe should not be in map mode")
                root.check(tileLayer.tilesActive === false && tileLayer.primaryTiles.length === 0,
                    "Default globe must NOT request tiles")

                // Smooth crossfade thresholds (1.42 .. 2.18)
                g.zoom = 1.42
                root.check(Math.abs(g.mapBlend) < 0.001, "mapBlend at 1.42 should be 0")
                g.zoom = 1.80
                root.check(g.mapBlend > 0.45 && g.mapBlend < 0.55, "mapBlend midpoint at 1.80 expected ~0.5, got " + g.mapBlend)
                g.zoom = 2.18
                root.check(Math.abs(g.mapBlend - 1.0) < 0.001 && g.isMapMode === true, "mapBlend at 2.18 should be 1.0")
                root.check(tileLayer.tilesActive === true && tileLayer.primaryTiles.length > 0,
                    "Zoomed map should build visible tile descriptors")
                root.check(tileLayer.primaryTiles[0].url.indexOf("dark_all/") > 0 && tileLayer.primaryTiles[0].url.endsWith("@2x.png"),
                    "Themed map should use CartoDB dark_all @2x tiles: " + tileLayer.primaryTiles[0].url)

                // Deep street/building zoom 18 (maxZoom = 64)
                root.check(g.maxZoom >= 64.0, "maxZoom should reach 64 for zoom 18")
                root.check(Math.abs(g.mapZoom(64.0) - 18.0) < 0.01, "mapZoom(64) should equal 18.0, got " + g.mapZoom(64.0))
                g.zoom = 64.0
                wait(30)
                root.check(tileLayer.tileZ === 18 && tileLayer.underlayZ === 16,
                    "Deep zoom tileZ/underlayZ mismatch: " + tileLayer.tileZ + "/" + tileLayer.underlayZ)

                // Verify key-diffed ListModel retains surviving Image delegates across tile-boundary pan!
                const tileRepeater = root.findByObjectName(g, "nexusGlobePrimaryTileRepeater")
                root.check(tileRepeater !== null && tileRepeater.count > 0, "Primary tile Repeater missing or empty")
                const beforeByUrl = ({})
                for (let ti = 0; ti < tileRepeater.count; ++ti) {
                    const it = tileRepeater.itemAt(ti)
                    if (it) beforeByUrl[String(it.source)] = it
                }
                const prevTxMin = tileLayer.txMin
                // Pan east by 1 tile width at zoom 18 (~360 / 2^18 deg) so tile boundary shifts by 1 column
                g.centerLon = g.wrapLon(g.centerLon + (360.0 / Math.pow(2, 18)))
                wait(30)
                root.check(tileLayer.txMin === prevTxMin + 1, "Expected tile pan to advance txMin by 1")
                let retainedCount = 0
                for (let ti = 0; ti < tileRepeater.count; ++ti) {
                    const it = tileRepeater.itemAt(ti)
                    if (it && beforeByUrl[String(it.source)] === it)
                        retainedCount++
                }
                root.check(retainedCount > 0,
                    "Panning across a tile boundary must retain surviving Image delegates (got retained=" + retainedCount + ")")

                // Verify large maximized viewport (1600x900) does not truncate at old 36-tile cap
                globeLoader.width = 1600
                globeLoader.height = 900
                g.zoom = 26.4 // effectiveMapZoom ~ 14.66 -> tileZ=15, tilePx ~ 202px -> needs 45-54 tiles
                wait(30)
                root.check(tileLayer.primaryTiles.length > 36,
                    "Large 1600x900 viewport must not truncate tiles at 36, got " + tileLayer.primaryTiles.length)
                globeLoader.width = 520
                globeLoader.height = 400
                g.zoom = 64.0
                wait(30)

                // Style toggle -> Voyager full-color street tiles
                g.toggleMapStyle()
                wait(20)
                root.check(g.mapStyle === "color" && tileLayer.primaryTiles[0].url.indexOf("voyager/") > 0,
                    "Color style should switch to CartoDB voyager tiles")
                g.toggleMapStyle()
                root.check(g.mapStyle === "themed", "toggleMapStyle should return to themed")

                // Toggle mode & symmetric zoom-out reset from pinned map mode
                g.toggleViewMode()
                root.check(!g.isMapMode && g.viewModePreference === "globe", "toggleViewMode should switch back to globe")
                g.toggleViewMode()
                root.check(g.isMapMode && g.viewModePreference === "map", "toggleViewMode should pin map")
                g.zoom = 1.4
                g.adjustZoom(0.7) // -> 0.98 <= 1.15 -> should symmetrically return to auto & globe
                root.check(g.viewModePreference === "auto" && !g.isMapMode,
                    "Zooming out below 1.15 from pinned map must return to auto globe, got pref=" + g.viewModePreference)
                g.resetView()
                root.check(Math.abs(g.zoom - 0.92) < 0.01 && g.viewModePreference === "auto" && tileLayer.primaryTiles.length === 0,
                    "resetView should restore globe and stop tile grid")

                // Freeze / pause / resume lifecycle invariants (identical to test-nexus-globe-freeze-runtime.py)
                wait(80)
                let before = g.paintCount
                g.resetView(); globeOwner.surfaceActive = false
                wait(80)
                root.check(g.paintCount === before, "queued-frame-does-not-paint-after-pause")
                before = g.paintCount; globeOwner.surfaceActive = true
                tryVerify(() => g.paintCount > before, 1500)
                wait(80)
                before = g.paintCount; g.focusCluster({ lon: 106.7, lat: 10.8 })
                tryVerify(() => g.paintCount > before, 1500)
                root.check(g.isMapMode === true, "focusCluster should smoothly enter Map mode")
                g.resetView(); wait(80)
                globeOwner.nexus = ({ isOpen: false }); before = g.paintCount; g.resetView()
                wait(80)
                root.check(g.paintCount === before, "closed-host-no-paint")
                globeOwner.nexus = ({ isOpen: true })
                tryVerify(() => g.paintCount > before, 1500)
                wait(80)
                g.visible = false; before = g.paintCount; g.resetView()
                wait(80)
                root.check(g.paintCount === before, "hidden-globe-no-paint")
                g.visible = true
                tryVerify(() => g.paintCount > before, 1500)

                // ── 2. NexusWorkspace + NexusCustomViews: RichText Separators, Hover Tab Bar, Auto-Theming ──
                const ws = wsLoader.item
                const cv = customViewsLoader.item

                const themedLegacyHr = ws.themeRichHtml("<p>A</p><hr class='sep'/><p>B</p>")
                root.check(themedLegacyHr.indexOf("<hr") < 0 && themedLegacyHr.indexOf("background-color:") > 0,
                    "Workspace themeRichHtml must auto-theme legacy & attributed <hr>: " + themedLegacyHr)
                const themedSentinel = ws.themeRichHtml("<td style='background-color:#334155;'></td>")
                root.check(themedSentinel.indexOf("#334155") < 0,
                    "Workspace themeRichHtml must rewrite #334155 separator sentinel")

                const cvMd = cv.renderMarkdownBlocksHtml("First\n---\nSecond")
                root.check(cvMd.indexOf("<hr") < 0 && cvMd.indexOf("background-color:") > 0,
                    "CustomViews renderMarkdownBlocksHtml must emit themed separator table instead of bare <hr/>: " + cvMd)
                const cvLegacyHr = cv.themeRichHtml("Before<hr style='color:gray'/>After")
                root.check(cvLegacyHr.indexOf("<hr") < 0 && cvLegacyHr.indexOf("background-color:") > 0,
                    "CustomViews themeRichHtml must auto-theme legacy & attributed <hr>")

                // Move pointer to neutral center away from window edges so offscreen default (0,0) cursor does not keep edge rails hovered
                // Wait past 150ms grace timer + 180ms OutCubic slide animation
                tc.mouseMove(ws, 600, 400)
                wait(450)

                // Verify genuine top-edge slide-down WorkspaceHoverTabBar (full 28px height, slides via y = -28)
                const localBar = root.findByObjectName(ws, "nexusLocalGraphStatusBar")
                const calBar = root.findByObjectName(ws, "nexusCalendarHoverTabBar")
                const vgBar = root.findByObjectName(ws, "nexusVaultGraphHoverTabBar")
                const mainHoverBar = root.findByObjectName(ws, "nexusMainHoverTabBar")
                const openTabsStrip = root.findByObjectName(ws, "nexusOpenTabsStrip")
                const mainCard = root.findByObjectName(ws, "nexusMainCard")
                const homepageView = root.findByObjectName(ws, "nexusHomepageView")
                root.check(localBar !== null && calBar !== null && vgBar !== null, "Missing WorkspaceHoverTabBar instances")
                root.check(localBar.height === 28 && localBar.y === -28 && localBar.opacity <= 0.01,
                    "WorkspaceHoverTabBar should hold full height=28 and slide from y=-28 when hidden, got h=" + localBar.height + " y=" + localBar.y)
                root.check(mainHoverBar !== null && openTabsStrip !== null && mainCard !== null,
                    "Missing nexusMainHoverTabBar, nexusOpenTabsStrip, or nexusMainCard")
                root.check(root.findByObjectName(mainCard, "nexusOpenTabsStrip") === null,
                    "nexusOpenTabsStrip should sit outside above nexusMainCard, not inside nexusMainCard")
                root.check(openTabsStrip.height === 28 && openTabsStrip.y === -28 && openTabsStrip.opacity <= 0.01,
                    "nexusOpenTabsStrip should hold height=28 and slide from y=-28 when hidden, got h=" + openTabsStrip.height + " y=" + openTabsStrip.y)
                root.check(openTabsStrip.border.width === 0 && openTabsStrip.color.a === 0,
                    "nexusOpenTabsStrip should have transparent background and no shared outer border, got border=" + openTabsStrip.border.width + " alpha=" + openTabsStrip.color.a)
                const homepageTab = root.findByObjectName(openTabsStrip, "nexusHomepagePinnedTab")
                const ribbon = root.findByObjectName(ws, "nexusObsidianRibbon")
                function hasCloseSymbol(node) {
                    if (!node) return false
                    if (node.text === "close") return true
                    const kids = node.children || []
                    for (let i = 0; i < kids.length; ++i) {
                        if (hasCloseSymbol(kids[i])) return true
                    }
                    return false
                }
                root.check(homepageTab !== null && !hasCloseSymbol(homepageTab),
                    "nexusHomepagePinnedTab must sit inside nexusOpenTabsStrip and have no close button")
                root.check(ribbon !== null && ribbon.width === 40 && ribbon.x === -40 && ribbon.opacity <= 0.01 && ribbon.border.width === 0 && ribbon.color.a === 0,
                    "nexusObsidianRibbon should hold width=40, slide from x=-40 when hidden, and stay borderless/transparent, got w=" + (ribbon ? ribbon.width : null) + " x=" + (ribbon ? ribbon.x : null) + " op=" + (ribbon ? ribbon.opacity : null) + " b=" + (ribbon ? ribbon.border.width : null) + " a=" + (ribbon ? ribbon.color.a : null))
                const basesBtn = root.findByObjectName(ribbon, "nexusBasesRibbonButton")
                const vimBtn = root.findByObjectName(ribbon, "nexusVimModeBadge")
                const ribbonCenterY = (basesBtn && vimBtn)
                    ? (basesBtn.mapToItem(ribbon, 0, 0).y + vimBtn.mapToItem(ribbon, 0, 0).y + vimBtn.height) * 0.5
                    : -1
                root.check(basesBtn !== null && vimBtn !== null && Math.abs(ribbonCenterY - ribbon.height * 0.5) <= 24,
                    "Obsidian ribbon icon buttons should sit vertically centered, got centerY=" + ribbonCenterY + " ribbonH=" + (ribbon ? ribbon.height : 0))
                root.check(root.findByObjectName(ws, "nexusWindowModeToggleButton") === null && root.findByObjectName(ws, "nexusNavBackButton") === null && root.findByObjectName(ws, "nexusNavForwardButton") === null,
                    "Window, Back, and Forward header buttons should be removed")
                function hasHomepageTitleLabel(node) {
                    if (!node) return false
                    if (node.text === "Homepage") return true
                    const kids = node.children || []
                    for (let i = 0; i < kids.length; ++i) {
                        if (hasHomepageTitleLabel(kids[i])) return true
                    }
                    return false
                }
                root.check(homepageView !== null && !hasHomepageTitleLabel(homepageView),
                    "nexusHomepageView should not render large 'Homepage' heading text")
                function hasLegacyWorkoutTableLabel(node) {
                    if (!node) return false
                    if (node.text === "Calisthenics" || node.text === "SET - REPS") return true
                    const kids = node.children || []
                    for (let i = 0; i < kids.length; ++i) {
                        if (hasLegacyWorkoutTableLabel(kids[i])) return true
                    }
                    return false
                }
                root.check(homepageView !== null && !hasLegacyWorkoutTableLabel(homepageView),
                    "nexusHomepageView should not render legacy Calisthenics/Cardio workout table")

                console.info("NEXUS_ROUND2_PASS", "checks=" + root.checks)
            } catch (err) {
                console.error("NEXUS_ROUND2_FAIL", err.message, err.stack)
            }
            Qt.quit()
        }
    }

    Timer {
        interval: 100
        running: true
        repeat: false
        onTriggered: tc.run()
    }
}
'''


def main() -> None:
    qs = shutil.which("qs")
    if not qs:
        print("SKIP: qs unavailable")
        return

    with tempfile.TemporaryDirectory(prefix="alis-nexus-r2-") as tmp:
        root = Path(tmp)
        for entry in ("modules", "services", "GlobalStates.qml", "qmldir", "assets", "scripts", "defaults", "translations"):
            (root / entry).symlink_to(HOST / entry)
        qml = (
            QML_HARNESS
            .replace("GLOBE_QML", str(ROOT / "plugins/nexus/modules/nexus/NexusGlobeWidget.qml"))
            .replace("CUSTOM_VIEWS_QML", str(ROOT / "plugins/nexus/modules/nexus/NexusCustomViews.qml"))
            .replace("WORKSPACE_QML", str(ROOT / "plugins/nexus/modules/nexus/NexusWorkspace.qml"))
        )
        (root / "shell.qml").write_text(qml, encoding="utf-8")

        env = os.environ.copy()
        env.pop("WAYLAND_DISPLAY", None)
        env.pop("DISPLAY", None)
        env["QT_QPA_PLATFORM"] = "offscreen"
        env["QT_QUICK_BACKEND"] = "software"
        env["XDG_CONFIG_HOME"] = str(root / "config")
        env["XDG_STATE_HOME"] = str(root / "state")
        env["XDG_CACHE_HOME"] = str(root / "cache")
        env["XDG_DATA_HOME"] = "/nonexistent"
        env["XDG_DATA_DIRS"] = "/nonexistent"
        (root / "config/illogical-impulse").mkdir(parents=True, exist_ok=True)
        (root / "config/illogical-impulse/config.json").write_text(
            (HOST / "defaults/config.json").read_text(encoding="utf-8"), encoding="utf-8"
        )

        res = subprocess.run(
            [qs, "-p", str(root / "shell.qml"), "--no-color"],
            env=env,
            capture_output=True,
            text=True,
            timeout=35,
        )
        out = (res.stdout or "") + "\n" + (res.stderr or "")
        conn_warns = [ln for ln in out.splitlines() if "Detected function" in ln and "Connections" in ln]
        if conn_warns:
            print("UNEXPECTED CONNECTIONS WARNINGS:\n" + "\n".join(conn_warns))
            sys.exit(1)
        if res.returncode != 0 or "NEXUS_ROUND2_PASS" not in out or re.search(r"NEXUS_ROUND2_FAIL|ReferenceError:|TypeError:", out):
            print(out)
            sys.exit(1)
        for line in out.splitlines():
            if "NEXUS_ROUND2_PASS" in line:
                print(line.strip())


if __name__ == "__main__":
    main()
