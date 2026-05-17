import SwiftUI
import AppKit

struct MusicalTypingKeyCaptureView: NSViewRepresentable {
    @ObservedObject var manager: MusicalTypingManager
    var enabled: Bool

    final class KeyCaptureNSView: NSView {
        var onKeyDownChar: ((Character) -> Void)?
        var onKeyUpChar: ((Character) -> Void)?
        var isCaptureEnabled = false

        override var acceptsFirstResponder: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            requestFocusIfNeeded()
        }

        func requestFocusIfNeeded() {
            guard isCaptureEnabled, window?.firstResponder !== self else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isCaptureEnabled, self.window?.firstResponder !== self else { return }
                self.window?.makeFirstResponder(self)
            }
        }

        override func keyDown(with event: NSEvent) {
            if event.modifierFlags.contains(.command) { super.keyDown(with: event); return }
            guard let chars = event.charactersIgnoringModifiers, let c = chars.first else { return }
            onKeyDownChar?(c)
        }

        override func keyUp(with event: NSEvent) {
            if event.modifierFlags.contains(.command) { super.keyUp(with: event); return }
            guard let chars = event.charactersIgnoringModifiers, let c = chars.first else { return }
            onKeyUpChar?(c)
        }
    }

    func makeNSView(context: Context) -> KeyCaptureNSView {
        let v = KeyCaptureNSView()
        v.isCaptureEnabled = enabled
        v.onKeyDownChar = { char in
            if enabled { manager.handleKeyDown(char: char) }
        }
        v.onKeyUpChar = { char in
            if enabled { manager.handleKeyUp(char: char) }
        }
        return v
    }

    func updateNSView(_ nsView: KeyCaptureNSView, context: Context) {
        let wasEnabled = nsView.isCaptureEnabled
        nsView.isCaptureEnabled = enabled
        nsView.onKeyDownChar = { char in
            if enabled { manager.handleKeyDown(char: char) }
        }
        nsView.onKeyUpChar = { char in
            if enabled { manager.handleKeyUp(char: char) }
        }
        if enabled {
            if !wasEnabled || nsView.window?.firstResponder !== nsView {
                nsView.requestFocusIfNeeded()
            }
        } else {
            manager.releaseAllNotes()
        }
    }
}
