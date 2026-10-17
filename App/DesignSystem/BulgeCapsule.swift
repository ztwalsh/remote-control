import SwiftUI

/// A capsule with a flat bottom whose top edge swells upward around `center`.
/// The bar sits at the bottom of the shape's rect; the space above is room for the swell and tooltip.
struct BulgeCapsule: Shape {
    /// Where the capsule starts and ends, as fractions of the width.
    var start: CGFloat
    var end: CGFloat
    /// Where the swell peaks, as a fraction of the width.
    var center: CGFloat
    /// How far, in points, the top edge rises at the peak.
    var amplitude: CGFloat
    var barHeight: CGFloat = 30
    var spread: CGFloat = 34

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(AnimatablePair(start, end), AnimatablePair(center, amplitude)) }
        set {
            start = newValue.first.first
            end = newValue.first.second
            center = newValue.second.first
            amplitude = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let x0 = rect.minX + start * rect.width
        let x1 = rect.minX + end * rect.width
        let width = x1 - x0
        guard width > 0.5 else { return path }

        let bottom = rect.maxY
        let top = bottom - barHeight
        let peak = rect.minX + center * rect.width
        func y(_ x: CGFloat) -> CGFloat {
            top - amplitude * exp(-pow((x - peak) / spread, 2))
        }

        let radius = barHeight / 2
        let leftRadius = min(radius, width / 2)
        let rightRadius = min(radius, width - leftRadius)
        let a = x0 + leftRadius
        let b = x1 - rightRadius

        path.move(to: CGPoint(x: a, y: bottom))
        path.addCurve(to: CGPoint(x: a, y: y(a)), control1: CGPoint(x: x0, y: bottom), control2: CGPoint(x: x0, y: y(a)))
        var x = a
        while x < b {
            x = min(b, x + 3)
            path.addLine(to: CGPoint(x: x, y: y(x)))
        }
        path.addCurve(to: CGPoint(x: b, y: bottom), control1: CGPoint(x: x1, y: y(b)), control2: CGPoint(x: x1, y: bottom))
        path.closeSubpath()
        return path
    }
}
