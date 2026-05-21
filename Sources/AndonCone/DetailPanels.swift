import SwiftUI

enum DetailTab: String, CaseIterable, Identifiable {
    case schedule = "Schedule"
    case topTracks = "Top Tracks"
    case buzz = "Buzz"

    var id: String { rawValue }
}

struct SchedulePanel: View {
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

struct TopTracksPanel: View {
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

struct BuzzPanel: View {
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

struct BlockRow: View {
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

struct GlassSegmentedPicker: View {
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
