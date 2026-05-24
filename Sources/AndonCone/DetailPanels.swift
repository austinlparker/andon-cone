import SwiftUI

enum DetailTab: String, CaseIterable, Identifiable {
    case schedule = "Schedule"
    case topTracks = "Top Tracks"
    case buzz = "Buzz"

    var id: String { rawValue }
}

struct SchedulePanel: View {
    @EnvironmentObject private var model: PlayerModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: dynamicTypeSize.isAccessibilitySize ? 16 : 12) {
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
                    TopTrackRow(rank: index + 1, song: song)
                }
            }
        }
        .panelStyle()
    }
}

private struct TopTrackRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let rank: Int
    let song: AndonStationDetail.ContentStats.Song

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    rankText
                    Spacer(minLength: 12)
                    countText
                }

                trackText
                artistText
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                rankText
                    .frame(width: 22, alignment: .trailing)

                VStack(alignment: .leading, spacing: 2) {
                    trackText
                    artistText
                }

                Spacer()

                countText
            }
        }
    }

    private var rankText: some View {
        Text("\(rank)")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.tertiary)
    }

    private var trackText: some View {
        Text(song.name)
            .font(.callout.weight(.semibold))
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var artistText: some View {
        Text(song.artist)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var countText: some View {
        Text("\(song.count)x")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

struct BuzzPanel: View {
    @EnvironmentObject private var model: PlayerModel
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
                            buzzHeader(for: tweet)

                            Text(tweet.content)
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 8 : 4)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(dynamicTypeSize.isAccessibilitySize ? 12 : 10)
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

    @ViewBuilder
    private func buzzHeader(for tweet: AndonStationDetail.Tweet) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 2) {
                authorLabel(for: tweet)

                Text(relativeText(for: tweet.postedAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        } else {
            HStack(spacing: 5) {
                authorLabel(for: tweet)

                Text(relativeText(for: tweet.postedAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func authorLabel(for tweet: AndonStationDetail.Tweet) -> some View {
        HStack(spacing: 5) {
            if tweet.isOwnTweet == true {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
            }

            Text("@\(tweet.author.username)")
                .font(.caption.weight(.semibold))
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct BlockRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    let block: AndonStationDetail.Block

    var body: some View {
        VStack(alignment: .leading, spacing: dynamicTypeSize.isAccessibilitySize ? 6 : 4) {
            header

            Text(block.name)
                .font(.headline)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                .fixedSize(horizontal: false, vertical: true)

            if let description = block.description, !description.isEmpty {
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 6 : 3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 4 : 0)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var header: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 2) {
                titleLabel
                progressText
            }
        } else {
            HStack {
                titleLabel
                Spacer()
                progressText
            }
        }
    }

    private var titleLabel: some View {
        Label(title, systemImage: "waveform.circle.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
    }

    private var progressText: some View {
        Text(block.progressText())
            .font(.caption)
            .foregroundStyle(.tertiary)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
    }
}

struct GlassSegmentedPicker: View {
    @EnvironmentObject private var model: PlayerModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var selection: DetailTab

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 6) {
                    ForEach(DetailTab.allCases) { tab in
                        tabButton(for: tab)
                    }
                }
                .padding(6)
                .appGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous), interactive: true)
            } else {
                HStack(spacing: 4) {
                    ForEach(DetailTab.allCases) { tab in
                        tabButton(for: tab)
                    }
                }
                .padding(5)
                .appGlass(in: Capsule(), interactive: true)
            }
        }
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
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: dynamicTypeSize.isAccessibilitySize ? 44 : 0)
                .padding(.vertical, 10)
                .background(
                    selectedBackground(for: tab)
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection == tab ? .isSelected : [])
    }

    @ViewBuilder
    private func selectedBackground(for tab: DetailTab) -> some View {
        let fill = selection == tab
            ? model.currentStation.accentColor.opacity(0.22)
            : Color.clear

        if dynamicTypeSize.isAccessibilitySize {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(fill)
        } else {
            Capsule()
                .fill(fill)
        }
    }
}
