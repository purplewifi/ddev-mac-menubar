import AppKit
import Foundation
import Observation

enum MainTab: String, CaseIterable, Identifiable {
    case groups = "Groups"
    case projects = "Projects"

    var id: String { rawValue }
}

@MainActor
@Observable
final class DdevProjectStore {
    private(set) var projects: [DdevProject] = []
    private(set) var groups: [DdevProjectGroup] = []
    private(set) var selectedProjectName: String?
    private(set) var selectedDetail: DdevProjectDetail?
    private(set) var selectedGroupID: UUID?
    private(set) var isEditingGroup = false
    private(set) var editingGroup: DdevProjectGroup?
    private(set) var isLoading = false
    private(set) var isPerformingAction = false
    private(set) var statusMessage: String?
    private(set) var lastRefreshed: Date?
    private(set) var ddevAvailable: Bool

    var mainTab: MainTab = .projects
    var searchText = "" {
        didSet { /* derived in filteredProjects */ }
    }
    var groupSearchText = ""

    private let cli: DdevCLI
    private let groupRepository: ProjectGroupRepository
    private let terminalLauncher: TerminalLauncher
    private var refreshTask: Task<Void, Never>?
    private var detailTask: Task<Void, Never>?

    init(
        cli: DdevCLI = .shared,
        groupRepository: ProjectGroupRepository = ProjectGroupRepository(),
        terminalLauncher: TerminalLauncher = TerminalLauncher()
    ) {
        self.cli = cli
        self.groupRepository = groupRepository
        self.terminalLauncher = terminalLauncher
        self.ddevAvailable = cli.isAvailable
        self.groups = groupRepository.load()
    }

    var filteredProjects: [DdevProject] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return projects }

        return projects.filter { project in
            project.name.localizedCaseInsensitiveContains(query)
                || project.shortroot.localizedCaseInsensitiveContains(query)
                || project.approot.localizedCaseInsensitiveContains(query)
        }
    }

    var runningCount: Int {
        projects.filter(\.isRunning).count
    }

    var selectedProject: DdevProject? {
        guard let selectedProjectName else { return nil }
        return projects.first { $0.name == selectedProjectName }
    }

    var selectedGroup: DdevProjectGroup? {
        guard let selectedGroupID else { return nil }
        return groups.first { $0.id == selectedGroupID }
    }

    var filteredGroups: [DdevProjectGroup] {
        let query = groupSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return groups }

        return groups.filter { group in
            group.name.localizedCaseInsensitiveContains(query)
                || group.projectNames.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    func projects(in group: DdevProjectGroup) -> [DdevProject] {
        let byName = Dictionary(uniqueKeysWithValues: projects.map { ($0.name, $0) })
        return group.projectNames.compactMap { byName[$0] }
    }

    func groupStatus(_ group: DdevProjectGroup) -> DdevGroupStatus {
        let known = projects(in: group)
        let knownNames = Set(known.map(\.name))
        let missing = group.projectNames.filter { !knownNames.contains($0) }.count
        let running = known.filter(\.isRunning).count
        let stopped = known.count - running

        return DdevGroupStatus(running: running, stopped: stopped, missing: missing)
    }

    func selectTab(_ tab: MainTab) {
        mainTab = tab
        if tab == .groups {
            clearProjectSelection()
        } else {
            clearGroupSelection()
        }
    }

    func selectGroup(_ id: UUID?) {
        selectedGroupID = id
        isEditingGroup = false
        editingGroup = nil
        clearProjectSelection()
    }

    func beginCreateGroup() {
        selectedGroupID = nil
        isEditingGroup = true
        editingGroup = DdevProjectGroup(name: "", projectNames: [])
        clearProjectSelection()
    }

    func beginEditGroup(_ group: DdevProjectGroup) {
        selectedGroupID = group.id
        isEditingGroup = true
        editingGroup = group
        clearProjectSelection()
    }

    func cancelGroupEditing() {
        isEditingGroup = false
        editingGroup = nil
    }

    func saveGroup(_ group: DdevProjectGroup) {
        let trimmedName = group.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            statusMessage = "Group name is required."
            return
        }

        var updatedGroup = group
        updatedGroup.name = trimmedName

        var seen = Set<String>()
        updatedGroup.projectNames = updatedGroup.projectNames.filter { seen.insert($0).inserted }

        if let index = groups.firstIndex(where: { $0.id == updatedGroup.id }) {
            groups[index] = updatedGroup
        } else {
            groups.append(updatedGroup)
        }

        groups.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        groupRepository.save(groups)
        selectedGroupID = updatedGroup.id
        isEditingGroup = false
        editingGroup = nil
        statusMessage = nil
    }

    func deleteGroup(_ group: DdevProjectGroup) {
        groups.removeAll { $0.id == group.id }
        groupRepository.save(groups)
        if selectedGroupID == group.id {
            selectedGroupID = nil
        }
        isEditingGroup = false
        editingGroup = nil
    }

    func startGroup(_ group: DdevProjectGroup) async {
        let names = stoppableProjectNames(in: group, running: false)
        guard !names.isEmpty else {
            statusMessage = "All projects in \(group.name) are already running."
            return
        }

        await performAction("Starting \(group.name)…") {
            try await cli.startProjects(names)
        }
    }

    func stopGroup(_ group: DdevProjectGroup) async {
        let names = stoppableProjectNames(in: group, running: true)
        guard !names.isEmpty else {
            statusMessage = "No running projects in \(group.name)."
            return
        }

        await performAction("Stopping \(group.name)…") {
            try await cli.stopProjects(names)
        }
    }

    func restartGroup(_ group: DdevProjectGroup) async {
        let names = group.projectNames.filter { name in
            projects.contains { $0.name == name }
        }
        guard !names.isEmpty else {
            statusMessage = "No known projects in \(group.name)."
            return
        }

        await performAction("Restarting \(group.name)…") {
            try await cli.restartProjects(names)
        }
    }

    func openProjectFromGroup(_ name: String) {
        mainTab = .projects
        clearGroupSelection()
        selectProject(name)
    }

    private func stoppableProjectNames(in group: DdevProjectGroup, running: Bool) -> [String] {
        projects(in: group)
            .filter { $0.isRunning == running }
            .map(\.name)
    }

    private func clearProjectSelection() {
        selectedProjectName = nil
        selectedDetail = nil
        detailTask?.cancel()
    }

    private func clearGroupSelection() {
        selectedGroupID = nil
        isEditingGroup = false
        editingGroup = nil
    }

    func startAutoRefresh(interval: TimeInterval = 15) {
        refreshTask?.cancel()
        refreshTask = Task {
            try? await Task.sleep(for: .seconds(interval))
            while !Task.isCancelled {
                await refreshProjects()
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    func refreshProjects() async {
        ddevAvailable = cli.isAvailable
        guard ddevAvailable else {
            statusMessage = "DDEV not found. Expected at /opt/homebrew/bin/ddev or /usr/local/bin/ddev."
            projects = []
            return
        }

        if isLoading { return }

        isLoading = true
        defer { isLoading = false }

        do {
            projects = try await cli.listProjects()
            lastRefreshed = .now
            statusMessage = nil

            if let selectedProjectName,
               projects.contains(where: { $0.name == selectedProjectName }) {
                await loadDetail(for: selectedProjectName)
            } else {
                selectedProjectName = nil
                selectedDetail = nil
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func selectProject(_ name: String?) {
        selectedProjectName = name
        selectedDetail = nil
        clearGroupSelection()

        guard let name else {
            detailTask?.cancel()
            return
        }

        detailTask?.cancel()
        detailTask = Task {
            await loadDetail(for: name)
        }
    }

    func startProject(_ name: String) async {
        await performAction("Starting \(name)…") {
            try await cli.startProject(name)
        }
    }

    func stopProject(_ name: String) async {
        await performAction("Stopping \(name)…") {
            try await cli.stopProject(name)
        }
    }

    func restartProject(_ name: String) async {
        await performAction("Restarting \(name)…") {
            try await cli.restartProject(name)
        }
    }

    func openPrimaryURL(for project: DdevProject) {
        guard let urlString = project.primaryURL ?? project.httpsURL ?? project.httpURL,
              let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    func openMailpit(for project: DdevProject) {
        guard let urlString = project.mailpitURL,
              let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    func revealInFinder(_ project: DdevProject) {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: project.approot)
    }

    func openInTerminal(_ command: String, workingDirectory: String? = nil) {
        do {
            try terminalLauncher.open(command: command, workingDirectory: workingDirectory)
            statusMessage = nil
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func sshIntoProject(_ name: String, approot: String) {
        openInTerminal("ddev ssh \(name.shellSingleQuoted)", workingDirectory: approot)
    }

    func showLogs(for name: String, approot: String) -> LogSession {
        LogSession(projectName: name, approot: approot)
    }

    func showLogsInTerminal(for name: String, approot: String) {
        openInTerminal("ddev logs -f \(name.shellSingleQuoted)", workingDirectory: approot)
    }

    private func loadDetail(for name: String) async {
        do {
            selectedDetail = try await cli.describeProject(name)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func performAction(_ progressMessage: String, action: () async throws -> Void) async {
        isPerformingAction = true
        statusMessage = progressMessage
        defer { isPerformingAction = false }

        do {
            try await action()
            statusMessage = nil
            await refreshProjects()
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}
