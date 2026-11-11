import SwiftUI
import TVKit

/// Every app installed on the selected TV, with the TV's inputs (HDMI, Live TV) in their own row
/// at the top. Tap one to open it on the TV; tap the pin (or long-press an input) to add it to
/// or take it off Favorites.
struct AllAppsSheet: View {
    let store: RemoteStore
    let onClose: () -> Void

    @State private var query = ""
    @State private var loading = false

    private var apps: [LaunchPoint]? { store.installedApps[store.selectedID] }

    private var filtered: [LaunchPoint] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return apps ?? [] }
        return (apps ?? []).filter { $0.title.localizedCaseInsensitiveContains(q) }
    }

    private var inputs: [LaunchPoint] { filtered.filter(\.isInput) }
    private var appsOnly: [LaunchPoint] { filtered.filter { !$0.isInput } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SheetHeader(title: "All apps", onClose: onClose)

            HStack(spacing: 8) {
                IconView(.search, size: 20).foregroundStyle(Theme.muted)
                TextField("Search", text: $query, prompt: Text("Search").foregroundStyle(Theme.mutedNumber))
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.text)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            if apps == nil {
                VStack(spacing: 12) {
                    if loading {
                        ProgressView().tint(Theme.muted)
                        Text("Loading apps…").foregroundStyle(Theme.muted)
                    } else {
                        Text("Couldn't load this TV's apps. Check it's on.").foregroundStyle(Theme.muted)
                        PillButton(title: "Try again", icon: .refresh) { Task { await load() } }
                    }
                }
                .font(.system(size: 15))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filtered.isEmpty {
                Text("No apps match “\(query)”.")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if !inputs.isEmpty {
                            sectionTitle("Inputs")
                            ScrollView(.horizontal) {
                                HStack(spacing: 8) {
                                    ForEach(inputs) { input in chip(input) }
                                }
                            }
                            .scrollIndicators(.hidden)
                            .padding(.bottom, 8)
                        }
                        if !appsOnly.isEmpty {
                            sectionTitle("Apps")
                            LazyVStack(spacing: 8) {
                                ForEach(appsOnly) { app in row(app) }
                            }
                        }
                    }
                    .padding(.bottom, 16)
                }
                .scrollDismissesKeyboard(.immediately)
            }
        }
        .sheetPadding()
        .task { await load() }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Theme.muted)
    }

    /// An input as a compact pill. Long-press to pin it.
    private func chip(_ input: LaunchPoint) -> some View {
        let pinned = store.isPinned(input.id)
        let isCurrent = store.foregroundIsInput(input.id)
        return Button {
            store.launch(appID: input.id)
            onClose()
        } label: {
            HStack(spacing: 8) {
                AppIcon(app: PinnedApp(input), size: 28)
                Text(input.title)
                    .font(.system(size: 15, weight: .medium))
                    .lineLimit(1)
                if pinned {
                    IconView(.pinFill, size: 14)
                }
            }
            .padding(.leading, 6)
            .padding(.trailing, 14)
            .frame(height: 42)
            .foregroundStyle(isCurrent ? Theme.onAccent : Theme.text)
            .background(isCurrent ? Theme.accent : Theme.raised, in: Capsule())
        }
        .buttonStyle(PressScaleStyle(scale: 0.95))
        .contextMenu {
            Button { store.togglePin(input) } label: {
                Label(pinned ? "Unpin from Favorites" : "Pin to Favorites", image: pinned ? Icon.unpin.assetName : Icon.pin.assetName)
            }
        }
        .accessibilityLabel("Switch to \(input.title)")
        .accessibilityAction(named: pinned ? "Unpin from Favorites" : "Pin to Favorites") { store.togglePin(input) }
    }

    private func row(_ app: LaunchPoint) -> some View {
        let pinned = store.isPinned(app.id)
        return HStack(spacing: 8) {
            Button {
                store.launch(appID: app.id)
                onClose()
            } label: {
                HStack(spacing: 14) {
                    AppIcon(app: PinnedApp(app), size: 44)
                    Text(app.title)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityLabel("Open \(app.title)")

            Button { store.togglePin(app) } label: {
                IconView(pinned ? .pinFill : .pin, size: 20)
                    .frame(width: 44, height: 44)
                    .background(pinned ? Theme.accent.opacity(0.12) : Theme.iconTile, in: Circle())
                    .foregroundStyle(pinned ? Theme.accent : Theme.muted)
            }
            .buttonStyle(PressScaleStyle(scale: 0.9))
            .sensoryFeedback(.selection, trigger: pinned)
            .accessibilityLabel(pinned ? "Unpin \(app.title) from Favorites" : "Pin \(app.title) to Favorites")
        }
        .padding(6)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func load() async {
        loading = true
        await store.loadApps()
        loading = false
    }
}
