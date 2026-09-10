import SwiftUI

@MainActor
struct ResolutionView: View {
    @Environment(AppModel.self) private var appModel
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.defaultLanguage.rawValue
    @State private var state = ResolutionModel()
    @State private var contextID = "__home__"
    @State private var toolFilter = "__all__"
    @State private var command = ""

    private var language: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? AppLanguage.defaultLanguage
    }

    private var contexts: [ResolutionContext] {
        [ResolutionContext(project: nil)] + appModel.projects.map { ResolutionContext(project: $0) }
    }

    private var selectedContext: ResolutionContext {
        contexts.first(where: { $0.id == contextID }) ?? ResolutionContext(project: nil)
    }

    private var selectedTool: String? {
        toolFilter == "__all__" ? nil : toolFilter
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(language.localized("Resolution"))
                    .font(.largeTitle.bold())
                Text(language.localized("Explain which runtime version and executable asdf resolves in a specific project context."))
                    .foregroundStyle(.secondary)
            }

            GroupBox {
                HStack(spacing: 14) {
                    Picker(language.localized("Directory"), selection: $contextID) {
                        ForEach(contexts) { context in
                            Text(context.project == nil ? language.localized("Home") : context.title).tag(context.id)
                        }
                    }
                    .frame(minWidth: 220)

                    Picker(language.localized("Tool"), selection: $toolFilter) {
                        Text(language.localized("All tools")).tag("__all__")
                        ForEach(appModel.plugins) { plugin in
                            Text(plugin.name).tag(plugin.name)
                        }
                    }
                    .frame(minWidth: 180)

                    Spacer()

                    if state.isLoadingCurrent {
                        ProgressView().controlSize(.small)
                    }
                    Button(language.localized("Resolve Versions"), systemImage: "arrow.triangle.branch") {
                        Task {
                            await state.loadCurrent(
                                appModel: appModel,
                                context: selectedContext,
                                tool: selectedTool
                            )
                        }
                    }
                    .disabled(state.isLoadingCurrent)
                }

                Text(selectedContext.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Text(language.localized("Context"))
            }

            if let error = state.currentError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.callout)
                    .textSelection(.enabled)
            }

            GroupBox {
                if state.currentEntries.isEmpty && !state.isLoadingCurrent {
                    ContentUnavailableView(
                        language.localized("No resolution results"),
                        systemImage: "arrow.triangle.branch",
                        description: Text(language.localized("Choose a context and resolve all tools or one installed plugin."))
                    )
                    .frame(maxWidth: .infinity, minHeight: 150)
                } else {
                    Table(state.currentEntries) {
                        TableColumn(language.localized("Tool")) { entry in
                            Text(entry.name).fontWeight(.medium)
                        }
                        TableColumn(language.localized("Version")) { entry in
                            Text(entry.version)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                        }
                        TableColumn(language.localized("Source")) { entry in
                            Text(entry.source ?? "—")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        TableColumn(language.localized("Installed")) { entry in
                            Label(
                                entry.isInstalled ? language.localized("Installed") : language.localized("Missing"),
                                systemImage: entry.isInstalled ? "checkmark.circle.fill" : "exclamationmark.circle"
                            )
                            .foregroundStyle(entry.isInstalled ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.red))
                        }
                    }
                    .frame(minHeight: 180)
                }
            } label: {
                Text(language.localized("Effective versions"))
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        TextField(language.localized("Command, e.g. node, npm, python, yarn"), text: $command)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { resolveCommand() }
                        if state.isLoadingCommand {
                            ProgressView().controlSize(.small)
                        }
                        Button(language.localized("Resolve Command"), systemImage: "scope") {
                            resolveCommand()
                        }
                        .disabled(command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || state.isLoadingCommand)
                    }

                    if let error = state.commandError {
                        Text(error)
                            .font(.callout)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }

                    if let path = state.resolvedCommandPath {
                        LabeledContent(language.localized("Resolved executable")) {
                            Text(path)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }

                    if !state.shimProviders.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(language.localized("Shim providers")).font(.headline)
                            ForEach(state.shimProviders) { provider in
                                HStack {
                                    Text(provider.plugin).fontWeight(.medium)
                                    Text(provider.version)
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Text(language.localized("Shim & command explorer"))
            }
        }
        .padding(28)
        .task {
            if state.currentEntries.isEmpty {
                await state.loadCurrent(appModel: appModel, context: selectedContext, tool: selectedTool)
            }
        }
        .onChange(of: appModel.projects) { _, projects in
            if contextID != "__home__" && !projects.contains(where: { $0.id == contextID }) {
                contextID = "__home__"
            }
        }
    }

    private func resolveCommand() {
        Task {
            await state.resolveCommand(command, appModel: appModel, context: selectedContext)
        }
    }
}
