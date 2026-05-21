import XCTest
@testable import AndonCone

final class EnrichedTrackTests: XCTestCase {

    private func track(
        appleMusicURL: URL? = nil,
        releaseDate: Date? = nil
    ) -> EnrichedTrack {
        EnrichedTrack(
            trackID: "1",
            trackName: "Yesterday",
            artistName: "The Beatles",
            albumTitle: "Help!",
            artworkURL: nil,
            appleMusicURL: appleMusicURL,
            releaseDate: releaseDate,
            genre: nil
        )
    }

    // MARK: - musicAppURL scheme rewrite

    func testMusicAppURLRewritesAppleMusicHostToMusicScheme() {
        let track = track(appleMusicURL: URL(string: "https://music.apple.com/us/album/help/123"))
        XCTAssertEqual(track.musicAppURL?.absoluteString, "music://music.apple.com/us/album/help/123")
    }

    func testMusicAppURLPreservesQueryStringDuringRewrite() {
        let track = track(appleMusicURL: URL(string: "https://music.apple.com/us/album/help/123?i=456"))
        XCTAssertEqual(track.musicAppURL?.absoluteString, "music://music.apple.com/us/album/help/123?i=456")
    }

    func testMusicAppURLFallsThroughForUnknownHost() {
        let url = URL(string: "https://example.com/song")!
        let track = track(appleMusicURL: url)
        XCTAssertEqual(track.musicAppURL, url)
    }

    func testMusicAppURLFallsThroughForHTTPScheme() {
        // http (not https) shouldn't be rewritten — defensive guard against unexpected schemes.
        let url = URL(string: "http://music.apple.com/us/album/help/123")!
        let track = track(appleMusicURL: url)
        XCTAssertEqual(track.musicAppURL, url)
    }

    func testMusicAppURLNilWhenAppleMusicURLNil() {
        let track = track(appleMusicURL: nil)
        XCTAssertNil(track.musicAppURL)
    }

    // MARK: - releaseYear

    func testReleaseYearFormatsKnownDate() {
        var components = DateComponents()
        components.year = 1965
        components.month = 8
        components.day = 6
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: components)!
        let track = track(releaseDate: date)
        XCTAssertEqual(track.releaseYear, "1965")
    }

    func testReleaseYearNilWhenNoDate() {
        XCTAssertNil(track(releaseDate: nil).releaseYear)
    }

    // MARK: - albumDisplayText

    func testAlbumDisplayTextIncludesYearWhenKnown() {
        var components = DateComponents()
        components.year = 1972
        components.month = 3
        components.day = 1
        let date = Calendar(identifier: .gregorian).date(from: components)!
        let t = track(releaseDate: date)
        XCTAssertEqual(t.albumDisplayText, "Help! · 1972")
    }

    func testAlbumDisplayTextOmitsYearWhenUnknown() {
        XCTAssertEqual(track(releaseDate: nil).albumDisplayText, "Help!")
    }
}
