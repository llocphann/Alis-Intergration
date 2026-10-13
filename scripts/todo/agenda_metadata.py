"""Read-only legacy Agenda metadata parser for existing Todo Markdown.

No Agenda links are created or modified; unknown/invalid markup stays literal.
"""
import base64
import json
import re

MARKER = re.compile(r"\s*<!-- alis:agenda:v1:([A-Za-z0-9_-]+) -->$")
KEY = re.compile(r"agenda-[a-z0-9-]{8,96}$")


def split(content):
    match = MARKER.search(content)
    if not match or len(match[1]) > 32768:
        return content, None
    try:
        data = json.loads(base64.urlsafe_b64decode(match[1] + '=' * (-len(match[1]) % 4)))
        if data.get('version') != 1 or not isinstance(data.get('key'), str) or not KEY.fullmatch(data['key']):
            return content, None
        return content[:match.start()], data
    except (ValueError, TypeError, AttributeError):
        return content, None

