import SwiftUI

/// Point d'entrée de l'app **iOS** (iPhone + iPad).
/// `SessionStore` (auth + add-ons), son `AddonRepository` et la `LibraryStore`
/// sont injectés dans l'environnement (pattern Observation, iOS 17+).
@main
struct StremioApp: App {
    @State private var session = SessionStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(session.repository)
                .environment(session.library)
                .tint(.brand)
                .preferredColorScheme(.dark)
        }
    }
}
