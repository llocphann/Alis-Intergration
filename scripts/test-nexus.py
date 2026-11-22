#!/usr/bin/env python3
"""Regression and headless QML runtime tests for Alis Nexus (alis-nexus Rust engine + QML workspace)."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

from integration_test_host import resolve_host_root

ROOT = Path(__file__).resolve().parents[1]
HOST = resolve_host_root(ROOT)
sys.path.insert(0, str(HOST / "scripts"))
from native_test_session import run_qs, private_wayland

BIN = ROOT / "assets/bin/alis-nexus"


def run_cli(*args, stdin_text=None, check=True, env_override=None):
    proc = subprocess.run(
        [str(BIN), *args],
        input=stdin_text,
        text=True,
        capture_output=True,
        timeout=15,
        env=env_override,
    )
    if check and proc.returncode != 0:
        raise AssertionError(f"alis-nexus {args} failed ({proc.returncode}): {proc.stdout} {proc.stderr}")
    return json.loads(proc.stdout), proc.returncode


def test_rust_engine():
    assert BIN.is_file() and os.access(BIN, os.X_OK), f"Missing executable {BIN}"
    assert BIN.stat().st_size < 2 * 1024 * 1024, "alis-nexus binary exceeds 2 MB release limit"

    with tempfile.TemporaryDirectory(prefix="alis-nexus-engine-") as tmp:
        vault = Path(tmp) / "Nexus-Vault"
        (vault / "00_Capture/01_Journal/2026/November").mkdir(parents=True)
        (vault / "00_Capture/03_Zettelkasten").mkdir(parents=True)
        (vault / "10_Projects").mkdir(parents=True)
        (vault / "20_Notes").mkdir(parents=True)
        (vault / "30_Assets").mkdir(parents=True)

        # Create markdown notes with wikilinks, tags, foldable blocks, callouts, tables, flashcards
        (vault / "10_Projects/NexusSpec.md").write_text(
            "---\n"
            "title: \"Nexus Spec\"\n"
            "tags: [nexus, architecture]\n"
            "aliases: [AlisNexus]\n"
            "---\n\n"
            "# Architecture\n"
            "- Parent block linking to [[OutlinerGuide|Outliner]] and #rust\n"
            "  - Indented child block 1\n"
            "  - [ ] Indented task open\n"
            "- [x] Completed root task\n\n"
            "> [!TIP] Performance\n"
            "> Powered by Rust.\n\n"
            "| Layer | Tech |\n"
            "| --- | --- |\n"
            "| Backend | Rust |\n\n"
            "Q: What powers Alis Nexus? :: Rust and Quickshell\n",
            encoding="utf-8",
        )
        (vault / "20_Notes/OutlinerGuide.md").write_text(
            "# Outliner Guide\n"
            "Backlink to [[NexusSpec]] and hybrid block folding.\n",
            encoding="utf-8",
        )
        (vault / "20_Notes/MentionNote.md").write_text(
            "# Mention Note\n"
            "This paragraph mentions Nexus Spec without brackets.\n",
            encoding="utf-8",
        )
        # Code file, Image file, Built-in PDF file, and Unsupported External file
        (vault / "10_Projects/demo.rs").write_text("fn main() { println!(\"hello\"); }\n", encoding="utf-8")
        (vault / "30_Assets/diagram.svg").write_text("<svg xmlns=\"http://www.w3.org/2000/svg\"/>\n", encoding="utf-8")
        (vault / "30_Assets/paper.pdf").write_bytes(b"%PDF-1.4 synthetic pdf bytes")
        (vault / "30_Assets/archive.docx").write_bytes(b"PK\x03\x04synthetic docx")

        # 1. Scan vault (and verify ~/Nexus-Vault tilde expansion + vault-internal absolute path resolution)
        scan, _ = run_cli("scan", "--vault", str(vault))
        tilde_env = dict(os.environ, HOME=str(tmp))
        tilde_scan, _ = run_cli("scan", "--vault", "~/Nexus-Vault", env_override=tilde_env)
        assert tilde_scan["ok"] is True and tilde_scan["stats"]["noteCount"] == 3
        abs_doc, _ = run_cli("read", "--vault", "~/Nexus-Vault", "--path", str(vault / "10_Projects/NexusSpec.md"), env_override=tilde_env)
        assert abs_doc["ok"] is True and abs_doc["relPath"] == "10_Projects/NexusSpec.md"
        assert scan["ok"] is True
        assert scan["stats"]["noteCount"] == 3
        assert scan["stats"]["openTasks"] == 1
        assert scan["stats"]["doneTasks"] == 1
        assert scan["stats"]["codeCount"] == 1
        assert scan["stats"]["imageCount"] == 1
        assert scan["stats"]["externalCount"] == 1
        assert len(scan["stats"]["activityHeatmap"]) == 119
        assert len(scan["graph"]["nodes"]) == 3
        assert len(scan["graph"]["edges"]) == 2
        assert scan["homepageLocalGraph"]["nodes"][0]["id"] == "__homepage__"

        # 2. Read markdown note & verify hybrid outliner blocks, backlinks, unlinked mentions, localGraph
        doc, _ = run_cli("read", "--vault", str(vault), "--path", "10_Projects/NexusSpec.md")
        assert doc["category"] == "markdown"
        assert doc["title"] == "Nexus Spec"
        assert len(doc["backlinks"]) == 1
        assert doc["backlinks"][0]["relPath"] == "20_Notes/OutlinerGuide.md"
        assert len(doc["unlinkedMentions"]) == 1
        assert doc["unlinkedMentions"][0]["relPath"] == "20_Notes/MentionNote.md"
        assert len(doc["flashcards"]) == 1
        assert doc["flashcards"][0]["front"] == "Q: What powers Alis Nexus?"
        blocks = doc["blocks"]
        assert any(b["kind"] == "heading" and b["foldable"] is True for b in blocks)
        assert any(b["kind"] == "bullet" and b["foldable"] is True for b in blocks)
        assert any(b["kind"] == "callout" and b["calloutType"] == "TIP" for b in blocks)
        assert any(b["kind"] == "table" and len(b["tableRows"]) == 1 for b in blocks)

        # 3. Link unlinked mention
        mention_line = doc["unlinkedMentions"][0]["line"]
        run_cli("link-mention", "--vault", str(vault), "--source", "20_Notes/MentionNote.md", "--line", str(mention_line), "--target", "Nexus Spec")
        doc_after, _ = run_cli("read", "--vault", str(vault), "--path", "10_Projects/NexusSpec.md")
        assert len(doc_after["backlinks"]) == 2

        # 4. Toggle Todo & Update Block
        open_todo_line = next(b["lineStart"] for b in blocks if b["kind"] == "todo" and b["todoState"] == "TODO")
        toggled, _ = run_cli("toggle-todo", "--vault", str(vault), "--path", "10_Projects/NexusSpec.md", "--line", str(open_todo_line))
        assert toggled["openTasks"] == 0 and toggled["doneTasks"] == 2

        updated, _ = run_cli(
            "update-block",
            "--vault",
            str(vault),
            "--path",
            "20_Notes/OutlinerGuide.md",
            "--start",
            "2",
            "--end",
            "2",
            "--content",
            "Updated block linking to [[NexusSpec]].",
        )
        assert "Updated block linking to [[NexusSpec]]." in updated["content"]

        # 5. Daily journal & Calendar
        daily, _ = run_cli("daily", "--vault", str(vault), "--date", "2026-11-07")
        assert daily["ok"] is True and daily["category"] == "markdown"
        cal, _ = run_cli("calendar", "--vault", str(vault), "--year", "2026", "--month", "11")
        assert len(cal["cells"]) == 42
        assert any(c["dateStr"] == "2026-11-07" and c["hasJournal"] is True for c in cal["cells"])

        # 6. File categories: code, image, built-in pdf, external
        code_doc, _ = run_cli("read", "--vault", str(vault), "--path", "10_Projects/demo.rs")
        assert code_doc["category"] == "code" and code_doc["language"] == "rust"

        img_doc, _ = run_cli("read", "--vault", str(vault), "--path", "30_Assets/diagram.svg")
        assert img_doc["category"] == "image"

        pdf_doc, _ = run_cli("read", "--vault", str(vault), "--path", "30_Assets/paper.pdf")
        assert pdf_doc["category"] == "pdf" and pdf_doc["absPath"].endswith("30_Assets/paper.pdf")

        ext_doc, _ = run_cli("read", "--vault", str(vault), "--path", "30_Assets/archive.docx")
        assert ext_doc["category"] == "external" and ext_doc["absPath"].endswith("30_Assets/archive.docx")

        # 7. Path traversal rejection
        err_traversal, code = run_cli("read", "--vault", str(vault), "--path", "../outside.md", check=False)
        assert code != 0 and err_traversal["ok"] is False
        err_abs, code2 = run_cli("read", "--vault", str(vault), "--path", "/etc/passwd", check=False)
        assert code2 != 0 and err_abs["ok"] is False

        # 8. Multi-byte UTF-8 Vietnamese filenames, nested .git submodule skip, Daily Schedule, and .obsidian/hotkeys.json
        (vault / "20_Notes/Sự_im_lặng.md").write_text("# Sự im lặng\nBài viết tiếng Việt.\n", encoding="utf-8")
        subrepo = vault / "10_Projects/NestedRepo"
        (subrepo / ".git").mkdir(parents=True)
        (subrepo / "README.md").write_text("# Should be skipped because of .git\n", encoding="utf-8")

        (vault / "90_System/93_Configuration").mkdir(parents=True)
        (vault / "90_System/93_Configuration/settings.md").write_text(
            "---\nusername: llocphann\nvault_name: obsidian-vault\nstart_date: 2024-06-08\n---\n",
            encoding="utf-8",
        )
        (vault / "90_System/97_Daily_Schedule").mkdir(parents=True)
        for prefix in ("01_Monday", "02_Tuesday", "03_Wednesday", "04_Thursday", "05_Friday", "06_Saturday", "07_Sunday"):
            (vault / f"90_System/97_Daily_Schedule/{prefix}.md").write_text(
                "## **Daily Schedule**\n| Time | Activity |\n| --- | --- |\n| **06:00 - 07:00** | Deep Work<br>Focus |\n\n"
                "## **Calisthenics**\n| Exercise | Equipment | Set - reps | Rest |\n| --- | --- | --- | --- |\n| **Push-ups** | None | **4 x 20** | **120s** |\n\n"
                "## **Cardio**\n| Exercise | Duration | Intensity |\n| --- | --- | --- |\n| Running | 30 mins | Moderate |\n",
                encoding="utf-8",
            )
        (vault / ".obsidian").mkdir(parents=True)
        (vault / ".obsidian/hotkeys.json").write_text(
            json.dumps({
                "switcher:open": [{"modifiers": ["Alt"], "key": "Enter"}],
                "file-explorer:new-file": [{"modifiers": ["Mod"], "key": "n"}],
                "workspace:close": [{"modifiers": ["Alt"], "key": "w"}],
            }),
            encoding="utf-8",
        )

        scan2, _ = run_cli("scan", "--vault", str(vault))
        assert scan2["ok"] is True
        assert scan2["stats"]["userHost"] == "llocphann@obsidian-vault"
        assert scan2["stats"]["noteCount"] == 13  # 3 original + 1 daily + 1 Vietnamese + 1 settings.md + 7 weekday schedules (NestedRepo skipped!)
        assert scan2["dailySchedule"]["available"] is True
        assert len(scan2["dailySchedule"]["scheduleRows"]) == 1
        assert scan2["dailySchedule"]["scheduleRows"][0]["time"] == "06:00 - 07:00"
        assert scan2["dailySchedule"]["scheduleRows"][0]["activity"] == "Deep Work · Focus"
        assert len(scan2["dailySchedule"]["exerciseRows"]) == 1
        assert scan2["dailySchedule"]["exerciseRows"][0]["exercise"] == "Push-ups"
        assert scan2["dailySchedule"]["exerciseRows"][0]["reps"] == "4 x 20"
        assert scan2["dailySchedule"]["exerciseRows"][0]["sets"] == "120s"
        assert len(scan2["dailySchedule"]["cardioRows"]) == 1
        assert scan2["vaultHotkeys"]["switcher:open"]["primary"] == "Alt+Enter"
        assert scan2["vaultHotkeys"]["file-explorer:new-file"]["primary"] == "Ctrl+N"

        # 9. Safe trash delete command
        del_res, _ = run_cli("delete", "--vault", str(vault), "--path", "20_Notes/Sự_im_lặng.md")
        assert del_res["ok"] is True
        assert not (vault / "20_Notes/Sự_im_lặng.md").exists()
        assert (vault / ".trash").is_dir()

        # 10. Journal H2 Day Planner title fallback, Movie Dossier, Cornell Marginalia, and Tag/Category Graph Clusters
        (vault / "00_Capture/01_Journal").mkdir(parents=True, exist_ok=True)
        (vault / "00_Capture/01_Journal/01-08-2026-Saturday.md").write_text(
            "## Day Planner\n- [ ] 08:00 Morning workout\n\n```dataviewjs\ndv.view('widgets/progress-clock')\n```\n\n## Journal\nGreat day.\n",
            encoding="utf-8",
        )
        (vault / "30_Resources/31_Media/Movies").mkdir(parents=True, exist_ok=True)
        (vault / "30_Resources/31_Media/Movies/Fight Club (1999).md").write_text(
            "---\n"
            "type: movie\n"
            "title: Fight Club\n"
            "year: 1999\n"
            "dataSource: OMDbAPI\n"
            "id: tt0137523\n"
            "plot: An insomniac office worker and a soap maker form an underground club.\n"
            "genre:\n"
            "  - Drama\n"
            "  - Thriller\n"
            "director:\n"
            "  - David Fincher\n"
            "onlineRating: 8.8\n"
            "image: https://example.com/fightclub.jpg\n"
            "status: Watched\n"
            "tags:\n"
            "  - movies\n"
            "---\n\n"
            "Classic film.\n",
            encoding="utf-8",
        )
        (vault / "20_Notes/22_Cornell").mkdir(parents=True, exist_ok=True)
        (vault / "20_Notes/22_Cornell/Rust Ownership.md").write_text(
            "---\ncssclasses:\n  - cornell-note\ntags:\n  - cornell\n  - rust\n---\n"
            "# Rust Ownership\n\n### ?\nHow does borrow checking work?\n\n### !\nLifetimes are verified at compile time.\n\n### Summary\nZero-cost memory safety.\n",
            encoding="utf-8",
        )
        (vault / "90_System/91_Templates").mkdir(parents=True, exist_ok=True)
        (vault / "90_System/91_Templates/Cornell_Template.md").write_text(
            "---\ncssclasses:\n  - cornell-note\ntags:\n  - cornell\n---\n# <% noteTitle %>\n",
            encoding="utf-8",
        )

        (vault / ".obsidian/plugins/obsidian-icon-folder").mkdir(parents=True, exist_ok=True)
        (vault / ".obsidian/plugins/obsidian-icon-folder/data.json").write_text(
            json.dumps({
                "settings": {},
                "00_Capture": "LiInbox",
                "10_Projects": "LiDatabase",
                "20_Notes": "LiNotebookText",
                "30_Resources": "LiFilm",
                "90_System": "LiSettings",
            }),
            encoding="utf-8",
        )
        (vault / ".obsidian/graph.json").write_text(
            json.dumps({
                "colorGroups": [
                    {"query": "path:00_Capture", "color": {"a": 1, "rgb": 13346551}},
                    {"query": "path:20_Notes", "color": {"a": 1, "rgb": 16429959}},
                ]
            }),
            encoding="utf-8",
        )
        (vault / "90_System/92_Scripts").mkdir(parents=True, exist_ok=True)
        (vault / "90_System/92_Scripts/quotes.js").write_text(
            'const quotes = [{ text: "Simplicity is prerequisite for reliability.", author: "Edsger W. Dijkstra" }];\n',
            encoding="utf-8",
        )
        (vault / "90_System/93_Configuration").mkdir(parents=True, exist_ok=True)
        (vault / "90_System/93_Configuration/settings.md").write_text(
            "---\ncategory:\n  - Settings\ntmdb_api_key: test_tmdb_key\nweather_location: Ho Chi Minh\n---\n# Vault Settings\n",
            encoding="utf-8",
        )
        (vault / "30_Resources/32_Finance").mkdir(parents=True, exist_ok=True)
        (vault / "30_Resources/32_Finance/November_2026_Finance.md").write_text(
            "---\ncategories:\n  - Finance Report\n---\n"
            "# Finance Ledger\n\n"
            "## Income\n"
            "| Date | Source | Category | Amount |\n"
            "| --- | --- | --- | --- |\n"
            "| 2026-11-01 | Salary | Work | 25000000 |\n\n"
            "## Spending\n"
            "| Date | Item | Category | Amount |\n"
            "| --- | --- | --- | --- |\n"
            "| 2026-11-02 | Groceries | Food | 450000 |\n",
            encoding="utf-8",
        )

        scan3, _ = run_cli("scan", "--vault", str(vault))
        assert scan3["ok"] is True
        assert scan3["stats"]["vaultAgeFormatted"] != ""

        # Verify folder prefix color & custom icon mapping on tree.children
        tree_by_name = {n["name"]: n for n in scan3["tree"]["children"] if n["isDir"]}
        assert tree_by_name["00_Capture"]["colorHex"] == "#82c2cf"
        assert tree_by_name["00_Capture"]["iconName"] == "inbox"
        assert tree_by_name["10_Projects"]["colorHex"] == "#7bb5c1"
        assert tree_by_name["10_Projects"]["iconName"] == "database"
        assert tree_by_name["90_System"]["colorHex"] == "#3d484b"
        assert tree_by_name["90_System"]["iconName"] == "settings"

        # Verify allWeekdaysSchedule & financeSummary on scan
        assert "monday" in scan3["allWeekdaysSchedule"]
        assert scan3["financeSummary"]["available"] is True
        assert scan3["financeSummary"]["totalIncome"] == 25000000.0
        assert scan3["financeSummary"]["totalSpent"] == 450000.0

        # Verify journalView & quote extraction
        j_doc, _ = run_cli("read", "--vault", str(vault), "--path", "00_Capture/01_Journal/01-08-2026-Saturday.md")
        assert j_doc["title"] == "01-08-2026-Saturday", f"Expected stem title, got {j_doc['title']}"
        assert j_doc["noteKind"] == "journal"
        assert j_doc["journalView"]["quote"] == "Simplicity is prerequisite for reliability."
        assert not any(b["kind"] == "code" and "progress-clock" in b["text"] for b in j_doc["blocks"])

        # Verify set-frontmatter CLI command preserves markdown body and updates YAML keys
        fm_res, _ = run_cli(
            "set-frontmatter",
            "--vault",
            str(vault),
            "--path",
            "00_Capture/01_Journal/01-08-2026-Saturday.md",
            "--json",
            json.dumps({"mood": 5, "energy": 4, "Gratitude": "Clean Rust architecture"}),
        )
        assert fm_res["ok"] is True
        assert fm_res["frontmatter"]["mood"] == "5"
        assert fm_res["frontmatter"]["gratitude"] == "Clean Rust architecture"
        assert "Gratitude:" in fm_res["content"]

        # Verify sync-api --api quote CLI command
        sync_res, _ = run_cli(
            "sync-api",
            "--vault",
            str(vault),
            "--path",
            "00_Capture/01_Journal/01-08-2026-Saturday.md",
            "--api",
            "quote",
        )
        assert sync_res["ok"] is True
        assert sync_res["frontmatter"]["quote"] == "Simplicity is prerequisite for reliability."

        # Verify finance-add CLI command
        fin_res, _ = run_cli(
            "finance-add",
            "--vault",
            str(vault),
            "--path",
            "30_Resources/32_Finance/November_2026_Finance.md",
            "--kind",
            "spending",
            "--date",
            "2026-11-03",
            "--description",
            "Coffee",
            "--category",
            "Food",
            "--amount",
            "50000",
        )
        assert fin_res["ok"] is True
        assert fin_res["financeSummary"]["totalSpent"] == 500000.0
        assert fin_res["financeSummary"]["balance"] == 24500000.0

        m_doc, _ = run_cli("read", "--vault", str(vault), "--path", "30_Resources/31_Media/Movies/Fight Club (1999).md")
        assert m_doc["noteKind"] == "movie"
        assert m_doc["dossier"]["score"] == "8.8"
        assert m_doc["dossier"]["director"] == "David Fincher"
        assert len(scan3["collections"]["movies"]) == 1

        c_doc, _ = run_cli("read", "--vault", str(vault), "--path", "20_Notes/22_Cornell/Rust Ownership.md")
        assert c_doc["noteKind"] == "cornell"
        assert len(c_doc["cornellView"]["pairs"]) >= 2
        assert "Zero-cost memory safety" in c_doc["cornellView"]["summaryHtml"]
        assert any(b["kind"] == "heading" and b["title"] == "?" and b["calloutType"] == "CORNELL_QUESTION" for b in c_doc["blocks"])
        assert any(b["kind"] == "heading" and b["title"] == "Summary" and b["calloutType"] == "CORNELL_SUMMARY" for b in c_doc["blocks"])
        assert len(scan3["collections"]["cornell"]) == 1  # Template in 91_Templates excluded!
        assert not any("91_Templates" in n["id"] or "<%" in n["title"] for n in scan3["graph"]["nodes"]), "Template notes must be excluded from vault graph nodes"
        assert not any("91_Templates" in n["id"] or "<%" in n["title"] for n in scan3["homepageLocalGraph"]["nodes"]), "Template notes must be excluded from homepageLocalGraph"
        assert not any("91_Templates" in n["relPath"] or "<%" in n["title"] for n in scan3["recentNotes"]), "Template notes must be excluded from recentNotes"
        assert not any("91_Templates" in n["id"] or "<%" in n["title"] for n in c_doc["localGraph"]["nodes"]), "Template notes must be excluded from document localGraph"
        assert all(0.05 <= n["x"] <= 0.95 and 0.05 <= n["y"] <= 0.95 for n in scan3["graph"]["nodes"]), "Graph node coordinates should be normalized without wall-clamping artifacts"


def test_qml_workspace_runtime():
    with tempfile.TemporaryDirectory(prefix="alis-nexus-qml-") as name:
        private = Path(name)
        shell = private / "shell"
        shell.mkdir()
        for entry in ("services", "modules", "GlobalStates.qml", "qmldir", "scripts", "defaults", "translations", "assets"):
            (shell / entry).symlink_to(HOST / entry)

        vault = private / "Vault"
        (vault / "10_Projects").mkdir(parents=True)
        (vault / "20_Notes").mkdir(parents=True)
        (vault / ".obsidian/plugins/obsidian-icon-folder").mkdir(parents=True)
        (vault / ".obsidian/plugins/obsidian-icon-folder/data.json").write_text(
            json.dumps({
                "10_Projects": "LiDatabase",
                "20_Notes": "LiNotebookText",
            }),
            encoding="utf-8",
        )
        (vault / ".obsidian/hotkeys.json").write_text(
            json.dumps({
                "command-palette:open": [{"modifiers": ["Alt"], "key": "Enter"}],
                "omnisearch:show-modal": [{"modifiers": ["Alt"], "key": "Escape"}],
                "quickadd:choice:e26ead52-86bc-4f2e-a0e4-d144cb7f3c4b": [{"modifiers": ["Alt"], "key": "t"}],
                "app:go-back": [
                    {"modifiers": ["Mod", "Alt"], "key": "ArrowLeft"},
                    {"modifiers": ["Alt"], "key": "h"},
                ],
            }),
            encoding="utf-8",
        )
        (vault / "10_Projects/Alpha.md").write_text(
            "---\ntitle: Alpha\ntags: [nexus]\n---\n# Heading 1\n- Parent item\n  - Child item\n- [ ] Task item\n\n### ?\nWhy use Cornell cues?\n",
            encoding="utf-8",
        )
        (vault / "20_Notes/Manual.pdf").write_bytes(b"%PDF-1.4 fixture")
        (vault / "20_Notes/Manual.docx").write_bytes(b"PK\x03\x04fixture")

        config = private / "config/alis"
        config.mkdir(parents=True)
        options = json.loads((HOST / "defaults/config.json").read_text())
        options["todo"]["nexus"]["vaultPath"] = str(vault)
        # Weather transitions are injected below. A real network response must
        # not race those values or add unrelated work to the paint-freeze gate.
        options["bar"]["weather"]["enable"] = False
        (config / "config.json").write_text(json.dumps(options))
        # Qt ConfigLocation includes the quickshell application directory.
        qt_config = private / "config/quickshell/alis"
        qt_config.mkdir(parents=True)
        (qt_config / "config.json").write_text(json.dumps(options))

        nexus_service_uri = str(ROOT / "services/NexusService.qml")
        nexus_workspace_uri = str(ROOT / "modules/nexus/NexusWorkspace.qml")
        nexus_settings_uri = str(ROOT / "modules/settings/NexusThemeSettings.qml")

        (shell / "shell.qml").write_text(
            f"""
import QtQuick
import QtTest
import Quickshell
import qs
import qs.services
import qs.modules.common

ShellRoot {{
    id: root
    Component.onCompleted: Quickshell.watchFiles = false
    FloatingWindow {{
        id: win
        visible: true
        implicitWidth: 1280
        implicitHeight: 820
        Loader {{
            id: serviceLoader
            source: "{nexus_service_uri}"
        }}
        Loader {{
            id: workspaceLoader
            anchors.fill: parent
            source: "{nexus_workspace_uri}"
            onLoaded: item.nexus = serviceLoader.item
        }}
        Loader {{
            id: settingsLoader
            width: 800
            visible: false
            source: "{nexus_settings_uri}"
        }}
        Loader {{
            id: bodyHostLoader
            width: 1200
            height: 700
            visible: false
            Component.onCompleted: setSource(Qt.resolvedUrl("modules/abyss/AbyssBodyHost.qml"), {{ edge: "bottom", identity: "nexus" }})
        }}
        Shortcut {{
            id: simulatedPerimeterEscapeShortcut
            sequences: ["Escape"]
            context: Qt.WindowShortcut
            enabled: Boolean(workspaceLoader.item && workspaceLoader.item.embeddedSurface && GlobalStates.abyssPerimeterActive)
            onActivated: {{
                if (workspaceLoader.item && !workspaceLoader.item.handleEscape() && workspaceLoader.item.nexus)
                    workspaceLoader.item.nexus.close()
            }}
        }}
    }}
    TestCase {{
        id: test
        when: false
        optional: true
        function check(v, msg) {{ if (!v) throw new Error(msg) }}
        function runChecks() {{
            try {{
                tryCompare(Config, "ready", true, 4000)
                check(Weather.enabled === false, "Weather network fetch must be disabled in the controlled fixture: " + Config.filePath)
                tryCompare(serviceLoader, "status", Loader.Ready, 4000)
                tryCompare(workspaceLoader, "status", Loader.Ready, 4000)
                tryCompare(settingsLoader, "status", Loader.Ready, 4000)
                const nexus = serviceLoader.item
                const ws = workspaceLoader.item
                const settingsPage = settingsLoader.item
                ws.nexus = nexus
                settingsPage.nexusOverride = nexus

                // Verify Settings UI controls exist (Workspace Card Layout section removed; Shortcut Editor behind sub-tab button)
                check(settingsPage.title === "Alis Nexus" && settingsPage.icon === "hub", "expected Alis Nexus card header")
                check(findChild(settingsPage, "openNexusOverlayButton") !== null, "missing openNexusOverlayButton")
                check(findChild(settingsPage, "openNexusWindowButton") !== null, "missing openNexusWindowButton")
                check(findChild(settingsPage, "openNexusDailyButton") !== null, "missing openNexusDailyButton")
                check(findChild(settingsPage, "resetNexusLayoutButton") === null, "resetNexusLayoutButton / Workspace Card Layout section must be removed")
                check(findChild(settingsPage, "openNexusShortcutsTabButton") !== null, "missing openNexusShortcutsTabButton")
                check(findChild(settingsPage, "syncNexusVaultShortcutsButton") !== null, "missing syncNexusVaultShortcutsButton")
                check(findChild(settingsPage, "resetNexusShortcutsButton") !== null, "missing resetNexusShortcutsButton")
                check(findChild(settingsPage, "nexusShortcutRow_commandPalette") !== null, "missing nexusShortcutRow_commandPalette")
                check(findChild(settingsPage, "nexusShortcutBindButton_commandPalette") !== null, "missing nexusShortcutBindButton_commandPalette")

                // Verify filtering shortcuts in NexusThemeSettings by Obsidian command ID (e.g. zk-prefixer)
                const filterInput = findChild(settingsPage, "nexusShortcutFilterInput")
                check(filterInput !== null, "missing nexusShortcutFilterInput")
                filterInput.text = "zk-prefixer"
                check(findChild(settingsPage, "nexusShortcutRow_newZettelkasten") !== null, "expected newZettelkasten row when filtering by zk-prefixer")
                check(findChild(settingsPage, "nexusShortcutRow_commandPalette") === null, "commandPalette row should be filtered out for zk-prefixer")
                filterInput.text = ""

                const liveClockTimer = findChild(ws, "nexusHomepageLiveClockTimer")
                check(liveClockTimer !== null, "missing nexusHomepageLiveClockTimer")
                check(liveClockTimer.running === false, "nexusHomepageLiveClockTimer must NOT run when Nexus is closed")

                nexus.open()
                tryCompare(nexus, "vaultLoaded", true, 4000)
                tryVerify(() => nexus.calendarCells.length === 42, 4000)
                check(liveClockTimer.running === true, "nexusHomepageLiveClockTimer should run when Nexus is open on Homepage")
                const hpActionsRow = findChild(ws, "nexusHomepageActionsRow")
                check(hpActionsRow !== null && hpActionsRow.actionButtons.length === 7, "Homepage hero should have exact 7 Obsidian action buttons")
                check(hpActionsRow.actionButtons[1].label === "/zettelkasten" && hpActionsRow.actionButtons[6].label === "/web-site", "Homepage action buttons should match Obsidian info-headers.js")
                check(nexus.stats.noteCount === 1, "expected 1 markdown note")
                check(nexus.stats.activityHeatmap.length === 119, "expected 17-week heatmap")

                // Verify Explorer folders start collapsed with 2-digit prefix colorHex & iconName, and propagate colorHex when expanded
                check(nexus.visibleTreeRows.length === 2, "expected 2 collapsed top-level folders initially, got " + nexus.visibleTreeRows.length)
                check(nexus.visibleTreeRows[0].name === "10_Projects" && nexus.visibleTreeRows[0].colorHex === "#7bb5c1" && nexus.visibleTreeRows[0].iconName === "database", "expected 10_Projects folder color #7bb5c1 and icon database")
                nexus.toggleFolderExpanded("10_Projects")
                check(nexus.visibleTreeRows.length === 3, "expanding 10_Projects should reveal Alpha.md")
                check(nexus.visibleTreeRows[1].name === "Alpha.md" && nexus.visibleTreeRows[1].colorHex === "#7bb5c1", "child note Alpha.md should inherit parent folder colorHex #7bb5c1")

                // Verify interactive splitters and top-level overlay resize handles exist in NexusWorkspace
                const leftResizeHandle = findChild(ws, "nexusLeftSidebarResizeHandle")
                const rightResizeHandle = findChild(ws, "nexusRightSidebarResizeHandle")
                const leftCol = findChild(ws, "nexusLeftColumn")
                const rightCol = findChild(ws, "nexusRightColumn")
                const ctxCard = findChild(ws, "nexusContextCard")
                check(leftResizeHandle !== null, "missing nexusLeftSidebarResizeHandle")
                check(rightResizeHandle !== null, "missing nexusRightSidebarResizeHandle")
                check(leftCol !== null && rightCol !== null, "missing nexusLeftColumn or nexusRightColumn")
                check(ctxCard !== null, "missing nexusContextCard")
                check(nexus.rightBottomTab === "schedule", "expected rightBottomTab to default to schedule (Weekly Planner)")
                check(ctxCard.weekDaysModel.length === 7, "expected 7-day strip in Weekly Planner")
                const weeklyTimeline = findChild(ws, "nexusWeeklyPlannerTimeline")
                check(weeklyTimeline !== null, "missing nexusWeeklyPlannerTimeline")
                check(weeklyTimeline.contentHeight === 24 * weeklyTimeline.hourRowHeight && weeklyTimeline.hourRowHeight >= 32, "expected 24-hour Weekly Planner timeline with increased hour mark spacing")
                check(findChild(ws, "nexusWeeklyPlannerNowLine") !== null, "missing nexusWeeklyPlannerNowLine")
                check(findChild(ws, "nexusOpenDashboardPlannerButton") !== null, "missing nexusOpenDashboardPlannerButton")

                // Verify Weekly Planner synchronization with Dashboard Events & quick add from Homepage Schedule card
                tryCompare(Events, "ready", true, 4000)
                const todayIso = ctxCard.activePlannerDateIso
                const parts = todayIso.split("-")
                const startDt = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]), 10, 0)
                const endDt = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]), 11, 30)
                Events.addEvent("Nexus Synced Sprint", "Synced test", startDt.toISOString(), "general", "normal", 15, "none", endDt.toISOString(), false)
                check(ctxCard.syncedTimedItems.some(it => it.title === "Nexus Synced Sprint" && it.source === "dashboard"), "Weekly Planner should sync timed events from Dashboard Events.list")
                const hpScheduleCard = findChild(ws, "nexusHomepageScheduleCard")
                check(hpScheduleCard !== null, "missing nexusHomepageScheduleCard")
                hpScheduleCard.addPlannerEventFromInput("08:30-09:30 Morning Standup")
                check(Events.list.some(ev => ev.title === "Morning Standup" && ev.priority === "normal" && String(ev.startDate).length > 10 && String(ev.endDate).length > 10), "addPlannerEventFromInput should create valid Dashboard Event with ISO startDate and endDate")
                check(ctxCard.syncedTimedItems.some(it => it.title === "Morning Standup" && it.source === "dashboard"), "Morning Standup added in Homepage should appear in Weekly Planner")

                check(findChild(ws, "nexusLeftSidebarSplitter") !== null, "missing nexusLeftSidebarSplitter")
                check(findChild(ws, "nexusRightSidebarSplitter") !== null, "missing nexusRightSidebarSplitter")
                check(findChild(ws, "nexusLeftCardSplitter") !== null, "missing nexusLeftCardSplitter")
                check(findChild(ws, "nexusRightTopCardSplitter") !== null, "missing nexusRightTopCardSplitter")
                check(findChild(ws, "nexusRightMidCardSplitter") !== null, "missing nexusRightMidCardSplitter")
                check(findChild(ws, "nexusHomepageHeroSplitter") === null, "nexusHomepageHeroSplitter should be removed from Nexus Dashboard")
                check(findChild(ws, "nexusHomepageScheduleSplitter") === null, "nexusHomepageScheduleSplitter should be removed from Nexus Dashboard")
                check(findChild(ws, "nexusCardDragPreview") !== null, "missing nexusCardDragPreview")

                // Verify sidebar & card resizing updates both service property AND actual visual ColumnLayout width 1:1
                nexus.setLeftSidebarWidth(312)
                tryCompare(leftCol, "width", 312, 1000)
                check(nexus.leftSidebarWidth === 312 && leftCol.width === 312, "leftSidebarWidth or nexusLeftColumn.width did not update to 312")
                nexus.setRightSidebarWidth(330)
                tryCompare(rightCol, "width", 330, 1000)
                check(nexus.rightSidebarWidth === 330 && rightCol.width === 330, "rightSidebarWidth or nexusRightColumn.width did not update to 330")

                // Verify dragging top-level overlay resize handles directly updates sidebar width 1:1 with exact pixel delta (no jump)
                mousePress(leftResizeHandle, 8, 200, Qt.LeftButton)
                mouseMove(leftResizeHandle, 48, 200)
                mouseRelease(leftResizeHandle, 48, 200, Qt.LeftButton)
                tryCompare(nexus, "leftSidebarWidth", 352, 1000)
                tryCompare(leftCol, "width", 352, 1000)

                mousePress(rightResizeHandle, 8, 200, Qt.LeftButton)
                mouseMove(rightResizeHandle, -24, 200)
                mouseRelease(rightResizeHandle, -24, 200, Qt.LeftButton)
                tryCompare(nexus, "rightSidebarWidth", 362, 1000)
                tryCompare(rightCol, "width", 362, 1000)

                nexus.setLeftSplitRatio(0.55)
                check(Math.abs(nexus.leftSplitRatio - 0.55) < 0.01, "leftSplitRatio did not update")
                nexus.setHomepageHeroHeight(310)
                check(nexus.homepageHeroHeight === 310, "homepageHeroHeight did not update to 310")
                nexus.setHomepageScheduleHeight(284)
                check(nexus.homepageScheduleHeight === 284, "homepageScheduleHeight did not update to 284")

                // Verify card drag-and-drop / swapCards across columns & workspace-local hit testing
                const calCard = findChild(ws, "nexusCalendarCard")
                const expCard = findChild(ws, "nexusFileTreeCard")
                check(calCard !== null && expCard !== null, "missing calendar or explorer card")
                check(expCard.parent.objectName === "nexusLeftSlot0", "explorer should start in nexusLeftSlot0")
                check(calCard.parent.objectName === "nexusRightSlot0", "calendar should start in nexusRightSlot0")
                const leftSlotCenter = expCard.parent.mapToItem(ws, expCard.parent.width / 2, expCard.parent.height / 2)
                check(ws.cardIdAtRootPos(leftSlotCenter.x, leftSlotCenter.y) === "explorer", "cardIdAtRootPos failed for leftSlot0")
                nexus.swapCards("explorer", "calendar")
                ws.syncCardSlots()
                check(calCard.parent.objectName === "nexusLeftSlot0", "calendar should move to nexusLeftSlot0 after swap")
                check(expCard.parent.objectName === "nexusRightSlot0", "explorer should move to nexusRightSlot0 after swap")

                // Verify searchInNote opens rightSidebarOpen when explorer is in right slot
                nexus.rightSidebarOpen = false
                nexus.triggerShortcutAction("searchInNote")
                check(nexus.rightSidebarOpen === true, "searchInNote should open rightSidebarOpen when explorer is in right slot")

                nexus.resetLayout()
                ws.syncCardSlots()
                check(expCard.parent.objectName === "nexusLeftSlot0", "explorer should return to nexusLeftSlot0 after resetLayout")
                check(nexus.leftSidebarWidth === 268, "leftSidebarWidth should reset to 268")
                check(nexus.homepageScheduleHeight === 216, "homepageScheduleHeight should reset to 216")

                // Verify Obsidian shortcuts adaptation & custom shortcut rebinding (including quickadd UUID & secondary hotkeys)
                check(nexus.shortcutFor("commandPalette") === "Alt+Enter", "expected Alt+Enter for commandPalette")
                check(nexus.shortcutFor("quickSwitcher") === "Alt+Escape", "expected Alt+Escape for quickSwitcher")
                check(nexus.shortcutFor("quickAddTask") === "Alt+T", "expected Alt+T for quickAddTask from .obsidian/hotkeys.json")
                check(nexus.shortcutFor("newZettelkasten") === "Ctrl+N", "expected Ctrl+N for newZettelkasten")
                check(nexus.shortcutFor("navigateBack") === "Ctrl+Alt+Left", "expected primary Ctrl+Alt+Left from .obsidian/hotkeys.json for navigateBack")
                check(nexus.syncShortcutsFromVault() >= 4, "expected syncShortcutsFromVault to sync at least 4 vault hotkeys")
                nexus.resetAllShortcuts()
                nexus.setShortcut("quickSwitcher", "Ctrl+K")
                check(nexus.shortcutFor("quickSwitcher") === "Ctrl+K", "custom shortcut Ctrl+K not saved")
                nexus.resetShortcut("quickSwitcher")
                check(nexus.shortcutFor("quickSwitcher") === "Alt+Escape", "resetShortcut did not restore Alt+Escape")
                check(nexus.triggerShortcutAction("quickSwitcher") === true, "triggerShortcutAction(quickSwitcher) failed")
                check(nexus.commandPaletteOpen === true && nexus.commandPaletteMode === "switcher", "commandPalette did not open in switcher mode")
                nexus.commandPaletteOpen = false

                // Window vs Overlay mode toggle via header button & service
                const modeBtn = findChild(ws, "nexusWindowModeToggleButton")
                check(modeBtn !== null, "missing nexusWindowModeToggleButton")
                const initialOverlay = nexus.overlayMode
                nexus.toggleOverlayMode()
                check(nexus.overlayMode === !initialOverlay, "overlayMode did not toggle")
                nexus.toggleOverlayMode()
                check(nexus.overlayMode === initialOverlay, "overlayMode did not toggle back")

                // Open markdown note in Hybrid Outliner via openNote(absPath)
                check(nexus.openNote("{str(vault / '10_Projects/Alpha.md')}") === true, "openNote(absPath) returned false")
                tryVerify(() => nexus.activeView === "document" && nexus.currentDoc !== null && !nexus.docBusy, 4000)
                check(nexus.currentDoc.title === "Alpha", "unexpected document title")
                check(nexus.currentDoc.blocks.length >= 5, "expected parsed outliner blocks")

                // Verify built-in Vim engine (hjkl, count prefix 3l, x, X, dw, dd, r, u undo, Ctrl+R redo)
                const vimArea = findChild(ws, "nexusVimEditorArea")
                check(vimArea !== null, "missing nexusVimEditorArea")
                nexus.setEditorMode("raw")
                vimArea.text = "hello world\\nsecond line"
                vimArea.cursorPosition = 0
                nexus.vimMode = "NORMAL"
                ws.vimHandleNormalKey({{ key: Qt.Key_3, text: "3", modifiers: Qt.NoModifier }}, vimArea)
                ws.vimHandleNormalKey({{ key: Qt.Key_L, text: "l", modifiers: Qt.NoModifier }}, vimArea)
                check(vimArea.cursorPosition === 3, "expected 3l to move cursor to 3, got " + vimArea.cursorPosition)
                ws.vimHandleNormalKey({{ key: Qt.Key_0, text: "0", modifiers: Qt.NoModifier }}, vimArea)
                check(vimArea.cursorPosition === 0, "expected 0 to move cursor to 0")
                ws.vimHandleNormalKey({{ key: Qt.Key_D, text: "d", modifiers: Qt.NoModifier }}, vimArea)
                ws.vimHandleNormalKey({{ key: Qt.Key_W, text: "w", modifiers: Qt.NoModifier }}, vimArea)
                check(vimArea.text.startsWith("world"), "expected dw to delete 'hello ', got: " + vimArea.text)
                ws.vimHandleNormalKey({{ key: Qt.Key_U, text: "u", modifiers: Qt.NoModifier }}, vimArea)
                check(vimArea.text.startsWith("hello world"), "expected u to undo dw, got: " + vimArea.text)
                ws.vimHandleNormalKey({{ key: Qt.Key_X, text: "x", modifiers: Qt.NoModifier }}, vimArea)
                check(vimArea.text.startsWith("ello world"), "expected x to delete 'h', got: " + vimArea.text)
                ws.vimHandleNormalKey({{ key: Qt.Key_R, text: "r", modifiers: Qt.NoModifier }}, vimArea)
                ws.vimHandleNormalKey({{ key: Qt.Key_M, text: "m", modifiers: Qt.NoModifier }}, vimArea)
                check(vimArea.text.startsWith("mllo world"), "expected rm to replace 'e' with 'm', got: " + vimArea.text)
                nexus.setEditorMode("hybrid")

                // Verify Cornell cue badge is ONLY visible on Cornell cue heading (id 4), NOT normal Heading 1 (id 0)
                const normalHeadingBadge = findChild(ws, "nexusCornellCueBadge_0")
                const cornellHeadingBadge = findChild(ws, "nexusCornellCueBadge_4")
                check(normalHeadingBadge !== null && normalHeadingBadge.visible === false, "normal heading should not show Cornell cue badge")
                check(cornellHeadingBadge !== null && cornellHeadingBadge.visible === true, "Cornell '?' heading should show Cornell cue badge")

                // Verify dailyFolder / dailyFormat bind to Config.options.todo.nexus.dailyNote
                Config.setNestedValue("todo.nexus.dailyNote.folder", "00_Capture/01_CustomJournal")
                check(nexus.dailyFolder === "00_Capture/01_CustomJournal", "dailyFolder did not track todo.nexus.dailyNote.folder")
                Config.setNestedValue("todo.nexus.dailyNote.folder", "00_Capture/01_Journal")

                // Block folding (Logseq-style zM / zR)
                nexus.foldAllBlocks()
                check(nexus.isBlockHiddenByFold(2) === true, "child block should be hidden when parent is folded")
                nexus.unfoldAllBlocks()
                check(nexus.isBlockHiddenByFold(2) === false, "child block should be visible after zR")

                // Vim Ex commands (:daily, :home, :graph, :split, :hybrid, :movies, :tv, :places)
                check(nexus.executeVimExCommand(":daily") === true, ":daily command failed")
                tryVerify(() => !nexus.docBusy && nexus.currentPath.indexOf("01_Journal") !== -1, 4000)
                const journalCustomView = findChild(ws, "nexusJournalCustomView")
                check(journalCustomView !== null && journalCustomView.visible === true, "nexusJournalCustomView should be visible when daily journal note is open")
                check(nexus.executeVimExCommand(":split") === true && nexus.editorMode === "split", ":split failed")
                check(nexus.executeVimExCommand(":hybrid") === true && nexus.editorMode === "hybrid", ":hybrid failed")

                // Interactive Graph Canvas zoom/reset & wheel/drag pointer events
                const vGraphCanvas = findChild(ws, "nexusVaultGraphCanvas")
                check(vGraphCanvas !== null, "missing nexusVaultGraphCanvas")
                vGraphCanvas.zoomIn()
                check(vGraphCanvas.zoom > 1.0, "expected NexusGraphCanvas zoomIn() to increase zoom")
                vGraphCanvas.resetView()
                check(vGraphCanvas.zoom === 1.0, "expected NexusGraphCanvas resetView() to reset zoom to 1.0")

                nexus.openGraphView()
                const fGraphCanvas = findChild(ws, "nexusFullGraphCanvas")
                check(fGraphCanvas !== null && fGraphCanvas.visible === true, "nexusFullGraphCanvas should be visible in graph view")
                check(fGraphCanvas.renderMode === "3d" && fGraphCanvas.autoRotate3D === true, "main nexusFullGraphCanvas should open in 3D auto-orbit")
                mouseWheel(fGraphCanvas, fGraphCanvas.width / 2, fGraphCanvas.height / 2, 0, 120, Qt.NoButton, Qt.NoModifier)
                check(fGraphCanvas.zoom > 1.0 && fGraphCanvas.autoRotate3D === false, "mouseWheel should zoom and disable auto-orbit on NexusGraphCanvas")
                const yawBefore = fGraphCanvas.rotYaw
                const pitchBefore = fGraphCanvas.rotPitch
                mousePress(fGraphCanvas, 20, 20, Qt.LeftButton)
                mouseMove(fGraphCanvas, 70, 55)
                mouseRelease(fGraphCanvas, 70, 55, Qt.LeftButton)
                check(fGraphCanvas.rotYaw !== yawBefore || fGraphCanvas.rotPitch !== pitchBefore, "mouseDrag on empty 3D canvas should orbit NexusGraphCanvas")
                fGraphCanvas.renderMode = "2d"
                const panBeforeX = fGraphCanvas.panX
                mousePress(fGraphCanvas, 20, 20, Qt.LeftButton)
                mouseMove(fGraphCanvas, 70, 55)
                mouseRelease(fGraphCanvas, 70, 55, Qt.LeftButton)
                check(fGraphCanvas.panX !== panBeforeX, "mouseDrag on empty 2D canvas should pan NexusGraphCanvas")
                fGraphCanvas.resetView()

                // Collection Browser: verify tvSeries camelCase normalization, Places metadata, and historyBack restoration
                check(findChild(ws, "nexusHomepageCollectionsStrip") !== null, "missing nexusHomepageCollectionsStrip")
                nexus.openCollection("tvSeries")
                const collView = findChild(ws, "nexusCollectionView")
                check(nexus.activeView === "collection" && nexus.activeCollection === "tvseries", "openCollection(tvSeries) should normalize to tvseries")
                check(collView !== null && collView.visible === true, "nexusCollectionView should be visible")
                check(collView.activeCollectionMeta.title === "TV-Series Tracker", "expected TV-Series Tracker header, got " + collView.activeCollectionMeta.title)

                nexus.openCollection("places")
                check(collView.activeCollectionMeta.title === "Places & Coordinates", "expected Places & Coordinates header, got " + collView.activeCollectionMeta.title)

                nexus.openCollection("movies")
                check(nexus.activeView === "collection" && nexus.activeCollection === "movies", "openCollection(movies) failed")
                check(nexus.createCollectionEntry("movies", "Inception") === true, "createCollectionEntry(movies, Inception) failed")
                tryVerify(() => nexus.activeView === "document" && nexus.currentDoc !== null && !nexus.docBusy && !nexus.scanBusy && nexus.currentDoc.noteKind === "movie" && (nexus.collections?.movies?.length ?? 0) > 0, 4000)
                const dossierBanner = findChild(ws, "nexusDocumentDossierBanner")
                check(dossierBanner !== null && dossierBanner.visible === true, "nexusDocumentDossierBanner should be visible for movie note")
                const customViewsRoot = findChild(ws, "nexusCustomViewsRoot")
                check(customViewsRoot !== null && customViewsRoot.visible === true, "nexusCustomViewsRoot should be visible for movie note")

                // Navigating back from a note opened from a collection should restore the collection view
                nexus.navigateBack()
                check(nexus.activeView === "collection" && nexus.activeCollection === "movies", "navigateBack() should return to movies collection view")
                wait(30)

                // Verify Cinema Ticket card & back dossier exist in Movies Bases view, plus Cards/Table view mode switcher
                const cinemaTicket = findChild(ws, "nexusCinemaTicketCard_0")
                const cinemaTicketBack = findChild(ws, "nexusCinemaTicketBack_0")
                check(cinemaTicket !== null && cinemaTicket.visible === true, "nexusCinemaTicketCard_0 should be visible in Movies Bases view")
                check(cinemaTicketBack !== null, "nexusCinemaTicketBack_0 should exist inside Cinema Ticket card")
                const basesTable = findChild(ws, "nexusBasesTableView")
                check(basesTable !== null && basesTable.visible === false, "nexusBasesTableView should start hidden in cards mode")
                collView.viewMode = "table"
                check(basesTable.visible === true, "nexusBasesTableView should be visible when viewMode === 'table'")
                collView.viewMode = "cards"
                check(basesTable.visible === false, "nexusBasesTableView should hide when returning to cards mode")

                // Verify clicking .base files in Explorer routes directly to Bases Collection View
                nexus.openFile("20_Permanent_Notes/23_Media_Tracker/Media_Tracker.base", true)
                check(nexus.activeView === "collection" && nexus.activeCollection === "movies", "Media_Tracker.base should route to movies Bases collection")
                nexus.openFile("20_Permanent_Notes/24_Book_Tracker/Book_Tracker.base", true)
                check(nexus.activeView === "collection" && nexus.activeCollection === "books", "Book_Tracker.base should route to books Bases collection")
                nexus.openFile("20_Permanent_Notes/27_Games/Game_Collection.base", true)
                check(nexus.activeView === "collection" && nexus.activeCollection === "games", "Game_Collection.base should route to games Bases collection")
                nexus.openFile("20_Permanent_Notes/25_Food_and_Drinks/FoodnDrinks.base", true)
                check(nexus.activeView === "collection" && nexus.activeCollection === "recipes", "FoodnDrinks.base should route to recipes Bases collection")
                nexus.openFile("20_Permanent_Notes/26_Bodybuilding/Bodybuilding.base", true)
                check(nexus.activeView === "collection" && nexus.activeCollection === "exercises", "Bodybuilding.base should route to exercises Bases collection")
                nexus.openFile("20_Permanent_Notes/28_Places/Places.base", true)
                check(nexus.activeView === "collection" && nexus.activeCollection === "places", "Places.base should route to places Bases collection")
                nexus.openFile("20_Permanent_Notes/29_Contacts/Contact_Tracker.base", true)
                check(nexus.activeView === "collection" && nexus.activeCollection === "contacts", "Contact_Tracker.base should route to contacts Bases collection")
                nexus.openFile("30_Resources/32_Finance/Finance.base", true)
                check(nexus.activeView === "collection" && nexus.activeCollection === "finance", "Finance.base should route to finance Bases collection")

                check(nexus.executeVimExCommand(":home") === true && nexus.activeView === "homepage", ":home failed")

                // Verify top header bar no longer has sidebar toggle buttons
                check(findChild(ws, "nexusToggleLeftSidebarButton") === null, "left sidebar toggle button should be removed")
                check(findChild(ws, "nexusToggleRightSidebarButton") === null, "right sidebar toggle button should be removed")

                // Verify resize splitters and status bar are hidden when not hovered/active
                check(findChild(ws, "nexusLeftSidebarSplitter").active === false, "nexusLeftSidebarSplitter should be inactive when not hovered")
                check(findChild(ws, "nexusRightSidebarSplitter").active === false, "nexusRightSidebarSplitter should be inactive when not hovered")
                check(findChild(ws, "nexusLeftCardSplitter").opacity === 0, "nexusLeftCardSplitter should be hidden when not hovered")
                check(findChild(ws, "nexusRightTopCardSplitter").opacity === 0, "nexusRightTopCardSplitter should be hidden when not hovered")
                check(findChild(ws, "nexusRightMidCardSplitter").opacity === 0, "nexusRightMidCardSplitter should be hidden when not hovered")
                check(findChild(ws, "nexusHomepageHeroSplitter") === null, "nexusHomepageHeroSplitter should stay removed")
                check(findChild(ws, "nexusHomepageScheduleSplitter") === null, "nexusHomepageScheduleSplitter should stay removed")

                const statusBar = findChild(ws, "nexusStatusBar")
                check(statusBar !== null, "missing nexusStatusBar")
                check(statusBar.statusBarShown === false && statusBar.opacity === 0, "nexusStatusBar should hide when not hovered and not in COMMAND/SEARCH mode")
                nexus.vimMode = "COMMAND"
                check(statusBar.statusBarShown === true, "nexusStatusBar should slide open in COMMAND mode")
                nexus.vimMode = "NORMAL"

                // Verify Colored Sidebar auto-theming function
                const tone00 = String(ws.autoThemedFolderColor("00", "#82c2cf"))
                const tone90 = String(ws.autoThemedFolderColor("90", "#3d484b"))
                check(tone00 !== tone90 && tone00.startsWith("#") && tone90.startsWith("#"), "autoThemedFolderColor should produce distinct themed tones for 00 vs 90")

                // Verify extended Vim text objects and motions (diw, ciw, f, N, >>, <<)
                nexus.openFile("10_Projects/Alpha.md", true)
                tryVerify(() => nexus.activeView === "document" && !nexus.docBusy, 4000)
                nexus.setEditorMode("raw")
                vimArea.text = "alpha beta gamma\\nsecond line"
                vimArea.cursorPosition = 6
                nexus.vimMode = "NORMAL"
                ws.vimHandleNormalKey({{ key: Qt.Key_D, text: "d", modifiers: Qt.NoModifier }}, vimArea)
                ws.vimHandleNormalKey({{ key: Qt.Key_I, text: "i", modifiers: Qt.NoModifier }}, vimArea)
                ws.vimHandleNormalKey({{ key: Qt.Key_W, text: "w", modifiers: Qt.NoModifier }}, vimArea)
                check(vimArea.text.startsWith("alpha  gamma"), "expected diw on 'beta' to leave 'alpha  gamma', got: " + vimArea.text)
                ws.vimHandleNormalKey({{ key: Qt.Key_U, text: "u", modifiers: Qt.NoModifier }}, vimArea)
                vimArea.cursorPosition = 0
                ws.vimHandleNormalKey({{ key: Qt.Key_F, text: "f", modifiers: Qt.NoModifier }}, vimArea)
                ws.vimHandleNormalKey({{ key: Qt.Key_G, text: "g", modifiers: Qt.NoModifier }}, vimArea)
                check(vimArea.text.substring(vimArea.cursorPosition, vimArea.cursorPosition + 5) === "gamma", "expected fg to jump to 'gamma'")
                ws.vimHandleNormalKey({{ key: Qt.Key_Greater, text: ">", modifiers: Qt.NoModifier }}, vimArea)
                ws.vimHandleNormalKey({{ key: Qt.Key_Greater, text: ">", modifiers: Qt.NoModifier }}, vimArea)
                check(vimArea.text.startsWith("  alpha"), "expected >> to indent line by 2 spaces")
                ws.vimHandleNormalKey({{ key: Qt.Key_Less, text: "<", modifiers: Qt.NoModifier }}, vimArea)
                ws.vimHandleNormalKey({{ key: Qt.Key_Less, text: "<", modifiers: Qt.NoModifier }}, vimArea)
                check(vimArea.text.startsWith("alpha"), "expected << to unindent line by 2 spaces")
                nexus.setEditorMode("hybrid")

                // External unsupported file (.docx) dispatches to xdg-open without replacing active markdown doc
                nexus.openFile("20_Notes/Manual.docx", true)
                tryVerify(() => !nexus.docBusy && nexus.lastExternalOpenedPath.endsWith("20_Notes/Manual.docx"), 4000)

                // Verify Weekly Planner recurring event projection & weekOffset sync
                check(ctxCard !== null, "missing nexusContextCard")
                check(ctxCard._matchesPlannerDate({{ startDate: "2026-11-02T09:00:00", recurrence: "weekly" }}, "2026-11-09") === true, "Weekly Planner should project weekly recurring events onto matching weekday")
                ctxCard.weekDayOffset = 2
                check(Number(GlobalStates.dashboardPlannerBrowser.weekOffset) === 2, "weekDayOffset should sync to GlobalStates.dashboardPlannerBrowser.weekOffset")
                ctxCard.weekDayOffset = 0

                // Verify Overlay mode unified Screen-Edge body in AbyssBodyHost (1 thể with Screen Edges like Dashboard/Settings)
                tryCompare(bodyHostLoader, "status", Loader.Ready, 4000)
                const bodyHost = bodyHostLoader.item
                nexus.setOverlayMode(true)
                GlobalStates.nexusOpen = true
                check(bodyHost.identity === "nexus" && bodyHost.placementPriority === 3, "AbyssBodyHost should treat identity='nexus' as placementPriority 3 unified screen-edge body like Dashboard/Settings")

                // ── Verify 11 User Corrections + 5 Follow-up Polish Fixes ──
                // 1. Heatmap Grid alignment, 119 rounded cells, and acyclic Column 3 scaling (cellW >= cellH and balanced aspect ratio at normal & wide widths)
                nexus.openHomepage()
                const hmCol = findChild(ws, "nexusHomepageHeatmapColumn")
                const hmGrid = findChild(ws, "nexusHomepageHeatmapGrid")
                check(hmCol !== null && hmGrid !== null && hmGrid.columns === 17 && hmGrid.rows === 7, "nexusHomepageHeatmapGrid should be a 17x7 Grid")
                check(hmCol.cellW >= hmCol.cellH && hmCol.cellW <= Math.round(hmCol.cellH * 1.5) && hmCol.cellW >= 11 && hmCol.gridW >= 232, "Heatmap cells must have balanced aspect ratio (expected cellH <= cellW <= 1.5*cellH, got " + hmCol.cellW + "x" + hmCol.cellH + ", gridW=" + hmCol.gridW + ")")
                workspaceLoader.anchors.fill = undefined
                workspaceLoader.width = 1680
                workspaceLoader.height = 820
                wait(40)
                check(hmCol.cellW >= hmCol.cellH && hmCol.cellW <= Math.round(hmCol.cellH * 1.5) && hmCol.gridW > 320, "At wide 1680px width, Heatmap must expand across Column 3 with balanced cell aspect ratio (expected cellH <= cellW <= 1.5*cellH, got " + hmCol.cellW + "x" + hmCol.cellH + ", gridW=" + hmCol.gridW + ")")
                workspaceLoader.anchors.fill = workspaceLoader.parent
                wait(20)

                // 2. 3D Globe widget ported from globe-widget.js + Super+Shift+S screenshot / transition timer pause
                const globeWidget = findChild(ws, "nexusGlobeWidget")
                const globeSpinTimer = findChild(globeWidget, "nexusGlobeSpinTimer")
                check(globeWidget !== null && globeSpinTimer !== null, "missing nexusGlobeWidget or nexusGlobeSpinTimer")
                check(globeWidget.autoRotate === true && Math.abs(globeWidget.zoom - 0.92) < 0.01, "expected globeWidget default autoRotate=true and zoom=0.92")
                check(globeSpinTimer.running === true, "nexusGlobeSpinTimer should run when Homepage is open and idle")
                GlobalStates.regionSelectorOpen = true
                check(globeSpinTimer.running === false && liveClockTimer.running === false, "Globe spinTimer and Homepage liveClockTimer must pause immediately during Super+Shift+S (regionSelectorOpen=true)")
                GlobalStates.regionSelectorOpen = false
                ws.transitionSettled = false
                check(globeSpinTimer.running === false && liveClockTimer.running === false, "Globe spinTimer and Homepage liveClockTimer must pause while Screen Edges open transition is animating (transitionSettled=false)")
                ws.transitionSettled = true
                check(globeSpinTimer.running === true && liveClockTimer.running === true, "Timers should resume once regionSelectorOpen=false and transitionSettled=true")
                check(findChild(globeWidget, "nexusGlobeFooterLegend") !== null, "missing nexusGlobeFooterLegend (.hd-globe-footer)")
                const prevZoom = globeWidget.zoom
                globeWidget.focusCluster({{ lon: 106.7, lat: 10.8, count: 3 }})
                check(globeWidget.zoom > prevZoom && globeWidget.pauseUntilMs > Date.now(), "focusCluster should zoom into multi-marker cluster and pause spin")
                globeWidget.resetView()
                check(globeWidget.autoRotate === true && Math.abs(globeWidget.zoom - 0.92) < 0.01, "resetView should restore zoom=0.92 and autoRotate=true")

                // 7. Vault Graph fine node radius
                check(vGraphCanvas._nodeRadius({{ degree: 0 }}, false, false, false, 1.0) <= 1.2, "compact leaf node radius should be fine and small")

                // 8 & 10. Removed Back/Forward/Close/CommandPalette/ResetLayout header buttons, unified Reading/Vim mode badge, instant Edit<->Reading mode cursor, and two-step Escape
                check(findChild(ws, "nexusCloseButton") === null, "header close button should be removed")
                check(findChild(ws, "nexusCommandPaletteButton") === null, "cluttered Alt+Enter header button should be removed")
                check(findChild(ws, "nexusResetLayoutHeaderButton") === null, "mystery dashboard_customize header button should be removed")
                const vimBadge = findChild(ws, "nexusVimModeBadge")
                check(vimBadge !== null && vimBadge.inEditMode === false, "nexusVimModeBadge should show Reading mode when on Homepage")
                nexus.openFile("10_Projects/Alpha.md", true)
                tryVerify(() => nexus.activeView === "document" && !nexus.docBusy, 4000)
                check(vimBadge.inEditMode === false, "nexusVimModeBadge should show Reading mode in hybrid document view")
                nexus.setEditorMode("raw")
                check(vimBadge.inEditMode === true, "nexusVimModeBadge should show Vim mode in raw edit view")
                const vimPane = findChild(ws, "nexusVimEditorPane")
                const vimCursorOverlay = findChild(ws, "nexusVimCursorOverlay")
                check(vimPane !== null && vimPane.visible === true && vimArea.cursorVisible === true && vimCursorOverlay !== null && vimCursorOverlay.visible === true, "vimEditorArea cursor and nexusVimCursorOverlay should be immediately visible on frame 1 when switching to Edit mode")
                check(ws.handleEscape() === true && nexus.editorMode === "hybrid" && nexus.isOpen === true, "first Escape in Edit mode should return to Reading mode ('hybrid') without closing Nexus")
                check(ws.handleEscape() === false, "second handleEscape() in Reading mode should return false so AbyssPerimeter closes Nexus")
                // Also verify Escape works inside vimEditorArea when vimEnabled === false
                nexus.vimEnabled = false
                nexus.setEditorMode("raw")
                ws.vimHandleNormalKey({{ key: Qt.Key_Escape, text: "", modifiers: Qt.NoModifier }}, vimArea)
                check(nexus.editorMode === "hybrid" && nexus.isOpen === true, "first Escape with vimEnabled=false should return to Reading mode")
                ws.vimHandleNormalKey({{ key: Qt.Key_Escape, text: "", modifiers: Qt.NoModifier }}, vimArea)
                check(nexus.isOpen === false, "second Escape key in Reading mode should close Nexus")
                nexus.vimEnabled = true
                nexus.open()
                check(nexus._loadedVaultPath === nexus.configuredVaultPath && nexus._calendarLoadedFromCli === true, "NexusService should retain _loadedVaultPath and _calendarLoadedFromCli across close/open without redundant rescan")

                // 5 & 9. Game Custom View (Game.html/js/css parity) & Note Auto-Theming workspace binding + themeRichHtml
                check(!ws.themeRichHtml('<span style="color:#38bdf8;">link</span>').includes("#38bdf8"), "ws.themeRichHtml should replace hardcoded #38bdf8 with auto-themed accent color")
                check(!customViewsRoot.themeRichHtml('<span style="color:#38bdf8;">link</span>').includes("#38bdf8"), "customViewsRoot.themeRichHtml should replace hardcoded #38bdf8 with auto-themed accent color")
                check(nexus.createCollectionEntry("games", "Crimson Desert") === true, "createCollectionEntry(games, Crimson Desert) failed")
                tryVerify(() => nexus.activeView === "document" && nexus.currentDoc !== null && !nexus.docBusy && nexus.currentDoc.noteKind === "game", 4000)
                const gameCustomView = findChild(ws, "nexusGameCustomView")
                check(gameCustomView !== null && gameCustomView.visible === true, "nexusGameCustomView should be visible when a game note is open")
                check(customViewsRoot.workspace === ws, "NexusCustomViews should bind workspace for auto-theming")

                // 4, 5, 6. TV Series full-bleed cover, Game Base card, Book Base spine + chevron ribbon + lined back, and Exercises virtualized GridView + Obsidian Exercise Custom View
                check(nexus.createCollectionEntry("tvseries", "Better Call Saul") === true, "createCollectionEntry(tvseries) failed")
                tryVerify(() => !nexus.docBusy && !nexus.scanBusy && nexus.currentDoc?.noteKind === "tvseries" && (nexus.collections?.tvseries?.length ?? 0) > 0, 4000)
                nexus.openCollection("tvseries")
                wait(30)
                const tvPoster = findChild(ws, "nexusTvPosterImg_0")
                check(tvPoster !== null && tvPoster.width === tvPoster.parent.width && tvPoster.height === tvPoster.parent.height, "TV Series poster should cover 100% of card")

                nexus.openCollection("games")
                wait(30)
                check(findChild(ws, "nexusGameBaseCard_0") !== null, "missing nexusGameBaseCard_0 in Games collection")

                check(nexus.createCollectionEntry("books", "The Rust Programming Language") === true, "createCollectionEntry(books) failed")
                tryVerify(() => !nexus.docBusy && !nexus.scanBusy && nexus.currentDoc?.noteKind === "book" && (nexus.collections?.books?.length ?? 0) > 0, 4000)
                nexus.openCollection("books")
                wait(30)
                check(findChild(ws, "nexusBookBaseCard_0") !== null, "missing nexusBookBaseCard_0")
                check(findChild(ws, "nexusBookSpineOverlay_0") !== null, "missing nexusBookSpineOverlay_0")
                check(findChild(ws, "nexusBookStatusRibbon_0") !== null, "missing nexusBookStatusRibbon_0")
                check(findChild(ws, "nexusBookBackFace_0") !== null, "missing nexusBookBackFace_0")

                // Verify Exercise Custom View (Obsidian Exercise.html/js/css parity + Alis auto-theming + NO top generic dossier photo banner) & virtualized Exercises Base GridView
                check(nexus.createCollectionEntry("exercises", "Ab Crunch Machine") === true, "createCollectionEntry(exercises) failed")
                tryVerify(() => nexus.activeView === "document" && nexus.currentDoc !== null && !nexus.docBusy && nexus.currentDoc.noteKind === "exercise", 4000)
                const exerciseCustomView = findChild(ws, "nexusExerciseCustomView")
                const exDossierBanner = findChild(ws, "nexusDocumentDossierBanner")
                const exMediaFrame = findChild(ws, "nexusExerciseMediaFrame")
                const exLevelBadge = findChild(ws, "nexusExerciseLevelBadge")
                const exPlayBtn = findChild(ws, "nexusExercisePlayDemoButton")
                const exStateCaption = findChild(ws, "nexusExerciseMediaStateCaption")
                const exPrimaryCard = findChild(ws, "nexusExercisePrimaryMuscleCard")
                const exSecondaryCard = findChild(ws, "nexusExerciseSecondaryMuscleCard")
                const exEquipmentCard = findChild(ws, "nexusExerciseEquipmentCard")
                const exEquipmentIcon = findChild(ws, "nexusExerciseEquipmentIcon")
                const exNotebookCard = findChild(ws, "nexusExerciseNotebookCard")
                const exPaperTape = findChild(ws, "nexusExercisePaperTape")
                const exAnatomyCard = findChild(ws, "nexusExerciseAnatomyCard")
                const exBodyMapCanvas = findChild(ws, "nexusExerciseBodyMapCanvas")
                const exProfileCard = findChild(ws, "nexusExerciseProfileCard")
                check(exerciseCustomView !== null && exerciseCustomView.visible === true, "nexusExerciseCustomView should be visible when an exercise note is open")
                check(exDossierBanner !== null && exDossierBanner.visible === false && customViewsRoot.isDossierBannerNote === false, "Exercise notes must NOT display the top nexusDocumentDossierBanner hero photo card")
                check(exMediaFrame !== null && exLevelBadge !== null && exPlayBtn !== null && exStateCaption !== null, "missing Exercise Hero media frame, level badge, play button, or state caption")
                check(customViewsRoot.exerciseShowAnimation === false && exStateCaption.text === "STATIC FIRST FRAME", "Exercise demo should start paused on STATIC FIRST FRAME")
                check(exPrimaryCard !== null && exSecondaryCard !== null && exEquipmentCard !== null && exEquipmentIcon !== null, "missing Exercise 2x2 Bento target cards or equipment icon")
                check(exNotebookCard !== null && exPaperTape !== null && exAnatomyCard !== null && exBodyMapCanvas !== null && exProfileCard !== null, "missing Exercise Ruled Notebook, Paper Tape, Anatomy Target Map, or Movement Profile card")
                customViewsRoot.setExerciseLevel("advanced")
                check(customViewsRoot.exerciseActiveLevel === "expert" && customViewsRoot.exerciseLevelLabel("advanced") === "Advanced", "setExerciseLevel(advanced) should update exercise level state")
                tryVerify(() => !nexus.docBusy && !nexus.scanBusy && (nexus.collections?.exercises?.length ?? 0) > 0, 4000)

                nexus.openCollection("exercises")
                wait(40)
                const cardsGrid = findChild(ws, "nexusCollectionCardsGrid")
                check(cardsGrid !== null && cardsGrid.cacheBuffer === 480 && findChild(ws, "nexusExerciseBaseCard_0") !== null, "Exercises Base should use virtualized GridView and render nexusExerciseBaseCard_0 without freezing")

                // 12. Center Workspace Card Perimeter Border (`nexusMainCard`, `nexusMainCardBorderRing`, `nexusMainHeaderBar`) in Overlay & Window modes
                const mainCard = findChild(ws, "nexusMainCard")
                const mainCardBorderRing = findChild(ws, "nexusMainCardBorderRing")
                const mainHeaderBar = findChild(ws, "nexusMainHeaderBar")
                const mainHeaderDivider = findChild(ws, "nexusMainHeaderBottomDivider")
                const fileTreeCard = findChild(ws, "nexusFileTreeCardSurface") ?? findChild(ws, "nexusFileTreeCard")
                const calendarCard = findChild(ws, "nexusCalendarCard")
                check(mainCard !== null && fileTreeCard !== null && mainCard.border.width === 1 && mainCard.radius === fileTreeCard.radius && mainCard.border.color === ws.borderSubtle && mainCard.border.color === fileTreeCard.border.color, "nexusMainCard in Overlay mode must have border.width=1, radius, and border.color: root.borderSubtle matching sidebar cards")
                check(mainCardBorderRing !== null && mainCardBorderRing.visible === true && mainCardBorderRing.border.width === 1 && mainCardBorderRing.border.color === ws.borderSubtle && mainCardBorderRing.radius === mainCard.radius && mainCardBorderRing.z === 60, "nexusMainCardBorderRing must render a crisp 1px perimeter border (z=60, border.color=root.borderSubtle) on top of header/content")
                check(mainHeaderBar !== null && mainHeaderBar.color.a === 0 && mainHeaderDivider !== null && mainHeaderDivider.height === 1, "nexusMainHeaderBar must be transparent so it never paints over the top 1px border of nexusMainCard")
                check(fileTreeCard !== null && calendarCard !== null && Math.abs(mainCard.mapToItem(ws, 0, 0).y - fileTreeCard.mapToItem(ws, 0, 0).y) <= 1 && Math.abs(mainCard.mapToItem(ws, 0, 0).y - calendarCard.mapToItem(ws, 0, 0).y) <= 1, "nexusMainCard top border must align vertically with left and right sidebar cards in Overlay mode")
                nexus.setOverlayMode(false)
                wait(20)
                check(mainCard.border.width === 1 && mainCard.radius === fileTreeCard.radius && Math.abs(mainCard.mapToItem(ws, 0, 0).y - fileTreeCard.mapToItem(ws, 0, 0).y) <= 1, "nexusMainCard top border must also align vertically with sidebar cards in Window mode")
                nexus.setOverlayMode(true)
                wait(20)

                // 13. Journal Custom View: Mood & Energy Low-to-High Left-to-Right order, Editable Weight, and Default Reading Mode + Click-to-Edit on Daily Log
                nexus.openDailyNote("2026-11-08")
                tryVerify(() => nexus.activeView === "document" && nexus.currentDoc !== null && !nexus.docBusy && nexus.currentDoc.noteKind === "journal", 4000)
                wait(30)
                const mood0 = findChild(ws, "nexusJournalMoodOption_0")
                const mood1 = findChild(ws, "nexusJournalMoodOption_1")
                const mood2 = findChild(ws, "nexusJournalMoodOption_2")
                const mood3 = findChild(ws, "nexusJournalMoodOption_3")
                const mood4 = findChild(ws, "nexusJournalMoodOption_4")
                check(mood0 !== null && mood1 !== null && mood2 !== null && mood3 !== null && mood4 !== null, "missing Journal Mood option pills 0..4")
                check(mood0.moodValue === "terrible" && mood1.moodValue === "bad" && mood2.moodValue === "okay" && mood3.moodValue === "good" && mood4.moodValue === "great", "Journal Mood options must be ordered Low-to-High from left to right (terrible -> bad -> okay -> good -> great)")
                check(mood0.x < mood1.x && mood1.x < mood2.x && mood2.x < mood3.x && mood3.x < mood4.x, "Journal Mood option pills must be laid out strictly left-to-right from lowest to highest")

                const energy0 = findChild(ws, "nexusJournalEnergyOption_0")
                const energy1 = findChild(ws, "nexusJournalEnergyOption_1")
                const energy2 = findChild(ws, "nexusJournalEnergyOption_2")
                const energy3 = findChild(ws, "nexusJournalEnergyOption_3")
                const energy4 = findChild(ws, "nexusJournalEnergyOption_4")
                check(energy0 !== null && energy1 !== null && energy2 !== null && energy3 !== null && energy4 !== null, "missing Journal Energy option pills 0..4")
                check(energy0.energyValue === "drained" && energy1.energyValue === "low" && energy2.energyValue === "medium" && energy3.energyValue === "high" && energy4.energyValue === "peak", "Journal Energy options must be ordered Low-to-High from left to right (drained -> low -> medium -> high -> peak)")
                check(energy0.x < energy1.x && energy1.x < energy2.x && energy2.x < energy3.x && energy3.x < energy4.x, "Journal Energy option pills must be laid out strictly left-to-right from lowest to highest")

                // Editable Weight in Journal (commitWeight + comma-decimal normalization + Escape save + immediate optimistic display)
                const weightCard = findChild(ws, "nexusJournalWeightCard")
                const weightInput = findChild(ws, "nexusJournalWeightInput")
                const weightValLbl = findChild(ws, "nexusJournalWeightValueLabel")
                check(weightCard !== null && weightInput !== null && weightValLbl !== null, "missing Journal Weight card, input, or value label")
                check(customViewsRoot.journalEditingWeight === false && weightCard.visible === true && weightInput.visible === false, "Journal Weight should start in display mode")
                customViewsRoot.journalEditingWeight = true
                wait(20)
                check(weightInput.visible === true, "clicking Journal Weight card should reveal inline weight input")
                weightInput.text = "68,5"
                weightInput.commitWeight()
                check(customViewsRoot.journalEditingWeight === false && weightValLbl.text === "68.5 kg", "saving Journal Weight '68,5' should normalize comma decimal and update weightValLbl immediately to '68.5 kg'")
                tryVerify(() => !nexus.docBusy && String(nexus.currentDoc?.journalView?.weight ?? "") === "68.5", 4000)
                // Also verify Escape via ws.handleEscape() saves modified weight
                customViewsRoot.journalEditingWeight = true
                wait(20)
                weightInput.text = "69.2"
                check(ws.handleEscape() === true && customViewsRoot.journalEditingWeight === false && weightValLbl.text === "69.2 kg", "Escape while editing Journal Weight must save and update label to '69.2 kg'")
                tryVerify(() => !nexus.docBusy && String(nexus.currentDoc?.journalView?.weight ?? "") === "69.2", 4000)

                // Daily Log defaults to Reading mode, renders rich HTML (not raw markdown), matches right sidebar height, switches to Editing mode when clicked, and saves on Escape
                const dailyFolioCard = findChild(ws, "nexusJournalDailyFolioCard")
                const rightRailCard = findChild(ws, "nexusJournalRightRailCard")
                const dailyLogReadArea = findChild(ws, "nexusJournalDailyLogReadingArea")
                const dailyLogReadText = findChild(ws, "nexusJournalDailyLogReadingText")
                const dailyLogEditor = findChild(ws, "nexusJournalDailyLogEditor")
                check(dailyFolioCard !== null && rightRailCard !== null && dailyLogReadArea !== null && dailyLogReadText !== null && dailyLogEditor !== null, "missing Journal Daily Folio card, Right Rail card, or Daily Log reading/editor items")
                check(dailyFolioCard.height >= rightRailCard.height, "Journal Daily Folio card height (" + dailyFolioCard.height + ") must match or exceed right sidebar height (" + rightRailCard.height + ")")
                check(customViewsRoot.journalEditingDailyLog === false && dailyLogReadArea.visible === true && dailyLogEditor.visible === false, "Journal Daily Log must default to Reading mode")
                // Initial daily note has `## Notes & Log\\n-` which must strip the redundant heading and render a bullet `•`
                check(!dailyLogReadText.text.includes("Notes &amp; Log") && !dailyLogReadText.text.includes("## Notes & Log") && dailyLogReadText.text.includes("•"), "Initial Journal Daily Log must strip redundant Notes & Log heading and render bullet in Reading mode, got: " + dailyLogReadText.text)
                customViewsRoot.journalEditingDailyLog = true
                wait(20)
                check(dailyLogReadArea.visible === false && dailyLogEditor.visible === true, "clicking Journal Daily Log must switch to Editing mode")
                dailyLogEditor.text = "## Notes & Log\\n- **Focus:** Completed [[Alpha]] review\\n- [x] Shipped Daily Folio rich markdown"
                check(ws.handleEscape() === true && customViewsRoot.journalEditingDailyLog === false && dailyLogReadArea.visible === true, "Escape while editing Journal Daily Log must save and return to Reading mode")
                tryVerify(() => !nexus.docBusy && String(nexus.currentDoc?.journalView?.dailyLogText ?? "").includes("Shipped Daily Folio rich markdown"), 4000)
                wait(20)
                check(dailyLogReadText.textFormat === Text.RichText && !dailyLogReadText.text.includes("Notes &amp; Log") && !dailyLogReadText.text.includes("## Notes & Log") && (dailyLogReadText.text.includes("<b>Focus:</b>") || dailyLogReadText.text.includes("<strong>Focus:</strong>")) && dailyLogReadText.text.includes("wikilink:Alpha") && dailyLogReadText.text.includes("☑"), "Journal Daily Log Reading mode must strip redundant Notes & Log heading and render rich HTML bullets/bold/wikilinks instead of raw markdown source, got: " + dailyLogReadText.text)
                check(dailyFolioCard.height >= rightRailCard.height, "Journal Daily Folio card height must remain aligned with right sidebar after saving markdown")

                // 14. Movie/TV/Book Dossier Custom View (Obsidian Media.html & Book.html parity + rich markdown + synced column height)
                check(typeof customViewsRoot.restoreWorkspaceFocus === "function" && typeof customViewsRoot.forwardWorkspaceShortcut === "function", "NexusCustomViews must define restoreWorkspaceFocus() and forwardWorkspaceShortcut(event)")
                check(nexus.createCollectionEntry("movies", "Avatar - Fire and Ash") === true, "createCollectionEntry(movies, Avatar - Fire and Ash) failed")
                tryVerify(() => nexus.activeView === "document" && nexus.currentDoc !== null && !nexus.docBusy && nexus.currentDoc.noteKind === "movie", 4000)
                nexus.saveNoteBodyMarkdown("")
                tryVerify(() => !nexus.docBusy, 4000)
                nexus.updateNoteFrontmatter({{ "description": "Jake and Neytiri's family grapples with grief after Neteyam's death.", "actors": ["Sam Worthington", "Zoe Saldana"] }})
                tryVerify(() => !nexus.docBusy && String(nexus.currentDoc?.dossier?.plot ?? "").includes("Neteyam"), 4000)
                wait(30)
                const synopsisBox = findChild(ws, "nexusDossierSynopsisBox")
                const mediaStatsCard = findChild(ws, "nexusMediaStatsCard")
                const mediaTabJournal = findChild(ws, "nexusMediaTab_journal")
                const mediaTabVideos = findChild(ws, "nexusMediaTab_videos")
                const mediaTabCast = findChild(ws, "nexusMediaTab_cast")
                const dossierLeftCard = findChild(ws, "nexusDossierLeftCard")
                const dossierRightCard = findChild(ws, "nexusDossierRightCard")
                const dossierReadArea = findChild(ws, "nexusDossierBodyReadingArea")
                const dossierRichText = findChild(ws, "nexusDossierRichMarkdownText")
                const dossierEmptyHint = findChild(ws, "nexusDossierBodyEmptyHint")
                const dossierBodyEditor = findChild(ws, "nexusDossierBodyEditor")
                check(synopsisBox !== null && synopsisBox.visible === true, "Movie synopsis box should be visible when frontmatter description is present")
                check(mediaStatsCard !== null && mediaStatsCard.visible === true && mediaTabJournal !== null && mediaTabVideos !== null && mediaTabCast !== null, "Movie Custom View must render STATISTICS hero aside card and Journal/Videos/Cast tabs matching Media.html")
                check(dossierLeftCard !== null && dossierRightCard !== null && dossierLeftCard.height >= dossierRightCard.height, "Dossier left lined-paper card height must match or exceed right sidebar height")
                check(dossierReadArea !== null && dossierReadArea.visible === true && customViewsRoot.editingNoteBody === false && dossierBodyEditor.visible === false, "Movie note content section must default to Reading mode")
                check(dossierEmptyHint !== null && dossierEmptyHint.visible === true, "Movie note with only frontmatter description must NOT duplicate the synthetic Synopsis block in the body area")
                customViewsRoot.mediaActiveTab = "cast"
                wait(20)
                check(customViewsRoot.mediaCastList.length === 2 && dossierReadArea.visible === false, "switching Media Custom View to Cast tab must show cast list and hide journal reading area")
                customViewsRoot.mediaActiveTab = "journal"
                wait(20)
                customViewsRoot.editingNoteBody = true
                wait(20)
                check(dossierBodyEditor.visible === true && dossierReadArea.visible === false, "clicking Movie note content area must switch to Editing mode")
                dossierBodyEditor.text = "## Viewing Log\\n- **Cinematography:** Stunning visuals in [[Pandora]]."
                check(ws.handleEscape() === true && customViewsRoot.editingNoteBody === false && dossierReadArea.visible === true, "Escape while editing Movie note body must save and return to Reading mode")
                tryVerify(() => !nexus.docBusy && String(nexus.getNoteBodyMarkdown() ?? "").includes("Stunning visuals"), 4000)
                wait(20)
                check(dossierRichText !== null && dossierRichText.visible === true && dossierRichText.text.includes("Viewing Log") && (dossierRichText.text.includes("Cinematography:") && dossierRichText.text.includes("<b")) && dossierRichText.text.includes("wikilink:Pandora") && !dossierRichText.text.includes("## Viewing Log"), "Movie Viewing Notes must render rich HTML instead of raw markdown source, got: " + dossierRichText.text)

                // Verify Book Custom View (`READING LOG` hero aside + `NOTEBOOK MAP`)
                nexus.openFile(nexus.collections.books[0].relPath, true)
                tryVerify(() => !nexus.docBusy && nexus.currentDoc?.noteKind === "book", 4000)
                wait(20)
                const bookReadingCard = findChild(ws, "nexusBookReadingCard")
                const bookNotebookMap = findChild(ws, "nexusBookNotebookMap")
                check(bookReadingCard !== null && bookReadingCard.visible === true && bookNotebookMap !== null && bookNotebookMap.visible === true, "Book Custom View must display READING LOG hero aside card and NOTEBOOK MAP 01..05 prompts matching Book.html")

                // Non-media Dossier notes (contact, clipping, website, teaching, vocabulary) must also reveal nexusDossierBodyEditor when clicked
                check(nexus.createCollectionEntry("contacts", "Ada Lovelace") === true, "createCollectionEntry(contacts, Ada Lovelace) failed")
                tryVerify(() => !nexus.docBusy && nexus.currentDoc?.noteKind === "contact", 4000)
                wait(20)
                check(customViewsRoot.editingNoteBody === false && dossierReadArea.visible === true && dossierBodyEditor.visible === false, "Contact dossier note must default to Reading mode")
                customViewsRoot.startPrimaryInlineEdit()
                wait(20)
                check(customViewsRoot.editingNoteBody === true && dossierBodyEditor.visible === true && dossierReadArea.visible === false, "clicking Contact dossier note body must reveal nexusDossierBodyEditor (not leave a blank card)")
                check(ws.handleEscape() === true && customViewsRoot.editingNoteBody === false && dossierReadArea.visible === true, "Escape on Contact dossier note must return to Reading mode")

                // Cornell Custom View (`Cornell.html` parity: metadata grid, bulleted Session Metadata, 30%/70% cue/notes column proportions, Active Recall & Review Schedule, Study Mode toggle, rich HTML cues/notes, empty `[[ ]]` -> Related note)
                check(nexus.createCollectionEntry("cornell", "Quantum Mechanics Lecture") === true, "createCollectionEntry(cornell) failed")
                tryVerify(() => !nexus.docBusy && nexus.currentDoc?.noteKind === "cornell", 4000)
                nexus.saveNoteBodyMarkdown("## Session Metadata\\n- **Course:** [[Alpha]]\\n- **Topic:** Quantum States\\n\\n## Cues & Questions\\n### What is wave-particle duality?\\n\\n## Notes\\n- [ ] Derive Schrodinger equation with detailed steps and physical interpretation across multiple lines\\n- Link: [[ ]]\\n\\n## Summary\\n### * Feynman Summary\\n**Key takeaway:** Matter exhibits both wave and particle properties.\\n\\n## Active Recall Questions\\n1. State the de Broglie wavelength formula.\\n\\n## Next Review\\n### V- Review Schedule\\n- [ ] **24 Hours:** Quick cue review\\n- [x] **3 Days:** Active recall test")
                tryVerify(() => !nexus.docBusy && String(nexus.currentDoc?.cornellView?.course ?? "") === "Alpha", 4000)
                wait(40)
                const cornellView = findChild(ws, "nexusCornellCustomView")
                const cornellStudyBtn = findChild(ws, "nexusCornellStudyModeButton")
                const cornellSheetCard = findChild(ws, "nexusCornellSheetCard")
                const cornellReadArea = findChild(ws, "nexusCornellBodyReadingArea")
                const cornellEditor = findChild(ws, "nexusCornellBodyEditor")
                const cornellSummaryCard = findChild(ws, "nexusCornellSummaryCard")
                const cornellRow0 = findChild(ws, "nexusCornellRow_0")
                const cornellLeft0 = findChild(ws, "nexusCornellCueLeftCol_0")
                const cornellRight0 = findChild(ws, "nexusCornellCueRightContainer_0")
                const cornellRecallSchedRow = findChild(ws, "nexusCornellRecallScheduleRow")
                const cornellHeadDiv = findChild(ws, "nexusCornellColHeadDivider")
                const cornellRowDiv0 = findChild(ws, "nexusCornellRowDivider_0")
                check(cornellView !== null && cornellView.visible === true && cornellStudyBtn !== null && cornellSheetCard !== null && cornellSummaryCard !== null, "Cornell Custom View must render header, Study mode button, sheet card, and Summary callout matching Cornell.html")
                check(cornellRow0 !== null && cornellLeft0 !== null && cornellRight0 !== null && cornellLeft0.width >= 170 && cornellLeft0.width <= cornellRow0.width * 0.42 && cornellRight0.width >= cornellRow0.width * 0.55 && (cornellLeft0.width + cornellRight0.width + 57) <= (cornellRow0.width + 1), "Cornell cue row must maintain ~30% left cue column and ~70% right notes column without squishing notes or overflowing 57px horizontal chrome (left=" + (cornellLeft0 ? cornellLeft0.width : -1) + ", right=" + (cornellRight0 ? cornellRight0.width : -1) + ", row=" + (cornellRow0 ? cornellRow0.width : -1) + ")")
                check(cornellHeadDiv !== null && cornellRowDiv0 !== null && Math.abs(cornellHeadDiv.mapToItem(cornellSheetCard, 0, 0).x - cornellRowDiv0.mapToItem(cornellSheetCard, 0, 0).x) <= 1, "Cornell column header divider and row vertical divider must align to the same X coordinate")
                check(cornellRecallSchedRow !== null && cornellRecallSchedRow.visible === true && (nexus.currentDoc?.cornellView?.recallQuestions?.length ?? 0) === 1 && (nexus.currentDoc?.cornellView?.reviewSchedule?.length ?? 0) === 2, "Cornell Custom View must parse and display Active Recall Questions and Review Schedule cards")
                check(String(nexus.currentDoc?.cornellView?.course ?? "") === "Alpha" && (nexus.currentDoc?.cornellView?.pairs?.length ?? 0) === 1 && String(nexus.currentDoc?.cornellView?.pairs?.[0]?.cue ?? "") === "What is wave-particle duality?" && String(nexus.currentDoc?.cornellView?.pairs?.[0]?.richHtml ?? "").includes("Related note") && !String(nexus.currentDoc?.cornellView?.summary ?? "").includes("Feynman Summary"), "Cornell parser must extract bulleted Course metadata, ignore Session Metadata/Review Schedule headings as cues, strip Feynman Summary subheading, and render empty [[ ]] wikilink as Related note badge")
                // Verify 2-node Local Graph (Quantum Mechanics Lecture -> Alpha) stays compact and centered without stretching to card borders
                const localGraphC = findChild(ws, "nexusLocalGraphCanvas")
                check(localGraphC !== null && (localGraphC.nodePositions?.length ?? 0) === 2, "2-node Local Graph expected when Cornell note links to [[Alpha]], got count=" + (localGraphC?.nodePositions?.length ?? -1))
                const lgP0 = localGraphC._screenPosForNode(0)
                const lgP1 = localGraphC._screenPosForNode(1)
                const lgDist = Math.hypot(lgP1.x - lgP0.x, lgP1.y - lgP0.y)
                check(lgDist >= 32 && lgDist <= Math.min(localGraphC.width, localGraphC.height) * 0.44 && lgP0.y >= 36 && lgP0.y <= localGraphC.height - 36 && lgP1.y >= 36 && lgP1.y <= localGraphC.height - 36, "2-node Local Graph must keep nodes at a compact radial distance (~36-44% max span) with >=36px top/bottom margin (dist=" + lgDist + ", p0.y=" + lgP0.y + ", p1.y=" + lgP1.y + ", h=" + localGraphC.height + ")")
                // Also verify a 6-node Local Graph (with 1-hop and 2-hop nodes) clamps total pixel span to <= 45% of min(width, height)
                const savedLocalGraph = localGraphC.graphData
                localGraphC.graphData = {{
                    "nodes": [
                        {{ "id": "n0", "title": "Center", "hop": 0, "x": 0.5, "y": 0.5 }},
                        {{ "id": "n1", "title": "Hop1-A", "hop": 1, "x": 0.5, "y": 0.27 }},
                        {{ "id": "n2", "title": "Hop1-B", "hop": 1, "x": 0.72, "y": 0.62 }},
                        {{ "id": "n3", "title": "Hop1-C", "hop": 1, "x": 0.28, "y": 0.62 }},
                        {{ "id": "n4", "title": "Hop2-A", "hop": 2, "x": 0.5, "y": 0.16 }},
                        {{ "id": "n5", "title": "Hop2-B", "hop": 2, "x": 0.84, "y": 0.74 }}
                    ],
                    "edges": [
                        {{ "source": "n0", "target": "n1" }},
                        {{ "source": "n0", "target": "n2" }},
                        {{ "source": "n0", "target": "n3" }},
                        {{ "source": "n1", "target": "n4" }},
                        {{ "source": "n2", "target": "n5" }}
                    ]
                }}
                let lgMinY = 9999, lgMaxY = -9999
                for (let k = 0; k < 6; ++k) {{
                    const sp = localGraphC._screenPosForNode(k)
                    if (sp.y < lgMinY) lgMinY = sp.y
                    if (sp.y > lgMaxY) lgMaxY = sp.y
                }}
                check((lgMaxY - lgMinY) <= Math.min(localGraphC.width, localGraphC.height) * 0.45 + 1.0 && lgMinY >= 36 && lgMaxY <= localGraphC.height - 36, "6-node Local Graph must clamp total rendered span to <=45% of min(w,h) with >=36px top/bottom margin (span=" + (lgMaxY - lgMinY) + ", minY=" + lgMinY + ", maxY=" + lgMaxY + ", h=" + localGraphC.height + ")")
                localGraphC.graphData = savedLocalGraph
                check(cornellReadArea !== null && cornellEditor !== null && customViewsRoot.editingNoteBody === false && cornellReadArea.visible === true && cornellEditor.visible === false, "Cornell note must default to Reading mode with click-to-edit")
                customViewsRoot.cornellStudyMode = true
                wait(20)
                check(findChild(ws, "nexusCornellRevealButton_0") !== null && findChild(ws, "nexusCornellRevealButton_0").visible === true, "Cornell Study mode must show Reveal explanation button on cue rows")
                customViewsRoot.cornellStudyMode = false
                customViewsRoot.startPrimaryInlineEdit()
                wait(20)
                check(customViewsRoot.editingNoteBody === true && cornellEditor.visible === true, "startPrimaryInlineEdit() on Cornell note must enter Editing mode")
                check(ws.handleEscape() === true && customViewsRoot.editingNoteBody === false, "Escape on Cornell note must return to Reading mode")

                // Zettelkasten Custom View (`Zettelkasten.html` parity: ATOMIC SLIP header, 30%/70% 2-column layout, Vietnamese headings, Markdown tables & <br>, multi-type YAML list normalization)
                check(nexus.createCollectionEntry("zettelkasten", "Emergent Complexity") === true, "createCollectionEntry(zettelkasten) failed")
                tryVerify(() => !nexus.docBusy && nexus.currentDoc?.noteKind === "zettelkasten", 4000)
                nexus.updateNoteFrontmatter({{ "type": ["Permanent", "Literature", "Fleeting"] }})
                tryVerify(() => !nexus.docBusy, 4000)
                nexus.saveNoteBodyMarkdown("# 202607151812 -\\n\\n## Tóm tắt\\nÝ tưởng cốt lõi về **Thiết kế Ngược** (Backward Design).\\n\\n## Nội dung\\n| Giai đoạn | Mô tả |\\n| :--- | :--- |\\n| 1. Kết quả | Xác định mục tiêu<br>cốt lõi |\\n\\n## Kết nối\\n- **Mở rộng từ**: [[Alpha]]\\n- **Dẫn tới**: [ ]\\n\\n## Nguồn\\n- [Understanding by Design]( )\\n\\n<center>End</center>")
                tryVerify(() => !nexus.docBusy && String(nexus.currentDoc?.zettelkastenView?.coreIdea ?? "").includes("Thiết kế Ngược"), 4000)
                wait(30)
                const zkView = findChild(ws, "nexusZettelkastenCustomView")
                const zkReadArea = findChild(ws, "nexusZettelkastenBodyReadingArea")
                const zkEditor = findChild(ws, "nexusZettelkastenBodyEditor")
                const zkBacklinksCard = findChild(ws, "nexusZettelkastenBacklinksCard")
                const zkFooter = findChild(ws, "nexusZettelkastenFooter")
                check(zkView !== null && zkView.visible === true && zkReadArea !== null && zkReadArea.visible === true && zkEditor !== null && zkEditor.visible === false && zkBacklinksCard !== null && zkBacklinksCard.visible === true && zkFooter !== null && zkFooter.visible === true, "Zettelkasten Custom View must render ATOMIC SLIP 2-column layout, always-visible Backlinks card, and footer in Reading mode")
                check(String(nexus.currentDoc?.zettelkastenView?.zettelType ?? "") === "Permanent", "Zettelkasten parser must normalize template list [Permanent, Literature, Fleeting] to 'Permanent', got: " + String(nexus.currentDoc?.zettelkastenView?.zettelType ?? ""))
                check(String(nexus.currentDoc?.zettelkastenView?.coreIdeaRichHtml ?? "").includes("Thiết kế Ngược") && String(nexus.currentDoc?.zettelkastenView?.contentRichHtml ?? "").includes("<table") && String(nexus.currentDoc?.zettelkastenView?.contentRichHtml ?? "").includes("<br/>") && !String(nexus.currentDoc?.zettelkastenView?.contentRichHtml ?? "").includes("<center>End</center>"), "Zettelkasten parser must map Vietnamese ## Tóm tắt / ## Nội dung, render Markdown tables & <br>, and strip <center>End</center>")
                check(String(nexus.currentDoc?.zettelkastenView?.connectionsRichHtml ?? "").includes("wikilink:Alpha") && String(nexus.currentDoc?.zettelkastenView?.sourcesRichHtml ?? "").includes("Understanding by Design") && (nexus.currentDoc?.zettelkastenView?.railSections?.length ?? 0) === 2, "Zettelkasten parser must extract ## Kết nối and ## Nguồn sections")

                // Finance Custom View (`Finance.html` parity: 4 KPI cards, range switcher, Balance movement canvas, Cash flow & Expense categories, Transactions ledger)
                check(nexus.createCollectionEntry("finance", "2026-11 Personal Finance") === true, "createCollectionEntry(finance) failed")
                tryVerify(() => !nexus.docBusy && nexus.currentDoc?.noteKind === "finance", 4000)
                wait(20)
                const finView = findChild(ws, "nexusFinanceCustomView")
                const finRangeMonthly = findChild(ws, "nexusFinanceRangeBtn_monthly")
                const finBalanceCanvas = findChild(ws, "nexusFinanceBalanceCanvas")
                const finNotesArea = findChild(ws, "nexusFinanceBodyReadingArea")
                check(finView !== null && finView.visible === true && finRangeMonthly !== null && finBalanceCanvas !== null && finNotesArea !== null, "Finance Custom View must render KPI cards, range switcher, Balance movement canvas, and Financial notes matching Finance.html")
                check((finView.activeCategories?.length ?? 0) >= 1 && findChild(ws, "nexusFinanceCategoryRow_Food") !== null, "Finance Custom View must populate Expense Categories breakdown from vault transactions")
                customViewsRoot.financeActiveRange = "weekly"
                wait(20)
                check(customViewsRoot.financeActiveRange === "weekly" && finView.activeTransactions.length >= 1, "Finance range switcher must filter activeTransactions reactively")
                customViewsRoot.financeActiveRange = "monthly"
                wait(20)

                // 15. Obsidian-Faithful Recipe Custom View (`nexusRecipeCustomView`)
                check(customViewsRoot.splitRecipeIngredient("6 rolls").name === "6 rolls" && customViewsRoot.splitRecipeIngredient("6 rolls").amount === "", "splitRecipeIngredient('6 rolls') must NOT fabricate 'To taste'")
                check(customViewsRoot.splitRecipeIngredient("Pork belly | 200 g").name === "Pork belly" && customViewsRoot.splitRecipeIngredient("Pork belly | 200 g").amount === "200 g", "splitRecipeIngredient('Pork belly | 200 g') must split on '|'")
                check(customViewsRoot.joinRecipeIngredient("Pork belly", "200 g") === "Pork belly | 200 g", "joinRecipeIngredient must join with ' | ' matching Obsidian Recipe.js")
                check(customViewsRoot.formatRecipeScalar("prep_time", "45") === "45 min", "numeric prep_time/cook_time must format with ' min'")
                check(nexus.createCollectionEntry("recipes", "Vietnamese Banh Mi") === true, "createCollectionEntry(recipes, Vietnamese Banh Mi) failed")
                tryVerify(() => nexus.activeView === "document" && nexus.currentDoc !== null && !nexus.docBusy && nexus.currentDoc.noteKind === "recipe", 4000)
                nexus.updateNoteFrontmatter({{
                    "recipe_category": "Street Food",
                    "cuisine": "Vietnamese",
                    "prep_time": 15,
                    "cook_time": 20,
                    "tagline": "Crispy baguette with savory pork and pickled daikon.",
                    "ingredients": ["6 rolls", "Pork belly | 200 g"],
                    "ingredients_done": [0],
                    "instructions": ["Toast the baguette until crisp.", "Layer pork, pickled daikon, and cilantro."],
                    "tips": ["Warm the baguette right before serving."],
                    "pairs_well_with": ["Vietnamese iced coffee"]
                }})
                tryVerify(() => !nexus.docBusy && (nexus.currentDoc?.recipeView?.ingredients?.length ?? 0) === 2 && (nexus.currentDoc?.recipeView?.instructions?.length ?? 0) === 2, 4000)
                wait(30)
                const recipeCustomView = findChild(ws, "nexusRecipeCustomView")
                const recipeHero = findChild(ws, "nexusRecipeHero")
                const recipePhotoCard = findChild(ws, "nexusRecipePhotoCard")
                const recipeHeroTape = findChild(ws, "nexusRecipeHeroTape")
                const recipeCategoryBadge = findChild(ws, "nexusRecipeCategoryBadge")
                const recipeFavBtn = findChild(ws, "nexusRecipeFavoriteButton")
                const recipeBmBtn = findChild(ws, "nexusRecipeBookmarkButton")
                const recipeEyebrow = findChild(ws, "nexusRecipeEyebrow")
                const recipeTitle = findChild(ws, "nexusRecipeTitle")
                const recipeTagline = findChild(ws, "nexusRecipeTagline")
                const recipeSectionNav = findChild(ws, "nexusRecipeSectionNav")
                const recipeStatsBar = findChild(ws, "nexusRecipeStatsBar")
                const recipePrepCard = findChild(ws, "nexusRecipeStatCard_prep_time")
                const recipeOverviewGrid = findChild(ws, "nexusRecipeOverviewGrid")
                const recipeDescBox = findChild(ws, "nexusRecipeDescriptionBox")
                const recipeIngCard = findChild(ws, "nexusRecipeIngredientsCard")
                const recipeIngRow0 = findChild(ws, "nexusRecipeIngredientRow_0")
                const recipeIngRow1 = findChild(ws, "nexusRecipeIngredientRow_1")
                const recipeIngName0 = findChild(ws, "nexusRecipeIngredientName_0")
                const recipeIngAmt0 = findChild(ws, "nexusRecipeIngredientAmount_0")
                const recipeIngName1 = findChild(ws, "nexusRecipeIngredientName_1")
                const recipeIngAmt1 = findChild(ws, "nexusRecipeIngredientAmount_1")
                check(customViewsRoot.recipeActiveSection === "overview", "Recipe note must default to Overview tab upon clicking/opening")
                customViewsRoot.recipeActiveSection = "all"
                wait(20)
                const recipeInstCard = findChild(ws, "nexusRecipeInstructionsCard")
                const recipeStepBtn0 = findChild(ws, "nexusRecipeStepButton_0")
                const recipeStepRail0 = findChild(ws, "nexusRecipeStepRail_0")
                const recipeTipsCard = findChild(ws, "nexusRecipeTipsCard")
                const recipePairingsCard = findChild(ws, "nexusRecipePairingsCard")
                const recipeNoteCard = findChild(ws, "nexusRecipePersonalNoteCard")
                const recipeNoteReadArea = findChild(ws, "nexusRecipePersonalNoteReadingArea")
                const recipeNoteEditor = findChild(ws, "nexusRecipePersonalNoteEditor")
                check(recipeCustomView !== null && recipeCustomView.visible === true, "nexusRecipeCustomView must be visible when a recipe note is open")
                check(recipeHero !== null && recipePhotoCard !== null && recipeHeroTape !== null && recipeCategoryBadge !== null && recipeFavBtn !== null && recipeBmBtn !== null, "missing Recipe Hero polaroid card, tape strip, category badge, or favorite/bookmark buttons")
                check(recipeEyebrow !== null && recipeEyebrow.text === "STREET FOOD · VIETNAMESE" && recipeTitle !== null && recipeTagline !== null && recipeSectionNav !== null, "missing Recipe Eyebrow, Title, Tagline, or Section Nav")
                check(recipeStatsBar !== null && recipePrepCard !== null && recipeOverviewGrid !== null && recipeDescBox !== null && recipeIngCard !== null, "missing Recipe Stats Bar, responsive Overview Grid, Description Box, or Ingredients Card")
                const recipeNutrition = findChild(ws, "nexusRecipeNutritionCard")
                check(recipeNutrition !== null && recipeNutrition.visible === true, "Recipe Overview must retain its Nutrition card")
                const expectedRecipeColumns = recipeOverviewGrid.width >= 680 ? 2 : 1
                check(recipeOverviewGrid.columns === expectedRecipeColumns, "Recipe Overview must use two columns at680px and above, otherwise stack all cards (width=" + recipeOverviewGrid.width + ", columns=" + recipeOverviewGrid.columns + ")")
                const overviewLeft = recipeDescBox.parent
                const overviewLeftPos = overviewLeft.mapToItem(recipeOverviewGrid, 0, 0)
                const overviewIngPos = recipeIngCard.mapToItem(recipeOverviewGrid, 0, 0)
                const overviewDescPos = recipeDescBox.mapToItem(recipeOverviewGrid, 0, 0)
                const overviewNutritionPos = recipeNutrition.mapToItem(recipeOverviewGrid, 0, 0)
                check([recipeDescBox, recipeNutrition, recipeIngCard].every(card => {{
                    const pos = card.mapToItem(recipeOverviewGrid, 0, 0)
                    return card.visible === true && card.width > 0 && card.height > 0 && pos.x >= -1 && pos.y >= -1 && pos.x + card.width <= recipeOverviewGrid.width + 1 && pos.y + card.height <= recipeOverviewGrid.height + 1
                }}), "Recipe Description, Nutrition, and Ingredients cards must remain visible, nonzero, and contained inside Overview in both responsive layouts")
                check(overviewNutritionPos.y >= overviewDescPos.y + recipeDescBox.height + 15 && Math.abs(overviewNutritionPos.x - overviewDescPos.x) <= 1, "Recipe Nutrition must remain below Description in the same column")
                check(expectedRecipeColumns === 1
                    ? (Math.abs(overviewIngPos.x - overviewLeftPos.x) <= 1 && overviewIngPos.y >= overviewLeftPos.y + overviewLeft.height + 17 && Math.abs(recipeIngCard.width - overviewLeft.width) <= 1)
                    : (overviewIngPos.x >= overviewLeftPos.x + overviewLeft.width + 21 && Math.abs(overviewIngPos.y - overviewLeftPos.y) <= 1), "Recipe Overview must stack Ingredients below the entire Description/Nutrition column when narrow and retain side-by-side cards with22px gutter when wide")
                check(recipeIngRow0 !== null && recipeIngRow0.isChecked === true && recipeIngRow1 !== null && recipeIngRow1.isChecked === false, "Recipe ingredients must initialize checked state from frontmatter ingredients_done")
                check(recipeIngRow0 !== null && recipeIngName0 !== null && recipeIngName0.text === "6 rolls" && recipeIngAmt0 !== null && recipeIngAmt0.text === "" && recipeIngAmt0.visible === false, "single-column ingredient '6 rolls' must display with empty hidden amount (not 'To taste')")
                check(recipeIngName1 !== null && recipeIngName1.text === "Pork belly" && recipeIngAmt1 !== null && recipeIngAmt1.text === "200 g" && recipeIngAmt1.visible === true, "pipe-separated ingredient 'Pork belly | 200 g' must display split name and amount")
                check(recipeInstCard !== null && recipeStepBtn0 !== null && recipeStepBtn0.width === 30 && recipeStepBtn0.radius === 10 && recipeStepRail0 !== null && recipeStepRail0.x === 11 && recipeTipsCard !== null && recipePairingsCard !== null, "missing Recipe Instructions Card, 30x30 radius-10 Step Checkbox/Rail, Tips Card, or Pairings Card")
                check(recipeNoteCard !== null && recipeNoteReadArea !== null && recipeNoteReadArea.visible === true && customViewsRoot.recipeEditingPersonalNote === false && recipeNoteEditor.visible === false, "Recipe Personal Note card must default to Reading mode")
                customViewsRoot.setRecipeStepProgress(2)
                tryVerify(() => !nexus.docBusy && customViewsRoot.recipeActiveStepProgress === 2 && Number(nexus.currentDoc?.recipeView?.stepsProgress ?? -1) === 2, 4000)
                customViewsRoot.recipeEditingPersonalNote = true
                wait(20)
                check(recipeNoteEditor.visible === true && recipeNoteReadArea.visible === false, "clicking Recipe Personal Note must switch to Editing mode")
                recipeNoteEditor.text = "Added extra pickled daikon and chili."
                check(ws.handleEscape() === true && customViewsRoot.recipeEditingPersonalNote === false && recipeNoteReadArea.visible === true, "Escape while editing Recipe Personal Note must save and return to Reading mode")
                tryVerify(() => !nexus.docBusy && String(nexus.currentDoc?.recipeView?.personalNotes ?? "").includes("Added extra pickled daikon and chili."), 4000)
                // Verify Cancel on Personal Note does NOT save uncancelled draft text
                customViewsRoot.recipeEditingPersonalNote = true
                wait(20)
                recipeNoteEditor.text = "SHOULD_BE_DISCARDED_ON_CANCEL"
                recipeNoteEditor._cancelingPersonalNote = true
                customViewsRoot.recipeEditingPersonalNote = false
                recipeNoteEditor._cancelingPersonalNote = false
                wait(30)
                check(!String(nexus.currentDoc?.recipeView?.personalNotes ?? "").includes("SHOULD_BE_DISCARDED_ON_CANCEL"), "Canceling Recipe Personal Note edit must not save draft text")

                // 11. Settings Shortcuts sub-tab: Workspace Card Layout removed, single button strictly opens sub-tab at standardBentoHeight
                settingsLoader.visible = true
                const openShortcutsBtn = findChild(settingsPage, "openNexusShortcutsTabButton")
                const closeShortcutsBtn = findChild(settingsPage, "closeNexusShortcutsTabButton")
                const mainSettingsTab = findChild(settingsPage, "nexusMainSettingsSubTab")
                const shortcutsScope = findChild(settingsPage, "nexusShortcutCaptureScope")
                const shortcutsFlick = findChild(settingsPage, "nexusShortcutsFlickable")
                check(openShortcutsBtn !== null && closeShortcutsBtn !== null && shortcutsFlick !== null, "missing open/close shortcuts sub-tab buttons or nexusShortcutsFlickable in NexusThemeSettings")
                check(settingsPage.shortcutsTabOpen === false && mainSettingsTab.visible === true && openShortcutsBtn.visible === true && shortcutsScope.visible === false, "shortcuts sub-tab should be closed initially with openNexusShortcutsTabButton visible")
                // Even when resized tall (1274x832) on the Main tab, openShortcutsBtn remains a single button and does NOT auto-expand inline
                settingsLoader.width = 1274
                settingsPage._resizePreviewHeight = 832
                wait(30)
                check(mainSettingsTab.visible === true && openShortcutsBtn.visible === true && shortcutsScope.visible === false, "On Main tab, Keyboard Shortcuts must remain a single button even when card is tall")
                settingsPage._resizePreviewHeight = -1
                settingsPage.shortcutsTabOpen = true
                wait(40)
                check(mainSettingsTab.visible === false && shortcutsScope.visible === true && closeShortcutsBtn.visible === true, "clicking openNexusShortcutsTabButton should switch view to shortcutsScope sub-tab")
                check(Math.abs(settingsPage.implicitHeight - settingsPage.standardSubTabTargetHeight) <= 2 && shortcutsFlick.height >= 500, "Shortcuts sub-tab card implicitHeight must match standardBentoHeight (" + settingsPage.standardSubTabTargetHeight + "), got implicitHeight=" + settingsPage.implicitHeight + ", flickH=" + shortcutsFlick.height)
                filterInput.text = "zk-prefixer"
                wait(20)
                check(shortcutsFlick.height >= 500, "When filtering shortcuts in sub-tab, nexusShortcutsFlickable must remain at standard height (>= 500px), got " + shortcutsFlick.height)
                filterInput.text = ""
                settingsPage.shortcutsTabOpen = false
                wait(20)
                check(mainSettingsTab.visible === true && openShortcutsBtn.visible === true && shortcutsScope.visible === false, "closing shortcuts sub-tab should return to main settings with button visible")
                settingsLoader.visible = false

                // 17. Window-level Alt Shortcuts, shifted number symbol normalization (Alt+Shift+1..6), secondary hotkeys, and child TextField forwarding
                const winShortcutRepeater = findChild(ws, "nexusWindowShortcutRepeater")
                const focusRecoveryTap = findChild(ws, "nexusWorkspaceFocusRecoveryTapHandler")
                check(winShortcutRepeater !== null && winShortcutRepeater.count >= 45 && focusRecoveryTap !== null, "nexusWindowShortcutRepeater must register Window-level Shortcut items (including secondary hotkeys & XKB shifted symbols) and focusRecoveryTapHandler, got count=" + (winShortcutRepeater ? winShortcutRepeater.count : -1))
                check(nexus.formatKeyEvent({{ key: Qt.Key_Exclam, text: "!", modifiers: Qt.AltModifier | Qt.ShiftModifier }}) === "Alt+Shift+1", "formatKeyEvent must normalize shifted Qt.Key_Exclam ('!') to 'Alt+Shift+1'")
                check(nexus.formatKeyEvent({{ key: Qt.Key_At, text: "@", modifiers: Qt.AltModifier | Qt.ShiftModifier }}) === "Alt+Shift+2", "formatKeyEvent must normalize shifted Qt.Key_At ('@') to 'Alt+Shift+2'")
                check(nexus.formatKeyEvent({{ key: Qt.Key_NumberSign, text: "#", modifiers: Qt.AltModifier | Qt.ShiftModifier }}) === "Alt+Shift+3", "formatKeyEvent must normalize shifted Qt.Key_NumberSign ('#') to 'Alt+Shift+3'")
                check(nexus.formatKeyEvent({{ key: Qt.Key_Dollar, text: "$", modifiers: Qt.AltModifier | Qt.ShiftModifier }}) === "Alt+Shift+4", "formatKeyEvent must normalize shifted Qt.Key_Dollar ('$') to 'Alt+Shift+4'")
                check(nexus.formatKeyEvent({{ key: Qt.Key_Percent, text: "%", modifiers: Qt.AltModifier | Qt.ShiftModifier }}) === "Alt+Shift+5", "formatKeyEvent must normalize shifted Qt.Key_Percent ('%') to 'Alt+Shift+5'")
                check(nexus.formatKeyEvent({{ key: Qt.Key_AsciiCircum, text: "^", modifiers: Qt.AltModifier | Qt.ShiftModifier }}) === "Alt+Shift+6", "formatKeyEvent must normalize shifted Qt.Key_AsciiCircum ('^') to 'Alt+Shift+6'")
                // Verify Alt+Shift+1..6 and Alt+G/Alt+C/Alt+D/Ctrl+O work via handleKeyEvent
                const prevRightOpen = nexus.rightSidebarOpen
                check(nexus.handleKeyEvent({{ key: Qt.Key_NumberSign, text: "#", modifiers: Qt.AltModifier | Qt.ShiftModifier }}) === true && String(nexus.vimStatusMessage).includes("Heading 3"), "Alt+Shift+3 (Qt.Key_NumberSign) must trigger heading3 via handleKeyEvent")
                tryVerify(() => !nexus.docBusy, 4000)
                check(nexus.handleKeyEvent({{ key: Qt.Key_C, text: "c", modifiers: Qt.AltModifier }}) === true && nexus.rightSidebarOpen === !prevRightOpen, "Alt+C secondary shortcut must toggle right sidebar")
                nexus.rightSidebarOpen = true
                check(nexus.handleKeyEvent({{ key: Qt.Key_G, text: "g", modifiers: Qt.AltModifier }}) === true && nexus.activeView === "graph", "Alt+G secondary shortcut must open Graph view")
                // Verify Alt shortcuts work even when fileFilterField holds activeFocus
                const filterField = findChild(ws, "nexusFileFilterField")
                check(filterField !== null, "missing nexusFileFilterField")
                filterField.forceActiveFocus()
                check(ws.triggerWindowShortcutAction("gotoTab3") === true && nexus.activeView === "graph", "Alt+3 (gotoTab3) must fire reliably even when a child TextField has focus")
                check(ws.triggerWindowShortcutAction("gotoTab1") === true && nexus.activeView === "homepage", "Alt+1 (gotoTab1) must fire reliably and return to Homepage")

                // 18. Verify repeated Alt+Enter / Alt+Esc / Alt+T / Alt+N / Alt+F -> Esc cycles via real Qt keyClick events preserve workspace activeFocus and all shortcuts
                const keyScope = findChild(ws, "nexusWorkspaceKeyScope")
                const cpModal = findChild(ws, "nexusCommandPaletteModal")
                const cpInput = findChild(ws, "nexusCommandPaletteInput")
                const newNoteBarItem = findChild(ws, "nexusNewNoteBar")
                const newNoteField = findChild(ws, "nexusNewNoteField")
                check(keyScope !== null && cpModal !== null && cpInput !== null && newNoteBarItem !== null && newNoteField !== null, "missing nexusWorkspaceKeyScope, nexusCommandPaletteModal, nexusCommandPaletteInput, nexusNewNoteBar, or nexusNewNoteField")
                ws.restoreWorkspaceFocus()
                wait(30)
                check(ws.activeFocus === true && keyScope.activeFocus === true, "restoreWorkspaceFocus() must give activeFocus to NexusWorkspace and nexusWorkspaceKeyScope")

                // Cycle 1: Alt+Enter (Command Palette) -> Esc
                keyClick(Qt.Key_Return, Qt.AltModifier)
                wait(40)
                check(nexus.commandPaletteOpen === true && nexus.commandPaletteMode === "commands" && cpModal.visible === true && cpInput.activeFocus === true, "Alt+Enter keyClick must open Command Palette and focus input")
                keyClick(Qt.Key_Escape, Qt.NoModifier)
                wait(40)
                check(nexus.commandPaletteOpen === false && nexus.isOpen === true && cpModal.visible === false && cpInput.activeFocus === false && cpInput.focus === false && ws.activeFocus === true && keyScope.activeFocus === true, "Esc after Alt+Enter must close only Command Palette, clear cpInput.focus, and restore activeFocus to NexusWorkspace")

                // Cycle 2: Alt+Esc (Quick Switcher) -> Esc
                keyClick(Qt.Key_Escape, Qt.AltModifier)
                wait(40)
                check(nexus.commandPaletteOpen === true && nexus.commandPaletteMode === "switcher" && cpModal.visible === true && cpInput.activeFocus === true, "Alt+Esc keyClick after Esc must open Quick Switcher and focus input")
                keyClick(Qt.Key_Escape, Qt.NoModifier)
                wait(40)
                check(nexus.commandPaletteOpen === false && nexus.isOpen === true && cpModal.visible === false && cpInput.activeFocus === false && cpInput.focus === false && ws.activeFocus === true && keyScope.activeFocus === true, "Esc after Alt+Esc must close only Quick Switcher, clear cpInput.focus, and restore activeFocus to NexusWorkspace")

                // Cycle 3: Alt+T (Quick Task) -> Esc
                keyClick(Qt.Key_T, Qt.AltModifier)
                wait(40)
                check(nexus.commandPaletteOpen === true && nexus.commandPaletteMode === "task" && cpModal.visible === true && cpInput.activeFocus === true, "Alt+T keyClick after Esc must open Quick Task modal and focus input")
                keyClick(Qt.Key_Escape, Qt.NoModifier)
                wait(40)
                check(nexus.commandPaletteOpen === false && nexus.isOpen === true && cpModal.visible === false && cpInput.activeFocus === false && cpInput.focus === false && ws.activeFocus === true && keyScope.activeFocus === true, "Esc after Alt+T must close only Quick Task modal, clear cpInput.focus, and restore activeFocus to NexusWorkspace")

                // Cycle 4: Mode switching while modal is open (Alt+Esc -> Alt+Enter -> Alt+T -> Esc)
                keyClick(Qt.Key_Escape, Qt.AltModifier)
                wait(30)
                check(nexus.commandPaletteOpen === true && nexus.commandPaletteMode === "switcher", "Alt+Esc should open Quick Switcher")
                keyClick(Qt.Key_Return, Qt.AltModifier)
                wait(30)
                check(nexus.commandPaletteOpen === true && nexus.commandPaletteMode === "commands", "Alt+Enter while Quick Switcher is open must switch mode to 'commands' rather than closing")
                keyClick(Qt.Key_T, Qt.AltModifier)
                wait(30)
                check(nexus.commandPaletteOpen === true && nexus.commandPaletteMode === "task", "Alt+T while Command Palette is open must switch mode to 'task'")
                keyClick(Qt.Key_Escape, Qt.NoModifier)
                wait(40)
                check(nexus.commandPaletteOpen === false && ws.activeFocus === true && keyScope.activeFocus === true, "Esc after mode-switching cycle must close modal and restore workspace focus")

                // Cycle 5: New Note Bar -> Esc -> Alt+F (Filter Field) -> Esc -> Alt+N -> Alt+3 -> Alt+1 -> Alt+Enter -> Esc
                newNoteBarItem.visible = true
                wait(40)
                check(newNoteBarItem.visible === true && newNoteField.activeFocus === true, "opening New Note bar must focus newNotePathField")
                keyClick(Qt.Key_Escape, Qt.NoModifier)
                wait(40)
                check(newNoteBarItem.visible === false && newNoteField.focus === false && ws.activeFocus === true && keyScope.activeFocus === true, "Esc in New Note bar must close bar and restore workspace focus")

                keyClick(Qt.Key_F, Qt.AltModifier)
                wait(40)
                check(filterField.activeFocus === true, "Alt+F after Esc cycles must focus fileFilterField")
                keyClick(Qt.Key_Escape, Qt.NoModifier)
                wait(40)
                check(filterField.activeFocus === false && filterField.focus === false && ws.activeFocus === true && keyScope.activeFocus === true, "Esc in fileFilterField must clear focus and restore workspace focus")

                keyClick(Qt.Key_N, Qt.AltModifier)
                tryVerify(() => !nexus.docBusy && nexus.activeView === "document" && String(nexus.currentPath).startsWith("00_Capture/Note-"), 4000)

                keyClick(Qt.Key_3, Qt.AltModifier)
                wait(40)
                check(nexus.activeView === "graph", "Alt+3 keyClick must switch to Graph view after Esc cycles")
                keyClick(Qt.Key_1, Qt.AltModifier)
                wait(40)
                check(nexus.activeView === "homepage", "Alt+1 keyClick must switch back to Homepage after Esc cycles")
                keyClick(Qt.Key_Return, Qt.AltModifier)
                wait(40)
                check(nexus.commandPaletteOpen === true && nexus.commandPaletteMode === "commands", "Alt+Enter must still open Command Palette after all Esc cycles")
                keyClick(Qt.Key_Escape, Qt.NoModifier)
                wait(40)
                check(nexus.commandPaletteOpen === false && ws.activeFocus === true && keyScope.activeFocus === true, "Final Esc must close Command Palette and keep activeFocus on NexusWorkspace")

                // Cycle 6: Embedded AbyssPerimeter surface (embeddedSurface=true, GlobalStates.abyssPerimeterActive=true) with host WindowShortcut Escape
                ws.embeddedSurface = true
                GlobalStates.abyssPerimeterActive = true
                ws.restoreWorkspaceFocus()
                wait(30)
                keyClick(Qt.Key_Return, Qt.AltModifier)
                wait(40)
                check(nexus.commandPaletteOpen === true && nexus.commandPaletteMode === "commands" && cpInput.activeFocus === true, "Embedded surface: Alt+Enter must open Command Palette")
                keyClick(Qt.Key_Escape, Qt.NoModifier)
                wait(40)
                check(nexus.commandPaletteOpen === false && nexus.isOpen === true && cpInput.focus === false && ws.activeFocus === true && keyScope.activeFocus === true, "Embedded surface: 1st Esc after Alt+Enter must close Command Palette without WindowShortcut ambiguity and restore focus")
                keyClick(Qt.Key_Escape, Qt.AltModifier)
                wait(40)
                check(nexus.commandPaletteOpen === true && nexus.commandPaletteMode === "switcher" && cpInput.activeFocus === true, "Embedded surface: Alt+Esc after Esc must open Quick Switcher")
                keyClick(Qt.Key_Escape, Qt.NoModifier)
                wait(40)
                check(nexus.commandPaletteOpen === false && nexus.isOpen === true && cpInput.focus === false && ws.activeFocus === true && keyScope.activeFocus === true, "Embedded surface: Esc after Alt+Esc must close Quick Switcher and restore focus")
                keyClick(Qt.Key_T, Qt.AltModifier)
                wait(40)
                check(nexus.commandPaletteOpen === true && nexus.commandPaletteMode === "task" && cpInput.activeFocus === true, "Embedded surface: Alt+T after Esc must open Quick Task modal")
                keyClick(Qt.Key_Escape, Qt.NoModifier)
                wait(40)
                check(nexus.commandPaletteOpen === false && nexus.isOpen === true && cpInput.focus === false && ws.activeFocus === true && keyScope.activeFocus === true, "Embedded surface: Esc after Alt+T must close Quick Task modal and restore focus")
                ws.embeddedSurface = false
                GlobalStates.abyssPerimeterActive = false

                // 16. Automatic NexusGraphCanvas, NexusGlobeWidget & Homepage Photo Overlay auto-theming repaint without waiting for hover
                nexus.openHomepage()
                wait(40)
                const photoCard = findChild(ws, "nexusHomepagePhotoCard")
                const photoOverlay = findChild(ws, "nexusHomepagePhotoThemeOverlay")
                check(photoCard !== null && photoOverlay !== null && photoOverlay.visible === true, "missing nexusHomepagePhotoCard or nexusHomepagePhotoThemeOverlay next to 3D Globe")
                const prevPhotoOverlayColor = String(photoOverlay.themePrimaryColor)
                const localGraphCanvas = findChild(ws, "nexusLocalGraphCanvas")
                check(vGraphCanvas.workspace === ws && localGraphCanvas !== null && localGraphCanvas.workspace === ws && fGraphCanvas.workspace === ws, "all 3 NexusGraphCanvas instances must bind workspace: root for auto-theming")
                check(String(ws.autoThemedFolderColor("25", "#73a7b3")).toLowerCase() !== "#73a7b3" && String(ws.autoThemedFolderColor("01", "#c5e4eb")).toLowerCase() !== "#c5e4eb", "autoThemedFolderColor must dynamically theme 2-digit subfolder prefixes (01..99), not just multiples of 10")
                const origPrimary = Appearance.m3colors.m3primary
                const origSecondary = Appearance.m3colors.m3secondary
                const origTertiary = Appearance.m3colors.m3tertiary
                const prevThemeCommits = ws.themeCommitCount
                const prevVaultPaintCount = vGraphCanvas.paintCount
                const prevVaultNodeHex = String(vGraphCanvas.resolvedNodeColors?.[0]?.hex ?? "")
                const prevLocalPaintCount = localGraphCanvas.paintCount
                const prevGlobePaintCount = globeWidget.paintCount
                Appearance.m3colors.m3primary = "#ff5577"
                Appearance.m3colors.m3secondary = "#cc4466"
                Appearance.m3colors.m3tertiary = "#ee8899"
                tryVerify(() => vGraphCanvas.paintCount > prevVaultPaintCount && localGraphCanvas.paintCount > prevLocalPaintCount && globeWidget.paintCount > prevGlobePaintCount, 2000)
                check(ws.themeCommitCount === prevThemeCommits + 1, "multi-property palette update while open must coalesce into 1 settled theme commit, got " + (ws.themeCommitCount - prevThemeCommits))
                check(String(photoOverlay.themePrimaryColor) !== prevPhotoOverlayColor, "nexusHomepagePhotoThemeOverlay must reactively update its theme color when Alis theme changes")
                const newVaultNodeHex = String(vGraphCanvas.resolvedNodeColors?.[0]?.hex ?? "")
                check(newVaultNodeHex.length > 0 && newVaultNodeHex !== prevVaultNodeHex && vGraphCanvas.lastPaintedNodeHex === newVaultNodeHex, "NexusGraphCanvas must rebuild resolvedNodeColors and repaint immediately when theme changes without waiting for hover (before=" + prevVaultNodeHex + ", after=" + newVaultNodeHex + ")")
                // Verify zero background work during wallpaperSelectorOpen / coverflowSelectorOpen or when closed/hidden, followed by immediate sync on reopen
                GlobalStates.wallpaperSelectorOpen = true
                const commitsBeforeWallPreview = ws.themeCommitCount
                const vaultPaintsBeforeWallPreview = vGraphCanvas.paintCount
                const sigBeforeWallPreview = ws.rawThemeSignature
                const borderBeforeWallPreview = String(ws.borderSubtle)
                Appearance.m3colors.m3primary = "#66aaff"
                Appearance.m3colors.m3outlineVariant = "#77bbff"
                wait(120)
                check(ws.themeCommitCount === commitsBeforeWallPreview && vGraphCanvas.paintCount === vaultPaintsBeforeWallPreview && ws.rawThemeSignature === sigBeforeWallPreview && String(ws.borderSubtle) === borderBeforeWallPreview, "Nexus must perform zero theme commits, rawThemeSignature evaluations, settledColors updates, or graph repaints while GlobalStates.wallpaperSelectorOpen is true")
                GlobalStates.wallpaperSelectorOpen = false
                GlobalStates.wallpaperLauncherOpen = false
                tryVerify(() => String(vGraphCanvas.lastPaintedAccentHex).toLowerCase() === "#66aaff", 2000)
                GlobalStates.coverflowSelectorOpen = true
                const commitsBeforeCoverflow = ws.themeCommitCount
                Appearance.m3colors.m3primary = "#aa66ff"
                wait(120)
                check(ws.themeCommitCount === commitsBeforeCoverflow && GlobalStates.wallpaperLauncherOpen === true, "Nexus must perform zero theme commits while coverflowSelectorOpen/wallpaperLauncherOpen is active")
                GlobalStates.coverflowSelectorOpen = false
                GlobalStates.wallpaperLauncherOpen = false
                tryVerify(() => String(vGraphCanvas.lastPaintedAccentHex).toLowerCase() === "#aa66ff", 2000)
                nexus.close()
                workspaceLoader.visible = false
                wait(20)
                const commitsWhileClosed = ws.themeCommitCount
                const vaultPaintsWhileClosed = vGraphCanvas.paintCount
                const localPaintsWhileClosed = localGraphCanvas.paintCount
                const globePaintsWhileClosed = globeWidget.paintCount
                const sigWhileClosed = ws.rawThemeSignature
                Appearance.m3colors.m3primary = "#44dd99"
                Appearance.m3colors.m3secondary = "#33bb88"
                wait(120)
                check(ws.themeCommitCount === commitsWhileClosed && ws.rawThemeSignature === sigWhileClosed && vGraphCanvas.paintCount === vaultPaintsWhileClosed && localGraphCanvas.paintCount === localPaintsWhileClosed && globeWidget.paintCount === globePaintsWhileClosed, "Nexus must perform zero theme commits, rawThemeSignature updates, or canvas repaints while closed/hidden")
                workspaceLoader.visible = true
                nexus.open()
                tryVerify(() => String(vGraphCanvas.lastPaintedAccentHex).toLowerCase() === "#44dd99" && String(globeWidget.lastPaintedAccentHex).toLowerCase() === "#44dd99", 2000)
                Appearance.m3colors.m3primary = origPrimary
                Appearance.m3colors.m3secondary = origSecondary
                Appearance.m3colors.m3tertiary = origTertiary
                wait(20)

                // 19. Verify 6 User Requirements (Daily Snapshot, Alis Weather Sync, Journal Sidebar Auto-Theming, Full-Viewport Note Expansion, Exercise Live Preview Edit & Compact Layout & Legend, Recipe Base Auto-Theming & Cover Crop)
                const outlinerFlick = findChild(ws, "nexusHybridOutlinerPane")
                const linkedRefsDiv = findChild(ws, "nexusLinkedReferencesDivider")
                const linkedRefsHdr = findChild(ws, "nexusLinkedReferencesHeader")
                check(outlinerFlick !== null && linkedRefsDiv !== null && linkedRefsHdr !== null, "missing nexusHybridOutlinerPane, nexusLinkedReferencesDivider, or nexusLinkedReferencesHeader")

                // 19a. Journal: Alis Weather Sync (auto-persist on async arrival + manual sync), Daily Snapshot clean background & wikilink stripping, Right Sidebar Auto-Theming, and Linked References below fold
                Weather.data = Object.assign({{}}, Weather.data, {{ description: "", temp: "--", humidity: "0%" }})
                nexus.openDailyNote("2031-02-03")
                tryVerify(() => !nexus.docBusy && !nexus.scanBusy && nexus.currentDoc?.noteKind === "journal", 4000)
                check(String(nexus.currentDoc?.journalView?.weather ?? "") === "", "Weather fixture must use its own unrecorded Journal")
                // Simulate HostServices.Weather finishing its fetch while an unrecorded Daily Note is open
                Weather.data = Object.assign({{}}, Weather.data, {{ description: "Partly cloudy", temp: "26°C", humidity: "64%" }})
                check(nexus.hasAlisWeather === true && nexus.alisWeatherSummary === "Partly cloudy, 26°C, 64% RH", "NexusService must format live Alis Weather data into alisWeatherSummary, got: " + nexus.alisWeatherSummary)
                tryVerify(() => !nexus.docBusy && !nexus.scanBusy && String(nexus.currentDoc?.journalView?.weather ?? "") === "Partly cloudy, 26°C, 64% RH", 4000)
                Weather.data = Object.assign({{}}, Weather.data, {{ description: "Later weather", temp: "30°C", humidity: "70%" }})
                wait(80)
                check(String(nexus.currentDoc?.journalView?.weather ?? "") === "Partly cloudy, 26°C, 64% RH", "Automatic updates must preserve already recorded Journal weather")
                nexus.dailySchedule = {{
                    "available": true,
                    "exerciseRows": [{{ "exercise": "[[Romanian_Deadlift|Romanian Deadlift]]", "equipment": "**Barbell**", "reps": "10", "sets": "4" }}],
                    "cardioRows": [{{ "exercise": "[[Incline_Walk|Incline Walk]]", "equipment": "Treadmill", "duration": "20m", "intensity": "Moderate" }}]
                }}
                wait(30)
                const jSnapshotCard = findChild(ws, "nexusJournalSnapshotCard")
                const jSchedulePane = findChild(ws, "nexusJournalSchedulePane")
                const jTrainingPane = findChild(ws, "nexusJournalTrainingPane")
                const jCardioPane = findChild(ws, "nexusJournalCardioPane")
                const jTrainEx0 = findChild(ws, "nexusJournalTrainingExerciseName_0")
                const jTrainSets0 = findChild(ws, "nexusJournalTrainingSetsReps_0")
                const jCardioName0 = findChild(ws, "nexusJournalCardioName_0")
                const jWeatherField = findChild(ws, "nexusJournalWeatherField")
                const jWeatherFieldBg = findChild(ws, "nexusJournalWeatherFieldBg")
                check(jSnapshotCard !== null && String(jSnapshotCard.color) === String(dailyFolioCard.color) && jSchedulePane.color.a === 0 && jTrainingPane.color.a === 0 && jCardioPane.color.a === 0, "DAILY SNAPSHOT must use the same base background color as Daily Log with transparent sub-panes (no grey backgrounds)")
                check(jTrainEx0 !== null && jTrainEx0.text === "Romanian Deadlift" && jTrainSets0 !== null && jTrainSets0.text === "4×10" && jCardioName0 !== null && jCardioName0.text === "Incline Walk", "DAILY SNAPSHOT TRAINING & CARDIO must strip wikilink/markdown syntax and render object-formatted rows cleanly without empty grey pills (got name=" + (jTrainEx0 ? jTrainEx0.text : "null") + ", setsReps=" + (jTrainSets0 ? jTrainSets0.text : "null") + ")")
                check(customViewsRoot.stripPlainMarkdown("**In the morning.** Revisited [[Rust Ownership|Rust notes]]") === "In the morning. Revisited Rust notes", "stripPlainMarkdown must strip bold and wikilinks for ON THIS DAY snippets")
                check(jWeatherField !== null && jWeatherField.text === "Partly cloudy, 26°C, 64% RH", "Journal WEATHER field must sync with Alis Weather service, got: " + (jWeatherField ? jWeatherField.text : "null"))
                check(String(rightRailCard.color) === String(dailyFolioCard.color), "Journal right sidebar must use the exact same base background color as Daily Log")
                check(jWeatherFieldBg !== null && String(jWeatherFieldBg.color) === String(customViewsRoot.journalSubSurfaceBg) && String(weightCard.color) === String(customViewsRoot.journalSubSurfaceBg), "Journal right sidebar sub-cards must use Auto-Theming journalSubSurfaceBg")
                check(linkedRefsDiv.y >= outlinerFlick.height && linkedRefsHdr.y > outlinerFlick.height, "Journal note must expand to fill viewport height so Linked References is pushed below the fold (linkedRefsDiv.y=" + linkedRefsDiv.y + ", flickH=" + outlinerFlick.height + ")")

                // 19b. Exercise Note: Compact media card, inline Live Preview Edit with Personal Notes & Tips, right-aligned muscle legend, and Linked References below fold
                nexus.openFile(nexus.collections.exercises[0].relPath, true)
                tryVerify(() => !nexus.docBusy && nexus.currentDoc?.noteKind === "exercise", 4000)
                wait(30)
                const exMapLegend = findChild(ws, "nexusExerciseMapLegend")
                const exLiveEditBox = findChild(ws, "nexusExerciseLivePreviewEditBox")
                const exBodyEditor = findChild(ws, "nexusExerciseBodyEditor")
                const exTipsSection = findChild(ws, "nexusExerciseTipsSection")
                check(exMediaFrame.width === 292 && exMediaFrame.height === 152, "Exercise media frame must be compact (292x152), got " + exMediaFrame.width + "x" + exMediaFrame.height)
                check(exMapLegend !== null && (exMapLegend.x + exMapLegend.width) >= (exMapLegend.parent.width - 4), "Exercise TARGET MAP Primary/Secondary legend must be right-aligned in header (x=" + (exMapLegend ? exMapLegend.x : -1) + ", w=" + (exMapLegend ? exMapLegend.width : -1) + ", parentW=" + (exMapLegend ? exMapLegend.parent.width : -1) + ")")
                check(exAnatomyCard !== null && exProfileCard !== null && exNotebookCard !== null && (exProfileCard.y + exProfileCard.height) <= (exNotebookCard.height + 2), "Exercise TARGET MAP and MOVEMENT PROFILE must fit within the lower row height without overflowing")
                check(linkedRefsDiv.y >= outlinerFlick.height && linkedRefsHdr.y > outlinerFlick.height, "Exercise note must expand to fill viewport height so Linked References is below the fold (linkedRefsDiv.y=" + linkedRefsDiv.y + ", flickH=" + outlinerFlick.height + ")")
                check(customViewsRoot.startPrimaryInlineEdit() === true, "startPrimaryInlineEdit() on Exercise note must succeed")
                wait(20)
                check(nexus.editorMode === "hybrid" && customViewsRoot.editingNoteBody === true && exLiveEditBox !== null && exLiveEditBox.visible === true && exBodyEditor !== null && exBodyEditor.visible === true, "Clicking Instructions on Exercise note must open inline Live Preview Edit in hybrid mode (NOT raw Source Edit)")
                exBodyEditor.text = "## Instructions\\n1. Brace core and hinge hips\\n2. Return under control\\n\\n## Personal Notes\\n- Keep neutral spine throughout\\n- Pause 1s at bottom"
                wait(20)
                check(customViewsRoot.parseLiveExerciseSteps(exBodyEditor.text).length === 2 && customViewsRoot.parseLiveExerciseTips(exBodyEditor.text).length === 2 && exTipsSection !== null && exTipsSection.visible === true, "Exercise Live Preview Edit must separate numbered steps and personal notes/tips live while editing")
                check(ws.handleEscape() === true && customViewsRoot.editingNoteBody === false && nexus.editorMode === "hybrid", "Escape in Exercise Live Preview Edit must commit and return to reading view")
                tryVerify(() => !nexus.docBusy && !nexus.scanBusy, 4000)
                wait(30)
                const exTip0 = findChild(ws, "nexusExerciseTip_0")
                check(exTipsSection !== null && exTipsSection.visible === true && exTip0 !== null && exTip0.visible === true, "Personal Notes & Tips in Exercise note must remain visible after saving")

                // 19c. Movie Dossier, Recipe Note (with Nutrition & Macros card, section expansion & step Live Preview Edit), Standard Markdown Note, and Recipe Base Auto-Theming + macro chips
                nexus.openFile(nexus.collections.movies[0].relPath, true)
                tryVerify(() => !nexus.docBusy && nexus.currentDoc?.noteKind === "movie", 4000)
                wait(30)
                check(linkedRefsDiv.y >= outlinerFlick.height && linkedRefsHdr.y > outlinerFlick.height, "Movie note Viewing Notes must expand to fill viewport height so Linked References is below the fold (linkedRefsDiv.y=" + linkedRefsDiv.y + ", flickH=" + outlinerFlick.height + ")")

                nexus.openFile(nexus.collections.recipes[0].relPath, true)
                tryVerify(() => !nexus.docBusy && nexus.currentDoc?.noteKind === "recipe", 4000)
                nexus.updateNoteFrontmatter({{
                    "description": "This Vietnamese recipe takes around 45 minutes and has 24g of protein, 21g of fat, and a total of 477 calories. For $2.44 per serving, this recipe covers 22% of your daily requirements of vitamins and minerals with a spoonacular score of 88%."
                }})
                tryVerify(() => !nexus.docBusy && !nexus.scanBusy, 4000)
                wait(30)
                const rcNutriCard = findChild(ws, "nexusRecipeNutritionCard")
                const rcMacroCal = findChild(ws, "nexusRecipeMacroValue_calories")
                const rcMacroProt = findChild(ws, "nexusRecipeMacroValue_protein")
                const rcMacroFat = findChild(ws, "nexusRecipeMacroValue_fat")
                const rcMacroCarbs = findChild(ws, "nexusRecipeMacroValue_carbs")
                const rcCostBadge = findChild(ws, "nexusRecipeCostBadgeText")
                const rcScoreBadge = findChild(ws, "nexusRecipeScoreBadgeText")
                check(rcNutriCard !== null && rcNutriCard.visible === true && rcMacroCal !== null && rcMacroCal.text === "477 kcal" && rcMacroProt !== null && rcMacroProt.text === "24g" && rcMacroFat !== null && rcMacroFat.text === "21g" && rcMacroCarbs !== null && rcMacroCarbs.text === "~48g", "Recipe Note must render Nutrition & Macros breakdown card from frontmatter/Spoonacular description (got cal=" + (rcMacroCal ? rcMacroCal.text : "null") + ", prot=" + (rcMacroProt ? rcMacroProt.text : "null") + ", fat=" + (rcMacroFat ? rcMacroFat.text : "null") + ", carbs=" + (rcMacroCarbs ? rcMacroCarbs.text : "null") + ")")
                check(rcCostBadge !== null && rcCostBadge.text === "$2.44 / serving" && rcScoreBadge !== null && rcScoreBadge.text === "Score 88%", "Recipe Note Nutrition card must display cost per serving and Spoonacular health score badges")
                check(linkedRefsDiv.y >= outlinerFlick.height && linkedRefsHdr.y > outlinerFlick.height, "Recipe note (All sections) must expand to fill viewport height so Linked References is below the fold")
                customViewsRoot.recipeActiveSection = "overview"
                wait(25)
                check(linkedRefsDiv.y >= outlinerFlick.height, "Recipe note (Overview section) must expand to keep Linked References below the fold")
                const primaryRecipePath = nexus.currentPath
                const primaryRecipeEditor = findChild(ws, "nexusRecipePersonalNoteEditor")
                check(ws.triggerWindowShortcutAction("togglePreviewMode") === true, "Recipe primary edit shortcut must be handled from Overview")
                wait(30)
                check(nexus.editorMode === "hybrid" && customViewsRoot.recipeActiveSection === "notes" && customViewsRoot.recipeEditingPersonalNote === true && primaryRecipeEditor !== null && primaryRecipeEditor.visible === true, "Recipe primary edit from Overview must reveal inline personal notes in hybrid mode")
                primaryRecipeEditor.text = "Recipe primary inline shortcut persisted."
                check(ws.handleEscape() === true, "Escape must commit Recipe primary inline edit")
                tryVerify(() => !nexus.docBusy && String(nexus.currentDoc?.recipeView?.personalNotes ?? "").includes("Recipe primary inline shortcut persisted."), 4000)
                nexus.openFile(primaryRecipePath, true)
                tryVerify(() => !nexus.docBusy && nexus.currentDoc?.noteKind === "recipe", 4000)
                check(String(nexus.currentDoc?.recipeView?.personalNotes ?? "").includes("Recipe primary inline shortcut persisted."), "Reopening Recipe must read the saved primary inline edit")
                check(ws.triggerWindowShortcutAction("togglePreviewMode") === true, "Recipe primary edit must reopen from Overview")
                wait(30)
                primaryRecipeEditor.text = "DISCARD_PRIMARY_RECIPE_CANCEL"
                primaryRecipeEditor._cancelingPersonalNote = true
                customViewsRoot.recipeEditingPersonalNote = false
                primaryRecipeEditor._cancelingPersonalNote = false
                wait(40)
                check(!String(nexus.currentDoc?.recipeView?.personalNotes ?? "").includes("DISCARD_PRIMARY_RECIPE_CANCEL"), "Canceling Recipe primary edit must preserve the saved personal note")
                customViewsRoot.recipeActiveSection = "method"
                wait(25)
                check(linkedRefsDiv.y >= outlinerFlick.height, "Recipe note (Method section) must expand to keep Linked References below the fold")
                customViewsRoot.recipeActiveSection = "all"
                wait(25)

                nexus.openFile("10_Projects/Alpha.md", true)
                tryVerify(() => !nexus.docBusy && nexus.currentDoc?.noteKind === "standard", 4000)
                wait(30)
                check(linkedRefsDiv.y >= outlinerFlick.height && linkedRefsHdr.y > outlinerFlick.height, "Standard markdown note must expand to fill viewport height so Linked References is below the fold (linkedRefsDiv.y=" + linkedRefsDiv.y + ", flickH=" + outlinerFlick.height + ")")

                nexus.openCollection("recipes")
                wait(30)
                const rcCard0 = findChild(ws, "nexusRecipeBaseCard_0")
                const rcCover0 = findChild(ws, "nexusRecipeBaseCover_0")
                const rcCoverImg0 = findChild(ws, "nexusRecipeBaseCoverImage_0")
                const rcCalPill0 = findChild(ws, "nexusRecipeBaseCaloriesPill_0")
                const rcMacroRow0 = findChild(ws, "nexusRecipeBaseMacroRow_0")
                check(rcCard0 !== null && rcCover0 !== null && rcCoverImg0 !== null, "missing nexusRecipeBaseCard_0, nexusRecipeBaseCover_0, or nexusRecipeBaseCoverImage_0 in Recipe Base")
                check(String(rcCard0.color) === String(Qt.color(ws.ccStop(2))), "Recipe Base card must use Alis Auto-Theming surface color instead of hardcoded #1b1e26")
                check(rcCalPill0 !== null && rcCalPill0.visible === true && rcMacroRow0 !== null && rcMacroRow0.visible === true && rcCard0.rcTimeDisplay === "35 min" && rcCard0.rcMacroChips.length === 4, "Recipe Base card must parse Spoonacular calories, macros, and time into cover pill and macro chips (got time=" + rcCard0.rcTimeDisplay + ", chips=" + JSON.stringify(rcCard0.rcMacroChips) + ")")

                // Built-in PDF Viewer opens .pdf inside Document view without external dispatch
                nexus.openFile("20_Notes/Manual.pdf", true)
                tryVerify(() => !nexus.docBusy && nexus.activeView === "document" && nexus.currentDoc && nexus.currentDoc.category === "pdf", 4000)
                const pdfLoader = findChild(ws, "nexusPdfViewerLoader")
                check(pdfLoader !== null && pdfLoader.shouldLoad === true, "nexusPdfViewerLoader should activate on .pdf file")

                console.info("ALIS_NEXUS_QML_RUNTIME_PASS")
            }} catch (e) {{
                console.error("ALIS_NEXUS_QML_RUNTIME_FAIL", e.message, e.stack)
            }}
            Qt.quit()
        }}
    }}
    Timer {{ interval: 100; running: true; onTriggered: test.runChecks() }}
}}
"""
        )

        runtime = private / "runtime"
        runtime.mkdir(mode=0o700)
        env = dict(
            os.environ,
            QT_QPA_PLATFORM="offscreen",
            QT_QUICK_BACKEND="software",
            XDG_RUNTIME_DIR=str(runtime),
            XDG_CONFIG_HOME=str(private / "config"),
            XDG_STATE_HOME=str(private / "state"),
            XDG_CACHE_HOME=str(private / "cache"),
            XDG_DATA_HOME=str(private / "data"),
            ALIS_NEXUS_DISABLE_XDG_OPEN="1",
            ALIS_NEXUS_HEADLESS_SERVICE_ONLY="1",
        )
        env.pop("NIRI_SOCKET", None)
        env.pop("HYPRLAND_INSTANCE_SIGNATURE", None)
        with private_wayland(private) as wayland_env:
            if wayland_env is not None:
                env.update({k: v for k, v in wayland_env.items() if k in ("WAYLAND_DISPLAY", "NIRI_SOCKET", "DISPLAY", "XDG_RUNTIME_DIR")})
                env["QT_QPA_PLATFORM"] = "wayland"
            result = run_qs(shell, env, timeout=30)
        if result.returncode or "ALIS_NEXUS_QML_RUNTIME_PASS" not in result.stdout or "ALIS_NEXUS_QML_RUNTIME_FAIL" in result.stdout:
            print(result.stdout)
            raise SystemExit(1)


def test_real_vault_notes_obsidian_nexus_compatibility():
    """Verify on temporary copies of real vault notes that Nexus mutations keep notes 100% valid for Obsidian."""
    import shutil
    real_vault = Path("/home/llocphann/Shared_Documents/Obsidian-Vault")
    if not real_vault.is_dir():
        return

    with tempfile.TemporaryDirectory(prefix="alis-nexus-obsidian-compat-") as tmp:
        vault = Path(tmp) / "Obsidian-Compat-Vault"
        vault.mkdir(parents=True)

        # Copy quotes.js so quote API enrichment works offline
        if (real_vault / "90_System/92_Scripts/quotes.js").is_file():
            (vault / "90_System/92_Scripts").mkdir(parents=True, exist_ok=True)
            shutil.copy2(real_vault / "90_System/92_Scripts/quotes.js", vault / "90_System/92_Scripts/quotes.js")

        # Real existing vault notes across all categories in /home/llocphann/Shared_Documents/Obsidian-Vault
        sample_candidates = [
            ("00_Capture/01_Journal/2024/August/04-08-2024-Sunday.md", "journal"),
            ("20_Personal_Life/25_Media_Tracker/Movies/World War Z.md", "movie"),
            ("20_Personal_Life/25_Media_Tracker/TV_Series/Breaking Bad.md", "tvseries"),
            ("20_Personal_Life/27_Game_Tracker/Games/Hollow Knight.md", "game"),
            ("20_Personal_Life/24_Book_Tracker/Books/A_Game_of_Thrones.md", "book"),
            ("20_Personal_Life/26_Food_&_Drinks/Recipes/Vietnamese Banh Mi.md", "recipe"),
            ("20_Personal_Life/33_Bodybuilding/Gym_n_Calisthenics_Exercises/Barbell_Bench_Press_-_Medium_Grip.md", "exercise"),
            ("20_Personal_Life/23_Places/Tourist/Bãi Bàng - Hòn Sơn.md", "place"),
            ("20_Personal_Life/29_Contact/Dad.md", "contact"),
            ("00_Capture/02_Cornell/Sample — Quang hợp cơ bản.md", "cornell"),
            ("00_Capture/02_Cornell/shda.md", "cornell"),
            ("99_Archives/Zettlekasten_Archives/202607131817 - Assignment on Wednesday.md", "zettelkasten"),
            ("99_Archives/Zettlekasten_Archives/202607151812 - bài tập nhóm (tóm tắt).md", "zettelkasten"),
            ("99_Archives/Zettlekasten_Archives/202607151817 - Tóm tắt video.md", "zettelkasten"),
            ("99_Archives/Zettlekasten_Archives/202607161009 - HOẠT ĐỘNG 5 RÈN LUYỆN KỸ NĂNG HÓA GIẢI MÂU THUẪN, XUNG ĐỘT VÀ QUAN TÂM CHĂM SÓC NGƯỜI THÂN TRONG GIA ĐÌNH.md", "zettelkasten"),
            ("99_Archives/Zettlekasten_Archives/202607261024 - My vault inspired by these sources.md", "zettelkasten"),
            ("99_Archives/Zettlekasten_Archives/202608071114 - Quick Note.md", "zettelkasten"),
        ]
        copied = []
        for rel, expected_kind in sample_candidates:
            src = real_vault / rel
            if src.is_file():
                dst = vault / rel
                dst.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(src, dst)
                copied.append((rel, expected_kind))

        assert len(copied) == 17, f"Expected all 17 real vault notes copied for compatibility test, got {len(copied)}"

        # Also test new Contact, Teaching, and Vocabulary note creation & roundtrip
        for kind, rel_path, title in [
            ("contact", "20_Personal_Life/23_Contact/Ada Lovelace.md", "Ada Lovelace"),
            ("teaching", "10_Projects/B1-VSTEP Session 1.md", "B1-VSTEP Session 1"),
            ("vocabulary", "20_Personal_Life/Academic Collocations.md", "Academic Collocations"),
        ]:
            created, _ = run_cli("create", "--vault", str(vault), "--path", rel_path, "--kind", kind, "--title", title)
            assert created["ok"] is True and created["noteKind"] == kind, f"Expected noteKind={kind}, got {created.get('noteKind')}"

        for rel, expected_kind in copied:
            before_text = (vault / rel).read_text(encoding="utf-8")
            has_dvjs = "```dataviewjs" in before_text
            doc, _ = run_cli("read", "--vault", str(vault), "--path", rel)
            assert doc["ok"] is True
            assert doc["noteKind"] == expected_kind, f"Expected {expected_kind} for {rel}, got {doc['noteKind']}"
            if expected_kind == "game":
                assert len(str(doc["dossier"].get("platform", "")).strip()) > 0, f"Expected non-empty dossier.platform extracted from plural Platforms key for {rel}"
            if expected_kind == "recipe":
                rv = doc.get("recipeView") or {}
                assert rv.get("recipeCategory") == "Vietnamese", f"Expected Vietnamese recipeCategory for {rel}, got {rv.get('recipeCategory')}"
                assert rv.get("cuisine") == "Vietnamese", f"Expected Vietnamese cuisine for {rel}, got {rv.get('cuisine')}"
                assert rv.get("tagline") == "Dairy Free", f"Expected Dairy Free tagline for {rel}, got {rv.get('tagline')}"
                assert len(rv.get("ingredients") or []) == 15, f"Expected 15 ingredients for {rel}, got {len(rv.get('ingredients') or [])}"
                assert len(rv.get("instructions") or []) == 6, f"Expected 6 instructions for {rel}, got {len(rv.get('instructions') or [])}"
                assert len(rv.get("instructionDone") or []) == 6, f"Expected 6 instructionDone flags for {rel}, got {len(rv.get('instructionDone') or [])}"
            if expected_kind == "cornell":
                cv = doc.get("cornellView") or {}
                cues = cv.get("cues") or []
                assert len(cues) >= 5, f"Expected >=5 cues in {rel}, got {len(cues)}"
                for c in cues:
                    assert str(c.get("title") or "").strip().lower() != str(c.get("label") or "").strip().lower(), (
                        f"Cornell cue title must not repeat badge label verbatim in {rel}: {c}"
                    )
            if expected_kind == "zettelkasten":
                zv = doc.get("zettelkastenView") or {}
                assert zv.get("zettelType") in ("Permanent", "Literature", "Fleeting"), f"Expected normalized zettelType for {rel}, got {zv.get('zettelType')}"
                assert len(str(zv.get("coreIdeaRichHtml") or "")) > 0, f"Expected non-empty coreIdeaRichHtml for {rel}"
                assert len(str(zv.get("contentRichHtml") or "")) > 0, f"Expected non-empty contentRichHtml for {rel}"
                assert "Một câu duy nhất mô tả cốt lõi" not in str(zv.get("coreIdea") or ""), f"Unedited template placeholder callout leaked into coreIdea for {rel}"
                assert "<center>End</center>" not in str(zv.get("contentRichHtml") or ""), f"Unexpected <center>End</center> in contentRichHtml for {rel}"
                if "202607151812" in rel:
                    assert "<table" in str(zv.get("contentRichHtml") or ""), f"Expected HTML table in contentRichHtml for {rel}"
                    assert "Gồm Hoạt động Khởi động" in str(zv.get("coreIdea") or "") and "Gồm Hoạt động Khởi động" not in str(zv.get("contentSection") or ""), f"Subtitle line duplicated across coreIdea and contentSection in {rel}"
                if "202608071114" in rel:
                    assert "## CỤM 6: NỘI DUNG GIÁO DỤC" in str(zv.get("contentSection") or ""), f"Custom cluster heading ## CỤM 6: NỘI DUNG GIÁO DỤC was swallowed in {rel}"
                    assert "<i>Giáo dục cơ bản" in str(zv.get("contentRichHtml") or ""), f"Expected _italic_ rendering in contentRichHtml for {rel}"
                if "202607131817" in rel:
                    assert "href=\"https://www.google.com/search?q=https%3A%2F%2Fwww.youtube.com%2Fwatch%3Fv%3DeYi2pgCt800" in str(zv.get("contentRichHtml") or ""), f"Expected [[01:06](url)] link in contentRichHtml for {rel}"
                    assert int(zv.get("connectionCount") or 0) >= 20, f"Expected connectionCount >= 20 for {rel}, got {zv.get('connectionCount')}"
                if "202607261024" in rel:
                    assert int(zv.get("connectionCount") or 0) == 5, f"Expected connectionCount == 5 bare URLs for {rel}, got {zv.get('connectionCount')}"

            # Update frontmatter via Nexus set-frontmatter and verify Obsidian dataviewjs blocks & YAML delimiters stay intact
            if expected_kind == "journal":
                upd, _ = run_cli(
                    "set-frontmatter",
                    "--vault",
                    str(vault),
                    "--path",
                    rel,
                    "--json",
                    json.dumps({"mood": 5, "Highlight": "Synchronized with Dashboard Weekly Planner"}),
                )
                assert upd["ok"] is True
                log_saved, _ = run_cli(
                    "journal-save-log",
                    "--vault",
                    str(vault),
                    "--path",
                    rel,
                    "--content",
                    "- Completed Obsidian <-> Nexus compatibility verification.",
                )
                assert log_saved["ok"] is True
                assert "Completed Obsidian <-> Nexus compatibility verification." in log_saved["journalView"]["dailyLogText"]
            else:
                orig_status = doc["dossier"].get("status", "Watched")
                upd, _ = run_cli(
                    "set-frontmatter",
                    "--vault",
                    str(vault),
                    "--path",
                    rel,
                    "--json",
                    json.dumps({"status": orig_status}),
                )
                assert upd["ok"] is True

            after_text = (vault / rel).read_text(encoding="utf-8")
            assert after_text.startswith("---\n"), f"YAML frontmatter header broken in {rel}"
            assert "\n---\n" in after_text[4:], f"YAML frontmatter closing delimiter broken in {rel}"
            if has_dvjs:
                assert "```dataviewjs" in after_text, f"Obsidian dataviewjs block was lost in {rel}"
            re_doc, _ = run_cli("read", "--vault", str(vault), "--path", rel)
            assert re_doc["noteKind"] == expected_kind, f"noteKind changed after Nexus edit in {rel}"


if __name__ == "__main__":
    test_rust_engine()
    test_real_vault_notes_obsidian_nexus_compatibility()
    test_qml_workspace_runtime()
    print("ALIS_NEXUS_PASS Rust engine scan/graph/outliner/calendar/external/schedule/hotkeys/custom-views/api-sync/finance + Obsidian-compat + QML workspace/vim/planner-sync/Bases/Overlay-Window")



