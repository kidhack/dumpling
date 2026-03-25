"""Create or append to a note in Apple Notes via osascript."""

import subprocess
from typing import Optional

from .escaping import escape_for_applescript


def create_note(
    title: str,
    body: str,
    folder: str = "Notes",
) -> dict:
    """Create a new note in Apple Notes. Uses folder if found under iCloud."""
    title_esc = escape_for_applescript(title)
    body_esc = escape_for_applescript(body)
    folder_esc = escape_for_applescript(folder)

    script = f'''
tell application "Notes"
    set theAccount to missing value
    repeat with a in accounts
        if name of a is "iCloud" then set theAccount to a
    end repeat
    if theAccount is missing value then set theAccount to default account
    set targetFolder to missing value
    repeat with f in (every folder of theAccount)
        if name of f is "{folder_esc}" then
            set targetFolder to f
            exit repeat
        end if
    end repeat
    if targetFolder is missing value then
        make new note at theAccount with properties {{name:"{title_esc}", body:"{body_esc}"}}
    else
        make new note at targetFolder with properties {{name:"{title_esc}", body:"{body_esc}"}}
    end if
end tell
'''
    return _run(script, f"Note created: {title}")


def get_note_titles_in_folder(folder: str) -> dict:
    """
    List all note titles in a folder. Returns {"success": True, "titles": [...]} or
    {"success": False, "error": "..."}. Used for duplicate detection (e.g. LinkedIn same-day).
    """
    folder_esc = escape_for_applescript(folder)
    script = f'''
tell application "Notes"
    set theAccount to missing value
    repeat with a in accounts
        if name of a is "iCloud" then set theAccount to a
    end repeat
    if theAccount is missing value then
        return "ERROR:FOLDER_NOT_FOUND:No iCloud account"
    end if
    set targetFolder to missing value
    repeat with f in (every folder of theAccount)
        if name of f is "{folder_esc}" then
            set targetFolder to f
            exit repeat
        end if
    end repeat
    if targetFolder is missing value then
        return "ERROR:FOLDER_NOT_FOUND:No folder named {folder_esc} found in Notes.app"
    end if
    set titleList to {{}}
    repeat with n in (every note of targetFolder)
        set end of titleList to name of n
    end repeat
    set AppleScript's text item delimiters to "\\n"
    return titleList as text
end tell
'''
    try:
        result = subprocess.run(
            ["osascript", "-e", script],
            capture_output=True, text=True, timeout=10
        )
        out = (result.stdout or "").strip()
        err = (result.stderr or "").strip()
        if result.returncode != 0:
            return {"success": False, "error": err or out}
        if out.startswith("ERROR:"):
            parts = out.split(":", 2)
            return {"success": False, "error": parts[-1] if len(parts) > 2 else out}
        titles = [t.strip() for t in out.split("\n") if t.strip()]
        return {"success": True, "titles": titles}
    except subprocess.TimeoutExpired:
        return {"success": False, "error": "osascript timed out"}
    except Exception as e:
        return {"success": False, "error": str(e)}


def create_note_in_folder(folder: str, title: str, body: str) -> dict:
    """
    Create a note in a specific folder under iCloud. Returns note_id for
    notes://showNote?identifier={id} deep link. Errors if folder not found.
    """
    folder_esc = escape_for_applescript(folder)
    title_esc = escape_for_applescript(title)
    body_esc = escape_for_applescript(body)

    script = f'''
tell application "Notes"
    set theAccount to missing value
    repeat with a in accounts
        if name of a is "iCloud" then set theAccount to a
    end repeat
    if theAccount is missing value then
        return "ERROR:FOLDER_NOT_FOUND:No iCloud account"
    end if
    set targetFolder to missing value
    repeat with f in (every folder of theAccount)
        if name of f is "{folder_esc}" then
            set targetFolder to f
            exit repeat
        end if
    end repeat
    if targetFolder is missing value then
        return "ERROR:FOLDER_NOT_FOUND:No folder named {folder_esc} found in Notes.app"
    end if
    set newNote to make new note at targetFolder with properties {{name:"{title_esc}", body:"{body_esc}"}}
    return id of newNote
end tell
'''
    try:
        result = subprocess.run(
            ["osascript", "-e", script],
            capture_output=True, text=True, timeout=10
        )
        out = (result.stdout or "").strip()
        err = (result.stderr or "").strip()
        if result.returncode != 0:
            return {"success": False, "error": err or out}
        if out.startswith("ERROR:"):
            parts = out.split(":", 2)
            return {"success": False, "error": parts[-1] if len(parts) > 2 else out}
        return {
            "success": True,
            "note_id": out,
            "message": f"Note created: {title}",
        }
    except subprocess.TimeoutExpired:
        return {"success": False, "error": "osascript timed out"}
    except Exception as e:
        return {"success": False, "error": str(e)}


def append_to_note(
    note_title: str,
    content: str,
    folder: str = "Notes",
    create_if_missing: bool = True,
) -> dict:
    """
    Append content to an existing note. If the note doesn't exist and
    create_if_missing is True, create it.
    """
    note_title_esc = escape_for_applescript(note_title)
    content_esc = escape_for_applescript(content)
    folder_esc = escape_for_applescript(folder)

    # AppleScript: find the note, append to its body
    script = f'''
tell application "Notes"
    set matchedNotes to every note whose name is "{note_title_esc}"
    if (count of matchedNotes) > 0 then
        set theNote to item 1 of matchedNotes
        set body of theNote to (body of theNote) & "
" & "{content_esc}"
        return "appended"
    else
        set theAccount to missing value
        repeat with a in accounts
            if name of a is "iCloud" then set theAccount to a
        end repeat
        if theAccount is missing value then set theAccount to default account
        make new note at theAccount with properties {{name:"{note_title_esc}", body:"{content_esc}"}}
        return "created"
    end if
end tell
'''
    return _run(script, f"Note updated: {note_title}")


def _run(script: str, success_msg: str) -> dict:
    try:
        result = subprocess.run(
            ["osascript", "-e", script],
            capture_output=True, text=True, timeout=10
        )
        if result.returncode != 0:
            return {"success": False, "error": result.stderr.strip()}
        return {"success": True, "message": success_msg}
    except subprocess.TimeoutExpired:
        return {"success": False, "error": "osascript timed out"}
    except Exception as e:
        return {"success": False, "error": str(e)}
