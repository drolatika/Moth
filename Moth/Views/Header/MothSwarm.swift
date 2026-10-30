import SwiftUI

/// Five small moths. On Queue they loop around the title; as the pages swipe
/// toward Heard they drift one after another to the lantern and gather there.
/// Everything is a function of page progress and time, so swiping back reverses it.
struct MothSwarm: View {
    let progress: Double
    let time: Double
    let titleCenter: CGPoint
    let lanternCenter: CGPoint

    static let count = 5

    var body: some View {
        Canvas { context, _ in
            context.addFilter(.shadow(color: Color(hex: 0xFF9A5A).opacity(0.9), radius: 2.5))
            context.addFilter(.shadow(color: Manuscript.ember.opacity(0.45), radius: 7))
            for i in 0..<Self.count {
                let here = position(i, progress, time)
                let ahead = position(i, progress, time + 0.03)
                let heading = atan2(ahead.y - here.y, ahead.x - here.x) + .pi / 2
                let flap = 0.4 + 0.6 * abs(sin(time * 20 + Double(i) * 1.9))
                let scale = 0.5 + Double(i % 3) * 0.07

                var moth = context
                moth.translateBy(x: here.x, y: here.y)
                moth.rotate(by: .radians(heading))
                moth.scaleBy(x: scale, y: scale)
                Self.drawMoth(in: &moth, flap: flap)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Paths

    private func orbit(_ i: Int, _ t: Double) -> CGPoint {
        let n = Double(Self.count), d = Double(i)
        let phase = d * 2 * .pi / n + d * 0.3
        let speed = (1 + Double(i % 3) * 0.18) * (i % 2 == 0 ? -1 : 1) * 0.72
        let a = t * speed + phase
        let rx = 70 + Double(i % 3) * 6, ry = 24 + Double(i % 2) * 5
        return CGPoint(x: titleCenter.x + cos(a) * rx + sin(t * 2.3 + d) * 3,
                       y: titleCenter.y + sin(a) * ry + cos(t * 3.1 + d * 2) * 2.5)
    }

    private func gather(_ i: Int, _ t: Double) -> CGPoint {
        let d = Double(i)
        let phase = d * 2 * .pi / Double(Self.count)
        let speed = 1.3 + Double(i % 3) * 0.3
        let a = t * speed * (i % 2 == 0 ? -1 : 1) + phase
        let r = 15 + Double(i % 3) * 3
        return CGPoint(x: lanternCenter.x + cos(a) * r * 1.3 + sin(t * 4 + d) * 1.2,
                       y: lanternCenter.y - 6 + sin(a) * r * 0.6 + cos(t * 3.5 + d) * 1.2)
    }

    private func position(_ i: Int, _ p: Double, _ t: Double) -> CGPoint {
        let s = ease(clamp((p - 0.04 - Double(i) * 0.07) / 0.42))
        let from = orbit(i, t), to = gather(i, t)
        let lift = sin(.pi * s) * (12 + Double(i) * 3)
        return CGPoint(x: from.x + (to.x - from.x) * s, y: from.y + (to.y - from.y) * s - lift)
    }

    private func clamp(_ x: Double) -> Double { min(1, max(0, x)) }
    private func ease(_ x: Double) -> Double { x < 0.5 ? 2 * x * x : 1 - pow(-2 * x + 2, 2) / 2 }

    // MARK: Drawing (moth faces up, about 22×18 points before scaling)

    private static let foreWings: Path = {
        var p = Path()
        p.move(to: CGPoint(x: -1, y: -1.5)); p.addLine(to: CGPoint(x: -10, y: -6))
        p.addQuadCurve(to: CGPoint(x: -7, y: 1.5), control: CGPoint(x: -11.5, y: -1)); p.closeSubpath()
        p.move(to: CGPoint(x: 1, y: -1.5)); p.addLine(to: CGPoint(x: 10, y: -6))
        p.addQuadCurve(to: CGPoint(x: 7, y: 1.5), control: CGPoint(x: 11.5, y: -1)); p.closeSubpath()
        return p
    }()

    private static let hindWings: Path = {
        var p = Path()
        p.move(to: CGPoint(x: -1, y: 0))
        p.addQuadCurve(to: CGPoint(x: -6, y: 6), control: CGPoint(x: -7, y: 1))
        p.addQuadCurve(to: CGPoint(x: -0.5, y: 2.5), control: CGPoint(x: -2.5, y: 7)); p.closeSubpath()
        p.move(to: CGPoint(x: 1, y: 0))
        p.addQuadCurve(to: CGPoint(x: 6, y: 6), control: CGPoint(x: 7, y: 1))
        p.addQuadCurve(to: CGPoint(x: 0.5, y: 2.5), control: CGPoint(x: 2.5, y: 7)); p.closeSubpath()
        return p
    }()

    private static let antennae: Path = {
        var p = Path()
        p.move(to: CGPoint(x: -0.5, y: -3)); p.addQuadCurve(to: CGPoint(x: -4, y: -7.5), control: CGPoint(x: -2, y: -6.5))
        p.move(to: CGPoint(x: 0.5, y: -3)); p.addQuadCurve(to: CGPoint(x: 4, y: -7.5), control: CGPoint(x: 2, y: -6.5))
        return p
    }()

    private static let thorax = Path(ellipseIn: CGRect(x: -1.3, y: -3.2, width: 2.6, height: 8.4))

    private static func drawMoth(in context: inout GraphicsContext, flap: Double) {
        var wings = context
        wings.scaleBy(x: flap, y: 1)
        for path in [foreWings, hindWings] {
            wings.fill(path, with: .color(Manuscript.mothCream))
            wings.stroke(path, with: .color(Manuscript.mothLine), style: StrokeStyle(lineWidth: 0.7, lineJoin: .round))
        }
        context.fill(thorax, with: .color(Manuscript.mothCream))
        context.stroke(antennae, with: .color(Manuscript.mothCream), lineWidth: 0.6)
    }
}
