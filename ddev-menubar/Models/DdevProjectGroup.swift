import Foundation

nonisolated struct DdevProjectGroup: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var projectNames: [String]

    init(id: UUID = UUID(), name: String, projectNames: [String]) {
        self.id = id
        self.name = name
        self.projectNames = projectNames
    }
}

struct DdevGroupStatus: Sendable {
    let running: Int
    let stopped: Int
    let missing: Int

    var total: Int { running + stopped + missing }

    var summary: String {
        if total == 0 { return "No projects" }
        if missing > 0 {
            return "\(running)/\(total) running · \(missing) missing"
        }
        return "\(running)/\(total) running"
    }

    var allRunning: Bool { total > 0 && running == total - missing && stopped == 0 }
    var allStopped: Bool { running == 0 }
}
