import SwiftUI

@main
struct WhatchaApp: App {
    @AppStorage private var role: String
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
            .preferredColorScheme(.light)
        }
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
