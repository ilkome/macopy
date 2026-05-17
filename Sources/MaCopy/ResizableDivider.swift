import AppKit
import SwiftUI

struct ResizableDivider: NSViewRepresentable {
    @Binding var width: Double
    let minWidth: Double
    let maxWidth: Double

    private func apply(_ delta: CGFloat) {
        let next = width + Double(delta)
        width = min(maxWidth, max(minWidth, next))
    }

    func makeNSView(context: Context) -> NSView {
        let view = DragView()
        view.onDelta = { apply($0) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let v = nsView as? DragView else { return }
        v.onDelta = { apply($0) }
    }

    private final class DragView: NSView {
        var onDelta: ((CGFloat) -> Void)?
        private var tracking: NSTrackingArea?

        override var mouseDownCanMoveWindow: Bool { false }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let tracking { removeTrackingArea(tracking) }
            let area = NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(area)
            tracking = area
        }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .resizeLeftRight)
        }

        override func mouseEntered(with event: NSEvent) {
            NSCursor.resizeLeftRight.set()
        }

        override func mouseExited(with event: NSEvent) {
            NSCursor.arrow.set()
        }

        override func mouseDown(with event: NSEvent) {}

        override func mouseDragged(with event: NSEvent) {
            onDelta?(event.deltaX)
        }

        override func draw(_ dirtyRect: NSRect) {
            NSColor.secondaryLabelColor.withAlphaComponent(0.25).setFill()
            NSRect(x: bounds.midX - 0.5, y: 0, width: 1, height: bounds.height).fill()
        }
    }
}
