import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.services as HostServices
Item {
 id:root
 property bool _live: true
 Component.onDestruction: root._live = false
 readonly property var options:Config.options?.integrations?.obsidian
 readonly property bool enabled:Config.ready && (options?.autoTheme ?? false)
 readonly property string vaultPath:HostServices.Todo.sharedVaultPath
 readonly property string configPath:options?.configPath ?? ""
 readonly property string applicationConfigPath:options?.applicationConfigPath ?? ""
 readonly property var palette:({background:hex(Appearance.m3colors.transparent ? Appearance.m3colors.m3background : Appearance.colors.colLayer0Base),foreground:hex(Appearance.m3colors.m3onSurface),accent:hex(Appearance.colors.colPrimary)})
 readonly property string signature:JSON.stringify({vault:vaultPath,config:configPath,application:applicationConfigPath,palette:palette})
 // A direct alias preserves Process notifications without evaluating a JS
 // binding after the worker context has been torn down.
 readonly property alias busy:worker.running
 property var info:({})
 property string error:""
 property var queued:null
 property var current:null
 function hex(color):string {return "#"+[color.r,color.g,color.b].map(value=>Math.round(Math.max(0,Math.min(1,value))*255).toString(16).padStart(2,"0")).join("")}
 function request(action):void {
  queued={action:action,vaultPath:vaultPath,configPath:configPath,applicationConfigPath:applicationConfigPath,palette:palette}
  runNext()
 }
 function runNext():void {
  if(worker.running || !queued)return
  current=queued;queued=null;error="";worker.response=""
  worker.command=["python3",decodeURIComponent(String(Qt.resolvedUrl("../scripts/integrations/obsidian_theme.py")).replace(/^file:\/\//, ""))]
  worker.running=true;deadline.restart()
 }
 function inspect():void {request("inspect")}
 function apply():void {request("apply")}
 function restore():void {Config.setNestedValue("integrations.obsidian.autoTheme",false);request("disable")}
 onEnabledChanged:if(enabled)debounce.restart();else {debounce.stop();if(queued?.action==="apply")queued=null}
 onSignatureChanged:if(enabled)debounce.restart()
 Component.onCompleted:if(enabled)debounce.restart()
 Timer {id:debounce;interval:350;repeat:false;onTriggered:if(root.enabled)root.apply()}
 Timer {id:deadline;interval:10000;repeat:false;onTriggered:{root.error="Obsidian did not respond in time";worker.running=false}}
 FileView {path:root.enabled && root.info.configPath ? root.info.configPath+"/appearance.json" : "";preload:false;watchChanges:root.enabled && Boolean(root.info.configPath);onFileChanged:if(root.enabled)debounce.restart()}
 Process {
  id:worker
  property string response:""
  stdinEnabled:true
  onStarted:{write(JSON.stringify(root.current));stdinEnabled=false}
  stdout:SplitParser {onRead:data=>{if(worker.response.length<32768)worker.response+=data}}
  onExited:(code,status)=>{
   deadline.stop();stdinEnabled=true
   try {
    const result=JSON.parse(response)
    if(result.ok){root.info=result;root.error=""}
    else root.error=result.error || "Could not update Obsidian"
   }catch(e){if(!root.error)root.error="Could not read Obsidian configuration"}
   Qt.callLater(() => { if (root._live) root.runNext() })
  }
 }
}
