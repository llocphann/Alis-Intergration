#!/usr/bin/env python3
"""Headless Quickshell WCAG contrast verification for Dashboard Exercises Tracker.

Mounts `DashboardExercisesTracker` inside real QML/Quickshell offscreen runtime across
Abyss Dark, Abyss Light, Material Dark, and Material Light themes (including translucent
card opacity) and asserts WCAG AA/AAA readability across text, subtext, accent text,
accent fill buttons, toggled pills, error text, and input fields.
"""
from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile

from integration_test_host import resolve_host_root

ROOT = Path(__file__).resolve().parents[1]
HOST = resolve_host_root(ROOT)
sys.path.insert(0, str(HOST / "scripts"))
from native_test_session import run_qs  # noqa: E402

spec = importlib.util.spec_from_file_location("installer", ROOT / "scripts/install.py")
installer = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(installer)

CONTRAST_SHELL_QML = r"""
pragma ComponentBehavior: Bound
import QtQuick
import QtTest
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.dashboard

ShellRoot {
    id: root
    Component.onCompleted: Quickshell.watchFiles = false

    Window {
        id: win
        visible: true
        width: 1120
        height: 760
        color: Appearance.colors.colLayer0Base

        Loader {
            id: trackerLoader
            anchors.fill: parent
            active: false
            source: AlisIntergration.exercisesTrackerDashboardSource()
            onLoaded: {
                if (item)
                    item.presentationActive = true
            }
        }
    }

    TestCase {
        id: test
        when: false
        optional: true

        function check(cond, msg) {
            if (!cond)
                throw new Error(msg)
        }

        function walkItems(item, fn) {
            if (!item)
                return
            fn(item)
            if (item.contentItem && item.contentItem !== item)
                walkItems(item.contentItem, fn)
            const list = item.children || []
            for (let i = 0; i < list.length; ++i)
                walkItems(list[i], fn)
        }

        function findToggledButtons(rootItem) {
            const found = []
            const seen = new Set()
            walkItems(rootItem, (node) => {
                if (node && node.objectName && node.toggled === true && node.buttonColor !== undefined && !seen.has(node.objectName)) {
                    seen.add(node.objectName)
                    found.push(node)
                }
            })
            return found
        }

        function findTextNodes(item) {
            const results = []
            walkItems(item, (node) => {
                if (node && node.visible !== false && typeof node.text === "string" && node.text.length > 0 && node.color !== undefined && node.font !== undefined)
                    results.push(node)
            })
            return results
        }

        function measureTracker(caseName, tracker) {
            const cCardBg = ColorUtils.applyAlpha(
                ColorUtils.mix(tracker.colCard, tracker.colSurfaceBase, tracker.colCard.a),
                1.0
            )
            const cElevBg = ColorUtils.applyAlpha(
                ColorUtils.mix(tracker.colCardElevated, cCardBg, tracker.colCardElevated.a),
                1.0
            )
            const cInputBg = ColorUtils.applyAlpha(
                ColorUtils.mix(tracker.colInputBg, cElevBg, tracker.colInputBg.a),
                1.0
            )

            const textRatioCard = ColorUtils.contrastRatio(tracker.colText, cCardBg)
            const textRatioElev = ColorUtils.contrastRatio(tracker.colText, cElevBg)
            const textRatioInput = ColorUtils.contrastRatio(tracker.colText, cInputBg)
            const subRatioElev = ColorUtils.contrastRatio(tracker.colSubtext, cElevBg)
            const accentTextRatio = ColorUtils.contrastRatio(tracker.colAccent, cElevBg)
            const onAccentRatio = ColorUtils.contrastRatio(tracker.colOnAccent, tracker.colAccentFill)
            const onToggledRatio = ColorUtils.contrastRatio(tracker.colOnToggled, tracker.colToggledBg)
            const errRatio = ColorUtils.contrastRatio(tracker.colErrorText, cElevBg)
            const elevInputSep = Math.abs(
                ColorUtils.relativeLuminance(cElevBg) - ColorUtils.relativeLuminance(cInputBg)
            )

            check(textRatioCard >= 7.0, caseName + " colText/colCard low: " + textRatioCard)
            check(textRatioElev >= 7.0, caseName + " colText/colCardElevated low: " + textRatioElev)
            check(textRatioInput >= 5.5, caseName + " colText/colInputBg low: " + textRatioInput)
            check(subRatioElev >= 4.5, caseName + " colSubtext/colCardElevated low: " + subRatioElev)
            check(accentTextRatio >= 4.5, caseName + " colAccent/colCardElevated low: " + accentTextRatio)
            check(onAccentRatio >= 5.0, caseName + " colOnAccent/colAccentFill low: " + onAccentRatio)
            check(onToggledRatio >= 5.0, caseName + " colOnToggled/colToggledBg low: " + onToggledRatio)
            check(errRatio >= 4.5, caseName + " colErrorText/colCardElevated low: " + errRatio)
            check(elevInputSep >= 0.007, caseName + " colInputBg too close to colCardElevated: " + elevInputSep)
            check(tracker.colInputBorder.a >= 0.18, caseName + " colInputBorder too faint: " + tracker.colInputBorder.a)

            // Verify every toggled PillButton / dayChip / routineChip / catBtn renders >= 5.0 contrast across icon + label
            const toggledBtns = findToggledButtons(tracker)
            check(toggledBtns.length >= 4, caseName + " expected >=4 active toggled buttons, got " + toggledBtns.length)
            for (const btn of toggledBtns) {
                const bg = ColorUtils.applyAlpha(ColorUtils.mix(btn.buttonColor, cCardBg, btn.buttonColor.a), 1.0)
                const txtNodes = findTextNodes(btn)
                check(txtNodes.length > 0, caseName + " toggled button missing text child: " + btn.objectName)
                for (const txt of txtNodes) {
                    const ratio = ColorUtils.contrastRatio(txt.color, bg)
                    check(ratio >= 5.0, caseName + " rendered toggled contrast low on " + btn.objectName + " (" + txt.text + "): " + ratio)
                }
            }

            // Verify chromatic background saturation is preserved across tonal elevation tiers (never washed into neutral gray)
            const baseSat = Qt.color(tracker.colSurfaceBase).hslSaturation
            if (baseSat >= 0.05) {
                check(Qt.color(cElevBg).hslSaturation >= baseSat * 0.90,
                    caseName + " cElevBg washed to gray: baseSat=" + baseSat + " elevSat=" + Qt.color(cElevBg).hslSaturation)
                check(Qt.color(cInputBg).hslSaturation >= baseSat * 0.90,
                    caseName + " cInputBg washed to gray: baseSat=" + baseSat + " inputSat=" + Qt.color(cInputBg).hslSaturation)
            }

            console.info("CASE_PASS", caseName, JSON.stringify({
                textElev: Number(textRatioElev.toFixed(2)),
                subElev: Number(subRatioElev.toFixed(2)),
                accentElev: Number(accentTextRatio.toFixed(2)),
                onAccent: Number(onAccentRatio.toFixed(2)),
                onToggled: Number(onToggledRatio.toFixed(2)),
                inputSep: Number(elevInputSep.toFixed(4)),
                toggledCount: toggledBtns.length
            }))
        }

        function applyPalette(panelFamily, dark, layer0, layer1, layer2, primary, onPrimary, secCont, onSecCont, text, subtext, errCol) {
            Config.setNestedValue("panelFamily", panelFamily)
            Appearance.m3colors.darkmode = dark
            Appearance.m3colors.m3background = layer0
            Appearance.m3colors.m3surface = layer0
            Appearance.m3colors.m3onSurface = text
            Appearance.m3colors.m3surfaceContainerLow = layer1
            Appearance.m3colors.m3surfaceContainer = layer1
            Appearance.m3colors.m3surfaceContainerHigh = layer2
            Appearance.m3colors.m3primary = primary
            Appearance.m3colors.m3onPrimary = onPrimary
            Appearance.m3colors.m3secondaryContainer = secCont
            Appearance.m3colors.m3onSecondaryContainer = onSecCont
            Appearance.m3colors.m3onSurfaceVariant = subtext
            Appearance.m3colors.m3error = errCol
        }

        function run() {
            try {
                tryCompare(Config, "ready", true, 5000)
                AlisIntergration.demandExercisesTracker()
                tryVerify(() => AlisIntergration.exercisesTracker !== null
                    && AlisIntergration.exercisesTrackerDashboardSource().length > 0, 5000)

                Config.setNestedValue("abyss.content.opacity", 0.35)
                trackerLoader.active = true
                tryVerify(() => trackerLoader.status === Loader.Ready && trackerLoader.item !== null, 5000)
                wait(80)

                const tracker = trackerLoader.item
                // 1. Abyss Dark with low user content opacity
                applyPalette("abyss", true, "#0f141c", "#161c26", "#222a38", "#7aa2f7", "#0b1320", "#283548", "#dbe7ff", "#edf2fb", "#9aa9c4", "#f7768e")
                wait(280)
                measureTracker("abyss-dark", tracker)

                // 2. Abyss Light
                applyPalette("abyss", false, "#eef2f9", "#e4eaf4", "#d6deed", "#2b59c3", "#ffffff", "#d0dcf5", "#132954", "#111622", "#47556b", "#c62828")
                wait(280)
                measureTracker("abyss-light", tracker)

                // 3. Material Dark
                applyPalette("material", true, "#121318", "#1c1f26", "#272b35", "#aac7ff", "#10284c", "#34445f", "#d8e4ff", "#e6eaf2", "#a8b2c7", "#ffb4ab")
                wait(280)
                measureTracker("material-dark", tracker)

                // 4. Material Light
                applyPalette("material", false, "#f8f9fc", "#eef1f6", "#e1e6ef", "#2f5cd3", "#ffffff", "#d8e2fb", "#152b59", "#171c26", "#50596c", "#ba1a1a")
                wait(280)
                measureTracker("material-light", tracker)

                // 5. Abyss Rose-Espresso Dark (regression guard for pink primary + warm dark background)
                applyPalette("abyss", true, "#150e0e", "#1d1414", "#271b1b", "#ffb4ab", "#690005", "#533f3d", "#ffdad6", "#f5dedb", "#bfa9a7", "#ffb4ab")
                wait(280)
                measureTracker("abyss-rose-espresso", tracker)

                console.info("EXERCISES_TRACKER_CONTRAST_PASS")
            } catch (err) {
                console.error("EXERCISES_TRACKER_CONTRAST_FAIL", err.message, err.stack)
            }
            Qt.quit()
        }
    }

    Timer {
        interval: 120
        running: true
        repeat: false
        onTriggered: test.run()
    }
}
"""


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="alis-et-contrast-") as tmp:
        private = Path(tmp)
        shell = private / "shell"
        shell.mkdir()
        for entry in (
            "services",
            "modules",
            "GlobalStates.qml",
            "qmldir",
            "scripts",
            "defaults",
            "translations",
            "assets",
        ):
            (shell / entry).symlink_to(HOST / entry)

        package = private / "data/alis-intergration/releases/fixture"
        package.parent.mkdir(parents=True)
        installer.assemble(ROOT, package, "c" * 40)
        (private / "data/alis-intergration/current").symlink_to("releases/fixture")

        config_dir = private / "config/alis"
        config_dir.mkdir(parents=True)
        options = json.loads((HOST / "defaults/config.json").read_text(encoding="utf-8"))
        options["integrations"]["alisIntergration"] = {
            "tlp": False,
            "thinkfan": False,
            "nexus": False,
            "spaced_repetition": False,
            "exercises_tracker": True,
        }
        options["battery"]["chargeLimit"]["enable"] = False
        options["powerProfiles"]["fanControl"]["enabled"] = False
        (config_dir / "config.json").write_text(json.dumps(options), encoding="utf-8")

        et_state_dir = private / "state/quickshell/user/exercises-tracker"
        et_state_dir.mkdir(parents=True)
        (et_state_dir / "state.json").write_text(
            json.dumps({"schemaVersion": 1, "days": {}, "bodyCheckins": []}),
            encoding="utf-8",
        )

        (shell / "shell.qml").write_text(CONTRAST_SHELL_QML, encoding="utf-8")
        env = {
            k: v
            for k, v in os.environ.items()
            if k not in ("WAYLAND_DISPLAY", "DISPLAY", "QSG_RHI_BACKEND")
        }
        env.update(
            QT_QPA_PLATFORM="offscreen",
            QT_QUICK_BACKEND="software",
            HOME=str(private),
            XDG_CONFIG_HOME=str(private / "config"),
            XDG_DATA_HOME=str(private / "data"),
            XDG_STATE_HOME=str(private / "state"),
            XDG_CACHE_HOME=str(private / "cache"),
        )
        res = run_qs(shell, env, timeout=30)
        bad = ("EXERCISES_TRACKER_CONTRAST_FAIL", "ReferenceError", "TypeError")
        if res.returncode != 0 or "EXERCISES_TRACKER_CONTRAST_PASS" not in res.stdout or any(t in res.stdout for t in bad):
            print(res.stdout)
            raise SystemExit(1)
        for line in res.stdout.splitlines():
            if "CASE_PASS" in line or "EXERCISES_TRACKER_CONTRAST_PASS" in line:
                print(line.strip())


if __name__ == "__main__":
    main()
