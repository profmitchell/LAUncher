import SwiftUI
import AVFoundation

/// Plain-language Settings for audio devices, sample rate, MIDI, and theme.
struct SettingsView: View {
    @ObservedObject var session: PluginHostSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationSplitView {
            List(PluginHostSession.SettingsSection.allCases, selection: $session.settingsSection) { section in
                Label(section.rawValue, systemImage: section.systemImage)
                    .tag(section)
            }
            .navigationTitle("Settings")
            .safeAreaInset(edge: .bottom) {
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
        } detail: {
            Group {
                switch session.settingsSection {
                case .audio:
                    audioSection
                case .midi:
                    midiSection
                case .appearance:
                    appearanceSection
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(24)
            .navigationTitle(session.settingsSection.rawValue)
        }
        .frame(minWidth: 640, minHeight: 420)
    }

    // MARK: - Audio

    private var audioSection: some View {
        Form {
            Section {
                Picker("Output", selection: $session.selectedOutputDevice) {
                    Text("None").tag(Optional<AudioDevice>.none)
                    ForEach(session.outputDevices) { device in
                        Text(device.displayName).tag(Optional(device))
                    }
                }
                Picker("Input", selection: $session.selectedInputDevice) {
                    Text("None (test tone for effects)").tag(Optional<AudioDevice>.none)
                    ForEach(session.inputDevices) { device in
                        Text(device.displayName).tag(Optional(device))
                    }
                }
                HStack {
                    Spacer()
                    Button("Refresh Devices") {
                        session.audioDeviceManager.refreshDevices()
                    }
                }
            } header: {
                Text("Devices")
            } footer: {
                Text("Effects like Ohmicide need either an input device or a built-in test tone. Instruments only need output.")
            }

            Section {
                Picker("Sample Rate", selection: sampleRateBinding) {
                    ForEach(session.availableOutputSampleRates, id: \.self) { rate in
                        Text(formatRate(rate)).tag(rate)
                    }
                }
                .disabled(session.selectedOutputDevice == nil)

                LabeledContent("Buffer") {
                    Text(bufferLabel)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Engine") {
                    Text(session.engineManager.isRunning ? "Running" : "Stopped")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Format")
            } footer: {
                Text("Sample rate is set on your output device. If a plugin won’t load, try 48 kHz.")
            }
        }
        .formStyle(.grouped)
    }

    private var sampleRateBinding: Binding<Double> {
        Binding(
            get: {
                if let device = session.selectedOutputDevice {
                    let rate = session.audioDeviceManager.nominalSampleRate(for: device.id)
                    if rate > 0 { return rate }
                }
                return session.sampleRate > 0 ? session.sampleRate : 48_000
            },
            set: { session.setOutputSampleRate($0) }
        )
    }

    private var bufferLabel: String {
        if let frames = session.outputBufferFrameSize, session.sampleRate > 0 {
            let ms = Double(frames) / session.sampleRate * 1000
            return "\(frames) frames · \(String(format: "%.1f", ms)) ms"
        }
        return "—"
    }

    private func formatRate(_ rate: Double) -> String {
        if rate >= 1000 {
            let k = rate / 1000
            if abs(k.rounded() - k) < 0.01 {
                return "\(Int(k)) kHz"
            }
            return String(format: "%.1f kHz", k)
        }
        return "\(Int(rate)) Hz"
    }

    // MARK: - MIDI

    private var midiSection: some View {
        Form {
            Section {
                Picker("MIDI Input", selection: $session.selectedMidiSource) {
                    Text("All Available").tag(Optional<MidiSource>.none)
                    ForEach(session.midiSources) { source in
                        Text(source.name).tag(Optional(source))
                    }
                }
                HStack {
                    Spacer()
                    Button("Refresh MIDI") {
                        session.midiManager.refreshSources()
                    }
                }
            } header: {
                Text("Controller")
            } footer: {
                Text("Choose a MIDI keyboard, or enable QWERTY Piano from More (A = C).")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        Form {
            Section {
                ForEach(session.themeManager.availableThemes) { theme in
                    Button {
                        session.themeManager.currentTheme = theme
                    } label: {
                        HStack {
                            Text(theme.name)
                            Spacer()
                            if session.themeManager.currentTheme.id == theme.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Theme")
            }
        }
        .formStyle(.grouped)
    }
}
