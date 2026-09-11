import SwiftUI

@MainActor
struct LocalizedAppRootView: View {
    @Environment(AppModel.self) private var model
    @Environment(AsdfBootstrapModel.self) private var bootstrap
    @Environment(AppNavigationModel.self) private var appNavigation
    @Environment(\.openWindow) private var openWindow
    @AppStorage("asdfGUI.hasPresentedGettingStarted") private var hasPresentedGettingStarted = false
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.defaultLanguage.rawValue

    private var language: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? AppLanguage.defaultLanguage
    }

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
                navigationView
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

    private var navigationView: some View {
        let selection = Binding<AppSection?>(
            get: { appNavigation.section },
            set: { newValue in
                if let newValue {
                    appNavigation.section = newValue
                }
            }
        )

        return NavigationSplitView {
            List(AppSection.allCases, selection: selection) { item in
                Label {
                    Text(language.localized(item.titleKey))
                } icon: {
                    Image(systemName: item.icon)
                }
                .tag(item)
                .accessibilityLabel(Text(language.localized(item.titleKey)))
                .accessibilityHint(Text(shortcutHint(item)))
            }
            .navigationTitle("asdf GUI")
            .navigationSplitViewColumnWidth(min: 170, ideal: 205, max: 240)
        } detail: {
            switch appNavigation.section {
            case .overview: PolishedOverviewView()
            case .projects: ProjectsPolishedView()
            case .versions: VersionsPolishedView()
            case .resolution: ResolutionView()
            case .plugins: PluginsView()
            }
        }
        .task { await model.refresh() }
    }

    private func shortcutHint(_ section: AppSection) -> String {
        if language == .simplifiedChinese {
            return "按 Command-\(section.shortcutNumber) 可快速切换到此页面。"
        }
        return "Press Command-\(section.shortcutNumber) to switch to this section."
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
