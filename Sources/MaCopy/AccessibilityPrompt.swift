import AppKit
import ApplicationServices

enum AccessibilityPrompt {
    static func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    static func ensureAccessibility() {
        let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    @MainActor
    static func showAlert() {
        let alert = NSAlert()
        alert.messageText = "Нужен доступ к Accessibility"
        alert.informativeText = """
        Чтобы MaCopy вставлял элементы автоматически, дай ему доступ:
        Системные настройки → Приватность и безопасность → Универсальный доступ → включи MaCopy.

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
