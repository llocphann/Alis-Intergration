#!/usr/bin/env python3
"""Regression tests for independent Markdown note Todo parsing/mutation."""
from __future__ import annotations

import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path

TODO_DIR = Path(__file__).resolve().parent.parent / "plugins/nexus/scripts/todo"
sys.path.insert(0, str(TODO_DIR))
SCRIPT = TODO_DIR / "nexus_daily_todo.py"
SPEC = importlib.util.spec_from_file_location("nexus_daily_todo", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
daily = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(daily)


class DailyTodoTests(unittest.TestCase):
    def make_vault(self, body: str, day: str = "2026-09-22"):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        vault = Path(tmp.name) / "Vault"
        note = vault / "00_Capture/01_Journal/2026/September/22-09-2026-Tuesday.md"
        note.parent.mkdir(parents=True)
        note.write_text(body, encoding="utf-8")
        return vault, note, day

    def scan(self, body: str):
        vault, note, day = self.make_vault(body)
        return vault, note, daily.scan_daily_note(str(vault), day=day)

    def test_arbitrary_heading_name_is_supported(self):
        vault, note, day = self.make_vault("## Focus Queue\n- [ ] one\n## Daily Log\n")
        result = daily.scan_daily_note(
            str(vault), day=day, heading="Focus Queue", heading_level=2
        )
        self.assertEqual([task["content"] for task in result["tasks"]], ["one"])

    def test_fixed_root_note_path_is_supported(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        vault = Path(tmp.name) / "Vault"
        vault.mkdir()
        note = vault / "Tasks.md"
        note.write_text("## Tasks\n- [ ] one\n", encoding="utf-8")
        _, path, resolved, _ = daily.resolve_daily_note(
            str(vault), folder="", fmt="Tasks.md", day="2026-09-22"
        )
        self.assertEqual(path, "Tasks.md")
        self.assertEqual(resolved, note.resolve())

    def test_resolves_real_vault_daily_note_pattern(self):
        vault, note, day = self.make_vault("## Tasks\n\n## Daily Log\n")
        _, path, resolved, parsed = daily.resolve_daily_note(str(vault), day=day)
        self.assertEqual(path, "00_Capture/01_Journal/2026/September/22-09-2026-Tuesday.md")
        self.assertEqual(resolved, note.resolve())
        self.assertEqual(parsed.isoformat(), day)

    def test_scans_only_exact_task_heading_section(self):
        _, _, result = self.scan(
            "~~~md\n## Tasks\n- [ ] fake\n~~~\n"
            "## Tasks\n- [ ] real\n### Child heading\n- [x] child\n"
            "## Daily Log\n- [ ] outside\n"
        )
        self.assertEqual([task["content"] for task in result["tasks"]], ["real", "child"])
        self.assertEqual([task["done"] for task in result["tasks"]], [False, True])

    def test_parses_groups_time_blocks_and_unscheduled_tasks(self):
        _, _, result = self.scan(
            "## Tasks\n"
            "**In the morning,**\n"
            "- [ ] 08:30 - 10:00 Reading vocabulary\n"
            "- [ ] Buy coffee\n"
            "**In the afternoon,**\n"
            "- [x] 15:30 Tutor ✅ 2026-09-22\n"
            "## Daily Log\n"
        )
        timed, plain, done = result["tasks"]
        self.assertEqual(
            (timed["content"], timed["startTime"], timed["endTime"], timed["durationMinutes"]),
            ("Reading vocabulary", "08:30", "10:00", 90),
        )
        self.assertEqual(timed["group"], "In the morning")
        self.assertEqual((plain["content"], plain["startTime"]), ("Buy coffee", ""))
        self.assertEqual(done["content"], "Tutor ✅ 2026-09-22")
        self.assertEqual(done["durationMinutes"], 30)
        self.assertEqual(done["group"], "In the afternoon")

    def test_missing_or_duplicate_planner_heading_fails_closed(self):
        for body in ("## Daily Log\n", "## Tasks\n## Tasks\n"):
            with self.subTest(body=body):
                vault, _, day = self.make_vault(body)
                with self.assertRaises(daily.core.TodoError) as error:
                    daily.scan_daily_note(str(vault), day=day)
                self.assertEqual(error.exception.code, "invalid_planner_section")

    def test_missing_daily_note_is_not_created(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        vault = Path(tmp.name) / "Vault"
        vault.mkdir()
        with self.assertRaises(daily.core.TodoError) as error:
            daily.scan_daily_note(str(vault), day="2026-09-22")
        self.assertEqual(error.exception.code, "daily_note_not_found")
        self.assertEqual(list(vault.rglob("*.md")), [])

    def test_add_uses_real_template_position_before_thematic_break(self):
        vault, note, scan = self.scan(
            "## Tasks\n\n---\n\n## Daily Log\n\n---\n"
        )
        daily.add_task(
            str(vault), daily.DEFAULT_FOLDER, daily.DEFAULT_FORMAT,
            "2026-09-22", daily.DEFAULT_HEADING, 2, 30,
            "Buy coffee", "", "",
            scan["document"]["sha256"], scan["managed"]["sha256"],
        )
        text = note.read_text(encoding="utf-8")
        self.assertIn(
            "## Tasks\n\n- [ ] Buy coffee\n---\n\n## Daily Log",
            text,
        )

    def test_add_unscheduled_task_preserves_other_sections(self):
        vault, note, scan = self.scan(
            "# Before\n## Tasks\n\n## Daily Log\nkeep me\n"
        )
        result = daily.add_task(
            str(vault), daily.DEFAULT_FOLDER, daily.DEFAULT_FORMAT,
            "2026-09-22", daily.DEFAULT_HEADING, 2, 30,
            "Buy coffee", "", "",
            scan["document"]["sha256"], scan["managed"]["sha256"],
        )
        text = note.read_text(encoding="utf-8")
        self.assertIn("## Tasks\n- [ ] Buy coffee\n\n## Daily Log", text)
        self.assertTrue(text.endswith("keep me\n"))
        self.assertEqual(result["tasks"][0]["content"], "Buy coffee")

    def test_add_timed_task_uses_matching_legacy_group(self):
        vault, note, scan = self.scan(
            "## Tasks\n"
            "**In the morning,**\n- [ ] Breakfast\n"
            "**In the afternoon,**\n- [ ] Lunch\n"
            "**In the evening,**\n- [ ] Sleep\n"
            "## Daily Log\n"
        )
        daily.add_task(
            str(vault), daily.DEFAULT_FOLDER, daily.DEFAULT_FORMAT,
            "2026-09-22", daily.DEFAULT_HEADING, 2, 30,
            "Tutor", "15:30", "17:00",
            scan["document"]["sha256"], scan["managed"]["sha256"],
        )
        text = note.read_text(encoding="utf-8")
        inserted = text.index("- [ ] 15:30 - 17:00 Tutor")
        self.assertLess(text.index("**In the afternoon,**"), inserted)
        self.assertLess(inserted, text.index("**In the evening,**"))

    def test_toggle_preserves_metadata_suffix_and_spacing(self):
        vault, note, scan = self.scan(
            "## Tasks\n"
            " - [ ] 08:30 Study  [due:: 2026-09-22] ✅ 2026-09-21\n"
            "## Daily Log\n"
        )
        task = scan["tasks"][0]
        result = daily.toggle_task(
            str(vault), daily.DEFAULT_FOLDER, daily.DEFAULT_FORMAT,
            "2026-09-22", daily.DEFAULT_HEADING, 2, 30,
            task["id"], scan["document"]["sha256"],
        )
        self.assertIn(
            " - [x] 08:30 Study  [due:: 2026-09-22] ✅ 2026-09-21",
            note.read_text(encoding="utf-8"),
        )
        self.assertTrue(result["tasks"][0]["done"])

    def test_delete_removes_only_exact_duplicate_line(self):
        vault, note, scan = self.scan(
            "## Tasks\n- [ ] same\n- [ ] same\n## Daily Log\n"
        )
        daily.delete_task(
            str(vault), daily.DEFAULT_FOLDER, daily.DEFAULT_FORMAT,
            "2026-09-22", daily.DEFAULT_HEADING, 2, 30,
            scan["tasks"][0]["id"], scan["document"]["sha256"],
        )
        self.assertEqual(note.read_text(encoding="utf-8").count("- [ ] same"), 1)

    def test_migration_preview_treats_template_divider_as_empty_target(self):
        vault, note, _ = self.scan(
            "## Tasks\n\n---\n\n## Daily Log\n"
        )
        internal = note.parent / "todo.json"
        internal.write_text(
            '[{"content":"one","done":false},{"content":"two","done":true}]',
            encoding="utf-8",
        )
        before = note.read_bytes()
        result = daily.preview_internal_migration(
            str(vault), daily.DEFAULT_FOLDER, daily.DEFAULT_FORMAT,
            "2026-09-22", daily.DEFAULT_HEADING, 2, 30, str(internal),
        )
        self.assertEqual(note.read_bytes(), before)
        self.assertTrue(result["target"]["empty"])
        self.assertEqual(result["preview"]["added"], 2)

    def test_migration_backs_up_daily_note_and_inserts_before_divider(self):
        vault, note, scan = self.scan(
            "## Tasks\n\n---\n\n## Daily Log\nkeep\n"
        )
        internal = note.parent / "todo.json"
        internal.write_text(
            '[{"content":"one","done":false},{"content":"two","done":true}]',
            encoding="utf-8",
        )
        before = note.read_bytes()
        source_sha = daily.core._sha256_bytes(internal.read_bytes())
        result = daily.migrate_internal_json(
            str(vault), daily.DEFAULT_FOLDER, daily.DEFAULT_FORMAT,
            "2026-09-22", daily.DEFAULT_HEADING, 2, 30, str(internal),
            scan["document"]["sha256"], scan["managed"]["sha256"], source_sha,
        )
        text = note.read_text(encoding="utf-8")
        self.assertIn(
            "- [ ] one\n- [x] two\n---\n\n## Daily Log",
            text,
        )
        self.assertEqual(result["migratedCount"], 2)
        self.assertEqual(Path(result["backupPath"]).read_bytes(), before)
        self.assertTrue(result["backupCreated"])

    def test_migration_refuses_existing_task_heading_tasks(self):
        vault, note, scan = self.scan(
            "## Tasks\n- [ ] existing\n---\n## Daily Log\n"
        )
        internal = note.parent / "todo.json"
        internal.write_text('[{"content":"new","done":false}]', encoding="utf-8")
        before = note.read_bytes()
        with self.assertRaises(daily.core.TodoError) as error:
            daily.migrate_internal_json(
                str(vault), daily.DEFAULT_FOLDER, daily.DEFAULT_FORMAT,
                "2026-09-22", daily.DEFAULT_HEADING, 2, 30, str(internal),
                scan["document"]["sha256"], scan["managed"]["sha256"],
            )
        self.assertEqual(error.exception.code, "migration_target_not_empty")
        self.assertEqual(note.read_bytes(), before)

    def test_stale_document_hash_rejects_mutation(self):
        vault, note, scan = self.scan(
            "## Tasks\n- [ ] task\n## Daily Log\n"
        )
        note.write_text(
            "## Tasks\n- [ ] external edit\n## Daily Log\n", encoding="utf-8"
        )
        with self.assertRaises(daily.core.TodoError) as error:
            daily.toggle_task(
                str(vault), daily.DEFAULT_FOLDER, daily.DEFAULT_FORMAT,
                "2026-09-22", daily.DEFAULT_HEADING, 2, 30,
                scan["tasks"][0]["id"], scan["document"]["sha256"],
            )
        self.assertEqual(error.exception.code, "conflict")

    def test_scan_daily_range_unicode_dashes_fallback_and_toggle(self):
        vault, _, _ = self.make_vault(
            "## Day Planner\n"
            "- [ ] 09:00–10:30 Họp nhóm\n"
            "- [ ] 14:00-15:00 Code review\n"
            "- [ ] Unscheduled task\n"
            "## Notes\n",
            day="2026-09-22",
        )
        # Second day note with standard heading
        day2_note = vault / "00_Capture/01_Journal/2026/September/23-09-2026-Wednesday.md"
        day2_note.write_text("## Tasks\n- [x] 07:00 Morning mobility\n", encoding="utf-8")

        res = daily.scan_daily_range(
            str(vault), daily.DEFAULT_FOLDER, daily.DEFAULT_FORMAT,
            start_date="2026-09-21", end_date="2026-09-24",
            heading="Tasks", heading_level=2, default_duration=45,
        )
        self.assertTrue(res["ok"])
        self.assertEqual(len(res["events"]), 3)
        ev0, ev1, ev2 = res["events"]
        self.assertEqual((ev0["title"], ev0["startTime"], ev0["endTime"], ev0["done"]), ("Họp nhóm", "09:00", "10:30", False))
        self.assertEqual((ev1["title"], ev1["startTime"], ev1["endTime"], ev1["done"]), ("Code review", "14:00", "15:00", False))
        self.assertEqual((ev2["title"], ev2["startTime"], ev2["endTime"], ev2["done"]), ("Morning mobility", "07:00", "07:45", True))
        self.assertEqual(ev0["sourceKind"], "nexusDailyTask")

        daily.toggle_task(
            str(vault), daily.DEFAULT_FOLDER, daily.DEFAULT_FORMAT,
            "2026-09-22", "Day Planner", 2, 45,
            ev0["taskId"], ev0["documentSha"],
        )
        after = daily.scan_daily_range(
            str(vault), daily.DEFAULT_FOLDER, daily.DEFAULT_FORMAT,
            start_date="2026-09-22", end_date="2026-09-22",
        )
        self.assertTrue(after["events"][0]["done"])

    def test_initialize_section_creates_note_or_appends_heading_idempotently(self):
        # 1. Appends missing heading cleanly while preserving existing body lines
        vault, note, day = self.make_vault("# Daily Note\n\nExisting entry\n", day="2026-09-22")
        res = daily.initialize_section(
            str(vault), daily.DEFAULT_FOLDER, daily.DEFAULT_FORMAT, day=day, heading="Day Planner", heading_level=2
        )
        self.assertTrue(res["ok"])
        self.assertEqual(res["mutation"], "initialize-section")
        self.assertEqual(res["tasks"], [])
        content = note.read_text(encoding="utf-8")
        self.assertIn("Existing entry", content)
        self.assertIn("## Day Planner\n", content)

        # 2. Idempotent when heading already exists once
        before_bytes = note.read_bytes()
        again = daily.initialize_section(
            str(vault), daily.DEFAULT_FOLDER, daily.DEFAULT_FORMAT, day=day, heading="Day Planner", heading_level=2
        )
        self.assertTrue(again["ok"])
        self.assertEqual(note.read_bytes(), before_bytes)

        # 3. Creates missing daily note safely inside vault when absent
        res_new = daily.initialize_section(
            str(vault), daily.DEFAULT_FOLDER, daily.DEFAULT_FORMAT, day="2026-09-23", heading="Day Planner", heading_level=2
        )
        self.assertTrue(res_new["ok"])
        self.assertEqual(
            (vault / "00_Capture/01_Journal/2026/September/23-09-2026-Wednesday.md").read_text(encoding="utf-8"),
            "## Day Planner\n",
        )

        # 4. Fails closed on duplicate headings
        note.write_text("## Day Planner\n## Day Planner\n", encoding="utf-8")
        dup_before = note.read_bytes()
        with self.assertRaises(daily.core.TodoError) as error:
            daily.initialize_section(
                str(vault), daily.DEFAULT_FOLDER, daily.DEFAULT_FORMAT, day=day, heading="Day Planner", heading_level=2
            )
        self.assertEqual(error.exception.code, "invalid_planner_section")
        self.assertEqual(note.read_bytes(), dup_before)


if __name__ == "__main__":
    unittest.main()
