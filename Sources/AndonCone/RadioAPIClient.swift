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
        mediaItemArtwork = MPMediaItemArtwork(boundsSize: image.size) { requestedSize in
            image.resizedForNowPlayingArtwork(targetSize: requestedSize)
        }
    }

    init(station: Station) {
        let image = UIImage.stationNowPlayingFallback(for: station)
        mediaItemArtwork = MPMediaItemArtwork(boundsSize: image.size) { requestedSize in
            image.resizedForNowPlayingArtwork(targetSize: requestedSize)
        }
    }
}

private extension UIImage {
    func resizedForNowPlayingArtwork(targetSize: CGSize) -> UIImage {
        guard targetSize.width > 0, targetSize.height > 0 else { return self }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    static func stationNowPlayingFallback(for station: Station) -> UIImage {
        let size = CGSize(width: 512, height: 512)
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        format.opaque = true

        let accent = UIColor(station.accentColor)
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let rect = CGRect(origin: .zero, size: size)
            UIColor(red: 0.05, green: 0.07, blue: 0.10, alpha: 1).setFill()
            context.fill(rect)

            accent.withAlphaComponent(0.9).setFill()
            context.cgContext.fillEllipse(in: rect.insetBy(dx: 88, dy: 88))

            UIColor.white.withAlphaComponent(0.92).setFill()
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 58, weight: .bold),
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraph
            ]
            let initials = station.name
                .split(separator: " ")
                .prefix(2)
                .compactMap(\.first)
                .map(String.init)
                .joined()
                .uppercased()
            let textRect = CGRect(x: 64, y: 220, width: 384, height: 72)
            initials.draw(with: textRect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes, context: nil)
        }
    }
}
#endif

struct MetadataResponse: Decodable {
    let stations: [String: AndonTrack]
}

struct StatsResponse: Decodable {
    let stations: [AndonStationDetail]
}
