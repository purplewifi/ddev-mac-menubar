import Foundation

nonisolated struct DdevProject: Identifiable, Codable, Hashable, Sendable {
    let name: String
    let approot: String
    let shortroot: String
    let status: String
    let statusDesc: String
    let type: String
    let primaryURL: String?
    let httpURL: String?
    let httpsURL: String?
    let mailpitURL: String?
    let nodejsVersion: String?
    let docroot: String?
    let mutagenEnabled: Bool?
    let mutagenStatus: String?

    var id: String { name }

    var isRunning: Bool { status == "running" }

    enum CodingKeys: String, CodingKey {
        case name
        case approot
        case shortroot
        case status
        case statusDesc = "status_desc"
        case type
        case primaryURL = "primary_url"
        case httpURL = "httpurl"
        case httpsURL = "httpsurl"
        case mailpitURL = "mailpit_url"
        case nodejsVersion = "nodejs_version"
        case docroot
        case mutagenEnabled = "mutagen_enabled"
        case mutagenStatus = "mutagen_status"
    }
}

nonisolated struct DdevProjectDetail: Codable, Sendable {
    let name: String
    let approot: String
    let shortroot: String
    let status: String
    let statusDesc: String
    let type: String
    let phpVersion: String?
    let webserverType: String?
    let nodejsVersion: String?
    let docroot: String?
    let databaseType: String?
    let databaseVersion: String?
    let performanceMode: String?
    let xdebugEnabled: Bool?
    let primaryURL: String?
    let urls: [String]?
    let mailpitURL: String?
    let mailpitHTTPSURL: String?
    let services: [String: DdevServiceInfo]?
    let dbinfo: DdevDatabaseInfo?

    var includesDatabaseService: Bool {
        services?.keys.contains { $0.lowercased() == "db" } ?? false
    }

    enum CodingKeys: String, CodingKey {
        case name
        case approot
        case shortroot
        case status
        case statusDesc = "status_desc"
        case type
        case phpVersion = "php_version"
        case webserverType = "webserver_type"
        case nodejsVersion = "nodejs_version"
        case docroot
        case databaseType = "database_type"
        case databaseVersion = "database_version"
        case performanceMode = "performance_mode"
        case xdebugEnabled = "xdebug_enabled"
        case primaryURL = "primary_url"
        case urls
        case mailpitURL = "mailpit_url"
        case mailpitHTTPSURL = "mailpit_https_url"
        case services
        case dbinfo
    }
}

nonisolated struct DdevServiceInfo: Codable, Hashable, Sendable {
    let shortName: String?
    let status: String?
    let httpURL: String?
    let httpsURL: String?
    let hostHTTPURL: String?
    let hostHTTPSURL: String?
    let image: String?

    enum CodingKeys: String, CodingKey {
        case shortName = "short_name"
        case status
        case httpURL = "http_url"
        case httpsURL = "https_url"
        case hostHTTPURL = "host_http_url"
        case hostHTTPSURL = "host_https_url"
        case image
    }
}

nonisolated struct DdevDatabaseInfo: Codable, Hashable, Sendable {
    let databaseType: String?
    let databaseVersion: String?
    let publishedPort: Int?
    let username: String?
    let password: String?
    let dbname: String?

    enum CodingKeys: String, CodingKey {
        case databaseType = "database_type"
        case databaseVersion = "database_version"
        case publishedPort = "published_port"
        case username
        case password
        case dbname
    }
}

nonisolated struct DdevJSONResponse<T: Decodable & Sendable>: Decodable, Sendable {
    let raw: T
}
