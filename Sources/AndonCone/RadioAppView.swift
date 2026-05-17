import SwiftUI
import StoreKit
import AVKit

private enum DetailTab: String, CaseIterable, Identifiable {
    case schedule = "Schedule"
    case topTracks = "Top Tracks"
    case buzz = "Buzz"

    var id: String { rawValue }
}

struct RadioAppView: View {
    @EnvironmentObject private var model: PlayerModel
    @EnvironmentObject private var appChrome: AppChromeModel
    @StateObject private var tipStore = TipStore()
    @State private var selectedTab: DetailTab = .schedule
    @State private var selectedStationID: Station.ID? = PlayerModel.stations[0].id
    @State private var columnVisibility = NavigationSplitViewVisibility.automatic

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
    }

    private var tabPicker: some View {
        GlassSegmentedPicker(selection: $selectedTab)
    }

    private func collapseSidebarAfterSelection() {
        #if os(iOS)
        columnVisibility = .detailOnly
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
            }

            metadataFooter
        }
        .listStyle(.sidebar)
        .navigationTitle("Andon FM")
    }

    private var metadataFooter: some View {
        Group {
            if model.metadataIsStale || model.metadataErrorMessage != nil {
                VStack(alignment: .leading, spacing: 4) {
                    if model.metadataIsStale {
                        Label("Metadata stale", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }

                    if let error = model.metadataErrorMessage {
                        Text(error)
                            .lineLimit(2)
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption2)
            }
        }
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
    @Environment(\.colorScheme) private var colorScheme

    private var detail: AndonStationDetail? { model.currentDetail }
    private var track: AndonTrack? { model.currentTrack }

    var body: some View {
        let accent = model.currentStation.accentColor
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)

        HStack(alignment: .center, spacing: 24) {
            StationArtwork(url: detail?.imageURL, size: 190)
                .shadow(color: accent.opacity(colorScheme == .dark ? 0.28 : 0.18), radius: 18, y: 10)

            VStack(alignment: .leading, spacing: 10) {
                stationContext

                Divider()
                    .padding(.vertical, 4)

                Text(track?.displayTitle ?? "Loading now playing")
                    .font(.title.weight(.bold))
                    .lineLimit(2)

                Text(track?.displayArtist ?? "Waiting for metadata")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                metadataLine

                MacInlineTransportControls()
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(22)
        .background(accent.opacity(colorScheme == .dark ? 0.12 : 0.07), in: shape)
        .background(.regularMaterial, in: shape)
        .overlay(shape.stroke(accent.opacity(colorScheme == .dark ? 0.26 : 0.18), lineWidth: 1))
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

            if model.metadataIsStale {
                Label("Stale", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

private struct MacInlineTransportControls: View {
    @EnvironmentObject private var model: PlayerModel

    var body: some View {
        HStack(spacing: 12) {
            Button {
                model.togglePlayback()
            } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 38, height: 32)
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.space, modifiers: [])
            .help(model.isPlaying ? "Pause" : "Play")

            Button {
                model.reconnect()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.borderless)
            .disabled(!model.isPlaying)
            .help("Reconnect stream")

            HStack(spacing: 8) {
                Image(systemName: "speaker.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: Binding(
                    get: { Double(model.volume) },
                    set: { model.setVolume(Float($0)) }
                ), in: 0 ... 1)
                .frame(width: 130)
            }
            .padding(.leading, 2)
        }
        .controlSize(.small)
    }
}

#endif

private struct NowPlayingPanel: View {
    @EnvironmentObject private var model: PlayerModel
    @Environment(\.colorScheme) private var colorScheme

    private var detail: AndonStationDetail? { model.currentDetail }
    private var track: AndonTrack? { model.currentTrack }

    var body: some View {
        let accent = model.currentStation.accentColor
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)

        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 18) {
                StationArtwork(url: detail?.imageURL, size: 132)

                VStack(alignment: .leading, spacing: 10) {
                    stationContext

                    Text(trackStatusTitle)
                        .font(.title2.weight(.bold))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(trackStatusSubtitle)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    metadataLine
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            TransportControls()
        }
        .padding(18)
        .background(accent.opacity(colorScheme == .dark ? 0.14 : 0.08), in: shape)
        .background(.regularMaterial, in: shape)
        .overlay(shape.stroke(accent.opacity(colorScheme == .dark ? 0.28 : 0.18), lineWidth: 1))
        .shadow(color: accent.opacity(colorScheme == .dark ? 0.18 : 0.11), radius: 24, y: 14)
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

            if model.metadataIsStale {
                Label("Stale", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

private struct TransportControls: View {
    @EnvironmentObject private var model: PlayerModel

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Spacer(minLength: 0)
                Button {
                    model.togglePlayback()
                } label: {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 32, weight: .semibold))
                        .symbolRenderingMode(.monochrome)
                        .frame(width: 64, height: 64)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.space, modifiers: [])
                .foregroundStyle(.primary)
                .background(
                    Circle()
                        .fill(Color.primary.opacity(0.08))
                )
                .help(model.isPlaying ? "Pause" : "Play")
                Spacer(minLength: 0)
            }

            HStack(spacing: 14) {
                Button {
                    model.toggleMute()
                } label: {
                    Image(systemName: model.isMuted ? "speaker.slash.fill" : "speaker.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 34, height: 34)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(model.isMuted ? "Unmute" : "Mute")

                Slider(value: Binding(
                    get: { Double(model.volume) },
                    set: { model.setVolume(Float($0)) }
                ), in: 0 ... 1)
                .tint(model.currentStation.accentColor)

                AirPlayRoutePicker(player: model.routePickerPlayer)
                    .frame(width: 34, height: 34)
                    .help("Choose AirPlay output")
                    .accessibilityLabel("Choose AirPlay output")

            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .appGlass(in: Capsule(), interactive: true)
        }
    }
}

private struct AirPlayRoutePicker: View {
    let player: AVPlayer?

    var body: some View {
        PlatformRoutePicker(player: player)
            .frame(width: 34, height: 34)
    }
}

private struct StationTintBackdrop: View {
    let accent: Color
    let imageURL: URL?

    var body: some View {
        ZStack {
            AppSurface.primary

            GeometryReader { geometry in
                ZStack {
                    accent
                        .opacity(0.08)

                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case let .success(image):
                            image
                                .resizable()
                                .scaledToFill()
                                .blur(radius: 52)
                                .saturation(1.2)
                                .opacity(0.18)
                        default:
                            accent.opacity(0.05)
                        }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()

                    AppSurface.primary.opacity(0.72)
                }
            }
        }
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
                EmptyState(text: "No current block")
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
                EmptyState(text: "No top tracks yet")
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
                EmptyState(text: "No recent activity")
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
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                Text(blockProgressText(for: block))
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

private struct StationArtwork: View {
    let url: URL?
    let size: CGFloat

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    default:
                        placeholder
                    }
                }
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
            }
            .padding(22)
        }
        .frame(minWidth: 320, idealWidth: 420, maxWidth: 500)
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #endif
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

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 32, height: 32)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Close")
        }
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

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 24)
    }
}

private struct GlassSegmentedPicker: View {
    @EnvironmentObject private var model: PlayerModel
    @Binding var selection: DetailTab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(DetailTab.allCases) { tab in
                Button {
                    selection = tab
                } label: {
                    Text(tab.rawValue)
                        .font(.callout.weight(selection == tab ? .semibold : .regular))
                        .foregroundStyle(selection == tab ? .primary : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            selection == tab ? model.currentStation.accentColor.opacity(0.12) : Color.clear,
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .appGlass(in: Capsule(), interactive: true)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Details")
    }
}

private struct AppBackground: View {
    let url: URL?

    var body: some View {
        ZStack {
            AppSurface.primary

            AmbientArtworkBackdrop(url: url)
                .opacity(0.82)
        }
        .ignoresSafeArea()
    }
}

private struct AmbientArtworkBackdrop: View {
    let url: URL?

    var body: some View {
        GeometryReader { geometry in
            Group {
                if let url {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case let .success(image):
                            image
                                .resizable()
                                .scaledToFill()
                        default:
                            AppSurface.primary
                        }
                    }
                } else {
                    AppSurface.primary
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .blur(radius: 42)
            .saturation(1.35)
            .opacity(0.28)
            .overlay(AppSurface.primary.opacity(0.64))
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

    @ViewBuilder
    func appGlass<S: Shape>(
        in shape: S,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            let baseGlass = tint.map { Glass.regular.tint($0) } ?? Glass.regular
            self.glassEffect(baseGlass.interactive(interactive), in: shape)
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(Color.primary.opacity(0.11), lineWidth: 1))
                .shadow(color: Color.primary.opacity(0.05), radius: 12, y: 6)
        }
    }

    func glassIcon() -> some View {
        font(.system(size: 17, weight: .semibold))
            .frame(width: 44, height: 38)
            .contentShape(Capsule())
            .appGlass(in: Capsule(), interactive: true)
    }

    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
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

    static var secondary: Color {
        #if os(iOS)
        Color(.secondarySystemGroupedBackground)
        #elseif os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color(.secondarySystemBackground)
        #endif
    }
}

private extension Station {
    var accentColor: Color {
        switch id {
        case "aab4d149-92fa-4386-9c1e-d938ecb66ee3":
            return Color(red: 0.10, green: 0.72, blue: 0.68)
        case "6b53fc38-ed57-4738-80d6-f9fddf981054":
            return Color(red: 0.86, green: 0.36, blue: 0.16)
        case "df197c3e-0137-4665-95f3-0fc5cec1ee1e":
            return Color(red: 0.18, green: 0.56, blue: 0.94)
        case "887ec509-2be8-433e-a27e-d05c1dc21278":
            return Color(red: 0.78, green: 0.22, blue: 0.88)
        default:
            return .accentColor
        }
    }
}

private func relativeText(for date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .short
    return formatter.localizedString(for: date, relativeTo: Date())
}

private func blockProgressText(for block: AndonStationDetail.Block) -> String {
    let elapsed = Int(Date().timeIntervalSince(block.startedAt) / 60)
    let total = block.durationMinutes
    if elapsed < 0 {
        return "starts \(relativeText(for: block.startedAt))"
    }
    if elapsed >= total {
        return "\(total)m block ending"
    }
    return "\(elapsed)m / \(total)m"
}
