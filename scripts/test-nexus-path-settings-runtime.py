#!/usr/bin/env python3
"""Real consolidated path controls preserve the shared vault configuration."""
import json,os,sys,tempfile
from pathlib import Path
from integration_test_host import resolve_host_root
ROOT=Path(__file__).resolve().parents[1]
HOST = resolve_host_root(ROOT)
sys.path.insert(0,str(HOST/"scripts"))
from native_test_session import private_wayland,run_qs
with tempfile.TemporaryDirectory(prefix="alis-nexus-path-ui-") as name:
 folder=Path(name)
 for entry in ["modules","services","GlobalStates.qml","qmldir","assets","scripts","defaults","translations"]:(folder/entry).symlink_to(HOST/entry)
 (folder/"shell.qml").write_text(r'''
import QtQuick
import QtTest
import Quickshell
import qs.services
import qs.modules.common
ShellRoot {
 Component.onCompleted:Quickshell.watchFiles=false
 FloatingWindow {
  id:window;visible:true;implicitWidth:1120;implicitHeight:850;color:"#111820"
  Loader {id:page;anchors.fill:parent;source:Quickshell.env("ALIS_INTERGRATION_SETTINGS")}
 }
 TestCase {
  id:test;when:false;optional:true
  function check(v,m){if(!v)throw new Error(m)}
  function hasText(item,needle){
   if(!item)return false
   if(typeof item.text==="string"&&item.text.includes(needle))return true
   for(const c of item.children??[])if(hasText(c,needle))return true
   return false
  }
  function count(item,name){let n=item.objectName===name?1:0;for(const c of item.children??[])n+=count(c,name);return n}
  function runChecks(){try{
   tryCompare(Config,"ready",true,4000);tryCompare(page,"status",Loader.Ready,5000);wait(150)
   const vault=findChild(page.item,"nexusVaultPath")
   const browse=findChild(page.item,"nexusVaultBrowseButton")
   check(vault && browse,"shared vault path or Browse control missing")
   check(count(page.item,"nexusVaultPath")===1,"vault control duplicated")
   check(findChild(page.item,"nexusVaultConfigPath")===null,"obsolete nexusVaultConfigPath should be removed")
   check(findChild(page.item,"nexusApplicationConfigPath")===null,"obsolete nexusApplicationConfigPath should be removed")
   check(!hasText(page.item,"Follow Alis colors"),"obsolete Follow Alis colors auto-theme control should be removed")
   check(findChild(page.item,"openNexusOverlayButton")!==null,"openNexusOverlayButton missing")
   check(findChild(page.item,"nexusOverlayModeSwitch")!==null,"nexusOverlayModeSwitch missing")
   check(findChild(page.item,"nexusVimModeSwitch")!==null,"nexusVimModeSwitch missing")
   check(findChild(page.item,"openNexusShortcutsTabButton")!==null,"openNexusShortcutsTabButton missing")
   Config.setNestedValues({"notes.zettelkasten.vaultPath":"legacy-vault","todo.nexus.vaultPath":""})
   vault.text="  new shared vault  ";vault.editingFinished();wait(80)
   check(Config.options.todo.nexus.vaultPath==="new shared vault" && Config.options.notes.zettelkasten.vaultPath==="" && Todo.sharedVaultPath==="new shared vault","new field lost canonical shared vault migration")
   vault.text="";vault.editingFinished();wait(60)
   check(Todo.sharedVaultPath==="","clearing shared field resurrected legacy vault "+JSON.stringify({canonical:Config.options.todo.nexus.vaultPath,legacy:Config.options.notes.zettelkasten.vaultPath,field:vault.text}))
   console.info("NEXUS_PATH_UI_PASS single vault/browse control, obsolete obsidian theming removed, canonical migration and clear")
  }catch(e){console.error("NEXUS_PATH_UI_FAIL",e.message,e.stack)}Qt.quit()}
 }
 Timer {interval:100;running:true;onTriggered:test.runChecks()}
}
''')
 with private_wayland(folder) as env:
  if env is None:raise SystemExit("SKIP: Nexus settings requires private Niri")
  cfg=folder/"config/alis";cfg.mkdir(parents=True,exist_ok=True)
  data=json.loads((HOST/"defaults/config.json").read_text());data["panelFamily"]="abyss";data["integrations"]["nexus"]["autoTheme"]=False
  (cfg/"config.json").write_text(json.dumps(data));env["QT_QUICK_BACKEND"]="software"
  env["ALIS_INTERGRATION_SETTINGS"]=(ROOT/"plugins/nexus/modules/settings/NexusThemeSettings.qml").as_uri()
  result=run_qs(folder,env,25)
  if result.returncode or "NEXUS_PATH_UI_PASS" not in result.stdout or any(x in result.stdout for x in ["NEXUS_PATH_UI_FAIL","ReferenceError:","TypeError:","Binding loop","Failed to load configuration"]):print(result.stdout);raise SystemExit(1)
  print("NEXUS_PATH_UI_PASS ordered paths, one shared vault field, legacy migration, clear and independent config saves")
