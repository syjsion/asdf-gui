import SwiftUI

@main
@MainActor
struct AsdfGUIApp: App {
    @State private var model = AppModel()
    @State private var bootstrapModel = AsdfBootstrapModel()
    @State private var navigation = AppNavigationModel()
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.defaultLanguage.rawValue

    private var language: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? AppLanguage.defaultLanguage
    }

    var body: some Scene {
        WindowGroup {
            LocalizedAppRootView()
                .environment(model)
                .environment(bootstrapModel)
                .environment(navigation)
                .environment(\.locale, language.locale)
                .id(languageRaw)
                .frame(minWidth: 900, minHeight: 580)
        }
        .commands {
            AsdfCommands(navigation: navigation)
        }

        Window(language == .simplifiedChinese ? "添加运行时" : "Add Runtime", id: "runtime-setup") {
            RuntimeSetupView()
                .environment(model)
                .environment(navigation)
                .environment(\.locale, language.locale)
                .id(languageRaw)
        }
        .defaultSize(width: 980, height: 720)

        Window("Getting Started", id: "getting-started") {
            GettingStartedView()
                .environment(model)
                .environment(navigation)
                .environment(\.locale, language.locale)
                .id(languageRaw)
        }
        .defaultSize(width: 740, height: 680)

        Window("Set Runtime Version", id: "version-selection") {
            VersionSelectionView()
                .environment(model)
                .environment(navigation)
                .environment(\.locale, language.locale)
                .id(languageRaw)
        }
        .defaultSize(width: 620, height: 500)

        Window("Plugin Manager", id: "plugin-manager") {
            PluginManagerView()
                .environment(model)
                .environment(navigation)
                .environment(\.locale, language.locale)
                .id(languageRaw)
        }
        .defaultSize(width: 860, height: 620)

        Window("Diagnostics", id: "diagnostics") {
            DiagnosticsView()
                .environment(model)
                .environment(navigation)
                .environment(\.locale, language.locale)
                .id(languageRaw)
        }
        .defaultSize(width: 820, height: 620)

        Window("Shell Integration", id: "shell-integration") {
            ShellIntegrationView()
                .environment(model)
                .environment(navigation)
                .environment(\.locale, language.locale)
                .id(languageRaw)
        }
        .defaultSize(width: 760, height: 610)

        Window(language == .simplifiedChinese ? "Shell 自动补全" : "Shell Completions", id: "shell-completions") {
            ShellCompletionView()
                .environment(model)
                .environment(navigation)
                .environment(\.locale, language.locale)
                .id(languageRaw)
        }
        .defaultSize(width: 780, height: 650)

        Window(language.localized("asdf Configuration"), id: "asdf-configuration") {
            AsdfConfigurationView()
                .environment(model)
                .environment(navigation)
                .environment(\.locale, language.locale)
                .id(languageRaw)
        }
        .defaultSize(width: 760, height: 680)

        Window("About asdf GUI", id: "about") {
            AboutView()
                .environment(model)
                .environment(navigation)
                .environment(\.locale, language.locale)
                .id(languageRaw)
        }
        .defaultSize(width: 640, height: 560)
        .windowResizability(.contentSize)

        Settings {
            AppSettingsView()
                .environment(model)
                .environment(bootstrapModel)
                .environment(navigation)
                .environment(\.locale, language.locale)
                .id(languageRaw)
        }
    }
}
