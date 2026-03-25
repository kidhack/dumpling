# Dumpling — Save For Later Pipeline Spec
## Feature: Route saved items to sections of the Now list in Reminders.app

---

## Overview

When the agent classifies an incoming message as a **save-for-later intent**, it:

1. Identifies the content type
2. Extracts a title and URL from the message
3. Adds a reminder to the correct section of the "Now" list in Reminders.app
4. Replies with a confirmation

No Safari opens. No new lists created. Everything lands in the existing Now list structure.

---

## Content type → section routing

| Content type | Now section | Signal words / patterns |
|---|---|---|
| YouTube or video URL | `Watch` | youtube.com, vimeo.com, "watch", "video" |
| GitHub repo | `Dev` | github.com, "repo", "library", "check out this" |
| Figma plugin | `Dev` | figma.com/community, "plugin", "figma" |
| Link / article / website | `Later` | Generic URL with no stronger type signal |
| Book title or Goodreads link | `Books` | "book", "read", goodreads.com |
| Place / restaurant / venue | `Places` | Address, maps link, "restaurant", "check out", Yelp/Google Maps URL |
| Product to buy | `Purchases` | "buy", "get this", amazon.com, shop URLs, product page |
| Gift idea for someone | `Gift ideas` | "gift", "present", "for [person's name]", "would love this" |

If the content type is ambiguous between two sections, prefer the more specific one (e.g. a GitHub URL always wins over `Later` even without explicit "repo" language).

If no type signal is found, **ask before saving** — do not default silently:
```
Not sure where to save this. Which section?
· Later · Dev · Watch · Books · Places · Purchases · Gift ideas
```

---

## Step 1 — Extract title and URL

For URL inputs:
- Use the URL as the reminder's notes/URL field
- Fetch the page title as the reminder name if possible (via `URLSession` HEAD or GET)
- If fetch fails or is slow, fall back to the domain + path slug as the title

For plain text inputs (e.g. "The Design of Everyday Things by Don Norman"):
- Use the text as the reminder name directly
- No URL to attach

Title formatting:
- Strip tracking parameters from URLs before storing (`?utm_source=...` etc.)
- Truncate titles longer than 100 characters with `…`

---

## Step 2 — Add to Now list via AppleScript

Reminders sections are called "reminder lists" within a list in AppleScript — specifically they map to the `section` property when available. However, AppleScript support for sections within a list is limited in older macOS versions. The reliable approach is to prefix the reminder title with the section name as a tag, and use a due-date-free reminder.

**Important:** Reminders.app sections (as seen in the screenshot) are a relatively recent UI feature. AppleScript accesses them via the list's section structure. If the section property is not available via AppleScript on the installed macOS version, fall back to adding a tag matching the section name — Reminders will surface tagged items in smart views.

### Preferred: section-aware AppleScript

```applescript
tell application "Reminders"
    set targetList to list "Now"
    
    -- Find the section
    set targetSection to missing value
    repeat with s in sections of targetList
        if name of s is "{SECTION_NAME}" then
            set targetSection to s
            exit repeat
        end if
    end repeat
    
    if targetSection is not missing value then
        tell targetSection
            make new reminder with properties {
                name: "{TITLE}",
                body: "{URL}",
                flagged: false
            }
        end tell
    else
        -- Fallback: add to list root with tag
        tell targetList
            make new reminder with properties {
                name: "{TITLE}",
                body: "{URL}",
                flagged: false
            }
        end tell
    end if
end tell
```

### Fallback: tag-based routing

If section targeting is unavailable, add the reminder to the Now list and apply a tag matching the section name:

```applescript
tell application "Reminders"
    tell list "Now"
        make new reminder with properties {
            name: "{TITLE}",
            body: "{URL}",
            flagged: false
        }
    end tell
end tell
```

Tag application via AppleScript is not supported directly — if fallback is needed, surface this in Dumpling's setup notes and suggest the user creates tag-based smart lists in Reminders manually.

---

## Step 3 — Reply

```
✓ Saved to Now → {SECTION}
{TITLE}
{URL}
```

If the content type was ambiguous, the agent asks first and saves only after the user replies with a section name.

---

## Section name reference (exact strings for AppleScript)

These must match exactly as they appear in the Now list:

| Section | Exact name string |
|---|---|
| New | `New` |
| Today | `Today` |
| Later | `Later` |
| Dev | `Dev` |
| Music | `Music` |
| Books | `Books` |
| Places | `Places` |
| Watch | `Watch` |
| Purchases | `Purchases` |
| Gift ideas | `Gift ideas` |

Dumpling's save-for-later pipeline only writes to: `Watch`, `Dev`, `Later`, `Books`, `Places`, `Purchases`, `Gift ideas`. It never writes to `New`, `Today` automatically — those remain manual.

---

## Error handling

| Condition | Behavior |
|---|---|
| "Now" list not found | Error reply: "Couldn't find a 'Now' list in Reminders.app — check the list name in settings" |
| Section not found in Now list | Fall back to list root; note in reply |
| Page title fetch fails | Use domain + slug as title; proceed silently |
| No URL and no clear title | Ask: "What should I save this as?" |
| Reminders.app not running | Launch before running AppleScript |

---

## Implementation notes for Cursor

- The "Now" list name should be configurable in Dumpling settings
- Section targeting via AppleScript should be tested on the user's macOS version first — if `sections of list` throws an error, implement the tag fallback immediately rather than shipping broken behavior
- URL title fetching should have a 2-second timeout — if it doesn't resolve, use the slug immediately rather than blocking the pipeline
- Strip common tracking params before saving: `utm_source`, `utm_medium`, `utm_campaign`, `utm_content`, `utm_term`, `fbclid`, `gclid`, `ref`
- GitHub URLs: if the URL is `github.com/{owner}/{repo}`, use `{owner}/{repo}` as the title rather than fetching the page (faster, always clean)
- YouTube URLs: extract the video title from the `<title>` tag on the page — YouTube page titles are in the format `"{Video Title} - YouTube"`, strip the ` - YouTube` suffix
- Figma community URLs follow the pattern `figma.com/community/plugin/{id}/{name}` — extract the plugin name from the URL slug directly as a fast fallback
