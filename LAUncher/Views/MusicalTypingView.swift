import SwiftUI

struct MusicalTypingView: View {
    @ObservedObject var session: PluginHostSession
    @ObservedObject private var manager: MusicalTypingManager
    @Environment(\.colorScheme) private var colorScheme

    init(session: PluginHostSession) {
        self.session = session
        self.manager = session.musicalTypingManager
    }

    private let whiteKeys: [(label: String, semitone: Int)] = [
        ("Z", 0), ("X", 2), ("C", 4), ("V", 5), ("B", 7), ("N", 9), ("M", 11)
    ]

    private let blackKeys: [(label: String, semitone: Int)] = [
        ("S", 1), ("D", 3), ("G", 6), ("H", 8), ("J", 10)
    ]

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button {
                    manager.baseOctave = max(manager.baseOctave - 1, 1)
                } label: {
                    Label("Octave Down", systemImage: "chevron.down")
                }
                .buttonStyle(.bordered)
                .help("Octave down ([)")

                Text("QWERTY Piano • Octave \(manager.baseOctave)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button {
                    manager.baseOctave = min(manager.baseOctave + 1, 8)
                } label: {
                    Label("Octave Up", systemImage: "chevron.up")
                }
                .buttonStyle(.bordered)
                .help("Octave up (])")

                Divider()
                    .frame(height: 20)

                Label("Velocity", systemImage: "speaker.wave.2")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(
                    value: Binding(
                        get: { Double(manager.velocity) },
                        set: { manager.velocity = UInt8($0.rounded()) }
                    ),
                    in: 1...127,
                    step: 1
                )
                .frame(width: 120)
            }

            ZStack {
                whiteKeyRow
                blackKeyRow
                    .padding(.horizontal, 36)
                    .offset(y: -22)
            }
        }
        .padding(16)
        .launcherGlassPanel(cornerRadius: 16, fallbackColor: musicalTypingBackground)
        .shadow(color: shadowColor, radius: 8, y: 4)
        .padding(.horizontal, 24)
    }

    private var whiteKeyRow: some View {
        HStack(spacing: 6) {
            ForEach(whiteKeys, id: \.label) { key in
                MusicalTypingKey(
                    label: key.label,
                    noteNumber: noteNumber(for: key.semitone),
                    isBlackKey: false,
                    isActive: manager.activeNotes.contains(noteNumber(for: key.semitone)),
                    manager: manager,
                    onChange: handleNoteStateChange
                )
            }
        }
    }

    private var blackKeyRow: some View {
        HStack(spacing: 6) {
            ForEach(blackKeys, id: \.label) { key in
                MusicalTypingKey(
                    label: key.label,
                    noteNumber: noteNumber(for: key.semitone),
                    isBlackKey: true,
                    isActive: manager.activeNotes.contains(noteNumber(for: key.semitone)),
                    manager: manager,
                    onChange: handleNoteStateChange
                )
                .frame(width: 48)
            }
        }
    }

    private func handleNoteStateChange(_ note: UInt8, isPressed: Bool) {
        if isPressed {
            manager.playPreview(note: note)
        } else {
            manager.stopPreview(note: note)
        }
    }

    private func noteNumber(for semitone: Int) -> UInt8 {
        let base = manager.baseOctave * 12 + manager.transpose
        return UInt8(clamping: base + semitone)
    }
}

private struct MusicalTypingKey: View {
    let label: String
    let noteNumber: UInt8
    let isBlackKey: Bool
    let isActive: Bool
    let manager: MusicalTypingManager
    let onChange: (_ note: UInt8, _ isPressed: Bool) -> Void

    @State private var isPressed = false

    var body: some View {
        RoundedRectangle(cornerRadius: isBlackKey ? 8 : 10, style: .continuous)
            .fill(keyColor)
            .overlay(
                Text(label)
                    .font(.headline)
                    .foregroundStyle(isBlackKey ? .white : .black)
            )
            .frame(width: isBlackKey ? 54 : 60, height: isBlackKey ? 100 : 140)
            .overlay(
                RoundedRectangle(cornerRadius: isBlackKey ? 8 : 10, style: .continuous)
                    .stroke(isActive ? Color.accentColor : outlineColor, lineWidth: isActive ? 3 : 1)
            )
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed {
                        isPressed = true
                        onChange(noteNumber, true)
                    }
                }
                .onEnded { _ in
                    if isPressed {
                        isPressed = false
                        onChange(noteNumber, false)
                    }
                }
            )
            .onDisappear {
                if isPressed {
                    onChange(noteNumber, false)
                }
            }
    }

    private var keyColor: LinearGradient {
        if isBlackKey {
            return LinearGradient(colors: [.black.opacity(0.85), .black.opacity(0.65)], startPoint: .top, endPoint: .bottom)
        } else {
            return LinearGradient(colors: [.white, .white.opacity(0.95)], startPoint: .top, endPoint: .bottom)
        }
    }

    private var outlineColor: Color {
        Color.black.opacity(0.2)
    }
}

private extension MusicalTypingView {
    var musicalTypingBackground: Color {
        colorScheme == .dark
            ? Color.black.opacity(0.35)
            : Color.white.opacity(0.85)
    }

    var shadowColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.6) : Color.black.opacity(0.15)
    }
}

private extension View {
    @ViewBuilder
    func launcherGlassPanel(cornerRadius: CGFloat, fallbackColor: Color) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
        } else {
            self
                .background(fallbackColor)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}
