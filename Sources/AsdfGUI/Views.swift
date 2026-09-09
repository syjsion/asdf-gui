import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: SidebarItem? = .overview

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                Label(item.title, systemImage: item.icon).tag(item)
            }
            .navigationTitle("asdf GUI")
        } detail: {
            switch selection ?? .overview {
            case .overview: OverviewView()
            case .plugins: PluginsView()
            }
        }
        .task { await model.refresh() }
    }
}

enum SidebarItem: String, CaseIterable, Identifiable {
    case overview, plugins
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var icon: String { self == .overview ? "gauge.with.dots.needle.67percent" : "shippingbox" }
}

struct OverviewView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Environment").font(.largeTitle.bold())
                        Text("Local asdf status and installation details").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Refresh", systemImage: "arrow.clockwise") { Task { await model.refresh() } }
                }

                GroupBox {
                    LabeledContent("asdf", value: model.asdfVersion)
                    Divider()
                    LabeledContent("Executable", value: model.executableURL?.path ?? "Not found")
                    Divider()
                    LabeledContent("Plugins", value: "\(model.plugins.count)")
                }

                if let error = model.errorMessage {
                    ContentUnavailableView("asdf unavailable", systemImage: "exclamationmark.triangle", description: Text(error))
                }
            }
            .padding(28)
        }
        .overlay { if model.isLoading { ProgressView().controlSize(.large) } }
    }
}

struct PluginsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Plugins").font(.largeTitle.bold())
            if model.plugins.isEmpty && !model.isLoading {
                ContentUnavailableView("No plugins", systemImage: "shippingbox", description: Text("Install an asdf plugin or refresh the environment."))
            } else {
                Table(model.plugins) {
                    TableColumn("Plugin") { plugin in Text(plugin.name).fontWeight(.medium) }
                    TableColumn("Repository") { plugin in Text(plugin.url ?? "—").foregroundStyle(.secondary) }
                }
            }
        }
        .padding(28)
        .toolbar { Button("Refresh", systemImage: "arrow.clockwise") { Task { await model.refresh() } } }
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section("asdf executable") {
                LabeledContent("Detected path", value: model.executableURL?.path ?? "Not detected")
                Text("MVP auto-detects common Homebrew, local-bin and Go install locations. Manual executable selection is planned next.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 220)
    }
}
