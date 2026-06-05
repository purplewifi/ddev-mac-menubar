import Foundation
import UserNotifications

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }
}

@MainActor
final class NotificationService {
    static let shared = NotificationService()

    func configure() {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
    }

    func requestAuthorizationIfNeeded() async {
        _ = await ensureAuthorized()
    }

    func notifyProjectsReady(
        projectNames: [String],
        restarted: Bool,
        url: String?
    ) async {
        guard await ensureAuthorized() else { return }

        let title: String
        let body: String

        switch projectNames.count {
        case 0:
            return
        case 1:
            let name = projectNames[0]
            title = restarted ? "\(name) restarted" : "\(name) is ready"
            if let url {
                body = url
            } else {
                body = restarted ? "Your project is back up and running." : "Your project started successfully."
            }
        default:
            title = restarted
                ? "\(projectNames.count) projects restarted"
                : "\(projectNames.count) projects started"
            body = projectNames.joined(separator: ", ")
        }

        await post(
            identifier: "ddev-ready-\(projectNames.joined(separator: "-"))-\(UUID().uuidString)",
            title: title,
            body: body
        )
    }

    func notifyProjectsFailed(
        projectNames: [String],
        restarted: Bool,
        message: String
    ) async {
        guard await ensureAuthorized() else { return }

        let title: String
        switch projectNames.count {
        case 0:
            title = restarted ? "Restart failed" : "Start failed"
        case 1:
            title = restarted
                ? "\(projectNames[0]) failed to restart"
                : "\(projectNames[0]) failed to start"
        default:
            title = restarted
                ? "\(projectNames.count) projects failed to restart"
                : "\(projectNames.count) projects failed to start"
        }

        let body = message
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init) ?? message
        let trimmed = body.count > 200 ? String(body.prefix(199)) + "…" : body

        await post(
            identifier: "ddev-failed-\(projectNames.joined(separator: "-"))-\(UUID().uuidString)",
            title: title,
            body: trimmed
        )
    }

    private func ensureAuthorized() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
        default:
            return false
        }
    }

    private func post(identifier: String, title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            // Fall back to immediate delivery if the trigger is rejected.
            let immediate = UNNotificationRequest(
                identifier: identifier + "-immediate",
                content: content,
                trigger: nil
            )
            try? await UNUserNotificationCenter.current().add(immediate)
        }
    }
}
