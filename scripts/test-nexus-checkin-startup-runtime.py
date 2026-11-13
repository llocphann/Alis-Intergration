#!/usr/bin/env python3
"""Check persisted Journal field presence and Companion dates in a private native host."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import sys
import tempfile
from zoneinfo import ZoneInfo

QML = r'''
import QtQuick
import QtTest
import Quickshell
import qs.services
import qs.modules.common
import "COMPANION/services" as Companion
ShellRoot {
 id: root
 property var mind: Companion.AquaMind
 Component.onCompleted: Quickshell.watchFiles = false
 Loader { id: service; source: "SERVICE" }
 FloatingWindow { visible: true; implicitWidth: 320; implicitHeight: 200 }
 TestCase {
  id: test; when: false; optional: true
  function check(pass, name, actual) { console.info("STARTUP_CHECK", JSON.stringify({name:name,status:pass?"PASS":"FAIL",actual:actual??null})); }
  function settle(n) { tryVerify(()=>!n.scanBusy&&!n.docBusy&&n._docQueue.length===0,6000); wait(250); }
  function run() { try {
   tryCompare(Config,"ready",true,6000); tryCompare(Persistent,"ready",true,6000); tryCompare(service,"status",Loader.Ready,6000);
   const n=service.item, ci=Persistent.states.aquaCheckIn, expected=EXPECTED;
   n.open(); tryCompare(n,"vaultLoaded",true,6000); settle(n);
   const local=Qt.formatDate(new Date(),"yyyy-MM-dd");
   check(local==="TODAY"&&root.mind.today()===local,"native-local-date",{local:local,utc:new Date().toISOString().slice(0,10)});
   check(ci.date===local&&ci.mood===expected.mood&&ci.energy===expected.energy,"startup-field-presence-authority",{date:ci.date,mood:ci.mood,energy:ci.energy,journal:n.todayJournalInfo});
   n.refreshVault(); settle(n);
   check(ci.mood===expected.mood&&ci.energy===expected.energy,"repeated-scan-stable",{mood:ci.mood,energy:ci.energy});
   n.openFile("RELPATH",true); settle(n);
   check(ci.mood===expected.mood&&ci.energy===expected.energy,"open-preserves-absent-and-explicit-fields",{mood:ci.mood,energy:ci.energy});
   check(!root.mind.liveModelAutoDetectAllowed&&!root.mind.busy,"no-provider-work");
   console.info("STARTUP_DONE"); Qt.quit();
  } catch(e) { console.error("STARTUP_ABORT",e.message,e.stack); Qt.exit(1); } }
 }
 Timer { interval: 500; running: true; onTriggered: test.run() }
}
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--host', required=True, type=Path)
    parser.add_argument('--plugin', required=True, type=Path)
    parser.add_argument('--companion', required=True, type=Path)
    parser.add_argument('--evidence-dir', required=True, type=Path)
    parser.add_argument('--timezone', default='America/Los_Angeles')
    args = parser.parse_args()
    host, plugin, companion, out = (p.resolve() for p in (args.host, args.plugin, args.companion, args.evidence_dir))
    out.mkdir(parents=True, exist_ok=True)
    sys.path.insert(0, str(host / 'scripts'))
    from native_test_session import private_wayland, run_qs
    today = datetime.datetime.now(ZoneInfo(args.timezone)).date()
    yesterday = today - datetime.timedelta(days=1)
    cases = [
        ('explicit-both-cleared', 'Mood: ""\r\nenergy: ""\r\n', today, 'good', 'high', '', '', True),
        ('explicit-energy-cleared', 'mood: great\r\nenergy: ""\r\n', today, 'good', 'high', 'great', '', True),
        ('explicit-mood-cleared', 'mood: ""\r\nenergy: peak\r\n', today, 'good', 'high', '', 'peak', True),
        ('absent-mood-preserved', 'energy: peak\r\n', today, 'good', 'high', 'good', 'peak', True),
        ('absent-energy-preserved', 'mood: great\r\n', today, 'good', 'high', 'great', 'high', True),
        ('previous-day-field-not-promoted', 'mood: great\r\n', yesterday, 'bad', 'low', 'great', '', True),
        ('absent-fields-discover-current-companion', '', today, 'good', 'high', 'good', 'high', False),
        ('existing-nonblank-journal-authority', 'mood: great\r\nenergy: peak\r\n', yesterday, 'bad', 'low', 'great', 'peak', True),
    ]
    results = []
    with tempfile.TemporaryDirectory(prefix='alis-checkin-startup-') as name:
        base = Path(name)
        with private_wayland(base) as environment:
            if not environment:
                raise SystemExit('SKIP private compositor unavailable')
            for case, fields, ci_date, mood, energy, expected_mood, expected_energy, no_write in cases:
                private = base / case
                private.mkdir()
                shell = private / 'shell'
                shell.mkdir()
                for entry in ('services', 'modules', 'GlobalStates.qml', 'qmldir', 'scripts', 'defaults', 'translations', 'assets'):
                    (shell / entry).symlink_to(host / entry)
                vault = private / 'Vault'
                journal = vault / 'Journal'
                journal.mkdir(parents=True)
                rel = 'Journal/' + today.strftime('%d-%m-%Y') + '-fixture.md'
                raw = ('---\r\njournal: Daily Notes\r\n' + fields + '# Owner comment\r\ncustom: retained\r\n---\r\n\r\n## Daily Log\r\nFixture legacy bytes, tiếng Việt.').encode()
                (vault / rel).write_bytes(raw)
                sentinel = vault / 'Unrelated.md'
                sentinel.write_bytes(b'# Unrelated\r\nKeep exact bytes')
                options = json.loads((host / 'defaults/config.json').read_text())
                options['todo']['nexus'].update(vaultPath=str(vault), dailyNote={'folder':'Journal','format':'DD-MM-YYYY-fixture'})
                options['bar']['weather']['enable'] = False
                options['integrations']['alisIntergration']['nexus'] = False
                options['abyss']['companion']['enabled'] = False
                options['abyss']['companionMind'].update(talkEnabled=True, proactive='off', memoryEnabled=False)
                for path in ('config/alis', 'config/quickshell/alis'):
                    dest = private / path
                    dest.mkdir(parents=True)
                    (dest / 'config.json').write_text(json.dumps(options))
                state = private / 'state/quickshell'
                state.mkdir(parents=True)
                (state / 'states.json').write_text(json.dumps({'aquaCheckIn':{'date':ci_date.isoformat(),'mood':mood,'energy':energy}}))
                qml = QML.replace('COMPANION', companion.as_uri()).replace('SERVICE', (plugin / 'services/NexusService.qml').as_uri()).replace('EXPECTED', json.dumps({'mood':expected_mood,'energy':expected_energy})).replace('TODAY', today.isoformat()).replace('RELPATH', rel)
                (shell / 'shell.qml').write_text(qml)
                home = private / 'home'
                home.mkdir()
                env = dict(environment, HOME=str(home), TZ=args.timezone, QT_QUICK_BACKEND='software', ALIS_NEXUS_HEADLESS_SERVICE_ONLY='1', ALIS_NEXUS_DISABLE_XDG_OPEN='1', AQUA_TEST_ENDPOINT='disabled-offline-fixture')
                for kind in ('config', 'state', 'cache', 'data'):
                    env['XDG_' + kind.upper() + '_HOME'] = str(private / kind)
                result = run_qs(shell, env, timeout=35)
                (out / (case + '.log')).write_text(result.stdout)
                checks = [json.loads(v) for v in re.findall(r'STARTUP_CHECK (\{[^\n]+\})', result.stdout)]
                after = (vault / rel).read_bytes()
                checks.append({'name':'journal-startup-byte-preservation','status':'PASS' if not no_write or after==raw else 'FAIL','actual':{'before':hashlib.sha256(raw).hexdigest(),'after':hashlib.sha256(after).hexdigest(),'noWriteExpected':no_write}})
                checks.append({'name':'unrelated-note-bytes-preserved','status':'PASS' if sentinel.read_bytes()==b'# Unrelated\r\nKeep exact bytes' else 'FAIL'})
                (out / (case + '-before.md')).write_bytes(raw)
                (out / (case + '-after.md')).write_bytes(after)
                results.append({'case':case,'exit':result.returncode,'complete':'STARTUP_DONE' in result.stdout,'checks':checks})
                if result.returncode or not results[-1]['complete']:
                    break
    receipt = {'host':str(host),'plugin':str(plugin),'companion':str(companion),'timezone':args.timezone,'localDate':today.isoformat(),'results':results,'scope':'Private native Wayland, actual host/service/Companion with isolated pre-existing persisted fixtures; no providers or Owner data writes.'}
    (out / 'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
    failures = [{'case':r['case'],'name':c['name']} for r in results for c in r['checks'] if c['status']=='FAIL']
    print(json.dumps({'complete':len(results)==len(cases) and all(r['complete'] for r in results),'cases':len(results),'checks':sum(len(r['checks']) for r in results),'failures':failures}))
    if len(results)!=len(cases) or any(r['exit'] or not r['complete'] for r in results) or failures:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
