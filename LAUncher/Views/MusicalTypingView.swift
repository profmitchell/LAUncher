import SwiftUI

/// Logic Pro–style Musical Typing window: labeled chromatic keys from A (C) through '.
struct MusicalTypingView: View {
    @ObservedObject var session: PluginHostSession
    @ObservedObject private var manager: MusicalTypingManager
    @Environment(\.colorScheme) private var colorScheme

    init(session: PluginHostSession) {
        self.session = session
        self.manager = session.musicalTypingManager
    }

    var body: some View {
        VStack(spacing: 10) {
            controlsRow
            piano
            legendRow
        }
        .padding(14)
        .launcherGlassPanel(cornerRadius: 16, fallbackColor: musicalTypingBackground)
        .shadow(color: shadowColor, radius: 8, y: 4)
        .padding(.horizontal, 16)
        .background(
            MusicalTypingKeyCaptureView(manager: manager, enabled: session.isMusicalTypingEnabled)
                .frame(width: 0, height: 0)
        )
        .onChange(of: manager.baseOctave) { _, _ in session.persistMusicalTypingPreferences() }
        .onChange(of: manager.velocity) { _, _ in session.persistMusicalTypingPreferences() }
    }

    private var controlsRow: some View {
        HStack(spacing: 10) {
            Button {
                manager.baseOctave = max(manager.baseOctave - 1, 0)
            } label: {
                Label("Oct−", systemImage: "chevron.down")
            }
            .buttonStyle(.bordered)
            .help("Octave down (Z)")

            Text("Octave \(manager.baseOctave)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 72)

            Button {
                manager.baseOctave = min(manager.baseOctave + 1, 8)
            } label: {
                Label("Oct+", systemImage: "chevron.up")
            }
            .buttonStyle(.bordered)
            .help("Octave up (X)")

            Button {
                manager.baseOctave = MusicalTypingManager.middleCOctave
            } label: {
                Text("Middle C")
            }
            .buttonStyle(.bordered)
            .help("Center on Middle C (C)")

            Divider().frame(height: 20)

            Button {
                manager.toggleLatchSustain()
            } label: {
                Label("Sustain", systemImage: manager.isLatchSustainEnabled ? "pianokeys" : "pianokeys.inverse")
            }
            .buttonStyle(.borderedProminent)
            .tint(manager.isLatchSustainEnabled ? .green : .gray)
            .help("Toggle sustain (Tab)")

            Divider().frame(height: 20)

            Text("Vel")
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
            .frame(width: 100)
            Text("\(manager.velocity)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .trailing)
        }
    }

    private var piano: some View {
        ZStack(alignment: .top) {
            HStack(spacing: 3) {
                ForEach(manager.whiteKeyLabels, id: \.label) { key in
                    MusicalTypingKey(
                        label: key.label,
                        noteNumber: manager.noteNumber(forSemitone: key.semitone),
                        isBlackKey: false,
                        isActive: manager.activeNotes.contains(manager.noteNumber(forSemitone: key.semitone)),
                        onChange: handleNoteStateChange
                    )
                }
            }

            // Black keys positioned over the gaps between whites (Logic Musical Typing layout)
            HStack(spacing: 0) {
                blackKeySpacer(0.65)
                ForEach(Array(manager.blackKeyLabels.enumerated()), id: \.element.label) { index, key in
                    MusicalTypingKey(
                        label: key.label,
                        noteNumber: manager.noteNumber(forSemitone: key.semitone),
                        isBlackKey: true,
                        isActive: manager.activeNotes.contains(manager.noteNumber(forSemitone: key.semitone)),
                        onChange: handleNoteStateChange
                    )
                    blackKeySpacer(gapAfterBlack(index: index))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
        }
        .frame(height: 150)
    }

    private var legendRow: some View {
        Text("A = C  ·  Z/X octave  ·  C middle C  ·  Tab sustain  ·  ,/. velocity")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func blackKeySpacer(_ units: CGFloat) -> some View {
        Color.clear.frame(width: 48 * units)
    }

    /// Approximate Logic spacing between black keys across the white-key row.
    private func gapAfterBlack(index: Int) -> CGFloat {
        // Gaps after W E | T Y U | O P  (skip E–F and B–C gaps already in white layout)
        switch index {
        case 0: return 0.55 // W → E
        case 1: return 1.35 // E → T (skip over D–F white gap)
        case 2: return 0.55 // T → Y
        case 3: return 0.55 // Y → U
        case 4: return 1.35 // U → O
        case 5: return 0.55 // O → P
        default: return 0.4
        }
    }

    private func handleNoteStateChange(_ note: UInt8, isPressed: Bool) {
        if isPressed {
            manager.playPreview(note: note)
        } else {
            manager.stopPreview(note: note)
        }
    }
}

private struct MusicalTypingKey: View {
    let label: String
    let noteNumber: UInt8
    let isBlackKey: Bool
    let isActive: Bool
    let onChange: (_ note: UInt8, _ isPressed: Bool) -> Void

    @State private var isPressed = false

    var body: some View {
        RoundedRectangle(cornerRadius: isBlackKey ? 6 : 8, style: .continuous)
            .fill(keyColor)
            .overlay(
                Text(label)
                    .font(.system(size: isBlackKey ? 11 : 12, weight: .semibold))
                    .foregroundStyle(isBlackKey ? .white : .black.opacity(0.85))
            )
            .frame(width: isBlackKey ? 34 : 42, height: isBlackKey ? 88 : 132)
            .overlay(
                RoundedRectangle(cornerRadius: isBlackKey ? 6 : 8, style: .continuous)
                    .stroke(isActive ? Color.accentColor : Color.black.opacity(0.18), lineWidth: isActive ? 2.5 : 1)
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
            .zIndex(isBlackKey ? 1 : 0)
    }

    private var keyColor: LinearGradient {
        if isBlackKey {
            return LinearGradient(colors: [.black.opacity(0.9), .black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
        }
        return LinearGradient(colors: [.white, .white.opacity(0.92)], startPoint: .top, endPoint: .bottom)
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
