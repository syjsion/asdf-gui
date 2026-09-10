import Foundation
import Observation

@MainActor
@Observable
final class ShellIntegrationModel {
    var selectedShell: SupportedShell
    var plan: ShellIntegrationPlan?
    var errorMessage: String?
    var isApplying = false

    private let service: ShellIntegrationService

    init(
        service: ShellIntegrationService = ShellIntegrationService(),
        detectedShellPath: String? = ProcessInfo.processInfo.environment["SHELL"]
    ) {
        self.service = service
        self.selectedShell = SupportedShell.detect(from: detectedShellPath) ?? .zsh
    }

    func refresh(executableURL: URL?) {
        guard let executableURL else {
            plan = nil
            errorMessage = "asdf executable is not available."
            return
        }

        do {
            plan = try service.plan(shell: selectedShell, executableURL: executableURL)
            errorMessage = nil
        } catch {
            plan = nil
            errorMessage = error.localizedDescription
        }
    }

    func selectShell(_ shell: SupportedShell, executableURL: URL?) {
        selectedShell = shell
        refresh(executableURL: executableURL)
    }

    func apply(appModel: AppModel) {
        guard !isApplying, let plan, appModel.beginExternalWriteOperation() else { return }
        isApplying = true
        defer {
            isApplying = false
            appModel.endExternalWriteOperation()
        }

        do {
            try service.apply(plan)
            self.plan = try service.plan(shell: selectedShell, executableURL: plan.executableURL)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            refresh(executableURL: appModel.executableURL)
        }
    }

    func remove(appModel: AppModel) {
        guard !isApplying, let plan, appModel.beginExternalWriteOperation() else { return }
        isApplying = true
        defer {
            isApplying = false
            appModel.endExternalWriteOperation()
        }

        do {
            try service.remove(plan)
            self.plan = try service.plan(shell: selectedShell, executableURL: plan.executableURL)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            refresh(executableURL: appModel.executableURL)
        }
    }
}
