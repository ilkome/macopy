import Foundation
import SwiftUI

@MainActor
final class UIState: ObservableObject {
    static let shared = UIState()

    @Published var showSettings: Bool = false
    @Published var commentFocusToken: Int = 0
    @Published var searchFocusToken: Int = 0
    @Published var editorFocusToken: Int = 0

    private init() {}
}
