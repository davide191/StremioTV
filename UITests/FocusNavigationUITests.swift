import XCTest

/// Navigation au focus avec la télécommande : en entrant dans une page poussée,
/// le focus doit atterrir dans la page (jamais rester dans la barre d'onglets)
/// et revenir sur l'élément d'origine au retour.
///
/// - Mode invité = Cinemeta seul, qui ne fournit **aucun** flux : cas « zéro
///   flux » déterministe. Réseau live requis (comme `AppFlowUITests`).
/// - `MOCK_ADDON_URL` (via `TEST_RUNNER_MOCK_ADDON_URL` côté xcodebuild) :
///   faux add-on de flux (torrents + 1 flux direct) pour les cas peuplés ;
///   tests ignorés sans lui. Voir `.github/ci/mock_addon.py`.
///
/// Chaque étape journalise l'élément focalisé (`FOCUS-LOG`) et joint une capture.
final class FocusNavigationUITests: XCTestCase {
    private let remote = XCUIRemote.shared
    private var app: XCUIApplication!

    private var mockAddonURL: String? { ProcessInfo.processInfo.environment["MOCK_ADDON_URL"] }

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    // MARK: - Accueil → fiche → flux (zéro) → retour, ×3

    func testZeroStreamsRoundTripKeepsFocusInContent() throws {
        app.launchArguments = ["-uitestGuest"]
        app.launch()
        let hero = app.buttons["heroBanner"]
        let primary = app.buttons["detailPrimaryAction"]
        let library = app.buttons["detailLibraryButton"]
        let retry = app.buttons["streamsRetry"]

        enterHomeContent(hero)
        for pass in 1...3 {
            waitForFocus("A\(pass) accueil : bannière", on: hero)
            remote.press(.select)
            guard primary.waitForExistence(timeout: 20) else {
                throw XCTSkip("La vedette n'est pas un film (pas d'action principale).")
            }
            waitForFocus("A\(pass) fiche : action principale", on: primary)
            assertTabBarNotFocused()

            if pass == 1 {
                // E : ▲ vers la barre d'onglets puis ▼ doit revenir dans la page.
                remote.press(.up); remote.press(.up)
                logFocus("E fiche après ▲▲")
                remote.press(.down); remote.press(.down)
                waitForFocus("E fiche après ▼▼ : retour dans la page") { [primary, library] _ in
                    primary.hasFocus || library.hasFocus
                }
                if !primary.hasFocus { remote.press(.left) }
                waitForFocus("E fiche : action principale", on: primary)
            }

            remote.press(.select)
            waitForFocus("G\(pass) zéro flux : Réessayer", on: retry, timeout: 60)
            assertTabBarNotFocused()

            if pass == 1 {
                // Réessayer → « Annuler » pendant la recherche → de nouveau Réessayer.
                remote.press(.select)
                waitForFocus("G1 après Réessayer : Réessayer refocalisé", on: retry, timeout: 60)
            }

            remote.press(.menu)
            waitForFocus("I\(pass) retour fiche : action principale restaurée", on: primary)
            XCTAssertEqual(app.state, .runningForeground, "Menu doit revenir en arrière, pas quitter l'app")

            remote.press(.menu)
        }
        waitForFocus("I retour accueil : bannière restaurée", on: hero)
    }

    // MARK: - Flux peuplés : 1er flux lisible, lecteur, retour

    func testPopulatedStreamsFocusFirstPlayableAndSurvivePlayer() throws {
        guard let mock = mockAddonURL else { throw XCTSkip("MOCK_ADDON_URL absent") }
        app.launchArguments = ["-uitestGuest", "-uitestAddon", mock]
        app.launch()
        let hero = app.buttons["heroBanner"]
        let primary = app.buttons["detailPrimaryAction"]

        enterHomeContent(hero)
        waitForFocus("H accueil : bannière", on: hero)
        remote.press(.select)
        guard primary.waitForExistence(timeout: 20) else {
            throw XCTSkip("La vedette n'est pas un film (pas d'action principale).")
        }
        waitForFocus("H fiche : action principale", on: primary)
        remote.press(.select)

        // Le 1er flux est un torrent : le focus doit aller au 1er flux *lisible*.
        waitForFocus("H flux : 1er flux lisible", timeout: 60, labelContains: "MockDirect")
        assertTabBarNotFocused()

        // Liste mixte : les torrents sont désactivés, ▲/▼ restent sur le flux lisible.
        remote.press(.up)
        sleep(1)
        waitForFocus("H ▲ : reste sur le flux lisible", labelContains: "MockDirect")
        remote.press(.down)
        sleep(1)
        waitForFocus("H ▼ : reste sur le flux lisible", labelContains: "MockDirect")

        // J : lecteur puis Menu → la liste n'est pas rechargée, le flux reste focalisé.
        remote.press(.select)
        sleep(10)
        snapshot("J lecteur")
        remote.press(.menu)
        if app.alerts.firstMatch.waitForExistence(timeout: 3) {
            snapshot("J alerte du lecteur")
            remote.press(.select)
        }
        waitForFocus("J retour du lecteur : flux joué refocalisé", timeout: 30, labelContains: "MockDirect")
        XCTAssertEqual(app.state, .runningForeground)

        remote.press(.menu)
        waitForFocus("J retour fiche : action principale", on: primary)
        remote.press(.menu)
        waitForFocus("J retour accueil : bannière", on: hero)
    }

    // MARK: - Torrents seuls (ex. Torrentio sans debrid) : focusables et défilables

    func testTorrentOnlyStreamsStayFocusableAndScrollable() throws {
        guard let mock = mockAddonURL else { throw XCTSkip("MOCK_ADDON_URL absent") }
        app.launchArguments = ["-uitestGuest", "-uitestAddon", mock + "/torrents"]
        app.launch()
        let hero = app.buttons["heroBanner"]
        let primary = app.buttons["detailPrimaryAction"]

        enterHomeContent(hero)
        waitForFocus("G2 accueil : bannière", on: hero)
        remote.press(.select)
        guard primary.waitForExistence(timeout: 20) else {
            throw XCTSkip("La vedette n'est pas un film (pas d'action principale).")
        }
        waitForFocus("G2 fiche : action principale", on: primary)
        remote.press(.select)

        waitForFocus("G2 torrents seuls : 1er torrent focalisé", timeout: 60, labelContains: "MockTorrent01")
        assertTabBarNotFocused()
        for _ in 1...11 { remote.press(.down) }
        waitForFocus("G2 ▼×11 : dernier torrent atteint (défilement)", labelContains: "MockTorrent12")

        remote.press(.menu)
        waitForFocus("G2 retour fiche : action principale", on: primary)
        XCTAssertEqual(app.state, .runningForeground)
    }

    // MARK: - Série : épisode → flux → retour sur le même épisode

    func testSeriesEpisodeToStreamsBackRestoresEpisodeFocus() throws {
        guard let mock = mockAddonURL else { throw XCTSkip("MOCK_ADDON_URL absent") }
        app.launchArguments = ["-uitestScreen", "detailSeries", "-uitestAddon", mock]
        app.launch()

        let episodes = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'episode-'"))
        XCTAssertTrue(episodes.firstMatch.waitForExistence(timeout: 40), "Les épisodes doivent se charger")
        waitForFocus("D fiche série : un contrôle de la page") { !$0.isEmpty }

        // ▼ jusqu'aux épisodes, puis un de plus : la restauration ne doit pas
        // simplement retomber sur le 1er élément focusable.
        var episode = ""
        for _ in 0..<5 {
            remote.press(.down)
            if let id = focusedIdentifier(prefix: "episode-") { episode = id; break }
        }
        XCTAssertFalse(episode.isEmpty, "▼ doit atteindre la liste d'épisodes")
        remote.press(.down)
        episode = focusedIdentifier(prefix: "episode-") ?? episode
        waitForFocus("D épisode choisi \(episode)", on: app.buttons[episode])

        remote.press(.select)
        waitForFocus("D flux de l'épisode : 1er flux lisible", timeout: 60, labelContains: "MockDirect")
        remote.press(.menu)
        waitForFocus("D retour : même épisode refocalisé", on: app.buttons[episode], timeout: 20)
    }

    // MARK: - Catalogue « Tout voir » : 1er poster, fiche, retour

    func testCatalogGridFocusAndRestore() throws {
        app.launchArguments = ["-uitestScreen", "grid"]
        app.launch()

        let primary = app.buttons["detailPrimaryAction"]
        let posters = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'poster-'"))
        XCTAssertTrue(posters.firstMatch.waitForExistence(timeout: 40), "Le catalogue doit se charger")
        waitForFocus("C grille chargée : un poster focalisé") { focused in
            focused.contains { $0.identifier.hasPrefix("poster-") }
        }
        remote.press(.right); remote.press(.right)
        let poster = try XCTUnwrap(focusedIdentifier(prefix: "poster-"))
        waitForFocus("C poster choisi \(poster)", on: app.buttons[poster])

        remote.press(.select)
        waitForFocus("C fiche : action principale", on: primary, timeout: 20)
        remote.press(.menu)
        waitForFocus("C retour : même poster refocalisé", on: app.buttons[poster])
    }

    // MARK: - Helpers

    /// Au lancement, l'accueil est vide → focus dans la barre d'onglets : ▼ entre dans le contenu.
    private func enterHomeContent(_ hero: XCUIElement) {
        XCTAssertTrue(hero.waitForExistence(timeout: 40), "La bannière doit se charger (réseau)")
        sleep(2)
        if !hero.hasFocus { remote.press(.down) }
    }

    private var focusedElements: [XCUIElement] {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "hasFocus == true"))
            .allElementsBoundByIndex
    }

    private func focusedIdentifier(prefix: String) -> String? {
        let deadline = Date().addingTimeInterval(3)
        repeat {
            if let id = focusedElements.map(\.identifier).first(where: { $0.hasPrefix(prefix) }) { return id }
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        } while Date() < deadline
        return nil
    }

    private func describeFocus() -> String {
        let focused = focusedElements
        guard !focused.isEmpty else { return "<aucun élément focalisé>" }
        return focused.map { "[\($0.elementType.rawValue) id='\($0.identifier)' label='\($0.label)']" }
            .joined(separator: " ")
    }

    private func waitForFocus(_ step: String, on element: XCUIElement, timeout: TimeInterval = 20,
                              file: StaticString = #filePath, line: UInt = #line) {
        waitForFocus(step, timeout: timeout, file: file, line: line) { _ in
            element.exists && element.hasFocus
        }
    }

    private func waitForFocus(_ step: String, timeout: TimeInterval = 20, labelContains text: String,
                              file: StaticString = #filePath, line: UInt = #line) {
        waitForFocus(step, timeout: timeout, file: file, line: line) { focused in
            focused.contains { $0.label.contains(text) }
        }
    }

    private func waitForFocus(_ step: String, timeout: TimeInterval = 20,
                              file: StaticString = #filePath, line: UInt = #line,
                              where condition: @escaping ([XCUIElement]) -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if condition(focusedElements) {
                logFocus(step)
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        } while Date() < deadline
        logFocus("ÉCHEC — \(step)")
        XCTFail("Focus attendu : \(step) — focus actuel : \(describeFocus())", file: file, line: line)
    }

    private func logFocus(_ step: String) {
        print("FOCUS-LOG \(step) → \(describeFocus())")
        snapshot(step)
    }

    private func snapshot(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func assertTabBarNotFocused(file: StaticString = #filePath, line: UInt = #line) {
        let inTabBar = app.tabBars.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true"))
        XCTAssertEqual(inTabBar.count, 0, "Le focus ne doit pas rester dans la barre d'onglets — \(describeFocus())",
                       file: file, line: line)
    }
}
