import SwiftUI

struct StatusBarView: View {
    @ObservedObject var session: PluginHostSession
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 24) {
            statusLabel(icon: "waveform.path", title: "Sample Rate", value: formattedSampleRate)
            statusLabel(icon: "timer", title: "Buffer", value: formattedBufferDuration)

            if let midi = session.selectedMidiSource {
                statusLabel(icon: "pianokeys", title: "MIDI", value: midi.name)
            } else {
                statusLabel(icon: "pianokeys", title: "MIDI", value: "All Sources")
            }

            if case let .error(message) = session.engineState {
                Divider()
                    .frame(height: 16)
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundColor(.yellow)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(12)
        .background(statusBackground)
        .overlay(
            Rectangle()
                .fill(borderColor)
                .frame(height: 1),
            alignment: .top
        )
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
            }
        }
    }

    private var statusBackground: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.04)
            : Color.white.opacity(0.75)
    }

    private var borderColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.08)
            : Color.black.opacity(0.08)
    }

    private var formattedSampleRate: String {
        let rate = session.sampleRate
        guard rate > 0 else { return "–" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: rate)) ?? "\(Int(rate))"
    }

    private var formattedBufferDuration: String {
        let duration = session.bufferDuration
        guard duration > 0 else { return "–" }
        let milliseconds = duration * 1000
        return String(format: "%.2f ms", milliseconds)
    }
}
