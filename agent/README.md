# Dumpling Mac Agent

Claims shared items from the relay, asks Claude what each one is, and files it into Apple apps:

| Claude's decision | Where it goes |
|---|---|
| `create_note` (links, ideas, anything unclear) | Notes → **Dumpling** folder |
| `create_reminder` | Reminders → **Dumpling** list |
| `create_event` | Calendar → first writable calendar (or `CALENDAR`) |
| `draft_email` | Opens a Mail compose window. **Never sends.** |

Each item gets one structured-output call to `claude-opus-5-5` (effort `low`, refusal fallbacks on). Claude only returns a decision; `main.py` performs it. Results are written back to the relay as `routed` (with a summary) or `failed` (with the error). Transient API errors put the item back to `pending`.

AppleScript receives all shared content as `on run argv` arguments, never as script source, so a crafted page title can't run commands.

## Setup

Needs Python 3.10+ (the Anthropic SDK 1.x requirement).

```bash
cd agent
/opt/homebrew/bin/python3.13 -m venv .venv
.venv/bin/pip install -r requirements.txt
cp .env.example .env    # then fill in RELAY_TOKEN and ANTHROPIC_API_KEY
```

## Run

```bash
.venv/bin/python main.py --dry-run   # show decisions for pending items; claims nothing, touches no apps
.venv/bin/python main.py --once      # process pending items, then exit
.venv/bin/python main.py             # poll every POLL_SECONDS (default 30)
```

The first real run triggers macOS prompts asking to let your terminal control Reminders, Calendar, Notes and Mail. Allow them, or the AppleScript calls fail.

## Test

```bash
.venv/bin/pip install pytest
.venv/bin/python -m pytest tests
```
