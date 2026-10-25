import SwiftUI

@main
struct RemoteControlApp: App {
    /// Paired TVs, or example TVs until one is added. Discovery comes later (docs/PLAN.md, phase 1).
    @State private var store = RemoteStore.load()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RemoteScreen(store: store)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.reconnect() }
        }
    }
}
