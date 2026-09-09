import SwiftUI

struct AsdfCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .appSettings) {
            Button("Set Runtime Version…") {
                openWindow(id: "version-selection")
            }
            .keyboardShortcut("v", modifiers: [.command, .shift])
        }
    }
}
