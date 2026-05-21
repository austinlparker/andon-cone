import Foundation
import CryptoKit

/// Shared helpers used by `ArtworkCache`, `MusicMetadataClient`, and `RadioAPIClient`
/// to construct the cache directories, hashed filenames, and URLSession configs they
/// all need. Centralized so timeouts, waitsForConnectivity behavior, and the cache
/// root layout under `~/Library/Caches/AndonCone/` stay consistent.
enum CacheSupport {

    /// Returns `~/Library/Caches/AndonCone/<subdirectory>/`, creating it if missing.
    /// Falls back to the system temp directory when the caches directory can't be
    /// resolved (sandboxed contexts, transient FS errors) — the disk cache stays
    /// best-effort either way.
    static func cacheDirectory(named subdirectory: String) -> URL {
        let fm = FileManager.default
        let caches = (try? fm.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fm.temporaryDirectory
        let dir = caches.appendingPathComponent("AndonCone/\(subdirectory)", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// SHA256 of the key as a 64-character lowercase hex string. Filename-safe and
    /// stable across processes, so the same key always points at the same file.
    static func cacheFilename(for key: String) -> String {
        let digest = SHA256.hash(data: Data(key.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// URLSession config tuned for polling-style fetches: short request timeout,
    /// slightly longer resource timeout, and `waitsForConnectivity` so a brief blip
    /// queues a retry rather than failing immediately.
    ///
    /// `disablesURLCache` is for endpoints we always want fresh (metadata polling);
    /// artwork/track-detail sessions leave URLCache enabled so HTTP caching can help.
    /// The artwork path uses longer timeouts (15/30) since image responses are larger.
    static func makePollingSession(
        requestTimeout: TimeInterval = 10,
        resourceTimeout: TimeInterval = 20,
        disablesURLCache: Bool = false
    ) -> URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = requestTimeout
        config.timeoutIntervalForResource = resourceTimeout
        config.waitsForConnectivity = true
        if disablesURLCache {
            config.urlCache = nil
        }
        return URLSession(configuration: config)
    }
}
