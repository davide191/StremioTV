import SwiftUI

/// Panneau tactile de sélection des pistes (sous-titres / audio), présenté en
/// feuille modale au-dessus du lecteur.
struct TrackSelectionSheet: View {
    @Bindable var controller: TrackController
    var onClose: () -> Void

    @State private var tab = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $tab) {
                    Text("Sous-titres").tag(0)
                    Text("Audio (doublage)").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()

                List {
                    if tab == 0 { subtitleContent } else { audioContent }
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle("Pistes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Terminé", action: onClose)
                }
            }
        }
    }

    // MARK: - Sous-titres

    @ViewBuilder private var subtitleContent: some View {
        Section {
            ForEach(controller.subtitleOptions) { option in
                selectableRow(
                    title: option.language,
                    subtitle: option.source.isEmpty ? nil : option.source,
                    isSelected: option.id == controller.currentSubtitleId
                ) {
                    controller.currentSubtitleId = option.id
                    controller.selectSubtitle(option)
                }
            }
        }
        if controller.currentSubtitleId != "off" {
            Section("Synchronisation") {
                Stepper("Délai : \(controller.subtitleDelayMs) ms") {
                    controller.subtitleDelayMs += 250
                    controller.setDelay(controller.subtitleDelayMs)
                } onDecrement: {
                    controller.subtitleDelayMs -= 250
                    controller.setDelay(controller.subtitleDelayMs)
                }
            }
        }
    }

    // MARK: - Audio

    @ViewBuilder private var audioContent: some View {
        Section {
            if controller.audioOptions.isEmpty {
                Text("Aucune piste audio détectée.").foregroundStyle(.secondary)
            }
            ForEach(controller.audioOptions) { option in
                selectableRow(title: option.label, subtitle: nil,
                              isSelected: option.id == controller.currentAudioId) {
                    controller.currentAudioId = option.id
                    controller.selectAudio(option.id)
                }
            }
        }
    }

    private func selectableRow(title: String, subtitle: String?, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.primary)
                    if let subtitle {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark").foregroundStyle(Color.brand).fontWeight(.semibold)
                }
            }
            .contentShape(Rectangle())
        }
    }
}
