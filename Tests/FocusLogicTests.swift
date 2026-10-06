import XCTest
@testable import StremioTV

/// Logique de focus des écrans asynchrones (sans UI) : chaque phase doit offrir
/// un élément focusable dans la page, et le 1er flux focusable doit être lisible.
final class FocusLogicTests: XCTestCase {

    func testLoadPhase() {
        XCTAssertEqual(LoadPhase(hasContent: false, isFinished: false), .loading)
        XCTAssertEqual(LoadPhase(hasContent: false, isFinished: true), .empty)
        XCTAssertEqual(LoadPhase(hasContent: true, isFinished: false), .populated)
        XCTAssertEqual(LoadPhase(hasContent: true, isFinished: true), .populated)
    }

    /// Liste mixte : seuls les flux lisibles sont focusables, donc le 1er
    /// focusable (cible naturelle de tvOS) est le 1er flux lisible.
    func testMixedListOnlyPlayableStreamsAreFocusable() throws {
        let list = try streams()
        XCTAssertEqual(list.filter { StreamsListView.isFocusable($0, among: list) }.map(\.name), ["RealDebrid"])
    }

    /// Torrents seuls : tout reste focusable — sinon la page n'aurait aucun
    /// élément focusable et le focus fuirait vers la barre d'onglets.
    func testTorrentOnlyListKeepsEveryStreamFocusable() throws {
        let torrents = try streams().filter { !$0.isDirectlyPlayable }
        XCTAssertEqual(torrents.count, 2)
        XCTAssertTrue(torrents.allSatisfy { StreamsListView.isFocusable($0, among: torrents) })
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
