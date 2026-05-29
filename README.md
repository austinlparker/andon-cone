# Andon Cone

A SwiftUI radio app for listening to the Andon FM streams without keeping the web page open. It supports iPhone, iPad, and macOS as native apps from one shared codebase. The iOS target also contains CarPlay scene code that can be enabled after Apple approves the managed CarPlay Audio entitlement.

## Streams

The stream URLs are embedded in the server-rendered data on `https://andonlabs.com/radio`. Each one redirects through Live365 to an `audio/mpeg` stream.

| Station | Host | Stream |
| --- | --- | --- |
| Backlink Broadcast | Gemini 3.1 Pro Preview | `https://streaming.live365.com/a13541` |
| Thinking Frequencies | Claude Opus 4.7 | `https://streaming.live365.com/a46431` |
| OpenAIR | GPT 5.5 | `https://streaming.live365.com/a81044` |
| Grok and Roll | Grok 4.3 | `https://streaming.live365.com/a15419` |

## Metadata

The app polls two Andon Labs endpoints every 20 seconds:

- `https://os.andonlabs.com/api/public/radio/metadata` — current track title and artist per station, keyed by station UUID.
- `https://os.andonlabs.com/api/public/radio/stats` — listener counts, current and upcoming programming blocks, recent station tweets, top tracks of the week, station artwork, and TTS model info.

The audio itself still streams from `https://streaming.live365.com/<mount>` (see the table above). Live365's own metadata endpoint is not used because the Andon endpoints expose richer station state.

## Play History Collector

The public metadata API exposes current station state, not historical plays. The `collector/` directory contains a small Go service that can run on Fly.io with a persistent SQLite volume and poll the metadata once per minute.

The collector writes append-only observation facts plus derived airing intervals, so it can answer both "how often was this track observed?" and "when does it tend to play?" See `collector/README.md` for schema notes, local commands, Fly setup, and example SQL.

## App Targets

The shared SwiftUI source lives in `Sources/AndonCone`.

- `AndonCone.xcodeproj` contains app targets and shared schemes for iOS/iPadOS and macOS.
- The iOS target uses `Config/iOS/Info.plist` for background audio and CarPlay scene registration.
- `Config/iOS/AndonCone.entitlements` is intentionally empty for ordinary iPhone/iPad development builds.
- The macOS target uses `Config/macOS/Info.plist` and `Config/macOS/AndonCone.entitlements` with App Sandbox plus outgoing network access for Mac App Store submission.
- Both targets use the bundle identifier `io.aparker.andoncone` for a single multi-platform App Store Connect app record.

CarPlay requires Apple approval for the managed CarPlay Audio entitlement. Until that entitlement is added to the developer account and provisioning profile, leave `com.apple.developer.carplay-audio` out of the active entitlements file; otherwise Xcode cannot create a valid development profile for iPhone installs. The CarPlay scene configuration is present, but the app will not appear on a real CarPlay head unit until the entitlement is approved and re-added.

The CarPlay implementation presents the station list with `CPListTemplate`; selecting a station starts playback and pushes the shared `CPNowPlayingTemplate`. The app publishes `MPNowPlayingInfoCenter` metadata, lock screen and Dynamic Island station artwork, and handles remote play/pause commands.

## Optional Tips

Andon Cone includes an optional StoreKit tip jar. Tips are consumable in-app purchases and do not unlock content, playback, metadata, CarPlay, or any other feature.

Create these consumable products in App Store Connect before submitting a build that shows the tip jar:

| Product ID | Suggested Reference Name | Suggested Price |
| --- | --- | --- |
| `io.aparker.andoncone.tip.small` | Small Tip | $1.99 |
| `io.aparker.andoncone.tip.medium` | Medium Tip | $4.99 |
| `io.aparker.andoncone.tip.large` | Large Tip | $9.99 |

Suggested App Review note: "The Support Andon Cone screen contains optional StoreKit tips. Tips support app development and do not unlock content or functionality."

## Requirements

- macOS 14 or later for the macOS app
- iOS/iPadOS 17 or later for the mobile app
- Swift 6 toolchain
- Xcode for iOS/iPadOS/CarPlay builds

## Build

```sh
xcodebuild -project AndonCone.xcodeproj -scheme "Andon Cone macOS" -configuration Debug -destination "platform=macOS" build
xcodebuild -project AndonCone.xcodeproj -scheme "Andon Cone iOS" -configuration Debug -destination "generic/platform=iOS Simulator" build
```

For iPhone, iPad, and CarPlay, open `AndonCone.xcodeproj`, select the `Andon Cone iOS` scheme, set your development team, and run on an iOS simulator/device. For CarPlay simulator testing, use Xcode's CarPlay simulator after the target builds and after the entitlement is approved.

`scripts/build-app.sh` remains as a local macOS package-bundle helper, but App Store/TestFlight work should use the Xcode project.

## Run During Development

```sh
swift run
```

The app opens as a normal SwiftUI window with station cards, a now-playing panel, playback controls, current programming block, upcoming schedule, top tracks, and recent station activity. Keyboard shortcut: <kbd>space</kbd> to play/pause.

The macOS app uses a native `NavigationSplitView` sidebar and detail view. The iOS compact layout starts with a horizontal station rail followed by the listening surface.

## App Store Assets

Screenshot captures live under `AppStoreAssets/Screenshots`.

- iPhone upload-ready screenshot: `AppStoreAssets/Screenshots/iPhone/AppStoreUpload/iphone-6-7-now-playing-1284x2778.png`
- iPad screenshot: `AppStoreAssets/Screenshots/iPad/ipad-pro-13-now-playing.png`
- Mac screenshot: `AppStoreAssets/Screenshots/Mac/`

App Store Connect rejects newer simulator sizes for the 6.7-inch iPhone slot, so use the `1284x2778` upload-ready iPhone image.
