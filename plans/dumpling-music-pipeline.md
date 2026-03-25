# Dumpling — Music Pipeline Spec
## Feature: Music routing via osascript + browser fallback

---

## Overview

When the agent classifies an incoming message as **music intent**, it runs this pipeline:

1. Parse the message for artist and/or track name
2. Try to add to the "Explore" playlist in Music.app via AppleScript
3. If Apple Music fails, construct Beatport + Bandcamp search links and save to Reminders
4. Send a reply text with the outcome and a direct play link

---

## Step 1 — Parse intent

The agent must extract:
- `artist` — string or nil
- `track` — string or nil
- `mode` — one of: `artist_only`, `artist_and_track`, `artist_and_album`, `ambiguous`

If both artist and track are nil, ask the user for clarification before proceeding.

---

## Step 2 — Apple Music via AppleScript

### Case A: Artist only (`mode == "artist_only"`)

Search Apple Music catalog for the artist. Take the **top 3 tracks** returned (by popularity/default sort). Add all 3 to the "Explore" playlist.

```applescript
tell application "Music"
    -- Search Apple Music catalog
    set results to search playlist "Music" for "{ARTIST}" only music
    
    -- Take top 3
    set trackCount to 0
    repeat with t in results
        if trackCount >= 3 then exit repeat
        
        -- Add to Explore playlist
        set targetPlaylist to playlist "Explore"
        duplicate t to targetPlaylist
        
        set trackCount to trackCount + 1
    end repeat
end tell
```

Capture the name, artist, and persistent ID of each added track for the reply.

### Case B: Artist + track (`mode == "artist_and_track"`)

Search for the specific track. Take the first result that matches both artist and track name. Add to "Explore".

### Case C: Artist + album (`mode == "artist_and_album"`)

When the user wants a full album, add all tracks from the matching album to "Explore".

### Case D: Song vs album ambiguity

When artist + name could refer to both a song and an album with the same name:
1. Call `search_music_options(artist, name)` first
2. If `ambiguous: true`, ask the user: "1: Add song\n2: Add full album (N tracks)"
3. User can reply with "1", "2", "1:", "2:", etc.
4. Call `add_to_explore_playlist` with `artist_and_track` (option 1) or `artist_and_album` (option 2)

```applescript
tell application "Music"
    set results to search playlist "Music" for "{ARTIST} {TRACK}" only music
    
    if (count of results) > 0 then
        set t to item 1 of results
        set targetPlaylist to playlist "Explore"
        duplicate t to targetPlaylist
        
        -- Capture for reply
        set trackName to name of t
        set artistName to artist of t
        set trackId to persistent ID of t
    else
        -- No result — trigger fallback
        error "TRACK_NOT_FOUND"
    end if
end tell
```

### Getting the Apple Music deep link

After adding a track, construct the direct play URL using the persistent ID:

```applescript
-- Get the store URL / share link for a track
tell application "Music"
    set shareURL to (store URL of t) as string
end tell
```

If `store URL` is not available via AppleScript in the installed version, fall back to constructing a search URL:
```
https://music.apple.com/search?term={ARTIST}+{TRACK}
```

### Important: "Explore" playlist must exist

Before the first run, the pipeline should check whether the "Explore" playlist exists and create it if not:

```applescript
tell application "Music"
    if not (exists playlist "Explore") then
        make new user playlist with properties {name:"Explore"}
    end if
end tell
```

This check should run once at startup, not on every message.

---

## Step 3 — Fallback chain

Only triggered if Apple Music search returns no results (`TRACK_NOT_FOUND` error).

No browser automation. Instead, construct pre-built search URLs for Beatport and Bandcamp and save them directly to Reminders — no Safari opens, no DOM injection. The user taps the link when ready to buy.

```swift
let query = "\(artist) \(track)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
let beatportURL  = "https://www.beatport.com/search/tracks?q=\(query)"
let bandcampURL  = "https://bandcamp.com/search?q=\(query)&item_type=t"
```

Add a single Reminder to "Music to Find" with both links in the notes field:

```applescript
tell application "Reminders"
    if not (exists list "Music to Find") then
        make new list with properties {name:"Music to Find"}
    end if
    
    tell list "Music to Find"
        make new reminder with properties {
            name: "{ARTIST} — {TRACK}",
            body: "Not on Apple Music.

Beatport: {BEATPORT_URL}
Bandcamp: {BANDCAMP_URL}",
            flagged: false
        }
    end tell
end tell
```

Outcome = `reminder_created`

---

## Step 4 — Reply

After the pipeline completes, send a reply text back to the user via the Dumpling relay. Format depends on outcome:

### Apple Music — single track added
```
✓ Added to Explore
{ARTIST} — {TRACK}
[Play in Apple Music]({APPLE_MUSIC_URL})
```

### Apple Music — artist only (3 tracks added)
```
✓ Added 3 tracks to Explore
{ARTIST}:
  · {TRACK_1} — [play]({URL_1})
  · {TRACK_2} — [play]({URL_2})
  · {TRACK_3} — [play]({URL_3})
```

### Not on Apple Music — saved to Reminders
```
⚠ Not on Apple Music — saved to Music to Find
{ARTIST} — {TRACK}
Beatport: {BEATPORT_URL}
Bandcamp: {BANDCAMP_URL}
```

---

## Error handling

| Condition | Behavior |
|---|---|
| Music.app not running | Launch it before running AppleScript |
| User not signed into Apple Music | Reply: "Sign into Apple Music first — tried Beatport instead" then run fallback |
| "Explore" playlist missing | Create it silently, then proceed |
| AppleScript permission denied | Surface error to user, do not silently fail |
| Artist name only, zero results on Apple Music | Run fallback chain with artist name as query |
| Track added but no store URL available | Use search URL as fallback link |

---

## Implementation notes for Cursor

- AppleScript calls should be executed via `Process.run("osascript", arguments: ["-e", script])` in Swift, or via `NSAppleScript` if already in AppKit context
- Browser fallback does not open Safari — only URL construction + AppleScript Reminders write
- The reply is sent back through the same relay path that received the incoming message — reuse the existing `DumplingRelay.send(_ message:)` method
- All outcomes should be logged to the agent's action log with timestamp, input, and result for debugging
- The `"Music to Find"` Reminders list and `"Explore"` Music playlist should be created on first launch as part of the app's setup/onboarding flow, not lazily per-message
