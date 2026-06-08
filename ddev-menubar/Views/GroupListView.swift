import SwiftUI

struct GroupListView: View {
    @Bindable var store: DdevProjectStore

    var body: some View {
        VStack(spacing: 0) {
            groupSearchField
            Divider()

            if store.filteredGroups.isEmpty {
                emptyView
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(store.filteredGroups) { group in
                            GroupRowView(store: store, group: group)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    store.selectGroup(group.id)
                                }

                            if group.id != store.filteredGroups.last?.id {
                                Divider()
                                    .padding(.leading, 12)
                            }
                        }
                    }
                }
                .transaction { $0.animation = nil }
                .frame(maxHeight: 360)
            }
        }
    }

    private var groupSearchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Filter groups…", text: $store.groupSearchText)
                .textFieldStyle(.plain)

            if !store.groupSearchText.isEmpty {
                Button {
                    store.groupSearchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var emptyView: some View {
        ContentUnavailableView {
            Label("No Groups", systemImage: "folder")
        } description: {
            Text(store.groupSearchText.isEmpty
                 ? "Create a group to start related projects together."
                 : "No groups match your filter.")
        } actions: {
            if store.groupSearchText.isEmpty {
                Button("New Group") {
                    store.beginCreateGroup()
                }
            }
        }
        .frame(maxHeight: 320)
    }
}

struct GroupRowView: View {
    @Bindable var store: DdevProjectStore

    let group: DdevProjectGroup

    private var status: DdevGroupStatus {
        store.groupStatus(group)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "folder.fill")
                .foregroundStyle(status.allRunning ? .green : .secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 3) {
                Text(group.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)

                Text(status.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(group.projectNames.joined(separator: ", "))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            groupActions
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var groupActions: some View {
        Menu {
            Button("Start All") {
                Task { await store.startGroup(group) }
            }
            .disabled(status.allRunning || status.total == 0)

            Button("Stop All") {
                Task { await store.stopGroup(group) }
            }
            .disabled(status.allStopped || status.running == 0)

            Button("Restart All") {
                Task { await store.restartGroup(group) }
            }
            .disabled(status.total == 0)

            Divider()

            Button("View Group") {
                store.selectGroup(group.id)
            }
            Button("Edit Group…") {
                store.beginEditGroup(group)
            }
            Button("Duplicate Group") {
                store.duplicateGroup(group)
            }
            Button("Delete Group", role: .destructive) {
                store.deleteGroup(group)
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}
