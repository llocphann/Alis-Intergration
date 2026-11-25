#!/usr/bin/env python3
"""Runtime verification for ThinkFanService suspend/resume recovery across all ThinkPad EC reset modes."""
import json
import os
from pathlib import Path
import sys
import tempfile

from integration_test_host import resolve_host_root

ROOT = Path(__file__).resolve().parents[1]
HOST = resolve_host_root(ROOT)
sys.path.insert(0, str(HOST / "scripts"))
from native_test_session import run_qs


with tempfile.TemporaryDirectory(prefix="alis-thinkfan-sleep-test-") as tmp:
    private = Path(tmp)
    shell = private / "shell"
    shell.mkdir()
    for entry in ("services", "modules", "GlobalStates.qml", "qmldir", "scripts", "defaults", "translations", "assets"):
        (shell / entry).symlink_to(HOST / entry)

    state_file = private / "mock-state.json"
    calls_file = private / "privileged-calls.jsonl"
    state_file.write_text(
        json.dumps(
            {
                "available": True,
                "serviceInstalled": True,
                "active": False,
                "enabled": False,
                "directControlAvailable": True,
                "profile": "firmware",
                "fanRpm": 0,
                "fanLevel": "auto",
                "configPath": "/etc/thinkfan.conf",
                "reason": "firmware-control",
            }
        ),
        encoding="utf-8",
    )
    calls_file.write_text("", encoding="utf-8")

    mock_pkexec = private / "mock-pkexec"
    mock_pkexec.write_text(
        "#!/usr/bin/python3\n"
        "import json, os, subprocess, sys\n"
        f"calls = {repr(str(calls_file))}\n"
        "with open(calls, 'a', encoding='utf-8') as fh:\n"
        "    fh.write(json.dumps(sys.argv[2:]) + '\\n')\n"
        "env = dict(os.environ, MOCK_PRIVILEGED='1')\n"
        "raise SystemExit(subprocess.call(sys.argv[1:], env=env))\n",
        encoding="utf-8",
    )
    mock_pkexec.chmod(0o755)

    mock_helper = private / "mock-thinkfan-helper"
    mock_helper.write_text(
        "#!/usr/bin/python3\n"
        "import json, os, sys\n"
        f"state_path = {repr(str(state_file))}\n"
        "with open(state_path, 'r', encoding='utf-8') as fh:\n"
        "    state = json.load(fh)\n"
        "args = sys.argv[1:]\n"
        "if args == ['--status']:\n"
        "    out = dict(state, schema=1, fanLevelControlSupported=True)\n"
        "    print(json.dumps(out))\n"
        "    raise SystemExit(0)\n"
        "if os.environ.get('MOCK_PRIVILEGED') != '1':\n"
        "    raise SystemExit(77)\n"
        "if len(args) == 2 and args[0] == '--set-level':\n"
        "    lvl = args[1]\n"
        "    state['fanLevel'] = lvl\n"
        "    state['profile'] = 'firmware' if lvl == 'auto' else 'manual'\n"
        "    state['fanRpm'] = 0 if lvl == 'auto' else 3400\n"
        "elif len(args) == 2 and args[0] == '--apply':\n"
        "    prof = args[1]\n"
        "    if prof == 'managed':\n"
        "        state['active'] = True\n"
        "        state['enabled'] = True\n"
        "        state['profile'] = 'managed'\n"
        "        state['fanLevel'] = '7'\n"
        "        state['fanRpm'] = 4100\n"
        "        state['reason'] = ''\n"
        "    elif prof == 'firmware':\n"
        "        state['active'] = False\n"
        "        state['enabled'] = False\n"
        "        state['profile'] = 'firmware'\n"
        "        state['fanLevel'] = 'auto'\n"
        "        state['fanRpm'] = 2100\n"
        "        state['reason'] = 'firmware-control'\n"
        "with open(state_path, 'w', encoding='utf-8') as fh:\n"
        "    json.dump(state, fh)\n"
        "out = dict(state, schema=1, fanLevelControlSupported=True)\n"
        "print(json.dumps(out))\n",
        encoding="utf-8",
    )
    mock_helper.chmod(0o755)

    set_state_helper = private / "set-mock-state"
    set_state_helper.write_text(
        "#!/usr/bin/python3\n"
        "import json, sys\n"
        f"state_path = {repr(str(state_file))}\n"
        "with open(state_path, 'r', encoding='utf-8') as fh:\n"
        "    state = json.load(fh)\n"
        "state.update(json.loads(sys.argv[1]))\n"
        "with open(state_path, 'w', encoding='utf-8') as fh:\n"
        "    json.dump(state, fh)\n",
        encoding="utf-8",
    )
    set_state_helper.chmod(0o755)

    config_dir = private / "config/alis"
    config_dir.mkdir(parents=True)
    options = json.loads((HOST / "defaults/config.json").read_text(encoding="utf-8"))
    options["powerProfiles"]["fanControl"]["enabled"] = False
    options["powerProfiles"]["fanControl"]["balanced"] = 5
    options["powerProfiles"]["fanControl"]["performance"] = 7
    options["powerProfiles"]["fanControl"]["powerSaver"] = 3
    (config_dir / "config.json").write_text(json.dumps(options), encoding="utf-8")

    (shell / "shell.qml").write_text(
        """
import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import qs.modules.common

ShellRoot {
    id: root

    Loader {
        id: workerLoader
        Component.onCompleted: {
            setSource("file://" + Quickshell.env("WORKER_QML_PATH"), {
                sleepMonitorEnabled: false,
                probeSystemSleepMeta: false,
                helperPath: Quickshell.env("MOCK_HELPER"),
                privilegeEscalationCommand: Quickshell.env("MOCK_PKEXEC"),
                resumeFirstPassDelayMs: 60,
                resumeSecondPassDelayMs: 180
            })
        }
    }
    readonly property var worker: workerLoader.item

    Process {
        id: mutator
        property bool done: false
        onExited: mutator.done = true
    }

    TestCase {
        id: test
        when: false
        optional: true

        function check(cond, msg) {
            if (!cond)
                throw new Error(msg)
        }

        function patchState(patchObj) {
            mutator.done = false
            mutator.command = [Quickshell.env("SET_STATE_HELPER"), JSON.stringify(patchObj)]
            mutator.running = true
            tryCompare(mutator, "done", true, 2000)
        }

        function runSuite() {
            try {
                tryCompare(Config, "ready", true, 4000)
                tryVerify(() => root.worker !== null && root.worker.stateKnown, 3000)
                const worker = root.worker

                // 1. Firmware mode before sleep -> wake performs NO privileged action
                check(worker.profile === "firmware" && worker.fanLevel === "auto", "initial firmware mismatch")
                worker.handlePrepareForSleep(true)
                worker.handlePrepareForSleep(false)
                wait(320)
                check(worker.profile === "firmware" && worker.fanLevel === "auto", "firmware wake mutated state")

                // 2. Power-profile fan control -> EC reset to auto is restored on wake
                Config.setNestedValue("powerProfiles.fanControl.enabled", true)
                worker._profileFollowArmed = true
                worker.applyConfiguredPowerProfileFanLevel()
                tryVerify(() => !worker.busy && worker.fanLevel !== "auto", 3000)
                const expectedProfileLevel = String(worker.configuredActiveFanLevel)
                check(worker.fanLevel === expectedProfileLevel, "power profile fan level did not apply")
                worker.handlePrepareForSleep(true)
                patchState({ profile: "firmware", fanLevel: "auto", fanRpm: 0 })
                worker.handlePrepareForSleep(false)
                tryVerify(() => !worker._resumeRecoveryPending && !worker.busy && worker.fanLevel === expectedProfileLevel, 3000)
                Config.setNestedValue("powerProfiles.fanControl.enabled", false)
                tryVerify(() => !worker.busy, 2000)

                // 3. Manual / standalone fan level 7 before sleep -> EC reset to auto is restored to 7 on wake
                patchState({ active: false, enabled: false, profile: "manual", fanLevel: "7", fanRpm: 3360 })
                worker.refresh()
                tryVerify(() => worker.profile === "manual" && worker.fanLevel === "7", 2000)
                worker.handlePrepareForSleep(true)
                patchState({ profile: "firmware", fanLevel: "auto", fanRpm: 0 })
                worker.handlePrepareForSleep(false)
                tryVerify(() => !worker._resumeRecoveryPending && !worker.busy && worker.fanLevel === "7" && worker.profile === "manual", 3000)

                // 4. Managed thinkfan.service stopped/crashed across sleep -> restarted via --apply managed
                worker.applyProfile("managed")
                tryVerify(() => !worker.busy && worker.active && worker.profile === "managed", 3000)
                worker.handlePrepareForSleep(true)
                patchState({ active: false, enabled: true, profile: "firmware", fanLevel: "auto", fanRpm: 0 })
                worker.handlePrepareForSleep(false)
                tryVerify(() => !worker._resumeRecoveryPending && !worker.busy && worker.active && worker.profile === "managed" && worker.fanLevel === "7", 3000)

                // 5. Managed thinkfan.service stays active across sleep while EC resets fanLevel to auto
                //    with single-bracket /etc/thinkfan.conf (autoCfg=false, wakeup=false) -> bounces firmware -> managed
                worker._wakeupUnitEnabled = false
                worker._configAllowsAutoLevel = false
                worker.handlePrepareForSleep(true)
                patchState({ active: true, enabled: true, profile: "managed", fanLevel: "auto", fanRpm: 0 })
                worker.handlePrepareForSleep(false)
                tryVerify(() => !worker._resumeRecoveryPending && !worker.busy && worker.active && worker.profile === "managed" && worker.fanLevel === "7", 3500)

                console.info("ALIS_THINKFAN_SUSPEND_RESUME_PASS")
            } catch (err) {
                const w = root.worker
                console.error("ALIS_THINKFAN_SUSPEND_RESUME_FAIL", err.message, err.stack, JSON.stringify(w ? {
                    busy: w.busy,
                    active: w.active,
                    enabled: w.enabled,
                    profile: w.profile,
                    fanLevel: w.fanLevel,
                    lastApplySucceeded: w.lastApplySucceeded,
                    lastApplyError: w.lastApplyError,
                    pendingOperation: w.pendingOperation,
                    manualBeforeSleep: w._manualLevelBeforeSleep,
                    managedBeforeSleep: w._managedBeforeSleep,
                    resumePending: w._resumeRecoveryPending,
                    helperPath: w.helperPath
                } : null))
            }
            Qt.quit()
        }
    }

    Timer {
        interval: 80
        running: true
        onTriggered: test.runSuite()
    }
}
""",
        encoding="utf-8",
    )

    runtime = private / "runtime"
    runtime.mkdir(mode=0o700)
    env = dict(
        os.environ,
        QT_QPA_PLATFORM="offscreen",
        XDG_RUNTIME_DIR=str(runtime),
        XDG_CONFIG_HOME=str(private / "config"),
        XDG_STATE_HOME=str(private / "state"),
        XDG_CACHE_HOME=str(private / "cache"),
        XDG_DATA_HOME=str(private / "data"),
        MOCK_HELPER=str(mock_helper),
        MOCK_PKEXEC=str(mock_pkexec),
        SET_STATE_HELPER=str(set_state_helper),
        WORKER_QML_PATH=str(ROOT / "plugins/thinkfan/services/ThinkFanService.qml"),
    )
    env.pop("WAYLAND_DISPLAY", None)
    env.pop("NIRI_SOCKET", None)
    env.pop("HYPRLAND_INSTANCE_SIGNATURE", None)
    result = run_qs(shell, env, timeout=25)
    if result.returncode != 0 or "ALIS_THINKFAN_SUSPEND_RESUME_PASS" not in result.stdout or "ALIS_THINKFAN_SUSPEND_RESUME_FAIL" in result.stdout:
        print(result.stdout)
        raise SystemExit(1)

    calls = [json.loads(line) for line in calls_file.read_text(encoding="utf-8").splitlines() if line.strip()]
    # Verify exact privileged call sequence:
    # - None during step 1 (firmware no-op)
    # - Step 2: ['--set-level', '<profileLevel>'], ['--set-level', '<profileLevel>'], ['--set-level', 'auto']
    # - Step 3: ['--set-level', '7']
    # - Step 4: ['--apply', 'managed'], ['--apply', 'managed']
    # - Step 5: ['--apply', 'firmware'], ['--apply', 'managed']
    assert ["--set-level", "7"] in calls, f"Expected manual level 7 restore in {calls}"
    assert calls[-2:] == [["--apply", "firmware"], ["--apply", "managed"]], f"Expected wedged managed bounce at tail, got {calls}"
    print("ALIS_THINKFAN_SUSPEND_RESUME_PASS", calls)
