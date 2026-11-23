"""Controlled native process races for Nexus search; no production data writes."""
import hashlib,json,os,re,shutil,sys,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'))
from integration_test_host import resolve_host_root
HOST=Path(os.environ.get('ALIS_RECENT_HOST',str(resolve_host_root(ROOT)))).resolve()
PLUGIN=Path(os.environ.get('ALIS_RECENT_PLUGIN',str(ROOT))).resolve()
OUT=Path(os.environ.get('ALIS_RECENT_EVIDENCE') or tempfile.mkdtemp(prefix='alis-search-stale-evidence-'));OUT.mkdir(parents=True,exist_ok=True)
LABEL=os.environ.get('ALIS_RECENT_LABEL','stale')
sys.path.insert(0,str(HOST/'scripts'))
from native_test_session import private_wayland,run_qs
with tempfile.TemporaryDirectory(prefix='alis-search-stale-') as name:
 p=Path(name);shell=p/'shell';shell.mkdir()
 for entry in ('services','modules','GlobalStates.qml','qmldir','scripts','defaults','translations','assets'):(shell/entry).symlink_to(HOST/entry)
 fixture=p/'plugin';(fixture/'services').mkdir(parents=True);shutil.copy2(PLUGIN/'services/NexusService.qml',fixture/'services/NexusService.qml');(fixture/'assets/bin').mkdir(parents=True)
 real=str(PLUGIN/'assets/bin/alis-nexus');helper=fixture/'assets/bin/alis-nexus'
 helper.write_text('''#!/usr/bin/env python3
import json,os,signal,sys,time
from pathlib import Path
args=sys.argv[1:]
if args and args[0] in ('serve', '--serve'):
 sys.exit(1)
if args[0]=='search' and '--query' in args and args[args.index('--query')+1].startswith('race-'):
 q=args[args.index('--query')+1];signal.signal(signal.SIGTERM,signal.SIG_IGN)
 countfile=Path(__file__).with_name('counter-'+q);count=int(countfile.read_text())+1 if countfile.exists() else 1;countfile.write_text(str(count))
 time.sleep(.20)
 print(json.dumps({'ok':True,'query':q,'results':[{'relPath':q+'-'+str(count)+'.md','title':q,'line':1,'snippet':q}]}),flush=True)
 sys.exit(1 if q=='race-failure' else 0)
os.execv(REAL,[REAL,*args])
'''.replace('REAL',repr(real)));helper.chmod(0o755)
 vault=p/'Vault';vault.mkdir();(vault/'Legacy note tiếng Việt.md').write_text('---\r\ntitle: Legacy note tiếng Việt\r\ncustom: retained\r\n---\r\nneedle\r\n')
 (vault/'New note 星河.md').write_text('# New note\nneedle\n')
 other=p/'OtherVault';other.mkdir();(other/'Different vault note.md').write_text('# Different vault\nneedle\n')
 before={f.name:hashlib.sha256(f.read_bytes()).hexdigest() for f in vault.iterdir()}
 options=json.loads((HOST/'defaults/config.json').read_text());options['todo']['nexus']['vaultPath']=str(vault);options['bar']['weather']['enable']=False
 for cfg in (p/'config/alis',p/'config/quickshell/alis'):cfg.mkdir(parents=True);(cfg/'config.json').write_text(json.dumps(options))
 qml=r'''import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import qs.modules.common
ShellRoot {
 Component.onCompleted: Quickshell.watchFiles=false
 Loader {id:service;source:SERVICE}
 Process {id:fixtureControl}
 TestCase {
  id:tc;when:false;optional:true
  property var seen:[]
  function check(name,pass,actual){console.info('STALE_CHECK',JSON.stringify({name:name,status:pass?'PASS':'FAIL',actual:actual}))}
  function paths(n){return n.searchResults.map(x=>String(x.relPath))}
  function control(args){fixtureControl.command=args;fixtureControl.running=true;tryCompare(fixtureControl,"running",false,1500);wait(20)}
  function run(){try{
   tryCompare(Config,'ready',true,5000);tryCompare(service,'status',Loader.Ready,5000);const n=service.item;
   n.searchVault('needle');tryVerify(()=>n.searchResults.length===2,5000);check('native-old-and-new-notes-search',n.searchResults.length===2,paths(n));
   n.searchVault('race-clear');wait(70);n.searchVault('');wait(380);check('clear-rejects-late-success',n.searchQuery===''&&n.searchResults.length===0,{query:n.searchQuery,paths:paths(n)});
   seen=[];n.searchResultsChanged.connect(function(){seen.push({query:n.searchQuery,paths:paths(n)})});
   n.searchVault('race-old');wait(70);n.searchVault('needle');wait(450);check('latest-query-wins',n.searchQuery==='needle'&&n.searchResults.length===2&&!paths(n).some(x=>x.startsWith('race-')),{query:n.searchQuery,paths:paths(n)});
   check('old-result-never-published-under-new-query',!seen.some(x=>x.query==='needle'&&x.paths.some(p=>p.startsWith('race-old'))),seen);
   n.searchVault('');wait(30);n.searchVault('race-same');wait(70);n.searchVault('race-same');wait(550);check('repeated-query-generation-wins',n.searchResults.length===1&&paths(n)[0]==='race-same-2.md',paths(n));
   n.searchVault('');wait(30);n.searchVault('race-failure');wait(350);check('nonzero-exit-cannot-publish-success-payload',n.searchResults.length===0,paths(n));
   n.searchVault('needle');tryVerify(()=>n.searchResults.length===2,5000);check('failure-retry-native-search',n.searchResults.length===2,paths(n));
   n.searchVault('race-clear');wait(70);n.searchVault('   ');wait(350);check('whitespace-clear-rejects-late-success',n.searchQuery==='   '&&n.searchResults.length===0,{query:n.searchQuery,paths:paths(n)});
   n.searchVault('needle');tryVerify(()=>n.searchResults.length===2,5000);check('clear-retry-native-search',n.searchResults.length===2,paths(n));
   n.searchVault('');wait(30);n.searchVault('race-vault');wait(70);Config.setNestedValue('todo.nexus.vaultPath',OTHER_VAULT);wait(350);check('vault-change-rejects-old-vault-response',n.searchResults.length===0,{vault:n.configuredVaultPath,paths:paths(n)});
   n.searchVault('needle');tryVerify(()=>n.searchResults.length===1,5000);check('next-query-reads-new-vault',paths(n)[0]==='Different vault note.md',{vault:n.configuredVaultPath,paths:paths(n)});
   n.searchVault('');wait(30);control(['chmod','644',HELPER]);n.searchVault('needle');wait(160);control(['chmod','755',HELPER]);n.searchVault('needle');wait(450);check('nonexecutable-helper-restored-retry',n.searchResults.length===1&&paths(n)[0]==='Different vault note.md',paths(n));
   n.searchVault('');wait(30);control(['mv',HELPER,HELPER+'.saved']);n.searchVault('needle');wait(160);control(['mv',HELPER+'.saved',HELPER]);n.searchVault('needle');wait(450);check('missing-helper-restored-retry',n.searchResults.length===1&&paths(n)[0]==='Different vault note.md',paths(n));
   console.info('STALE_DONE');Qt.quit();
  }catch(e){console.error('STALE_ABORT',e.message,e.stack);Qt.exit(1)}}
 }
 Timer{interval:300;running:true;onTriggered:tc.run()}
}'''.replace('SERVICE',json.dumps(str(fixture/'services/NexusService.qml'))).replace('OTHER_VAULT',json.dumps(str(other))).replace('HELPER',json.dumps(str(helper)))
 (shell/'shell.qml').write_text(qml)
 runtime=p/'runtime';runtime.mkdir(mode=0o700)
 env=dict(os.environ,QT_QPA_PLATFORM='wayland',QT_QUICK_BACKEND='software',XDG_RUNTIME_DIR=str(runtime),ALIS_NEXUS_DISABLE_XDG_OPEN='1',ALIS_NEXUS_HEADLESS_SERVICE_ONLY='1')
 for kind in ('config','state','cache','data'):env['XDG_'+kind.upper()+'_HOME']=str(p/kind)
 env.pop('NIRI_SOCKET',None);env.pop('HYPRLAND_INSTANCE_SIGNATURE',None)
 with private_wayland(p) as native:
  if native is None:raise SystemExit('SKIP private compositor unavailable')
  env.update({k:v for k,v in native.items() if k in ('WAYLAND_DISPLAY','NIRI_SOCKET','DISPLAY','XDG_RUNTIME_DIR')});result=run_qs(shell,env,timeout=15)
 after={f.name:hashlib.sha256(f.read_bytes()).hexdigest() for f in vault.iterdir()}
 checks=[json.loads(x) for x in re.findall(r'STALE_CHECK (\{[^\n]+\})',result.stdout)];checks.append({'name':'legacy-and-new-note-bytes-preserved','status':'PASS' if before==after else 'FAIL','actual':{'before':before,'after':after}})
 receipt={'host':str(HOST),'plugin':str(PLUGIN),'serviceSha256':hashlib.sha256((PLUGIN/'services/NexusService.qml').read_bytes()).hexdigest(),'scope':'Actual host and exact Service bytes; native controlled delayed helper for race-* queries, real installed native helper for needle queries, temporary vault with legacy CRLF and new Unicode notes.','exit':result.returncode,'complete':'STALE_DONE' in result.stdout,'checks':checks}
 (OUT/(LABEL+'.log')).write_text(result.stdout);(OUT/(LABEL+'.json')).write_text(json.dumps(receipt,indent=2)+'\n');print(json.dumps(receipt,indent=2))
 if result.returncode or not receipt['complete'] or any(c['status']!='PASS' for c in checks):raise SystemExit(1)
