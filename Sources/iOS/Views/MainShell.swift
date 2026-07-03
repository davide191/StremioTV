import SwiftUI
import UIKit

/// Les quatre sections principales de l'app.
enum AppSection: String, CaseIterable, Identifiable {
    case home = "Accueil"
    case search = "Recherche"
    case library = "Bibliothèque"
    case settings = "Réglages"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home: "house.fill"
        case .search: "magnifyingglass"
        case .library: "rectangle.stack.fill"
        case .settings: "gearshape.fill"
        }
    }

    @ViewBuilder var screen: some View {
        switch self {
        case .home: HomeScreen()
        case .search: SearchScreen()
        case .library: LibraryScreen()
        case .settings: SettingsScreen()
        }
    }
}

/// Enveloppe de navigation **adaptative** :
/// - iPhone → `TabView` (barre d'onglets en bas) ;
/// - iPad   → `NavigationSplitView` (barre latérale + détail).
///
/// On aiguille sur l'**idiom de l'appareil** (stable) plutôt que sur la classe
/// de taille horizontale : cette dernière change quand l'iPad passe en Split
/// View / Slide Over, ce qui recréerait tout le conteneur et détruirait l'état
/// (view-models, catalogues chargés…). `NavigationSplitView` gère lui-même la
/// largeur compacte en repliant ses colonnes.
struct MainShell: View {
    var body: some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            SidebarShell()
        } else {
            TabShell()
        }
    }
}

/// iPhone : onglets classiques. Chaque section porte sa propre pile de navigation.
private struct TabShell: View {
    var body: some View {
        TabView {
            ForEach(AppSection.allCases) { section in
                section.screen
                    .tabItem { Label(section.rawValue, systemImage: section.icon) }
                    .tag(section)
            }
        }
    }
}

/// iPad : barre latérale + colonne de détail.
private struct SidebarShell: View {
    @State private var selection: AppSection? = .home

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.icon)
                    .tag(section)
            }
            .navigationTitle("StremioTV")
            .listStyle(.sidebar)
        } detail: {
            (selection ?? .home).screen
                .id(selection)
        }
    }
}
