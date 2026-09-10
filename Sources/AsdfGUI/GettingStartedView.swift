import SwiftUI

@MainActor
struct OnboardingRootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @AppStorage("asdfGUI.hasPresentedGettingStarted") private var hasPresentedGettingStarted = false

    var body: some View {
        RootContentView()
            .task { presentIfNeeded() }
            .onChange(of: model.executableURL?.path) { _, _ in presentIfNeeded() }
            .onChange(of: model.plugins) { _, _ in presentIfNeeded() }
    }

    private func presentIfNeeded() {
        guard !hasPresentedGettingStarted,
              !model.isLoading,
              model.executableURL != nil,
              model.plugins.isEmpty,
              model.projects.isEmpty else { return }
        hasPresentedGettingStarted = true
        openWindow(id: "getting-started")
    }
}

@MainActor
struct GettingStartedView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Getting Started")
                        .font(.largeTitle.bold())
                    Text("A short path from a working asdf installation to your first managed project.")
                        .foregroundStyle(.secondary)
                }

                onboardingStep(
                    number: 1,
                    title: "asdf is ready",
                    detail: model.executableURL.map { "\(model.asdfVersion) at \($0.path)" } ?? "Install or select asdf first.",
                    complete: model.executableURL != nil
                )

                onboardingStep(
                    number: 2,
                    title: "Connect your shell",
                    detail: "Add the active asdf executable directory and asdf shims to Zsh or Bash PATH. The exact managed block is previewed before any file is changed.",
                    complete: false,
                    actionTitle: "Shell Integration…"
                ) {
                    openWindow(id: "shell-integration")
                }

                onboardingStep(
                    number: 3,
                    title: "Add a plugin",
                    detail: model.plugins.isEmpty
                        ? "Plugins teach asdf how to install tools such as Node.js, Python, or Ruby."
                        : "\(model.plugins.count) plugin\(model.plugins.count == 1 ? "" : "s") installed.",
                    complete: !model.plugins.isEmpty,
                    actionTitle: model.plugins.isEmpty ? "Open Plugin Manager…" : "Manage Plugins…"
                ) {
                    openWindow(id: "plugin-manager")
                }

                onboardingStep(
                    number: 4,
                    title: "Install a runtime",
                    detail: "After adding a plugin, open Versions in the main sidebar, choose a version, and click Install."
                        + (model.plugins.isEmpty ? " Add a plugin first." : ""),
                    complete: false
                )

                onboardingStep(
                    number: 5,
                    title: "Add your first project",
                    detail: model.projects.isEmpty
                        ? "Open Projects in the main sidebar and add a folder containing .tool-versions."
                        : "\(model.projects.count) project\(model.projects.count == 1 ? "" : "s") managed.",
                    complete: !model.projects.isEmpty
                )

                GroupBox("What asdf GUI will not do automatically") {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("It will not silently edit shell files; Shell Integration requires an explicit confirmation.", systemImage: "doc.badge.gearshape")
                        Label("It will not auto-install plugins when a project references a missing plugin.", systemImage: "shippingbox")
                        Label("It will not rewrite .tool-versions unless you explicitly use a version-selection action.", systemImage: "checkmark.shield")
                    }
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: 660, alignment: .leading)
            .padding(30)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func onboardingStep(
        number: Int,
        title: String,
        detail: String,
        complete: Bool,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(complete ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.tertiary.opacity(0.5)))
                    .frame(width: 30, height: 30)
                if complete {
                    Image(systemName: "checkmark")
                        .font(.caption.bold())
                } else {
                    Text("\(number)")
                        .font(.caption.bold())
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .disabled(model.hasActiveOperation)
                }
            }
            Spacer()
        }
    }
}
