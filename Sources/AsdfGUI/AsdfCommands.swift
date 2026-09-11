import SwiftUI

@MainActor
struct AsdfCommands: Commands {
    let navigation: AppNavigationModel

    @Environment(\.openWindow) private var openWindow
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.defaultLanguage.rawValue

    private var language: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? AppLanguage.defaultLanguage
    }

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button(language.localized("About asdf GUI…")) {
                openWindow(id: "about")
            }
        }

        CommandMenu(language.localized("Navigate")) {
            Button(language.localized("Overview")) { navigation.show(.overview) }
                .keyboardShortcut("1", modifiers: [.command])
            Button(language.localized("Projects")) { navigation.show(.projects) }
                .keyboardShortcut("2", modifiers: [.command])
            Button(language.localized("Versions")) { navigation.show(.versions) }
                .keyboardShortcut("3", modifiers: [.command])
            Button(language.localized("Resolution")) { navigation.show(.resolution) }
                .keyboardShortcut("4", modifiers: [.command])
            Button(language.localized("Plugins")) { navigation.show(.plugins) }
                .keyboardShortcut("5", modifiers: [.command])
        }

        CommandGroup(after: .appSettings) {
            Button(language.localized("Getting Started…")) {
                openWindow(id: "getting-started")
            }

            Divider()

            Button(language.localized("Set Runtime Version…")) {
                openWindow(id: "version-selection")
            }
            .keyboardShortcut("v", modifiers: [.command, .shift])

            Button(language.localized("asdf Configuration…")) {
                openWindow(id: "asdf-configuration")
            }
            .keyboardShortcut(",", modifiers: [.command, .option])

            Divider()

            Button(language.localized("Manage Plugins…")) {
                openWindow(id: "plugin-manager")
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])

            Button(language.localized("Diagnostics…")) {
                openWindow(id: "diagnostics")
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])

            Button(language.localized("Shell Integration…")) {
                openWindow(id: "shell-integration")
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])

            Button(language == .simplifiedChinese ? "Shell 自动补全…" : "Shell Completions…") {
                openWindow(id: "shell-completions")
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
        }
    }
}
