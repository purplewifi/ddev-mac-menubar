import AppKit
import Foundation

enum TerminalLauncherError: LocalizedError {
    case scriptWriteFailed(String)

    var errorDescription: String? {
        switch self {
        case .scriptWriteFailed(let message):
            message
        }
    }
}

struct TerminalLauncher: Sendable {
    func open(command: String, workingDirectory: String? = nil) throws {
        var lines = [
            "#!/bin/zsh",
            "export PATH=\"/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:$PATH\"",
        ]

        if let workingDirectory {
            lines.append("cd \(workingDirectory.shellSingleQuoted)")
        }

        lines.append(command)

        let script = lines.joined(separator: "\n") + "\n"
        let fileName = "ddev-menubar-\(UUID().uuidString).command"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        do {
            try script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        } catch {
            throw TerminalLauncherError.scriptWriteFailed(
                "Could not prepare Terminal script: \(error.localizedDescription)"
            )
        }

        guard NSWorkspace.shared.open(url) else {
            throw TerminalLauncherError.scriptWriteFailed("Could not open Terminal.")
        }
    }
}

extension String {
    var shellSingleQuoted: String {
        "'\(replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
