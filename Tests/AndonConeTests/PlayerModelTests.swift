import XCTest
@testable import AndonCone

@MainActor
final class PlayerModelTests: XCTestCase {

    private func makeModel() -> PlayerModel {
        // Inject a stub so tests stay free of real URLSession allocation. Avoiding
        // `.shared` also keeps tests from leaking state into the production singleton.
        PlayerModel(apiClient: StubRadioAPI())
    }

    // MARK: - Station navigation

    func testNextStationAdvancesThroughCatalog() {
        let model = makeModel()
        XCTAssertEqual(model.currentStation, PlayerModel.stations[0])

        model.nextStation()
        XCTAssertEqual(model.currentStation, PlayerModel.stations[1])
    }

    func testNextStationWrapsFromLastToFirst() {
        let model = makeModel()
        model.selectStation(PlayerModel.stations.last!)
        model.nextStation()
        XCTAssertEqual(model.currentStation, PlayerModel.stations.first!)
    }

    func testPreviousStationWrapsFromFirstToLast() {
        let model = makeModel()
        XCTAssertEqual(model.currentStation, PlayerModel.stations.first!)
        model.previousStation()
        XCTAssertEqual(model.currentStation, PlayerModel.stations.last!)
    }

    func testSelectStationIsNoOpWhenSameStation() {
        let model = makeModel()
        let start = model.currentStation
        model.selectStation(start)
        XCTAssertEqual(model.currentStation, start)
    }

    // MARK: - Volume / mute

    func testSetVolumeClampsAboveOne() {
        let model = makeModel()
        model.setVolume(2.5)
        XCTAssertEqual(model.volume, 1.0)
        XCTAssertFalse(model.isMuted)
    }

    func testSetVolumeClampsBelowZero() {
        let model = makeModel()
        model.setVolume(-0.5)
        XCTAssertEqual(model.volume, 0.0)
        XCTAssertTrue(model.isMuted, "Zero volume should set the muted flag")
    }

    func testSetVolumeZeroEnablesMuteFlag() {
        let model = makeModel()
        model.setVolume(0)
        XCTAssertTrue(model.isMuted)
    }

    func testSetVolumeAboveZeroClearsMuteFlag() {
        let model = makeModel()
        model.setVolume(0)
        XCTAssertTrue(model.isMuted)

        model.setVolume(0.4)
        XCTAssertEqual(model.volume, 0.4, accuracy: 0.0001)
        XCTAssertFalse(model.isMuted)
    }

    func testToggleMuteRestoresPreviousVolume() {
        let model = makeModel()
        model.setVolume(0.7)
        model.toggleMute()
        XCTAssertTrue(model.isMuted)

        model.toggleMute()
        XCTAssertFalse(model.isMuted)
        XCTAssertEqual(model.volume, 0.7, accuracy: 0.0001)
    }

    func testToggleMuteRestoresAtLeastQuarterVolume() {
        // The unmute path floors the restored volume at 0.25 so a user who muted while
        // at near-zero volume gets audible output when they unmute.
        let model = makeModel()
        model.setVolume(0.05)
        model.toggleMute()
        XCTAssertTrue(model.isMuted)

        model.toggleMute()
        XCTAssertFalse(model.isMuted)
        XCTAssertEqual(model.volume, 0.25, accuracy: 0.0001)
    }

    // MARK: - Staleness threshold

    func testIsStaleReturnsTrueForNilLastRefresh() {
        XCTAssertTrue(PlayerModel.isStale(lastRefresh: nil))
    }

    func testIsStaleReturnsFalseJustBefore75Seconds() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let lastRefresh = now.addingTimeInterval(-74)
        XCTAssertFalse(PlayerModel.isStale(lastRefresh: lastRefresh, now: now))
    }

    func testIsStaleReturnsTrueJustAfter75Seconds() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let lastRefresh = now.addingTimeInterval(-76)
        XCTAssertTrue(PlayerModel.isStale(lastRefresh: lastRefresh, now: now))
    }
}
