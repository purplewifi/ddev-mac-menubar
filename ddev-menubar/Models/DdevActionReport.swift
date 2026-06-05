import Foundation

struct DdevLogLine: Sendable {
    let level: String
    let message: String
}

struct DdevActionOutput: Sendable {
    let exitCode: Int32
    let lines: [DdevLogLine]
    let rawOutput: String

    static let empty = DdevActionOutput(exitCode: 0, lines: [], rawOutput: "")

    var errors: [String] {
        lines.filter { $0.level == "error" || $0.level == "fatal" }.map(\.message)
    }

    var warnings: [String] {
        lines.filter { $0.level == "warning" }.map(\.message)
    }
}

struct DdevServiceIssue: Identifiable, Sendable {
    let projectName: String
    let serviceName: String
    let status: String

    var id: String { "\(projectName)-\(serviceName)" }
}

struct DdevLogExcerpt: Identifiable, Sendable {
    let projectName: String
    let serviceName: String
    let text: String

    var id: String { "\(projectName)-\(serviceName)" }
}

struct DdevActionReport: Identifiable, Sendable {
    let id = UUID()
    let title: String
    let projectNames: [String]
    let messages: [String]
    let serviceIssues: [DdevServiceIssue]
    let logExcerpts: [DdevLogExcerpt]
    let hints: [String]
}
