import SwiftUI

/// Liste des flux d'un item. Lance la lecture (reprise + sous-titres) et
/// enregistre la progression sur le compte à l'arrêt.
///
/// Focus : chaque phase garde un contrôle focusable dans la page (voir
/// `LoadPhase`) — « Annuler » pendant la recherche, « Réessayer » sans flux,
/// sinon les flux, y compris non lisibles.
struct StreamsListView: View {
    let metaId: String
    let type: String
    let videoId: String        // épisode (= metaId pour un film)
    let title: String
    let name: String
    let poster: String?
    let resumeOffsetMs: UInt64
    var episodeIds: [String] = []

    @Environment(AddonRepository.self) private var repo
    @Environment(LibraryStore.self) private var library
    @State private var model = DetailViewModel()
    @State private var playback: PlaybackRequest?
    @State private var hasLoaded = false
    @FocusState private var focus: StreamsFocusTarget?

    private var phase: LoadPhase {
        LoadPhase(hasContent: !model.streams.isEmpty,
                  isFinished: hasLoaded && !model.isLoadingStreams)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScreenHeader(title: title)
            switch phase {
            case .loading: LoadingPlaceholder(message: "Recherche de flux…")
            case .empty: emptyState
            case .populated: streamList
            }
        }
        .task {
            // Une seule recherche par écran : au retour du lecteur, la liste
            // (et le flux que le système re-focalise) doit rester en place.
            guard !hasLoaded else { return }
            await load()
        }
        .onChange(of: phase) { _, newPhase in
            // Le bouton focalisé (« Annuler ») vient de disparaître : on
            // désigne explicitement son successeur dans la page.
            if let target = StreamsFocusTarget.after(newPhase, streams: model.streams) {
                focus = target
            }
        }
        .fullScreenCover(item: $playback) { request in
            PlayerView(
                request: request,
                resolveNext: { currentVideoId in
                    await resolveNextEpisode(after: currentVideoId, episodeIds: request.episodeIds, providerBase: request.providerBase)
                },
                onProgress: { playedVideoId, offset, duration in
                    Task {
                        await library.recordProgress(
                            metaId: metaId, type: type, name: name, poster: poster,
                            videoId: playedVideoId, timeOffsetMs: offset, durationMs: duration
                        )
                    }
                },
                onClose: { playback = nil }
            )
            .ignoresSafeArea()
        }
    }

    private func load() async {
        await model.loadStreams(type: type, id: videoId, bases: repo.addons.map(\.base))
        // Une recherche annulée (écran quitté) n'est pas un résultat vide.
        guard !Task.isCancelled else { return }
        hasLoaded = true
        await model.loadSubtitles(type: type, id: videoId, addons: repo.addons)
    }

    private var streamList: some View {
        List {
            if let note = model.note {
                Text(note).font(.callout).foregroundStyle(.secondary)
            }
            if !model.subtitles.isEmpty {
                Label("\(model.subtitles.count) sous-titres disponibles",
                      systemImage: "captions.bubble")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(model.streams) { stream in
                streamRow(stream)
                    .focused($focus, equals: .stream(stream.id))
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Aucun flux disponible", systemImage: "play.slash")
        } description: {
            Text(model.note ?? "")
        } actions: {
            Button("Réessayer") { Task { await load() } }
                .focused($focus, equals: .retry)
                .accessibilityIdentifier("streamsRetry")
        }
    }

    /// Résout l'épisode suivant en réutilisant **le même provider** (repli sur
    /// tous les add-ons sinon), avec ses sous-titres.
    private func resolveNextEpisode(after currentVideoId: String, episodeIds: [String], providerBase: String?) async -> PlaybackRequest? {
        guard let index = episodeIds.firstIndex(of: currentVideoId), index + 1 < episodeIds.count else { return nil }
        let nextId = episodeIds[index + 1]
        let client = AddonClient()

        var streams: [StreamItem] = []
        if let base = providerBase, let found = try? await client.streams(base: base, type: type, id: nextId) {
            streams = found.map { var s = $0; s.sourceBase = base; return s }
        }
        if !streams.contains(where: { $0.isDirectlyPlayable }) {
            for base in repo.addons.map(\.base) {
                if let found = try? await client.streams(base: base, type: type, id: nextId) {
                    streams += found.map { var s = $0; s.sourceBase = base; return s }
                }
            }
        }
        guard let chosen = streams.first(where: { $0.isDirectlyPlayable }), let url = chosen.playableURL else { return nil }

        await model.loadSubtitles(type: type, id: nextId, addons: repo.addons)
        return PlaybackRequest(
            url: url, metaId: metaId, type: type, name: name, poster: poster,
            videoId: nextId, resumeOffsetMs: 0, subtitles: model.subtitles,
            episodeIds: episodeIds, providerBase: chosen.sourceBase
        )
    }

    private func streamRow(_ stream: StreamItem) -> some View {
        Button {
            if let url = stream.playableURL {
                playback = PlaybackRequest(
                    url: url, metaId: metaId, type: type, name: name, poster: poster,
                    videoId: videoId, resumeOffsetMs: resumeOffsetMs, subtitles: model.subtitles,
                    episodeIds: episodeIds, providerBase: stream.sourceBase
                )
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(stream.headline).font(.headline)
                if let subtitle = stream.subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                if !stream.isDirectlyPlayable {
                    Label(
                        stream.isTorrent ? "Torrent — nécessite debrid/streaming-server" : "Format non lisible nativement",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption2)
                    .foregroundStyle(.orange)
                }
            }
            .padding(.vertical, 4)
            .opacity(stream.isDirectlyPlayable ? 1 : 0.6)
        }
        // Pas de `.disabled` : sur tvOS un bouton désactivé n'est pas
        // focusable, et une liste 100 % torrents ne laisserait aucun élément
        // focusable (ni défilable). L'action ignore déjà les flux non lisibles.
    }
}

/// Cible de focus de la liste des flux.
enum StreamsFocusTarget: Hashable {
    case retry
    case stream(String)

    /// Successeur d'« Annuler » à l'issue d'une recherche : le 1er flux lisible,
    /// sinon le 1er flux, sinon « Réessayer ». `nil` pendant le chargement
    /// (« Annuler » est alors le seul contrôle de la page).
    static func after(_ phase: LoadPhase, streams: [StreamItem]) -> StreamsFocusTarget? {
        switch phase {
        case .loading:
            return nil
        case .empty:
            return .retry
        case .populated:
            return (streams.first(where: \.isDirectlyPlayable) ?? streams.first).map { .stream($0.id) }
        }
    }
}
