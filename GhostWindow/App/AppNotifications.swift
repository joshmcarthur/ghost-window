import Foundation
import UserNotifications

enum AppNotifications {
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                GhostLogger.log("Notification authorization error: \(error.localizedDescription)")
            } else {
                GhostLogger.log("Notification authorization granted: \(granted)")
            }
        }
    }

    static func notify(_ body: String) {
        let content = UNMutableNotificationContent()
        content.title = "Ghost Window"
        content.body = body
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                GhostLogger.log("Notification failed: \(error.localizedDescription)")
            }
        }
    }
}
