import Foundation
import Observation

/// Store **local** des téléchargements hors-ligne — source de vérité de l'UI et
/// propriétaire de l'unique `URLSession` d'arrière-plan. Volontairement séparé
/// de `LibraryStore` (qui, lui, synchronise avec le compte Stremio) : les
/// téléchargements et leur progression de lecture restent sur l'appareil.
///
/// ## Pourquoi un singleton ?
/// Le contrat des transferts d'arrière-plan impose que la MÊME session (même
/// identifiant) existe au lancement pour que le système puisse re-livrer les
/// événements en attente (via `AppDelegate.handleEventsForBackgroundURLSession`,
/// qui est global au processus). D'où `DownloadStore.shared`. Il reste injecté
/// dans l'environnement SwiftUI (les vues utilisent `@Environment`), et un
/// `init(directory:startsSession:)` testable évite de créer une vraie session
/// d'arrière-plan dans les tests.
@Observable
@MainActor
final class DownloadStore {
    static let shared = DownloadStore()

    static let backgroundSessionIdentifier = "com.nicolasbataille.stremiotv.downloads"

    private(set) var items: [DownloadItem] = []

    private let paths: DownloadPaths
    private let downloader = Downloader()
    private var session: URLSession?
    private var tasks: [String: URLSessionDownloadTask] = [:]
    private var resumeData: [String: Data] = [:]

    /// Renseigné par l'`AppDelegate` lorsqu'iOS réveille l'app pour les
    /// événements de session d'arrière-plan ; rappelé quand ils sont livrés.
    var backgroundCompletionHandler: (() -> Void)?

    init(directory: URL = DownloadPaths.defaultBase(), startsSession: Bool = true) {
        self.paths = DownloadPaths(base: directory)
        try? paths.ensureDirectory()
        self.items = DownloadManifest.load(from: paths.manifestURL())
        if startsSession {
            ensureSession()
            reconcile()
        }
    }

    // MARK: - Session

    /// Crée (une seule fois) la session d'arrière-plan. Idempotent.
    func ensureSession() {
        guard session == nil else { return }
        let config = URLSessionConfiguration.background(withIdentifier: Self.backgroundSessionIdentifier)
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        config.allowsCellularAccess = true
        config.timeoutIntervalForResource = 7 * 24 * 3600
        session = URLSession(configuration: config, delegate: downloader, delegateQueue: nil)
    }

    /// Re-lie les items persistés aux tâches vivantes après relance, et
    /// finalise / marque en échec les téléchargements orphelins.
    func reconcile() {
        session?.getAllTasks { liveTasks in
            let live = liveTasks.compactMap { $0 as? URLSessionDownloadTask }
            Task { @MainActor in self.rebind(live) }
        }
    }

    private func rebind(_ liveTasks: [URLSessionDownloadTask]) {
        var live: [String: URLSessionDownloadTask] = [:]
        for task in liveTasks {
            if let id = task.taskDescription { live[id] = task }
        }
        tasks = live
        let fm = FileManager.default
        for item in items where item.isActive && live[item.id] == nil {
            let staged = paths.stagingURL(id: item.id)
            if fm.fileExists(atPath: staged.path) {
                finishDownload(id: item.id, stagedAt: staged)
            } else if fm.fileExists(atPath: paths.fileURL(fileName: item.fileName).path) {
                update(item.id) { $0.status = .completed }
            } else {
                update(item.id) { $0.status = .failed; $0.failureReason = "Téléchargement interrompu" }
            }
        }
        persist()
    }

    func callBackgroundCompletionHandler() {
        let handler = backgroundCompletionHandler
        backgroundCompletionHandler = nil
        handler?()
    }

    // MARK: - Lecture de l'état (UI)

    func item(id: String) -> DownloadItem? { items.first { $0.id == id } }

    func item(metaId: String, videoId: String) -> DownloadItem? {
        item(id: DownloadItem.makeId(metaId: metaId, videoId: videoId))
    }

    /// Items triés du plus récent au plus ancien (affichage).
    var sortedItems: [DownloadItem] { items.sorted { $0.createdAt > $1.createdAt } }

    // MARK: - Intentions

    /// Lance le téléchargement d'un flux direct (ou crée un item en échec si le
    /// flux est refusé — HLS/DASH). Idempotent si déjà téléchargé.
    func enqueue(sourceURL: URL, metaId: String, type: String, videoId: String,
                 name: String, videoTitle: String, poster: String?,
                 streamTitle: String, subtitle: SubtitleItem?) async {
        ensureSession()
        let id = DownloadItem.makeId(metaId: metaId, videoId: videoId)
        // Dédup SYNCHRONE, avant toute suspension : seul un item en échec peut
        // être relancé. Le MainActor étant réentrant au `await probe`, on réserve
        // ici un item `.queued` AVANT de suspendre, pour qu'un second appel
        // (double-tap) le voie et abandonne — sinon deux tâches concurrentes
        // partent pour le même id (l'une non suivie / non annulable).
        let existing = item(id: id)
        if let existing, existing.status != .failed { return }

        var reserved = makeItem(id: id, metaId: metaId, type: type, videoId: videoId, name: name,
                                videoTitle: videoTitle, poster: poster, streamTitle: streamTitle,
                                sourceURL: sourceURL,
                                ext: StreamDownloadRules.containerExtension(for: sourceURL),
                                status: .queued)
        // Reprise d'un échec : on conserve le sous-titre déjà téléchargé et la
        // position de lecture (sinon `makeItem` les remet à zéro et orpheline le .srt).
        if let existing {
            reserved.subtitleFileName = existing.subtitleFileName
            reserved.subtitleLang = existing.subtitleLang
            reserved.resumeOffsetMs = existing.resumeOffsetMs
            reserved.durationMs = existing.durationMs
        }
        upsert(reserved)
        persist()

        switch await StreamDownloadRules.probe(sourceURL) {
        case .refused(let reason):
            update(id) { $0.status = .failed; $0.failureReason = reason }
            persist()
        case .ok(let contentLength, let ext):
            update(id) {
                $0.status = .downloading
                $0.failureReason = nil
                $0.totalBytes = contentLength
                $0.fileName = "\(DownloadPaths.sanitize(id)).\(ext)"
            }
            persist()
            if let item = item(id: id) { startTask(for: item) }
            if let subtitle, item(id: id)?.subtitleFileName == nil {
                await downloadSubtitle(subtitle, for: id)
            }
        }
    }

    func pause(id: String) {
        guard let task = tasks[id] else { return }
        task.cancel(byProducingResumeData: { [weak self] data in
            Task { @MainActor in self?.didPause(id: id, resumeData: data) }
        })
    }

    func resume(id: String) {
        ensureSession()
        guard let session, let item = item(id: id) else { return }
        tasks[id]?.cancel()
        let task: URLSessionDownloadTask
        if let data = loadResumeData(id: id) {
            task = session.downloadTask(withResumeData: data)   // reprend à l'octet sauvegardé
        } else {
            task = session.downloadTask(with: item.sourceURL)   // repli : reprise depuis zéro
        }
        task.taskDescription = id
        tasks[id] = task
        clearResumeData(id: id)
        update(id) { $0.status = .downloading; $0.failureReason = nil }
        persist()
        task.resume()
    }

    /// Relance un item en échec **en repassant par la sonde** (un flux refusé —
    /// HLS/DASH — ne doit pas être forcé ; un échec réseau repart proprement).
    func retry(id: String) {
        guard let item = item(id: id) else { return }
        Task { [weak self] in
            await self?.enqueue(
                sourceURL: item.sourceURL, metaId: item.metaId, type: item.type,
                videoId: item.videoId, name: item.name, videoTitle: item.videoTitle,
                poster: item.poster, streamTitle: item.streamTitle, subtitle: nil
            )
        }
    }

    func delete(id: String) {
        tasks[id]?.cancel()
        tasks[id] = nil
        resumeData[id] = nil
        if let item = item(id: id) {
            let fm = FileManager.default
            try? fm.removeItem(at: paths.fileURL(fileName: item.fileName))
            try? fm.removeItem(at: paths.stagingURL(id: id))
            try? fm.removeItem(at: paths.resumeURL(id: id))
            if let sub = item.subtitleFileName {
                try? fm.removeItem(at: paths.dir.appendingPathComponent(sub))
            }
        }
        items.removeAll { $0.id == id }
        persist()
    }

    // MARK: - Lecture hors-ligne

    func localURL(for item: DownloadItem) -> URL {
        paths.fileURL(fileName: item.fileName)
    }

    /// Sous-titre local téléchargé, présenté comme un `SubtitleItem` file:// pour
    /// passer par la file de sous-titres existante du lecteur.
    func localSubtitle(for item: DownloadItem) -> SubtitleItem? {
        guard let name = item.subtitleFileName else { return nil }
        let url = paths.dir.appendingPathComponent(name)
        return SubtitleItem(url: url.absoluteString, lang: item.subtitleLang ?? "")
    }

    /// Enregistre la position de reprise localement — substitut hors-ligne de
    /// `LibraryStore.recordProgress` (qui ne fait rien sans compte/réseau).
    func recordPlaybackProgress(id: String, offsetMs: UInt64, durationMs: UInt64) {
        update(id) {
            $0.resumeOffsetMs = offsetMs
            if durationMs > 0 { $0.durationMs = durationMs }
        }
        persist()
    }

    // MARK: - Rappels du délégué (MainActor)

    func updateProgress(id: String, written: Int64, total: Int64) {
        update(id) {
            $0.bytesReceived = written
            if total > 0 { $0.totalBytes = total }
            if $0.status == .queued || $0.status == .paused { $0.status = .downloading }
        }
        // Pas de persistance à chaque tick : la progression est transitoire et
        // reconstruite au besoin (reconcile). On persiste aux transitions d'état.
    }

    func finishDownload(id: String, stagedAt staged: URL) {
        tasks[id] = nil
        clearResumeData(id: id)
        guard let item = item(id: id) else {
            try? FileManager.default.removeItem(at: staged)
            return
        }
        let dest = paths.fileURL(fileName: item.fileName)
        let fm = FileManager.default
        do {
            try? paths.ensureDirectory()
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
            try fm.moveItem(at: staged, to: dest)
            var excluded = dest
            try? DownloadPaths.excludeFromBackup(&excluded)
            update(id) {
                $0.status = .completed
                $0.failureReason = nil
                if $0.totalBytes == 0,
                   let size = (try? fm.attributesOfItem(atPath: dest.path)[.size]) as? Int64 {
                    $0.totalBytes = size
                }
                $0.bytesReceived = $0.totalBytes
            }
        } catch {
            update(id) { $0.status = .failed; $0.failureReason = error.localizedDescription }
        }
        persist()
    }

    func markFailed(id: String, reason: String, resumeData data: Data?) {
        tasks[id] = nil
        // Un item déjà terminé (fichier sur disque) ou en pause ne doit pas être
        // basculé en échec par l'erreur tardive d'une tâche orpheline.
        guard let item = item(id: id), item.status != .paused, item.status != .completed else { return }
        if let data { saveResumeData(data, id: id) }
        update(id) { $0.status = .failed; $0.failureReason = reason }
        persist()
    }

    // MARK: - Privé

    private func didPause(id: String, resumeData data: Data?) {
        tasks[id] = nil
        if let data { saveResumeData(data, id: id) }
        update(id) { $0.status = .paused }
        persist()
    }

    private func startTask(for item: DownloadItem) {
        guard let session else { return }
        tasks[item.id]?.cancel()   // jamais deux tâches vivantes pour un même id
        let task = session.downloadTask(with: item.sourceURL)
        task.taskDescription = item.id
        tasks[item.id] = task
        task.resume()
    }

    // MARK: Resume-data (mémoire + disque, pour survivre à une relance)

    private func saveResumeData(_ data: Data, id: String) {
        resumeData[id] = data
        let url = paths.resumeURL(id: id)
        guard (try? data.write(to: url, options: .atomic)) != nil else { return }
        var excluded = url
        try? DownloadPaths.excludeFromBackup(&excluded)
    }

    private func loadResumeData(id: String) -> Data? {
        resumeData[id] ?? (try? Data(contentsOf: paths.resumeURL(id: id)))
    }

    private func clearResumeData(id: String) {
        resumeData[id] = nil
        try? FileManager.default.removeItem(at: paths.resumeURL(id: id))
    }

    private func downloadSubtitle(_ subtitle: SubtitleItem, for id: String) async {
        guard let url = URL(string: subtitle.url), url.scheme?.hasPrefix("http") == true else { return }
        let ext = url.pathExtension.lowercased() == "vtt" ? "vtt" : "srt"
        let dest = paths.subtitleURL(id: id, ext: ext)
        guard let (data, _) = try? await URLSession.shared.data(from: url), !data.isEmpty else { return }
        do {
            try data.write(to: dest, options: .atomic)
            var excluded = dest
            try? DownloadPaths.excludeFromBackup(&excluded)
            update(id) {
                $0.subtitleFileName = dest.lastPathComponent
                $0.subtitleLang = subtitle.lang
            }
            persist()
        } catch { /* sous-titre optionnel : on ignore l'échec */ }
    }

    private func makeItem(id: String, metaId: String, type: String, videoId: String,
                          name: String, videoTitle: String, poster: String?, streamTitle: String,
                          sourceURL: URL, ext: String, status: DownloadStatus) -> DownloadItem {
        DownloadItem(metaId: metaId, type: type, videoId: videoId, name: name,
                     videoTitle: videoTitle, poster: poster, streamTitle: streamTitle,
                     sourceURL: sourceURL, fileName: "\(DownloadPaths.sanitize(id)).\(ext)",
                     status: status)
    }

    private func upsert(_ item: DownloadItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else {
            items.append(item)
        }
    }

    private func update(_ id: String, _ transform: (inout DownloadItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        transform(&items[index])
    }

    private func persist() {
        try? DownloadManifest.save(items, to: paths.manifestURL())
    }
}
