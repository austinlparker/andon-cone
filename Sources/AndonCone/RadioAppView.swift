import SwiftUI
import StoreKit
import AVKit
#if os(iOS)
import UIKit
#endif

private enum DetailTab: String, CaseIterable, Identifiable {
    case schedule = "Schedule"
    case topTracks = "Top Tracks"
    case buzz = "Buzz"

    var id: String { rawValue }
}

// Cached: re-creating a formatter on every SwiftUI render is wasteful and shows up in scrolling.
// nonisolated(unsafe) is required for Swift 6 since RelativeDateTimeFormatter isn't Sendable;
// the only use is `localizedString(for:relativeTo:)` which is read-only and thread-safe.
nonisolated(unsafe) private let relativeDateFormatter: RelativeDateTimeFormatter = {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .short
    return formatter
}()

private func relativeText(for date: Date) -> String {
    // RelativeDateTimeFormatter renders the very recent past as "in 0 sec." / "0 sec. ago",
    // which reads strangely right after a refresh. Treat anything under five seconds as "just now".
    let interval = abs(Date().timeIntervalSince(date))
    if interval < 5 { return "just now" }
    return relativeDateFormatter.localizedString(for: date, relativeTo: Date())
}

@MainActor
private func playHaptic() {
    #if os(iOS)
    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    #endif
}

struct RadioAppView: View {
    @EnvironmentObject private var model: PlayerModel
    @EnvironmentObject private var appChrome: AppChromeModel
    @EnvironmentObject private var artworkCache: ArtworkCache
    @EnvironmentObject private var metadata: MusicMetadataClient
    @EnvironmentObject private var library: MusicLibraryService
    @StateObject private var tipStore = TipStore()
    @State private var selectedTab: DetailTab = .schedule
    @State private var selectedStationID: Station.ID? = PlayerModel.stations[0].id
    @State private var columnVisibility = NavigationSplitViewVisibility.automatic
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            StationSourceList(
                selectedStationID: $selectedStationID,
                onSelectStation: collapseSidebarAfterSelection
            )
                .navigationSplitViewColumnWidth(min: 230, ideal: 276, max: 330)
        } detail: {
            StationDetailView(
                tabPicker: { tabPicker },
                tabContent: { tabContent }
            )
            .navigationTitle(model.currentStation.name)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        .navigationSplitViewStyle(.balanced)
        #if os(macOS)
        .frame(minWidth: 720, idealWidth: 980, minHeight: 520, idealHeight: 680)
        #endif
        .sheet(isPresented: $appChrome.isShowingAbout) {
            AboutView(store: tipStore)
        }
        .task {
            await tipStore.loadProducts()
        }
        .onChange(of: model.currentStation.id) { stationID in
            selectedStationID = stationID
        }
        .onChange(of: model.detailsByID) { details in
            // Prefetch every station's artwork as soon as we know the URLs so switching
            // stations becomes an instant memory-cache hit, no network round trip.
            for detail in details.values {
                if let url = detail.imageURL {
                    artworkCache.prefetch(url)
                }
            }
        }
        .onChange(of: model.tracksByID) { tracks in
            // Enrich every station's track in the background so a station switch shows
            // album art / metadata immediately. Lookups dedupe internally.
            for track in tracks.values {
                metadata.enrich(track)
            }
        }
        .onChange(of: metadata.version) { _ in
            // Whenever an enriched track lands, kick the artwork cache so the high-res
            // album art is hot by the time the view next reads it.
            for track in model.tracksByID.values {
                if let enriched = metadata.enriched(for: track), let url = enriched.artworkURL {
                    artworkCache.prefetch(url)
                }
            }
        }
        .alert("Apple Music", isPresented: Binding(
            get: { library.pendingMessage != nil },
            set: { if !$0 { library.dismissMessage() } }
        ), actions: {
            Button("OK", role: .cancel) { library.dismissMessage() }
        }, message: {
            Text(library.pendingMessage ?? "")
        })
        #if os(iOS)
        .onAppear {
            // Land on Now Playing in compact mode so the listener-facing surface is the first thing
            // a user sees. The navigation bar provides a sidebar toggle to reach the station list.
            if horizontalSizeClass == .compact {
                columnVisibility = .detailOnly
            }
        }
        #endif
    }

    private var tabPicker: some View {
        GlassSegmentedPicker(selection: $selectedTab)
    }

    private func collapseSidebarAfterSelection() {
        #if os(iOS)
        if horizontalSizeClass == .compact {
            columnVisibility = .detailOnly
        }
        #endif
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .schedule:
            SchedulePanel()
        case .topTracks:
            TopTracksPanel()
        case .buzz:
            BuzzPanel()
        }
    }
}

private struct StationDetailView<TabPicker: View, TabContent: View>: View {
    @EnvironmentObject private var model: PlayerModel
    let tabPicker: () -> TabPicker
    let tabContent: () -> TabContent

    var body: some View {
        let backdrop = StationTintBackdrop(
            accent: model.currentStation.accentColor,
            imageURL: model.currentDetail?.imageURL
        )

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                #if os(macOS)
                MacNowPlayingHero()
                #else
                NowPlayingPanel()
                #endif
                Divider()
                tabPicker()
                tabContent()
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(backdrop.ignoresSafeArea())
        #if os(iOS)
        .toolbarBackground(.hidden, for: .navigationBar)
        #endif
    }
}

private struct StationSourceList: View {
    @EnvironmentObject private var model: PlayerModel
    @EnvironmentObject private var appChrome: AppChromeModel
    @Environment(\.openURL) private var openURL
    @Binding var selectedStationID: Station.ID?
    let onSelectStation: () -> Void

    private var selection: Binding<Station.ID?> {
        Binding(
            get: { selectedStationID },
            set: { stationID in
                selectedStationID = stationID

                if let stationID, let station = model.station(id: stationID) {
                    model.selectStation(station)
                    onSelectStation()
                }
            }
        )
    }

    var body: some View {
        List(selection: selection) {
            Section("Library") {
                ForEach(PlayerModel.stations) { station in
                    NavigationLink(value: station.id) {
                        StationSourceRow(
                            station: station,
                            detail: model.detailsByID[station.id],
                            track: model.tracksByID[station.id]
                        )
                    }
                }
            }

            #if os(iOS)
            // macOS reaches About through the application menu, so we don't duplicate
            // it (or the radio page link) into the sidebar.
            Section("App") {
                Button {
                    appChrome.isShowingAbout = true
                } label: {
                    Label("About Andon Cone", systemImage: "info.circle")
                }

                Button {
                    openURL(PlayerModel.radioPageURL)
                } label: {
                    Label("Open Andon FM", systemImage: "safari")
                }

                #if DEBUG && os(iOS)
                Button(role: .destructive) {
                    fatalError("Intentional Embrace crash test")
                } label: {
                    Label("Crash Test", systemImage: "exclamationmark.triangle")
                }
                #endif
            }
            #endif
        }
        .listStyle(.sidebar)
        .navigationTitle("Andon FM")
    }
}

private struct StationSourceRow: View {
    let station: Station
    let detail: AndonStationDetail?
    let track: AndonTrack?

    var body: some View {
        HStack(spacing: 10) {
            StationArtwork(url: detail?.imageURL, size: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(station.name)
                    .font(.callout)
                    .lineLimit(1)
                Text(track?.displayTitle ?? station.host)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}

#if os(macOS)

private struct MacNowPlayingHero: View {
    @EnvironmentObject private var model: PlayerModel
    @EnvironmentObject private var metadata: MusicMetadataClient
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.openURL) private var openURL

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

                albumLine

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

    @ViewBuilder
    private var albumLine: some View {
        if let enriched {
            if let url = enriched.musicAppURL {
                Button {
                    openURL(url)
                } label: {
                    HStack(spacing: 4) {
                        Text(albumDisplayText(enriched))
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
                Text(albumDisplayText(enriched))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func albumDisplayText(_ enriched: EnrichedTrack) -> String {
        if let year = enriched.releaseYear {
            return "\(enriched.albumTitle) · \(year)"
        }
        return enriched.albumTitle
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
private struct MacInlineTransportControls: View {
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

private struct NowPlayingPanel: View {
    @EnvironmentObject private var model: PlayerModel
    @EnvironmentObject private var metadata: MusicMetadataClient
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.openURL) private var openURL

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

                    albumLine

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

    @ViewBuilder
    private var albumLine: some View {
        if let enriched {
            if let url = enriched.musicAppURL {
                Button {
                    openURL(url)
                } label: {
                    HStack(spacing: 4) {
                        Text(albumDisplayText(enriched))
                            .lineLimit(1)
                        Image(systemName: "arrow.up.right")
                            .font(.caption2.weight(.semibold))
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open \(enriched.albumTitle) in Apple Music")
            } else {
                Text(albumDisplayText(enriched))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func albumDisplayText(_ enriched: EnrichedTrack) -> String {
        if let year = enriched.releaseYear {
            return "\(enriched.albumTitle) · \(year)"
        }
        return enriched.albumTitle
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

private enum HeroElevation {
    case compact
    case lifted
}

private struct HeroCardBackground<S: Shape>: ViewModifier {
    let accent: Color
    let shape: S
    let reduceTransparency: Bool
    let colorScheme: ColorScheme
    let elevation: HeroElevation

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(AppSurface.elevated, in: shape)
                .overlay(shape.stroke(accent.opacity(0.5), lineWidth: 1.5))
                .shadow(color: accent.opacity(colorScheme == .dark ? 0.18 : 0.10),
                        radius: elevation == .lifted ? 18 : 12,
                        y: elevation == .lifted ? 10 : 6)
        } else {
            content
                .background(accent.opacity(colorScheme == .dark ? 0.14 : 0.08), in: shape)
                .background(.regularMaterial, in: shape)
                .overlay(shape.stroke(accent.opacity(colorScheme == .dark ? 0.28 : 0.18), lineWidth: 1))
                .shadow(color: accent.opacity(colorScheme == .dark ? 0.18 : 0.11),
                        radius: elevation == .lifted ? 24 : 18,
                        y: elevation == .lifted ? 14 : 10)
        }
    }
}

private struct TransportControls: View {
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

private struct StationTintBackdrop: View {
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
private struct PlatformRoutePicker: UIViewRepresentable {
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
private struct PlatformRoutePicker: NSViewRepresentable {
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

private struct SchedulePanel: View {
    @EnvironmentObject private var model: PlayerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let block = model.currentDetail?.currentBlock {
                BlockRow(title: "On now", block: block)
            } else {
                EmptyState(text: "No current block", systemImage: "calendar")
            }

            let upcoming = model.currentDetail?.upcomingBlocks ?? []
            if !upcoming.isEmpty {
                Divider()
                ForEach(upcoming.prefix(4)) { block in
                    BlockRow(title: "Up next", block: block)
                }
            }
        }
        .panelStyle()
    }
}

private struct TopTracksPanel: View {
    @EnvironmentObject private var model: PlayerModel

    var body: some View {
        let songs = model.currentDetail?.contentStats?.topSongsWeek ?? []
        VStack(alignment: .leading, spacing: 10) {
            if songs.isEmpty {
                EmptyState(text: "No top tracks yet", systemImage: "music.note.list")
            } else {
                ForEach(Array(songs.prefix(8).enumerated()), id: \.element.id) { index, song in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(index + 1)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.tertiary)
                            .frame(width: 22, alignment: .trailing)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(song.name)
                                .font(.callout.weight(.semibold))
                                .lineLimit(1)
                            Text(song.artist)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Text("\(song.count)x")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .panelStyle()
    }
}

private struct BuzzPanel: View {
    @EnvironmentObject private var model: PlayerModel
    @Environment(\.openURL) private var openURL

    var body: some View {
        let tweets = model.currentDetail?.tweets ?? []
        VStack(alignment: .leading, spacing: 10) {
            if tweets.isEmpty {
                EmptyState(text: "No recent activity", systemImage: "bubble.left.and.bubble.right")
            } else {
                ForEach(tweets.prefix(5)) { tweet in
                    Button {
                        if let url = tweet.tweetURL {
                            openURL(url)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 5) {
                                if tweet.isOwnTweet == true {
                                    Image(systemName: "checkmark.seal.fill")
                                        .foregroundStyle(.tint)
                                }
                                Text("@\(tweet.author.username)")
                                    .font(.caption.weight(.semibold))
                                Text(relativeText(for: tweet.postedAt))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Text(tweet.content)
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .lineLimit(4)
                                .multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        // Plain tinted fill rather than .thinMaterial — the surrounding panel is
                        // already material, and material-on-material reads flat.
                        .background(Color.primary.opacity(0.04),
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .panelStyle()
    }
}

private struct BlockRow: View {
    let title: String
    let block: AndonStationDetail.Block

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(title, systemImage: "waveform.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(block.progressText())
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Text(block.name)
                .font(.headline)
                .lineLimit(1)

            if let description = block.description, !description.isEmpty {
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
    }
}

private struct LibraryButton: View {
    @EnvironmentObject private var library: MusicLibraryService
    let trackID: String

    var body: some View {
        let status = library.status(for: trackID)

        Button {
            switch status {
            case .inLibrary, .adding, .checking:
                break
            default:
                library.addToLibrary(trackID: trackID)
            }
        } label: {
            iconView(for: status)
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(status == .adding || status == .checking)
        .help(helpText(for: status))
        .accessibilityLabel(accessibilityLabel(for: status))
        .task(id: trackID) {
            library.refreshStatus(for: trackID)
        }
    }

    private func iconView(for status: MusicLibraryService.LibraryStatus) -> some View {
        // ZStack with a Color.clear anchor keeps the icon's intrinsic size stable across
        // case swaps so flipping from the plus symbol to ProgressView doesn't resize the row.
        ZStack {
            Color.clear.frame(width: 22, height: 22)

            switch status {
            case .inLibrary:
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.tint)
            case .adding, .checking:
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.small)
            default:
                Image(systemName: "plus.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func helpText(for status: MusicLibraryService.LibraryStatus) -> String {
        switch status {
        case .inLibrary: return "In your library"
        case .adding: return "Adding…"
        case .checking: return "Checking library…"
        case .notAuthorized: return "Tap to enable Apple Music access"
        case .noSubscription: return "Requires an Apple Music subscription"
        case .unavailable: return "Apple Music unavailable"
        case .error(let msg): return msg
        default: return "Add to your Apple Music library"
        }
    }

    private func accessibilityLabel(for status: MusicLibraryService.LibraryStatus) -> String {
        switch status {
        case .inLibrary: return "In your Apple Music library"
        case .adding: return "Adding to library"
        case .checking: return "Checking library"
        default: return "Add to Apple Music library"
        }
    }
}

private struct StationArtwork: View {
    @EnvironmentObject private var cache: ArtworkCache
    let url: URL?
    /// Shown while `url` is still loading on first appearance — typically the station
    /// logo when `url` is an album-art URL. Prevents a placeholder flash during the
    /// brief window between metadata enrichment and the artwork bytes arriving.
    var fallbackURL: URL? = nil
    let size: CGFloat

    private var displayedImage: PlatformImage? {
        if let url, let image = cache.image(for: url) { return image }
        if let fallbackURL, let image = cache.image(for: fallbackURL) { return image }
        return nil
    }

    var body: some View {
        Group {
            if let image = displayedImage {
                cachedImage(image)
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: max(8, size * 0.12), style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: max(8, size * 0.12), style: .continuous)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .task(id: url) {
            // Trigger fetch on miss. The cache dedupes, so re-asking is cheap.
            if let url { cache.prefetch(url) }
        }
        .task(id: fallbackURL) {
            if let fallbackURL { cache.prefetch(fallbackURL) }
        }
        .animation(.easeInOut(duration: 0.25), value: displayedImage != nil)
    }

    @ViewBuilder
    private func cachedImage(_ image: PlatformImage) -> some View {
        #if canImport(UIKit)
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
        #elseif canImport(AppKit)
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
        #endif
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.18))
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: size * 0.38))
                .foregroundStyle(.secondary)
        }
    }
}

private struct AboutView: View {
    @ObservedObject var store: TipStore
    @Environment(\.dismiss) private var dismiss

    private let blogURL = URL(string: "https://andonlabs.com/blog/andon-fm")!

    var body: some View {
        #if os(iOS)
        NavigationStack {
            content
                .navigationTitle("About")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #else
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding([.horizontal, .top], 16)
            content
        }
        .frame(minWidth: 360, idealWidth: 440, maxWidth: 520, minHeight: 460)
        #endif
    }

    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header

                VStack(alignment: .leading, spacing: 10) {
                    Text("About")
                        .font(.headline)

                    Text("Andon Cone is a native player for the andon.fm live streams, an experiment run by Andon Labs to have LLMs manage a radio station.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Link(destination: blogURL) {
                        Label("Read about Andon FM", systemImage: "safari")
                    }
                    .font(.callout)
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("About Me")
                        .font(.headline)

                    (
                        Text("I'm ")
                        + Text("[@aparker.io](https://bsky.app/profile/aparker.io)")
                        + Text(", a developer and tinkerer. This application is free, but if you enjoyed it, feel free to leave a tip.")
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .tint(.accentColor)
                    .fixedSize(horizontal: false, vertical: true)

                    TipMenu(store: store)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("What does the name mean?")
                        .font(.headline)

                    Text("It is a little bit of wordplay: Andon Labs, light cones, and the fact that a speaker is, physically enough, a cone.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let message = store.message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                versionFooter
            }
            .padding(22)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 46, height: 46)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text("Andon Cone")
                    .font(.title2.weight(.bold))
                Text("Native radio for Andon FM")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private var versionFooter: some View {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return Text("Version \(version) (\(build))")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TipMenu: View {
    @ObservedObject var store: TipStore

    var body: some View {
        Group {
            if store.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if store.products.isEmpty {
                Text("Tips are not available yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Menu {
                    ForEach(store.products) { product in
                        Button {
                            Task {
                                await store.purchase(product)
                            }
                        } label: {
                            Text("\(product.displayName) - \(product.displayPrice)")
                        }
                    }
                } label: {
                    Label("Leave a Tip", systemImage: "heart.fill")
                        .font(.callout.weight(.semibold))
                }
                .disabled(store.purchaseInProgressProductID != nil)
            }
        }
    }
}

private struct EmptyState: View {
    let text: String
    let systemImage: String

    var body: some View {
        if #available(iOS 17.0, macOS 14.0, *) {
            ContentUnavailableView(text, systemImage: systemImage)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        } else {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text(text)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 24)
        }
    }
}

private struct GlassSegmentedPicker: View {
    @EnvironmentObject private var model: PlayerModel
    @Binding var selection: DetailTab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(DetailTab.allCases) { tab in
                tabButton(for: tab)
            }
        }
        .padding(5)
        .appGlass(in: Capsule(), interactive: true)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Details")
    }

    private func tabButton(for tab: DetailTab) -> some View {
        Button {
            selection = tab
        } label: {
            Text(tab.rawValue)
                .font(.callout.weight(selection == tab ? .semibold : .regular))
                .foregroundStyle(selection == tab ? .primary : .secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    Capsule().fill(
                        selection == tab
                            ? model.currentStation.accentColor.opacity(0.22)
                            : Color.clear
                    )
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection == tab ? .isSelected : [])
    }
}

private struct AppGlassModifier<S: Shape>: ViewModifier {
    let shape: S
    let tint: Color?
    let interactive: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(AppSurface.elevated, in: shape)
                .overlay(shape.stroke(Color.primary.opacity(0.18), lineWidth: 1))
        } else if #available(iOS 26.0, macOS 26.0, *) {
            let baseGlass = tint.map { Glass.regular.tint($0) } ?? Glass.regular
            content.glassEffect(baseGlass.interactive(interactive), in: shape)
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(Color.primary.opacity(0.11), lineWidth: 1))
                .shadow(color: Color.primary.opacity(0.05), radius: 12, y: 6)
        }
    }
}

private extension View {
    func panelStyle() -> some View {
        padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }

    func appGlass<S: Shape>(
        in shape: S,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        modifier(AppGlassModifier(shape: shape, tint: tint, interactive: interactive))
    }
}

private enum AppSurface {
    static var primary: Color {
        #if os(iOS)
        Color(.systemGroupedBackground)
        #elseif os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(.systemBackground)
        #endif
    }

    /// Solid surface used when Reduce Transparency is on.
    static var elevated: Color {
        #if os(iOS)
        Color(.secondarySystemGroupedBackground)
        #elseif os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color(.secondarySystemBackground)
        #endif
    }
}
