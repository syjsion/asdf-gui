import SwiftUI

@MainActor
struct ShellIntegrationView: View {
    @Environment(AppModel.self) private var appModel
    @State private var model = ShellIntegrationModel()
    @State private var isShowingApplyConfirmation = false
    @State private var isShowingRemoveConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Shell Integration")
                        .font(.largeTitle.bold())
                    Text("Make the same asdf installation and its shims available in Terminal.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Shell", selection: Binding(
                    get: { model.selectedShell },
                    set: { model.selectShell($0, executableURL: appModel.executableURL) }
                )) {
                    ForEach(SupportedShell.allCases) { shell in
                        Text(shell.displayName).tag(shell)
                    }
                }
                .frame(width: 150)
            }

            if let plan = model.plan {
                GroupBox("Status") {
                    VStack(alignment: .leading, spacing: 9) {
                        LabeledContent("Shell", value: plan.shell.displayName)
                        LabeledContent("Configuration file", value: plan.configurationURL.path)
                        LabeledContent("asdf executable", value: plan.executableURL.path)
                        HStack {
                            Text("Integration")
                            Spacer()
                            Label(plan.status.title, systemImage: plan.status.symbolName)
                                .foregroundStyle(plan.status == .configured ? .secondary : .primary)
                        }
                    }
                    .textSelection(.enabled)
                }

                GroupBox("Managed block preview") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("asdf GUI only adds or replaces the block below. Existing content outside these markers is left unchanged.")
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        ScrollView {
                            Text(plan.managedBlock)
                                .font(.system(.callout, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                        }
                        .frame(minHeight: 115, maxHeight: 170)
                        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 7))
                    }
                }

                HStack {
                    Button("Refresh Preview", systemImage: "arrow.clockwise") {
                        model.refresh(executableURL: appModel.executableURL)
                    }
                    .disabled(model.isApplying || appModel.hasActiveOperation)

                    Spacer()

                    if plan.status != .notConfigured {
                        Button("Remove Integration", role: .destructive) {
                            isShowingRemoveConfirmation = true
                        }
                        .disabled(model.isApplying || appModel.hasActiveOperation)
                    }

                    if plan.status != .configured {
                        Button(plan.status == .needsUpdate ? "Update Integration" : "Configure Shell", systemImage: "terminal") {
                            isShowingApplyConfirmation = true
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isApplying || appModel.hasActiveOperation)
                    }
                }

                if plan.status == .configured {
                    Label("Configured. Open a new terminal session for PATH changes to take effect.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            } else if let executableURL = appModel.executableURL {
                ContentUnavailableView(
                    "Integration unavailable",
                    systemImage: "terminal",
                    description: Text(model.errorMessage ?? "Could not prepare shell integration for \(executableURL.path).")
                )
            } else {
                ContentUnavailableView(
                    "asdf is not ready",
                    systemImage: "shippingbox.and.arrow.backward",
                    description: Text("Install or select asdf before configuring your shell.")
                )
            }

            if let error = model.errorMessage, model.plan != nil {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.callout)
                    .textSelection(.enabled)
            }
        }
        .padding(28)
        .task(id: appModel.executableURL?.path) {
            model.refresh(executableURL: appModel.executableURL)
        }
        .alert("Configure shell?", isPresented: $isShowingApplyConfirmation) {
            Button("Configure") {
                model.apply(appModel: appModel)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let plan = model.plan {
                Text("asdf GUI will modify \(plan.configurationURL.path) by adding or replacing only its marked integration block. Existing content outside the markers will remain unchanged.")
            }
        }
        .alert("Remove shell integration?", isPresented: $isShowingRemoveConfirmation) {
            Button("Remove", role: .destructive) {
                model.remove(appModel: appModel)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let plan = model.plan {
                Text("Only the block between the asdf GUI markers will be removed from \(plan.configurationURL.path).")
            }
        }
    }
}

private extension ShellIntegrationStatus {
    var title: String {
        switch self {
        case .notConfigured: "Not configured"
        case .configured: "Configured"
        case .needsUpdate: "Update available"
        }
    }

    var symbolName: String {
        switch self {
        case .notConfigured: "circle.dashed"
        case .configured: "checkmark.circle.fill"
        case .needsUpdate: "arrow.triangle.2.circlepath.circle"
        }
    }
}
