pragma ComponentBehavior: Bound

import QtQuick
import qs.services as HostServices
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.modules.common

Item {
    id: root
    property bool _live: true
    Component.onDestruction: root._live = false
    property string helperPath: "/usr/libexec/alis-thinkfan"

    property bool available: false
    property bool serviceInstalled: false
    property bool active: false
    property bool enabled: false
    property bool directControlAvailable: false
    property bool fanLevelControlSupported: false
    property bool stateKnown: false
    property bool busy: false
    property string profile: "firmware"
    property int fanRpm: -1
    property string fanLevel: ""
    property string configPath: ""
    property string statusReason: ""
    property bool lastApplySucceeded: false
    property string lastApplyError: ""
    property string pendingOperation: ""
    property bool _refreshQueued: false
    property bool _profileFollowArmed: false
    property real _lastStatusRefreshAt: 0
    readonly property int _statusFreshnessMs: 30 * 1000
    readonly property int _activePollMs: 30 * 1000
    readonly property int _idleSafetyPollMs: 5 * 60 * 1000
    property string _queuedFanLevel: ""
    property bool _fanConfigApplyQueued: false

    readonly property bool profileFanControlEnabled:
        Config.getNestedValue("powerProfiles.fanControl.enabled", false) === true
    readonly property string activePowerProfileKey:
        root._powerProfileKey(PowerProfiles.profile)
    readonly property int configuredActiveFanLevel:
        root.configuredFanLevel(root.activePowerProfileKey)

    function _powerProfileKey(profileValue): string {
        switch (profileValue) {
        case PowerProfile.PowerSaver: return "powerSaver"
        case PowerProfile.Performance: return "performance"
        case PowerProfile.Balanced:
        default: return "balanced"
        }
    }

    function configuredFanLevel(key: string): int {
        const normalizedKey = String(key ?? "")
        let path = "powerProfiles.fanControl.balanced"
        if (normalizedKey === "powerSaver")
            path = "powerProfiles.fanControl.powerSaver"
        else if (normalizedKey === "performance")
            path = "powerProfiles.fanControl.performance"
        const value = Number(Config.getNestedValue(path, 0))
        if (!isFinite(value))
            return 0
        return Math.max(0, Math.min(7, Math.round(value)))
    }

    function _normalizeFanLevel(requestedLevel): string {
        if (String(requestedLevel ?? "").toLowerCase() === "auto")
            return "auto"
        const numeric = Number(requestedLevel)
        if (!isFinite(numeric))
            return ""
        const level = Math.round(numeric)
        if (level === 0)
            return "auto"
        if (level < 1 || level > 7)
            return ""
        return String(level)
    }

    function _clearStatus(reason: string): void {
        root.available = false
        root.serviceInstalled = false
        root.active = false
        root.enabled = false
        root.directControlAvailable = false
        root.fanLevelControlSupported = false
        root.stateKnown = false
        root.profile = "firmware"
        root.fanRpm = -1
        root.fanLevel = ""
        root.configPath = ""
        root.statusReason = reason
    }

    function _parseStatus(line: string): bool {
        let data
        try {
            data = JSON.parse(String(line ?? "").trim())
        } catch (error) {
            root._clearStatus("invalid-status")
            return false
        }
        if (data?.schema !== 1) {
            root._clearStatus("unsupported-status-schema")
            return false
        }

        root.available = data.available === true
        root.serviceInstalled = data.serviceInstalled === true
        root.active = data.active === true
        root.enabled = data.enabled === true
        root.fanLevelControlSupported = data.fanLevelControlSupported === true
            || data.directControlAvailable !== undefined
        root.directControlAvailable = root.fanLevelControlSupported
            && data.directControlAvailable === true
        root.profile = String(data.profile ?? "firmware")
        root.fanRpm = typeof data.fanRpm === "number" && isFinite(data.fanRpm)
            ? Math.max(0, Math.round(data.fanRpm)) : -1
        root.fanLevel = String(data.fanLevel ?? "")
        root.configPath = String(data.configPath ?? "")
        root.statusReason = String(data.reason ?? "")
        root.stateKnown = true
        root._lastStatusRefreshAt = Date.now()
        root._scheduleConfiguredFanLevelApply()
        return true
    }

    function refresh(): void {
        if (root.busy || detector.running) {
            root._refreshQueued = true
            return
        }
        root._refreshQueued = false
        detector.running = true
    }

    function setConfiguredFanLevel(key: string, requestedLevel): bool {
        const normalizedKey = String(key ?? "")
        if (normalizedKey !== "powerSaver"
                && normalizedKey !== "balanced"
                && normalizedKey !== "performance") {
            root.lastApplySucceeded = false
            root.lastApplyError = "unsupported-power-profile"
            return false
        }

        const normalizedLevel = root._normalizeFanLevel(requestedLevel)
        if (normalizedLevel.length === 0) {
            root.lastApplySucceeded = false
            root.lastApplyError = "unsupported-fan-level"
            return false
        }

        const numericLevel = normalizedLevel === "auto" ? 0 : Number(normalizedLevel)
        if (root.configuredFanLevel(normalizedKey) !== numericLevel) {
            Config.setNestedValue("powerProfiles.fanControl." + normalizedKey, numericLevel)
            Config.flushWrites()
        }

        if (root.profileFanControlEnabled
                && root.activePowerProfileKey === normalizedKey
                && root.profile !== "managed") {
            Qt.callLater(() => { if (root._live) root.applyFanLevel(normalizedLevel) })
        }
        return true
    }

    function setProfileFanControlEnabled(requestedEnabled: bool): bool {
        const nextEnabled = requestedEnabled === true
        if (root.profileFanControlEnabled !== nextEnabled) {
            Config.setNestedValue("powerProfiles.fanControl.enabled", nextEnabled)
            Config.flushWrites()
        }

        if (!nextEnabled) {
            root._queuedFanLevel = ""
            if (root.profile !== "managed")
                Qt.callLater(() => { if (root._live) root.applyFanLevel("auto") })
            return true
        }

        if (root.profile !== "managed") {
            const requestedLevel = root.configuredActiveFanLevel
            Qt.callLater(() => { if (root._live) root.applyFanLevel(requestedLevel) })
        }
        return true
    }

    function _drainQueuedFanLevel(): void {
        if (root.busy || root._queuedFanLevel.length === 0)
            return
        const queued = root._queuedFanLevel
        root._queuedFanLevel = ""
        root.applyFanLevel(queued)
    }

    function applyProfile(requestedProfile: string): bool {
        const normalized = String(requestedProfile ?? "")
        if (normalized !== "managed" && normalized !== "firmware") {
            root.lastApplySucceeded = false
            root.lastApplyError = "unsupported-profile"
            return false
        }
        if (root.busy) {
            root.lastApplySucceeded = false
            root.lastApplyError = "apply-busy"
            return false
        }
        if (!root.serviceInstalled) {
            root.lastApplySucceeded = false
            root.lastApplyError = "service-unavailable"
            return false
        }
        if (normalized === "managed" && !root.available) {
            root.lastApplySucceeded = false
            root.lastApplyError = "thinkfan-unavailable"
            return false
        }

        if (normalized === "managed")
            root._queuedFanLevel = ""

        root.busy = true
        root.pendingOperation = "profile:" + normalized
        root.lastApplySucceeded = false
        root.lastApplyError = ""
        applyProcess.command = [
            "/usr/bin/pkexec", root.helperPath,
            "--apply", normalized
        ]
        applyProcess.running = true
        return true
    }

    function applyFanLevel(requestedLevel): bool {
        const normalized = root._normalizeFanLevel(requestedLevel)
        if (normalized.length === 0) {
            root.lastApplySucceeded = false
            root.lastApplyError = "unsupported-fan-level"
            return false
        }
        if (root.busy) {
            if (root.pendingOperation === "fan-level:" + normalized)
                return true
            root._queuedFanLevel = normalized
            root.lastApplySucceeded = false
            root.lastApplyError = ""
            return true
        }
        if (!root.stateKnown || !root.fanLevelControlSupported
                || !root.directControlAvailable) {
            root.lastApplySucceeded = false
            root.lastApplyError = root.fanLevelControlSupported
                ? "direct-control-unavailable"
                : "helper-update-required"
            return false
        }
        if (root.profile === "managed") {
            root.lastApplySucceeded = false
            root.lastApplyError = "managed-control-active"
            return false
        }

        root._queuedFanLevel = ""
        root.busy = true
        root.pendingOperation = "fan-level:" + normalized
        root.lastApplySucceeded = false
        root.lastApplyError = ""
        applyProcess.command = [
            "/usr/bin/pkexec", root.helperPath,
            "--set-level", normalized
        ]
        applyProcess.running = true
        return true
    }

    function applyConfiguredPowerProfileFanLevel(): bool {
        if (!root.profileFanControlEnabled)
            return false
        const normalized = root._normalizeFanLevel(root.configuredActiveFanLevel)
        if (normalized.length === 0)
            return false
        if (root.stateKnown && root.profile !== "managed"
                && String(root.fanLevel ?? "").trim().toLowerCase() === normalized)
            return true
        return root.applyFanLevel(normalized)
    }

    function _scheduleConfiguredFanLevelApply(): void {
        if (!root._profileFollowArmed || !root.profileFanControlEnabled
                || root.profile === "managed")
            return
        if (root._fanConfigApplyQueued)
            return
        root._fanConfigApplyQueued = true
        Qt.callLater(() => {
            if (!root._live) return
            root._fanConfigApplyQueued = false
            if (root._profileFollowArmed && root.profileFanControlEnabled
                    && root.profile !== "managed")
                root.applyConfiguredPowerProfileFanLevel()
        })
    }

    function _handleProfileFollowEvent(): void {
        if (!root.profileFanControlEnabled)
            return
        const stale = root._lastStatusRefreshAt <= 0
            || Date.now() - root._lastStatusRefreshAt >= root._statusFreshnessMs
        if (stale) {
            root.refresh()
            return
        }
        root._scheduleConfiguredFanLevelApply()
    }

    Component.onCompleted: root.refresh()

    Connections {
        target: PowerProfiles
        function onProfileChanged(): void {
            root._handleProfileFollowEvent()
        }
    }

    Connections {
        target: Config
        function onConfigChanged(): void {
            root._handleProfileFollowEvent()
        }
    }

    // Do not trigger a privileged fan write during shell startup/profile restore.
    // After startup settles, later user/runtime power-profile changes can follow
    // the configured fan level when the opt-in switch is enabled.
    Timer {
        interval: 5000
        repeat: false
        running: true
        onTriggered: {
            root._profileFollowArmed = true
            root._scheduleConfiguredFanLevelApply()
        }
    }

    Process {
        id: detector
        property bool statusSeen: false
        property bool timedOut: false
        property bool startObserved: false
        command: [root.helperPath, "--status"]

        stdout: SplitParser {
            onRead: data => {
                if (root._parseStatus(data))
                    detector.statusSeen = true
            }
        }

        onRunningChanged: {
            if (detector.running) {
                detector.startObserved = false
                return
            }
            if (detector.startObserved)
                return

            detectorTimeout.stop()
            root._clearStatus("helper-unavailable")
            root._lastStatusRefreshAt = Date.now()
            if (root._refreshQueued) {
                root._refreshQueued = false
                Qt.callLater(() => { if (root._live) root.refresh() })
            }
        }
        onStarted: {
            detector.startObserved = true
            detector.statusSeen = false
            detector.timedOut = false
            detectorTimeout.restart()
        }
        onExited: (exitCode, exitStatus) => {
            detectorTimeout.stop()
            if (detector.timedOut)
                root._clearStatus("status-timeout")
            else if (exitCode !== 0 || !detector.statusSeen)
                root._clearStatus(exitCode === 127
                    ? "helper-unavailable" : "status-failed")
            root._lastStatusRefreshAt = Date.now()
            if (root._refreshQueued) {
                root._refreshQueued = false
                Qt.callLater(() => { if (root._live) root.refresh() })
            }
        }
    }

    Timer {
        id: detectorTimeout
        interval: 5000
        repeat: false
        onTriggered: {
            if (!detector.running)
                return
            detector.timedOut = true
            detector.running = false
        }
    }

    Process {
        id: applyProcess
        property bool timedOut: false
        property bool startObserved: false

        stdout: SplitParser {
            onRead: data => root._parseStatus(data)
        }

        onRunningChanged: {
            if (applyProcess.running) {
                applyProcess.startObserved = false
                return
            }
            if (applyProcess.startObserved || !root.busy)
                return

            applyTimeout.stop()
            root.busy = false
            root.lastApplySucceeded = false
            root.lastApplyError = "apply-start-failed"
            root.pendingOperation = ""
            console.warn("[ThinkFan] Failed to start privileged fan-control helper")
            Qt.callLater(() => { if (root._live) root.refresh() })
        }
        onStarted: {
            applyProcess.startObserved = true
            applyProcess.timedOut = false
            applyTimeout.restart()
        }
        onExited: (exitCode, exitStatus) => {
            applyTimeout.stop()
            const completedOperation = root.pendingOperation
            root.busy = false
            root.lastApplySucceeded = exitCode === 0 && !applyProcess.timedOut
            root.lastApplyError = applyProcess.timedOut
                ? "apply-timeout" : (exitCode === 0 ? "" : "apply-failed")
            if (!root.lastApplySucceeded) {
                if (applyProcess.timedOut)
                    console.warn("[ThinkFan] Timed out while applying fan-control intent")
                else
                    console.warn("[ThinkFan] Failed to apply fan-control intent (exit code " + exitCode + ")")
            }
            root.pendingOperation = ""

            if (root.lastApplySucceeded
                    && completedOperation === "profile:firmware"
                    && root.profileFanControlEnabled) {
                root._queuedFanLevel = ""
                Qt.callLater(() => { if (root._live) root.applyConfiguredPowerProfileFanLevel() })
            } else if (root._queuedFanLevel.length > 0) {
                Qt.callLater(() => { if (root._live) root._drainQueuedFanLevel() })
            }
            Qt.callLater(() => { if (root._live) root.refresh() })
        }
    }

    Timer {
        id: applyTimeout
        interval: 60000
        repeat: false
        onTriggered: {
            if (!applyProcess.running)
                return
            applyProcess.timedOut = true
            applyProcess.running = false
        }
    }

    Timer {
        id: statusRefreshTimer
        interval: (root.active || root.busy)
            ? root._activePollMs : root._idleSafetyPollMs
        repeat: true
        // Active ThinkFan state keeps the responsive 30-second status cadence.
        // Profile-follow alone uses a sparse safety poll; PowerProfiles/Config
        // changes demand-refresh stale state immediately before applying intent.
        running: root.profileFanControlEnabled || root.active || root.busy
        onTriggered: root.refresh()
    }
}
