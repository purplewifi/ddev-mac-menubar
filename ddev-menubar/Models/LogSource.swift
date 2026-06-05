import Foundation

enum LogSource: Hashable, Sendable {
    case container(service: String)
    case file(path: String)
}

struct LogTab: Identifiable, Hashable, Sendable {
    let id: String
    let label: String
    let source: LogSource
    let isCustom: Bool

    init(id: String, label: String, source: LogSource, isCustom: Bool = false) {
        self.id = id
        self.label = label
        self.source = source
        self.isCustom = isCustom
    }
}

enum LogSourceCatalog {
    static func tabs(for projectType: String?) -> [LogTab] {
        var tabs = [
            LogTab(id: "web", label: "Web", source: .container(service: "web")),
            LogTab(id: "db", label: "DB", source: .container(service: "db")),
        ]

        tabs.append(contentsOf: fileTabs(for: projectType))
        tabs.append(
            LogTab(id: "custom", label: "Custom", source: .file(path: ""), isCustom: true)
        )
        return tabs
    }

    private static func fileTabs(for projectType: String?) -> [LogTab] {
        guard let projectType else { return [] }

        switch projectType.lowercased() {
        case "laravel":
            return [
                fileTab(id: "laravel", label: "Laravel", path: "storage/logs/laravel.log"),
            ]
        case "drupal", "drupal6", "drupal7", "drupal8", "drupal9", "drupal10", "drupal11":
            return [
                fileTab(id: "drupal", label: "Drupal", path: "sites/default/files/debug.log"),
            ]
        case "wordpress":
            return [
                fileTab(id: "wordpress", label: "WordPress", path: "wp-content/debug.log"),
            ]
        case "typo3":
            return [
                fileTab(id: "typo3", label: "TYPO3", path: "var/log/typo3_site.log"),
            ]
        case "magento", "magento2":
            return [
                fileTab(id: "magento", label: "Magento", path: "var/log/system.log"),
            ]
        case "symfony":
            return [
                fileTab(id: "symfony", label: "Symfony", path: "var/log/dev.log"),
            ]
        default:
            return []
        }
    }

    private static func fileTab(id: String, label: String, path: String) -> LogTab {
        LogTab(id: id, label: label, source: .file(path: path))
    }
}
