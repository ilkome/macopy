import AppKit
import SwiftData
import SwiftUI

final class FloatingPanel: NSPanel {
    @MainActor
    init() {
        super.init(
            contentRect: NSRect(
                x: 0, y: 0,
                width: Layout.panelWidth,
                height: Layout.panelHeight
            ),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        appearance = NSAppearance(named: .darkAqua)

        let root = ContentView().modelContainer(Storage.container)
        contentView = NSHostingView(rootView: root)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.state = .active
        view.blendingMode = .behindWindow
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

