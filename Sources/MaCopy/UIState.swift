import Foundation
import SwiftUI

@MainActor
final class UIState: ObservableObject {
    static let shared = UIState()

    @Published var showSettings: Bool = false

    private init() {}
}
