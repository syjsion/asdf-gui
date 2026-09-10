import Foundation
import Observation
import SwiftUI

struct RuntimeUpdateRecord: Identifiable, Hashable, Sendable {
    let tool: String
    let installedVersions: [String]
    let latestVersion: String?
    let errorMessage: String?

    var id: String { tool }
    var latestInstalled: Bool {
        guard let latestVersion else { return false }
        return installedVersions.contains(latestVersion)
    }
    var canInstallLatest: Bool { latestVersion != nil && !latestInstalled && errorMessage == nil }
}

@MainActor
@Observable
final class RuntimeUpdateCenterModel {
    var records: [RuntimeUpdateRecord] = []
    var isLoading = false
    var errorMessage: String?

    private let service = AsdfService()

    func load(appModel: AppModel) async {
        guard let executable = appModel.executableURL else {
            records = []
            errorMessage = "asdf executable is not available."
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        var loaded: [RuntimeUpdateRecord] = []
        for plugin in appModel.plugins.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) {
            var installed: [String] = []
            var latest: String?
            var errors: [String] = []

            do {
                installed = try await service.installedVersions(executable: executable, tool: plugin.name)
                appModel.installedVersionsByTool[plugin.name] = installed
            } catch {
                errors.append("Installed: \(error.localizedDescription)")
            }

            do {
                latest = try await service.latestVersion(executable: executable, tool: plugin.name)
            } catch {
                errors.append("Latest: \(error.localizedDescription)")
            }

            loaded.append(
                RuntimeUpdateRecord(
                    tool: plugin.name,
                    installedVersions: installed,
                    latestVersion: latest,
                    errorMessage: errors.isEmpty ? nil : errors.joined(separator: "\n")
                )
            )
        }
        records = loaded
    }
}

@MainActor
struct RuntimeUpdateCenterView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.defaultLanguage.rawValue
    @State private var model = RuntimeUpdateCenterModel()
    @State private var searchText = ""

    private var language: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? AppLanguage.defaultLanguage
    }

    private var displayed: [RuntimeUpdateRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return model.records }
        return model.records.filter { $0.tool.localizedCaseInsensitiveContains(query) }
    }

    private var updatesAvailable: Int {
        model.records.filter(\.canInstallLatest).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(language.localized("Runtime Update Center"))
                        .font(.largeTitle.bold())
                    Text(language.localized("Compare every installed plugin with its latest stable runtime without changing project configuration."))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if model.isLoading { ProgressView().controlSize(.small) }
                Button(language.localized("Refresh"), systemImage: "arrow.clockwise") {
                    Task { await model.load(appModel: appModel) }
                }
                .disabled(model.isLoading || appModel.hasActiveOperation)
                Button(language.localized("Close")) { dismiss() }
            }

            GroupBox {
                HStack {
                    LabeledContent(language.localized("Plugins"), value: "\(model.records.count)")
                    Spacer()
                    LabeledContent(language.localized("Updates available"), value: "\(updatesAvailable)")
                }
            }

            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }

            if let operation = appModel.activeVersionOperation {
                VersionOperationPanel(task: operation)
            }

            Table(displayed) {
                TableColumn(language.localized("Tool")) { record in
                    Text(record.tool).fontWeight(.medium)
                }
                TableColumn(language.localized("Installed")) { record in
                    Text(installedSummary(record.installedVersions))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
                TableColumn(language.localized("Latest")) { record in
                    Text(record.latestVersion ?? "—")
                        .font(.system(.body, design: .monospaced))
                }
                TableColumn(language.localized("Status")) { record in
                    if let error = record.errorMessage {
                        Label(language.localized("Check failed"), systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .help(error)
                    } else if record.latestInstalled {
                        Label(language.localized("Up to date"), systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.secondary)
                    } else if record.installedVersions.isEmpty {
                        Text(language.localized("Not installed"))
                            .foregroundStyle(.secondary)
                    } else {
                        Label(language.localized("Update available"), systemImage: "arrow.up.circle.fill")
                    }
                }
                TableColumn(language.localized("Action")) { record in
                    if record.canInstallLatest, let latest = record.latestVersion {
                        Button(language.localized("Install Latest")) {
                            appModel.installVersionFromBrowser(tool: record.tool, version: latest)
                        }
                        .buttonStyle(.borderless)
                        .disabled(appModel.hasActiveOperation)
                        .help(language.localized("Installs the exact latest version. Existing versions and .tool-versions entries are not removed or rewritten."))
                    }
                }
            }
        }
        .padding(24)
        .frame(minWidth: 820, minHeight: 580)
        .searchable(text: $searchText, prompt: language.localized("Search runtimes"))
        .task { await model.load(appModel: appModel) }
        .onChange(of: appModel.activeVersionOperation?.status) { _, status in
            if status == .succeeded {
                Task { await model.load(appModel: appModel) }
            }
        }
    }

    private func installedSummary(_ versions: [String]) -> String {
        guard !versions.isEmpty else { return language.localized("None") }
        if versions.count <= 3 { return versions.joined(separator: ", ") }
        return versions.prefix(3).joined(separator: ", ") + " +\(versions.count - 3)"
    }
}
