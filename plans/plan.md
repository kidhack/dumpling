# Dumpling v2 — Native iOS App Plan

> Share anything from any iOS app → Dumpling keeps it (with full context), sorts it into one of Alex's categories, and only pushes it into Reminders/Calendar when it's actually time to act.

This plan replaces the v1 architecture (iOS share extension → Fly.io relay → Mac polling agent → osascript). v1 code stays in the repo as reference only.

---

## 1. Why v1 failed (design constraints for v2)

| v1 problem | Evidence | v2 rule |
|---|---|---|
| Info lost on save | EventKit can't set the Reminders URL field; links/tags got crammed into notes as `#hashtags` (`agent/tools/apple_reminders.py`, `create_reminder.swift`) | **Dumpling is the store of record.** Reminders/Calendar only get a pointer back. |
| Silent failures | Local `relay/dumpling.db`: many items marked `done` whose result was `osascript timed out` | **Save raw first, process second.** An item exists the instant the share sheet closes. Failures are visible states, never "done". |
| Mis-categorized links | One forced category at share time; no review path | **Confidence + review.** Low-confidence items land in Inbox for one-tap confirm. Corrections become rules. |
| Fragile pipeline | Needs relay + awake Mac + Claude + AppleScript | **Everything on the phone.** No relay, no Mac agent. |
| Reminders clutter | Ten "someday" lists sitting in Reminders until they rot into **Stale** | **Only `Next` lives in Reminders.** Everything else waits in Dumpling until it's relevant. |

---

## 2. Product model

### Categories (mirror Alex's current Reminders lists)

| Category | Icon (SF Symbol, match current list) | Default home | Promotes to **Next** when… |
|---|---|---|---|
| Dev | `curlybraces` | Dumpling | Weekly review / manual |
| Ideas | `lightbulb.fill` | Dumpling | Weekly review / manual |
| Design | `wrench.and.screwdriver.fill` | Dumpling | Weekly review / manual |
| Watch | `tv.fill` | Dumpling | Release date reached |
| Home | `heart.fill` | Dumpling (urgent → Next) | Due date / season / weekend |
| Music | `music.note` | Dumpling | Manual (later: show near you) |
| Read | `book.fill` | Dumpling | Weekend digest / manual |
| Purchase | `banknote.fill` | Dumpling | Due date (gift occasion) / location / manual |
| Dine | `fork.knife` | Dumpling | Location (near it) / manual |
| Destinations | `airplane` | Dumpling | Manual (trip planning) |

Plus two system destinations that are *not* categories:
- **Next** — the one Reminders list Dumpling writes to. "Do this now."
- **Calendar** — dated events (flyers, tickets, shows). Created directly with the URL field set.

`Stale` stops being a list: it's the **Archive** state (auto after N days untouched, default 60, still searchable).

### Item lifecycle

```
captured ──► sorted ──► (resting) ──► surfaced ──► promoted ──► done
   │            │                         │            (Reminder in Next
   │            └─► needsReview (Inbox)   │             or Calendar event)
   └─► failed (visible, retryable)        └─► snoozed / archived
```

- `captured`: raw payload saved by the share extension. Never lost.
- `sorted`: category + extracted fields assigned (by rule or model).
- `needsReview`: confidence below threshold → Inbox.
- `surfaced`: a trigger fired (date, location, digest) → notification.
- `promoted`: Dumpling created a Reminder/Event and stored its identifier.
- `archived`: the new "Stale".

### Promotion triggers (v2.0 scope = on-device only)
1. **Date** — model extracts a relevant future date (on-sale date, release date, event date, deadline). Dumpling schedules a local notification / promotion N days before.
2. **Location** — Dine, Purchase (store), Home (hardware store) items with a place get a geofence. iOS caps region monitoring (~20 regions): keep the nearest/most recent active.
3. **Weekly digest** — one notification (default Sunday morning) listing resting items per category; actions: Promote, Snooze, Archive.
4. **Urgency override** — share-sheet note containing "now"/"urgent"/"today", or the "Next" toggle in the share UI → straight to Reminders.

Deferred (needs background web checks): price drops, artist tour dates, streaming availability.

---

## 3. Architecture

```
┌─────────────────────┐   App Group container   ┌──────────────────────────┐
│ Share Extension     │ ───── SwiftData ──────► │ Dumpling App             │
│ - extract payload   │                          │ - Sorter (rules → model) │
│ - write `captured`  │                          │ - Promoter (EventKit)    │
│ - optional quick    │                          │ - Triggers (dates, geo,  │
│   category / Next   │                          │   digest)                │
└─────────────────────┘                          │ - App Intents / Spotlight│
                                                  └──────────────────────────┘
```

- **Targets:** `Dumpling` (iOS app, SwiftUI), `DumplingShareExtension`. Later: macOS via multiplatform target + CloudKit.
- **Min OS:** iOS 27.
- **Project generation:** XcodeGen (`project.yml` in `ios/`) so the project is editable from the terminal. Alex opens Xcode only to set signing team and run on device.
- **Persistence:** SwiftData store in App Group container `group.<bundle-prefix>.dumpling`. Share extension writes; app reads/processes.
- **Sorting:**
  1. Rules first (port `agent/rules.py`: substring / domain / regex → category). Rules stored in SwiftData.
  2. Then model via **Foundation Models framework** with guided generation (`@Generable` struct output). Try on-device Apple model first; fall back to Claude provider (API key in Keychain) when on-device is unavailable or confidence is low. ⚠️ Verify the iOS 27 `LanguageModel` provider API and Claude provider setup against the SDK/WWDC26 docs before implementing.
  3. Multimodal: images (screenshots, flyers) go to the model directly; Vision OCR as fallback.
- **Promotion:** EventKit directly from the app (`requestFullAccessToReminders`, `requestFullAccessToEvents`). Reminder notes contain `dumpling://item/<id>` deep link + original URL. Calendar events set `url`. Store `ekIdentifier` on the item.
- **Discovery:** App Intents — `ItemEntity` exposed to Spotlight / Siri ("find the Figma plugin I saved"), plus intents: `SaveToDumpling`, `PromoteItem`, `OpenItem`. ⚠️ Verify iOS 27 entity/intent schema APIs.
- **Background:** `BGAppRefreshTask` to process any `captured` items the extension couldn't finish, and to schedule date triggers.

---

## 4. Data model (SwiftData, first pass)

```swift
@Model final class Item {
    var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var state: ItemState              // captured, sorted, needsReview, surfaced, promoted, done, archived, failed
    var sourceApp: String?

    // Raw capture — never mutated after save
    var rawText: String?
    var rawURL: URL?
    var rawImagePath: String?          // file in App Group container
    var userNote: String?

    // Sorted output
    var category: Category?
    var title: String?
    var summary: String?
    var confidence: Double?
    var sortedBy: SortSource?          // rule, onDevice, claude, user
    var linkPreview: LinkPreview?      // title, site, image (LPMetadataProvider)

    // Triggers
    var relevantDate: Date?
    var place: Place?                  // name, lat/lng, radius
    var snoozedUntil: Date?

    // Promotion
    var promotedTo: PromotionTarget?   // reminder, calendarEvent
    var ekIdentifier: String?

    var processingError: String?
}

@Model final class Rule {
    var pattern: String
    var patternType: PatternType       // substring, domain, regex
    var category: Category
    var promote: Bool                  // e.g. "zeffy.com → Next"
    var createdFromItemID: UUID?
}
```

`Category` is an enum matching section 2. Keep raw + sorted fields separate so re-sorting is always possible.

---

## 5. Screens

1. **Inbox** — `needsReview` + `failed` items. Swipe: confirm category / change / Next / archive. Changing a category offers "Always do this for `<domain>`?" → creates a Rule.
2. **Library** — grid of the 10 categories (same colors/icons as the Reminders lists); tap → item list with link previews.
3. **Coming Up** — items with a relevant date or active geofence, sorted by soonest.
4. **Item detail** — preview, raw capture, user note, extracted fields, actions: Promote to Next, Add to Calendar, Snooze, Archive, Open original.
5. **Settings** — Reminders list name (default `Next`), calendar name (v1 used `Social`), digest day/time, archive-after days, Claude API key, rules editor.
6. **Share sheet UI** — keep v1 Y2K pastel pixel style (`ios/DumplingShareExtension/ShareViewController.swift`). Show: preview, note field, suggested category chip (tap to change), "Next" toggle, Save. Must close in < 1s; sorting continues in the app/background if needed.

---

## 6. Build phases

Each phase ends with something Alex can run on his phone.

### Phase 0 — Project setup
- [ ] Create `ios/project.yml` (XcodeGen) with app + share extension targets, App Group, iOS 27 deployment target.
- [ ] Move/adapt existing `ShareViewController.swift` / `ShareViewModel.swift` into the extension target; remove relay upload code.
- [ ] `ios/README.md`: `brew install xcodegen && xcodegen generate`, signing steps.
- [ ] Add `CLAUDE.md` at repo root describing v2 layout and that `relay/` + `agent/` are legacy reference.
- **Done when:** app + extension build and install on device; sharing a URL shows the share UI.

### Phase 1 — Capture that never loses anything
- [ ] SwiftData model + App Group store shared by both targets.
- [ ] Extension saves `captured` item (text, URL, image, note, source app) and dismisses.
- [ ] App lists all items (plain list), shows raw fields.
- [ ] Link previews via `LPMetadataProvider`.
- **Done when:** 20 varied shares (Safari, Instagram, Music, Maps, screenshots, plain text) all appear with nothing missing.

### Phase 2 — Sorting
- [ ] Port rule engine from `agent/rules.py`; seed rules from v1 `routing_rules` table if useful.
- [ ] Foundation Models sorter with `@Generable` output: `category`, `title`, `summary`, `relevantDate`, `place`, `urgency`, `confidence`.
- [ ] Prompt: adapt `SYSTEM_PROMPT` in `agent/agent.py`, rewritten for the 10 categories + Next/Calendar.
- [ ] Claude fallback provider; Keychain-stored key.
- [ ] Confidence threshold (start 0.7) → `needsReview`.
- [ ] Inbox screen + "always do this" rule creation.
- [ ] Eval set: `ios/DumplingTests/sorting_cases.json` — 40+ real examples (pull from v1 `relay/dumpling.db` and Alex's current Reminders lists) with expected category. Test target runs it.
- **Done when:** ≥ 90% correct category on the eval set; everything else lands in Inbox, not in a wrong category.

### Phase 3 — Promotion (Reminders + Calendar)
- [ ] EventKit permission flow.
- [ ] Promote to `Next` reminder: clean title (port `_clean_title` from `apple_reminders.py`), notes = original URL + `dumpling://item/<id>`, due date if any.
- [ ] Add to Calendar: title, start/end, location, `url`, notes; configurable calendar.
- [ ] Urgency override from share sheet → auto-promote.
- [ ] Deep link handling `dumpling://item/<id>`.
- [ ] Sync back: when the Reminder is completed, mark item `done` (check on app foreground via `ekIdentifier`).
- **Done when:** share a ticket link with "buy Friday" → reminder in Next due Friday, tapping link opens the item in Dumpling.

### Phase 4 — Resting + triggers
- [ ] Library and Coming Up screens.
- [ ] Date triggers → local notifications with Promote / Snooze actions.
- [ ] Location triggers (Core Location region monitoring, nearest ≤ 20).
- [ ] Weekly digest notification.
- [ ] Auto-archive after N days untouched.
- **Done when:** a Dine item fires a notification when near the restaurant; Sunday digest arrives with actionable items.

### Phase 5 — Siri, Spotlight, migration
- [ ] App Intents: `ItemEntity` in Spotlight; Save / Promote / Open intents.
- [ ] One-time importer: read Alex's existing Reminders lists (Dev, Ideas, Design, Watch, Home, Music, Read, Purchase, Dine, Destinations, Stale) via EventKit → create Dumpling items in matching categories (Stale → archived). Preview before import; don't delete originals until Alex confirms.
- **Done when:** "Hey Siri, find the GitHub repo I saved about agents" returns the item; old lists imported.

### Later
- macOS target + CloudKit sync.
- Background web checks: price drops, tour dates, streaming availability.
- Music: add to Apple Music "Explore" playlist via MusicKit (v1 `apple_music.py` spec).

---

## 7. Reuse from v1

| v1 file | Use in v2 |
|---|---|
| `ios/DumplingShareExtension/*.swift` | Starting point for extension UI + payload extraction |
| `agent/rules.py` | Port matching logic to Swift |
| `agent/agent.py` `SYSTEM_PROMPT` | Basis for sorter instructions |
| `agent/tools/apple_reminders.py` `_clean_title` | Port title cleanup |
| `relay/dumpling.db` | Mine for eval cases |
| `plans/dumpling-*-pipeline.md` | Per-type behavior ideas (events, music, jobs, etc.) |
| `logo/` | App icon |

Do not port: relay, Mac poll loop, osascript tools, Telegram input.

---

## 8. Open questions for Alex
1. Bundle ID prefix and Apple Developer team (paid account needed for App Groups).
2. Calendar for events — keep `Social`?
3. Should Claude fallback be on by default, or on-device only unless enabled?
4. Digest day/time and archive-after days.
5. Are LinkedIn drafts and job leads still wanted, or drop them? (They don't map to a current list.)
6. Is "Next" the exact Reminders list name the app should write to?
