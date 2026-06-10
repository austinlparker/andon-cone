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

    func testSongUsesFallbackForMissingArtist() {
        let song = AndonStationDetail.ContentStats.Song(name: "Station Jingle", artist: nil, count: 3)
        XCTAssertEqual(song.displayArtist, "Unknown artist")
        XCTAssertEqual(song.id, "Station Jingle|Unknown artist")
    }

    @MainActor
    func testStationCatalogHasUniqueIDs() {
        let ids = Set(PlayerModel.stations.map(\.id))
        XCTAssertEqual(ids.count, PlayerModel.stations.count)
    }

    func testBlockDecodesISO8601Date() throws {
        let json = """
        {
            "name": "Hour of Power",
            "description": "Synth deep cuts",
            "imageUrl": "https://example.com/block.png",
            "startedAt": "2026-05-15T18:00:00Z",
            "durationMinutes": 60
        }
        """.data(using: .utf8)!

        let block = try decoder.decode(AndonStationDetail.Block.self, from: json)
        XCTAssertEqual(block.name, "Hour of Power")
        XCTAssertEqual(block.description, "Synth deep cuts")
        XCTAssertEqual(block.imageUrl, "https://example.com/block.png")
        XCTAssertEqual(block.durationMinutes, 60)
        XCTAssertEqual(block.id, block.startedAt)
    }

    func testContentStatsDecodesSongsAndGenres() throws {
        let json = """
        {
            "topSongsWeek": [
                { "name": "Song A", "artist": "Artist A", "count": 7 },
                { "name": "Station Jingle", "artist": null, "count": 3 }
            ],
            "topGenres": [
                { "name": "Synthwave", "count": 14, "percentage": 70 },
                { "name": "Ambient", "count": 6, "percentage": 30 }
            ]
        }
        """.data(using: .utf8)!

        let stats = try decoder.decode(AndonStationDetail.ContentStats.self, from: json)
        XCTAssertEqual(stats.topSongsWeek?.count, 2)
        XCTAssertEqual(stats.topSongsWeek?.first?.id, "Song A|Artist A")
        XCTAssertEqual(stats.topSongsWeek?.last?.displayArtist, "Unknown artist")
        XCTAssertEqual(stats.topGenres?.count, 2)
        XCTAssertEqual(stats.topGenres?.first?.percentage, 70)
        XCTAssertEqual(stats.topGenres?.first?.id, "Synthwave")
    }

    func testAndonStationDetailDecodesRealisticPayload() throws {
        // Trimmed but realistic shape of one entry in /api/public/radio/stats.stations.
        let json = """
        {
            "id": "aab4d149-92fa-4386-9c1e-d938ecb66ee3",
            "imageUrl": "https://example.com/station.png",
            "subtitle": "Hosted by Claude",
            "primaryModel": "claude-opus-4.7",
            "ttsProvider": "ElevenLabs",
            "ttsModel": "eleven-multilingual",
            "stats": {
                "currentListeners": 42,
                "totalListeners": 1337,
                "popularity": 88,
                "totalListenHours": 2500
            },
            "currentBlock": {
                "name": "Now Block",
                "description": null,
                "imageUrl": null,
                "startedAt": "2026-05-15T17:00:00Z",
                "durationMinutes": 60
            },
            "upcomingBlocks": [
                {
                    "name": "Next Block",
                    "description": "Up next",
                    "imageUrl": null,
                    "startedAt": "2026-05-15T18:00:00Z",
                    "durationMinutes": 30
                }
            ],
            "tweets": [
                {
                    "id": "t1",
                    "content": "On air",
                    "posted_at": "2026-05-15T17:30:00Z",
                    "tweet_url": "https://example.com/t/t1",
                    "is_own_tweet": true,
                    "author": { "username": "andon", "name": "Andon FM" }
                }
            ],
            "contentStats": {
                "topSongsWeek": [
                    { "name": "Hit", "artist": "Band", "count": 9 }
                ],
                "topGenres": [
                    { "name": "Synthwave", "count": 9, "percentage": 100 }
                ]
            }
        }
        """.data(using: .utf8)!

        let detail = try decoder.decode(AndonStationDetail.self, from: json)
        XCTAssertEqual(detail.id, "aab4d149-92fa-4386-9c1e-d938ecb66ee3")
        XCTAssertEqual(detail.imageURL?.absoluteString, "https://example.com/station.png")
        XCTAssertEqual(detail.subtitle, "Hosted by Claude")
        XCTAssertEqual(detail.stats?.currentListeners, 42)
        XCTAssertEqual(detail.stats?.totalListenHours, 2500)
        XCTAssertEqual(detail.currentBlock?.name, "Now Block")
        XCTAssertNil(detail.currentBlock?.description)
        XCTAssertEqual(detail.upcomingBlocks?.count, 1)
        XCTAssertEqual(detail.upcomingBlocks?.first?.durationMinutes, 30)
        XCTAssertEqual(detail.tweets?.count, 1)
        XCTAssertEqual(detail.tweets?.first?.isOwnTweet, true)
        XCTAssertEqual(detail.contentStats?.topSongsWeek?.first?.name, "Hit")
        XCTAssertEqual(detail.contentStats?.topGenres?.first?.percentage, 100)
    }

    func testAndonStationDetailIsTolerantOfMissingOptionalFields() throws {
        // Stations sometimes return with only id + stats while a block hasn't been
        // assigned yet — none of the optional collections should fail to decode.
        let json = """
        {
            "id": "abc",
            "imageUrl": null,
            "subtitle": null,
            "primaryModel": null,
            "ttsProvider": null,
            "ttsModel": null,
            "stats": null,
            "currentBlock": null,
            "upcomingBlocks": null,
            "tweets": null,
            "contentStats": null
        }
        """.data(using: .utf8)!

        let detail = try decoder.decode(AndonStationDetail.self, from: json)
        XCTAssertEqual(detail.id, "abc")
        XCTAssertNil(detail.imageURL)
        XCTAssertNil(detail.stats)
        XCTAssertNil(detail.currentBlock)
        XCTAssertNil(detail.upcomingBlocks)
        XCTAssertNil(detail.tweets)
        XCTAssertNil(detail.contentStats)
    }
}
