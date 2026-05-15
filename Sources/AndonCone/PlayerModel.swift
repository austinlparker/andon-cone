import AVFoundation
import AppKit
import Foundation

struct Station: Identifiable, Hashable, Sendable {
    /// Andon Labs station UUID. Matches keys in /api/public/radio/metadata
    /// and the `id` field in /api/public/radio/stats.
    let id: String
    let name: String
    let host: String
    let streamURL: URL
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

@MainActor
final class PlayerModel: ObservableObject {
    static let stations: [Station] = [
        Station(
            id: "aab4d149-92fa-4386-9c1e-d938ecb66ee3",
            name: "Backlink Broadcast",
            host: "Gemini 3.1 Pro Preview",
            streamURL: URL(string: "https://streaming.live365.com/a13541")!
        ),
        Station(
            id: "6b53fc38-ed57-4738-80d6-f9fddf981054",
            name: "Thinking Frequencies",
            host: "Claude Opus 4.7",
            streamURL: URL(string: "https://streaming.live365.com/a46431")!
        ),
        Station(
            id: "df197c3e-0137-4665-95f3-0fc5cec1ee1e",
            name: "OpenAIR",
            host: "GPT 5.5",
            streamURL: URL(string: "https://streaming.live365.com/a81044")!
        ),
        Station(
            id: "887ec509-2be8-433e-a27e-d05c1dc21278",
            name: "Grok and Roll",
            host: "Grok 4.3",
            streamURL: URL(string: "https://streaming.live365.com/a15419")!
        ),
    ]

    private static let metadataEndpoint = URL(string: "https://os.andonlabs.com/api/public/radio/metadata")!
    private static let statsEndpoint = URL(string: "https://os.andonlabs.com/api/public/radio/stats")!

    @Published var currentStation: Station
    @Published private(set) var isPlaying = false
    @Published var volume: Float = 1.0
    @Published private(set) var tracksByID: [String: AndonTrack] = [:]
    @Published private(set) var detailsByID: [String: AndonStationDetail] = [:]
    @Published private(set) var lastMetadataRefresh: Date?
    @Published private(set) var metadataIsStale = false

    private var player: AVPlayer?
    private var playerItemStatusObservation: NSKeyValueObservation?
    private var metadataPollingTask: Task<Void, Never>?
    private let session: URLSession

    init() {
        currentStation = PlayerModel.stations[0]
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 20
        config.waitsForConnectivity = false
        session = URLSession(configuration: config)
    }

    func start() {
        guard metadataPollingTask == nil else { return }
        metadataPollingTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.refreshAllMetadata()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    func shutdown() {
        metadataPollingTask?.cancel()
        metadataPollingTask = nil
        stopPlayback()
        session.invalidateAndCancel()
    }

    func togglePlayback() {
        if isPlaying {
            stopPlayback()
        } else {
            startPlayback(for: currentStation)
        }
    }

    func reconnect() {
        guard isPlaying else { return }
        startPlayback(for: currentStation)
    }

    func selectStation(_ station: Station) {
        guard station != currentStation else { return }
        currentStation = station
        if isPlaying {
            startPlayback(for: station)
        }
    }

    func setVolume(_ value: Float) {
        let clamped = max(0, min(1, value))
        volume = clamped
        player?.volume = clamped
    }

    func refreshAllMetadata() {
        refreshTracks()
        refreshStats()
    }

    func openRadioPage() {
        NSWorkspace.shared.open(URL(string: "https://andonlabs.com/radio")!)
    }

    private func startPlayback(for station: Station) {
        // Tear the outgoing player down explicitly. ARC alone can leave a brief
        // window where the previous stream keeps feeding audio if anything
        // transient (a pending notification, an in-flight load) retains it.
        player?.pause()
        clearPlayerObservers()

        let playerItem = AVPlayerItem(url: station.streamURL)
        let newPlayer = AVPlayer(playerItem: playerItem)
        newPlayer.volume = volume
        player = newPlayer
        isPlaying = true
        observe(item: playerItem)
        newPlayer.play()
    }

    private func stopPlayback() {
        clearPlayerObservers()
        player?.pause()
        player = nil
        isPlaying = false
    }

    private func observe(item: AVPlayerItem) {
        playerItemStatusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            Task { @MainActor [weak self] in
                self?.isPlaying = false
            }
        }
    }

    private func clearPlayerObservers() {
        playerItemStatusObservation?.invalidate()
        playerItemStatusObservation = nil
    }

    private func refreshTracks() {
        let session = self.session
        Task { [weak self] in
            do {
                let (data, _) = try await session.data(from: PlayerModel.metadataEndpoint)
                try Task.checkCancellation()
                let response = try Self.decoder.decode(MetadataResponse.self, from: data)
                self?.applyTracks(response.stations)
            } catch {
                if Task.isCancelled { return }
                if let urlError = error as? URLError, urlError.code == .cancelled { return }
                NSLog("Andon Cone metadata refresh failed: %@", error.localizedDescription)
                self?.markMetadataStale()
            }
        }
    }

    private func refreshStats() {
        let session = self.session
        Task { [weak self] in
            do {
                let (data, _) = try await session.data(from: PlayerModel.statsEndpoint)
                try Task.checkCancellation()
                let response = try Self.decoder.decode(StatsResponse.self, from: data)
                self?.applyStats(response.stations)
            } catch {
                if Task.isCancelled { return }
                if let urlError = error as? URLError, urlError.code == .cancelled { return }
                NSLog("Andon Cone stats refresh failed: %@", error.localizedDescription)
                self?.markMetadataStale()
            }
        }
    }

    private func applyTracks(_ tracks: [String: AndonTrack]) {
        tracksByID = tracks
        lastMetadataRefresh = Date()
        metadataIsStale = false
    }

    private func applyStats(_ details: [AndonStationDetail]) {
        var dict: [String: AndonStationDetail] = [:]
        for detail in details {
            dict[detail.id] = detail
        }
        detailsByID = dict
        lastMetadataRefresh = Date()
        metadataIsStale = false
    }

    private func markMetadataStale() {
        metadataIsStale = true
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

private struct MetadataResponse: Decodable {
    let stations: [String: AndonTrack]
}

private struct StatsResponse: Decodable {
    let stations: [AndonStationDetail]
}
