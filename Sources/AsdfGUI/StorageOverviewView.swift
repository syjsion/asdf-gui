import AppKit
import SwiftUI

private struct PendingStorageUninstall {
    let entry: RuntimeStorageEntry
}

@MainActor
struct StorageOverviewView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.defaultLanguage.rawValue
    @State private var inventory = RuntimeStorageInventoryModel()
    @State private var searchText = ""
    @State private var scope: RuntimeStorageInventoryScope = .all
    @State private var sortOrder: RuntimeStorageInventorySortOrder = .largest
    @State private var scanGeneration = 0
    @State private var pendingUninstall: PendingStorageUninstall?
    @State private var isShowingUninstallConfirmation = false

    private var language: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? AppLanguage.defaultLanguage
    }

    private var referencedEntryIDs: Set<String> {
        Set(inventory.entries.compactMap { entry in
            appModel.projectsUsing(tool: entry.tool, version: entry.version).isEmpty ? nil : entry.id
        })
    }

    private var displayedEntries: [RuntimeStorageEntry] {
        RuntimeStorageInventoryPlanner.displayedEntries(
            inventory.entries,
            searchText: searchText,
            scope: scope,
            sortOrder: sortOrder,
            referencedEntryIDs: referencedEntryIDs
        )
    }

    private var noManagedReferenceCount: Int {
        inventory.entries.filter { !referencedEntryIDs.contains($0.id) }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(l("Storage Overview", "存储总览"))
                        .font(.largeTitle.bold())
                    Text(l(
                        "Measure installed runtimes across all plugins and review cleanup candidates without deleting folders directly.",
                        "按需统计所有插件的已安装运行时，并在不直接删除目录的前提下查看清理候选。"
                    ))
                    .foregroundStyle(.secondary)
                }
                Spacer()
                if inventory.isScanning {
                    ProgressView().controlSize(.small)
                }
                Menu {
                    Picker(l("Sort storage", "存储排序"), selection: $sortOrder) {
                        Text(l("Largest first", "占用最大优先")).tag(RuntimeStorageInventorySortOrder.largest)
                        Text(l("Tool", "工具")).tag(RuntimeStorageInventorySortOrder.tool)
                    }
                } label: {
                    Label(l("Sort", "排序"), systemImage: "arrow.up.arrow.down")
                }
                Button(l("Rescan", "重新扫描"), systemImage: "arrow.clockwise") {
                    scanGeneration += 1
                }
                .disabled(inventory.isScanning || appModel.hasActiveOperation)
                Button(l("Close", "关闭")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            HStack(spacing: 16) {
                metric(
                    title: l("Measured size", "已统计大小"),
                    value: byteCount(inventory.totalAllocatedBytes),
                    symbol: "internaldrive"
                )
                metric(
                    title: l("Measured versions", "已统计版本"),
                    value: "\(inventory.measuredVersionCount)",
                    symbol: "square.stack.3d.up"
                )
                metric(
                    title: l("No managed project references", "无已管理项目引用"),
                    value: "\(noManagedReferenceCount)",
                    symbol: "tray.and.arrow.up"
                )
                metric(
                    title: l("Plugin scan errors", "插件扫描错误"),
                    value: "\(inventory.toolErrors.count)",
                    symbol: inventory.toolErrors.isEmpty ? "checkmark.circle" : "exclamationmark.triangle"
                )
            }

            HStack {
                Picker(l("Storage scope", "存储范围"), selection: $scope) {
                    Text(l("All runtimes", "全部运行时")).tag(RuntimeStorageInventoryScope.all)
                    Text(l("No managed references", "无已管理项目引用")).tag(RuntimeStorageInventoryScope.noManagedReferences)
                }
                .pickerStyle(.segmented)
                .frame(width: 330)

                Spacer()

                if let scannedAt = inventory.scannedAt {
                    Text(l("Scanned", "扫描时间") + " ") + Text(scannedAt, style: .relative)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let task = appModel.activeVersionOperation {
                VersionOperationPanel(task: task)
            }

            if let error = inventory.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.callout)
                    .textSelection(.enabled)
            }

            if !inventory.toolErrors.isEmpty {
                DisclosureGroup(l("Plugin scan errors", "插件扫描错误")) {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(inventory.toolErrors.keys.sorted(), id: \.self) { tool in
                            Text("\(tool): \(inventory.toolErrors[tool] ?? "")")
                                .font(.caption)
                                .foregroundStyle(.red)
                                .textSelection(.enabled)
                        }
                    }
                }
            }

            if inventory.isScanning && inventory.entries.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(l("Measuring installed runtimes…", "正在统计已安装运行时…"))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if displayedEntries.isEmpty {
                ContentUnavailableView(
                    l("No matching runtimes", "没有匹配的运行时"),
                    systemImage: "internaldrive",
                    description: Text(l(
                        inventory.entries.isEmpty
                            ? "No installed runtimes were found across the current plugins."
                            : "Try another search or storage scope.",
                        inventory.entries.isEmpty
                            ? "当前插件中没有找到已安装运行时。"
                            : "请尝试其他搜索条件或存储范围。"
                    ))
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(displayedEntries) {
                    TableColumn(l("Tool", "工具")) { entry in
                        Text(entry.tool).fontWeight(.medium)
                    }
                    .width(min: 110, ideal: 140)

                    TableColumn(l("Version", "版本")) { entry in
                        Text(entry.version)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    .width(min: 120, ideal: 150)

                    TableColumn(l("Disk Usage", "磁盘占用")) { entry in
                        if let bytes = entry.allocatedBytes {
                            Text(byteCount(bytes)).monospacedDigit()
                        } else {
                            Text("—").foregroundStyle(.secondary)
                        }
                    }
                    .width(min: 100, ideal: 120)

                    TableColumn(l("Managed Projects", "已管理项目")) { entry in
                        let projects = appModel.projectsUsing(tool: entry.tool, version: entry.version)
                        if projects.isEmpty {
                            Text(l("None known", "无已知引用"))
                                .foregroundStyle(.secondary)
                        } else {
                            Text("\(projects.count)")
                                .help(projects.map { $0.name }.joined(separator: ", "))
                        }
                    }
                    .width(min: 110, ideal: 125)

                    TableColumn(l("Install Path", "安装路径")) { entry in
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

                    TableColumn(l("Action", "操作")) { entry in
                        HStack(spacing: 9) {
                            if let path = entry.path {
                                Button {
                                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                                } label: {
                                    Image(systemName: "finder")
                                }
                                .buttonStyle(.borderless)
                                .help(l("Reveal runtime in Finder", "在 Finder 中显示运行时"))
                                .accessibilityLabel(Text(l("Reveal runtime in Finder", "在 Finder 中显示运行时")))
                            }

                            Button(role: .destructive) {
                                pendingUninstall = PendingStorageUninstall(entry: entry)
                                isShowingUninstallConfirmation = true
                            } label: {
                                Label(l("Uninstall", "卸载"), systemImage: "trash")
                            }
                            .buttonStyle(.borderless)
                            .disabled(appModel.hasActiveOperation)
                        }
                    }
                    .width(min: 130, ideal: 150)
                }
            }

            Text(l(
                "“No managed references” is only a cleanup hint. Home configuration, unmanaged projects, or other workflows may still depend on a version. Cleanup always runs through asdf uninstall.",
                "“无已管理项目引用”仅表示清理提示；Home 配置、未纳入管理的项目或其他工作流仍可能依赖该版本。清理始终通过 asdf uninstall 执行。"
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(26)
        .frame(minWidth: 1040, minHeight: 680)
        .searchable(text: $searchText, prompt: l("Search tools, versions, or paths", "搜索工具、版本或路径"))
        .task(id: scanGeneration) {
            await inventory.scan(
                tools: appModel.plugins.map(\.name),
                executableURL: appModel.executableURL
            )
        }
        .onChange(of: appModel.activeVersionOperation?.status) { _, status in
            if status == .succeeded {
                scanGeneration += 1
            }
        }
        .alert(
            l("Uninstall version?", "卸载版本？"),
            isPresented: $isShowingUninstallConfirmation,
            presenting: pendingUninstall
        ) { request in
            Button(l("Uninstall", "卸载"), role: .destructive) {
                appModel.uninstallVersionFromBrowser(
                    tool: request.entry.tool,
                    version: request.entry.version
                )
                pendingUninstall = nil
            }
            Button(l("Cancel", "取消"), role: .cancel) {
                pendingUninstall = nil
            }
        } message: { request in
            Text(uninstallMessage(request.entry))
        }
    }

    @ViewBuilder
    private func metric(title: String, value: String, symbol: String) -> some View {
        GroupBox {
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
        .frame(maxWidth: .infinity)
    }

    private func l(_ english: String, _ chinese: String) -> String {
        language == .simplifiedChinese ? chinese : english
    }

    private func byteCount(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func uninstallMessage(_ entry: RuntimeStorageEntry) -> String {
        let projects = appModel.projectsUsing(tool: entry.tool, version: entry.version)
        let size = entry.allocatedBytes.map(byteCount) ?? l("unknown size", "未知大小")

        if language == .simplifiedChinese {
            if projects.isEmpty {
                return "将通过 asdf uninstall 移除 \(entry.tool) \(entry.version)（约 \(size)）。GUI 只知道没有已管理项目直接引用它；这不代表其他环境没有依赖。"
            }
            let names = projects.map { "• \($0.name)" }.joined(separator: "\n")
            return "该版本约占用 \(size)，并被 \(projects.count) 个已管理项目引用：\n\n\(names)\n\n卸载只会通过 asdf uninstall 执行；如果没有可用 fallback，这些项目可能会缺少运行时。"
        }

        if projects.isEmpty {
            return "This removes \(entry.tool) \(entry.version) (about \(size)) through asdf uninstall. The GUI only knows that no managed project references it directly; other environments may still depend on it."
        }
        let names = projects.map { "• \($0.name)" }.joined(separator: "\n")
        return "This version uses about \(size) and is referenced by \(projects.count) managed project\(projects.count == 1 ? "" : "s"):\n\n\(names)\n\nCleanup runs only through asdf uninstall. Those projects may be left without a runtime unless another configured fallback remains usable."
    }
}
