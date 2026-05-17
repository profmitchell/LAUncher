import Foundation
import Combine

@MainActor
final class MusicalTypingManager: ObservableObject {
    @Published var baseOctave: Int = 4
    @Published var transpose: Int = 0
    @Published var velocity: UInt8 = 100
    @Published private(set) var activeNotes: Set<UInt8> = []

    private var activeKeys: [Character: UInt8] = [:]

    // Map QWERTY keys to semitone offsets in the Z-M row
    private let keyToSemitone: [Character: Int] = [
        "z": 0, "s": 1, "x": 2, "d": 3, "c": 4, "v": 5, "g": 6,
        "b": 7, "h": 8, "n": 9, "j": 10, "m": 11,
        // Optional upper row as next octave
        "q": 12, "2": 13, "w": 14, "3": 15, "e": 16, "r": 17, "5": 18,
        "t": 19, "6": 20, "y": 21, "7": 22, "u": 23
    ]

    var sendNoteOn: ((UInt8, UInt8) -> Void)?
    var sendNoteOff: ((UInt8) -> Void)?

    private func currentBaseNote() -> Int {
        return 12 * baseOctave + transpose
    }

    func handleKeyDown(char: Character) {
        let c = Character(String(char).lowercased())
        if c == "[" {
            baseOctave = max(baseOctave - 1, 1)
            return
        }
        if c == "]" {
            baseOctave = min(baseOctave + 1, 8)
            return
        }
        guard let semitone = keyToSemitone[c] else { return }
        if activeKeys[c] != nil { return } // ignore repeats
        let note = UInt8(currentBaseNote() + semitone)
        activeKeys[c] = note
        activeNotes.insert(note)
        sendNoteOn?(note, velocity)
    }

    func handleKeyUp(char: Character) {
        let c = Character(String(char).lowercased())
        guard let note = activeKeys.removeValue(forKey: c) else { return }
        activeNotes.remove(note)
        sendNoteOff?(note)
    }

    func playPreview(note: UInt8) {
        guard !activeNotes.contains(note) else { return }
        activeNotes.insert(note)
        sendNoteOn?(note, velocity)
    }

    func stopPreview(note: UInt8) {
        guard activeNotes.remove(note) != nil else { return }
        sendNoteOff?(note)
    }

    func releaseAllNotes() {
        let notes = Set(activeKeys.values).union(activeNotes)
        activeKeys.removeAll()
        activeNotes.removeAll()
        for note in notes {
            sendNoteOff?(note)
        }
    }
}

