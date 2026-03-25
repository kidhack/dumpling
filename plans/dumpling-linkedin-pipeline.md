# Dumpling — LinkedIn Draft Pipeline Spec
## Feature: Save LinkedIn post drafts to Notes + Reminder to post

---

## Overview

When the agent classifies an incoming message as **LinkedIn post intent**, it:

1. Takes the text as-is — no edits, no rewriting
2. Creates a new note in the "Writing" folder in Notes.app
3. Titles it with today's date + "LinkedIn Draft"
4. Creates a flagged Reminder in Reminders.app to post it
5. Replies with a confirmation and a deep link to the note

---

## Step 1 — Detect intent

LinkedIn intent signals:
- Message contains a block of text with a professional/reflective tone
- User explicitly says "LinkedIn post", "post this", "draft this"
- Text reads like a narrative, lesson, or professional update

If ambiguous between LinkedIn and another note type, the agent should confirm:
```
Save this as a LinkedIn draft?
```

---

## Step 2 — Create note in Notes.app

Title format: `{MMM D} · LinkedIn Draft`
Examples: `Jun 14 · LinkedIn Draft`, `Mar 3 · LinkedIn Draft`

If a note with the same title already exists (two drafts on the same day), append a counter:
`Jun 14 · LinkedIn Draft 2`

```applescript
tell application "Notes"
    -- Find the Writing folder
    set targetFolder to missing value
    repeat with f in folders
        if name of f is "Writing" then
            set targetFolder to f
            exit repeat
        end if
    end repeat
    
    if targetFolder is missing value then
        error "FOLDER_NOT_FOUND: No folder named 'Writing' found in Notes.app"
    end if
    
    -- Check for duplicate title
    set noteTitle to "{DATE_TITLE}"
    set existingNotes to notes of targetFolder whose name is noteTitle
    if (count of existingNotes) > 0 then
        set noteTitle to noteTitle & " 2"
    end if
    
    -- Create the note
    set newNote to make new note at targetFolder with properties {
        name: noteTitle,
        body: "{POST_TEXT}"
    }
    
    -- Capture the note ID for deep link
    set noteId to id of newNote
end tell
```

The note body should contain only the raw post text — no metadata, no headers, no word count padding. Clean and ready to copy-paste.

---

## Step 3 — Create Reminder to post

Creates a flagged reminder in a "LinkedIn" list (create the list if it doesn't exist). No due date is set by default — flagged so it surfaces at the top. If the user includes a posting time or date in their message (e.g. "post this Thursday"), set that as the due date.

```applescript
tell application "Reminders"
    -- Find or create LinkedIn list
    if not (exists list "LinkedIn") then
        make new list with properties {name: "LinkedIn"}
    end if
    
    tell list "LinkedIn"
        make new reminder with properties {
            name: "Post: {NOTE_TITLE}",
            body: "{NOTES_DEEP_LINK}",
            flagged: true
        }
    end tell
end tell
```

If the user specified a posting time, add `due date: date "{DUE_DATETIME}"` to the reminder properties.

---

## Step 4 — Reply

```
✓ Saved to Writing
{NOTE_TITLE}
{NOTES_DEEP_LINK}

Reminder added to post it.
```

The Notes deep link format:
```
notes://showNote?identifier={NOTE_ID}
```

This opens the note directly in Notes.app on Mac, and in the Notes app on iPhone via Handoff.

---

## Error handling

| Condition | Behavior |
|---|---|
| "Writing" folder not found | Error reply: "Couldn't find a 'Writing' folder in Notes.app — check the folder name in settings" |
| Duplicate title on same day | Append counter silently: "Jun 14 · LinkedIn Draft 2" |
| User includes a posting date/time | Parse and set as reminder due date |
| Post text is very short (< 20 words) | Save as-is — do not second-guess |
| Notes.app not running | Launch before running AppleScript |

---

## Implementation notes for Cursor

- The "Writing" folder name should be configurable in Dumpling settings
- Notes deep link (`notes://showNote?identifier=`) uses the note's internal ID returned by AppleScript — capture `id of newNote` immediately after creation
- Date title generation: format today's date in Swift as `"MMM d"` using `DateFormatter` with `locale: Locale(identifier: "en_US")` before injecting into the AppleScript
- Post text may contain apostrophes, quotes, and special characters — escape these before injecting into the AppleScript string: replace `"` with `\"` and `'` with `'` (right single quotation mark, U+2019) to avoid breaking the AppleScript string literal
- The "LinkedIn" Reminders list should be created on first launch as part of Dumpling's setup flow, not lazily per-message
