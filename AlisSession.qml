import QtQuick

// Integration workers are disposable objects, never engine-owned singletons.
Item {
    id: root
    required property var host
    property string batteryHelperPath: "/usr/libexec/alis-battery-charge-limit"
    property string fanHelperPath: "/usr/libexec/alis-thinkfan"
    readonly property var tlp: charge.item
    readonly property var tlpSettings: settings.item
    readonly property var tlpCapabilities: capabilities.item
    readonly property var thinkfan: fan.item
    readonly property var obsidianTheme: theme.item
    readonly property var zettelkasten: notes.item
    Loader { id: capabilities; active: host.tlpEnabled; source: "services/TlpRuntimeCapabilities.qml" }
    Loader {
        id: charge; active: host.tlpEnabled
        function syncSource(): void {
            if(active && String(source).length === 0) setSource("services/TlpService.qml", {helperPath:root.batteryHelperPath})
            else if (!active) source=""
        }
        onActiveChanged: syncSource()
        Component.onCompleted: syncSource()
    }
    Loader {
        id: settings; active: host.tlpEnabled
        function syncSource(): void {
            if(active && String(source).length === 0) setSource("services/TlpSettingsService.qml", {helperPath:root.batteryHelperPath})
            else if (!active) source=""
        }
        onActiveChanged: syncSource()
        Component.onCompleted: syncSource()
    }
    Loader {
        id: fan; active: host.thinkfanEnabled
        function syncSource(): void {
            if(active && String(source).length === 0) setSource("services/ThinkFanService.qml", {helperPath:root.fanHelperPath})
            else if (!active) source=""
        }
        onActiveChanged: syncSource()
        Component.onCompleted: syncSource()
    }
    Loader { id: theme; active: host.obsidianEnabled; source: "services/ObsidianTheme.qml" }
    Loader { id: notes; active: host.obsidianEnabled; source: "services/Zettelkasten.qml" }
}
