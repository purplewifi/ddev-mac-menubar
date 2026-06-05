import Foundation

struct LogSession: Hashable, Codable, Sendable {
    let projectName: String
    let approot: String
    let projectType: String?
}
