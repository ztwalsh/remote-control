import SwiftUI

/// Wind the ring clockwise to set a timer of up to 4 hours. It then counts down live.
struct SleepTimerSheet: View {
    let endsAt: Date?
    let canUndo: Bool
    let onSet: (Int) -> Void
    let onUndo: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            SheetHeader(title: "Sleep timer", onClose: onClose)
            SleepDial(endsAt: endsAt, onSet: onSet)
            ZStack {
                if endsAt != nil {
                    PillButton(title: "Cancel timer", icon: .close) { onSet(0) }
                } else if canUndo {
                    PillButton(title: "Undo", icon: .back, action: onUndo)
                }
            }
            .frame(height: 40)
            .animation(Theme.bounce, value: endsAt)
            .animation(Theme.bounce, value: canUndo)
        }
        .sheetPadding()
    }
}

/// The ring itself: four one-hour sections, a blue arc for the time left, and a swell under your finger.
struct SleepDial: View {
    let endsAt: Date?
    let onSet: (Int) -> Void

    static let maxMinutes: Double = 240
    private let size: CGFloat = 280

    @State private var dragMinutes: Double?
    @State private var lastAngle: Double = 0
    @State private var swell: Double = 0
    @State private var hourTicks = 0
    @State private var appeared = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = endsAt.map { max(0, $0.timeIntervalSince(context.date)) } ?? 0
            let minutes = dragMinutes ?? remaining / 60
            let end = appeared ? minutes / Self.maxMinutes * 2 * .pi : 0

            ZStack {
                RingArc(startAngle: 0, endAngle: 2 * .pi - 0.001, swellAngle: end, swell: swell)
                    .fill(Theme.track)
                RingArc(startAngle: 0, endAngle: min(end, 2 * .pi - 0.001), swellAngle: end, swell: swell)
                    .fill(Theme.accent)
                centerLabel(remaining: remaining)
            }
            .animation(dragMinutes == nil ? Theme.settle : nil, value: end)
            .frame(width: size, height: size)
            .contentShape(Circle())
            .gesture(windGesture(currentMinutes: remaining / 60))
        }
        .frame(width: size, height: size)
        .sensoryFeedback(.impact(weight: .medium), trigger: hourTicks)
        .sensoryFeedback(.selection, trigger: dragMinutes.map(Self.snap))
        .onAppear {
            // Opening the sheet winds the ring up from zero to the time left.
            withAnimation(Theme.settle.delay(0.1)) { appeared = true }
        }
        .accessibilityElement()
        .accessibilityLabel("Sleep timer, up to 4 hours")
        .accessibilityValue(endsAt == nil ? "Off" : RemoteStore.duration(minutes: Self.snap((endsAt?.timeIntervalSinceNow ?? 0) / 60)))
        .accessibilityAdjustableAction { direction in
            let current = Self.snap((endsAt?.timeIntervalSinceNow ?? 0) / 60)
            switch direction {
            case .increment: onSet(min(Int(Self.maxMinutes), current + 5))
            case .decrement: onSet(max(0, current - 5))
            @unknown default: break
            }
        }
    }

    @ViewBuilder
    private func centerLabel(remaining: TimeInterval) -> some View {
        VStack(spacing: 6) {
            if let dragMinutes {
                let minutes = Self.snap(dragMinutes)
                Text(String(format: "%d:%02d", minutes / 60, minutes % 60))
                    .font(.system(size: 46, weight: .semibold))
                    .contentTransition(.numericText(value: Double(minutes)))
                Text(minutes > 0 ? "Off at \(Date.now.addingTimeInterval(Double(minutes * 60)).formatted(date: .omitted, time: .shortened))" : " ")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.muted)
            } else if let endsAt, remaining > 0 {
                let total = Int(remaining.rounded(.up))
                (Text(String(format: "%d:%02d", total / 3600, (total % 3600) / 60))
                    .font(.system(size: 46, weight: .semibold))
                + Text(String(format: ":%02d", total % 60))
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(Theme.muted))
                    .contentTransition(.numericText(countsDown: true))
                Text("Off at \(endsAt.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.muted)
            } else {
                Text("0:00")
                    .font(.system(size: 46, weight: .semibold))
                Text(" ")
                    .font(.system(size: 14))
            }
        }
        .monospacedDigit()
        .foregroundStyle(Theme.text)
        .animation(.snappy, value: Int(remaining))
    }

    private func windGesture(currentMinutes: Double) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { drag in
                let angle = angle(of: drag.location)
                guard let minutes = dragMinutes else {
                    let tapped = angle / (2 * .pi) * Self.maxMinutes
                    // Grabbing near 12 o'clock with a long timer keeps winding instead of jumping to zero.
                    dragMinutes = currentMinutes > 200 && tapped < 40 ? currentMinutes : tapped
                    lastAngle = angle
                    withAnimation(Theme.bounce) { swell = 14 }
                    return
                }
                var delta = angle - lastAngle
                if delta > .pi { delta -= 2 * .pi } else if delta < -.pi { delta += 2 * .pi }
                lastAngle = angle
                let next = min(Self.maxMinutes, max(0, minutes + delta / (2 * .pi) * Self.maxMinutes))
                if Int(next / 60) != Int(minutes / 60) { hourTicks += 1 }
                dragMinutes = next
            }
            .onEnded { _ in
                let minutes = Self.snap(dragMinutes ?? 0)
                dragMinutes = nil
                withAnimation(Theme.bounce) { swell = 0 }
                onSet(minutes)
            }
    }

    private func angle(of point: CGPoint) -> Double {
        var angle = atan2(Double(point.x - size / 2), Double(size / 2 - point.y))
        if angle < 0 { angle += 2 * .pi }
        return angle
    }

    static func snap(_ minutes: Double) -> Int {
        Int((minutes / 5).rounded()) * 5
    }
}
