import SwiftUI
import AppKit

struct MusicalTypingKeyCaptureView: NSViewRepresentable {
    @ObservedObject var manager: MusicalTypingManager
    var enabled: Bool

    final class KeyCaptureNSView: NSView {
        var onKeyDownChar: ((Character) -> Void)?
        var onKeyUpChar: ((Character) -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async {
                self.window?.makeFirstResponder(self)
            }
        }

        override func keyDown(with event: NSEvent) {
            guard let chars = event.charactersIgnoringModifiers, let c = chars.first else { return }
            if event.modifierFlags.contains(.command) { super.keyDown(with: event); return }
            onKeyDownChar?(c)
        }

        override func keyUp(with event: NSEvent) {
            guard let chars = event.charactersIgnoringModifiers, let c = chars.first else { return }
            if event.modifierFlags.contains(.command) { super.keyUp(with: event); return }
            onKeyUpChar?(c)
        }
    }

    func makeNSView(context: Context) -> KeyCaptureNSView {
        let v = KeyCaptureNSView()
        v.onKeyDownChar = { char in
            if enabled { manager.handleKeyDown(char: char) }
        }
        v.onKeyUpChar = { char in
            if enabled { manager.handleKeyUp(char: char) }
        }
        return v
    }

    func updateNSView(_ nsView: KeyCaptureNSView, context: Context) {
        // closures capture state
    }
}


