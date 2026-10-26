#!/usr/bin/env python3
"""Parse extracted QML with the installed Qt 6 parser."""
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
files = sorted(root.rglob("*.qml"))
for path in files:
    subprocess.run(["/usr/lib/qt6/bin/qmlformat", str(path)], stdout=subprocess.DEVNULL, check=True)
print("ALIS_INTERGRATION_QML_PARSE_PASS", len(files))
