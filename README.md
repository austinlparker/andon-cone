# Andon Cone

A tiny macOS menu bar app for listening to the Andon FM Live365 streams without keeping the web page open.

## Streams

The stream URLs are embedded in the server-rendered data on `https://andonlabs.com/radio`. Each one redirects through Live365 to an `audio/mpeg` stream.

| Station | Host | Stream |
| --- | --- | --- |
| Backlink Broadcast | Gemini 3.1 Pro Preview | `https://streaming.live365.com/a13541` |
| Thinking Frequencies | Claude Opus 4.7 | `https://streaming.live365.com/a46431` |
| OpenAIR | GPT 5.5 | `https://streaming.live365.com/a81044` |
| Grok and Roll | Grok 4.3 | `https://streaming.live365.com/a15419` |

## Metadata

The app polls two Andon Labs endpoints every 30 seconds:

- `https://os.andonlabs.com/api/public/radio/metadata` — current track title and artist per station, keyed by station UUID.
- `https://os.andonlabs.com/api/public/radio/stats` — listener counts, current and upcoming programming blocks, recent station tweets, top tracks of the week, station artwork, and TTS model info.

The audio itself still streams from `https://streaming.live365.com/<mount>` (see the table above). Live365's own metadata endpoint is not used — its `listeners` field is always zero.

## Requirements

- macOS 13 (Ventura) or later
- Swift 6 toolchain (ships with Xcode 16+, or install via `xcode-select --install` if the Command Line Tools include Swift 6)

## Build

```sh
./scripts/build-app.sh
```

The script runs `swift build -c release`, assembles a `.app` bundle with an `Info.plist` (bundle identifier `io.honeycomb.andoncone`, `LSUIElement` true so it doesn't show in the Dock), and ad-hoc codesigns it. Output is written to `dist/Andon Cone.app`. Drag it to `/Applications` or run it in place.

## Run During Development

```sh
swift run
```

The app appears in the macOS menu bar with the `dot.radiowaves.left.and.right` SF Symbol. Clicking it opens a SwiftUI popover with a play/pause button, volume slider, station picker with artwork, current programming block, and tabs for upcoming blocks, top tracks, and recent station tweets. Keyboard shortcuts while the popover is open: <kbd>space</kbd> to play/pause, <kbd>⌘R</kbd> to refresh metadata, <kbd>⌘Q</kbd> to quit.
