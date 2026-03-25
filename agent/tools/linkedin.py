"""LinkedIn post draft pipeline — Notes + flagged Reminder."""

import re
from datetime import datetime
from typing import Optional

from . import apple_notes
from . import apple_reminders


def _next_linkedin_draft_title(folder: str, base_title: str) -> str:
    """
    If a note with base_title exists, append " 2". If " 2" exists, use " 3", etc.
    Per spec: same-day duplicates get "Jun 14 · LinkedIn Draft 2".
    """
    result = apple_notes.get_note_titles_in_folder(folder)
    if not result.get("success"):
        return base_title  # Fallback to base on error (create may still succeed)
    titles = set(result.get("titles", []))
    if base_title not in titles:
        return base_title
    # Find next available suffix: " 2", " 3", ...
    pattern = re.escape(base_title) + r" (\d+)$"
    max_n = 1
    for t in titles:
        m = re.match(pattern, t)
        if m:
            max_n = max(max_n, int(m.group(1)) + 1)
    return f"{base_title} {max_n}"


def create_linkedin_draft_note(
    body: str,
    due_date: Optional[str] = None,
) -> dict:
    """
    Create a LinkedIn post draft: note in Writing folder + flagged Reminder in
    LinkedIn list with notes deep link. Optional due_date for when to post.
    Same-day duplicates get title "Mar 23 · LinkedIn Draft 2", " 3", etc.
    """
    # Title format: "Mar 23 · LinkedIn Draft" (no leading zero on day)
    d = datetime.now()
    base_title = f"{d:%b} {d.day} · LinkedIn Draft"
    title = _next_linkedin_draft_title("Writing", base_title)

    # 1. Create note in Writing folder
    note_result = apple_notes.create_note_in_folder("Writing", title, body)
    if not note_result.get("success"):
        return note_result

    note_id = note_result.get("note_id", "")
    notes_deep_link = f"notes://showNote?identifier={note_id}" if note_id else ""

    # 2. Create flagged reminder in LinkedIn list
    reminder_title = f"Post: {title}"
    reminder_result = apple_reminders.create_flagged_reminder(
        title=reminder_title,
        body=notes_deep_link,
        list_name="LinkedIn",
        due_date=due_date,
    )
    if not reminder_result.get("success"):
        return {
            "success": True,  # Note was created
            "note_title": title,
            "note_id": note_id,
            "notes_deep_link": notes_deep_link,
            "reminder_error": reminder_result.get("error", "Reminder creation failed"),
        }

    return {
        "success": True,
        "note_title": title,
        "note_id": note_id,
        "notes_deep_link": notes_deep_link,
        "message": f"Saved to Writing: {title}. Reminder added to post it.",
    }
