import SwiftUI
import TVVLCKit

/// Lecteur vidéo tvOS : habillage **télécommande** au-dessus du cœur VLC partagé
/// (`VLCPlayerCoreController`). Play/pause, saut ±15 s, menu pistes (▲),
/// épisode suivant (▼), Menu pour quitter.
struct PlayerView: UIViewControllerRepresentable {
    let request: PlaybackRequest
    var resolveNext: (_ currentVideoId: String) async -> PlaybackRequest? = { _ in nil }
    var onProgress: (_ videoId: String, _ timeOffsetMs: UInt64, _ durationMs: UInt64) -> Void = { _, _, _ in }
    var onClose: () -> Void = {}

    init(request: PlaybackRequest,
         resolveNext: @escaping (String) async -> PlaybackRequest? = { _ in nil },
         onProgress: @escaping (String, UInt64, UInt64) -> Void = { _, _, _ in },
         onClose: @escaping () -> Void = {}) {
        self.request = request
        self.resolveNext = resolveNext
        self.onProgress = onProgress
        self.onClose = onClose
    }

    /// Lecture simple (chemins de test) sans contexte de progression.
    init(url: URL, onClose: @escaping () -> Void = {}) {
        self.init(
            request: PlaybackRequest(url: url, metaId: "", type: "movie",
                                     name: url.lastPathComponent, poster: nil,
                                     videoId: "", resumeOffsetMs: 0, subtitles: []),
            onClose: onClose
        )
    }

    func makeUIViewController(context: Context) -> TVPlayerViewController {
        TVPlayerViewController(request: request, resolveNext: resolveNext, onProgress: onProgress, onClose: onClose)
    }

    func updateUIViewController(_ controller: TVPlayerViewController, context: Context) {}
}

/// Contrôleur tvOS : overlay statique + navigation à la télécommande.
final class TVPlayerViewController: VLCPlayerCoreController {
    private let controls = UIView()
    private let progress = UIProgressView(progressViewStyle: .default)
    private let currentTimeLabel = UILabel()
    private let durationLabel = UILabel()
    private let titleLabel = UILabel()
    private let hintLabel = UILabel()
    private var controlsHideWorkItem: DispatchWorkItem?

    // MARK: - Overlay

    override func setupControls() {
        controls.translatesAutoresizingMaskIntoConstraints = false
        controls.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        controls.layer.cornerRadius = 14
        view.addSubview(controls)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.textColor = .white
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.text = currentRequest.name

        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        hintLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        hintLabel.font = .preferredFont(forTextStyle: .caption1)
        hintLabel.text = hasNextEpisode
            ? "▲ pistes   ◀▶ ±15 s   ▼ épisode suivant   Menu : quitter"
            : "▲ pistes audio / sous-titres   ◀▶ ±15 s   Menu : quitter"

        progress.translatesAutoresizingMaskIntoConstraints = false
        progress.progressTintColor = .white
        progress.trackTintColor = UIColor.white.withAlphaComponent(0.3)

        for label in [currentTimeLabel, durationLabel] {
            label.font = .monospacedDigitSystemFont(ofSize: 28, weight: .regular)
            label.textColor = .white
            label.text = "00:00"
        }

        let timeStack = UIStackView(arrangedSubviews: [currentTimeLabel, progress, durationLabel])
        timeStack.translatesAutoresizingMaskIntoConstraints = false
        timeStack.axis = .horizontal
        timeStack.spacing = 24
        timeStack.alignment = .center

        controls.addSubview(titleLabel)
        controls.addSubview(timeStack)
        controls.addSubview(hintLabel)

        NSLayoutConstraint.activate([
            controls.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 80),
            controls.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -80),
            controls.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -60),

            titleLabel.topAnchor.constraint(equalTo: controls.topAnchor, constant: 24),
            titleLabel.leadingAnchor.constraint(equalTo: controls.leadingAnchor, constant: 32),
            titleLabel.trailingAnchor.constraint(equalTo: controls.trailingAnchor, constant: -32),

            timeStack.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            timeStack.leadingAnchor.constraint(equalTo: controls.leadingAnchor, constant: 32),
            timeStack.trailingAnchor.constraint(equalTo: controls.trailingAnchor, constant: -32),

            hintLabel.topAnchor.constraint(equalTo: timeStack.bottomAnchor, constant: 12),
            hintLabel.leadingAnchor.constraint(equalTo: controls.leadingAnchor, constant: 32),
            hintLabel.bottomAnchor.constraint(equalTo: controls.bottomAnchor, constant: -24),
        ])

        showControls(autoHide: true)
    }

    // MARK: - Hooks

    override func onLoadNewRequest(_ request: PlaybackRequest) {
        titleLabel.text = request.name
        showControls(autoHide: true)
    }

    override func onTimeUpdate(currentMs: UInt64, durationMs: UInt64, position: Float) {
        progress.setProgress(position, animated: false)
        currentTimeLabel.text = format(ms: currentMs)
        if durationMs > 0 { durationLabel.text = format(ms: durationMs) }
    }

    override func presentTracks(_ controller: TrackController) {
        let panel = TrackSelectionView(controller: controller) { [weak self] in
            self?.dismiss(animated: true)
        }
        let host = UIHostingController(rootView: panel)
        host.modalPresentationStyle = .overFullScreen
        host.view.backgroundColor = .clear
        present(host, animated: true)
    }

    // MARK: - Télécommande

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var handled = true
        for press in presses {
            switch press.type {
            case .playPause, .select:
                togglePlayPause(); showControls(autoHide: true)
            case .leftArrow:
                skipBackward(); showControls(autoHide: true)
            case .rightArrow:
                skipForward(); showControls(autoHide: true)
            case .upArrow:
                openTrackMenu()
            case .downArrow:
                goNext()
            case .menu:
                closePlayer()
            default:
                handled = false
            }
        }
        if !handled { super.pressesBegan(presses, with: event) }
    }

    // MARK: - Overlay auto-masquant

    private func showControls(autoHide: Bool) {
        controlsHideWorkItem?.cancel()
        UIView.animate(withDuration: 0.2) { self.controls.alpha = 1 }
        guard autoHide else { return }
        let work = DispatchWorkItem { [weak self] in
            UIView.animate(withDuration: 0.3) { self?.controls.alpha = 0 }
        }
        controlsHideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
    }
}
