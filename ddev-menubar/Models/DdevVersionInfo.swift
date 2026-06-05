import Foundation

nonisolated struct DdevVersionInfo: Codable, Sendable {
    let ddevVersion: String
    let docker: String?
    let dockerPlatform: String?
    let dockerCompose: String?
    let router: String?
    let mutagen: String?

    enum CodingKeys: String, CodingKey {
        case ddevVersion = "DDEV version"
        case docker
        case dockerPlatform = "docker-platform"
        case dockerCompose = "docker-compose"
        case router
        case mutagen
    }
}

enum AppVersionInfo {
    static var marketingVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    static var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    static var fullVersion: String {
        "\(marketingVersion) (\(buildNumber))"
    }
}
