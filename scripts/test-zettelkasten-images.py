#!/usr/bin/env python3
"""Copied images follow vault attachment settings without consuming drafts."""
import base64
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parent / "notes/zettelkasten.py"
spec = importlib.util.spec_from_file_location("zettel", SCRIPT)
zettel = importlib.util.module_from_spec(spec)
spec.loader.exec_module(zettel)
PNG = base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNwmLDhPwAFFAKA8JVvSQAAAABJRU5ErkJggg==")


class Images(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="zettel-images-")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.vault = self.base / "Vault có dấu"
        self.vault.mkdir()
        self.config = self.vault / ".nexus"
        self.config.mkdir()
        self.store = self.base / "state" / "notepad-attachments"
        self.store.mkdir(parents=True)
        self.name = hashlib.sha256(PNG).hexdigest() + ".png"
        self.source = self.store / self.name
        self.source.write_bytes(PNG)
        self.body = "Draft\n![Image](" + self.source.as_uri() + ")\n"

    def capture(self, **kwargs):
        return zettel.capture(str(self.vault), "Notes", "A note", self.body,
                              attachment_root=str(self.store), **kwargs)

    def test_all_builtin_vault_locations_and_unicode_links(self):
        for location, expected in [("", ""), (".", "Notes"), ("./Images", "Notes/Images"), ("Ảnh chung", "Ảnh chung")]:
            with self.subTest(location=location):
                (self.config / "app.json").write_text(json.dumps({"attachmentFolderPath": location}))
                result = self.capture()
                copied = self.vault / expected / self.name
                self.assertEqual(copied.read_bytes(), PNG)
                self.assertEqual(self.source.read_bytes(), PNG)
                note = Path(result["noteFullPath"]).read_text()
                self.assertNotIn("file://", note)
                self.assertIn("![Image](", note)
                self.assertEqual(result["attachments"][0]["path"], copied.relative_to(self.vault).as_posix())

    def test_custom_config_path_and_repeat_capture_are_idempotent(self):
        alternate = self.vault / "Config khác"
        alternate.mkdir()
        (alternate / "app.json").write_text('{"attachmentFolderPath":"Assets"}')
        first = self.capture(config_path=str(alternate))
        second = self.capture(config_path=str(alternate))
        self.assertEqual(first["attachments"], second["attachments"])
        self.assertEqual(len(list((self.vault / "Assets").iterdir())), 1)
        self.assertEqual(self.source.read_bytes(), PNG)

    def test_existing_collision_is_preserved_and_new_link_is_correct(self):
        destination = self.vault / self.name
        destination.write_bytes(b"owner image")
        result = self.capture()
        self.assertEqual(destination.read_bytes(), b"owner image")
        exported = result["attachments"][0]["path"]
        self.assertNotEqual(exported, self.name)
        self.assertEqual((self.vault / exported).read_bytes(), PNG)
        self.assertIn(exported, Path(result["noteFullPath"]).read_text())

    def test_invalid_config_or_escape_never_publishes_note(self):
        for settings in ["not json", '{"attachmentFolderPath":"../../outside"}', '{"attachmentFolderPath":false}']:
            (self.config / "app.json").write_text(settings)
            with self.assertRaises(zettel.ZettelError):
                self.capture()
            self.assertEqual(list(self.vault.rglob("*.md")), [])
            self.assertEqual(self.source.read_bytes(), PNG)
        self.assertFalse((self.base / "outside").exists())

    def test_changed_or_missing_image_fails_before_any_asset_is_copied(self):
        missing = self.store / ("a" * 64 + ".png")
        self.body += "![Missing](" + missing.as_uri() + ")"
        with self.assertRaises(zettel.ZettelError):
            self.capture()
        self.assertFalse((self.vault / self.name).exists())
        self.assertEqual(list(self.vault.rglob("*.md")), [])
        self.body = "![Changed](" + self.source.as_uri() + ")"
        self.source.write_bytes(b"changed bytes")
        with self.assertRaises(zettel.ZettelError) as error:
            self.capture()
        self.assertEqual(error.exception.code, "attachment_source_changed")
        self.assertEqual(self.source.read_bytes(), b"changed bytes")

    def test_note_migration_copies_images_preserves_source_and_restarts_safely(self):
        source = self.store.parent / "notepad-tabs.json"
        original = json.dumps({"tabs": [{"title": "Note 1", "text": self.body}]}).encode()
        source.write_bytes(original)
        preview = zettel.preview_notepad_migration(str(self.vault), "Notes", str(source))
        self.assertFalse((self.vault / self.name).exists())
        first = zettel.migrate_notepad_json(str(self.vault), "Notes", str(source), preview["source"]["sha256"])
        second = zettel.migrate_notepad_json(str(self.vault), "Notes", str(source), preview["source"]["sha256"])
        self.assertEqual(first["migratedCount"], 1)
        self.assertEqual(second["migratedCount"], 0)
        self.assertEqual(source.read_bytes(), original)
        self.assertEqual(self.source.read_bytes(), PNG)
        self.assertEqual((self.vault / self.name).read_bytes(), PNG)
        self.assertNotIn("file://", (self.vault / first["notePaths"][0]).read_text())

    def test_cli_capture_routes_attachment_and_config_arguments(self):
        (self.config / "app.json").write_text('{"attachmentFolderPath":"Pictures"}')
        result = subprocess.run(["python3", str(SCRIPT), "--vault", str(self.vault),
                                 "--folder", "Notes", "--body", self.body,
                                 "--attachment-root", str(self.store), "--config-path", str(self.config)],
                                text=True, capture_output=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(json.loads(result.stdout)["attachments"][0]["path"], "Pictures/" + self.name)

    def test_image_only_note_does_not_turn_source_url_into_title(self):
        result = zettel.capture(str(self.vault), "Notes", "", "![Image](" + self.source.as_uri() + ")",
                               attachment_root=str(self.store))
        self.assertEqual(result["title"], "Quick note")
        self.assertNotIn("file://", Path(result["noteFullPath"]).read_text())


if __name__ == "__main__":
    unittest.main()
