import SwiftUI

/// Recherche multi-add-ons. Résultats en grille adaptative.
struct SearchScreen: View {
    @Environment(AddonRepository.self) private var repo
    @State private var model = SearchViewModel()
    @State private var query = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                if model.isSearching && model.results.isEmpty {
                    ProgressView().padding(.top, 80)
                } else if !model.lastQuery.isEmpty && model.results.isEmpty {
                    ContentUnavailableView.search(text: model.lastQuery)
                        .padding(.top, 60)
                } else if model.results.isEmpty {
                    ContentUnavailableView {
                        Label("Rechercher", systemImage: "magnifyingglass")
                    } description: {
                        Text("Films, séries… dans tous tes add-ons.")
                    }
                    .padding(.top, 60)
                } else {
                    PosterGrid(metas: model.results)
                        .padding(.vertical)
                }
            }
            .navigationTitle("Recherche")
            .searchable(text: $query, prompt: "Rechercher un film, une série…")
            .task(id: query) {
                // `.task(id:)` annule automatiquement la recherche précédente à
                // chaque frappe ; le court délai debounce les saisies rapides.
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                await model.search(query: query, addons: repo.addons)
            }
        }
    }
}
