import SwiftUI
import AVKit
#if os(iOS)
import UIKit
#endif

/// The album line under the title in both heroes. When the enriched track has an
/// Apple Music URL, the line becomes a tappable button with a chevron; otherwise
/// it's plain secondary text. Returns an EmptyView when there's no enrichment yet.
struct AlbumLinkView: View {
    let enriched: EnrichedTrack?
    @Environment(\.openURL) private var openURL

    var body: some View {
        if let enriched {
            if let url = enriched.musicAppURL {
                Button {
                    openURL(url)
                } label: {
                    HStack(spacing: 4) {
                        Text(enriched.albumDisplayText)
                            .lineLimit(1)
                        Image(systemName: "arrow.up.right")
                            .font(.caption2.weight(.semibold))
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open in Apple Music")
                .accessibilityLabel("Open \(enriched.albumTitle) in Apple Music")
            } else {
                Text(enriched.albumDisplayText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

#if os(macOS)

struct MacNowPlayingHero: View {
    @EnvironmentObject private var model: PlayerModel
    @EnvironmentObject private var metadata: MusicMetadataClient
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var detail: AndonStationDetail? { model.currentDetail }
    private var track: AndonTrack? { model.currentTrack }
    private var enriched: EnrichedTrack? { track.flatMap { metadata.enriched(for: $0) } }

    var body: some View {
        let accent = model.currentStation.accentColor
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)

        HStack(alignment: .center, spacing: 24) {
            StationArtwork(
                url: enriched?.artworkURL ?? detail?.imageURL,
                fallbackURL: enriched != nil ? detail?.imageURL : nil,
                size: 190
            )
            .shadow(color: accent.opacity(colorScheme == .dark ? 0.28 : 0.18), radius: 18, y: 10)
            .accessibilityLabel(enriched?.albumTitle ?? model.currentStation.name)

            VStack(alignment: .leading, spacing: 10) {
                stationContext

                Divider()
                    .padding(.vertical, 4)

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(track?.displayTitle ?? "Loading now playing")
                        .font(.title.weight(.bold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    // LibraryButton intentionally omitted on macOS — Apple's MusicLibrary.add
                    // API isn't available there. Album line below carries the Apple Music link.
                }

                Text(track?.displayArtist ?? "Waiting for metadata")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                AlbumLinkView(enriched: enriched)

                metadataLine

                MacInlineTransportControls()
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(22)
        .modifier(HeroCardBackground(accent: accent,
                                     shape: shape,
                                     reduceTransparency: reduceTransparency,
                                     colorScheme: colorScheme,
                                     elevation: .compact))
    }

    private var stationContext: some View {
        HStack(spacing: 8) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(model.currentStation.accentColor)

            Text(model.currentStation.host)
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var metadataLine: some View {
        HStack(spacing: 10) {
            if let listeners = detail?.stats?.currentListeners {
                Label("\(listeners)", systemImage: "person.2.fill")
                    .monospacedDigit()
            }

            // Only surface metadata problems once they've persisted long enough to be
            // stale — a single transient fetch failure shouldn't show chrome.
            if model.metadataIsStale, let error = model.metadataErrorMessage {
                Label("Metadata offline", systemImage: "wifi.exclamationmark")
                    .foregroundStyle(.orange)
                    .help(error)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

/// Mac transport mirrors the iOS pill: prominent circular play button on the left,
/// secondary actions (reconnect, mute) and the volume slider sharing one glass capsule.
struct MacInlineTransportControls: View {
    @EnvironmentObject private var model: PlayerModel

    var body: some View {
        HStack(spacing: 8) {
            playButton

            if model.isPlaying {
                reconnectButton
            }

            muteButton

            Slider(value: Binding(
                get: { Double(model.volume) },
                set: { model.setVolume(Float($0)) }
            ), in: 0 ... 1)
            .tint(model.currentStation.accentColor)
            .controlSize(.small)
            // Explicit width — `maxWidth` collapses to the slider's tiny intrinsic size
            // once the surrounding pill becomes fixedSize.
            .frame(width: 180)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .appGlass(in: Capsule(), interactive: true)
        .fixedSize(horizontal: true, vertical: true)
    }

    private var playButton: some View {
        Button {
            model.togglePlayback()
        } label: {
            ZStack {
                Circle().fill(Color.primary.opacity(0.08))
                if model.isBuffering {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.mini)
                } else {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.primary)
                }
            }
            .frame(width: 28, height: 28)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        // Space-as-menu-shortcut is unreliable on macOS (the menu bar competes with focused
        // controls). Attaching it to a button in the active window is the dependable form.
        .keyboardShortcut(.space, modifiers: [])
        .help(model.isPlaying ? "Pause (Space)" : "Play (Space)")
        .accessibilityLabel(model.isBuffering ? "Buffering" : (model.isPlaying ? "Pause" : "Play"))
    }

    private var reconnectButton: some View {
        Button {
            model.reconnect()
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Reconnect stream (⌘R)")
    }

    private var muteButton: some View {
        Button {
            model.toggleMute()
        } label: {
            Image(systemName: model.isMuted ? "speaker.slash.fill" : "speaker.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(model.isMuted ? "Unmute (⌘M)" : "Mute (⌘M)")
    }
}

#endif

struct NowPlayingPanel: View {
    @EnvironmentObject private var model: PlayerModel
    @EnvironmentObject private var metadata: MusicMetadataClient
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var detail: AndonStationDetail? { model.currentDetail }
    private var track: AndonTrack? { model.currentTrack }
    private var enriched: EnrichedTrack? { track.flatMap { metadata.enriched(for: $0) } }

    var body: some View {
        let accent = model.currentStation.accentColor
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)

        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 18) {
                // Album art wins over station logo whenever iTunes Search returned a match.
                // Station logo doubles as the fallback during the brief window before
                // album bytes land, so we never flash a placeholder mid-transition.
                StationArtwork(
                    url: enriched?.artworkURL ?? detail?.imageURL,
                    fallbackURL: enriched != nil ? detail?.imageURL : nil,
                    size: 132
                )
                .accessibilityLabel(enriched?.albumTitle ?? model.currentStation.name)

                VStack(alignment: .leading, spacing: 10) {
                    stationContext

                    titleRow

                    Text(trackStatusSubtitle)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)

                    AlbumLinkView(enriched: enriched)

                    metadataLine
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            TransportControls()
        }
        .padding(18)
        .modifier(HeroCardBackground(accent: accent,
                                     shape: shape,
                                     reduceTransparency: reduceTransparency,
                                     colorScheme: colorScheme,
                                     elevation: .lifted))
    }

    private var titleRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(trackStatusTitle)
                .font(.title2.weight(.bold))
                .lineLimit(3)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)

            #if os(iOS)
            // macOS surfaces the same affordance through the Apple Music URL on the album line —
            // MusicLibrary.add() is iOS-only at the API level.
            if let trackID = enriched?.trackID {
                LibraryButton(trackID: trackID)
                    .padding(.top, 3)
            }
            #endif
        }
    }

    private var stationContext: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(model.currentStation.accentColor)

            Text(model.currentStation.host)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var trackStatusTitle: String {
        if track?.online == false {
            return "Station offline"
        }
        return track?.displayTitle ?? "Loading now playing"
    }

    private var trackStatusSubtitle: String {
        if let error = track?.error, !error.isEmpty {
            return error
        }
        return track?.displayArtist ?? "Waiting for metadata"
    }

    private var metadataLine: some View {
        HStack(spacing: 8) {
            if let listeners = detail?.stats?.currentListeners {
                Label("\(listeners)", systemImage: "person.2.fill")
                    .labelStyle(.titleAndIcon)
                    .monospacedDigit()
            }

            // Stays hidden until a real connection problem has persisted past the
            // staleness threshold; transient blips don't show chrome.
            if model.metadataIsStale, let error = model.metadataErrorMessage {
                Label("Metadata offline", systemImage: "wifi.exclamationmark")
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Metadata offline: \(error)")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

struct TransportControls: View {
    @EnvironmentObject private var model: PlayerModel

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Spacer(minLength: 0)
                playButton
                Spacer(minLength: 0)
            }

            HStack(spacing: 14) {
                muteButton

                Slider(value: Binding(
                    get: { Double(model.volume) },
                    set: { model.setVolume(Float($0)) }
                ), in: 0 ... 1)
                .tint(model.currentStation.accentColor)

                routePicker
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .appGlass(in: Capsule(), interactive: true)
        }
    }

    private var playButton: some View {
        Button {
            playHaptic()
            model.togglePlayback()
        } label: {
            ZStack {
                Circle()
                    .fill(Color.primary.opacity(0.08))
                if model.isBuffering {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.large)
                } else {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 32, weight: .semibold))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(.primary)
                }
            }
            .frame(width: 64, height: 64)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.space, modifiers: [])
        .help(playButtonHelp)
        .accessibilityLabel(playButtonAccessibilityLabel)
    }

    private var playButtonHelp: String {
        if model.isBuffering { return "Buffering" }
        return model.isPlaying ? "Pause" : "Play"
    }

    private var playButtonAccessibilityLabel: String {
        if model.isBuffering { return "Buffering" }
        return model.isPlaying ? "Pause" : "Play"
    }

    private var muteButton: some View {
        Button {
            model.toggleMute()
        } label: {
            // 44pt frame meets the iOS HIG touch-target floor without enlarging the glyph.
            Image(systemName: model.isMuted ? "speaker.slash.fill" : "speaker.fill")
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(model.isMuted ? "Unmute" : "Mute")
        .accessibilityLabel(model.isMuted ? "Unmute" : "Mute")
    }

    private var routePicker: some View {
        PlatformRoutePicker(player: model.routePickerPlayer)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .help("Choose AirPlay output")
            .accessibilityLabel("Choose AirPlay output")
    }
}

struct StationTintBackdrop: View {
    @EnvironmentObject private var cache: ArtworkCache
    let accent: Color
    let imageURL: URL?
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            AppSurface.primary

            if !reduceTransparency {
                GeometryReader { geometry in
                    ZStack {
                        accent.opacity(0.08)

                        if let imageURL, let img = cache.image(for: imageURL) {
                            backdropImage(img)
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .clipped()
                        } else {
                            accent.opacity(0.05)
                        }

                        AppSurface.primary.opacity(0.72)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func backdropImage(_ image: PlatformImage) -> some View {
        #if canImport(UIKit)
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .blur(radius: 52)
            .saturation(1.2)
            .opacity(0.18)
        #elseif canImport(AppKit)
        Image(nsImage: image)
            .resizable()
            .scaledToFill()
            .blur(radius: 52)
            .saturation(1.2)
            .opacity(0.18)
        #endif
    }
}

#if os(iOS)
struct PlatformRoutePicker: UIViewRepresentable {
    let player: AVPlayer?

    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.backgroundColor = .clear
        view.tintColor = .secondaryLabel
        view.activeTintColor = .tintColor
        view.prioritizesVideoDevices = false
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        uiView.tintColor = .secondaryLabel
        uiView.activeTintColor = .tintColor
    }
}
#elseif os(macOS)
struct PlatformRoutePicker: NSViewRepresentable {
    let player: AVPlayer?

    func makeNSView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.isRoutePickerButtonBordered = false
        view.setRoutePickerButtonColor(.secondaryLabelColor, for: .normal)
        view.setRoutePickerButtonColor(.controlAccentColor, for: .active)
        view.player = player
        return view
    }

    func updateNSView(_ nsView: AVRoutePickerView, context: Context) {
        nsView.player = player
        nsView.setRoutePickerButtonColor(.secondaryLabelColor, for: .normal)
        nsView.setRoutePickerButtonColor(.controlAccentColor, for: .active)
    }
}
#endif
