"""
Open addresses in Apple Maps.

Uses the `open` command (not osascript) — simpler and more reliable for
URL scheme launches on macOS. osascript would require an extra process and
is unnecessary for opening maps:// URLs.
"""

import subprocess
from urllib.parse import quote


def open_address_in_maps(address: str) -> dict:
    """
    Open an address in Apple Maps via the maps:// URL scheme.
    """
    try:
        encoded = quote(address, safe="")
        subprocess.run(
            ["open", f"maps://?q={encoded}"],
            check=True,
            capture_output=True,
            timeout=5,
        )
        return {"success": True, "message": "Opened in Maps"}
    except subprocess.CalledProcessError as e:
        return {"success": False, "error": str(e) or "Failed to open Maps"}
    except Exception as e:
        return {"success": False, "error": str(e)}
