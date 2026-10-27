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
legacy = re.compile(r'(?i)(?<![a-z0-9_])(?:\x68\x61\x64\x61\x6c\x69\x72\x64|\x68\x61\x64\x61\x6c\x69\x73|\x69\x6e\x69\x72)(?![a-z0-9_])')
protected = [
    'AlisSession.qml', 'Alis/Todo.md', '99_Alis_Theme.css',
    'alis ipc alis-intergration refresh', 'alis ipc alis-intergration status',
    '.alis-zettel-backup-', '.alis-backup-', '.alis.',
    '<!-- alis:todo:start -->', '<!-- alis:todo:end -->',
    '/usr/libexec/alis-thinkfan', '/usr/libexec/alis-battery-charge-limit',
    'assets/helpers/alis-thinkfan', 'assets/helpers/alis-battery-charge-limit',
    'alis-intergration-gateway', 'alis-intergration-system-provision',
    'org.alis.intergration-system-provision.policy',
    'optional/alis-intergration', 'optional/alis-intergration',
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
        assert '"Alis-Intergration " + AlisIntergration.version' in source

for root, names in ((ROOT, ('scripts/install.py', 'scripts/notes/zettelkasten.py', 'scripts/todo/obsidian_todo.py')),
                    (HOST, ('scripts/alis-intergration-manager.py', 'scripts/alis-intergration-system-package.py'))):
    for name in names:
        for node in ast.walk(ast.parse((root / name).read_text())):
            if isinstance(node, ast.Constant) and isinstance(node.value, str):
                if node.value in ('alis-intergration',):
                    continue  # Exact machine package locator, not display copy.
                public(node.value, name + ':' + str(node.lineno))

manifest = json.loads((ROOT / 'manifest.json').read_text())
assert manifest['name'] == 'Alis-Intergration' and manifest['host'] == 'Alis'
assert manifest['id'] == 'alis-intergration' and manifest['hostApi'] == 1 and manifest['session'] == 'AlisSession.qml'
assert (ROOT / 'README.md').read_text().startswith('# Alis-Intergration\n')
assert 'editing Alis-Intergration.' in (ROOT / 'AGENTS.md').read_text()
todo = (HOST / 'services/Todo.qml').read_text()
assert re.search(r'if \(!root\.useObsidian\)\s+return "Alis"', todo)
assert '?? "Alis/Todo.md"' in todo, 'old saved/default note path lost'
service = (HOST / 'services/AlisIntergration.qml').read_text()
for target in ('integrations', 'alis-intergration'):
    assert f'target: "{target}"' in service
assert service.count('function refresh(): void {root.refresh()}') == 2
assert service.count('function status(): string {return root.status()}') == 2
registry = (HOST / 'scripts/lib/ipc-registry.sh').read_text()
for target in ('integrations', 'alis-intergration'):
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
for old in ('Install Alis-Intergration', 'Remove Alis-Intergration', 'Restore Alis-Intergration', 'Use Alis',
            'Alis internal Todo is canonical', 'Overridden by Alis'):
    assert old in catalog, 'installed package translation lookup removed: ' + old
    public(catalog[old], 'legacy translation value: ' + old)

for path in ('README.md', 'docs/README.md', 'docs/SERVICES.md', 'docs/THINKFAN.md', 'docs/UNINSTALL.md', 'docs/RELEASING.md', 'docs/PACKAGES.md'):
    root = ROOT if path == 'README.md' else HOST
    source = (root / path).read_text()
    assert 'github.com/llocphann/\x48\x61\x64\x61\x6c\x69\x72\x64' not in source, path
    assert not re.search(r'(?<![A-Za-z0-9_])\x48\x61\x64\x61\x6c\x69\x72\x64(?![A-Za-z0-9_])', source), path

# This exact allowlist is the documented security exception. Even changing a
# policy's wording requires an explicit compatible security migration.
expected = {
    'assets/helpers/alis-battery-charge-limit': '9ca3b1aee470a130fdc0e8861953858a9d2da218ee910ff3b4e2dc39398fba03',
    'assets/helpers/alis-thinkfan': 'dfab10c593032322d89b2e06b796fbdaf6a36cbc55fba272acac85500166f06a',
    'assets/polkit/org.alis.battery-charge-limit.policy': 'a1e82cdf472a6df24fe0539e47012acd70f6e90aaadc328406787eb6917597b0',
    'assets/polkit/org.alis.thinkfan.policy': 'b50ddbdd2619496e22322a3f02dd7a94522b627e2b9bff08818fd9cfae2fa17d',
    'assets/tlp/tlp-settings-schema.json': 'b23cdaa8b3bb4fd3f8bd36e1bb1c8b61fcce0018eaa5175656353af42d309adb',
}
for path, value in expected.items():
    assert hashlib.sha256((ROOT / path).read_bytes()).hexdigest() == value, path
print('INTEGRATION_PUBLIC_BRAND_PASS public-copy metadata legacy-lookups single-owner-IPC preserved-API security-pins')
