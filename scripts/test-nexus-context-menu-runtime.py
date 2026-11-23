"""Native context-menu CRUD audit using private vault and transport spies only."""
import hashlib,json,os,re,sys,tempfile
from contextlib import nullcontext
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'))
from integration_test_host import resolve_host_root
HOST=Path(os.environ.get('ALIS_MENU_HOST',str(resolve_host_root(ROOT)))).resolve()
PLUGIN=Path(os.environ.get('ALIS_MENU_PLUGIN',str(ROOT))).resolve()
OUT=Path(os.environ.get('ALIS_MENU_EVIDENCE') or tempfile.mkdtemp(prefix='alis-menu-evidence-'));OUT.mkdir(parents=True,exist_ok=True)
LABEL=os.environ.get('ALIS_MENU_LABEL','native')
sys.path.insert(0,str(HOST/'scripts'))
from native_test_session import private_wayland,run_qs
with tempfile.TemporaryDirectory(prefix='alis-menu-') as name:
 p=Path(name);shell=p/'shell';shell.mkdir()
 for entry in ('services','modules','GlobalStates.qml','qmldir','scripts','defaults','translations','assets'):(shell/entry).symlink_to(HOST/entry)
 vault=p/'Vault';vault.mkdir();folder='Legacy Folder tiếng Việt';(vault/folder).mkdir()
 legacy='---\r\ntitle: Legacy Unicode 星河\r\ncustom: "retained # bytes"\r\n---\r\n# Old note\r\nOwner-authored body.\r\n'
 seed={folder+'/Legacy "quote" $note.md':legacy,folder+'/Existing.md':'# Collision target\nDO NOT OVERWRITE\n',folder+'/Untitled.md':'# Existing Untitled\nKEEP\n',folder+'/Child.md':'# Nested child\nKEEP CHILD\n','Failure.md':'# Failed trash\nKEEP\n'}
 for path,content in seed.items():(vault/path).write_bytes(content.encode())
 transport=p/'transport.jsonl';binpath=p/'bin';binpath.mkdir()
 for command in ('wl-copy','xdg-open'):
  spy=binpath/command;spy.write_text('#!/usr/bin/env python3\nimport json,sys\nwith open('+repr(str(transport))+',"a") as f:f.write(json.dumps({"command":'+repr(command)+',"args":sys.argv[1:]},ensure_ascii=False)+"\\n")\n');spy.chmod(0o755)
 inspector=p/'inspect.py';inspector.write_text('''import sys,json,hashlib
from pathlib import Path
v=Path(sys.argv[1]);mode=sys.argv[2];a=json.loads(sys.argv[3])
if mode=='write':q=v/a['path'];q.parent.mkdir(parents=True,exist_ok=True);q.write_bytes(a['content'].encode())
if mode=='remove':(v/a['path']).unlink()
print(json.dumps({'files':{str(q.relative_to(v)):{'sha':hashlib.sha256(q.read_bytes()).hexdigest(),'text':q.read_bytes().decode(errors='replace')} for q in v.rglob('*') if q.is_file()},'dirs':[str(q.relative_to(v)) for q in v.rglob('*') if q.is_dir()]},ensure_ascii=False))
''')
 options=json.loads((HOST/'defaults/config.json').read_text());options['todo']['nexus']['vaultPath']=str(vault);options['bar']['weather']['enable']=False
 for cfg in (p/'config/alis',p/'config/quickshell/alis'):cfg.mkdir(parents=True);(cfg/'config.json').write_text(json.dumps(options))
 qml=r'''import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
ShellRoot {
 Component.onCompleted:Quickshell.watchFiles=false
 FloatingWindow{id:win;visible:true;implicitWidth:1280;implicitHeight:820
  Loader{id:service;source:SERVICE}
  Loader{id:workspace;anchors.fill:parent;source:WORKSPACE;onLoaded:item.nexus=service.item}
 }
 Process{id:inspect;stdout:StdioCollector{}}
 TestCase{id:tc;when:false;optional:true
  property var initial:null
  function check(name,pass,actual){console.info('MENU_CHECK',JSON.stringify({name:name,status:pass?'PASS':'FAIL',actual:actual}))}
  function require(v,s){if(!v)throw new Error(s)}
  function fs(mode,args){inspect.command=['python3',INSPECTOR,VAULT,mode||'state',JSON.stringify(args||{})];inspect.running=true;tryCompare(inspect,'running',false,2000);return JSON.parse(inspect.stdout.text)}
  function settle(){tryVerify(()=>!service.item.docBusy&&!service.item.scanBusy,5000);wait(90)}
  function nodes(item,pred,out){out=out||[];if(item&&item.visible){if(pred(item))out.push(item);for(const c of(item.children||[]))nodes(c,pred,out)}return out}
  function label(item,text){return nodes(item,c=>c.text!==undefined&&String(c.text)===text)[0]||null}
  function clickLabel(item,text){const t=label(item,text);require(t,'visible action '+text);mouseClick(t.parent,t.parent.width/2,t.parent.height/2,Qt.LeftButton);wait(60)}
  function menu(type,path,title){workspace.item.openContextMenu(workspace.item.width-2,workspace.item.height-2,{type:type,relPath:path,title:title||path,isDir:type==='folder'});wait(60)}
  function clickAction(text){clickLabel(findChild(workspace.item,'nexusContextMenuPopup'),text)}
  function renameInput(){return nodes(findChild(workspace.item,'nexusRenameDialog'),c=>String(c).startsWith('QQuickTextInput'))[0]}
  function rename(path,newName,isDir){menu(isDir?'folder':'file',path);clickAction(isDir?'Rename Folder...':'Rename Note...');const input=renameInput();require(input,'rename text input');input.text=newName;input.forceActiveFocus();keyClick(Qt.Key_Return);settle()}
  function snap(name){let done=false;workspace.item.grabToImage(result=>{result.saveToFile(OUT+'/'+LABEL+'-'+name+'.png');done=true},Qt.size(workspace.item.width,workspace.item.height));tryVerify(()=>done,2000)}
  function run(){try{
   tryCompare(Config,'ready',true,6000);tryCompare(service,'status',Loader.Ready,6000);tryCompare(workspace,'status',Loader.Ready,6000);require(Config.options.bar.weather.enable===false,'private weather disabled');const n=service.item;const ws=workspace.item;ws.nexus=n;n.open();tryCompare(n,'vaultLoaded',true,6000);settle();initial=fs();
   const original=ORIGINAL;
   menu('file',original);ws.forceActiveFocus();keyClick(Qt.Key_Escape);wait(60);check('native-menu-escape-keeps-workspace-open',!ws.contextMenuOpen&&n.isOpen,{menu:ws.contextMenuOpen,workspaceOpen:n.isOpen});ws.closeContextMenu();n.open();settle();
   for(const size of[{w:750,h:500},{w:1280,h:820}]){win.implicitWidth=size.w;win.implicitHeight=size.h;wait(120);for(const type of['file','folder','base-card','tag','workspace']){menu(type,type==='folder'?FOLDER:original);const popup=findChild(ws,'nexusContextMenuPopup');const texts=nodes(popup,c=>c.text!==undefined&&c.font!==undefined&&String(c.text).length>0);check('bottom-right-fit-'+type+'-'+size.w,popup.x>=0&&popup.y>=0&&popup.x+popup.width<=ws.width&&popup.y+popup.height<=ws.height&&texts.every(t=>{const p=t.mapToItem(popup,0,0);return t.width>0&&p.x>=0&&p.x+t.width<=popup.width+1}),{x:popup.x,y:popup.y,w:popup.width,h:popup.height,workspace:[ws.width,ws.height]});ws.closeContextMenu()}}
   menu('file',original);clickAction('Open Note');settle();check('native-file-open',n.currentPath===original,n.currentPath);
   menu('file',original,'Legacy "quote" $note');clickAction('Copy Wikilink');check('clipboard-wikilink',Quickshell.clipboardText==='[[Legacy "quote" $note]]',Quickshell.clipboardText);menu('file',original);clickAction('Copy Relative Path');check('clipboard-relpath',Quickshell.clipboardText===original,Quickshell.clipboardText);menu('file',original);clickAction('Reveal in File Manager');
   menu('folder',FOLDER);clickAction('Copy Path');check('clipboard-folder-path',Quickshell.clipboardText===FOLDER,Quickshell.clipboardText);menu('folder',FOLDER);clickAction('Reveal in File Manager');
   menu('file',original);clickAction('Rename Note...');const ri=renameInput();ri.text='UNSAVED-CANCEL';clickLabel(findChild(ws,'nexusRenameDialog'),'Cancel');check('native-rename-cancel-preserves',!ws.renameDialogOpen&&fs().files[original].sha===initial.files[original].sha,n.currentPath);
   rename(original,'Existing',false);check('rename-collision-preserves-current-path',n.currentPath===original&&String(n.currentDoc?.relPath)===original,{path:n.currentPath,doc:n.currentDoc?.relPath,error:n.errorMessage});check('rename-collision-preserves-both-bytes',fs().files[original].sha===initial.files[original].sha&&fs().files[FOLDER+'/Existing.md'].sha===initial.files[FOLDER+'/Existing.md'].sha,fs());
   n.openFile(original,true);settle();n.draftContent='UNSAVED OWNER DRAFT';n.isDirty=true;rename(original,'Renamed tiếng Việt',false);const renamed=FOLDER+'/Renamed tiếng Việt.md';check('rename-success-keeps-active-draft',n.currentPath===renamed&&n.draftContent==='UNSAVED OWNER DRAFT'&&n.isDirty,{path:n.currentPath,draft:n.draftContent,dirty:n.isDirty});check('rename-success-preserves-legacy-bytes',fs().files[renamed]?.sha===initial.files[original].sha,fs().files[renamed]);
   n.saveCurrentNote();settle();check('renamed-draft-saves-only-new-path',fs().files[renamed].text.includes('UNSAVED OWNER DRAFT')&&!fs().files[original]&&fs().files[FOLDER+'/Existing.md'].sha===initial.files[FOLDER+'/Existing.md'].sha,{path:n.currentPath,text:fs().files[renamed].text});fs('write',{path:renamed,content:initial.files[original].text});n.openFile(renamed,true);settle();
   n.draftContent='QUEUED OWNER DRAFT';n.isDirty=true;menu('file',renamed);clickAction('Rename Note...');const qi=renameInput();qi.text='Queued name';qi.accepted();n.saveCurrentNote();settle();const queuedPath=FOLDER+'/Queued name.md';check('save-queued-during-rename-targets-new-path',!fs().files[renamed]&&fs().files[queuedPath]?.text.includes('QUEUED OWNER DRAFT'),{path:n.currentPath,old:fs().files[renamed],new:fs().files[queuedPath]});if(fs().files[queuedPath])fs('remove',{path:queuedPath});fs('write',{path:renamed,content:initial.files[original].text});
   n.openFile(FOLDER+'/Child.md',true);settle();rename(FOLDER,'Renamed Folder',true);check('folder-rename-retargets-open-descendant',n.currentPath==='Renamed Folder/Child.md'&&String(n.currentDoc?.relPath)==='Renamed Folder/Child.md',{path:n.currentPath,doc:n.currentDoc?.relPath});
   menu('folder','Renamed Folder');clickAction('New Note in Folder');settle();check('native-folder-create-note',Boolean(fs().files['Renamed Folder/Untitled 1.md']),{path:n.currentPath,files:Object.keys(fs().files)});
   menu('folder','Renamed Folder');clickAction('New Subfolder...');settle();check('native-folder-create-subfolder',fs().dirs.includes('Renamed Folder/New Folder'),fs().dirs);
   fs('write',{path:'Renamed Folder/ExistingFolder/keep.md',content:'EXISTING FOLDER CONTENT'});rename('Renamed Folder/New Folder','ExistingFolder',true);check('native-folder-rename-collision-preserves',fs().dirs.includes('Renamed Folder/New Folder')&&fs().files['Renamed Folder/ExistingFolder/keep.md'].text==='EXISTING FOLDER CONTENT',fs().dirs);
   menu('folder','Renamed Folder/New Folder');clickAction('Rename Folder...');const cancelInput=renameInput();cancelInput.text='CANCELLED FOLDER';cancelInput.forceActiveFocus();keyClick(Qt.Key_Escape);wait(60);check('native-folder-rename-escape-cancel',!ws.renameDialogOpen&&fs().dirs.includes('Renamed Folder/New Folder')&&!fs().dirs.includes('Renamed Folder/CANCELLED FOLDER'),fs().dirs);
   fs('write',{path:'.trash/New Folder/occupied.md',content:'PREPOPULATED TRASH DIRECTORY'});fs('write',{path:'Renamed Folder/New Folder/child.md',content:'FIRST FOLDER CONTENT'});menu('folder','Renamed Folder/New Folder');clickAction('Delete Folder (.trash)');settle();check('native-folder-trash-prepopulated-collision',!fs().dirs.includes('Renamed Folder/New Folder')&&Object.values(fs().files).some(v=>v.text==='FIRST FOLDER CONTENT')&&fs().files['.trash/New Folder/occupied.md'].text==='PREPOPULATED TRASH DIRECTORY',fs().dirs);
   fs('write',{path:'Renamed Folder/New Folder/child.md',content:'SECOND FOLDER CONTENT'});n.refreshVault();settle();menu('folder','Renamed Folder/New Folder');clickAction('Delete Folder (.trash)');settle();check('native-folder-repeat-trash-keeps-all-bytes',['FIRST FOLDER CONTENT','SECOND FOLDER CONTENT','PREPOPULATED TRASH DIRECTORY'].every(x=>Object.values(fs().files).some(v=>v.text===x)),fs().dirs);
   menu('workspace','');clickAction('New Note');settle();check('native-workspace-create-note',Boolean(fs().files['Untitled.md']),Object.keys(fs().files));
   fs('write',{path:'LateRescan.md',content:'# Added externally'});menu('workspace','');clickAction('Rescan Vault');wait(180);check('native-workspace-rescan',n.flatFiles.some(x=>x.relPath==='LateRescan.md'),{loaded:n.vaultLoaded,paths:n.flatFiles.map(x=>x.relPath)});ws.closeContextMenu();
   n.createCollectionEntry('movies','Fixture Movie');settle();n.openCollection('movies');wait(150);const base=findChild(ws,'nexusBaseCard_0');require(base,'actual Bases card');mouseClick(base,base.width/2,base.height/2,Qt.RightButton);wait(60);check('native-bases-rightclick-menu',ws.contextMenuOpen&&ws.contextMenuData.type==='base-card',{dataType:ws.contextMenuData?.type});clickAction('Flip to Back');check('native-bases-flip',base.flipped===true,base.flipped);mouseClick(base,base.width/2,base.height/2,Qt.RightButton);wait(60);clickAction('Flip to Front');check('native-bases-flip-back',base.flipped===false,base.flipped);
   mouseClick(base,base.width/2,base.height/2,Qt.RightButton);wait(60);clickAction('Open Note');settle();check('native-bases-open',n.currentPath.includes('Fixture Movie.md'),n.currentPath);
   menu('file','Renamed Folder/Renamed tiếng Việt.md');clickAction('Duplicate Note');settle();const copy=n.currentPath;check('duplicate-native-byte-preservation',copy.includes('(Copy)')&&fs().files[copy]?.sha===initial.files[original].sha,{path:copy});
   menu('file','Renamed Folder/Renamed tiếng Việt.md');clickAction('Move to Trash');settle();const trash1=fs();fs('write',{path:'Renamed Folder/Renamed tiếng Việt.md',content:'SECOND DISTINCT BYTES'});n.refreshVault();settle();menu('file','Renamed Folder/Renamed tiếng Việt.md');clickAction('Move to Trash');settle();const trash2=fs();check('repeat-trash-keeps-distinct-bytes',Object.values(trash2.files).some(v=>v.sha===initial.files[original].sha)&&Object.values(trash2.files).some(v=>v.text==='SECOND DISTINCT BYTES')&&!trash2.files['Renamed Folder/Renamed tiếng Việt.md'],{trash:Object.entries(trash2.files).filter(([k])=>k.startsWith('.trash/'))});
   n.openFile('Failure.md',true);settle();n.draftContent='UNSAVED AFTER EXTERNAL DELETE';n.isDirty=true;fs('remove',{path:'Failure.md'});menu('file','Failure.md');clickAction('Move to Trash');settle();check('failed-trash-keeps-active-draft',n.currentPath==='Failure.md'&&String(n.currentDoc?.relPath)==='Failure.md'&&n.draftContent==='UNSAVED AFTER EXTERNAL DELETE'&&n.isDirty,{path:n.currentPath,doc:n.currentDoc?.relPath,draft:n.draftContent,dirty:n.isDirty,error:n.errorMessage});
   snap('final');console.info('MENU_DONE');Qt.quit();
  }catch(e){console.error('MENU_ABORT',e.message,e.stack);Qt.exit(1)}}
 }
 Timer{interval:300;running:true;onTriggered:tc.run()}
}'''
 for key,value in {'SERVICE':str(PLUGIN/'services/NexusService.qml'),'WORKSPACE':str(PLUGIN/'modules/nexus/NexusWorkspace.qml'),'INSPECTOR':str(inspector),'VAULT':str(vault),'FOLDER':folder,'ORIGINAL':folder+'/Legacy "quote" $note.md','OUT':str(OUT),'LABEL':LABEL}.items():qml=qml.replace(key,json.dumps(value,ensure_ascii=False))
 (shell/'shell.qml').write_text(qml);runtime=p/'runtime';runtime.mkdir(mode=0o700)
 env=dict(os.environ,QT_QPA_PLATFORM='wayland',QT_QUICK_BACKEND='software',XDG_RUNTIME_DIR=str(runtime),PATH=str(binpath)+':'+os.environ['PATH'],ALIS_NEXUS_DISABLE_XDG_OPEN='0',ALIS_NEXUS_HEADLESS_SERVICE_ONLY='1')
 for kind in ('config','state','cache','data'):env['XDG_'+kind.upper()+'_HOME']=str(p/kind)
 env.pop('NIRI_SOCKET',None);env.pop('HYPRLAND_INSTANCE_SIGNATURE',None)
 offscreen=os.environ.get('ALIS_MENU_OFFSCREEN')=='1'
 with (nullcontext(None) if offscreen else private_wayland(p)) as native:
  if native is None and not offscreen:raise SystemExit('SKIP private compositor unavailable')
  if native:env.update({k:v for k,v in native.items() if k in ('WAYLAND_DISPLAY','NIRI_SOCKET','DISPLAY','XDG_RUNTIME_DIR')})
  if offscreen:env['QT_QPA_PLATFORM']='offscreen'
  result=run_qs(shell,env,timeout=50)
 checks=[json.loads(x) for x in re.findall(r'MENU_CHECK (\{[^\n]+\})',result.stdout)];transported=[json.loads(x) for x in transport.read_text().splitlines()] if transport.exists() else []
 expected=[{'command':'xdg-open','args':[str(vault/folder)]},{'command':'xdg-open','args':[str(vault/folder)]}]
 checks.append({'name':'private-clipboard-and-path-argv-preserved','status':'PASS' if transported==expected else 'FAIL','actual':transported})
 receipt={'platform':env['QT_QPA_PLATFORM'],'scope':'Exact Integration payload + actual installed host in private compositor/vault/config; clipboard/xdg transport intercepted by private PATH spies; no real vault/config/clipboard/desktop changes.','plugin':str(PLUGIN),'host':str(HOST),'exit':result.returncode,'complete':'MENU_DONE' in result.stdout,'checks':checks,'workspaceSha256':hashlib.sha256((PLUGIN/'modules/nexus/NexusWorkspace.qml').read_bytes()).hexdigest(),'serviceSha256':hashlib.sha256((PLUGIN/'services/NexusService.qml').read_bytes()).hexdigest()}
 (OUT/(LABEL+'.log')).write_text(result.stdout);(OUT/(LABEL+'.json')).write_text(json.dumps(receipt,indent=2,ensure_ascii=False)+'\n');print(json.dumps(receipt,indent=2,ensure_ascii=False))
 if result.returncode or not receipt['complete'] or any(c['status']!='PASS' for c in checks):raise SystemExit(1)
