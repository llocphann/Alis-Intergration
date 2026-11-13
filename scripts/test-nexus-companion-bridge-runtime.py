#!/usr/bin/env python3
"""Actual installed Companion caller and Integration gateway in a private native host."""
from pathlib import Path
import datetime,hashlib,json,os,re,shutil,sys,tempfile
from zoneinfo import ZoneInfo
HOST=Path(os.environ.get('ALIS_BRIDGE_HOST','/home/llocphann/.config/quickshell/alis'))
PLUGIN=Path(os.environ.get('ALIS_BRIDGE_PLUGIN','/home/llocphann/.local/share/alis-intergration/current')).resolve()
COMPANION=Path(os.environ.get('ALIS_BRIDGE_COMPANION','/home/llocphann/.local/share/alis-companion/current')).resolve()
OUT=Path(os.environ.get('ALIS_BRIDGE_EVIDENCE','/tmp/alis-journal-bridge-evidence'));OUT.mkdir(parents=True,exist_ok=True)
sys.path.insert(0,str(HOST/'scripts'))
from native_test_session import private_wayland,run_qs
TZ=os.environ.get('ALIS_BRIDGE_TZ','Asia/Ho_Chi_Minh')
QML=r'''import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import "COMPANION/services" as Companion
ShellRoot {
 id:root
 property var mind:Companion.AquaMind
 property int permissionExit:-1
 Component.onCompleted:Quickshell.watchFiles=false
 FloatingWindow{visible:true;implicitWidth:320;implicitHeight:220}
 Process{id:permission;onExited:(code,status)=>root.permissionExit=code}
 TestCase{
 id:tc;when:false;optional:true
 function check(value,name,actual){console.info("BRIDGE_CHECK",JSON.stringify({name:name,status:value?"PASS":"FAIL",actual:actual??null}));if(!value)throw Error(name)}
 function settled(n){tryVerify(()=>!n.docBusy&&!n.scanBusy&&n._docQueue.length===0,6000);wait(140)}
 function mode(value){root.permissionExit=-1;permission.command=["chmod",value,"JOURNALDIR"];permission.running=true;tryVerify(()=>root.permissionExit!==-1,2000);check(root.permissionExit===0,"fault-directory-mode-"+value)}
 function choice(n,field,value){Companion.AquaMind.checkInDate=Companion.AquaMind.today();Companion.AquaMind.checkInStage="";Companion.AquaMind.choiceSaved(field,value);settled(n)}
 function run(){try{
  tryCompare(Config,"ready",true,6000);tryCompare(Persistent,"ready",true,6000);tryVerify(()=>!!AlisIntergration.nexus,8000);
  const n=AlisIntergration.nexus,m=Companion.AquaMind,ci=Persistent.states.aquaCheckIn;
  check(!m.liveModelAutoDetectAllowed&&!m.busy&&m.pending===null,"provider-and-autodetect-off");
  n.open();tryCompare(n,"vaultLoaded",true,6000);settled(n);
  const today=Qt.formatDate(new Date(),"yyyy-MM-dd");check(today==="TODAY"&&m.today()===today,"local-date-consistency",{nexus:today,companion:m.today(),utc:new Date().toISOString().slice(0,10)});
  check(n.todayJournalInfo.relPath==="RELPATH","existing-legacy-journal-selected",n.todayJournalInfo);
  if("PHASE"==="reload"){
   check(m.userMood==="good"&&m.userEnergy==="peak","restart-state-readback",{mood:m.userMood,energy:m.userEnergy});
   check(n.todayJournalInfo.mood==="good"&&n.todayJournalInfo.energy==="peak","restart-journal-readback",n.todayJournalInfo);
   n.refreshVault();settled(n);check(ci.mood==="good"&&ci.energy==="peak","repeated-scan-no-overwrite");
   choice(n,"mood","");choice(n,"energy","");wait(450);
   console.info("BRIDGE_DONE");Qt.quit();return;
  }
  if("PHASE"==="reload-cleared"){
   check(m.userMood===""&&m.userEnergy===""&&n.todayJournalInfo.mood===""&&n.todayJournalInfo.energy==="","restart-explicit-clears-retained",n.todayJournalInfo);
   n.refreshVault();settled(n);check(m.userMood===""&&m.userEnergy==="","repeated-empty-readback-does-not-restore-stale-values");
   console.info("BRIDGE_DONE");Qt.quit();return;
  }
  check(m.userMood==="great"&&m.userEnergy==="high","journal-to-actual-companion-readback",{mood:m.userMood,energy:m.userEnergy});
  check(m.setChatCheckInChoice("mood","good"),"actual-chat-mood-caller-accepted");settled(n);
  check(n.todayJournalInfo.mood==="good"&&n.todayJournalInfo.energy==="high","actual-caller-partial-mood-roundtrip",n.todayJournalInfo);
  choice(n,"mood","");check(n.todayJournalInfo.mood===""&&n.todayJournalInfo.energy==="high"&&m.userMood==="","caller-explicit-mood-clear");
  choice(n,"energy","");check(n.todayJournalInfo.mood===""&&n.todayJournalInfo.energy===""&&m.userEnergy==="","caller-explicit-energy-clear");
  check(n.syncCompanionCheckIn(today,undefined,undefined)===false,"omitted-both-enqueues-nothing");
  choice(n,"mood","good");choice(n,"energy","high");
  n.openFile("RELPATH",true);settled(n);
  check(n.setFrontmatter("RELPATH",{mood:"great"}),"journal-edit-enqueued");settled(n);
  check(m.userMood==="great"&&m.userEnergy==="high","journal-edit-roundtrip-to-companion");
  n.setFrontmatter("RELPATH",{mood:""});settled(n);check(m.userMood===""&&m.userEnergy==="high","journal-explicit-clear-preserves-omitted-energy");
  n.setFrontmatter("RELPATH",{mood:"good"});settled(n);
  const oldPath="OLDPATH";n.openFile(oldPath,true);settled(n);n.setFrontmatter(oldPath,{mood:"bad",energy:"low"});settled(n);
  check(m.userMood==="good"&&m.userEnergy==="high","old-date-edit-does-not-overwrite-today");
  n.openFile("RELPATH",true);settled(n);mode("0555");
  n.setFrontmatter("RELPATH",{mood:"bad"});check(m.userMood==="good","failed-write-does-not-publish-before-commit",{mood:m.userMood});settled(n);
  check(m.userMood==="good"&&n.todayJournalInfo.mood==="good","failed-journal-write-does-not-publish-unsaved-choice",{companion:m.userMood,journal:n.todayJournalInfo.mood,error:n.errorMessage});
  mode("0755");n.setFrontmatter("RELPATH",{mood:"great"});settled(n);
  check(m.userMood==="great"&&n.todayJournalInfo.mood==="great","journal-write-retry-publishes-on-success");
  mode("0555");choice(n,"mood","");check(n.todayJournalInfo.mood==="great","failed-companion-clear-keeps-authoritative-readback");
  mode("0755");choice(n,"mood","");check(n.todayJournalInfo.mood===""&&m.userMood==="","same-companion-clear-retries-after-failure");
  choice(n,"mood","good");choice(n,"energy","peak");n.refreshVault();settled(n);
  check(n.todayJournalInfo.mood==="good"&&n.todayJournalInfo.energy==="peak","fresh-scan-reloads-mixed-fields");
  check(n.syncCompanionCheckIn(today,"good","peak")===false,"successful-repeat-idempotent");
  wait(450);console.info("BRIDGE_DONE");Qt.quit();
 }catch(error){console.error("BRIDGE_ABORT",error.message,error.stack);permission.command=["chmod","0755","JOURNALDIR"];permission.running=true;wait(150);Qt.exit(1)}}
 }
 Timer{interval:600;running:true;onTriggered:tc.run()}
}'''
with tempfile.TemporaryDirectory(prefix='alis-full-checkin-') as name:
 p=Path(name);home=p/'home';home.mkdir();shell=p/'shell';shell.mkdir()
 for entry in ('services','modules','GlobalStates.qml','qmldir','scripts','defaults','translations','assets'):(shell/entry).symlink_to(HOST/entry)
 package=p/'data/alis-intergration/releases'/PLUGIN.name;package.parent.mkdir(parents=True);shutil.copytree(PLUGIN,package)
 (package.parents[1]/'current').symlink_to(Path('releases')/PLUGIN.name)
 vault=p/'Vault';journals=vault/'Journal';journals.mkdir(parents=True);(vault/'20_Notes').mkdir()
 today=datetime.datetime.now(ZoneInfo(TZ)).date();old=today-datetime.timedelta(days=1)
 rel='Journal/'+today.strftime('%d-%m-%Y')+'-fixture.md';oldrel='Journal/'+old.strftime('%d-%m-%Y')+'-fixture.md'
 raw=b'---\r\njournal: Daily Notes\r\nMood: great\r\nenergy: high\r\ncreated: 2020-01-02T03:04:05\r\ncustom: preserve owner field\r\n---\r\n\r\n## Daily Log\r\nPrivate legacy fixture only.\r\n```dataviewjs\r\nkeep()\r\n```'
 (vault/rel).write_bytes(raw);(vault/oldrel).write_bytes(raw);sentinel=vault/'20_Notes/Owner.md';sentinel.write_bytes(b'# Preserve unrelated\r\nCustom owner bytes \xf0\x9f\x8e\xb5\r\n')
 original_sentinel=sentinel.read_bytes()
 options=json.loads((HOST/'defaults/config.json').read_text());options['todo']['nexus']['vaultPath']=str(vault);options['todo']['nexus']['dailyNote']={'folder':'Journal','format':'DD-MM-YYYY-fixture'}
 options['bar']['weather']['enable']=False;options['integrations']['alisIntergration'].update(nexus=True,tlp=False,thinkfan=False,spaced_repetition=False)
 options['abyss']['companion']['enabled']=False;options['abyss']['companionMind'].update(talkEnabled=True,proactive='off',memoryEnabled=False)
 for directory in [p/'config/alis',p/'config/quickshell/alis']:
  directory.mkdir(parents=True);(directory/'config.json').write_text(json.dumps(options))
 state=p/'state/quickshell';state.mkdir(parents=True);(state/'states.json').write_text(json.dumps({'aquaCheckIn':{'date':today.isoformat(),'mood':'','energy':''}}))
 results=[]
 with private_wayland(p) as env:
  if env is None:raise SystemExit('SKIP: private native compositor unavailable')
  env=dict(env,HOME=str(home),TZ=TZ,QT_QUICK_BACKEND='software',ALIS_NEXUS_DISABLE_XDG_OPEN='1',ALIS_NEXUS_HEADLESS_SERVICE_ONLY='1',AQUA_TEST_ENDPOINT='disabled-offline-fixture')
  for kind in ('config','state','cache','data'):env['XDG_'+kind.upper()+'_HOME']=str(p/kind)
  for phase in ('roundtrip','reload','reload-cleared'):
   qml=QML.replace('COMPANION',COMPANION.as_uri()).replace('JOURNALDIR',str(journals)).replace('TODAY',today.isoformat()).replace('RELPATH',rel).replace('OLDPATH',oldrel).replace('PHASE',phase)
   (shell/'shell.qml').write_text(qml)
   try:result=run_qs(shell,env,timeout=55)
   finally:journals.chmod(0o755)
   checks=[json.loads(x) for x in re.findall(r'BRIDGE_CHECK (\{[^\n]+\})',result.stdout)]
   (OUT/(phase+'.log')).write_text(result.stdout)
   results.append({'phase':phase,'exit':result.returncode,'complete':'BRIDGE_DONE' in result.stdout,'checks':checks})
   if result.returncode or not results[-1]['complete'] or any(c['status']=='FAIL' for c in checks):break
 actual=(vault/rel).read_bytes()
 (OUT/"legacy-before.md").write_bytes(raw);(OUT/"legacy-after.md").write_bytes(actual);(OUT/"old-after.md").write_bytes((vault/oldrel).read_bytes())
 def unrelated(data):return re.sub(rb'(?im)^(mood|energy):[^\r\n]*\r?\n',b'',data)
 preservation=unrelated(actual)==unrelated(raw) and unrelated((vault/oldrel).read_bytes())==unrelated(raw) and sentinel.read_bytes()==original_sentinel
 receipt={'scope':'Actual installed AquaMind singleton caller and host AlisIntergration gateway loading an exact private copy of the installed Integration payload; isolated native compositor/HOME/XDG/vault, no providers or Owner writes. Directory permission fault only in temporary vault.','host':str(HOST),'integration':str(PLUGIN),'companion':str(COMPANION),'timezone':TZ,'actualLocalDate':today.isoformat(),'results':results,'unrelatedJournalAndSentinelBytesPreserved':preservation,'runtimeTouched':False}
 (OUT/'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n');print(json.dumps(receipt,indent=2))
 for result in results:
  for line in (OUT/(result['phase']+'.log')).read_text().splitlines():
   if 'BRIDGE_ABORT' in line:print(line)
 if len(results)!=3 or any(r['exit'] or not r['complete'] or any(c['status']=='FAIL' for c in r['checks']) for r in results) or not preservation:raise SystemExit(1)
