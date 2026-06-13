import Foundation

enum Tab: Int, CaseIterable {
    case favorites, all, folders, urls, images, colors, code

    var title: String {
        switch self {
        case .all: String(localized: "All")
        case .favorites: String(localized: "Favorites")
        case .folders: String(localized: "Folders")
        case .images: String(localized: "Images")
        case .urls: String(localized: "Links")
        case .colors: String(localized: "Colors")
        case .code: String(localized: "Code")
        }
    }

    func matches(_ item: ClipboardItemRecord) -> Bool {
        switch self {
        case .all: true
        // Folder membership isn't a property of the record; the folders tab keeps every
        // loaded clip available so the active folder's items can be looked up by id.
        case .folders: true
        case .favorites: item.isFavorite
        case .images: item.kind == .image
        case .urls: item.kind == .url
        case .colors: item.kind == .color
        case .code: item.kind == .code
        }
    }
}
