"""Native Recent/Search resize regression; all data and Config writes are private fixtures."""
import hashlib, json, os, re, sys, tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HOST = Path(os.environ.get('ALIS_RECENT_HOST', str(Path.home()/'.config/quickshell/alis'))).resolve()
PLUGIN = Path(os.environ.get('ALIS_RECENT_PLUGIN', str(Path.home()/'.local/share/alis-intergration/current'))).resolve()
OUT = Path(os.environ.get('ALIS_RECENT_EVIDENCE') or tempfile.mkdtemp(prefix='alis-recent-evidence-'))
OUT.mkdir(parents=True, exist_ok=True)
LABEL = os.environ.get('ALIS_RECENT_LABEL', 'native')
sys.path.insert(0, str(HOST/'scripts'))
from native_test_session import private_wayland, run_qs

with tempfile.TemporaryDirectory(prefix='alis-recent-search-') as name:
    private=Path(name); shell=private/'shell'; shell.mkdir()
    for entry in ('services','modules','GlobalStates.qml','qmldir','scripts','defaults','translations','assets'):
        (shell/entry).symlink_to(HOST/entry)
    vault=private/'Vault'; vault.mkdir()
    query='từ khóa đặc biệt nghiên cứu 星河'
    folder=vault/'Nghiên cứu tiếng Việt — Tài liệu rất dài cho kiểm tra thanh bên với Unicode 星河'
    folder.mkdir()
    for i in range(4):
        title=f'{i+1} — Nghiên cứu tiếng Việt và 星河 — A deliberately long recent note title to verify text elision'
        (folder/(title+'.md')).write_text(f'---\ntitle: {title}\n---\n# {title}\n{query} needle\nA long search snippet with Unicode tiếng Việt and 星河 that must elide within a narrow sidebar.\n')
    before={str(p.relative_to(vault)):hashlib.sha256(p.read_bytes()).hexdigest() for p in vault.rglob('*') if p.is_file()}
    options=json.loads((HOST/'defaults/config.json').read_text())
    options['todo']['nexus']['vaultPath']=str(vault)
    options['bar']['weather']['enable']=False
    for config in (private/'config/alis',private/'config/quickshell/alis'):
        config.mkdir(parents=True); (config/'config.json').write_text(json.dumps(options))
    qml=r'''import QtQuick
import QtTest
import Quickshell
import qs
import qs.services
import qs.modules.common
ShellRoot {
 Component.onCompleted: Quickshell.watchFiles=false
 FloatingWindow {
  visible:true;implicitWidth:1280;implicitHeight:820
  Loader {id:service;source:SERVICE}
  Loader {id:workspace;anchors.fill:parent;source:WORKSPACE;onLoaded:item.nexus=service.item}
 }
 TestCase {
  id:tc;when:false;optional:true
  function check(name,pass,actual) {console.info("RECENT_CHECK",JSON.stringify({name:name,status:pass?"PASS":"FAIL",actual:actual}))}
  function require(v,s){if(!v)throw new Error(s)}
  function box(item,parent){const p=item.mapToItem(parent||workspace.item,0,0);return {x:p.x,y:p.y,w:item.width,h:item.height,visible:item.visible}}
  function inside(item,parent){const b=box(item,parent);return item.visible&&b.w>0&&b.h>0&&b.x>=-1&&b.y>=-1&&b.x+b.w<=parent.width+1&&b.y+b.h<=parent.height+1}
  function descendants(item,predicate,found){found=found||[];if(item&&item.visible){if(predicate(item))found.push(item);for(const c of(item.children||[]))descendants(c,predicate,found)}return found}
  function label(item,text){return descendants(item,c=>c.text!==undefined&&String(c.text)===text)[0]||null}
  function list(card){return descendants(card,c=>String(c).startsWith('QQuickListView'))[0]||null}
  function settle(){tryVerify(()=>!service.item.docBusy&&!service.item.scanBusy,5000);wait(100)}
  function snap(s){let done=false;workspace.item.grabToImage(result=>{result.saveToFile(OUT+'/'+LABEL+'-'+s+'.png');done=true},Qt.size(workspace.item.width,workspace.item.height));tryVerify(()=>done,2500)}
  function run(){try{
   tryCompare(Config,'ready',true,6000);tryCompare(service,'status',Loader.Ready,6000);tryCompare(workspace,'status',Loader.Ready,6000);
   require(Config.options.bar.weather.enable===false,'fixture Weather must be disabled');
   const n=service.item;const ws=workspace.item;ws.nexus=n;n.open();tryCompare(n,'vaultLoaded',true,6000);settle();require(n.recentNotes.length===4,'native scan must read four fixture notes');
   const card=findChild(ws,'nexusFileTreeCard');const field=findChild(ws,'nexusFileFilterField');
   for(const placement of [{side:'left',width:160},{side:'left',width:360},{side:'right',width:180},{side:'right',width:340}]){
    const right=n.cardSlotIndex('explorer')>=2;
    if(right!==(placement.side==='right'))require(n.swapCards('explorer','calendar'),'move explorer to other sidebar');
    n.leftSidebarWidth=placement.side==='left'?placement.width:160;n.rightSidebarWidth=placement.side==='right'?placement.width:180;wait(160);
    const tag=placement.side+'-'+placement.width;
    check(tag+'-actual-width',Math.abs(card.width-placement.width)<=1,box(card));
    mouseMove(card,card.width/2,card.height/2);wait(180);
    const icons=['folder','sell','schedule','search','note_add','today','refresh','navigate_before','drag_indicator','navigate_next'];
    const actions=icons.map(t=>{const icon=label(card,t);return {name:t,item:icon?icon.parent:null}});
    check(tag+'-all-toolbar-actions-contained',actions.every(a=>a.item&&inside(a.item,card)),actions.map(a=>({name:a.name,box:a.item?box(a.item,card):null})));
    const recentIcon=label(card,'schedule');mouseClick(recentIcon.parent,recentIcon.parent.width/2,recentIcon.parent.height/2,Qt.LeftButton);field.text='';wait(100);
    check(tag+'-native-recent-tab',n.leftSidebarTab==='recent',n.leftSidebarTab);
    let view=list(card);require(view&&view.count===4,'Recent list contains all notes');
    let row=view.itemAtIndex(0);require(row,'Recent first row instantiated');
    const recentText=descendants(row,c=>c.text!==undefined&&c.font!==undefined&&String(c.text).length>0);
    check(tag+'-recent-text-contained',inside(view,card)&&inside(row,view)&&recentText.length===2&&recentText.every(t=>inside(t,row)&&t.elide===Text.ElideRight&&t.truncated),recentText.map(t=>({text:String(t.text),box:box(t,row),truncated:t.truncated})));
    const recentTarget=String(row.modelData.relPath);mouseClick(row,row.width/2,row.height/2,Qt.LeftButton);settle();
    check(tag+'-native-recent-click',n.currentPath===recentTarget,{actual:n.currentPath,expected:recentTarget});
    snap(tag+'-recent');
    const keyboardTarget=String(n.recentNotes[0].relPath);n.openHomepage();settle();ws.forceActiveFocus();keyClick(Qt.Key_5,Qt.AltModifier);settle();
    check(tag+'-native-recent-shortcut',n.currentPath===keyboardTarget&&n.activeView==='document',{actual:n.currentPath,expected:keyboardTarget,view:n.activeView});
    const searchIcon=label(card,'search');mouseClick(searchIcon.parent,searchIcon.parent.width/2,searchIcon.parent.height/2,Qt.LeftButton);wait(80);
    check(tag+'-native-search-tab',n.leftSidebarTab==='search',n.leftSidebarTab);
    field.text=QUERY;field.forceActiveFocus();keyClick(Qt.Key_End);keyClick(Qt.Key_Return);tryVerify(()=>n.searchResults.length>=4,5000);wait(100);
    check(tag+'-unicode-query-preserved',field.text===QUERY&&n.searchQuery===QUERY&&field.clip&&inside(field,card),{text:field.text,query:n.searchQuery,field:box(field,card),contentWidth:field.contentWidth});
    view=list(card);require(view&&view.count>=4,'native search results instantiated');row=view.itemAtIndex(0);require(row,'search first row');
    const texts=descendants(row,c=>c.text!==undefined&&c.font!==undefined&&String(c.text).length>0);
    check(tag+'-search-result-contained',inside(view,card)&&inside(row,view)&&texts.length===3&&texts.every(t=>inside(t,row)),texts.map(t=>({text:String(t.text),box:box(t,row),truncated:t.truncated})));
    const target=String(row.modelData.relPath);mouseClick(row,row.width/2,row.height/2,Qt.LeftButton);settle();check(tag+'-native-search-click',n.currentPath===target,{actual:n.currentPath,expected:target});
    snap(tag+'-search');
    field.forceActiveFocus();keyClick(Qt.Key_A,Qt.ControlModifier);keyClick(Qt.Key_Backspace);wait(80);
    check(tag+'-keyboard-clear',field.text===''&&n.searchQuery===''&&n.searchResults.length===0,{text:field.text,query:n.searchQuery,count:n.searchResults.length});
    for(const key of[Qt.Key_N,Qt.Key_E,Qt.Key_E,Qt.Key_D,Qt.Key_L,Qt.Key_E])keyClick(key);
    keyClick(Qt.Key_Return);tryVerify(()=>n.searchResults.length>=4,5000);check(tag+'-keyboard-ascii-search',field.text==='needle'&&n.searchQuery==='needle',{text:field.text,query:n.searchQuery});
    const clear=label(card,'close');require(clear,'clear query action');check(tag+'-clear-action-contained',inside(clear.parent,card),box(clear.parent,card));mouseClick(clear.parent,clear.parent.width/2,clear.parent.height/2,Qt.LeftButton);wait(80);
    check(tag+'-native-clear-click',field.text===''&&n.searchQuery===''&&n.searchResults.length===0,{text:field.text,query:n.searchQuery,count:n.searchResults.length});
   }
   console.info('RECENT_DONE');Qt.quit();
  }catch(e){console.error('RECENT_ABORT',e.message,e.stack);Qt.exit(1)}}
 }
 Timer {interval:300;running:true;onTriggered:tc.run()}
}'''
    for key,value in {'SERVICE':str(PLUGIN/'services/NexusService.qml'),'WORKSPACE':str(PLUGIN/'modules/nexus/NexusWorkspace.qml'),'OUT':str(OUT),'LABEL':LABEL,'QUERY':query}.items():
        qml=qml.replace(key,json.dumps(value,ensure_ascii=False))
    (shell/'shell.qml').write_text(qml)
    runtime=private/'runtime';runtime.mkdir(mode=0o700)
    env=dict(os.environ,QT_QPA_PLATFORM='wayland',QT_QUICK_BACKEND='software',XDG_RUNTIME_DIR=str(runtime),ALIS_NEXUS_DISABLE_XDG_OPEN='1',ALIS_NEXUS_HEADLESS_SERVICE_ONLY='1')
    for kind in ('config','state','cache','data'):env['XDG_'+kind.upper()+'_HOME']=str(private/kind)
    env.pop('NIRI_SOCKET',None);env.pop('HYPRLAND_INSTANCE_SIGNATURE',None)
    with private_wayland(private) as native:
        if native is None:raise SystemExit('SKIP: private native compositor unavailable')
        env.update({k:v for k,v in native.items() if k in ('WAYLAND_DISPLAY','NIRI_SOCKET','DISPLAY','XDG_RUNTIME_DIR')})
        result=run_qs(shell,env,timeout=55)
    after={str(p.relative_to(vault)):hashlib.sha256(p.read_bytes()).hexdigest() for p in vault.rglob('*') if p.is_file()}
    checks=[json.loads(x) for x in re.findall(r'RECENT_CHECK (\{[^\n]+\})',result.stdout)]
    checks.append({'name':'fixture-note-bytes-unchanged','status':'PASS' if before==after else 'FAIL','actual':{'before':before,'after':after}})
    receipt={'scope':'Actual installed host with explicit Integration payload, private native compositor/config/vault; no physical desktop or production vault writes.','host':str(HOST),'plugin':str(PLUGIN),'workspaceSha256':hashlib.sha256((PLUGIN/'modules/nexus/NexusWorkspace.qml').read_bytes()).hexdigest(),'scale':env.get('QT_SCALE_FACTOR','1'),'exit':result.returncode,'complete':'RECENT_DONE' in result.stdout,'checks':checks}
    (OUT/(LABEL+'.log')).write_text(result.stdout);(OUT/(LABEL+'.json')).write_text(json.dumps(receipt,indent=2,ensure_ascii=False)+'\n');print(json.dumps(receipt,indent=2,ensure_ascii=False))
    if result.returncode or not receipt['complete'] or any(c['status']!='PASS' for c in checks):raise SystemExit(1)
