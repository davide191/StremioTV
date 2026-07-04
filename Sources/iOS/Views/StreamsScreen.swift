import SwiftUI

/// Liste des flux d'un item. Lance la lecture (reprise + sous-titres) et
/// enregistre la progression sur le compte à l'arrêt.
struct StreamsScreen: View {
    let metaId: String
    let type: String
    let videoId: String
    let title: String
    let name: String
    let poster: String?
    let resumeOffsetMs: UInt64
    var episodeIds: [String] = []

    @Environment(AddonRepository.self) private var repo
    @Environment(LibraryStore.self) private var library
    @Environment(DownloadStore.self) private var downloads
    @State private var model = DetailViewModel()
    @State private var playback: PlaybackRequest?

    var body: some View {
        List {
            if model.isLoadingStreams {
                HStack(spacing: 10) { ProgressView(); Text("Recherche de flux…") }
            }
            if let note = model.note {
                Text(note).font(.callout).foregroundStyle(.secondary)
            }
            if !model.subtitles.isEmpty {
                Label("\(model.subtitles.count) sous-titres disponibles", systemImage: "captions.bubble")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(model.streams) { stream in
                streamRow(stream)
            }
        }
        .listStyle(.plain)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let bases = repo.addons.map(\.base)
            await model.loadStreams(type: type, id: videoId, bases: bases)
            await model.loadSubtitles(type: type, id: videoId, addons: repo.addons)
        }
        .fullScreenCover(item: $playback) { request in
            PlayerView(
                request: request,
                resolveNext: { currentVideoId in
                    await resolveNextEpisode(after: currentVideoId,
                                             episodeIds: request.episodeIds,
                                             providerBase: request.providerBase)
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

    private func streamRow(_ stream: StreamItem) -> some View {
        HStack(spacing: 12) {
            Button {
                if let url = stream.playableURL {
                    playback = PlaybackRequest(
                        url: url, metaId: metaId, type: type, name: name, poster: poster,
                        videoId: videoId, resumeOffsetMs: resumeOffsetMs, subtitles: model.subtitles,
                        episodeIds: episodeIds, providerBase: stream.sourceBase
                    )
                }
            } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Text(stream.headline).font(.headline)
                    if let subtitle = stream.subtitle {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(3)
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
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!stream.isDirectlyPlayable)

            downloadControl(for: stream)
        }
    }

    // MARK: - Téléchargement hors-ligne

    /// Affordance de téléchargement pour une source directe (masquée pour les
    /// torrents / HLS / formats non lisibles).
    @ViewBuilder private func downloadControl(for stream: StreamItem) -> some View {
        if let url = stream.playableURL, StreamDownloadRules.isLikelyDownloadable(url) {
            if let item = downloads.item(metaId: metaId, videoId: videoId) {
                existingDownloadControl(item)
            } else {
                Button { startDownload(stream, url: url) } label: {
                    Image(systemName: "arrow.down.circle").font(.title3)
                }
                .buttonStyle(.plain)
                .tint(.brand)
                .accessibilityLabel("Télécharger pour le hors-ligne")
            }
        }
    }

    @ViewBuilder private func existingDownloadControl(_ item: DownloadItem) -> some View {
        switch item.status {
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.title3).foregroundStyle(Color.brand)
                .accessibilityLabel("Téléchargé")
        case .downloading, .queued:
            Button { downloads.pause(id: item.id) } label: { progressRing(item.progress) }
                .buttonStyle(.plain)
                .accessibilityLabel("Mettre en pause")
        case .paused:
            Button { downloads.resume(id: item.id) } label: {
                Image(systemName: "arrow.down.circle").font(.title3)
            }
            .buttonStyle(.plain).tint(.brand)
            .accessibilityLabel("Reprendre")
        case .failed:
            Button { downloads.retry(id: item.id) } label: {
                Image(systemName: "arrow.clockwise.circle").font(.title3)
            }
            .buttonStyle(.plain).tint(.orange)
            .accessibilityLabel("Réessayer")
        }
    }

    private func progressRing(_ progress: Double) -> some View {
        ZStack {
            Circle().stroke(.gray.opacity(0.3), lineWidth: 2)
            Circle().trim(from: 0, to: max(0.02, progress))
                .stroke(Color.brand, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: "stop.fill").font(.system(size: 7)).foregroundStyle(.secondary)
        }
        .frame(width: 24, height: 24)
    }

    private func startDownload(_ stream: StreamItem, url: URL) {
        Task {
            await downloads.enqueue(
                sourceURL: url, metaId: metaId, type: type, videoId: videoId,
                name: name, videoTitle: title, poster: poster,
                streamTitle: stream.headline, subtitle: preferredSubtitle()
            )
        }
    }

    /// Sous-titre externe à télécharger avec la vidéo : uniquement la langue
    /// préférée persistée (v1), s'il y a une correspondance.
    private func preferredSubtitle() -> SubtitleItem? {
        let prefs = PlaybackPreferences()
        guard let lang = prefs.subtitleLanguage, lang != "OFF" else { return nil }
        return model.subtitles.first { $0.displayLanguage == lang }
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
}
