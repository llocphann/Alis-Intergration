#!/usr/bin/env python3
"""Exercise actual Places cards through live palette changes in a private shell."""
import hashlib
import json
import os
from pathlib import Path
import re
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
from integration_test_host import resolve_host_root
HOST = Path(os.environ.get("ALIS_ROOT", str(resolve_host_root(ROOT))))
PLUGIN = Path(os.environ.get("ALIS_PLACES_PLUGIN", str(ROOT))).resolve()
sys.path.insert(0, str(HOST / "scripts"))
from native_test_session import private_wayland, run_qs

with tempfile.TemporaryDirectory(prefix="alis-places-theme-") as name:
    private = Path(name)
    out = Path(os.environ.get("ALIS_PLACES_EVIDENCE", str(private / "evidence")))
    out.mkdir(parents=True, exist_ok=True)
    shell = private / "shell"
    shell.mkdir()
    for entry in ("services", "modules", "GlobalStates.qml", "qmldir", "scripts", "defaults", "translations", "assets"):
        (shell / entry).symlink_to(HOST / entry)
    vault = private / "Vault"
    place = vault / "20_Personal_Life/23_Places/Tourist/Fixture.md"
    place.parent.mkdir(parents=True)
    original = "---\ntitle: Fixture Place\ntype: place\ncategory: Museum\nstatus: Visited\nlocation: Fixture City\nlatitude: 10.5\nlongitude: 106.5\nscore: 4\n---\n\nPreserved historical fixture body.\n"
    place.write_text(original)
    options = json.loads((HOST / "defaults/config.json").read_text())
    options["todo"]["nexus"]["vaultPath"] = str(vault)
    options["bar"]["weather"]["enable"] = False
    for rel in ("config/alis", "config/quickshell/alis"):
        folder = private / rel
        folder.mkdir(parents=True)
        (folder / "config.json").write_text(json.dumps(options))
    qml = r'''import QtQuick
import QtTest
import Quickshell
import qs
import qs.services
import qs.modules.common
ShellRoot {
 Component.onCompleted: Quickshell.watchFiles=false
 FloatingWindow {
  visible:true;implicitWidth:1280;implicitHeight:820
  Loader {id:svc;source:"PLUGIN/services/NexusService.qml"}
  Loader {id:workspace;anchors.fill:parent;source:"PLUGIN/modules/nexus/NexusWorkspace.qml";onLoaded:item.nexus=svc.item}
 }
 TestCase {
  id:tc;when:false;optional:true
  function check(name,pass,value){console.info("PLACES_CHECK",JSON.stringify({name:name,status:pass?"PASS":"FAIL",actual:value}));if(!pass)throw Error(name)}
  function text(item,value){if(!item||!item.visible)return null;if(item.text!==undefined&&String(item.text)===value)return item;for(const c of(item.children||[])){const f=text(c,value);if(f)return f;}return null}
  function palette(p){for(const key of Object.keys(p))Appearance.colors[key]=p[key]}
  function capture(card,label){let saved=false;const started=card.grabToImage(result=>{saved=result.saveToFile("OUT/"+label+".png")});check(label+"-capture-started",started,{});tryVerify(()=>saved,2000,"actual card grabToImage saved");check(label+"-rendered",saved,{w:card.width,h:card.height})}
  function colors(card,expected,label){
   const title=text(card,"Fixture Place"),cat=text(card,"MUSEUM"),status=text(card,"VISITED"),location=text(card,"Fixture City");
   check(label+"-fields-visible",!!title&&!!cat&&!!status&&!!location,{});
   const tests={background:String(card.color)===expected.colLayer1,border:String(card.border.color)===expected.colLayer0Border,
    categoryBg:String(cat.parent.color)===expected.colPrimary,categoryText:String(cat.color)===expected.colOnPrimary,
    statusBorder:String(status.parent.border.color)===expected.colPrimary,statusText:String(status.color)===expected.colPrimary,
    title:String(title.color)===expected.colOnLayer1,location:String(location.color)===expected.colSubtext};
   check(label+"-all-palette-bindings",Object.values(tests).every(Boolean),tests);capture(card,label);
  }
  function run(){try{
   tryCompare(Config,"ready",true,6000);check("weather-offline",Weather.enabled===false,Config.filePath);
   tryCompare(svc,"status",Loader.Ready,6000);tryCompare(workspace,"status",Loader.Ready,6000);
   const n=svc.item,ws=workspace.item;ws.nexus=n;n.open();tryCompare(n,"vaultLoaded",true,6000,"vault loads: "+n.errorMessage);tryVerify(()=>!n.scanBusy,6000);
   n.openCollection("places");tryVerify(()=>(n.collections?.places?.length??0)===1,6000,"one persisted Place");
   const view=findChild(ws,"nexusCollectionView");tryVerify(()=>view.visible,2000);
   const card=findChild(ws,"nexusPlaceBaseCard_0");tryVerify(()=>card&&card.visible&&card.width>100,3000);
   mouseMove(ws,ws.width-1,ws.height-1);wait(200);
   const dark={colPrimary:"#22bb88",colOnPrimary:"#102030",colTertiary:"#d4a4e4",colLayer0:"#101820",colLayer1:"#203040",colLayer2:"#304050",colOnLayer0:"#f0f1f2",colOnLayer1:"#e1e2e3",colSubtext:"#a1a2a3",colLayer0Border:"#718293"};
   const light={colPrimary:"#883355",colOnPrimary:"#fff1e2",colTertiary:"#375a7b",colLayer0:"#f1f2f3",colLayer1:"#e4e5e6",colLayer2:"#d7d8d9",colOnLayer0:"#111213",colOnLayer1:"#242526",colSubtext:"#575859",colLayer0Border:"#6a7b8c"};
   const identity=card;palette(dark);tryVerify(()=>ws._settledPrimary===dark.colPrimary,2500);wait(200);colors(card,dark,"dark");
   palette(light);tryVerify(()=>ws._settledPrimary===light.colPrimary,2500);wait(200);check("same-card-live-transition",card===identity&&findChild(ws,"nexusPlaceBaseCard_0")===identity,{});colors(card,light,"light");
   const frozen=String(card.color);GlobalStates.wallpaperLauncherOpen=true;palette(dark);wait(250);check("paused-palette-keeps-card",String(card.color)===frozen,{color:String(card.color)});
   GlobalStates.wallpaperLauncherOpen=false;tryVerify(()=>ws._settledPrimary===dark.colPrimary,2500);wait(150);colors(card,dark,"resumed");
   mouseMove(card,card.width/2,card.height/2);wait(180);check("hover-border-reacts",String(card.border.color)===dark.colPrimary,String(card.border.color));
   let parent=card.parent;while(parent&&parent.showBack===undefined)parent=parent.parent;
   check("flip-contract-present",!!parent,{});parent.flipped=true;mouseMove(ws,ws.width-1,ws.height-1);wait(150);check("back-face-visible",!!text(card,"PLACE DOSSIER"),{});
   palette(light);tryVerify(()=>ws._settledPrimary===light.colPrimary,2500);wait(180);const heading=text(card,"PLACE DOSSIER");check("back-face-live-palette",String(heading.color)===light.colPrimary,String(heading.color));capture(card,"back-light");
   parent.flipped=false;wait(150);check("flip-retains-record",!!text(card,"Fixture Place")&&n.collections.places.length===1,{});
   check("modern-coordinate-fields-rendered",!!text(card,"10.5, 106.5"),{});
   const cases=[{name:"modern-zero",data:{hasCoordinates:true,lat:0,lon:0},expected:"0, 0"},{name:"modern-equator",data:{hasCoordinates:true,lat:0,lon:106.5},expected:"0, 106.5"},{name:"legacy-zero",data:{latitude:"0",longitude:"106.5"},expected:"0, 106.5"},{name:"legacy-prepatch",data:{latitude:10.5,longitude:106.5},expected:"10.5, 106.5"},{name:"missing-flag",data:{hasCoordinates:false,lat:0,lon:0},expected:""},{name:"missing",data:{},expected:""},{name:"malformed",data:{latitude:"invalid",longitude:""},expected:""}];
   for(const c of cases)check("coordinate-compat-"+c.name,view._placeCoordinates(c.data)===c.expected,view._placeCoordinates(c.data));
   parent.flipped=true;wait(120);check("back-coordinate-rendered",!!text(card,"10.5, 106.5"),{});
   console.info("PLACES_DONE");Qt.quit();
  }catch(error){console.error("PLACES_ABORT",error.message,error.stack,"themeState",workspace.item?JSON.stringify({primary:workspace.item._settledPrimary,live:String(Appearance.colors.colPrimary),active:workspace.item.surfaceActive,preview:MaterialThemeLoader.previewActive,selector:GlobalStates.wallpaperSelectorOpen}):"missing");Qt.exit(1)}}
 }
 Timer {interval:600;running:true;onTriggered:tc.run()}
}'''.replace("PLUGIN", str(PLUGIN)).replace("OUT", str(out))
    (shell / "shell.qml").write_text(qml)
    with private_wayland(private) as env:
        if env is None:
            raise SystemExit("SKIP: private native compositor unavailable")
        env = dict(env, QT_QUICK_BACKEND="software", ALIS_NEXUS_HEADLESS_SERVICE_ONLY="1", ALIS_NEXUS_DISABLE_XDG_OPEN="1")
        result = run_qs(shell, env, timeout=25)
    checks = [json.loads(s) for s in re.findall(r"PLACES_CHECK (\{[^\n]+\})", result.stdout)]
    receipt = {"scope": "Actual Places collection card in private native Wayland; real NexusService and sanitized persisted fixture, no provider/weather network or real vault writes.",
               "plugin": str(PLUGIN), "host": str(HOST), "workspaceSha256": hashlib.sha256((PLUGIN / "modules/nexus/NexusWorkspace.qml").read_bytes()).hexdigest(),
               "exit": result.returncode, "complete": "PLACES_DONE" in result.stdout, "checks": checks,
               "fixtureBytesUnchanged": place.read_text() == original}
    (out / "native.json").write_text(json.dumps(receipt, indent=2) + "\n")
    (out / "native.log").write_text(result.stdout)
    print(json.dumps(receipt, indent=2))
    if result.returncode or not receipt["complete"] or not checks or any(c["status"] != "PASS" for c in checks) or not receipt["fixtureBytesUnchanged"]:
        raise SystemExit(1)
