import SwiftUI

struct LogViewerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: LogViewerModel

    init(session: LogSession) {
        _model = State(initialValue: LogViewerModel(session: session))
    }

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            toolbar
            if model.selectedTab?.isCustom == true {
                customPathBar
                Divider()
            }
            logOutput
            Divider()
            statusBar
        }
        .frame(minWidth: 720, minHeight: 480)
        .navigationTitle("Logs — \(model.windowTitle)")
        .onAppear {
            AppActivation.showLogWindow()
            model.start()
        }
        .onDisappear {
            model.stop()
            AppActivation.restoreMenuBarOnlyIfNeeded()
        }
    }

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(model.tabs) { tab in
                    Button(tab.label) {
                        model.selectTab(tab.id)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(model.selectedTabID == tab.id ? .accentColor : .secondary)
                    .background(
                        model.selectedTabID == tab.id
                            ? Color.accentColor.opacity(0.15)
                            : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6)
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
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

    private var customPathBar: some View {
        HStack(spacing: 8) {
            Text("Path")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("storage/logs/laravel.log", text: Binding(
                get: { model.customLogPath },
                set: { model.setCustomLogPath($0) }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.system(.caption, design: .monospaced))
            .onSubmit {
                model.applyCustomLogPath()
            }

            Button("Tail") {
                model.applyCustomLogPath()
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var logOutput: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(placeholderText)
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

    private var placeholderText: String {
        if !model.text.isEmpty {
            return model.text
        }

        if model.selectedTab?.isCustom == true,
           model.customLogPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Enter a log file path above, then click Tail."
        }

        return "Waiting for log output…"
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
    LogViewerView(
        session: LogSession(
            projectName: "portal",
            approot: "/Users/alan/Projects/portal",
            projectType: "laravel"
        )
    )
}
