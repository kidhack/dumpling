"""Write markdown draft files to ~/Dumpling/Drafts/ (LinkedIn posts, project specs, etc.)."""

import os
from datetime import datetime
from typing import Optional


DRAFTS_DIR = os.path.expanduser(os.getenv("DUMPLING_DRAFTS_DIR", "~/Dumpling/Drafts"))


def write_draft_file(
    filename: str,          # e.g. "linkedin_post_2026-03-20.md"
    content: str,
    subfolder: Optional[str] = None,   # e.g. "linkedin", "projects", "ideas"
) -> dict:
    """
    Write content to a markdown file in ~/Dumpling/Drafts/.

    Returns {"success": True, "path": "..."} or {"success": False, "error": "..."}
    """
    try:
        base = DRAFTS_DIR
        if subfolder:
            base = os.path.join(base, subfolder)
        os.makedirs(base, exist_ok=True)

        # Sanitize filename
        safe_name = "".join(c for c in filename if c.isalnum() or c in "._- ").strip()
        if not safe_name.endswith(".md"):
            safe_name += ".md"

        path = os.path.join(base, safe_name)

        # If file exists, version it
        if os.path.exists(path):
            ts = datetime.now().strftime("%H%M%S")
            safe_name = safe_name.replace(".md", f"_{ts}.md")
            path = os.path.join(base, safe_name)

        with open(path, "w", encoding="utf-8") as f:
            f.write(content)

        return {"success": True, "path": path, "message": f"Draft saved: {path}"}
    except Exception as e:
        return {"success": False, "error": str(e)}


def create_linkedin_draft(title: str, body: str, hashtags: Optional[list[str]] = None) -> dict:
    """Convenience wrapper: create a LinkedIn post draft."""
    ts = datetime.now().strftime("%Y-%m-%d")
    slug = title[:40].lower().replace(" ", "_").replace("/", "-")
    filename = f"linkedin_{ts}_{slug}.md"

    tags_section = ""
    if hashtags:
        tags_section = "\n\n---\n**Hashtags:** " + " ".join(f"#{t.lstrip('#')}" for t in hashtags)

    content = f"""# {title}

*Draft created by Dumpling on {datetime.now().strftime("%B %d, %Y")}*

---

{body}{tags_section}
"""
    return write_draft_file(filename, content, subfolder="linkedin")


def create_project_spec(name: str, description: str, ideas: str = "", tech_notes: str = "") -> dict:
    """Convenience wrapper: create a software project spec draft."""
    ts = datetime.now().strftime("%Y-%m-%d")
    slug = name[:40].lower().replace(" ", "_").replace("/", "-")
    filename = f"project_{ts}_{slug}.md"

    content = f"""# Project: {name}

*Spec drafted by Dumpling on {datetime.now().strftime("%B %d, %Y")}*

---

## Overview
{description}

## Ideas & Features
{ideas or "_To be filled in_"}

## Tech Notes
{tech_notes or "_To be filled in_"}

## Next Steps
- [ ] Research existing solutions
- [ ] Define MVP scope
- [ ] Identify tech stack

---
*Auto-generated spec — edit freely*
"""
    return write_draft_file(filename, content, subfolder="projects")
