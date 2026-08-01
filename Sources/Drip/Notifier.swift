import Foundation
import UserNotifications
import DripCore

/// macOS banners for the "Notification" style. Only works when running from the .app bundle.
final class Notifier: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    enum Action { case done, snooze }

    /// Action plus the habit the banner was about.
    var onAction: ((Action, HabitKind) -> Void)?
    /// Published on the main queue so Settings' warning appears as soon as we learn it.
    @Published private(set) var denied = false

    /// UNUserNotificationCenter crashes outside an app bundle (e.g. `swift run`).
    var available: Bool { Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil }

    func setup() {
        guard available else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let done = UNNotificationAction(identifier: "DONE", title: "Done ✅", options: [])
        let snooze = UNNotificationAction(identifier: "SNOOZE", title: snoozeLabel, options: [])
        center.setNotificationCategories([UNNotificationCategory(identifier: "REMINDER", actions: [done, snooze],
                                                                 intentIdentifiers: [], options: [])])
        center.getNotificationSettings { s in
            let denied = s.authorizationStatus == .denied
            DispatchQueue.main.async { self.denied = denied }
        }
    }

    func requestAuthorization() {
        guard available else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async { self.denied = !granted }
        }
    }

    func post(kind: HabitKind, body: String) {
        guard available else { return }
        let content = UNMutableNotificationContent()
        content.title = "\(kind.emoji) \(kind.title)"
        content.body = body
        content.categoryIdentifier = "REMINDER"
        content.sound = .default
        content.userInfo = ["kind": kind.rawValue]
        let req = UNNotificationRequest(identifier: "drip-\(kind.rawValue)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    /// Once a reminder is handled in-app, its banner shouldn't linger in Notification Center.
    func clear(kind: HabitKind) {
        guard available else { return }
        let id = "drip-\(kind.rawValue)"
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id])
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completion: @escaping (UNNotificationPresentationOptions) -> Void) {
        completion([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completion: @escaping () -> Void) {
        let kind = (response.notification.request.content.userInfo["kind"] as? String).flatMap(HabitKind.init(rawValue:))
        if let kind {
            switch response.actionIdentifier {
            case "DONE": onAction?(.done, kind)
            case "SNOOZE": onAction?(.snooze, kind)
            default: break
            }
        }
        completion()
    }
}
