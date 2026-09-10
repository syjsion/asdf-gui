import SwiftUI

@main
@MainActor
struct AsdfGUIApp: App {
    @State private var model = AppModel()
    @State private var bootstrapModel = AsdfBootstrapModel()

    var body: some Scene {
        WindowGroup {
            RootContentView()
                .environment(model)
                .environment(bootstrapModel)
                .frame(minWidth: 900, minHeight: 580)
        }
        .commands {
            AsdfCommands()
        }

        Window("Set Runtime Version", id: "version-selection") {
            VersionSelectionView()
                .environment(model)
        }
        .defaultSize(width: 620, height: 500)

        Window("Plugin Manager", id: "plugin-manager") {
            PluginManagerView()
                .environment(model)
        }
        .defaultSize(width: 860, height: 620)

        Window("Diagnostics", id: "diagnostics") {
            DiagnosticsView()
                .environment(model)
        }
        .defaultSize(width: 820, height: 620)

        Window("Shell Integration", id: "shell-integration") {
            ShellIntegrationView()
                .environment(model)
        }
        .defaultSize(width: 760, height: 610)

        Settings {
            SettingsView()
                .environment(model)
                .environment(bootstrapModel)
        }
    }
}
