import SwiftUI

/// The logo grid. Tapping lifts the app, dims the rest and shows "Opening" above it.
struct FavoritesCard: View {
    let apps: [FavoriteApp]
    let currentAppID: String?
    let onOpen: (FavoriteApp) -> Void

    @State private var openingID: String?
    @State private var resetTask: Task<Void, Never>?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Favorites")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(Theme.text)
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(apps) { app in
                    tile(app)
                }
            }
        }
        .card()
    }

    private func tile(_ app: FavoriteApp) -> some View {
        let isOpening = openingID == app.id
        let isCurrent = currentAppID == app.id && openingID == nil
        return Button {
            open(app)
        } label: {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(app.tile)
                .frame(width: 62, height: 62)
                .overlay {
                    Image(app.logo)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: app.logoSize, height: app.logoSize)
                        .foregroundStyle(app.glyph)
                }
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.08)))
                .padding(3.5)
                .overlay(
                    RoundedRectangle(cornerRadius: 19, style: .continuous)
                        .strokeBorder(isCurrent ? Theme.blue : .clear, lineWidth: 1.5)
                )
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
        .opacity(openingID != nil && !isOpening ? 0.32 : 1)
        .zIndex(isOpening ? 1 : 0)
        .accessibilityLabel("Open \(app.name)")
        .accessibilityAddTraits(currentAppID == app.id ? .isSelected : [])
    }

    private func open(_ app: FavoriteApp) {
        withAnimation(Theme.bounce) { openingID = app.id }
        onOpen(app)
        resetTask?.cancel()
        resetTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1100))
            guard !Task.isCancelled else { return }
            withAnimation(Theme.settle) { openingID = nil }
        }
    }
}
