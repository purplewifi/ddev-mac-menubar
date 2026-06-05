import SwiftUI

struct ProjectRowView: View {
    @Environment(\.openWindow) private var openWindow
    @Bindable var store: DdevProjectStore

    let project: DdevProject
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            StatusIndicator(isRunning: project.isRunning, statusDesc: project.statusDesc)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(project.name)
                        .font(.body.weight(.medium))
                        .lineLimit(1)

                    Spacer()

                    Text(project.statusDesc)
                        .font(.caption)
                        .foregroundStyle(project.isRunning ? .green : .secondary)
                }

                Text(project.shortroot)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let primaryURL = project.primaryURL {
                    Text(primaryURL)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            projectActions
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
    }

    private var projectActions: some View {
        Menu {
            if project.isRunning {
                Button("Open Site") {
                    store.openPrimaryURL(for: project)
                }
                Button("Open Mailpit") {
                    store.openMailpit(for: project)
                }
                Divider()
                Button("Stop") {
                    Task { await store.stopProject(project.name) }
                }
                Button("Restart") {
                    Task { await store.restartProject(project.name) }
                }
            } else {
                Button("Start") {
                    Task { await store.startProject(project.name) }
                }
            }

            Divider()

            Button("Show Details") {
                store.selectProject(project.name)
            }
            Button("Reveal in Finder") {
                store.revealInFinder(project)
            }
            Button("SSH") {
                store.sshIntoProject(project.name, approot: project.approot)
            }
            Button("Logs") {
                openWindow(value: store.showLogs(for: project.name, approot: project.approot))
            }
            Button("Logs in Terminal") {
                store.showLogsInTerminal(for: project.name, approot: project.approot)
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

private struct StatusIndicator: View {
    let isRunning: Bool
    let statusDesc: String

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .padding(.top, 5)
            .help(statusDesc)
    }

    private var color: Color {
        if isRunning {
            .green
        } else if statusDesc.localizedCaseInsensitiveContains("unhealthy") {
            .orange
        } else {
            .secondary.opacity(0.5)
        }
    }
}

#Preview {
    ProjectRowView(
        store: DdevProjectStore(),
        project: DdevProject(
            name: "portal",
            approot: "/Users/alan/Projects/portal",
            shortroot: "~/Projects/portal",
            status: "running",
            statusDesc: "running",
            type: "laravel",
            primaryURL: "https://portal.ddev.site",
            httpURL: "http://portal.ddev.site",
            httpsURL: "https://portal.ddev.site",
            mailpitURL: "http://portal.ddev.site:8025",
            nodejsVersion: "24",
            docroot: "public",
            mutagenEnabled: true,
            mutagenStatus: "ok"
        ),
        isSelected: false
    )
    .frame(width: 360)
}
