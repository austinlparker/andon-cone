import Foundation
import SwiftUI

struct Station: Identifiable, Hashable, Sendable {
    /// Andon Labs station UUID. Matches keys in /api/public/radio/metadata
    /// and the `id` field in /api/public/radio/stats.
    let id: String
    let name: String
    let host: String
    let streamURL: URL
    let accentColor: Color
}

struct AndonTrack: Decodable, Equatable, Sendable {
    let title: String?
    let artist: String?
    let online: Bool?
    let error: String?

    var displayTitle: String {
        guard let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else { return "Unknown title" }
        return trimmed
    }

    var displayArtist: String {
        guard let trimmed = artist?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else { return "Unknown artist" }
        return trimmed
    }
}

struct AndonStationDetail: Decodable, Equatable, Sendable, Identifiable {
    let id: String
    let imageUrl: String?
    let subtitle: String?
    let primaryModel: String?
    let ttsProvider: String?
    let ttsModel: String?
    let stats: Stats?
    let currentBlock: Block?
    let upcomingBlocks: [Block]?
    let tweets: [Tweet]?
    let contentStats: ContentStats?

    var imageURL: URL? {
        imageUrl.flatMap(URL.init(string:))
    }

    struct Stats: Decodable, Equatable, Sendable {
        let currentListeners: Int?
        let totalListeners: Int?
        let popularity: Int?
        let totalListenHours: Int?
    }

    struct Block: Decodable, Equatable, Sendable, Identifiable {
        let name: String
        let description: String?
        let imageUrl: String?
        let startedAt: Date
        let durationMinutes: Int

        var id: Date { startedAt }

        /// Human-readable progress for a block relative to a clock time
        /// (defaulted to now). Extracted from the view so it's unit-testable.
        func progressText(relativeTo now: Date = Date()) -> String {
            let elapsed = Int(now.timeIntervalSince(startedAt) / 60)
            if elapsed < 0 {
                let formatter = RelativeDateTimeFormatter()
                formatter.unitsStyle = .short
                return "starts \(formatter.localizedString(for: startedAt, relativeTo: now))"
            }
            if elapsed >= durationMinutes {
                return "\(durationMinutes)m block ending"
            }
            return "\(elapsed)m / \(durationMinutes)m"
        }
    }

    struct Tweet: Decodable, Equatable, Sendable, Identifiable {
        let id: String
        let content: String
        let postedAt: Date
        let tweetUrl: String
        let isOwnTweet: Bool?
        let author: Author

        var tweetURL: URL? { URL(string: tweetUrl) }

        struct Author: Decodable, Equatable, Sendable {
            let username: String
            let name: String
        }

        enum CodingKeys: String, CodingKey {
            case id, content, author
            case postedAt = "posted_at"
            case tweetUrl = "tweet_url"
            case isOwnTweet = "is_own_tweet"
        }
    }

    struct ContentStats: Decodable, Equatable, Sendable {
        let topSongsWeek: [Song]?
        let topGenres: [Genre]?

        struct Song: Decodable, Equatable, Sendable, Identifiable {
            let name: String
            let artist: String
            let count: Int

            var id: String { "\(name)|\(artist)" }
        }

        struct Genre: Decodable, Equatable, Sendable, Identifiable {
            let name: String
            let count: Int
            let percentage: Int

            var id: String { name }
        }
    }
}
