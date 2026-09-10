import Foundation
import Observation
import SwiftUI

enum AsdfConfigSyncInterval: Hashable, Sendable {
    case everyTrigger
    case minutes(Int)
    case never

    var rawValue: String {
        switch self {
        case .everyTrigger: "0"
        case .minutes(let value): String(value)
        case .never: "never"
        }
    }
}

enum AsdfConfigConcurrency: Hashable, Sendable {
    case auto
    case cores(Int)

    var rawValue: String {
        switch self {
        case .auto: "auto"
        case .cores(let value): String(value)
        }
    }
}

struct AsdfConfigValues: Hashable, Sendable {
    var legacyVersionFile: Bool
    var useReleaseCandidates: Bool
    var alwaysKeepDownload: Bool
    var pluginRepositoryLastCheckDuration: AsdfConfigSyncInterval
    var disablePluginShortNameRepository: Bool
    var concurrency: AsdfConfigConcurrency

    static let defaults = AsdfConfigValues(
        legacyVersionFile: false,
        useReleaseCandidates: false,
        alwaysKeepDownload: false,
        pluginRepositoryLastCheckDuration: .minutes(60),
        disablePluginShortNameRepository: false,
        concurrency: .auto
    )
}

struct AsdfConfigSnapshot: Hashable, Sendable {
    let url: URL
    let values: AsdfConfigValues
    let originalContents: String?
    let usesEnvironmentOverride: Bool
    let concurrencyEnvironmentOverride: String?
}

enum AsdfConfigError: LocalizedError, Equatable {
    case configPathMustBeAbsolute(String)
    case duplicateKey(String)
    case invalidBoolean(key: String, value: String)
    case invalidSyncInterval(String)
    case invalidConcurrency(String)
    case configurationChanged
    case parentDirectoryMissing(String)

    var errorDescription: String? {
        switch self {
        case .configPathMustBeAbsolute(let value):
            return "ASDF_CONFIG_FILE must be an absolute path: \(value)"
        case .duplicateKey(let key):
            return "The asdf configuration contains more than one \(key) entry. Resolve the duplicate before using the structured editor."
        case .invalidBoolean(let key, let value):
            return "Invalid \(key) value: \(value). Expected yes or no."
        case .invalidSyncInterval(let value):
            return "Invalid plugin_repository_last_check_duration value: \(value). Use 0, never, or a number from 1 to 999999999."
        case .invalidConcurrency(let value):
            return "Invalid concurrency value: \(value). Use auto or a positive integer."
        case .configurationChanged:
            return "The asdf configuration file changed after it was loaded. Reload before saving so external edits are not overwritten."
        case .parentDirectoryMissing(let path):
            return "The configuration directory does not exist: \(path)"
        }
    }
}

struct AsdfConfigService {
    private static let managedKeys = [
        "legacy_version_file",
        "use_release_candidates",
        "always_keep_download",
        "plugin_repository_last_check_duration",
        "disable_plugin_short_name_repository",
        "concurrency"
    ]

    private let fileManager = FileManager.default

    func configURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) throws -> (url: URL, overridden: Bool) {
        if let configured = environment["ASDF_CONFIG_FILE"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !configured.isEmpty {
            guard configured.hasPrefix("/") else {
                throw AsdfConfigError.configPathMustBeAbsolute(configured)
            }
            return (URL(fileURLWithPath: configured).standardizedFileURL, true)
        }
        return (homeDirectory.appendingPathComponent(".asdfrc").standardizedFileURL, false)
    }

    func load(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) throws -> AsdfConfigSnapshot {
        let target = try configURL(environment: environment, homeDirectory: homeDirectory)
        let exists = fileManager.fileExists(atPath: target.url.path)
        let contents = exists ? try String(contentsOf: target.url, encoding: .utf8) : nil
        let values = try parse(contents ?? "")
        let override = environment["ASDF_CONCURRENCY"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return AsdfConfigSnapshot(
            url: target.url,
            values: values,
            originalContents: contents,
            usesEnvironmentOverride: target.overridden,
            concurrencyEnvironmentOverride: override?.isEmpty == false ? override : nil
        )
    }

    func parse(_ contents: String) throws -> AsdfConfigValues {
        var values = AsdfConfigValues.defaults
        var seen = Set<String>()

        for rawLine in contents.components(separatedBy: "\n") {
            guard let pair = managedPair(in: rawLine) else { continue }
            guard seen.insert(pair.key).inserted else {
                throw AsdfConfigError.duplicateKey(pair.key)
            }

            switch pair.key {
            case "legacy_version_file":
                values.legacyVersionFile = try parseBoolean(pair.value, key: pair.key)
            case "use_release_candidates":
                values.useReleaseCandidates = try parseBoolean(pair.value, key: pair.key)
            case "always_keep_download":
                values.alwaysKeepDownload = try parseBoolean(pair.value, key: pair.key)
            case "plugin_repository_last_check_duration":
                values.pluginRepositoryLastCheckDuration = try parseSyncInterval(pair.value)
            case "disable_plugin_short_name_repository":
                values.disablePluginShortNameRepository = try parseBoolean(pair.value, key: pair.key)
            case "concurrency":
                values.concurrency = try parseConcurrency(pair.value)
            default:
                break
            }
        }
        return values
    }

    func updatedContents(original: String, values: AsdfConfigValues) throws -> String {
        _ = try parse(original) // validates duplicates and existing managed values before rewriting.
        try validate(values)

        var lines = original.components(separatedBy: "\n")
        var replaced = Set<String>()

        for index in lines.indices {
            guard let pair = managedPair(in: lines[index]) else { continue }
            lines[index] = replacingManagedLine(lines[index], key: pair.key, value: rawValue(for: pair.key, values: values))
            replaced.insert(pair.key)
        }

        let missing = Self.managedKeys.filter { !replaced.contains($0) }
        if !missing.isEmpty {
            if !lines.isEmpty && lines.last == "" {
                lines.removeLast()
            }
            if !lines.isEmpty && !lines.last!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.append("")
            }
            lines.append("# Managed asdf settings (edited by asdf GUI)")
            for key in missing {
                lines.append("\(key) = \(rawValue(for: key, values: values))")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    func save(snapshot: AsdfConfigSnapshot, values: AsdfConfigValues) throws -> AsdfConfigSnapshot {
        try validate(values)

        let exists = fileManager.fileExists(atPath: snapshot.url.path)
        let currentContents = exists ? try String(contentsOf: snapshot.url, encoding: .utf8) : nil
        guard currentContents == snapshot.originalContents else {
            throw AsdfConfigError.configurationChanged
        }

        let parent = snapshot.url.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: parent.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw AsdfConfigError.parentDirectoryMissing(parent.path)
        }

        let attributes = exists ? try? fileManager.attributesOfItem(atPath: snapshot.url.path) : nil
        let updated = try updatedContents(original: currentContents ?? "", values: values)
        try updated.write(to: snapshot.url, atomically: true, encoding: .utf8)
        if let permissions = attributes?[.posixPermissions] {
            try? fileManager.setAttributes([.posixPermissions: permissions], ofItemAtPath: snapshot.url.path)
        }

        return AsdfConfigSnapshot(
            url: snapshot.url,
            values: values,
            originalContents: updated,
            usesEnvironmentOverride: snapshot.usesEnvironmentOverride,
            concurrencyEnvironmentOverride: snapshot.concurrencyEnvironmentOverride
        )
    }

    private func managedPair(in line: String) -> (key: String, value: String)? {
        let noCarriageReturn = line.hasSuffix("\r") ? String(line.dropLast()) : line
        let trimmed = noCarriageReturn.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), let equal = trimmed.firstIndex(of: "=") else { return nil }
        let key = trimmed[..<equal].trimmingCharacters(in: .whitespaces)
        guard Self.managedKeys.contains(key) else { return nil }
        var value = trimmed[trimmed.index(after: equal)...].trimmingCharacters(in: .whitespaces)
        if let hash = value.firstIndex(of: "#") {
            value = value[..<hash].trimmingCharacters(in: .whitespaces)
        }
        return (key, value)
    }

    private func replacingManagedLine(_ line: String, key: String, value: String) -> String {
        let carriageReturn = line.hasSuffix("\r") ? "\r" : ""
        let base = carriageReturn.isEmpty ? line : String(line.dropLast())
        let leading = String(base.prefix { $0 == " " || $0 == "\t" })
        var comment = ""
        if let equal = base.firstIndex(of: "=") {
            let rhs = base[base.index(after: equal)...]
            if let hash = rhs.firstIndex(of: "#") {
                comment = " " + rhs[hash...].trimmingCharacters(in: .whitespaces)
            }
        }
        return "\(leading)\(key) = \(value)\(comment)\(carriageReturn)"
    }

    private func parseBoolean(_ value: String, key: String) throws -> Bool {
        switch value.lowercased() {
        case "yes": true
        case "no": false
        default: throw AsdfConfigError.invalidBoolean(key: key, value: value)
        }
    }

    private func parseSyncInterval(_ value: String) throws -> AsdfConfigSyncInterval {
        if value == "never" { return .never }
        guard let number = Int(value) else { throw AsdfConfigError.invalidSyncInterval(value) }
        if number == 0 { return .everyTrigger }
        guard (1...999_999_999).contains(number) else { throw AsdfConfigError.invalidSyncInterval(value) }
        return .minutes(number)
    }

    private func parseConcurrency(_ value: String) throws -> AsdfConfigConcurrency {
        if value == "auto" { return .auto }
        guard let number = Int(value), number > 0 else { throw AsdfConfigError.invalidConcurrency(value) }
        return .cores(number)
    }

    private func validate(_ values: AsdfConfigValues) throws {
        _ = try parseSyncInterval(values.pluginRepositoryLastCheckDuration.rawValue)
        _ = try parseConcurrency(values.concurrency.rawValue)
    }

    private func rawValue(for key: String, values: AsdfConfigValues) -> String {
        switch key {
        case "legacy_version_file": values.legacyVersionFile ? "yes" : "no"
        case "use_release_candidates": values.useReleaseCandidates ? "yes" : "no"
        case "always_keep_download": values.alwaysKeepDownload ? "yes" : "no"
        case "plugin_repository_last_check_duration": values.pluginRepositoryLastCheckDuration.rawValue
        case "disable_plugin_short_name_repository": values.disablePluginShortNameRepository ? "yes" : "no"
        case "concurrency": values.concurrency.rawValue
        default: ""
        }
    }
}

@MainActor
@Observable
final class AsdfConfigurationModel {
    var snapshot: AsdfConfigSnapshot?
    var values = AsdfConfigValues.defaults
    var isLoading = false
    var isSaving = false
    var errorMessage: String?
    var successMessage: String?

    private let service = AsdfConfigService()

    var hasChanges: Bool {
        guard let snapshot else { return false }
        return values != snapshot.values
    }

    func load() {
        isLoading = true
        errorMessage = nil
        successMessage = nil
        defer { isLoading = false }
        do {
            let loaded = try service.load()
            snapshot = loaded
            values = loaded.values
        } catch {
            snapshot = nil
            values = .defaults
            errorMessage = error.localizedDescription
        }
    }

    func restoreDefaults() {
        values = .defaults
        successMessage = nil
    }

    func save(appModel: AppModel) {
        guard let snapshot else { return }
        guard appModel.beginExternalWriteOperation() else {
            errorMessage = "Another asdf write operation is currently running."
            return
        }
        isSaving = true
        errorMessage = nil
        successMessage = nil
        defer {
            isSaving = false
            appModel.endExternalWriteOperation()
        }

        do {
            self.snapshot = try service.save(snapshot: snapshot, values: values)
            successMessage = "asdf configuration saved."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private enum ConfigSyncMode: String, CaseIterable, Identifiable {
    case minutes
    case everyTrigger
    case never
    var id: String { rawValue }
}

private enum ConfigConcurrencyMode: String, CaseIterable, Identifiable {
    case auto
    case custom
    var id: String { rawValue }
}

@MainActor
struct AsdfConfigurationView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.defaultLanguage.rawValue
    @State private var model = AsdfConfigurationModel()
    @State private var syncMode: ConfigSyncMode = .minutes
    @State private var syncMinutes = 60
    @State private var concurrencyMode: ConfigConcurrencyMode = .auto
    @State private var concurrencyCores = 4

    private var language: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? .defaultLanguage
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(language.localized("asdf Configuration"))
                        .font(.largeTitle.bold())
                    Text(language.localized("Manage machine-specific .asdfrc settings without editing the file as raw text."))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if model.isLoading || model.isSaving { ProgressView().controlSize(.small) }
                Button(language.localized("Reload"), systemImage: "arrow.clockwise") {
                    model.load(); syncControlsFromValues()
                }
                .disabled(model.isSaving)
                Button(language.localized("Close")) { dismiss() }
            }

            if let snapshot = model.snapshot {
                GroupBox(language.localized("Configuration file")) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(snapshot.url.path).font(.callout.monospaced()).textSelection(.enabled)
                        if snapshot.usesEnvironmentOverride {
                            Label(language.localized("Path comes from ASDF_CONFIG_FILE."), systemImage: "terminal")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if let override = snapshot.concurrencyEnvironmentOverride {
                            Label(language.format("ASDF_CONCURRENCY is set to %@ and overrides the value below.", override), systemImage: "exclamationmark.triangle")
                                .font(.caption).foregroundStyle(Color.orange)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Form {
                Section(language.localized("Version resolution")) {
                    Toggle(language.localized("Use legacy version files when supported"), isOn: boolBinding(\.legacyVersionFile))
                    Toggle(language.localized("Allow release candidates"), isOn: boolBinding(\.useReleaseCandidates))
                }

                Section(language.localized("Downloads")) {
                    Toggle(language.localized("Keep downloaded source or binaries after install"), isOn: boolBinding(\.alwaysKeepDownload))
                }

                Section(language.localized("Plugin short-name repository")) {
                    Toggle(language.localized("Disable short-name repository"), isOn: boolBinding(\.disablePluginShortNameRepository))
                    Picker(language.localized("Repository sync"), selection: $syncMode) {
                        Text(language.localized("Every trigger")).tag(ConfigSyncMode.everyTrigger)
                        Text(language.localized("Every N minutes")).tag(ConfigSyncMode.minutes)
                        Text(language.localized("Never")).tag(ConfigSyncMode.never)
                    }
                    .onChange(of: syncMode) { _, _ in updateSyncValue() }

                    if syncMode == .minutes {
                        HStack {
                            Text(language.localized("Minutes"))
                            TextField("60", value: $syncMinutes, format: .number)
                                .frame(width: 90)
                                .onChange(of: syncMinutes) { _, _ in updateSyncValue() }
                        }
                    }
                    if model.values.disablePluginShortNameRepository {
                        Text(language.localized("Plugin discovery by short name may be unavailable while this repository is disabled. Explicit Git URL installs still work."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section(language.localized("Build concurrency")) {
                    Picker(language.localized("Concurrency"), selection: $concurrencyMode) {
                        Text("auto").tag(ConfigConcurrencyMode.auto)
                        Text(language.localized("Custom cores")).tag(ConfigConcurrencyMode.custom)
                    }
                    .onChange(of: concurrencyMode) { _, _ in updateConcurrencyValue() }
                    if concurrencyMode == .custom {
                        HStack {
                            Text(language.localized("Cores"))
                            TextField("4", value: $concurrencyCores, format: .number)
                                .frame(width: 90)
                                .onChange(of: concurrencyCores) { _, _ in updateConcurrencyValue() }
                        }
                    }
                }
            }
            .formStyle(.grouped)

            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red).textSelection(.enabled)
            }
            if let success = model.successMessage {
                Label(language.localized(success), systemImage: "checkmark.circle.fill").foregroundStyle(.secondary)
            }

            HStack {
                Button(language.localized("Restore Defaults")) {
                    model.restoreDefaults(); syncControlsFromValues()
                }
                Spacer()
                Text(changeSummary)
                    .font(.caption).foregroundStyle(.secondary)
                Button(language.localized("Save Configuration")) {
                    updateSyncValue(); updateConcurrencyValue(); model.save(appModel: appModel)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(model.snapshot == nil || !model.hasChanges || model.isSaving || appModel.hasActiveOperation)
            }
        }
        .padding(24)
        .frame(minWidth: 720, minHeight: 650)
        .task {
            if model.snapshot == nil {
                model.load(); syncControlsFromValues()
            }
        }
    }

    private func boolBinding(_ keyPath: WritableKeyPath<AsdfConfigValues, Bool>) -> Binding<Bool> {
        Binding(
            get: { model.values[keyPath: keyPath] },
            set: { model.values[keyPath: keyPath] = $0 }
        )
    }

    private var changeSummary: String {
        guard let original = model.snapshot?.values else { return "" }
        var count = 0
        if original.legacyVersionFile != model.values.legacyVersionFile { count += 1 }
        if original.useReleaseCandidates != model.values.useReleaseCandidates { count += 1 }
        if original.alwaysKeepDownload != model.values.alwaysKeepDownload { count += 1 }
        if original.pluginRepositoryLastCheckDuration != model.values.pluginRepositoryLastCheckDuration { count += 1 }
        if original.disablePluginShortNameRepository != model.values.disablePluginShortNameRepository { count += 1 }
        if original.concurrency != model.values.concurrency { count += 1 }
        return language == .simplifiedChinese ? "\(count) 项更改" : "\(count) change\(count == 1 ? "" : "s")"
    }

    private func syncControlsFromValues() {
        switch model.values.pluginRepositoryLastCheckDuration {
        case .everyTrigger:
            syncMode = .everyTrigger
        case .never:
            syncMode = .never
        case .minutes(let value):
            syncMode = .minutes
            syncMinutes = value
        }
        switch model.values.concurrency {
        case .auto:
            concurrencyMode = .auto
        case .cores(let value):
            concurrencyMode = .custom
            concurrencyCores = value
        }
    }

    private func updateSyncValue() {
        switch syncMode {
        case .everyTrigger:
            model.values.pluginRepositoryLastCheckDuration = .everyTrigger
        case .never:
            model.values.pluginRepositoryLastCheckDuration = .never
        case .minutes:
            model.values.pluginRepositoryLastCheckDuration = .minutes(max(1, min(999_999_999, syncMinutes)))
        }
    }

    private func updateConcurrencyValue() {
        switch concurrencyMode {
        case .auto:
            model.values.concurrency = .auto
        case .custom:
            model.values.concurrency = .cores(max(1, concurrencyCores))
        }
    }
}