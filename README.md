# 🥟 Dumpling

> idea dump agent for productivity — drop anything from your phone into your productivity stack.

Share a link, event, song, idea, or text from any iOS app → Dumpling classifies it, enriches it (ticket links, music links, GitHub summaries), and routes it to Apple Reminders, Calendar, Notes, or a draft file — automatically.

---

## Architecture

```
[iOS Share Extension]  →  [Relay (Fly.io)]  →  [Mac Agent]  →  Apple tools
      DumplingApp                FastAPI              Claude
```

## Quick Start

### 1. Relay (local dev)

```bash
cd dumpling/relay
pip install -r requirements.txt
cp ../.env.example .env   # edit as needed
uvicorn main:app --reload --port 8000
```

Test it:
```bash
curl -X POST http://localhost:8000/ingest \
  -H "Authorization: Bearer dumpling-dev-token" \
  -F "content_text=Reminder to buy tickets to the Chelsea Flower Show" \
  -F "source_app=Notes"
```

Or **text from your phone**: set up a Telegram bot and webhook — see `plans/input-channels.md`.

### 2. Mac Agent

```bash
cd dumpling
cd agent && pip install -r requirements.txt
cp .env.example .env   # add your ANTHROPIC_API_KEY (in agent/.env)
cd .. && python -m agent.main
```
Run from project root — `python -m agent.main` must see the `agent` package.

### 3. iOS Share Extension

Open `dumpling/ios/` in Xcode. Set your team/bundle ID, then run on your device or simulator.

On first launch, open **DumplingApp → Settings** and enter:
- **Relay URL**: `http://YOUR_MAC_IP:8000` (local) or `https://dumpling.fly.dev` (hosted)
- **Auth Token**: `dumpling-dev-token` (local) or your real token

---

## Content Types

| Type | Example | Action |
|------|---------|--------|
| `event` | "Chelsea Flower Show May 21" | Find tickets → propose Calendar event |
| `reminder` | "Buy garden tour tickets" | Create Apple Reminder |
| `music` | "Cut Copy Moments" or "Charlotte De Witte" | Apple Music catalog → add to Explore playlist |
| `linkedin_post` | "Excited to share…" | Create draft in ~/Dumpling/Drafts/linkedin/ |
| `link_save` | GitHub URL, Figma plugin link | Save to Apple Notes |
| `software_idea` | "App that does X" | Create project spec draft |
| `address` | "123 Main St, Brooklyn" | Apple Maps deeplink |
| `job_app` | "Senior Engineer at Stripe" | Find application URL |
| `unknown` | Anything else | Agent asks you → you teach it a rule |

## Learning System

When Dumpling doesn't know what to do, it asks you. Your answer becomes a routing rule:

```
You: share figma.com/community/plugin/XYZ
Agent: "Not sure how to handle this. Save to: a) Notes b) Reminder c) 'Figma Plugins' note?"
You: c
→ Rule saved: figma.com/community → append_to_note → "Figma Plugins"
→ All future Figma plugin links auto-route, no questions asked
```

Rules are editable at `http://localhost:8000/rules` (or in the dashboard — Phase 3).

## Project Structure

```
dumpling/
  relay/        FastAPI server (hosts the item queue + routing rules DB)
  agent/        Mac agent (polls relay, runs Claude, calls Apple tools)
  ios/          Xcode project (DumplingApp + DumplingShareExtension)
  dashboard/    Next.js web dashboard (Phase 3)
```

## Pushing to GitHub

The repo includes a pre-push hook that blocks pushes containing `.env` or API keys. After `git init`:

```bash
./scripts/setup-git-hooks.sh
```

Or manually: `git config core.hooksPath .githooks`

---

## Deploy to Fly.io

```bash
cd dumpling/relay
fly launch
fly secrets set MASTER_SECRET=$(python -c "import secrets; print(secrets.token_hex(32))")
fly secrets set DATABASE_URL=postgres://...  # from fly postgres create
fly secrets set TELEGRAM_BOT_TOKEN=your_bot_token  # for Telegram push
fly deploy
```

Update `RELAY_URL` in your agent `.env` and iOS app settings to the Fly.io URL.

---

## Telegram Troubleshooting

If you're not receiving confirmations in Telegram after sending items:

1. **Same relay for webhook and agent** — The agent must poll the same relay that receives the Telegram webhook. Set `RELAY_URL` in `agent/.env` to your relay URL (ngrok or Fly.io).
2. **Check config** — `curl http://localhost:8000/telegram-status` should show `"configured": true` when `TELEGRAM_BOT_TOKEN` is set in `relay/.env`.
3. **Restart relay** — After adding `telegram_chat_id` support, restart the relay so it runs the DB migration.
4. **New items only** — Items created before the Telegram push update don't have `telegram_chat_id`; send a fresh message to the bot.
5. **Relay logs** — Watch relay logs for "Sending to Telegram" or "Skip Telegram: ..." to see what's happening.

---

## Design

Pastel neo-brutalism + Y2K pixel Windows aesthetic.
- Font: `Press Start 2P` (headings) + `Courier New` (body)
- Colors: pink `#FFB3C6`, blue `#B3D9FF`, mint `#B3FFD9`, lavender `#D9B3FF`
- Borders: 3px solid black, 5px hard offset shadow, zero border-radius
