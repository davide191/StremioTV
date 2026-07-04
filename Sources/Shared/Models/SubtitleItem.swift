import Foundation

/// Réponse de sous-titres : `GET {base}/subtitles/{type}/{id}.json`
/// (add-ons OpenSubtitles & co.).
struct SubtitleResponse: Codable, Sendable {
    let subtitles: [SubtitleItem]?
}

/// Un sous-titre externe proposé par un add-on (fichier SRT/VTT distant).
struct SubtitleItem: Codable, Sendable, Identifiable {
    let url: String
    let lang: String
    private let subtitleId: String?

    enum CodingKeys: String, CodingKey {
        case url, lang
        case subtitleId = "id"
    }

    var id: String { subtitleId ?? url }

    /// Libellé lisible pour le menu (nom de langue normalisé).
    var displayLanguage: String { lang.isEmpty ? "Sous-titre" : LanguageNames.display(lang) }

    /// Construit un sous-titre depuis une URL locale/distante (le membre
    /// `subtitleId` étant privé, l'init mémberwise l'est aussi : on l'expose ici
    /// pour, p. ex., rattacher un sous-titre téléchargé en `file://`).
    init(url: String, lang: String) {
        self.url = url
        self.lang = lang
        self.subtitleId = nil
    }
}
