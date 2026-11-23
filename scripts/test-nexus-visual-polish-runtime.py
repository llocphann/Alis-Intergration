#!/usr/bin/env python3
"""Isolated rendered audit of Nexus paper, anatomy, photo tint and planner."""
import json, os, re, sys, tempfile
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    print("SKIP: Pillow (PIL) not installed")
    raise SystemExit(77)

ROOT=Path(__file__).resolve().parents[1]
OUT=Path(os.environ.get('ALIS_NEXUS_RESPONSIVE_EVIDENCE_DIR') or tempfile.mkdtemp(prefix='alis-responsive-evidence-'))
OUT.mkdir(parents=True,exist_ok=True)
VIEWPORT=int(os.environ.get('VISUAL_WIDTH','1280'))
HEIGHT=int(os.environ.get('VISUAL_HEIGHT','820'))
LABEL=os.environ.get('VISUAL_LABEL',str(VIEWPORT))
sys.path.insert(0,str(ROOT/'scripts'))
from integration_test_host import resolve_host_root
HOST=Path(os.environ.get('ALIS_RESPONSIVE_HOST',str(resolve_host_root(ROOT)))).resolve()
PLUGIN=Path(os.environ.get('VISUAL_PLUGIN',str(ROOT))).resolve()
sys.path.insert(0,str(HOST/'scripts'))
from native_test_session import private_wayland, run_qs

with tempfile.TemporaryDirectory(prefix='alis-installed-visual-') as name:
    private=Path(name); shell=private/'shell'; shell.mkdir()
    for entry in ('services','modules','GlobalStates.qml','qmldir','scripts','defaults','translations','assets'):
        (shell/entry).symlink_to(HOST/entry)
    vault=private/'Vault'; vault.mkdir()
    (vault/'A deliberately long standard note title with Unicode tiếng Việt and spaces.md').write_text('# Fixture\nInitial body.\n')
    config=private/'config/alis'; config.mkdir(parents=True)
    options=json.loads((HOST/'defaults/config.json').read_text())
    options['todo']['nexus']['vaultPath']=str(vault)
    options['bar']['weather']['enable']=False
    (config/'config.json').write_text(json.dumps(options))
    photo=private/'photo.svg'
    photo.write_text('<svg xmlns="http://www.w3.org/2000/svg" width="400" height="300"><rect width="400" height="300" fill="#d6c0a1"/><path fill="#527c8d" d="M0 0h200v150H0z M200 150h200v150H200z"/></svg>')
    qt_config=private/'config/quickshell/alis';qt_config.mkdir(parents=True);(qt_config/'config.json').write_text(json.dumps(options))
    qml=r'''import QtQuick
import QtTest
import Quickshell
import qs
import qs.services
import qs.modules.common
ShellRoot {
  Component.onCompleted: Quickshell.watchFiles = false
  FloatingWindow {
    id: win; visible: true; implicitWidth: INITIAL_WIDTH; implicitHeight: INITIAL_HEIGHT
    Loader { id: svc; source: "SERVICE" }
    Loader { id: workspace; anchors.fill: parent; source: "WORKSPACE"; onLoaded: item.nexus=svc.item }
  }
  TestCase {
    id: tc; when: false; optional: true
    function report(name, pass, actual) { console.info("VISUAL_AUDIT", JSON.stringify({name:name,status:pass?"PASS":"FAIL",actual:actual})); }
    function required(value, message) { if (!value) throw new Error(message); }
    function settle() { tryVerify(()=>!svc.item.docBusy && !svc.item.scanBusy,6000); wait(160); }
    function capture(name) { wait(100); const im=grabImage(workspace.item); required(im.width>0 && im.height>0,"nonempty image "+name); im.save("OUT/"+"LABEL-"+name+".png"); }
    function box(item) { if (!item) return null; const p=item.mapToItem(workspace.item,0,0); return {x:p.x,y:p.y,w:item.width,h:item.height,visible:item.visible}; }
    function leafBounds(cv) {
      const failures=[];
      function walk(item) {
        if (!item || !item.visible) return;
        const type=String(item);
        if (/^QQuickText(?:\(|Edit\(|Field\(|Area\()/.test(type) && item.text !== undefined && String(item.text).length > 0) {
          const p=item.mapToItem(cv,0,0);
          if (item.width<=0 || p.x < -1 || p.x+item.width>cv.width+1)
            failures.push({name:item.objectName,type:type,text:String(item.text).slice(0,50),x:p.x,w:item.width,surfaceW:cv.width});
        }
        for (const child of (item.children||[])) walk(child);
      }
      walk(cv);return failures;
    }
    function findLabel(item,label) {
      if(!item || !item.visible)return null;
      if(item.text!==undefined && String(item.text)===label)return item;
      for(const child of(item.children||[])){const found=findLabel(child,label);if(found)return found;}
      return null;
    }
    function ensureVisible(item) {
      const flick=findChild(workspace.item,"nexusHybridOutlinerPane");
      if(flick) {const p=item.mapToItem(flick.contentItem,0,0);flick.contentY=Math.max(0,Math.min(flick.contentHeight-flick.height,p.y-flick.height/2));wait(100);}
    }
    function colorAt(image,x,y){return String(image.pixel(Math.max(0,Math.min(image.width-1,Math.round(x))),Math.max(0,Math.min(image.height-1,Math.round(y)))));}
    function canvasOf(card){return card.children.find(child=>typeof child.getContext === "function");}
    property bool captureDone:false
    property bool captureSaved:false
    function surfaceCapture(item,name){
      wait(100);captureDone=false;captureSaved=false;
      required(item.grabToImage(result=>{captureSaved=result.saveToFile("OUT/"+"LABEL-"+name+".png");captureDone=true;}),"capture requested "+name);
      tryVerify(()=>captureDone,3000);required(captureSaved,"capture saved "+name);
      return {width:item.width,height:item.height};
    }
    function theme(light){
      const c=Appearance.m3colors;
      c.m3background=light?"#f5f0fa":"#111218";c.m3surface=c.m3background;
      c.m3surfaceContainerLow=light?"#eee8f4":"#191821";c.m3surfaceContainer=light?"#e8e1ed":"#211f2a";c.m3surfaceContainerHigh=light?"#e2dae8":"#292635";
      c.m3onSurface=light?"#201a28":"#f1e8f7";c.m3onBackground=c.m3onSurface;
      c.m3onSurfaceVariant=light?"#514759":"#cabfd4";
      c.m3primary=light?"#7139af":"#bd8cf5";c.m3secondary=light?"#006b58":"#74d6b5";
      c.m3outlineVariant=light?"#aaa0b5":"#665d75";
      const ws=workspace.item;tryVerify(()=>ws._settledPrimary===String(c.m3primary),2000);wait(300);
    }
    function runAudit(){try{
      tryCompare(Config,"ready",true,6000);tryCompare(svc,"status",Loader.Ready,6000);tryCompare(workspace,"status",Loader.Ready,6000);
      const n=svc.item,ws=workspace.item;ws.nexus=n;n.open();tryCompare(n,"vaultLoaded",true,6000);settle();
      const paths={};const kinds=[{collection:"games",kind:"game",card:"nexusGamePaperCard"},{collection:"exercises",kind:"exercise",card:"nexusExerciseNotebookCard"},{collection:"recipes",kind:"recipe",card:"nexusRecipePersonalNoteCard"},{collection:"movies",kind:"movie",card:"nexusDossierLeftCard"}];
      for(const k of kinds){required(n.createCollectionEntry(k.collection,"Visual fixture "+k.kind),"create "+k.kind);settle();paths[k.kind]=n.currentPath;}
      for(const light of [false,true]){
        theme(light);const mode=light?"light":"dark";let reference=null;
        for(const k of kinds){
          n.openFile(paths[k.kind],true);settle();const cv=findChild(ws,"nexusCustomViewsRoot");required(cv,"custom view "+k.kind);
          if(k.kind==="recipe"){cv.recipeActiveSection="notes";wait(100);}
          const card=findChild(ws,k.card);required(card&&card.width>0,"paper "+k.kind);ensureVisible(card);wait(250);
          const canvas=canvasOf(card);required(canvas&&canvas.available,"paper canvas "+k.kind);canvas.requestPaint();wait(120);
          const image=surfaceCapture(card,mode+"-paper-"+k.kind);
          const style={radius:card.radius,bg:String(card.color),border:String(card.border.color),opacity:canvas.opacity};
          if(!reference)reference=style;
          report(mode+"-paper-parity-"+k.kind,style.radius===9&&style.radius===reference.radius&&style.bg===reference.bg&&style.border===reference.border&&style.opacity===.25,style);
          const ctx=canvas.getContext("2d");const rows=[];
          for(let y=40;y<Math.min(145,canvas.height-12);y++){if(ctx.getImageData(15,y,1,1).data[3]>0)rows.push(y);}
          const groups=[];for(const y of rows)if(!groups.length||y>groups[groups.length-1][1]+1)groups.push([y,y]);else groups[groups.length-1][1]=y;
          const spacing=groups.slice(1).map((p,i)=>p[0]-groups[i][0]);
          report(mode+"-paper-rendered-rules-"+k.kind,groups.length>=3&&Math.abs(groups[0][0]-52)<=1&&spacing.every(x=>x===26),{groups:groups,spacing:spacing,size:[image.width,image.height]});
          if(k.kind==="exercise"){
            const doc=Object.assign({},n.currentDoc);doc.exerciseView=Object.assign({},doc.exerciseView,{primaryMuscles:["chest"],secondaryMuscles:["triceps"]});n.currentDoc=doc;wait(200);
            const anatomy=findChild(ws,"nexusExerciseBodyMapCanvas");required(anatomy,"anatomy");ensureVisible(anatomy);anatomy.requestPaint();wait(180);surfaceCapture(anatomy,mode+"-anatomy-highlighted");
            const pixels=anatomy.getContext("2d").getImageData(0,0,Math.floor(anatomy.width),Math.floor(anatomy.height)).data;let opaque=0,white=0,colored=0;
            for(let i=0;i<pixels.length;i+=4){if(pixels[i+3]>20){opaque++;if(pixels[i]>245&&pixels[i+1]>245&&pixels[i+2]>245)white++;if(Math.max(pixels[i],pixels[i+1],pixels[i+2])-Math.min(pixels[i],pixels[i+1],pixels[i+2])>25)colored++;}}
            report(mode+"-anatomy-rendered-highlight",opaque>150&&colored>40&&white/opaque<.01,{opaque:opaque,colored:colored,white:white,primary:anatomy.primaryMuscles,secondary:anatomy.secondaryMuscles});
            const empty=Object.assign({},doc,{exerciseView:Object.assign({},doc.exerciseView,{primaryMuscles:[],secondaryMuscles:[]}),dossier:Object.assign({},doc.dossier,{muscleGroup:"",secondaryMuscles:""})});n.currentDoc=empty;wait(150);anatomy.requestPaint();wait(120);surfaceCapture(anatomy,mode+"-anatomy-inactive");
            const inactive=anatomy.getContext("2d").getImageData(0,0,Math.floor(anatomy.width),Math.floor(anatomy.height)).data;let different=0;
            for(let i=0;i<pixels.length;i+=4)if(Math.abs(pixels[i]-inactive[i])+Math.abs(pixels[i+1]-inactive[i+1])+Math.abs(pixels[i+2]-inactive[i+2])>20)different++;
            report(mode+"-anatomy-primary-secondary-visible",different>50,{changedPixels:different});
          }
        }
      }
      n.openHomepage();settle();n.homepagePhotoUrl="PHOTO";wait(200);
      const photo=findChild(ws,"nexusHomepagePhotoImage"),card=findChild(ws,"nexusHomepagePhotoCard"),overlay=findChild(ws,"nexusHomepagePhotoThemeOverlay");required(photo&&card&&overlay,"photo objects");tryCompare(photo,"status",Image.Ready,4000);ensureVisible(card);
      for(const light of [false,true]){theme(light);surfaceCapture(card,(light?"light":"dark")+"-photo-tint");
       report((light?"light":"dark")+"-photo-full-coverage-geometry",overlay.width===photo.width&&overlay.height===photo.height&&overlay.x===0&&overlay.y===0&&photo.visible&&photo.opacity>0,{image:[photo.width,photo.height],overlay:[overlay.x,overlay.y,overlay.width,overlay.height]});}
      const timeline=findChild(ws,"nexusWeeklyPlannerTimeline");required(timeline&&timeline.visible,"planner timeline");timeline.contentY=0;wait(100);
      for(const light of [false,true]){theme(light);timeline.contentY=0;const image=surfaceCapture(timeline,(light?"light":"dark")+"-planner");report((light?"light":"dark")+"-planner-geometry",timeline.width>0&&timeline.height>0,{rowHeight:timeline.hourRowHeight,contentHeight:timeline.contentHeight,border:String(ws.borderSubtle),background:String(ws._settledLayer1),width:timeline.width});}
      report("planner-scroll-preserved",timeline.contentHeight===timeline.hourRowHeight*24&&timeline.hourRowHeight>=44,{rowHeight:timeline.hourRowHeight});
      const context=findChild(ws,"nexusContextCard");tryCompare(Events,"ready",true,4000);
      const date=context.activePlannerDateIso,parts=date.split("-");const start=new Date(Number(parts[0]),Number(parts[1])-1,Number(parts[2]),10,0),end=new Date(Number(parts[0]),Number(parts[1])-1,Number(parts[2]),11,30);
      Events.addEvent("Visual audit planner event","Isolated fixture",start.toISOString(),"general","normal",15,"none",end.toISOString(),false);
      tryVerify(()=>context.syncedTimedItems.some(item=>item.title==="Visual audit planner event"),2000);
      const event=findChild(ws,"nexusWeeklyPlannerEvent_0");required(event,"native planner event");timeline.contentY=Math.min(timeline.contentHeight-timeline.height,Math.max(0,event.y-6));wait(100);
      mouseClick(event,event.width/2,event.height/2,Qt.LeftButton);settle();
      report("planner-native-event-opens-journal",n.currentDoc?.noteKind==="journal",{kind:n.currentDoc?.noteKind,path:n.currentPath,date:date});
      timeline.contentY=0;wait(100);mouseWheel(timeline,timeline.width/2,timeline.height/2,0,-120,Qt.NoButton,Qt.NoModifier,20);wait(200);
      report("planner-native-wheel-scroll",timeline.contentY>0,{contentY:timeline.contentY});
      console.info("VISUAL_AUDIT_DONE");Qt.quit();
    }catch(e){console.error("VISUAL_AUDIT_ABORT",e.message,e.stack);Qt.exit(1)}}
  }
  Timer { interval:500; running:true; onTriggered:tc.runAudit() }
}'''.replace('INITIAL_WIDTH',str(VIEWPORT)).replace('INITIAL_HEIGHT',str(HEIGHT)).replace('LABEL',LABEL).replace('SERVICE',str(PLUGIN/'services/NexusService.qml')).replace('WORKSPACE',str(PLUGIN/'modules/nexus/NexusWorkspace.qml')).replace('OUT',str(OUT)).replace('PHOTO',photo.as_uri())
    (shell/'shell.qml').write_text(qml)
    runtime=private/'runtime'; runtime.mkdir(mode=0o700)
    env=dict(os.environ,QT_QPA_PLATFORM='offscreen',XDG_RUNTIME_DIR=str(runtime),ALIS_NEXUS_DISABLE_XDG_OPEN='1',ALIS_NEXUS_HEADLESS_SERVICE_ONLY='1')
    for kind in ('config','state','cache','data'): env['XDG_'+kind.upper()+'_HOME']=str(private/kind)
    env.pop('NIRI_SOCKET',None); env.pop('HYPRLAND_INSTANCE_SIGNATURE',None)
    with private_wayland(private) as native:
        if native is None: raise SystemExit('SKIP: responsive geometry needs a private native compositor')
        if native:
            env.update({k:v for k,v in native.items() if k in ('WAYLAND_DISPLAY','NIRI_SOCKET','DISPLAY','XDG_RUNTIME_DIR')}); env['QT_QPA_PLATFORM']='wayland'
        result=run_qs(shell,env,timeout=90)
    (OUT/('audit-'+LABEL+'.log')).write_text(result.stdout)
    samples=[json.loads(x) for x in re.findall(r'VISUAL_AUDIT (\{[^\n]+\})',result.stdout)]
    def pixel_test(name,passed,actual): samples.append({'name':name,'status':'PASS' if passed else 'FAIL','actual':actual})
    if result.returncode==0 and 'VISUAL_AUDIT_DONE' in result.stdout:
        photos=[]
        for mode in ('dark','light'):
            image=Image.open(OUT/(LABEL+'-'+mode+'-photo-tint.png')).convert('RGBA')
            points=[(6,6),(image.width-7,6),(6,image.height-7),(image.width-7,image.height-7),(image.width//2,image.height//2)]
            colors=[image.getpixel(point) for point in points];photos.append(colors)
            pixel_test(mode+'-photo-rendered-detail',len(set(colors))>=2 and all(c[3]>0 for c in colors),{'pixels':colors,'size':image.size})
            planner=Image.open(OUT/(LABEL+'-'+mode+'-planner.png')).convert('RGBA')
            scale=planner.width/max(1,next(x['actual'].get('width',planner.width) for x in samples if x['name']==mode+'-planner-geometry'))
            line=planner.getpixel((planner.width-12,10));bg=planner.getpixel((planner.width-12,20))
            geometry=next(x['actual'] for x in samples if x['name']==mode+'-planner-geometry')
            expected=tuple(bytes.fromhex(geometry['border'].lstrip('#')))+(255,)
            pixel_test(mode+'-planner-uses-undiluted-border-token',line==expected,{'line':line,'expected':expected})
        pixel_test('photo-reactive-edge-center-tint',all(a!=b for a,b in zip(*photos)),photos)
    receipt={'plugin':str(PLUGIN),'host':str(HOST),'scope':'Explicit installed/candidate payload, actual installed host, native private compositor and temporary vault/config. Child PNGs use item.grabToImage; dark/light paper26px rules, anatomy primary/secondary/inactive and pixel clipping, photo full-coverage/detail/reactivity, planner line token and event/wheel actions. Exact historical15percent and Owner/physical display acceptance unproven.','exitCode':result.returncode,'complete':'VISUAL_AUDIT_DONE' in result.stdout,'checks':samples,'viewport':{'width':VIEWPORT,'height':HEIGHT,'scale':env.get('QT_SCALE_FACTOR','1')}}
    (OUT/('audit-'+LABEL+'.json')).write_text(json.dumps(receipt,indent=2)+'\n')
    print(json.dumps(receipt,indent=2))
    print('\n'.join(x for x in result.stdout.splitlines() if 'VISUAL_AUDIT_ABORT' in x))

    if result.returncode or not receipt['complete'] or any(x['status']!='PASS' for x in samples): raise SystemExit(1)
