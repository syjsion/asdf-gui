import SwiftUI

@MainActor
struct ResolutionView: View {
    @Environment(AppModel.self) private var appModel
    @State private var state = ResolutionModel()
    @State private var contextID = "__home__"
    @State private var toolFilter = "__all__"
    @State private var command = ""

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
                Text("Resolution")
                    .font(.largeTitle.bold())
                Text("Explain which runtime version and executable asdf resolves in a specific project context.")
                    .foregroundStyle(.secondary)
            }

            GroupBox("Context") {
                HStack(spacing: 14) {
                    Picker("Directory", selection: $contextID) {
                        ForEach(contexts) { context in
                            Text(context.title).tag(context.id)
                        }
                    }
                    .frame(minWidth: 220)

                    Picker("Tool", selection: $toolFilter) {
                        Text("All tools").tag("__all__")
                        ForEach(appModel.plugins) { plugin in
                            Text(plugin.name).tag(plugin.name)
                        }
                    }
                    .frame(minWidth: 180)

                    Spacer()

                    if state.isLoadingCurrent {
                        ProgressView().controlSize(.small)
                    }
                    Button("Resolve Versions", systemImage: "arrow.triangle.branch") {
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
            }

            if let error = state.currentError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.callout)
                    .textSelection(.enabled)
            }

            GroupBox("Effective versions") {
                if state.currentEntries.isEmpty && !state.isLoadingCurrent {
                    ContentUnavailableView(
                        "No resolution results",
                        systemImage: "arrow.triangle.branch",
                        description: Text("Choose a context and resolve all tools or one installed plugin.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 150)
                } else {
                    Table(state.currentEntries) {
                        TableColumn("Tool") { entry in
                            Text(entry.name).fontWeight(.medium)
                        }
                        TableColumn("Version") { entry in
                            Text(entry.version)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                        }
                        TableColumn("Source") { entry in
                            Text(entry.source ?? "—")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        TableColumn("Installed") { entry in
                            Label(
                                entry.isInstalled ? "Installed" : "Missing",
                                systemImage: entry.isInstalled ? "checkmark.circle.fill" : "exclamationmark.circle"
                            )
                            .foregroundStyle(entry.isInstalled ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.red))
                        }
                    }
                    .frame(minHeight: 180)
                }
            }

            GroupBox("Shim & command explorer") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        TextField("Command, e.g. node, npm, python, yarn", text: $command)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { resolveCommand() }
                        if state.isLoadingCommand {
                            ProgressView().controlSize(.small)
                        }
                        Button("Resolve Command", systemImage: "scope") {
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
                        LabeledContent("Resolved executable") {
                            Text(path)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }

                    if !state.shimProviders.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Shim providers").font(.headline)
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
