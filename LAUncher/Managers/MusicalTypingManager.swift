import Foundation
import Combine
import AppKit

@MainActor
final class MusicalTypingManager: ObservableObject {
    @Published var baseOctave: Int = 4
    @Published var transpose: Int = 0
    @Published var velocity: UInt8 = 100
    @Published var isLatchSustainEnabled = false
    @Published private(set) var activeNotes: Set<UInt8> = []

    private var activeKeys: [Character: UInt8] = [:]
    private var latchedNotes: Set<UInt8> = []
    private var keyDownMonitor: Any?
    private var keyUpMonitor: Any?

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

    deinit {
        if let keyDownMonitor {
            NSEvent.removeMonitor(keyDownMonitor)
        }
        if let keyUpMonitor {
            NSEvent.removeMonitor(keyUpMonitor)
        }
    }

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
        let wasAlreadyActive = activeNotes.contains(note)
        activeNotes.insert(note)
        latchedNotes.remove(note)
        if !wasAlreadyActive {
            sendNoteOn?(note, velocity)
        }
    }

    func handleKeyUp(char: Character) {
        let c = Character(String(char).lowercased())
        guard let note = activeKeys.removeValue(forKey: c) else { return }
        if isLatchSustainEnabled {
            latchedNotes.insert(note)
        } else {
            activeNotes.remove(note)
            sendNoteOff?(note)
        }
    }

    func toggleLatchSustain() {
        isLatchSustainEnabled.toggle()
        if !isLatchSustainEnabled {
            releaseLatchedNotes()
        }
    }

    private func releaseLatchedNotes() {
        let notesToRelease = latchedNotes
        latchedNotes.removeAll()
        for note in notesToRelease {
            guard !activeKeys.values.contains(note) else { continue }
            activeNotes.remove(note)
            sendNoteOff?(note)
        }
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
        latchedNotes.removeAll()
        activeNotes.removeAll()
        isLatchSustainEnabled = false
        for note in notes {
            sendNoteOff?(note)
        }
    }

    func setKeyboardCaptureEnabled(_ enabled: Bool) {
        if enabled {
            installKeyboardMonitorIfNeeded()
        } else {
            removeKeyboardMonitor()
            releaseAllNotes()
        }
    }

    private func installKeyboardMonitorIfNeeded() {
        guard keyDownMonitor == nil, keyUpMonitor == nil else { return }

        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handle(event: event, isKeyDown: true)
        }

        keyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            guard let self else { return event }
            return self.handle(event: event, isKeyDown: false)
        }
    }

    private func removeKeyboardMonitor() {
        if let keyDownMonitor {
            NSEvent.removeMonitor(keyDownMonitor)
            self.keyDownMonitor = nil
        }
        if let keyUpMonitor {
            NSEvent.removeMonitor(keyUpMonitor)
            self.keyUpMonitor = nil
        }
    }

    private func handle(event: NSEvent, isKeyDown: Bool) -> NSEvent? {
        if event.modifierFlags.contains(.command) ||
            event.modifierFlags.contains(.control) ||
            event.modifierFlags.contains(.option) {
            return event
        }

        if event.keyCode == 48 {
            if isKeyDown, !event.isARepeat {
                toggleLatchSustain()
            }
            return nil
        }

        guard let chars = event.charactersIgnoringModifiers,
              let char = chars.first,
              handles(char: char) else {
            return event
        }

        if isKeyDown {
            if !event.isARepeat {
                handleKeyDown(char: char)
            }
        } else {
            handleKeyUp(char: char)
        }

        return nil
    }

    private func handles(char: Character) -> Bool {
        let c = Character(String(char).lowercased())
        return keyToSemitone[c] != nil || c == "[" || c == "]"
    }
}
