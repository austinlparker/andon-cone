import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
typealias PlatformImage = NSImage
#endif

/// In-memory + disk cache for station artwork.
///
/// `AsyncImage` only caches via URLSession.shared, which leans on response headers and
/// memory-only. Station artwork is small, stable, and re-fetched on every station switch,
/// so a tiny dedicated cache makes the swap feel instant and eliminates redundant
/// network round trips.
@MainActor
final class ArtworkCache: ObservableObject {

    /// Bumped each time a new image lands in the cache so views re-render and pick up
    /// the value via `image(for:)`. Cheaper than publishing the whole dictionary.
    @Published private(set) var version: Int = 0

    private var images: [URL: PlatformImage] = [:]
    private var loadingURLs: Set<URL> = []
    private let cacheDirectory: URL
    private let session: URLSession

    init() {
        cacheDirectory = CacheSupport.cacheDirectory(named: "Artwork")
        // Longer timeouts than the metadata sessions — image bytes are bigger and slower.
        session = CacheSupport.makePollingSession(requestTimeout: 15, resourceTimeout: 30)
    }

    /// Synchronous lookup. Returns the cached image if either the memory or disk store
    /// has one; otherwise nil. Disk hits are promoted into memory on first access.
    func image(for url: URL) -> PlatformImage? {
        if let cached = images[url] { return cached }
        if let disk = loadFromDisk(url) {
            images[url] = disk
            return disk
        }
        return nil
    }

    /// Kick off a background fetch and disk-write if the image isn't already cached
    /// or in flight. Safe to call repeatedly — it deduplicates.
    func prefetch(_ url: URL) {
        guard images[url] == nil, !loadingURLs.contains(url) else { return }

        if let disk = loadFromDisk(url) {
            loadingURLs.insert(url)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.loadingURLs.remove(url)
                guard self.images[url] == nil else { return }
                self.images[url] = disk
                self.version &+= 1
            }
            return
        }

        loadingURLs.insert(url)
        Task { [weak self] in
            await self?.fetchAndStore(url)
        }
    }

    private func fetchAndStore(_ url: URL) async {
        defer { loadingURLs.remove(url) }
        do {
            let (data, _) = try await session.data(from: url)
            try? data.write(to: cacheFile(for: url), options: [.atomic])
            if let image = PlatformImage(data: data) {
                images[url] = image
                version &+= 1
            }
        } catch {
            // Silent: a placeholder will keep showing and the next prefetch will retry.
        }
    }

    private func loadFromDisk(_ url: URL) -> PlatformImage? {
        let path = cacheFile(for: url)
        guard let data = try? Data(contentsOf: path) else { return nil }
        return PlatformImage(data: data)
    }

    private func cacheFile(for url: URL) -> URL {
        cacheDirectory.appendingPathComponent(CacheSupport.cacheFilename(for: url.absoluteString))
    }
}
