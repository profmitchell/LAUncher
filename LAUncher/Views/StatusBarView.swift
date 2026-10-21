import SwiftUI

struct StatusBarView: View {
    @ObservedObject var session: PluginHostSession
    @ObservedObject var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    
    init(session: PluginHostSession) {
        self.session = session
        self.themeManager = session.themeManager
    }

    var body: some View {
        HStack(spacing: 16) {
            Button {
                session.openSettings(section: .audio)
            } label: {
                statusLabel(icon: "waveform.path", title: "Sample Rate", value: formattedSampleRate)
            }
            .buttonStyle(.plain)
            .help("Open Settings to change sample rate")

            Button {
                session.openSettings(section: .audio)
            } label: {
                statusLabel(icon: "hifispeaker", title: "Output", value: outputDeviceLabel)
            }
            .buttonStyle(.plain)
            .help("Open Settings to choose output device")

            Button {
                session.openSettings(section: .midi)
            } label: {
                statusLabel(
                    icon: "pianokeys",
                    title: "MIDI",
                    value: session.selectedMidiSource?.name ?? "All Sources"
                )
            }
            .buttonStyle(.plain)
            .help("Open Settings to choose MIDI input")

            if case let .error(message) = session.engineState {
                Divider().frame(height: 16)
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundColor(.yellow)
                    .lineLimit(2)
                    .help(message)
            } else if let message = session.lastErrorDescription, session.currentComponent == nil {
                Divider().frame(height: 16)
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundColor(.yellow)
                    .lineLimit(2)
                    .help(message)
            }

            Spacer()

            HStack(spacing: 8) {
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundStyle(.secondary)
                Slider(value: Binding(get: {
                    Double(session.masterGain)
                }, set: { newVal in
                    session.masterGain = Float(newVal)
                }), in: 0...1)
                    .frame(width: 140)
                Text(masterGainDb)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(width: 48, alignment: .trailing)
            }
        }
        .padding(12)
        .background(statusBackground)
        .overlay(
            Rectangle()
                .fill(borderColor)
                .frame(height: 1),
            alignment: .top
        )
        .animation(.easeInOut(duration: 0.2), value: themeManager.currentTheme.id)
    }

    private var outputDeviceLabel: String {
        session.selectedOutputDevice?.displayName ?? "None"
    }

    private func statusLabel(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
    }

    private var statusBackground: Color {
        let theme = themeManager.currentTheme
        return theme.containerBackground.color.opacity(0.75)
    }

    private var borderColor: Color {
        let theme = themeManager.currentTheme
        return theme.containerBorder.color
    }

    private var formattedSampleRate: String {
        let rate = session.sampleRate
        guard rate > 0 else { return "–" }
        if rate >= 1000 {
            let k = rate / 1000
            if abs(k.rounded() - k) < 0.01 {
                return "\(Int(k)) kHz"
            }
            return String(format: "%.1f kHz", k)
        }
        return "\(Int(rate)) Hz"
    }

    private var masterGainDb: String {
        let linear = max(0.000_1, Double(session.masterGain))
        let db = 20.0 * log10(linear)
        return String(format: "%0.1f dB", db)
    }
}
