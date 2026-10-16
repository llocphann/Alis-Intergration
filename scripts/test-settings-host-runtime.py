#!/usr/bin/env python3
"""Real extracted workers with scoped vault data and injected hardware helpers."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

from integration_test_host import resolve_host_root
ROOT = Path(__file__).resolve().parents[1]
HOST = resolve_host_root(ROOT)
sys.path.insert(0, str(HOST / "scripts"))
from native_test_session import run_qs, private_wayland
spec = importlib.util.spec_from_file_location("installer", ROOT / "scripts/install.py")
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)

with tempfile.TemporaryDirectory(prefix="hadalird-native-") as name:
    private = Path(name)
    shell = private / "shell"
    shell.mkdir()
    for entry in ("services","modules","GlobalStates.qml","qmldir","scripts","defaults","translations","assets"):
        (shell / entry).symlink_to(HOST / entry)
    calls = private / "helper-calls.jsonl"
    helper = private / "fixture-helper"
    helper.write_text("#!/usr/bin/python3\nimport json,sys\nfrom pathlib import Path\n"
                      + "with Path("+repr(str(calls))+").open('a') as f:f.write(json.dumps(sys.argv[1:])+chr(10))\n"
                      + "print(json.dumps({'schema':1,'available':True,'supported':True,'configAvailable':True,'enabled':True,'tlpVersion':'1.11.0','active':False,'managed':False,'stateKnown':False,'statusReason':'fixture','reason':'fixture','effective':{'CPU_BOOST_ON_AC':'1','CPU_BOOST_ON_BAT':'0'},'managed':{}}))\n")
    helper.chmod(0o755)
    package = private / "data/hadalird/releases/fixture"
    package.parent.mkdir(parents=True)
    installer.assemble(ROOT, package, "f"*40)
    (private / "data/hadalird/current").symlink_to("releases/fixture")
    vault = private / "Vault có spaces"
    (vault / ".obsidian").mkdir(parents=True)
    (vault / ".obsidian/appearance.json").write_text(json.dumps({"cssTheme":"Fixture","enabledCssSnippets":[]}))
    managed = vault / "Managed.md"
    managed.write_text("# Todo\n<!-- hadalis:todo:start -->\n- [ ] first\n<!-- hadalis:todo:end -->\n")
    (vault / "Daily.md").write_text("## Tasks\n- [ ] first daily\n## Notes\n")
    config = private / "config/illogical-impulse"
    config.mkdir(parents=True)
    options = json.loads((HOST / "defaults/config.json").read_text())
    options["integrations"]["hadalird"] = {key:False for key in ("tlp","thinkfan","obsidian")}
    options["battery"]["chargeLimit"]["enable"] = False
    options["powerProfiles"]["fanControl"]["enabled"] = False
    options["integrations"]["obsidian"]["autoTheme"] = False
    options["todo"]["backend"] = "internal"
    options["todo"]["obsidian"]["vaultPath"] = str(vault)
    (config / "config.json").write_text(json.dumps(options))
    (shell / "shell.qml").write_text(r"""
import QtQuick
import QtTest
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.settings
import qs.modules.waffle.settings as WSettings
ShellRoot {
 id:root
 readonly property var waffle:waffleHost.item
 Component.onCompleted:Quickshell.watchFiles=false
 FloatingWindow {
  id:window;visible:true;implicitWidth:1100;implicitHeight:900;color:"#111820"
  IntegrationsConfig {id:integrations;anchors.fill:parent}
  Loader {id:waffleHost;anchors.fill:parent;source:Quickshell.shellPath("modules/waffle/settings/pages/WTlpPage.qml");onLoaded:item.visible=false}
  ThinkfanSettings {id:fanUi;width:800;visible:false}
  TlpPowerSettings {id:classic;width:800;visible:false}
  TlpSettingRow {id:classicRow;width:800;visible:false;definition:({key:"CPU_BOOST_ON_AC",type:"select",profile:"AC",options:["0","1"]})}
  WSettings.WTlpSettingRow {id:waffleRow;width:800;visible:false;definition:classicRow.definition}
 }
 TestCase {
  id:test;when:false;optional:true
  function check(v,m){if(!v)throw new Error(m)}
  function ownedRow(host,name){const item=findChild(host,name);check(item!==null,"missing optional row "+name);return item}
  function runChecks(){try{
   tryCompare(Config,"ready",true,4000);tryCompare(Hadalird,"available",true,4000)
   tryCompare(waffleHost,"status",Loader.Ready,2000)
   check(Hadalird.session===null,"default-off package started workers")
   check(findChild(integrations,"hadalirdObsidianTodoSettings")===null,"disabled Obsidian rendered owned controls")
   const preferences=JSON.stringify(Config.options)
   check(classicRow.implicitHeight===0 && waffleRow.implicitHeight===0,"disabled rows started an editor")
   waffle.visible=true;wait(100);waffle.visible=false
   check(JSON.stringify(Config.options)===preferences,"disabled settings mutated preferences")
   Config.setNestedValue("integrations.hadalird.obsidian",true)
   tryVerify(()=>Hadalird.session!==null,2000)
   const session=Hadalird.session
   session.batteryHelperPath=Quickshell.env("FIXTURE_HELPER");session.fanHelperPath=Quickshell.env("FIXTURE_HELPER")
   tryVerify(()=>findChild(integrations,"hadalirdObsidianTodoSettings")!==null,3000)
   const pattern=findChild(integrations,"obsidianTodoNotePattern"),heading=findChild(integrations,"obsidianTodoHeading"),folder=findChild(integrations,"obsidianQuickNoteFolder")
   check(pattern && heading && folder,"owned Todo/capture editors missing")
   pattern.text=" /Capture/My Tasks.md/ ";pattern.editingFinished()
   heading.text=" New tasks ";heading.editingFinished();folder.text=" Capture/Fleeting ";folder.editingFinished()
   tryCompare(Config.options.todo.obsidian.dailyNote,"folder","Capture",1000)
   check(Config.options.todo.obsidian.dailyNote.format==="My Tasks.md" && Config.options.todo.obsidian.dailyNote.plannerHeading==="New tasks","extracted task fields lost parsing/save behavior")
   check(Config.options.notes.zettelkasten.folder==="Capture/Fleeting","extracted capture field did not save")
   integrations.activateSettingsSearchSection("Calendar Sync")
   tryVerify(()=>findChild(integrations,"hadalirdObsidianTodoSettings")===null,1000)
   integrations.activateSettingsSearchSection("To-do & Quick Notes")
   tryVerify(()=>findChild(integrations,"obsidianTodoNotePattern")!==null,2000)
   check(findChild(integrations,"obsidianTodoNotePattern").text==="Capture/My Tasks.md","reopening task fields lost saved state")
   Config.setNestedValue("integrations.hadalird.tlp",true)
   tryCompare(TlpSettingsService,"schemaLoaded",true,3000)
   tryCompare(TlpSettingsService,"statusReason","fixture",3000)
   tryCompare(TlpSettingsService,"busy",false,2000)
   let c=ownedRow(classicRow,"hadalirdTlpSettingRow"),w=ownedRow(waffleRow,"hadalirdWaffleTlpSettingRow")
   check(c.definition.key==="CPU_BOOST_ON_AC" && w.definition.key===c.definition.key,"required row definition lost at load")
   classicRow.definition=({key:"CPU_BOOST_ON_BAT",type:"select",profile:"BAT",options:["0","1"]})
   tryCompare(c,"settingKey","CPU_BOOST_ON_BAT",1000);tryCompare(w,"settingKey","CPU_BOOST_ON_BAT",1000)
   c.setValue("1");check(TlpSettingsService.pendingValues.CPU_BOOST_ON_BAT?.value==="1","Classic edit did not stage")
   w.unsetValue();check(TlpSettingsService.pendingValues.CPU_BOOST_ON_BAT===undefined,"Waffle unset did not inherit")
   integrations.visible=false;waffle.visible=true
   tryVerify(()=>findChild(waffle,"hadalirdWaffleTlpSettings")!==null,3000)
   const contents=findChild(waffle,"hadalirdWaffleTlpSettings")
   waffle.selectedCategoryIndex=2;tryCompare(contents,"selectedCategoryIndex",2,1000)
   contents.filterText="CPU";tryCompare(waffle,"filterText","CPU",1000)
   waffle.visible=false
   tryVerify(()=>findChild(waffle,"hadalirdWaffleTlpSettings")===null,1000)
   waffle.visible=true
   tryVerify(()=>findChild(waffle,"hadalirdWaffleTlpSettings")!==null,3000)
   check(findChild(waffle,"hadalirdWaffleTlpSettings").selectedCategoryIndex===2 && findChild(waffle,"hadalirdWaffleTlpSettings").filterText==="CPU","Waffle reopen lost category/filter")
   Config.setNestedValue("integrations.hadalird.thinkfan",true)
   fanUi.visible=true
   tryVerify(()=>findChild(fanUi,"hadalirdThinkfanSettings")!==null,2000)
   const fanLevel=findChild(fanUi,"balancedFanLevel")
   check(fanLevel && fanLevel.from===0 && fanLevel.to===7,"owned fan editor lost safe bounds")
   fanLevel.value=2
   tryCompare(Config.options.powerProfiles.fanControl,"balanced",2,1000)
   check(Config.options.powerProfiles.fanControl.enabled===false,"editing a saved level enabled hardware policy")
   fanUi.visible=false
   tryVerify(()=>findChild(fanUi,"hadalirdThinkfanSettings")===null,1000)
   check(Hadalird.session===session,"UI routes rebuilt shared workers")
   // Pending/editor notifications immediately followed by unload must be safe.
   TlpSettingsService.discard()
   Config.setNestedValues({"integrations.hadalird.tlp":false,"integrations.hadalird.obsidian":false,"integrations.hadalird.thinkfan":false})
   tryVerify(()=>Hadalird.session===null,2000);wait(150)
   check(findChild(classicRow,"hadalirdTlpSettingRow")===null && findChild(waffleRow,"hadalirdWaffleTlpSettingRow")===null,"disabled rows survived")
   check(findChild(waffle,"hadalirdWaffleTlpSettings")===null,"disabled Waffle page survived")
   check(Config.options.todo.obsidian.dailyNote.folder==="Capture" && Config.options.notes.zettelkasten.folder==="Capture/Fleeting","unload lost saved settings")
   console.info("HADALIRD_SETTINGS_HOST_PASS")
  }catch(e){console.error("HADALIRD_SETTINGS_HOST_FAIL",e.message,e.stack)}Qt.quit()}
 }
 Timer {interval:100;running:true;onTriggered:test.runChecks()}
}
""")
    runtime = private / "runtime"
    runtime.mkdir(mode=0o700)
    env = dict(os.environ,QT_QPA_PLATFORM="offscreen",XDG_RUNTIME_DIR=str(runtime),
               XDG_CONFIG_HOME=str(private/"config"),XDG_STATE_HOME=str(private/"state"),
               XDG_CACHE_HOME=str(private/"cache"),XDG_DATA_HOME=str(private/"data"),FIXTURE_VAULT=str(vault),FIXTURE_HELPER=str(helper))
    env.pop("NIRI_SOCKET",None)
    env.pop("HYPRLAND_INSTANCE_SIGNATURE",None)
    with private_wayland(private) as wayland_env:
        if wayland_env is None: raise SystemExit("Private Niri is required for actual integration settings")
        env.update({key:value for key,value in wayland_env.items() if key in ("WAYLAND_DISPLAY","NIRI_SOCKET","DISPLAY","XDG_RUNTIME_DIR")})
        env["QT_QPA_PLATFORM"]="wayland"
        result = run_qs(shell,env,timeout=50)
    if result.returncode or "HADALIRD_SETTINGS_HOST_PASS" not in result.stdout or any(token in result.stdout for token in ("HADALIRD_SETTINGS_HOST_FAIL","TypeError:","ReferenceError:","Binding loop","Unable to assign","Failed to load configuration","Invalid property assignment","invalid context")):
        print(result.stdout)
        raise SystemExit(1)
    invocations = [json.loads(line) for line in calls.read_text().splitlines()]
    assert invocations and all(argv in (["--status"],["--config-status"]) for argv in invocations),invocations
print("HADALIRD_SETTINGS_HOST_PASS Classic/Waffle rows, owned Todo/capture fields, routes, reopen and disable; injected status-only helpers")
