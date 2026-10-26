#!/usr/bin/env python3
"""Regression tests for scripts/todo/obsidian_todo.py."""

from __future__ import annotations

import codecs
import importlib.util
import json
import os
import stat
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent / "todo" / "obsidian_todo.py"
sys.path.insert(0,str(SCRIPT.parent))
SPEC = importlib.util.spec_from_file_location("obsidian_todo", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
obsidian_todo = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(obsidian_todo)


class ObsidianTodoTests(unittest.TestCase):
    def make_vault(self, data: bytes, note: str = "Alis/Todo.md"):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        vault = Path(tmp.name) / "Vault"
        path = vault / note
        path.parent.mkdir(parents=True)
        path.write_bytes(data)
        return vault, path

    def scan(self, text: str, newline: str = "\n"):
        body = text.replace("\n", newline).encode("utf-8")
        vault, path = self.make_vault(body)
        return vault, path, obsidian_todo.scan_note(str(vault), "Alis/Todo.md")

    def test_parses_tasks_and_preserves_structure(self):
        _, _, result = self.scan(
            """# Tasks
<!-- alis:todo:start -->
- [ ] plain
  * [x] nested
> - [/] progress
1. [-] cancelled
12) [Q] custom metadata 📅 2026-09-25
not a task
<!-- alis:todo:end -->
"""
        )
        tasks = result["tasks"]
        self.assertEqual([t["listMarker"] for t in tasks], ["-", "*", "-", "1.", "12)"])
        self.assertEqual([t["statusType"] for t in tasks], [
            "TODO", "DONE", "IN_PROGRESS", "CANCELLED", "TODO"
        ])
        self.assertEqual(tasks[1]["indent"], "  ")
        self.assertEqual(tasks[2]["indent"], "> ")
        self.assertEqual(tasks[4]["content"], "custom metadata 📅 2026-09-25")
        self.assertTrue(tasks[1]["done"])
        self.assertFalse(tasks[3]["done"])

    def test_plus_marker_and_uppercase_done_status_are_supported(self):
        _, _, result = self.scan(
            "<!-- alis:todo:start -->\n"
            "+ [ ] plus marker\n"
            "- [X] uppercase done\n"
            "<!-- alis:todo:end -->\n"
        )
        self.assertEqual([task["listMarker"] for task in result["tasks"]], ["+", "-"])
        self.assertEqual([task["done"] for task in result["tasks"]], [False, True])
        self.assertEqual([task["statusType"] for task in result["tasks"]], ["TODO", "DONE"])

    def test_duplicate_text_has_distinct_ephemeral_ids(self):
        _, _, result = self.scan(
            """<!-- alis:todo:start -->
- [ ] same
- [ ] same
<!-- alis:todo:end -->
"""
        )
        self.assertEqual(len(result["tasks"]), 2)
        self.assertNotEqual(result["tasks"][0]["id"], result["tasks"][1]["id"])

    def test_fenced_tasks_and_markers_are_ignored(self):
        _, _, result = self.scan(
            """```md
<!-- alis:todo:start -->
- [ ] fake
<!-- alis:todo:end -->
```
<!-- alis:todo:start -->
- [ ] real
~~~md
- [ ] fenced
~~~
<!-- alis:todo:end -->
"""
        )
        self.assertEqual([t["content"] for t in result["tasks"]], ["real"])

    def test_blockquote_fence_is_ignored(self):
        _, _, result = self.scan(
            """<!-- alis:todo:start -->
> ```
> - [ ] fake
> ```
- [ ] real
<!-- alis:todo:end -->
"""
        )
        self.assertEqual([t["content"] for t in result["tasks"]], ["real"])

    def test_crlf_bom_and_final_newline_are_reported(self):
        text = (
            "<!-- alis:todo:start -->\r\n"
            "- [ ] café\r\n"
            "<!-- alis:todo:end -->\r\n"
        ).encode("utf-8")
        vault, _ = self.make_vault(codecs.BOM_UTF8 + text)
        result = obsidian_todo.scan_note(str(vault), "Alis/Todo.md")
        self.assertTrue(result["document"]["bom"])
        self.assertEqual(result["document"]["newline"], "crlf")
        self.assertTrue(result["document"]["finalNewline"])
        self.assertEqual(result["tasks"][0]["content"], "café")

    def test_no_final_newline_is_reported(self):
        _, _, result = self.scan(
            "<!-- alis:todo:start -->\n"
            "- [ ] task\n"
            "<!-- alis:todo:end -->"
        )
        self.assertFalse(result["document"]["finalNewline"])

    def test_missing_or_duplicate_markers_fail_closed(self):
        with self.assertRaises(obsidian_todo.TodoError) as missing:
            self.scan("- [ ] task\n")
        self.assertEqual(missing.exception.code, "invalid_managed_section")

        with self.assertRaises(obsidian_todo.TodoError) as duplicate:
            self.scan(
                """<!-- alis:todo:start -->
<!-- alis:todo:start -->
- [ ] task
<!-- alis:todo:end -->
"""
            )
        self.assertEqual(duplicate.exception.code, "invalid_managed_section")

    def test_out_of_order_markers_fail_closed(self):
        with self.assertRaises(obsidian_todo.TodoError) as error:
            self.scan(
                """<!-- alis:todo:end -->
- [ ] task
<!-- alis:todo:start -->
"""
            )
        self.assertEqual(error.exception.code, "invalid_managed_section")

    def test_note_path_must_be_vault_relative(self):
        vault, _ = self.make_vault(
            b"<!-- alis:todo:start -->\n<!-- alis:todo:end -->\n"
        )
        for bad in ("../outside.md", "/tmp/outside.md", r"..\outside.md", ""):
            with self.subTest(path=bad):
                with self.assertRaises(obsidian_todo.TodoError):
                    obsidian_todo.resolve_note(str(vault), bad)

    @unittest.skipUnless(hasattr(os, "symlink"), "symlinks unavailable")
    def test_symlink_escape_is_rejected(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        root = Path(tmp.name)
        vault = root / "Vault"
        vault.mkdir()
        outside = root / "outside.md"
        outside.write_text(
            "<!-- alis:todo:start -->\n<!-- alis:todo:end -->\n",
            encoding="utf-8",
        )
        (vault / "escape.md").symlink_to(outside)
        with self.assertRaises(obsidian_todo.TodoError) as error:
            obsidian_todo.scan_note(str(vault), "escape.md")
        self.assertEqual(error.exception.code, "note_outside_vault")

    def test_filesystem_root_is_rejected(self):
        with self.assertRaises(obsidian_todo.TodoError) as error:
            obsidian_todo.resolve_note("/", "tmp/example.md")
        self.assertEqual(error.exception.code, "invalid_vault_path")

    def test_initialize_section_appends_only_markers_and_is_idempotent(self):
        original = codecs.BOM_UTF8 + "# Existing\r\nbody".encode("utf-8")
        vault, path = self.make_vault(original)
        result = obsidian_todo.initialize_section(str(vault), "Alis/Todo.md")
        raw = path.read_bytes()
        self.assertTrue(result["initialized"])
        self.assertTrue(raw.startswith(codecs.BOM_UTF8 + b"# Existing\r\nbody\r\n"))
        self.assertTrue(raw.endswith(
            b"<!-- alis:todo:start -->\r\n<!-- alis:todo:end -->"
        ))
        self.assertEqual(result["document"]["newline"], "crlf")

        again = obsidian_todo.initialize_section(str(vault), "Alis/Todo.md")
        self.assertFalse(again["initialized"])
        self.assertEqual(path.read_bytes(), raw)

    def test_initialize_section_creates_missing_nested_note(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        vault = Path(tmp.name) / "Vault"
        vault.mkdir()
        result = obsidian_todo.initialize_section(
            str(vault), "Alis/Nested/Todo.md"
        )
        note = vault / "Alis" / "Nested" / "Todo.md"
        self.assertTrue(note.is_file())
        self.assertTrue(result["initialized"])
        self.assertEqual(
            note.read_text(encoding="utf-8"),
            "<!-- alis:todo:start -->\n<!-- alis:todo:end -->",
        )

    @unittest.skipUnless(hasattr(os, "symlink"), "symlinks unavailable")
    def test_initialize_section_rejects_symlink_parent_escape(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        root = Path(tmp.name)
        vault = root / "Vault"
        outside = root / "Outside"
        vault.mkdir()
        outside.mkdir()
        (vault / "Alis").symlink_to(outside, target_is_directory=True)
        with self.assertRaises(obsidian_todo.TodoError) as error:
            obsidian_todo.initialize_section(str(vault), "Alis/Todo.md")
        self.assertEqual(error.exception.code, "note_outside_vault")
        self.assertFalse((outside / "Todo.md").exists())

    def test_initialize_section_ignores_marker_text_inside_fence(self):
        vault, path = self.make_vault(
            b"```md\n<!-- alis:todo:start -->\n<!-- alis:todo:end -->\n```\n"
        )
        result = obsidian_todo.initialize_section(str(vault), "Alis/Todo.md")
        self.assertTrue(result["initialized"])
        self.assertEqual(
            path.read_text(encoding="utf-8").count("<!-- alis:todo:start -->"), 2
        )

    def test_initialize_section_rejects_partial_marker_without_writing(self):
        vault, path = self.make_vault(
            b"# Existing\n<!-- alis:todo:start -->\n- [ ] task\n"
        )
        before = path.read_bytes()
        with self.assertRaises(obsidian_todo.TodoError) as error:
            obsidian_todo.initialize_section(str(vault), "Alis/Todo.md")
        self.assertEqual(error.exception.code, "invalid_managed_section")
        self.assertEqual(path.read_bytes(), before)

    def test_migration_preview_is_read_only_and_reports_conflicts(self):
        vault, path, _ = self.scan(
            "<!-- alis:todo:start -->\n- [ ] same\n<!-- alis:todo:end -->\n"
        )
        internal = path.parent / "internal.json"
        internal.write_text(
            json.dumps([
                {"content": "same", "done": False},
                {"content": "same", "done": True},
                {"content": "new", "done": False},
            ]),
            encoding="utf-8",
        )
        before = path.read_bytes()
        result = obsidian_todo.preview_internal_migration(
            str(vault), "Alis/Todo.md", str(internal)
        )
        self.assertEqual(path.read_bytes(), before)
        self.assertEqual(result["source"]["sha256"], obsidian_todo._sha256_bytes(internal.read_bytes()))
        self.assertFalse(result["target"]["empty"])
        self.assertEqual(result["preview"], {
            "added": 1,
            "duplicates": 1,
            "conflicts": 1,
        })

    def test_migrate_internal_store_requires_empty_managed_section(self):
        vault, path, scan = self.scan(
            "<!-- alis:todo:start -->\n- [ ] existing\n<!-- alis:todo:end -->\n"
        )
        internal = path.parent / "internal.json"
        internal.write_text('[{"content":"old","done":false}]', encoding="utf-8")
        before = path.read_bytes()
        with self.assertRaises(obsidian_todo.TodoError) as error:
            obsidian_todo.migrate_internal_json(
                str(vault), "Alis/Todo.md", str(internal),
                scan["document"]["sha256"], scan["managed"]["sha256"],
            )
        self.assertEqual(error.exception.code, "migration_target_not_empty")
        self.assertEqual(path.read_bytes(), before)

    def test_migrate_internal_store_preserves_done_and_global_filter(self):
        vault, path, scan = self.scan(
            "# Before\n<!-- alis:todo:start -->\n<!-- alis:todo:end -->\n# After\n"
        )
        internal = path.parent / "internal.json"
        internal.write_text(
            '[{"content":"one","done":false},{"content":"two","done":true}]',
            encoding="utf-8",
        )
        before = path.read_bytes()
        source_sha = obsidian_todo._sha256_bytes(internal.read_bytes())
        result = obsidian_todo.migrate_internal_json(
            str(vault), "Alis/Todo.md", str(internal),
            scan["document"]["sha256"], scan["managed"]["sha256"], "#task",
            source_sha,
        )
        text = path.read_text(encoding="utf-8")
        self.assertIn("- [ ] #task one\n- [x] #task two\n", text)
        self.assertTrue(text.startswith("# Before\n"))
        self.assertTrue(text.endswith("# After\n"))
        self.assertEqual(result["migratedCount"], 2)
        self.assertEqual(result["sourceSha256"], source_sha)
        backup = Path(result["backupPath"])
        self.assertTrue(result["backupCreated"])
        self.assertTrue(backup.name.startswith(".Todo.md.alis-backup-"))
        self.assertEqual(backup.read_bytes(), before)
        self.assertEqual([task["done"] for task in result["tasks"]], [False, True])

    def test_migrate_internal_store_rejects_stale_preview_source_hash(self):
        vault, path, scan = self.scan(
            "<!-- alis:todo:start -->\n<!-- alis:todo:end -->\n"
        )
        internal = path.parent / "internal.json"
        internal.write_text('[{"content":"one","done":false}]', encoding="utf-8")
        before = path.read_bytes()
        with self.assertRaises(obsidian_todo.TodoError) as error:
            obsidian_todo.migrate_internal_json(
                str(vault), "Alis/Todo.md", str(internal),
                scan["document"]["sha256"], scan["managed"]["sha256"], "",
                "0" * 64,
            )
        self.assertEqual(error.exception.code, "migration_source_conflict")
        self.assertEqual(path.read_bytes(), before)

    def test_migrate_internal_store_rejects_multiline_task(self):
        vault, path, scan = self.scan(
            "<!-- alis:todo:start -->\n<!-- alis:todo:end -->\n"
        )
        internal = path.parent / "internal.json"
        internal.write_text(
            json.dumps([{"content": "one\ntwo", "done": False}]),
            encoding="utf-8",
        )
        before = path.read_bytes()
        with self.assertRaises(obsidian_todo.TodoError) as error:
            obsidian_todo.migrate_internal_json(
                str(vault), "Alis/Todo.md", str(internal),
                scan["document"]["sha256"], scan["managed"]["sha256"],
            )
        self.assertEqual(error.exception.code, "migration_source_invalid")
        self.assertEqual(path.read_bytes(), before)

    def test_basic_toggle_preserves_bom_crlf_spacing_and_outside_bytes(self):
        original = codecs.BOM_UTF8 + (
            "# Before\r\n"
            "<!-- alis:todo:start -->\r\n"
            "  *   [ ]   keep spacing\r\n"
            "<!-- alis:todo:end -->\r\n"
            "# After\r\n"
        ).encode("utf-8")
        vault, path = self.make_vault(original)
        before = obsidian_todo.scan_note(str(vault), "Alis/Todo.md")
        task = before["tasks"][0]
        result = obsidian_todo.toggle_basic_task(
            str(vault), "Alis/Todo.md", task["id"], before["document"]["sha256"]
        )
        raw = path.read_bytes()
        self.assertTrue(raw.startswith(codecs.BOM_UTF8))
        self.assertIn(b"  *   [x]   keep spacing\r\n", raw)
        self.assertTrue(raw.endswith(b"# After\r\n"))
        self.assertTrue(result["tasks"][0]["done"])
        self.assertEqual(result["document"]["newline"], "crlf")

    def test_basic_toggle_rejects_rich_metadata_and_custom_status(self):
        for line in (
            "- [ ] repeat 🔁 every week",
            "- [ ] due 📅 2026-09-25",
            "- [ ] [due:: 2026-09-25]",
            "- [/] in progress",
            "- [Q] custom",
        ):
            with self.subTest(line=line):
                vault, _, scan = self.scan(
                    "<!-- alis:todo:start -->\n"
                    + line + "\n"
                    + "<!-- alis:todo:end -->\n"
                )
                with self.assertRaises(obsidian_todo.TodoError) as error:
                    obsidian_todo.toggle_basic_task(
                        str(vault), "Alis/Todo.md",
                        scan["tasks"][0]["id"], scan["document"]["sha256"],
                    )
                self.assertEqual(error.exception.code, "rich_task_required")

    def test_delete_can_remove_rich_task_without_completion_semantics(self):
        vault, path, scan = self.scan(
            """# Before
<!-- alis:todo:start -->
- [ ] recurring 🔁 every day
- [ ] keep
<!-- alis:todo:end -->
# After
"""
        )
        result = obsidian_todo.delete_task(
            str(vault), "Alis/Todo.md",
            scan["tasks"][0]["id"], scan["document"]["sha256"],
        )
        text = path.read_text(encoding="utf-8")
        self.assertNotIn("recurring", text)
        self.assertIn("- [ ] keep", text)
        self.assertIn("# Before", text)
        self.assertIn("# After", text)
        self.assertEqual([t["content"] for t in result["tasks"]], ["keep"])

    def test_add_requires_document_and_managed_hashes(self):
        vault, path, scan = self.scan(
            """# Before
<!-- alis:todo:start -->
- [ ] existing
<!-- alis:todo:end -->
# After
"""
        )
        result = obsidian_todo.add_basic_task(
            str(vault), "Alis/Todo.md", "new task",
            scan["document"]["sha256"], scan["managed"]["sha256"],
        )
        text = path.read_text(encoding="utf-8")
        self.assertIn("- [ ] existing\n- [ ] new task\n<!-- alis:todo:end -->", text)
        self.assertTrue(text.startswith("# Before\n"))
        self.assertTrue(text.endswith("# After\n"))
        self.assertEqual(len(result["tasks"]), 2)

    def test_add_rejects_multiline_text(self):
        vault, _, scan = self.scan(
            "<!-- alis:todo:start -->\n<!-- alis:todo:end -->\n"
        )
        with self.assertRaises(obsidian_todo.TodoError) as error:
            obsidian_todo.add_basic_task(
                str(vault), "Alis/Todo.md", "one\ntwo",
                scan["document"]["sha256"], scan["managed"]["sha256"],
            )
        self.assertEqual(error.exception.code, "invalid_task_text")

    def test_stale_document_hash_fails_without_writing(self):
        vault, path, scan = self.scan(
            """<!-- alis:todo:start -->
- [ ] task
<!-- alis:todo:end -->
"""
        )
        path.write_text(
            """external
<!-- alis:todo:start -->
- [ ] task
<!-- alis:todo:end -->
""",
            encoding="utf-8",
        )
        external = path.read_bytes()
        with self.assertRaises(obsidian_todo.TodoError) as error:
            obsidian_todo.toggle_basic_task(
                str(vault), "Alis/Todo.md",
                scan["tasks"][0]["id"], scan["document"]["sha256"],
            )
        self.assertEqual(error.exception.code, "conflict")
        self.assertEqual(path.read_bytes(), external)

    def test_stale_task_id_fails_without_writing(self):
        vault, path, scan = self.scan(
            """<!-- alis:todo:start -->
- [ ] task
<!-- alis:todo:end -->
"""
        )
        current = obsidian_todo.scan_note(str(vault), "Alis/Todo.md")
        with self.assertRaises(obsidian_todo.TodoError) as error:
            obsidian_todo.toggle_basic_task(
                str(vault), "Alis/Todo.md",
                "deadbeef", current["document"]["sha256"],
            )
        self.assertEqual(error.exception.code, "conflict")
        self.assertIn("- [ ] task", path.read_text(encoding="utf-8"))

    def test_atomic_write_preserves_file_mode(self):
        vault, path, scan = self.scan(
            """<!-- alis:todo:start -->
- [ ] task
<!-- alis:todo:end -->
"""
        )
        path.chmod(0o640)
        obsidian_todo.toggle_basic_task(
            str(vault), "Alis/Todo.md",
            scan["tasks"][0]["id"], scan["document"]["sha256"],
        )
        self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o640)


if __name__ == "__main__":
    unittest.main()
