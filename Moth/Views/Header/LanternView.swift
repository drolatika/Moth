import SwiftUI

/// The stone lantern (after a yukimi-style ishidōrō): wide mossy roof, rounded
/// firebox with a front window and side opening, a platform disc and curved legs.
/// Drawn on a 60×64 grid; `lit` runs 0 (dark) to ~1.2 (flaring).
struct LanternView: View {
    var lit: Double
    var time: Double

    static func flicker(_ t: Double) -> Double {
        0.8 + 0.09 * sin(t * 13) + 0.07 * sin(t * 29 + 1.3) + 0.04 * sin(t * 7.1 + 0.4)
    }

    private static let stone = Color(hex: 0x7B766B)
    private static let dark = Color(hex: 0x3E3A34)
    private static let highlight = Color(hex: 0xA39C8E)
    private static let moss = Color(hex: 0x6F7A52)
    private static let unlitWindow = Color(hex: 0x201D1A)

    var body: some View {
        let k = max(0, lit) * Self.flicker(time)
        Canvas { context, size in
            context.scaleBy(x: size.width / 60, y: size.height / 64)
            draw(in: &context, k: k)
        }
        .frame(width: 60, height: 64)
        .background {
            RadialGradient(
                colors: [Manuscript.flame.opacity(min(1, 1.05 * k)), Manuscript.ember.opacity(0.5 * min(1, k)), .clear],
                center: .center, startRadius: 0, endRadius: 16 + 34 * k
            )
            .frame(width: 160, height: 140)
            .offset(y: -3)
            .allowsHitTesting(false)
        }
        .shadow(color: Manuscript.ember.opacity(lit > 0 ? 0.3 + 0.45 * min(1, k) : 0), radius: 6 + 14 * k)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func draw(in context: inout GraphicsContext, k: Double) {
        let lineWidth = 0.8
        let isLit = k > 0.03

        // Legs: curved and splayed, with an arch between.
        var legs = Path()
        legs.move(to: CGPoint(x: 11, y: 44))
        legs.addLine(to: CGPoint(x: 49, y: 44))
        legs.addQuadCurve(to: CGPoint(x: 46, y: 52.5), control: CGPoint(x: 50, y: 50))
        legs.addQuadCurve(to: CGPoint(x: 46.5, y: 59), control: CGPoint(x: 43.5, y: 55))
        legs.addLine(to: CGPoint(x: 50, y: 62.5))
        legs.addLine(to: CGPoint(x: 42.5, y: 62.5))
        legs.addQuadCurve(to: CGPoint(x: 38, y: 54), control: CGPoint(x: 40.5, y: 56.5))
        legs.addQuadCurve(to: CGPoint(x: 22, y: 54), control: CGPoint(x: 30, y: 50.5))
        legs.addQuadCurve(to: CGPoint(x: 17.5, y: 62.5), control: CGPoint(x: 19.5, y: 56.5))
        legs.addLine(to: CGPoint(x: 10, y: 62.5))
        legs.addLine(to: CGPoint(x: 13.5, y: 59))
        legs.addQuadCurve(to: CGPoint(x: 14, y: 52.5), control: CGPoint(x: 16.5, y: 55))
        legs.addQuadCurve(to: CGPoint(x: 11, y: 44), control: CGPoint(x: 10, y: 50))
        legs.closeSubpath()
        stoneFill(legs, in: &context, lineWidth: lineWidth)

        // Platform disc with an inscription band.
        var platform = Path()
        platform.move(to: CGPoint(x: 5, y: 38.5))
        platform.addQuadCurve(to: CGPoint(x: 55, y: 38.5), control: CGPoint(x: 30, y: 35.5))
        platform.addLine(to: CGPoint(x: 55, y: 43.5))
        platform.addQuadCurve(to: CGPoint(x: 5, y: 43.5), control: CGPoint(x: 30, y: 46.5))
        platform.closeSubpath()
        stoneFill(platform, in: &context, lineWidth: lineWidth)
        if isLit {
            var spill = Path()
            spill.move(to: CGPoint(x: 5, y: 38.5))
            spill.addQuadCurve(to: CGPoint(x: 55, y: 38.5), control: CGPoint(x: 30, y: 35.5))
            spill.addQuadCurve(to: CGPoint(x: 5, y: 38.5), control: CGPoint(x: 30, y: 40.5))
            context.fill(spill, with: .color(Manuscript.ember.opacity(0.55 * min(1, k))))
        }
        var band = Path()
        band.move(to: CGPoint(x: 9, y: 41.5))
        band.addQuadCurve(to: CGPoint(x: 51, y: 41.5), control: CGPoint(x: 30, y: 43.6))
        context.stroke(band, with: .color(Self.dark.opacity(0.8)), style: StrokeStyle(lineWidth: 0.45, dash: [1.2, 0.8]))

        // Firebox.
        var box = Path()
        box.move(to: CGPoint(x: 13, y: 20))
        box.addLine(to: CGPoint(x: 47, y: 20))
        box.addQuadCurve(to: CGPoint(x: 47, y: 37.5), control: CGPoint(x: 50.5, y: 28.5))
        box.addLine(to: CGPoint(x: 13, y: 37.5))
        box.addQuadCurve(to: CGPoint(x: 13, y: 20), control: CGPoint(x: 9.5, y: 28.5))
        box.closeSubpath()
        stoneFill(box, in: &context, lineWidth: lineWidth)

        let window = Path(roundedRect: CGRect(x: 19, y: 23, width: 18, height: 11), cornerRadius: 0.8)
        var sideWindow = Path()
        sideWindow.move(to: CGPoint(x: 42, y: 24))
        sideWindow.addQuadCurve(to: CGPoint(x: 42, y: 33), control: CGPoint(x: 45.5, y: 28.5))
        sideWindow.addQuadCurve(to: CGPoint(x: 42, y: 24), control: CGPoint(x: 40.5, y: 28.5))
        sideWindow.closeSubpath()

        if isLit {
            // Light bleeding out of the openings.
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: 2.6))
                layer.opacity = min(1, k)
                layer.fill(window, with: .color(Color(hex: 0xFF9A50)))
                layer.fill(sideWindow, with: .color(Color(hex: 0xFF9A50)))
            }
            context.fill(window, with: .radialGradient(
                Gradient(colors: [Color(hex: 0xFFF4D6), Color(hex: 0xFFD089), Color(hex: 0xF08A3C)]),
                center: CGPoint(x: 27, y: 28.5), startRadius: 0, endRadius: 12
            ))
            context.fill(sideWindow, with: .color(Color(hex: 0xFFC27E).opacity(0.3 + 0.7 * min(1, k))))
        } else {
            context.fill(window, with: .color(Self.unlitWindow))
            context.fill(sideWindow, with: .color(Self.unlitWindow))
        }
        context.stroke(window, with: .color(Self.dark), lineWidth: 0.7)
        context.stroke(sideWindow, with: .color(Self.dark), lineWidth: 0.5)

        // Roof: wide flat cap, lit from below, moss on top, small knob.
        var roof = Path()
        roof.move(to: CGPoint(x: 1.5, y: 17.5))
        roof.addQuadCurve(to: CGPoint(x: 14, y: 10), control: CGPoint(x: 3, y: 12))
        roof.addQuadCurve(to: CGPoint(x: 46, y: 10), control: CGPoint(x: 30, y: 6.5))
        roof.addQuadCurve(to: CGPoint(x: 58.5, y: 17.5), control: CGPoint(x: 57, y: 12))
        roof.addQuadCurve(to: CGPoint(x: 50, y: 20.5), control: CGPoint(x: 57, y: 20.5))
        roof.addLine(to: CGPoint(x: 10, y: 20.5))
        roof.addQuadCurve(to: CGPoint(x: 1.5, y: 17.5), control: CGPoint(x: 3, y: 20.5))
        roof.closeSubpath()
        stoneFill(roof, in: &context, lineWidth: lineWidth)
        if isLit {
            var underside = Path()
            underside.move(to: CGPoint(x: 4, y: 18.6))
            underside.addQuadCurve(to: CGPoint(x: 56, y: 18.6), control: CGPoint(x: 30, y: 21.6))
            underside.addLine(to: CGPoint(x: 50, y: 20.5))
            underside.addLine(to: CGPoint(x: 10, y: 20.5))
            underside.closeSubpath()
            context.fill(underside, with: .color(Color(hex: 0xFFB070).opacity(0.5 * min(1, k))))
        }
        var moss = Path()
        moss.move(to: CGPoint(x: 6, y: 13.8))
        moss.addQuadCurve(to: CGPoint(x: 30, y: 9.2), control: CGPoint(x: 18, y: 9.6))
        moss.move(to: CGPoint(x: 36, y: 9.5))
        moss.addQuadCurve(to: CGPoint(x: 54, y: 13.6), control: CGPoint(x: 46, y: 10.4))
        context.stroke(moss, with: .color(Self.moss.opacity(0.85)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
        var ridge = Path()
        ridge.move(to: CGPoint(x: 10, y: 12.6))
        ridge.addQuadCurve(to: CGPoint(x: 50, y: 12.4), control: CGPoint(x: 30, y: 8))
        context.stroke(ridge, with: .color(Self.highlight.opacity(0.7)), lineWidth: 0.5)

        var knob = Path()
        knob.move(to: CGPoint(x: 25, y: 9))
        knob.addQuadCurve(to: CGPoint(x: 30, y: 3.8), control: CGPoint(x: 25.5, y: 4.2))
        knob.addQuadCurve(to: CGPoint(x: 35, y: 9), control: CGPoint(x: 34.5, y: 4.2))
        knob.closeSubpath()
        stoneFill(knob, in: &context, lineWidth: 0.7)
        let cap = Path(ellipseIn: CGRect(x: 28, y: 3, width: 4, height: 2.4))
        context.fill(cap, with: .color(Self.highlight))
        context.stroke(cap, with: .color(Self.dark), lineWidth: 0.5)
    }

    private func stoneFill(_ path: Path, in context: inout GraphicsContext, lineWidth: CGFloat) {
        context.fill(path, with: .color(Self.stone))
        context.stroke(path, with: .color(Self.dark), style: StrokeStyle(lineWidth: lineWidth, lineJoin: .round))
    }
}
