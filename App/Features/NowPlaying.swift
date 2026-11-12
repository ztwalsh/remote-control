import SwiftUI

/// What's on the selected TV, at the bottom of the main screen: a strip with play and pause that
/// opens into a player with rewind and fast forward. It's tinted with the app's brand color, the way
/// Spotify tints its player with the album art. Tap or swipe up on the strip to open it; drag the
/// player down, tap outside it or tap the chevron to put it away.
///
/// TVs report which app is on screen but not the show, the artwork or the position, so the player
/// shows the app's icon and name and has no progress bar. See the strip in `prototype/app.html`.
struct NowPlaying: View {
    let store: RemoteStore
    @Binding var isExpanded: Bool

    @State private var drag: CGFloat = 0

    private let stripHeight: CGFloat = 64
    private let artSize: CGFloat = 210
    private let thumbSize: CGFloat = 40
    /// The open player's height above the home indicator.
    private let playerHeight: CGFloat = 500

    var body: some View {
        GeometryReader { geo in
            let inset = geo.safeAreaInsets.bottom
            ZStack(alignment: .bottom) {
                if isExpanded {
                    Color.black.opacity(0.42)
                        .ignoresSafeArea()
                        .onTapGesture { isExpanded = false }
                        .accessibilityHidden(true)
                        .transition(.opacity)
                }
                if let app = store.nowPlaying {
                    card(app, inset: inset)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .ignoresSafeArea(edges: .bottom)
        }
        .animation(Theme.settle, value: store.nowPlaying?.id)
        .animation(Theme.settle, value: isExpanded)
        .onChange(of: store.nowPlaying == nil) { _, gone in
            if gone { isExpanded = false }
        }
    }

    // MARK: - The card that morphs between strip and player

    private func card(_ app: PinnedApp, inset: CGFloat) -> some View {
        let open = isExpanded
        let paused = store.selected.isPaused
        let corner: CGFloat = open ? 30 : 20
        let bottomCorner: CGFloat = open ? 0 : 20
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: corner,
            bottomLeadingRadius: bottomCorner,
            bottomTrailingRadius: bottomCorner,
            topTrailingRadius: corner,
            style: .continuous
        )
        return ZStack(alignment: .topLeading) {
            shape.fill(app.playerColor)
            shape.fill(LinearGradient(
                colors: [.white.opacity(0.09), .black.opacity(0.22)],
                startPoint: .top,
                endPoint: .bottom
            ))
            player(app, paused: paused)
                .opacity(open ? 1 : 0)
                .allowsHitTesting(open)
                .accessibilityHidden(!open)
            strip(app, paused: paused)
                .opacity(open ? 0 : 1)
                .allowsHitTesting(!open)
                .accessibilityHidden(open)
            artwork(app, open: open)
        }
        .frame(height: open ? playerHeight + inset : stripHeight)
        .clipShape(shape)
        .contentShape(shape)
        .onTapGesture { if !isExpanded { isExpanded = true } }
        .shadow(color: .black.opacity(open ? 0.25 : 0.3), radius: open ? 20 : 16, y: open ? -6 : 8)
        .padding(.horizontal, open ? 0 : 12)
        .padding(.bottom, open ? 0 : max(inset, 12) + 4)
        .offset(y: drag)
        .gesture(dragGesture)
        .foregroundStyle(.white)
        .accessibilityAddTraits(open ? .isModal : [])
    }

    /// One icon that grows from the strip's thumbnail into the player's artwork.
    private func artwork(_ app: PinnedApp, open: Bool) -> some View {
        AppIcon(app: app, size: artSize)
            .shadow(color: .black.opacity(open ? 0.4 : 0), radius: 30, y: 20)
            .scaleEffect(open ? 1 : thumbSize / artSize, anchor: .topLeading)
            .frame(maxWidth: .infinity, alignment: open ? .center : .leading)
            .padding(.leading, open ? 0 : 12)
            .padding(.top, open ? 86 : 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    // MARK: - Strip

    private func strip(_ app: PinnedApp, paused: Bool) -> some View {
        HStack(spacing: 2) {
            Button { isExpanded = true } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(app.title)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        PlayingBars(isPlaying: !paused)
                        Text(store.selected.name)
                            .lineLimit(1)
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.68))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Now playing: \(app.title) on \(store.selected.name)")
            .accessibilityHint("Opens the player")

            Button { store.togglePlayback() } label: {
                IconView(paused ? .play : .pause, size: 24)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(PressScaleStyle(scale: 0.88))
            .accessibilityLabel(paused ? "Play" : "Pause")
        }
        .padding(.leading, 12 + thumbSize + 12)
        .padding(.trailing, 8)
        .frame(height: stripHeight)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Player

    private func player(_ app: PinnedApp, paused: Bool) -> some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(.white.opacity(0.3))
                .frame(width: 36, height: 5)
                .padding(.top, 6)
            HStack {
                Button { isExpanded = false } label: {
                    IconView(.chevronDown, size: 22)
                        .frame(width: 38, height: 38)
                        .background(Color.white.opacity(0.14), in: Circle())
                }
                .buttonStyle(PressScaleStyle(scale: 0.9))
                .accessibilityLabel("Close player")
                Spacer()
            }
            .padding(.horizontal, 22)
            .padding(.top, 13)

            // The artwork is drawn by `artwork(_:open:)`, 86 points from the top.
            Spacer().frame(height: 258)

            VStack(spacing: 6) {
                Text(app.title)
                    .font(.system(size: 24, weight: .semibold))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    PlayingBars(isPlaying: !paused)
                    Text(store.selected.name)
                        .lineLimit(1)
                }
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.68))
            }
            .padding(.horizontal, 28)

            HStack(spacing: 30) {
                SkipButton(forward: false) { store.skip(forward: false) }
                Button { store.togglePlayback() } label: {
                    IconView(paused ? .play : .pause, size: 34)
                        .foregroundStyle(app.playerColor)
                        .frame(width: 78, height: 78)
                        .background(Color.white, in: Circle())
                        .shadow(color: .black.opacity(0.25), radius: 12, y: 10)
                }
                .buttonStyle(PressScaleStyle(scale: 0.92))
                .accessibilityLabel(paused ? "Play" : "Pause")
                SkipButton(forward: true) { store.skip(forward: true) }
            }
            .padding(.top, 27)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Dragging

    /// Swipe up on the strip to open it; drag the player down to put it away.
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                if isExpanded {
                    drag = max(0, value.translation.height)
                } else if value.translation.height < -24 {
                    isExpanded = true
                }
            }
            .onEnded { value in
                guard isExpanded else { return }
                let dismiss = value.translation.height > 110 || value.predictedEndTranslation.height > 260
                withAnimation(Theme.settle) {
                    if dismiss { isExpanded = false }
                    drag = 0
                }
            }
    }
}

/// Rewind or fast forward: the arrows nudge the way they point on each press.
private struct SkipButton: View {
    let forward: Bool
    let action: () -> Void

    @State private var nudge: CGFloat = 0

    var body: some View {
        Button {
            action()
            Task { @MainActor in
                withAnimation(.spring(response: 0.16, dampingFraction: 0.7)) { nudge = forward ? 6 : -6 }
                try? await Task.sleep(for: .milliseconds(130))
                withAnimation(Theme.bounce) { nudge = 0 }
            }
        } label: {
            IconView(forward ? .fastForward : .rewind, size: 30)
                .offset(x: nudge)
                .frame(width: 62, height: 62)
                .contentShape(Circle())
        }
        .buttonStyle(SkipStyle())
        .accessibilityLabel(forward ? "Fast forward" : "Rewind")
    }
}

private struct SkipStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Circle().fill(Color.white.opacity(configuration.isPressed ? 0.14 : 0)))
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(Theme.bounce, value: configuration.isPressed)
    }
}

/// Three bars that bounce while something plays and rest low when paused.
struct PlayingBars: View {
    let isPlaying: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let speeds: [Double] = [7.6, 9.8, 6.7]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isPlaying || reduceMotion)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .frame(width: 3, height: barHeight(index, time: time))
                }
            }
            .frame(height: 11, alignment: .bottom)
        }
        .accessibilityHidden(true)
    }

    private func barHeight(_ index: Int, time: Double) -> CGFloat {
        guard isPlaying else { return 4 }
        guard !reduceMotion else { return [7, 11, 5][index] }
        let wave = 0.5 + 0.5 * sin(time * speeds[index] + Double(index) * 2.1)
        return 3 + 8 * wave
    }
}
