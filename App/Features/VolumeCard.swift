import SwiftUI

/// Volume: a rolling number, mute and −/+ (hold to repeat), and the bar that swells under your finger.
struct VolumeCard: View {
    let volume: Int
    let isMuted: Bool
    let onChange: (Int) -> Void
    let onStep: (Int) -> Void
    let onToggleMute: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Volume")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(volume)")
                            .fontWeight(.medium)
                            .foregroundStyle(isMuted ? Theme.mutedNumber : Theme.text)
                            .contentTransition(.numericText(value: Double(volume)))
                        Text("of 100")
                            .foregroundStyle(Theme.muted)
                    }
                    .font(.system(size: 16))
                    .monospacedDigit()
                    .animation(.snappy, value: volume)
                }
                Spacer()
                HStack(spacing: 8) {
                    RoundIconButton(
                        systemImage: isMuted ? "speaker.slash" : "speaker.wave.1",
                        label: isMuted ? "Unmute" : "Mute",
                        isOn: isMuted,
                        action: onToggleMute
                    )
                    VolumeStepper(onStep: onStep)
                }
            }
            VolumeBar(value: volume, isMuted: isMuted, onChange: onChange)
                .padding(.top, -16)
        }
        .card()
    }
}

/// The −/+ pill. Holding either button keeps stepping.
private struct VolumeStepper: View {
    let onStep: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            step("minus", label: "Volume down", by: -1)
            Rectangle().fill(Theme.lineStrong).frame(width: 1, height: 18)
            step("plus", label: "Volume up", by: 1)
        }
        .frame(height: 38)
        .background(Theme.raised, in: Capsule())
    }

    private func step(_ symbol: String, label: String, by delta: Int) -> some View {
        Button {
            onStep(delta)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 44, height: 38)
                .contentShape(Rectangle())
        }
        .buttonRepeatBehavior(.enabled)
        .buttonStyle(.plain)
        .foregroundStyle(Theme.text)
        .accessibilityLabel(label)
    }
}

/// The capsule bar. Dragging raises a swell that follows your finger, with a tooltip showing the level.
/// Changes from elsewhere (−/+, the TV's own remote) slide the fill and pulse the swell at its end.
struct VolumeBar: View {
    let value: Int
    let isMuted: Bool
    let onChange: (Int) -> Void

    @State private var isDragging = false
    @State private var swellCenter: CGFloat = 0
    @State private var swell: CGFloat = 0
    @State private var pulse: Task<Void, Never>?

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            let fraction = CGFloat(value) / 100
            ZStack(alignment: .topLeading) {
                BulgeCapsule(start: 0, end: 1, center: swellCenter, amplitude: swell)
                    .fill(Theme.track)
                BulgeCapsule(start: 0, end: fraction, center: swellCenter, amplitude: swell)
                    .fill(isMuted ? Theme.mutedFill : Theme.blue)
                    .animation(isDragging ? nil : Theme.settle, value: fraction)
                ValueTip(text: "\(value)")
                    .position(x: min(max(swellCenter * width, 44), width - 44), y: 20)
                    .opacity(isDragging ? 1 : 0)
                    .scaleEffect(isDragging ? 1 : 0.92, anchor: .bottom)
                    .animation(.easeOut(duration: 0.16), value: isDragging)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let x = min(max(drag.location.x / width, 0), 1)
                        if !isDragging {
                            isDragging = true
                            pulse?.cancel()
                            withAnimation(Theme.bounce) { swell = 12 }
                        }
                        swellCenter = x
                        let level = Int((x * 100).rounded())
                        if level != value { onChange(level) }
                    }
                    .onEnded { _ in
                        isDragging = false
                        withAnimation(Theme.bounce) { swell = 0 }
                    }
            )
        }
        .frame(height: 96)
        .sensoryFeedback(.selection, trigger: value)
        .onChange(of: value) { _, newValue in
            guard !isDragging else { return }
            swellCenter = CGFloat(newValue) / 100
            withAnimation(Theme.bounce) { swell = 8 }
            pulse?.cancel()
            pulse = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                withAnimation(Theme.bounce) { swell = 0 }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Volume")
        .accessibilityValue(isMuted ? "\(value), muted" : "\(value)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onChange(min(100, value + 1))
            case .decrement: onChange(max(0, value - 1))
            @unknown default: break
            }
        }
    }
}
