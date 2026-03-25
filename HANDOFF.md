# Dumpling — Project Handoff

> Personal routing agent: share anything from your phone → Claude classifies, enriches, and routes it to your Mac productivity tools.

---

## What This Is

You encounter content constantly on your phone (Instagram events, Spotify tracks, GitHub repos, LinkedIn drafts, ticket reminders). Today it dies in your self-texts. Dumpling fixes that:

1. **iOS Share Extension** — tap Share from any app, content goes to Dumpling instantly
2. **Relay backend** — hosted queue so phone ↔ Mac works anywhere (not just local WiFi)
3. **Mac Agent** — Claude reads the item, enriches it (finds ticket links, music links, etc.), and routes it to Apple Reminders / Calendar / Notes / Mail or creates draft files
4. **Learning system** — unknown content types teach the agent new rules; never asked twice
5. **Web dashboard** — inbox, action queue, routing rules editor *(Phase 3, not started)*

---

## Project Location

```
/Users/kidhack/Documents/Dev/dumpling/
```

---

## What's Built

### `relay/` — FastAPI backend (SQLite locally, Postgres on Fly.io)

| File | Purpose |
|------|---------|
| `main.py` | All endpoints: `POST /ingest`, `GET /items`, `PATCH /items/{id}`, `POST /actions`, `GET /rules`, `POST /rules`, `PATCH /rules/{id}`, `DELETE /rules/{id}` |
| `db.py` | SQLAlchemy models: `Item`, `Action`, `RoutingRule`, `User` |
| `auth.py` | Bearer token middleware — dev token: `dumpling-dev-token` |
| `config.py` | Env vars: `DATABASE_URL`, `DEV_TOKEN`, `MASTER_SECRET`, `UPLOAD_DIR` |
| `requirements.txt` | `fastapi`, `uvicorn`, `sqlalchemy`, `python-multipart`, `python-dotenv` |

**To run locally:**
```bash
cd dumpling/relay
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
uvicorn main:app --reload --port 8000
```

**Test with curl:**
```bash
curl -X POST http://localhost:8000/ingest \
  -H "Authorization: Bearer dumpling-dev-token" \
  -F "content_text=Reminder to buy garden tour tickets Saturday"
```

**Test with Telegram (text from phone):** Create a bot via [@BotFather](https://t.me/BotFather), set `TELEGRAM_BOT_TOKEN` in relay `.env`, expose relay via [ngrok](https://ngrok.com) for local dev, then:
```bash
curl "https://api.telegram.org/bot<TOKEN>/setWebhook?url=https://YOUR-NGROK-URL/ingest/telegram"
```
Message your bot — items flow to Dumpling. See `plans/input-channels.md` for details.

---

### `agent/` — Mac agent (polls relay, runs Claude, fires Apple tools)

| File | Purpose |
|------|---------|
| `main.py` | Poll loop — fetches pending items every `POLL_INTERVAL` seconds, dispatches to agent or rule engine |
| `agent.py` | Full Claude agentic loop — tool definitions, system prompt, dispatcher, response parser |
| `rules.py` | Rule matching engine — checks `routing_rules` before calling Claude (substring / domain / regex) |
| `relay_client.py` | HTTP client for talking to the relay |
| `tools/apple_reminders.py` | `create_reminder()` via osascript |
| `tools/apple_calendar.py` | `create_calendar_event()` via osascript |
| `tools/apple_notes.py` | `create_note()`, `append_to_note()` via osascript |
| `tools/apple_mail.py` | `create_mail_draft()` via osascript |
| `tools/file_drafts.py` | `write_draft_file()`, `create_linkedin_draft()`, `create_project_spec()` → `~/Dumpling/Drafts/` |
| `tools/web_search.py` | `search_event_tickets()`, `search_music()`, `summarize_github_repo()`, `find_job_application_url()`, `general_search()` |
| `tools/teach_rule.py` | `teach_rule()` — persists a new routing rule to the relay DB |

**`.env` file** (at `agent/.env` — create if missing):
```
RELAY_URL=http://localhost:8000
RELAY_TOKEN=dumpling-dev-token
ANTHROPIC_API_KEY=       ← paste your key here
CLAUDE_MODEL=claude-sonnet-4-6
POLL_INTERVAL=30
DUMPLING_DRAFTS_DIR=~/Dumpling/Drafts

# Optional — Software ideas (append Claude Coding link to notes)
DUMPLING_CODING_PROJECT_ID=   ← from https://claude.ai/project/

# Optional — Job applications (Airtable Job Hunt base)
AIRTABLE_API_KEY=             ← Personal Access Token from https://airtable.com/create/tokens

# Optional overrides (defaults: Writing, Coding, Now)
DUMPLING_WRITING_FOLDER=Writing
DUMPLING_CODING_FOLDER=Coding
DUMPLING_NOW_LIST=Now
```

**To run:**
```bash
cd dumpling
pip install -r agent/requirements.txt   # or: cd agent && pip install -r requirements.txt
python -m agent.main
```
Run from the project root (dumpling/), not from inside agent/ — the agent uses relative imports.

---

### `ios/` — Share Extension (Swift/SwiftUI — needs Xcode project)

The Swift files are written but **not yet wrapped in an Xcode project**. This is the next major build step.

| File | Purpose |
|------|---------|
| `DumplingShareExtension/ShareViewController.swift` | `UIViewController` that hosts SwiftUI view, extracts URL/text/image from share context, calls upload |
| `DumplingShareExtension/ShareViewModel.swift` | `ObservableObject` — multipart POST to relay, manages loading/result state, reads relay URL + token from `UserDefaults` app group |

**Share sheet UI** (Y2K pastel pixel style):
- Blue pixel title bar with `□ — ×` chrome
- Optional note field
- Quick-tag buttons: 🔔 Remind / 📅 Event / 🎵 Music / 💡 Idea / 🔗 Save
- **"🥟 DUMPLING IT"** pink neo-brutalist button
- Loading: chunky segmented progress bar
- Result: green (success) or pink (error) panel, then auto-closes

**What still needs to be done in Xcode:**
1. Create new iOS project `DumplingApp` (SwiftUI, bundle ID `com.dumpling.app`)
2. Add Share Extension target (`DumplingShareExtension`)
3. Add App Group entitlement: `group.com.dumpling.app` to both targets
4. Copy in the two Swift files
5. Set `NSExtensionActivationRule` in extension `Info.plist` to accept URLs, text, images
6. Add Settings screen to host app (relay URL + auth token → `UserDefaults` app group)

---

## What's NOT Built Yet

| Item | Phase | Notes |
|------|-------|-------|
| Xcode project for iOS | 2 | Swift files exist, need project scaffolding |
| Push notifications (APNs) | 2 | Agent replies go back to phone |
| Next.js web dashboard | 3 | Inbox / Action Queue / Routing Rules editor |
| Fly.io deployment | 2 | Relay needs to be hosted for phone to reach it off-WiFi |
| Multi-user auth (OAuth) | 4 | Currently single dev token |
| Twilio fallback | 4 | For non-Claude users |

---

## Next Steps (in order)

1. **Set `ANTHROPIC_API_KEY`** in `agent/.env` (get from console.anthropic.com — never paste in chat)
2. **End-to-end local test**:
   - `uvicorn main:app --reload` in `relay/`
   - `python -m agent.main` in `agent/`
   - `curl` a few test items (see test cases below)
3. **Build Xcode project** — wrap the iOS Swift files into a real Share Extension
4. **Deploy relay to Fly.io** so phone can reach it from anywhere
5. **Build Next.js dashboard** (Phase 3)

---

## Test Cases

```bash
# Reminder
curl -X POST http://localhost:8000/ingest \
  -H "Authorization: Bearer dumpling-dev-token" \
  -F "content_text=Reminder to buy tickets to the garden tour this Saturday"
# Expected: Apple Reminder created

# Music
curl -X POST http://localhost:8000/ingest \
  -H "Authorization: Bearer dumpling-dev-token" \
  -F "content_text=Charlotte De Witte - Synergy"
# Expected: agent searches Beatport/Apple Music, returns links, asks to save

# GitHub link
curl -X POST http://localhost:8000/ingest \
  -H "Authorization: Bearer dumpling-dev-token" \
  -F "content_url=https://github.com/openai/swarm"
# Expected: repo summarized, saved to Apple Notes as link_save

# LinkedIn draft
curl -X POST http://localhost:8000/ingest \
  -H "Authorization: Bearer dumpling-dev-token" \
  -F "content_text=Excited to share that I just launched a new project..."
# Expected: .md draft file created in ~/Dumpling/Drafts/linkedin/

# Unknown → rule learning
curl -X POST http://localhost:8000/ingest \
  -H "Authorization: Bearer dumpling-dev-token" \
  -F "content_url=https://www.figma.com/community/plugin/12345/SomePlugin"
# Expected: agent asks how to handle → user replies → rule saved
```

---

## Design System

**Style**: Pastel neo-brutalism + Y2K pixel Windows

| Token | Value | Use |
|-------|-------|-----|
| `--color-pink` | `#FFB3C6` | Primary buttons, event badges |
| `--color-blue` | `#B3D9FF` | Title bars, link badges |
| `--color-mint` | `#B3FFD9` | Success, music badges |
| `--color-lavender` | `#D9B3FF` | Idea/software badges |
| `--color-butter` | `#FFF3B3` | Reminders, warnings |
| `--color-cream` | `#FAFAF0` | Card/panel backgrounds |
| `--color-black` | `#1A1A1A` | All borders + shadows |
| `--bg-grid` | `#E8F5E8` | Page background (mint + grid) |

- **Font**: `Press Start 2P` (headings/labels), `VT323` or `Courier New` (body)
- **Borders**: `3px solid #1A1A1A`, `border-radius: 0`
- **Shadows**: `5px 5px 0px #1A1A1A` (hard offset, no blur)
- **Buttons**: shift on click via `transform: translate(4px, 4px)` + shadow collapse

---

## Key Decisions Made

- **Claude Dispatch vs. Share Extension**: they coexist. Share Extension is the primary input (share from any app). Dispatch handles conversational follow-ups ("what happened with that thing I sent?").
- **Relay is hosted (Fly.io)**: phone can't talk to Mac directly off local WiFi. Relay queues items; Mac agent polls.
- **Rule engine runs before Claude**: if a routing rule matches, skip the LLM entirely for speed + cost.
- **Learning system**: unknown items trigger a multiple-choice question; user's answer becomes a stored routing rule.
- **Apple-native integrations via osascript**: no OAuth, no third-party APIs — Reminders, Calendar, Notes, Mail all via AppleScript subprocess calls.
- **SQLite locally → Postgres on Fly.io**: same SQLAlchemy models, just swap `DATABASE_URL`.
