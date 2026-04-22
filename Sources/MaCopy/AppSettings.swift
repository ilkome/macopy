import Foundation
import SwiftUI

enum PanelMaterial: String, CaseIterable, Identifiable {
    case regular
    case thick
    case ultraThick

    var id: String { rawValue }

    var title: String {
        switch self {
        case .regular: "Обычная"
        case .thick: "Плотная"
        case .ultraThick: "Максимальная"
        }
    }

    var material: Material {
        switch self {
        case .regular: .regularMaterial
        case .thick: .thickMaterial
        case .ultraThick: .ultraThickMaterial
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var ocrEnabled: Bool {
        didSet { UserDefaults.standard.set(ocrEnabled, forKey: Keys.ocr) }
    }

    @Published var panelMaterial: PanelMaterial {
        didSet { UserDefaults.standard.set(panelMaterial.rawValue, forKey: Keys.material) }
    }

    @Published var linkPreviewsEnabled: Bool {
        didSet { UserDefaults.standard.set(linkPreviewsEnabled, forKey: Keys.linkPreviews) }
    }

    private enum Keys {
        static let ocr = "ocrEnabled"
        static let material = "panelMaterial"
        static let linkPreviews = "linkPreviewsEnabled"
    }

    private init() {
        let d = UserDefaults.standard
        if d.object(forKey: Keys.ocr) == nil {
            d.set(true, forKey: Keys.ocr)
        }
        self.ocrEnabled = d.bool(forKey: Keys.ocr)
        let raw = d.string(forKey: Keys.material) ?? PanelMaterial.thick.rawValue
        self.panelMaterial = PanelMaterial(rawValue: raw) ?? .thick
        if d.object(forKey: Keys.linkPreviews) == nil {
            d.set(true, forKey: Keys.linkPreviews)
        }
        self.linkPreviewsEnabled = d.bool(forKey: Keys.linkPreviews)
    }
}
