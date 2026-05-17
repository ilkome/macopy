import Foundation

enum Tab: Int, CaseIterable {
    case favorites, all, urls, images, colors, code

    var title: String {
        switch self {
        case .all: "Все"
        case .favorites: "Избранное"
        case .images: "Изображения"
        case .urls: "Ссылки"
        case .colors: "Цвета"
        case .code: "Код"
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
