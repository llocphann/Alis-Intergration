#!/usr/bin/env python3
"""Real consolidated path controls preserve the shared vault configuration."""
import json,os,sys,tempfile
from pathlib import Path
from integration_test_host import resolve_host_root
ROOT=Path(__file__).resolve().parents[1]
HOST = resolve_host_root(ROOT)
sys.path.insert(0,str(HOST/"scripts"))
from native_test_session import private_wayland,run_qs
with tempfile.TemporaryDirectory(prefix="hadalis-obsidian-path-ui-") as name:
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
  Loader {id:page;anchors.fill:parent;source:Quickshell.env("HADALIRD_SETTINGS")}
 }
 TestCase {
  id:test;when:false;optional:true
  function check(v,m){if(!v)throw new Error(m)}
  function count(item,name){let n=item.objectName===name?1:0;for(const c of item.children??[])n+=count(c,name);return n}
  function runChecks(){try{
   tryCompare(Config,"ready",true,4000);tryCompare(page,"status",Loader.Ready,5000);wait(150)
   const vault=findChild(page.item,"obsidianVaultPath"),cfg=findChild(page.item,"obsidianVaultConfigPath"),app=findChild(page.item,"obsidianApplicationConfigPath")
   check(vault && cfg && app,"shared path controls missing")
   check(count(page.item,"obsidianVaultPath")===1,"vault control duplicated")
   const y=i=>i.mapToItem(page.item,0,0).y
   check(y(vault)<y(cfg) && y(cfg)<y(app),"vault/config/application paths out of order")
   Config.setNestedValues({"notes.zettelkasten.vaultPath":"legacy-vault","todo.obsidian.vaultPath":""})
   vault.text="  new shared vault  ";vault.editingFinished();wait(80)
   check(Config.options.todo.obsidian.vaultPath==="new shared vault" && Config.options.notes.zettelkasten.vaultPath==="" && Todo.sharedVaultPath==="new shared vault","new field lost canonical shared vault migration")
   cfg.text=" custom-config ";cfg.editingFinished();app.text=" custom-application ";app.editingFinished();wait(60)
   check(Config.options.integrations.obsidian.configPath==="custom-config" && Config.options.integrations.obsidian.applicationConfigPath==="custom-application","separate config paths did not save")
   vault.text="";vault.editingFinished();wait(60)
   check(Todo.sharedVaultPath==="","clearing shared field resurrected legacy vault "+JSON.stringify({canonical:Config.options.todo.obsidian.vaultPath,legacy:Config.options.notes.zettelkasten.vaultPath,field:vault.text}))
   console.info("OBSIDIAN_PATH_UI_PASS single ordered vault/config/app controls, canonical migration, clear and saved paths")
  }catch(e){console.error("OBSIDIAN_PATH_UI_FAIL",e.message,e.stack)}Qt.quit()}
 }
 Timer {interval:100;running:true;onTriggered:test.runChecks()}
}
''')
 with private_wayland(folder) as env:
  if env is None:raise SystemExit("SKIP: Obsidian settings requires private Niri")
  cfg=folder/"config/illogical-impulse";cfg.mkdir(parents=True,exist_ok=True)
  data=json.loads((HOST/"defaults/config.json").read_text());data["panelFamily"]="abyss";data["integrations"]["obsidian"]["autoTheme"]=False
  (cfg/"config.json").write_text(json.dumps(data));env["QT_QUICK_BACKEND"]="software"
  env["HADALIRD_SETTINGS"]=(ROOT/"modules/settings/ObsidianThemeSettings.qml").as_uri()
  result=run_qs(folder,env,25)
  if result.returncode or "OBSIDIAN_PATH_UI_PASS" not in result.stdout or any(x in result.stdout for x in ["OBSIDIAN_PATH_UI_FAIL","ReferenceError:","TypeError:","Binding loop","Failed to load configuration"]):print(result.stdout);raise SystemExit(1)
  print("OBSIDIAN_PATH_UI_PASS ordered paths, one shared vault field, legacy migration, clear and independent config saves")
