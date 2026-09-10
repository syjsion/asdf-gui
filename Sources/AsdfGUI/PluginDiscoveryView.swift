import SwiftUI

@MainActor
struct PluginDiscoveryView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.defaultLanguage.rawValue
    @State private var discovery = PluginDiscoveryModel()
    @State private var searchText = ""

    let operationModel: PluginManagementModel

    private var language: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? AppLanguage.defaultLanguage
    }

    private var filteredCatalog: [AsdfPluginCatalogEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return discovery.catalog }
        return discovery.catalog.filter { entry in
            entry.name.localizedCaseInsensitiveContains(query)
                || (entry.url?.localizedCaseInsensitiveContains(query) == true)
        }
    }

    private var installedNames: Set<String> {
        Set(appModel.plugins.map(\.name))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(language.localized("Discover Plugins"))
                        .font(.largeTitle.bold())
                    Text(language.localized("Search the official asdf short-name plugin catalog and install without memorizing plugin names."))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if discovery.isLoading {
                    ProgressView().controlSize(.small)
                }
                Button(language.localized("Refresh"), systemImage: "arrow.clockwise") {
                    Task { await discovery.load(appModel: appModel) }
                }
                .disabled(discovery.isLoading)
                Button(language.localized("Close")) { dismiss() }
            }

            TextField(language.localized("Search plugins"), text: $searchText)
                .textFieldStyle(.roundedBorder)

            if let error = discovery.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            if filteredCatalog.isEmpty && !discovery.isLoading {
                ContentUnavailableView(
                    language.localized(discovery.catalog.isEmpty ? "No plugin catalog" : "No matching plugins"),
                    systemImage: "shippingbox.and.arrow.backward",
                    description: Text(language.localized(discovery.catalog.isEmpty
                        ? "Refresh to load asdf plugin list all."
                        : "Try another plugin name or repository URL."))
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(filteredCatalog) {
                    TableColumn(language.localized("Plugin")) { entry in
                        HStack(spacing: 8) {
                            Text(entry.name).fontWeight(.medium)
                            if installedNames.contains(entry.name) {
                                Label(language.localized("Installed"), systemImage: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    TableColumn(language.localized("Repository")) { entry in
                        Text(entry.url ?? "—")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    TableColumn(language.localized("Action")) { entry in
                        if installedNames.contains(entry.name) {
                            Text(language.localized("Installed")).foregroundStyle(.secondary)
                        } else {
                            Button(language.localized("Install")) {
                                operationModel.addPlugin(
                                    name: entry.name,
                                    gitURL: entry.url,
                                    appModel: appModel
                                )
                                dismiss()
                            }
                            .buttonStyle(.borderless)
                            .disabled(operationModel.isBusy || appModel.hasActiveOperation)
                        }
                    }
                }
            }
        }
        .padding(24)
        .frame(minWidth: 760, minHeight: 560)
        .task {
            if discovery.catalog.isEmpty {
                await discovery.load(appModel: appModel)
            }
        }
    }
}
