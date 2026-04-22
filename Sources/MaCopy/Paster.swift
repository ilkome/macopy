import AppKit
import ApplicationServices

extension Notification.Name {
    static let clipboardPanelReset = Notification.Name("clipboardPanelReset")
}

@MainActor
final class Paster {
    static let shared = Paster()

    var previousApp: NSRunningApplication?
    var didPaste = false

    private var activationObserver: NSObjectProtocol?
    private var activationTimer: DispatchWorkItem?

    private init() {}

    @discardableResult
    func copyToPasteboard(_ item: ClipboardItem) -> Bool {
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
        return true
    }

    @discardableResult
    func copyOnly(_ item: ClipboardItem) -> Bool {
        guard copyToPasteboard(item) else { return false }
        didPaste = true
        AppDelegate.shared?.hidePanel()
        return true
    }

    @discardableResult
    func paste(_ item: ClipboardItem) -> Bool {
        guard copyToPasteboard(item) else { return false }

        didPaste = true
        AppDelegate.shared?.hidePanel()

        guard Self.isTrusted() else {
            Self.showAccessibilityAlert()
            return true
        }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        if let prev = previousApp, prev.processIdentifier != ownPID, !prev.isActive {
            prev.activate(options: [])
            awaitActivation(of: prev) { [weak self] in
                self?.simulateCmdV()
            }
        } else {
            simulateCmdV()
        }
        return true
    }

    private func awaitActivation(
        of app: NSRunningApplication,
        timeout: TimeInterval = 0.3,
        action: @escaping @MainActor () -> Void
    ) {
        cancelActivationWait()
        let center = NSWorkspace.shared.notificationCenter
        let targetPID = app.processIdentifier

        let fire: @MainActor () -> Void = { [weak self] in
            guard let self else { return }
            self.cancelActivationWait()
            action()
        }

        activationObserver = center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let running = notification
                .userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  running.processIdentifier == targetPID
            else { return }
            MainActor.assumeIsolated { fire() }
        }

        let work = DispatchWorkItem { MainActor.assumeIsolated { fire() } }
        activationTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: work)
    }

    private func cancelActivationWait() {
        if let observer = activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            activationObserver = nil
        }
        activationTimer?.cancel()
        activationTimer = nil
    }

    private func simulateCmdV() {
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
