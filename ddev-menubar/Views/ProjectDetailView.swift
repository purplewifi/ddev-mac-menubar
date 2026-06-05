import SwiftUI

struct ProjectDetailView: View {
    @Bindable var store: DdevProjectStore

    let detail: DdevProjectDetail

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button {
                    store.selectProject(nil)
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Text(detail.name)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                Text(detail.statusDesc)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(detail.status == "running" ? .green : .secondary)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    detailGrid

                    if let services = sortedServices, !services.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Services")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)

                            ForEach(services, id: \.name) { service in
                                HStack {
                                    Text(service.name)
                                        .font(.caption.monospaced())
                                    Spacer()
                                    Text(service.status ?? "unknown")
                                        .font(.caption)
                                        .foregroundStyle(service.status == "running" ? .green : .secondary)
                                }
                            }
                        }
                    }

                    if let urls = detail.urls?.prefix(4), !urls.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("URLs")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)

                            ForEach(Array(urls), id: \.self) { urlString in
                                if let url = URL(string: urlString) {
                                    Link(urlString, destination: url)
                                        .font(.caption)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                }
            }
            .frame(minHeight: 240, maxHeight: 280)

            actionButtons
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var detailGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
            if let type = nonEmpty(detail.type) {
                detailRow("Type", type)
            }
            if let phpVersion = nonEmpty(detail.phpVersion) {
                detailRow("PHP", phpVersion)
            }
            if let webserver = nonEmpty(detail.webserverType) {
                detailRow("Web", webserver)
            }
            if let node = nonEmpty(detail.nodejsVersion) {
                detailRow("Node", node)
            }
            if let databaseType = nonEmpty(detail.databaseType) {
                let version = detail.databaseVersion.map { " \($0)" } ?? ""
                detailRow("Database", databaseType + version)
            }
            if let performanceMode = nonEmpty(detail.performanceMode) {
                detailRow("Performance", performanceMode)
            }
            if detail.xdebugEnabled != nil {
                GridRow {
                    Text("Xdebug")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Toggle(
                        detail.xdebugEnabled == true ? "On" : "Off",
                        isOn: Binding(
                            get: { detail.xdebugEnabled == true },
                            set: { enabled in
                                Task { await store.setXdebug(for: detail.name, enabled: enabled) }
                            }
                        )
                    )
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                    .disabled(store.isPerformingAction)
                }
            }
            if let port = detail.dbinfo?.publishedPort {
                detailRow("DB Port", String(port))
            }
        }
    }

    private var actionButtons: some View {
        HStack {
            if detail.status == "running" {
                Button("Open") {
                    if let project = store.selectedProject {
                        store.openPrimaryURL(for: project)
                    }
                }
                Button("Stop") {
                    Task { await store.stopProject(detail.name) }
                }
                Button("Restart") {
                    Task { await store.restartProject(detail.name) }
                }
            } else {
                Button("Start") {
                    Task { await store.startProject(detail.name) }
                }
            }

            Spacer()

            Button("Logs") {
                store.requestLogs(
                    for: detail.name,
                    approot: detail.approot,
                    projectType: detail.type
                )
            }

            Button("SSH") {
                store.sshIntoProject(detail.name, approot: detail.approot)
            }
        }
        .controlSize(.small)
        .disabled(store.isPerformingAction)
    }

    private var sortedServices: [(name: String, status: String?)]? {
        guard let services = detail.services else { return nil }

        let priority = ["web", "db"]
        return services
            .map { (name: $0.key, status: $0.value.status) }
            .sorted { lhs, rhs in
                let leftIndex = priority.firstIndex(of: lhs.name) ?? Int.max
                let rightIndex = priority.firstIndex(of: rhs.name) ?? Int.max
                if leftIndex != rightIndex {
                    return leftIndex < rightIndex
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospaced())
        }
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}
