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

relay/                      FastAPI relay (phone → queue → Mac agent); see relay/README.md

plans/
  plan.md                   v2 architecture, phases, design system

logo/                       Brand assets
ref/                        Reference screenshots / PDFs

archive/v1/                 v1 Python relay + agent (git-ignored locally)
```

**v1 code** (Python relay, agent, Apple tools) lives in `archive/v1/` locally (git-ignored) and on the remote `v1` branch:

```bash
git show origin/v1:<path>
# e.g. git show origin/v1:relay/main.py
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

### Relay

```bash
cd relay
python3 -m venv .venv && .venv/bin/pip install -r requirements-dev.txt
.venv/bin/python -m pytest
```

## Current phase

**Phase 2** — Relay + Mac agent. The relay (`relay/`) is deployed at https://dumpling-relay.fly.dev (SQLite on a Fly volume; one machine only, deploy with `--ha=false`). Next: share extension POSTs to the relay, then the Mac agent.

See `plans/plan.md` for the full roadmap.

## Design system

Y2K pastel neo-brutalism pixel aesthetic.

**On hold:** the first pass at this style was unusable, so the app and share extension currently use stock iOS components (`List`, `Form`, `NavigationStack`). Don't reapply custom styling until it's been redesigned. The old styled UI is in commit `1d400ba`.

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

## Share extension checklist

If the extension stops showing in the share sheet, check these first (all in `ios/project.yml`):

- [ ] `NSExtensionActivationRule` is nested **inside `NSExtensionAttributes`**, not directly under `NSExtension`. Otherwise iOS silently never shows the extension.
- [ ] The app's dependency on the extension has `embed: true`. XcodeGen doesn't embed app-extension dependencies by default.
- [ ] `com.apple.security.application-groups: [group.com.kidhack.dumpling]` is under `entitlements.properties` for **both** targets.
- [ ] Never add capabilities in Xcode's Signing & Capabilities UI. `xcodegen generate` wipes them.
- [ ] After building, verify `Dumpling.app/PlugIns/DumplingShareExtension.appex` exists in the build products.

## Key rules

- Never commit `.env` or secrets
- `project.yml` is the source of truth — don't commit `.xcodeproj` files (git-ignored)
- **Never add capabilities in Xcode's Signing & Capabilities UI** — xcodegen regenerates `.entitlements` and `Info.plist` on every run, wiping anything set in Xcode. All entitlements and Info.plist keys must live in `project.yml`.
- Check iOS API signatures against Apple docs before using; don't guess
- Relay tokens are stored hashed; never add a default/dev token
