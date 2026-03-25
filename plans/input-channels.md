# Dumpling — Alternative Input Channels

The relay's `POST /ingest` endpoint is the single ingestion point. Any channel that can HTTP POST to it can feed Dumpling. This doc covers viable alternatives to the iOS Share Extension and curl.

---

## Claude Dispatch

**What it is:** Anthropic's phone-to-desktop feature (Claude Cowork). You text Claude from your phone; it runs tasks on your Mac.

**Relation to Dumpling:** Per HANDOFF Key Decisions, Dispatch and the Share Extension *coexist* — Share Extension for dumping content, Dispatch for conversational follow-ups ("what happened with that thing I sent?").

**Integration with Dumpling:** Claude Dispatch is a separate Anthropic product. It does not POST to Dumpling's relay. To use "text from phone" with Dumpling, you need one of the channels below. Dispatch is a parallel option if you're a Claude Pro/Max subscriber and want Anthropic's native mobile→desktop flow.

**Verdict:** Use Dispatch for follow-up chats; use Telegram (or Share Extension) for dumping into Dumpling.

---

## Telegram

**What it is:** Messaging app with a Bot API. Create a bot, message it, get webhooks.

**How it fits:** Message your Dumpling bot → webhook receives it → POST to relay `/ingest` → agent processes.

**Implementation:** A Telegram webhook endpoint is added to the relay. When you message `@YourDumplingBot`, the relay creates an Item and the Mac agent picks it up. No curl, no Share Extension required.

**Setup:**
1. Create a bot via [@BotFather](https://t.me/BotFather), get token.
2. Set `TELEGRAM_BOT_TOKEN` in relay `.env`.
3. Register webhook: `curl "https://api.telegram.org/bot<TOKEN>/setWebhook?url=https://your-relay-url/ingest/telegram"`.
4. For local dev, use [ngrok](https://ngrok.com/) to expose your relay to Telegram.

**Reply delivery:** The agent's reply is stored in the item. To push it back to Telegram, the relay would need to call `sendMessage` when an item is done. Optional follow-up.

**Verdict:** ✅ Best "text yourself" option. Implemented as `POST /ingest/telegram`.

---

## Neuron

**What it is:** Several products share this name:
- **Neuron (neuronapp.tech)** — Note-taking / knowledge management, not messaging.
- **Neuron AI** — Private on-device AI chat (iOS/Mac), no external API for forwarding.
- **Neuron (developer frameworks)** — AI agent messaging, blockchain protocols.

**Integration:** No clear path. None of these offer a simple "message → webhook" like Telegram. If you meant a different Neuron (e.g. a specific Slack/Discord bot), clarify and we can evaluate.

**Verdict:** Not viable without a concrete API or webhook support.

---

## Twilio (SMS)

**What it is:** SMS gateway. You get a phone number; when someone texts it, Twilio POSTs to your webhook.

**How it fits:** Text your Twilio number → webhook → relay `/ingest`. True "text yourself" (or text any number you control).

**Implementation:** Add `POST /ingest/twilio` that parses Twilio's webhook format, extracts body, creates Item. Requires `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, and a Twilio number.

**Verdict:** Feasible. Phase 4 per HANDOFF. More setup than Telegram (phone number, billing) but native SMS UX.

---

## Summary

| Channel        | Effort | "Text from phone" | Status                    |
|----------------|--------|-------------------|---------------------------|
| iOS Share Ext  | Medium | Share, not text   | Swift exists, needs Xcode |
| Telegram       | Low    | ✅                | Implemented               |
| Claude Dispatch| N/A    | Via Anthropic     | Separate product          |
| Twilio SMS     | Medium | ✅                | Phase 4                   |
| Neuron         | —      | —                 | No clear API              |
