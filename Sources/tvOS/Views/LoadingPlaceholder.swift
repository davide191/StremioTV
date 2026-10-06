import SwiftUI

/// État d'un écran **poussé** dont le contenu arrive en asynchrone.
///
/// Règle de focus tvOS : chaque phase doit offrir au moins un contrôle
/// focusable *dans la page*. Une page sans élément focusable laisse le moteur
/// de focus se rabattre sur la barre d'onglets, d'où ni ▼ ni Menu ne ramènent
/// dans la page.
enum LoadPhase: Equatable {
    case loading    // « Annuler » (LoadingPlaceholder)
    case empty      // « Réessayer »
    case populated  // le contenu lui-même

    init(hasContent: Bool, isFinished: Bool) {
        if hasContent {
            self = .populated
        } else {
            self = isFinished ? .empty : .loading
        }
    }
}

/// Indicateur de chargement d'un écran poussé, avec un vrai bouton « Annuler »
/// (retour) qui porte le focus pendant l'attente.
struct LoadingPlaceholder: View {
    let message: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 28) {
            ProgressView()
            Text(message).font(.title3).foregroundStyle(.secondary)
            Button("Annuler") { dismiss() }
                .accessibilityIdentifier("loadingCancel")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
