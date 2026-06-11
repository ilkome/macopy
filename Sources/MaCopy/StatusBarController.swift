import AppKit

@MainActor
final class StatusBarController: NSObject {
    private let onToggle: () -> Void
    private let onOpenSettings: () -> Void
    private let onCheckUpdates: () -> Void
    private let onQuit: () -> Void

    private var statusItem: NSStatusItem?

    init(
        onToggle: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onCheckUpdates: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.onToggle = onToggle
        self.onOpenSettings = onOpenSettings
        self.onCheckUpdates = onCheckUpdates
        self.onQuit = onQuit
    }

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            if let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "pdf"),
               let image = NSImage(contentsOf: url) {
                image.size = NSSize(width: 18, height: 18)
                image.isTemplate = true // macOS tints it for light/dark menu bars
                button.image = image
            } else {
                button.title = "📋"
            }
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
    }

    @objc private func statusItemClicked() {
        guard let event = NSApp.currentEvent else {
            onToggle()
            return
        }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showMenu()
        } else {
            onToggle()
        }
    }

    private func showMenu() {
        let menu = NSMenu()

        let settingsItem = NSMenuItem(
            title: String(localized: "Settings…"),
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let update = NSMenuItem(
            title: String(localized: "Check for updates"),
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        update.target = self
        menu.addItem(update)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: String(localized: "Quit"), action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        guard let button = statusItem?.button else { return }
        let origin = NSPoint(x: 0, y: button.bounds.height + 4)
        menu.popUp(positioning: nil, at: origin, in: button)
    }

    @objc private func openSettings() { onOpenSettings() }
    @objc private func checkForUpdates() { onCheckUpdates() }
    @objc private func quit() { onQuit() }
}
