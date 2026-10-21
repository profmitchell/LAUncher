import SwiftUI

/// On-screen QWERTY Piano: A = C, chromatic home-row layout.
struct MusicalTypingView: View {
    @ObservedObject var session: PluginHostSession
    @ObservedObject private var manager: MusicalTypingManager

    private let whiteKeyWidth: CGFloat = 40
    private let whiteKeyHeight: CGFloat = 118
    private let whiteSpacing: CGFloat = 2
    private let blackKeyWidth: CGFloat = 26
    private let blackKeyHeight: CGFloat = 72

    /// Black keys sit on the boundary after these white-key indices.
    /// Whites: A S D F G H J K L ; '  → blacks after A,S | F,G,H | K,L
    private let blackAfterWhiteIndex = [0, 1, 3, 4, 5, 7, 8]

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
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
        .padding(.top, 4)
        .background(
            MusicalTypingKeyCaptureView(manager: manager, enabled: session.isMusicalTypingEnabled)
                .frame(width: 0, height: 0)
        )
        .onChange(of: manager.baseOctave) { _, _ in session.persistMusicalTypingPreferences() }
        .onChange(of: manager.velocity) { _, _ in session.persistMusicalTypingPreferences() }
    }

    private var controlsRow: some View {
        HStack(spacing: 8) {
            Button {
                manager.baseOctave = max(manager.baseOctave - 1, 0)
            } label: {
                Text("Oct−")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Octave down (Z)")

            Text("Octave \(manager.baseOctave)")
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 64)

            Button {
                manager.baseOctave = min(manager.baseOctave + 1, 8)
            } label: {
                Text("Oct+")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Octave up (X)")

            Button {
                manager.baseOctave = MusicalTypingManager.middleCOctave
            } label: {
                Text("Middle C")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Center on Middle C (C)")

            Divider().frame(height: 18)

            Button {
                manager.toggleLatchSustain()
            } label: {
                Text("Sustain")
            }
            .buttonStyle(.borderedProminent)
            .tint(manager.isLatchSustainEnabled ? .green : .gray)
            .controlSize(.small)
            .help("Toggle sustain (Tab)")

            Divider().frame(height: 18)

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
            .frame(width: 90)
            .controlSize(.mini)
            Text("\(manager.velocity)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 26, alignment: .trailing)
        }
    }

    private var piano: some View {
        let whiteCount = CGFloat(manager.whiteKeyLabels.count)
        let totalWidth = whiteCount * whiteKeyWidth + (whiteCount - 1) * whiteSpacing

        return ZStack(alignment: .topLeading) {
            HStack(spacing: whiteSpacing) {
                ForEach(manager.whiteKeyLabels, id: \.label) { key in
                    QWERTYPianoKey(
                        label: key.label,
                        noteNumber: manager.noteNumber(forSemitone: key.semitone),
                        isBlackKey: false,
                        isActive: manager.activeNotes.contains(manager.noteNumber(forSemitone: key.semitone)),
                        width: whiteKeyWidth,
                        height: whiteKeyHeight,
                        onChange: handleNoteStateChange
                    )
                }
            }

            ForEach(Array(manager.blackKeyLabels.enumerated()), id: \.element.label) { index, key in
                let after = blackAfterWhiteIndex[index]
                let boundaryX = CGFloat(after + 1) * whiteKeyWidth + CGFloat(after) * whiteSpacing + whiteSpacing / 2
                QWERTYPianoKey(
                    label: key.label,
                    noteNumber: manager.noteNumber(forSemitone: key.semitone),
                    isBlackKey: true,
                    isActive: manager.activeNotes.contains(manager.noteNumber(forSemitone: key.semitone)),
                    width: blackKeyWidth,
                    height: blackKeyHeight,
                    onChange: handleNoteStateChange
                )
                .offset(x: boundaryX - blackKeyWidth / 2, y: 0)
            }
        }
        .frame(width: totalWidth, height: whiteKeyHeight, alignment: .topLeading)
        .frame(maxWidth: .infinity)
    }

    private var legendRow: some View {
        Text("A = C  ·  Z/X octave  ·  C middle C  ·  Tab sustain  ·  ,/. velocity")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func handleNoteStateChange(_ note: UInt8, isPressed: Bool) {
        if isPressed {
            manager.playPreview(note: note)
        } else {
            manager.stopPreview(note: note)
        }
    }
}

private struct QWERTYPianoKey: View {
    let label: String
    let noteNumber: UInt8
    let isBlackKey: Bool
    let isActive: Bool
    let width: CGFloat
    let height: CGFloat
    let onChange: (_ note: UInt8, _ isPressed: Bool) -> Void

    @State private var isPressed = false

    var body: some View {
        RoundedRectangle(cornerRadius: isBlackKey ? 4 : 6, style: .continuous)
            .fill(keyFill)
            .overlay(alignment: .bottom) {
                Text(label)
                    .font(.system(size: isBlackKey ? 10 : 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(isBlackKey ? Color.white.opacity(0.9) : Color.black.opacity(0.75))
                    .padding(.bottom, isBlackKey ? 8 : 10)
            }
            .overlay(
                RoundedRectangle(cornerRadius: isBlackKey ? 4 : 6, style: .continuous)
                    .strokeBorder(
                        isActive ? Color.accentColor : Color.black.opacity(isBlackKey ? 0.35 : 0.12),
                        lineWidth: isActive ? 2 : 1
                    )
            )
            .frame(width: width, height: height)
            .shadow(color: .black.opacity(isBlackKey ? 0.35 : 0.12), radius: isBlackKey ? 2 : 1, y: 1)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !isPressed else { return }
                        isPressed = true
                        onChange(noteNumber, true)
                    }
                    .onEnded { _ in
                        guard isPressed else { return }
                        isPressed = false
                        onChange(noteNumber, false)
                    }
            )
            .onDisappear {
                if isPressed {
                    onChange(noteNumber, false)
                }
            }
            .zIndex(isBlackKey ? 2 : 0)
    }

    private var keyFill: LinearGradient {
        if isBlackKey {
            return LinearGradient(
                colors: [
                    isActive ? Color(white: 0.35) : Color(white: 0.12),
                    isActive ? Color(white: 0.22) : Color(white: 0.05)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        return LinearGradient(
            colors: [
                isActive ? Color(red: 0.85, green: 0.92, blue: 1.0) : .white,
                isActive ? Color(red: 0.75, green: 0.86, blue: 0.98) : Color(white: 0.94)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
