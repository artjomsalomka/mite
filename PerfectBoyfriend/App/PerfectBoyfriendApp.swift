import SwiftUI
import FirebaseAppCheck
import FirebaseAuth
import FirebaseCore
import FirebaseCrashlytics
import FirebaseFirestore
import FirebaseFunctions
import FirebaseMessaging
import FirebaseStorage
import UIKit
import UserNotifications

final class PushApplicationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Messaging.messaging().apnsToken = deviceToken
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let data = response.notification.request.content.userInfo
        let type = data["type"] as? String
        if type == "group_event" || type == "group_event_message" {
            let eventID = data["eventId"] as? String
            Task { @MainActor in
                MiteDeepLinkRouter.shared.openGroupEvent(eventID)
            }
        } else if type == "single_match" || type == "single_message" || type == "match_date" {
            let matchID = data["matchId"] as? String
            Task { @MainActor in
                MiteDeepLinkRouter.shared.openSingleMatch(
                    matchID,
                    destination: type == "single_message" ? .chat : .overview
                )
            }
        } else if type == "couple_date" {
            let coupleID = data["coupleId"] as? String
            let savedDateID = data["savedDateId"] as? String
            Task { @MainActor in
                MiteDeepLinkRouter.shared.openCoupleDate(coupleID: coupleID, savedDateID: savedDateID)
            }
        }
        completionHandler()
    }
}

/// Holds a notification destination until the authenticated app shell is ready. A plain
/// NotificationCenter event is lossy during a cold launch because RootView may not exist yet.
@MainActor
final class MiteDeepLinkRouter: ObservableObject {
    struct SingleMatchRoute: Equatable, Identifiable {
        enum Destination: Equatable {
            case overview
            case chat
        }

        let matchID: String
        let destination: Destination

        var id: String { "\(matchID)-\(destination == .chat ? "chat" : "overview")" }
    }

    struct CoupleDateRoute: Equatable, Identifiable {
        let coupleID: String
        let savedDateID: String

        var id: String { "\(coupleID)-\(savedDateID)" }
    }

    static let shared = MiteDeepLinkRouter()

    @Published private(set) var groupEventID: String?
    @Published private(set) var singleMatchRoute: SingleMatchRoute?
    @Published private(set) var coupleDateRoute: CoupleDateRoute?

    private init() {}

    func openGroupEvent(_ eventID: String?) {
        guard let eventID, !eventID.isEmpty else { return }
        groupEventID = eventID
    }

    func consumeGroupEvent(_ eventID: String) {
        guard groupEventID == eventID else { return }
        groupEventID = nil
    }

    func openSingleMatch(_ matchID: String?, destination: SingleMatchRoute.Destination) {
        guard let matchID, !matchID.isEmpty else { return }
        singleMatchRoute = SingleMatchRoute(matchID: matchID, destination: destination)
    }

    func consumeSingleMatch(_ route: SingleMatchRoute) {
        guard singleMatchRoute == route else { return }
        singleMatchRoute = nil
    }

    func openCoupleDate(coupleID: String?, savedDateID: String?) {
        guard let coupleID, !coupleID.isEmpty,
              let savedDateID, !savedDateID.isEmpty else { return }
        coupleDateRoute = CoupleDateRoute(coupleID: coupleID, savedDateID: savedDateID)
    }

    func consumeCoupleDate(_ route: CoupleDateRoute) {
        guard coupleDateRoute == route else { return }
        coupleDateRoute = nil
    }
}

@main
struct PerfectBoyfriendApp: App {
    @UIApplicationDelegateAdaptor(PushApplicationDelegate.self) private var pushApplicationDelegate

    init() {
        configureFirebaseIfPossible()
        PushNotificationService.shared.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                // The current product and all UX copy are German. Pinning the locale avoids
                // mixed cards such as “Sun … at …” on devices configured in another language.
                .environment(\.locale, Locale(identifier: "de_DE"))
        }
    }

    /// Firebase configuration is supplied by GoogleService-Info.plist. Debug builds always use
    /// the local Emulator Suite, even when that plist belongs to the real Firebase project. This
    /// gives local development the same project identifier and callable-function URLs as a later
    /// deployment, without allowing a simulator run to touch cloud user data. Archive/Release
    /// builds use the configured Firebase project normally.
    private func configureFirebaseIfPossible() {
        let configurationName: String
        #if STAGING
        configurationName = "GoogleService-Info-Staging"
        #else
        configurationName = "GoogleService-Info"
        #endif
        guard let configurationPath = Bundle.main.path(forResource: configurationName, ofType: "plist"),
              let firebaseOptions = FirebaseOptions(contentsOfFile: configurationPath) else {
            print("⚠️ \(configurationName).plist missing or invalid — Firebase not configured.")
            return
        }
        #if DEBUG || STAGING
        // Simulator and local-device builds use the debug provider. The printed token can be
        // registered in the staging Firebase project; the local Functions emulator ignores it.
        AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
        #else
        // DeviceCheck is supported by every device that can run the iOS 17 deployment target.
        // Enforcement is enabled service-by-service in Firebase only after staging telemetry is clean.
        AppCheck.setAppCheckProviderFactory(DeviceCheckProviderFactory())
        #endif
        FirebaseApp.configure(options: firebaseOptions)

        #if DEBUG
        // Local development can contain seeded identities and intentional failures. Never send
        // those diagnostics to the production Crashlytics project.
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(false)
        #else
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(true)
        #endif

        #if DEBUG
        if let projectID = FirebaseApp.app()?.options.projectID {
            connectToLocalEmulators()
            print("🧪 Using Firebase Local Emulator Suite (project: \(projectID)) — run `firebase emulators:start` from the project root.")
        }
        #endif
    }

    private func connectToLocalEmulators() {
        // A simulator can reach the Mac via its loopback. A physical iPhone needs the Mac's
        // LAN address instead; Xcode provides it through PBLocalEmulatorHost in Debug builds.
        let host = localEmulatorHost
        Auth.auth().useEmulator(withHost: host, port: 9099)
        let settings = Firestore.firestore().settings
        settings.host = "\(host):8080"
        settings.isSSLEnabled = false
        settings.cacheSettings = MemoryCacheSettings()
        Firestore.firestore().settings = settings
        Functions.functions().useEmulator(withHost: host, port: 5001)
        Storage.storage().useEmulator(withHost: host, port: 9199)
        print("🧪 Firebase emulators reachable at \(host)")
    }

    private var localEmulatorHost: String {
        #if targetEnvironment(simulator)
        return "127.0.0.1"
        #else
        let configuredHost = Bundle.main.object(forInfoDictionaryKey: "PBLocalEmulatorHost") as? String
        let host = configuredHost?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return host.isEmpty || host.contains("$(") ? "127.0.0.1" : host
        #endif
    }
}
