import XCTest
@testable import AndonCone

final class CacheSupportTests: XCTestCase {

    func testCacheFilenameIsDeterministicAcrossInvocations() {
        let key = "https://example.com/artwork.png"
        XCTAssertEqual(CacheSupport.cacheFilename(for: key), CacheSupport.cacheFilename(for: key))
    }

    func testCacheFilenameDistinguishesKeys() {
        XCTAssertNotEqual(
            CacheSupport.cacheFilename(for: "a"),
            CacheSupport.cacheFilename(for: "b")
        )
    }

    func testCacheFilenameIs64CharLowercaseHex() {
        let name = CacheSupport.cacheFilename(for: "any input")
        XCTAssertEqual(name.count, 64, "SHA256 hex digest must be 64 chars")
        XCTAssertTrue(
            name.allSatisfy { $0.isHexDigit && (!$0.isLetter || $0.isLowercase) },
            "Filename must be filesystem-safe lowercase hex"
        )
    }

    func testCacheFilenameMatchesKnownSHA256() {
        // Pin against a well-known vector so we don't accidentally swap the digest
        // family and silently invalidate everyone's existing disk cache.
        let expected = "ca978112ca1bbdcafac231b39a23dc4da786eff8147c4e72b9807785afee48bb"
        XCTAssertEqual(CacheSupport.cacheFilename(for: "a"), expected)
    }

    func testCacheDirectoryEndsInAndonConeSubdirectory() {
        let dir = CacheSupport.cacheDirectory(named: "TestSubdir")
        XCTAssertTrue(
            dir.path.hasSuffix("AndonCone/TestSubdir"),
            "Cache dirs should live under ~/Library/Caches/AndonCone/<subdir>: \(dir.path)"
        )
    }

    func testCacheDirectoryIsCreated() {
        let subdir = "TestCreate-\(UUID().uuidString)"
        let dir = CacheSupport.cacheDirectory(named: subdir)
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir)
        XCTAssertTrue(exists)
        XCTAssertTrue(isDir.boolValue)
        try? FileManager.default.removeItem(at: dir)
    }
}
