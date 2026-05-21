import XCTest
@testable import AndonCone

@MainActor
final class RelativeTextTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testJustNowForCurrentMoment() {
        XCTAssertEqual(relativeText(for: now, now: now), "just now")
    }

    func testJustNowJustBeforeFiveSecondThreshold() {
        let date = now.addingTimeInterval(-4)
        XCTAssertEqual(relativeText(for: date, now: now), "just now")
    }

    func testJustNowForNearFutureWithinThreshold() {
        // The threshold uses `abs(...)`, so a date a couple of seconds in the future
        // also reads "just now" rather than the formatter's weird "in 2 sec." output.
        let date = now.addingTimeInterval(2)
        XCTAssertEqual(relativeText(for: date, now: now), "just now")
    }

    func testFallsThroughToFormatterAtOrPastFiveSeconds() {
        let date = now.addingTimeInterval(-30)
        let text = relativeText(for: date, now: now)
        XCTAssertNotEqual(text, "just now", "30s ago must not collapse to 'just now'")
        // Don't pin the literal wording — RelativeDateTimeFormatter is locale-sensitive.
        XCTAssertFalse(text.isEmpty)
    }
}
