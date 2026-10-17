import SwiftUI

@main
struct RemoteControlApp: App {
    /// Example TVs until discovery and pairing are built (docs/PLAN.md, phase 1).
    @State private var store = RemoteStore.demo()

    var body: some Scene {
        WindowGroup {
            RemoteScreen(store: store)
        }
    }
}
