import SwiftUI

struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    @Bindable var store: DdevProjectStore
    @EnvironmentObject private var updater: UpdaterController
    @State private var showAppInfo = false

    var body: some View {
        VStack(spacing: 0) {
            header
            tabPicker
            Divider()

            if !store.ddevAvailable {
                unavailableView
            } else if store.isLoading && store.projects.isEmpty {
                loadingView
            } else {
                mainContent
            }

            if let startupProgress = store.startupProgress {
                Divider()
                StartupProgressView(progress: startupProgress)
            }

            if let activityMessage = store.activityMessage {
                Divider()
                ActionStatusBar(
                    message: activityMessage,
                    showsProgress: store.isPerformingAction || store.isRefreshing,
                    isError: false
                )
            } else if store.startupProgress == nil, let statusMessage = store.statusMessage {
                Divider()
                ActionStatusBar(
                    message: statusMessage,
                    showsProgress: false,
                    isError: store.actionReport != nil || statusMessage.contains("not found")
                )
            }

            Divider()
            footer
        }
        .frame(width: 420)
        .frame(minHeight: 520)
        .onAppear {
            store.setMenuPresented(true)
            store.startAutoRefresh()
            Task {
                await NotificationService.shared.requestAuthorizationIfNeeded()
                await store.refreshProjects()
            }
        }
        .onDisappear {
            store.setMenuPresented(false)
            store.stopAutoRefresh()
        }
        .onChange(of: store.logOpenNonce) { _, _ in
            guard let session = store.pendingLogSession else { return }
            AppActivation.showLogWindow()
            openWindow(id: "logs", value: session)
        }
        .sheet(isPresented: Binding(
            get: { store.actionReport != nil },
            set: { if !$0 { store.dismissActionReport() } }
        )) {
            if let report = store.actionReport {
                ActionReportView(store: store, report: report)
            }
        }
        .sheet(isPresented: $showAppInfo) {
            AppInfoView(
                ddevAvailable: store.ddevAvailable,
                ddevPath: store.ddevExecutablePath
            )
            .environmentObject(updater)
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        switch store.mainTab {
        case .groups:
            groupsContent
        case .projects:
            projectsContent
        }
    }

    @ViewBuilder
    private var groupsContent: some View {
        if store.isEditingGroup, let group = store.editingGroup {
            GroupEditorView(store: store, group: group)
                .id(group.id)
        } else if let group = store.selectedGroup {
            GroupDetailView(store: store, group: group)
        } else {
            GroupListView(store: store)
        }
    }

    @ViewBuilder
    private var projectsContent: some View {
        if store.selectedProjectName != nil && store.selectedDetail == nil {
            loadingDetailView
        } else if let detail = store.selectedDetail {
            ProjectDetailView(store: store, detail: detail)
        } else {
            projectBrowser
        }
    }

    private var projectBrowser: some View {
        VStack(spacing: 0) {
            projectSearchField
            Divider()

            if store.filteredProjects.isEmpty {
                emptyProjectsView
            } else {
                projectList
            }
        }
    }

    private var header: some View {
        HStack {
            Label("DDEV", systemImage: "shippingbox.fill")
                .font(.headline)

            Spacer()

            if store.isLoading && store.projects.isEmpty {
                ProgressView()
                    .controlSize(.small)
            }

            Text("\(store.runningCount) running · \(store.projects.count) total")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var tabPicker: some View {
        Picker("View", selection: Binding(
            get: { store.mainTab },
            set: { store.selectTab($0) }
        )) {
            ForEach(MainTab.allCases) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var projectSearchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Filter projects…", text: $store.searchText)
                .textFieldStyle(.plain)

            if !store.searchText.isEmpty {
                Button {
                    store.searchText = ""
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

    private var projectList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(store.filteredProjects) { project in
                    ProjectRowView(
                        store: store,
                        project: project,
                        isSelected: store.selectedProjectName == project.name
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        store.selectProject(project.name)
                    }

                    if project.id != store.filteredProjects.last?.id {
                        Divider()
                            .padding(.leading, 12)
                    }
                }
            }
            .transaction { $0.animation = nil }
        }
        .frame(maxHeight: 360)
    }

    private var loadingDetailView: some View {
        VStack(spacing: 12) {
            ProgressView()
            if let name = store.selectedProjectName {
                Text("Loading \(name)…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("Cancel") {
                store.selectProject(nil)
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, minHeight: 280, maxHeight: 320)
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading DDEV projects…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 280, maxHeight: 320)
    }

    private var unavailableView: some View {
        ContentUnavailableView {
            Label("DDEV Not Found", systemImage: "exclamationmark.triangle")
        } description: {
            Text("Install DDEV or ensure it is available in your shell PATH.")
        }
        .frame(maxHeight: 320)
    }

    private var emptyProjectsView: some View {
        ContentUnavailableView {
            Label("No Projects", systemImage: "tray")
        } description: {
            Text(store.searchText.isEmpty
                 ? "No DDEV projects were found on this machine."
                 : "No projects match your filter.")
        }
        .frame(maxHeight: 320)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let lastRefreshed = store.lastRefreshed {
                    Text("Updated \(lastRefreshed.formatted(date: .omitted, time: .standard))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer()
            }

            HStack {
                if store.mainTab == .groups && !store.isEditingGroup && store.selectedGroup == nil {
                    Button("New Group") {
                        store.beginCreateGroup()
                    }
                    .disabled(store.isPerformingAction)
                }

                Button("Refresh") {
                    Task { await store.refreshProjects(showActivity: true) }
                }
                .disabled(store.isLoading || store.isPerformingAction || store.isRefreshing)

                Button("Auth SSH") {
                    store.authSSHInTerminal()
                }
                .disabled(store.isPerformingAction)

                Spacer()

                Button {
                    showAppInfo = true
                } label: {
                    Image(systemName: "info.circle")
                }
                .help("About DDEV Menubar")

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

#Preview {
    MenuBarView(store: DdevProjectStore())
}
