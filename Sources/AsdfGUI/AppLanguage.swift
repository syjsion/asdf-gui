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
            let value = bundle.localizedString(forKey: key, value: key, table: nil)
            if value != key {
                return value
            }
        }

        return Self.fallbackChinese[key] ?? key
    }

    func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: localized(key), locale: locale, arguments: arguments)
    }

    private static let fallbackChinese: [String: String] = [
        "Overview": "概览",
        "Projects": "项目",
        "Versions": "版本",
        "Resolution": "解析",
        "Plugins": "插件",
        "Settings": "设置",
        "Language": "语言",
        "Refresh": "刷新",
        "Close": "关闭",
        "Apply": "应用",
        "Project": "项目",
        "Parent": "父级",
        "Scope": "范围",
        "Parent configuration": "父级配置",
        "No parent .tool-versions file exists above this project.": "该项目上层没有父级 .tool-versions 文件。",
        "Choose where the exact version should be written: this project, the closest parent configuration, or Home.": "选择精确版本写入位置：当前项目、最近的父级配置或 Home。",
        "The selected project is no longer available.": "所选项目已不可用。",
        "Not set locally": "未在项目中设置",
        "Add Project": "添加项目",
        "Search projects, paths, or tools": "搜索项目、路径或工具",
        "Sort": "排序",
        "Sort projects": "项目排序",
        "Name": "名称",
        "Path": "路径",
        "Tool count": "工具数量",
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
        "Missing": "缺失",
        "Available": "可用",
        "Latest": "最新",
        "Install": "安装",
        "Uninstall": "卸载",
        "Discover": "发现",
        "Discover Plugins": "发现插件",
        "Search plugins": "搜索插件",
        "No plugin catalog": "没有插件目录",
        "No matching plugins": "没有匹配插件",
        "About asdf GUI": "关于 asdf GUI",
        "Check for Updates": "检查更新",
        "Getting Started": "开始使用",
        "Plugin Manager": "插件管理器",
        "Diagnostics": "诊断",
        "Shell Integration": "Shell 集成",
        "Resolve Versions": "解析版本",
        "Effective versions": "生效版本",
        "Context": "上下文",
        "Directory": "目录",
        "All tools": "全部工具",
        "Source": "来源",
        "No resolution results": "暂无解析结果",
        "Shim & command explorer": "Shim 与命令解析器",
        "Command, e.g. node, npm, python, yarn": "命令，例如 node、npm、python、yarn",
        "Resolve Command": "解析命令",
        "Resolved executable": "实际可执行文件",
        "Shim providers": "Shim 提供者",
        "Environment Inspector": "环境检查器",
        "Inspect the environment that asdf gives a shimmed command, and compare this project with the Home context.": "检查 asdf 为 shim 命令提供的环境，并将当前项目与 Home 上下文进行比较。",
        "Shimmed command, e.g. node or python": "Shim 命令，例如 node 或 python",
        "Changed only": "仅显示差异",
        "Inspect Environment": "检查环境",
        "Variable": "变量",
        "Selected context": "当前上下文",
        "Run an inspection to see PATH, ASDF_* variables, and plugin-provided environment differences.": "运行检查以查看 PATH、ASDF_* 变量和插件提供的环境差异。",
        "Update Center": "更新中心",
        "Runtime Update Center": "运行时更新中心",
        "Compare every installed plugin with its latest stable runtime without changing project configuration.": "比较每个已安装插件的最新稳定运行时，不修改任何项目配置。",
        "Updates available": "可更新",
        "Status": "状态",
        "Action": "操作",
        "Check failed": "检查失败",
        "Up to date": "已是最新",
        "Not installed": "未安装",
        "Update available": "有更新",
        "Install Latest": "安装最新版本",
        "Installs the exact latest version. Existing versions and .tool-versions entries are not removed or rewritten.": "安装解析后的精确最新版本；不会移除旧版本，也不会改写 .tool-versions。",
        "Search runtimes": "搜索运行时",
        "None": "无",
        "Project Health": "项目健康检查",
        "Combine project requirements with asdf resolution to surface missing plugins, runtimes, and inherited configuration sources.": "结合项目需求和 asdf 实际解析结果，发现缺失插件、运行时以及继承的配置来源。",
        "Issues only": "仅显示问题",
        "No project health issues": "没有项目健康问题",
        "All managed projects currently satisfy their known asdf requirements.": "所有已管理项目当前都满足已知的 asdf 需求。",
        "Healthy": "健康",
        "Effective configuration sources": "生效配置来源",
        "Open the full health report to include effective asdf resolution sources for every project.": "打开完整健康报告以查看每个项目的实际 asdf 配置来源。",
        "Open Health Report": "打开健康报告",
        "No managed projects": "没有已管理项目",
        "No known project issues": "未发现项目问题",
        "Project cannot be read": "无法读取项目",
        "No project-local .tool-versions": "项目没有本地 .tool-versions",
        "The project may inherit versions from a parent directory or Home.": "项目可能从父级目录或 Home 继承版本。",
        ".tool-versions has no tool entries": ".tool-versions 没有工具条目",
        "Add at least one tool or remove the empty configuration file if it is not needed.": "请至少添加一个工具；如果不需要该配置文件，也可以将空文件删除。",
        "Effective version is not installed": "生效版本尚未安装",
        "asdf current reports at least one resolved runtime that is not installed.": "asdf current 显示至少有一个已解析运行时尚未安装。",
        "Effective version check failed": "生效版本检查失败",
        "asdf unavailable": "asdf 不可用",
        "Configure or install asdf before checking project health.": "请先配置或安装 asdf，再检查项目健康状态。",
        "Project configuration unavailable": "项目配置不可用",
        "Project unavailable": "项目不可用",
        "The project is no longer in the managed-project list.": "该项目已不在管理列表中。",
        "The file will be created by asdf when you add the first tool.": "添加第一个工具时，asdf 会创建该文件。",
        "No tool entries": "暂无工具条目",
        "No .tool-versions yet": "尚无 .tool-versions",
        "Add a tool and choose one or more versions. asdf GUI will write the configuration through asdf set.": "添加工具并选择一个或多个版本，asdf GUI 会通过 asdf set 写入配置。",
        "All catalog versions are already in the fallback chain.": "版本目录中的版本都已加入回退链。",
        "No versions match this filter.": "没有版本匹配此筛选条件。",
        "Explain which runtime version and executable asdf resolves in a specific project context.": "解释 asdf 在指定项目上下文中最终解析到的运行时版本和可执行文件。",
        "Choose a context and resolve all tools or one installed plugin.": "选择上下文后解析全部工具或单个已安装插件。",
        "Search the official asdf short-name plugin catalog and install without memorizing plugin names.": "搜索 asdf 官方短名称插件目录，无需记住插件名即可安装。",
        "Refresh to load asdf plugin list all.": "刷新以加载 asdf plugin list all。",
        "Try another plugin name or repository URL.": "尝试其他插件名或仓库 URL。",
        "Add, discover, update, and safely remove asdf plugins.": "发现、添加、更新并安全移除 asdf 插件。",
        "Discover the official catalog, or add a plugin by short name / Git URL.": "可以浏览官方目录，或通过短名称 / Git URL 添加插件。"
    ]
}
