"""Create a draft email in Apple Mail via osascript."""

import subprocess
from typing import Optional


def create_mail_draft(
    subject: str,
    body: str,
    to_address: Optional[str] = None,
) -> dict:
    """
    Create a draft email in Apple Mail.
    Leaves it in Drafts (not sent) so the user can review and send.
    """
    subject_esc = subject.replace('"', '\\"')
    body_esc = body.replace('"', '\\"').replace('\n', '\\n')
    to_esc = (to_address or "").replace('"', '\\"')

    to_line = ""
    if to_address:
        to_line = f"""
            make new to recipient at newDraft with properties {{address:"{to_esc}"}}
"""

    script = f"""
tell application "Mail"
    set newDraft to make new outgoing message with properties {{
        subject:"{subject_esc}",
        content:"{body_esc}",
        visible:false
    }}
    {to_line}
    save newDraft
end tell
"""

    try:
        result = subprocess.run(
            ["osascript", "-e", script],
            capture_output=True, text=True, timeout=10
        )
        if result.returncode != 0:
            return {"success": False, "error": result.stderr.strip()}
        return {"success": True, "message": f"Mail draft created: {subject}"}
    except subprocess.TimeoutExpired:
        return {"success": False, "error": "osascript timed out"}
    except Exception as e:
        return {"success": False, "error": str(e)}
