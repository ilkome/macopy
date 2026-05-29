import SwiftUI

/// Единый источник истины для команд над элементом: подписи, иконки и глифы
/// клавиш. Используется контекстным меню (`ContentView`) и списком шорткатов в
/// настройках (`SettingsView`), чтобы маппинг не разъезжался с `PanelKeyMonitor`.
enum PanelCommand: CaseIterable, Identifiable {
    case paste
    case copyOnly
    case openURL
    case favorite
    case clone
    case edit
    case comment
    case quickLook
    case delete

    var id: Self { self }

    /// SF Symbol для пункта меню.
    var symbol: String {
        switch self {
        case .paste: return "doc.on.clipboard"
        case .copyOnly: return "doc.on.doc"
        case .openURL: return "safari"
        case .favorite: return "star"
        case .clone: return "plus.square.on.square"
        case .edit: return "pencil"
        case .comment: return "text.bubble"
        case .quickLook: return "eye"
        case .delete: return "trash"
        }
    }

    /// Глифы клавиш в порядке отображения, например `["⌘", "S"]`.
    var shortcutGlyphs: [String] {
        switch self {
        case .paste: return ["⏎"]
        case .copyOnly: return ["⇧", "⏎"]
        case .openURL: return ["⌘", "⏎"]
        case .favorite: return ["⌘", "S"]
        case .clone: return ["⌘", "D"]
        case .edit: return ["⌘", "E"]
        case .comment: return ["⌘", "W"]
        case .quickLook: return ["␣"]
        case .delete: return ["⌘", "⌫"]
        }
    }

    /// Готовая строка глифов для инлайн-подсказки в меню, например `"⌘S"`.
    var shortcutDisplay: String { shortcutGlyphs.joined() }

    /// Нативный шорткат для правого края пункта меню. Задаём только для
    /// ⌘-команд: их перехватывает локальный NSEvent-монитор раньше, чем меню
    /// обработает key equivalent, поэтому двойного срабатывания нет. Для ⏎/⇧⏎/␣
    /// возвращаем nil — иначе меню перехватит Enter/пробел раньше поля поиска.
    var nativeShortcut: KeyboardShortcut? {
        switch self {
        case .openURL: return KeyboardShortcut(.return, modifiers: .command)
        case .favorite: return KeyboardShortcut("s", modifiers: .command)
        case .clone: return KeyboardShortcut("d", modifiers: .command)
        case .edit: return KeyboardShortcut("e", modifiers: .command)
        case .comment: return KeyboardShortcut("w", modifiers: .command)
        case .delete: return KeyboardShortcut(.delete, modifiers: .command)
        case .paste, .copyOnly, .quickLook: return nil
        }
    }

    func title(for item: ClipboardItemRecord) -> String {
        switch self {
        case .paste: return "Вставить"
        case .copyOnly: return "Скопировать без вставки"
        case .openURL: return "Открыть в браузере"
        case .favorite: return item.isFavorite ? "Убрать из избранного" : "В избранное"
        case .clone: return "Дублировать"
        case .edit: return "Редактировать текст"
        case .comment: return "Комментарий"
        case .quickLook: return "Quick Look"
        case .delete: return "Удалить"
        }
    }

    func isAvailable(for item: ClipboardItemRecord) -> Bool {
        switch self {
        case .openURL: return item.kind == .url
        case .clone, .edit: return item.kind == .text
        case .quickLook: return item.kind == .image
        case .paste, .copyOnly, .favorite, .comment, .delete: return true
        }
    }
}
