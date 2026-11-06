import SwiftUI

@main
struct WhatchaApp: App {
    @StateObject private var model = ChatModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ChatScreen(model: model)
                .preferredColorScheme(.light)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { model.cameBack() }
                }
        }
    }
}
