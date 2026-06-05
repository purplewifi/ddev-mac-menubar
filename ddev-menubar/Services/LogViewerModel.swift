import Foundation
import Observation

@MainActor
@Observable
final class LogViewerModel {
    let session: LogSession

    var service = "web"
    var isFollowing = true
    var autoScroll = true

    private(set) var text = ""
    private(set) var status = "Connecting…"
    private(set) var isStreaming = false

    private let cli: DdevCLI
    private var streamTask: Task<Void, Never>?

    init(session: LogSession, cli: DdevCLI = .shared) {
        self.session = session
        self.cli = cli
    }

    var windowTitle: String {
        "\(session.projectName) · \(service)"
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
        text = ""
    }

    func setFollowing(_ value: Bool) {
        guard isFollowing != value else { return }
        isFollowing = value
        restartStream()
    }

    func setService(_ value: String) {
        guard service != value else { return }
        service = value
        restartStream()
    }

    func reconnect() {
        restartStream()
    }

    private func restartStream() {
        streamTask?.cancel()
        isStreaming = true
        status = isFollowing ? "Tailing…" : "Loading…"

        streamTask = Task {
            do {
                let stream = cli.streamLogs(
                    projectName: session.projectName,
                    service: service,
                    follow: isFollowing,
                    tail: isFollowing ? "100" : "200"
                )

                for try await chunk in stream {
                    if Task.isCancelled { return }
                    append(chunk)
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

    private func append(_ chunk: String) {
        text += chunk

        let limit = 500_000
        if text.count > limit {
            text = String(text.suffix(limit - 100_000))
        }
    }
}
