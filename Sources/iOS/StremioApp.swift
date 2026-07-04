import SwiftUI

/// Point d'entrée de l'app **iOS** (iPhone + iPad).
/// `SessionStore` (auth + add-ons), son `AddonRepository` et la `LibraryStore`
/// sont injectés dans l'environnement (pattern Observation, iOS 17+).
@main
struct StremioApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var session = SessionStore()
    @State private var downloads = DownloadStore.shared
    @State private var network = NetworkMonitor()

    init() {
        // Instancie la session de téléchargement d'arrière-plan dès le lancement
        // pour que le système puisse re-livrer les événements de transfert.
        _ = DownloadStore.shared
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(session.repository)
                .environment(session.library)
                .environment(downloads)
                .environment(network)
                .tint(.brand)
                .preferredColorScheme(.dark)
        }
    }
}
