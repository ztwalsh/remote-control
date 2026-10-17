import SwiftUI

/// A stretch of the sleep dial's ring with round ends. Angles are radians, clockwise from 12 o'clock.
/// The outer edge swells around `swellAngle`, like the volume bar's top edge.
struct RingArc: Shape {
    var startAngle: Double
    var endAngle: Double
    var swellAngle: Double
    var swell: Double
    /// Radii on a 280-point dial; scaled to the shape's rect.
    var innerRadius: CGFloat = 98
    var outerRadius: CGFloat = 124

    var animatableData: AnimatablePair<Double, AnimatablePair<Double, Double>> {
        get { AnimatablePair(endAngle, AnimatablePair(swellAngle, swell)) }
        set {
            endAngle = newValue.first
            swellAngle = newValue.second.first
            swell = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let span = endAngle - startAngle
        guard span > 0.002 else { return path }

        let scale = min(rect.width, rect.height) / 280
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let inner = innerRadius * scale

        func outer(_ angle: Double) -> CGFloat {
            (outerRadius + CGFloat(swell * exp(-pow(RingArc.distance(angle, swellAngle) / 0.36, 2)))) * scale
        }
        func point(_ radius: CGFloat, _ angle: Double) -> CGPoint {
            CGPoint(x: center.x + radius * CGFloat(sin(angle)), y: center.y - radius * CGFloat(cos(angle)))
        }
        // Half-circle cap around `angle`, from the outer edge to the inner one, bulging forward (or backward).
        func cap(at angle: Double, forward: Bool) {
            let outerRadius = outer(angle)
            let capRadius = (outerRadius - inner) / 2
            let capCenter = point(inner + capRadius, angle)
            let radial = CGVector(dx: sin(angle), dy: -cos(angle))
            let tangent = CGVector(dx: cos(angle), dy: sin(angle))
            let sign: CGFloat = forward ? 1 : -1
            for step in 1...12 {
                let theta = Double.pi * Double(step) / 12
                let r = CGFloat(cos(theta)) * sign
                let t = CGFloat(sin(theta)) * sign
                path.addLine(to: CGPoint(
                    x: capCenter.x + capRadius * (radial.dx * r + tangent.dx * t),
                    y: capCenter.y + capRadius * (radial.dy * r + tangent.dy * t)
                ))
            }
        }

        let steps = max(2, Int((span / 0.03).rounded(.up)))
        for step in 0...steps {
            let angle = startAngle + span * Double(step) / Double(steps)
            let p = point(outer(angle), angle)
            if step == 0 {
                path.move(to: p)
            } else {
                path.addLine(to: p)
            }
        }
        cap(at: endAngle, forward: true)
        for step in stride(from: steps - 1, through: 0, by: -1) {
            let angle = startAngle + span * Double(step) / Double(steps)
            path.addLine(to: point(inner, angle))
        }
        cap(at: startAngle, forward: false)
        path.closeSubpath()
        return path
    }

    static func distance(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 2 * .pi)
        return d > .pi ? 2 * .pi - d : d
    }
}
