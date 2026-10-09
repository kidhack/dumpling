# Dumpling — CLAUDE.md

## Project overview

Personal iOS content routing agent. Share anything from the iOS share sheet (links, events, ideas, job listings, etc.); content is queued locally and will be routed by a Mac agent to Apple Reminders, Calendar, Notes, or Mail.

## Repository layout

```
ios/                        iOS app + Share Extension
  project.yml               XcodeGen spec (source of truth — edit this, not .xcodeproj)
  DumplingApp/              Host app (SwiftUI, iOS 27)
  DumplingShareExtension/   Share extension (UIKit + SwiftUI)
  README.md                 Build + signing instructions

plans/
  plan.md                   v2 architecture, phases, design system

logo/                       Brand assets
ref/                        Reference screenshots / PDFs

archive/v1/                 v1 Python relay + agent (git-ignored locally)
```

**v1 code** (Python relay, agent, Apple tools) lives on the `v1` git branch. Read it with:

```bash
git show v1:<path>
# e.g. git show v1:relay/main.py
```

## Build commands

### iOS

Install XcodeGen (once):

```bash
brew install xcodegen
```

Generate and build for Simulator:

```bash
cd ios
xcodegen generate
xcodebuild \
  -project Dumpling.xcodeproj \
  -scheme Dumpling \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug \
  build
```

## Current phase

**Phase 1** — SwiftData models, App Group queue, settings screen. Share extension enqueues items; main app imports on launch. Extension loading on device being verified.

See `plans/plan.md` for the full roadmap.

## Design system

Y2K pastel neo-brutalism pixel aesthetic.

| Color | Hex |
|-------|-----|
| Pink | `#FFB3C6` |
| Blue | `#B3D9FF` |
| Mint | `#B3FFD9` |
| Lavender | `#D9B3FF` |
| Butter | `#FFF3B3` |
| Cream | `#FAFAF0` |
| Black | `#1A1A1A` |

- Fonts: Press Start 2P (headers), Courier New (body)
- Borders: 3px solid `#1A1A1A`, zero border-radius
- Shadows: 5px hard offset (no blur), `#1A1A1A`

## App Group

`group.com.kidhack.dumpling` — shared UserDefaults between app and extension.

## Key rules

- Never commit `.env` or secrets
- `project.yml` is the source of truth — don't commit `.xcodeproj` files (git-ignored)
- **Never add capabilities in Xcode's Signing & Capabilities UI** — xcodegen regenerates `.entitlements` and `Info.plist` on every run, wiping anything set in Xcode. All entitlements and Info.plist keys must live in `project.yml`.
- Check iOS API signatures against Apple docs before using; don't guess
- No relay/HTTP until Phase 2
