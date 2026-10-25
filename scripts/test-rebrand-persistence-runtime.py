#!/usr/bin/env python3
"""Read actual pre-patch persistence through native Settings and process restarts."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile

from integration_test_host import resolve_host_root

parser = argparse.ArgumentParser()
parser.add_argument('--baseline', action='store_true', help='Expect pre-rebrand host display copy')
parser.add_argument('--package-root', type=Path, help='Pinned pre-patch checkout for a comparable baseline')
parser.add_argument('--fixture-root', type=Path, help='Sanitized persisted capture outside the source checkout')
args = parser.parse_args()
ROOT = args.package_root or Path(__file__).resolve().parents[1]
HOST = resolve_host_root(ROOT)
FIXTURE = args.fixture_root or ROOT / 'scripts/fixtures/rebrand-v1'
sys.path.insert(0, str(HOST / 'scripts'))
from native_test_session import private_wayland, run_qs

def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value

installer = module('persistence_installer', ROOT / 'scripts/install.py')
manager = module('persistence_manager', HOST / 'scripts/alis-intergration-manager.py')
expected_tasks = json.loads((FIXTURE / 'todo.json').read_text())
settings = json.loads((FIXTURE / 'config.json').read_text())
old_bytes = (FIXTURE / 'managed-note.md').read_bytes()
old_config_keys = ('integrations', 'todo', 'notes', 'battery', 'powerProfiles', 'ownerRecord')
phases = [('absent', False, False), ('old', False, False), ('new', True, False),
          ('new', False, True), ('old', False, True), ('old', False, True)]

with tempfile.TemporaryDirectory(prefix='alis-rebrand-persistence-') as name:
    private = Path(name)
    shell = private / 'shell'
    shell.mkdir()
    for entry in ('modules', 'services', 'GlobalStates.qml', 'qmldir', 'defaults', 'translations', 'assets'):
        (shell / entry).symlink_to(HOST / entry)
    scripts = shell / 'scripts'
    scripts.mkdir()
    for entry in (HOST / 'scripts').iterdir():
        if entry.name != 'alis-intergration-manager.py':
            (scripts / entry.name).symlink_to(entry)
    # Only the read-only status transport is injected. Production QML,
    # discovery, settings, persisted data and package workers remain real.
    status_calls = private / 'status-calls.jsonl'
    (scripts / 'alis-intergration-manager.py').write_text(
        'import json,sys\nfrom pathlib import Path\n'
        + f'p=Path({str(status_calls)!r})\n'
        + 'with p.open("a") as f:f.write(json.dumps(sys.argv[1:])+"\\n")\n'
        + 'assert sys.argv[1]=="system-status"\n'
        + 'print(json.dumps({"ok":True,"systemProvisionerAvailable":False,"systemHelpersInstalled":False,"systemHelpersDiagnostic":"fixture-not-installed"}))\n')
    config_dir = private / 'config/alis'
    config_dir.mkdir(parents=True)
    state = private / 'state/quickshell/user'
    state.mkdir(parents=True)
    for filename in ('todo.json', 'todo.txt'):
        shutil.copy2(FIXTURE / filename, state / filename)
    vault = private / 'old vault café'
    (vault / 'Hadalis').mkdir(parents=True)
    note = vault / 'Hadalis/Todo.md'
    note.write_bytes(old_bytes)
    (vault / '.obsidian').mkdir()
    (vault / '.obsidian/appearance.json').write_text('{"cssTheme":"Owner theme","enabledCssSnippets":[]}\n')
    settings['notes']['zettelkasten']['vaultPath'] = str(vault)
    (config_dir / 'config.json').write_text(json.dumps(settings))
    data = private / 'data/alis-intergration'
    data.mkdir(parents=True)
    old_release = data / 'releases/old'
    old_release.mkdir(parents=True)
    for path, content in manager.unpack((FIXTURE / 'legacy-package.tar.gz').read_bytes()).items():
        output = old_release / path
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_bytes(content)
    new_release = data / 'releases/new'
    installer.assemble(ROOT, new_release, 'f' * 40)
    shell_qml = r'''
import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.services
import qs.modules.settings
ShellRoot {
 Component.onCompleted: Quickshell.watchFiles=false
 Process {
  id:ipcProbe
  property bool finished:false
  property int code:-1
  stdout:StdioCollector {id:ipcOutput}
  stderr:StdioCollector {id:ipcError}
  onExited:exitCode=>{code=exitCode;finished=true}
 }
 FloatingWindow {visible:true;implicitWidth:850;implicitHeight:700
  IntegrationsConfig {id:page;anchors.fill:parent}
 }
 TestCase {
  id:test;when:false;optional:true
  function check(v,m){if(!v)throw new Error(m)}
  function invoke(target,method){
   ipcProbe.finished=false;ipcProbe.code=-1
   ipcProbe.command=["qs","-p",Quickshell.shellPath(""),"ipc","call",target,method]
   ipcProbe.running=true
   tryVerify(()=>ipcProbe.finished,4000)
   check(ipcProbe.code===0,"IPC failed: "+target+" "+method+" "+ipcError.text)
   return String(ipcOutput.text??"").trim()
  }
  function run(){try{
   tryCompare(Config,"ready",true,4000);tryCompare(Todo,"ready",true,4000)
   const installed=Quickshell.env("REBRAND_INSTALLED")==="1"
   const enabled=Quickshell.env("REBRAND_ENABLED")==="1"
   tryCompare(Hadalird,"available",installed,4000)
   check(page.primaryTabs.length===(installed?4:1),"old/new plugin tabs duplicated or missing")
   check(Todo.backend==="internal" && Todo.sourceLabel===Quickshell.env("REBRAND_SOURCE_LABEL"),"internal source/label changed")
   check(Todo.sharedVaultPath===Quickshell.env("REBRAND_VAULT"),"legacy vault fallback lost")
   check(Config.options.todo.obsidian.notePath==="Hadalis/Todo.md","stored note path renamed")
   check(Config.options.todo.obsidian.sourceMode==="managed-note","stored source mode reset")
   check(Config.options.battery.chargeLimit.threshold===73,"battery preference reset")
   check(Config.options.powerProfiles.fanControl.balanced===2,"fan preference reset")
   check(!Hadalird.tlpEnabled && !Hadalird.thinkfanEnabled,"hardware workers activated")
   check(Config.options.integrations.hadalird.obsidian===enabled,"explicit saved plugin flag lost")
   tryCompare(Todo,"internalItemCount",Number(Quickshell.env("REBRAND_COUNT")),4000)
   check(Todo.list[0].id==="legacy-task-001" && Todo.list[1].id==="legacy-task-002","stored IDs lost")
   check(Todo.list[0].agenda.createdAt==="2025-01-02T03:04:05Z" && Todo.list[0].agenda.recurrence.interval===2,"historic metadata changed")
   if(enabled)tryVerify(()=>Hadalird.session!==null,3000)
   else check(Hadalird.session===null,"default-disabled worker loaded")
   const legacyStatus=JSON.parse(invoke("hadalird","status"))
   if(Quickshell.env("REBRAND_BASELINE")!=="1"){
    const canonicalStatus=JSON.parse(invoke("integrations","status"))
    check(JSON.stringify(canonicalStatus)===JSON.stringify(legacyStatus),"IPC alias status drift")
    invoke("integrations","refresh");tryCompare(Hadalird,"available",installed,3000)
   }
   const source=JSON.stringify(Config.options.todo.obsidian)
   check(Todo.beginObsidianSetup(),"setup preview unavailable")
   Todo.cancelObsidianSetup()
   check(Todo.backend==="internal" && JSON.stringify(Config.options.todo.obsidian)===source,"Cancel rewrote the persisted source")
   if(Quickshell.env("REBRAND_WRITE")==="1"){
    check(Todo.addItem({id:"post-patch-003",content:"New record alongside old",done:false}),"post-patch save failed")
    Config.setNestedValue("todo.obsidian.preferTasksPlugin",false)
    Hadalird.setPluginEnabled("obsidian",true)
    tryVerify(()=>!Todo.internalPersistenceBusy,4000)
   }
   Config.flushWrites();wait(500)
   console.info("REBRAND_PERSISTENCE_RUNTIME_PASS",Quickshell.env("REBRAND_PHASE"))
  }catch(e){console.error("REBRAND_PERSISTENCE_RUNTIME_FAIL",e.message,e.stack)}Qt.quit()}
 }
 Timer {interval:100;running:true;onTriggered:test.run()}
}
'''
    (shell / 'shell.qml').write_text(shell_qml)
    with private_wayland(private) as env:
        if env is None:
            raise SystemExit('SKIP: persisted Settings/worker lifecycle requires private Niri')
        for index, (package, write, enabled) in enumerate(phases):
            current = data / 'current'
            current.unlink(missing_ok=True)
            if package != 'absent':
                current.symlink_to('releases/' + package)
            before_config = json.loads((config_dir / 'config.json').read_text())
            before_records = json.loads((state / 'todo.json').read_text())
            run_env = dict(env, LC_ALL='C.UTF-8', LANG='C.UTF-8',
                REBRAND_INSTALLED='0' if package=='absent' else '1',
                REBRAND_ENABLED='1' if enabled else '0', REBRAND_WRITE='1' if write else '0',
                REBRAND_COUNT=str(len(before_records)), REBRAND_VAULT=str(vault),
                REBRAND_SOURCE_LABEL='Hadalis' if args.baseline else 'Alis', REBRAND_PHASE=str(index),
                REBRAND_BASELINE='1' if args.baseline else '0')
            result = run_qs(shell, run_env, timeout=25)
            if result.returncode or 'REBRAND_PERSISTENCE_RUNTIME_PASS' not in result.stdout or any(token in result.stdout for token in
                ('REBRAND_PERSISTENCE_RUNTIME_FAIL', 'TypeError:', 'ReferenceError:', 'Binding loop', 'Unable to assign', 'Failed to load configuration')):
                print(result.stdout)
                raise SystemExit(1)
            saved = json.loads((config_dir / 'config.json').read_text())
            records = json.loads((state / 'todo.json').read_text())
            assert records[:2] == expected_tasks, ('historic task record changed', index)
            assert saved['ownerRecord'] == settings['ownerRecord']
            assert saved['todo']['obsidian']['notePath'] == 'Hadalis/Todo.md'
            assert saved['notes']['zettelkasten']['vaultPath'] == str(vault)
            assert note.read_bytes() == old_bytes, 'native Settings mutated vault bytes'
            if write:
                expected = json.loads(json.dumps(before_config))
                expected['todo']['obsidian']['preferTasksPlugin'] = False
                expected['integrations']['hadalird']['obsidian'] = True
                for key in old_config_keys:
                    assert saved[key] == expected[key], ('unrelated setting changed during save', key)
                assert records[2]['id'] == 'post-patch-003' and len(records) == 3
            else:
                for key in old_config_keys:
                    assert saved[key] == before_config[key], ('restart/Cancel/rollback rewrote settings', key)
                assert records == before_records
    assert status_calls.exists()
    assert all(json.loads(line)[0]=='system-status' for line in status_calls.read_text().splitlines())

print('INTEGRATION_REBRAND_PERSISTENCE_PASS 6 native process lifecycles old-settings old-tasks mixed-data Cancel explicit-save restart rollback repeat no-vault-write')
