import XCTest
@testable import AndonCone

final class MetadataDecodingTests: XCTestCase {

    private lazy var decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    func testTweetMapsSnakeCaseKeys() throws {
        let json = """
        {
            "id": "abc123",
            "content": "live now",
            "posted_at": "2026-05-15T18:00:00Z",
            "tweet_url": "https://example.com/t/abc123",
            "is_own_tweet": true,
            "author": { "username": "user", "name": "User Name" }
        }
        """.data(using: .utf8)!

        let tweet = try decoder.decode(AndonStationDetail.Tweet.self, from: json)

        XCTAssertEqual(tweet.id, "abc123")
        XCTAssertEqual(tweet.content, "live now")
        XCTAssertEqual(tweet.tweetUrl, "https://example.com/t/abc123")
        XCTAssertEqual(tweet.isOwnTweet, true)
        XCTAssertEqual(tweet.author.username, "user")
        XCTAssertEqual(tweet.author.name, "User Name")
        XCTAssertEqual(tweet.tweetURL?.absoluteString, "https://example.com/t/abc123")
    }

    func testTweetTolerantOfMissingIsOwnTweet() throws {
        let json = """
        {
            "id": "x",
            "content": "y",
            "posted_at": "2026-05-15T18:00:00Z",
            "tweet_url": "https://example.com/x",
            "author": { "username": "u", "name": "n" }
        }
        """.data(using: .utf8)!

        let tweet = try decoder.decode(AndonStationDetail.Tweet.self, from: json)
        XCTAssertNil(tweet.isOwnTweet)
    }

    func testAndonTrackDecodesPartialPayload() throws {
        let json = """
        { "title": "Track", "artist": "Artist" }
        """.data(using: .utf8)!

        let track = try decoder.decode(AndonTrack.self, from: json)
        XCTAssertEqual(track.title, "Track")
        XCTAssertEqual(track.artist, "Artist")
        XCTAssertNil(track.online)
        XCTAssertNil(track.error)
    }

    func testSongIdentifiableComposesNameAndArtist() {
        let song = AndonStationDetail.ContentStats.Song(name: "A", artist: "B", count: 3)
        XCTAssertEqual(song.id, "A|B")
    }

    @MainActor
    func testStationCatalogHasUniqueIDs() {
        let ids = Set(PlayerModel.stations.map(\.id))
        XCTAssertEqual(ids.count, PlayerModel.stations.count)
    }
}
