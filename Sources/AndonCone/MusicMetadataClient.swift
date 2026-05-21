import Foundation
import SwiftUI

/// Catalog-level metadata for a single track, enriched from the iTunes Search API.
/// `trackID` is an Apple Music catalog identifier and can be passed straight to MusicKit.
struct EnrichedTrack: Codable, Equatable, Sendable, Identifiable {
    let trackID: String
    let trackName: String
    let artistName: String
    let albumTitle: String
    let artworkURL: URL?
    let appleMusicURL: URL?
    let releaseDate: Date?
    let genre: String?

    var id: String { trackID }

    var releaseYear: String? {
        guard let releaseDate else { return nil }
        return String(Calendar(identifier: .gregorian).component(.year, from: releaseDate))
    }

    /// The `https://music.apple.com/...` URL routed through the `music://` scheme so it
    /// opens directly in Music.app on iOS and macOS instead of bouncing through Safari.
    /// Falls back to the original URL if the host isn't `music.apple.com`.
    var musicAppURL: URL? {
        guard let appleMusicURL,
              var components = URLComponents(url: appleMusicURL, resolvingAgainstBaseURL: false),
              components.scheme == "https",
              components.host == "music.apple.com"
        else { return appleMusicURL }
        components.scheme = "music"
        return components.url ?? appleMusicURL
    }

    /// "Album · 1972" when we know the year, otherwise just "Album". Shared between
    /// the iOS and macOS hero layouts.
    var albumDisplayText: String {
        if let year = releaseYear {
            return "\(albumTitle) · \(year)"
        }
        return albumTitle
    }
}

/// Looks up `EnrichedTrack` info from the iTunes Search API.
///
/// Anonymous, no API key. Results are cached in memory and on disk (negative results
/// included, so we don't re-fetch obvious misses). Views read synchronously via
/// `enriched(for:)`; misses kick off a background fetch and the published `version`
/// counter ticks when results land.
@MainActor
final class MusicMetadataClient: ObservableObject {
    static let shared = MusicMetadataClient()

    /// Bumped each time a new entry lands in the cache so views re-render.
    @Published private(set) var version: Int = 0

    private enum CacheEntry: Codable {
        case match(EnrichedTrack)
        case miss
    }

    private var cache: [String: CacheEntry] = [:]
    private var inFlight: Set<String> = []
    private let cacheDirectory: URL
    private let session: URLSession

    init() {
        cacheDirectory = CacheSupport.cacheDirectory(named: "Tracks")
        session = CacheSupport.makePollingSession()
    }

    /// Synchronous read. Returns nil for both "looked up, no match" and "not yet looked up"
    /// — callers shouldn't care about the distinction.
    func enriched(for track: AndonTrack) -> EnrichedTrack? {
        let key = Self.cacheKey(for: track)
        switch resolved(key: key) {
        case .match(let enriched): return enriched
        case .miss, .none: return nil
        }
    }

    /// Fire a background lookup if we don't already have a result (or one in flight).
    /// Safe to call as often as you like — it dedupes.
    func enrich(_ track: AndonTrack) {
        let key = Self.cacheKey(for: track)
        if resolved(key: key) != nil { return }
        if inFlight.contains(key) { return }

        // Skip placeholder values — no point searching for "Unknown artist".
        let title = track.displayTitle
        let artist = track.displayArtist
        guard title != "Unknown title", artist != "Unknown artist" else { return }

        inFlight.insert(key)
        Task { [weak self] in
            await self?.fetch(key: key, artist: artist, title: title)
        }
    }

    private func resolved(key: String) -> CacheEntry? {
        if let memory = cache[key] { return memory }
        if let disk = loadFromDisk(key: key) {
            cache[key] = disk
            return disk
        }
        return nil
    }

    private func fetch(key: String, artist: String, title: String) async {
        defer { inFlight.remove(key) }

        let url = Self.makeSearchURL(artist: artist, title: title)
        do {
            let (data, _) = try await session.data(from: url)
            let response = try Self.decoder.decode(iTunesSearchResponse.self, from: data)

            let chosen = Self.bestMatch(in: response.results, matchingArtist: artist)

            let entry: CacheEntry
            if let item = chosen {
                entry = .match(EnrichedTrack(
                    trackID: String(item.trackId),
                    trackName: item.trackName,
                    artistName: item.artistName,
                    albumTitle: item.collectionName ?? item.trackName,
                    artworkURL: item.hiResArtworkURL,
                    appleMusicURL: item.trackViewUrl.flatMap(URL.init(string:)),
                    releaseDate: item.releaseDateDecoded,
                    genre: item.primaryGenreName
                ))
            } else {
                entry = .miss
            }

            cache[key] = entry
            try? saveToDisk(entry, key: key)
            version &+= 1
        } catch {
            // Network failure: leave uncached so the next prefetch retries.
        }
    }

    nonisolated static func cacheKey(for track: AndonTrack) -> String {
        // Lowercase so capitalization wobbles between metadata refreshes don't fork the cache.
        "\(track.displayArtist.lowercased())|\(track.displayTitle.lowercased())"
    }

    /// Picks the first iTunes result whose artist overlaps the query artist as a
    /// case-insensitive substring in either direction. Suppresses obviously wrong
    /// matches (live, remix, cover versions sometimes return unrelated tracks).
    nonisolated static func bestMatch(in results: [iTunesSong], matchingArtist artist: String) -> iTunesSong? {
        results.first { item in
            item.artistName.localizedCaseInsensitiveContains(artist)
                || artist.localizedCaseInsensitiveContains(item.artistName)
        }
    }

    private static func makeSearchURL(artist: String, title: String) -> URL {
        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            URLQueryItem(name: "term", value: "\(artist) \(title)"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "1"),
        ]
        return components.url!
    }

    private func diskPath(for key: String) -> URL {
        cacheDirectory.appendingPathComponent("\(CacheSupport.cacheFilename(for: key)).json")
    }

    private func loadFromDisk(key: String) -> CacheEntry? {
        let path = diskPath(for: key)
        guard let data = try? Data(contentsOf: path) else { return nil }
        return try? Self.decoder.decode(CacheEntry.self, from: data)
    }

    private func saveToDisk(_ entry: CacheEntry, key: String) throws {
        let data = try Self.encoder.encode(entry)
        try data.write(to: diskPath(for: key), options: [.atomic])
    }

    private static let decoder = JSONDecoder()
    private static let encoder = JSONEncoder()
}

struct iTunesSearchResponse: Decodable {
    let resultCount: Int
    let results: [iTunesSong]
}

struct iTunesSong: Decodable {
    let trackId: Int
    let trackName: String
    let artistName: String
    let collectionName: String?
    let artworkUrl100: String?
    let trackViewUrl: String?
    let releaseDate: String?
    let primaryGenreName: String?

    /// Rewrite the 100×100 URL Apple returns to a 600×600 variant — the underlying CDN
    /// honors the substitution and we get crisp artwork for the hero card.
    var hiResArtworkURL: URL? {
        guard let url = artworkUrl100 else { return nil }
        let hiRes = url.replacingOccurrences(of: "100x100bb", with: "600x600bb")
        return URL(string: hiRes)
    }

    var releaseDateDecoded: Date? {
        guard let dateStr = releaseDate else { return nil }
        return ISO8601DateFormatter().date(from: dateStr)
    }
}
