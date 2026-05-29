import AVFoundation
import Combine
import Foundation
import SwiftUI
#if os(iOS)
import MediaPlayer
import UIKit
#endif

@MainActor
final class PlayerModel: ObservableObject {
    static let shared = PlayerModel()

    static let stations: [Station] = [
        Station(
            id: "aab4d149-92fa-4386-9c1e-d938ecb66ee3",
            name: "Backlink Broadcast",
            host: "Gemini 3.1 Pro Preview",
            streamURL: URL(string: "https://streaming.live365.com/a13541")!,
            accentColor: Color(red: 0.10, green: 0.72, blue: 0.68)
        ),
        Station(
            id: "6b53fc38-ed57-4738-80d6-f9fddf981054",
            name: "Thinking Frequencies",
            host: "Claude Opus 4.7",
            streamURL: URL(string: "https://streaming.live365.com/a46431")!,
            accentColor: Color(red: 0.86, green: 0.36, blue: 0.16)
        ),
        Station(
            id: "df197c3e-0137-4665-95f3-0fc5cec1ee1e",
            name: "OpenAIR",
            host: "GPT 5.5",
            streamURL: URL(string: "https://streaming.live365.com/a81044")!,
            accentColor: Color(red: 0.18, green: 0.56, blue: 0.94)
        ),
        Station(
            id: "887ec509-2be8-433e-a27e-d05c1dc21278",
            name: "Grok and Roll",
            host: "Grok 4.3",
            streamURL: URL(string: "https://streaming.live365.com/a15419")!,
            accentColor: Color(red: 0.78, green: 0.22, blue: 0.88)
        ),
    ]

    @Published var currentStation: Station
    @Published private(set) var isPlaying = false
    @Published private(set) var isBuffering = false
    @Published var volume: Float = 1.0
    @Published private(set) var isMuted = false
    @Published private(set) var tracksByID: [String: AndonTrack] = [:]
    @Published private(set) var detailsByID: [String: AndonStationDetail] = [:]
    @Published private(set) var lastMetadataRefresh: Date?
    @Published private(set) var metadataIsStale = false
    @Published private(set) var isRefreshingMetadata = false
    @Published private(set) var metadataErrorMessage: String?

    private var player: AVPlayer?
    private var playerStation: Station?
    private var playerItemStatusObservation: NSKeyValueObservation?
    private var playerTimeControlObservation: NSKeyValueObservation?
    private var playbackNotificationObservers: [NSObjectProtocol] = []
    private var metadataPollingTask: Task<Void, Never>?
    private var manualMetadataRefreshTask: Task<Void, Never>?
    private var volumeBeforeMute: Float = 1.0
    #if os(iOS)
    private var artworkByURL: [URL: NowPlayingArtwork] = [:]
    private var artworkLoadingURLs: Set<URL> = []
    private let metadataClient = MusicMetadataClient.shared
    private var metadataVersionCancellable: AnyCancellable?
    private var nowPlayingSession: MPNowPlayingSession?
    #endif
    private let apiClient: RadioAPI
    private let performsExternalEffects: Bool

    init(apiClient: RadioAPI = RadioAPIClient(), performsExternalEffects: Bool = true) {
        currentStation = PlayerModel.stations[0]
        self.apiClient = apiClient
        self.performsExternalEffects = performsExternalEffects

        if performsExternalEffects {
            configureAudioSession()
            #if os(iOS)
            configureRemoteCommands(on: MPRemoteCommandCenter.shared())
            #endif
            observeMetadataEnrichment()
        }
    }

    func start() {
        guard metadataPollingTask == nil else { return }
        metadataPollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.performMetadataRefresh(force: false)
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
        // Session lifecycle stays out of the RadioAPI protocol — tests don't model it.
        (apiClient as? RadioAPIClient)?.invalidateAndCancel()
    }

    func togglePlayback() {
        if isPlaying {
            pausePlayback()
        } else {
            resumePlayback()
        }
    }

    func play(_ station: Station) {
        // Tapping the currently-playing station should be a no-op,
        // not a stream restart. CarPlay relies on this.
        guard station != currentStation || !isPlaying else { return }
        currentStation = station
        if playerStation == station {
            resumePlayback()
        } else {
            startPlayback(for: station)
        }
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

    func nextStation() {
        guard let index = Self.stations.firstIndex(of: currentStation) else { return }
        let next = Self.stations[(index + 1) % Self.stations.count]
        selectStation(next)
    }

    func previousStation() {
        guard let index = Self.stations.firstIndex(of: currentStation) else { return }
        let count = Self.stations.count
        let prev = Self.stations[(index - 1 + count) % count]
        selectStation(prev)
    }

    func setVolume(_ value: Float) {
        let clamped = max(0, min(1, value))
        volume = clamped
        player?.volume = clamped
        if clamped > 0 {
            volumeBeforeMute = clamped
            isMuted = false
            player?.isMuted = false
        } else {
            isMuted = true
            player?.isMuted = true
        }
    }

    func toggleMute() {
        if isMuted {
            let restoredVolume = max(volumeBeforeMute, 0.25)
            isMuted = false
            volume = restoredVolume
            player?.volume = restoredVolume
            player?.isMuted = false
        } else {
            volumeBeforeMute = max(volume, 0.25)
            isMuted = true
            player?.isMuted = true
        }
    }

    func station(id: String) -> Station? {
        Self.stations.first { $0.id == id }
    }

    func refreshAllMetadata() {
        manualMetadataRefreshTask?.cancel()
        manualMetadataRefreshTask = Task { [weak self] in
            await self?.performMetadataRefresh(force: true)
        }
    }

    static let radioPageURL = URL(string: "https://andonlabs.com/radio")!

    var currentTrack: AndonTrack? {
        tracksByID[currentStation.id]
    }

    var currentDetail: AndonStationDetail? {
        detailsByID[currentStation.id]
    }

    var routePickerPlayer: AVPlayer? {
        player
    }

    private func startPlayback(for station: Station) {
        guard performsExternalEffects else {
            isPlaying = true
            isBuffering = false
            updateNowPlayingInfo()
            return
        }

        // Tear the outgoing player down explicitly. ARC alone can leave a brief
        // window where the previous stream keeps feeding audio if anything
        // transient (a pending notification, an in-flight load) retains it.
        player?.pause()
        clearPlayerObservers()

        let playerItem = AVPlayerItem(url: station.streamURL)
        let newPlayer = AVPlayer(playerItem: playerItem)
        newPlayer.allowsExternalPlayback = true
        newPlayer.volume = volume
        newPlayer.isMuted = isMuted
        player = newPlayer
        playerStation = station
        #if os(iOS)
        configureNowPlayingSession(for: newPlayer)
        #endif
        isPlaying = true
        isBuffering = true
        updateNowPlayingInfo()
        observe(player: newPlayer, item: playerItem)
        newPlayer.play()
    }

    private func pausePlayback() {
        guard performsExternalEffects else {
            isPlaying = false
            isBuffering = false
            updateNowPlayingInfo()
            return
        }

        player?.pause()
        isPlaying = false
        isBuffering = false
        updateNowPlayingInfo()
    }

    private func resumePlayback() {
        guard performsExternalEffects else {
            isPlaying = true
            updateNowPlayingInfo()
            return
        }

        guard let player, playerStation == currentStation else {
            startPlayback(for: currentStation)
            return
        }

        isPlaying = true
        isBuffering = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
        updateNowPlayingInfo()
        player.play()
    }

    private func stopPlayback() {
        clearPlayerObservers()
        player?.pause()
        player = nil
        playerStation = nil
        #if os(iOS)
        clearNowPlayingSession()
        #endif
        isPlaying = false
        isBuffering = false
        updateNowPlayingInfo()
    }

    private func observe(player: AVPlayer, item: AVPlayerItem) {
        playerItemStatusObservation = item.observe(\.status, options: [.new]) { [weak self, weak player] item, _ in
            guard item.status == .failed else { return }
            Task { @MainActor [weak self] in
                guard let self, self.player === player else { return }
                self.handlePlaybackFailure()
            }
        }

        playerTimeControlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self, weak player] observedPlayer, _ in
            // KVO can fire off-main; capture the status and hop back to main for state mutation.
            let waiting = (observedPlayer.timeControlStatus == .waitingToPlayAtSpecifiedRate)
            Task { @MainActor [weak self] in
                guard let self, self.player === player else { return }
                self.isBuffering = waiting
            }
        }

        let center = NotificationCenter.default
        let stallObserver = center.addObserver(
            forName: AVPlayerItem.playbackStalledNotification,
            object: item,
            queue: .main
        ) { [weak self, weak player] _ in
            Task { @MainActor [weak self] in
                guard let self, self.player === player else { return }
                self.isBuffering = true
            }
        }
        let failureObserver = center.addObserver(
            forName: AVPlayerItem.failedToPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self, weak player] _ in
            Task { @MainActor [weak self] in
                guard let self, self.player === player else { return }
                self.handlePlaybackFailure()
            }
        }
        playbackNotificationObservers = [stallObserver, failureObserver]
    }

    private func handlePlaybackFailure() {
        isPlaying = false
        isBuffering = false
        updateNowPlayingInfo()
    }

    private func clearPlayerObservers() {
        playerItemStatusObservation?.invalidate()
        playerItemStatusObservation = nil
        playerTimeControlObservation?.invalidate()
        playerTimeControlObservation = nil
        for observer in playbackNotificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        playbackNotificationObservers = []
    }

    /// Internal (not private) so tests can drive a single refresh cycle deterministically
    /// against an injected `RadioAPI` stub. The public `refreshAllMetadata` wraps this
    /// in a Task for the production app.
    func performMetadataRefresh(force: Bool) async {
        // Keep refreshes serialized so scene-activation and polling cannot race
        // each other into duplicate network calls and interleaved published state.
        if isRefreshingMetadata { return }

        isRefreshingMetadata = true
        defer {
            isRefreshingMetadata = false
            updateMetadataStaleness()
        }

        async let metadataTask = apiClient.fetchMetadata()
        async let statsTask = apiClient.fetchStats()

        var lastError: String?
        var anySuccess = false

        do {
            let response = try await metadataTask
            // Merge so a station temporarily missing from the response
            // doesn't blink out of the UI.
            var dict = tracksByID
            for (id, track) in response.stations {
                dict[id] = track
            }
            tracksByID = dict
            anySuccess = true
        } catch {
            // Cancellation isn't a refresh failure — the call was aborted from outside
            // (background, manual-refresh-while-polling). Suppress it so a sibling
            // success still commits its timestamp below.
            if !isCancellation(error) {
                lastError = "metadata: \(error.localizedDescription)"
                NSLog("Andon Cone metadata refresh failed: %@", error.localizedDescription)
            }
        }

        do {
            let response = try await statsTask
            applyStats(response.stations)
            anySuccess = true
        } catch {
            if !isCancellation(error) {
                lastError = "stats: \(error.localizedDescription)"
                NSLog("Andon Cone stats refresh failed: %@", error.localizedDescription)
            }
        }

        if anySuccess {
            lastMetadataRefresh = Date()
            metadataErrorMessage = lastError
            updateNowPlayingInfo()
        } else if let lastError {
            metadataErrorMessage = lastError
            metadataIsStale = true
        }
        // else: both calls were cancelled — leave user-visible state untouched.
    }

    private func applyStats(_ details: [AndonStationDetail]) {
        var dict = detailsByID
        for detail in details {
            dict[detail.id] = detail
        }
        detailsByID = dict
    }

    private func updateMetadataStaleness() {
        metadataIsStale = Self.isStale(lastRefresh: lastMetadataRefresh)
    }

    /// Metadata is considered stale once it's older than 75 seconds (~3.75 poll cycles).
    /// `nil` lastRefresh is treated as stale.
    static func isStale(lastRefresh: Date?, now: Date = Date()) -> Bool {
        guard let lastRefresh else { return true }
        return now.timeIntervalSince(lastRefresh) > 75
    }

    private func configureAudioSession() {
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, policy: .longFormAudio, options: [])
            try session.setActive(true)
        } catch {
            NSLog("Andon Cone audio session setup failed: %@", error.localizedDescription)
        }
        #endif
    }

    #if os(iOS)
    private func configureRemoteCommands(on commandCenter: MPRemoteCommandCenter) {
        commandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.resumePlayback()
            }
            return .success
        }

        commandCenter.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.pausePlayback()
            }
            return .success
        }

        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.togglePlayback()
            }
            return .success
        }

        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.isEnabled = true

        disableUnsupportedRemoteCommands(on: commandCenter)
    }

    private func disableUnsupportedRemoteCommands(on commandCenter: MPRemoteCommandCenter) {
        [
            commandCenter.stopCommand,
            commandCenter.nextTrackCommand,
            commandCenter.previousTrackCommand,
            commandCenter.skipForwardCommand,
            commandCenter.skipBackwardCommand,
            commandCenter.seekForwardCommand,
            commandCenter.seekBackwardCommand,
            commandCenter.changePlaybackPositionCommand,
            commandCenter.changePlaybackRateCommand,
            commandCenter.changeRepeatModeCommand,
            commandCenter.changeShuffleModeCommand,
            commandCenter.ratingCommand,
            commandCenter.likeCommand,
            commandCenter.dislikeCommand,
            commandCenter.bookmarkCommand
        ].forEach { $0.isEnabled = false }
    }
    #endif

    private func observeMetadataEnrichment() {
        #if os(iOS)
        metadataVersionCancellable = metadataClient.$version
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.updateNowPlayingInfo()
                }
            }
        #endif
    }

    private func updateNowPlayingInfo() {
        #if os(iOS)
        guard performsExternalEffects else { return }

        let track = currentTrack
        let enriched = enrichedCurrentTrack(for: track)
        var info: [String: Any] = [
            MPMediaItemPropertyAlbumTitle: enriched?.albumTitle ?? currentStation.name,
            MPMediaItemPropertyTitle: enriched?.trackName ?? track?.displayTitle ?? currentStation.name,
            MPMediaItemPropertyArtist: enriched?.artistName ?? track?.displayArtist ?? currentStation.host,
            MPMediaItemPropertyMediaType: NSNumber(value: MPMediaType.music.rawValue),
            MPNowPlayingInfoPropertyMediaType: NSNumber(value: MPNowPlayingInfoMediaType.audio.rawValue),
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]

        if let listeners = currentDetail?.stats?.currentListeners {
            info[MPMediaItemPropertyComments] = "\(listeners) current listeners"
        }

        applyNowPlayingArtwork(
            preferredURL: enriched?.artworkURL,
            fallbackURL: currentDetail?.imageURL,
            station: currentStation,
            to: &info
        )

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        if let nowPlayingSession {
            nowPlayingSession.nowPlayingInfoCenter.nowPlayingInfo = info
            nowPlayingSession.becomeActiveIfPossible { didBecomeActive in
                if !didBecomeActive {
                    NSLog("Andon Cone Now Playing session did not become active")
                }
            }
        }
        #endif
    }

    #if os(iOS)
    private func configureNowPlayingSession(for player: AVPlayer) {
        let session = MPNowPlayingSession(players: [player])
        session.automaticallyPublishesNowPlayingInfo = false
        configureRemoteCommands(on: session.remoteCommandCenter)
        nowPlayingSession = session
        session.becomeActiveIfPossible { didBecomeActive in
            if !didBecomeActive {
                NSLog("Andon Cone Now Playing session did not become active")
            }
        }
    }

    private func clearNowPlayingSession() {
        nowPlayingSession?.nowPlayingInfoCenter.nowPlayingInfo = nil
        nowPlayingSession = nil
    }

    private func enrichedCurrentTrack(for track: AndonTrack?) -> EnrichedTrack? {
        guard let track else { return nil }
        if let enriched = metadataClient.enriched(for: track) {
            return enriched
        }
        metadataClient.enrich(track)
        return nil
    }

    private func applyNowPlayingArtwork(
        preferredURL: URL?,
        fallbackURL: URL?,
        station: Station,
        to info: inout [String: Any]
    ) {
        if let preferredURL {
            if let artwork = artworkByURL[preferredURL] {
                info[MPMediaItemPropertyArtwork] = artwork.mediaItemArtwork
                return
            }
            loadNowPlayingArtwork(from: preferredURL, for: currentStation.id)
        }

        guard let fallbackURL, fallbackURL != preferredURL else {
            info[MPMediaItemPropertyArtwork] = NowPlayingArtwork(station: station).mediaItemArtwork
            return
        }
        if let artwork = artworkByURL[fallbackURL] {
            info[MPMediaItemPropertyArtwork] = artwork.mediaItemArtwork
        } else {
            loadNowPlayingArtwork(from: fallbackURL, for: currentStation.id)
            info[MPMediaItemPropertyArtwork] = NowPlayingArtwork(station: station).mediaItemArtwork
        }
    }

    private func loadNowPlayingArtwork(from url: URL, for stationID: String) {
        guard !artworkLoadingURLs.contains(url) else { return }
        artworkLoadingURLs.insert(url)

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let artwork = try await self.apiClient.fetchArtwork(from: url)
                self.artworkLoadingURLs.remove(url)
                self.artworkByURL[url] = artwork
                if self.currentStation.id == stationID {
                    self.updateNowPlayingInfo()
                }
            } catch {
                self.artworkLoadingURLs.remove(url)
                if isCancellation(error) { return }
                NSLog("Andon Cone artwork load failed: %@", error.localizedDescription)
            }
        }
    }
    #endif
}

extension PlayerModel {
    static var preview: PlayerModel {
        let model = PlayerModel(apiClient: PreviewRadioAPI(), performsExternalEffects: false)
        model.applyPreviewData()
        return model
    }

    private func applyPreviewData() {
        let now = Date()
        let tracks: [AndonTrack] = [
            AndonTrack(title: "Midnight Cache Warmup", artist: "The Async Letdowns", online: true, error: nil),
            AndonTrack(title: "Glass Effect Overdrive", artist: "Selector Set", online: true, error: nil),
            AndonTrack(title: "No Manual Refresh", artist: "Silent Poller", online: true, error: nil),
            AndonTrack(title: "Backpressure Ballad", artist: "Main Actor Trio", online: true, error: nil),
        ]

        tracksByID = Dictionary(uniqueKeysWithValues: zip(Self.stations.map(\.id), tracks))
        detailsByID = Dictionary(uniqueKeysWithValues: Self.stations.enumerated().map { index, station in
            (station.id, Self.previewDetail(for: station, index: index, now: now))
        })
        lastMetadataRefresh = now
        metadataIsStale = false
        metadataErrorMessage = nil
    }

    private static func previewDetail(for station: Station, index: Int, now: Date) -> AndonStationDetail {
        AndonStationDetail(
            id: station.id,
            imageUrl: nil,
            subtitle: "Preview station",
            primaryModel: station.host,
            ttsProvider: "Andon Preview",
            ttsModel: station.host,
            stats: AndonStationDetail.Stats(
                currentListeners: 28 + (index * 7),
                totalListeners: 1280 + (index * 245),
                popularity: 70 + index,
                totalListenHours: 560 + (index * 90)
            ),
            currentBlock: AndonStationDetail.Block(
                name: station.name,
                description: "A live preview block with enough metadata to exercise the production layout.",
                imageUrl: nil,
                startedAt: now.addingTimeInterval(-18 * 60),
                durationMinutes: 60
            ),
            upcomingBlocks: [
                AndonStationDetail.Block(
                    name: "Signal Check",
                    description: "Fresh station IDs, schedules, and listener stats roll forward.",
                    imageUrl: nil,
                    startedAt: now.addingTimeInterval(42 * 60),
                    durationMinutes: 45
                ),
                AndonStationDetail.Block(
                    name: "Late Rotation",
                    description: "Deep cuts and metadata enrichment for the next listening window.",
                    imageUrl: nil,
                    startedAt: now.addingTimeInterval(87 * 60),
                    durationMinutes: 60
                ),
            ],
            tweets: [
                AndonStationDetail.Tweet(
                    id: "\(station.id)-tweet-1",
                    content: "Preview metadata landed cleanly across the app shell.",
                    postedAt: now.addingTimeInterval(-14 * 60),
                    tweetUrl: "https://andonlabs.com/radio",
                    isOwnTweet: true,
                    author: AndonStationDetail.Tweet.Author(username: "andonfm", name: "Andon FM")
                ),
                AndonStationDetail.Tweet(
                    id: "\(station.id)-tweet-2",
                    content: "The current station keeps playing while the detail panels stay warm.",
                    postedAt: now.addingTimeInterval(-48 * 60),
                    tweetUrl: "https://andonlabs.com/radio",
                    isOwnTweet: false,
                    author: AndonStationDetail.Tweet.Author(username: "listener", name: "Listener")
                ),
            ],
            contentStats: AndonStationDetail.ContentStats(
                topSongsWeek: [
                    AndonStationDetail.ContentStats.Song(name: "Midnight Cache Warmup", artist: "The Async Letdowns", count: 18),
                    AndonStationDetail.ContentStats.Song(name: "Glass Effect Overdrive", artist: "Selector Set", count: 14),
                    AndonStationDetail.ContentStats.Song(name: "No Manual Refresh", artist: "Silent Poller", count: 11),
                    AndonStationDetail.ContentStats.Song(name: "Backpressure Ballad", artist: "Main Actor Trio", count: 9),
                ],
                topGenres: [
                    AndonStationDetail.ContentStats.Genre(name: "Ambient", count: 28, percentage: 42),
                    AndonStationDetail.ContentStats.Genre(name: "Indie", count: 18, percentage: 27),
                ]
            )
        )
    }
}

private struct PreviewRadioAPI: RadioAPI {
    func fetchMetadata() async throws -> MetadataResponse {
        MetadataResponse(stations: [:])
    }

    func fetchStats() async throws -> StatsResponse {
        StatsResponse(stations: [])
    }

    #if os(iOS)
    func fetchArtwork(from url: URL) async throws -> NowPlayingArtwork {
        throw URLError(.resourceUnavailable)
    }
    #endif
}
