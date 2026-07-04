import SwiftUI

/// Onglet **Téléchargements** : les médias disponibles hors-ligne (et ceux en
/// cours). Fonctionne **sans compte et sans réseau** — c'est le cœur du mode
/// hors-ligne. Lit le fichier local via le lecteur existant.
struct DownloadsScreen: View {
    @Environment(DownloadStore.self) private var downloads
    @Environment(NetworkMonitor.self) private var network

    @State private var playback: PlaybackRequest?
    @State private var playingItem: DownloadItem?

    var body: some View {
        NavigationStack {
            Group {
                if downloads.items.isEmpty {
                    emptyState
                } else {
                    List {
                        if network.isOffline {
                            offlineBanner
                        }
                        ForEach(downloads.sortedItems) { item in
                            DownloadRow(item: item, onPlay: { play(item) })
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        downloads.delete(id: item.id)
                                    } label: {
                                        Label("Supprimer", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Téléchargements")
        }
        .fullScreenCover(item: $playback) { request in
            PlayerView(
                request: request,
                onProgress: { _, offset, duration in
                    if let id = playingItem?.id {
                        downloads.recordPlaybackProgress(id: id, offsetMs: offset, durationMs: duration)
                    }
                },
                onClose: { playback = nil }
            )
            .ignoresSafeArea()
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Aucun téléchargement", systemImage: "arrow.down.circle")
        } description: {
            Text("Télécharge un film ou un épisode depuis ses sources pour le regarder hors-ligne.")
        }
    }

    private var offlineBanner: some View {
        Label("Mode hors-ligne — lecture depuis l'appareil", systemImage: "wifi.slash")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .listRowSeparator(.hidden)
    }

    private func play(_ item: DownloadItem) {
        guard item.isPlayable else { return }
        playingItem = item
        playback = PlaybackRequest(
            url: downloads.localURL(for: item),
            metaId: item.metaId, type: item.type, name: item.name, poster: item.poster,
            videoId: item.videoId, resumeOffsetMs: item.resumeOffsetMs,
            subtitles: downloads.localSubtitle(for: item).map { [$0] } ?? []
        )
    }
}

/// Une ligne de la liste des téléchargements : vignette, titre, état.
private struct DownloadRow: View {
    @Environment(DownloadStore.self) private var downloads
    let item: DownloadItem
    let onPlay: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: item.poster ?? "")) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                RoundedRectangle(cornerRadius: 6).fill(.gray.opacity(0.25))
            }
            .frame(width: 54, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name).font(.subheadline.weight(.semibold)).lineLimit(2)
                if item.type == "series", item.videoTitle != item.name, !item.videoTitle.isEmpty {
                    Text(item.videoTitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                statusLine
            }
            Spacer(minLength: 8)
            trailingControl
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { if item.isPlayable { onPlay() } }
    }

    @ViewBuilder private var statusLine: some View {
        switch item.status {
        case .completed:
            Label(item.sizeText ?? "Prêt hors-ligne", systemImage: "checkmark.circle.fill")
                .font(.caption).foregroundStyle(Color.brand)
        case .downloading, .queued:
            VStack(alignment: .leading, spacing: 3) {
                ProgressView(value: item.progress).tint(.brand)
                Text(item.sizeText ?? "Téléchargement…").font(.caption2).foregroundStyle(.secondary)
            }
        case .paused:
            Label("En pause — \(item.sizeText ?? "")", systemImage: "pause.circle")
                .font(.caption).foregroundStyle(.secondary)
        case .failed:
            Label(item.failureReason ?? "Échec du téléchargement", systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(.orange).lineLimit(2)
        }
    }

    @ViewBuilder private var trailingControl: some View {
        switch item.status {
        case .completed:
            Image(systemName: "play.circle.fill").font(.title2).foregroundStyle(Color.brand)
        case .downloading, .queued:
            Button { downloads.pause(id: item.id) } label: {
                Image(systemName: "pause.circle").font(.title2)
            }.buttonStyle(.plain).tint(.secondary)
        case .paused:
            Button { downloads.resume(id: item.id) } label: {
                Image(systemName: "arrow.down.circle").font(.title2)
            }.buttonStyle(.plain).tint(.brand)
        case .failed:
            Button { downloads.retry(id: item.id) } label: {
                Image(systemName: "arrow.clockwise.circle").font(.title2)
            }.buttonStyle(.plain).tint(.brand)
        }
    }
}
