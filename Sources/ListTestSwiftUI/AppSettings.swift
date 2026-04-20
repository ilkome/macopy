import Foundation

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var ocrEnabled: Bool {
        didSet { UserDefaults.standard.set(ocrEnabled, forKey: Keys.ocr) }
    }

    private enum Keys { static let ocr = "ocrEnabled" }

    private init() {
        let d = UserDefaults.standard
        if d.object(forKey: Keys.ocr) == nil {
            d.set(true, forKey: Keys.ocr)
        }
        self.ocrEnabled = d.bool(forKey: Keys.ocr)
    }
}
