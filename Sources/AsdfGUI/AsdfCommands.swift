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
            ForEach(AppSection.allCases) { section in
                Button(language.localized(section.titleKey)) {
                    navigation.show(section)
                }
                .keyboardShortcut(KeyEquivalent(Character(section.shortcutNumber)), modifiers: [.command])
            }
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
        }
    }
}
