import FirebaseAuth
import FirebaseFirestore
import FirebaseMessaging
import Foundation
import UIKit
import UserNotifications

/// Stores a push token only after an explicit in-app opt-in. The token is readable only by
/// trusted server code, never by other users or clients.
@MainActor
final class PushNotificationService: NSObject, ObservableObject, MessagingDelegate {
    static let shared = PushNotificationService()

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var isEnabledForCurrentUser = false
    @Published var errorMessage: String?

    private let notificationCenter = UNUserNotificationCenter.current()
    private var activeUserId: String?

    private override init() {}

    func configure() {
        Messaging.messaging().delegate = self
    }

    func load(for uid: String) async {
        activeUserId = uid
        isEnabledForCurrentUser = UserDefaults.standard.bool(forKey: preferenceKey(for: uid))
        authorizationStatus = await notificationCenter.notificationSettings().authorizationStatus
        if isEnabledForCurrentUser, let token = Messaging.messaging().fcmToken {
            await persist(token: token, for: uid)
        }
    }

    func enable(for uid: String) async {
        errorMessage = nil
        activeUserId = uid
        #if targetEnvironment(simulator)
        errorMessage = "Push-Benachrichtigungen werden erst auf einem echten iPhone mit Firebase- und APNs-Konfiguration aktiviert. Im Simulator bleibt dieser Test bewusst lokal."
        return
        #else
        do {
            var settings = await notificationCenter.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                let granted = try await notificationCenter.requestAuthorization(options: [.alert, .badge, .sound])
                guard granted else { throw PushNotificationError.permissionDenied }
                settings = await notificationCenter.notificationSettings()
            }
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                throw PushNotificationError.permissionDenied
            }

            UserDefaults.standard.set(true, forKey: preferenceKey(for: uid))
            isEnabledForCurrentUser = true
            authorizationStatus = settings.authorizationStatus
            UIApplication.shared.registerForRemoteNotifications()

            let token = try await Messaging.messaging().token()
            await persist(token: token, for: uid)
        } catch {
            errorMessage = error.localizedDescription
        }
        #endif
    }

    func disable(for uid: String) async {
        if let token = Messaging.messaging().fcmToken {
            try? await Firestore.firestore()
                .collection("users")
                .document(uid)
                .collection("deviceTokens")
                .document(token)
                .delete()
        }
        UserDefaults.standard.set(false, forKey: preferenceKey(for: uid))
        isEnabledForCurrentUser = false
    }

    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken else { return }
        Task { @MainActor [weak self] in
            guard let self, let uid = self.activeUserId ?? Auth.auth().currentUser?.uid,
                  UserDefaults.standard.bool(forKey: self.preferenceKey(for: uid)) else { return }
            await self.persist(token: fcmToken, for: uid)
        }
    }

    private func persist(token: String, for uid: String) async {
        do {
            try await Firestore.firestore()
                .collection("users")
                .document(uid)
                .collection("deviceTokens")
                .document(token)
                .setData([
                    "token": token,
                    "platform": "ios",
                    "updatedAt": Timestamp(date: Date()),
                ])
        } catch {
            // Token persistence must never prevent sign-in or a local app flow. The setting can
            // be retried when Firebase Messaging refreshes its token or the view is reopened.
            errorMessage = "Push-Einstellung konnte nicht gespeichert werden: \(error.localizedDescription)"
        }
    }

    private func preferenceKey(for uid: String) -> String {
        "push-notifications-enabled-\(uid)"
    }
}

private enum PushNotificationError: LocalizedError {
    case permissionDenied

    var errorDescription: String? {
        "Benachrichtigungen sind deaktiviert. Du kannst sie in den iPhone-Einstellungen für Mite erlauben."
    }
}
