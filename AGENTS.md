# Agent Notes

This repository contains a SwiftUI radio app for Andon FM.

## Project Shape

- Main app code lives in `Sources/AndonCone`.
- Play-history collector code lives in `collector`.
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
- Optional tips use StoreKit consumable in-app purchases. Keep them optional and never gate playback, metadata, CarPlay, or any other app functionality behind a tip.
- Tip product IDs are `io.aparker.andoncone.tip.small`, `io.aparker.andoncone.tip.medium`, and `io.aparker.andoncone.tip.large`.

## App Behavior

- Stream URLs are Live365 mount URLs embedded in `PlayerModel.stations`.
- Rich metadata comes from `https://os.andonlabs.com/api/public/radio/metadata` and `https://os.andonlabs.com/api/public/radio/stats`.
- Metadata polling is intentionally automatic; avoid reintroducing visible manual refresh UI unless explicitly requested.
- iOS now-playing info must include station artwork through `MPNowPlayingInfoCenter` so Lock Screen, Dynamic Island, and CarPlay surfaces show channel art.

## Collector Behavior

- The collector is a separate Go service that can run as one Fly Machine with SQLite on a persistent volume.
- Keep `observations` as the minute-grain source of truth: one row per station per UTC minute, with `minute_epoch`, `observed_date`, and `minute_of_day` populated for analytics.
- `airings` is a derived convenience table for approximate play sessions; do not treat it as more authoritative than `observations`.
