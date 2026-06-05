import Foundation

struct StartupStep: Identifiable, Sendable {
    enum Status: Sendable {
        case pending
        case active
        case complete
        case warning
        case failed
    }

    let id: String
    let label: String
    var status: Status
}

struct ProjectProgressItem: Identifiable, Sendable {
    let name: String
    var label: String
    var status: StartupStep.Status

    var id: String { name }
}

struct StartupProgress: Sendable {
    enum Kind: Sendable {
        case start
        case restart
        case stop
    }

    let kind: Kind
    let title: String
    let projectNames: [String]
    var projects: [ProjectProgressItem]
    var steps: [StartupStep]
    var note: String?
    var isFinished = false
    var succeeded = false

    var isMultiProject: Bool { projectNames.count > 1 }

    var completedCount: Int {
        projects.filter { $0.status == .complete }.count
    }

    var activeStep: StartupStep? {
        steps.last(where: { $0.status == .active })
    }
}

enum DdevFriendlyLog {
    private static let stepOrder = ["prepare", "build", "services", "sync", "router", "ready"]

    static func initialProgress(
        title: String,
        projectNames: [String],
        kind: StartupProgress.Kind
    ) -> StartupProgress {
        if projectNames.count > 1 {
            return StartupProgress(
                kind: kind,
                title: title,
                projectNames: projectNames,
                projects: projectNames.map {
                    ProjectProgressItem(
                        name: $0,
                        label: waitingLabel(for: kind),
                        status: .pending
                    )
                },
                steps: [],
                note: summaryNote(for: kind, completed: 0, total: projectNames.count)
            )
        }

        return StartupProgress(
            kind: kind,
            title: title,
            projectNames: projectNames,
            projects: [],
            steps: initialSteps(for: kind)
        )
    }

    static func markRemainingComplete(_ progress: inout StartupProgress) {
        if progress.isMultiProject {
            let label = finishedLabel(for: progress.kind)
            for index in progress.projects.indices where progress.projects[index].status != .failed {
                progress.projects[index].status = .complete
                progress.projects[index].label = label
            }
            refreshOverallStatus(&progress)
            return
        }

        markSuccess(&progress, label: finishedLabel(for: progress.kind))
    }

    static func apply(_ line: DdevLogLine, to progress: inout StartupProgress) {
        let (projectName, message) = extractProjectAndMessage(from: line.message)

        if progress.isMultiProject {
            guard let projectName else { return }
            applyToProject(projectName, line: line, message: message, progress: &progress)
            return
        }

        applyToSingleProject(line: line, message: message, progress: &progress)
    }

    private static func applyToProject(
        _ name: String,
        line: DdevLogLine,
        message: String,
        progress: inout StartupProgress
    ) {
        guard let index = progress.projects.firstIndex(where: { $0.name == name }) else { return }
        let normalized = message.lowercased()

        switch line.level {
        case "error", "fatal":
            progress.projects[index].status = .failed
            progress.projects[index].label = firstSentence(from: message)
            refreshOverallStatus(&progress)
            return
        default:
            break
        }

        switch progress.kind {
        case .stop:
            if normalized.contains("has been stopped") {
                progress.projects[index].label = "Stopped"
                progress.projects[index].status = .complete
            } else if normalized.contains("stopping") || normalized.contains("removed") {
                progress.projects[index].label = "Stopping"
                progress.projects[index].status = .active
            } else if progress.projects[index].status == .pending {
                progress.projects[index].label = "Stopping"
                progress.projects[index].status = .active
            }
        case .start, .restart:
            if normalized.contains("successfully started") || normalized.contains("successfully restarted") {
                progress.projects[index].label = "Ready"
                progress.projects[index].status = .complete
            } else if normalized.contains("your project can be reached at") {
                progress.projects[index].label = "Ready"
                progress.projects[index].status = .complete
            } else if normalized.contains("mutagen") {
                progress.projects[index].label = "Syncing files"
                progress.projects[index].status = .active
            } else if normalized.contains("building project images") {
                progress.projects[index].label = "Building"
                progress.projects[index].status = .active
            } else if normalized.contains("container") && normalized.contains("started") {
                progress.projects[index].label = "Starting services"
                progress.projects[index].status = .active
            } else if normalized.contains("starting") {
                progress.projects[index].label = "Getting ready"
                progress.projects[index].status = .active
            } else if normalized.contains("router") {
                progress.projects[index].label = "Connecting router"
                progress.projects[index].status = .active
            } else if progress.projects[index].status == .pending {
                progress.projects[index].label = "Getting ready"
                progress.projects[index].status = .active
            }
        }

        refreshOverallStatus(&progress)
    }

    private static func applyToSingleProject(
        line: DdevLogLine,
        message: String,
        progress: inout StartupProgress
    ) {
        let normalized = message.lowercased()

        switch line.level {
        case "error", "fatal":
            failCurrentStep(in: &progress)
            progress.note = firstSentence(from: message)
            return
        case "warning":
            if let note = friendlyWarning(from: message) {
                progress.note = note
            }
        default:
            break
        }

        switch progress.kind {
        case .stop:
            if normalized.contains("has been stopped") {
                markSuccess(&progress, label: "Stopped")
            } else if normalized.contains("stopping") || normalized.contains("removed") {
                activate(&progress, id: "prepare", label: "Stopping containers")
            }
            return
        case .start, .restart:
            break
        }

        if normalized.contains("starting") && normalized.hasSuffix("...") {
            activate(&progress, id: "prepare", label: "Getting ready")
            return
        }

        if normalized.contains("building project images") {
            activate(&progress, id: "build", label: "Building containers")
            return
        }

        if normalized.contains("project images built") {
            complete(&progress, id: "build")
            return
        }

        if normalized.contains("container") && normalized.contains("-db") && normalized.contains("started") {
            complete(&progress, id: "build")
            activate(&progress, id: "services", label: "Starting database")
            return
        }

        if normalized.contains("container") && normalized.contains("-web") && normalized.contains("started") {
            complete(&progress, id: "services", label: "Starting web server")
            return
        }

        if normalized.contains("mutagen") {
            activate(&progress, id: "sync", label: "Syncing your files")
            if normalized.contains("completed") || normalized.contains("flush completed") {
                complete(&progress, id: "sync")
            }
            return
        }

        if normalized.contains("web_extra_daemons") || normalized.contains("extra_daemons") {
            activate(&progress, id: "services", label: "Starting background services")
            return
        }

        if normalized.contains("ddev-router") || normalized.contains("router") {
            activate(&progress, id: "router", label: "Connecting router")
            if normalized.contains("started") {
                complete(&progress, id: "router")
            }
            return
        }

        if normalized.contains("successfully started") || normalized.contains("successfully restarted") {
            markSuccess(&progress, label: "Ready to go")
            return
        }

        if normalized.contains("your project can be reached at") {
            markSuccess(&progress, label: "Ready to go")
            if let url = extractURL(from: message) {
                progress.note = "Ready at \(url)"
            }
            return
        }

        if line.level == "info", let friendly = friendlyInfo(from: message) {
            updateActiveLabel(&progress, friendly)
        }
    }

    private static func refreshOverallStatus(_ progress: inout StartupProgress) {
        let total = progress.projects.count
        let completed = progress.projects.filter { $0.status == .complete }.count
        let failed = progress.projects.contains { $0.status == .failed }
        let allDone = progress.projects.allSatisfy {
            $0.status == .complete || $0.status == .failed
        }

        if allDone {
            progress.isFinished = true
            progress.succeeded = !failed && completed == total
            if progress.succeeded {
                progress.note = finishedNote(for: progress.kind, count: completed)
            } else {
                progress.note = "\(completed) of \(total) finished"
            }
        } else {
            progress.note = summaryNote(for: progress.kind, completed: completed, total: total)
        }
    }

    private static func initialSteps(for kind: StartupProgress.Kind) -> [StartupStep] {
        switch kind {
        case .stop:
            return [
                StartupStep(id: "prepare", label: "Stopping containers", status: .active),
                StartupStep(id: "ready", label: "Finishing up", status: .pending),
            ]
        case .start, .restart:
            return [
                StartupStep(id: "prepare", label: "Getting ready", status: .active),
                StartupStep(id: "build", label: "Building containers", status: .pending),
                StartupStep(id: "services", label: "Starting services", status: .pending),
                StartupStep(id: "sync", label: "Syncing files", status: .pending),
                StartupStep(id: "router", label: "Connecting router", status: .pending),
                StartupStep(id: "ready", label: "Finishing up", status: .pending),
            ]
        }
    }

    private static func waitingLabel(for kind: StartupProgress.Kind) -> String {
        switch kind {
        case .stop: "Waiting"
        case .start, .restart: "Waiting"
        }
    }

    private static func summaryNote(
        for kind: StartupProgress.Kind,
        completed: Int,
        total: Int
    ) -> String {
        switch kind {
        case .stop:
            return "\(completed) of \(total) stopped"
        case .start, .restart:
            return "\(completed) of \(total) ready"
        }
    }

    private static func finishedLabel(for kind: StartupProgress.Kind) -> String {
        switch kind {
        case .stop: "Stopped"
        case .start, .restart: "Ready"
        }
    }

    private static func finishedNote(for kind: StartupProgress.Kind, count: Int) -> String {
        switch kind {
        case .stop:
            return count == 1 ? "Project stopped" : "All \(count) projects stopped"
        case .start, .restart:
            return count == 1 ? "Project ready" : "All \(count) projects ready"
        }
    }

    private static func markSuccess(_ progress: inout StartupProgress, label: String) {
        for index in progress.steps.indices {
            if progress.steps[index].status == .active || progress.steps[index].status == .pending {
                progress.steps[index].status = .complete
            }
        }
        if let readyIndex = progress.steps.firstIndex(where: { $0.id == "ready" }) {
            progress.steps[readyIndex] = StartupStep(id: "ready", label: label, status: .complete)
        }
        progress.isFinished = true
        progress.succeeded = true
    }

    private static func failCurrentStep(in progress: inout StartupProgress) {
        if let index = progress.steps.lastIndex(where: { $0.status == .active }) {
            progress.steps[index].status = .failed
        } else if let index = progress.steps.firstIndex(where: { $0.status == .pending }) {
            progress.steps[index].status = .failed
        }
        progress.isFinished = true
        progress.succeeded = false
    }

    private static func activate(_ progress: inout StartupProgress, id: String, label: String) {
        completeEarlierSteps(in: &progress, before: id)
        setStep(&progress, id: id, label: label, status: .active)
    }

    private static func complete(_ progress: inout StartupProgress, id: String, label: String? = nil) {
        setStep(&progress, id: id, label: label, status: .complete)
    }

    private static func completeEarlierSteps(in progress: inout StartupProgress, before id: String) {
        guard let targetIndex = stepOrder.firstIndex(of: id) else { return }
        for stepID in stepOrder.prefix(targetIndex) {
            if let index = progress.steps.firstIndex(where: { $0.id == stepID }),
               progress.steps[index].status != .complete {
                progress.steps[index].status = .complete
            }
        }
    }

    private static func setStep(
        _ progress: inout StartupProgress,
        id: String,
        label: String?,
        status: StartupStep.Status
    ) {
        guard let index = progress.steps.firstIndex(where: { $0.id == id }) else { return }
        progress.steps[index] = StartupStep(
            id: id,
            label: label ?? progress.steps[index].label,
            status: status
        )
    }

    private static func updateActiveLabel(_ progress: inout StartupProgress, _ label: String) {
        guard let index = progress.steps.lastIndex(where: { $0.status == .active }) else { return }
        progress.steps[index] = StartupStep(
            id: progress.steps[index].id,
            label: label,
            status: .active
        )
    }

    private static func extractProjectAndMessage(from message: String) -> (String?, String) {
        if message.hasPrefix("["),
           let end = message.firstIndex(of: "]") {
            let name = String(message[message.index(after: message.startIndex)..<end])
            let rest = message[message.index(after: end)...].trimmingCharacters(in: .whitespaces)
            return (name, rest)
        }
        return (nil, message)
    }

    private static func friendlyInfo(from message: String) -> String? {
        let normalized = message.lowercased()
        if normalized.contains("network") && normalized.contains("created") {
            return "Setting up network"
        }
        if normalized.contains("waiting") {
            return "Waiting for services"
        }
        if normalized.contains("pulling") {
            return "Pulling images"
        }
        return nil
    }

    private static func friendlyWarning(from message: String) -> String? {
        let normalized = message.lowercased()
        if normalized.contains("mutagen") && normalized.contains("upload_dirs") {
            return "Tip: configuring upload folders can speed up startup."
        }
        if normalized.contains("custom configuration detected") {
            return "This project has custom DDEV settings."
        }
        return firstSentence(from: message, maxLength: 120)
    }

    private static func firstSentence(from message: String, maxLength: Int = 180) -> String {
        let trimmed = message
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init) ?? message
        if trimmed.count <= maxLength {
            return trimmed
        }
        return String(trimmed.prefix(maxLength - 1)) + "…"
    }

    private static func extractURL(from message: String) -> String? {
        let pattern = #"https?://[^\s\\]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: message, range: NSRange(message.startIndex..., in: message)),
              let range = Range(match.range, in: message) else {
            return nil
        }
        return String(message[range])
    }
}
