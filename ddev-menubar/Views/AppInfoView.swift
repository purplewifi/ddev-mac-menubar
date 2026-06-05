import SwiftUI

struct AppInfoView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var updater: UpdaterController

    let ddevAvailable: Bool
    let ddevPath: String?

    @State private var ddevVersion: DdevVersionInfo?
    @State private var versionError: String?
    @State private var isLoadingVersion = false

    private let cli = DdevCLI.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            VStack(alignment: .leading, spacing: 16) {
                appSection
                Divider()
                ddevSection
            }
            .padding(16)
            Spacer(minLength: 0)
            Divider()
            footer
        }
        .frame(width: 360)
        .task {
            await loadDdevVersion()
        }
    }

    private var header: some View {
        HStack {
            Label("About", systemImage: "info.circle")
                .font(.headline)
            Spacer()
            Button("Close") {
                dismiss()
            }
        }
        .padding(16)
    }

    private var appSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("DDEV Menubar")
                .font(.subheadline.weight(.semibold))

            infoRow("Version", AppVersionInfo.fullVersion)
        }
    }

    private var ddevSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("DDEV")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if isLoadingVersion {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading DDEV version…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let ddevVersion {
                infoRow("Version", ddevVersion.ddevVersion)

                if let ddevPath {
                    infoRow("Path", ddevPath, monospaced: true)
                }

                if let details = dockerDetails(for: ddevVersion) {
                    infoRow("Runtime", details)
                }
            } else if !ddevAvailable {
                Text("DDEV not found on this machine.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let versionError {
                Text(versionError)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Check for Updates…") {
                updater.checkForUpdates()
            }
            .disabled(!updater.canCheckForUpdates)

            Spacer()

            Button("Done") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }

    private func infoRow(_ label: String, _ value: String, monospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(monospaced ? .caption.monospaced() : .caption)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func dockerDetails(for version: DdevVersionInfo) -> String? {
        var parts: [String] = []
        if let docker = version.docker {
            parts.append("Docker \(docker)")
        }
        if let platform = version.dockerPlatform {
            parts.append(platform)
        }
        if let compose = version.dockerCompose {
            parts.append("Compose \(compose)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func loadDdevVersion() async {
        guard ddevAvailable else { return }

        isLoadingVersion = true
        defer { isLoadingVersion = false }

        do {
            ddevVersion = try await cli.versionInfo()
            versionError = nil
        } catch {
            ddevVersion = nil
            versionError = error.localizedDescription
        }
    }
}

#Preview {
    AppInfoView(ddevAvailable: true, ddevPath: "/opt/homebrew/bin/ddev")
        .environmentObject(UpdaterController())
}
