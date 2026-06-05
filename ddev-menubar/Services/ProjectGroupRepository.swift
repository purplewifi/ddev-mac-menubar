import Foundation

struct ProjectGroupRepository: Sendable {
    private let defaultsKey = "ai.purple.ddev-menubar.project-groups"

    func load() -> [DdevProjectGroup] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else {
            return []
        }

        do {
            return try JSONDecoder().decode([DdevProjectGroup].self, from: data)
        } catch {
            return []
        }
    }

    func save(_ groups: [DdevProjectGroup]) {
        guard let data = try? JSONEncoder().encode(groups) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
