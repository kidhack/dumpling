"""Save software ideas to Notes.app Coding folder with API expansion."""

import os
import re
from datetime import datetime

from .apple_notes import create_note_in_folder
from .escaping import escape_for_applescript
from .idea_expander import expand_software_idea


def create_software_idea_note(idea: str) -> dict:
    """
    Expand idea via API, save to Notes.app Coding folder.
    On expansion failure, saves raw idea with note "Expansion failed — raw idea saved".
    Appends Claude Coding project link if DUMPLING_CODING_PROJECT_ID is set.
    """
    result = expand_software_idea(idea)

    if "error" in result:
        body = f"{idea}\n\nExpansion failed — raw idea saved"
        slug = "Software Idea"
    else:
        body = result["body"]
        slug = result.get("title_slug") or "Software Idea"

    coding_project_id = os.getenv("DUMPLING_CODING_PROJECT_ID")
    if coding_project_id:
        links_block = f"\n\n## Links\nClaude Coding project: https://claude.ai/project/{coding_project_id}"
        body = body.rstrip()
        if "## Links" in body:
            # Replace empty ## Links section (with optional "leave empty" text) with link
            body = re.sub(r"\n## Links[^\n]*\s*$", links_block, body)
        else:
            body += links_block

    now = datetime.now()
    title = f"{now.strftime('%b')} {int(now.day)} · {slug}"

    return create_note_in_folder(
        folder="Coding",
        title=title,
        body=body,
    )
