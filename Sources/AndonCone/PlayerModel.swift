import AVFoundation
import Foundation
#if os(iOS)
import MediaPlayer
import UIKit
#endif

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
    static let shared = PlayerModel()

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
    @Published private(set) var isRefreshingMetadata = false
    @Published private(set) var metadataErrorMessage: String?

    private var player: AVPlayer?
    private var playerItemStatusObservation: NSKeyValueObservation?
    private var metadataPollingTask: Task<Void, Never>?
    private var manualMetadataRefreshTask: Task<Void, Never>?
    #if os(iOS)
    private var artworkByURL: [URL: MPMediaItemArtwork] = [:]
    private var artworkLoadingURLs: Set<URL> = []
    #endif
    private let session: URLSession

    init() {
        currentStation = PlayerModel.stations[0]
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 20
        config.waitsForConnectivity = false
        session = URLSession(configuration: config)
        configureAudioSession()
        configureRemoteCommands()
    }

    func start() {
        guard metadataPollingTask == nil else { return }
        metadataPollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.performMetadataRefresh()
                try? await Task.sleep(for: .seconds(20))
            }
        }
    }

    func shutdown() {
        metadataPollingTask?.cancel()
        metadataPollingTask = nil
        manualMetadataRefreshTask?.cancel()
        manualMetadataRefreshTask = nil
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

    func play(_ station: Station) {
        currentStation = station
        startPlayback(for: station)
    }

    func reconnect() {
        guard isPlaying else { return }
        startPlayback(for: currentStation)
    }

    func selectStation(_ station: Station) {
        guard station != currentStation else { return }
        currentStation = station
        updateNowPlayingInfo()
        if isPlaying {
            startPlayback(for: station)
        }
    }

    func setVolume(_ value: Float) {
        let clamped = max(0, min(1, value))
        volume = clamped
        player?.volume = clamped
    }

    func station(id: String) -> Station? {
        Self.stations.first { $0.id == id }
    }

    func refreshAllMetadata() {
        manualMetadataRefreshTask?.cancel()
        manualMetadataRefreshTask = Task { [weak self] in
            await self?.performMetadataRefresh()
        }
    }

    static let radioPageURL = URL(string: "https://andonlabs.com/radio")!

    var currentTrack: AndonTrack? {
        tracksByID[currentStation.id]
    }

    var currentDetail: AndonStationDetail? {
        detailsByID[currentStation.id]
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
        updateNowPlayingInfo()
        observe(item: playerItem)
        newPlayer.play()
    }

    private func stopPlayback() {
        clearPlayerObservers()
        player?.pause()
        player = nil
        isPlaying = false
        updateNowPlayingInfo()
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

    private func performMetadataRefresh() async {
        guard !isRefreshingMetadata else { return }

        isRefreshingMetadata = true
        defer {
            isRefreshingMetadata = false
            updateMetadataStaleness()
        }

        var refreshErrors: [String] = []
        var didRefresh = false

        do {
            let response = try await Self.fetchMetadata(using: session)
            try Task.checkCancellation()
            tracksByID = response.stations
            didRefresh = true
        } catch {
            guard !Self.isCancellation(error) else { return }
            refreshErrors.append("metadata: \(error.localizedDescription)")
            NSLog("Andon Cone metadata refresh failed: %@", error.localizedDescription)
        }

        do {
            let response = try await Self.fetchStats(using: session)
            try Task.checkCancellation()
            applyStats(response.stations)
            didRefresh = true
        } catch {
            guard !Self.isCancellation(error) else { return }
            refreshErrors.append("stats: \(error.localizedDescription)")
            NSLog("Andon Cone stats refresh failed: %@", error.localizedDescription)
        }

        if didRefresh {
            lastMetadataRefresh = Date()
            metadataErrorMessage = refreshErrors.first
            updateNowPlayingInfo()
        } else {
            metadataErrorMessage = refreshErrors.first ?? "Metadata refresh failed"
            markMetadataStale()
        }
    }

    private static func fetchMetadata(using session: URLSession) async throws -> MetadataResponse {
        let (data, response) = try await session.data(for: noCacheRequest(for: metadataEndpoint))
        try validate(response)
        return try decoder.decode(MetadataResponse.self, from: data)
    }

    private static func fetchStats(using session: URLSession) async throws -> StatsResponse {
        let (data, response) = try await session.data(for: noCacheRequest(for: statsEndpoint))
        try validate(response)
        return try decoder.decode(StatsResponse.self, from: data)
    }

    private static func noCacheRequest(for url: URL) -> URLRequest {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let cacheBust = URLQueryItem(name: "_", value: String(Int(Date().timeIntervalSince1970)))
        var queryItems = components?.queryItems ?? []
        queryItems.append(cacheBust)
        components?.queryItems = queryItems

        var request = URLRequest(url: components?.url ?? url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 10
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        return request
    }

    private static func validate(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else { return }
        guard (200 ... 299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    private func applyStats(_ details: [AndonStationDetail]) {
        var dict: [String: AndonStationDetail] = [:]
        for detail in details {
            dict[detail.id] = detail
        }
        detailsByID = dict
    }

    private func markMetadataStale() {
        metadataIsStale = true
    }

    private func updateMetadataStaleness() {
        guard let lastMetadataRefresh else {
            metadataIsStale = true
            return
        }
        metadataIsStale = Date().timeIntervalSince(lastMetadataRefresh) > 75
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return Task.isCancelled
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private func configureAudioSession() {
        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            NSLog("Andon Cone audio session setup failed: %@", error.localizedDescription)
        }
        #endif
    }

    private func configureRemoteCommands() {
        #if os(iOS)
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.startPlayback(for: self.currentStation)
            }
            return .success
        }

        commandCenter.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.stopPlayback()
            }
            return .success
        }

        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.togglePlayback()
            }
            return .success
        }
        #endif
    }

    private func updateNowPlayingInfo() {
        #if os(iOS)
        let artworkURL = currentDetail?.imageURL
        var info: [String: Any] = [
            MPMediaItemPropertyAlbumTitle: currentStation.name,
            MPMediaItemPropertyTitle: currentTrack?.displayTitle ?? currentStation.name,
            MPMediaItemPropertyArtist: currentTrack?.displayArtist ?? currentStation.host,
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]

        if let listeners = currentDetail?.stats?.currentListeners {
            info[MPMediaItemPropertyComments] = "\(listeners) current listeners"
        }

        if let artworkURL {
            if let artwork = artworkByURL[artworkURL] {
                info[MPMediaItemPropertyArtwork] = artwork
            } else {
                loadNowPlayingArtwork(from: artworkURL, for: currentStation.id)
            }
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        #endif
    }

    #if os(iOS)
    private func loadNowPlayingArtwork(from url: URL, for stationID: String) {
        guard !artworkLoadingURLs.contains(url) else { return }

        artworkLoadingURLs.insert(url)
        Task { [weak self] in
            guard let self else { return }
            defer { Task { @MainActor in self.artworkLoadingURLs.remove(url) } }

            do {
                var request = URLRequest(url: url)
                request.cachePolicy = .returnCacheDataElseLoad
                request.timeoutInterval = 10
                let (data, response) = try await self.session.data(for: request)
                try Self.validate(response)
                try Task.checkCancellation()

                guard let image = UIImage(data: data) else { return }
                let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }

                await MainActor.run {
                    self.artworkByURL[url] = artwork
                    if self.currentStation.id == stationID {
                        self.updateNowPlayingInfo()
                    }
                }
            } catch {
                guard !Self.isCancellation(error) else { return }
                NSLog("Andon Cone artwork load failed: %@", error.localizedDescription)
            }
        }
    }
    #endif
}

private struct MetadataResponse: Decodable {
    let stations: [String: AndonTrack]
}

private struct StatsResponse: Decodable {
    let stations: [AndonStationDetail]
}
