import SwiftUI

/// Onglet Bibliothèque : les items sauvegardés (favoris) du compte.
struct LibraryScreen: View {
    @Environment(LibraryStore.self) private var library
    @Environment(SessionStore.self) private var session

    var body: some View {
        NavigationStack {
            Group {
                if session.status != .loggedIn {
                    ContentUnavailableView {
                        Label("Connecte-toi pour voir ta bibliothèque", systemImage: "person.crop.circle.badge.questionmark")
                    } description: {
                        Text("Tes favoris et ta progression sont synchronisés avec ton compte Stremio.")
                    }
                } else if library.library.isEmpty {
                    ContentUnavailableView {
                        Label("Ta bibliothèque est vide", systemImage: "rectangle.stack.badge.plus")
                    } description: {
                        Text("Ajoute des films et séries depuis leur fiche pour les retrouver ici.")
                    }
                } else {
                    ScrollView {
                        PosterGrid(
                            metas: library.library.map { $0.asPreview() },
                            progressFor: { meta in library.item(for: meta.id)?.progress }
                        )
                        .padding(.vertical)
                    }
                    .refreshable { await library.refresh() }
                }
            }
            .navigationTitle("Bibliothèque")
        }
    }
}
