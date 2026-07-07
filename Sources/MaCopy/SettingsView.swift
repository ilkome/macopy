import AppKit
import KeyboardShortcuts
import ServiceManagement
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
                .help("Back")
            }
            Text("Settings")
                .font(.system(size: 14, weight: .semibold))
            Spacer()
        }
        .padding(.horizontal, 18)
        .frame(height: Layout.searchHeight)
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 24) {
            section(title: "Language") {
                    HStack {
                        Text("Interface language")
                        Spacer()
                        Picker("", selection: languageBinding) {
                            Text("System").tag("")
                            ForEach(Self.languageOptions) { option in
                                Text(verbatim: option.name).tag(option.code)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 200)
                    }
                }

                section(title: "Startup") {
                    Toggle(isOn: launchAtLoginBinding) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Launch at login")
                            Text("MaCopy starts automatically when you sign in.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                section(title: "Search") {
                    Toggle(isOn: $settings.ocrEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("OCR for screenshots")
                            Text("Recognizes text in images and makes it searchable.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                section(title: "Privacy") {
                    Toggle(isOn: $settings.filterSensitiveContent) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Don't save secrets")
                            Text("Filters out JWTs, API keys (AWS, GitHub, Stripe, OpenAI, Anthropic, Google) and high-entropy strings. Such entries never reach the history.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                section(title: "Appearance") {
                    HStack {
                        Text("Background density")
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

                section(title: "Link previews") {
                    Toggle(isOn: $settings.linkPreviewsEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Show link previews")
                            Text("Loads the title, description, and image. Doesn't work for local/private addresses.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                section(title: "Global hotkey") {
                    HStack {
                        Text("Open panel")
                        Spacer()
                        KeyboardShortcuts.Recorder(for: .togglePanel)
                    }
                }

                section(title: "Keys in the panel") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(Self.panelShortcuts.enumerated()), id: \.offset) { _, row in
                            shortcutRow(label: row.label, keys: row.keys)
                        }
                    }
                }

                section(title: "FAQ") {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(Self.faqEntries.enumerated()), id: \.offset) { _, entry in
                            faqItem(q: entry.q, a: entry.a)
                        }
                    }
                }
        }
    }

    private func shortcutRow(label: LocalizedStringKey, keys: [String]) -> some View {
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

    private func faqItem(q: LocalizedStringKey, a: LocalizedStringKey) -> some View {
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
        title: LocalizedStringKey,
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
    private static let panelShortcuts: [(label: LocalizedStringKey, keys: [String])] = [
        ("List navigation", ["↑", "↓"]),
        ("Switch tabs", ["←", "→"]),
        ("Paste into the previous window", PanelCommand.paste.shortcutGlyphs),
        ("Copy to clipboard without pasting", PanelCommand.copyOnly.shortcutGlyphs),
        ("Open link in browser", PanelCommand.openURL.shortcutGlyphs),
        ("Favorites", PanelCommand.favorite.shortcutGlyphs),
        ("Duplicate", PanelCommand.clone.shortcutGlyphs),
        ("Edit text", PanelCommand.edit.shortcutGlyphs),
        ("Comment", PanelCommand.comment.shortcutGlyphs),
        ("Delete item", PanelCommand.delete.shortcutGlyphs),
        ("Quick Look for images", PanelCommand.quickLook.shortcutGlyphs),
        ("Open settings", ["⌘", ","]),
        ("Hide panel", ["⎋"])
    ]

    private static let faqEntries: [(q: LocalizedStringKey, a: LocalizedStringKey)] = [
        (
            "How do I find a link quickly?",
            "The @ prefix in search pushes URL results to the top: \"@github\" shows link matches first. A lone \"@\" lists all links by recency."
        ),
        (
            "How do I allow automatic pasting?",
            "System Settings → Privacy & Security → Accessibility, enable MaCopy. Without it, content is copied to the clipboard, but ⌘V won't be simulated."
        ),
        (
            "Where is data stored?",
            "~/Library/Application Support/MaCopy. A SwiftData SQLite database plus images in separate files."
        ),
        (
            "How do I exclude an app?",
            "MaCopy respects pasteboard.org types (ConcealedType, AutoGeneratedType, TransientType) and 1Password/Bitwarden-specific types."
        )
    ]

    // MARK: - Language picker

    struct LanguageOption: Identifiable {
        let code: String
        let name: String
        var id: String { code }
    }

    static let languageOptions: [LanguageOption] = [
        .init(code: "en", name: "English"),
        .init(code: "ru", name: "Русский"),
        .init(code: "zh-Hans", name: "简体中文"),
        .init(code: "ja", name: "日本語"),
        .init(code: "ko", name: "한국어"),
        .init(code: "de", name: "Deutsch"),
        .init(code: "fr", name: "Français"),
        .init(code: "es", name: "Español"),
        .init(code: "it", name: "Italiano"),
        .init(code: "pt-BR", name: "Português (Brasil)"),
        .init(code: "tr", name: "Türkçe"),
        .init(code: "pl", name: "Polski")
    ]

    /// Wraps `settings.appLanguage` so changing the picker also offers a
    /// relaunch, which is when an `AppleLanguages` override actually takes hold.
    private var languageBinding: Binding<String> {
        Binding(
            get: { settings.appLanguage },
            set: { newValue in
                guard newValue != settings.appLanguage else { return }
                settings.appLanguage = newValue
                promptRelaunch()
            }
        )
    }

    /// Writes the Login Items state, reflects the actual resulting status back
    /// into the toggle, and guides the user to System Settings when macOS holds
    /// the request for approval.
    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { settings.launchAtLogin },
            set: { newValue in
                let status = LaunchAtLogin.setEnabled(newValue)
                settings.launchAtLogin = (status == .enabled)
                if newValue && status == .requiresApproval {
                    promptLoginItemsApproval()
                }
            }
        )
    }

    @MainActor
    private func promptLoginItemsApproval() {
        let alert = NSAlert()
        alert.messageText = String(localized: "Allow MaCopy in Login Items")
        alert.informativeText = String(localized: "macOS needs your approval. Open System Settings → General → Login Items and enable MaCopy.")
        alert.addButton(withTitle: String(localized: "Open System Settings"))
        alert.addButton(withTitle: String(localized: "Later"))
        if alert.runModal() == .alertFirstButtonReturn {
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    @MainActor
    private func promptRelaunch() {
        let alert = NSAlert()
        alert.messageText = String(localized: "Restart required")
        alert.informativeText = String(localized: "The language change will take effect after MaCopy restarts.")
        alert.addButton(withTitle: String(localized: "Restart now"))
        alert.addButton(withTitle: String(localized: "Later"))
        if alert.runModal() == .alertFirstButtonReturn {
            relaunchApp()
        }
    }

    @MainActor
    private func relaunchApp() {
        let bundleURL = Bundle.main.bundleURL
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", bundleURL.path]
        try? task.run()
        NSApp.terminate(nil)
    }
}
