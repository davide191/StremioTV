import SwiftUI
import MobileVLCKit

/// Lecteur vidéo iOS : habillage **tactile** au-dessus du cœur VLC partagé
/// (`VLCPlayerCoreController`). Tap pour afficher/masquer les contrôles,
/// scrubber déplaçable, boutons lecture/saut/pistes/épisode suivant.
struct PlayerView: UIViewControllerRepresentable {
    let request: PlaybackRequest
    var resolveNext: (_ currentVideoId: String) async -> PlaybackRequest? = { _ in nil }
    var onProgress: (_ videoId: String, _ timeOffsetMs: UInt64, _ durationMs: UInt64) -> Void = { _, _, _ in }
    var onClose: () -> Void = {}

    func makeUIViewController(context: Context) -> IOSPlayerViewController {
        IOSPlayerViewController(request: request, resolveNext: resolveNext, onProgress: onProgress, onClose: onClose)
    }

    func updateUIViewController(_ controller: IOSPlayerViewController, context: Context) {}
}

/// Contrôleur iOS : overlay tactile + gestes.
final class IOSPlayerViewController: VLCPlayerCoreController, UIGestureRecognizerDelegate {
    private let controlsContainer = UIView()
    private let dimView = UIView()
    private let titleLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private let playPauseButton = UIButton(type: .system)
    private let skipBackButton = UIButton(type: .system)
    private let skipForwardButton = UIButton(type: .system)
    private let tracksButton = UIButton(type: .system)
    private let nextButton = UIButton(type: .system)
    private let slider = UISlider()
    private let currentTimeLabel = UILabel()
    private let durationLabel = UILabel()

    private var controlsVisible = true
    private var isScrubbing = false
    private var autoHideWorkItem: DispatchWorkItem?

    // MARK: - Barre d'état / indicateur home

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { !controlsVisible }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .allButUpsideDown }

    // MARK: - Contrôles

    override func setupControls() {
        controlsContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controlsContainer)
        NSLayoutConstraint.activate([
            controlsContainer.topAnchor.constraint(equalTo: view.topAnchor),
            controlsContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            controlsContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controlsContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        dimView.translatesAutoresizingMaskIntoConstraints = false
        dimView.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        dimView.isUserInteractionEnabled = false
        controlsContainer.addSubview(dimView)
        NSLayoutConstraint.activate([
            dimView.topAnchor.constraint(equalTo: controlsContainer.topAnchor),
            dimView.bottomAnchor.constraint(equalTo: controlsContainer.bottomAnchor),
            dimView.leadingAnchor.constraint(equalTo: controlsContainer.leadingAnchor),
            dimView.trailingAnchor.constraint(equalTo: controlsContainer.trailingAnchor),
        ])

        setupTopBar()
        setupCenterControls()
        setupBottomBar()

        // Tap n'importe où (hors bouton/slider) pour afficher/masquer.
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tap.delegate = self
        view.addGestureRecognizer(tap)
    }

    private func setupTopBar() {
        var closeConfig = UIButton.Configuration.plain()
        closeConfig.image = UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold))
        closeConfig.baseForegroundColor = .white
        closeButton.configuration = closeConfig
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(didTapClose), for: .touchUpInside)
        controlsContainer.addSubview(closeButton)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.textColor = .white
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.text = currentRequest.name
        titleLabel.lineBreakMode = .byTruncatingTail
        controlsContainer.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: controlsContainer.safeAreaLayoutGuide.topAnchor, constant: 8),
            closeButton.leadingAnchor.constraint(equalTo: controlsContainer.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44),

            titleLabel.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: closeButton.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: controlsContainer.safeAreaLayoutGuide.trailingAnchor, constant: -16),
        ])
    }

    private func setupCenterControls() {
        configureSymbolButton(skipBackButton, symbol: "gobackward.15", pointSize: 34)
        configureSymbolButton(playPauseButton, symbol: "pause.fill", pointSize: 52)
        configureSymbolButton(skipForwardButton, symbol: "goforward.15", pointSize: 34)
        skipBackButton.addTarget(self, action: #selector(didTapSkipBack), for: .touchUpInside)
        playPauseButton.addTarget(self, action: #selector(didTapPlayPause), for: .touchUpInside)
        skipForwardButton.addTarget(self, action: #selector(didTapSkipForward), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [skipBackButton, playPauseButton, skipForwardButton])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 44
        controlsContainer.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: controlsContainer.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: controlsContainer.centerYAnchor),
        ])
    }

    private func setupBottomBar() {
        for label in [currentTimeLabel, durationLabel] {
            label.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
            label.textColor = .white
            label.text = "00:00"
            label.translatesAutoresizingMaskIntoConstraints = false
        }

        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.minimumValue = 0
        slider.maximumValue = 1
        slider.minimumTrackTintColor = UIColor(Color.brand)
        slider.addTarget(self, action: #selector(sliderTouchDown), for: .touchDown)
        slider.addTarget(self, action: #selector(sliderChanged), for: .valueChanged)
        slider.addTarget(self, action: #selector(sliderTouchUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])

        let timeRow = UIStackView(arrangedSubviews: [currentTimeLabel, slider, durationLabel])
        timeRow.translatesAutoresizingMaskIntoConstraints = false
        timeRow.axis = .horizontal
        timeRow.alignment = .center
        timeRow.spacing = 12

        configureSymbolButton(tracksButton, symbol: "captions.bubble", pointSize: 20)
        configureSymbolButton(nextButton, symbol: "forward.end.fill", pointSize: 20)
        tracksButton.addTarget(self, action: #selector(didTapTracks), for: .touchUpInside)
        nextButton.addTarget(self, action: #selector(didTapNext), for: .touchUpInside)
        nextButton.isHidden = !hasNextEpisode

        let actionRow = UIStackView(arrangedSubviews: [UIView(), tracksButton, nextButton])
        actionRow.translatesAutoresizingMaskIntoConstraints = false
        actionRow.axis = .horizontal
        actionRow.alignment = .center
        actionRow.spacing = 24

        let bottomStack = UIStackView(arrangedSubviews: [timeRow, actionRow])
        bottomStack.translatesAutoresizingMaskIntoConstraints = false
        bottomStack.axis = .vertical
        bottomStack.spacing = 8
        controlsContainer.addSubview(bottomStack)
        NSLayoutConstraint.activate([
            bottomStack.leadingAnchor.constraint(equalTo: controlsContainer.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            bottomStack.trailingAnchor.constraint(equalTo: controlsContainer.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            bottomStack.bottomAnchor.constraint(equalTo: controlsContainer.safeAreaLayoutGuide.bottomAnchor, constant: -12),
        ])
    }

    private func configureSymbolButton(_ button: UIButton, symbol: String, pointSize: CGFloat) {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: pointSize, weight: .medium))
        config.baseForegroundColor = .white
        button.configuration = config
        button.translatesAutoresizingMaskIntoConstraints = false
    }

    // MARK: - Hooks

    override func onLoadNewRequest(_ request: PlaybackRequest) {
        titleLabel.text = request.name
        nextButton.isHidden = !hasNextEpisode
        showControls(autoHide: true)
    }

    override func onTimeUpdate(currentMs: UInt64, durationMs: UInt64, position: Float) {
        if !isScrubbing {
            slider.value = position
            currentTimeLabel.text = format(ms: currentMs)
        }
        if durationMs > 0 { durationLabel.text = format(ms: durationMs) }
    }

    override func onPlaybackStateChanged(isPlaying: Bool) {
        let symbol = isPlaying ? "pause.fill" : "play.fill"
        playPauseButton.configuration?.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 52, weight: .medium))
        if isPlaying { scheduleAutoHide() } else { autoHideWorkItem?.cancel() }
    }

    override func onRenderedFirstFrame() {
        showControls(autoHide: true)
    }

    override func presentTracks(_ controller: TrackController) {
        let sheet = TrackSelectionSheet(controller: controller) { [weak self] in
            self?.dismiss(animated: true)
        }
        let host = UIHostingController(rootView: sheet)
        if let presentation = host.sheetPresentationController {
            presentation.detents = [.medium(), .large()]
            presentation.prefersGrabberVisible = true
        }
        present(host, animated: true)
    }

    // MARK: - Actions

    @objc private func didTapClose() { closePlayer() }
    @objc private func didTapPlayPause() { togglePlayPause(); scheduleAutoHide() }
    @objc private func didTapSkipBack() { skipBackward(); scheduleAutoHide() }
    @objc private func didTapSkipForward() { skipForward(); scheduleAutoHide() }
    @objc private func didTapTracks() { autoHideWorkItem?.cancel(); openTrackMenu() }
    @objc private func didTapNext() { goNext() }

    @objc private func handleTap() {
        setControls(visible: !controlsVisible)
    }

    // MARK: - Scrubber

    @objc private func sliderTouchDown() {
        isScrubbing = true
        autoHideWorkItem?.cancel()
    }

    @objc private func sliderChanged() {
        // Mise à l'échelle AVANT conversion : slider.value ∈ [0,1] (Float), donc
        // convertir d'abord en entier donnerait toujours 0.
        let previewMs = UInt64(Double(slider.value) * Double(durationMs))
        currentTimeLabel.text = format(ms: previewMs)
    }

    @objc private func sliderTouchUp() {
        seek(toPosition: slider.value)
        isScrubbing = false
        scheduleAutoHide()
    }

    // MARK: - Visibilité des contrôles

    private func showControls(autoHide: Bool) {
        setControls(visible: true)
        if autoHide { scheduleAutoHide() }
    }

    private func setControls(visible: Bool) {
        controlsVisible = visible
        controlsContainer.isUserInteractionEnabled = visible
        UIView.animate(withDuration: 0.25) {
            self.controlsContainer.alpha = visible ? 1 : 0
        }
        setNeedsUpdateOfHomeIndicatorAutoHidden()
        if visible { scheduleAutoHide() } else { autoHideWorkItem?.cancel() }
    }

    private func scheduleAutoHide() {
        autoHideWorkItem?.cancel()
        guard isPlaying else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.isScrubbing else { return }
            self.setControls(visible: false)
        }
        autoHideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: work)
    }

    // MARK: - UIGestureRecognizerDelegate

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // Ne pas déclencher le tap « toggle » quand on touche un bouton ou le slider.
        !(touch.view is UIControl)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Notre tap doit survivre à l'arbitrage face aux recognizers tiers
        // (SwiftUI, libVLC…) éventuellement posés sur la même hiérarchie.
        true
    }
}
