import UIKit

/// Reçoit le réveil système pour les événements de la session de téléchargement
/// d'arrière-plan. iOS relance l'app (ou l'informe) quand un transfert se
/// termine hors du premier plan : on mémorise le handler puis on garantit que
/// la session existe pour que le délégué reçoive les événements en attente.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        guard identifier == DownloadStore.backgroundSessionIdentifier else {
            completionHandler()
            return
        }
        DownloadStore.shared.backgroundCompletionHandler = completionHandler
        DownloadStore.shared.ensureSession()
    }
}
