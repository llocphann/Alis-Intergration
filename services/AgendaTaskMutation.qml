pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id:root
    property string mode:"daily"
    property var sourceArgs:[]
    property bool configured:false
    readonly property bool busy:process.running && !root._reported
    property string _source:""
    property string _key:""
    property bool _started:false
    property bool _reported:false
    // Keep array identity across the QML signal boundary. A QVariant sequence
    // is not Array.isArray(), which would transiently clear the task model.
    signal finished(bool success,string payloadJson)
    function execute(operation,event) {
        if(!root.configured || root.busy)return false
        const args=root.sourceArgs.slice()
        const link=event.todoLink || event
        const date=args.indexOf("--date")
        if(root.mode==="daily" && date>=0 && link.sourceDate)args[date+1]=link.sourceDate
        root._source=JSON.stringify(root.sourceArgs)
        root._key=link.key;root._started=false;root._reported=false
        process.command=["/usr/bin/python3",decodeURIComponent(String(Qt.resolvedUrl("../scripts/todo/obsidian_agenda.py")).replace(/^file:\/\//,"")),"--mode",root.mode,"--operation",operation]
            .concat(args).concat(["--event",JSON.stringify(event)])
        process.running=true
        return true
    }
    function report(success,payload) {
        if(root._reported)return
        root._reported=true;deadline.stop()
        root.finished(success,typeof payload==="string" ? payload : JSON.stringify(payload))
    }
    Timer {id:deadline;interval:8000;onTriggered:{process.running=false;root.report(false,{error:{code:"agenda_timeout",message:"To-do link timed out"},key:root._key})}}
    Process {
        id:process
        stdout:StdioCollector {id:output}
        onStarted:{root._started=true;deadline.restart()}
        onRunningChanged:if(!running && !root._started)root.report(false,{error:{code:"agenda_start_failed",message:"Could not start To-do link"},key:root._key})
        onExited:(code,status)=>{
            if(!root.configured || root._source!==JSON.stringify(root.sourceArgs)) {root.report(false,{error:{code:"agenda_source_changed",message:"To-do source changed"},key:root._key});return}
            try {
                const payload=JSON.parse(output.text || "")
                root.report(code===0 && payload.ok===true,String(output.text))
            } catch(error) {root.report(false,{error:{code:"agenda_invalid_result",message:"Could not confirm To-do link"},key:root._key})}
        }
    }
}
