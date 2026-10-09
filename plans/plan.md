# Dumpling v2 — Architecture Plan

## What is Dumpling

Personal content routing agent. Share anything from your iPhone (links, events, music, ideas, LinkedIn posts, job listings, GitHub repos) via the native iOS share sheet. Apple's **on-device** model sorts it on the iPhone, and Dumpling files dated things into Apple Reminders and Calendar (which sync to the Mac through iCloud). Everything else stays in Dumpling's own list.

**AI runs locally.** Sorting uses the Foundation Models framework's `SystemLanguageModel` on the phone: no API keys, no per-item cost, works offline, shared content never leaves the device. No cloud LLM by default (not Claude, not Apple's `PrivateCloudComputeLanguageModel`).

**Goal:** Make it shareable with friends as a product.

---

## Architecture

```
iPhone
  Share Extension ── App Group queue ──► Dumpling app (on open / foreground)
                                           1. rules (substring / domain)
                                           2. on-device model (@Generable decision)
                                           3. EventKit → Reminders / Calendar  ──iCloud──► Mac
                                           4. everything else → Dumpling list
```

### Components

| Component | Stack | Location |
|---|---|---|
| iOS app + Share Extension | Swift / SwiftUI / SwiftData / FoundationModels / EventKit, iOS 26+ | `ios/` |
| Relay server *(parked)* | FastAPI + SQLite on a Fly volume | `relay/` |
| Mac agent *(parked)* | Python 3.13 + Anthropic SDK + osascript | `agent/` |
| Web dashboard | TBD | Phase 3 |

The relay and Mac agent were built and tested in Phase 2 before the switch to on-device sorting. They're not on the critical path. The relay could come back for a dashboard, multi-device sync, or sharing with friends, and the agent only if a Claude fallback is ever opted into.

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

`group.com.kidhack.dumpling` — shared UserDefaults between Dumpling.app and DumplingShareExtension: relay URL, auth token, and the pending-items queue.

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

### Phase 1 — SwiftData + App Settings UI ✅

**Goal:** Persistent local storage, settings screen for relay URL + auth token.

- [x] SwiftData models: `Item`, `RoutingRule`
- [x] Settings screen: relay URL, auth token fields (stored in App Group UserDefaults)
- [x] Share extension enqueues to App Group; main app imports on launch
- [x] Items list screen showing recently shared content (local only)

---

### Phase 2 — On-device sorting

**Goal:** The iPhone sorts every shared item with Apple's on-device model and files dated things into Reminders/Calendar itself.

Verified against the iOS 27 SDK (`FoundationModels.swiftinterface`): `SystemLanguageModel.default.availability` (`deviceNotEligible` / `appleIntelligenceNotEnabled` / `modelNotReady`), `LanguageModelSession(instructions:)`, `respond(to:generating:)` with a `@Generable` type, `response.content`. Nothing is marked unavailable in app extensions. A `rateLimited` error exists, so sort while the app is in the foreground.

- [ ] Sorter: `@Generable` decision (category, title, notes, due/start/end, location) from `SystemLanguageModel`, run in the app when it imports the queue
- [ ] Item states: `unsorted` → `sorted` → `filed`, or `needsReview`; items stay `unsorted` and retry when the model is unavailable (not eligible, Apple Intelligence off, model downloading)
- [ ] The user's note and quick tag override the model
- [ ] EventKit: reminders into a "Dumpling" list, events into the default calendar for new events; store the EventKit identifier on the item
- [ ] Links, ideas and anything unclear stay in Dumpling's list (iOS apps can't write Apple Notes)
- [ ] Rules engine (substring / domain) before the model, learned from the user's corrections
- [ ] Image sharing: the extension activates for images but drops the image data, so items save as "(no content)". Write the image to the App Group container, reference it from the pending item, and show a thumbnail
- [x] ~~Relay server~~ (parked): deployed at https://dumpling-relay.fly.dev; the share extension still uploads to it if Settings has a URL and token
- [x] ~~Mac agent~~ (parked): built and tested offline in `agent/`, never run live

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
