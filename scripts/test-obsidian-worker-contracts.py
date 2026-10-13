#!/usr/bin/env python3
"""Preserved Obsidian worker contracts; native/private-vault tests cover behavior."""
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
CONTRACTS = {'services/ObsidianTodoBackend.qml': ['Scope {',
                                      'property bool active: false',
                                      'property string vaultPath: ""',
                                      'property string notePath: ""',
                                      'property bool preferTasksPlugin: true',
                                      'property bool allowBasicOfflineMutation: true',
                                      'property var list: []',
                                      'property bool ready: false',
                                      'property bool busy: false',
                                      'property var capabilities:',
                                      'property string _capabilityVaultPath: ""',
                                      'property string _capabilityNotePath: ""',
                                      'property string _mutationVaultPath: ""',
                                      'property string _mutationNotePath: ""',
                                      'root._pendingMutation = null',
                                      'function _capabilitySourceCurrent(): bool',
                                      'function _mutationSourceCurrent(): bool',
                                      'root._capabilityVaultPath = root.vaultPath',
                                      'root._capabilityNotePath = root.notePath',
                                      'root._mutationVaultPath = root.vaultPath',
                                      'root._mutationNotePath = root.notePath',
                                      'if (!root._capabilitySourceCurrent())',
                                      'if (!root._mutationSourceCurrent())',
                                      'Qt.resolvedUrl("../scripts/todo/obsidian_todo.py")',
                                      'Qt.resolvedUrl("../scripts/todo/obsidian_tasks.py")',
                                      '"scan"',
                                      '"probe-capabilities"',
                                      '"add-basic"',
                                      '"toggle-basic"',
                                      '"toggle-tasks"',
                                      '"delete"',
                                      'function initializeSection(): bool',
                                      'function previewInternal(internalJsonPath: string): bool',
                                      '"preview-migration"',
                                      'property var migrationPreview: null',
                                      'signal migrationCommitted(var payload)',
                                      'function migrateInternal(internalJsonPath: string, '
                                      'expectedInternalSha: string): bool',
                                      '"--expected-internal-sha"',
                                      '"migrate-internal"',
                                      '"--internal-json"',
                                      '"initialize-section"',
                                      'function toggleTask(taskId: string)',
                                      'function deleteTask(taskId: string)',
                                      'function refreshCapabilities(): void',
                                      'FileView {',
                                      'watchChanges: root.configured',
                                      'preload: false',
                                      'scanDebounce.restart()',
                                      'capabilityDebounce.restart()',
                                      'root._taskNeedsTasks(task)',
                                      'function _applyTasksStatusSemantics(): void',
                                      'const statusType = String(bySymbol[symbol] ?? "TODO")',
                                      'item.done = statusType === "DONE"',
                                      'root.capabilities?.richMutationAvailable === true',
                                      'const filter = '
                                      'String(root.capabilities.tasksSettings?.globalFilter ?? "")',
                                      'text = filter + " " + text',
                                      'if (mutationProc.running || root._pendingMutation !== null)',
                                      'code === "rich_task_required"',
                                      'mutationProc.kind === "preview-migration"',
                                      'root.migrationPreview = payload',
                                      'root.migrationCommitted(payload)',
                                      'JSON.parse(output)'],
 'services/DailyNoteTodoBackend.qml': ['property string folder: "00_Capture/01_Journal"',
                                       'property string noteFormat: "YYYY/MMMM/DD-MM-YYYY-dddd"',
                                       'property string plannerHeading: "Tasks"',
                                       'property int plannerHeadingLevel: 2',
                                       'property int defaultDurationMinutes: 30',
                                       'sourceMode: "markdown-note"',
                                       'Qt.resolvedUrl("../scripts/todo/obsidian_daily_todo.py")',
                                       'Qt.formatDate(new Date(), "yyyy-MM-dd")',
                                       'function addTask(text: string, startTime: string, endTime: '
                                       'string): bool',
                                       'function toggleTask(taskId: string): bool',
                                       'function deleteTask(taskId: string): bool',
                                       'function previewInternal(internalJsonPath: string): bool',
                                       'function migrateInternal(internalJsonPath: string, '
                                       'expectedInternalSha: string): bool',
                                       '"preview-migration"',
                                       '"migrate-internal"',
                                       'expected-section-sha',
                                       'root.migrationFinished(success, payload)',
                                       'root.migrationCommitted(payload)'],
 'scripts/todo/obsidian_daily_todo.py': ['DEFAULT_FOLDER = "00_Capture/01_Journal"',
                                         'DEFAULT_FORMAT = "YYYY/MMMM/DD-MM-YYYY-dddd"',
                                         'DEFAULT_HEADING = "Tasks"',
                                         'def scan_daily_note(',
                                         'def add_task(',
                                         'def toggle_task(',
                                         'def delete_task(',
                                         'daily_note_not_found',
                                         'invalid_planner_section'],
 'services/Zettelkasten.qml': ['Item {',
                               'Qt.resolvedUrl("../scripts/notes/zettelkasten.py")',
                               'function capture(title, body): bool',
                               'readonly property string configuredVaultPath: '
                               'HostServices.Todo.sharedVaultPath',
                               '?? "00_Capture/03_Zettelkasten"',
                               '?? "Fleeting"',
                               'signal captured(var payload)'],
 'scripts/notes/zettelkasten.py': ['ALLOWED_TYPES = ("Permanent", "Literature", "Fleeting")',
                                   'DEFAULT_FOLDER = "00_Capture/03_Zettelkasten"',
                                   'DEFAULT_TYPE = "Fleeting"',
                                   '"## Core Idea"',
                                   '"## Content"',
                                   '"## Context & Connections"',
                                   '"## Sources & References"',
                                   '"aliases: []"',
                                   '"templateCompatible": True']}
for path,tokens in CONTRACTS.items():
    text=(ROOT/path).read_text(encoding="utf-8")
    for token in tokens:
        assert token in text, path+" lost contract: "+token
managed=(ROOT/"services/ObsidianTodoBackend.qml").read_text()
for token in ('root._notifyMigrationFinished(false, null)', 'root._notifyMigrationFinished(true, payload)'):
    assert token in managed, "owned migration completion lost contract: "+token
for token in ('["obsidian"','"eval"','vault=','bySymbol[symbol] ?? item.statusType'):
    assert token not in managed, "QML must not bypass non-launching/active-vault/status guards: "+token
daily=(ROOT/"services/DailyNoteTodoBackend.qml").read_text()
assert "obsidian_tasks.py" not in daily and "probe-capabilities" not in daily
for path in ("scripts/todo/obsidian_todo.py","scripts/todo/obsidian_tasks.py"):
    assert (ROOT/path).is_file()
settings=(ROOT/"modules/settings/ObsidianThemeSettings.qml").read_text()
for token in ('id: todoObsidianVaultPath','updates["todo.obsidian.vaultPath"] = value','updates["notes.zettelkasten.vaultPath"] = ""','Config.setNestedValues(updates)'):
    assert token in settings, "shared-vault settings lost contract: "+token
for token in ('Translation.tr("Obsidian vault folder")', 'Translation.tr("Shared by To-do and Zettelkasten.")', 'text: Todo.sharedVaultPath'):
    assert token in settings, "shared-vault label/help lost contract: "+token
# Agenda-to-Todo automation was withdrawn by the owner. Backends must never
# expose its mutation API; still parse historical metadata without rewriting it.
for name in ("services/ObsidianTodoBackend.qml", "services/DailyNoteTodoBackend.qml"):
    source=(ROOT/name).read_text(encoding="utf-8")
    for retired in ("AgendaTaskMutation", "agendaJob", "ensureAgenda(",
                    "unlinkAgenda(", "deleteAgenda(", "agendaMutationFinished"):
        assert retired not in source, name+" retains retired Agenda writer: "+retired
for name in ("services/AgendaTaskMutation.qml", "services/qmldir",
             "scripts/todo/obsidian_agenda.py",
             "scripts/test-obsidian-agenda-helper.py"):
    assert not (ROOT/name).exists(), name+" resurrected obsolete linking code"
metadata=(ROOT/"scripts/todo/agenda_metadata.py").read_text(encoding="utf-8")
assert "def split(content):" in metadata and "def render(" not in metadata
import base64
import json
import sys
sys.path.insert(0,str(ROOT/"scripts/todo"))
import agenda_metadata
legacy={"version":1,"key":"agenda-legacy-test-001","date":"2026-10-12"}
encoded=base64.urlsafe_b64encode(json.dumps(legacy).encode()).decode().rstrip("=")
body="Old user task <!-- alis:agenda:v1:"+encoded+" -->"
clean,parsed=agenda_metadata.split(body)
assert clean=="Old user task" and parsed==legacy
assert agenda_metadata.split("Unrelated task <!-- other:marker -->")==("Unrelated task <!-- other:marker -->",None)
print("HADALIRD_OBSIDIAN_WORKER_CONTRACTS_PASS managed/daily source identity, migration/status/plugin boundaries, quick-note template and shared vault")
