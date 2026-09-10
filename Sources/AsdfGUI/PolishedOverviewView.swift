import SwiftUI

@MainActor
struct PolishedOverviewView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.defaultLanguage.rawValue
    @State private var isShowingProjectHealth = false

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
        .sheet(isPresented: $isShowingProjectHealth) {
            ProjectHealthView()
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
}
