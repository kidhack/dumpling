"""Open URLs in Safari."""

import subprocess
from typing import Any

from .escaping import escape_for_applescript


def open_url_in_safari(url: str) -> dict[str, Any]:
    """
    Open a URL in a new Safari tab.
    Returns {"success": True} or {"success": False, "error": "..."}.
    """
    url_esc = escape_for_applescript(url)
    script = f'''
tell application "Safari"
    activate
    tell window 1
        set current tab to (make new tab with properties {{URL:"{url_esc}"}})
    end tell
end tell
'''
    try:
        result = subprocess.run(
            ["osascript", "-e", script],
            capture_output=True,
            text=True,
            timeout=10,
        )
        if result.returncode != 0:
            return {"success": False, "error": result.stderr.strip() or result.stdout.strip()}
        return {"success": True}
    except subprocess.TimeoutExpired:
        return {"success": False, "error": "osascript timed out"}
    except Exception as e:
        return {"success": False, "error": str(e)}
