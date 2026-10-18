#!/usr/bin/env python3
"""Owned Obsidian task/capture settings contract; host routing is tested in Hadalis."""
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
todo=(ROOT/'modules/settings/ObsidianTodoSettings.qml').read_text()
required = [
    'Translation.tr("To-do & Quick Notes")',
    'title: Translation.tr("Task source")',
    'Translation.tr("Note path pattern")',
    'Translation.tr("Heading")',
    'id: todoMarkdownNotePattern',
    'id: todoMarkdownHeading',
    'Config.setNestedValue("todo.obsidian.dailyNote.folder", folder)',
    'Config.setNestedValue("todo.obsidian.dailyNote.format", format)',
    'Config.setNestedValue("todo.obsidian.dailyNote.plannerHeading", value)',
    'Config.setNestedValue("todo.obsidian.dailyNote.plannerHeadingLevel", value)',
    'Config.setNestedValue("todo.obsidian.dailyNote.defaultDurationMinutes", value)',
    'Config.setNestedValue("todo.obsidian.sourceMode", "markdown-note")',
    'Todo.beginObsidianSetup()',
    'Todo.cancelObsidianSetup()',
    'Todo.reactivateInternal()',
    'Todo.previewInternalToObsidian()',
    'Todo.migrateInternalToObsidian(',
    'Todo.activateObsidian()',
    'Todo.openObsidianSource()',
    'Translation.tr("Use Obsidian source")',
]
for token in required:
    assert token in todo, f"Obsidian task settings contract lost: {token}"
assert 'Config.setNestedValue("todo.backend", "obsidian")' not in todo
for token in ['Day Planner', 'Planner heading', 'font.pixelSize: Appearance.font.pixelSize.smallest', 'id: zettelkastenVaultPath', 'Translation.tr("Vault path override")']:
    assert token not in todo, token
assert todo.count('Translation.tr("To-do & Quick Notes")')==1
assert todo.count('placeholderText: ""')>=3
assert '/^\\/+|\\/+$/g' in todo
assert 'notes.zettelkasten.folder' in todo and 'notes.zettelkasten.defaultType' in todo
for token in ['title: Translation.tr("Quick Notes")', 'Translation.tr("Default Zettelkasten type")', 'value: "Fleeting"', 'value: "Literature"', 'value: "Permanent"', 'Zettelkasten.folder', 'Translation.tr("Activate verified source.")']:
    assert token in todo, token
zettel=todo[todo.index('title: Translation.tr("Quick Notes")'):]
assert 'color: Appearance.colors.colSubtext' not in zettel
assert 'placeholderText: "00_Capture/03_Zettelkasten"' not in zettel
assert 'Translation.tr("Canonical task store")' not in todo
print('HADALIRD_OBSIDIAN_TODO_SETTINGS_PASS')

INTEGRATIONS=todo
for removed_copy in (
    'Translation.tr("One Markdown file and heading.")',
    'Translation.tr("Obsidian vault root.")',
    'Translation.tr("Fixed or date-based Markdown path.")',
    'Translation.tr("Checkboxes under this heading only.")',
    'Translation.tr("Direct Markdown sync.")',
    'Translation.tr("Capture to Zettelkasten; keep the draft.")',
    'Translation.tr("Blank = reuse Todo vault.")',
    'Translation.tr("Vault-relative capture folder.")',
    'Translation.tr("Uses the vault Zettelkasten template.")',
    'Translation.tr("Vault path override")',
):
    assert removed_copy not in INTEGRATIONS, f"redundant Settings copy returned: {removed_copy}"

for stale in (
    "Use one Markdown note source. The path may be fixed or contain date tokens",
    "Physical Obsidian vault folder. Hadalis resolves the configured note strictly inside this directory.",
    "Dashboard Quick Notes are drafts until capture. A successful capture creates one filesystem-canonical Zettelkasten note, then clears the unchanged draft.",
    "The generated Markdown follows the vault's Zettelkasten schema:",
):
    assert stale not in INTEGRATIONS, f"verbose/stale Settings copy returned: {stale}"
