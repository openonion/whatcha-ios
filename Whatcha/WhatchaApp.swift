import SwiftUI
import UserNotifications

@main
struct WhatchaApp: App {
    @AppStorage private var role: String
    @UIApplicationDelegateAdaptor(FamilyNotificationDelegate.self) private var notifications
    #if DEBUG
    private let previewParent = ProcessInfo.processInfo.arguments.contains("-uitest-unpaired")
    #else
    private let previewParent = false
    #endif

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uitest-role-picker") {
            let defaults = UserDefaults(suiteName: "ai.openonion.whatcha.RolePickerTests")!
            defaults.removeObject(forKey: "familyRole")
            _role = AppStorage(wrappedValue: "", "familyRole", store: defaults)
            return
        }
        #endif
        _role = AppStorage(wrappedValue: "", "familyRole")
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if role == "parent" || previewParent {
                    ParentScreen { role = "" }
                } else if role == "child" {
                    FamilyAdminScreen { role = "" }
                } else {
                    VStack(spacing: 12) {
                        Spacer()
                        Text("在干嘛")
                            .font(.largeTitle.weight(.semibold))
                            .accessibilityAddTraits(.isHeader)
                        Button {
                            role = "parent"
                        } label: {
                            Text("我是家长")
                                .font(.title2.bold())
                                .frame(maxWidth: .infinity, minHeight: 64)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(red: 0.03, green: 0.48, blue: 0.27))
                        Spacer()
                        Button {
                            role = "child"
                        } label: {
                            Text("我是孩子 · 管理家人")
                                .font(.subheadline)
                                .frame(minHeight: 48)
                                .padding(.horizontal, 16)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: 420)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 12)
                }
            }
            .environmentObject(notifications)
            .preferredColorScheme(.light)
        }
    }
}

final class FamilyNotificationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, ObservableObject {
    @Published private(set) var token: String?
    @Published private(set) var registrationFailed = false
    @Published private(set) var handoffOpenCount = 0

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uitest-apns-registration") {
            Task {
                if (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) == true {
                    application.registerForRemoteNotifications()
                }
            }
        }
        if ProcessInfo.processInfo.arguments.contains("-uitest-apns-delivery") {
            Task {
                let notifications = await UNUserNotificationCenter.current().deliveredNotifications()
                let received = notifications.contains { $0.request.content.userInfo["whatcha"] as? String == "handoffs" }
                let path = URL.documentsDirectory.appending(path: "whatcha-apns-test-delivery")
                try? (received ? "received" : "not-received").write(to: path, atomically: true, encoding: .utf8)
            }
        }
        #endif
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        registrationFailed = false
        token = deviceToken.map { String(format: "%02x", $0) }.joined()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uitest-apns-registration") {
            let path = URL.documentsDirectory.appending(path: "whatcha-apns-test-token")
            try? token?.write(to: path, atomically: true, encoding: .utf8)
        }
        #endif
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        registrationFailed = true
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        guard response.notification.request.content.userInfo["whatcha"] as? String == "handoffs" else { return }
        await MainActor.run { handoffOpenCount += 1 }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        notification.request.content.userInfo["whatcha"] as? String == "handoffs" ? [.banner, .list, .sound] : []
    }
}

private struct ParentScreen: View {
    let switchRole: () -> Void
    @StateObject private var model = ChatModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ChatScreen(model: model, switchRole: switchRole)
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { model.cameBack() }
            }
    }
}
