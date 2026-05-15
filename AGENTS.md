# Agent Notes

This repository contains a SwiftUI radio app for Andon FM.

## Project Shape

- Main app code lives in `Sources/AndonCone`.
- Use `AndonCone.xcodeproj` for real iOS, iPadOS, macOS, TestFlight, and App Store work.
- Shared schemes are checked in for `Andon Cone iOS` and `Andon Cone macOS`.
- `Package.swift` and `scripts/build-app.sh` are local macOS helper paths only; do not treat them as the primary release build.

## Build Checks

Prefer these checks after code changes:

```sh
xcodebuild -project AndonCone.xcodeproj -scheme "Andon Cone macOS" -configuration Debug -destination "platform=macOS" build
xcodebuild -project AndonCone.xcodeproj -scheme "Andon Cone iOS" -configuration Debug -destination "generic/platform=iOS Simulator" build
```

The bundle identifier for both App Store platforms is `io.aparker.andoncone`.

## Signing And Review Notes

- iOS entitlements are intentionally empty for ordinary iPhone/iPad development builds.
- Do not add `com.apple.developer.carplay-audio` until Apple approves the managed CarPlay Audio entitlement for the developer account and provisioning profile.
- The macOS target uses App Sandbox and outgoing network client entitlements for Mac App Store submission.
- `Config/macOS/Info.plist` must keep `LSApplicationCategoryType` set to `public.app-category.music`.

## App Behavior

- Stream URLs are Live365 mount URLs embedded in `PlayerModel.stations`.
- Rich metadata comes from `https://os.andonlabs.com/api/public/radio/metadata` and `https://os.andonlabs.com/api/public/radio/stats`.
- Metadata polling is intentionally automatic; avoid reintroducing visible manual refresh UI unless explicitly requested.
- iOS now-playing info must include station artwork through `MPNowPlayingInfoCenter` so Lock Screen, Dynamic Island, and CarPlay surfaces show channel art.
