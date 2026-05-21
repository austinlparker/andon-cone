import XCTest
@testable import AndonCone

@MainActor
final class PlayerModelRefreshTests: XCTestCase {

    private func detail(id: String, listeners: Int) -> AndonStationDetail {
        AndonStationDetail(
            id: id,
            imageUrl: nil,
            subtitle: nil,
            primaryModel: nil,
            ttsProvider: nil,
            ttsModel: nil,
            stats: AndonStationDetail.Stats(
                currentListeners: listeners,
                totalListeners: nil,
                popularity: nil,
                totalListenHours: nil
            ),
            currentBlock: nil,
            upcomingBlocks: nil,
            tweets: nil,
            contentStats: nil
        )
    }

    private func track(title: String) -> AndonTrack {
        AndonTrack(title: title, artist: "Artist", online: true, error: nil)
    }

    // MARK: - applyStats merge behavior

    func testRefreshMergesStatsWithoutDroppingMissingStations() async {
        let api = StubRadioAPI()
        let model = PlayerModel(apiClient: api)
        let stationA = PlayerModel.stations[0].id
        let stationB = PlayerModel.stations[1].id

        // First refresh: both stations present.
        api.statsResult = .success(StatsResponse(stations: [
            detail(id: stationA, listeners: 10),
            detail(id: stationB, listeners: 20),
        ]))
        await model.performMetadataRefresh(force: true)
        XCTAssertEqual(model.detailsByID[stationA]?.stats?.currentListeners, 10)
        XCTAssertEqual(model.detailsByID[stationB]?.stats?.currentListeners, 20)

        // Second refresh: stationA temporarily missing. stationB updates; stationA
        // should NOT blink out of the UI.
        api.statsResult = .success(StatsResponse(stations: [
            detail(id: stationB, listeners: 25),
        ]))
        await model.performMetadataRefresh(force: true)
        XCTAssertEqual(model.detailsByID[stationA]?.stats?.currentListeners, 10,
                       "stationA must persist when missing from a later refresh")
        XCTAssertEqual(model.detailsByID[stationB]?.stats?.currentListeners, 25)
    }

    func testRefreshMergesTracksWithoutDroppingMissingStations() async {
        let api = StubRadioAPI()
        let model = PlayerModel(apiClient: api)
        let stationA = PlayerModel.stations[0].id
        let stationB = PlayerModel.stations[1].id

        api.metadataResult = .success(MetadataResponse(stations: [
            stationA: track(title: "Track A1"),
            stationB: track(title: "Track B1"),
        ]))
        await model.performMetadataRefresh(force: true)
        XCTAssertEqual(model.tracksByID[stationA]?.title, "Track A1")
        XCTAssertEqual(model.tracksByID[stationB]?.title, "Track B1")

        api.metadataResult = .success(MetadataResponse(stations: [
            stationB: track(title: "Track B2"),
        ]))
        await model.performMetadataRefresh(force: true)
        XCTAssertEqual(model.tracksByID[stationA]?.title, "Track A1",
                       "stationA track must persist when missing from a later refresh")
        XCTAssertEqual(model.tracksByID[stationB]?.title, "Track B2")
    }

    // MARK: - Partial failure semantics

    func testRefreshTreatsMetadataSuccessAndStatsFailureAsPartialSuccess() async {
        let api = StubRadioAPI()
        let stationA = PlayerModel.stations[0].id

        api.metadataResult = .success(MetadataResponse(stations: [
            stationA: track(title: "Track A"),
        ]))
        api.statsResult = .failure(StubRadioAPI.StubError.forced("boom"))

        let model = PlayerModel(apiClient: api)
        await model.performMetadataRefresh(force: true)

        XCTAssertEqual(model.tracksByID[stationA]?.title, "Track A",
                       "Metadata fetch succeeded — tracks should be populated")
        XCTAssertNotNil(model.lastMetadataRefresh,
                        "anySuccess=true must set lastMetadataRefresh")
        XCTAssertEqual(model.metadataErrorMessage?.hasPrefix("stats:"), true,
                       "metadataErrorMessage should carry the stats failure context")
        XCTAssertFalse(model.metadataIsStale,
                       "Partial success isn't stale — only total failure is")
    }

    func testRefreshTreatsStatsSuccessAndMetadataFailureAsPartialSuccess() async {
        let api = StubRadioAPI()
        let stationA = PlayerModel.stations[0].id

        api.metadataResult = .failure(StubRadioAPI.StubError.forced("boom"))
        api.statsResult = .success(StatsResponse(stations: [detail(id: stationA, listeners: 7)]))

        let model = PlayerModel(apiClient: api)
        await model.performMetadataRefresh(force: true)

        XCTAssertEqual(model.detailsByID[stationA]?.stats?.currentListeners, 7)
        XCTAssertNotNil(model.lastMetadataRefresh)
        XCTAssertEqual(model.metadataErrorMessage?.hasPrefix("metadata:"), true)
        XCTAssertFalse(model.metadataIsStale)
    }

    // MARK: - Total-failure semantics

    func testRefreshMarksMetadataStaleWhenBothCallsFail() async {
        let api = StubRadioAPI()
        api.metadataResult = .failure(StubRadioAPI.StubError.forced("m boom"))
        api.statsResult = .failure(StubRadioAPI.StubError.forced("s boom"))

        let model = PlayerModel(apiClient: api)
        await model.performMetadataRefresh(force: true)

        XCTAssertTrue(model.metadataIsStale,
                      "Both calls failing must mark metadata stale even before the threshold")
        XCTAssertNotNil(model.metadataErrorMessage)
    }

    // MARK: - Cancellation semantics
    //
    // Cancellation isn't a refresh failure — it means the call was aborted externally
    // (app backgrounded, manual refresh triggered while polling was in flight). A
    // cancellation alongside a sibling success must still commit the success.

    func testRefreshCommitsTimestampWhenMetadataSucceedsAndStatsIsCancelled() async {
        let api = StubRadioAPI()
        let stationA = PlayerModel.stations[0].id
        api.metadataResult = .success(MetadataResponse(stations: [stationA: track(title: "Track A")]))
        api.statsResult = .failure(URLError(.cancelled))

        let model = PlayerModel(apiClient: api)
        await model.performMetadataRefresh(force: true)

        XCTAssertEqual(model.tracksByID[stationA]?.title, "Track A")
        XCTAssertNotNil(model.lastMetadataRefresh,
                        "Metadata success must commit the timestamp even when the sibling was cancelled")
        XCTAssertNil(model.metadataErrorMessage,
                     "Cancellation must not surface as an error")
        XCTAssertFalse(model.metadataIsStale)
    }

    func testRefreshCommitsTimestampWhenStatsSucceedsAndMetadataIsCancelled() async {
        let api = StubRadioAPI()
        let stationA = PlayerModel.stations[0].id
        api.metadataResult = .failure(CancellationError())
        api.statsResult = .success(StatsResponse(stations: [detail(id: stationA, listeners: 9)]))

        let model = PlayerModel(apiClient: api)
        await model.performMetadataRefresh(force: true)

        XCTAssertEqual(model.detailsByID[stationA]?.stats?.currentListeners, 9)
        XCTAssertNotNil(model.lastMetadataRefresh)
        XCTAssertNil(model.metadataErrorMessage)
        XCTAssertFalse(model.metadataIsStale)
    }

    func testRefreshLeavesErrorMessageUntouchedWhenBothCallsAreCancelled() async {
        let api = StubRadioAPI()
        api.metadataResult = .failure(URLError(.cancelled))
        api.statsResult = .failure(CancellationError())

        let model = PlayerModel(apiClient: api)
        await model.performMetadataRefresh(force: true)

        XCTAssertNil(model.metadataErrorMessage,
                     "All-cancelled refresh must not surface a fake 'Metadata refresh failed' message")
        XCTAssertNil(model.lastMetadataRefresh)
        // metadataIsStale ends up true via updateMetadataStaleness seeing a nil lastRefresh,
        // which accurately reflects "no successful refresh has happened yet" — not a fabricated failure.
        XCTAssertTrue(model.metadataIsStale)
    }
}
