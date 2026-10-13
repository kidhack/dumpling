"""Apple app actions via osascript.

User content is always passed as `on run argv` arguments, never interpolated into
script source, so shared text can't break or inject AppleScript.
"""

import html
import re
import subprocess
from datetime import datetime
from typing import List, Optional

_DATE_HANDLER = """
on mkdate(parts)
    set d to current date
    set day of d to 1
    set year of d to (item 1 of parts) as integer
    set month of d to (item 2 of parts) as integer
    set day of d to (item 3 of parts) as integer
    set hours of d to (item 4 of parts) as integer
    set minutes of d to (item 5 of parts) as integer
    set seconds of d to 0
    return d
end mkdate
"""


class AppleScriptError(RuntimeError):
    pass


def run_osascript(script: str, args: List[str], timeout: int = 60) -> str:
    result = subprocess.run(
        ["osascript", "-e", script, *args],
        capture_output=True, text=True, timeout=timeout,
    )
    if result.returncode != 0:
        raise AppleScriptError(result.stderr.strip() or "osascript failed")
    return result.stdout.strip()


def _date_args(value: Optional[datetime]) -> List[str]:
    if value is None:
        return ["", "", "", "", ""]
    return [str(value.year), str(value.month), str(value.day), str(value.hour), str(value.minute)]


def create_reminder(list_name: str, title: str, notes: str, due: Optional[datetime]) -> str:
    script = _DATE_HANDLER + """
on run argv
    set listName to item 1 of argv
    tell application "Reminders"
        if not (exists list listName) then make new list with properties {name:listName}
        set r to make new reminder at end of list listName with properties {name:(item 2 of argv), body:(item 3 of argv)}
        if (item 4 of argv) is not "" then set due date of r to my mkdate(items 4 thru 8 of argv)
    end tell
    return listName
end run
"""
    return run_osascript(script, [list_name, title, notes, *_date_args(due)])


def create_event(
    calendar_name: str, title: str, notes: str, start: datetime, end: datetime,
    location: str, all_day: bool,
) -> str:
    """Creates an event and returns the calendar's name. Empty calendar_name means the first writable calendar."""
    script = _DATE_HANDLER + """
on run argv
    set calName to item 1 of argv
    tell application "Calendar"
        if calName is "" then
            set cal to first calendar whose writable is true
        else
            set cal to calendar calName
        end if
        set props to {summary:(item 2 of argv), description:(item 3 of argv), location:(item 4 of argv), start date:my mkdate(items 6 thru 10 of argv), end date:my mkdate(items 11 thru 15 of argv), allday event:((item 5 of argv) is "1")}
        make new event at end of events of cal with properties props
        return name of cal
    end tell
end run
"""
    args = [calendar_name, title, notes, location, "1" if all_day else "0", *_date_args(start), *_date_args(end)]
    return run_osascript(script, args)


_URL_RE = re.compile(r"(https?://[^\s<]+)")


def notes_html(title: str, body: str) -> str:
    escaped = html.escape(body)
    linked = _URL_RE.sub(r'<a href="\1">\1</a>', escaped)
    return f"<h1>{html.escape(title)}</h1>" + "<br>".join(linked.splitlines())


def create_note(folder_name: str, title: str, body: str) -> str:
    script = """
on run argv
    set folderName to item 1 of argv
    tell application "Notes"
        if not (exists folder folderName) then make new folder with properties {name:folderName}
        make new note at folder folderName with properties {body:(item 2 of argv)}
    end tell
    return folderName
end run
"""
    return run_osascript(script, [folder_name, notes_html(title, body)])


def draft_email(to: str, subject: str, body: str) -> str:
    """Opens a Mail compose window for review. Never sends."""
    script = """
on run argv
    tell application "Mail"
        set m to make new outgoing message with properties {subject:(item 2 of argv), content:(item 3 of argv), visible:true}
        if (item 1 of argv) is not "" then
            tell m to make new to recipient at end of to recipients with properties {address:(item 1 of argv)}
        end if
    end tell
    return "Mail"
end run
"""
    return run_osascript(script, [to, subject, body])
