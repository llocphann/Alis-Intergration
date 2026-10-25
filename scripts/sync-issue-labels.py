#!/usr/bin/env python3
"""Idempotently apply Alis issue label colors to custom Integration labels only."""
import json
import os
import re
from pathlib import Path
from urllib.error import HTTPError
from urllib.parse import quote
from urllib.request import Request, urlopen

root = Path(__file__).resolve().parents[1]
palette = json.loads((root / ".github/issue-label-palette.json").read_text(encoding="utf-8"))
for name, item in palette.items():
    if not name.startswith(("area:", "status:", "complexity:")):
        raise SystemExit(f"Refusing noncustom label: {name}")
    if not re.fullmatch(r"[0-9a-fA-F]{6}", item["color"]):
        raise SystemExit(f"Invalid label color: {name}")
if not {"area:integration", "complexity:high", "status:blocked", "status:deferred", "status:awaiting-owner"} <= set(palette):
    raise SystemExit("Incomplete Integration label palette")

repository = os.environ.get("GITHUB_REPOSITORY", "")
token = os.environ.get("GITHUB_TOKEN", "")
if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository) or not token:
    raise SystemExit("Valid GITHUB_REPOSITORY and GITHUB_TOKEN are required")
base = f"https://api.github.com/repos/{repository}"
headers = {
    "Accept": "application/vnd.github+json",
    "Authorization": f"Bearer {token}",
    "X-GitHub-Api-Version": "2022-11-28",
    "User-Agent": "alis-integration-label-sync",
}

def api(method, path, payload=None):
    data = json.dumps(payload).encode("utf-8") if payload is not None else None
    request = Request(base + path, data=data, headers=headers, method=method)
    try:
        with urlopen(request, timeout=30) as response:
            return json.load(response)
    except HTTPError as exc:
        raise RuntimeError(f"{method} {path}: GitHub HTTP {exc.code}") from exc

existing = {}
page = 1
while True:
    entries = api("GET", f"/labels?per_page=100&page={page}")
    existing.update({entry["name"]: entry for entry in entries})
    if len(entries) < 100:
        break
    page += 1

created = updated = unchanged = 0
for name, item in palette.items():
    color, description = item["color"], item["description"]
    current = existing.get(name)
    if current is None:
        actual = api("POST", "/labels", {"name": name, "color": color, "description": description})
        created += 1
    elif current["color"].lower() != color.lower() or (current.get("description") or "") != description:
        actual = api("PATCH", "/labels/" + quote(name, safe=""), {"color": color, "description": description})
        updated += 1
    else:
        actual = current
        unchanged += 1
    if (actual.get("name") != name or actual.get("color", "").lower() != color.lower()
            or (actual.get("description") or "") != description):
        raise RuntimeError(f"Label sync readback mismatch: {name}")
    print(f"Verified {name}: #{color}")

print(f"INTEGRATION_LABEL_COLORS_PASS created={created} updated={updated} unchanged={unchanged} total={len(palette)}")
