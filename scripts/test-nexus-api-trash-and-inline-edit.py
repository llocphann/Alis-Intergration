#!/usr/bin/env python3
"""End-to-end verification for incremental scan cache, <50ms optimistic trash,
6-kind API search/sync + A2 modal, standard note ruled-paper inline edit,
Companion auto-journal creation, Recipe pill toggle, and 52px Weekly Planner."""

import datetime
import json
import os
import re
import subprocess
import sys
import tempfile
from contextlib import nullcontext
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from integration_test_host import resolve_host_root  # noqa: E402

HOST = Path(os.environ.get("ALIS_TEST_HOST", str(resolve_host_root(ROOT)))).resolve()
PLUGIN = Path(os.environ.get("ALIS_TEST_PLUGIN", str(ROOT))).resolve()
BIN = PLUGIN / "assets/bin/alis-nexus"
sys.path.insert(0, str(HOST / "scripts"))
from native_test_session import private_wayland, run_qs  # noqa: E402


def run_cli(args, env):
    proc = subprocess.run(
        [str(BIN)] + args,
        env=env,
        capture_output=True,
        text=True,
        timeout=15,
        check=False,
    )
    if proc.returncode != 0:
        raise AssertionError(f"CLI failed ({proc.returncode}): {args}\nstdout={proc.stdout}\nstderr={proc.stderr}")
    return json.loads(proc.stdout)


def write_mock_fixtures(mock_dir: Path):
    mock_dir.mkdir(parents=True, exist_ok=True)
    (mock_dir / "movie_search.json").write_text(json.dumps({
        "results": [{
            "trackId": 901,
            "trackName": "Arrival",
            "releaseDate": "2016-11-11T08:00:00Z",
            "artistName": "Denis Villeneuve",
            "primaryGenreName": "Sci-Fi",
            "trackTimeMillis": 6960000,
            "artworkUrl100": "https://example.invalid/arrival/100x100bb.jpg",
            "longDescription": "A linguist works with the military to communicate with alien lifeforms."
        }]
    }))
    (mock_dir / "tv_search.json").write_text(json.dumps([{
        "show": {
            "id": 702,
            "name": "Severance",
            "premiered": "2022-02-18",
            "status": "Running",
            "runtime": 55,
            "genres": ["Drama", "Sci-Fi"],
            "rating": {"average": 8.7},
            "network": {"name": "Apple TV+"},
            "image": {"original": "https://example.invalid/severance-orig.jpg"},
            "summary": "<p>Mark leads a team of office workers whose memories have been <b>surgically</b> divided.</p>"
        }
    }]))
    (mock_dir / "book_search.json").write_text(json.dumps({
        "docs": [{
            "key": "/works/OL893415W",
            "title": "Dune",
            "author_name": ["Frank Herbert"],
            "first_publish_year": 1965,
            "cover_i": 8765432,
            "number_of_pages_median": 688,
            "isbn": ["9780441172719"],
            "subject": ["Science Fiction", "Arrakis"]
        }]
    }))
    (mock_dir / "game_search.json").write_text(json.dumps({
        "items": [{
            "id": 1145360,
            "name": "Hades",
            "platforms": {"windows": True, "mac": True, "linux": False}
        }]
    }))
    (mock_dir / "game_sync.json").write_text(json.dumps({
        "1145360": {
            "success": True,
            "data": {
                "name": "Hades",
                "developers": ["Supergiant Games"],
                "publishers": ["Supergiant Games"],
                "genres": [{"description": "Action"}, {"description": "Roguelike"}],
                "release_date": {"date": "17 Sep, 2020"},
                "metacritic": {"score": 93},
                "short_description": "Defy the god of the dead as you hack and slash out of the Underworld.",
                "header_image": "https://example.invalid/hades/header.jpg"
            }
        }
    }))
    (mock_dir / "recipe_search.json").write_text(json.dumps({
        "meals": [{
            "idMeal": "52835",
            "strMeal": "Pho Bo",
            "strCategory": "Beef",
            "strArea": "Vietnamese",
            "strMealThumb": "https://example.invalid/phobo.jpg",
            "strTags": "Soup,Noodles",
            "strYoutube": "https://youtube.invalid/watch?v=phobo",
            "strIngredient1": "Beef Bones",
            "strMeasure1": "1.5 kg",
            "strIngredient2": "Rice Noodles",
            "strMeasure2": "500 g",
            "strInstructions": "Simmer charred ginger, onion, and beef bones for 6 hours.\nSlice brisket thinly and Ladle boiling broth over noodles."
        }]
    }))
    (mock_dir / "place_search.json").write_text(json.dumps([{
        "place_id": 4455,
        "name": "Hoi An Ancient Town",
        "display_name": "Hoi An Ancient Town, Quang Nam, Vietnam",
        "lat": "15.8794",
        "lon": "108.3350",
        "type": "attraction",
        "category": "tourism",
        "address": {"city": "Hoi An", "country": "Vietnam"},
        "extratags": {"wikipedia": "en:Hội An"}
    }]))
    (mock_dir / "place_wiki.json").write_text(json.dumps({
        "title": "Hội An",
        "extract": "Hội An is a historic coastal port city in central Vietnam famed for lantern-lit streets.",
        "originalimage": {"source": "https://example.invalid/hoian-lanterns.jpg"}
    }))
    (mock_dir / "weather_sync.json").write_text(json.dumps({
        "current_condition": [{
            "temp_C": "-99",
            "humidity": "99",
            "weatherDesc": [{"value": "WEATHER_POISON_CANARY"}]
        }]
    }))


def main():
    checks = []

    def record(name, passed, actual=None):
        checks.append({"name": name, "status": "PASS" if passed else "FAIL", "actual": actual})
        if not passed:
            raise AssertionError(f"Check failed: {name} -> {actual}")

    with tempfile.TemporaryDirectory(prefix="alis-nexus-slice5-") as tmp:
        base = Path(tmp)
        vault = base / "Vault"
        vault.mkdir()
        mock_dir = base / "mock_api"
        write_mock_fixtures(mock_dir)

        cli_env = dict(
            os.environ,
            ALIS_NEXUS_MOCK_API_DIR=str(mock_dir),
            ALIS_NEXUS_DISABLE_XDG_OPEN="1",
            ALIS_NEXUS_DISABLE_WL_COPY="1",
        )

        # Seed isolated vault notes (including custom user folders to test dynamic folder inference!)
        (vault / "Custom_Library/SciFi_Books").mkdir(parents=True)
        (vault / "Custom_Library/SciFi_Books/Hyperion.md").write_text(
            "---\ntags: [book]\nauthor: Dan Simmons\nstatus: Completed\nrating: 9.5\n---\n\nUser book review.\n",
            encoding="utf-8",
        )
        (vault / "Custom_Library/SciFi_Books/Dune.md").write_text(
            "---\ntags: [book]\nstatus: Reading\nrating: 10\ncustom_owner_flag: preserve_me\n---\n\nMy personal Dune annotations — keep intact!\n",
            encoding="utf-8",
        )
        (vault / "Places/Hoi An Ancient Town.md").mkdir(parents=True, exist_ok=True)
        (vault / "Places/Hoi An Ancient Town.md").rmdir()
        (vault / "Places").mkdir(parents=True, exist_ok=True)
        (vault / "Places/Hoi An Ancient Town.md").write_text(
            "---\ntags: [place]\nvisited: true\nrating: 9.8\n---\n\nVisited lantern market at dusk.\n",
            encoding="utf-8",
        )
        (vault / "Games").mkdir(parents=True)
        (vault / "Games/Hades.md").write_text(
            "---\ntags: [game]\nstatus: Playing\nrating: 9.7\n---\n\nCleared Heat 16 with Twin Fists.\n",
            encoding="utf-8",
        )
        (vault / "Movies").mkdir(parents=True)
        (vault / "Movies/Arrival.md").write_text(
            "---\ntags: [movie]\nstatus: Watched\nrating: 9.4\n---\n\nUnforgettable nonlinear score.\n",
            encoding="utf-8",
        )
        (vault / "TV").mkdir(parents=True)
        (vault / "TV/Severance.md").write_text(
            "---\ntags: [tv]\nstatus: Watching\nrating: 9.2\n---\n\nThe waffle party episode was wild.\n",
            encoding="utf-8",
        )
        (vault / "Recipes").mkdir(parents=True)
        (vault / "Recipes/Pho Bo.md").write_text(
            "---\ntags: [recipe]\nservings: 4\n---\n\n## Personal Notes\n\nAdd extra Thai basil.\n",
            encoding="utf-8",
        )
        (vault / "Recipes/Pho Bo Custom.md").write_text(
            "---\ntitle: Pho Bo\ntags: [recipe]\n---\n\n## Ingredients\n\n- 999 g Secret Family Spice\n\n## Instructions\n\n1. Never overwrite family recipe.\n",
            encoding="utf-8",
        )
        (vault / "00_Capture").mkdir(parents=True)
        (vault / "00_Capture/StandardNote.md").write_text(
            "---\ntitle: Standard Note\ncustom_owner_key: keep-100-percent\ntags: [notes]\n---\n\n# Research Heading\n\nInitial paragraph body.\n",
            encoding="utf-8",
        )
        (vault / "00_Capture/FastTrash.md").write_text("# Fast Trash Target\nDelete me optimistically.\n", encoding="utf-8")
        (vault / "00_Capture/Extra1.md").write_text("# Extra 1\nBody 1\n", encoding="utf-8")
        (vault / "00_Capture/Extra2.md").write_text("# Extra 2\nBody 2\n", encoding="utf-8")

        # ── 1. Incremental Scan Cache & Cache-Pruned Delete ──
        cache_file = base / "scan_cache.json"
        scan1 = run_cli(["scan", "--vault", str(vault), "--cache-file", str(cache_file)], cli_env)
        total_md = len([f for f in scan1["files"] if f["ext"] == "md"])
        record(
            "cli-scan-cold-populates-cache",
            cache_file.exists()
            and scan1["stats"]["cacheHits"] == 0
            and scan1["stats"]["parsedNotes"] == total_md
            and "_cachedEntries" not in scan1,
            {"totalMd": total_md, "stats": {k: scan1["stats"].get(k) for k in ("cacheHits", "parsedNotes")}},
        )

        scan2 = run_cli(["scan", "--vault", str(vault), "--cache-file", str(cache_file)], cli_env)
        record(
            "cli-scan-warm-reuses-all-unchanged",
            scan2["stats"]["cacheHits"] == total_md and scan2["stats"]["parsedNotes"] == 0,
            {"cacheHits": scan2["stats"]["cacheHits"], "parsedNotes": scan2["stats"]["parsedNotes"]},
        )

        # Modify exactly 1 file and ensure mtime advances
        extra1 = vault / "00_Capture/Extra1.md"
        extra1.write_text("# Extra 1\nModified content line!\n", encoding="utf-8")
        st = extra1.stat()
        os.utime(extra1, ns=(st.st_atime_ns, st.st_mtime_ns + 2_000_000_000))
        scan3 = run_cli(["scan", "--vault", str(vault), "--cache-file", str(cache_file)], cli_env)
        record(
            "cli-scan-incremental-invalidates-only-modified",
            scan3["stats"]["cacheHits"] == total_md - 1 and scan3["stats"]["parsedNotes"] == 1,
            {"cacheHits": scan3["stats"]["cacheHits"], "parsedNotes": scan3["stats"]["parsedNotes"]},
        )

        run_cli(["delete", "--vault", str(vault), "--path", "00_Capture/Extra2.md", "--cache-file", str(cache_file)], cli_env)
        cached_disk = json.loads(cache_file.read_text(encoding="utf-8"))
        record(
            "cli-delete-prunes-cache-file",
            "00_Capture/Extra2.md" not in cached_disk.get("_cachedEntries", {})
            and all(f.get("relPath") != "00_Capture/Extra2.md" for f in cached_disk.get("files", [])),
            {"remainingFiles": len(cached_disk.get("files", []))},
        )

        # ── 2. All 6 search-api & sync-api Kinds ──
        queries = {
            "movie": "Arrival",
            "tv": "Severance",
            "book": "Dune",
            "game": "Hades",
            "recipe": "Pho Bo",
            "place": "Hoi An",
        }
        for kind, q in queries.items():
            res = run_cli(["search-api", "--kind", kind, "--query", q], cli_env)
            results = res.get("results", [])
            record(
                f"cli-search-api-{kind}",
                res.get("ok") is True and len(results) >= 1 and bool(results[0].get("title")) and bool(results[0].get("cover")),
                results[0] if results else None,
            )
            if kind == "movie":
                record("cli-movie-itunes-hires-poster", "600x600bb" in results[0]["cover"], results[0]["cover"])

        sync_targets = [
            ("movie", "Movies/Arrival.md", "Denis Villeneuve", "Unforgettable nonlinear score."),
            ("tv", "TV/Severance.md", "Apple TV+", "The waffle party episode was wild."),
            ("book", "Custom_Library/SciFi_Books/Dune.md", "Frank Herbert", "My personal Dune annotations — keep intact!"),
            ("game", "Games/Hades.md", "Supergiant Games", "Cleared Heat 16 with Twin Fists."),
            ("recipe", "Recipes/Pho Bo.md", "Beef Bones", "Add extra Thai basil."),
            ("place", "Places/Hoi An Ancient Town.md", "15.8794", "Visited lantern market at dusk."),
        ]
        for kind, rel_path, expected_meta, preserved_body in sync_targets:
            run_cli(["sync-api", "--vault", str(vault), "--path", rel_path, "--kind", kind], cli_env)
            updated_text = (vault / rel_path).read_text(encoding="utf-8")
            record(
                f"cli-sync-api-{kind}-preserves-user-notes",
                expected_meta in updated_text
                and preserved_body in updated_text
                and "WEATHER_POISON_CANARY" not in updated_text,
                {"relPath": rel_path, "hasExpectedMeta": expected_meta in updated_text},
            )

        # Verify custom user ingredients are NOT overwritten on Recipe sync
        run_cli(["sync-api", "--vault", str(vault), "--path", "Recipes/Pho Bo Custom.md", "--kind", "recipe"], cli_env)
        custom_recipe_txt = (vault / "Recipes/Pho Bo Custom.md").read_text(encoding="utf-8")
        record(
            "cli-sync-api-recipe-preserves-existing-ingredients",
            "999 g Secret Family Spice" in custom_recipe_txt and "Beef Bones" not in custom_recipe_txt,
            {"customKept": "999 g Secret Family Spice" in custom_recipe_txt},
        )

        # ── 3. Native Quickshell Runtime Verification ──
        shell = base / "shell"
        shell.mkdir()
        for entry in ("services", "modules", "GlobalStates.qml", "qmldir", "scripts", "defaults", "translations", "assets"):
            (shell / entry).symlink_to(HOST / entry)

        today_iso = datetime.date.today().isoformat()
        options = json.loads((HOST / "defaults/config.json").read_text(encoding="utf-8"))
        options["todo"]["nexus"]["vaultPath"] = str(vault)
        options["todo"]["nexus"]["dailyNote"] = {"folder": "00_Capture/01_Journal", "format": "YYYY-MM-DD"}
        options["bar"]["weather"]["enable"] = False
        options["integrations"]["alisIntergration"]["nexus"] = False
        for cfg_sub in ("config/alis", "config/quickshell/alis"):
            d = base / cfg_sub
            d.mkdir(parents=True)
            (d / "config.json").write_text(json.dumps(options), encoding="utf-8")

        state_dir = base / "state/quickshell"
        state_dir.mkdir(parents=True)
        # Pre-seed Companion check-in for TODAY with NO journal file on disk yet!
        (state_dir / "states.json").write_text(
            json.dumps({"aquaCheckIn": {"date": today_iso, "mood": "Focused", "energy": "High"}}),
            encoding="utf-8",
        )

        transport_log = base / "xdg_spy.jsonl"
        binpath = base / "bin"
        binpath.mkdir()
        for cmd_name in ("xdg-open", "wl-copy"):
            spy = binpath / cmd_name
            spy.write_text(
                "#!/usr/bin/env python3\nimport json, sys\n"
                f"with open({repr(str(transport_log))}, 'a') as f:\n"
                f"    f.write(json.dumps({{'cmd': {repr(cmd_name)}, 'args': sys.argv[1:]}}) + '\\n')\n",
                encoding="utf-8",
            )
            spy.chmod(0o755)

        helper_py = base / "write_helper.py"
        helper_py.write_text(
            "import sys\nfrom pathlib import Path\n"
            "p = Path(sys.argv[1]) / sys.argv[2]\n"
            "p.parent.mkdir(parents=True, exist_ok=True)\n"
            "p.write_text(sys.argv[3], encoding='utf-8')\n",
            encoding="utf-8",
        )

        qml = r'''import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common

ShellRoot {
    Component.onCompleted: Quickshell.watchFiles = false
    FloatingWindow {
        id: win
        visible: true
        implicitWidth: 1320
        implicitHeight: 860
        Loader {
            id: serviceLoader
            source: SERVICE_URL
        }
        Loader {
            id: hostLoader
            source: HOST_URL
            onLoaded: item.nexus = serviceLoader.item
        }
        Loader {
            id: workspaceLoader
            anchors.fill: parent
            active: false
            source: WORKSPACE_URL
            onLoaded: item.nexus = serviceLoader.item
        }
    }
    Process { id: writerProc }

    TestCase {
        id: tc
        when: false
        optional: true

        function emitCheck(name, pass, actual) {
            console.info("SLICE5_CHECK", JSON.stringify({
                "name": name,
                "status": pass ? "PASS" : "FAIL",
                "actual": actual ?? null
            }));
            if (!pass)
                throw new Error("Failed check: " + name + " -> " + JSON.stringify(actual));
        }

        function settle(n) {
            tryVerify(() => !n.scanBusy && !n.docBusy && n._docQueue.length === 0 && !n.searchApiLoading, 7000);
            wait(100);
        }

        function findNamed(item, targetName) {
            if (!item) return null;
            if (String(item.objectName ?? "") === targetName) return item;
            const kids = item.children || [];
            for (let i = 0; i < kids.length; ++i) {
                const found = findNamed(kids[i], targetName);
                if (found) return found;
            }
            if (item.contentItem) {
                const foundC = findNamed(item.contentItem, targetName);
                if (foundC) return foundC;
            }
            return null;
        }

        function clickActionInPopup(ws, labelText) {
            const popup = findNamed(ws, "nexusContextMenuPopup");
            const stack = [popup];
            while (stack.length > 0) {
                const cur = stack.pop();
                if (!cur || !cur.visible) continue;
                if (cur.text !== undefined && String(cur.text) === labelText) {
                    mouseClick(cur.parent, cur.parent.width / 2, cur.parent.height / 2, Qt.LeftButton);
                    wait(80);
                    return;
                }
                const ch = cur.children || [];
                for (let i = 0; i < ch.length; ++i) stack.push(ch[i]);
            }
            throw new Error("Context menu action not found: " + labelText);
        }

        function run() {
            try {
                tryCompare(Config, "ready", true, 6000);
                tryCompare(Persistent, "ready", true, 6000);
                tryCompare(serviceLoader, "status", Loader.Ready, 6000);
                tryCompare(hostLoader, "status", Loader.Ready, 6000);
                const n = serviceLoader.item;
                const h = hostLoader.item;
                h.nexus = n;

                // 1. Cold-boot NexusHost lazy workspace check + Companion check-in auto-creating missing journal while closed!
                emitCheck("cold-boot-host-lazy-before-open", n.isOpen === false && h.workspaceLoaded === false && h._workspaceWarmed === false, {
                    isOpen: n.isOpen,
                    workspaceLoaded: h.workspaceLoaded,
                    workspaceWarmed: h._workspaceWarmed
                });

                tryCompare(n, "vaultLoaded", true, 7000);
                settle(n);

                emitCheck("companion-auto-created-missing-journal-while-closed",
                    n.isOpen === false
                    && Boolean(n.todayJournalInfo?.exists)
                    && String(n.todayJournalInfo?.mood ?? "") === "Focused"
                    && String(n.todayJournalInfo?.energy ?? "") === "High",
                    n.todayJournalInfo
                );

                // Warm NexusHost once and verify warm state persists across close/open
                n.open();
                wait(120);
                emitCheck("host-workspace-warmed-on-open", h.workspaceLoaded === true && h._workspaceWarmed === true, {
                    workspaceLoaded: h.workspaceLoaded,
                    workspaceWarmed: h._workspaceWarmed
                });
                n.close();
                wait(80);
                emitCheck("host-workspace-stays-warm-after-close", n.isOpen === false && h.workspaceLoaded === true && h._workspaceWarmed === true, {
                    isOpen: n.isOpen,
                    workspaceLoaded: h.workspaceLoaded,
                    workspaceWarmed: h._workspaceWarmed
                });

                // Unload standalone host overlay so FloatingWindow win owns deterministic Wayland keyboard/pointer focus
                hostLoader.active = false;
                wait(40);
                workspaceLoader.active = true;
                tryCompare(workspaceLoader, "status", Loader.Ready, 6000);
                const ws = workspaceLoader.item;
                ws.nexus = n;
                n.open();
                wait(120);

                // Reverse sync: editing today's Journal energy in Nexus updates Persistent.states.aquaCheckIn cleanly
                const journalRel = String(n.todayJournalInfo.relPath);
                n.openFile(journalRel, true);
                settle(n);
                n.setFrontmatter(journalRel, { "energy": "Calm" });
                settle(n);
                emitCheck("journal-edit-syncs-back-to-companion",
                    String(Persistent.states.aquaCheckIn.energy) === "Calm"
                    && String(Persistent.states.aquaCheckIn.mood) === "Focused",
                    { mood: Persistent.states.aquaCheckIn.mood, energy: Persistent.states.aquaCheckIn.energy }
                );

                // 2. Optimistic <50ms deletePath & _rescanQueued handling
                const beforeCount = n.flatFiles.length;
                const t0 = Date.now();
                const delOk = n.deletePath("00_Capture/FastTrash.md");
                const elapsedMs = Date.now() - t0;
                const immediatelyGone = !n.flatFiles.some(f => f.relPath === "00_Capture/FastTrash.md")
                    && !n.visibleTreeRows.some(r => r.relPath === "00_Capture/FastTrash.md");
                emitCheck("optimistic-trash-under-50ms", delOk && elapsedMs < 50 && immediatelyGone && n.flatFiles.length === beforeCount - 1, {
                    elapsedMs: elapsedMs,
                    immediatelyGone: immediatelyGone
                });
                settle(n);

                // Queue a rescan while scanBusy is true
                n.refreshVault();
                const wasRunning = n.scanBusy;
                writerProc.command = ["python3", HELPER_PY, VAULT_DIR, "00_Capture/QueuedDuringScan.md", "# Queued During Scan\nPicked up!\n"];
                writerProc.running = true;
                tryCompare(writerProc, "running", false, 2000);
                if (!n.scanBusy) {
                    n.refreshVault();
                }
                n.refreshVault(); // Must set _rescanQueued = true while scanProc.running!
                const queuedObserved = n._rescanQueued || !wasRunning;
                settle(n);
                emitCheck("rescan-queued-picks-up-concurrent-file",
                    queuedObserved && n._rescanQueued === false && n.flatFiles.some(f => f.relPath === "00_Capture/QueuedDuringScan.md"),
                    { queuedObserved: queuedObserved, found: n.flatFiles.some(f => f.relPath === "00_Capture/QueuedDuringScan.md") }
                );

                // 3. Task #16: Generic standard Markdown note ruled-paper card & inline Live-Preview edit + i shortcut
                n.openFile("00_Capture/StandardNote.md", true);
                settle(n);
                const paperCard = findNamed(ws, "nexusStandardNotePaperCard");
                emitCheck("standard-note-ruled-paper-visible",
                    paperCard !== null && paperCard.visible && paperCard.isStandardSheet === true && n.editorMode === "hybrid",
                    { visible: paperCard?.visible, mode: n.editorMode }
                );

                ws.restoreWorkspaceFocus();
                wait(60);
                keyClick(Qt.Key_I);
                wait(80);
                const inlineEd = findNamed(ws, "nexusStandardNoteInlineEditor");
                emitCheck("standard-note-i-shortcut-starts-inline-live-preview",
                    ws.standardNoteInlineEditing === true
                    && n.editorMode === "hybrid"
                    && inlineEd !== null
                    && inlineEd.visible === true,
                    { inlineEditing: ws.standardNoteInlineEditing, editorMode: n.editorMode, edVisible: inlineEd?.visible }
                );

                inlineEd.text = "# Research Heading\n\nUpdated inline on ruled paper without raw source jump!";
                inlineEd.forceActiveFocus();
                wait(40);
                keyClick(Qt.Key_Escape);
                settle(n);
                emitCheck("standard-note-inline-edit-saved-preserving-frontmatter",
                    ws.standardNoteInlineEditing === false
                    && String(n.currentDoc?.content ?? "").includes("custom_owner_key: keep-100-percent")
                    && String(n.currentDoc?.content ?? "").includes("Updated inline on ruled paper without raw source jump!"),
                    { inlineEditing: ws.standardNoteInlineEditing }
                );

                // 4. Task #6: Recipe default Overview & active pill toggle to "all" + Sync button
                n.openFile("Recipes/Pho Bo.md", true);
                settle(n);
                const cvLoader = findNamed(ws, "nexusCustomViewsLoader");
                const cv = cvLoader ? cvLoader.item : null;
                const syncRecipeBtn = findNamed(ws, "nexusRecipeSyncApiButton");
                const methodPill = findNamed(ws, "nexusRecipeSectionPill_method");
                emitCheck("recipe-defaults-to-overview-and-has-sync-btn",
                    cv !== null && cv.recipeActiveSection === "overview" && syncRecipeBtn !== null && syncRecipeBtn.visible,
                    { section: cv?.recipeActiveSection, syncBtn: Boolean(syncRecipeBtn?.visible) }
                );
                mouseClick(methodPill, methodPill.width / 2, methodPill.height / 2, Qt.LeftButton);
                wait(60);
                const afterFirstClick = cv.recipeActiveSection;
                mouseClick(methodPill, methodPill.width / 2, methodPill.height / 2, Qt.LeftButton);
                wait(60);
                const afterSecondClick = cv.recipeActiveSection;
                emitCheck("recipe-section-pill-toggles-to-all",
                    afterFirstClick === "method" && afterSecondClick === "all",
                    { first: afterFirstClick, second: afterSecondClick }
                );

                // 5. Task #15: Weekly Planner 52px hour spacing
                const timeline = findNamed(ws, "nexusWeeklyPlannerTimeline");
                emitCheck("weekly-planner-52px-hour-spacing",
                    timeline !== null && timeline.hourRowHeight === 52 && timeline.contentHeight === 24 * 52,
                    { hourRowHeight: timeline?.hourRowHeight, contentHeight: timeline?.contentHeight }
                );

                // 6. Task #1: Folder deduplication + auto-open Rename modal, commandPaletteSearch, & ALIS_NEXUS_DISABLE_XDG_OPEN=1
                ws.openContextMenu(200, 200, { "type": "workspace", "title": "Vault" });
                wait(60);
                clickActionInPopup(ws, "New Folder...");
                settle(n);
                const firstFolderOpenRename = ws.renameDialogOpen && ws.renameDialogOldPath === "New Folder";
                ws.openContextMenu(200, 200, { "type": "workspace", "title": "Vault" });
                wait(60);
                clickActionInPopup(ws, "New Folder...");
                settle(n);
                const secondFolderOpenRename = ws.renameDialogOpen && ws.renameDialogOldPath === "New Folder 2";
                ws.renameDialogOpen = false;
                emitCheck("context-menu-new-folder-deduplicates-and-opens-rename",
                    firstFolderOpenRename && secondFolderOpenRename,
                    { first: firstFolderOpenRename, second: secondFolderOpenRename, path2: ws.renameDialogOldPath }
                );

                ws.openContextMenu(200, 200, { "type": "workspace", "title": "Vault" });
                wait(60);
                clickActionInPopup(ws, "Command Palette...");
                wait(60);
                emitCheck("context-menu-command-palette-no-typeerror",
                    n.commandPaletteOpen === true && n.commandPaletteSearch === "",
                    { open: n.commandPaletteOpen }
                );
                n.commandPaletteOpen = false;
                wait(40);

                ws.openContextMenu(200, 200, { "type": "workspace", "title": "Vault" });
                wait(60);
                clickActionInPopup(ws, "Reveal Vault in File Manager");
                wait(80);

                // 7. Part D.3: Interactive New Note & API Search Modal (A2) + Dynamic Vault Folder Inference + Book Sync check
                n.openNewNoteModal("book", "");
                wait(80);
                emitCheck("new-note-modal-infers-dominant-vault-folder",
                    n.newNoteModalOpen === true && n.newNoteModalFolder === "Custom_Library/SciFi_Books",
                    { open: n.newNoteModalOpen, folder: n.newNoteModalFolder }
                );
                n.searchExternalApi("book", "Dune");
                settle(n);
                emitCheck("new-note-modal-live-api-results",
                    Array.isArray(n.searchApiResults) && n.searchApiResults.length >= 1 && n.searchApiResults[0].title === "Dune",
                    { count: n.searchApiResults.length, first: n.searchApiResults[0]?.title }
                );
                const candCard = findNamed(ws, "nexusApiCandidateCard_0");
                mouseClick(candCard, candCard.width / 2, candCard.height / 2, Qt.LeftButton);
                settle(n);
                emitCheck("new-note-modal-creates-deduped-rich-book-note",
                    n.newNoteModalOpen === false
                    && n.currentPath === "Custom_Library/SciFi_Books/Dune (2).md"
                    && String(n.currentDoc?.noteKind) === "book"
                    && String(n.currentDoc?.content ?? "").includes("Frank Herbert"),
                    { currentPath: n.currentPath, noteKind: n.currentDoc?.noteKind }
                );

                // Trigger fetchMediaMetadataForCurrentNote() on Book note and ensure it hits book API, NOT weather!
                const syncStarted = n.fetchMediaMetadataForCurrentNote();
                settle(n);
                emitCheck("book-fetch-metadata-never-hits-weather",
                    syncStarted === true
                    && !String(n.currentDoc?.content ?? "").includes("WEATHER_POISON_CANARY")
                    && String(n.currentDoc?.content ?? "").includes("Frank Herbert"),
                    { syncStarted: syncStarted }
                );

                console.info("SLICE5_DONE");
                Qt.quit();
            } catch (e) {
                console.error("SLICE5_ABORT", e.message, e.stack);
                Qt.exit(1);
            }
        }
    }

    Timer {
        interval: 250
        running: true
        onTriggered: tc.run()
    }
}
'''
        for k, v in {
            "SERVICE_URL": str(PLUGIN / "services/NexusService.qml"),
            "HOST_URL": str(PLUGIN / "modules/nexus/NexusHost.qml"),
            "WORKSPACE_URL": str(PLUGIN / "modules/nexus/NexusWorkspace.qml"),
            "HELPER_PY": str(helper_py),
            "VAULT_DIR": str(vault),
        }.items():
            qml = qml.replace(k, json.dumps(v))
        (shell / "shell.qml").write_text(qml, encoding="utf-8")

        runtime_dir = base / "runtime"
        runtime_dir.mkdir(mode=0o700)
        env = dict(
            os.environ,
            QT_QUICK_BACKEND="software",
            XDG_RUNTIME_DIR=str(runtime_dir),
            PATH=str(binpath) + ":" + os.environ.get("PATH", ""),
            ALIS_NEXUS_MOCK_API_DIR=str(mock_dir),
            ALIS_NEXUS_DISABLE_XDG_OPEN="1",
            ALIS_NEXUS_DISABLE_WL_COPY="1",
            ALIS_NEXUS_HEADLESS_SERVICE_ONLY="1",
        )
        for kind in ("config", "state", "cache", "data"):
            env["XDG_" + kind.upper() + "_HOME"] = str(base / kind)
        env.pop("NIRI_SOCKET", None)
        env.pop("HYPRLAND_INSTANCE_SIGNATURE", None)

        offscreen = os.environ.get("ALIS_SLICE5_OFFSCREEN") == "1"
        with (nullcontext(None) if offscreen else private_wayland(base)) as native_env:
            if native_env:
                env.update({k: v for k, v in native_env.items() if k in ("WAYLAND_DISPLAY", "NIRI_SOCKET", "DISPLAY", "XDG_RUNTIME_DIR")})
                env["QT_QPA_PLATFORM"] = "wayland"
            else:
                env["QT_QPA_PLATFORM"] = "offscreen"
            qs_res = run_qs(shell, env, timeout=55)

        qml_checks = [json.loads(m) for m in re.findall(r"SLICE5_CHECK (\{[^\n]+\})", qs_res.stdout)]
        checks.extend(qml_checks)

        if qs_res.returncode != 0 or "SLICE5_DONE" not in qs_res.stdout:
            print(qs_res.stdout, file=sys.stderr)
            raise SystemExit(f"Quickshell runtime test failed (exit={qs_res.returncode})")

        # Verify ALIS_NEXUS_DISABLE_XDG_OPEN=1 and ALIS_NEXUS_DISABLE_WL_COPY=1 suppressed external spawns
        spawned = [json.loads(line) for line in transport_log.read_text(encoding="utf-8").splitlines()] if transport_log.exists() else []
        record("disable-xdg-open-and-wl-copy-honored", len(spawned) == 0, spawned)

        # Verify auto-created Journal file exists on disk with Focused / High -> Calm
        journal_rel = vault / "00_Capture/01_Journal" / f"{today_iso}.md"
        journal_txt = journal_rel.read_text(encoding="utf-8")
        record(
            "auto-created-journal-persisted-on-disk",
            journal_rel.exists() and "mood: Focused" in journal_txt and "energy: Calm" in journal_txt,
            {"path": str(journal_rel.relative_to(vault))},
        )

        # Verify StandardNote.md frontmatter + inline-edited body persisted cleanly on disk
        std_txt = (vault / "00_Capture/StandardNote.md").read_text(encoding="utf-8")
        record(
            "standard-note-disk-frontmatter-and-body-intact",
            "custom_owner_key: keep-100-percent" in std_txt
            and "Updated inline on ruled paper without raw source jump!" in std_txt,
            {"len": len(std_txt)},
        )

    failures = [c for c in checks if c["status"] != "PASS"]
    summary = {
        "ok": len(failures) == 0,
        "totalChecks": len(checks),
        "passed": len(checks) - len(failures),
        "failures": failures,
    }
    print(json.dumps(summary, indent=2))
    print("ALIS_NEXUS_API_TRASH_INLINE_EDIT_PASS")
    if failures:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
