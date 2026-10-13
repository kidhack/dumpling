"""Ask Claude what to do with one shared item. Returns a validated Decision; never touches apps."""

from datetime import datetime
from typing import Literal, Optional

import anthropic
from pydantic import BaseModel, Field

MODEL = "claude-opus-5-5"

SYSTEM_PROMPT = """You file things the user shared from their phone into Apple apps on their Mac.

Pick exactly one action:
- create_event: a specific happening with a date (concert, dinner, appointment, tour). Needs start; set end too (default to 2 hours after start if unknown). Use all_day for date-only events.
- create_reminder: something the user should do (buy, call, book, read by a date). Set due only if a date is stated or clearly implied.
- create_note: anything to keep or read later (articles, links, ideas, recipes, products) and anything you're unsure about. This is the safe default.
- draft_email: only when the user's note explicitly asks to email someone.

The user's note and quick tag express intent and outrank your own reading of the content. Tag meanings: reminder, event, music, software_idea (an app idea, keep as a note), link_save (save the link as a note).

Writing rules:
- title: 2-6 words, specific, no "Reminder to"/"Remember to" prefixes, no URLs.
- notes: the URL on its own line, then the user's note, then useful details. Plain text.
- Dates are local time, formatted YYYY-MM-DDTHH:MM. Resolve relative dates against the current time given with the item. Never invent a date that isn't stated or clearly implied.
- summary: one short line describing what you filed, for the user to read later.

You can't open links; work from the URL, text, note, and tag you're given."""


class Decision(BaseModel):
    content_type: Literal["event", "reminder", "link", "idea", "music", "note", "email", "unknown"]
    action: Literal["create_reminder", "create_event", "create_note", "draft_email"]
    title: str
    notes: str
    summary: str
    due: Optional[str] = Field(None, description="Reminder due time, YYYY-MM-DDTHH:MM local")
    start: Optional[str] = Field(None, description="Event start, YYYY-MM-DDTHH:MM local")
    end: Optional[str] = Field(None, description="Event end, YYYY-MM-DDTHH:MM local")
    all_day: bool = False
    location: Optional[str] = None
    email_to: Optional[str] = None
    email_subject: Optional[str] = None
    email_body: Optional[str] = None


class Refused(RuntimeError):
    pass


def describe_item(item: dict, now: datetime) -> str:
    lines = [f"Current local time: {now.strftime('%A %Y-%m-%d %H:%M')}"]
    for label, key in (("URL", "content_url"), ("Text", "content_text"), ("User note", "user_note"),
                       ("Quick tag", "quick_tag"), ("Shared from", "source_app")):
        if item.get(key):
            lines.append(f"{label}: {item[key]}")
    return "\n".join(lines)


def decide(client: anthropic.Anthropic, item: dict, now: datetime) -> Decision:
    response = client.beta.messages.parse(
        model=MODEL,
        max_tokens=4096,
        system=SYSTEM_PROMPT,
        messages=[{"role": "user", "content": describe_item(item, now)}],
        output_format=Decision,
        output_config={"effort": "low"},
        betas=["server-side-fallback-2026-07-01"],
        fallbacks="default",
    )
    if response.stop_reason == "refusal":
        raise Refused("Claude declined to process this item")
    if response.parsed_output is None:
        raise RuntimeError(f"No structured output (stop_reason={response.stop_reason})")
    return response.parsed_output
