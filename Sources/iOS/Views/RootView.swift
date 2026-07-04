import SwiftUI

/// Aiguille entre l'écran de connexion et l'app principale selon l'état de session.
/// Au lancement, tente de restaurer une session via l'authKey du Keychain.
struct RootView: View {
    @Environment(SessionStore.self) private var session
    @Environment(NetworkMonitor.self) private var network

    var body: some View {
        Group {
            switch session.status {
            case .working:
                SplashView()
            case .loggedOut:
                LoginScreen()
            case .loggedIn, .guest:
                MainShell()
            }
        }
        .task {
            if ProcessInfo.processInfo.arguments.contains("-uitestGuest") {
                session.continueAsGuest()
                return
            }
            // Attend le premier état réseau connu (évite une course au lancement).
            await network.firstUpdate()
            if network.isOffline {
                // Hors-ligne : on entre directement dans l'app en mode invité pour
                // que l'onglet Téléchargements soit accessible sans réseau ni compte.
                // La clé d'auth reste en Keychain — une relance en ligne restaure.
                session.continueAsGuest()
            } else {
                await session.restore()
            }
        }
    }
}

/// Écran de lancement pendant la restauration de session.
struct SplashView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "play.tv.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.brand)
            Text("StremioTV").font(.largeTitle.bold())
            ProgressView().padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
    }
}
