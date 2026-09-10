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
        // Keep key navigation/settings text useful there as a fallback; packaged apps
        // use the complete Localizable.strings table copied into Contents/Resources.
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
        "Shell Integration": "Shell 集成"
    ]
}
