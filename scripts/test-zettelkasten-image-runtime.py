#!/usr/bin/env python3
"""Actual optional QML worker captures a shared Quick Notes image to a vault."""
import base64
import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile

from integration_test_host import resolve_host_root
ROOT = Path(__file__).resolve().parents[1]
HOST = resolve_host_root(ROOT)
sys.path.insert(0, str(HOST / "scripts"))
from native_test_session import private_wayland, run_qs
spec = importlib.util.spec_from_file_location("installer", ROOT / "scripts/install.py")
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)
PNG = base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNwmLDhPwAFFAKA8JVvSQAAAABJRU5ErkJggg==")
with tempfile.TemporaryDirectory(prefix="hadalird-note-image-") as name:
    private = Path(name)
    shell = private / "shell"
    shell.mkdir()
    for entry in ("modules", "services", "GlobalStates.qml", "qmldir", "scripts", "defaults", "translations", "assets"):
        (shell / entry).symlink_to(HOST / entry)
    source = private / "Ảnh.png"
    source.write_bytes(PNG)
    package = private / "data/alis-intergration/releases/fixture"
    package.parent.mkdir(parents=True)
    installer.assemble(ROOT, package, "f" * 40)
    (private / "data/alis-intergration/current").symlink_to("releases/fixture")
    vault = private / "Vault có dấu"
    config = vault / "Custom Config"
    config.mkdir(parents=True)
    (config / "app.json").write_text('{"attachmentFolderPath":"Ảnh/Assets"}')
    options = json.loads((HOST / "defaults/config.json").read_text())
    options["panelFamily"] = "abyss"
    options["abyss"]["companion"]["enabled"] = False
    options["integrations"]["hadalird"].update(tlp=False, thinkfan=False, obsidian=True)
    options["integrations"]["obsidian"].update(autoTheme=False, configPath=str(config))
    options["todo"]["obsidian"]["vaultPath"] = str(vault)
    (shell / "shell.qml").write_text(r'''
import QtQuick
import QtTest
import Quickshell
import qs.modules.common
import qs.modules.sidebarRight.notepad
import qs.services
ShellRoot {
 Component.onCompleted:Quickshell.watchFiles=false
 FloatingWindow {
  visible:true;implicitWidth:450;implicitHeight:380;color:"#111820"
  QuickNotesView {id:notes;width:430;height:320}
 }
 TestCase {
  id:test;when:false;optional:true
  function check(ok,message){if(!ok)throw new Error(message)}
  function runChecks(){try{
   tryCompare(Config,"ready",true,4000);tryCompare(Notepad,"ready",true,4000)
   tryCompare(Zettelkasten,"ready",true,4000)
   const editor=notes.editor
   check(editor.importImage(Quickshell.env("IMAGE_SOURCE")),"generic image import did not start")
   tryCompare(editor,"attachmentBusy",false,6000)
   check(editor.imageUrls.length===1,"generic image reference was lost")
   const draft=Notepad.tabs[Notepad.indexForTabId(editor._loadedTabId)].text
   check(notes.captureQuickNote(),"optional image capture did not start")
   tryVerify(()=>Zettelkasten.lastCreatedPath.length>0 && !Zettelkasten.busy,6000)
   check(Zettelkasten.errorMessage==="","optional image capture failed: "+Zettelkasten.errorMessage)
   check(Notepad.tabs[Notepad.indexForTabId(editor._loadedTabId)].text===draft,"capture consumed or changed the generic draft")
   console.info("ZETTEL_IMAGE_HOST_PASS",Zettelkasten.lastCreatedPath)
  }catch(e){console.error("ZETTEL_IMAGE_HOST_FAIL",e.message,e.stack)}Qt.quit()}
 }
 Timer {interval:100;running:true;onTriggered:test.runChecks()}
}
''')
    with private_wayland(private) as env:
        if env is None:
            raise SystemExit("SKIP: optional notes image worker requires private Niri")
        user_config = private / "config/alis"
        user_config.mkdir(parents=True)
        (user_config / "config.json").write_text(json.dumps(options))
        store = private / "state/quickshell/user"
        store.mkdir(parents=True)
        (store / "notepad-tabs.json").write_text('{"currentTab":0,"tabs":[{"id":"note","title":"Note 1","text":"draft\\n"}]}')
        env["IMAGE_SOURCE"] = source.as_uri()
        result = run_qs(shell, env, timeout=30)
        if result.returncode or "ZETTEL_IMAGE_HOST_PASS" not in result.stdout or any(token in result.stdout for token in
            ("ZETTEL_IMAGE_HOST_FAIL", "TypeError:", "ReferenceError:", "Binding loop", "Unable to assign", "Failed to load configuration")):
            print(result.stdout)
            raise SystemExit(1)
        print(next(line for line in result.stdout.splitlines() if "ZETTEL_IMAGE_HOST_PASS" in line))
    images = list((vault / "Ảnh/Assets").glob("*.png"))
    notes = list((vault / options["notes"]["zettelkasten"]["folder"]).glob("*.md"))
    assert len(images) == len(notes) == 1
    assert images[0].read_bytes() == source.read_bytes() == PNG
    assert "file://" not in notes[0].read_text()
    assert "![Image](" in notes[0].read_text()
