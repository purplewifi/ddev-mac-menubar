import SwiftUI

struct GroupEditorView: View {
    @Bindable var store: DdevProjectStore

    @State private var draft: DdevProjectGroup
    @State private var projectFilter = ""

    init(store: DdevProjectStore, group: DdevProjectGroup) {
        self.store = store
        _draft = State(initialValue: group)
    }

    private var filteredProjects: [DdevProject] {
        let query = projectFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return store.projects }

        return store.projects.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.shortroot.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button {
                    store.cancelGroupEditing()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Text(draft.name.isEmpty ? "New Group" : "Edit Group")
                    .font(.headline)
            }

            TextField("Group name", text: $draft.name)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Filter projects to add…", text: $projectFilter)
                    .textFieldStyle(.plain)
            }

            Text("\(draft.projectNames.count) selected")
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(filteredProjects) { project in
                        Toggle(isOn: binding(for: project.name)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(project.name)
                                    .font(.caption.weight(.medium))
                                Text(project.shortroot)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.checkbox)
                        .padding(.vertical, 4)

                        if project.id != filteredProjects.last?.id {
                            Divider()
                        }
                    }
                }
            }
            .frame(minHeight: 340, maxHeight: 380)

            HStack {
                Button("Save") {
                    store.saveGroup(draft)
                }
                .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          || draft.projectNames.isEmpty
                          || store.isPerformingAction)

                if groupsContainDraft {
                    Button("Delete", role: .destructive) {
                        store.deleteGroup(draft)
                    }
                }

                Spacer()

                Button("Cancel") {
                    store.cancelGroupEditing()
                }
            }
            .controlSize(.small)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var groupsContainDraft: Bool {
        store.groups.contains { $0.id == draft.id }
    }

    private func binding(for projectName: String) -> Binding<Bool> {
        Binding(
            get: { draft.projectNames.contains(projectName) },
            set: { isSelected in
                if isSelected {
                    if !draft.projectNames.contains(projectName) {
                        draft.projectNames.append(projectName)
                    }
                } else {
                    draft.projectNames.removeAll { $0 == projectName }
                }
            }
        )
    }
}
