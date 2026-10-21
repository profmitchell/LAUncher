import SwiftUI

/// Quiet footer — I/O at a glance; tap opens Settings. Volume lives here.
struct StatusBarView: View {
    @ObservedObject var session: PluginHostSession
    @ObservedObject var themeManager: ThemeManager

    init(session: PluginHostSession) {
        self.session = session
        self.themeManager = session.themeManager
    }

    private var theme: AppTheme { themeManager.currentTheme }

    var body: some View {
        HStack(spacing: 0) {
            Button {
                session.openSettings(section: .audio)
            } label: {
                chip(formattedSampleRate)
            }
            .buttonStyle(.plain)
            .help("Sample rate — open Settings")

            separator

            Button {
                session.openSettings(section: .audio)
            } label: {
                chip(session.selectedOutputDevice?.displayName ?? "No output")
            }
            .buttonStyle(.plain)
            .help("Output device — open Settings")

            separator

            Button {
                session.openSettings(section: .midi)
            } label: {
                chip(session.selectedMidiSource?.name ?? "All MIDI")
            }
            .buttonStyle(.plain)
            .help("MIDI input — open Settings")

            if case let .error(message) = session.engineState {
                separator
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.yellow)
                    .lineLimit(1)
                    .help(message)
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(LauncherChrome.textMuted(theme))
                Slider(
                    value: Binding(
                        get: { Double(session.masterGain) },
                        set: { session.masterGain = Float($0) }
                    ),
                    in: 0...1
                )
                .frame(width: 110)
                .controlSize(.mini)
                Text(masterGainDb)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(LauncherChrome.textMuted(theme))
                    .frame(width: 48, alignment: .trailing)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(LauncherChrome.barBackground(theme))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(LauncherChrome.border(theme).opacity(0.45))
                .frame(height: 1)
        }
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(LauncherChrome.textMuted(theme))
            .lineLimit(1)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
    }

    private var separator: some View {
        Text("·")
            .font(.system(size: 11))
            .foregroundStyle(LauncherChrome.textMuted(theme).opacity(0.45))
            .padding(.horizontal, 8)
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
