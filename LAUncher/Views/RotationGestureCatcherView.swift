import SwiftUI
import AppKit

struct RotationGestureCatcherView: NSViewRepresentable {
    final class RotationView: NSView {
        override func magnify(with event: NSEvent) { /* ignore */ }
    }

    func makeNSView(context: Context) -> RotationView {
        let view = RotationView(frame: .zero)
        let recognizer = NSRotationGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleRotation(_:)))
        view.addGestureRecognizer(recognizer)
        return view
    }

    func updateNSView(_ nsView: RotationView, context: Context) { }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject {
        @objc func handleRotation(_ sender: NSRotationGestureRecognizer) {
            // Consume rotation so the system recognizes it within this window.
            // You can hook this to actions if needed; intentionally no effect here.
            _ = sender.rotation
        }
    }
}


