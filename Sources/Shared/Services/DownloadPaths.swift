import Foundation

/// Emplacements sur disque des téléchargements, avec un dossier de base
/// **injectable** (les tests passent un dossier temporaire). Par défaut :
/// `Application Support/Downloads` — créé à la demande (il n'existe pas par
/// défaut sur iOS) et exclu des sauvegardes iCloud/iTunes (fichiers volumineux).
struct DownloadPaths {
    let dir: URL

    init(base: URL = DownloadPaths.defaultBase()) {
        self.dir = base
    }

    static func defaultBase() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return support.appendingPathComponent("Downloads", isDirectory: true)
    }

    /// Crée le dossier si besoin et l'exclut des sauvegardes.
    func ensureDirectory() throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        var url = dir
        try? Self.excludeFromBackup(&url)
    }

    /// Noms de fichiers sûrs : seuls `/` et les caractères de contrôle posent
    /// problème sur APFS ; on remplace tout ce qui n'est pas alphanumérique / `.` / `-`.
    static func sanitize(_ id: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-"))
        let scalars = id.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        return String(scalars)
    }

    func fileURL(fileName: String) -> URL {
        URL(fileURLWithPath: fileName, relativeTo: dir).standardizedFileURL
    }

    func resumeURL(id: String) -> URL {
        dir.appendingPathComponent("\(Self.sanitize(id)).resume", isDirectory: false)
    }

    /// Emplacement temporaire (dérivé de l'`id` seul) où le délégué déplace
    /// SYNCHRONEMENT le fichier fini avant que le store ne le renomme en `fileName`.
    func stagingURL(id: String) -> URL {
        dir.appendingPathComponent("\(Self.sanitize(id)).part", isDirectory: false)
    }

    func subtitleURL(id: String, ext: String) -> URL {
        dir.appendingPathComponent("\(Self.sanitize(id)).\(ext)", isDirectory: false)
    }

    func manifestURL() -> URL {
        dir.appendingPathComponent("manifest.json", isDirectory: false)
    }

    /// Exclut une URL des sauvegardes (synchrone).
    static func excludeFromBackup(_ url: inout URL) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }
}
