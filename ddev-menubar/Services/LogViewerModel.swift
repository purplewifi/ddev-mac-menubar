import Foundation
import Observation

@MainActor
@Observable
final class LogViewerModel {
    let session: LogSession

    let tabs: [LogTab]
    var selectedTabID: String
    var customLogPath = ""
    var isFollowing = true
    var autoScroll = true

    private(set) var tabTexts: [String: String] = [:]
    private(set) var status = "Connecting…"
    private(set) var isStreaming = false

    private let cli: DdevCLI
    private var streamTask: Task<Void, Never>?
    private var initializedTabs: Set<String> = []

    init(session: LogSession, cli: DdevCLI = .shared) {
        self.session = session
        self.cli = cli
        self.tabs = LogSourceCatalog.tabs(for: session.projectType)
        self.selectedTabID = tabs.first?.id ?? "web"
    }

    var selectedTab: LogTab? {
        tabs.first { $0.id == selectedTabID }
    }

    var text: String {
        tabTexts[selectedTabID] ?? ""
    }

    var windowTitle: String {
        guard let selectedTab else { return session.projectName }
        return "\(session.projectName) · \(selectedTab.label)"
    }

    func start() {
        restartStream()
    }

    func stop() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
    }

    func clear() {
        tabTexts[selectedTabID] = ""
        initializedTabs.remove(selectedTabID)
        restartStream()
    }

    func setFollowing(_ value: Bool) {
        guard isFollowing != value else { return }
        isFollowing = value
        restartStream()
    }

    func selectTab(_ id: String) {
        guard selectedTabID != id else { return }
        selectedTabID = id
        restartStream()
    }

    func setCustomLogPath(_ value: String) {
        customLogPath = value
    }

    func applyCustomLogPath() {
        guard selectedTab?.isCustom == true else { return }
        initializedTabs.remove(selectedTabID)
        restartStream()
    }

    func reconnect() {
        initializedTabs.remove(selectedTabID)
        restartStream()
    }

    private func restartStream() {
        streamTask?.cancel()
        isStreaming = false

        guard let selectedTab else {
            status = "No log source selected."
            return
        }

        guard let source = resolvedSource(for: selectedTab) else {
            status = "Enter a log file path."
            return
        }

        isStreaming = true
        status = isFollowing ? "Tailing…" : "Loading…"

        let tabID = selectedTab.id
        let tailCount = tailCount(for: tabID)

        streamTask = Task {
            do {
                let stream: AsyncThrowingStream<String, Error>
                switch source {
                case .container(let service):
                    stream = cli.streamLogs(
                        projectName: session.projectName,
                        service: service,
                        follow: isFollowing,
                        tail: tailCount
                    )
                case .file(let path):
                    stream = cli.streamFileLog(
                        projectName: session.projectName,
                        path: path,
                        follow: isFollowing,
                        tail: tailCount
                    )
                }

                for try await chunk in stream {
                    if Task.isCancelled { return }
                    append(chunk, to: tabID)
                    initializedTabs.insert(tabID)
                }

                if !Task.isCancelled {
                    status = isFollowing ? "Stream ended" : "Done"
                    isStreaming = false
                }
            } catch is CancellationError {
                return
            } catch {
                if !Task.isCancelled {
                    status = error.localizedDescription
                    isStreaming = false
                }
            }
        }
    }

    private func resolvedSource(for tab: LogTab) -> LogSource? {
        switch tab.source {
        case .container:
            return tab.source
        case .file(let path):
            if tab.isCustom {
                let trimmed = customLogPath.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                return .file(path: trimmed)
            }
            guard !path.isEmpty else { return nil }
            return .file(path: path)
        }
    }

    private func tailCount(for tabID: String) -> String? {
        if initializedTabs.contains(tabID) {
            return nil
        }
        return isFollowing ? "100" : "200"
    }

    private func append(_ chunk: String, to tabID: String) {
        var current = tabTexts[tabID] ?? ""
        current += chunk

        let limit = 500_000
        if current.count > limit {
            current = String(current.suffix(limit - 100_000))
        }

        tabTexts[tabID] = current
    }
}
