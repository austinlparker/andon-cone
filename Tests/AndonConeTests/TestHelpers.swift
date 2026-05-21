import Foundation
@testable import AndonCone

/// Test stub for `RadioAPI`. Each fetch returns whatever the test set up, or throws
/// a controllable error. Lets tests drive `performMetadataRefresh` deterministically
/// without hitting the live Andon endpoints, and lets `PlayerModel` tests construct
/// instances that don't spin up a real URLSession through the default `RadioAPIClient()`.
///
/// `@unchecked Sendable` is acceptable here because all consumers are `@MainActor` test
/// classes and XCTest runs methods serially — the stub's mutable result properties are
/// only touched from the main actor. If a parallel test runner or off-main `Task.detached`
/// in tests is ever introduced, this needs to gain a lock.
final class StubRadioAPI: RadioAPI, @unchecked Sendable {
    enum StubError: Error, Equatable {
        case forced(String)
    }

    var metadataResult: Result<MetadataResponse, Error> = .success(MetadataResponse(stations: [:]))
    var statsResult: Result<StatsResponse, Error> = .success(StatsResponse(stations: []))

    func fetchMetadata() async throws -> MetadataResponse {
        try metadataResult.get()
    }

    func fetchStats() async throws -> StatsResponse {
        try statsResult.get()
    }

    #if os(iOS)
    func fetchArtwork(from url: URL) async throws -> NowPlayingArtwork {
        // Tests in this suite don't exercise the artwork path.
        throw StubError.forced("fetchArtwork not stubbed")
    }
    #endif
}
