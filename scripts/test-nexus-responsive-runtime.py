import json, os, re, sys, tempfile
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
OUT=Path(os.environ.get('ALIS_NEXUS_RESPONSIVE_EVIDENCE_DIR') or tempfile.mkdtemp(prefix='alis-responsive-evidence-'))
OUT.mkdir(parents=True,exist_ok=True)
VIEWPORT=int(os.environ.get('VISUAL_WIDTH','1280'))
HEIGHT=int(os.environ.get('VISUAL_HEIGHT','820'))
LABEL=os.environ.get('VISUAL_LABEL',str(VIEWPORT))
sys.path.insert(0,str(ROOT/'scripts'))
from integration_test_host import resolve_host_root
HOST=Path(os.environ.get('ALIS_RESPONSIVE_HOST',str(resolve_host_root(ROOT))))
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
    (config/'config.json').write_text(json.dumps(options))
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
    function runAudit() {
      try {
        tryCompare(Config,"ready",true,6000); tryCompare(svc,"status",Loader.Ready,6000); tryCompare(workspace,"status",Loader.Ready,6000);
        const n=svc.item; const ws=workspace.item; ws.nexus=n;
        n.open(); tryCompare(n,"vaultLoaded",true,6000); settle();
        const h=findChild(ws,"nexusHomepageHeatmapColumn");
        for (const w of [INITIAL_WIDTH]) {
          wait(200);
          report("heatmap-populated-width-"+w,ws.width===w && h.cellsData.length===h.numWeeks*7 && h.cellW===11,{viewport:ws.width,weeks:h.numWeeks,cells:h.cellsData.length,tile:h.cellW});
          capture("homepage-"+w);
        }
        wait(120);
        const kinds=[{collection:"movies",kind:"movie",card:"nexusDossierLeftCard",editor:"nexusDossierBodyEditor"},{collection:"games",kind:"game",card:"nexusGamePaperCard",editor:"nexusGameBodyEditor"},{collection:"exercises",kind:"exercise",card:"nexusExerciseNotebookCard",editor:"nexusExerciseBodyEditor"},{collection:"recipes",kind:"recipe",card:"nexusRecipePersonalNoteCard",editor:"nexusRecipePersonalNoteEditor"},{collection:"books",kind:"book",card:"nexusDossierLeftCard",editor:"nexusDossierBodyEditor"},{collection:"cornell",kind:"cornell",card:"nexusCornellSheetCard",editor:"nexusCornellBodyEditor"},{collection:"places",kind:"place",card:"nexusDossierLeftCard",editor:"nexusDossierBodyEditor"}];
        for (const k of kinds) {
          required(n.createCollectionEntry(k.collection,"Fixture "+k.kind),"create "+k.kind);
          tryVerify(()=>!n.docBusy && n.currentDoc?.noteKind===k.kind,6000); settle();
          const cv=findChild(ws,"nexusCustomViewsRoot"); required(cv,"custom views loaded "+k.kind);
          const path=n.currentPath;
          if(k.kind==="cornell") {n.saveNoteBodyMarkdown("### ? A deliberately long cue question with Unicode tiếng Việt and details\n\nAnswer with **bold** text and [[Fixture]].\n\n### ! Key concept\n\nAn explanation that must remain visible.");settle();}
          const noteFlick=findChild(ws,"nexusHybridOutlinerPane"); if(noteFlick) noteFlick.contentY=0; wait(120);
          if (k.kind==="recipe") report("recipe-default-overview",cv.recipeActiveSection==="overview",cv.recipeActiveSection);
          const header=findChild(ws,"nexusMainHeaderBar");const hb=box(header);
          const breadcrumb=findChild(ws,"nexusActiveTabBreadcrumb");
          const ribbon=findChild(ws,"nexusObsidianRibbon");
          const ribbonActions=[findChild(ws,"nexusBasesRibbonButton"),findChild(ws,"nexusCanvasRibbonButton"),findChild(ws,"nexusPaneRibbonButton"),findChild(ws,"nexusVimModeBadge"),findChild(ws,"nexusSplitModeButton"),findChild(ws,"nexusSaveNoteButton")];
          const breadcrumbOk=(breadcrumb && header && breadcrumb.visible && (function(){const p=breadcrumb.mapToItem(header,0,0);return p.x>=0&&p.y>=0&&p.x+breadcrumb.width<=header.width+1&&p.y+breadcrumb.height<=header.height+1;})());
          report("header-actions-contained-"+k.kind,Boolean(breadcrumbOk)&&Boolean(ribbon)&&ribbonActions.every(x=>{if(!x||!x.visible||x.width<=0)return false;const p=x.mapToItem(ribbon,0,0);return p.x>=0&&p.y>=0&&p.x+x.width<=ribbon.width+1&&p.y+x.height<=ribbon.height+1;}),{header:hb,ribbon:box(ribbon),actions:ribbonActions.map(box)});
          capture(k.kind+"-1280");
          const started=cv.startPrimaryInlineEdit(); wait(100);
          const edit=findChild(ws,k.editor);
          const localEditor=edit?edit.mapToItem(cv,0,0):null;
          report("inline-visible-"+k.kind,started && n.editorMode==="hybrid" && edit && edit.visible&&edit.width>0&&localEditor.x>=-1&&localEditor.x+edit.width<=cv.width+1,{mode:n.editorMode,editor:box(edit),localX:localEditor?localEditor.x:null,surfaceW:cv.width,section:cv.recipeActiveSection});
          if (edit && edit.visible) {
            const mark=k.kind==="cornell"?"### ? A deliberately long cue question with Unicode tiếng Việt and details\n\nFixture edited cornell with **bold** text and [[Fixture]].\n\n### ! Key concept\n\nAn explanation that must remain visible.":"Fixture edited "+k.kind;
            edit.text=mark;
            required(ws.handleEscape(),"Escape handled "+k.kind); settle();
            n.openFile(path,true); settle();
            const read=k.kind==="recipe"?String(n.currentDoc?.recipeView?.personalNotes??""):String(n.getNoteBodyMarkdown());
            report("inline-save-reopen-"+k.kind,read.includes(mark),read);
          }
          required(cv.startPrimaryInlineEdit(),"cancel edit starts "+k.kind);wait(120);
          const cancelEditor=findChild(ws,k.editor);cancelEditor.text="UNSAVED CANCELLED "+k.kind;
          const cancelLabel=findLabel(cv,"Cancel");required(cancelLabel,"Cancel action retained "+k.kind);
          ensureVisible(cancelLabel);mouseClick(cancelLabel.parent,cancelLabel.parent.width/2,cancelLabel.parent.height/2,Qt.LeftButton);wait(100);
          report("inline-cancel-exits-"+k.kind,!cancelEditor.visible,{editor:box(cancelEditor)});
          n.openFile(path,true);settle();
          const cancelledRead=k.kind==="recipe"?String(n.currentDoc?.recipeView?.personalNotes??""):String(n.getNoteBodyMarkdown());
          report("inline-cancel-preserves-"+k.kind,cancelledRead.includes("Fixture edited "+k.kind)&&!cancelledRead.includes("UNSAVED CANCELLED"),cancelledRead);
          const refreshedFlick=findChild(ws,"nexusHybridOutlinerPane");if(refreshedFlick)refreshedFlick.contentY=0;wait(150); capture(k.kind+"-narrow");
          const card=findChild(ws,k.card); const b=box(card);
          const leafProblems=leafBounds(cv);
          report("text-child-containment-"+k.kind,leafProblems.length===0,{surfaceW:cv.width,problems:leafProblems});
          const localCard=card?card.mapToItem(cv,0,0):null;
          report("nonzero-note-card-"+k.kind,Boolean(card)&&card.width>0&&localCard.x>=-1&&localCard.x+card.width<=cv.width+1,{card:b,localX:localCard?localCard.x:null,surfaceW:cv.width});
          report("card-horizontal-bounds-"+k.kind,ws.width===INITIAL_WIDTH && (!b || !b.visible || (b.x>=0 && b.x+b.w<=ws.width+1)),{card:b,viewport:ws.width});
          wait(100);
          if (k.kind==="cornell") {
            const row=findChild(ws,"nexusCornellRow_0");const left=findChild(ws,"nexusCornellCueLeftCol_0");const right=findChild(ws,"nexusCornellCueRightContainer_0");
            required(row&&left&&right,"rich Cornell cue containers");
            const lp=left.mapToItem(row,0,0);const rp=right.mapToItem(row,0,0);
            const stacked=row.width<560;
            const inside=left.width>0&&right.width>0&&lp.x>=0&&rp.x>=0&&lp.x+left.width<=row.width+1&&rp.x+right.width<=row.width+1&&lp.y>=0&&rp.y>=0&&lp.y+left.height<=row.height+1&&rp.y+right.height<=row.height+1;
            const layout=stacked?(left.width>=row.width-26&&right.width>=row.width-26&&rp.y>=lp.y+left.height+10):(left.width>=170&&left.width<=row.width*.42&&right.width>=row.width*.55&&left.width+right.width+57<=row.width+1&&Math.abs(lp.y-rp.y)<=1);
            report("cornell-cue-responsive-order-and-containment",inside&&layout,{stacked:stacked,row:box(row),left:box(left),right:box(right)});
            const headDivider=findChild(ws,"nexusCornellColHeadDivider");const rowDivider=findChild(ws,"nexusCornellRowDivider_0");
            const headPos=headDivider.mapToItem(card,0,0);const rowPos=rowDivider.mapToItem(card,0,0);
            report("cornell-divider-alignment",Math.abs(headPos.x-rowPos.x)<=1&&rowDivider.width>0&&rowDivider.height>0,{head:box(headDivider),row:box(rowDivider)});
          }
          if (k.kind==="movie") {
            n.saveNoteBodyMarkdown(Array(65).fill("Long viewing note: **details** and [[Fixture]].").join("\n\n")); settle();
            capture("movie-long-top");
            const flick=findChild(ws,"nexusHybridOutlinerPane");
            if (flick) { flick.contentY=Math.max(0,flick.contentHeight-flick.height); wait(120); capture("movie-long-bottom"); }
            report("long-note-scroll-reachable",Boolean(flick) && flick.contentY+flick.height>=flick.contentHeight-1,{flick:box(flick),contentHeight:flick?flick.contentHeight:0,contentY:flick?flick.contentY:0,card:box(card)});
          }
        }
        n.openCollection("places"); settle(); capture("places-base");
        console.info("VISUAL_AUDIT_DONE"); Qt.quit();
      } catch(e) { console.error("VISUAL_AUDIT_ABORT",e.message,e.stack); Qt.exit(1); }
    }
  }
  Timer { interval:500; running:true; onTriggered:tc.runAudit() }
}'''.replace('INITIAL_WIDTH',str(VIEWPORT)).replace('INITIAL_HEIGHT',str(HEIGHT)).replace('LABEL',LABEL).replace('SERVICE',str(PLUGIN/'plugins/nexus/services/NexusService.qml')).replace('WORKSPACE',str(PLUGIN/'plugins/nexus/modules/nexus/NexusWorkspace.qml')).replace('OUT',str(OUT))
    (shell/'shell.qml').write_text(qml)
    runtime=private/'runtime'; runtime.mkdir(mode=0o700)
    env=dict(os.environ,QT_QPA_PLATFORM='offscreen',QT_QUICK_BACKEND='software',XDG_RUNTIME_DIR=str(runtime),ALIS_NEXUS_DISABLE_XDG_OPEN='1',ALIS_NEXUS_HEADLESS_SERVICE_ONLY='1')
    for kind in ('config','state','cache','data'): env['XDG_'+kind.upper()+'_HOME']=str(private/kind)
    env.pop('NIRI_SOCKET',None); env.pop('HYPRLAND_INSTANCE_SIGNATURE',None)
    with private_wayland(private) as native:
        if native is None: raise SystemExit('SKIP: responsive geometry needs a private native compositor')
        if native:
            env.update({k:v for k,v in native.items() if k in ('WAYLAND_DISPLAY','NIRI_SOCKET','DISPLAY','XDG_RUNTIME_DIR')}); env['QT_QPA_PLATFORM']='wayland'
        result=run_qs(shell,env,timeout=65)
    (OUT/('audit-'+LABEL+'.log')).write_text(result.stdout)
    samples=[json.loads(x) for x in re.findall(r'VISUAL_AUDIT (\{[^\n]+\})',result.stdout)]
    receipt={'plugin':str(PLUGIN),'host':str(HOST),'scope':'Explicit source/candidate payload with actual installed host in private native compositor and temporary vault/config; rendered child containment plus Save/Escape/Cancel/reopen across seven note types. Not installed activation or Owner acceptance.','exitCode':result.returncode,'complete':'VISUAL_AUDIT_DONE' in result.stdout,'checks':samples,'viewport':{'width':VIEWPORT,'height':HEIGHT,'scale':env.get('QT_SCALE_FACTOR','1')}}
    (OUT/('audit-'+LABEL+'.json')).write_text(json.dumps(receipt,indent=2)+'\n')
    print(json.dumps(receipt,indent=2))
    print('\n'.join(x for x in result.stdout.splitlines() if 'VISUAL_AUDIT_ABORT' in x))

    if result.returncode or not receipt['complete'] or any(x['status']!='PASS' for x in samples): raise SystemExit(1)
