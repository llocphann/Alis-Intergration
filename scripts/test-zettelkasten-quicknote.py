#!/usr/bin/env python3
"""Regression tests for filesystem-canonical Zettelkasten quick notes."""
from __future__ import annotations

import importlib.util
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent / "notes" / "zettelkasten.py"
SPEC = importlib.util.spec_from_file_location("zettelkasten", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
zettel = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(zettel)


class ZettelkastenTests(unittest.TestCase):
    def vault(self) -> Path:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        vault = Path(tmp.name) / "Vault"
        vault.mkdir()
        return vault

    def test_capture_creates_fleeting_zettel(self):
        vault = self.vault()
        now = datetime(2026, 9, 22, 11, 42, 31, tzinfo=timezone.utc)
        result = zettel.capture(
            str(vault), "00_Capture/03_Zettelkasten",
            "Atomic notes", "A short capture.", "Fleeting", now,
        )
        path = Path(result["noteFullPath"])
        self.assertTrue(path.is_file())
        self.assertEqual(
            result["notePath"],
            "00_Capture/03_Zettelkasten/20260922114231 - Atomic notes.md",
        )
        text = path.read_text(encoding="utf-8")
        self.assertIn("id: 20260922114231", text)
        self.assertIn("date: 2026-09-22", text)
        self.assertIn("type: Fleeting", text)
        self.assertIn("aliases: []", text)
        self.assertIn("# Atomic notes", text)
        self.assertIn("## Core Idea\nAbstract\nAtomic notes", text)
        self.assertIn(
            "## Content\n> [!info] Explanation\n> A short capture.",
            text,
        )
        self.assertIn("## Context & Connections", text)
        self.assertIn("## Sources & References", text)
        self.assertNotIn("created:", text)
        self.assertTrue(result["templateCompatible"])

    def test_title_falls_back_to_first_body_line(self):
        vault = self.vault()
        result = zettel.capture(
            str(vault), "Zettel", "", "## Derived title\nBody",
            now=datetime(2026, 9, 22, 1, 2, 3, tzinfo=timezone.utc),
        )
        self.assertEqual(result["title"], "Derived title")
        self.assertIn("Derived title.md", result["notePath"])

    def test_filename_sanitizes_path_characters(self):
        vault = self.vault()
        result = zettel.capture(
            str(vault), "Zettel", "a/b:c", "",
            now=datetime(2026, 9, 22, 1, 2, 3, tzinfo=timezone.utc),
        )
        self.assertNotIn("/", Path(result["noteFullPath"]).name)
        self.assertIn("a b c", Path(result["noteFullPath"]).name)

    def test_collision_allocates_unique_filename(self):
        vault = self.vault()
        now = datetime(2026, 9, 22, 1, 2, 3, tzinfo=timezone.utc)
        first = zettel.capture(str(vault), "Zettel", "same", "", now=now)
        second = zettel.capture(str(vault), "Zettel", "same", "", now=now)
        self.assertNotEqual(first["noteFullPath"], second["noteFullPath"])
        self.assertNotEqual(first["id"], second["id"])
        self.assertEqual(first["id"], "20260922010203")
        self.assertEqual(second["id"], "20260922010204")
        self.assertTrue(Path(second["noteFullPath"]).name.startswith("20260922010204 - "))

    def test_note_type_must_match_vault_template_choices(self):
        vault = self.vault()
        for value in ("Permanent", "Literature", "Fleeting"):
            with self.subTest(value=value):
                result = zettel.capture(
                    str(vault), "Zettel", value, "body", value,
                    now=datetime(2026, 9, 22, 2, 0, 0, tzinfo=timezone.utc),
                )
                self.assertEqual(result["type"], value)

        with self.assertRaises(zettel.ZettelError) as error:
            zettel.capture(str(vault), "Zettel", "bad", "body", "Scratch")
        self.assertEqual(error.exception.code, "invalid_note_type")

    def test_notepad_migration_preview_is_read_only(self):
        vault = self.vault()
        source = vault.parent / "state" / "notepad-tabs.json"
        source.parent.mkdir()
        source.write_text(
            '{"currentTab":0,"tabs":['
            '{"title":"Note 1","text":"first body"},'
            '{"title":"Custom","text":"second body"},'
            '{"title":"Note 3","text":""}'
            ']}',
            encoding="utf-8",
        )
        target = vault / "00_Capture/03_Zettelkasten"
        result = zettel.preview_notepad_migration(
            str(vault), "00_Capture/03_Zettelkasten", str(source), "Fleeting"
        )
        self.assertFalse(target.exists())
        self.assertEqual(result["source"]["tabCount"], 2)
        self.assertEqual(result["preview"], {
            "added": 2,
            "duplicates": 0,
            "conflicts": 0,
        })

    def test_notepad_migration_is_backed_up_verified_and_idempotent(self):
        vault = self.vault()
        source = vault.parent / "state" / "notepad-tabs.json"
        source.parent.mkdir()
        source.write_text(
            '{"currentTab":0,"tabs":['
            '{"title":"Note 1","text":"first body"},'
            '{"title":"Custom","text":"second body"}'
            ']}',
            encoding="utf-8",
        )
        source_raw = source.read_bytes()
        source_sha = zettel._sha256_bytes(source_raw)

        first = zettel.migrate_notepad_json(
            str(vault), "00_Capture/03_Zettelkasten",
            str(source), source_sha, "Fleeting",
        )
        self.assertTrue(first["verified"])
        self.assertTrue(first["sourcePreserved"])
        self.assertEqual(first["migratedCount"], 2)
        self.assertEqual(first["duplicateCount"], 0)
        self.assertEqual(source.read_bytes(), source_raw)
        self.assertEqual(Path(first["backupPath"]).read_bytes(), source_raw)

        notes = sorted((vault / "00_Capture/03_Zettelkasten").glob("*.md"))
        self.assertEqual(len(notes), 2)
        marker_count = sum(
            "alis_import_id:" in note.read_text(encoding="utf-8")
            for note in notes
        )
        self.assertEqual(marker_count, 2)

        second = zettel.migrate_notepad_json(
            str(vault), "00_Capture/03_Zettelkasten",
            str(source), source_sha, "Fleeting",
        )
        self.assertEqual(second["migratedCount"], 0)
        self.assertEqual(second["duplicateCount"], 2)
        self.assertEqual(
            len(list((vault / "00_Capture/03_Zettelkasten").glob("*.md"))),
            2,
        )

    def test_notepad_migration_rejects_stale_preview_sha(self):
        vault = self.vault()
        source = vault.parent / "state" / "notepad-tabs.json"
        source.parent.mkdir()
        source.write_text(
            '{"currentTab":0,"tabs":[{"title":"Note 1","text":"old"}]}',
            encoding="utf-8",
        )
        preview = zettel.preview_notepad_migration(
            str(vault), "00_Capture/03_Zettelkasten", str(source)
        )
        source.write_text(
            '{"currentTab":0,"tabs":[{"title":"Note 1","text":"new"}]}',
            encoding="utf-8",
        )
        with self.assertRaises(zettel.ZettelError) as error:
            zettel.migrate_notepad_json(
                str(vault), "00_Capture/03_Zettelkasten",
                str(source), preview["source"]["sha256"],
            )
        self.assertEqual(error.exception.code, "migration_source_conflict")
        self.assertFalse((vault / "00_Capture/03_Zettelkasten").exists())

    def test_folder_escape_is_rejected(self):
        vault = self.vault()
        with self.assertRaises(zettel.ZettelError) as error:
            zettel.capture(str(vault), "../escape", "bad", "")
        self.assertEqual(error.exception.code, "invalid_folder")


if __name__ == "__main__":
    unittest.main()
