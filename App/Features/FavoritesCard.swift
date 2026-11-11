import SwiftUI

/// The pinned apps. Tapping lifts the app, dims the rest and shows "Opening" above it.
/// Long-press an app to unpin it; All apps lists everything on the TV.
struct FavoritesCard: View {
    let apps: [PinnedApp]
    let currentAppID: String?
    let onOpen: (String) -> Void
    let onUnpin: (String) -> Void
    let onShowAll: () -> Void

    @State private var openingID: String?
    @State private var resetTask: Task<Void, Never>?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Favorites")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Spacer()
                Button("All apps", action: onShowAll)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.accent)
            }
            if apps.isEmpty {
                Button(action: onShowAll) {
                    Text("Pin the apps you use most from All apps.")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, minHeight: 62)
                }
                .buttonStyle(.plain)
            } else {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(apps) { app in
                        tile(app)
                    }
                }
            }
        }
        .card()
        .animation(Theme.settle, value: apps)
    }

    private func tile(_ app: PinnedApp) -> some View {
        let isOpening = openingID == app.id
        let isCurrent = currentAppID == app.id && openingID == nil
        return Button {
            open(app)
        } label: {
            AppIcon(app: app, size: 62)
                .padding(3.5)
                // What's on screen now: a small dot under the icon that slowly pulses.
                .overlay(alignment: .bottom) {
                    if isCurrent {
                        CurrentAppDot()
                            .offset(y: 9)
                            .transition(.opacity.combined(with: .scale(scale: 0.5)))
                    }
                }
                .animation(Theme.settle, value: isCurrent)
                .scaleEffect(isOpening ? 1.1 : 1)
                .offset(y: isOpening ? -3 : 0)
                .overlay(alignment: .top) {
                    if isOpening {
                        ValueTip(text: "Opening")
                            .offset(y: -44)
                            .transition(.scale(scale: 0.9, anchor: .bottom).combined(with: .opacity))
                    }
                }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { onUnpin(app.id) } label: { Label("Unpin \(app.title)", image: Icon.unpin.assetName) }
        }
        .opacity(openingID != nil && !isOpening ? 0.32 : 1)
        .zIndex(isOpening ? 1 : 0)
        .transition(.scale(scale: 0.8).combined(with: .opacity))
        .accessibilityLabel("Open \(app.title)")
        .accessibilityAddTraits(currentAppID == app.id ? .isSelected : [])
        .accessibilityAction(named: "Unpin") { onUnpin(app.id) }
    }

    private func open(_ app: PinnedApp) {
        withAnimation(Theme.bounce) { openingID = app.id }
        onOpen(app.id)
        resetTask?.cancel()
        resetTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1100))
            guard !Task.isCancelled else { return }
            withAnimation(Theme.settle) { openingID = nil }
        }
    }
}

/// The accent dot under the app that's on screen. It slowly fades and swells between soft and
/// full; with Reduce Motion on it holds still at full strength.
private struct CurrentAppDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let dot = Circle().fill(Theme.accent).frame(width: 6, height: 6)
        if reduceMotion {
            dot
        } else {
            PhaseAnimator([false, true]) { bright in
                dot
                    .opacity(bright ? 1 : 0.35)
                    .scaleEffect(bright ? 1 : 0.8)
            } animation: { _ in
                .easeInOut(duration: 1.6)
            }
        }
    }
}

/// An app's icon: the bundled logo for well-known apps, otherwise the icon the TV serves,
/// otherwise the app's first letter.
struct AppIcon: View {
    let app: PinnedApp
    let size: CGFloat

    @Environment(RemoteStore.self) private var store
    @State private var image: UIImage?

    private var radius: CGFloat { size * 0.26 }

    var body: some View {
        Group {
            if let bundled = app.bundled {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(bundled.tile)
                    .overlay {
                        Image(bundled.logo)
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: bundled.logoSize * size / 62, height: bundled.logoSize * size / 62)
                            .foregroundStyle(bundled.glyph)
                    }
            } else if let url = app.iconURL {
                ZStack {
                    if let image {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else {
                        letter
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                .task(id: url) { image = await store.icon(for: url) }
            } else {
                letter
            }
        }
        .frame(width: size, height: size)
    }

    private var letter: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Theme.iconTile)
            .overlay {
                Text(app.title.prefix(1).uppercased())
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(Theme.muted)
            }
    }
}
