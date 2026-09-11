import SwiftUI

@MainActor
struct PolishedOverviewView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigationModel.self) private var appNavigation
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.defaultLanguage.rawValue
    @State private var activity = ProjectActivityModel()
    @State private var isShowingProjectHealth = false
    @State private var isShowingStorageOverview = false
    @State private var projectToManage: ManagedProject?

    private var language: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? AppLanguage.defaultLanguage
    }

    private var localHealthIssues: Int {
        model.projectSnapshots.reduce(into: 0) { count, snapshot in
            count += ProjectHealthAnalyzer.issues(snapshot: snapshot) { tool, version in
                model.status(for: tool, version: version)
            }.filter { $0.severity == .warning || $0.severity == .error }.count
        }
    }

    private var favoriteSnapshots: [ProjectSnapshot] {
        Array(ProjectListPlanner.displayedSnapshots(
            model.projectSnapshots,
            searchText: "",
            scope: .favorites,
            sortOrder: .name,
            favoritePaths: activity.favoritePaths,
            lastUsedDates: activity.lastUsedDates
        ).prefix(4))
    }

    private var recentSnapshots: [ProjectSnapshot] {
        let candidates = ProjectListPlanner.displayedSnapshots(
            model.projectSnapshots,
            searchText: "",
            scope: .all,
            sortOrder: .recent,
            favoritePaths: [],
            lastUsedDates: activity.lastUsedDates
        )
        return Array(candidates.filter { snapshot in
            activity.lastUsedDates[snapshot.project.path] != nil
                && !activity.favoritePaths.contains(snapshot.project.path)
        }.prefix(4))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Environment").font(.largeTitle.bold())
                        Text("Local asdf status and installation details")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(l("Storage Overview", "存储总览"), systemImage: "internaldrive") {
                        isShowingStorageOverview = true
                    }
                    .disabled(model.plugins.isEmpty || model.isLoading || model.hasActiveOperation)
                    .accessibilityHint(Text(l(
                        "Measure disk usage across installed runtimes.",
                        "统计所有已安装运行时的磁盘占用。"
                    )))
                    Button(language.localized("Project Health"), systemImage: "checkmark.shield") {
                        isShowingProjectHealth = true
                    }
                    .disabled(model.projects.isEmpty || model.isLoading)
                    Button("Refresh", systemImage: "arrow.clockwise") {
                        Task { await model.refresh() }
                    }
                }

                GroupBox {
                    LabeledContent("asdf", value: model.asdfVersion)
                    Divider()
                    LabeledContent("Executable", value: model.executableURL?.path ?? "Not found")
                    Divider()
                    LabeledContent("Plugins", value: "\(model.plugins.count)")
                    Divider()
                    LabeledContent("Managed projects", value: "\(model.projects.count)")
                }

                if !favoriteSnapshots.isEmpty || !recentSnapshots.isEmpty {
                    GroupBox(l("Quick Access", "快速访问")) {
                        VStack(alignment: .leading, spacing: 14) {
                            if !favoriteSnapshots.isEmpty {
                                quickSection(
                                    title: l("Favorites", "收藏项目"),
                                    symbol: "star.fill",
                                    snapshots: favoriteSnapshots
                                )
                            }
                            if !favoriteSnapshots.isEmpty && !recentSnapshots.isEmpty {
                                Divider()
                            }
                            if !recentSnapshots.isEmpty {
                                quickSection(
                                    title: l("Recently Used", "最近使用"),
                                    symbol: "clock",
                                    snapshots: recentSnapshots
                                )
                            }
                        }
                    }
                }

                GroupBox(language.localized("Project Health")) {
                    HStack(spacing: 12) {
                        Image(systemName: localHealthIssues == 0 ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                            .font(.title2)
                            .foregroundStyle(localHealthIssues == 0 ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.orange))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(healthHeadline)
                                .font(.headline)
                            Text(language.localized("Open the full health report to include effective asdf resolution sources for every project."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(language.localized("Open Health Report")) {
                            isShowingProjectHealth = true
                        }
                        .disabled(model.projects.isEmpty)
                    }
                }

                if let error = model.errorMessage {
                    ContentUnavailableView("asdf unavailable", systemImage: "exclamationmark.triangle", description: Text(error))
                }
            }
            .padding(28)
        }
        .overlay { if model.isLoading { ProgressView().controlSize(.large) } }
        .onAppear {
            activity.reload()
            activity.prune(to: model.projects)
        }
        .onChange(of: model.projects) { _, projects in
            activity.prune(to: projects)
        }
        .sheet(isPresented: $isShowingProjectHealth) {
            ProjectHealthView()
        }
        .sheet(isPresented: $isShowingStorageOverview) {
            StorageOverviewView()
        }
        .sheet(item: $projectToManage) { project in
            ProjectToolVersionsManagerView(project: project)
        }
    }

    @ViewBuilder
    private func quickSection(
        title: String,
        symbol: String,
        snapshots: [ProjectSnapshot]
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(title, systemImage: symbol)
                .font(.headline)
            ForEach(snapshots) { snapshot in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(snapshot.project.name)
                            .fontWeight(.medium)
                        Text(snapshot.project.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    if let lastUsed = activity.lastUsedDates[snapshot.project.path] {
                        Text(lastUsed, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Button(l("Show in Projects", "在项目中显示")) {
                        activity.markUsed(snapshot.project)
                        appNavigation.showProject(snapshot.project)
                    }
                    .buttonStyle(.borderless)
                    Button(l("Manage", "管理")) {
                        activity.markUsed(snapshot.project)
                        projectToManage = snapshot.project
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.hasActiveOperation)
                    .accessibilityLabel(Text(l(
                        "Manage .tool-versions for \(snapshot.project.name)",
                        "管理 \(snapshot.project.name) 的 .tool-versions"
                    )))
                }
                .accessibilityElement(children: .contain)
            }
        }
    }

    private var healthHeadline: String {
        if model.projects.isEmpty {
            return language.localized("No managed projects")
        }
        if localHealthIssues == 0 {
            return language.localized("No known project issues")
        }
        return language == .simplifiedChinese
            ? "发现 \(localHealthIssues) 个项目问题"
            : "\(localHealthIssues) project issue\(localHealthIssues == 1 ? "" : "s") detected"
    }

    private func l(_ english: String, _ chinese: String) -> String {
        language == .simplifiedChinese ? chinese : english
    }
}
