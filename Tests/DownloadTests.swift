import XCTest
@testable import StremioTV

// Désambiguïsation (comme LibraryTests) : le host de test peut exposer d'autres
// modules ; on force nos types applicatifs.
private typealias DownloadItem = StremioTV.DownloadItem

/// Logique pure du mode hors-ligne : progression/état d'un téléchargement,
/// éligibilité des flux, aller-retour du manifeste (sans réseau ni MainActor).
final class DownloadTests: XCTestCase {

    private func makeItem(metaId: String = "tt0111161", status: DownloadStatus = .queued) -> DownloadItem {
        DownloadItem(
            metaId: metaId, type: "movie", videoId: metaId,
            name: "Shawshank", videoTitle: "Shawshank", poster: nil,
            streamTitle: "RealDebrid 1080p",
            sourceURL: URL(string: "https://cdn.example/v.mp4")!,
            fileName: "\(metaId).mp4", status: status,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    // MARK: Progression / état

    func testProgressIsZeroWithoutTotal() {
        var item = makeItem()
        item.bytesReceived = 1_000
        item.totalBytes = 0
        XCTAssertEqual(item.progress, 0)
    }

    func testProgressMidAndClamped() {
        var item = makeItem()
        item.totalBytes = 1_000
        item.bytesReceived = 250
        XCTAssertEqual(item.progress, 0.25, accuracy: 0.0001)
        item.bytesReceived = 5_000            // > total ⇒ borné à 1
        XCTAssertEqual(item.progress, 1)
    }

    func testDerivedFlags() {
        XCTAssertTrue(makeItem(status: .completed).isPlayable)
        XCTAssertFalse(makeItem(status: .downloading).isPlayable)
        XCTAssertTrue(makeItem(status: .downloading).isActive)
        XCTAssertTrue(makeItem(status: .queued).isActive)
        XCTAssertFalse(makeItem(status: .paused).isActive)
    }

    func testStableIdFromMedia() {
        XCTAssertEqual(DownloadItem.makeId(metaId: "tt1", videoId: "tt1:2:3"), "tt1|tt1:2:3")
        XCTAssertEqual(makeItem().id, "tt0111161|tt0111161")
    }

    func testStatusCodableRoundTrip() throws {
        for status in [DownloadStatus.queued, .downloading, .paused, .completed, .failed] {
            let data = try JSONEncoder().encode(status)
            XCTAssertEqual(try JSONDecoder().decode(DownloadStatus.self, from: data), status)
        }
    }

    // MARK: Éligibilité des flux

    func testManifestStreamsAreNotDownloadable() {
        for s in ["https://x/v.m3u8", "https://x/v.m3u", "https://x/v.mpd",
                  "https://x/V.M3U8", "https://x/v.m3u8?token=abc"] {
            XCTAssertFalse(StreamDownloadRules.isLikelyDownloadable(URL(string: s)!), s)
        }
    }

    func testProgressiveStreamsAreDownloadable() {
        for s in ["https://x/v.mp4", "https://x/v.mkv", "https://x/v.mov", "https://x/stream"] {
            XCTAssertTrue(StreamDownloadRules.isLikelyDownloadable(URL(string: s)!), s)
        }
    }

    func testContainerExtensionMapping() {
        XCTAssertEqual(StreamDownloadRules.containerExtension(for: URL(string: "https://x/v.mkv")!), "mkv")
        XCTAssertEqual(StreamDownloadRules.containerExtension(for: URL(string: "https://x/v.bin")!), "mp4")
        XCTAssertEqual(StreamDownloadRules.containerExtension(forMime: "video/x-matroska"), "mkv")
        XCTAssertEqual(StreamDownloadRules.containerExtension(forMime: "video/mp4"), "mp4")
        XCTAssertNil(StreamDownloadRules.containerExtension(forMime: "text/plain"))
    }

    // MARK: Manifeste (persistance)

    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("dltest-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testManifestRoundTrip() throws {
        let url = tempDir().appendingPathComponent("manifest.json")
        var a = makeItem(status: .completed)
        a.totalBytes = 2_000; a.bytesReceived = 2_000; a.resumeOffsetMs = 42_000
        a.subtitleFileName = "tt0111161.srt"; a.subtitleLang = "fr"
        var b = makeItem(metaId: "tt0068646", status: .failed)
        b.failureReason = "Flux HLS/DASH — non téléchargeable pour le hors-ligne."

        try DownloadManifest.save([a, b], to: url)
        let loaded = DownloadManifest.load(from: url)

        XCTAssertEqual(loaded.count, 2)
        let ra = try XCTUnwrap(loaded.first { $0.id == a.id })
        XCTAssertEqual(ra.status, .completed)
        XCTAssertEqual(ra.totalBytes, 2_000)
        XCTAssertEqual(ra.resumeOffsetMs, 42_000)
        XCTAssertEqual(ra.subtitleFileName, "tt0111161.srt")
        XCTAssertEqual(ra.subtitleLang, "fr")
        XCTAssertEqual(ra.createdAt, a.createdAt)
        let rb = try XCTUnwrap(loaded.first { $0.id == b.id })
        XCTAssertEqual(rb.status, .failed)
        XCTAssertEqual(rb.failureReason, b.failureReason)
    }

    func testManifestLoadMissingOrCorruptReturnsEmpty() throws {
        let dir = tempDir()
        XCTAssertTrue(DownloadManifest.load(from: dir.appendingPathComponent("nope.json")).isEmpty)
        let corrupt = dir.appendingPathComponent("corrupt.json")
        try Data("{ not json".utf8).write(to: corrupt)
        XCTAssertTrue(DownloadManifest.load(from: corrupt).isEmpty)
    }

    // MARK: Chemins

    func testSanitizeMakesFilesystemSafeNames() {
        XCTAssertEqual(DownloadPaths.sanitize("tt1|tt1:2:3"), "tt1_tt1_2_3")
        XCTAssertFalse(DownloadPaths.sanitize("a/b:c").contains("/"))
    }
}
