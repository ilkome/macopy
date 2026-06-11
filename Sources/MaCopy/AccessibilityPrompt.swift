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
        alert.messageText = String(localized: "Accessibility access required")
        alert.informativeText = String(localized: """
        To let MaCopy paste items automatically, grant it access:
        System Settings → Privacy & Security → Accessibility → enable MaCopy.

        The clipboard is already updated - you can paste manually with ⌘V.
        """)
        alert.addButton(withTitle: String(localized: "Open settings"))
        alert.addButton(withTitle: String(localized: "Later"))
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
