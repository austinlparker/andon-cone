import XCTest
@testable import AndonCone

final class AndonTrackTests: XCTestCase {

    func testDisplayTitleReturnsTrimmedTitle() {
        let track = AndonTrack(title: "  Some Song  ", artist: "Artist", online: true, error: nil)
        XCTAssertEqual(track.displayTitle, "Some Song")
    }

    func testDisplayTitleFallsBackOnNil() {
        let track = AndonTrack(title: nil, artist: "Artist", online: true, error: nil)
        XCTAssertEqual(track.displayTitle, "Unknown title")
    }

    func testDisplayTitleFallsBackOnWhitespaceOnly() {
        let track = AndonTrack(title: "   \n\t  ", artist: "Artist", online: true, error: nil)
        XCTAssertEqual(track.displayTitle, "Unknown title")
    }

    func testDisplayTitleFallsBackOnEmptyString() {
        let track = AndonTrack(title: "", artist: "Artist", online: true, error: nil)
        XCTAssertEqual(track.displayTitle, "Unknown title")
    }

    func testDisplayArtistReturnsTrimmedArtist() {
        let track = AndonTrack(title: "Song", artist: "  Artist  ", online: true, error: nil)
        XCTAssertEqual(track.displayArtist, "Artist")
    }

    func testDisplayArtistFallsBackOnMissing() {
        let track = AndonTrack(title: "Song", artist: nil, online: true, error: nil)
        XCTAssertEqual(track.displayArtist, "Unknown artist")
    }
}
