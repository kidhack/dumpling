"""Create a reminder via EventKit (Swift) or osascript — supports title, notes, due_date, list, flagged."""

import os
import re
import subprocess
from typing import Optional

from .escaping import escape_for_applescript

_SWIFT_BIN = os.path.join(os.path.dirname(__file__), "create_reminder")
_SWIFT_SCRIPT = os.path.join(os.path.dirname(__file__), "create_reminder.swift")

_BAD_TITLE_PREFIXES = re.compile(
    r"^(reminder to|remember to|don't forget to|dont forget to)\s+", re.IGNORECASE
)
_URL_RE = re.compile(r'https?://\S+')


def _clean_title(title: str) -> str:
    title = _BAD_TITLE_PREFIXES.sub("", title).strip()
    # Strip any URLs that leaked into the title
    title = _URL_RE.sub("", title).strip(" —-·")
    # Capitalise first letter
    if title:
        title = title[0].upper() + title[1:]
    # Truncate at a sensible boundary if still long
    if len(title) > 80:
        for sep in (" — ", " - ", ": "):
            if sep in title:
                title = title.split(sep)[0].strip()
                break
        else:
            title = title[:80].rsplit(" ", 1)[0]
    return title


def create_reminder(
    title: str,
    due_date: Optional[str] = None,
    notes: Optional[str] = None,
    tag: Optional[str] = None,
    list_name: str = "Now",
) -> dict:
    """
    Create a reminder via EventKit Swift script.
    Supports title, notes, due_date, and list_name.
    URLs should go in notes — Apple does not expose the Reminders URL field to any external API.
    """
    title = _clean_title(title)

    runner = _SWIFT_BIN if os.path.exists(_SWIFT_BIN) else ["swift", _SWIFT_SCRIPT]
    cmd = ([runner] if isinstance(runner, str) else runner) + ["--title", title, "--list", list_name]
    if notes:
        cmd += ["--notes", notes]
    if tag:
        cmd += ["--tag", tag]
    if due_date:
        cmd += ["--due", due_date]

    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        if result.returncode != 0 or result.stderr:
            return {"success": False, "error": result.stderr.strip() or result.stdout.strip()}
        return {"success": True, "message": f"Reminder created: {title}"}
    except subprocess.TimeoutExpired:
        return {"success": False, "error": "Swift script timed out"}
    except Exception as e:
        return {"success": False, "error": str(e)}


def create_flagged_reminder(
    title: str,
    body: str,
    list_name: str = "LinkedIn",
    due_date: Optional[str] = None,
) -> dict:
    """
    Create a flagged reminder in Reminders via osascript (Reminders supports flagged).
    Creates the list if it doesn't exist. Optional due_date (ISO format).
    """
    title = _clean_title(title)
    title_esc = escape_for_applescript(title)
    body_esc = escape_for_applescript(body)
    list_esc = escape_for_applescript(list_name)

    due_prop = ""
    if due_date:
        from datetime import datetime as dt
        try:
            for fmt in ("%Y-%m-%dT%H:%M:%S", "%Y-%m-%d"):
                try:
                    d = dt.strptime(due_date[:19], fmt)
                    as_date = f"{d.month}/{d.day}/{d.year}"
                    if "T" in due_date[:19]:
                        h12 = 12 if d.hour in (0, 12) else d.hour % 12
                        ampm = "AM" if d.hour < 12 else "PM"
                        as_date += f" {h12}:{d.minute:02d} {ampm}"
                    else:
                        as_date += " 12:00 AM"
                    due_prop = f', due date: date "{as_date}"'
                    break
                except ValueError:
                    continue
        except Exception:
            pass

    script = f'''
tell application "Reminders" to launch
tell application "Reminders"
    if not (exists list "{list_esc}") then
        make new list with properties {{name:"{list_esc}"}}
    end if
    tell list "{list_esc}"
        make new reminder with properties {{
            name:"{title_esc}",
            body:"{body_esc}",
            flagged:true{due_prop}
        }}
    end tell
end tell
'''
    try:
        result = subprocess.run(
            ["osascript", "-e", script],
            capture_output=True, text=True, timeout=15
        )
        if result.returncode != 0:
            return {"success": False, "error": (result.stderr or result.stdout or "").strip()}
        return {"success": True, "message": f"Flagged reminder created: {title}"}
    except subprocess.TimeoutExpired:
        return {"success": False, "error": "osascript timed out"}
    except Exception as e:
        return {"success": False, "error": str(e)}


def add_to_now_section(
    section_name: str,
    title: str,
    url: Optional[str] = None,
) -> dict:
    """
    Add item to the Now list. Section names (Watch, Dev, Later, Books, Places,
    Purchases, Gift ideas, 🎧 Music) are used as #tag in the body — Reminders
    sections have limited AppleScript support. Record must be single-line for
    osascript to avoid parse errors.
    """
    title_esc = escape_for_applescript(title)
    body_esc = escape_for_applescript(url or "")
    tag = escape_for_applescript(f" #{section_name.replace(' ', '-')}") if section_name else ""
    body_with_tag = (body_esc + tag) if tag else body_esc

    # Single-line record required — multiline causes "Expected expression, found end of line"
    script = (
        'tell application "Reminders" to launch\n'
        'tell application "Reminders"\n'
        '    tell list "Now"\n'
        f'        make new reminder with properties {{name:"{title_esc}", body:"{body_with_tag}", flagged:false}}\n'
        "    end tell\n"
        "end tell\n"
    )
    try:
        result = subprocess.run(
            ["osascript", "-e", script],
            capture_output=True, text=True, timeout=15
        )
        if result.returncode != 0:
            return {"success": False, "error": (result.stderr or result.stdout or "").strip()}
        return {
            "success": True,
            "message": f"Added to Now → {section_name}: {title}",
            "section": section_name,
        }
    except subprocess.TimeoutExpired:
        return {"success": False, "error": "osascript timed out"}
    except Exception as e:
        return {"success": False, "error": str(e)}
