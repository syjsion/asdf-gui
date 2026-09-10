import Foundation
import Observation

@MainActor
@Observable
final class AsdfBootstrapModel {
    var activeInstallation: AsdfInstallationTaskState?

    private let installer = AsdfInstaller()
    private let logLimit = 120_000
    private var installationTask: Task<Void, Never>?

    var isInstalling: Bool {
        activeInstallation?.isRunning == true
    }

    func install(appModel: AppModel) {
        guard appModel.executableURL == nil else { return }
        guard activeInstallation?.isRunning != true else { return }
        guard appModel.beginExternalWriteOperation() else { return }

        let id = UUID()
        activeInstallation = AsdfInstallationTaskState(
            id: id,
            status: .running,
            version: nil,
            destination: nil,
            log: "Installing asdf from the latest official GitHub release…\n",
            errorMessage: nil
        )

        installationTask = Task { [weak self] in
            guard let self else {
                appModel.endExternalWriteOperation()
                return
            }
            defer { appModel.endExternalWriteOperation() }

            do {
                let destination = try await installer.installLatest { [weak self] text in
                    Task { @MainActor [weak self] in
                        self?.append(text, id: id)
                    }
                }
                try Task.checkCancellation()
                await appModel.setExecutable(destination)

                guard appModel.executableURL?.standardizedFileURL == destination.standardizedFileURL else {
                    let message = appModel.errorMessage ?? "asdf was installed but the app could not activate it."
                    append("\n✗ \(message)\n", id: id)
                    finish(id: id, status: .failed, destination: destination, error: message)
                    return
                }

                append("\n✓ asdf is ready to use in asdf GUI.\n", id: id)
                finish(
                    id: id,
                    status: .succeeded,
                    destination: destination,
                    error: nil,
                    version: appModel.asdfVersion
                )
            } catch is CancellationError {
                append("\nInstallation cancelled.\n", id: id)
                finish(id: id, status: .cancelled, destination: nil, error: nil)
            } catch {
                append("\n✗ \(error.localizedDescription)\n", id: id)
                finish(id: id, status: .failed, destination: nil, error: error.localizedDescription)
            }
        }
    }

    func cancel() {
        guard activeInstallation?.isRunning == true else { return }
        installationTask?.cancel()
    }

    func dismiss() {
        guard activeInstallation?.isRunning != true else { return }
        activeInstallation = nil
    }

    private func append(_ text: String, id: UUID) {
        guard var state = activeInstallation, state.id == id else { return }
        state.log = capped(state.log + text)
        activeInstallation = state
    }

    private func finish(
        id: UUID,
        status: AsdfInstallationStatus,
        destination: URL?,
        error: String?,
        version: String? = nil
    ) {
        guard var state = activeInstallation, state.id == id else { return }
        state.status = status
        state.destination = destination
        state.errorMessage = error
        state.version = version
        activeInstallation = state
        installationTask = nil
    }

    private func capped(_ value: String) -> String {
        guard value.count > logLimit else { return value }
        return "… older installer output truncated …\n" + String(value.suffix(logLimit - 80))
    }
}
