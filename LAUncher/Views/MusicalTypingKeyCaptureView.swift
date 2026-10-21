import SwiftUI
import AppKit

/// Focus-based key capture for Musical Typing. Prefer this when the piano is visible;
/// local monitors in MusicalTypingManager remain as a fallback and skip text fields.
struct MusicalTypingKeyCaptureView: NSViewRepresentable {
    @ObservedObject var manager: MusicalTypingManager
    var enabled: Bool

    final class KeyCaptureNSView: NSView {
        var onKeyDownChar: ((Character) -> Void)?
        var onKeyUpChar: ((Character) -> Void)?
        var onTab: (() -> Void)?
        var isCaptureEnabled = false

        override var acceptsFirstResponder: Bool { isCaptureEnabled }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            requestFocusIfNeeded()
        }

        func requestFocusIfNeeded() {
            guard isCaptureEnabled, window?.firstResponder !== self else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isCaptureEnabled else { return }
                // Don't steal focus from text editing
                if MusicalTypingManager.isTextInputFirstResponder() { return }
                self.window?.makeFirstResponder(self)
            }
        }

        override func keyDown(with event: NSEvent) {
            if event.modifierFlags.contains(.command)
                || event.modifierFlags.contains(.control)
                || event.modifierFlags.contains(.option) {
                super.keyDown(with: event)
                return
            }
            if event.keyCode == 48 { // Tab
                if !event.isARepeat { onTab?() }
                return
            }
            guard let chars = event.charactersIgnoringModifiers, let c = chars.first else {
                super.keyDown(with: event)
                return
            }
            onKeyDownChar?(c)
        }

        override func keyUp(with event: NSEvent) {
            if event.modifierFlags.contains(.command)
                || event.modifierFlags.contains(.control)
                || event.modifierFlags.contains(.option) {
                super.keyUp(with: event)
                return
            }
            if event.keyCode == 48 { return }
            guard let chars = event.charactersIgnoringModifiers, let c = chars.first else {
                super.keyUp(with: event)
                return
            }
            onKeyUpChar?(c)
        }
    }

    func makeNSView(context: Context) -> KeyCaptureNSView {
        let v = KeyCaptureNSView()
        v.isCaptureEnabled = enabled
        wire(v)
        return v
    }

    func updateNSView(_ nsView: KeyCaptureNSView, context: Context) {
        let wasEnabled = nsView.isCaptureEnabled
        nsView.isCaptureEnabled = enabled
        wire(nsView)
        if enabled {
            if !wasEnabled || nsView.window?.firstResponder !== nsView {
                nsView.requestFocusIfNeeded()
            }
        } else if wasEnabled {
            manager.releaseAllNotes()
        }
    }

    private func wire(_ nsView: KeyCaptureNSView) {
        nsView.onKeyDownChar = { [manager] char in
            if enabled { manager.handleKeyDown(char: char) }
        }
        nsView.onKeyUpChar = { [manager] char in
            if enabled { manager.handleKeyUp(char: char) }
        }
        nsView.onTab = { [manager] in
            if enabled { manager.toggleLatchSustain() }
        }
    }
}
