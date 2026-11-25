#!/usr/bin/env python3
"""Owned-link, exact-source, lightweight base, per-plugin isolation and helper staging contracts."""
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("installer", ROOT / "scripts/install.py")
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)

with tempfile.TemporaryDirectory(prefix="alis-intergration-install-") as name:
    private = Path(name)
    source = private / "source"
    shutil.copytree(ROOT, source, ignore=shutil.ignore_patterns(".git", "__pycache__", "*.pyc"))
    for args in (("init", "-b", "main"), ("add", "."),
                 ("-c", "user.name=Fixture", "-c", "user.email=fixture@invalid", "commit", "-m", "fixture")):
        subprocess.run(["git", *args], cwd=source, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    # 1. Default install() installs lightweight base only; zero plugins pre-installed.
    data = private / "data/alis-intergration"
    data.mkdir(parents=True)
    release = installer.install(data, source)
    assert (data / "current").resolve() == release
    before = (release / "manifest.json").read_bytes()
    assert installer.install(data, source) == release
    assert (release / "manifest.json").read_bytes() == before
    manifest = json.loads(before)
    assert manifest["layout"] == "base-v2"
    assert set(manifest["files"]) == {"AlisSession.qml", "LICENSE"}
    assert all(installer.digest(release / path) == digest for path, digest in manifest["files"].items())
    assert not (release / "plugins").exists()
    assert not (data / "plugins").exists()
    assert json.loads((data / "installed-plugins.json").read_text()) == {"schemaVersion": 1, "plugins": []}

    # 2. Full assemble() bundles plugins/<id>/ with exact inventories.
    full_stage = private / "full-bundle"
    installer.assemble(source, full_stage, "f" * 40)
    full_manifest = json.loads((full_stage / "manifest.json").read_text())
    assert all(installer.digest(full_stage / path) == digest for path, digest in full_manifest["files"].items())
    for required_et in (
        "plugins/exercises_tracker/modules/dashboard/DashboardExercisesTracker.qml",
        "plugins/exercises_tracker/services/ExercisesTracker.qml",
        "plugins/exercises_tracker/services/ExercisesTrackerEngine.js",
        "plugins/exercises_tracker/scripts/integrations/exercises_tracker.py",
    ):
        assert required_et in full_manifest["files"], f"missing {required_et} in assembled release manifest"

    def expect_reinstall_rejected(reason):
        try:
            installer.install(data, source)
        except ValueError:
            return
        raise AssertionError(reason)

    original_manifest = (release / "manifest.json").read_text()
    omitted = dict(manifest)
    omitted["files"] = {name: value for name, value in manifest["files"].items()
                        if name != "AlisSession.qml"}
    (release / "manifest.json").write_text(json.dumps(omitted))
    expect_reinstall_rejected("missing mandatory digest entry accepted")
    (release / "manifest.json").write_text(original_manifest)
    (release / "unexpected.qml").write_text("unlisted")
    expect_reinstall_rejected("unlisted release payload accepted")
    (release / "unexpected.qml").unlink()
    (release / "plugins" / "unlisted").mkdir(parents=True)
    (release / "plugins" / "unlisted" / "bad.qml").symlink_to(source / "README.md")
    expect_reinstall_rejected("linked release payload accepted")
    shutil.rmtree(release / "plugins")

    original_source_manifest = (source / "manifest.json").read_text()
    for field, value in (("hostApi", 2), ("session", "Untrusted.qml")):
        incompatible = json.loads(original_source_manifest)
        incompatible[field] = value
        (source / "manifest.json").write_text(json.dumps(incompatible))
        try:
            installer.assemble(source, private / ("invalid-" + field), "a" * 40)
            raise AssertionError("incompatible manifest accepted: " + field)
        except ValueError:
            pass
    (source / "manifest.json").write_text(original_source_manifest)

    installer.uninstall(data)
    assert not (data / "current").exists() and release.exists()
    foreign = private / "foreign"
    foreign.mkdir()
    (data / "current").symlink_to(foreign)
    for action in (lambda: installer.install(data, source), lambda: installer.uninstall(data)):
        try:
            action()
            raise AssertionError("unowned link accepted")
        except ValueError:
            pass
    assert foreign.exists()
    (data / "current").unlink()

    # 3. Independent per-plugin install/remove copies ONLY that single plugin's files.
    plugin_data = private / "plugin-data"
    rel_single, enabled = installer.install_plugin(plugin_data, "nexus", source)
    assert rel_single.is_dir() and enabled == ["nexus"]
    assert json.loads((plugin_data / "installed-plugins.json").read_text()) == {"schemaVersion": 1, "plugins": ["nexus"]}
    assert sorted(p.name for p in (plugin_data / "plugins").iterdir()) == ["nexus"]
    nexus_manifest = json.loads((plugin_data / "plugins/nexus/plugin-manifest.json").read_text())
    assert nexus_manifest["id"] == "nexus"
    assert all(installer.digest(plugin_data / "plugins/nexus" / path) == digest for path, digest in nexus_manifest["files"].items())

    _, enabled = installer.install_plugin(plugin_data, "spaced_repetition", source)
    assert enabled == ["nexus", "spaced_repetition"]
    assert sorted(p.name for p in (plugin_data / "plugins").iterdir()) == ["nexus", "spaced_repetition"]
    _, enabled = installer.install_plugin(plugin_data, "exercises_tracker", source)
    assert enabled == ["nexus", "spaced_repetition", "exercises_tracker"]
    enabled = installer.remove_plugin(plugin_data, "nexus")
    assert enabled == ["spaced_repetition", "exercises_tracker"]
    assert not (plugin_data / "plugins/nexus").exists()
    assert sorted(p.name for p in (plugin_data / "plugins").iterdir()) == ["exercises_tracker", "spaced_repetition"]
    assert (plugin_data / "current").exists()
    installer.uninstall(plugin_data)
    assert not (plugin_data / "current").exists() and not (plugin_data / "installed-plugins.json").exists()
    assert not (plugin_data / "plugins").exists()

    # Reject symlinked installed-plugins.json, symlinked plugin dir, and unknown plugin ids.
    installer.install_base(plugin_data, source)
    (plugin_data / "plugins").mkdir(exist_ok=True)
    (plugin_data / "plugins/tlp").symlink_to(foreign)
    for bad in (lambda: installer.install_plugin(plugin_data, "tlp", source),
                lambda: installer.remove_plugin(plugin_data, "tlp"),
                lambda: installer.install_plugin(plugin_data, "unknown-plugin", source)):
        try:
            bad()
            raise AssertionError("unsafe or unknown plugin action accepted")
        except ValueError:
            pass
    (plugin_data / "plugins/tlp").unlink()
    (plugin_data / "installed-plugins.json").unlink()
    (plugin_data / "installed-plugins.json").symlink_to(foreign)
    for bad in (lambda: installer.install_plugin(plugin_data, "nexus", source),
                lambda: installer.remove_plugin(plugin_data, "nexus")):
        try:
            bad()
            raise AssertionError("symlinked installed-plugins.json accepted")
        except ValueError:
            pass

    (release / "AlisSession.qml").write_text("modified")
    try:
        installer.install(data, source)
        raise AssertionError("modified release accepted")
    except ValueError:
        pass
    (source / "README.md").write_text("uncommitted")
    try:
        installer.install(data, source)
        raise AssertionError("dirty source accepted")
    except ValueError:
        pass

    # 4. Separate Makefile helper installation targets (tlp and thinkfan independently + combined).
    stage_tlp = private / "system-tlp"
    subprocess.run(["make", "install-helpers-tlp", "DESTDIR=" + str(stage_tlp), "LIBEXECDIR=/custom/libexec",
                    "POLKIT_ACTIONS_DIR=/custom/share/polkit-1/actions", "ALIS_SYSTEM_SHAREDIR=/custom/share/alis",
                    "TLP_CONFDIR=/custom/etc/tlp.d"], cwd=source, check=True, stdout=subprocess.DEVNULL)
    assert (stage_tlp / "custom/libexec/alis-battery-charge-limit").is_file()
    assert not (stage_tlp / "custom/libexec/alis-thinkfan").exists()

    stage_fan = private / "system-fan"
    subprocess.run(["make", "install-helpers-thinkfan", "DESTDIR=" + str(stage_fan), "LIBEXECDIR=/custom/libexec",
                    "POLKIT_ACTIONS_DIR=/custom/share/polkit-1/actions"], cwd=source, check=True, stdout=subprocess.DEVNULL)
    assert (stage_fan / "custom/libexec/alis-thinkfan").is_file()
    assert not (stage_fan / "custom/libexec/alis-battery-charge-limit").exists()

    stage = private / "system"
    subprocess.run(["make", "install-helpers", "DESTDIR=" + str(stage), "LIBEXECDIR=/custom/libexec",
                    "POLKIT_ACTIONS_DIR=/custom/share/polkit-1/actions", "ALIS_SYSTEM_SHAREDIR=/custom/share/alis",
                    "TLP_CONFDIR=/custom/etc/tlp.d"], cwd=source, check=True, stdout=subprocess.DEVNULL)
    assert (stage / "custom/libexec/alis-thinkfan").is_file()
    battery = stage / "custom/libexec/alis-battery-charge-limit"
    result = subprocess.run(["sh", "-ec", '. "$1"; printf "%s\\n" "$config_dir" "$config_file" "$tlp_settings_config_file" "$tlp_settings_schema"',
                             "fixture", str(battery)], check=True, text=True, capture_output=True)
    assert result.stdout.splitlines() == ["/custom/etc/tlp.d", "/custom/etc/tlp.d/99-alis-battery-charge-limit.conf",
                                          "/custom/etc/tlp.d/99-alis-tlp-settings.conf", "/custom/share/alis/tlp-settings-schema.json"]
    for feature, helper in (("battery-charge-limit", "alis-battery-charge-limit"), ("thinkfan", "alis-thinkfan")):
        policy = ET.parse(stage / "custom/share/polkit-1/actions" / ("org.alis." + feature + ".policy"))
        assert policy.find('.//annotate[@key="org.freedesktop.policykit.exec.path"]').text == "/custom/libexec/" + helper
        assert policy.find('.//allow_any').text == "no"
        assert policy.find('.//allow_inactive').text == "no"
        assert policy.find('.//allow_active').text == "yes"
    assert (stage / "custom/share/alis/tlp-settings-schema.json").is_file()
    assert not (stage / "etc").exists() and not (stage / "custom/etc").exists()
print("ALIS_INTERGRATION_INSTALL_PASS base-v2 per-plugin-isolation exact-source immutable-release split-helpers")
