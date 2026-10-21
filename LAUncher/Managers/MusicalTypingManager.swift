import Foundation
import Combine
import AppKit

/// Logic Pro–style Musical Typing: A = C of the current octave, chromatic across the home row.
@MainActor
final class MusicalTypingManager: ObservableObject {
    /// Octave where A plays C. Default 5 → A = MIDI 60 (Middle C).
    @Published var baseOctave: Int = 5
    @Published var transpose: Int = 0
    @Published var velocity: UInt8 = 100
    @Published var isLatchSustainEnabled = false
    @Published private(set) var activeNotes: Set<UInt8> = []

    private var activeKeys: [Character: UInt8] = [:]
    private var latchedNotes: Set<UInt8> = []
    private var keyDownMonitor: Any?
    private var keyUpMonitor: Any?

    /// Logic Musical Typing chromatic map (A = C).
    /// Whites: A S D F G H J K L ; '
    /// Blacks: W E T Y U O P
    private let keyToSemitone: [Character: Int] = [
        "a": 0,  // C
        "w": 1,  // C#
        "s": 2,  // D
        "e": 3,  // D#
        "d": 4,  // E
        "f": 5,  // F
        "t": 6,  // F#
        "g": 7,  // G
        "y": 8,  // G#
        "h": 9,  // A
        "u": 10, // A#
        "j": 11, // B
        "k": 12, // C
        "o": 13, // C#
        "l": 14, // D
        "p": 15, // D#
        ";": 16, // E
        "'": 17  // F
    ]

    /// Ordered white-key labels for the on-screen Logic Musical Typing keyboard.
    let whiteKeyLabels: [(label: String, semitone: Int)] = [
        ("A", 0), ("S", 2), ("D", 4), ("F", 5), ("G", 7), ("H", 9), ("J", 11),
        ("K", 12), ("L", 14), (";", 16), ("'", 17)
    ]

    let blackKeyLabels: [(label: String, semitone: Int)] = [
        ("W", 1), ("E", 3), ("T", 6), ("Y", 8), ("U", 10), ("O", 13), ("P", 15)
    ]

    static let middleCOctave = 5

    var sendNoteOn: ((UInt8, UInt8) -> Void)?
    var sendNoteOff: ((UInt8) -> Void)?
    var onPreferencesChanged: (() -> Void)?

    deinit {
        if let keyDownMonitor {
            NSEvent.removeMonitor(keyDownMonitor)
        }
        if let keyUpMonitor {
            NSEvent.removeMonitor(keyUpMonitor)
        }
    }

    private func currentBaseNote() -> Int {
        12 * baseOctave + transpose
    }

    func noteNumber(forSemitone semitone: Int) -> UInt8 {
        UInt8(clamping: currentBaseNote() + semitone)
    }

    func handleKeyDown(char: Character) {
        let c = Character(String(char).lowercased())

        // Logic: Z = octave down, X = octave up, C = center on Middle C
        if c == "z" {
            baseOctave = max(baseOctave - 1, 0)
            onPreferencesChanged?()
            return
        }
        if c == "x" {
            baseOctave = min(baseOctave + 1, 8)
            onPreferencesChanged?()
            return
        }
        if c == "c" {
            baseOctave = Self.middleCOctave
            onPreferencesChanged?()
            return
        }

        // Velocity nudge: , down / . up (avoids conflicting with Logic note map)
        if c == "," {
            velocity = UInt8(max(1, Int(velocity) - 8))
            onPreferencesChanged?()
            return
        }
        if c == "." {
            velocity = UInt8(min(127, Int(velocity) + 8))
            onPreferencesChanged?()
            return
        }

        guard let semitone = keyToSemitone[c] else { return }
        if activeKeys[c] != nil { return }
        let note = noteNumber(forSemitone: semitone)
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

    /// Returns nil to swallow the event, or the event to pass through.
    private func handle(event: NSEvent, isKeyDown: Bool) -> NSEvent? {
        if Self.isTextInputFirstResponder() {
            return event
        }

        if event.modifierFlags.contains(.command) ||
            event.modifierFlags.contains(.control) ||
            event.modifierFlags.contains(.option) {
            return event
        }

        // Tab = sustain / latch (Logic Musical Typing)
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
        return keyToSemitone[c] != nil
            || c == "z" || c == "x" || c == "c"
            || c == "," || c == "."
    }

    /// Don't steal keys from search fields, BPM fields, chat, etc.
    static func isTextInputFirstResponder() -> Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        if responder is NSTextView || responder is NSTextField || responder is NSComboBox || responder is NSText {
            return true
        }
        if let view = responder as? NSView {
            var current: NSView? = view
            while let c = current {
                if c is NSTextField || c is NSTextView || c is NSComboBox { return true }
                current = c.superview
            }
        }
        return false
    }
}
