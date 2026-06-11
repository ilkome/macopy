import Foundation
import SwiftUI

@MainActor
final class UIState: ObservableObject {
    static let shared = UIState()

    @Published var showSettings: Bool = false
    // Gates the list recompute: writes that arrive while the panel is hidden are skipped
    // because reopening the panel rebuilds from fresh store.items via resetToTop.
    @Published var isPanelVisible: Bool = false
    @Published var commentFocusToken: Int = 0
    @Published var searchFocusToken: Int = 0
    @Published var editorFocusToken: Int = 0

    private init() {}
}
