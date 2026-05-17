import AppKit
import KeyboardShortcuts
import SwiftUI

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    nonisolated(unsafe) static var shared: AppDelegate?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        Self.shared = delegate
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    private var statusBar: StatusBarController?
    private var panel: FloatingPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        ImageStore.sweepPreviewDirectory()
        statusBar = StatusBarController(
            onToggle: { [weak self] in self?.togglePanel() },
            onOpenSettings: { [weak self] in
                UIState.shared.showSettings = true
                self?.showPanel()
            },
            onCheckUpdates: { UpdaterController.shared.checkForUpdates() },
            onQuit: { NSApp.terminate(nil) }
        )
        statusBar?.install()
        panel = FloatingPanel()
        KeyboardShortcuts.onKeyUp(for: .togglePanel) { [weak self] in
            self?.togglePanel()
        }
        ClipboardMonitor.shared.start()
        _ = UpdaterController.shared
        LinkPreviewService.shared.backfillPending()

        let filterSecrets = AppSettings.shared.filterSensitiveContent
        Task.detached(priority: .utility) {
            await OCRService.backfillRedactionsOnceIfNeeded(filterSecrets: filterSecrets)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        ImageStore.sweepPreviewDirectory()
    }

    func togglePanel() {
        guard let panel else { return }
        if panel.isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    func showPanel() {
        guard let panel else { return }
        Paster.shared.previousApp = NSWorkspace.shared.frontmostApplication
        if let screen = NSScreen.main {
            let frame = panel.frame
            let x = screen.visibleFrame.midX - frame.width / 2
            let y = screen.visibleFrame.midY - frame.height / 2
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
        if !Paster.shared.didPaste {
            NotificationCenter.default.post(name: .clipboardPanelReset, object: nil)
        }
        Paster.shared.didPaste = false
        panel.makeKeyAndOrderFront(nil)
    }

    func hidePanel() {
        UIState.shared.showSettings = false
        panel?.orderOut(nil)
    }
}
