# Dumpling — Software Ideas Pipeline Spec
## Feature: Expand and save software ideas to Notes + link to Claude Coding project

---

## Overview

When the agent classifies an incoming message as **software idea intent**, it:

1. Extracts the core idea from the raw message
2. Calls the Anthropic API to expand it into a structured note with architecture suggestions and tradeoffs
3. Generates a short title slug from the idea content
4. Saves the note to the "Coding" folder in Notes.app
5. Appends a direct link to the Claude Coding project at the bottom of the note
6. Replies with a confirmation and a deep link to the note

---

## Step 1 — Detect intent

Software idea signals:
- Message describes a tool, app, feature, or system to build
- Contains phrases like "app idea", "what if", "build a", "I want to make", "project idea"
- References a technical problem to solve

If ambiguous (could be a task or a note), default to saving as an idea and mention it in the reply so the user can correct if needed.

---

## Step 2 — Call Anthropic API to expand the idea

Make a Claude API call with the raw idea text. The goal is a medium-depth expansion: enough to spark a real architecture conversation, not a full spec.

### System prompt
```
You are a technical co-founder helping to quickly evaluate and structure a software idea.
Given a raw idea, produce a structured note with the following sections.
Be concise — this is a seed document, not a full spec.
Return plain text with markdown headings. No preamble, no sign-off.
```

### User prompt
```
Raw idea: {RAW_MESSAGE}

Produce a structured note with these sections:

## Problem
What problem does this solve? Who has it? (2–3 sentences)

## MVP
The smallest useful version. What does it do and not do? (3–5 bullet points)

## Architecture
Suggested technical approach — platform, stack, key components. Include 1–2 alternatives with brief tradeoffs. (4–8 bullet points)

## Open questions
The most important unknowns to resolve before building. (3–5 bullet points)

## Links
(Leave this section empty — it will be filled in automatically)
```

### Title slug generation
In the same API call, also ask for a short title:
```
Also return a title slug: 2–4 words that name the idea, in title case, no punctuation.
Format your response as:

TITLE: {slug}
---
{note body}
```

Parse the `TITLE:` line to get the slug. Final note title: `{MMM D} · {SLUG}`
Examples: `Jun 14 · Offline Sync Tool`, `Mar 3 · DJ Set Planner`

---

## Step 3 — Append Claude Coding project link

After the API response, append a Links section to the note body:

```
## Links
Claude Coding project: https://claude.ai/project/{CODING_PROJECT_ID}
```

The Coding project ID is a fixed value configured in Dumpling settings — the user provides it once during setup by copying it from the Claude.ai URL when viewing their Coding project.

---

## Step 4 — Save note to Notes.app

```applescript
tell application "Notes"
    -- Find the Coding folder
    set targetFolder to missing value
    repeat with f in folders
        if name of f is "Coding" then
            set targetFolder to f
            exit repeat
        end if
    end repeat
    
    if targetFolder is missing value then
        error "FOLDER_NOT_FOUND: No folder named 'Coding' found in Notes.app"
    end if
    
    -- Handle duplicate titles (two ideas same day)
    set noteTitle to "{DATE_SLUG_TITLE}"
    set existingNotes to notes of targetFolder whose name is noteTitle
    if (count of existingNotes) > 0 then
        set noteTitle to noteTitle & " 2"
    end if
    
    -- Create the note
    set newNote to make new note at targetFolder with properties {
        name: noteTitle,
        body: "{EXPANDED_NOTE_BODY}"
    }
    
    set noteId to id of newNote
end tell
```

---

## Step 5 — Reply

```
✓ Saved to Coding
{NOTE_TITLE}
{NOTES_DEEP_LINK}

Open your Claude Coding project to continue:
https://claude.ai/project/{CODING_PROJECT_ID}
```

The Notes deep link:
```
notes://showNote?identifier={NOTE_ID}
```

---

## Error handling

| Condition | Behavior |
|---|---|
| "Coding" folder not found | Error reply: "Couldn't find a 'Coding' folder in Notes.app — check the folder name in settings" |
| API call fails | Save the raw idea text as-is with a note: "Expansion failed — raw idea saved" |
| Title slug missing from API response | Fall back to `{MMM D} · Software Idea` |
| Duplicate title on same day | Append counter silently |
| Coding project ID not configured | Omit the project link, add to reply: "Add your Claude Coding project ID in Dumpling settings to include a direct link" |
| Idea is very short (< 10 words) | Proceed — the API expansion will flesh it out |

---

## Implementation notes for Cursor

- The Anthropic API call uses `claude-sonnet-4-20250514` with `max_tokens: 1000` — sufficient for a medium-depth expansion without being expensive per message
- Parse the API response by splitting on the `---` delimiter: everything before is the title line, everything after is the note body
- The Coding project ID is stored in Dumpling's user settings (UserDefaults) as `dumplingCodingProjectId` — surface a setup prompt if it's empty when the first idea is processed
- Note body is markdown — Notes.app renders basic markdown (headings, bullets) natively when the body is set via AppleScript, so the structured output will display cleanly
- Special character escaping applies here too — the expanded note body will contain apostrophes, dashes, and code-like text; sanitize before AppleScript injection same as the LinkedIn pipeline
- The "Coding" folder name should be configurable in Dumpling settings
- API latency (1–3s) means the reply will be slightly delayed vs. other pipelines — no special handling needed, but worth noting so the user isn't surprised by the pause
