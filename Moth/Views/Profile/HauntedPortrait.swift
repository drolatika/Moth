import SwiftUI

/// Your picture in an old gilded rococo frame: a shell crest, scrolls and acanthus
/// leaves, the gilt worn dark, cobwebs strung off the frame, a spider idling on its
/// thread, and a candle beside it that flickers and warms the gold.
/// Drawn on a 300×300 grid.
struct HauntedPortrait: View {
    var photo: UIImage?

    static let size: CGFloat = 300
    private static let center = CGPoint(x: 140, y: 146)
    private static let radii = CGSize(width: 74, height: 94)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topLeading) {
            portrait
                .frame(width: Self.radii.width * 2, height: Self.radii.height * 2)
                .offset(x: Self.center.x - Self.radii.width, y: Self.center.y - Self.radii.height)

            Canvas { context, _ in
                FrameArt.drawFrame(in: &context, center: Self.center, radii: Self.radii)
                FrameArt.drawCobwebs(in: &context, center: Self.center, radii: Self.radii)
            }

            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
                let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 10_000)
                Canvas { context, _ in
                    FrameArt.drawCandle(in: &context, time: t, base: CGPoint(x: 262, y: 262))
                    FrameArt.drawSpider(in: &context, time: t, anchor: CGPoint(x: Self.center.x - Self.radii.width - 17, y: Self.center.y + 26))
                }
            }
        }
        .frame(width: Self.size, height: Self.size)
        .contentShape(Rectangle())
        .accessibilityHidden(true)
    }

    private var portrait: some View {
        ZStack {
            if let photo {
                Image(uiImage: photo).resizable().scaledToFill()
            } else {
                LinearGradient(colors: [Color(hex: 0x2A2420), Color(hex: 0x15110F)], startPoint: .top, endPoint: .bottom)
                Image(systemName: "person.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Color(hex: 0x4A4038))
                    .offset(y: 14)
            }
            // Old varnish: warm, darker toward the edges.
            RadialGradient(colors: [.clear, Color(hex: 0x1A0F06).opacity(0.55)], center: .center, startRadius: 40, endRadius: 110)
            Color(hex: 0xC08A3E).opacity(0.08).blendMode(.multiply)
        }
        .clipShape(Ellipse())
    }
}

/// The drawing itself, kept apart from the view so each layer redraws only when it must.
enum FrameArt {
    static let gold = Color(hex: 0xB8954A)
    static let goldLight = Color(hex: 0xE9D395)
    static let goldDark = Color(hex: 0x5C4520)
    static let tarnish = Color(hex: 0x2E2618)

    // MARK: Frame

    static func drawFrame(in context: inout GraphicsContext, center c: CGPoint, radii r: CGSize) {
        // The oval moulding: a gilt band between two ellipses.
        let inner = CGRect(x: c.x - r.width - 1, y: c.y - r.height - 1, width: (r.width + 1) * 2, height: (r.height + 1) * 2)
        let outer = inner.insetBy(dx: -8, dy: -8)
        var band = Path(ellipseIn: outer)
        band.addEllipse(in: inner)
        context.fill(band, with: .linearGradient(
            Gradient(colors: [goldLight, gold, goldDark, gold, goldDark]),
            startPoint: CGPoint(x: outer.minX, y: outer.minY), endPoint: CGPoint(x: outer.maxX, y: outer.maxY)
        ), style: FillStyle(eoFill: true))
        context.stroke(Path(ellipseIn: outer), with: .color(tarnish), lineWidth: 1)
        context.stroke(Path(ellipseIn: inner), with: .color(tarnish), lineWidth: 1.2)

        // A row of beads along the middle of the band.
        let beads = 54
        for i in 0..<beads {
            let a = Double(i) / Double(beads) * 2 * .pi
            let p = CGPoint(x: c.x + (r.width + 5) * cos(a), y: c.y + (r.height + 5) * sin(a))
            let bead = Path(ellipseIn: CGRect(x: p.x - 1.1, y: p.y - 1.1, width: 2.2, height: 2.2))
            context.fill(bead, with: .color(goldLight.opacity(0.85)))
        }

        let top = CGPoint(x: c.x, y: c.y - r.height - 9)
        let bottom = CGPoint(x: c.x, y: c.y + r.height + 9)
        let mirror = CGAffineTransform(translationX: 2 * c.x, y: 0).scaledBy(x: -1, y: 1)

        // Crest: a scalloped shell with a scroll curling away on each side.
        drawShell(in: &context, base: top)
        var crestScroll = Path()
        crestScroll.move(to: CGPoint(x: top.x - 8, y: top.y + 1))
        crestScroll.addCurve(to: CGPoint(x: top.x - 42, y: top.y + 6),
                             control1: CGPoint(x: top.x - 20, y: top.y - 10), control2: CGPoint(x: top.x - 34, y: top.y - 8))
        addCurl(to: &crestScroll, at: CGPoint(x: top.x - 42, y: top.y + 6), radius: 6, start: -.pi / 2, turns: 1.1, clockwise: false)
        gild(crestScroll, in: &context, width: 2.2)
        gild(crestScroll.applying(mirror), in: &context, width: 2.2)

        // Sides: a C-scroll on each, curled at both ends.
        var side = Path()
        let sx = c.x - r.width - 10
        side.move(to: CGPoint(x: sx + 2, y: c.y - 30))
        side.addCurve(to: CGPoint(x: sx + 2, y: c.y + 30),
                      control1: CGPoint(x: sx - 14, y: c.y - 14), control2: CGPoint(x: sx - 14, y: c.y + 14))
        addCurl(to: &side, at: CGPoint(x: sx + 2, y: c.y + 30), radius: 4.5, start: .pi, turns: 1, clockwise: true)
        var sideTop = Path()
        sideTop.move(to: CGPoint(x: sx + 2, y: c.y - 30))
        addCurl(to: &sideTop, at: CGPoint(x: sx + 2, y: c.y - 30), radius: 4.5, start: .pi, turns: 1, clockwise: false)
        side.addPath(sideTop)
        gild(side, in: &context, width: 2.4)
        gild(side.applying(mirror), in: &context, width: 2.4)

        // Bottom: two acanthus leaves sweeping up from a small knot.
        var leaf = Path()
        leaf.move(to: CGPoint(x: bottom.x - 2, y: bottom.y + 4))
        leaf.addQuadCurve(to: CGPoint(x: bottom.x - 50, y: bottom.y - 8), control: CGPoint(x: bottom.x - 26, y: bottom.y + 16))
        leaf.addQuadCurve(to: CGPoint(x: bottom.x - 2, y: bottom.y - 2), control: CGPoint(x: bottom.x - 34, y: bottom.y + 2))
        leaf.closeSubpath()
        context.fill(leaf, with: .linearGradient(Gradient(colors: [goldLight, gold, goldDark]),
                                                 startPoint: CGPoint(x: bottom.x - 50, y: bottom.y - 8),
                                                 endPoint: CGPoint(x: bottom.x, y: bottom.y + 4)))
        context.fill(leaf.applying(mirror), with: .linearGradient(Gradient(colors: [goldLight, gold, goldDark]),
                                                                  startPoint: CGPoint(x: bottom.x + 50, y: bottom.y - 8),
                                                                  endPoint: CGPoint(x: bottom.x, y: bottom.y + 4)))
        var vein = Path()
        vein.move(to: CGPoint(x: bottom.x - 4, y: bottom.y + 1))
        vein.addQuadCurve(to: CGPoint(x: bottom.x - 44, y: bottom.y - 6), control: CGPoint(x: bottom.x - 28, y: bottom.y + 8))
        var tip = Path()
        tip.move(to: CGPoint(x: bottom.x - 50, y: bottom.y - 8))
        addCurl(to: &tip, at: CGPoint(x: bottom.x - 50, y: bottom.y - 8), radius: 4, start: 0, turns: 1, clockwise: false)
        vein.addPath(tip)
        for path in [vein, vein.applying(mirror)] {
            context.stroke(path, with: .color(tarnish.opacity(0.8)), lineWidth: 0.8)
        }
        let knot = Path(ellipseIn: CGRect(x: bottom.x - 5, y: bottom.y - 2, width: 10, height: 8))
        context.fill(knot, with: .color(gold))
        context.stroke(knot, with: .color(tarnish), lineWidth: 0.8)

        // Small leaf sprigs on the four diagonals.
        for angle in [-0.78, -2.36, 0.85, 2.29] {
            let p = CGPoint(x: c.x + (r.width + 9) * cos(angle), y: c.y + (r.height + 9) * sin(angle))
            var sprig = Path()
            let out = CGPoint(x: p.x + 11 * cos(angle), y: p.y + 11 * sin(angle))
            sprig.move(to: p)
            sprig.addQuadCurve(to: out, control: CGPoint(x: p.x + 9 * cos(angle - 0.7), y: p.y + 9 * sin(angle - 0.7)))
            sprig.addQuadCurve(to: p, control: CGPoint(x: p.x + 9 * cos(angle + 0.7), y: p.y + 9 * sin(angle + 0.7)))
            context.fill(sprig, with: .color(gold))
            context.stroke(sprig, with: .color(tarnish.opacity(0.9)), lineWidth: 0.7)
        }

        // Age: dark patches where the gilt has worn through.
        for (x, y, w) in [(-0.6, -0.95, 14.0), (0.92, 0.3, 10.0), (-0.85, 0.55, 12.0), (0.3, 0.97, 9.0)] {
            let p = CGPoint(x: c.x + (r.width + 5) * x, y: c.y + (r.height + 5) * y)
            context.fill(Path(ellipseIn: CGRect(x: p.x - w / 2, y: p.y - 3, width: w, height: 6)),
                         with: .color(tarnish.opacity(0.35)))
        }
    }

    private static func drawShell(in context: inout GraphicsContext, base: CGPoint) {
        let ribs = 7
        let radius: CGFloat = 22
        let ends = (0...ribs).map { i -> CGPoint in
            let a = -Double.pi + 0.35 + Double(i) / Double(ribs) * (Double.pi - 0.7)
            return CGPoint(x: base.x + radius * cos(a), y: base.y + 2 + radius * 0.95 * sin(a))
        }
        var shell = Path()
        shell.move(to: base)
        shell.addLine(to: ends[0])
        for i in 1...ribs {
            let mid = CGPoint(x: (ends[i - 1].x + ends[i].x) / 2, y: (ends[i - 1].y + ends[i].y) / 2)
            let bulge = CGPoint(x: base.x + (mid.x - base.x) * 1.22, y: base.y + (mid.y - base.y) * 1.22)
            shell.addQuadCurve(to: ends[i], control: bulge)
        }
        shell.closeSubpath()
        context.fill(shell, with: .linearGradient(Gradient(colors: [goldLight, gold, goldDark]),
                                                  startPoint: CGPoint(x: base.x, y: base.y - radius), endPoint: base))
        context.stroke(shell, with: .color(tarnish), lineWidth: 1)
        var ribLines = Path()
        for end in ends.dropFirst().dropLast() {
            ribLines.move(to: CGPoint(x: base.x, y: base.y - 1))
            ribLines.addLine(to: end)
        }
        context.stroke(ribLines, with: .color(goldDark.opacity(0.9)), lineWidth: 0.7)
    }

    /// Appends a spiral curl that starts at `point` and winds inward.
    private static func addCurl(to path: inout Path, at point: CGPoint, radius: CGFloat, start: Double, turns: Double, clockwise: Bool) {
        let steps = 24
        let direction: Double = clockwise ? 1 : -1
        // The spiral's centre sits one radius away from the start point.
        let center = CGPoint(x: point.x - radius * cos(start), y: point.y - radius * sin(start))
        path.move(to: point)
        for step in 1...steps {
            let t = Double(step) / Double(steps)
            let a = start + direction * t * turns * 2 * .pi
            let r = radius * (1 - 0.75 * t)
            path.addLine(to: CGPoint(x: center.x + r * cos(a), y: center.y + r * sin(a)))
        }
    }

    /// A gilt stroke: dark underside, gold body, a thin highlight.
    private static func gild(_ path: Path, in context: inout GraphicsContext, width: CGFloat) {
        let round = StrokeStyle(lineWidth: width + 1.6, lineCap: .round, lineJoin: .round)
        context.stroke(path.applying(CGAffineTransform(translationX: 0, y: 0.8)), with: .color(tarnish.opacity(0.9)), style: round)
        context.stroke(path, with: .color(gold), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
        context.stroke(path.applying(CGAffineTransform(translationX: -0.3, y: -0.4)), with: .color(goldLight.opacity(0.6)),
                       style: StrokeStyle(lineWidth: width * 0.35, lineCap: .round, lineJoin: .round))
    }

    // MARK: Cobwebs

    static func drawCobwebs(in context: inout GraphicsContext, center c: CGPoint, radii r: CGSize) {
        // Upper left, strung from the frame to the crest scroll and out to the wall.
        web(in: &context, anchor: CGPoint(x: c.x - r.width * 0.62, y: c.y - r.height * 0.84),
            from: -2.95, to: -1.35, length: 52, rings: 5, seed: 1)
        // A smaller one strung between the right side scroll and the frame above it.
        web(in: &context, anchor: CGPoint(x: c.x + r.width + 12, y: c.y - 30),
            from: -2.75, to: -1.45, length: 34, rings: 4, seed: 2)
        // Loose strands drooping between the frame and the crest.
        var strand = Path()
        strand.move(to: CGPoint(x: c.x + 10, y: c.y - r.height - 14))
        strand.addQuadCurve(to: CGPoint(x: c.x + 46, y: c.y - r.height + 2), control: CGPoint(x: c.x + 30, y: c.y - r.height + 6))
        strand.move(to: CGPoint(x: c.x - r.width - 12, y: c.y + 32))
        strand.addQuadCurve(to: CGPoint(x: c.x - r.width + 2, y: c.y + 70), control: CGPoint(x: c.x - r.width - 12, y: c.y + 58))
        context.stroke(strand, with: .color(.white.opacity(0.22)), lineWidth: 0.5)
    }

    private static func web(in context: inout GraphicsContext, anchor: CGPoint, from: Double, to: Double,
                            length: CGFloat, rings: Int, seed: Int) {
        let threads = 7
        let ends = (0..<threads).map { i -> (angle: Double, length: CGFloat) in
            let jitter = sin(Double(i * 7 + seed * 13)) * 0.18
            return (from + (to - from) * Double(i) / Double(threads - 1), length * CGFloat(1 + jitter))
        }
        var path = Path()
        for end in ends {
            path.move(to: anchor)
            path.addLine(to: CGPoint(x: anchor.x + end.length * cos(end.angle), y: anchor.y + end.length * sin(end.angle)))
        }
        for ring in 1...rings {
            let fraction = CGFloat(ring) / CGFloat(rings + 1)
            for i in 1..<threads {
                let a0 = ends[i - 1], a1 = ends[i]
                let p0 = CGPoint(x: anchor.x + a0.length * fraction * cos(a0.angle), y: anchor.y + a0.length * fraction * sin(a0.angle))
                let p1 = CGPoint(x: anchor.x + a1.length * fraction * cos(a1.angle), y: anchor.y + a1.length * fraction * sin(a1.angle))
                // Each strand sags toward the centre.
                let mid = (a0.angle + a1.angle) / 2
                let sag = (a0.length + a1.length) / 2 * fraction * 0.84
                let control = CGPoint(x: anchor.x + sag * cos(mid), y: anchor.y + sag * sin(mid))
                if ring == rings && i % 3 == 0 { continue }   // a broken strand or two
                path.move(to: p0)
                path.addQuadCurve(to: p1, control: control)
            }
        }
        context.stroke(path, with: .color(.white.opacity(0.26)), lineWidth: 0.5)
    }

    // MARK: Candle and spider

    static func drawCandle(in context: inout GraphicsContext, time t: Double, base: CGPoint) {
        let flicker = 0.82 + 0.1 * sin(t * 11) + 0.06 * sin(t * 23 + 1.1) + 0.04 * sin(t * 5.3)
        let sway = 1.2 * sin(t * 2.1) + 0.6 * sin(t * 5.7)
        let width: CGFloat = 16, height: CGFloat = 44
        let top = base.y - height
        let flameBase = CGPoint(x: base.x, y: top - 3)

        // Warm light falling on the frame and the wall.
        context.drawLayer { layer in
            layer.blendMode = .plusLighter
            let glow = Path(ellipseIn: CGRect(x: flameBase.x - 120, y: flameBase.y - 110, width: 240, height: 220))
            layer.fill(glow, with: .radialGradient(
                Gradient(colors: [Manuscript.flame.opacity(0.26 * flicker), Manuscript.ember.opacity(0.1 * flicker), .clear]),
                center: CGPoint(x: flameBase.x + sway, y: flameBase.y - 6), startRadius: 0, endRadius: 115 * flicker
            ))
        }

        // Brass dish.
        let dish = Path(ellipseIn: CGRect(x: base.x - 17, y: base.y - 4, width: 34, height: 9))
        context.fill(dish, with: .linearGradient(Gradient(colors: [goldLight, gold, goldDark]),
                                                 startPoint: CGPoint(x: base.x, y: base.y - 4), endPoint: CGPoint(x: base.x, y: base.y + 5)))
        context.stroke(dish, with: .color(tarnish), lineWidth: 0.8)

        // Wax, with drips over the rim and a lit side facing the flame.
        var wax = Path()
        wax.move(to: CGPoint(x: base.x - width / 2, y: base.y))
        wax.addLine(to: CGPoint(x: base.x - width / 2, y: top + 3))
        wax.addQuadCurve(to: CGPoint(x: base.x + width / 2, y: top + 3), control: CGPoint(x: base.x, y: top - 1))
        wax.addLine(to: CGPoint(x: base.x + width / 2, y: base.y))
        wax.closeSubpath()
        context.fill(wax, with: .linearGradient(Gradient(colors: [Color(hex: 0xBFAE8E), Color(hex: 0xEADCBF), Color(hex: 0x9C8B6E)]),
                                                startPoint: CGPoint(x: base.x - width / 2, y: 0), endPoint: CGPoint(x: base.x + width / 2, y: 0)))
        var drips = Path()
        for (x, length) in [(-5.0, 11.0), (2.0, 6.0), (5.5, 16.0)] {
            drips.addRoundedRect(in: CGRect(x: base.x + x - 1.6, y: top + 1, width: 3.2, height: length),
                                 cornerSize: CGSize(width: 1.6, height: 1.6))
        }
        context.fill(drips, with: .color(Color(hex: 0xF2E7CF)))
        context.stroke(wax, with: .color(Color(hex: 0x6E5E44).opacity(0.7)), lineWidth: 0.6)

        // Wick and flame.
        var wick = Path()
        wick.move(to: CGPoint(x: base.x, y: top + 1))
        wick.addQuadCurve(to: CGPoint(x: base.x + 0.8, y: top - 4), control: CGPoint(x: base.x - 0.6, y: top - 2))
        context.stroke(wick, with: .color(Color(hex: 0x2A211A)), lineWidth: 1.1)

        let flameHeight = 17 * flicker
        let tip = CGPoint(x: flameBase.x + sway * 1.6, y: flameBase.y - flameHeight)
        var flame = Path()
        flame.move(to: CGPoint(x: flameBase.x, y: flameBase.y + 2))
        flame.addQuadCurve(to: tip, control: CGPoint(x: flameBase.x - 6.5, y: flameBase.y - flameHeight * 0.3))
        flame.addQuadCurve(to: CGPoint(x: flameBase.x, y: flameBase.y + 2), control: CGPoint(x: flameBase.x + 6.5, y: flameBase.y - flameHeight * 0.3))
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 3))
            layer.fill(flame, with: .color(Manuscript.ember.opacity(0.8)))
        }
        context.fill(flame, with: .linearGradient(
            Gradient(colors: [Color(hex: 0xFFF6DD), Color(hex: 0xFFD27A), Color(hex: 0xF07A2A)]),
            startPoint: CGPoint(x: flameBase.x, y: flameBase.y), endPoint: tip
        ))
        let core = Path(ellipseIn: CGRect(x: flameBase.x - 1.6, y: flameBase.y - 5, width: 3.2, height: 6))
        context.fill(core, with: .color(Color(hex: 0x4A6BD8).opacity(0.55)))
    }

    static func drawSpider(in context: inout GraphicsContext, time t: Double, anchor: CGPoint) {
        // It drifts down and back up very slowly, turning a little on its thread.
        let drop = 34 + 10 * sin(t * 0.35) + 2 * sin(t * 1.3)
        let swing = 1.5 * sin(t * 0.8)
        let body = CGPoint(x: anchor.x + swing, y: anchor.y + drop)
        var thread = Path()
        thread.move(to: anchor)
        thread.addLine(to: body)
        context.stroke(thread, with: .color(.white.opacity(0.3)), lineWidth: 0.5)

        var legs = Path()
        for side in [-1.0, 1.0] {
            for i in 0..<4 {
                let a = (-0.9 + Double(i) * 0.6)
                let knee = CGPoint(x: body.x + side * 3.2 * cos(a), y: body.y - 2.2 + 3 * sin(a))
                let foot = CGPoint(x: body.x + side * 5.2 * cos(a * 0.8), y: body.y + 0.6 + 3.6 * sin(a))
                legs.move(to: body)
                legs.addLine(to: knee)
                legs.addLine(to: foot)
            }
        }
        // Dark, with a faint rim of candlelight so it shows on a dark wall too.
        let spider = Color(hex: 0x2B241E)
        let abdomen = Path(ellipseIn: CGRect(x: body.x - 2.2, y: body.y - 1.4, width: 4.4, height: 4.6))
        let head = Path(ellipseIn: CGRect(x: body.x - 1.3, y: body.y - 3.4, width: 2.6, height: 2.4))
        context.stroke(legs, with: .color(Color(hex: 0x8A7A66).opacity(0.5)), lineWidth: 1.1)
        context.stroke(legs, with: .color(spider), lineWidth: 0.6)
        for part in [abdomen, head] {
            context.stroke(part, with: .color(Color(hex: 0x8A7A66).opacity(0.55)), lineWidth: 0.8)
            context.fill(part, with: .color(spider))
        }
    }
}
