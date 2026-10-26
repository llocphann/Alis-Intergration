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

with tempfile.TemporaryDirectory(prefix="alis-intergration-native-") as name:
    private = Path(name)
    shell = private / "shell"
    shell.mkdir()
    for entry in ("services","modules","GlobalStates.qml","qmldir","scripts","defaults","translations","assets"):
        (shell / entry).symlink_to(HOST / entry)
    calls = private / "helper-calls.jsonl"
    helper = private / "fixture-helper"
    helper.write_text("#!/usr/bin/python3\nimport json,sys\nfrom pathlib import Path\n"
                      + "with Path("+repr(str(calls))+").open('a') as f:f.write(json.dumps(sys.argv[1:])+chr(10))\n"
                      + "print(json.dumps({'schema':1,'available':False,'supported':False,'configAvailable':False,'enabled':False,'active':False,'managed':False,'stateKnown':False,'statusReason':'fixture','reason':'fixture','effective':{},'managedValues':{}}))\n")
    helper.chmod(0o755)
    package = private / "data/alis-intergration/releases/fixture"
    package.parent.mkdir(parents=True)
    installer.assemble(ROOT, package, "f"*40)
    (private / "data/alis-intergration/current").symlink_to("releases/fixture")
    vault = private / "Vault có spaces"
    (vault / ".obsidian").mkdir(parents=True)
    (vault / ".obsidian/appearance.json").write_text(json.dumps({"cssTheme":"Fixture","enabledCssSnippets":[]}))
    managed = vault / "Managed.md"
    managed.write_text("# Todo\n<!-- alis:todo:start -->\n- [ ] first\n<!-- alis:todo:end -->\n")
    (vault / "Daily.md").write_text("## Tasks\n- [ ] first daily\n## Notes\n")
    config = private / "config/alis"
    config.mkdir(parents=True)
    options = json.loads((HOST / "defaults/config.json").read_text())
    options["integrations"]["alisIntergration"] = {key:False for key in ("tlp","thinkfan","obsidian")}
    options["battery"]["chargeLimit"]["enable"] = False
    options["powerProfiles"]["fanControl"]["enabled"] = False
    options["integrations"]["obsidian"]["autoTheme"] = False
    options["todo"]["backend"] = "internal"
    options["todo"]["obsidian"]["vaultPath"] = str(vault)
    (config / "config.json").write_text(json.dumps(options))
    (shell / "shell.qml").write_text('''
import QtQuick
import QtTest
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.settings
ShellRoot {
 id:root
 ObsidianTodoBackend {id:managed;active:true;vaultPath:Quickshell.env("FIXTURE_VAULT");notePath:"Managed.md"}
 DailyNoteTodoBackend {id:daily;active:true;vaultPath:Quickshell.env("FIXTURE_VAULT");folder:"";noteFormat:"Daily.md"}
 TlpPowerSettings {id:tlpUi;width:700;visible:false}
 ObsidianThemeSettings {id:obsidianUi;width:700;visible:false}
 TestCase {
  id:test;when:false;optional:true
  function check(value,message){if(!value)throw new Error(message)}
  function runChecks(){try{
   tryCompare(Config,"ready",true,4000)
   tryCompare(AlisIntergration,"available",true,4000)
   check(AlisIntergration.session===null,"package enabled itself")
   Config.setNestedValue("integrations.alisIntergration.obsidian",true)
   tryVerify(()=>AlisIntergration.session!==null,2000)
   const session=AlisIntergration.session
   session.batteryHelperPath=Quickshell.env("FIXTURE_HELPER")
   session.fanHelperPath=Quickshell.env("FIXTURE_HELPER")
   Config.setNestedValues({"integrations.alisIntergration.tlp":true,"integrations.alisIntergration.thinkfan":true})
   tryCompare(TlpSettingsService,"schemaLoaded",true,3000)
   check(TlpSettingsService.categories.length>0,"external schema URI did not resolve")
   check(TlpSettingsService._array(TlpSettingsService.categories).length>0,"shared value adapter failed")
   tryCompare(TlpSettingsService,"statusReason","fixture",3000)
   tryCompare(ThinkFanService,"statusReason","fixture",3000)
   tryCompare(managed,"ready",true,4000)
   tryCompare(daily,"ready",true,4000)
   check(managed.list.length===1 && daily.list.length===1,"external Todo scan lost tasks")
   check(managed.addTask("added through optional host"),"managed task was not queued")
   tryVerify(()=>managed.list.length===2 && !managed.busy,4000)
   check(daily.addTask("added daily","",""),"daily task was not queued")
   tryVerify(()=>daily.list.length===2 && !daily.busy,4000)
   ObsidianTheme.inspect()
   tryVerify(()=>ObsidianTheme.info.activeTheme==="Fixture" && !ObsidianTheme.busy,4000)
   check(ObsidianTheme.error==="","external inspection failed")
   Config.setNestedValue("integrations.obsidian.autoTheme",true)
   tryVerify(()=>ObsidianTheme.info.enabled===true && !ObsidianTheme.busy,4000)
   check(ObsidianTheme.info.activeTheme==="Fixture","optional theming changed the selected theme")
   ObsidianTheme.restore()
   tryVerify(()=>!ObsidianTheme.enabled && ObsidianTheme.info.enabled===false && !ObsidianTheme.busy,4000)
   check(Zettelkasten.capture("Fixture note","Only synthetic content"),"capture was not queued")
   tryVerify(()=>Zettelkasten.lastCreatedFullPath.length>0 && !Zettelkasten.busy,4000)
   check(Zettelkasten.lastCreatedFullPath.startsWith(Quickshell.env("FIXTURE_VAULT")+"/"),"capture escaped its synthetic vault")
   check(AlisIntergration.session===session,"actions rebuilt the shared session")
   Config.setNestedValues({"integrations.alisIntergration.tlp":false,"integrations.alisIntergration.thinkfan":false,"integrations.alisIntergration.obsidian":false})
   tryVerify(()=>AlisIntergration.session===null && managed.implementation===null && daily.implementation===null,2000)
   check(!managed.ready && !daily.ready && !TlpService.available && !ThinkFanService.available,"unload retained a worker")
   console.info("ALIS_INTERGRATION_REAL_HOST_PASS")
  }catch(error){console.error("ALIS_INTERGRATION_REAL_HOST_FAIL",error.message,error.stack,JSON.stringify({obsidian:AlisIntergration.obsidianEnabled,managed:{active:managed.active,configured:managed.configured,ready:managed.ready,error:managed.errorMessage,implementation:String(managed.implementation),source:AlisIntergration.backendSource("managed"),vault:managed.implementation?.vaultPath,note:managed.implementation?.notePath,helper:managed.implementation?.helperPath,busy:managed.implementation?.busy,list:managed.implementation?.list,capabilityBusy:managed.implementation?.capabilityBusy,queued:managed.implementation?._refreshQueued},daily:{ready:daily.ready,error:daily.errorMessage,implementation:String(daily.implementation)}}))}Qt.quit()}
 }
 Timer {interval:100;running:true;onTriggered:test.runChecks()}
}
''')
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
        result = run_qs(shell,env,timeout=35)
    if result.returncode or "ALIS_INTERGRATION_REAL_HOST_PASS" not in result.stdout or any(token in result.stdout for token in ("ALIS_INTERGRATION_REAL_HOST_FAIL","TypeError:","ReferenceError:","Binding loop","Unable to assign","Failed to load configuration")):
        print(result.stdout)
        raise SystemExit(1)
    assert "added through optional host" in managed.read_text()
    assert "added daily" in (vault/"Daily.md").read_text()
    assert json.loads((vault/".obsidian/appearance.json").read_text())["cssTheme"]=="Fixture"
    invocations = [json.loads(line) for line in calls.read_text().splitlines()]
    assert invocations and all(argv in (["--status"],["--config-status"]) for argv in invocations),invocations
print("ALIS_INTERGRATION_REAL_HOST_PASS real external workers/settings/URI, synthetic vault receipts, only injected status helpers, disable/unload")
