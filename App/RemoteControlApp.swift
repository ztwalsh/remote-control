import SwiftUI

@main
struct RemoteControlApp: App {
    /// Paired TVs, or example TVs until one is added.
    @State private var store = RemoteStore.load()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appearance") private var appearance = Appearance.system

    var body: some Scene {
        WindowGroup {
            RemoteScreen(store: store)
                .environment(store)
                .onAppear { apply(appearance) }
                .onChange(of: appearance) { _, new in apply(new) }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            apply(appearance)
            store.reconnect()
        }
    }

    /// Sets light, dark or system on the app's windows. Done on the window, not with
    /// `preferredColorScheme`, so open sheets switch too and System really follows the phone.
    private func apply(_ appearance: Appearance) {
        let style: UIUserInterfaceStyle = switch appearance {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows { window.overrideUserInterfaceStyle = style }
        }
    }
}
