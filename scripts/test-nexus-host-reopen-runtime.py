#!/usr/bin/env python3
"""Measure real standalone Nexus hosts and verify warm reopen state retention.

This private native fixture measures a settled rendered workspace, not the
entire Alis process launch or physical suspend/resume on the owner's desktop.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
from integration_test_host import resolve_host_root

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--host", type=Path, default=resolve_host_root(ROOT))
parser.add_argument("--plugin", type=Path, default=ROOT)
parser.add_argument("--evidence-dir", type=Path, required=True)
parser.add_argument("--family", choices=["abyss", "waffle"], default="waffle")
args = parser.parse_args()
HOST, PLUGIN = args.host.resolve(), args.plugin.resolve()
OUT = args.evidence_dir.resolve()
OUT.mkdir(parents=True, exist_ok=True)
sys.path.insert(0, str(HOST / "scripts"))
from native_test_session import private_wayland, run_qs

with tempfile.TemporaryDirectory(prefix="alis-host-reopen-") as name:
    private = Path(name)
    shell = private / "shell"
    shell.mkdir()
    for entry in ["modules", "services", "GlobalStates.qml", "qmldir", "scripts", "defaults", "translations", "assets"]:
        (shell / entry).symlink_to(HOST / entry)
    vault = private / "Vault"
    folder = vault / "20_Notes"
    folder.mkdir(parents=True)
    for i in range(200):
        (folder / f"Fixture {i:03}.md").write_text(f"# Fixture {i}\n\nPreserved original note {i}.\n")
    originals = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in folder.glob("*.md")}
    config = json.loads((HOST / "defaults/config.json").read_text())
    config["todo"]["nexus"]["vaultPath"] = str(vault)
    config["bar"]["weather"]["enable"] = False
    config["panelFamily"] = args.family
    config["integrations"]["alisIntergration"]["nexus"] = False
    for rel in ["config/alis", "config/quickshell/alis"]:
        directory = private / rel
        directory.mkdir(parents=True)
        (directory / "config.json").write_text(json.dumps(config))
    qml = r'''import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import qs
import qs.services
import qs.modules.common
ShellRoot {
 id:root
 property var observedWindow:null
 property int frames:0
 property int ticks:0
 property real lastTick:Date.now()
 property real maxTickGap:0
 Component.onCompleted:Quickshell.watchFiles=false
 Connections {target:root.observedWindow;function onFrameSwapped(){root.frames++}}
 Timer {interval:16;running:true;repeat:true;onTriggered:{const now=Date.now();root.maxTickGap=Math.max(root.maxTickGap,now-root.lastTick);root.lastTick=now;root.ticks++}}
 Loader {id:service;source:"PLUGIN/services/NexusService.qml"}
 TestCase {
  id:tc;when:false;optional:true
  function check(name,ok,actual){console.info("HOST_CHECK",JSON.stringify({name:name,status:ok?"PASS":"FAIL",actual:actual}));if(!ok)throw Error(name)}
  function workspace(n,floating){const container=findChild(n,floating?"nexusFloatingWindow":"nexusOverlayCard");return container?findChild(container,"nexusWorkspace"):null}
  function open(n,floating,label,previous){
   root.maxTickGap=0;root.lastTick=Date.now();const begin=Date.now();
   if(floating)n.openWindow();else n.openOverlay();
   tryVerify(()=>workspace(n,floating)!==null,6000,label+" workspace exists");
   const ws=workspace(n,floating);tryVerify(()=>ws.width>100&&ws.height>100&&ws.nexus===n,2000);
   if(!floating)tryVerify(()=>ws.transitionSettled,2500,label+" reveal settled");
   tryVerify(()=>ws.Window.window&&ws.Window.window.visible,2500,label+" native window shown");
   root.observedWindow=ws.Window.window;const before=root.frames;root.observedWindow.update();
   tryVerify(()=>root.frames>before,2500,label+" native frame");
   let saved=false;check(label+"-grab-started",ws.grabToImage(image=>{saved=image.saveToFile("OUT/"+label+".png")}),{});
   tryVerify(()=>saved,2500,label+" actual frame capture");
   check(label+"-same-workspace",!previous||ws===previous,{reused:!!previous&&ws===previous});
   check(label+"-interactive",ws.visible&&n.isOpen&&ws.activeFocus,{focus:ws.activeFocus,visible:ws.visible});
   console.info("HOST_METRIC",JSON.stringify({label:label,elapsedMs:Date.now()-begin,maxUiTickGapMs:root.maxTickGap,ticks:root.ticks,frames:root.frames,width:ws.width,height:ws.height}));
   return ws;
  }
  function close(n,ws,label){n.close();wait(600);const win=ws.Window.window;check(label+"-closed",!n.isOpen&&(!win||!win.visible),{windowVisible:win?win.visible:false});check(label+"-inactive",!ws.surfaceActive,{active:ws.surfaceActive});}
  function run(){try{
   tryCompare(Config,"ready",true,5000);check("weather-offline",!Weather.enabled,{});tryCompare(service,"status",Loader.Ready,5000);
   GlobalStates.abyssPerimeterActive=false;
   const n=service.item;tryCompare(n,"hostLoaded",true,5000);
   const overlay=open(n,false,"overlay-cold",null);tryVerify(()=>n.vaultLoaded&&!n.scanBusy,6000);check("all-fixture-notes-loaded",n.stats.noteCount===200,n.stats.noteCount);
   const graph=findChild(overlay,"nexusVaultGraphCanvas");check("graph-found",!!graph,{});graph.zoomIn();const zoom=graph.zoom;
   close(n,overlay,"overlay-first");
   for(let i=0;i<3;i++){const ws=open(n,false,"overlay-warm-"+i,overlay);check("overlay-zoom-retained-"+i,findChild(ws,"nexusVaultGraphCanvas").zoom===zoom,zoom);close(n,ws,"overlay-"+i)}
   const floating=open(n,true,"floating-cold",null);n.setLeftSidebarWidth(312);close(n,floating,"floating-first");
   for(let i=0;i<2;i++){const ws=open(n,true,"floating-warm-"+i,floating);check("sidebar-setting-retained-"+i,n.leftSidebarWidth===312,n.leftSidebarWidth);close(n,ws,"floating-"+i)}
   n.openOverlay();tryVerify(()=>workspace(n,false)===overlay,2500);wait(200);check("mode-switch-reuses-overlay",workspace(n,false)===overlay&&findChild(overlay,"nexusVaultGraphCanvas").zoom===zoom,{});n.close();wait(500);
   console.info("HOST_DONE");Qt.quit();
  }catch(e){console.error("HOST_ABORT",e.message,e.stack);Qt.exit(1)}}
 }
 Timer {interval:500;running:true;onTriggered:tc.run()}
}'''.replace("PLUGIN", str(PLUGIN)).replace("OUT", str(OUT))
    (shell / "shell.qml").write_text(qml)
    with private_wayland(private) as env:
        if env is None:
            raise SystemExit("SKIP: private native compositor unavailable")
        env = dict(env, HOME=str(private), QT_QUICK_BACKEND="software", ALIS_NEXUS_DISABLE_XDG_OPEN="1")
        env.pop("ALIS_NEXUS_HEADLESS_SERVICE_ONLY", None)
        result = run_qs(shell, env, timeout=45)
    checks = [json.loads(s) for s in re.findall(r"HOST_CHECK (\{[^\n]+\})", result.stdout)]
    metrics = [json.loads(s) for s in re.findall(r"HOST_METRIC (\{[^\n]+\})", result.stdout)]
    current = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in folder.glob("*.md")}
    receipt = {"scope": "Actual standalone NexusHost overlay/floating instances, real NexusService, private Wayland and200-note fixture. Settled native requested-frame timings; no physical suspend or entire Alis cold process timing.",
               "plugin": str(PLUGIN), "host": str(HOST), "family": args.family, "exit": result.returncode,
               "complete": "HOST_DONE" in result.stdout, "checks": checks, "metrics": metrics,
               "originalNotesUnchanged": current == originals}
    (OUT / "native.json").write_text(json.dumps(receipt, indent=2) + "\n")
    (OUT / "native.log").write_text(result.stdout)
    print(json.dumps(receipt, indent=2))
    if result.returncode or not receipt["complete"] or len(metrics) != 7 or any(c["status"] != "PASS" for c in checks) or current != originals:
        raise SystemExit(1)
