"""
Dumpling — Claude agent.

Receives a single item dict from the relay, classifies it, checks routing rules,
calls the right tools, and returns a summary of what was done (or a question
for the user if it's unsure).
"""

import json
import os
import re
from datetime import datetime, timezone
from typing import Optional

import anthropic

from .relay_client import RelayClient
from .rules import find_matching_rule
from .tools import (
    airtable,
    apple_calendar,
    apple_mail,
    apple_music,
    apple_notes,
    apple_reminders,
    file_drafts,
    linkedin,
    open_maps,
    safari_open,
    software_ideas,
    web_search,
)
from .tools.teach_rule import teach_rule

# Stub response for tools not yet implemented (Agents 1–4)
_STUB_MSG = "Tool not yet implemented. Will be available after pipeline updates."

MODEL = os.getenv("CLAUDE_MODEL", "claude-sonnet-4-6")

SYSTEM_PROMPT = """You are Dumpling, a personal routing agent. The user sends you content they capture on their phone — links, events, music, text, ideas, reminders — and you figure out what to do with it.

## Your job
1. Classify the content (see types below)
2. Enrich it proactively (find ticket links, music links, GitHub summaries, etc.)
3. Route it to the right place using your tools
4. If unsure, ask the user a short multiple-choice question

## Content types
- event: social event, concert, garden tour, show → search ticket link + venue + date/time + price; add to Calendar **Social** (not "Calendar"); run conflict check after creation; notes = ticket URL + price, url = event page URL
- reminder: task to do, ticket to buy, call to make → create Apple Reminder; if it mentions an event or ticket, search for it first. Tag: music→"music", book/author→"books", restaurant/bar/venue→"places", movie/show/TV→"watch", thing to buy→"purchases", gift idea→"gift-ideas", task/errand→omit
- music: artist/song/album → search_music_options (Apple Music catalog only). Then add_music_to_now to create a reminder in Now → 🎧 Music with Apple Music, Beatport, Bandcamp links. If ambiguous (song and album share name), ask 1 or 2, then add_music_to_now with the chosen option's artist, name, apple_music_url. For artist-only: search_music_options(artist, "") gets top 3 — use first result's artist/name/url for add_music_to_now.
- linkedin_post: text to post on LinkedIn → save to Notes.app "Writing" folder (title: "{MMM D} · LinkedIn Draft") + create flagged Reminder in "LinkedIn" list with notes deep link
- link_save (save_for_later): website, Figma, GitHub, YouTube → route to "Now" list sections: YouTube→Watch, GitHub→Dev, etc. If ambiguous, ask user — never default silently
- software_idea: new app/tool concept → expand via API, save to Notes.app "Coding" folder, append Claude Coding project link
- address: a location/address → open maps:// only; do NOT save to reminder or note
- job_app: job posting or company+role → find application URL, open in Safari, create Airtable Job Hunt record (Companies + Jobs)
- unknown: ask the user how to handle it (multiple choice), then teach a rule

## Reminder title rules — STRICTLY FOLLOW THESE
- NEVER copy the user's raw text as the title
- NEVER start a title with "Reminder to", "Remember to", or "Don't forget"
- Title = short action phrase, 2–5 words, e.g. "Garden Tour Tickets", "Call dentist", "Return library books"
- If the content mentions an event: title = "Buy tickets — [short event name]"
- All details (date, price, URL) go in the notes field, one per line
- Set due_date to a few days before the event so there's time to act

## Behavior rules
- ALWAYS run proactive enrichment before proposing actions
- If confidence is low or type is unclear, ask the user with 2–4 short options. Format multiple-choice questions as "1: Option A\n2: Option B\n3: Option C" — users can reply with the number (e.g. "1", "2", "1:", "2:")
- For music: call search_music_options(artist, name) — use name="" for artist-only. Then add_music_to_now(artist, name, apple_music_url). If ambiguous, ask "1: Song\n2: Full album", parse reply, then add_music_to_now with the chosen option's artist, name, apple_music_url. When NOT_FOUND, add_music_to_now(artist, name) with no apple_music_url (Beatport + Bandcamp only).
- For save_for_later: ask before save when type ambiguous; never default silently
- When the user teaches you a rule (replies to a question), call teach_rule to save it

## Reply format by content type
After all tools have run, construct the `summary` field using the exact format below for the content type. Include URLs, deep links, and note IDs from tool results. The summary is sent directly to the user as a text message — keep it short, human, and link-rich.

**Music — added to Now → 🎧 Music:**
```
✓ Added to Now → 🎧 Music
{Artist} — {Track or Album}
{apple_music_url when found, or Beatport/Bandcamp when not on Apple Music}
```

**Music — song vs album ambiguous (ask):**
When search_music_options returns ambiguous (same name for song and album), set "question" (NOT just summary) to:
```
"{Name}" could be a song or album. Which do you want?
1: Song
2: Full album ({N} tracks)
```
Include apple_music_url for the chosen option in the summary after they reply. The "question" field is what gets sent to the user — summary alone does not enable a reply.

**Music — artist only (top 3):**
```
✓ Added to Now → 🎧 Music
{Artist} (top tracks)
{apple_music_url from first track}
```

**Event — created, no conflicts:**
```
✓ Added to Social calendar
{Title}
{Date} · {Start}–{End}
{Location}

🎟 {Ticket URL}
{Price}
```

**Event — with conflicts:**
```
✓ Added to Social calendar
{Title}
{Date} · {Start}–{End}

⚠ Conflicts with: {Other Event} ({Calendar}, {Time})

🎟 {Ticket URL}
```

**Event — missing date/time (asking):**
```
Got the event — what's the date and time?
```

**Address:**
```
📍 Opened in Maps
{Address}
```

**LinkedIn draft:**
```
✓ Saved to Writing
{Note title}
{notes://showNote?identifier=...}

Reminder added to post it.
```

**Software idea:**
```
✓ Saved to Coding
{Note title}
{notes://showNote?identifier=...}

Continue here: https://claude.ai/project/{CLAUDE_CODING_PROJECT_ID}
```

**Job application:**
```
✓ Saved to Job Hunt
{Company} — {Role}
{Location type} · {Level}

Airtable: {record URL}
Opened in Safari.
```

**Save for later — known type:**
```
✓ Saved to Now → {Section}
{Title}
{URL}
```

**Save for later — ambiguous (asking):**
```
Not sure where to save this. Which section?
1: Later
2: Dev
3: Watch
4: Books
5: Places
6: Purchases
7: Gift ideas
```

## Response format
After calling tools, return a short JSON summary:
{
  "content_type": "event",
  "confidence": 90,
  "actions_taken": ["searched tickets", "created reminder"],
  "summary": "<use exact reply format for content type from above>",
  "question": null   // REQUIRED when you need user input — put the full question text here (e.g. "1: Add song\n2: Add album"). Without this, the user never sees or can reply to the question. Never put "Let me ask..." in summary instead.
}
"""

# ---------------------------------------------------------------------------
# Tool definitions for the Claude API
# ---------------------------------------------------------------------------

TOOLS = [
    {
        "name": "create_reminder",
        "description": "Create a reminder in Apple Reminders",
        "input_schema": {
            "type": "object",
            "properties": {
                "title": {"type": "string", "description": "Short action phrase, 2–5 words. NEVER copy raw user text. NEVER start with 'Reminder to'. E.g. 'Garden Tour Tickets', 'Call dentist'"},
                "due_date": {"type": "string", "description": "ISO date/datetime e.g. 2026-03-25 or 2026-03-25T14:00:00"},
                "notes": {"type": "string", "description": "Event details on separate lines: date, price, ticket URL. E.g. 'Saturday May 3, 2026\\n$20–$35\\nhttps://tickets.example.com'"},
                "tag": {"type": "string", "description": "Category tag — must be one of: music, books, places, watch, purchases, gift-ideas. Omit for tasks/events."},
                "list_name": {"type": "string", "description": "Reminders list name (default: Now)"},
            },
            "required": ["title"],
        },
    },
    {
        "name": "create_calendar_event",
        "description": "Create an event in Apple Calendar. Default calendar is Social (iCloud). notes = ticket URL + price; url = event page URL.",
        "input_schema": {
            "type": "object",
            "properties": {
                "title": {"type": "string"},
                "start_date": {"type": "string", "description": "ISO datetime e.g. 2026-03-25T14:00:00"},
                "end_date": {"type": "string", "description": "ISO datetime (optional, defaults to start + 1hr)"},
                "location": {"type": "string"},
                "notes": {"type": "string", "description": "Ticket URL + price"},
                "calendar_name": {"type": "string", "description": "Calendar name (default: Social)"},
                "url": {"type": "string", "description": "Event page URL"},
            },
            "required": ["title", "start_date"],
        },
    },
    {
        "name": "check_calendar_conflicts",
        "description": "Check for overlapping events after creating one. Call after create_calendar_event.",
        "input_schema": {
            "type": "object",
            "properties": {
                "start_date": {"type": "string", "description": "ISO datetime"},
                "end_date": {"type": "string", "description": "ISO datetime"},
                "exclude_title": {"type": "string", "description": "Title of event just created (exclude from conflict list)"},
            },
            "required": ["start_date", "end_date"],
        },
    },
    {
        "name": "create_note",
        "description": "Create a new note in Apple Notes",
        "input_schema": {
            "type": "object",
            "properties": {
                "title": {"type": "string"},
                "body": {"type": "string"},
                "folder": {"type": "string", "description": "Notes folder (default: Notes)"},
            },
            "required": ["title", "body"],
        },
    },
    {
        "name": "append_to_note",
        "description": "Append content to an existing Apple Note (creates it if missing)",
        "input_schema": {
            "type": "object",
            "properties": {
                "note_title": {"type": "string", "description": "Title of the note to append to"},
                "content": {"type": "string", "description": "Content to append"},
                "folder": {"type": "string", "description": "Notes folder (default: Notes)"},
            },
            "required": ["note_title", "content"],
        },
    },
    {
        "name": "create_mail_draft",
        "description": "Create a draft email in Apple Mail (not sent, just saved to Drafts)",
        "input_schema": {
            "type": "object",
            "properties": {
                "subject": {"type": "string"},
                "body": {"type": "string"},
                "to_address": {"type": "string", "description": "Optional recipient email"},
            },
            "required": ["subject", "body"],
        },
    },
    {
        "name": "write_draft_file",
        "description": "Write a markdown file to ~/Dumpling/Drafts/ (for LinkedIn posts, project specs, ideas)",
        "input_schema": {
            "type": "object",
            "properties": {
                "filename": {"type": "string", "description": "Filename without path e.g. linkedin_post_2026-03-20.md"},
                "content": {"type": "string", "description": "Full markdown content"},
                "subfolder": {"type": "string", "description": "Subfolder: linkedin / projects / ideas / etc."},
            },
            "required": ["filename", "content"],
        },
    },
    {
        "name": "create_linkedin_draft",
        "description": "Create a LinkedIn post draft file with formatting (legacy file-based)",
        "input_schema": {
            "type": "object",
            "properties": {
                "title": {"type": "string", "description": "Internal title for the draft file"},
                "body": {"type": "string", "description": "The LinkedIn post text (lightly edited/polished)"},
                "hashtags": {
                    "type": "array",
                    "items": {"type": "string"},
                    "description": "Suggested hashtags",
                },
            },
            "required": ["title", "body"],
        },
    },
    {
        "name": "create_linkedin_draft_note",
        "description": "Save LinkedIn post to Notes.app Writing folder + flagged Reminder in LinkedIn list. Preferred over create_linkedin_draft.",
        "input_schema": {
            "type": "object",
            "properties": {
                "body": {"type": "string", "description": "The LinkedIn post text (lightly edited/polished)"},
                "due_date": {"type": "string", "description": "Optional ISO date/datetime when to post, e.g. 2026-03-25 or 2026-03-25T14:00:00"},
            },
            "required": ["body"],
        },
    },
    {
        "name": "create_project_spec",
        "description": "Create a software project spec draft file (legacy file-based)",
        "input_schema": {
            "type": "object",
            "properties": {
                "name": {"type": "string", "description": "Project name"},
                "description": {"type": "string", "description": "What the project does"},
                "ideas": {"type": "string", "description": "Features / ideas"},
                "tech_notes": {"type": "string", "description": "Tech stack thoughts"},
            },
            "required": ["name", "description"],
        },
    },
    {
        "name": "create_software_idea_note",
        "description": "Expand idea via API, save to Notes.app Coding folder, append Claude Coding project link. Preferred over create_project_spec.",
        "input_schema": {
            "type": "object",
            "properties": {
                "idea": {"type": "string", "description": "Brief description of the software idea"},
            },
            "required": ["idea"],
        },
    },
    {
        "name": "search_event_tickets",
        "description": "Find ticket links for an event",
        "input_schema": {
            "type": "object",
            "properties": {
                "event_name": {"type": "string"},
                "location": {"type": "string", "description": "Optional city/venue"},
            },
            "required": ["event_name"],
        },
    },
    {
        "name": "search_music",
        "description": "Find Apple Music and Beatport links for an artist/track",
        "input_schema": {
            "type": "object",
            "properties": {
                "artist": {"type": "string"},
                "track": {"type": "string", "description": "Optional track/album name"},
            },
            "required": ["artist"],
        },
    },
    {
        "name": "search_music_options",
        "description": "Search Apple Music catalog only (no Library). Returns on_apple_music_store with apple_music_url, artist, name. Use name=\"\" for artist-only (top 3 tracks). ambiguous=True when song and album share name — ask 1 or 2. Then call add_music_to_now.",
        "input_schema": {
            "type": "object",
            "properties": {
                "artist": {"type": "string"},
                "name": {"type": "string", "description": "Track or album name; empty for artist-only top 3"},
            },
            "required": ["artist"],
        },
    },
    {
        "name": "add_music_to_now",
        "description": "Create reminder in Now → 🎧 Music with Apple Music, Beatport, Bandcamp links. Use after search_music_options. When found: pass apple_music_url. When NOT_FOUND: omit apple_music_url (Beatport + Bandcamp only).",
        "input_schema": {
            "type": "object",
            "properties": {
                "artist": {"type": "string"},
                "name": {"type": "string", "description": "Track or album name; empty for artist-only"},
                "apple_music_url": {"type": "string", "description": "Optional; omit when not on Apple Music"},
            },
            "required": ["artist"],
        },
    },
    {
        "name": "open_address_in_maps",
        "description": "Open an address in Apple Maps. Use for address content type — do NOT save to reminder or note.",
        "input_schema": {
            "type": "object",
            "properties": {
                "address": {"type": "string"},
            },
            "required": ["address"],
        },
    },
    {
        "name": "add_to_now_section",
        "description": "Add item to a section of the Now list (Watch, Dev, Later, Books, Places, Purchases, Gift ideas, 🎧 Music). Ask user if section ambiguous.",
        "input_schema": {
            "type": "object",
            "properties": {
                "section_name": {"type": "string", "description": "One of: Watch, Dev, Later, Books, Places, Purchases, Gift ideas, 🎧 Music"},
                "title": {"type": "string"},
                "url": {"type": "string", "description": "Optional URL"},
            },
            "required": ["section_name", "title"],
        },
    },
    {
        "name": "open_url_in_safari",
        "description": "Open a URL in Safari. Use for job application URLs.",
        "input_schema": {
            "type": "object",
            "properties": {
                "url": {"type": "string"},
            },
            "required": ["url"],
        },
    },
    {
        "name": "search_airtable_companies",
        "description": "Search Companies table in Job Hunt base by name",
        "input_schema": {
            "type": "object",
            "properties": {
                "company_name": {"type": "string"},
            },
            "required": ["company_name"],
        },
    },
    {
        "name": "create_airtable_company",
        "description": "Create a company record in Airtable Job Hunt base",
        "input_schema": {
            "type": "object",
            "properties": {
                "name": {"type": "string"},
            },
            "required": ["name"],
        },
    },
    {
        "name": "create_airtable_job",
        "description": "Create a job record in Airtable Job Hunt base. Check for duplicate by Job Link first.",
        "input_schema": {
            "type": "object",
            "properties": {
                "company_id": {"type": "string", "description": "Airtable record ID from search_airtable_companies or create_airtable_company"},
                "role": {"type": "string"},
                "job_link": {"type": "string"},
                "location_type": {"type": "string", "description": "e.g. Remote, Hybrid, On-site"},
                "level": {"type": "string", "description": "e.g. Senior, Mid-level"},
            },
            "required": ["company_id", "role", "job_link"],
        },
    },
    {
        "name": "summarize_github_repo",
        "description": "Fetch GitHub repo metadata (stars, description, language, topics)",
        "input_schema": {
            "type": "object",
            "properties": {
                "url": {"type": "string", "description": "Full GitHub repo URL"},
            },
            "required": ["url"],
        },
    },
    {
        "name": "find_job_application_url",
        "description": "Find the direct job application URL for a company/role",
        "input_schema": {
            "type": "object",
            "properties": {
                "job_title": {"type": "string"},
                "company": {"type": "string"},
            },
            "required": ["job_title", "company"],
        },
    },
    {
        "name": "general_search",
        "description": "General-purpose web search for enrichment",
        "input_schema": {
            "type": "object",
            "properties": {
                "query": {"type": "string"},
            },
            "required": ["query"],
        },
    },
    {
        "name": "teach_rule",
        "description": "Save a routing rule so future similar content is auto-handled without asking",
        "input_schema": {
            "type": "object",
            "properties": {
                "pattern": {"type": "string", "description": "Text to match (substring, domain, or regex)"},
                "pattern_type": {
                    "type": "string",
                    "enum": ["substring", "domain", "regex"],
                    "description": "How to match the pattern",
                },
                "action": {
                    "type": "string",
                    "description": "Tool to call: create_reminder / append_to_note / create_note / etc.",
                },
                "target": {"type": "string", "description": "Target note name, calendar, etc."},
                "content_type": {"type": "string", "description": "Optional: scope rule to a content type"},
            },
            "required": ["pattern", "action"],
        },
    },
]


# ---------------------------------------------------------------------------
# Tool dispatcher
# ---------------------------------------------------------------------------

_URL_RE = re.compile(r'https?://\S+')

def _sanitize_reminder(inputs: dict) -> dict:
    """
    Clean up reminder inputs before they reach Apple Reminders.
    - Extract any URLs from the title or notes and move them to the url field
    - Shorten overly long titles to the first meaningful phrase
    """
    inputs = dict(inputs)
    title = inputs.get("title", "")
    notes = inputs.get("notes", "") or ""
    existing_url = inputs.get("url") or ""

    # Pull URLs out of the title → url field
    urls_in_title = _URL_RE.findall(title)
    if urls_in_title:
        title = _URL_RE.sub("", title).strip(" —-·")
        if not existing_url:
            existing_url = urls_in_title[0]

    # Pull URLs out of notes → url field
    urls_in_notes = _URL_RE.findall(notes)
    if urls_in_notes:
        notes = _URL_RE.sub("", notes).strip()
        if not existing_url:
            existing_url = urls_in_notes[0]

    if existing_url:
        inputs["url"] = existing_url
        # Also put URL in notes so it's always visible in the Reminders UI
        notes = f"{notes}\n{existing_url}".strip() if notes else existing_url
    if notes:
        inputs["notes"] = notes

    # If title is still very long, truncate at a sensible boundary
    if len(title) > 50:
        for sep in (" — ", " - ", ": "):
            if sep in title:
                title = title.split(sep)[0].strip()
                break
        else:
            title = title[:50].rsplit(" ", 1)[0]

    inputs["title"] = title
    return inputs


def _dispatch_tool(name: str, inputs: dict, relay: RelayClient) -> str:
    """Call the right Python function for a tool name and return a JSON string result."""
    try:
        if name == "create_reminder":
            inputs = _sanitize_reminder(inputs)
            result = apple_reminders.create_reminder(**inputs)
        elif name == "create_calendar_event":
            result = apple_calendar.create_calendar_event(**inputs)
        elif name == "create_note":
            result = apple_notes.create_note(**inputs)
        elif name == "append_to_note":
            result = apple_notes.append_to_note(**inputs)
        elif name == "create_mail_draft":
            result = apple_mail.create_mail_draft(**inputs)
        elif name == "write_draft_file":
            result = file_drafts.write_draft_file(**inputs)
        elif name == "create_linkedin_draft":
            result = file_drafts.create_linkedin_draft(**inputs)
        elif name == "create_project_spec":
            result = file_drafts.create_project_spec(**inputs)
        elif name == "search_event_tickets":
            result = web_search.search_event_tickets(**inputs)
        elif name == "search_music":
            result = web_search.search_music(**inputs)
        elif name == "summarize_github_repo":
            result = web_search.summarize_github_repo(**inputs)
        elif name == "find_job_application_url":
            result = web_search.find_job_application_url(**inputs)
        elif name == "general_search":
            result = web_search.general_search(**inputs)
        elif name == "teach_rule":
            result = teach_rule(relay, **inputs)
        elif name == "check_calendar_conflicts":
            result = apple_calendar.check_calendar_conflicts(**inputs)
        elif name == "create_linkedin_draft_note":
            result = linkedin.create_linkedin_draft_note(**inputs)
        elif name == "create_software_idea_note":
            result = software_ideas.create_software_idea_note(**inputs)
        elif name == "search_music_options":
            result = apple_music.search_music_options(**inputs)
        elif name == "add_music_to_now":
            result = apple_music.add_music_to_now(**inputs)
        elif name == "open_address_in_maps":
            result = open_maps.open_address_in_maps(**inputs)
        elif name == "add_to_now_section":
            result = apple_reminders.add_to_now_section(**inputs)
        elif name == "open_url_in_safari":
            result = safari_open.open_url_in_safari(**inputs)
        elif name == "search_airtable_companies":
            result = airtable.search_airtable_companies(**inputs)
        elif name == "create_airtable_company":
            result = airtable.create_airtable_company(**inputs)
        elif name == "create_airtable_job":
            result = airtable.create_airtable_job(**inputs)
        else:
            result = {"error": f"Unknown tool: {name}"}
    except Exception as e:
        result = {"error": str(e)}

    return json.dumps(result)


# ---------------------------------------------------------------------------
# Main agent entrypoint
# ---------------------------------------------------------------------------

def process_item(item: dict, relay: RelayClient) -> dict:
    """
    Run the full agent loop for one item.

    Returns a dict:
      {"content_type", "confidence", "actions_taken", "summary", "question"}
    """
    client = anthropic.Anthropic(api_key=os.getenv("ANTHROPIC_API_KEY"))

    # Build the user message
    parts = []
    if item.get("content_url"):
        parts.append(f"URL: {item['content_url']}")
    if item.get("content_text"):
        parts.append(f"Text: {item['content_text']}")
    if item.get("user_note"):
        parts.append(f"User note: {item['user_note']}")
    if item.get("quick_tag"):
        parts.append(f"User tagged this as: {item['quick_tag']}")
    if item.get("source_app"):
        parts.append(f"Shared from: {item['source_app']}")
    if item.get("content_image_path"):
        parts.append(f"[Image attached — path: {item['content_image_path']}]")
    if item.get("user_reply"):
        reply = item["user_reply"].strip()
        parts.append(f"\nUser replied to your question: {item['user_reply']}")
        # Normalize numeric replies (1, 2, 1:, 2:, etc.) for option selection
        m = re.match(r"^(\d+)\s*:?\s*", reply)
        if m:
            parts.append(f"(User selected option {m.group(1)} — use this to complete the action.)")
        parts.append("Please act on this reply — save any new routing rule if appropriate, then complete the action.")

    user_message = "\n".join(parts) if parts else "No content provided."

    messages = [{"role": "user", "content": user_message}]
    actions_taken = []

    # Agentic loop — keep calling Claude until it stops using tools
    while True:
        response = client.messages.create(
            model=MODEL,
            max_tokens=4096,
            system=SYSTEM_PROMPT,
            tools=TOOLS,
            messages=messages,
        )

        # Collect any tool calls from this response
        tool_uses = [b for b in response.content if b.type == "tool_use"]

        if not tool_uses:
            # Claude is done — extract the final JSON summary
            text_blocks = [b for b in response.content if b.type == "text"]
            raw = (text_blocks[-1].text if text_blocks else "") or ""
            try:
                # Extract JSON from the response (may have prose around it)
                m = re.search(r"\{[\s\S]+\}", raw)
                result = json.loads(m.group(0)) if m else {}
            except Exception:
                result = {}

            result.setdefault("content_type", item.get("quick_tag", "unknown"))
            result.setdefault("confidence", 50)
            result.setdefault("actions_taken", actions_taken)
            result.setdefault("summary", (raw or "")[:300])
            result.setdefault("question", None)
            return result

        # Execute each tool call and feed results back
        messages.append({"role": "assistant", "content": response.content})
        tool_results = []

        for tu in tool_uses:
            inputs = tu.input if isinstance(tu.input, dict) else {}
            tool_result = _dispatch_tool(tu.name, inputs, relay)
            actions_taken.append(tu.name)
            tool_results.append({
                "type": "tool_result",
                "tool_use_id": tu.id,
                "content": tool_result,
            })

        messages.append({"role": "user", "content": tool_results})
