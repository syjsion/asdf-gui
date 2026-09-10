import SwiftUI

private enum LocalizedSidebarItem: String, CaseIterable, Identifiable {
    case overview
    case projects
    case versions
    case resolution
    case plugins

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .overview: "Overview"
        case .projects: "Projects"
        case .versions: "Versions"
        case .resolution: "Resolution"
        case .plugins: "Plugins"
        }
    }

    var icon: String {
        switch self {
        case .overview: "gauge.with.dots.needle.67percent"
        case .projects: "folder"
        case .versions: "square.stack.3d.up"
        case .resolution: "arrow.triangle.branch"
        case .plugins: "shippingbox"
        }
    }
}

@MainActor
struct LocalizedAppRootView: View {
    @Environment(AppModel.self) private var model
    @Environment(AsdfBootstrapModel.self) private var bootstrap
    @Environment(\.openWindow) private var openWindow
    @AppStorage("asdfGUI.hasPresentedGettingStarted") private var hasPresentedGettingStarted = false
    @State private var selection: LocalizedSidebarItem? = .overview

    var body: some View {
        Group {
            if model.isLoading && model.executableURL == nil && bootstrap.activeInstallation == nil {
                VStack(spacing: 14) {
                    ProgressView().controlSize(.large)
                    Text("Checking for asdf…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.executableURL == nil {
                AsdfSetupView()
            } else {
                navigation
            }
        }
        .task {
            if model.executableURL == nil {
                await model.refresh()
            }
            presentGettingStartedIfNeeded()
        }
        .onChange(of: model.executableURL?.path) { _, _ in presentGettingStartedIfNeeded() }
        .onChange(of: model.plugins) { _, _ in presentGettingStartedIfNeeded() }
    }

    private var navigation: some View {
        NavigationSplitView {
            List(LocalizedSidebarItem.allCases, selection: $selection) { item in
                Label(item.title, systemImage: item.icon)
                    .tag(item)
            }
            .navigationTitle("asdf GUI")
            .navigationSplitViewColumnWidth(min: 170, ideal: 205, max: 240)
        } detail: {
            switch selection ?? .overview {
            case .overview: OverviewView()
            case .projects: ProjectsPolishedView()
            case .versions: VersionsPolishedView()
            case .resolution: ResolutionView()
            case .plugins: PluginsView()
            }
        }
        .task { await model.refresh() }
    }

    private func presentGettingStartedIfNeeded() {
        guard !hasPresentedGettingStarted,
              !model.isLoading,
              model.executableURL != nil,
              model.plugins.isEmpty,
              model.projects.isEmpty else { return }
        hasPresentedGettingStarted = true
        openWindow(id: "getting-started")
    }
}
