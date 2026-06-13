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

        // Bound the DB + image directory once at launch, after the backfill scan has settled.
        Task.detached(priority: .utility) {
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            RetentionService.prune()
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
        UIState.shared.isPanelVisible = true
        Paster.shared.previousApp = NSWorkspace.shared.frontmostApplication
        if let screen = NSScreen.main {
            let frame = panel.frame
            let x = screen.visibleFrame.midX - frame.width / 2
            let y = screen.visibleFrame.midY - frame.height / 2
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
        NotificationCenter.default.post(name: .clipboardPanelReset, object: nil)
        panel.makeKeyAndOrderFront(nil)
    }

    func hidePanel() {
        UIState.shared.showSettings = false
        UIState.shared.isPanelVisible = false
        panel?.orderOut(nil)
    }
}
