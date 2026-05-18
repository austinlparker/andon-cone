import Foundation
import SwiftUI
#if os(iOS)
import MusicKit
#endif

/// Wraps the MusicKit Swift API for one specific feature on iOS: checking whether a
/// track is already in the user's Apple Music library, and adding it if not.
///
/// macOS deliberately uses the `appleMusicURL` escape hatch instead — Apple does not
/// expose `MusicLibrary.add()` on macOS, and the catalog/library request types we'd
/// need require macOS 14 while our minimum is macOS 13. So on macOS this service is
/// a no-op stub that always reports `.unavailable`.
@MainActor
final class MusicLibraryService: ObservableObject {

    enum LibraryStatus: Equatable, Sendable {
        case unknown                    // we've never inspected this track
        case checking                   // a library lookup is in flight
        case notInLibrary
        case inLibrary
        case adding                     // a write is in flight
        case notAuthorized              // user denied Apple Music access
        case noSubscription             // requires Apple Music subscription
        case unavailable                // MusicKit add path not present (macOS)
        case error(String)
    }

    @Published private(set) var statuses: [String: LibraryStatus] = [:]
    /// One-shot user-facing message for sheets/toasts. View clears it after presenting.
    @Published var pendingMessage: String?

    #if os(iOS)
    private var checkTasks: [String: Task<Void, Never>] = [:]
    #endif

    func status(for trackID: String) -> LibraryStatus {
        statuses[trackID] ?? .unknown
    }

    func dismissMessage() { pendingMessage = nil }

    /// Lightweight passive check — does not trigger an auth prompt. If the user hasn't
    /// authorized yet, we stay in `.notInLibrary` so the add button still works on tap.
    func refreshStatus(for trackID: String) {
        #if os(iOS)
        if statuses[trackID] == .inLibrary { return }
        if checkTasks[trackID] != nil { return }

        guard MusicAuthorization.currentStatus == .authorized else {
            statuses[trackID] = .notInLibrary
            return
        }

        statuses[trackID] = .checking
        checkTasks[trackID] = Task { [weak self] in
            await self?.performStatusCheck(trackID: trackID)
            self?.checkTasks[trackID] = nil
        }
        #else
        statuses[trackID] = .unavailable
        #endif
    }

    /// Add to library. Triggers the auth prompt if needed; handles subscription failure
    /// gracefully by routing to `pendingMessage` instead of crashing or going silent.
    func addToLibrary(trackID: String) {
        #if os(iOS)
        Task { [weak self] in
            await self?.performAdd(trackID: trackID)
        }
        #else
        statuses[trackID] = .unavailable
        #endif
    }

    #if os(iOS)
    private func performStatusCheck(trackID: String) async {
        do {
            let id = MusicItemID(trackID)
            var request = MusicLibraryRequest<Song>()
            request.filter(matching: \.id, equalTo: id)
            let response = try await request.response()
            statuses[trackID] = response.items.isEmpty ? .notInLibrary : .inLibrary
        } catch {
            // A failed read shouldn't degrade the UI to a hard-error state.
            statuses[trackID] = .notInLibrary
            NSLog("Andon Cone library status check failed: %@", error.localizedDescription)
        }
    }

    private func performAdd(trackID: String) async {
        guard await ensureAuthorized(for: trackID) else { return }

        statuses[trackID] = .adding

        do {
            let id = MusicItemID(trackID)
            let request = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: id)
            let response = try await request.response()

            guard let song = response.items.first else {
                statuses[trackID] = .error("Track not in Apple Music catalog")
                pendingMessage = "We couldn't find this track in Apple Music."
                return
            }

            try await MusicLibrary.shared.add(song)
            statuses[trackID] = .inLibrary
        } catch {
            handleAddError(error, trackID: trackID)
        }
    }

    private func ensureAuthorized(for trackID: String) async -> Bool {
        switch MusicAuthorization.currentStatus {
        case .authorized:
            return true
        case .notDetermined:
            let result = await MusicAuthorization.request()
            if result == .authorized { return true }
            statuses[trackID] = .notAuthorized
            pendingMessage = "Apple Music access is needed to save tracks."
            return false
        case .denied, .restricted:
            statuses[trackID] = .notAuthorized
            pendingMessage = "Apple Music access was denied. Enable it in Settings to save tracks."
            return false
        @unknown default:
            statuses[trackID] = .unavailable
            return false
        }
    }

    private func handleAddError(_ error: Error, trackID: String) {
        let description = error.localizedDescription
        // MusicKit surfaces "subscription required" as either a typed or string error
        // depending on flow — fall back to a substring check to be robust.
        if description.localizedCaseInsensitiveContains("subscri") {
            statuses[trackID] = .noSubscription
            pendingMessage = "An Apple Music subscription is required to save tracks."
        } else {
            statuses[trackID] = .error(description)
            pendingMessage = description
            NSLog("Andon Cone add-to-library failed: %@", description)
        }
    }
    #endif
}
