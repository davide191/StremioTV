import SwiftUI

/// Catalogue complet en grille, avec chargement progressif (pagination `skip`).
struct CatalogGridScreen: View {
    let title: String
    let base: String
    let type: String
    let catalogId: String

    @State private var model = CatalogGridViewModel()

    var body: some View {
        ScrollView {
            PosterGrid(metas: model.metas, onReachEnd: {
                Task { await model.loadMore(base: base, type: type, catalogId: catalogId) }
            })
            .padding(.vertical)

            if model.isLoading {
                ProgressView().padding(24)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await model.loadFirstPage(base: base, type: type, catalogId: catalogId)
        }
    }
}
