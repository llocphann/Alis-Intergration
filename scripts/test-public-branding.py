#!/usr/bin/env python3
"""Guard public names while keeping exact API/data/security compatibility aliases."""
import ast
import hashlib
import json
from pathlib import Path
import re

from integration_test_host import resolve_host_root

ROOT = Path(__file__).resolve().parents[1]
HOST = resolve_host_root(ROOT)
legacy = re.compile(r'(?i)(?<![a-z0-9_])(?:hadalird|hadalis|inir)(?![a-z0-9_])')
protected = [
    'HadalisSession.qml', 'Hadalis/Todo.md', '99_Hadalis_Theme.css',
    'alis ipc hadalird refresh', 'alis ipc hadalird status',
    '.hadalis-zettel-backup-', '.hadalis-backup-', '.hadalis.',
    '<!-- hadalis:todo:start -->', '<!-- hadalis:todo:end -->',
    '/usr/libexec/inir-thinkfan', '/usr/libexec/inir-battery-charge-limit',
    'assets/helpers/inir-thinkfan', 'assets/helpers/inir-battery-charge-limit',
    'alis-hadalird-gateway', 'alis-hadalird-system-provision',
    'org.alis.hadalird-system-provision.policy',
    'optional/alis-intergration', 'optional/hadalird',
    'scripts/alis-intergration-manager.py', 'scripts/alis-intergration-status.py',
    'scripts/alis-intergration-system-package.py',
]

def public(text, location):
    for identifier in protected:
        text = text.replace(identifier, '<compatibility-identifier>')
    assert not legacy.search(text), (location, text)

package_qml = sorted((ROOT / 'modules').rglob('*.qml'))
host_qml = [HOST / path for path in (
    'modules/settings/IntegrationsConfig.qml', 'modules/settings/ObsidianThemeSettings.qml',
    'modules/settings/ObsidianTodoSettings.qml', 'modules/settings/ThinkfanSettings.qml',
    'modules/settings/TlpPowerSettings.qml', 'modules/waffle/settings/pages/WTlpPage.qml')]
for path in package_qml + host_qml:
    source = path.read_text()
    strings = re.findall(r'(?:Translation\.tr\(\s*|\b(?:text|buttonText|tooltip|description|label)\s*:\s*)("(?:[^"\\]|\\.)*")', source)
    for literal in strings:
        public(json.loads(literal), str(path.relative_to(ROOT if path.is_relative_to(ROOT) else HOST)))
    if path.name == 'IntegrationsConfig.qml':
        assert '"Alis-Intergration " + Hadalird.version' in source

for root, names in ((ROOT, ('scripts/install.py', 'scripts/notes/zettelkasten.py', 'scripts/todo/obsidian_todo.py')),
                    (HOST, ('scripts/alis-intergration-manager.py', 'scripts/alis-intergration-system-package.py'))):
    for name in names:
        for node in ast.walk(ast.parse((root / name).read_text())):
            if isinstance(node, ast.Constant) and isinstance(node.value, str):
                if node.value in ('hadalird',):
                    continue  # Exact machine package locator, not display copy.
                public(node.value, name + ':' + str(node.lineno))

manifest = json.loads((ROOT / 'manifest.json').read_text())
assert manifest['name'] == 'Alis-Intergration' and manifest['host'] == 'Alis'
assert manifest['id'] == 'hadalird' and manifest['hostApi'] == 1 and manifest['session'] == 'HadalisSession.qml'
assert (ROOT / 'README.md').read_text().startswith('# Alis-Intergration\n')
assert 'editing Alis-Intergration.' in (ROOT / 'AGENTS.md').read_text()
todo = (HOST / 'services/Todo.qml').read_text()
assert re.search(r'if \(!root\.useObsidian\)\s+return "Alis"', todo)
assert '?? "Hadalis/Todo.md"' in todo, 'old saved/default note path lost'
service = (HOST / 'services/Hadalird.qml').read_text()
for target in ('integrations', 'hadalird'):
    assert f'target: "{target}"' in service
assert service.count('function refresh(): void {root.refresh()}') == 2
assert service.count('function status(): string {return root.status()}') == 2
registry = (HOST / 'scripts/lib/ipc-registry.sh').read_text()
for target in ('integrations', 'hadalird'):
    assert f'[{target}]="refresh status"' in registry

wrapper_hints = {
    'modules/settings/ObsidianThemeSettings.qml': 'Install Alis-Intergration; enable this integration in Settings → Integrations.',
    'modules/settings/ObsidianTodoSettings.qml': 'Install Alis-Intergration; enable Obsidian in Settings → Integrations.',
    'modules/settings/ThinkfanSettings.qml': 'Install Alis-Intergration; enable Thinkfan in Settings → Integrations.',
    'modules/waffle/settings/pages/WTlpPage.qml': 'Install Alis-Intergration; enable TLP in Settings → Integrations.',
}
for path, hint in wrapper_hints.items():
    assert 'Translation.tr(' + json.dumps(hint, ensure_ascii=False) + ')' in (HOST / path).read_text(), path

catalog = json.loads((HOST / 'translations/en_US.json').read_text())
for old in ('Install Hadalird', 'Remove Hadalird', 'Restore Hadalird', 'Use Hadalis',
            'Hadalis internal Todo is canonical', 'Overridden by iNiR'):
    assert old in catalog, 'installed package translation lookup removed: ' + old
    public(catalog[old], 'legacy translation value: ' + old)

for path in ('README.md', 'docs/README.md', 'docs/SERVICES.md', 'docs/THINKFAN.md', 'docs/UNINSTALL.md', 'docs/RELEASING.md', 'docs/PACKAGES.md'):
    root = ROOT if path == 'README.md' else HOST
    source = (root / path).read_text()
    assert 'github.com/llocphann/Hadalird' not in source, path
    assert not re.search(r'(?<![A-Za-z0-9_])Hadalird(?![A-Za-z0-9_])', source), path

# This exact allowlist is the documented security exception. Even changing a
# policy's wording requires an explicit compatible security migration.
expected = {
    'assets/helpers/inir-battery-charge-limit': '8244445450870f78507dee75ef62005acb1338e0f3fee635d9dc92fac3e93562',
    'assets/helpers/inir-thinkfan': 'd0d66270170999a86a791fd0da9a6e8a8c431dcd5f39b59a53fb7ab3d48d6f16',
    'assets/polkit/org.inir.battery-charge-limit.policy': 'f201c62a44715372c9d463f1c5cc492d48fcc54834ed6137b5103d22257921c5',
    'assets/polkit/org.inir.thinkfan.policy': '13bfd4dc99baa4aa5b2b09db6d7e3cd45765967487ebe0b82597e6cfd13ca2ef',
    'assets/tlp/tlp-settings-schema.json': 'b23cdaa8b3bb4fd3f8bd36e1bb1c8b61fcce0018eaa5175656353af42d309adb',
}
for path, value in expected.items():
    assert hashlib.sha256((ROOT / path).read_bytes()).hexdigest() == value, path
print('INTEGRATION_PUBLIC_BRAND_PASS public-copy metadata legacy-lookups single-owner-IPC preserved-API security-pins')
