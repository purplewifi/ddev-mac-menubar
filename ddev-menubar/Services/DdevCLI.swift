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

    func startProject(_ name: String) async throws {
        try await startProjects([name])
    }

    func stopProject(_ name: String) async throws {
        try await stopProjects([name])
    }

    func restartProject(_ name: String) async throws {
        try await restartProjects([name])
    }

    func startProjects(_ names: [String]) async throws {
        guard !names.isEmpty else { return }
        _ = try await runRaw(["start"] + names + ["-j", "-y"])
    }

    func stopProjects(_ names: [String]) async throws {
        guard !names.isEmpty else { return }
        _ = try await runRaw(["stop"] + names + ["-j", "-y"])
    }

    func restartProjects(_ names: [String]) async throws {
        guard !names.isEmpty else { return }
        _ = try await runRaw(["restart"] + names + ["-j", "-y"])
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

    private func runRaw(_ arguments: [String]) async throws -> Data {
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

                    let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
                    let errorData = stderr.fileHandleForReading.readDataToEndOfFile()

                    guard process.terminationStatus == 0 else {
                        let message = String(data: errorData, encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        let fallback = String(data: outputData, encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        let combined = [message, fallback]
                            .compactMap { value in
                                guard let value, !value.isEmpty else { return nil }
                                return value
                            }
                            .joined(separator: "\n")
                        continuation.resume(
                            throwing: DdevCLIError.commandFailed(
                                combined.isEmpty ? "DDEV command failed." : combined
                            )
                        )
                        return
                    }

                    continuation.resume(returning: outputData)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
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
