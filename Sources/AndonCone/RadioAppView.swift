import SwiftUI

private enum DetailTab: String, CaseIterable, Identifiable {
    case schedule = "Schedule"
    case topTracks = "Top Tracks"
    case buzz = "Buzz"

    var id: String { rawValue }
}

struct RadioAppView: View {
    @EnvironmentObject private var model: PlayerModel
    @State private var selectedTab: DetailTab = .schedule
    @Environment(\.openURL) private var openURL

    var body: some View {
        #if os(macOS)
        macOSRoot
        #else
        GeometryReader { geometry in
            Group {
                if geometry.size.width >= 760 {
                    wideLayout
                } else {
                    compactLayout
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppBackground(url: model.currentDetail?.imageURL))
        }
        .navigationTitle("Andon FM")
        #endif
    }

    #if os(macOS)
    private var macOSRoot: some View {
        macOSLayout
            .frame(minWidth: 720, idealWidth: 980, minHeight: 520, idealHeight: 680)
    }

    private var macOSLayout: some View {
        NavigationSplitView {
            MacStationSourceList()
                .navigationSplitViewColumnWidth(min: 230, ideal: 260, max: 320)
        } detail: {
            MacStationDetail(
                tabPicker: { tabPicker },
                tabContent: { tabContent }
            )
            .navigationTitle(model.currentStation.name)
        }
        .navigationSplitViewStyle(.balanced)
    }
    #endif

    private var wideLayout: some View {
        HStack(spacing: 0) {
            StationSidebar()
                .frame(width: 316)
                .padding(18)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    NowPlayingPanel()
                    tabPicker
                    tabContent
                }
                .padding(24)
                .frame(maxWidth: 760, alignment: .leading)
            }
        }
    }

    private var compactLayout: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                StationRail()
                NowPlayingPanel()
                tabPicker
                tabContent
            }
            .padding(18)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Andon FM")
                    .font(.largeTitle.weight(.black))
            }

            Spacer()

            Button {
                openURL(PlayerModel.radioPageURL)
            } label: {
                Image(systemName: "safari")
                    .glassIcon()
            }
            .buttonStyle(.plain)
            .help("Open Andon FM")
        }
    }

    private var tabPicker: some View {
        GlassSegmentedPicker(selection: $selectedTab)
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

#if os(macOS)
private struct MacStationDetail<TabPicker: View, TabContent: View>: View {
    @EnvironmentObject private var model: PlayerModel
    let tabPicker: () -> TabPicker
    let tabContent: () -> TabContent

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                MacNowPlayingHero()
                Divider()
                tabPicker()
                tabContent()
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.background)
    }
}

private struct MacStationSourceList: View {
    @EnvironmentObject private var model: PlayerModel

    private var selection: Binding<Station?> {
        Binding(
            get: { model.currentStation },
            set: { station in
                if let station {
                    model.selectStation(station)
                }
            }
        )
    }

    var body: some View {
        List(selection: selection) {
            Section("Library") {
                ForEach(PlayerModel.stations) { station in
                    MacStationRow(
                        station: station,
                        detail: model.detailsByID[station.id],
                        track: model.tracksByID[station.id]
                    )
                    .tag(station)
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

private struct MacStationRow: View {
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

private struct MacNowPlayingHero: View {
    @EnvironmentObject private var model: PlayerModel

    private var detail: AndonStationDetail? { model.currentDetail }
    private var track: AndonTrack? { model.currentTrack }

    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            StationArtwork(url: detail?.imageURL, size: 190)
                .shadow(color: Color.primary.opacity(0.14), radius: 16, y: 8)

            VStack(alignment: .leading, spacing: 10) {
                Text(model.currentStation.name)
                    .font(.title.weight(.bold))
                    .lineLimit(1)

                Text(model.currentStation.host)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Divider()
                    .padding(.vertical, 4)

                Text(track?.displayTitle ?? "Loading now playing")
                    .font(.title2.weight(.semibold))
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
        .padding(.top, 8)
        .padding(.bottom, 4)
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

private struct StationSidebar: View {
    @EnvironmentObject private var model: PlayerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Stations")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(spacing: 8) {
                ForEach(PlayerModel.stations) { station in
                    StationCard(
                        station: station,
                        detail: model.detailsByID[station.id],
                        track: model.tracksByID[station.id],
                        isSelected: station == model.currentStation,
                        layout: .sidebar
                    )
                }
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .appGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous), interactive: true)
    }
}

private struct StationRail: View {
    @EnvironmentObject private var model: PlayerModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(PlayerModel.stations) { station in
                    StationCard(
                        station: station,
                        detail: model.detailsByID[station.id],
                        track: model.tracksByID[station.id],
                        isSelected: station == model.currentStation,
                        layout: .rail
                    )
                    .frame(width: 230)
                }
            }
            .padding(.vertical, 2)
        }
    }
}

private enum StationCardLayout {
    case sidebar
    case rail
}

private struct StationCard: View {
    @EnvironmentObject private var model: PlayerModel
    let station: Station
    let detail: AndonStationDetail?
    let track: AndonTrack?
    let isSelected: Bool
    let layout: StationCardLayout

    var body: some View {
        Button {
            model.selectStation(station)
        } label: {
            cardContent
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var cardContent: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

        HStack(spacing: 10) {
            StationArtwork(url: detail?.imageURL, size: layout == .sidebar ? 44 : 40)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(station.name)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.tint)
                    }
                }

                Text(track?.displayTitle ?? station.host)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let listeners = detail?.stats?.currentListeners {
                    Label("\(listeners)", systemImage: "person.2.fill")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .labelStyle(.titleAndIcon)
                        .monospacedDigit()
                }
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.primary.opacity(layout == .rail ? 0.025 : 0.04), in: shape)
        .overlay(
            shape.stroke(isSelected ? Color.accentColor.opacity(0.48) : Color.primary.opacity(0.08), lineWidth: 1)
        )
        .if(layout == .rail) { view in
            view.appGlass(in: shape, interactive: true)
        }
    }
}

private struct NowPlayingPanel: View {
    @EnvironmentObject private var model: PlayerModel

    private var detail: AndonStationDetail? { model.currentDetail }
    private var track: AndonTrack? { model.currentTrack }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 18) {
                StationArtwork(url: detail?.imageURL, size: 132)

                VStack(alignment: .leading, spacing: 8) {
                    Text(model.currentStation.name)
                        .font(.title2.weight(.bold))
                        .lineLimit(2)

                    Text(model.currentStation.host)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Divider()
                        .padding(.vertical, 4)

                    Text(trackStatusTitle)
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)

                    Text(trackStatusSubtitle)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    metadataLine
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            TransportControls()
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.primary.opacity(0.09), lineWidth: 1)
        )
        .shadow(color: Color.primary.opacity(0.08), radius: 22, y: 12)
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
            HStack(spacing: 22) {
                Spacer()

                Button {
                    model.reconnect()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .glassIcon()
                }
                .disabled(!model.isPlaying)
                .help("Reconnect stream")

                Button {
                    model.togglePlayback()
                } label: {
                    Image(systemName: model.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 34, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .frame(width: 70, height: 70)
                        .appGlass(
                            in: Circle(),
                            tint: model.isPlaying ? Color.accentColor.opacity(0.22) : nil,
                            interactive: true
                        )
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.space, modifiers: [])
                .help(model.isPlaying ? "Pause" : "Play")

                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(8)
            .appGlass(in: Capsule(), interactive: true)

            #if os(macOS)
            HStack(spacing: 10) {
                Image(systemName: "speaker.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: Binding(
                    get: { Double(model.volume) },
                    set: { model.setVolume(Float($0)) }
                ), in: 0 ... 1)
                Image(systemName: "speaker.wave.3.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .appGlass(in: Capsule(), interactive: true)
            #endif
        }
    }
}

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
                            selection == tab ? Color.primary.opacity(0.08) : Color.clear,
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
