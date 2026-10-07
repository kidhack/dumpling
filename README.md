# 🥟 Dumpling

> Share anything from your phone. Dumpling keeps it — with full context — and only turns it into a reminder or calendar event when it's time to act.

**Status:** v2 in planning. See [`plans/plan.md`](plans/plan.md).

## What it does

- **Capture:** iOS share extension saves links, text, screenshots and notes instantly. Nothing is lost, even if sorting fails.
- **Sort:** saved rules first, then on-device AI (Apple Foundation Models, Claude fallback) into categories: Dev, Ideas, Design, Watch, Home, Music, Read, Purchase, Dine, Destinations. Unsure items go to an Inbox for one-tap review.
- **Rest:** items wait in Dumpling instead of cluttering Reminders.
- **Promote:** when something becomes relevant (a date, a place, the weekly digest, or you mark it urgent), Dumpling creates a reminder in **Next** or a Calendar event, linked back to the full item.
- **Find:** saves are searchable from Spotlight and Siri.

## Architecture

Native iOS 27 app — no server, no Mac agent.

```
Share Extension ──► SwiftData (App Group) ──► Dumpling app
                                              ├─ Sorter (rules → Foundation Models)
                                              ├─ Promoter (EventKit → Reminders / Calendar)
                                              ├─ Triggers (dates, places, weekly digest)
                                              └─ App Intents (Siri / Spotlight)
```

## Repo layout

```
ios/      Xcode project (generated with XcodeGen) — app + share extension
plans/    plan.md — v2 build plan
logo/     app icon source
```

## v1

The original version (share extension → Fly.io relay → Mac agent → AppleScript) lives on the [`v1` branch](https://github.com/kidhack/dumpling/tree/v1).

## Setup

Requires Xcode 27, a paid Apple Developer account (for App Groups), and an Apple Intelligence–capable iPhone. Build steps will land in `ios/README.md` in Phase 0.

Install the secret-scanning pre-push hook once per clone:

```bash
./scripts/setup-git-hooks.sh
```
