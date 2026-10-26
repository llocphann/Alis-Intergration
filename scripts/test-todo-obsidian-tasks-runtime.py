#!/usr/bin/env python3
"""Regression tests for the non-launching Obsidian Tasks runtime bridge."""

from __future__ import annotations

import importlib.util
import json
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent / "todo"
SCRIPT = SCRIPT_DIR / "obsidian_tasks.py"

import sys
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

SPEC = importlib.util.spec_from_file_location("obsidian_tasks", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
obsidian_tasks = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(obsidian_tasks)


class ObsidianTasksRuntimeTests(unittest.TestCase):
    def make_vault(self, text: str = ""):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        vault = Path(tmp.name) / "Vault"
        note = vault / "Alis" / "Todo.md"
        note.parent.mkdir(parents=True)
        note.write_text(
            text
            or "<!-- alis:todo:start -->\n"
               "- [ ] task\n"
               "<!-- alis:todo:end -->\n",
            encoding="utf-8",
        )
        return vault, note

    def patch(self, name, value):
        original = getattr(obsidian_tasks, name)
        setattr(obsidian_tasks, name, value)
        self.addCleanup(lambda: setattr(obsidian_tasks, name, original))

    def test_process_classifier_accepts_app_and_rejects_cli(self):
        self.assertTrue(obsidian_tasks._looks_like_obsidian_app("obsidian", ["/usr/bin/obsidian"]))
        self.assertTrue(obsidian_tasks._looks_like_obsidian_app("", ["/opt/Obsidian/obsidian", "--type=renderer"]))
        self.assertFalse(obsidian_tasks._looks_like_obsidian_app("obsidian-cli", ["/home/u/.local/bin/obsidian-cli"]))
        self.assertFalse(obsidian_tasks._looks_like_obsidian_app("python3", ["python3", "obsidian_tasks.py"]))

    def test_process_classifier_accepts_verified_obsidian_flatpak_identity(self):
        self.assertTrue(obsidian_tasks._looks_like_obsidian_app(
            "zypak-wrapper",
            ["zypak-wrapper", "/app/obsidian"],
            "md.obsidian.Obsidian",
        ))
        self.assertFalse(obsidian_tasks._looks_like_obsidian_app(
            "zypak-wrapper",
            ["zypak-wrapper", "/app/other"],
            "org.example.Other",
        ))

    def test_flatpak_identity_reads_only_application_metadata(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        process_dir = Path(tmp.name) / "123"
        info = process_dir / "root" / ".flatpak-info"
        info.parent.mkdir(parents=True)
        info.write_text(
            "[Application]\n"
            "name=md.obsidian.Obsidian\n"
            "runtime=org.freedesktop.Platform/x86_64/25.08\n"
            "\n[Instance]\n"
            "instance-id=123\n",
            encoding="utf-8",
        )
        self.assertEqual(
            obsidian_tasks._flatpak_app_id(process_dir),
            "md.obsidian.Obsidian",
        )

    def test_stopped_probe_never_invokes_cli(self):
        vault, _ = self.make_vault()
        self.patch("_obsidian_running", lambda: False)
        self.patch("_find_cli", lambda: "/fake/obsidian")

        def forbidden(*_args, **_kwargs):
            raise AssertionError("CLI must not run while Obsidian is stopped")

        self.patch("_run_cli", forbidden)
        result = obsidian_tasks.probe_capabilities(str(vault))
        self.assertFalse(result["obsidianRunning"])
        self.assertFalse(result["cliResponsive"])
        self.assertFalse(result["richMutationAvailable"])

    def test_cli_timeout_maps_to_runtime_error(self):
        original = obsidian_tasks.subprocess.run

        def timeout(*_args, **_kwargs):
            raise subprocess.TimeoutExpired(["obsidian"], 0.01)

        obsidian_tasks.subprocess.run = timeout
        self.addCleanup(lambda: setattr(obsidian_tasks.subprocess, "run", original))

        with self.assertRaises(obsidian_tasks.RuntimeErrorInfo) as error:
            obsidian_tasks._run_cli("/fake/obsidian", ["eval", "code=1"], 0.01)
        self.assertEqual(error.exception.code, "cli_timeout")

    def test_eval_json_parser_handles_cli_prefix_and_quoted_json(self):
        self.assertEqual(
            obsidian_tasks._parse_eval_json('noise\n=> {"vaultPath":"/v"}\n'),
            {"vaultPath": "/v"},
        )
        quoted = json.dumps(json.dumps({"vaultPath": "/v"}))
        self.assertEqual(
            obsidian_tasks._parse_eval_json("=> " + quoted),
            {"vaultPath": "/v"},
        )

    def test_settings_defaults_and_custom_status_are_sanitized(self):
        summary = obsidian_tasks._settings_summary({
            "globalFilter": "#task",
        })
        self.assertEqual(summary["globalFilter"], "#task")
        self.assertEqual(summary["taskFormat"], "tasksPluginEmoji")
        self.assertTrue(summary["setDoneDate"])
        by_symbol = {entry["symbol"]: entry for entry in summary["statuses"]}
        self.assertEqual(by_symbol["/"]["type"], "IN_PROGRESS")
        self.assertEqual(by_symbol["-"]["type"], "CANCELLED")

    def test_explicit_custom_status_registry_replaces_default_customs(self):
        summary = obsidian_tasks._settings_summary({
            "statusSettings": {
                "customStatuses": [
                    {
                        "symbol": "?",
                        "name": "Question",
                        "nextStatusSymbol": "x",
                        "type": "ON_HOLD",
                    },
                    {
                        "symbol": "!",
                        "name": "Bad type",
                        "nextStatusSymbol": "x",
                        "type": "NOT_A_TYPE",
                    },
                    {
                        "symbol": "x",
                        "name": "Cannot override core",
                        "nextStatusSymbol": " ",
                        "type": "CANCELLED",
                    },
                    {
                        "symbol": "?",
                        "name": "Duplicate symbol",
                        "nextStatusSymbol": " ",
                        "type": "DONE",
                    },
                ]
            },
        })
        by_symbol = {entry["symbol"]: entry for entry in summary["statuses"]}
        self.assertNotIn("/", by_symbol)
        self.assertNotIn("-", by_symbol)
        self.assertEqual(by_symbol["?"]["name"], "Question")
        self.assertEqual(by_symbol["?"]["type"], "ON_HOLD")
        self.assertEqual(by_symbol["!"]["type"], "TODO")
        self.assertEqual(by_symbol["x"]["type"], "DONE")

    def test_explicit_empty_custom_status_registry_stays_empty(self):
        summary = obsidian_tasks._settings_summary({
            "statusSettings": {"customStatuses": []},
        })
        by_symbol = {entry["symbol"]: entry for entry in summary["statuses"]}
        self.assertEqual(set(by_symbol), {" ", "x"})

    def test_capability_probe_matches_physical_vault(self):
        vault, _ = self.make_vault()
        self.patch("_obsidian_running", lambda: True)
        self.patch("_find_cli", lambda: "/fake/obsidian")

        payload = {
            "vaultPath": str(vault.resolve()),
            "tasksPluginEnabled": True,
            "tasksPluginVersion": "7.22.0",
            "tasksApiAvailable": True,
            "settings": {"globalFilter": "#task"},
        }

        def fake_cli(_cli, _args, _timeout):
            return subprocess.CompletedProcess(
                ["obsidian"], 0, stdout="=> " + json.dumps(payload), stderr=""
            )

        self.patch("_run_cli", fake_cli)
        result = obsidian_tasks.probe_capabilities(str(vault))
        self.assertTrue(result["cliResponsive"])
        self.assertTrue(result["activeVaultMatches"])
        self.assertEqual(result["activeVaultBasePath"], str(vault.resolve()))
        self.assertTrue(result["tasksApiAvailable"])
        self.assertTrue(result["richMutationAvailable"])
        self.assertEqual(result["tasksSettings"]["globalFilter"], "#task")

    def test_capability_probe_does_not_invent_settings_when_tasks_is_disabled(self):
        vault, _ = self.make_vault()
        self.patch("_obsidian_running", lambda: True)
        self.patch("_find_cli", lambda: "/fake/obsidian")

        payload = {
            "vaultPath": str(vault.resolve()),
            "tasksPluginEnabled": False,
            "tasksApiAvailable": False,
            "settings": None,
        }
        self.patch(
            "_run_cli",
            lambda *_args: subprocess.CompletedProcess(
                ["obsidian"], 0, stdout="=> " + json.dumps(payload), stderr=""
            ),
        )
        result = obsidian_tasks.probe_capabilities(str(vault))
        self.assertTrue(result["cliResponsive"])
        self.assertTrue(result["activeVaultMatches"])
        self.assertFalse(result["tasksPluginEnabled"])
        self.assertFalse(result["tasksApiAvailable"])
        self.assertFalse(result["richMutationAvailable"])
        self.assertIsNone(result["tasksSettings"])

    def test_capability_probe_accepts_symlink_alias_and_preserves_raw_base_path(self):
        vault, _ = self.make_vault()
        alias = vault.parent / "VaultAlias"
        alias.symlink_to(vault, target_is_directory=True)
        self.patch("_obsidian_running", lambda: True)
        self.patch("_find_cli", lambda: "/fake/obsidian")

        payload = {
            "vaultPath": str(alias),
            "tasksPluginEnabled": True,
            "tasksApiAvailable": True,
            "settings": {},
        }
        self.patch(
            "_run_cli",
            lambda *_args: subprocess.CompletedProcess(
                ["obsidian"], 0, stdout="=> " + json.dumps(payload), stderr=""
            ),
        )
        result = obsidian_tasks.probe_capabilities(str(vault))
        self.assertTrue(result["activeVaultMatches"])
        self.assertEqual(result["activeVaultPath"], str(vault.resolve()))
        self.assertEqual(result["activeVaultBasePath"], str(alias))

    def test_capability_probe_fails_closed_on_other_vault(self):
        vault, _ = self.make_vault()
        other_tmp = tempfile.TemporaryDirectory()
        self.addCleanup(other_tmp.cleanup)
        other = Path(other_tmp.name).resolve()
        self.patch("_obsidian_running", lambda: True)
        self.patch("_find_cli", lambda: "/fake/obsidian")

        payload = {
            "vaultPath": str(other),
            "tasksPluginEnabled": True,
            "tasksApiAvailable": True,
            "settings": {},
        }
        self.patch(
            "_run_cli",
            lambda *_args: subprocess.CompletedProcess(
                ["obsidian"], 0, stdout="=> " + json.dumps(payload), stderr=""
            ),
        )
        result = obsidian_tasks.probe_capabilities(str(vault))
        self.assertFalse(result["activeVaultMatches"])
        self.assertFalse(result["richMutationAvailable"])

    def test_tasks_plugin_lookup_prefers_tasks_documented_registry(self):
        capability_code = obsidian_tasks._capability_eval_code()
        self.assertIn("app.plugins?.plugins?.[", capability_code)
        self.assertIn("app.plugins?.getPlugin?.(", capability_code)

    def test_toggle_eval_uses_tasks_api_vault_process_and_exact_line_guard(self):
        code = obsidian_tasks._toggle_eval_code(
            "/vault", "Alis/Todo.md", 7, "- [ ] café"
        )
        self.assertIn("adapter.getBasePath()!==expectedVault", code)
        self.assertIn("app.vault.getFileByPath(notePath)", code)
        self.assertIn("executeToggleTaskDoneCommand", code)
        self.assertIn("app.plugins?.plugins?.[", code)
        self.assertIn("app.plugins?.getPlugin?.(", code)
        self.assertIn("app.vault.process(file,(data)=>", code)
        self.assertIn("if(r.raw!==expectedRaw)", code)
        self.assertIn("transformed.split", code)
        self.assertNotIn("vault=", code)

    def test_toggle_when_stopped_never_invokes_cli(self):
        vault, _ = self.make_vault()
        scan = obsidian_tasks.obsidian_todo.scan_note(str(vault), "Alis/Todo.md")
        self.patch("_obsidian_running", lambda: False)
        self.patch("_find_cli", lambda: "/fake/obsidian")

        def forbidden(*_args, **_kwargs):
            raise AssertionError("CLI must not run while Obsidian is stopped")

        self.patch("_run_cli", forbidden)
        with self.assertRaises(obsidian_tasks.RuntimeErrorInfo) as error:
            obsidian_tasks.toggle_tasks_task(
                str(vault),
                "Alis/Todo.md",
                scan["tasks"][0]["id"],
                scan["document"]["sha256"],
            )
        self.assertEqual(error.exception.code, "obsidian_not_running")

    def test_toggle_requires_fresh_document_hash_before_cli(self):
        vault, note = self.make_vault()
        scan = obsidian_tasks.obsidian_todo.scan_note(str(vault), "Alis/Todo.md")
        note.write_text(
            "<!-- alis:todo:start -->\n- [ ] changed\n<!-- alis:todo:end -->\n",
            encoding="utf-8",
        )
        self.patch("_obsidian_running", lambda: True)
        self.patch("_find_cli", lambda: "/fake/obsidian")

        def forbidden(*_args, **_kwargs):
            raise AssertionError("CLI must not run after CAS failure")

        self.patch("_run_cli", forbidden)
        with self.assertRaises(obsidian_tasks.obsidian_todo.TodoError) as error:
            obsidian_tasks.toggle_tasks_task(
                str(vault),
                "Alis/Todo.md",
                scan["tasks"][0]["id"],
                scan["document"]["sha256"],
            )
        self.assertEqual(error.exception.code, "conflict")

    def test_success_is_verified_by_fresh_filesystem_scan(self):
        vault, note = self.make_vault()
        scan = obsidian_tasks.obsidian_todo.scan_note(str(vault), "Alis/Todo.md")
        self.patch("_obsidian_running", lambda: True)
        self.patch("_find_cli", lambda: "/fake/obsidian")
        calls = []

        capability = {
            "vaultPath": str(vault.resolve()),
            "tasksPluginEnabled": True,
            "tasksPluginVersion": "7.22.0",
            "tasksApiAvailable": True,
            "settings": {},
        }

        def fake_cli(_cli, args, _timeout):
            code = next(arg[5:] for arg in args if arg.startswith("code="))
            calls.append(code)
            if "app.vault.process(file" not in code:
                return subprocess.CompletedProcess(
                    ["obsidian"], 0,
                    stdout="=> " + json.dumps(capability),
                    stderr="",
                )
            current = note.read_text(encoding="utf-8")
            note.write_text(current.replace("- [ ] task", "- [x] task"), encoding="utf-8")
            # Deliberately empty: mutation stdout is not an acknowledgement.
            return subprocess.CompletedProcess(["obsidian"], 0, stdout="", stderr="")

        self.patch("_run_cli", fake_cli)
        result = obsidian_tasks.toggle_tasks_task(
            str(vault),
            "Alis/Todo.md",
            scan["tasks"][0]["id"],
            scan["document"]["sha256"],
        )
        self.assertTrue(result["verified"])
        self.assertEqual(result["mutation"], "toggle-tasks")
        self.assertTrue(result["tasks"][0]["done"])
        self.assertEqual(len(calls), 2)

    def test_toggle_binds_eval_to_probed_symlink_alias(self):
        vault, note = self.make_vault()
        alias = vault.parent / "VaultAlias"
        alias.symlink_to(vault, target_is_directory=True)
        scan = obsidian_tasks.obsidian_todo.scan_note(str(vault), "Alis/Todo.md")
        self.patch("_obsidian_running", lambda: True)
        self.patch("_find_cli", lambda: "/fake/obsidian")
        calls = []

        capability = {
            "vaultPath": str(alias),
            "tasksPluginEnabled": True,
            "tasksApiAvailable": True,
            "settings": {},
        }

        def fake_cli(_cli, args, _timeout):
            code = next(arg[5:] for arg in args if arg.startswith("code="))
            calls.append(code)
            if "app.vault.process(file" not in code:
                return subprocess.CompletedProcess(
                    ["obsidian"], 0,
                    stdout="=> " + json.dumps(capability), stderr=""
                )
            self.assertIn(
                "const expectedVault=" + json.dumps(str(alias), ensure_ascii=False),
                code,
            )
            current = note.read_text(encoding="utf-8")
            note.write_text(current.replace("- [ ] task", "- [x] task"), encoding="utf-8")
            return subprocess.CompletedProcess(["obsidian"], 0, stdout="", stderr="")

        self.patch("_run_cli", fake_cli)
        result = obsidian_tasks.toggle_tasks_task(
            str(vault),
            "Alis/Todo.md",
            scan["tasks"][0]["id"],
            scan["document"]["sha256"],
        )
        self.assertTrue(result["verified"])
        self.assertTrue(result["tasks"][0]["done"])
        self.assertEqual(len(calls), 2)

    def test_recurring_tasks_transform_can_expand_one_line_to_two(self):
        vault, note = self.make_vault(
            "<!-- alis:todo:start -->\n"
            "- [ ] repeat 🔁 every day\n"
            "<!-- alis:todo:end -->\n"
        )
        scan = obsidian_tasks.obsidian_todo.scan_note(str(vault), "Alis/Todo.md")
        self.patch("_obsidian_running", lambda: True)
        self.patch("_find_cli", lambda: "/fake/obsidian")
        capability = {
            "vaultPath": str(vault.resolve()),
            "tasksPluginEnabled": True,
            "tasksApiAvailable": True,
            "settings": {},
        }

        def fake_cli(_cli, args, _timeout):
            code = next(arg[5:] for arg in args if arg.startswith("code="))
            if "app.vault.process(file" not in code:
                return subprocess.CompletedProcess(
                    ["obsidian"], 0,
                    stdout="=> " + json.dumps(capability), stderr=""
                )
            current = note.read_text(encoding="utf-8")
            note.write_text(
                current.replace(
                    "- [ ] repeat 🔁 every day",
                    "- [x] repeat 🔁 every day ✅ 2026-09-22\n"
                    "- [ ] repeat 🔁 every day 📅 2026-09-23",
                ),
                encoding="utf-8",
            )
            return subprocess.CompletedProcess(["obsidian"], 0, stdout="", stderr="")

        self.patch("_run_cli", fake_cli)
        result = obsidian_tasks.toggle_tasks_task(
            str(vault),
            "Alis/Todo.md",
            scan["tasks"][0]["id"],
            scan["document"]["sha256"],
        )
        self.assertTrue(result["verified"])
        self.assertEqual(len(result["tasks"]), 2)
        self.assertTrue(result["tasks"][0]["done"])
        self.assertFalse(result["tasks"][1]["done"])

    def test_on_completion_delete_can_transform_one_line_to_zero(self):
        vault, note = self.make_vault(
            "<!-- alis:todo:start -->\n"
            "- [ ] delete me 🏁 delete\n"
            "<!-- alis:todo:end -->\n"
        )
        scan = obsidian_tasks.obsidian_todo.scan_note(str(vault), "Alis/Todo.md")
        self.patch("_obsidian_running", lambda: True)
        self.patch("_find_cli", lambda: "/fake/obsidian")
        capability = {
            "vaultPath": str(vault.resolve()),
            "tasksPluginEnabled": True,
            "tasksApiAvailable": True,
            "settings": {},
        }

        def fake_cli(_cli, args, _timeout):
            code = next(arg[5:] for arg in args if arg.startswith("code="))
            if "app.vault.process(file" not in code:
                return subprocess.CompletedProcess(
                    ["obsidian"], 0,
                    stdout="=> " + json.dumps(capability), stderr=""
                )
            current = note.read_text(encoding="utf-8")
            note.write_text(
                current.replace("- [ ] delete me 🏁 delete\n", ""),
                encoding="utf-8",
            )
            return subprocess.CompletedProcess(["obsidian"], 0, stdout="", stderr="")

        self.patch("_run_cli", fake_cli)
        result = obsidian_tasks.toggle_tasks_task(
            str(vault),
            "Alis/Todo.md",
            scan["tasks"][0]["id"],
            scan["document"]["sha256"],
        )
        self.assertTrue(result["verified"])
        self.assertEqual(result["tasks"], [])

    def test_unchanged_file_is_not_accepted_as_mutation_success(self):
        vault, _ = self.make_vault()
        scan = obsidian_tasks.obsidian_todo.scan_note(str(vault), "Alis/Todo.md")
        self.patch("_obsidian_running", lambda: True)
        self.patch("_find_cli", lambda: "/fake/obsidian")
        capability = {
            "vaultPath": str(vault.resolve()),
            "tasksPluginEnabled": True,
            "tasksApiAvailable": True,
            "settings": {},
        }

        def fake_cli(_cli, args, _timeout):
            code = next(arg[5:] for arg in args if arg.startswith("code="))
            if "app.vault.process(file" not in code:
                return subprocess.CompletedProcess(
                    ["obsidian"], 0,
                    stdout="=> " + json.dumps(capability), stderr=""
                )
            return subprocess.CompletedProcess(["obsidian"], 0, stdout="", stderr="")

        self.patch("_run_cli", fake_cli)
        with self.assertRaises(obsidian_tasks.RuntimeErrorInfo) as error:
            obsidian_tasks.toggle_tasks_task(
                str(vault),
                "Alis/Todo.md",
                scan["tasks"][0]["id"],
                scan["document"]["sha256"],
            )
        self.assertEqual(error.exception.code, "mutation_unverified")


if __name__ == "__main__":
    unittest.main()
