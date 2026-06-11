import Foundation

enum Tab: Int, CaseIterable {
    case favorites, all, urls, images, colors, code

    var title: String {
        switch self {
        case .all: String(localized: "All")
        case .favorites: String(localized: "Favorites")
        case .images: String(localized: "Images")
        case .urls: String(localized: "Links")
        case .colors: String(localized: "Colors")
        case .code: String(localized: "Code")
        }
    }

    func matches(_ item: ClipboardItemRecord) -> Bool {
        switch self {
        case .all: true
        case .favorites: item.isFavorite
        case .images: item.kind == .image
        case .urls: item.kind == .url
        case .colors: item.kind == .color
        case .code: item.kind == .code
        }
    }
}
