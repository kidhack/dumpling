"""Create a calendar event in Apple Calendar via osascript."""

import subprocess
from typing import Optional

from .escaping import escape_for_applescript


def _apple_dt(dt) -> str:
    """Format datetime for AppleScript date coercion."""
    return dt.strftime("%A, %B %d, %Y at %I:%M:%S %p")


def create_calendar_event(
    title: str,
    start_date: str,           # ISO: "2026-03-25T14:00:00"
    end_date: Optional[str] = None,    # ISO; defaults to start + 1 hour
    location: Optional[str] = None,
    notes: Optional[str] = None,
    calendar_name: str = "Social",
    url: Optional[str] = None,
) -> dict:
    """
    Create an event in Apple Calendar.

    Uses the "Social" calendar by default. Looks up calendar by name via
    repeat-with; if not found, returns error (no fallback).
    url = event page URL; notes/description = ticket link + price (per spec).

    Returns {"success": True, "message": "..."} or {"success": False, "error": "..."}
    """
    from datetime import datetime, timedelta

    try:
        start_dt = datetime.fromisoformat(start_date)
        if end_date:
            end_dt = datetime.fromisoformat(end_date)
        else:
            end_dt = start_dt + timedelta(hours=1)
    except ValueError as e:
        return {"success": False, "error": f"Invalid date: {e}"}

    esc_title = escape_for_applescript(title)
    esc_cal = escape_for_applescript(calendar_name)
    esc_location = escape_for_applescript(location or "")
    esc_notes = escape_for_applescript(notes or "")
    esc_url = escape_for_applescript(url or "")

    props = (
        f'summary: "{esc_title}", start date: date "{_apple_dt(start_dt)}", '
        f'end date: date "{_apple_dt(end_dt)}", location: "{esc_location}", '
        f'url: "{esc_url}", description: notesText'
    )
    script = f'''
tell application "Calendar"
    set targetCal to missing value
    repeat with c in calendars
        if name of c is "{esc_cal}" then
            set targetCal to c
            exit repeat
        end if
    end repeat

    if targetCal is missing value then
        error "CALENDAR_NOT_FOUND: No calendar named '{calendar_name}' found"
    end if

    set notesText to ""
    if "{esc_notes}" is not "" then
        set notesText to "{esc_notes}"
    end if

    set newEvent to make new event at end of events of targetCal with properties {{{props}}}
end tell
'''

    try:
        result = subprocess.run(
            ["osascript", "-e", script],
            capture_output=True, text=True, timeout=10
        )
        if result.returncode != 0:
            return {"success": False, "error": result.stderr.strip()}
        return {"success": True, "message": f"Event created: {title} on {_apple_dt(start_dt)}"}
    except subprocess.TimeoutExpired:
        return {"success": False, "error": "osascript timed out"}
    except Exception as e:
        return {"success": False, "error": str(e)}


def check_calendar_conflicts(
    start_date: str,
    end_date: str,
    exclude_title: Optional[str] = None,
) -> dict:
    """
    Check for events overlapping the given time window.
    Excludes events whose summary matches exclude_title (e.g. the one just created).

    Returns {"conflicts": [{"title": "...", "calendar": "...", "start": "..."}]}
    """
    from datetime import datetime

    try:
        start_dt = datetime.fromisoformat(start_date)
        end_dt = datetime.fromisoformat(end_date)
    except ValueError as e:
        return {"conflicts": [], "error": f"Invalid date: {e}"}

    esc_exclude = escape_for_applescript(exclude_title or "")

    # AppleScript outputs conflicts as "title|||calendar|||start" per line for easy parsing
    script = f'''
tell application "Calendar"
    set checkStart to date "{_apple_dt(start_dt)}"
    set checkEnd to date "{_apple_dt(end_dt)}"
    set output to ""

    repeat with c in calendars
        repeat with e in (events of c whose start date < checkEnd and end date > checkStart)
            if summary of e is not "{esc_exclude}" then
                set t to summary of e
                set cn to name of c
                set sd to start date of e
                set output to output & t & "|||" & cn & "|||" & (sd as text) & linefeed
            end if
        end repeat
    end repeat

    return output
end tell
'''

    try:
        # Calendar queries can be slow with many events; allow 30s
        result = subprocess.run(
            ["osascript", "-e", script],
            capture_output=True, text=True, timeout=30
        )
        if result.returncode != 0:
            return {"conflicts": [], "error": result.stderr.strip()}

        conflicts = []
        for line in (result.stdout or "").strip().split("\n"):
            if not line or "|||" not in line:
                continue
            parts = line.split("|||", 2)
            if len(parts) >= 3:
                conflicts.append({
                    "title": parts[0],
                    "calendar": parts[1],
                    "start": parts[2].strip(),
                })

        return {"conflicts": conflicts}
    except subprocess.TimeoutExpired:
        return {"conflicts": [], "error": "osascript timed out"}
    except Exception as e:
        return {"conflicts": [], "error": str(e)}
