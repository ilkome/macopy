import AppKit
import ApplicationServices

extension Notification.Name {
    static let clipboardPanelReset = Notification.Name("clipboardPanelReset")
}

@MainActor
enum Paster {
    static var previousApp: NSRunningApplication?
    static var didPaste: Bool = false

    @discardableResult
    static func paste(_ item: ClipboardItem) -> Bool {
        let pb = NSPasteboard.general

        switch item.kind {
        case .image:
            guard let path = item.imagePath else { return false }
            let url = Storage.imageURL(for: path)
            guard FileManager.default.fileExists(atPath: url.path),
                  let image = NSImage(contentsOf: url),
                  image.isValid
            else { return false }
            pb.clearContents()
            guard pb.writeObjects([image]) else { return false }
        default:
            guard let text = item.text, !text.isEmpty else { return false }
            pb.clearContents()
            pb.setString(text, forType: .string)
        }

        didPaste = true
        AppDelegate.shared?.hidePanel()

        if let prev = previousApp {
            prev.activate(options: [])
        }

        if !isTrusted() {
            showAccessibilityAlert()
            return true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            simulateCmdV()
        }
        return true
    }

    private static func simulateCmdV() {
        let source = CGEventSource(stateID: .hidSystemState)
        let vKeyCode: CGKeyCode = 0x09

        let down = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
        down?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)

        let up = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        up?.flags = .maskCommand
        up?.post(tap: .cghidEventTap)
    }

    static func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    static func ensureAccessibility() {
        let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    private static func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = "Нужен доступ к Accessibility"
        alert.informativeText = """
        Чтобы ListTestSwiftUI вставлял элементы автоматически, дай ему доступ:
        Системные настройки → Приватность и безопасность → Универсальный доступ → включи ListTestSwiftUI.

        Буфер уже обновлён — можешь вставить вручную ⌘V.
        """
        alert.addButton(withTitle: "Открыть настройки")
        alert.addButton(withTitle: "Позже")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
