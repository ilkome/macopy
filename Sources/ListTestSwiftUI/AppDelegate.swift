import AppKit
import SwiftUI
import Carbon.HIToolbox

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
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.title = "L4"
            button.target = self
            button.action = #selector(statusItemClicked)
        }
        statusItem = item
    }

    @objc private func statusItemClicked() {
        togglePanel()
    }

    func togglePanel() {
        guard let panel else { return }
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            if let screen = NSScreen.main {
                let frame = panel.frame
                let x = screen.visibleFrame.midX - frame.width / 2
                let y = screen.visibleFrame.midY - frame.height / 2
                panel.setFrameOrigin(NSPoint(x: x, y: y))
            }
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
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
            1,
            &spec,
            nil,
            nil
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
