import SwiftUI

struct ActionReportView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: DdevProjectStore

    let report: DdevActionReport

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !report.serviceIssues.isEmpty {
                        section("Failed services") {
                            ForEach(report.serviceIssues) { issue in
                                HStack {
                                    Text("\(issue.projectName) / \(issue.serviceName)")
                                        .font(.caption.monospaced())
                                    Spacer()
                                    Text(issue.status)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                    }

                    if !report.messages.isEmpty {
                        section("Messages") {
                            ForEach(Array(report.messages.enumerated()), id: \.offset) { _, message in
                                Text(message)
                                    .font(.caption)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }

                    if !report.logExcerpts.isEmpty {
                        section("Recent logs") {
                            ForEach(report.logExcerpts) { excerpt in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(excerpt.projectName) · \(excerpt.serviceName)")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)

                                    Text(excerpt.text)
                                        .font(.system(.caption2, design: .monospaced))
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(8)
                                        .background(Color(nsColor: .textBackgroundColor))
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                            }
                        }
                    }

                    if !report.hints.isEmpty {
                        section("Suggestions") {
                            ForEach(report.hints, id: \.self) { hint in
                                Label(hint, systemImage: "lightbulb")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
                .padding(16)
            }
            Divider()
            footer
        }
        .frame(width: 560, height: 480)
    }

    private var header: some View {
        HStack {
            Text(report.title)
                .font(.headline)
            Spacer()
            Button("Close") {
                store.dismissActionReport()
                dismiss()
            }
        }
        .padding(16)
    }

    private var footer: some View {
        HStack {
            if let name = report.projectNames.first,
               let project = store.projects.first(where: { $0.name == name }) {
                Button("View Logs") {
                    store.requestLogs(
                        for: name,
                        approot: project.approot,
                        projectType: project.type
                    )
                }
            }

            Button("Auth SSH") {
                store.authSSHInTerminal()
            }

            Spacer()

            Button("Done") {
                store.dismissActionReport()
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }
}
