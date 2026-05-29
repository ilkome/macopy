import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    var onBack: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.3)
            ScrollView {
                content
                    .padding(20)
            }
        }
    }

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 10) {
            if let onBack {
                Button {
                    onBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Назад")
            }
            Text("Настройки")
                .font(.system(size: 14, weight: .semibold))
            Spacer()
        }
        .padding(.horizontal, 18)
        .frame(height: Layout.searchHeight)
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 24) {
            section(title: "Поиск") {
                    Toggle(isOn: $settings.ocrEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("OCR для скриншотов")
                            Text("Распознаёт текст на изображениях и делает его искомым.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                section(title: "Приватность") {
                    Toggle(isOn: $settings.filterSensitiveContent) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Не сохранять секреты")
                            Text("Отфильтровывает JWT, API-ключи (AWS, GitHub, Stripe, OpenAI, Anthropic, Google) и строки с высокой энтропией. В историю такие записи не попадают.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                section(title: "Внешний вид") {
                    HStack {
                        Text("Плотность фона")
                        Spacer()
                        Picker("", selection: $settings.panelMaterial) {
                            ForEach(PanelMaterial.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 160)
                    }
                }

                section(title: "Превью ссылок") {
                    Toggle(isOn: $settings.linkPreviewsEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Показывать превью ссылок")
                            Text("Подгружает заголовок, описание и картинку. Не работает для локальных/приватных адресов.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                section(title: "Глобальный хоткей") {
                    HStack {
                        Text("Открыть панель")
                        Spacer()
                        KeyboardShortcuts.Recorder(for: .togglePanel)
                    }
                }

                section(title: "Клавиши в панели") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Self.panelShortcuts, id: \.label) { row in
                            shortcutRow(label: row.label, keys: row.keys)
                        }
                    }
                }

                section(title: "FAQ") {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Self.faqEntries, id: \.q) { entry in
                            faqItem(q: entry.q, a: entry.a)
                        }
                    }
                }
        }
    }

    private func shortcutRow(label: String, keys: [String]) -> some View {
        HStack {
            Text(label)
            Spacer()
            HStack(spacing: 4) {
                ForEach(keys, id: \.self) { key in
                    Text(key)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.primary.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(Color.primary.opacity(0.12))
                        )
                }
            }
        }
    }

    private func faqItem(q: String, a: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(q)
                .font(.system(size: 13, weight: .semibold))
            Text(a)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func section<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
            content()
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.05))
                )
        }
    }

    // Глифы команд над элементом берём из PanelCommand, чтобы FAQ, контекстное
    // меню и PanelKeyMonitor не разъезжались.
    private static let panelShortcuts: [(label: String, keys: [String])] = [
        ("Навигация по списку", ["↑", "↓"]),
        ("Переключение вкладок", ["←", "→"]),
        ("Вставить в предыдущее окно", PanelCommand.paste.shortcutGlyphs),
        ("Скопировать в буфер без вставки", PanelCommand.copyOnly.shortcutGlyphs),
        ("Открыть ссылку в браузере", PanelCommand.openURL.shortcutGlyphs),
        ("Избранное", PanelCommand.favorite.shortcutGlyphs),
        ("Дублировать", PanelCommand.clone.shortcutGlyphs),
        ("Редактировать текст", PanelCommand.edit.shortcutGlyphs),
        ("Комментарий", PanelCommand.comment.shortcutGlyphs),
        ("Удалить элемент", PanelCommand.delete.shortcutGlyphs),
        ("Quick Look для изображений", PanelCommand.quickLook.shortcutGlyphs),
        ("Открыть настройки", ["⌘", ","]),
        ("Скрыть панель", ["⎋"])
    ]

    private static let faqEntries: [(q: String, a: String)] = [
        (
            "Как быстро найти ссылку?",
            "Префикс @ в поиске поднимает URL-результаты вверх: «@github» сначала покажет совпадения по ссылкам. Одиночный «@» выводит все ссылки по свежести."
        ),
        (
            "Как разрешить автоматическую вставку?",
            "Системные настройки → Приватность и безопасность → Универсальный доступ, включи MaCopy. Без этого содержимое копируется в буфер, но ⌘V симулироваться не будет."
        ),
        (
            "Где хранятся данные?",
            "~/Library/Application Support/MaCopy. SwiftData SQLite-база + картинки в отдельных файлах."
        ),
        (
            "Как исключить приложение?",
            "MaCopy уважает pasteboard.org-типы (ConcealedType, AutoGeneratedType, TransientType) и специфичные типы 1Password/Bitwarden."
        )
    ]
}
