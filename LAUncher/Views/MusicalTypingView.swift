import SwiftUI

struct MusicalTypingView: View {
    @ObservedObject var session: PluginHostSession
    @State private var activeNotes: Set<UInt8> = []
    @State private var octaveOffset: Int = 4
    @Environment(\.colorScheme) private var colorScheme

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
                    octaveOffset = max(octaveOffset - 1, 1)
                } label: {
                    Label("Octave Down", systemImage: "chevron.down")
                }
                .buttonStyle(.bordered)

                Text("QWERTY Piano • Octave \(octaveOffset)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button {
                    octaveOffset = min(octaveOffset + 1, 8)
                } label: {
                    Label("Octave Up", systemImage: "chevron.up")
                }
                .buttonStyle(.bordered)
            }

            ZStack {
                whiteKeyRow
                blackKeyRow
                    .padding(.horizontal, 36)
                    .offset(y: -22)
            }
        }
        .padding(16)
        .background(musicalTypingBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                    isActive: activeNotes.contains(noteNumber(for: key.semitone)),
                    session: session,
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
                    isActive: activeNotes.contains(noteNumber(for: key.semitone)),
                    session: session,
                    onChange: handleNoteStateChange
                )
                .frame(width: 48)
            }
        }
    }

    private func handleNoteStateChange(_ note: UInt8, isPressed: Bool) {
        if isPressed {
            activeNotes.insert(note)
            session.sendVirtualNoteOn(noteNumber: note, velocity: 100)
        } else {
            activeNotes.remove(note)
            session.sendVirtualNoteOff(noteNumber: note)
        }
    }

    private func noteNumber(for semitone: Int) -> UInt8 {
        let base = octaveOffset * 12
        return UInt8(clamping: base + semitone)
    }
}

private struct MusicalTypingKey: View {
    let label: String
    let noteNumber: UInt8
    let isBlackKey: Bool
    let isActive: Bool
    let session: PluginHostSession
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
