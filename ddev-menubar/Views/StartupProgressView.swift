import SwiftUI

struct StartupProgressView: View {
    let progress: StartupProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if progress.isMultiProject {
                multiProjectList
            } else {
                singleProjectSteps
            }

            if let note = progress.note {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.accentColor.opacity(0.07))
    }

    private var header: some View {
        HStack(spacing: 8) {
            if progress.isFinished {
                Image(systemName: progress.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(progress.succeeded ? .green : .orange)
            } else {
                ProgressView()
                    .controlSize(.small)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(progress.title)
                    .font(.subheadline.weight(.semibold))

                if progress.isMultiProject {
                    Text(progressSubtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
    }

    private var progressSubtitle: String {
        let total = progress.projects.count
        let done = progress.completedCount
        switch progress.kind {
        case .stop:
            return "\(done) of \(total) stopped"
        case .start, .restart:
            return "\(done) of \(total) ready"
        }
    }

    private var multiProjectList: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(progress.projects) { project in
                HStack(spacing: 8) {
                    stepIcon(for: project.status)
                        .frame(width: 14)

                    Text(project.name)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Text(project.label)
                        .font(.caption2)
                        .foregroundStyle(labelColor(for: project.status))
                        .lineLimit(1)
                }
            }
        }
    }

    private var singleProjectSteps: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(visibleSteps) { step in
                HStack(spacing: 8) {
                    stepIcon(for: step.status)
                        .frame(width: 14)

                    Text(step.label)
                        .font(.caption)
                        .foregroundStyle(labelColor(for: step.status))
                }
            }
        }
    }

    private var visibleSteps: [StartupStep] {
        guard let lastActiveIndex = progress.steps.lastIndex(where: {
            $0.status == .active || $0.status == .complete || $0.status == .failed || $0.status == .warning
        }) else {
            return Array(progress.steps.prefix(1))
        }

        return Array(progress.steps.prefix(lastActiveIndex + 1))
    }

    @ViewBuilder
    private func stepIcon(for status: StartupStep.Status) -> some View {
        switch status {
        case .pending:
            Image(systemName: "circle")
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
        case .active:
            Image(systemName: "circle.inset.filled")
                .font(.system(size: 8))
                .foregroundStyle(.tint)
        case .complete:
            Image(systemName: "checkmark")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.green)
        case .warning:
            Image(systemName: "exclamationmark")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.orange)
        case .failed:
            Image(systemName: "xmark")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.orange)
        }
    }

    private func labelColor(for status: StartupStep.Status) -> Color {
        switch status {
        case .pending:
            .secondary.opacity(0.55)
        case .active:
            .primary
        case .complete:
            .secondary
        case .warning, .failed:
            .primary
        }
    }
}

#Preview("Multi") {
    StartupProgressView(
        progress: StartupProgress(
            kind: .start,
            title: "Starting Purple Stack",
            projectNames: ["portal", "api", "cms"],
            projects: [
                ProjectProgressItem(name: "portal", label: "Syncing files", status: .active),
                ProjectProgressItem(name: "api", label: "Building", status: .active),
                ProjectProgressItem(name: "cms", label: "Ready", status: .complete),
            ],
            steps: [],
            note: "1 of 3 ready"
        )
    )
    .frame(width: 420)
}
