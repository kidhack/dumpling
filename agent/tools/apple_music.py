"""
Apple Music and Music-to-Find Reminders via osascript.

Adds tracks to the "Explore" playlist in Music.app, or creates a Reminder
in "Music to Find" when tracks are not available on Apple Music.

search_music_options uses the Apple Music catalog (iTunes Search API) only —
for exploring music you don't have yet, not your local Library.
"""

import json
import os
import subprocess
from typing import Any, Optional
from urllib.parse import quote
from urllib.request import Request, urlopen

from .escaping import escape_for_applescript

# "Library" is the standard playlist/source for searching the user's library
# (includes added Apple Music tracks). "Music" was used in older iTunes; Library works on current macOS.
_MUSIC_SEARCH_SOURCE = "Library"

# Tab/newline must be defined outside "tell application Music" or AppleScript sends them to Music and errors
_AS_TAB = "character id 9"
_AS_NL = "character id 10"

# Fallback Apple Music search URL when store URL is not available via AppleScript
def _apple_music_search_url(artist: str, track: Optional[str] = None) -> str:
    query = f"{artist} {track}".strip() if track else artist
    return f"https://music.apple.com/search?term={quote(query)}"


def _artist_matches(expected: str, api_artist: str) -> bool:
    """Loose match for iTunes artistName vs user-supplied artist."""
    a = expected.strip().lower()
    b = (api_artist or "").strip().lower()
    if not a or not b:
        return False
    if a == b or a in b or b in a:
        return True
    aw = {w for w in a.replace(",", " ").split() if len(w) > 1}
    bw = {w for w in b.replace(",", " ").split() if len(w) > 1}
    return len(aw & bw) >= min(2, len(aw)) if aw else False


def _name_matches_album(user_name: str, collection_name: str) -> bool:
    un = user_name.strip().lower()
    cn = (collection_name or "").strip().lower()
    if not un or not cn:
        return False
    if un == cn:
        return True
    if len(un) >= 4 and (un in cn or cn.startswith(un + " ")):
        return True
    return False


def _name_matches_track(user_name: str, track_name: str) -> bool:
    un = user_name.strip().lower()
    tn = (track_name or "").strip().lower()
    return bool(un and tn and un == tn)


def _itunes_catalog_lookup(artist: str, name: str) -> Optional[dict[str, Any]]:
    """Query iTunes Search API (Apple Music catalog)."""
    term = f"{artist} {name}".strip()
    url = f"https://itunes.apple.com/search?term={quote(term)}&entity=album,song&limit=30"
    try:
        req = Request(url, headers={"User-Agent": "DumplingAgent/1.0"})
        with urlopen(req, timeout=12) as resp:
            data = json.loads(resp.read().decode("utf-8"))
    except Exception:
        return None

    results = data.get("results") or []
    if not results:
        return None

    album_hits: list[dict] = []
    track_hits: list[dict] = []

    for row in results:
        an = row.get("artistName") or ""
        if not _artist_matches(artist, an):
            continue
        w = row.get("wrapperType")
        if w == "collection":
            cn = row.get("collectionName") or ""
            if _name_matches_album(name, cn):
                album_hits.append(row)
        elif w == "track":
            cn = row.get("collectionName") or ""
            tn = row.get("trackName") or ""
            if _name_matches_album(name, cn):
                album_hits.append(row)
            elif _name_matches_track(name, tn):
                track_hits.append(row)

    # Prefer distinct album rows (dedupe by collectionId)
    seen_albums: set[int] = set()
    unique_albums: list[dict] = []
    for row in album_hits:
        cid = row.get("collectionId")
        if cid and cid not in seen_albums:
            seen_albums.add(cid)
            unique_albums.append(row)
        elif not cid:
            unique_albums.append(row)

    has_album = len(unique_albums) > 0
    has_track = len(track_hits) > 0
    name_lower = name.strip().lower()

    if has_album and has_track:
        title_on_album = any(
            (r.get("trackName") or "").strip().lower() == name_lower for r in track_hits
        )
        if title_on_album and unique_albums:
            row = unique_albums[0]
            tc = int(row.get("trackCount") or 0)
            track_row = next((r for r in track_hits if (r.get("trackName") or "").strip().lower() == name_lower), track_hits[0] if track_hits else row)
            track_url = track_row.get("trackViewUrl") or track_row.get("collectionViewUrl") or ""
            album_url = row.get("collectionViewUrl") or row.get("trackViewUrl") or ""
            return {
                "on_apple_music_store": True,
                "ambiguous": True,
                "options": [
                    {"type": "track", "artist": artist, "name": name, "apple_music_url": track_url, "catalog_id": str(track_row.get("trackId", ""))},
                    {
                        "type": "album",
                        "artist": row.get("artistName") or artist,
                        "name": row.get("collectionName") or name,
                        "track_count": tc or None,
                        "apple_music_url": album_url,
                        "catalog_id": str(row.get("collectionId", "")),
                    },
                ],
                "apple_music_url": album_url,
                "note": "Add to Now → 🎧 Music via add_music_to_now.",
            }

    if has_album:
        row = unique_albums[0]
        tc = int(row.get("trackCount") or 0)
        am_url = row.get("collectionViewUrl") or row.get("trackViewUrl") or ""
        ca = row.get("artistName") or artist
        cname = row.get("collectionName") or name
        return {
            "on_apple_music_store": True,
            "ambiguous": False,
            "option": "album",
            "artist": ca,
            "name": cname,
            "track_count": tc or None,
            "apple_music_url": am_url,
            "catalog_id": str(row.get("collectionId", "")),
            "note": "Add to Now → 🎧 Music via add_music_to_now.",
        }

    if has_track:
        row = track_hits[0]
        am_url = row.get("trackViewUrl") or row.get("collectionViewUrl") or ""
        return {
            "on_apple_music_store": True,
            "ambiguous": False,
            "option": "track",
            "artist": row.get("artistName") or artist,
            "name": row.get("trackName") or name,
            "apple_music_url": am_url,
            "catalog_id": str(row.get("trackId", "")),
            "note": "Add to Now → 🎧 Music via add_music_to_now.",
        }

    return None


def _itunes_artist_top_tracks(artist: str, limit: int = 3) -> Optional[dict[str, Any]]:
    """Get top tracks for an artist from Apple Music catalog (artist-only query)."""
    term = artist.strip()
    if not term:
        return None
    url = f"https://itunes.apple.com/search?term={quote(term)}&entity=song&limit={limit * 3}"
    try:
        req = Request(url, headers={"User-Agent": "DumplingAgent/1.0"})
        with urlopen(req, timeout=12) as resp:
            data = json.loads(resp.read().decode("utf-8"))
    except Exception:
        return None

    results = data.get("results") or []
    if not results:
        return None

    # Filter by artist match and dedupe by track
    seen: set[int] = set()
    tracks: list[dict] = []
    for row in results:
        if not _artist_matches(artist, row.get("artistName") or ""):
            continue
        tid = row.get("trackId")
        if tid and tid not in seen and len(tracks) < limit:
            seen.add(tid)
            tracks.append(row)

    if not tracks:
        return None

    return {
        "on_apple_music_store": True,
        "ambiguous": False,
        "option": "artist_top",
        "artist": tracks[0].get("artistName") or artist,
        "tracks": [
            {
                "name": r.get("trackName"),
                "artist": r.get("artistName"),
                "apple_music_url": r.get("trackViewUrl") or r.get("collectionViewUrl"),
                "catalog_id": str(r.get("trackId", "")),
            }
            for r in tracks
        ],
        "apple_music_url": tracks[0].get("trackViewUrl") or tracks[0].get("collectionViewUrl") or "",
        "note": "Add to Now → 🎧 Music via add_music_to_now.",
    }


def search_music_options(artist: str, name: str = "") -> dict:
    """
    Search Apple Music catalog (iTunes Search API) only — for exploring music
    you don't have in your library yet.

    Returns:
      {on_apple_music_store: True, option, artist, name, apple_music_url, catalog_id, ...}
      when found. For artist-only (name empty): option=artist_top, tracks=[...].
      ambiguous=True if song and album share the same name.
      {success: False, error: "NOT_FOUND"} when not on Apple Music.
    """
    if not name or not name.strip():
        cat = _itunes_artist_top_tracks(artist, limit=3)
    else:
        cat = _itunes_catalog_lookup(artist, name)
    if cat:
        return cat
    return {"success": False, "error": "NOT_FOUND"}


def _itunes_lookup_collection_tracks(collection_id: str) -> list[dict]:
    """Fetch track IDs for an album from iTunes lookup API."""
    url = f"https://itunes.apple.com/lookup?id={collection_id}&entity=song&limit=200"
    try:
        req = Request(url, headers={"User-Agent": "DumplingAgent/1.0"})
        with urlopen(req, timeout=12) as resp:
            data = json.loads(resp.read().decode("utf-8"))
    except Exception:
        return []
    results = data.get("results") or []
    return [r for r in results if r.get("wrapperType") == "track" and r.get("trackId")]


def add_music_to_now(
    artist: str,
    name: str = "",
    apple_music_url: Optional[str] = None,
    beatport_url: Optional[str] = None,
    bandcamp_url: Optional[str] = None,
) -> dict:
    """
    Create a reminder in the Now list under the 🎧 Music section with links to
    Apple Music, Beatport, and/or Bandcamp. Uses whichever URLs are provided.
    """
    from . import apple_reminders

    query = f"{artist} {name}".strip() if name else artist
    if not beatport_url:
        beatport_url = f"https://www.beatport.com/search/tracks?q={quote(query)}"
    if not bandcamp_url:
        bandcamp_url = f"https://bandcamp.com/search?q={quote(query)}&item_type=t"

    lines = []
    if apple_music_url:
        lines.append(f"Apple Music: {apple_music_url}")
    lines.append(f"Beatport: {beatport_url}")
    lines.append(f"Bandcamp: {bandcamp_url}")
    body = "\n".join(lines)

    title = f"{artist} — {name}" if name else artist
    return apple_reminders.add_to_now_section(
        section_name="🎧 Music",
        title=title,
        url=body,
    )


def add_catalog_to_explore(catalog_result: dict) -> dict:
    """
    Add catalog items from search_music_options result to the Explore playlist.
    Uses MusicKit API when APPLE_MUSIC_DEVELOPER_TOKEN and APPLE_MUSIC_USER_TOKEN are set.
    Otherwise opens the Apple Music URL in Music.app (user adds manually).

    For ambiguous results, pass the chosen option (options[0] for song, options[1] for album).
    """
    # Handle both full result and selected-option dict (when ambiguous)
    if catalog_result.get("on_apple_music_store"):
        data = catalog_result
    elif catalog_result.get("catalog_id"):
        data = catalog_result
    else:
        return {"success": False, "error": "Not a catalog result"}

    dev_token = os.getenv("APPLE_MUSIC_DEVELOPER_TOKEN", "").strip()
    user_token = os.getenv("APPLE_MUSIC_USER_TOKEN", "").strip()
    am_url = data.get("apple_music_url") or ""

    # Collect catalog track IDs to add
    track_ids: list[str] = []
    option = data.get("option") or data.get("type", "")

    if option == "track" and data.get("catalog_id"):
        track_ids = [data["catalog_id"]]
    elif option == "artist_top":
        for t in data.get("tracks") or []:
            cid = t.get("catalog_id")
            if cid:
                track_ids.append(cid)
    elif option == "album" and data.get("catalog_id"):
        rows = _itunes_lookup_collection_tracks(data["catalog_id"])
        track_ids = [str(r["trackId"]) for r in rows if r.get("trackId")]
    elif catalog_result.get("ambiguous"):
        return {"success": False, "error": "Ambiguous — pass the chosen option (options[0] or options[1]) when user replies 1 or 2"}

    if not track_ids:
        return {"success": False, "error": "No track IDs to add"}

    # MusicKit API path
    if dev_token and user_token:
        result = _musickit_add_to_explore(track_ids, dev_token, user_token)
        if result.get("success"):
            result["added_tracks"] = len(track_ids)
            result["apple_music_url"] = am_url
        return result

    # Fallback: open in Music.app
    if am_url:
        try:
            subprocess.run(
                ["open", "-a", "Music", am_url],
                capture_output=True, timeout=5,
            )
        except Exception:
            pass
        return {
            "success": True,
            "opened_in_music": True,
            "apple_music_url": am_url,
            "message": "Opened in Music.app — add to Explore from there, or set APPLE_MUSIC_DEVELOPER_TOKEN and APPLE_MUSIC_USER_TOKEN for automatic add.",
        }

    return {"success": False, "error": "No URL to open"}


def _musickit_add_to_explore(track_ids: list[str], dev_token: str, user_token: str) -> dict:
    """Add catalog tracks to Explore playlist via MusicKit API."""
    base = "https://api.music.apple.com/v1"
    headers = {
        "Authorization": f"Bearer {dev_token}",
        "Music-User-Token": user_token,
        "Content-Type": "application/json",
    }

    # Find Explore playlist
    try:
        req = Request(f"{base}/me/library/playlists", headers=headers)
        with urlopen(req, timeout=15) as resp:
            data = json.loads(resp.read().decode("utf-8"))
    except Exception as e:
        return {"success": False, "error": f"Failed to list playlists: {e}"}

    playlists = data.get("data") or []
    explore = next((p for p in playlists if (p.get("attributes") or {}).get("name") == "Explore"), None)
    if not explore:
        # Create Explore playlist
        try:
            body = json.dumps({"attributes": {"name": "Explore", "description": "Dumpling discoveries"}}).encode()
            create_req = Request(
                f"{base}/me/library/playlists",
                data=body,
                headers={**headers, "Content-Type": "application/json"},
                method="POST",
            )
            with urlopen(create_req, timeout=15) as resp:
                create_data = json.loads(resp.read().decode("utf-8"))
            explore = (create_data.get("data") or [{}])[0]
        except Exception as e:
            return {"success": False, "error": f"Failed to create Explore: {e}"}

    playlist_id = explore.get("id")
    if not playlist_id:
        return {"success": False, "error": "No playlist ID"}

    # Add tracks
    body = json.dumps({
        "data": [{"id": tid, "type": "songs"} for tid in track_ids],
    }).encode()
    try:
        add_req = Request(
            f"{base}/me/library/playlists/{playlist_id}/tracks",
            data=body,
            headers={**headers, "Content-Type": "application/json"},
            method="POST",
        )
        with urlopen(add_req, timeout=30) as resp:
            pass
    except Exception as e:
        return {"success": False, "error": f"Failed to add tracks: {e}"}

    return {"success": True}


def _count_album_tracks(artist: str, album: str) -> int:
    """Count tracks in an album via AppleScript."""
    esc_artist = escape_for_applescript(artist)
    esc_album = escape_for_applescript(album)
    script = f'''
tell application "Music"
    set lib to playlist "{_MUSIC_SEARCH_SOURCE}"
    set matches to (every track of lib whose album is "{esc_album}" and artist is "{esc_artist}")
    return (count of matches)
end tell
'''
    try:
        r = subprocess.run(
            ["osascript", "-e", script],
            capture_output=True, text=True, timeout=10,
        )
        if r.returncode == 0 and r.stdout:
            return int(r.stdout.strip() or 0)
    except Exception:
        pass
    return 0


def add_to_explore_playlist(
    artist: str,
    track: Optional[str] = None,
    mode: str = "artist_and_track",
) -> dict:
    """
    Search Music.app catalog and add track(s) to the "Explore" playlist.

    - artist_only: add top 3 tracks
    - artist_and_track: add first matching track/song
    - artist_and_album: add all tracks from the matching album (track param = album name)

    Returns dict with success, added_tracks (list of {name, artist, url}), apple_music_url.
    On failure returns {success: False, error: "..."}.
    """
    esc_artist = escape_for_applescript(artist)
    esc_track = escape_for_applescript(track or "")

    # Create Explore playlist if it doesn't exist
    ensure_playlist = '''
tell application "Music"
    if not (exists playlist "Explore") then
        make new user playlist with properties {name:"Explore"}
    end if
end tell
'''
    try:
        r = subprocess.run(
            ["osascript", "-e", ensure_playlist],
            capture_output=True, text=True, timeout=10,
        )
        if r.returncode != 0:
            return {"success": False, "error": r.stderr.strip() or "Failed to ensure Explore playlist"}
    except Exception as e:
        return {"success": False, "error": str(e)}

    if mode == "artist_only":
        search_term = esc_artist
        limit = 3
        use_album_mode = False
    elif mode == "artist_and_album":
        if not esc_track:
            return {"success": False, "error": "Album name required for artist_and_album mode"}
        use_album_mode = True
        search_term = ""
    else:
        search_term = f"{esc_artist} {esc_track}".strip() if esc_track else esc_artist
        limit = 1
        use_album_mode = False

    if use_album_mode:
        # Add all tracks from the album
        # Note: "store URL" causes AppleScript syntax errors in Music.app, use fallback URL
        script = f'''
set tab to {_AS_TAB}
set nl to {_AS_NL}
tell application "Music"
    set lib to playlist "{_MUSIC_SEARCH_SOURCE}"
    set albumTracks to (every track of lib whose album is "{esc_track}" and artist is "{esc_artist}")
    set targetPlaylist to playlist "Explore"
    set output to ""
    repeat with t in albumTracks
        try
            duplicate t to targetPlaylist
            set trackName to name of t
            set artistName to artist of t
            if output is not "" then set output to output & nl
            set output to output & trackName & tab & artistName & tab
        end try
    end repeat
    return output
end tell
'''
    else:
        # For artist_and_track: use direct query (name + artist) — more reliable than search.
        # Search returns results in arbitrary order (often track 1 first); direct query gets the exact track.
        if limit == 1 and esc_track:
            script = f'''
set tab to {_AS_TAB}
set nl to {_AS_NL}
tell application "Music"
    set lib to playlist "{_MUSIC_SEARCH_SOURCE}"
    set targetPlaylist to playlist "Explore"
    set output to ""
    try
        set matches to (every track of lib whose name is "{esc_track}" and artist is "{esc_artist}")
        if (count of matches) > 0 then
            set t to item 1 of matches
            duplicate t to targetPlaylist
            set output to (name of t) & tab & (artist of t) & tab
        end if
    end try
    return output
end tell
'''
        else:
            # artist_only or no track: use search
            script = f'''
set tab to {_AS_TAB}
set nl to {_AS_NL}
tell application "Music"
    set searchResults to search playlist "{_MUSIC_SEARCH_SOURCE}" for "{search_term}"
    if (class of searchResults) is not list then
        set searchResults to {{searchResults}}
    end if
    set targetPlaylist to playlist "Explore"
    set output to ""
    set n to 0
    repeat with t in searchResults
        if n >= {limit} then exit repeat
        try
            duplicate t to targetPlaylist
            set trackName to name of t
            set artistName to artist of t
            if output is not "" then set output to output & nl
            set output to output & trackName & tab & artistName & tab
            set n to n + 1
        end try
    end repeat
    return output
end tell
'''
        # If direct query found nothing, fall back to search (track might have different name, e.g. "Graceland (Remaster)")
        if limit == 1 and esc_track:
            try:
                r = subprocess.run(
                    ["osascript", "-e", script],
                    capture_output=True, text=True, timeout=15,
                )
                if r.returncode == 0 and (r.stdout or "").strip():
                    raw = r.stdout.strip()
                    added_tracks = []
                    for line in raw.split("\n"):
                        parts = line.split("\t", 2)
                        name = parts[0] if len(parts) > 0 else ""
                        artist_name = parts[1] if len(parts) > 1 else artist
                        url = parts[2] if len(parts) > 2 else ""
                        if not url:
                            url = _apple_music_search_url(artist, track)
                        added_tracks.append({"name": name, "artist": artist_name, "url": url})
                    if added_tracks:
                        return {
                            "success": True,
                            "added_tracks": added_tracks,
                            "apple_music_url": added_tracks[0]["url"],
                        }
            except Exception:
                pass
            # Fall through to search-based path
            script = f'''
set tab to {_AS_TAB}
set nl to {_AS_NL}
set targetTrack to "{esc_track}"
tell application "Music"
    set searchResults to search playlist "{_MUSIC_SEARCH_SOURCE}" for "{search_term}"
    if (class of searchResults) is not list then
        set searchResults to {{searchResults}}
    end if
    set targetPlaylist to playlist "Explore"
    set output to ""
    set found to false
    repeat with t in searchResults
        try
            set trackName to name of t
            set artistName to artist of t
            ignoring case
                if trackName is equal to targetTrack then
                    duplicate t to targetPlaylist
                    set output to trackName & tab & artistName & tab
                    set found to true
                    exit repeat
                end if
            end ignoring
        end try
    end repeat
    if not found and (count of searchResults) > 0 then
        set t to item 1 of searchResults
        duplicate t to targetPlaylist
        set output to (name of t) & tab & (artist of t) & tab
    end if
    return output
end tell
'''
    try:
        r = subprocess.run(
            ["osascript", "-e", script],
            capture_output=True, text=True, timeout=15,
        )
        if r.returncode != 0:
            return {"success": False, "error": r.stderr.strip() or "Music search failed"}

        # Output format: "name<TAB>artist<TAB>url" per line
        raw = (r.stdout or "").strip()
        if not raw:
            return {"success": False, "error": "TRACK_NOT_FOUND"}

        added_tracks = []
        for line in raw.split("\n"):
            parts = line.split("\t", 2)
            name = parts[0] if len(parts) > 0 else ""
            artist_name = parts[1] if len(parts) > 1 else artist
            url = parts[2] if len(parts) > 2 else ""
            if not url:
                url = _apple_music_search_url(artist, track)
            added_tracks.append({"name": name, "artist": artist_name, "url": url})

        if not added_tracks:
            return {"success": False, "error": "TRACK_NOT_FOUND"}

        apple_music_url = added_tracks[0]["url"]
        return {
            "success": True,
            "added_tracks": added_tracks,
            "apple_music_url": apple_music_url,
        }
    except subprocess.TimeoutExpired:
        return {"success": False, "error": "osascript timed out"}
    except Exception as e:
        return {"success": False, "error": str(e)}


def create_music_to_find_reminder(
    artist: str,
    track: Optional[str] = None,
    beatport_url: Optional[str] = None,
    bandcamp_url: Optional[str] = None,
) -> dict:
    """
    Create a Reminder in "Music to Find" with Beatport + Bandcamp URLs in notes.

    If beatport_url and bandcamp_url are not provided, they are constructed
    from artist and track.
    """
    query = f"{artist} {track}".strip() if track else artist
    if not beatport_url:
        beatport_url = f"https://www.beatport.com/search/tracks?q={quote(query)}"
    if not bandcamp_url:
        bandcamp_url = f"https://bandcamp.com/search?q={quote(query)}&item_type=t"

    title = f"{artist} — {track}" if track else artist
    notes = f"""Not on Apple Music.

Beatport: {beatport_url}
Bandcamp: {bandcamp_url}"""

    esc_title = escape_for_applescript(title)
    esc_notes = escape_for_applescript(notes)

    script = f'''
tell application "Reminders"
    if not (exists list "Music to Find") then
        make new list with properties {{name:"Music to Find"}}
    end if

    tell list "Music to Find"
        make new reminder with properties {{
            name: "{esc_title}",
            body: "{esc_notes}",
            flagged: false
        }}
    end tell
end tell
'''
    try:
        r = subprocess.run(
            ["osascript", "-e", script],
            capture_output=True, text=True, timeout=10,
        )
        if r.returncode != 0:
            return {"success": False, "error": r.stderr.strip()}
        return {
            "success": True,
            "message": "Saved to Music to Find",
            "beatport_url": beatport_url,
            "bandcamp_url": bandcamp_url,
        }
    except subprocess.TimeoutExpired:
        return {"success": False, "error": "osascript timed out"}
    except Exception as e:
        return {"success": False, "error": str(e)}
