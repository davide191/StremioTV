import XCTest

/// Diagnostic sur le code **d'origine** (avant correctif), copié dans UITests/
/// par le job `baseline` de la CI : où est le focus sur un écran de flux sans
/// résultat, et que fait Menu ? Journalise seulement (aucune assertion).
final class BaselineFocusUITests: XCTestCase {
    func testBaselineZeroStreamsFocus() {
        let app = XCUIApplication()
        let remote = XCUIRemote.shared
        app.launchArguments = ["-uitestGuest"]
        app.launch()

        let hero = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Voir'")).firstMatch
        _ = hero.waitForExistence(timeout: 40)
        sleep(3)
        log(app, "B0 accueil chargé")
        if !hero.hasFocus { remote.press(.down) }
        sleep(2)
        log(app, "B1 accueil après ▼")

        remote.press(.select)
        _ = app.buttons["Voir les sources"].waitForExistence(timeout: 20)
        sleep(2)
        log(app, "B2 fiche")

        remote.press(.select)
        sleep(20)
        log(app, "B3 flux (zéro) après 20 s")

        remote.press(.down); sleep(1)
        remote.press(.down); sleep(1)
        remote.press(.right); sleep(2)
        log(app, "B4 flux après ▼ ▼ ▶")

        remote.press(.menu)
        sleep(3)
        log(app, "B5 après Menu")
        print("FOCUS-LOG B5 état de l'app : \(app.state.rawValue) (4 = premier plan, 3 = arrière-plan)")
    }

    private func log(_ app: XCUIApplication, _ step: String) {
        let focused = app.descendants(matching: .any)
            .matching(NSPredicate(format: "hasFocus == true"))
            .allElementsBoundByIndex
            .map { "[\($0.elementType.rawValue) id='\($0.identifier)' label='\($0.label)']" }
        print("FOCUS-LOG \(step) → \(focused.isEmpty ? "<aucun élément focalisé>" : focused.joined(separator: " "))")
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = step
        shot.lifetime = .keepAlways
        add(shot)
    }
}
