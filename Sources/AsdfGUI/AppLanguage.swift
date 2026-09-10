import Foundation

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    static let storageKey = "asdfGUI.appLanguage"

    var id: String { rawValue }

    static var defaultLanguage: AppLanguage {
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? ""
        return preferred.hasPrefix("zh") ? .simplifiedChinese : .english
    }

    static var current: AppLanguage {
        guard let raw = UserDefaults.standard.string(forKey: storageKey),
              let language = AppLanguage(rawValue: raw) else {
            return defaultLanguage
        }
        return language
    }

    var locale: Locale {
        Locale(identifier: rawValue)
    }

    var displayName: String {
        switch self {
        case .english: "English"
        case .simplifiedChinese: "简体中文"
        }
    }

    func localized(_ key: String) -> String {
        guard self == .simplifiedChinese else { return key }

        if let path = Bundle.main.path(forResource: "zh-Hans", ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle.localizedString(forKey: key, value: key, table: nil)
        }

        // SwiftPM command-line runs do not have a normal .app Resources directory.
        // Keep key navigation/settings/management text useful there as a fallback;
        // packaged apps use the complete Localizable.strings table copied into Resources.
        return Self.fallbackChinese[key] ?? key
    }

    func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: localized(key), locale: locale, arguments: arguments)
    }

    private static let fallbackChinese: [String: String] = [
        "Overview": "概览",
        "Projects": "项目",
        "Versions": "版本",
        "Plugins": "插件",
        "Settings": "设置",
        "Language": "语言",
        "Refresh": "刷新",
        "Add Project": "添加项目",
        "Manage .tool-versions": "管理 .tool-versions",
        "Configured tools": "已配置工具",
        "Add Tool": "添加工具",
        "Add tool configuration": "添加工具配置",
        "Edit tool configuration": "编辑工具配置",
        "Tool": "工具",
        "Fallback chain": "回退链",
        "Version catalog": "版本目录",
        "Add Version": "添加版本",
        "Save with asdf set": "使用 asdf set 保存",
        "Installed": "已安装",
        "Available": "可用",
        "Latest": "最新",
        "Install": "安装",
        "Uninstall": "卸载",
        "About asdf GUI": "关于 asdf GUI",
        "Check for Updates": "检查更新",
        "Getting Started": "开始使用",
        "Plugin Manager": "插件管理器",
        "Diagnostics": "诊断",
        "Shell Integration": "Shell 集成",
        "Project configuration unavailable": "项目配置不可用",
        "Project unavailable": "项目不可用",
        "The project is no longer in the managed-project list.": "该项目已不在管理列表中。",
        "The file will be created by asdf when you add the first tool.": "添加第一个工具时，asdf 会创建该文件。",
        "No tool entries": "暂无工具条目",
        "No .tool-versions yet": "尚无 .tool-versions",
        "Add a tool and choose one or more versions. asdf GUI will write the configuration through asdf set.": "添加工具并选择一个或多个版本，asdf GUI 会通过 asdf set 写入配置。",
        "All catalog versions are already in the fallback chain.": "版本目录中的版本都已加入回退链。",
        "No versions match this filter.": "没有版本匹配此筛选条件。"
    ]
}
