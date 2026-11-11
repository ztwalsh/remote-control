import SwiftUI
import TVKit

/// Moves around the TV's screen like an Apple TV remote: swipe to move the highlight, tap to select.
/// Back and Home sit underneath.
struct NavigateSheet: View {
    let store: RemoteStore
    let onClose: () -> Void

    @State private var presses = 0
    @State private var repair = Repair.idle

    enum Repair: Equatable { case idle, pairing, awaitingPrompt, failed }

    var body: some View {
        VStack(spacing: 16) {
            SheetHeader(title: "Navigate", onClose: onClose)

            SwipePad { button in
                store.press(button)
                presses += 1
            }
            .overlay { if store.pointerRefused { refusedNotice } }

            HStack(spacing: 16) {
                KeyButton(title: "Back", icon: .back) { store.press(.back) }
                KeyButton(title: "Home", icon: .home) { store.press(.home) }
            }
            .frame(maxWidth: .infinity)
        }
        .sheetPadding()
        .padding(.bottom, 12)
        .sensoryFeedback(.impact(weight: .light), trigger: presses)
    }

    // MARK: - Older pairings

    private var refusedNotice: some View {
        VStack(spacing: 14) {
            Text(repair == .awaitingPrompt ? "Choose Allow on your TV" : "This TV needs to be paired again to allow remote navigation.")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.center)
            if repair == .failed {
                Text("Couldn't pair. Check the TV is on, then try again.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
            }
            if repair != .awaitingPrompt {
                PillButton(title: repair == .pairing ? "Connecting…" : "Pair again", icon: .tv, action: repairTV)
                    .disabled(repair == .pairing)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.card.opacity(0.94), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .transition(.opacity)
    }

    private func repairTV() {
        repair = .pairing
        Task {
            do {
                try await store.repairSelected { repair = .awaitingPrompt }
                repair = .idle
            } catch {
                repair = .failed
            }
        }
    }
}

/// An Apple TV-style touch surface. A deliberate swipe of about an inch moves the TV's highlight
/// one step; keep dragging to keep stepping, or flick to add one more. A tap is OK.
///
/// Drawn as a dot grid. While touching, the dots near the finger turn solid, and they flash on each
/// step or tap. Nothing moves, blurs or glows; only the dots' color changes.
private struct SwipePad: View {
    let onPress: (RemoteButton) -> Void

    /// Drag distance for one step. Raise it to make swiping less sensitive.
    private static let step: CGFloat = 72
    /// How much a swipe must favor one direction over the other before it counts.
    /// Keeps a slightly diagonal swipe from stepping sideways.
    private static let straightness: CGFloat = 1.6
    /// Speed (points per second) at the end of a swipe that counts as a flick.
    private static let flickSpeed: CGFloat = 1000
    /// A flick this fast adds one more step.
    private static let fastFlickSpeed: CGFloat = 2400

    @State private var anchor: CGSize = .zero
    @State private var started: Date?
    @State private var farthest: CGFloat = 0
    @State private var steps = 0
    @State private var isTouching = false
    @State private var touch: CGPoint = .zero
    /// When the finger went down and came up, for fading the color in and out.
    @State private var touchedAt = Date.distantPast
    @State private var releasedAt = Date.distantPast
    /// When the last step or tap happened; the dots near the finger brighten, then ease back.
    @State private var flashedAt = Date.distantPast
    /// Keeps the drawing animating while a fade is running; off when the pad is idle.
    @State private var animating = false

    /// Dots within this distance of the finger change color, most strongly near the center.
    private static let reach: CGFloat = 96
    private static let fadeIn: TimeInterval = 0.18
    private static let fadeOut: TimeInterval = 0.4
    private static let flashLength: TimeInterval = 0.3
    private static let spacing: CGFloat = 28
    private static let dotRadius: CGFloat = 2.6

    var body: some View {
        surface
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged(changed)
                    .onEnded(ended)
            )
            .accessibilityElement()
            .accessibilityLabel("Touch surface")
            .accessibilityHint("Swipe up, down, left or right to move. Double-tap to select.")
            .accessibilityAction { onPress(.enter) }
            .accessibilityAction(named: "Up") { onPress(.up) }
            .accessibilityAction(named: "Down") { onPress(.down) }
            .accessibilityAction(named: "Left") { onPress(.left) }
            .accessibilityAction(named: "Right") { onPress(.right) }
    }

    /// The dot grid. Only color changes: resting dots are faint, the ones near the finger are solid,
    /// and they flash fully on each step. The grid fades out at the top and bottom.
    private var surface: some View {
        TimelineView(.animation(paused: !animating)) { timeline in
            let level = touchLevel(at: timeline.date)
            let flash = flashLevel(at: timeline.date)
            Canvas { context, size in
                let columns = Int(size.width / Self.spacing), rows = Int(size.height / Self.spacing)
                let x0 = (size.width - CGFloat(columns) * Self.spacing) / 2
                let y0 = (size.height - CGFloat(rows) * Self.spacing) / 2
                let r = Self.dotRadius
                var resting = Path()
                for row in 0...rows {
                    for column in 0...columns {
                        let x = x0 + CGFloat(column) * Self.spacing, y = y0 + CGFloat(row) * Self.spacing
                        let dot = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
                        let distance = hypot(x - touch.x, y - touch.y)
                        guard level > 0, distance < Self.reach else {
                            resting.addEllipse(in: dot)
                            continue
                        }
                        // Full strength near the finger, easing to the resting color at the edge.
                        let edge = Self.smoothstep(Double(1 - distance / Self.reach))
                        let opacity = Self.restingOpacity + (0.55 + 0.4 * flash - Self.restingOpacity) * edge * level
                        context.fill(Path(ellipseIn: dot), with: .color(Theme.text.opacity(opacity)))
                    }
                }
                context.fill(resting, with: .color(Theme.text.opacity(Self.restingOpacity)))
            }
        }
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .white, location: 0.12),
                    .init(color: .white, location: 0.88),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )
        }
    }

    private static let restingOpacity = 0.08

    /// 0 to 1: fades in after the finger goes down, out after it comes up.
    private func touchLevel(at date: Date) -> Double {
        if isTouching {
            return min(1, date.timeIntervalSince(touchedAt) / Self.fadeIn)
        }
        // A quick tap ends before the fade-in does; if it did something, show it fully anyway.
        let reached = flashedAt >= touchedAt ? 1 : min(1, releasedAt.timeIntervalSince(touchedAt) / Self.fadeIn)
        return max(0, reached * (1 - date.timeIntervalSince(releasedAt) / Self.fadeOut))
    }

    /// 1 right after a step or tap, easing to 0.
    private func flashLevel(at date: Date) -> Double {
        max(0, 1 - date.timeIntervalSince(flashedAt) / Self.flashLength)
    }

    private static func smoothstep(_ t: Double) -> Double {
        let t = min(1, max(0, t))
        return t * t * (3 - 2 * t)
    }

    private func changed(_ value: DragGesture.Value) {
        touch = value.location
        if started == nil {
            started = .now
            anchor = .zero
            farthest = 0
            steps = 0
            isTouching = true
            touchedAt = .now
            animating = true
        }
        let t = value.translation
        farthest = max(farthest, hypot(t.width, t.height))
        let dx = t.width - anchor.width
        let dy = t.height - anchor.height
        let horizontal = abs(dx) > abs(dy)
        let major = max(abs(dx), abs(dy)), minor = min(abs(dx), abs(dy))
        guard major >= Self.step, major >= minor * Self.straightness else { return }

        if horizontal {
            send(dx > 0 ? .right : .left)
            // Advance along the swipe's axis; reset the other so drift doesn't build up.
            anchor = CGSize(width: anchor.width + (dx > 0 ? Self.step : -Self.step), height: t.height)
        } else {
            send(dy > 0 ? .down : .up)
            anchor = CGSize(width: t.width, height: anchor.height + (dy > 0 ? Self.step : -Self.step))
        }
        steps += 1
    }

    private func ended(_ value: DragGesture.Value) {
        defer {
            started = nil
            isTouching = false
            releasedAt = .now
            // Stop redrawing once the fade-out and any flash have finished.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(Int((max(Self.fadeOut, Self.flashLength) + 0.15) * 1000)))
                if !isTouching { animating = false }
            }
        }
        let quick = started.map { Date.now.timeIntervalSince($0) < 0.35 } ?? false
        if steps == 0 && farthest < 12 && quick {
            send(.enter)
            return
        }

        // A flick: a short fast swipe still counts as one step, and a very fast one adds one more.
        let v = value.velocity
        let speed = max(abs(v.width), abs(v.height))
        let straight = max(abs(v.width), abs(v.height)) >= min(abs(v.width), abs(v.height)) * Self.straightness
        guard speed > Self.flickSpeed, straight else { return }
        let button: RemoteButton = abs(v.width) > abs(v.height)
            ? (v.width > 0 ? .right : .left)
            : (v.height > 0 ? .down : .up)
        let extra = (steps == 0 ? 1 : 0) + (speed > Self.fastFlickSpeed ? 1 : 0)
        guard extra > 0 else { return }
        Task { @MainActor in
            for i in 0..<extra {
                if i > 0 { try? await Task.sleep(for: .milliseconds(120)) }
                send(button)
            }
        }
    }

    private func send(_ button: RemoteButton) {
        onPress(button)
        flashDots()
    }

    /// Flashes the dots under the finger fully on, then back.
    private func flashDots() {
        flashedAt = .now
    }
}

/// Back and Home under the touch surface: round, icon only. `title` is the spoken label.
private struct KeyButton: View {
    let title: String
    let icon: Icon
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            IconView(icon, size: 24)
                .frame(width: 60, height: 60)
                .background(Theme.raised, in: Circle())
                .foregroundStyle(Theme.text)
        }
        .buttonStyle(PressScaleStyle(scale: 0.92))
        .accessibilityLabel(title)
    }
}
