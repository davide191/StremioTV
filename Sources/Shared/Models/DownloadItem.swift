import Foundation

/// État d'un téléchargement pour le mode hors-ligne.
enum DownloadStatus: String, Codable, Sendable {
    case queued        // créé, en attente de démarrage
    case downloading   // transfert en cours
    case paused        // suspendu par l'utilisateur (resume-data conservé)
    case completed     // fichier disponible, lisible hors-ligne
    case failed        // échec (voir `failureReason`)
}

/// Un média téléchargé (ou en cours) stocké **localement** pour la lecture
/// hors-ligne. Indépendant de `LibraryItem` (qui, lui, est synchronisé avec le
/// compte Stremio). Persisté dans le manifeste JSON via `DownloadManifest`.
///
/// L'`id` est **déterministe** — `"{metaId}|{videoId}"` — de sorte qu'un film /
/// épisode n'est téléchargé qu'une fois, quelle que soit la source, et qu'on
/// puisse re-lier un item à sa tâche `URLSession` après relance
/// (`taskDescription == id`).
struct DownloadItem: Codable, Sendable, Identifiable {
    let id: String
    let metaId: String
    let type: String            // "movie" / "series"
    let videoId: String         // épisode courant (= metaId pour un film)
    let name: String            // nom du film / de la série
    let videoTitle: String      // titre affiché (épisode ou film)
    let poster: String?
    var streamTitle: String     // libellé de la source (ex: « RealDebrid 1080p »)
    var sourceURL: URL
    var fileName: String        // nom de fichier local relatif (ex: « tt0111161.mp4 »)
    var subtitleFileName: String?
    var subtitleLang: String?
    var status: DownloadStatus
    var failureReason: String?
    var bytesReceived: Int64
    var totalBytes: Int64
    var resumeOffsetMs: UInt64  // position de reprise locale (substitut hors-ligne)
    var durationMs: UInt64
    let createdAt: Date

    /// Identifiant stable dérivé du média (pas d'un UUID) — voir doc du type.
    static func makeId(metaId: String, videoId: String) -> String {
        "\(metaId)|\(videoId)"
    }

    init(metaId: String, type: String, videoId: String, name: String,
         videoTitle: String, poster: String?, streamTitle: String,
         sourceURL: URL, fileName: String,
         status: DownloadStatus = .queued, createdAt: Date = Date()) {
        self.id = Self.makeId(metaId: metaId, videoId: videoId)
        self.metaId = metaId
        self.type = type
        self.videoId = videoId
        self.name = name
        self.videoTitle = videoTitle
        self.poster = poster
        self.streamTitle = streamTitle
        self.sourceURL = sourceURL
        self.fileName = fileName
        self.subtitleFileName = nil
        self.subtitleLang = nil
        self.status = status
        self.failureReason = nil
        self.bytesReceived = 0
        self.totalBytes = 0
        self.resumeOffsetMs = 0
        self.durationMs = 0
        self.createdAt = createdAt
    }

    // MARK: Dérivés

    /// Progression 0…1 (0 tant que la taille totale est inconnue).
    var progress: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, Double(bytesReceived) / Double(totalBytes))
    }

    var isPlayable: Bool { status == .completed }
    var isActive: Bool { status == .downloading || status == .queued }

    /// Taille lisible (« 1,2 Go »), reçue / totale si connue.
    var sizeText: String? {
        guard totalBytes > 0 else {
            return bytesReceived > 0 ? ByteCountFormatter.string(fromByteCount: bytesReceived, countStyle: .file) : nil
        }
        let total = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
        if status == .completed { return total }
        let received = ByteCountFormatter.string(fromByteCount: bytesReceived, countStyle: .file)
        return "\(received) / \(total)"
    }
}
