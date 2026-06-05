import Foundation

enum DdevCLIError: LocalizedError {
    case ddevNotFound
    case commandFailed(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .ddevNotFound:
            "Could not find the ddev executable. Install DDEV or add it to your PATH."
        case .commandFailed(let message):
            message
        case .invalidResponse:
            "DDEV returned an unexpected response."
        }
    }
}

nonisolated struct DdevCLI: Sendable {
    nonisolated static let shared = DdevCLI()

    private let ddevPath: String?
    private let decoder = JSONDecoder()

    init(ddevPath: String? = DdevCLI.locateDdev()) {
        self.ddevPath = ddevPath
    }

    var isAvailable: Bool { ddevPath != nil }

    var executablePath: String? { ddevPath }

    func versionInfo() async throws -> DdevVersionInfo {
        let response: DdevJSONResponse<DdevVersionInfo> = try await run(["version", "-j"])
        return response.raw
    }

    func listProjects() async throws -> [DdevProject] {
        let response: DdevJSONResponse<[DdevProject]> = try await run(["list", "-j"])
        return response.raw.sorted { lhs, rhs in
            if lhs.isRunning != rhs.isRunning {
                return lhs.isRunning && !rhs.isRunning
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    func describeProject(_ name: String) async throws -> DdevProjectDetail {
        let response: DdevJSONResponse<DdevProjectDetail> = try await run(["describe", name, "-j"])
        return response.raw
    }

    func startProject(_ name: String) async throws -> DdevActionOutput {
        try await startProjects([name])
    }

    @discardableResult
    func stopProject(_ name: String) async throws -> DdevActionOutput {
        try await stopProjects([name])
    }

    func restartProject(_ name: String) async throws -> DdevActionOutput {
        try await restartProjects([name])
    }

    func startProjects(
        _ names: [String],
        parallel: Bool = false,
        onLine: (@Sendable (DdevLogLine) -> Void)? = nil
    ) async throws -> DdevActionOutput {
        guard !names.isEmpty else { return .empty }
        if parallel, names.count > 1 {
            return try await runProjectsInParallel(command: "start", names: names, onLine: onLine)
        }
        return try await runAction(["start"] + names + ["-j", "-y"], onLine: onLine)
    }

    func stopProjects(
        _ names: [String],
        parallel: Bool = false,
        onLine: (@Sendable (DdevLogLine) -> Void)? = nil
    ) async throws -> DdevActionOutput {
        guard !names.isEmpty else { return .empty }
        if parallel {
            return try await runProjectsInParallel(command: "stop", names: names, onLine: onLine)
        }
        if names.count == 1 {
            return try await runStopAction(projectName: names[0], onLine: onLine)
        }
        let arguments = ["stop"] + names + ["-j"]
        if let onLine {
            return try await runAction(arguments, onLine: onLine)
        }
        _ = try await runRaw(arguments)
        return .empty
    }

    private func runStopAction(
        projectName: String,
        onLine: (@Sendable (DdevLogLine) -> Void)? = nil
    ) async throws -> DdevActionOutput {
        let arguments = Self.arguments(for: "stop", projectName: projectName)
        if let onLine {
            return try await runAction(arguments, onLine: onLine)
        }
        _ = try await runRaw(arguments)
        return .empty
    }

    func restartProjects(
        _ names: [String],
        parallel: Bool = false,
        onLine: (@Sendable (DdevLogLine) -> Void)? = nil
    ) async throws -> DdevActionOutput {
        guard !names.isEmpty else { return .empty }
        if parallel, names.count > 1 {
            return try await runProjectsInParallel(command: "restart", names: names, onLine: onLine)
        }
        return try await runAction(["restart"] + names + ["-j", "-y"], onLine: onLine)
    }

    func logsSnippet(projectName: String, service: String, tail: Int = 30) async throws -> String {
        let result = try await runProcess(["logs", projectName, "-s", service, "--tail", String(tail)])
        return result.combinedOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let optionalAddOnServices: Set<String> = [
        "xhgui",
        "phpmyadmin",
    ]

    func serviceIssues(for detail: DdevProjectDetail) -> [DdevServiceIssue] {
        guard let services = detail.services else { return [] }

        return services.compactMap { name, info in
            guard let status = info.status, status != "running" else { return nil }
            if shouldIgnoreNonRunningService(name, detail: detail) {
                return nil
            }
            return DdevServiceIssue(projectName: detail.name, serviceName: name, status: status)
        }
    }

    private func shouldIgnoreNonRunningService(_ name: String, detail: DdevProjectDetail) -> Bool {
        let normalized = name.lowercased()

        if Self.optionalAddOnServices.contains(normalized) {
            return true
        }

        if normalized == "db" {
            return !detail.includesDatabaseService
        }

        return false
    }

    func projectLooksHealthy(_ detail: DdevProjectDetail) -> Bool {
        if detail.status != "running" {
            return false
        }

        let statusDesc = detail.statusDesc.lowercased()
        if statusDesc.contains("unhealthy") || statusDesc.contains("paused") || statusDesc.contains("stopped") {
            return false
        }

        return serviceIssues(for: detail).isEmpty
    }

    func setXdebug(projectName: String, enabled: Bool) async throws {
        _ = try await runRaw(["xdebug", enabled ? "on" : "off", projectName, "-j", "-y"])
    }

    func streamFileLog(
        projectName: String,
        path: String,
        service: String = "web",
        follow: Bool = true,
        tail: String? = "100"
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            guard let ddevPath else {
                continuation.finish(throwing: DdevCLIError.ddevNotFound)
                return
            }

            var tailArguments = ["tail"]
            if follow {
                tailArguments.append("-f")
            }
            if let tail, !tail.isEmpty {
                tailArguments.append(contentsOf: ["-n", tail])
            }
            tailArguments.append(path)

            let process = Process()
            let arguments = ["exec", "-p", projectName, "-s", service, "--"] + tailArguments

            process.executableURL = URL(fileURLWithPath: ddevPath)
            process.arguments = arguments
            process.environment = Self.processEnvironment()

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            let handle = pipe.fileHandleForReading
            var pending = ""

            handle.readabilityHandler = { fileHandle in
                let data = fileHandle.availableData
                guard !data.isEmpty else { return }
                guard let chunk = String(data: data, encoding: .utf8) else { return }

                pending += chunk
                while let newlineIndex = pending.firstIndex(of: "\n") {
                    let line = String(pending[..<newlineIndex]) + "\n"
                    pending.removeSubrange(...newlineIndex)
                    continuation.yield(line)
                }
            }

            process.terminationHandler = { proc in
                handle.readabilityHandler = nil

                if !pending.isEmpty {
                    continuation.yield(pending)
                    pending = ""
                }

                if proc.terminationStatus == 0 || proc.terminationStatus == 15 {
                    continuation.finish()
                } else {
                    continuation.finish(
                        throwing: DdevCLIError.commandFailed(
                            "File log stream exited with code \(proc.terminationStatus)."
                        )
                    )
                }
            }

            continuation.onTermination = { @Sendable _ in
                handle.readabilityHandler = nil
                if process.isRunning {
                    process.terminate()
                }
            }

            do {
                try process.run()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }

    func streamLogs(
        projectName: String,
        service: String = "web",
        follow: Bool = true,
        tail: String? = "100"
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            guard let ddevPath else {
                continuation.finish(throwing: DdevCLIError.ddevNotFound)
                return
            }

            let process = Process()
            var arguments = ["logs", projectName]
            if follow {
                arguments.append("-f")
            }
            if let tail, !tail.isEmpty {
                arguments.append(contentsOf: ["--tail", tail])
            }
            if service != "web" {
                arguments.append(contentsOf: ["-s", service])
            }

            process.executableURL = URL(fileURLWithPath: ddevPath)
            process.arguments = arguments
            process.environment = Self.processEnvironment()

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            let handle = pipe.fileHandleForReading
            var pending = ""

            handle.readabilityHandler = { fileHandle in
                let data = fileHandle.availableData
                guard !data.isEmpty else { return }
                guard let chunk = String(data: data, encoding: .utf8) else { return }

                pending += chunk
                while let newlineIndex = pending.firstIndex(of: "\n") {
                    let line = String(pending[..<newlineIndex]) + "\n"
                    pending.removeSubrange(...newlineIndex)
                    continuation.yield(line)
                }
            }

            process.terminationHandler = { proc in
                handle.readabilityHandler = nil

                if !pending.isEmpty {
                    continuation.yield(pending)
                    pending = ""
                }

                if proc.terminationStatus == 0 || proc.terminationStatus == 15 {
                    continuation.finish()
                } else {
                    continuation.finish(
                        throwing: DdevCLIError.commandFailed(
                            "Log stream exited with code \(proc.terminationStatus)."
                        )
                    )
                }
            }

            continuation.onTermination = { @Sendable _ in
                handle.readabilityHandler = nil
                if process.isRunning {
                    process.terminate()
                }
            }

            do {
                try process.run()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }

    private func run<T: Decodable>(_ arguments: [String]) async throws -> T {
        let data = try await runRaw(arguments)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw DdevCLIError.commandFailed("Could not parse DDEV response: \(error.localizedDescription)")
        }
    }

    private struct ProcessResult: Sendable {
        let exitCode: Int32
        let stdout: String
        let stderr: String

        var combinedOutput: String {
            [stderr, stdout]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
        }
    }

    private func runProjectsInParallel(
        command: String,
        names: [String],
        onLine: (@Sendable (DdevLogLine) -> Void)? = nil
    ) async throws -> DdevActionOutput {
        try await withThrowingTaskGroup(of: (String, Result<DdevActionOutput, Error>).self) { group in
            for name in names {
                group.addTask {
                    do {
                        let arguments = Self.arguments(for: command, projectName: name)
                        let output = try await self.runAction(arguments) { line in
                            onLine?(
                                DdevLogLine(
                                    level: line.level,
                                    message: "[\(name)] \(line.message)"
                                )
                            )
                        }
                        return (name, .success(output))
                    } catch {
                        return (name, .failure(error))
                    }
                }
            }

            var lines: [DdevLogLine] = []
            var rawOutput = ""
            var failures: [String] = []

            for try await (name, result) in group {
                switch result {
                case .success(let output):
                    lines.append(contentsOf: output.lines)
                    rawOutput += output.rawOutput
                case .failure(let error):
                    let message = Self.errorMessage(from: error)
                    failures.append("\(name): \(message)")
                    lines.append(DdevLogLine(level: "error", message: "[\(name)] \(message)"))
                }
            }

            if failures.count == names.count {
                throw DdevCLIError.commandFailed(failures.joined(separator: "\n"))
            }

            return DdevActionOutput(
                exitCode: failures.isEmpty ? 0 : 1,
                lines: lines,
                rawOutput: rawOutput
            )
        }
    }

    private static func arguments(for command: String, projectName: String) -> [String] {
        switch command {
        case "start", "restart":
            return [command, projectName, "-j", "-y"]
        case "stop":
            return [command, projectName, "-j"]
        default:
            return [command, projectName, "-j"]
        }
    }

    private static func errorMessage(from error: Error) -> String {
        if let cliError = error as? DdevCLIError,
           case .commandFailed(let message) = cliError {
            return message
        }
        return error.localizedDescription
    }

    private func runAction(
        _ arguments: [String],
        onLine: (@Sendable (DdevLogLine) -> Void)? = nil
    ) async throws -> DdevActionOutput {
        if let onLine {
            return try await runActionStreaming(arguments, onLine: onLine)
        }

        let result = try await runProcess(arguments)
        let lines = Self.parseNDJSONLines(result.combinedOutput)

        guard result.exitCode == 0 else {
            throw DdevCLIError.commandFailed(Self.formatActionFailure(result, lines: lines))
        }

        return DdevActionOutput(exitCode: result.exitCode, lines: lines, rawOutput: result.combinedOutput)
    }

    private final class OutputLineBuffer: @unchecked Sendable {
        private var pending = ""
        private let lock = NSLock()

        func append(_ chunk: String, onLine: (String) -> Void) {
            lock.lock()
            defer { lock.unlock() }
            pending += chunk
            while let newlineIndex = pending.firstIndex(of: "\n") {
                let line = String(pending[..<newlineIndex])
                pending.removeSubrange(...newlineIndex)
                onLine(line)
            }
        }

        func flush(onLine: (String) -> Void) {
            lock.lock()
            defer { lock.unlock() }
            guard !pending.isEmpty else { return }
            onLine(pending)
            pending = ""
        }
    }

    private func runActionStreaming(
        _ arguments: [String],
        onLine: @escaping @Sendable (DdevLogLine) -> Void
    ) async throws -> DdevActionOutput {
        guard let ddevPath else {
            throw DdevCLIError.ddevNotFound
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: ddevPath)
                process.arguments = arguments
                process.environment = Self.processEnvironment()

                let stdout = Pipe()
                let stderr = Pipe()
                process.standardOutput = stdout
                process.standardError = stderr

                let stdoutBuffer = OutputLineBuffer()
                let stderrBuffer = OutputLineBuffer()
                var allOutput = ""
                var parsedLines: [DdevLogLine] = []
                let outputLock = NSLock()

                let handleLine: (String) -> Void = { line in
                    outputLock.lock()
                    allOutput += line + "\n"
                    outputLock.unlock()

                    guard let logLine = Self.parseNDJSONLine(line) else { return }
                    outputLock.lock()
                    parsedLines.append(logLine)
                    outputLock.unlock()
                    onLine(logLine)
                }

                let stdoutHandle = stdout.fileHandleForReading
                let stderrHandle = stderr.fileHandleForReading

                stdoutHandle.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
                    stdoutBuffer.append(chunk, onLine: handleLine)
                }

                stderrHandle.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
                    stderrBuffer.append(chunk, onLine: handleLine)
                }

                process.terminationHandler = { proc in
                    stdoutHandle.readabilityHandler = nil
                    stderrHandle.readabilityHandler = nil
                    stdoutBuffer.flush(onLine: handleLine)
                    stderrBuffer.flush(onLine: handleLine)

                    outputLock.lock()
                    let output = allOutput
                    let lines = parsedLines
                    outputLock.unlock()

                    let result = ProcessResult(exitCode: proc.terminationStatus, stdout: output, stderr: "")

                    if proc.terminationStatus == 0 {
                        continuation.resume(
                            returning: DdevActionOutput(
                                exitCode: result.exitCode,
                                lines: lines,
                                rawOutput: output
                            )
                        )
                    } else {
                        continuation.resume(
                            throwing: DdevCLIError.commandFailed(
                                Self.formatActionFailure(result, lines: lines)
                            )
                        )
                    }
                }

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func runProcess(_ arguments: [String]) async throws -> ProcessResult {
        guard let ddevPath else {
            throw DdevCLIError.ddevNotFound
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: ddevPath)
                    process.arguments = arguments
                    process.environment = Self.processEnvironment()

                    let stdout = Pipe()
                    let stderr = Pipe()
                    process.standardOutput = stdout
                    process.standardError = stderr

                    try process.run()
                    process.waitUntilExit()

                    let stdoutText = String(
                        data: stdout.fileHandleForReading.readDataToEndOfFile(),
                        encoding: .utf8
                    ) ?? ""
                    let stderrText = String(
                        data: stderr.fileHandleForReading.readDataToEndOfFile(),
                        encoding: .utf8
                    ) ?? ""

                    continuation.resume(
                        returning: ProcessResult(
                            exitCode: process.terminationStatus,
                            stdout: stdoutText,
                            stderr: stderrText
                        )
                    )
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func runRaw(_ arguments: [String]) async throws -> Data {
        let result = try await runProcess(arguments)

        guard result.exitCode == 0 else {
            throw DdevCLIError.commandFailed(
                result.combinedOutput.isEmpty ? "DDEV command failed." : result.combinedOutput
            )
        }

        return Data(result.stdout.utf8)
    }

    private static func parseNDJSONLine(_ line: String) -> DdevLogLine? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let level = json["level"] as? String,
              let message = json["msg"] as? String else {
            return nil
        }
        return DdevLogLine(level: level, message: message)
    }

    private static func parseNDJSONLines(_ text: String) -> [DdevLogLine] {
        text
            .split(whereSeparator: \.isNewline)
            .compactMap { parseNDJSONLine(String($0)) }
    }

    private static func formatActionFailure(_ result: ProcessResult, lines: [DdevLogLine]) -> String {
        var parts: [String] = lines
            .filter { $0.level == "error" || $0.level == "fatal" || $0.level == "warning" }
            .map(\.message)

        if parts.isEmpty, !result.combinedOutput.isEmpty {
            parts = [result.combinedOutput]
        }

        if parts.isEmpty {
            return "DDEV command failed with exit code \(result.exitCode)."
        }

        return parts.joined(separator: "\n")
    }

    private static func processEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["HOME"] = environment["HOME"] ?? NSHomeDirectory()
        environment["USER"] = environment["USER"] ?? NSUserName()
        environment["DDEV_NO_TUI"] = "true"

        let pathEntries = (environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
            .split(separator: ":")
            .map(String.init)
        let standardPaths = [
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/local/sbin",
        ]
        var seen = Set<String>()
        environment["PATH"] = (standardPaths + pathEntries)
            .filter { seen.insert($0).inserted }
            .joined(separator: ":")

        return environment
    }

    private static func locateDdev() -> String? {
        let home = NSHomeDirectory()
        let candidates = [
            "/opt/homebrew/bin/ddev",
            "/usr/local/bin/ddev",
            "\(home)/.ddev/bin/ddev",
        ]

        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["ddev"]
        process.environment = processEnvironment()

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let path = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let path, !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) else {
                return nil
            }
            return path
        } catch {
            return nil
        }
    }
}
