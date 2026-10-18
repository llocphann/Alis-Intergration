#!/usr/bin/env python3
"""Actual QML rejects failed/malformed capture receipts and recovers once."""
import json
from pathlib import Path
import sys
import tempfile
from integration_test_host import resolve_host_root

ROOT = Path(__file__).resolve().parents[1]
HOST = resolve_host_root(ROOT)
sys.path.insert(0, str(HOST / "scripts"))
from native_test_session import private_wayland, run_qs

with tempfile.TemporaryDirectory(prefix="alis-capture-failures-") as name:
    private = Path(name)
    shell = private / "shell"
    shell.mkdir()
    for entry in ("services", "modules", "GlobalStates.qml", "qmldir", "scripts", "defaults", "translations", "assets"):
        (shell / entry).symlink_to(HOST / entry)
    vault = private / "vault"
    vault.mkdir()
    config = private / "config/alis"
    config.mkdir(parents=True)
    options = json.loads((HOST / "defaults/config.json").read_text())
    options["todo"]["obsidian"]["vaultPath"] = str(vault)
    options["integrations"]["hadalird"] = {key: False for key in ("tlp", "thinkfan", "obsidian")}
    options["integrations"]["obsidian"]["autoTheme"] = False
    (config / "config.json").write_text(json.dumps(options))
    good = {"ok": True, "notePath": "Notes/saved.md", "noteFullPath": str(vault / "Notes/saved.md")}
    cases = [(1, json.dumps(good)), (0, '{"ok":true}'), (0, "null"), (0, "[]"),
             (0, "not json"), (0, json.dumps({**good, "notePath": "../escape.md"})),
             (0, '{"ok":false,"error":{"code":"conflict","message":"Synthetic conflict"}}'), (0, json.dumps(good))]
    helper = private / "helper.py"
    helper.write_text("#!/usr/bin/python3\nimport json,sys\nfrom pathlib import Path\n"
                      + "counter=Path(" + repr(str(private / "calls")) + ")\n"
                      + "index=int(counter.read_text()) if counter.exists() else 0\ncounter.write_text(str(index+1))\n"
                      + "cases=" + repr(cases) + "\n"
                      + "if index==len(cases)-1:\n note=Path(" + repr(good["noteFullPath"]) + ");note.parent.mkdir();note.write_text('fixture saved note')\n"
                      + "code,output=cases[index];print(output);sys.exit(code)\n")
    helper.chmod(0o755)
    (private / "CaptureWorker.qml").write_bytes((ROOT / "services/Zettelkasten.qml").read_bytes())
    (shell / "shell.qml").write_text(r'''
import QtQuick
import QtTest
import Quickshell
import qs.services
import qs.modules.common
ShellRoot {
 Component.onCompleted: Quickshell.watchFiles=false
 property int captures: 0
 Loader {id:worker;source:Quickshell.env("FIXTURE_WORKER");onLoaded:item.helperPath=Quickshell.env("FIXTURE_HELPER")}
 Connections {target:worker.item;function onCaptured(payload){captures++}}
 TestCase {
  id:test;when:false;optional:true
  function check(value,message){if(!value)throw new Error(message)}
  function runChecks(){try{
   tryCompare(Config,"ready",true,4000);tryCompare(worker,"status",Loader.Ready,2000)
   tryCompare(worker.item,"ready",true,2000)
   worker.item.lastCreatedPath="prior.md";worker.item.lastCreatedFullPath="/prior.md"
   for(let i=0;i<7;i++){
    check(worker.item.capture("test","body"),"capture did not start")
    tryCompare(worker.item,"busy",false,4000)
    check(worker.item.errorCode.length>0,"failed receipt reported success at "+i)
    check(worker.item.lastCreatedPath==="prior.md" && worker.item.lastCreatedFullPath==="/prior.md" && captures===0,"failed receipt mutated saved state at "+i)
   }
   check(worker.item.capture("test","body"),"recovery did not start")
   tryCompare(worker.item,"busy",false,4000)
   check(worker.item.lastCreatedPath==="Notes/saved.md" && worker.item.errorCode==="" && captures===1,"recovery did not produce exactly one saved receipt")
   check(Hadalird.session===null,"fixture enabled optional workers")
   console.info("ZETTEL_FAILURE_RUNTIME_PASS")
  }catch(e){console.error("ZETTEL_FAILURE_RUNTIME_FAIL",e.message,e.stack)}Qt.quit()}
 }
 Timer {interval:100;running:true;onTriggered:test.runChecks()}
}
''')
    with private_wayland(private) as env:
        if env is None:
            raise SystemExit("SKIP: capture receipt runtime requires private Niri")
        env.update(FIXTURE_WORKER=(private / "CaptureWorker.qml").as_uri(), FIXTURE_HELPER=str(helper))
        result = run_qs(shell, env, timeout=35)
    if result.returncode or "ZETTEL_FAILURE_RUNTIME_PASS" not in result.stdout or any(token in result.stdout for token in
        ("ZETTEL_FAILURE_RUNTIME_FAIL", "TypeError:", "ReferenceError:", "Binding loop", "Failed to load configuration")):
        print(result.stdout)
        raise SystemExit(1)
    assert (vault / "Notes/saved.md").read_text() == "fixture saved note"
    assert (private / "calls").read_text() == "8"
print("ZETTEL_FAILURE_RUNTIME_PASS nonzero/empty/null/array/invalid/traversal/conflict receipts, state preservation and one recovery")
