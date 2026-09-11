import AppKit
import SwiftUI

private enum RuntimeStorageSortOrder: String, CaseIterable, Identifiable {
    case largest
    case version

    var id: String { rawValue }
}

@MainActor
struct RuntimeStorageView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.defaultLanguage.rawValue
    @State private var storageModel = RuntimeStorageModel()
    @State private var sortOrder: RuntimeStorageSortOrder = .largest
    @State private var pendingUninstall: RuntimeStorageEntry?
    @State private var isShowingUninstallConfirmation = false

    let tool: String

    private var language: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? AppLanguage.defaultLanguage
    }

    private var installedVersions: [String] {
        if appModel.versionBrowserTool == tool {
            return appModel.versionBrowserInstalledVersions
        }
        return appModel.installedVersionsByTool[tool] ?? []
    }

    private var sortedEntries: [RuntimeStorageEntry] {
        storageModel.entries.sorted { lhs, rhs in
            switch sortOrder {
            case .largest:
                let left = lhs.allocatedBytes ?? -1
                let right = rhs.allocatedBytes ?? -1
                if left == right {
                    return lhs.version.localizedStandardCompare(rhs.version) == .orderedDescending
                }
                return left > right
            case .version:
                return lhs.version.localizedStandardCompare(rhs.version) == .orderedDescending
            }
        }
    }

    private var failedEntryCount: Int {
        storageModel.entries.filter { $0.errorMessage != nil }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(language.localized("Runtime Storage"))
                        .font(.largeTitle.bold())
                    Text(tool)
                        .font(.title3.weight(.medium))
                    Text(language.localized("Measure installed runtime folders and clean up only through asdf uninstall."))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if storageModel.isScanning {
                    ProgressView().controlSize(.small)
                }
                Menu {
                    Picker(language.localized("Sort storage"), selection: $sortOrder) {
                        Text(language.localized("Largest first")).tag(RuntimeStorageSortOrder.largest)
                        Text(language.localized("Version")).tag(RuntimeStorageSortOrder.version)
                    }
                } label: {
                    Label(language.localized("Sort"), systemImage: "arrow.up.arrow.down")
                }
                Button(language.localized("Rescan"), systemImage: "arrow.clockwise") {
                    Task { await scan() }
                }
                .disabled(storageModel.isScanning || appModel.hasActiveOperation)
                Button(language.localized("Close")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            GroupBox(language.localized("Storage Summary")) {
                HStack(spacing: 28) {
                    summaryMetric(
                        title: language.localized("Measured size"),
                        value: byteCount(storageModel.totalAllocatedBytes),
                        symbol: "internaldrive"
                    )
                    summaryMetric(
                        title: language.localized("Installed versions"),
                        value: "\(installedVersions.count)",
                        symbol: "square.stack.3d.up"
                    )
                    summaryMetric(
                        title: language.localized("Measurement errors"),
                        value: "\(failedEntryCount)",
                        symbol: failedEntryCount == 0 ? "checkmark.circle" : "exclamationmark.triangle"
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let task = appModel.activeVersionOperation, task.tool == tool {
                VersionOperationPanel(task: task)
            }

            if let error = storageModel.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.callout)
                    .textSelection(.enabled)
            }

            if installedVersions.isEmpty && !storageModel.isScanning {
                ContentUnavailableView(
                    language.localized("No installed versions"),
                    systemImage: "internaldrive.slash",
                    description: Text(language.localized("This plugin has no installed runtime versions to measure."))
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if storageModel.isScanning && storageModel.entries.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(language.localized("Measuring runtime folders…"))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(sortedEntries) {
                    TableColumn(language.localized("Version")) { entry in
                        Text(entry.version)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    .width(min: 120, ideal: 150)

                    TableColumn(language.localized("Disk Usage")) { entry in
                        if let bytes = entry.allocatedBytes {
                            Text(byteCount(bytes))
                                .monospacedDigit()
                        } else {
                            Text("—")
                                .foregroundStyle(.secondary)
                                .help(entry.errorMessage ?? "")
                        }
                    }
                    .width(min: 100, ideal: 120)

                    TableColumn(language.localized("Projects")) { entry in
                        let count = appModel.projectsUsing(tool: tool, version: entry.version).count
                        Text(count == 0 ? "—" : "\(count)")
                            .foregroundStyle(count == 0 ? .secondary : .primary)
                            .accessibilityLabel(Text(projectReferenceAccessibility(count)))
                    }
                    .width(min: 70, ideal: 85)

                    TableColumn(language.localized("Install Path")) { entry in
                        if let path = entry.path {
                            Text(path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .textSelection(.enabled)
                                .help(path)
                        } else {
                            Text(entry.errorMessage ?? "—")
                                .font(.caption)
                                .foregroundStyle(.red)
                                .lineLimit(1)
                        }
                    }

                    TableColumn(language.localized("Action")) { entry in
                        HStack(spacing: 10) {
                            if let path = entry.path {
                                Button {
                                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                                } label: {
                                    Image(systemName: "finder")
                                }
                                .buttonStyle(.borderless)
                                .help(language.localized("Reveal runtime in Finder"))
                                .accessibilityLabel(Text(language.localized("Reveal runtime in Finder")))
                            }

                            Button(role: .destructive) {
                                pendingUninstall = entry
                                isShowingUninstallConfirmation = true
                            } label: {
                                Label(language.localized("Uninstall"), systemImage: "trash")
                            }
                            .buttonStyle(.borderless)
                            .disabled(appModel.hasActiveOperation)
                            .accessibilityLabel(Text(uninstallAccessibilityLabel(entry)))
                        }
                    }
                    .width(min: 130, ideal: 150)
                }
            }

            Text(language.localized("Sizes are measured on demand from paths reported by asdf where. asdf GUI never deletes runtime folders directly."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(26)
        .frame(minWidth: 900, minHeight: 610)
        .task(id: tool) {
            await scan()
        }
        .onChange(of: installedVersions) { oldVersions, newVersions in
            guard oldVersions != newVersions else { return }
            Task { await scan() }
        }
        .alert(
            language.localized("Uninstall version?"),
            isPresented: $isShowingUninstallConfirmation,
            presenting: pendingUninstall
        ) { entry in
            Button(language.localized("Uninstall"), role: .destructive) {
                appModel.uninstallVersionFromBrowser(tool: entry.tool, version: entry.version)
                pendingUninstall = nil
            }
            Button(language.localized("Cancel"), role: .cancel) {
                pendingUninstall = nil
            }
        } message: { entry in
            Text(uninstallMessage(entry))
        }
    }

    @ViewBuilder
    private func summaryMetric(title: String, value: String, symbol: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(.title3.bold()).monospacedDigit()
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func scan() async {
        await storageModel.scan(
            tool: tool,
            versions: installedVersions,
            executableURL: appModel.executableURL
        )
    }

    private func byteCount(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func projectReferenceAccessibility(_ count: Int) -> String {
        if language == .simplifiedChinese {
            return count == 0 ? "没有已管理项目引用" : "\(count) 个已管理项目引用"
        }
        return count == 0 ? "No managed projects reference this version" : "Referenced by \(count) managed project\(count == 1 ? "" : "s")"
    }

    private func uninstallAccessibilityLabel(_ entry: RuntimeStorageEntry) -> String {
        if language == .simplifiedChinese {
            return "卸载 \(entry.tool) \(entry.version)"
        }
        return "Uninstall \(entry.tool) \(entry.version)"
    }

    private func uninstallMessage(_ entry: RuntimeStorageEntry) -> String {
        let projects = appModel.projectsUsing(tool: entry.tool, version: entry.version)
        let size = entry.allocatedBytes.map(byteCount) ?? language.localized("Unknown size")
        if language == .simplifiedChinese {
            guard !projects.isEmpty else {
                return "将通过 asdf uninstall 移除 \(entry.tool) \(entry.version)（约 \(size)）。asdf GUI 不会直接删除运行时目录。"
            }
            let names = projects.map { "• \($0.name)" }.joined(separator: "\n")
            return "该版本约占用 \(size)，并被 \(projects.count) 个已管理项目引用：\n\n\(names)\n\n卸载仍只会通过 asdf uninstall 执行；如果没有可用 fallback，这些项目可能会缺少运行时。"
        }

        guard !projects.isEmpty else {
            return "This removes \(entry.tool) \(entry.version) (about \(size)) through asdf uninstall. asdf GUI will not delete the runtime directory directly."
        }
        let names = projects.map { "• \($0.name)" }.joined(separator: "\n")
        return "This version uses about \(size) and is referenced by \(projects.count) managed project\(projects.count == 1 ? "" : "s"):\n\n\(names)\n\nCleanup still runs only through asdf uninstall. Those projects may be left without a runtime unless another configured fallback remains usable."
    }
}
