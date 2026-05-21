import Foundation
#if os(iOS)
import MediaPlayer
import UIKit
#endif

func isCancellation(_ error: Error) -> Bool {
    if error is CancellationError { return true }
    if let urlError = error as? URLError, urlError.code == .cancelled { return true }
    return Task.isCancelled
}

/// Network surface used by `PlayerModel`. Carved out so tests can inject a stub
/// instead of hitting the live Andon endpoints. The concrete `RadioAPIClient` below
/// is the production conformer.
///
/// Session lifecycle (`invalidateAndCancel`) is intentionally *not* on this protocol
/// — it's a `URLSession` implementation detail. `PlayerModel.shutdown` typed-downcasts
/// to invoke it on the concrete client.
protocol RadioAPI: Sendable {
    func fetchMetadata() async throws -> MetadataResponse
    func fetchStats() async throws -> StatsResponse
    #if os(iOS)
    // Artwork-loading is iOS-only because MPNowPlayingInfoCenter / MPMediaItemArtwork
    // only exist there. macOS lock-screen surfaces are handled by the system.
    func fetchArtwork(from url: URL) async throws -> NowPlayingArtwork
    #endif
}

final class RadioAPIClient: RadioAPI, @unchecked Sendable {
    private static let metadataEndpoint = URL(string: "https://os.andonlabs.com/api/public/radio/metadata")!
    private static let statsEndpoint = URL(string: "https://os.andonlabs.com/api/public/radio/stats")!

    private let session: URLSession

    init() {
        // Metadata endpoints always want fresh data — disable URLCache so a 304-like
        // response doesn't keep us pinned to a stale payload. waitsForConnectivity (in
        // the shared factory) handles brief blips without surfacing an error.
        session = CacheSupport.makePollingSession(disablesURLCache: true)
    }

    func fetchMetadata() async throws -> MetadataResponse {
        let data = try await data(for: Self.noCacheRequest(for: Self.metadataEndpoint))
        return try Self.decoder.decode(MetadataResponse.self, from: data)
    }

    func fetchStats() async throws -> StatsResponse {
        let data = try await data(for: Self.noCacheRequest(for: Self.statsEndpoint))
        return try Self.decoder.decode(StatsResponse.self, from: data)
    }

    #if os(iOS)
    func fetchArtwork(from url: URL) async throws -> NowPlayingArtwork {
        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        request.timeoutInterval = 10

        let data = try await data(for: request)
        guard let image = UIImage(data: data) else {
            throw URLError(.cannotDecodeContentData)
        }
        return NowPlayingArtwork(image: image)
    }
    #endif

    func invalidateAndCancel() {
        session.invalidateAndCancel()
    }

    private func data(for request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        try Self.validate(response)
        try Task.checkCancellation()
        return data
    }

    private static func noCacheRequest(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 10
        return request
    }

    private static func validate(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else { return }
        guard (200 ... 299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

#if os(iOS)
// UIImage is effectively immutable once initialized from data, so vending it
// from an MPMediaItemArtwork closure is safe across actors. @unchecked is on the wrapper.
struct NowPlayingArtwork: @unchecked Sendable {
    let mediaItemArtwork: MPMediaItemArtwork

    init(image: UIImage) {
        mediaItemArtwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }
}
#endif

struct MetadataResponse: Decodable {
    let stations: [String: AndonTrack]
}

struct StatsResponse: Decodable {
    let stations: [AndonStationDetail]
}
