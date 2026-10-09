# iOS — Dumpling Share Extension

## Prerequisites

- Xcode 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

```bash
brew install xcodegen
```

## Generate the Xcode project

From `ios/`:

```bash
xcodegen generate
```

This creates `Dumpling.xcodeproj` from `project.yml`. Re-run any time you edit `project.yml` or add Swift files. **Never edit `.xcodeproj` directly** — it is git-ignored and regenerated on every run.

> **Never add capabilities in Xcode's Signing & Capabilities UI.** XcodeGen regenerates
> `.entitlements` and `Info.plist` files on every `xcodegen generate`, wiping anything set
> in Xcode. All entitlements must be in `project.yml`.

## Signing

Team ID `FVJVPTJ48N` and automatic signing are set in `project.yml` and apply to both targets. No manual Xcode setup is needed.

## Build for Simulator

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

## Run on device

1. Connect iPhone over USB.
2. Open `ios/Dumpling.xcodeproj` in Xcode.
3. Select your iPhone as the destination.
4. ⌘R — Xcode builds, signs, and installs both targets.
5. **Open the Dumpling app once** after install; iOS won't register the extension until the host app has launched.

## Test the share extension

1. In Safari, navigate to any page.
2. Tap the Share button → scroll the app row right → tap **More**.
3. Find **Dumpling** and enable it if needed, then share.
4. If it doesn't appear, run the **DumplingShareExtension** scheme (Product → Scheme → DumplingShareExtension), pick Safari as the app to launch, then share again.

## Debug extension loading

Open **Console.app** on the Mac, select your iPhone, and filter by `DumplingShareExtension` or `pkd` to see extension registration and crash messages.

## App Group

Both targets share `group.com.kidhack.dumpling` for queuing items between the extension and the main app. This is configured in `project.yml`; no manual setup is needed.
