import AppKit
import SwiftUI

extension View {
    /// Runs `action` on a middle-button click. Other clicks pass through to the view.
    func onMiddleClick(perform action: @escaping () -> Void) -> some View {
        overlay(MiddleClickCatcher(action: action))
    }
}

private struct MiddleClickCatcher: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> Catcher {
        Catcher(action: action)
    }

    func updateNSView(_ view: Catcher, context: Context) {
        view.action = action
    }

    final class Catcher: NSView {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
            super.init(frame: .zero)
        }

        @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

        /// Take only middle clicks, so left clicks, drags, and hovers reach the view below.
        override func hitTest(_ point: NSPoint) -> NSView? {
            NSApp.currentEvent?.type == .otherMouseDown || NSApp.currentEvent?.type == .otherMouseUp ? super.hitTest(point) : nil
        }

        override func otherMouseUp(with event: NSEvent) {
            if event.buttonNumber == 2 { action() }
        }
    }
}
