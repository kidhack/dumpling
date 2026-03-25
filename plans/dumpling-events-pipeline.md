# Dumpling — Events Pipeline Spec
## Feature: Event routing to Social calendar via osascript

---

## Overview

When the agent classifies an incoming message as **event intent**, it runs this pipeline:

1. Identify input type (URL, screenshot, or plain text)
2. Extract event details from the input
3. If date or time is missing, ask before proceeding
4. Locate ticketing link and price if the event requires tickets
5. Create event in the "Social" calendar on iCloud via AppleScript
6. Check for conflicting events in the same time window
7. Reply with a summary, conflicts, and ticket link

---

## Step 1 — Identify input type

| Input signal | Type |
|---|---|
| Message contains a URL only (or URL + short note) | `url` |
| Message contains an attached image | `screenshot` |
| Message is plain text describing an event | `text` |

A message can contain both a URL and a screenshot. In that case, prefer the URL for structured data and use the screenshot to fill gaps.

---

## Step 2 — Extract event details

Target fields:

| Field | Required | Notes |
|---|---|---|
| `title` | Yes | Event name |
| `date` | Yes | Must ask if missing |
| `start_time` | Yes | Must ask if missing |
| `end_time` | No | Estimate +2–3 hrs if not found; flag in reply |
| `location` | No | Venue name + address if available |
| `event_url` | No | Canonical URL of the event page |
| `ticket_url` | No | Direct link to buy tickets |
| `ticket_price` | No | Price string (e.g. "$25", "£10–£20", "Free") |
| `is_ticketed` | No | Boolean — inferred from context |

### Case A: URL input

Fetch the URL content. Parse for event fields using the page's structured data first (`ld+json` schema.org `Event` markup), then fall back to heuristic parsing of the visible text.

**Known platforms with reliable structure:**
- **Eventbrite** — title, date, location, ticket price all in structured markup
- **Resident Advisor (RA)** — event schema includes lineup, venue, ticket link
- **Dice.fm** — structured event data in page JSON
- **Ticketmaster** — event schema present
- **Facebook Events** — login-walled; fetch will return partial or no data. If the page returns a login redirect, flag `extraction_partial: true` and surface what was found in the URL slug (often contains event name and date)
- **Instagram** — login-walled. Extract what's possible from URL, then ask user to paste the caption or confirm details manually

For social media URLs that are login-walled, send a clarification message before proceeding:
```
I can see this is an Instagram/Facebook post. I couldn't read the full details — can you paste the event info or confirm:
· Event name:
· Date and time:
· Location (if known):
```

### Case B: Screenshot input

Pass the image to Claude's vision. Prompt:

```
Extract the following from this event image. Return as JSON:
{
  "title": "",
  "date": "",        // ISO 8601 if possible, else raw string
  "start_time": "",  // 24hr or 12hr, raw string
  "end_time": "",
  "location": "",
  "event_url": "",
  "ticket_url": "",
  "ticket_price": "",
  "is_ticketed": true/false/null,
  "notes": ""        // any other relevant details (lineup, age restriction, dress code, etc.)
}
Return only JSON, no preamble.
```

If the screenshot is low quality or text is obscured, return the best available extraction and flag `extraction_partial: true`.

### Case C: Plain text input

Parse inline. The agent should handle common formats:
- "Honey Dijon at Fabric, Saturday 14th June, 10pm–6am, £20 advance"
- "Garden tour reminder — June 7th, 10am, Chelsea Physic Garden"

Apply the same target fields. If `date` uses a relative reference ("this Saturday", "next Friday"), resolve to an absolute date using today's date before confirming with the user.

---

## Step 3 — Clarification for missing required fields

If `date` or `start_time` is missing after extraction, send a clarification message **before creating any calendar event**:

```
Got the event — just need a couple of details before I add it to your calendar:
· {MISSING_FIELD_1}: ?
· {MISSING_FIELD_2}: ?
```

Only ask for missing required fields. Do not ask for optional fields (end time, ticket price) — the agent will estimate or skip those.

If `end_time` is missing but `start_time` is known, default to `start_time + 3 hours` and note this in the reply.

---

## Step 4 — Ticket link discovery

If `is_ticketed` is true or inferred (e.g. price mentioned, "tickets available", "advance" in text), and `ticket_url` was not found during extraction:

1. Check the event page for a "Buy tickets", "Get tickets", or "Book now" link — this is usually the most reliable source
2. If not found on the event page, construct a targeted web search:
   ```
   "{EVENT_TITLE}" "{VENUE}" tickets site:eventbrite.com OR site:dice.fm OR site:ticketmaster.com OR site:residentadvisor.net
   ```
3. Take the first credible result. If none found, set `ticket_url = nil` and note in reply.

If the event is free (`ticket_price == "Free"` or "free" appears in the description), set `is_ticketed = false` and skip this step.

---

## Step 5 — Create calendar event via AppleScript

Target: **"Social" calendar on the iCloud account**.

```applescript
tell application "Calendar"
    -- Find the Social calendar on iCloud
    set targetCal to missing value
    repeat with c in calendars
        if name of c is "Social" then
            set targetCal to c
            exit repeat
        end if
    end repeat
    
    if targetCal is missing value then
        -- Calendar not found — surface error, do not create in wrong calendar
        error "CALENDAR_NOT_FOUND: No calendar named 'Social' found"
    end if
    
    -- Build notes field
    set notesText to ""
    if "{TICKET_URL}" is not "" then
        set notesText to notesText & "Tickets: {TICKET_URL}" & linefeed
    end if
    if "{TICKET_PRICE}" is not "" then
        set notesText to notesText & "Price: {TICKET_PRICE}" & linefeed
    end if
    if "{EXTRA_NOTES}" is not "" then
        set notesText to notesText & linefeed & "{EXTRA_NOTES}"
    end if
    
    -- Create the event
    set newEvent to make new event at end of events of targetCal with properties {
        summary: "{TITLE}",
        start date: date "{START_DATETIME}",
        end date: date "{END_DATETIME}",
        location: "{LOCATION}",
        url: "{EVENT_URL}",
        description: notesText
    }
end tell
```

**Date format for AppleScript:** Use the format `"Saturday, June 14, 2025 at 10:00:00 PM"` — AppleScript's `date` coercion is locale-sensitive. Alternatively, construct via `current date` manipulation in Swift before passing to the script.

**If "Social" calendar is not found:** Do not fall back to the default calendar. Surface the error in the reply:
```
⚠ Couldn't find a calendar named "Social" on your iCloud account. Check Calendar.app and make sure it exists, then resend.
```

---

## Step 6 — Conflict detection

After creating the event, query Calendar for any other events that overlap the same time window on the same day.

```applescript
tell application "Calendar"
    set checkStart to date "{START_DATETIME}"
    set checkEnd to date "{END_DATETIME}"
    set conflicts to {}
    
    repeat with c in calendars
        repeat with e in (events of c whose start date < checkEnd and end date > checkStart)
            -- Exclude the event we just created
            if summary of e is not "{TITLE}" then
                set end of conflicts to {
                    title: summary of e,
                    calName: name of c,
                    startTime: start date of e
                }
            end if
        end repeat
    end repeat
    
    return conflicts
end tell
```

Capture the list of conflicting events for inclusion in the reply.

---

## Step 7 — Reply

Send a reply via the Dumpling relay after the event is created.

### Standard reply (no conflicts, ticketed)
```
✓ Added to Social calendar
{TITLE}
{DATE} · {START_TIME}–{END_TIME}
{LOCATION}

🎟 Tickets: {TICKET_URL}
Price: {TICKET_PRICE}
```

### With conflicts
```
✓ Added to Social calendar
{TITLE}
{DATE} · {START_TIME}–{END_TIME}
{LOCATION}

⚠ Conflicts with:
  · {CONFLICT_TITLE} ({CONFLICT_CAL}, {CONFLICT_TIME})

🎟 Tickets: {TICKET_URL}
Price: {TICKET_PRICE}
```

### Free event
```
✓ Added to Social calendar
{TITLE}
{DATE} · {START_TIME}–{END_TIME}
{LOCATION}
Free entry
```

### End time estimated
```
✓ Added to Social calendar
{TITLE}
{DATE} · {START_TIME} (end time estimated — update if known)
{LOCATION}
```

### Ticket link not found
```
✓ Added to Social calendar
{TITLE}
{DATE} · {START_TIME}–{END_TIME}
{LOCATION}

🎟 Couldn't find a direct ticket link — check the event page:
{EVENT_URL}
```

---

## Error handling

| Condition | Behavior |
|---|---|
| "Social" calendar not found | Error reply — do not create event in wrong calendar |
| Date resolved to a past date | Ask to confirm: "Just checking — did you mean {DATE} in 2026?" |
| Relative date ("this Saturday") with ambiguity | Resolve and confirm: "Adding for Saturday June 14 — that right?" |
| Event URL is a login-walled social post | Ask user to confirm details manually |
| Screenshot unreadable / too low quality | Reply asking for the details as text |
| Extraction is partial (some fields missing) | Proceed with what's available; note missing fields in reply |
| Multiple ticket platforms found | Use the first direct buy link, not an aggregator |
| Calendar.app not running | Launch before running AppleScript |

---

## Implementation notes for Cursor

- AppleScript `url` property on Calendar events maps to the "URL" field visible in Calendar.app event inspector
- AppleScript `description` property maps to the "Notes" field in Calendar.app
- Date/time construction: parse extracted date strings in Swift using `DateFormatter` with multiple format patterns, then convert to AppleScript date string in the locale-safe long format before injecting into the script
- For URL fetching: use `URLSession` with a browser-like User-Agent to avoid bot blocks on event pages; parse HTML with a lightweight Swift HTML parser (e.g. SwiftSoup) or pass raw HTML to Claude for extraction
- For screenshot extraction: pass the image data to the Claude API with the vision extraction prompt from Step 2; handle the JSON response in Swift
- Conflict detection query runs **after** event creation — this avoids a double-read and ensures the newly created event is excluded by title match
- If the agent is mid-clarification flow (waiting for user to confirm date/time), the pipeline state should be persisted in memory keyed on conversation ID so the follow-up message resumes correctly rather than starting fresh
- The "Social" calendar name should be configurable in Dumpling's settings in case the user has named it differently
