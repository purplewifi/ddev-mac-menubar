import SwiftUI

struct GroupDetailView: View {
    @Bindable var store: DdevProjectStore

    let group: DdevProjectGroup

    private var status: DdevGroupStatus {
        store.groupStatus(group)
    }

    private var groupProjects: [DdevProject] {
        store.projects(in: group)
    }

    private var missingProjects: [String] {
        let known = Set(groupProjects.map(\.name))
        return group.projectNames.filter { !known.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button {
                    store.selectGroup(nil)
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Text(group.name)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                Text(status.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Start All") {
                    Task { await store.startGroup(group) }
                }
                .disabled(status.allRunning || status.total == 0 || store.isPerformingAction)

                Button("Stop All") {
                    Task { await store.stopGroup(group) }
                }
                .disabled(status.allStopped || status.running == 0 || store.isPerformingAction)

                Button("Restart") {
                    Task { await store.restartGroup(group) }
                }
                .disabled(status.total == 0 || store.isPerformingAction)

                Spacer()

                Button("Edit") {
                    store.beginEditGroup(group)
                }
                .disabled(store.isPerformingAction)
            }
            .controlSize(.small)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(groupProjects) { project in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(project.isRunning ? Color.green : Color.secondary.opacity(0.5))
                                .frame(width: 8, height: 8)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(project.name)
                                    .font(.caption.weight(.medium))
                                Text(project.statusDesc)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button("Details") {
                                store.openProjectFromGroup(project.name)
                            }
                            .controlSize(.mini)
                        }
                        .padding(.vertical, 6)

                        if project.id != groupProjects.last?.id {
                            Divider()
                        }
                    }

                    ForEach(missingProjects, id: \.self) { name in
                        Divider()
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 8, height: 8)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(name)
                                    .font(.caption.weight(.medium))
                                Text("Not found on this machine")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }

                            Spacer()
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
            .frame(minHeight: 280, maxHeight: 320)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
