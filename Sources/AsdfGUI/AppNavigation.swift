import Foundation
import Observation

enum AppSection: String, CaseIterable, Identifiable, Sendable {
    case overview
    case projects
    case versions
    case resolution
    case plugins
    case tools

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .overview: "Overview"
        case .projects: "Projects"
        case .versions: "Versions"
        case .resolution: "Resolution"
        case .plugins: "Plugins"
        case .tools: "Settings"
        }
    }

    var icon: String {
        switch self {
        case .overview: "gauge.with.dots.needle.67percent"
        case .projects: "folder"
        case .versions: "square.stack.3d.up"
        case .resolution: "arrow.triangle.branch"
        case .plugins: "shippingbox"
        case .tools: "gearshape.2"
        }
    }

    var shortcutNumber: String {
        switch self {
        case .overview: "1"
        case .projects: "2"
        case .versions: "3"
        case .resolution: "4"
        case .plugins: "5"
        case .tools: "6"
        }
    }
}

@MainActor
@Observable
final class AppNavigationModel {
    var section: AppSection = .overview
    var projectSearchRequest: String?
    var versionToolRequest: String?

    func show(_ section: AppSection) {
        self.section = section
    }

    func showProject(_ project: ManagedProject) {
        projectSearchRequest = project.path
        section = .projects
    }

    func showVersions(tool: String) {
        versionToolRequest = tool
        section = .versions
    }

    func consumeProjectSearchRequest() -> String? {
        defer { projectSearchRequest = nil }
        return projectSearchRequest
    }

    func consumeVersionToolRequest() -> String? {
        defer { versionToolRequest = nil }
        return versionToolRequest
    }
}
