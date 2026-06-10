# Privacy Policy

Effective date: June 10, 2026

Andon Cone is a native iOS, iPadOS, and macOS app for listening to Andon FM radio streams.

## Summary

Andon Cone does not require an account, does not sell personal information, and does not use personal information for advertising. The app connects to radio, metadata, artwork, Apple Music, and diagnostics services to provide playback, now-playing details, optional library actions, and reliability information.

## Information the App Handles

### Radio Streaming and Station Metadata

When you play a station, Andon Cone streams audio from Live365-hosted stream URLs. The app also requests public station metadata and listening statistics from Andon Labs services so it can show the current track, station artwork, listener counts, programming blocks, and upcoming schedule.

These network requests may expose standard technical information to those services, such as your IP address, device user agent, request time, and the requested stream or endpoint. Andon Cone does not add an account identifier to these requests.

### Track Enrichment and Artwork

Andon Cone may query Apple's iTunes Search API to enrich track information and artwork. These requests are based on the track title and artist currently playing on the station. Results are cached locally on your device to reduce repeat lookups.

Artwork may also be loaded from URLs provided by Andon Labs metadata or Apple search results. Standard technical information may be visible to the services hosting those assets.

### Apple Music

On iOS and iPadOS, Andon Cone offers an optional Apple Music add-to-library feature. If you use it, the app may ask for Apple Music permission through Apple's system prompt, check whether a track is already in your library, and add the track through MusicKit.

Apple Music access is optional. Playback, station metadata, schedules, and artwork do not require Apple Music permission, an Apple Music subscription, or Apple Music sign-in. Andon Cone does not send your Apple Music library status to Andon Labs or to the app developer's own servers.

On macOS, Andon Cone does not add tracks directly to your Apple Music library. It may show Apple Music links when available.

### Local Caches

Andon Cone stores artwork and enriched track metadata in the app's local cache directory on your device. These caches help the app load faster and reduce network traffic. Cache contents are not uploaded by Andon Cone and may be removed by the operating system or by deleting the app's local data.

### Crash Diagnostics

The iOS and iPadOS app includes Embrace crash diagnostics to help identify crashes and reliability problems. Diagnostic data may include crash reports, stack traces, app version, operating system version, device model, session timing, performance information, and network diagnostics needed to troubleshoot app behavior.

Crash diagnostics are used to improve app stability and are not used for advertising.

## Information Sharing

Andon Cone shares information only as needed to operate the app and its services:

- Live365 receives stream requests when you play radio audio.
- Andon Labs receives metadata and station statistics requests.
- Apple receives iTunes Search API, Apple Music, App Store, and TestFlight requests as applicable.
- Embrace receives iOS and iPadOS diagnostic information when crash reporting is active.

Andon Cone does not sell personal information.

## Children

Andon Cone is not directed to children, and the app does not knowingly collect personal information from children.

## Changes

This policy may be updated as the app changes. Material changes will be reflected in this file with a new effective date.

## Contact

For privacy questions, open an issue in this GitHub repository or contact the repository owner through GitHub.
