import AppKit
import SwiftUI

private enum DetailTab: String, CaseIterable, Identifiable {
    case stations = "Stations"
    case upNext = "Up Next"
    case topTracks = "Top Tracks"
    case buzz = "Buzz"

    var id: String { rawValue }
}

struct MenuContentView: View {
    @ObservedObject var model: PlayerModel
    @State private var selectedTab: DetailTab = .stations

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            nowPlaying
            Divider()
            transport
            if currentDetail?.currentBlock != nil {
                Divider()
                currentBlockSection
            }
            Divider()
            Picker("", selection: $selectedTab) {
                ForEach(DetailTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            tabContent
                .frame(maxWidth: .infinity, alignment: .leading)
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 340)
    }

    private var currentDetail: AndonStationDetail? {
        model.detailsByID[model.currentStation.id]
    }

    private var currentTrack: AndonTrack? {
        model.tracksByID[model.currentStation.id]
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            StationArtwork(url: currentDetail?.imageURL, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.currentStation.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(model.currentStation.host)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let badge = aiBadge {
                    Text(badge)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
    }

    private var aiBadge: String? {
        guard let detail = currentDetail else { return nil }
        let parts = [detail.ttsProvider, detail.ttsModel].compactMap { $0 }
        guard !parts.isEmpty else { return nil }
        return "TTS · \(parts.joined(separator: " "))"
    }

    private var nowPlaying: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let track = currentTrack, track.online == false {
                Text("Station offline")
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else if let track = currentTrack {
                Text(track.displayTitle)
                    .font(.body)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(track.displayArtist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else {
                Text("Loading…")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                if let listeners = currentDetail?.stats?.currentListeners {
                    Label("\(listeners)", systemImage: "person.2.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .labelStyle(.titleAndIcon)
                        .help("\(listeners) current listeners")
                }
                if let total = currentDetail?.stats?.totalListeners {
                    Text("· \(total) all-time")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                if let refreshed = model.lastMetadataRefresh {
                    HStack(spacing: 3) {
                        if model.metadataIsStale {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                                .help("Metadata refresh failed; values may be stale.")
                        }
                        Text("Updated \(relativeText(for: refreshed))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var transport: some View {
        VStack(spacing: 12) {
            HStack(spacing: 24) {
                Spacer()
                Button {
                    model.reconnect()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.title3)
                        .foregroundStyle(model.isPlaying ? Color.primary : Color.secondary.opacity(0.4))
                }
                .buttonStyle(.borderless)
                .disabled(!model.isPlaying)
                .help("Reconnect stream")

                Button {
                    model.togglePlayback()
                } label: {
                    Image(systemName: model.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .resizable()
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.tint)
                        .frame(width: 48, height: 48)
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.space, modifiers: [])
                .help(model.isPlaying ? "Pause" : "Play")

                Button {
                    model.refreshAllMetadata()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.title3)
                }
                .buttonStyle(.borderless)
                .keyboardShortcut("r")
                .help("Refresh metadata")
                Spacer()
            }

            HStack(spacing: 8) {
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
        }
    }

    private var currentBlockSection: some View {
        Group {
            if let block = currentDetail?.currentBlock {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Image(systemName: "waveform.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.tint)
                        Text(block.name)
                            .font(.caption.weight(.semibold))
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(blockProgressText(for: block))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let description = block.description, !description.isEmpty {
                        Text(description)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.tail)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .stations: stationListContent
        case .upNext: upcomingBlocksContent
        case .topTracks: topTracksContent
        case .buzz: buzzContent
        }
    }

    private var stationListContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(PlayerModel.stations) { station in
                StationRow(
                    station: station,
                    detail: model.detailsByID[station.id],
                    track: model.tracksByID[station.id],
                    isSelected: station == model.currentStation
                ) {
                    model.selectStation(station)
                }
            }
        }
    }

    private var upcomingBlocksContent: some View {
        let upcoming = currentDetail?.upcomingBlocks ?? []
        return Group {
            if upcoming.isEmpty {
                emptyTabState("No upcoming blocks")
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(upcoming.prefix(4)) { block in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(block.name)
                                    .font(.caption.weight(.semibold))
                                Spacer()
                                Text(relativeText(for: block.startedAt))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            if let description = block.description, !description.isEmpty {
                                Text(description)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .truncationMode(.tail)
                            }
                        }
                    }
                }
            }
        }
    }

    private var topTracksContent: some View {
        let songs = currentDetail?.contentStats?.topSongsWeek ?? []
        return Group {
            if songs.isEmpty {
                emptyTabState("No top tracks yet")
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(songs.prefix(6)) { song in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(song.name)
                                    .font(.caption)
                                    .lineLimit(1)
                                Text(song.artist)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text("\(song.count)×")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }

    private var buzzContent: some View {
        let tweets = currentDetail?.tweets ?? []
        return Group {
            if tweets.isEmpty {
                emptyTabState("No recent activity")
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(tweets.prefix(3)) { tweet in
                        TweetRow(tweet: tweet, relativeText: relativeText)
                    }
                }
            }
        }
    }

    private func emptyTabState(_ message: String) -> some View {
        Text(message)
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 8)
    }

    private var footer: some View {
        HStack {
            Button {
                model.openRadioPage()
            } label: {
                Text("Open Andon FM")
                    .font(.caption)
            }
            .buttonStyle(.borderless)

            Spacer()

            Button {
                NSApp.terminate(nil)
            } label: {
                Text("Quit")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("q")
        }
        .foregroundStyle(.secondary)
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
            return "\(total)m block · ending"
        }
        return "\(elapsed)m / \(total)m"
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
                        image.resizable().aspectRatio(contentMode: .fill)
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.18))
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.18)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.18)
                .fill(Color.secondary.opacity(0.18))
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: size * 0.45))
                .foregroundStyle(.secondary)
        }
    }
}

private struct StationRow: View {
    let station: Station
    let detail: AndonStationDetail?
    let track: AndonTrack?
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                StationArtwork(url: detail?.imageURL, size: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(station.name)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let track, let title = track.title, !title.isEmpty {
                        Text(title)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text(station.host)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if let listeners = detail?.stats?.currentListeners {
                    Label("\(listeners)", systemImage: "person.2.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .labelStyle(.titleAndIcon)
                        .monospacedDigit()
                }
                Image(systemName: "checkmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
                    .opacity(isSelected ? 1 : 0)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(rowBackground)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private var rowBackground: Color {
        if isSelected {
            return Color.accentColor.opacity(0.15)
        } else if isHovering {
            return Color.primary.opacity(0.06)
        } else {
            return Color.clear
        }
    }
}

private struct TweetRow: View {
    let tweet: AndonStationDetail.Tweet
    let relativeText: (Date) -> String

    var body: some View {
        Button {
            if let url = tweet.tweetURL {
                NSWorkspace.shared.open(url)
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if tweet.isOwnTweet == true {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption2)
                            .foregroundStyle(.tint)
                    }
                    Text("@\(tweet.author.username)")
                        .font(.caption2.weight(.semibold))
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(relativeText(tweet.postedAt))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(tweet.content)
                    .font(.caption2)
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open in browser")
    }
}
