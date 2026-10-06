import XCTest
@testable import StremioTV

/// Logique de focus des écrans asynchrones (sans UI) : chaque phase doit
/// désigner une cible focusable dans la page.
final class FocusLogicTests: XCTestCase {

    func testLoadPhase() {
        XCTAssertEqual(LoadPhase(hasContent: false, isFinished: false), .loading)
        XCTAssertEqual(LoadPhase(hasContent: false, isFinished: true), .empty)
        XCTAssertEqual(LoadPhase(hasContent: true, isFinished: false), .populated)
        XCTAssertEqual(LoadPhase(hasContent: true, isFinished: true), .populated)
    }

    func testLoadingLeavesFocusOnCancel() throws {
        let list = try streams()
        XCTAssertNil(StreamsFocusTarget.after(.loading, streams: list))
    }

    func testEmptyFocusesRetry() {
        XCTAssertEqual(StreamsFocusTarget.after(.empty, streams: []), .retry)
    }

    func testPopulatedFocusesFirstPlayableStream() throws {
        let list = try streams()
        XCTAssertEqual(StreamsFocusTarget.after(.populated, streams: list), .stream(list[1].id))
    }

    /// Liste 100 % torrents : le 1er flux reste une cible (focusable même non
    /// lisible), jamais `nil` — sinon le focus fuirait vers la barre d'onglets.
    func testTorrentOnlyFocusesFirstStream() throws {
        let torrents = try streams().filter { !$0.isDirectlyPlayable }
        XCTAssertEqual(StreamsFocusTarget.after(.populated, streams: torrents), .stream(torrents[0].id))
    }

    private func streams() throws -> [StreamItem] {
        let json = """
        {"streams": [
          {"name": "Torrent", "title": "4K", "infoHash": "aaaa"},
          {"name": "RealDebrid", "title": "1080p", "url": "https://cdn.example/v.mp4"},
          {"name": "Torrent", "title": "720p", "infoHash": "bbbb"}
        ]}
        """
        return try XCTUnwrap(JSONDecoder().decode(StreamResponse.self, from: Data(json.utf8)).streams)
    }
}
