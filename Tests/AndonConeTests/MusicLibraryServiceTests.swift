import XCTest
@testable import AndonCone

final class MusicLibraryServiceTests: XCTestCase {

    func testClassifyAddErrorMapsSubscriptionRequiredToNoSubscription() {
        // Canonical exact phrasing MusicKit uses.
        XCTAssertEqual(
            MusicLibraryService.classifyAddError(description: "Subscription required"),
            .noSubscription
        )
    }

    func testClassifyAddErrorMatchesSubscriptionSubstringCaseInsensitively() {
        // MusicKit varies wording across iOS versions and failure paths. The classifier
        // is intentionally lax — any case of "subscri" hits noSubscription.
        XCTAssertEqual(
            MusicLibraryService.classifyAddError(description: "This requires an Apple Music subscription."),
            .noSubscription
        )
        XCTAssertEqual(
            MusicLibraryService.classifyAddError(description: "SUBSCRIPTION required"),
            .noSubscription
        )
    }

    func testClassifyAddErrorMapsUnrelatedErrorToErrorCase() {
        XCTAssertEqual(
            MusicLibraryService.classifyAddError(description: "Network unavailable"),
            .error("Network unavailable")
        )
    }

    func testClassifyAddErrorPreservesOriginalDescription() {
        let description = "The operation couldn't be completed. (MPErrorDomain error 1.)"
        XCTAssertEqual(
            MusicLibraryService.classifyAddError(description: description),
            .error(description)
        )
    }
}
