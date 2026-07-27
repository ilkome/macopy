import AppKit

@MainActor
final class PanelKeyMonitor {
    struct Callbacks {
        var isItemSelected: () -> Bool
        var isURLSelected: () -> Bool
        var toggleFavorite: () -> Void
        var openFolderPicker: () -> Void
        var focusComment: () -> Void
        var focusEditor: () -> Void
        var deleteSelected: () -> Void
        var cloneSelected: () -> Void
        var openSelectedURL: () -> Void
        var hidePanel: () -> Void
        var openSettings: () -> Void
        var pasteAt: (Int) -> Bool
        var setCommandHeld: (Bool) -> Void
    }

    private var monitor: Any?
    private let callbacks: Callbacks

    init(callbacks: Callbacks) {
        self.callbacks = callbacks
    }

    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            if event.type == .flagsChanged {
                self.callbacks.setCommandHeld(event.modifierFlags.contains(.command))
                return event
            }
            return self.handle(event)
        }
    }

    func remove() {
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        if event.keyCode == 53 {
            callbacks.hidePanel()
            return nil
        }
        guard event.modifierFlags.contains(.command) else { return event }
        let shift = event.modifierFlags.contains(.shift)
        switch event.keyCode {
        case 1:
            guard callbacks.isItemSelected() else { return event }
            callbacks.toggleFavorite()
            return nil
        case 2:
            guard callbacks.isItemSelected() else { return event }
            callbacks.cloneSelected()
            return nil
        case 37:
            guard callbacks.isItemSelected() else { return event }
            callbacks.openFolderPicker()
            return nil
        case 13:
            guard callbacks.isItemSelected() else { return event }
            callbacks.focusComment()
            return nil
        case 14:
            guard callbacks.isItemSelected() else { return event }
            callbacks.focusEditor()
            return nil
        case 36:
            guard callbacks.isItemSelected() else { return event }
            if callbacks.isURLSelected() {
                callbacks.openSelectedURL()
            }
            return nil
        case 43:
            callbacks.openSettings()
            return nil
        // Digit keyCodes 1-9 (ANSI): Cmd+N pastes the Nth visible item.
        case 18: return callbacks.pasteAt(1) ? nil : event
        case 19: return callbacks.pasteAt(2) ? nil : event
        case 20: return callbacks.pasteAt(3) ? nil : event
        case 21: return callbacks.pasteAt(4) ? nil : event
        case 23: return callbacks.pasteAt(5) ? nil : event
        case 22: return callbacks.pasteAt(6) ? nil : event
        case 26: return callbacks.pasteAt(7) ? nil : event
        case 28: return callbacks.pasteAt(8) ? nil : event
        case 25: return callbacks.pasteAt(9) ? nil : event
        case 51, 117:
            if let text = NSApp.keyWindow?.firstResponder as? NSText,
               !text.string.isEmpty {
                return event
            }
            callbacks.deleteSelected()
            return nil
        case 0:
            return forwardAction(Selector("selectAll:"), event: event)
        case 8:
            return forwardAction(Selector("copy:"), event: event)
        case 9:
            return forwardAction(Selector("paste:"), event: event)
        case 7:
            return forwardAction(Selector("cut:"), event: event)
        case 6:
            return forwardAction(Selector(shift ? "redo:" : "undo:"), event: event)
        default:
            return event
        }
    }

    private func forwardAction(_ selector: Selector, event: NSEvent) -> NSEvent? {
        if NSApp.sendAction(selector, to: nil, from: nil) {
            return nil
        }
        return event
    }
}
