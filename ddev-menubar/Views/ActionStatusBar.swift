import SwiftUI

struct ActionStatusBar: View {
    let message: String
    let showsProgress: Bool
    let isError: Bool

    var body: some View {
        HStack(spacing: 8) {
            if showsProgress {
                ProgressView()
                    .controlSize(.small)
            } else if isError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }

            Text(message)
                .font(.caption)
                .foregroundStyle(isError ? .primary : .secondary)
                .lineLimit(2)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(backgroundColor)
    }

    private var backgroundColor: Color {
        if isError {
            Color.orange.opacity(0.12)
        } else if showsProgress {
            Color.accentColor.opacity(0.1)
        } else {
            Color(nsColor: .controlBackgroundColor)
        }
    }
}
