import SwiftUI

struct LogViewerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: LogViewerModel

    private let services = ["web", "db"]

    init(session: LogSession) {
        _model = State(initialValue: LogViewerModel(session: session))
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            logOutput
            Divider()
            statusBar
        }
        .frame(minWidth: 720, minHeight: 480)
        .navigationTitle("Logs — \(model.windowTitle)")
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Picker("Service", selection: Binding(
                get: { model.service },
                set: { model.setService($0) }
            )) {
                ForEach(services, id: \.self) { service in
                    Text(service).tag(service)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 160)

            Toggle("Tail", isOn: Binding(
                get: { model.isFollowing },
                set: { model.setFollowing($0) }
            ))

            Toggle("Auto-scroll", isOn: $model.autoScroll)

            Spacer()

            Button("Clear") {
                model.clear()
            }

            Button("Reconnect") {
                model.reconnect()
            }

            Button("Close") {
                dismiss()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var logOutput: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(model.text.isEmpty ? "Waiting for log output…" : model.text)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(model.text.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .id("log-bottom")
            }
            .background(Color(nsColor: .textBackgroundColor))
            .onChange(of: model.text) { _, _ in
                guard model.autoScroll else { return }
                proxy.scrollTo("log-bottom", anchor: .bottom)
            }
        }
    }

    private var statusBar: some View {
        HStack {
            if model.isStreaming {
                ProgressView()
                    .controlSize(.small)
            }

            Text(model.status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            Text("\(model.text.count.formatted()) characters")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

#Preview {
    LogViewerView(session: LogSession(projectName: "portal", approot: "/Users/alan/Projects/portal"))
}
