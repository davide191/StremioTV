import Foundation
import Network
import Observation

/// Surveille la connectivité réseau (Wi-Fi/cellulaire) pour piloter l'UX
/// hors-ligne. `firstUpdate()` permet d'attendre le tout premier état connu au
/// lancement (sinon `isOnline` vaut `true` par défaut, ce qui fausserait
/// l'aiguillage hors-ligne de `RootView`).
@Observable
@MainActor
final class NetworkMonitor {
    private(set) var isOnline = true
    var isOffline: Bool { !isOnline }

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.nicolasbataille.stremiotv.networkmonitor")
    private var didReceiveFirstUpdate = false
    private var firstUpdateWaiters: [CheckedContinuation<Void, Never>] = []

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.apply(online: online) }
        }
        monitor.start(queue: queue)
    }

    /// Attend le premier état réseau réel (retourne aussitôt s'il est déjà connu).
    func firstUpdate() async {
        if didReceiveFirstUpdate { return }
        await withCheckedContinuation { continuation in
            if didReceiveFirstUpdate {
                continuation.resume()
            } else {
                firstUpdateWaiters.append(continuation)
            }
        }
    }

    private func apply(online: Bool) {
        isOnline = online
        if !didReceiveFirstUpdate {
            didReceiveFirstUpdate = true
            let waiters = firstUpdateWaiters
            firstUpdateWaiters.removeAll()
            waiters.forEach { $0.resume() }
        }
    }

    deinit { monitor.cancel() }
}
