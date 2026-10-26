#!/usr/bin/env python3
"""Real pre-patch payload/settings survive offline rebrand lifecycle operations."""
import copy
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import stat
import tarfile
import tempfile
from unittest.mock import patch
import xml.etree.ElementTree as ET

from integration_test_host import resolve_host_root

ROOT = Path(__file__).resolve().parents[1]
HOST = resolve_host_root(ROOT)
sys.path.insert(0, str(ROOT / 'scripts/todo'))
FIXTURE = ROOT / 'scripts/fixtures/rebrand-v1'
provenance = json.loads((FIXTURE / 'provenance.json').read_text())
assert provenance['hostSha'] == '36b163a52298a3d9cfc5b021097531a89c7d17dd'
assert provenance['integrationSha'] == '9d67e80024dba838b9574e52e65bff71ec4eac3c'
for name, expected in provenance['files'].items():
    assert hashlib.sha256((FIXTURE / name).read_bytes()).hexdigest() == expected, name

def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value

installer = module('rebrand_installer', ROOT / 'scripts/install.py')
manager = module('rebrand_manager', HOST / 'scripts/alis-intergration-manager.py')
legacy_reader = module('legacy_reader', FIXTURE / 'legacy-host-discovery.py')
todo = module('rebrand_todo', ROOT / 'scripts/todo/obsidian_todo.py')
new_sha = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
old_sha = provenance['integrationSha']

def snapshot(folder):
    return {p.relative_to(folder).as_posix(): (stat.S_IMODE(p.stat().st_mode), p.read_bytes())
            for p in folder.rglob('*') if p.is_file() and not p.is_symlink()}

def archive(folder):
    output = io.BytesIO()
    with tarfile.open(fileobj=output, mode='w:gz') as stream:
        for path in sorted(folder.rglob('*')):
            if path.is_file():
                stream.add(path, arcname='source/' + str(path.relative_to(folder)), recursive=False)
    return output.getvalue()

with tempfile.TemporaryDirectory(prefix='alis-rebrand-compat-') as name:
    private = Path(name)
    home = private / 'data/alis-intergration'
    home.mkdir(parents=True)
    old_files = manager.unpack((FIXTURE / 'legacy-package.tar.gz').read_bytes())
    old_release = home / 'releases' / old_sha
    old_release.mkdir(parents=True)
    with tarfile.open(FIXTURE / 'legacy-package.tar.gz', 'r:gz') as archived:
        modes = {str(Path(m.name).relative_to('legacy-release')): m.mode for m in archived.getmembers() if m.isfile()}
    for path, content in old_files.items():
        dest = old_release / path
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(content)
        dest.chmod(modes[path])
    (home / 'current').symlink_to('releases/' + old_sha)
    old_bytes = snapshot(old_release)
    assert manager.discovery.inspect_package(old_release)['available']
    assert legacy_reader.inspect_package(old_release)['available']

    preserved = private / 'user'
    preserved.mkdir()
    for filename in ('config.json', 'todo.json', 'todo.txt', 'managed-note.md'):
        (preserved / filename).write_bytes((FIXTURE / filename).read_bytes())
    (preserved / 'credentials').write_bytes(b'synthetic opaque owner secret\x00preserve')
    (preserved / 'custom-profile.conf').write_bytes(b'CPU_BOOST_ON_AC=0\n# owner setting\n')
    preserved_bytes = snapshot(preserved)

    candidate = private / 'candidate'
    installer.assemble(ROOT, candidate, new_sha)
    new_manifest = json.loads((candidate / 'manifest.json').read_text())
    old_manifest = json.loads(old_files['manifest.json'])
    assert new_manifest['id'] == old_manifest['id'] == 'alis-intergration'
    assert new_manifest['name'] == 'Alis-Intergration' and new_manifest['host'] == 'Alis'
    for field in ('hostApi', 'session', 'settings', 'backends', 'integrations', 'plugins', 'derivedFrom', 'uiDerivedFrom'):
        assert new_manifest[field] == old_manifest[field], field
    assert legacy_reader.inspect_package(candidate)['available'], 'API 1 host cannot load new display metadata'
    assert manager.discovery.inspect_package(candidate)['available']
    for path in old_files:
        if path.startswith(('assets/helpers/', 'assets/polkit/', 'assets/tlp/')):
            assert (candidate / path).read_bytes() == old_files[path], path
    for path in ('assets/polkit/org.alis.battery-charge-limit.policy', 'assets/polkit/org.alis.thinkfan.policy'):
        policy = ET.fromstring((candidate / path).read_bytes())
        assert policy.find('.//allow_any').text == policy.find('.//allow_inactive').text == 'no'
        assert policy.find('.//allow_active').text == 'yes'
        assert policy.find('.//action').attrib['id'].startswith('org.alis.')

    bundle = archive(candidate)
    calls = []
    def fetch(url, limit):
        calls.append(url)
        assert len(bundle) <= limit
        return bundle
    def operate(action, **kwargs):
        return manager.operate(action, home, HOST,
            revision_fetch=lambda: new_sha, archive_fetch=fetch, **kwargs)
    def preserved_state():
        assert snapshot(preserved) == preserved_bytes
        assert snapshot(old_release) == old_bytes
        assert sorted(p.name for p in home.parent.iterdir()) == ['alis-intergration']

    assert operate('status')['installedSha'] == old_sha
    assert operate('check')['updateAvailable']
    # Failed download and interrupted atomic activation preserve the old owner.
    with patch.object(manager, 'unpack', side_effect=ValueError('injected incomplete download')):
        try:
            operate('install')
            raise AssertionError('failed download reported success')
        except ValueError:
            pass
    assert (home / 'current').resolve() == old_release
    preserved_state()
    original_replace = manager.os.replace
    def interrupted(source, target):
        if Path(target) == home / 'current':
            raise OSError('injected interruption before atomic activation')
        return original_replace(source, target)
    with patch.object(manager.os, 'replace', side_effect=interrupted):
        try:
            operate('install')
            raise AssertionError('interrupted activation reported success')
        except OSError:
            pass
    assert (home / 'current').resolve() == old_release
    assert not (home / '.previous').exists()
    preserved_state()

    report = operate('install')
    assert report['installedSha'] == new_sha and report['available']
    assert (home / '.previous').read_text().strip() == old_sha
    new_release = home / 'releases' / new_sha
    new_bytes = snapshot(new_release)
    downloads = len(calls)
    for _ in range(3):
        assert operate('install')['installedSha'] == new_sha
        assert snapshot(new_release) == new_bytes
        assert len(calls) == downloads, 'idempotent reinstall fetched or rewrote a release'
        preserved_state()
    # A fresh manager object models process restart, not cached in-memory state.
    restarted = module('rebrand_manager_restart', HOST / 'scripts/alis-intergration-manager.py')
    assert restarted.operate('status', home, HOST)['installedSha'] == new_sha
    assert operate('rollback')['installedSha'] == old_sha
    assert operate('rollback')['installedSha'] == new_sha
    preserved_state()
    assert not operate('remove')['available']
    assert not (home / 'current').is_symlink() and old_release.is_dir() and new_release.is_dir()
    preserved_state()
    assert operate('install')['installedSha'] == new_sha
    assert sorted(p.name for p in (home / 'releases').iterdir()) == sorted([old_sha, new_sha])
    preserved_state()

    # Mixed historic/new note records preserve source IDs and surrounding bytes.
    vault = private / 'vault'
    note = vault / 'Alis/Todo.md'
    note.parent.mkdir(parents=True)
    note.write_bytes((FIXTURE / 'managed-note.md').read_bytes())
    before = todo.scan_note(str(vault), 'Alis/Todo.md')
    old_id = before['tasks'][0]['id']
    todo.add_basic_task(str(vault), 'Alis/Todo.md', 'new task after rebrand',
                        before['document']['sha256'], before['managed']['sha256'])
    after = todo.scan_note(str(vault), 'Alis/Todo.md')
    assert after['tasks'][0]['id'] == old_id and len(after['tasks']) == 2
    assert note.read_bytes().startswith(b'# Existing owner note\r\n')
    assert note.read_bytes().endswith(b'Unrelated owner bytes.\r\n')
    assert note.read_bytes().count(b'<!-- alis:todo:start -->') == 1

    fresh_home = private / 'fresh-data/alis-intergration'
    assert manager.operate('install', fresh_home, HOST, revision_fetch=lambda:new_sha, archive_fetch=fetch)['available']
    assert manager.discovery.inspect(HOST, fresh_home.parent)['available']
    assert [p['id'] for p in manager.discovery.inspect(HOST, fresh_home.parent)['plugins']] == ['tlp','thinkfan','obsidian']
    # The supported setup preview cannot touch the persisted transaction store.
    env = dict(os.environ, XDG_DATA_HOME=str(home.parent), XDG_STATE_HOME=str(private/'state'))
    preview = subprocess.run(['python3', str(HOST/'scripts/integration-setup.py'), 'install', '--dry-run'],
                             env=env, capture_output=True, text=True, check=True)
    assert json.loads(preview.stdout)['workersEnabled'] is False
    assert not (private/'state').exists()
    preserved_state()

print('INTEGRATION_REBRAND_COMPAT_PASS authentic-old-payload old-host/new-package new-host/old-package fresh mixed repeat restart rollback remove failure-retry preserved-data permissions')
