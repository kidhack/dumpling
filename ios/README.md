# iOS — Dumpling Share Extension

## Prerequisites

- Xcode 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

```bash
brew install xcodegen
```

## Generate the Xcode project

From the repo root:

```bash
cd ios
xcodegen generate
```

This creates `Dumpling.xcodeproj` from `project.yml`. Re-run any time you add Swift files.

## Signing (one-time setup)

Before building to a device you must set your Apple Developer team:

1. Open `Dumpling.xcodeproj` in Xcode.
2. Select the **Dumpling** target → Signing & Capabilities → set **Team** to your Apple Developer account.
3. Repeat for the **DumplingShareExtension** target.
4. Xcode will set a provisioning profile automatically.

## App Group (one-time setup)

The app and extension share a UserDefaults suite named `group.com.dumpling.app`.

1. In Xcode, select the **Dumpling** target → Signing & Capabilities → **+ Capability** → App Groups.
2. Add `group.com.dumpling.app`.
3. Repeat for **DumplingShareExtension**.
4. Register the App Group at [developer.apple.com](https://developer.apple.com) → Identifiers → App Groups if prompted.

## Build for Simulator

```bash
cd ios
xcodegen generate
xcodebuild \
  -project Dumpling.xcodeproj \
  -scheme Dumpling \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -configuration Debug \
  build
```

## Run on device

1. Connect iPhone over USB and trust the Mac.
2. In Xcode, select your iPhone as the destination.
3. ⌘R to build and run.
4. The share sheet extension appears in any app after the first install.

## Phase 0 behaviour

The share extension logs the extracted payload (URL, text, image, source app, note, quick tag) to the Xcode console and dismisses. No network calls are made. This is intentional — relay integration comes in Phase 2.
