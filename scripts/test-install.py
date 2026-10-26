#!/usr/bin/env python3
"""Owned-link, exact-source and helper staging contracts; never uses the desktop."""
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
    data = private / "data/alis-intergration"
    data.mkdir(parents=True)
    release = installer.install(data, source)
    assert (data / "current").resolve() == release
    before = (release / "manifest.json").read_bytes()
    assert installer.install(data, source) == release
    assert (release / "manifest.json").read_bytes() == before
    manifest = json.loads(before)
    assert all(installer.digest(release / path) == digest for path, digest in manifest["files"].items())

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
    (release / "services/unlisted.qml").symlink_to(source / "README.md")
    expect_reinstall_rejected("linked release payload accepted")
    (release / "services/unlisted.qml").unlink()
    pycache = release / "scripts/todo/__pycache__"
    pycache.mkdir(parents=True, exist_ok=True)
    (pycache / "obsidian_todo.cpython-314.pyc").write_bytes(b"bytecode")
    assert installer.install(data, source) == release
    (pycache / "unlisted.qml").write_text("unlisted")
    expect_reinstall_rejected("unlisted non-bytecode in __pycache__ accepted")
    (pycache / "unlisted.qml").unlink()
    (pycache / "linked.pyc").symlink_to(source / "README.md")
    expect_reinstall_rejected("symlink in __pycache__ accepted")
    (pycache / "linked.pyc").unlink()
    assert installer.install(data, source) == release

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
    stage = private / "system"
    subprocess.run(["make", "install-helpers", "DESTDIR=" + str(stage), "LIBEXECDIR=/custom/libexec",
                    "POLKIT_ACTIONS_DIR=/custom/share/polkit-1/actions", "ALIS_SYSTEM_SHAREDIR=/custom/share/alis",
                    "TLP_CONFDIR=/custom/etc/tlp.d"], cwd=source, check=True, stdout=subprocess.DEVNULL)
    assert (stage / "custom/libexec/alis-thinkfan").is_file()
    battery = stage / "custom/libexec/alis-battery-charge-limit"
    # Source only pure helper definitions under the fixture basename, so neither
    # root checks nor hardware actions run. Read the installed path assignments.
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
print("ALIS_INTERGRATION_INSTALL_PASS exact source, immutable release, owned link, idempotence, prefix/DESTDIR, no profiles")
