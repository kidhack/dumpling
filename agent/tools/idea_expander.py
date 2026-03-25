"""Expand a raw software idea into a structured note via Anthropic API."""

import os
import re
from typing import Any

import anthropic


SYSTEM_PROMPT = """You are a technical co-founder helping to quickly evaluate and structure a software idea.
Given a raw idea, produce a structured note. Be concise. Return plain text with markdown headings. No preamble, no sign-off."""


def expand_software_idea(raw_idea: str) -> dict[str, Any]:
    """
    Call Anthropic API to expand a raw software idea into a structured note.
    Returns {"title_slug": "...", "body": "..."} or {"error": "..."} on failure.
    """
    model = os.getenv("CLAUDE_MODEL", "claude-sonnet-4-20250514")

    user_prompt = f"""Raw idea: {raw_idea}

Produce a structured note with: ## Problem, ## MVP, ## Architecture, ## Open questions, ## Links (leave empty).
Also return a title slug: 2-4 words, title case. Format:
TITLE: {{slug}}
---
{{note body}}"""

    try:
        client = anthropic.Anthropic(api_key=os.getenv("ANTHROPIC_API_KEY"))
        response = client.messages.create(
            model=model,
            max_tokens=1000,
            system=SYSTEM_PROMPT,
            messages=[{"role": "user", "content": user_prompt}],
        )

        text = ""
        for block in response.content:
            if hasattr(block, "text"):
                text += block.text

        if not text.strip():
            return {"error": "Empty API response"}

        parts = text.split("---", 1)
        if len(parts) < 2:
            return {"error": "Response missing --- delimiter"}

        title_line = parts[0].strip()
        body = parts[1].strip()

        m = re.search(r"TITLE:\s*(.+)", title_line, re.IGNORECASE)
        title_slug = m.group(1).strip() if m else "Software Idea"

        return {"title_slug": title_slug, "body": body}

    except Exception as e:
        return {"error": str(e)}
