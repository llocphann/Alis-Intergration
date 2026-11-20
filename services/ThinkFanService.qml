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
    readonly property string _legacyHelperPath: "/usr/libexec/" + ["i", "nir"].join("") + "-thinkfan"
    property string privilegeEscalationCommand: "/usr/bin/pkexec"
    readonly property string packagedHelperPath: decodeURIComponent(String(Qt.resolvedUrl("../assets/helpers/alis-thinkfan")).replace(/^file:\/\//, ""))

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
    property bool sleepMonitorEnabled: true
    property bool probeSystemSleepMeta: true
    property int resumeFirstPassDelayMs: 1500
    property int resumeSecondPassDelayMs: 5000
    property bool _managedBeforeSleep: false
    property bool _daemonRunning: false
    property bool _daemonRunningBeforeSleep: false
    property string _manualLevelBeforeSleep: ""
    property bool _sleeping: false
    property bool _resumeRecoveryPending: false
    property bool _resumeSecondPass: false
    property bool _reapplyManagedAfterBounce: false
    property bool _wakeupUnitEnabled: true
    property bool _configAllowsAutoLevel: true
    property real _lastWatchdogWallMs: 0

    readonly property bool profileFanControlEnabled:
        Config.getNestedValue("powerProfiles.fanControl.enabled", false) === true
    readonly property bool managedIntentEnabled:
        Config.ready && Config.getNestedValue("powerProfiles.fanControl.managed", false) === true
    property bool _startupManagedRecoveryDone: false
    property string _pendingManagedIntentValue: ""
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
        if (root.active || root.enabled) {
            root._managedBeforeSleep = true
            root._manualLevelBeforeSleep = ""
        } else if (!root._sleeping && !root._resumeRecoveryPending) {
            if (root.profile !== "managed")
                root._managedBeforeSleep = false
            const trimmedLevel = String(root.fanLevel ?? "").trim()
            if (root.profile === "manual" && /^[1-7]$/.test(trimmedLevel))
                root._manualLevelBeforeSleep = trimmedLevel
            else if (root.profile === "firmware" && !root._daemonRunning)
                root._manualLevelBeforeSleep = ""
            root._daemonRunningBeforeSleep = root._daemonRunning
        }
        root._scheduleConfiguredFanLevelApply()
        root._maybeRecoverManagedOnStartup()
        root._reconcileResumeRecovery()
        return true
    }

    function _maybeRecoverManagedOnStartup(): void {
        if (root._startupManagedRecoveryDone || !root._profileFollowArmed
                || !Config.ready || !root.stateKnown)
            return
        if (!root.managedIntentEnabled || root.profileFanControlEnabled)
            return
        root._startupManagedRecoveryDone = true
        if (root.serviceInstalled && root.available && !root.active
                && !root.busy && !root._sleeping)
            root._applyProfileInternal("managed", false)
    }

    function _reconcileResumeRecovery(): void {
        if (!root._resumeRecoveryPending || !root.stateKnown)
            return
        const finishPass = root._resumeSecondPass
        if (((root.enabled || root.managedIntentEnabled || root._managedBeforeSleep) && !root.active
                || (root._daemonRunningBeforeSleep && !root._daemonRunning && !root.active))
                && root.serviceInstalled
                && root.available) {
            root._resumeRecoveryPending = false
            root._resumeSecondPass = false
            Qt.callLater(() => {
                if (root._live && !root.busy && !root.active)
                    root._applyProfileInternal("managed", false)
            })
            return
        }
        if (finishPass
                && root.active
                && root.profile === "managed"
                && root.directControlAvailable
                && String(root.fanLevel ?? "").trim().toLowerCase() === "auto"
                && (!root._wakeupUnitEnabled || !root._configAllowsAutoLevel)) {
            root._resumeRecoveryPending = false
            root._resumeSecondPass = false
            root._reapplyManagedAfterBounce = true
            Qt.callLater(() => {
                if (root._live && !root.busy)
                    root.applyProfile("firmware")
            })
            return
        }
        if (root.profileFanControlEnabled && root.profile !== "managed") {
            root._profileFollowArmed = true
            root._scheduleConfiguredFanLevelApply()
        } else if (root.profile !== "managed"
                && root.directControlAvailable
                && root._manualLevelBeforeSleep.length > 0
                && String(root.fanLevel ?? "").trim() !== root._manualLevelBeforeSleep) {
            const restoreLevel = root._manualLevelBeforeSleep
            root._resumeRecoveryPending = false
            root._resumeSecondPass = false
            Qt.callLater(() => {
                if (root._live && !root.busy && root.profile !== "managed")
                    root.applyFanLevel(restoreLevel)
            })
            return
        }
        if (finishPass) {
            root._resumeRecoveryPending = false
            root._resumeSecondPass = false
        }
    }

    function handlePrepareForSleep(goingToSleep: bool): void {
        if (goingToSleep) {
            root._sleeping = true
            root._managedBeforeSleep = root.active || root.enabled || root.profile === "managed"
            root._daemonRunningBeforeSleep = root._daemonRunning
            const trimmedLevel = String(root.fanLevel ?? "").trim()
            if (root.profile === "manual" && /^[1-7]$/.test(trimmedLevel))
                root._manualLevelBeforeSleep = trimmedLevel
            resumeFirstPassTimer.stop()
            resumeSecondPassTimer.stop()
            root._resumeRecoveryPending = false
            root._resumeSecondPass = false
            return
        }
        root.handleSuspendResume()
    }

    function handleSuspendResume(): void {
        if (!root._live)
            return
        root._sleeping = false
        root._resumeRecoveryPending = true
        root._resumeSecondPass = false
        root._lastStatusRefreshAt = 0
        resumeFirstPassTimer.restart()
        resumeSecondPassTimer.restart()
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

    function _buildApplyCommand(flag: string, value: string): var {
        if (root.helperPath === "/usr/libexec/alis-thinkfan") {
            return [
                "/bin/sh", "-c",
                "helper=\"$2\"; if [ ! -x \"$helper\" ] && [ -x \"$3\" ]; then helper=\"$3\"; fi; exec \"$1\" \"$helper\" \"$4\" \"$5\"",
                "sh",
                root.privilegeEscalationCommand,
                root.helperPath,
                root._legacyHelperPath,
                flag,
                value
            ]
        }
        return [root.privilegeEscalationCommand, root.helperPath, flag, value]
    }

    function applyProfile(requestedProfile: string): bool {
        return root._applyProfileInternal(requestedProfile, true)
    }

    function _applyProfileInternal(requestedProfile: string, persistIntent: bool): bool {
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

        if (normalized === "managed") {
            root._queuedFanLevel = ""
            root._managedBeforeSleep = true
            root._manualLevelBeforeSleep = ""
        } else if (!root._reapplyManagedAfterBounce) {
            root._managedBeforeSleep = false
            root._daemonRunningBeforeSleep = false
            root._manualLevelBeforeSleep = ""
        }

        root._pendingManagedIntentValue = (persistIntent && !root._reapplyManagedAfterBounce) ? normalized : ""
        root.busy = true
        root.pendingOperation = "profile:" + normalized
        root.lastApplySucceeded = false
        root.lastApplyError = ""
        applyProcess.command = root._buildApplyCommand("--apply", normalized)
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

        if (normalized === "auto")
            root._manualLevelBeforeSleep = ""
        else
            root._manualLevelBeforeSleep = normalized
        root._queuedFanLevel = ""
        root.busy = true
        root.pendingOperation = "fan-level:" + normalized
        root.lastApplySucceeded = false
        root.lastApplyError = ""
        applyProcess.command = root._buildApplyCommand("--set-level", normalized)
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

    Component.onCompleted: {
        root._lastFanConfigSignature = root._fanConfigSignature()
        root.refresh()
    }

    property string _lastFanConfigSignature: ""
    function _fanConfigSignature(): string {
        return String(root.profileFanControlEnabled) + "|"
            + String(root.configuredFanLevel("powerSaver")) + "|"
            + String(root.configuredFanLevel("balanced")) + "|"
            + String(root.configuredFanLevel("performance"))
    }

    Connections {
        target: PowerProfiles
        function onProfileChanged(): void {
            root._handleProfileFollowEvent()
        }
    }

    Connections {
        target: Config
        function onReadyChanged(): void {
            if (!Config.ready)
                return
            root.refresh()
            root._maybeRecoverManagedOnStartup()
        }
        function onConfigChanged(): void {
            const nextSignature = root._fanConfigSignature()
            if (nextSignature === root._lastFanConfigSignature)
                return
            root._lastFanConfigSignature = nextSignature
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
            root._maybeRecoverManagedOnStartup()
        }
    }

    Process {
        id: detector
        property bool statusSeen: false
        property bool timedOut: false
        property bool startObserved: false
        command: [
            "/bin/sh", "-c",
            "for p in \"$1\" /usr/libexec/alis-thinkfan /usr/libexec/inir-thinkfan \"$2\"; do if [ -n \"$p\" ] && [ -x \"$p\" ]; then if [ \"$3\" = \"1\" ]; then wakeup=0; systemctl is-enabled --quiet thinkfan-wakeup.service 2>/dev/null && wakeup=1; auto_cfg=1; for c in /etc/thinkfan.yaml /etc/thinkfan.conf; do if [ -r \"$c\" ]; then grep -Eq 'level[[:space:]]+auto|\"auto\"' \"$c\" || auto_cfg=0; break; fi; done; proc=0; pgrep -x thinkfan >/dev/null 2>&1 && proc=1; printf 'META:wakeup=%s,autoCfg=%s,proc=%s\\n' \"$wakeup\" \"$auto_cfg\" \"$proc\"; fi; printf 'HELPER:%s\\n' \"$p\"; exec \"$p\" --status; fi; done; exit 127",
            "sh", root.helperPath, root.packagedHelperPath, root.probeSystemSleepMeta ? "1" : "0"
        ]

        stdout: SplitParser {
            onRead: data => {
                const line = String(data ?? "").trim()
                if (line.startsWith("META:")) {
                    root._wakeupUnitEnabled = line.includes("wakeup=1")
                    root._configAllowsAutoLevel = !line.includes("autoCfg=0")
                    root._daemonRunning = line.includes("proc=1")
                    return
                }
                if (line.startsWith("HELPER:")) {
                    const resolved = line.slice(7).trim()
                    if (resolved.startsWith("/usr/libexec/") && root.helperPath === "/usr/libexec/alis-thinkfan")
                        root.helperPath = resolved
                    return
                }
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
            const succeeded = exitCode === 0 && !applyProcess.timedOut
            const errCode = applyProcess.timedOut
                ? "apply-timeout" : (exitCode === 0 ? "" : "apply-failed")
            if (!succeeded) {
                if (applyProcess.timedOut)
                    console.warn("[ThinkFan] Timed out while applying fan-control intent")
                else
                    console.warn("[ThinkFan] Failed to apply fan-control intent (exit code " + exitCode + ")")
            }
            root.lastApplySucceeded = succeeded
            root.lastApplyError = errCode
            const intentTarget = root._pendingManagedIntentValue
            root._pendingManagedIntentValue = ""
            root.pendingOperation = ""
            if (succeeded && Config.ready && intentTarget.length > 0
                    && (completedOperation === "profile:managed" || completedOperation === "profile:firmware")) {
                const desiredManaged = completedOperation === "profile:managed"
                if (root.managedIntentEnabled !== desiredManaged && typeof Config.setNestedValue === "function") {
                    Config.setNestedValue("powerProfiles.fanControl.managed", desiredManaged)
                    if (typeof Config.flushWrites === "function")
                        Config.flushWrites()
                }
            }

            Qt.callLater(() => {
                if (!root._live)
                    return
                root.busy = false
                if (completedOperation === "profile:firmware"
                        && root._reapplyManagedAfterBounce) {
                    root._reapplyManagedAfterBounce = false
                    if (succeeded) {
                        root.applyProfile("managed")
                        return
                    }
                } else if (succeeded
                        && completedOperation === "profile:firmware"
                        && root.profileFanControlEnabled) {
                    root._queuedFanLevel = ""
                    root.applyConfiguredPowerProfileFanLevel()
                    return
                } else if (root._queuedFanLevel.length > 0) {
                    root._drainQueuedFanLevel()
                    return
                }
                root.refresh()
            })
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
        id: resumeFirstPassTimer
        interval: root.resumeFirstPassDelayMs
        repeat: false
        onTriggered: {
            if (!root._live)
                return
            root.refresh()
        }
    }

    Timer {
        id: resumeSecondPassTimer
        interval: root.resumeSecondPassDelayMs
        repeat: false
        onTriggered: {
            if (!root._live)
                return
            root._resumeSecondPass = true
            root._lastStatusRefreshAt = 0
            root.refresh()
        }
    }

    Process {
        id: dbusSleepMonitor
        property bool awaitingSleepArg: false
        property bool binaryMissing: false
        running: root._live && root.sleepMonitorEnabled && !dbusSleepMonitor.binaryMissing
        Component.onDestruction: dbusSleepMonitor.running = false
        command: [
            "/bin/sh", "-c",
            "command -v dbus-monitor >/dev/null 2>&1 || exit 127; exec dbus-monitor --system \"type='signal',interface='org.freedesktop.login1.Manager',member='PrepareForSleep'\""
        ]
        stdout: SplitParser {
            onRead: data => {
                const line = String(data ?? "").trim()
                if (line.includes("member=PrepareForSleep")) {
                    dbusSleepMonitor.awaitingSleepArg = true
                    return
                }
                if (!dbusSleepMonitor.awaitingSleepArg)
                    return
                if (line === "boolean true") {
                    dbusSleepMonitor.awaitingSleepArg = false
                    root.handlePrepareForSleep(true)
                } else if (line === "boolean false") {
                    dbusSleepMonitor.awaitingSleepArg = false
                    root.handlePrepareForSleep(false)
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            dbusSleepMonitor.awaitingSleepArg = false
            if (exitCode === 127) {
                dbusSleepMonitor.binaryMissing = true
                return
            }
            if (root._live && root.sleepMonitorEnabled)
                dbusSleepMonitorRestart.restart()
        }
    }

    Timer {
        id: dbusSleepMonitorRestart
        interval: 5000
        repeat: false
        onTriggered: {
            if (root._live && root.sleepMonitorEnabled && !dbusSleepMonitor.binaryMissing && !dbusSleepMonitor.running)
                dbusSleepMonitor.running = true
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
        onTriggered: {
            const now = Date.now()
            if (root._lastWatchdogWallMs > 0 && (now - root._lastWatchdogWallMs) > statusRefreshTimer.interval + 45000) {
                root._lastWatchdogWallMs = now
                root.handleSuspendResume()
                return
            }
            root._lastWatchdogWallMs = now
            root.refresh()
        }
    }
}
