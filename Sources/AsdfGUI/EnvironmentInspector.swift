import Foundation
import Observation
import SwiftUI

struct EnvironmentComparisonRow: Identifiable, Hashable, Sendable {
    let key: String
    let homeValue: String?
    let contextValue: String?

    var id: String { key }
    var isChanged: Bool { homeValue != contextValue }
}

enum EnvironmentComparison {
    static func rows(
        home: [AsdfEnvironmentEntry],
        context: [AsdfEnvironmentEntry]
    ) -> [EnvironmentComparisonRow] {
        let homeMap = Dictionary(uniqueKeysWithValues: home.map { ($0.key, $0.value) })
        let contextMap = Dictionary(uniqueKeysWithValues: context.map { ($0.key, $0.value) })
        let keys = Set(homeMap.keys).union(contextMap.keys)
        return keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }.map { key in
            EnvironmentComparisonRow(
                key: key,
                homeValue: homeMap[key],
                contextValue: contextMap[key]
            )
        }
    }
}

@MainActor
@Observable
final class EnvironmentInspectorModel {
    var rows: [EnvironmentComparisonRow] = []
    var isLoading = false
    var errorMessage: String?
    var inspectedCommand: String?

    private let service = AsdfService()

    func inspect(command: String, appModel: AppModel, context: ResolutionContext) async {
        let command = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else {
            errorMessage = "Enter a shimmed command such as node, python, ruby, or yarn."
            return
        }
        guard let executable = appModel.executableURL else {
            errorMessage = "asdf executable is not available."
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let contextEnvironment = try await service.environment(
                executable: executable,
                command: command,
                currentDirectory: context.directory
            )
            let homeEnvironment: [AsdfEnvironmentEntry]
            if context.project == nil {
                homeEnvironment = contextEnvironment
            } else {
                homeEnvironment = try await service.environment(
                    executable: executable,
                    command: command,
                    currentDirectory: FileManager.default.homeDirectoryForCurrentUser
                )
            }
            rows = EnvironmentComparison.rows(home: homeEnvironment, context: contextEnvironment)
            inspectedCommand = command
        } catch {
            rows = []
            inspectedCommand = nil
            errorMessage = error.localizedDescription
        }
    }

    func reset() {
        rows = []
        errorMessage = nil
        inspectedCommand = nil
    }
}

@MainActor
struct EnvironmentInspectorSection: View {
    @Environment(AppModel.self) private var appModel
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.defaultLanguage.rawValue
    @State private var model = EnvironmentInspectorModel()
    @State private var command = ""
    @State private var changedOnly = true

    let context: ResolutionContext

    private var language: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? AppLanguage.defaultLanguage
    }

    private var displayedRows: [EnvironmentComparisonRow] {
        guard changedOnly, context.project != nil else { return model.rows }
        return model.rows.filter(\.isChanged)
    }

    var body: some View {
        GroupBox(language.localized("Environment Inspector")) {
            VStack(alignment: .leading, spacing: 12) {
                Text(language.localized("Inspect the environment that asdf gives a shimmed command, and compare this project with the Home context."))
                    .font(.callout)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    TextField(language.localized("Shimmed command, e.g. node or python"), text: $command)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { runInspection() }
                    if context.project != nil {
                        Toggle(language.localized("Changed only"), isOn: $changedOnly)
                            .toggleStyle(.checkbox)
                    }
                    if model.isLoading {
                        ProgressView().controlSize(.small)
                    }
                    Button(language.localized("Inspect Environment"), systemImage: "list.bullet.rectangle") {
                        runInspection()
                    }
                    .disabled(command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isLoading)
                }

                if let error = model.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.callout)
                        .textSelection(.enabled)
                }

                if model.rows.isEmpty && !model.isLoading {
                    Text(language.localized("Run an inspection to see PATH, ASDF_* variables, and plugin-provided environment differences."))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
                } else {
                    Table(displayedRows) {
                        TableColumn(language.localized("Variable")) { row in
                            HStack(spacing: 6) {
                                Text(row.key).font(.system(.body, design: .monospaced))
                                if row.isChanged {
                                    Image(systemName: "circle.fill")
                                        .font(.system(size: 6))
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                        TableColumn("Home") { row in
                            Text(row.homeValue ?? "—")
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .lineLimit(2)
                        }
                        TableColumn(language.localized("Selected context")) { row in
                            Text(row.contextValue ?? "—")
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .lineLimit(2)
                        }
                    }
                    .frame(minHeight: 180)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onChange(of: context.id) { _, _ in
            model.reset()
            changedOnly = context.project != nil
        }
    }

    private func runInspection() {
        Task { await model.inspect(command: command, appModel: appModel, context: context) }
    }
}
