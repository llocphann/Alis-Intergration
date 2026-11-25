import QtQuick
import qs

// Integration workers are disposable objects, never engine-owned singletons.
Item {
    id: root
    required property var host
    property string batteryHelperPath: "/usr/libexec/alis-battery-charge-limit"
    property string fanHelperPath: "/usr/libexec/alis-thinkfan"
    readonly property string _pluginsBaseUrl: {
        const raw = String(root.host?.pluginsRoot ?? "").trim()
        if (raw.length > 0) {
            const clean = raw.replace(/\/+$/, "")
            return (clean.startsWith("file://") || clean.startsWith("qs:")) ? clean : ("file://" + clean)
        }
        return String(Qt.resolvedUrl("plugins")).replace(/\/+$/, "")
    }
    function pluginUrl(pluginId: string, relPath: string): string {
        const perPlugin = root.host?.pluginRoots?.[pluginId]
        if (typeof perPlugin === "string" && perPlugin.trim().length > 0) {
            const clean = perPlugin.trim().replace(/\/+$/, "")
            const base = (clean.startsWith("file://") || clean.startsWith("qs:")) ? clean : ("file://" + clean)
            return `${base}/${relPath}`
        }
        return `${root._pluginsBaseUrl}/${pluginId}/${relPath}`
    }
    readonly property var tlp: charge.item
    readonly property var tlpSettings: settings.item
    readonly property var tlpCapabilities: capabilities.item
    readonly property var thinkfan: fan.item
    readonly property var nexusTheme: theme.item
    readonly property var zettelkasten: notes.item
    readonly property var nexus: nexusLoader.item
    readonly property var alisFiles: alisFilesLoader.item
    readonly property var spacedRepetition: spacedRepetitionLoader.item
    readonly property var exercisesTracker: exercisesTrackerLoader.item
    readonly property bool _srWanted: (root.host?.spacedRepetitionEnabled ?? false)
        && ((root.host?.spacedRepetitionDemanded ?? false)
            || Boolean(GlobalStates?.dashboardOpen)
            || Boolean(GlobalStates?.settingsOverlayOpen))
    readonly property bool _etWanted: (root.host?.exercisesTrackerEnabled ?? false)
        && ((root.host?.exercisesTrackerDemanded ?? false)
            || Boolean(GlobalStates?.dashboardOpen)
            || Boolean(GlobalStates?.settingsOverlayOpen))
    property bool _srLatched: false
    property bool _etLatched: false
    on_SrWantedChanged: if (_srWanted) _srLatched = true
    on_EtWantedChanged: if (_etWanted) _etLatched = true
    Component.onCompleted: {
        if (_srWanted) _srLatched = true
        if (_etWanted) _etLatched = true
    }
    Connections {
        target: root.host
        function onSpacedRepetitionEnabledChanged(): void {
            if (!(root.host?.spacedRepetitionEnabled ?? false))
                root._srLatched = false
        }
        function onExercisesTrackerEnabledChanged(): void {
            if (!(root.host?.exercisesTrackerEnabled ?? false))
                root._etLatched = false
        }
    }
    Loader {
        id: capabilities
        active: root.host?.tlpEnabled ?? false
        source: active ? root.pluginUrl("tlp", "services/TlpRuntimeCapabilities.qml") : ""
    }
    Loader {
        id: charge; active: root.host?.tlpEnabled ?? false
        function syncSource(): void {
            if (active && String(source).length === 0)
                setSource(root.pluginUrl("tlp", "services/TlpService.qml"), {helperPath: root.batteryHelperPath})
            else if (!active) source = ""
        }
        onActiveChanged: syncSource()
        Component.onCompleted: syncSource()
    }
    Loader {
        id: settings; active: root.host?.tlpEnabled ?? false
        function syncSource(): void {
            if (active && String(source).length === 0)
                setSource(root.pluginUrl("tlp", "services/TlpSettingsService.qml"), {helperPath: root.batteryHelperPath})
            else if (!active) source = ""
        }
        onActiveChanged: syncSource()
        Component.onCompleted: syncSource()
    }
    Loader {
        id: fan; active: root.host?.thinkfanEnabled ?? false
        function syncSource(): void {
            if (active && String(source).length === 0)
                setSource(root.pluginUrl("thinkfan", "services/ThinkFanService.qml"), {helperPath: root.fanHelperPath})
            else if (!active) source = ""
        }
        onActiveChanged: syncSource()
        Component.onCompleted: syncSource()
    }
    Loader {
        id: theme
        active: root.host?.nexusEnabled ?? false
        asynchronous: true
        source: active ? root.pluginUrl("nexus", "services/NexusTheme.qml") : ""
    }
    Loader {
        id: notes
        active: root.host?.nexusEnabled ?? false
        asynchronous: true
        source: active ? root.pluginUrl("nexus", "services/Zettelkasten.qml") : ""
    }
    Loader {
        id: nexusLoader
        active: root.host?.nexusEnabled ?? false
        asynchronous: true
        source: active ? root.pluginUrl("nexus", "services/NexusService.qml") : ""
    }
    Loader {
        id: alisFilesLoader
        active: root.host?.alisFilesEnabled ?? false
        asynchronous: true
        source: active ? root.pluginUrl("alis_files", "services/AlisFilesService.qml") : ""
    }
    Loader {
        id: spacedRepetitionLoader
        active: (root.host?.spacedRepetitionEnabled ?? false) && root._srLatched
        asynchronous: true
        function syncSource(): void {
            if (active && String(source).length === 0)
                source = root.pluginUrl("spaced_repetition", "services/SpacedRepetition.qml")
            else if (!active) source = ""
        }
        onActiveChanged: syncSource()
        Component.onCompleted: syncSource()
    }
    Loader {
        id: exercisesTrackerLoader
        active: (root.host?.exercisesTrackerEnabled ?? false) && root._etLatched
        asynchronous: true
        function syncSource(): void {
            if (active && String(source).length === 0)
                source = root.pluginUrl("exercises_tracker", "services/ExercisesTracker.qml")
            else if (!active) source = ""
        }
        onActiveChanged: syncSource()
        Component.onCompleted: syncSource()
    }
}
