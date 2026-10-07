# Dumpling v2 — Architecture Plan

## What is Dumpling

Personal content routing agent. Share anything from your iPhone (links, events, music, ideas, LinkedIn posts, job listings, GitHub repos) via the native iOS share sheet. A Mac agent powered by Claude classifies the content, enriches it, and routes it to Apple Reminders, Calendar, Notes, Mail, or creates draft files.

**Goal:** Make it shareable with friends as a product.

---

## Architecture

```
iPhone (iOS Share Extension)
    ↓  HTTPS POST /ingest
Hosted Relay (Fly.io — FastAPI + Postgres)
    ↓  polling every 30s
Mac Agent (Python + Anthropic SDK + osascript)
    → Apple Reminders, Calendar, Notes, Mail
```

### Components

| Component | Stack | Location |
|---|---|---|
| iOS app + Share Extension | Swift / SwiftUI / iOS 27 | `ios/` |
| Relay server | FastAPI + SQLAlchemy + Postgres | `relay/` (Phase 2) |
| Mac agent | Python + Anthropic SDK | `agent/` (Phase 2) |
| Web dashboard | Next.js | `dashboard/` (Phase 3) |

---

## Design System

**Y2K pastel neo-brutalism pixel aesthetic.**

| Token | Value |
|---|---|
| Pink | `#FFB3C6` |
| Blue | `#B3D9FF` |
| Mint | `#B3FFD9` |
| Lavender | `#D9B3FF` |
| Butter | `#FFF3B3` |
| Cream | `#FAFAF0` |
| Black | `#1A1A1A` |

- Font: Press Start 2P (headers), Courier New (body/monospace)
- Borders: 3px solid black, zero border-radius
- Shadows: 5px hard offset (no blur), black
- Title bar: blue (`#B3D9FF`) with □ — × chrome buttons

---

## Content Types

`event` | `reminder` | `music` | `linkedin_post` | `link_save` | `software_idea` | `address` | `job_app` | `unknown`

---

## App Group

`group.com.dumpling.app` — shared UserDefaults between Dumpling.app and DumplingShareExtension for relay URL + auth token.

---

## Phases

### Phase 0 — iOS XcodeGen Project Setup ✅

**Goal:** Buildable Xcode project with share extension that logs payload and dismisses. No relay, no networking.

- [x] `ios/project.yml` — XcodeGen spec for Dumpling app + DumplingShareExtension
- [x] `ios/DumplingApp/` — Minimal SwiftUI host app (placeholder screen)
- [x] `ios/DumplingShareExtension/` — Updated Swift files (Y2K UI, log + dismiss, no HTTP)
- [x] App icon from `logo/dumpling-big.png`
- [x] `ios/README.md` — XcodeGen install + generate + signing + run instructions
- [x] Root `CLAUDE.md` — v2 layout, build commands, v1 location
- [x] `.gitignore` — XcodeGen/Xcode generated files
- [x] `xcodebuild` clean build for iOS Simulator

**Done when:** `xcodebuild` exits 0 for iOS Simulator. No device required.

---

### Phase 1 — SwiftData + App Settings UI

**Goal:** Persistent local storage, settings screen for relay URL + auth token.

- [ ] SwiftData models: `Item`, `RoutingRule`
- [ ] Settings screen: relay URL, auth token fields (stored in App Group UserDefaults)
- [ ] Share extension reads config from App Group
- [ ] Items list screen showing recently shared content (local only)

---

### Phase 2 — Relay + Mac Agent

**Goal:** End-to-end routing from iPhone to Mac productivity tools.

- [ ] Relay server (FastAPI + Postgres) deployed on Fly.io
- [ ] Share extension POSTs to relay on "🥟 DUMPLING IT"
- [ ] Mac agent polls relay, calls Claude, runs osascript tools
- [ ] Routing rules engine (substring/domain/regex) with learn-from-unknown
- [ ] Apple tools: Reminders, Calendar, Notes, Mail

---

### Phase 3 — Web Dashboard

**Goal:** View and manage items + rules from a browser.

- [ ] Next.js dashboard at `dashboard/`
- [ ] Auth via relay token
- [ ] Items feed, rules editor, agent question/reply UI

---

### Phase 4 — Push Notifications

**Goal:** Agent replies delivered to iPhone as push notifications.

- [ ] APNs integration
- [ ] Relay sends push on agent question or routing confirmation

---

## v1 Reference

v1 (Python relay + agent + basic Swift extension) lives on the `v1` git branch and is archived at `archive/v1/` (git-ignored). Read with `git show v1:<path>`.
