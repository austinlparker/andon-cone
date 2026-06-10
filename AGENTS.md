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
- iOS uses MusicKit for the add-to-library affordance. The capability is self-service (enable it on the App ID in the developer portal — no Apple review needed), and `NSAppleMusicUsageDescription` lives in `Config/iOS/Info.plist`. Keep library access optional; never gate playback or metadata on Apple Music sign-in or subscription. macOS deliberately does not expose an add-to-library button because `MusicLibrary.add()` is iOS-only and the read APIs are macOS 14+; the Apple Music link on the album line is the macOS equivalent.

## App Behavior

- Stream URLs are Live365 mount URLs embedded in `PlayerModel.stations`.
- Rich metadata comes from `https://os.andonlabs.com/api/public/radio/metadata` and `https://os.andonlabs.com/api/public/radio/stats`.
- Track-level album info is enriched anonymously via the iTunes Search API (`https://itunes.apple.com/search`). No API key. Results require an artist substring match before being accepted to guard against bad matches on live/remix versions.
- Metadata polling is intentionally automatic; avoid reintroducing visible manual refresh UI unless explicitly requested. Stale/error states are intentionally silent in the chrome — only a small `wifi.exclamationmark` indicator surfaces when staleness *and* an error coincide.
- Image and track-metadata caches live under `~/Library/Caches/AndonCone/` (`Artwork/` for SwiftUI images, `Tracks/` for JSON-encoded `EnrichedTrack` lookups, both keyed by SHA256 of the source identifier). Both survive relaunches; clearing them is a no-op the next launch will repopulate.
- iOS now-playing info must include station artwork through `MPNowPlayingInfoCenter` so Lock Screen, Dynamic Island, and CarPlay surfaces show channel art.

## Collector Behavior

- The collector is a separate Go service that can run as one Fly Machine with SQLite on a persistent volume.
- Keep `observations` as the minute-grain source of truth: one row per station per UTC minute, with `minute_epoch`, `observed_date`, and `minute_of_day` populated for analytics.
- `airings` is a derived convenience table for approximate play sessions; do not treat it as more authoritative than `observations`.
