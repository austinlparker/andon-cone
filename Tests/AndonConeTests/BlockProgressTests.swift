import XCTest
@testable import AndonCone

final class BlockProgressTests: XCTestCase {

    /// Reference "now" used by every test below — the helper formats relative
    /// to this clock so we get deterministic strings.
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func block(startMinutesAgo: Int, durationMinutes: Int) -> AndonStationDetail.Block {
        let startedAt = now.addingTimeInterval(TimeInterval(-startMinutesAgo * 60))
        return AndonStationDetail.Block(
            name: "Test Block",
            description: nil,
            imageUrl: nil,
            startedAt: startedAt,
            durationMinutes: durationMinutes
        )
    }

    func testMidBlockShowsElapsedOverTotal() {
        let b = block(startMinutesAgo: 12, durationMinutes: 60)
        XCTAssertEqual(b.progressText(relativeTo: now), "12m / 60m")
    }

    func testStartOfBlockShowsZeroOverTotal() {
        let b = block(startMinutesAgo: 0, durationMinutes: 30)
        XCTAssertEqual(b.progressText(relativeTo: now), "0m / 30m")
    }

    func testCompletedBlockShowsEnding() {
        let b = block(startMinutesAgo: 70, durationMinutes: 60)
        XCTAssertEqual(b.progressText(relativeTo: now), "60m block ending")
    }

    func testExactlyAtEndShowsEnding() {
        let b = block(startMinutesAgo: 60, durationMinutes: 60)
        XCTAssertEqual(b.progressText(relativeTo: now), "60m block ending")
    }

    func testFutureBlockShowsStartsPrefix() {
        let future = AndonStationDetail.Block(
            name: "Future",
            description: nil,
            imageUrl: nil,
            startedAt: now.addingTimeInterval(15 * 60),
            durationMinutes: 30
        )
        // Don't pin the exact relative wording (locale/version sensitive),
        // but it must be the "starts …" branch.
        XCTAssertTrue(future.progressText(relativeTo: now).hasPrefix("starts "))
    }
}
