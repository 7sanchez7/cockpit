import Foundation
import UserNotifications
import os

/// Notifications macOS. Hors d'une app empaquetée (`swift test`, `make essai`), elles ne partent pas.
enum Notifs {
    private static let log = Logger(subsystem: "com.tonysanchez.cockpit", category: "notifs")
    private static var disponible: Bool { Bundle.main.bundleIdentifier != nil }

    static func autoriser() {
        guard disponible else { return }
        Task {
            do {
                _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            } catch {
                log.error("autorisation refusée : \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    static func envoyer(titre: String, corps: String, id: String) {
        guard disponible else { return }
        let contenu = UNMutableNotificationContent()
        contenu.title = titre
        contenu.body = corps
        contenu.sound = .default
        Task {
            do {
                try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: contenu, trigger: nil))
            } catch {
                log.error("notification perdue : \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
