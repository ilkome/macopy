import AppKit
import Carbon.HIToolbox
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

    private var statusItem: NSStatusItem?
    private var panel: FloatingPanel?
    private var hotKeyRef: EventHotKeyRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        panel = FloatingPanel()
        registerHotKey()
        ClipboardMonitor.shared.start()
        _ = UpdaterController.shared
        LinkPreviewService.shared.backfillPending()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.title = "📋"
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
    }

    @objc private func statusItemClicked() {
        guard let event = NSApp.currentEvent else {
            togglePanel()
            return
        }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showMenu()
        } else {
            togglePanel()
        }
    }

    private func showMenu() {
        let menu = NSMenu()

        let ocr = NSMenuItem(
            title: "OCR для скриншотов",
            action: #selector(toggleOCR),
            keyEquivalent: ""
        )
        ocr.state = AppSettings.shared.ocrEnabled ? .on : .off
        ocr.target = self
        menu.addItem(ocr)

        menu.addItem(.separator())

        let update = NSMenuItem(
            title: "Проверить обновления",
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        update.target = self
        menu.addItem(update)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Выход", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        guard let button = statusItem?.button else { return }
        let origin = NSPoint(x: 0, y: button.bounds.height + 4)
        menu.popUp(positioning: nil, at: origin, in: button)
    }

    @objc private func toggleOCR() {
        AppSettings.shared.ocrEnabled.toggle()
    }

    @objc private func checkForUpdates() {
        UpdaterController.shared.checkForUpdates()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
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
        panel?.orderOut(nil)
    }

    private func registerHotKey() {
        let hotKeyID = EventHotKeyID(signature: 0x4C544B31, id: 1)
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            AppDelegate.hotKeyCallback,
            1, &spec, nil, nil
        )
        var ref: EventHotKeyRef?
        RegisterEventHotKey(
            UInt32(kVK_ANSI_4),
            UInt32(cmdKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        hotKeyRef = ref
    }

    private static let hotKeyCallback: @convention(c) (
        EventHandlerCallRef?,
        EventRef?,
        UnsafeMutableRawPointer?
    ) -> OSStatus = { _, _, _ in
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                AppDelegate.shared?.togglePanel()
            }
        }
        return noErr
    }
}
