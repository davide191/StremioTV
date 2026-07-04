import Foundation

/// Codec de persistance de l'index des téléchargements, isolé du `DownloadStore`
/// pour être testable sans MainActor ni `URLSession`. Écriture atomique ; la
/// lecture ne lève jamais (fichier absent / corrompu ⇒ liste vide).
enum DownloadManifest {
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    static func load(from url: URL) -> [DownloadItem] {
        guard let data = try? Data(contentsOf: url),
              let items = try? decoder.decode([DownloadItem].self, from: data) else {
            return []
        }
        return items
    }

    static func save(_ items: [DownloadItem], to url: URL) throws {
        let data = try encoder.encode(items)
        try data.write(to: url, options: .atomic)
    }
}
