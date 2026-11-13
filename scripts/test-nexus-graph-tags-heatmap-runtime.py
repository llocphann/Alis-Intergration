"""Installed graph input/palette, nested tags, and legacy heatmap cache gates."""
import datetime,hashlib,json,os,re,sys,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
HOST=Path(os.environ.get('ALIS_GTH_HOST',str(Path.home()/'.config/quickshell/alis'))).resolve()
PLUGIN=Path(os.environ.get('ALIS_GTH_PLUGIN',str(Path.home()/'.local/share/alis-intergration/current'))).resolve()
OUT=Path(os.environ.get('ALIS_GTH_EVIDENCE') or tempfile.mkdtemp(prefix='alis-gth-evidence-'));OUT.mkdir(parents=True,exist_ok=True)
LABEL=os.environ.get('ALIS_GTH_LABEL','native')
sys.path.insert(0,str(HOST/'scripts'))
from native_test_session import private_wayland,run_qs
with tempfile.TemporaryDirectory(prefix='alis-gth-') as name:
 p=Path(name);shell=p/'shell';shell.mkdir()
 for entry in ('services','modules','GlobalStates.qml','qmldir','scripts','defaults','translations','assets'):(shell/entry).symlink_to(HOST/entry)
 vault=p/'Vault';vault.mkdir()
 originals={'Alpha.md':'---\r\ntags: [tone, tone/positive]\r\ncustom: retained\r\n---\r\n# Alpha\r\n[[Beta]]\r\n','Beta.md':'---\ntags: [tone/positive/strong, topic/sub/grand]\n---\n# Beta\n[[Alpha]]\n'}
 for path,content in originals.items():(vault/path).write_bytes(content.encode())
 day=datetime.date(2026,11,11)
 cells=[{'date':str(day-datetime.timedelta(days=118-i)),'count':(i%7)+1,'level':min(4,(i%7)+1)} for i in range(119)]
 tags=[{'name':'tone','count':1,'notes':['Alpha.md']},{'name':'tone/positive','count':1,'notes':['Alpha.md']},{'name':'tone/positive/strong','count':1,'notes':['Beta.md']},{'name':'topic/sub/grand','count':1,'notes':['Beta.md']}]
 cache={'ok':True,'vaultPath':str(vault),'vaultName':'Fixture','tree':{'name':'Vault','relPath':'','isDir':True,'children':[]},'files':[],'tags':tags,'homepageLocalGraph':{'nodes':[{'id':'Alpha.md','relPath':'Alpha.md','title':'Alpha','x':.25,'y':.45},{'id':'Beta.md','relPath':'Beta.md','title':'Beta','x':.7,'y':.65}],'edges':[{'source':'Alpha.md','target':'Beta.md'}]},'stats':{'userHost':'private@fixture','noteCount':2,'activityHeatmap':cells,'legacyCacheFixture':True}}
 cachepath=p/'state/quickshell/user/nexus_vault_cache.json';cachepath.parent.mkdir(parents=True);cachepath.write_text(json.dumps(cache));cachebytes=cachepath.read_bytes()
 options=json.loads((HOST/'defaults/config.json').read_text());options['todo']['nexus']['vaultPath']=str(vault);options['bar']['weather']['enable']=False
 for cfg in (p/'config/alis',p/'config/quickshell/alis'):cfg.mkdir(parents=True);(cfg/'config.json').write_text(json.dumps(options))
 qml=r'''import QtQuick
import QtTest
import Quickshell
import qs
import qs.services
import qs.modules.common
ShellRoot {
 Component.onCompleted:Quickshell.watchFiles=false
 FloatingWindow{id:win;visible:true;implicitWidth:1700;implicitHeight:820
  Loader{id:service}
  Loader{id:workspace;anchors.left:parent.left;anchors.top:parent.top;width:1280;height:parent.height}
 }
 TestCase{id:tc;when:false;optional:true
  function check(name,pass,actual){console.info('GTH_CHECK',JSON.stringify({name:name,status:pass?'PASS':'FAIL',actual:actual}))}
  function need(v,message){if(!v)throw new Error(message)}
  function nodes(item,pred,out){out=out||[];if(item&&item.visible){if(pred(item))out.push(item);for(const c of(item.children||[]))nodes(c,pred,out)}return out}
  function label(item,text){return nodes(item,c=>c.text!==undefined&&String(c.text)===text)[0]||null}
  function settle(n){tryVerify(()=>!n.docBusy&&!n.scanBusy,5000);wait(100)}
  function grab(item,name){let saved=false;item.grabToImage(result=>{saved=result.saveToFile(OUT+'/'+LABEL+'-'+name+'.png')});tryVerify(()=>saved,2500)}
  function loadCache(){service.source=SERVICE;tryCompare(service,'status',Loader.Ready,5000);const n=service.item;tryCompare(n,'vaultLoaded',true,5000);need(n.stats.legacyCacheFixture===true&&n._lastScanDoneMs===0,'actual legacy FileView cache loaded before native rescan');n.isOpen=true;return n}
  function heatmap(ws,n,name){
   n.openHomepage();const h=findChild(ws,'nexusHomepageHeatmapColumn');wait(140);
   const expected=n.stats.activityHeatmap;const tail=h.cellsData.slice(-119);
   check(name+'-legacy-tail-right-aligned',h.numWeeks>=17&&h.cellsData.length===h.numWeeks*7&&JSON.stringify(tail)===JSON.stringify(expected),{workspaceWidth:ws.width,windowWidth:win.width,implicitWidth:win.implicitWidth,available:h.availW,computed:h.computedRowW,weeks:h.numWeeks,cells:h.cellsData.length,first:h.cellsData[0],last:h.cellsData[h.cellsData.length-1]});
   check(name+'-known-counts-dates-preserved',tail.every((c,i)=>c?.date===expected[i].date&&c?.count===expected[i].count&&c?.level===expected[i].level),{known:tail.length,expected:expected.length});
   check(name+'-unknown-history-stays-unknown',h.cellsData.slice(0,h.cellsData.length-119).every(c=>c===null),{prefix:h.cellsData.length-119});
   const grid=findChild(ws,'nexusHomepageHeatmapGrid');const tiles=grid.children.filter(c=>c.cellEntry!==undefined);
   check(name+'-fixed-rendered-tiles',tiles.length===h.numWeeks*7&&tiles.every(c=>c.width===11&&c.height===11)&&tiles[tiles.length-1].dateKey===expected[118].date,{tiles:tiles.length,tile:h.cellW,last:tiles[tiles.length-1]?.dateKey});
  }
  function tagRow(ws,name){const card=findChild(ws,'nexusFileTreeCard');return nodes(card,c=>c.modelData?.name===name&&String(c).startsWith('QQuickRectangle'))[0]||null}
  function chevron(ws,name){const row=tagRow(ws,name);need(row,'tag row '+name);const icon=label(row,row.modelData.expanded?'expand_more':'chevron_right');need(icon,'tag chevron '+name);mouseClick(icon.parent,icon.parent.width/2,icon.parent.height/2,Qt.LeftButton);wait(80)}
  function run(){try{
   tryCompare(Config,'ready',true,5000);need(Weather.enabled===false,'offline Weather disabled');let n=loadCache();workspace.source=WORKSPACE;tryCompare(workspace,'status',Loader.Ready,5000);const ws=workspace.item;ws.nexus=n;wait(150);
   heatmap(ws,n,'cache-1280');workspace.width=1700;tryCompare(ws,"width",1700,2000);wait(140);heatmap(ws,n,'cache-grow1700');workspace.width=1280;tryCompare(ws,"width",1280,2000);wait(140);heatmap(ws,n,'cache-shrink1280');
   ws.nexus=null;service.source='';tryCompare(service,'status',Loader.Null,2000);n=loadCache();ws.nexus=n;workspace.width=1700;tryCompare(ws,"width",1700,2000);wait(140);heatmap(ws,n,'cache-reloaded1700');workspace.width=1280;tryCompare(ws,"width",1280,2000);wait(140);
   if(HEATMAP_ONLY){console.info('GTH_DONE');Qt.quit();return;}
   const card=findChild(ws,'nexusLocalGraphCard');const header=findChild(ws,'nexusLocalGraphStatusBar');const graph=findChild(ws,'nexusLocalGraphCanvas');const title=label(header,'Local Graph');const originalHeader=header;const geometry=[card.width,card.height];
   mouseMove(ws,ws.width-2,ws.height/2);wait(180);check('installed-header-idle',header.opacity<=.01,header.opacity);
   const originalPan=[graph.panX,graph.panY];mousePress(card,50,18,Qt.LeftButton);mouseMove(card,74,27,80);mouseRelease(card,74,27,Qt.LeftButton);wait(180);check('header-label-area-input-reaches-canvas',graph.panX!==originalPan[0]||graph.panY!==originalPan[1],{before:originalPan,after:[graph.panX,graph.panY]});graph.resetView();
   mouseMove(card,card.width/2,card.height/2);wait(180);check('installed-header-enter',header.opacity>=.99,header.opacity);mouseMove(header,header.width/2,header.height/2);wait(180);check('installed-header-stays-on-controls',header.opacity>=.99,header.opacity);
   const dark={colPrimary:'#22bb88',colOnPrimary:'#102030',colTertiary:'#d4a4e4',colLayer0:'#101820',colLayer1:'#203040',colLayer2:'#304050',colOnLayer0:'#f0f1f2',colOnLayer1:'#e1e2e3',colSubtext:'#a1a2a3',colLayer0Border:'#718293'};
   const light={colPrimary:'#883355',colOnPrimary:'#fff1e2',colTertiary:'#375a7b',colLayer0:'#f1f2f3',colLayer1:'#e4e5e6',colLayer2:'#d7d8d9',colOnLayer0:'#111213',colOnLayer1:'#242526',colSubtext:'#575859',colLayer0Border:'#6a7b8c'};
   let beforePaint=graph.paintCount;let previousColors=JSON.stringify(graph.resolvedNodeColors);
   for(const [name,palette]of[['dark',dark],['light',light]]){
    for(const key of Object.keys(palette))Appearance.colors[key]=palette[key];tryVerify(()=>ws._settledPrimary===palette.colPrimary,2500);tryVerify(()=>graph.paintCount>beforePaint&&graph.lastPaintedThemeSignature===ws.themeSignature,2500);wait(450);
    const bg=Qt.color(palette.colLayer0);const hub=label(header,'hub');
    check(name+'-same-live-header-palette',header===originalHeader&&Math.abs(header.color.r-bg.r)<.005&&Math.abs(header.color.a-.88)<.005&&String(header.border.color)===palette.colLayer0Border&&String(title.color)===palette.colOnLayer1&&String(hub.color)===palette.colPrimary,{header:String(header.color),border:String(header.border.color),title:String(title.color),hub:String(hub.color)});
    check(name+'-live-graph-painted-new-palette',JSON.stringify(graph.resolvedNodeColors)!==previousColors&&graph.lastPaintedThemeSignature===ws.themeSignature,{paint:graph.paintCount,colors:graph.resolvedNodeColors});grab(card,name+'-graph-header');beforePaint=graph.paintCount;previousColors=JSON.stringify(graph.resolvedNodeColors);
   }
   mouseMove(ws,ws.width-2,ws.height/2);wait(180);check('installed-header-leave-keeps-geometry',header.opacity<=.01&&card.width===geometry[0]&&card.height===geometry[1],{opacity:header.opacity,geometry:[card.width,card.height]});
   const point=graph._screenPosForNode(0);const target=String(graph.graphData.nodes[0].relPath);mouseClick(graph,point.x,point.y,Qt.LeftButton);settle(n);check('native-local-node-click-opens-note',n.currentPath===target,{target:target,path:n.currentPath});
   n.leftSidebarTab='tags';wait(80);const expectedCounts={'tone':2,'topic':1};check('native-cache-deduplicated-parent-counts',n.hierarchicalTagsList.every(x=>expectedCounts[x.name]===x.count),n.hierarchicalTagsList);
   chevron(ws,'tone');check('parent-chevron-expands-without-filter',n.leftSidebarTab==='tags'&&n.hierarchicalTagsList.some(x=>x.name==='tone/positive')&&n.searchQuery==='',{tab:n.leftSidebarTab,query:n.searchQuery,tags:n.hierarchicalTagsList});chevron(ws,'tone/positive');check('child-chevron-expands-grandchild',n.hierarchicalTagsList.some(x=>x.name==='tone/positive/strong'),n.hierarchicalTagsList);
   chevron(ws,'topic');chevron(ws,'topic/sub');check('absent-parent-chain-created-and-reachable',n.hierarchicalTagsList.some(x=>x.name==='topic/sub/grand'&&x.depth===2&&x.count===1),n.hierarchicalTagsList);
   const leaf=tagRow(ws,'tone/positive/strong');const leafText=label(leaf,'/strong');need(leafText,'grandchild row text');mouseClick(leafText,leafText.width/2,leafText.height/2,Qt.LeftButton);tryVerify(()=>n.searchResults.length===1,5000);check('native-grandchild-label-click-filters',n.leftSidebarTab==='search'&&n.searchQuery==='#tone/positive/strong'&&n.searchResults[0].relPath==='Beta.md',{tab:n.leftSidebarTab,query:n.searchQuery,results:n.searchResults});
   const filter=findChild(ws,'nexusFileFilterField');n.leftSidebarTab='tags';wait(80);check('return-to-tags-preserves-query-and-expansion',filter.text==='#tone/positive/strong'&&n.expandedParentTags['tone']&&n.expandedParentTags['tone/positive']&&n.expandedParentTags['topic/sub'],{query:filter.text,expanded:n.expandedParentTags});
   chevron(ws,'tone');check('collapse-parent-hides-descendants-only',!n.hierarchicalTagsList.some(x=>x.name.startsWith('tone/'))&&n.hierarchicalTagsList.some(x=>x.name==='topic/sub/grand'),n.hierarchicalTagsList);chevron(ws,'tone');check('reexpand-restores-child-expansion',n.hierarchicalTagsList.some(x=>x.name==='tone/positive/strong')&&n.searchQuery==='#tone/positive/strong',n.hierarchicalTagsList);
   n.refreshVault();tryVerify(()=>!n.scanBusy,5000);wait(100);check('native-rescan-preserves-expanded-filter-state',n.expandedParentTags['tone/positive']&&n.hierarchicalTagsList.some(x=>x.name==='tone/positive/strong')&&filter.text==='#tone/positive/strong',n.hierarchicalTagsList);
   console.info('GTH_DONE');Qt.quit();
  }catch(e){console.error('GTH_ABORT',e.message,e.stack);Qt.exit(1)}}
 }
 Timer{interval:300;running:true;onTriggered:tc.run()}
}'''
 for key,value in {'SERVICE':str(PLUGIN/'services/NexusService.qml'),'WORKSPACE':str(PLUGIN/'modules/nexus/NexusWorkspace.qml'),'OUT':str(OUT),'LABEL':LABEL,'HEATMAP_ONLY':os.environ.get('ALIS_GTH_ONLY_HEATMAP')=='1'}.items():qml=qml.replace(key,json.dumps(value))
 (shell/'shell.qml').write_text(qml)
 with private_wayland(p) as env:
  if env is None:raise SystemExit('SKIP private Wayland unavailable')
  env=dict(env,QT_QUICK_BACKEND='software',ALIS_NEXUS_DISABLE_XDG_OPEN='1',ALIS_NEXUS_HEADLESS_SERVICE_ONLY='1');result=run_qs(shell,env,timeout=30)
 checks=[json.loads(x) for x in re.findall(r'GTH_CHECK (\{[^\n]+\})',result.stdout)]
 checks.append({'name':'legacy-note-and-cache-bytes-unchanged','status':'PASS' if cachepath.read_bytes()==cachebytes and all((vault/k).read_bytes()==v.encode() for k,v in originals.items()) else 'FAIL'})
 receipt={'host':str(HOST),'plugin':str(PLUGIN),'workspaceSha256':hashlib.sha256((PLUGIN/'modules/nexus/NexusWorkspace.qml').read_bytes()).hexdigest(),'serviceSha256':hashlib.sha256((PLUGIN/'services/NexusService.qml').read_bytes()).hexdigest(),'scope':'Actual installed host and explicit payload, private native Wayland. Actual legacy cache FileView reload isolated from fresh scan; native graph/tag input and palette; no production state/vault/desktop writes.','exit':result.returncode,'complete':'GTH_DONE' in result.stdout,'checks':checks}
 (OUT/(LABEL+'.log')).write_text(result.stdout);(OUT/(LABEL+'.json')).write_text(json.dumps(receipt,indent=2)+'\n');print(json.dumps(receipt,indent=2))
 if result.returncode or not receipt['complete'] or any(c['status']!='PASS' for c in checks):raise SystemExit(1)
