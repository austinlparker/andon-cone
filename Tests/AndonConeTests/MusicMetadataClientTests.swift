import XCTest
@testable import AndonCone

final class MusicMetadataClientTests: XCTestCase {

    // MARK: - Cache key normalization

    func testCacheKeyLowercasesArtistAndTitle() {
        let mixed = AndonTrack(title: "Yesterday", artist: "The Beatles", online: true, error: nil)
        let upper = AndonTrack(title: "YESTERDAY", artist: "THE BEATLES", online: true, error: nil)
        XCTAssertEqual(
            MusicMetadataClient.cacheKey(for: mixed),
            MusicMetadataClient.cacheKey(for: upper),
            "Capitalization wobbles between metadata refreshes shouldn't fork the cache"
        )
    }

    func testCacheKeyDistinguishesDifferentTracks() {
        let a = AndonTrack(title: "Yesterday", artist: "The Beatles", online: true, error: nil)
        let b = AndonTrack(title: "Yesterday", artist: "Toni Braxton", online: true, error: nil)
        XCTAssertNotEqual(MusicMetadataClient.cacheKey(for: a), MusicMetadataClient.cacheKey(for: b))
    }

    func testCacheKeyShapeIsArtistPipeTitle() {
        let track = AndonTrack(title: "Yesterday", artist: "The Beatles", online: true, error: nil)
        XCTAssertEqual(MusicMetadataClient.cacheKey(for: track), "the beatles|yesterday")
    }

    // MARK: - Artist-overlap match filter

    private func song(artist: String, track: String = "Track") -> iTunesSong {
        iTunesSong(
            trackId: 0,
            trackName: track,
            artistName: artist,
            collectionName: nil,
            artworkUrl100: nil,
            trackViewUrl: nil,
            releaseDate: nil,
            primaryGenreName: nil
        )
    }

    func testBestMatchAcceptsExactArtist() {
        let result = MusicMetadataClient.bestMatch(
            in: [song(artist: "The Beatles")],
            matchingArtist: "The Beatles"
        )
        XCTAssertEqual(result?.artistName, "The Beatles")
    }

    func testBestMatchAcceptsCaseInsensitiveMatch() {
        let result = MusicMetadataClient.bestMatch(
            in: [song(artist: "the beatles")],
            matchingArtist: "The Beatles"
        )
        XCTAssertNotNil(result)
    }

    func testBestMatchAcceptsResultArtistContainingQuery() {
        // iTunes returns "The Beatles & Friends" for a query of "The Beatles".
        let result = MusicMetadataClient.bestMatch(
            in: [song(artist: "The Beatles & Friends")],
            matchingArtist: "The Beatles"
        )
        XCTAssertNotNil(result)
    }

    func testBestMatchAcceptsQueryContainingResultArtist() {
        // Live broadcast metadata says "The Beatles ft. Billy Preston" — the catalog
        // entry for the original is just "The Beatles".
        let result = MusicMetadataClient.bestMatch(
            in: [song(artist: "The Beatles")],
            matchingArtist: "The Beatles ft. Billy Preston"
        )
        XCTAssertNotNil(result)
    }

    func testBestMatchRejectsUnrelatedArtist() {
        let result = MusicMetadataClient.bestMatch(
            in: [song(artist: "Some Cover Band")],
            matchingArtist: "The Beatles"
        )
        XCTAssertNil(result, "Live/remix versions can return unrelated artists; those must be filtered out")
    }

    func testBestMatchPicksFirstAmongMultipleCandidates() {
        let results = [
            song(artist: "The Beatles", track: "First"),
            song(artist: "The Beatles", track: "Second"),
        ]
        let result = MusicMetadataClient.bestMatch(in: results, matchingArtist: "The Beatles")
        XCTAssertEqual(result?.trackName, "First")
    }

    func testBestMatchReturnsNilForEmptyResults() {
        XCTAssertNil(MusicMetadataClient.bestMatch(in: [], matchingArtist: "anything"))
    }

    // MARK: - iTunes artwork URL substitution

    func testHiResArtworkURLSubstitutes600x600() {
        let song = iTunesSong(
            trackId: 0,
            trackName: "t",
            artistName: "a",
            collectionName: nil,
            artworkUrl100: "https://example.com/art/100x100bb.jpg",
            trackViewUrl: nil,
            releaseDate: nil,
            primaryGenreName: nil
        )
        XCTAssertEqual(song.hiResArtworkURL?.absoluteString, "https://example.com/art/600x600bb.jpg")
    }

    func testHiResArtworkURLNilWhenNoArtwork() {
        let song = iTunesSong(
            trackId: 0,
            trackName: "t",
            artistName: "a",
            collectionName: nil,
            artworkUrl100: nil,
            trackViewUrl: nil,
            releaseDate: nil,
            primaryGenreName: nil
        )
        XCTAssertNil(song.hiResArtworkURL)
    }

    func testHiResArtworkURLLeavesUnrelatedSegmentsAlone() {
        // Apple's CDN sometimes serves URLs without the bb suffix — only the 100x100bb
        // token should be touched.
        let song = iTunesSong(
            trackId: 0,
            trackName: "t",
            artistName: "a",
            collectionName: nil,
            artworkUrl100: "https://example.com/art/200x200.jpg",
            trackViewUrl: nil,
            releaseDate: nil,
            primaryGenreName: nil
        )
        XCTAssertEqual(song.hiResArtworkURL?.absoluteString, "https://example.com/art/200x200.jpg")
    }
}
