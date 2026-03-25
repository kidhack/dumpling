# Dumpling — Implementation Plan

## Summary

All spec files (`dumpling-*-pipeline.md`) are present and readable in `/plans/`. The `files.zip` archive can be ignored — it is not a blocker.

The current implementation provides a working foundation: relay, agent loop, rule engine, and basic tools for Reminders, Calendar, Notes, Mail, file drafts, and web search. Six pipeline specs plus Address define target behaviors that differ from the current code in significant ways. The main gaps are:

1. **Music** — No AppleScript integration; currently only web search returns links. Spec requires: add to Music.app "Explore" playlist, or fallback to "Music to Find" Reminder.
2. **Events** — Calendar defaults to "Calendar", not "Social"; missing conflict check; notes/url usage differs from spec.
3. **LinkedIn** — Saves to file; spec requires Notes.app "Writing" folder + flagged Reminder in "LinkedIn" list.
4. **Software ideas** — Saves to file; spec requires Anthropic expansion + Notes.app "Coding" folder + Claude Coding link.
5. **Job applications** — Saves to Notes; spec requires Safari open + Airtable Job Hunt record (via MCP).
6. **Save for later** — Routes to Notes; spec requires Now list sections (Watch, Dev, Later, Books, Places, Purchases, Gift ideas).
7. **Address** — Currently reminder/note; spec requires only opening `maps://?q={address}` — no save.

---

## Pipeline Status

### Music

- **Status**: Partial (web search only)
- **What exists**: `web_search.search_music()` — finds Apple Music and Beatport URLs via DuckDuckGo; agent proposes saving to Notes.
- **Gaps**:
  - No osascript to search Music.app catalog or add tracks to "Explore" playlist.
  - No fallback to Reminder in "Music to Find" with Beatport/Bandcamp search URLs.
  - Music.app AppleScript API differs from spec (e.g. `search playlist "Music"` — verify against current Music.app scripting).
- **Changes needed**:
  - [ ] Add `agent/tools/apple_music.py` — `add_to_explore_playlist(artist, track=None, mode="artist_only"|"artist_and_track")` using osascript to search and add tracks; create "Explore" if missing.
  - [ ] Add `create_music_to_find_reminder(artist, track)` — creates Reminder in "Music to Find" with Beatport + Bandcamp URLs in notes (osascript or Swift).
  - [ ] **Prerequisite:** Use `escape_for_applescript()` from `escaping.py` for all user-supplied strings before AppleScript injection.
  - [ ] Update `agent/agent.py` — add `add_to_explore_playlist` and `create_music_to_find_reminder` tools; update system prompt for music pipeline (add to Explore vs. fallback to Music to Find).
  - [ ] Verify Music.app AppleScript syntax for catalog search — the spec’s `search playlist "Music" for "X" only music` may need adjustment for current macOS/Music.app.

---

### Events

- **Status**: Partial
- **What exists**: `apple_calendar.create_calendar_event()` — creates events with title, start/end, location, notes, url, calendar_name.
- **Gaps**:
  - Default calendar is "Calendar", not "Social"; spec requires explicit "Social" on iCloud.
  - No post-creation conflict check.
  - Notes field should contain ticket URL + price per spec; url field for event page URL.
  - No explicit handling for "Social" calendar not found (spec: do not fall back).
- **Changes needed**:
  - [ ] Update `agent/tools/apple_calendar.py` — default `calendar_name` to "Social"; improve error when "Social" not found; ensure `url` = event page, `notes` = ticket link + price.
  - [ ] Add `check_calendar_conflicts(start_date, end_date, exclude_title)` — osascript to return overlapping events; call after creation.
  - [ ] **Prerequisite:** Use `escape_for_applescript()` from `escaping.py` for all user-supplied strings before AppleScript injection.
  - [ ] Update `agent/agent.py` — add `check_calendar_conflicts` tool; update create_calendar_event description to use Social; prompt agent to run conflict check after creation and include conflicts in reply.

---

### LinkedIn

- **Status**: Not started (wrong destination)
- **What exists**: `file_drafts.create_linkedin_draft()` — writes markdown to `~/Dumpling/Drafts/linkedin/`.
- **Gaps**:
  - Spec: save to Notes.app "Writing" folder, title `{MMM D} · LinkedIn Draft`.
  - Spec: create flagged Reminder in "LinkedIn" list with notes deep link in body.
  - `create_reminder.swift` has no `--flagged`; EventKit’s EKReminder may not expose flagged. AppleScript Reminders does support `flagged`.
- **Changes needed**:
  - [ ] Update `agent/tools/apple_notes.py` — ensure `create_note` can target a folder by name (see Shared changes below). Add or use `create_note_in_folder(folder, title, body)` that finds folder and creates note; return note id for deep link.
  - [ ] Add `agent/tools/apple_reminders_osascript.py` or extend `apple_reminders.py` — `create_linkedin_reminder(title, body, list_name="LinkedIn", flagged=True)` via osascript (Reminders supports flagged).
  - [ ] Add tool `create_linkedin_draft_note` — create note in "Writing" with title `{MMM D} · LinkedIn Draft`, body = raw post text; create reminder with `notes://showNote?identifier={id}` in body, flagged.
  - [ ] Update `agent/agent.py` — replace or supplement `create_linkedin_draft` with `create_linkedin_draft_note`; system prompt: LinkedIn → Notes "Writing" + Reminder "LinkedIn".
  - [ ] **Prerequisite:** Use `escape_for_applescript()` from `escaping.py` for post text in both Notes and Reminder (apostrophes, quotes, em-dashes).
  - [x] **Same-day duplicate handling** — If a note with `{MMM D} · LinkedIn Draft` already exists, append ` 2`, ` 3`, etc. (implemented in `linkedin.py` via `get_note_titles_in_folder`).

---

### Software Ideas

- **Status**: Partial (file-based, no expansion)
- **What exists**: `file_drafts.create_project_spec()` — writes markdown file to `~/Dumpling/Drafts/projects/`.
- **Gaps**:
  - No Anthropic API call for structured expansion (Problem, MVP, Architecture, Open questions).
  - Spec: save to Notes.app "Coding" folder, not file.
  - Spec: append Claude Coding project link; need `DUMPLING_CODING_PROJECT_ID` or similar config.
- **Changes needed**:
  - [ ] Add `agent/tools/idea_expander.py` — call Anthropic API with spec’s system/user prompt; parse `TITLE:` and `---`; return `{title_slug, body}`.
  - [ ] Add `create_note_in_folder` support in `apple_notes.py` (folder = "Coding").
  - [ ] Add tool `create_software_idea_note` — expand via API, append Links section with Coding project URL, save to "Coding" folder, title `{MMM D} · {slug}`.
  - [ ] Add `DUMPLING_CODING_PROJECT_ID` to agent `.env`; document in HANDOFF.
  - [ ] Update `agent/agent.py` — add `create_software_idea_note`; route software_idea to it instead of `create_project_spec`.
  - [ ] **Prerequisite:** Use `escape_for_applescript()` from `escaping.py` when saving expanded note body to Notes.

---

### Job Applications

- **Status**: Partial (wrong destination)
- **What exists**: `web_search.find_job_application_url()`; agent typically saves to Notes.
- **Gaps**:
  - No Safari open; spec requires opening job URL in Safari (Jobs tab group if possible).
  - No Airtable integration; spec requires creating record in Job Hunt base (Companies + Jobs).
  - Airtable MCP not present in current MCP folder — must be wired or confirmed.
- **Changes needed**:
  - [ ] Add `agent/tools/safari_open.py` — `open_url_in_safari(url)` via osascript.
  - [ ] Wire Airtable MCP — confirm Airtable MCP is available to the agent; if not, add and configure.
  - [ ] Add tool(s) or MCP usage for: `search_airtable_companies(company_name)`, `create_airtable_company(name)`, `create_airtable_job(...)` with Level/Location inference.
  - [ ] Add duplicate check: search Jobs by Job Link before creating.
  - [ ] Update `agent/agent.py` — job_app flow: extract details → open Safari → Airtable Companies lookup/create → Jobs create → reply with Airtable link.

---

### Save for Later

- **Status**: Partial (routes to Notes, wrong structure)
- **What exists**: `link_save` content type; agent uses `append_to_note` or `create_note`.
- **Gaps**:
  - Spec: route to sections of "Now" list (Watch, Dev, Later, Books, Places, Purchases, Gift ideas).
  - No section-aware Reminders logic; Reminders sections may have limited AppleScript support.
  - Spec: if ambiguous, ask user — never default silently.
- **Changes needed**:
  - [ ] Add `agent/tools/reminders_sections.py` — `add_to_now_section(section_name, title, url=None)` — try section-aware osascript; fallback to list root with tag if sections unavailable.
  - [ ] Implement content-type → section mapping (YouTube→Watch, GitHub→Dev, etc.) per spec.
  - [ ] Update `agent/agent.py` — add `add_to_now_section` tool; add `save_for_later` content type; system prompt: route by type, ask if ambiguous.
  - [ ] Test Reminders section AppleScript on target macOS; document fallback behavior.
  - [ ] **Prerequisite:** Use `escape_for_applescript()` from `escaping.py` for title and URL before AppleScript injection.

---

### Address

- **Status**: Not started
- **What exists**: Agent may create reminder or note for addresses.
- **Gaps**: Spec is one-liner: open `maps://?q={ENCODED_ADDRESS}`; no save.
- **Changes needed**:
  - [ ] Add `agent/tools/open_maps.py` — `open_address_in_maps(address)` using `subprocess.run(["open", f"maps://?q={encoded}"])`. Use the `open` command (not osascript) — simpler and more reliable for URL scheme launches on macOS. Document this choice with an inline comment in the code.
  - [ ] Update `agent/agent.py` — add `open_address_in_maps` tool; system prompt: address → open Maps only, no save.

---

## Shared / Cross-cutting Changes

### Apple Notes folder targeting

- **Current**: `create_note` and `append_to_note` accept `folder` but the AppleScript creates notes at account level; `folder` is effectively ignored.
- **Change**: Rewrite Notes AppleScript to find folder by name under iCloud (or default) account and create/append within it. Handle "Writing" and "Coding" not found with clear errors.

### Special character escaping (Agent 0)

- **Risk**: Apostrophes, quotes, em-dashes in user content can break osascript string literals.
- **Change**: Agent 0 must create `agent/tools/escaping.py` as a shared utility. All agents (1–4) depend on it and must import it for every user-supplied string before AppleScript injection. Implementation:

```python
def escape_for_applescript(s: str) -> str:
    """
    Escape a string for safe injection into an AppleScript double-quoted string.
    - Backslashes first (must be first to avoid double-escaping)
    - Double quotes
    - Straight apostrophes → right single quotation mark (U+2019)
      so AppleScript doesn't interpret them as string delimiters
    - Newlines → \\n for AppleScript linefeed handling
    """
    if not s:
        return ""
    s = s.replace("\\", "\\\\")
    s = s.replace('"', '\\"')
    s = s.replace("'", "\u2019")
    s = s.replace("\n", "\\n")
    return s
```

### create_reminder.swift

- **Current**: Supports `--title`, `--notes`, `--due`, `--list`, `--tag`. No `--flagged`.
- **Change**: For LinkedIn, use osascript Reminders (supports flagged) rather than extending Swift, unless we add `--flagged` to Swift and confirm EventKit supports it. Prefer osascript for one-off cases to avoid script churn.

**Agent 3 prerequisite — `create_reminder.swift` flagged support audit:** Before implementing `create_flagged_reminder()`, read `agent/tools/create_reminder.swift` and check whether `--flagged` is already a supported argument. If it is, use it. If not, add it to the Swift script as part of Agent 3's scope:

```swift
// In argument parsing section:
if let flaggedIdx = args.firstIndex(of: "--flagged") {
    reminder.priority = 1  // High priority = flagged in Reminders.app
    args.remove(at: flaggedIdx)
}
```

Note: EventKit does not have a direct `.flagged` property — priority 1 (high) is how flagging is represented via EventKit. Verify this maps to the flag icon in Reminders.app on the target device before shipping.

### Agent system prompt

- Update content types and behaviors: music (Explore / Music to Find), events (Social + conflicts), linkedin (Notes + Reminder), software_idea (Notes + expansion), job_app (Safari + Airtable), save_for_later (Now sections), address (Maps only).
- Add explicit instructions for: ask before save when type ambiguous; never default silently for save-for-later.

### Config / env

- `DUMPLING_CODING_PROJECT_ID` — Claude Coding project URL for software ideas.
- Optional: `DUMPLING_WRITING_FOLDER`, `DUMPLING_CODING_FOLDER`, `DUMPLING_NOW_LIST` for overrides.

---

## Reply Pipeline

Every pipeline must return a structured reply that Dumpling sends back to the user as a text message. The reply is built from the agent's JSON summary (`summary` field) and must include specific content per pipeline. Agent 0's system prompt update must include these reply formats explicitly.

The relay sends the reply via `relay_client.send_reply(item_id, message)`. The agent already returns a `summary` string — that summary IS the reply text. So reply quality is entirely determined by what the system prompt instructs Claude to put in `summary`.

### Reply formats by pipeline

Add these to the system prompt under a `## Reply format by content type` section:

**Music — track added to Explore:**
```
✓ Added to Explore
{Artist} — {Track}
{Apple Music URL}
```

**Music — artist only (3 tracks):**
```
✓ Added 3 tracks to Explore
{Artist}:
· {Track 1} — {URL}
· {Track 2} — {URL}
· {Track 3} — {URL}
```

**Music — not on Apple Music (fallback):**
```
⚠ Not on Apple Music — saved to Music to Find
Beatport: {beatport_search_url}
Bandcamp: {bandcamp_search_url}
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
Later · Dev · Watch · Books · Places · Purchases · Gift ideas
```

### Implementation note for Agent 0

The system prompt must instruct Claude to construct the `summary` field using the above formats, incorporating values returned by the tools (URLs, note IDs, conflict lists, etc.). The tool results flow back into the agentic loop — Claude has access to them when writing the final JSON summary. Make this explicit in the prompt:

> After all tools have run, construct the `summary` field using the exact reply format for the content type. Include URLs, deep links, and note IDs from tool results. The summary is sent directly to the user as a text message — keep it short, human, and link-rich.

---

## Parallel Agent Execution — Agent 0 Responsibilities

Agent 0 runs first and must create the foundation before Agents 1–4 run. In addition to updating `agent/agent.py` (tool definitions, dispatcher stubs, system prompt with reply formats), Agent 0 must:

**Create `agent/tools/escaping.py`** — A shared utility all other agents depend on. Must exist before Agents 1–4 run. See the escaping spec under Shared / Cross-cutting Changes above. All agents (1–4) must import and use `escape_for_applescript()` for every user-supplied string before AppleScript injection.

---

## Implementation Order

1. **Agent 0 (Foundation)** — Create `escaping.py`, update `agent.py` with tool contracts, dispatcher stubs, system prompt including reply formats. Must complete before Agents 1–4.
2. **Agents 1, 2, 3** — Can merge in any order once Agent 0 is done.
3. **Agent 4** — **Must merge after Agent 3.** Agent 4's software idea pipeline calls `create_note_in_folder()` which is implemented by Agent 3 in `apple_notes.py`. If merging in parallel, Agent 4 should be tested against Agent 3's branch, not against Agent 0's stubs alone.

**Recommended merge order:** Agent 0 → Agents 1 + 2 + 3 (any order) → Agent 4.

**Legacy pipeline order** (if not using parallel agents):
1. Address — Trivial; good warm-up.
2. Shared: escaping — Prevents bugs across pipelines.
3. Shared: Notes folder targeting — Blocks LinkedIn and Software Ideas.
4. LinkedIn — Uses Notes folder + Reminders; no new APIs.
5. Events — Calendar tweaks + conflict check; moderate scope.
6. Save for later — Reminders sections; test AppleScript availability.
7. Software ideas — Anthropic expansion + Notes; depends on folder support.
8. Music — New Music.app + Reminders tools; verify AppleScript API.
9. Job applications — Safari + Airtable MCP; depends on MCP availability.

---

## Follow-ups (95% complete)

- [x] **LinkedIn same-day duplicate handling** — Append ` 2`, ` 3`, etc. when multiple drafts same day. Implemented in `linkedin.py`.
- [x] **HANDOFF env vars** — Updated with `DUMPLING_CODING_PROJECT_ID`, `AIRTABLE_API_KEY`, `DUMPLING_WRITING_FOLDER`, `DUMPLING_CODING_FOLDER`, `DUMPLING_NOW_LIST`.
- [x] **Airtable create response** — Parsing updated to handle both `{"id": "rec..."}` and `{"records": [{"id": "rec..."}]}` formats.

---

## Open Questions

1. **Airtable MCP** — Spec says use "existing MCP server"; it is not in the current MCP folder. Confirm how/when it will be wired to the agent.
2. **Music.app AppleScript** — The spec’s `search playlist "Music" for "X" only music` may not match current Music.app scripting. Need to verify and adapt.
3. **Reminders sections** — Section support varies by macOS. Confirm target macOS version and fallback (tag-based) behavior.
4. **Claude Coding project ID** — Where should users configure this? `.env`, relay, or agent config?
5. **Safari Jobs tab group** — Spec notes it is not reliably scriptable; new tabs land in active group. Document for users.
