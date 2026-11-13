#!/usr/bin/env python3
"""Native regression for queued paints and dirty data across pause/resume."""
from pathlib import Path
import os, sys, json, re, tempfile
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'))
from integration_test_host import resolve_host_root
HOST=Path(os.environ.get('ALIS_GRAPH_HOST',str(resolve_host_root(ROOT))))
sys.path.insert(0,str(HOST/'scripts'))
from native_test_session import private_wayland,run_qs
GRAPH=Path(os.environ.get('GRAPH_FILE',str(ROOT/'modules/nexus/NexusGlobeWidget.qml')))
LABEL=os.environ.get('FREEZE_LABEL','result')
with tempfile.TemporaryDirectory(prefix='alis-freeze-') as name:
 p=Path(name)
 OUT=Path(os.environ.get('ALIS_GRAPH_EVIDENCE_DIR',str(p/'evidence')));OUT.mkdir(parents=True,exist_ok=True)
 for item in ['services','modules','GlobalStates.qml','qmldir','scripts','defaults','translations','assets']:(p/item).symlink_to(HOST/item)
 qml='''import QtQuick
import QtTest
import Quickshell
ShellRoot {
 Component.onCompleted: Quickshell.watchFiles=false
 QtObject {
  id:owner
  property var nexus:({isOpen:true})
  property bool transitionSettled:true
  property bool surfaceActive:true
  property string themeSignature:"initial"
  property string _settledPrimary:"#22bb88"
  property string _settledOnLayer1:"#eeeeee"
  property string _settledSubtext:"#aaaaaa"
  property string _settledBorder:"#333333"
  property string _settledLayer1:"#111111"
 }
 FloatingWindow {
  visible:true;implicitWidth:700;implicitHeight:550
  Loader {id:loader;anchors.fill:parent;source:"GRAPH";onLoaded:{item.workspace=owner;item.autoRotate=false;item.places=tc.data(0)}}
 }
 TestCase {
  id:tc;when:false;optional:true
  function data(offset) {return [{title:"Alpha",lon:106+offset,lat:10},{title:"Beta",lon:108-offset,lat:16}]}
  function sample(name,pass,before,after){console.info("FREEZE_CHECK",JSON.stringify({name:name,status:pass?"PASS":"FAIL",before:before,after:after}))}
  function run() {
   try {
    tryCompare(loader,"status",Loader.Ready,5000); const g=loader.item;
    tryVerify(()=>g.paintCount>0,5000);wait(100);
    let before=g.paintCount;
    g.resetView();owner.surfaceActive=false;
    wait(100);sample("queued-frame-does-not-paint-after-pause",g.paintCount===before,before,g.paintCount);
    before=g.paintCount;owner.surfaceActive=true;
    tryVerify(()=>g.paintCount>before,1500);sample("queued-frame-redrawn-on-resume",g.paintCount>before,before,g.paintCount);
    wait(100);owner.surfaceActive=false;before=g.paintCount;
    g.places=data(.1);g.resetView();g.resetView();
    wait(100);sample("paused-same-count-data-and-reset-no-paint",g.paintCount===before,before,g.paintCount);
    before=g.paintCount;owner.surfaceActive=true;
    tryVerify(()=>g.paintCount>before,1500);sample("same-count-data-redrawn-on-resume",g.paintCount>before,before,g.paintCount);
    wait(100);before=g.paintCount;g.focusCluster({lon:107,lat:12});tryVerify(()=>g.paintCount>before,1000);
    sample("active-focus-still-repaints",g.paintCount>before,before,g.paintCount);
    wait(100);owner.nexus=({isOpen:false});before=g.paintCount;g.places=data(.05);g.resetView();
    wait(100);sample("closed-host-no-paint",g.paintCount===before,before,g.paintCount);
    before=g.paintCount;owner.nexus=({isOpen:true});tryVerify(()=>g.paintCount>before,1500);
    sample("closed-host-data-redrawn-on-open",g.paintCount>before,before,g.paintCount);
    wait(100);g.visible=false;before=g.paintCount;g.places=data(.08);g.resetView();
    wait(100);sample("hidden-globe-no-paint",g.paintCount===before,before,g.paintCount);
    before=g.paintCount;g.visible=true;tryVerify(()=>g.paintCount>before,1500);
    sample("hidden-data-redrawn-on-show",g.paintCount>before,before,g.paintCount);
    console.info("FREEZE_DONE");Qt.quit();
   }catch(e){console.error("FREEZE_ABORT",e.message);Qt.exit(1)}
  }
 }
 Timer {interval:500;running:true;onTriggered:tc.run()}
}'''.replace('GRAPH',str(GRAPH))
 (p/'shell.qml').write_text(qml)
 with private_wayland(p) as env:
  if env is None:raise SystemExit('SKIP no private compositor')
  result=run_qs(p,env,timeout=12)
 checks=[json.loads(x) for x in re.findall(r'FREEZE_CHECK (\{[^\n]+\})',result.stdout)]
 receipt={'scope':'Actual installed common host, isolated native globe with controlled owner-active state; no weather/network/vault operations. Nine native behavior checks; source or explicit candidate globe and isolated host.','graph':str(GRAPH),'exit':result.returncode,'complete':'FREEZE_DONE' in result.stdout,'checks':checks}
 (OUT/(LABEL+'.json')).write_text(json.dumps(receipt,indent=2)+'\n');(OUT/(LABEL+'.log')).write_text(result.stdout)
 print(json.dumps(receipt,indent=2))

 if result.returncode or not receipt['complete'] or len(checks)!=9 or any(x['status']!='PASS' for x in checks):raise SystemExit(1)
