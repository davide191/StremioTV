import Foundation

/// Règles d'éligibilité au téléchargement hors-ligne.
///
/// Seuls les **fichiers progressifs uniques** (mp4/mkv/…) en HTTP(S) sont
/// téléchargeables. Les manifestes de streaming adaptatif — HLS (`.m3u8`) et
/// DASH (`.mpd`) — ne le sont PAS : une simple tâche de téléchargement ne
/// récupère que le manifeste, jamais les segments, et le `.movpkg` produit par
/// `AVAssetDownloadTask` n'est pas lisible par VLC. Les torrents et YouTube sont
/// gérés en amont (jamais `isDirectlyPlayable`).
enum StreamDownloadRules {
    /// Extensions de manifeste adaptatif à refuser.
    private static let manifestExtensions: Set<String> = ["m3u8", "m3u", "mpd"]

    /// Extensions de conteneur acceptées (sinon repli sur « mp4 »).
    private static let containerExtensions: Set<String> = ["mp4", "mkv", "avi", "mov", "webm", "m4v", "ts"]

    /// Types MIME de manifeste adaptatif.
    private static let manifestMimeTypes: Set<String> = [
        "application/vnd.apple.mpegurl", "application/x-mpegurl", "audio/mpegurl",
        "application/mpegurl", "vnd.apple.mpegurl", "application/dash+xml",
    ]

    static let refusalReason = "Flux HLS/DASH — non téléchargeable pour le hors-ligne."

    /// Filtre synchrone bon marché (extension d'URL) pour masquer le bouton.
    static func isLikelyDownloadable(_ url: URL) -> Bool {
        !manifestExtensions.contains(url.pathExtension.lowercased())
    }

    /// Conteneur déduit d'une extension d'URL (pour nommer le fichier local).
    static func containerExtension(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        return containerExtensions.contains(ext) ? ext : "mp4"
    }

    /// Conteneur déduit d'un type MIME.
    static func containerExtension(forMime mime: String) -> String? {
        switch mime.lowercased() {
        case "video/mp4", "video/x-m4v": return "mp4"
        case "video/x-matroska": return "mkv"
        case "video/quicktime": return "mov"
        case "video/x-msvideo": return "avi"
        case "video/webm": return "webm"
        case "video/mp2t": return "ts"
        default: return nil
        }
    }

    enum Probe: Sendable {
        case ok(contentLength: Int64, ext: String)
        case refused(reason: String)
    }

    /// Sonde légère : lit l'en-tête `Content-Type` et un **préfixe borné** (≤ 2 Ko)
    /// pour démasquer un manifeste HLS/DASH à l'extension trompeuse (magie
    /// `#EXTM3U`) et récupérer la taille + le conteneur réel avant le transfert.
    ///
    /// Utilise `bytes(for:)` (flux paresseux) et non `data(for:)` : si le serveur
    /// **ignore** l'en-tête `Range` et répond 200, `data(for:)` bufferiserait le
    /// fichier ENTIER (plusieurs Go) en mémoire. Ici on s'arrête après 2 Ko.
    static func probe(_ url: URL, session: URLSession = .shared) async -> Probe {
        guard isLikelyDownloadable(url) else { return .refused(reason: refusalReason) }

        var request = URLRequest(url: url)
        request.setValue("bytes=0-2047", forHTTPHeaderField: "Range")
        request.timeoutInterval = 20

        guard let (byteStream, response) = try? await session.bytes(for: request),
              let http = response as? HTTPURLResponse else {
            // Réseau indisponible : on tente quand même (déduction par extension).
            return .ok(contentLength: 0, ext: containerExtension(for: url))
        }

        let mime = (http.value(forHTTPHeaderField: "Content-Type") ?? "")
            .split(separator: ";").first.map { String($0).trimmingCharacters(in: .whitespaces).lowercased() } ?? ""
        if manifestMimeTypes.contains(mime) { return .refused(reason: refusalReason) }

        // Préfixe borné (le flux — donc la tâche — est annulé dès qu'on sort).
        var prefix = [UInt8]()
        prefix.reserveCapacity(2048)
        if let iterator = try? await Self.readPrefix(byteStream, max: 2048) { prefix = iterator }
        if let text = String(bytes: prefix, encoding: .utf8),
           let firstLine = text.split(whereSeparator: \.isNewline).first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }),
           firstLine.trimmingCharacters(in: .whitespaces).hasPrefix("#EXTM3U") {
            return .refused(reason: refusalReason)
        }

        // Taille totale : Content-Range « bytes 0-2047/12345678 » sinon Content-Length.
        var contentLength: Int64 = 0
        if let range = http.value(forHTTPHeaderField: "Content-Range"),
           let total = range.split(separator: "/").last, let value = Int64(total) {
            contentLength = value
        } else if http.statusCode == 200, let length = http.value(forHTTPHeaderField: "Content-Length"),
                  let value = Int64(length) {
            contentLength = value
        }

        let ext = containerExtension(forMime: mime) ?? containerExtension(for: url)
        return .ok(contentLength: contentLength, ext: ext)
    }

    /// Lit au plus `max` octets d'un flux `URLSession.bytes` puis s'arrête
    /// (le reste du transfert est annulé à la sortie).
    private static func readPrefix(_ bytes: URLSession.AsyncBytes, max: Int) async throws -> [UInt8] {
        var out = [UInt8]()
        out.reserveCapacity(max)
        for try await byte in bytes {
            out.append(byte)
            if out.count >= max { break }
        }
        return out
    }
}
