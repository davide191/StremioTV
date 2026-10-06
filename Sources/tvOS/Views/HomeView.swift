import SwiftUI

/// Écran d'accueil : une rangée horizontale par catalogue d'add-on.
struct HomeView: View {
    @Environment(AddonRepository.self) private var repo
    @Environment(LibraryStore.self) private var library
    @State private var model = HomeViewModel()
    /// Add-ons dont les catalogues sont déjà affichés.
    @State private var loadedAddonIDs: [String]?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 50) {
                    if let featured = model.sections.first?.metas.first {
                        HeroBanner(preview: featured, bases: repo.addons.map(\.base))
                    }
                    if !library.continueWatching.isEmpty {
                        ContinueWatchingRow(items: library.continueWatching)
                    }
                    content
                }
                .padding(.bottom, 40)
            }
        }
        // Sur la pile et non sur sa racine : ouvrir une fiche n'annule pas le
        // chargement, et le retour ne vide pas les rangées (`load` repart de
        // zéro) — le poster d'origine reste là pour recevoir le focus restauré.
        .task(id: repo.addons.map(\.id)) {
            guard loadedAddonIDs != repo.addons.map(\.id) else { return }
            await loadCatalogs()
        }
    }

    private func loadCatalogs() async {
        let ids = repo.addons.map(\.id)
        await model.load(addons: repo.addons)
        if !Task.isCancelled, !model.sections.isEmpty { loadedAddonIDs = ids }
    }

    @ViewBuilder private var content: some View {
        if model.isLoading && model.sections.isEmpty {
            ProgressView("Chargement des catalogues…")
                .frame(maxWidth: .infinity)
                .padding(.top, 120)
        } else if let error = model.errorMessage, model.sections.isEmpty {
            VStack(spacing: 16) {
                Image(systemName: "wifi.exclamationmark").font(.system(size: 60))
                Text("Impossible de charger les catalogues").font(.title3)
                Text(error).font(.callout).foregroundStyle(.secondary)
                Button("Réessayer") { Task { await loadCatalogs() } }
                    .padding(.top, 12)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 120)
        } else {
            ForEach(model.sections) { section in
                CatalogRowView(section: section)
            }
        }
    }
}
