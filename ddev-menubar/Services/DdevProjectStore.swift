import AppKit
import Foundation
import Observation

@MainActor
private final class StartupProgressSink {
    weak var store: DdevProjectStore?

    nonisolated func receive(_ line: DdevLogLine) {
        DispatchQueue.main.async { [weak self] in
            self?.store?.ingestStartupLogLine(line)
        }
    }
}

enum MainTab: String, CaseIterable, Identifiable {
    case projects = "Projects"
    case groups = "Groups"

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
    private(set) var isRefreshing = false
    private(set) var isPerformingAction = false
    private(set) var activityMessage: String?
    private(set) var statusMessage: String?
    private(set) var lastRefreshed: Date?
    private(set) var ddevAvailable: Bool
    private(set) var pendingLogSession: LogSession?
    private(set) var logOpenNonce = 0
    private(set) var actionReport: DdevActionReport?
    private(set) var startupProgress: StartupProgress?
    private(set) var isMenuPresented = false
    private(set) var isAppActive = NSApplication.shared.isActive
    private(set) var favouritedProjectNames: Set<String> = []

    var mainTab: MainTab = .projects
    var searchText = "" {
        didSet { /* derived in filteredProjects */ }
    }
    var groupSearchText = ""

    private let cli: DdevCLI
    private let groupRepository: ProjectGroupRepository
    private let preferencesRepository: PreferencesRepository
    private let terminalLauncher: TerminalLauncher
    private let notifications: NotificationService
    private var refreshTask: Task<Void, Never>?
    private var detailTask: Task<Void, Never>?
    private var refreshInProgress = false
    private var startupProgressSink: StartupProgressSink?
    private var appActivityObservers: [NSObjectProtocol] = []

    init(
        cli: DdevCLI = .shared,
        groupRepository: ProjectGroupRepository = ProjectGroupRepository(),
        preferencesRepository: PreferencesRepository = PreferencesRepository(),
        terminalLauncher: TerminalLauncher = TerminalLauncher(),
        notifications: NotificationService = .shared
    ) {
        self.cli = cli
        self.groupRepository = groupRepository
        self.preferencesRepository = preferencesRepository
        self.terminalLauncher = terminalLauncher
        self.notifications = notifications
        self.ddevAvailable = cli.isAvailable
        self.groups = groupRepository.load()
        self.favouritedProjectNames = preferencesRepository.loadFavourites()
        startObservingAppActivity()
    }

    var shouldNotifyForBackgroundEvents: Bool {
        !isMenuPresented
    }

    var ddevExecutablePath: String? {
        cli.executablePath
    }

    func setMenuPresented(_ presented: Bool) {
        isMenuPresented = presented
    }

    private func startObservingAppActivity() {
        let center = NotificationCenter.default

        appActivityObservers = [
            center.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.isAppActive = true
                    self?.syncMenuPresentedFromWindows()
                }
            },
            center.addObserver(
                forName: NSApplication.didResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.isAppActive = false
                    self?.syncMenuPresentedFromWindows()
                }
            },
            center.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.syncMenuPresentedFromWindows()
                }
            },
            center.addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.syncMenuPresentedFromWindows()
                }
            },
        ]
    }

    private func syncMenuPresentedFromWindows() {
        isMenuPresented = NSApp.windows.contains { window in
            window.isVisible && window.isKind(of: NSPanel.self)
        }
    }

    var filteredProjects: [DdevProject] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered: [DdevProject] = query.isEmpty ? projects : projects.filter { project in
            project.name.localizedCaseInsensitiveContains(query)
                || project.shortroot.localizedCaseInsensitiveContains(query)
                || project.approot.localizedCaseInsensitiveContains(query)
        }
        let favs = filtered.filter { favouritedProjectNames.contains($0.name) }
        let rest = filtered.filter { !favouritedProjectNames.contains($0.name) }
        return favs + rest
    }

    func isFavourite(_ name: String) -> Bool {
        favouritedProjectNames.contains(name)
    }

    func toggleFavourite(_ name: String) {
        if favouritedProjectNames.contains(name) {
            favouritedProjectNames.remove(name)
        } else {
            favouritedProjectNames.insert(name)
        }
        preferencesRepository.saveFavourites(favouritedProjectNames)
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

    func duplicateGroup(_ group: DdevProjectGroup) {
        let newGroup = DdevProjectGroup(name: "Copy of \(group.name)", projectNames: group.projectNames)
        selectedGroupID = nil
        isEditingGroup = true
        editingGroup = newGroup
        clearProjectSelection()
    }

    func startGroup(_ group: DdevProjectGroup) async {
        let names = stoppableProjectNames(in: group, running: false)
        guard !names.isEmpty else {
            statusMessage = "All projects in \(group.name) are already running."
            return
        }

        await performProjectAction(
            "Starting \(group.name)…",
            projectNames: names,
            progressKind: .start
        ) { onLine in
            try await cli.startProjects(names, parallel: true, onLine: onLine)
        }
    }

    func stopGroup(_ group: DdevProjectGroup) async {
        let names = stoppableProjectNames(in: group, running: true)
        guard !names.isEmpty else {
            statusMessage = "No running projects in \(group.name)."
            return
        }

        await performProjectAction(
            "Stopping \(group.name)…",
            projectNames: names,
            progressKind: .stop
        ) { onLine in
            try await cli.stopProjects(names, parallel: true, onLine: onLine)
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

        await performProjectAction(
            "Restarting \(group.name)…",
            projectNames: names,
            progressKind: .restart
        ) { onLine in
            try await cli.restartProjects(names, parallel: true, onLine: onLine)
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

    func startAutoRefresh(interval: TimeInterval = 120) {
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

    func refreshProjects(showActivity: Bool = false) async {
        await refreshProjects(
            activityMessage: showActivity ? "Refreshing projects…" : nil
        )
    }

    private func refreshProjects(activityMessage: String?) async {
        ddevAvailable = cli.isAvailable
        guard ddevAvailable else {
            statusMessage = "DDEV not found. Expected at /opt/homebrew/bin/ddev or /usr/local/bin/ddev."
            projects = []
            self.activityMessage = nil
            return
        }

        guard !refreshInProgress else { return }

        refreshInProgress = true
        let isInitialLoad = projects.isEmpty
        if isInitialLoad {
            isLoading = true
        } else {
            isRefreshing = true
            if let activityMessage {
                self.activityMessage = activityMessage
            }
        }
        defer {
            refreshInProgress = false
            isLoading = false
            isRefreshing = false
            if activityMessage != nil {
                self.activityMessage = nil
            }
        }

        do {
            let fetched = try await cli.listProjects()
            applyProjects(fetched)
            lastRefreshed = .now

            if statusMessage?.hasPrefix("DDEV not found") != true {
                statusMessage = nil
            }

            if let selectedProjectName,
               projects.contains(where: { $0.name == selectedProjectName }) {
                await loadDetail(for: selectedProjectName)
            } else if selectedProjectName != nil {
                selectedProjectName = nil
                selectedDetail = nil
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func applyProjects(_ fetched: [DdevProject]) {
        guard fetched != projects else { return }
        projects = fetched
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
        await performProjectAction(
            "Starting \(name)…",
            projectNames: [name],
            progressKind: .start
        ) { onLine in
            try await cli.startProjects([name], onLine: onLine)
        }
    }

    func stopProject(_ name: String) async {
        await performProjectAction(
            "Stopping \(name)…",
            projectNames: [name],
            progressKind: .stop
        ) { onLine in
            try await cli.stopProjects([name], onLine: onLine)
        }
    }

    func restartProject(_ name: String) async {
        await performProjectAction(
            "Restarting \(name)…",
            projectNames: [name],
            progressKind: .restart
        ) { onLine in
            try await cli.restartProjects([name], onLine: onLine)
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

    func authSSHInTerminal() {
        let keychain = "\(NSHomeDirectory())/Library/Keychains/login.keychain-db"
        openInTerminal(
            """
            security unlock-keychain \(keychain.shellSingleQuoted) 2>/dev/null || security unlock-keychain login.keychain 2>/dev/null || true
            ddev auth ssh
            """
        )
    }

    func dismissActionReport() {
        actionReport = nil
    }

    func requestLogs(for name: String, approot: String, projectType: String? = nil) {
        pendingLogSession = LogSession(
            projectName: name,
            approot: approot,
            projectType: projectType
        )
        logOpenNonce += 1
    }

    func setXdebug(for name: String, enabled: Bool) async {
        await performAction(enabled ? "Enabling Xdebug for \(name)…" : "Disabling Xdebug for \(name)…") {
            try await cli.setXdebug(projectName: name, enabled: enabled)
        }
    }

    func showLogsInTerminal(for name: String, approot: String) {
        openInTerminal("ddev logs -f \(name.shellSingleQuoted)", workingDirectory: approot)
    }

    func ingestStartupLogLine(_ line: DdevLogLine) {
        guard var progress = startupProgress else { return }
        DdevFriendlyLog.apply(line, to: &progress)
        startupProgress = progress
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
        activityMessage = progressMessage
        statusMessage = nil
        defer {
            isPerformingAction = false
            if statusMessage == nil {
                activityMessage = nil
            }
        }

        do {
            try await action()
            await refreshProjects(activityMessage: "Updating projects…")
        } catch {
            activityMessage = nil
            statusMessage = error.localizedDescription
        }
    }

    private func performProjectAction(
        _ progressMessage: String,
        projectNames: [String],
        progressKind: StartupProgress.Kind,
        action: (_ onLine: (@Sendable (DdevLogLine) -> Void)?) async throws -> DdevActionOutput
    ) async {
        isPerformingAction = true
        activityMessage = nil
        statusMessage = nil
        actionReport = nil
        let progressSink = StartupProgressSink()
        startupProgressSink = progressSink
        progressSink.store = self
        startupProgress = DdevFriendlyLog.initialProgress(
            title: progressMessage.replacingOccurrences(of: "…", with: ""),
            projectNames: projectNames,
            kind: progressKind
        )
        defer {
            isPerformingAction = false
            startupProgressSink = nil
            if statusMessage == nil {
                startupProgress = nil
            }
            if statusMessage == nil, actionReport == nil {
                activityMessage = nil
            }
        }

        let onLine: @Sendable (DdevLogLine) -> Void = { line in
            progressSink.receive(line)
        }

        do {
            let output = try await action(onLine)
            syncMenuPresentedFromWindows()
            if var progress = startupProgress, !progress.isFinished {
                DdevFriendlyLog.markRemainingComplete(&progress)
                startupProgress = progress
            }
            activityMessage = "Updating projects…"
            await refreshProjects(activityMessage: "Updating projects…")
            syncMenuPresentedFromWindows()

            if progressKind == .stop {
                if !output.errors.isEmpty {
                    statusMessage = output.errors.joined(separator: "\n")
                } else {
                    statusMessage = nil
                    activityMessage = nil
                }
                return
            }

            var messages: [String] = output.errors

            var serviceIssues: [DdevServiceIssue] = []
            var logExcerpts: [DdevLogExcerpt] = []
            var hints: [String] = []
            var mutagenProblems = false

            for name in projectNames {
                if let project = projects.first(where: { $0.name == name }),
                   let mutagenStatus = project.mutagenStatus,
                   Self.mutagenLooksUnhealthy(mutagenStatus) {
                    mutagenProblems = true
                    messages.append("\(name): Mutagen — \(mutagenStatus)")
                }

                guard let detail = try? await cli.describeProject(name) else { continue }

                if !cli.projectLooksHealthy(detail) {
                    messages.append("\(name): status is \(detail.statusDesc)")
                }

                let issues = cli.serviceIssues(for: detail)
                serviceIssues.append(contentsOf: issues)

                for issue in issues.prefix(2) {
                    if let snippet = try? await cli.logsSnippet(
                        projectName: name,
                        service: issue.serviceName,
                        tail: 30
                    ), !snippet.isEmpty {
                        logExcerpts.append(
                            DdevLogExcerpt(
                                projectName: name,
                                serviceName: issue.serviceName,
                                text: snippet
                            )
                        )
                    }
                }
            }

            let notRunning = projectNames.filter { name in
                projects.first(where: { $0.name == name })?.isRunning != true
            }

            let hasRealProblems = !notRunning.isEmpty
                || !serviceIssues.isEmpty
                || mutagenProblems

            hints.append(contentsOf: Self.hints(
                for: serviceIssues,
                messages: messages,
                mutagenProblems: mutagenProblems
            ))

            if hasRealProblems {
                let title = progressMessage.replacingOccurrences(of: "…", with: "")
                actionReport = DdevActionReport(
                    title: "\(title) — issues detected",
                    projectNames: projectNames,
                    messages: messages,
                    serviceIssues: serviceIssues,
                    logExcerpts: logExcerpts,
                    hints: Array(Set(hints)).sorted()
                )
                statusMessage = Self.summary(serviceIssues: serviceIssues, messages: messages)
            } else {
                statusMessage = nil
                activityMessage = nil
            }

            await notifyBasedOnProjectState(
                projectNames: projectNames,
                progressKind: progressKind,
                failureMessage: statusMessage
            )
        } catch {
            activityMessage = nil
            if var progress = startupProgress {
                DdevFriendlyLog.apply(
                    DdevLogLine(level: "error", message: error.localizedDescription),
                    to: &progress
                )
                startupProgress = progress
            }

            await refreshProjects(activityMessage: nil)
            syncMenuPresentedFromWindows()

            let runningNames = runningProjectNames(from: projectNames)
            if runningNames.isEmpty {
                statusMessage = error.localizedDescription
            } else {
                statusMessage = nil
            }

            await notifyBasedOnProjectState(
                projectNames: projectNames,
                progressKind: progressKind,
                failureMessage: error.localizedDescription
            )
        }
    }

    private func runningProjectNames(from projectNames: [String]) -> [String] {
        projectNames.filter { name in
            projects.first(where: { $0.name == name })?.isRunning == true
        }
    }

    private func notifyBasedOnProjectState(
        projectNames: [String],
        progressKind: StartupProgress.Kind,
        failureMessage: String?
    ) async {
        guard progressKind != .stop, shouldNotifyForBackgroundEvents else { return }

        let running = runningProjectNames(from: projectNames)
        let notRunning = projectNames.filter { !running.contains($0) }

        if notRunning.isEmpty {
            await notifyProjectsReady(
                projectNames: projectNames,
                restarted: progressKind == .restart
            )
            return
        }

        if running.isEmpty {
            await notifyProjectsFailed(
                projectNames: notRunning,
                restarted: progressKind == .restart,
                message: failureMessage ?? "Project failed to start."
            )
            return
        }

        await notifyProjectsReady(
            projectNames: running,
            restarted: progressKind == .restart
        )
        await notifyProjectsFailed(
            projectNames: notRunning,
            restarted: progressKind == .restart,
            message: failureMessage ?? "Some projects failed to start."
        )
    }

    private func notifyProjectsReady(projectNames: [String], restarted: Bool) async {
        let url = startupProgress?.note.flatMap(extractURL(from:))
            ?? projectNames.compactMap { name in
                projects.first(where: { $0.name == name })?.primaryURL
            }.first

        await notifications.notifyProjectsReady(
            projectNames: projectNames,
            restarted: restarted,
            url: url
        )
    }

    private func notifyProjectsFailed(
        projectNames: [String],
        restarted: Bool,
        message: String
    ) async {
        await notifications.notifyProjectsFailed(
            projectNames: projectNames,
            restarted: restarted,
            message: message
        )
    }

    private func extractURL(from note: String) -> String? {
        let pattern = #"https?://[^\s]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: note, range: NSRange(note.startIndex..., in: note)),
              let range = Range(match.range, in: note) else {
            return nil
        }
        return String(note[range])
    }

    private static func mutagenLooksUnhealthy(_ status: String) -> Bool {
        let normalized = status.lowercased()
        return normalized.contains("fail")
            || normalized.contains("error")
            || normalized.contains("nosession")
    }

    private static func summary(serviceIssues: [DdevServiceIssue], messages: [String]) -> String {
        if let issue = serviceIssues.first {
            return "\(issue.projectName): \(issue.serviceName) is \(issue.status)"
        }
        if let message = messages.first {
            let firstLine = message.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? message
            return String(firstLine.prefix(180))
        }
        return "Start completed with issues."
    }

    private static func hints(
        for serviceIssues: [DdevServiceIssue],
        messages: [String],
        mutagenProblems: Bool
    ) -> [String] {
        var hints: [String] = []
        let combined = (messages + serviceIssues.map { "\($0.serviceName) \($0.status)" })
            .joined(separator: " ")
            .lowercased()

        if combined.contains("ssh") || combined.contains("keychain") || combined.contains("agent") {
            hints.append("Try Auth SSH (unlocks keychain and loads keys into ddev-ssh-agent).")
        }

        if mutagenProblems {
            hints.append("Mutagen issues can pause projects — try `ddev mutagen st <project>` or `ddev mutagen reset <project>`.")
        }

        if serviceIssues.contains(where: { $0.status == "exited" }) {
            hints.append("A container exited after start — check the service logs below for crash output.")
        }

        if !serviceIssues.isEmpty {
            hints.append("DDEV may report success even when a service fails — inspect logs for the stopped service.")
        }

        return hints
    }
}
