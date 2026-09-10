import SwiftUI

struct AsdfCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .appSettings) {
            Button("Getting Started…") {
                openWindow(id: "getting-started")
            }

            Divider()

            Button("Set Runtime Version…") {
                openWindow(id: "version-selection")
            }
            .keyboardShortcut("v", modifiers: [.command, .shift])

            Divider()

            Button("Manage Plugins…") {
                openWindow(id: "plugin-manager")
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])

            Button("Diagnostics…") {
                openWindow(id: "diagnostics")
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])

            Button("Shell Integration…") {
                openWindow(id: "shell-integration")
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
        }
    }
}
