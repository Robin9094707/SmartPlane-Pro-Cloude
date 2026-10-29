import SwiftUI

@main
struct SmartPlaneProApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(Theme.accent)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { model.enterBackground() }
        }
    }
}
