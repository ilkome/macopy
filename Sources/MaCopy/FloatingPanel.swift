import AppKit
import SwiftData
import SwiftUI

@MainActor
final class FloatingPanel: NSPanel, NSWindowDelegate {
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
        delegate = self

        let root = ContentView().modelContainer(Storage.container)
        contentView = NSHostingView(rootView: root)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    nonisolated func windowDidResignKey(_ notification: Notification) {
        MainActor.assumeIsolated {
            guard !AppSettings.shared.panelPinned,
                  !UIState.shared.showSettings
            else { return }
            orderOut(nil)
        }
    }
}


