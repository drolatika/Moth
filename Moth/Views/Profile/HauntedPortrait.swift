import SwiftUI

/// Your picture hung in an old carved gilt frame (rendered by scripts/make_frame.py),
/// cobwebs in its corners, and a tall taper burning in front of it whose flame
/// dances and throws a warm, flickering light across the gold.
/// Laid out on a 300×300 grid.
struct HauntedPortrait: View {
    var photo: UIImage?

    static let size: CGFloat = 300
    /// The frame's width on the 300 grid (110 of the asset's 900 px).
    static let frameWidth: CGFloat = 110.0 / 3

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let inset = Self.frameWidth - 2
        ZStack(alignment: .topLeading) {
            portrait
                .frame(width: Self.size - inset * 2, height: Self.size - inset * 2)
                .clipped()
                .offset(x: inset, y: inset)

            Image("PortraitFrame")
                .resizable()
                .interpolation(.high)
                .frame(width: Self.size, height: Self.size)

            Canvas { context, _ in
                Candlelight.drawCobwebs(in: &context, opening: CGRect(x: Self.frameWidth, y: Self.frameWidth,
                                                                       width: Self.size - Self.frameWidth * 2,
                                                                       height: Self.size - Self.frameWidth * 2))
            }

            TimelineView(.animation(minimumInterval: 1.0 / 60, paused: reduceMotion)) { timeline in
                let t = reduceMotion ? 1.3 : timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 100_000)
                Canvas { context, _ in
                    Candlelight.draw(in: &context, time: t, candle: Candlelight.candleRect)
                }
            }
        }
        .frame(width: Self.size, height: Self.size)
        .shadow(color: .black.opacity(0.55), radius: 14, y: 8)
        .contentShape(Rectangle())
        .accessibilityHidden(true)
    }

    private var portrait: some View {
        ZStack {
            if let photo {
                Image(uiImage: photo).resizable().scaledToFill()
            } else {
                LinearGradient(colors: [Color(hex: 0x3A2E24), Color(hex: 0x17110D)], startPoint: .top, endPoint: .bottom)
                Image(systemName: "person.fill")
                    .font(.system(size: 92))
                    .foregroundStyle(Color(hex: 0x54463A))
                    .offset(y: 26)
            }
            // Old varnish: warm, and darker toward the edges.
            RadialGradient(colors: [.clear, Color(hex: 0x140C05).opacity(0.5)], center: .center, startRadius: 60, endRadius: 170)
            Color(hex: 0xC08A3E).opacity(0.1).blendMode(.multiply)
        }
    }
}

/// The frame's gold, for small touches elsewhere (profile slots, the Settings card).
enum FrameArt {
    static let gold = Color(hex: 0xA08848)
    static let goldDark = Color(hex: 0x4E4220)
}

/// The candle, its flame and its light, plus the cobwebs.
enum Candlelight {
    /// The taper, standing in front of the lower right of the picture.
    static let candleRect = CGRect(x: 226, y: 132, width: 10, height: 154)

    // MARK: Flame motion

    /// Smooth 1D value noise in -1…1.
    static func noise(_ x: Double) -> Double {
        let i = floor(x)
        let f = x - i
        let u = f * f * (3 - 2 * f)
        return hash(i) * (1 - u) + hash(i + 1) * u
    }

    private static func hash(_ n: Double) -> Double {
        let s = sin(n * 127.1 + 311.7) * 43_758.5453
        return (s - floor(s)) * 2 - 1
    }

    struct FlameState {
        var height: Double
        var width: Double
        /// Where the tip has drifted to, sideways.
        var lean: Double
        /// Quick sideways licks on top of the lean.
        var flutter: Double
        /// 0…1 brightness for the glow.
        var intensity: Double
    }

    static func flame(at t: Double) -> FlameState {
        // Every so often a draught catches it: it leans, licks and shrinks, then settles.
        let gust = max(0, noise(t * 0.33 + 40) - 0.35) * 1.6
        let lean = 2.2 * noise(t * 0.8 + 10) + 1.2 * noise(t * 2.7 + 20) + gust * 3.5 * noise(t * 1.7 + 5)
        let flutter = (0.7 + 2.6 * gust) * (sin(t * 19 + 3 * noise(t * 2)) * 0.6 + noise(t * 11 + 60) * 0.7)
        let height = 30 * (0.9 + 0.12 * noise(t * 4.3 + 30) + 0.05 * sin(t * 13.7)) * (1 - 0.22 * gust)
        let width = 9.6 * (1 + 0.1 * noise(t * 6.1 + 50) + 0.12 * gust)
        let intensity = 0.86 + 0.09 * noise(t * 7 + 70) + 0.05 * noise(t * 23 + 80) - 0.12 * gust
        return FlameState(height: height, width: width, lean: lean, flutter: flutter, intensity: intensity)
    }

    // MARK: Drawing

    static func draw(in context: inout GraphicsContext, time t: Double, candle: CGRect) {
        let state = flame(at: t)
        let wickTop = CGPoint(x: candle.midX + 0.4, y: candle.minY - 3)
        let k = state.intensity

        // Light thrown across the frame and the picture.
        context.drawLayer { layer in
            layer.blendMode = .plusLighter
            let center = CGPoint(x: wickTop.x + state.lean * 0.6, y: wickTop.y - state.height * 0.35)
            let radius = 170 * (0.9 + 0.1 * k)
            layer.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                       with: .radialGradient(Gradient(stops: [
                           .init(color: Color(hex: 0xFFC27A).opacity(0.42 * k), location: 0),
                           .init(color: Color(hex: 0xFF9A48).opacity(0.2 * k), location: 0.35),
                           .init(color: Color(hex: 0xFF7A30).opacity(0.07 * k), location: 0.7),
                           .init(color: .clear, location: 1),
                       ]), center: center, startRadius: 0, endRadius: radius))
        }

        drawCandle(in: &context, rect: candle, intensity: k)
        drawFlame(in: &context, state: state, wickTop: wickTop)
    }

    private static func drawCandle(in context: inout GraphicsContext, rect: CGRect, intensity k: Double) {
        // A soft shadow on the painting behind it.
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 3))
            layer.fill(Path(roundedRect: rect.offsetBy(dx: 4, dy: 3), cornerRadius: 3), with: .color(.black.opacity(0.35)))
        }

        // Beeswax, shaded round.
        var wax = Path()
        wax.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        wax.addLine(to: CGPoint(x: rect.minX, y: rect.minY + 2))
        wax.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + 2), control: CGPoint(x: rect.midX, y: rect.minY + 4.5))
        wax.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        wax.closeSubpath()
        context.fill(wax, with: .linearGradient(
            Gradient(colors: [Color(hex: 0x6E5424), Color(hex: 0xC9A458), Color(hex: 0xEED48E), Color(hex: 0xB89248), Color(hex: 0x5E461E)]),
            startPoint: CGPoint(x: rect.minX, y: 0), endPoint: CGPoint(x: rect.maxX, y: 0)
        ))
        // The top glows where the flame shines through the wax, and the light fades down its length.
        context.fill(wax, with: .linearGradient(
            Gradient(stops: [
                .init(color: Color(hex: 0xFFE2A0).opacity(0.55 * k), location: 0),
                .init(color: Color(hex: 0xFFC870).opacity(0.18 * k), location: 0.12),
                .init(color: .clear, location: 0.35),
                .init(color: .black.opacity(0.25), location: 1),
            ]),
            startPoint: CGPoint(x: 0, y: rect.minY), endPoint: CGPoint(x: 0, y: rect.maxY)
        ))
        // Two drips run down from the rim, a shade paler than the candle.
        var drips = Path()
        for (x, length) in [(rect.minX + 0.4, 15.0), (rect.maxX - 2.6, 8.0)] {
            drips.move(to: CGPoint(x: x, y: rect.minY + 2))
            drips.addLine(to: CGPoint(x: x, y: rect.minY + length))
            drips.addQuadCurve(to: CGPoint(x: x + 2.2, y: rect.minY + length), control: CGPoint(x: x + 1.1, y: rect.minY + length + 2.2))
            drips.addLine(to: CGPoint(x: x + 2.2, y: rect.minY + 2))
            drips.closeSubpath()
        }
        context.fill(drips, with: .color(Color(hex: 0xF0D898).opacity(0.85)))
        // Melted cup at the top.
        let cup = Path(ellipseIn: CGRect(x: rect.minX + 0.5, y: rect.minY + 0.5, width: rect.width - 1, height: 3.5))
        context.fill(cup, with: .color(Color(hex: 0xFFE7A8).opacity(0.75)))

        // A small brass socket at the foot.
        let socket = CGRect(x: rect.midX - 9, y: rect.maxY - 6, width: 18, height: 8)
        context.fill(Path(roundedRect: socket, cornerRadius: 2.5), with: .linearGradient(
            Gradient(colors: [Color(hex: 0x4A3A18), Color(hex: 0xC8A860), Color(hex: 0x7A6028), Color(hex: 0x3A2C12)]),
            startPoint: CGPoint(x: socket.minX, y: 0), endPoint: CGPoint(x: socket.maxX, y: 0)
        ))
        context.fill(Path(ellipseIn: CGRect(x: socket.minX - 2, y: socket.minY - 2, width: socket.width + 4, height: 4)),
                     with: .color(Color(hex: 0xB89650)))
    }

    private static func drawFlame(in context: inout GraphicsContext, state: FlameState, wickTop: CGPoint) {
        let base = wickTop
        let h = state.height, w = state.width
        let tipX = base.x + state.lean + state.flutter
        let tip = CGPoint(x: tipX, y: base.y - h)
        // The upper body lags the tip, so licks travel up the flame as an S-bend.
        let bend = state.lean * 0.5 + state.flutter * 0.25

        func body(widthScale: Double, heightScale: Double, rise: Double) -> Path {
            let hh = h * heightScale, ww = w * widthScale
            let b = CGPoint(x: base.x, y: base.y - rise)
            let tp = CGPoint(x: base.x + (tip.x - base.x) * heightScale, y: b.y - hh)
            var path = Path()
            path.move(to: CGPoint(x: b.x, y: b.y + 2))
            path.addCurve(to: CGPoint(x: b.x - ww / 2, y: b.y - hh * 0.3),
                          control1: CGPoint(x: b.x - ww * 0.3, y: b.y + 2), control2: CGPoint(x: b.x - ww * 0.56, y: b.y - hh * 0.08))
            path.addCurve(to: tp,
                          control1: CGPoint(x: b.x - ww * 0.42 + bend * 0.3, y: b.y - hh * 0.55),
                          control2: CGPoint(x: tp.x - ww * 0.12 + bend * 0.35, y: tp.y + hh * 0.3))
            path.addCurve(to: CGPoint(x: b.x + ww / 2, y: b.y - hh * 0.3),
                          control1: CGPoint(x: tp.x + ww * 0.12 + bend * 0.35, y: tp.y + hh * 0.3),
                          control2: CGPoint(x: b.x + ww * 0.42 + bend * 0.3, y: b.y - hh * 0.55))
            path.addCurve(to: CGPoint(x: b.x, y: b.y + 2),
                          control1: CGPoint(x: b.x + ww * 0.56, y: b.y - hh * 0.08), control2: CGPoint(x: b.x + ww * 0.3, y: b.y + 2))
            path.closeSubpath()
            return path
        }

        let outer = body(widthScale: 1, heightScale: 1, rise: 0)
        // The wick, mostly swallowed by the flame, its tip glowing.
        var wick = Path()
        wick.move(to: CGPoint(x: base.x - 0.3, y: base.y + 4))
        wick.addQuadCurve(to: CGPoint(x: base.x + 0.4 + state.lean * 0.08, y: base.y - 2.5),
                          control: CGPoint(x: base.x - 0.8, y: base.y + 0.5))
        context.stroke(wick, with: .color(Color(hex: 0x1E1610)), style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
        context.fill(Path(ellipseIn: CGRect(x: base.x - 0.5 + state.lean * 0.08, y: base.y - 3.4, width: 1.8, height: 1.8)),
                     with: .color(Color(hex: 0xFF6A28)))
        // Halo.
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 9))
            layer.fill(body(widthScale: 2.2, heightScale: 1.15, rise: -2), with: .color(Color(hex: 0xFFAA50).opacity(0.5 * state.intensity)))
        }
        // Soft orange envelope.
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 1.2))
            layer.fill(outer, with: .linearGradient(Gradient(stops: [
                .init(color: Color(hex: 0xFFB04A).opacity(0.25), location: 0),
                .init(color: Color(hex: 0xFFC25A), location: 0.15),
                .init(color: Color(hex: 0xFFD27A), location: 0.45),
                .init(color: Color(hex: 0xFF9A3A).opacity(0.9), location: 0.8),
                .init(color: Color(hex: 0xE0541A).opacity(0), location: 1),
            ]), startPoint: base, endPoint: tip))
        }
        // Bright core.
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 0.8))
            layer.fill(body(widthScale: 0.52, heightScale: 0.6, rise: 1.5), with: .linearGradient(Gradient(stops: [
                .init(color: Color(hex: 0xFFFDF2), location: 0),
                .init(color: Color(hex: 0xFFF2C4), location: 0.55),
                .init(color: Color(hex: 0xFFE39A).opacity(0), location: 1),
            ]), startPoint: base, endPoint: tip))
        }
        // Blue at the root.
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 0.9))
            layer.fill(Path(ellipseIn: CGRect(x: base.x - 2, y: base.y - 2, width: 4, height: 3.6)),
                       with: .color(Color(hex: 0x5878F0).opacity(0.35)))
        }
    }

    // MARK: Cobwebs

    static func drawCobwebs(in context: inout GraphicsContext, opening r: CGRect) {
        // A full web filling the top left corner of the picture.
        cornerWeb(in: &context, corner: CGPoint(x: r.minX, y: r.minY), from: 0.03, to: .pi / 2 - 0.03, length: 78, rings: 7, seed: 1)
        // A smaller, torn one in the top right.
        cornerWeb(in: &context, corner: CGPoint(x: r.maxX, y: r.minY), from: .pi / 2 + 0.05, to: .pi - 0.05, length: 44, rings: 5, seed: 4)
        // Loose strands: one sagging along the top, a few hanging off the right side by the candle.
        var strands = Path()
        strands.move(to: CGPoint(x: r.minX + 70, y: r.minY + 1))
        strands.addQuadCurve(to: CGPoint(x: r.maxX - 34, y: r.minY + 1), control: CGPoint(x: r.midX + 10, y: r.minY + 22))
        strands.move(to: CGPoint(x: r.maxX, y: r.minY + 96))
        strands.addQuadCurve(to: CGPoint(x: candleRect.maxX, y: candleRect.minY + 40), control: CGPoint(x: r.maxX - 8, y: r.minY + 122))
        strands.move(to: CGPoint(x: r.maxX, y: r.minY + 120))
        strands.addQuadCurve(to: CGPoint(x: candleRect.maxX, y: candleRect.minY + 76), control: CGPoint(x: r.maxX - 10, y: r.minY + 150))
        strands.move(to: CGPoint(x: r.maxX, y: r.minY + 140))
        strands.addQuadCurve(to: CGPoint(x: r.maxX - 22, y: r.maxY), control: CGPoint(x: r.maxX - 4, y: r.maxY - 30))
        context.stroke(strands, with: .color(.white.opacity(0.16)), lineWidth: 0.5)
    }

    private static func cornerWeb(in context: inout GraphicsContext, corner: CGPoint, from: Double, to: Double,
                                  length: CGFloat, rings: Int, seed: Int) {
        let threads = 9
        let spokes = (0..<threads).map { i -> (angle: Double, length: CGFloat) in
            let jitter = sin(Double(i * 7 + seed * 13)) * 0.22
            return (from + (to - from) * Double(i) / Double(threads - 1), length * CGFloat(1 + jitter))
        }
        var path = Path()
        for spoke in spokes {
            path.move(to: corner)
            path.addLine(to: CGPoint(x: corner.x + spoke.length * cos(spoke.angle), y: corner.y + spoke.length * sin(spoke.angle)))
        }
        for ring in 1...rings {
            let fraction = pow(CGFloat(ring) / CGFloat(rings + 1), 0.9)
            for i in 1..<threads {
                let a0 = spokes[i - 1], a1 = spokes[i]
                if (ring * 3 + i + seed) % 5 == 0 { continue }   // torn here and there
                // Each strand meets its spokes at slightly different heights, as real ones do.
                let f0 = fraction * CGFloat(1 + 0.08 * sin(Double(ring * 11 + i * 5 + seed)))
                let f1 = fraction * CGFloat(1 + 0.08 * sin(Double(ring * 11 + (i + 1) * 5 + seed)))
                let p0 = CGPoint(x: corner.x + a0.length * f0 * cos(a0.angle), y: corner.y + a0.length * f0 * sin(a0.angle))
                let p1 = CGPoint(x: corner.x + a1.length * f1 * cos(a1.angle), y: corner.y + a1.length * f1 * sin(a1.angle))
                let mid = (a0.angle + a1.angle) / 2
                let sag = (a0.length + a1.length) / 2 * fraction * 0.86
                path.move(to: p0)
                path.addQuadCurve(to: p1, control: CGPoint(x: corner.x + sag * cos(mid), y: corner.y + sag * sin(mid)))
            }
        }
        context.stroke(path, with: .color(.white.opacity(0.2)), lineWidth: 0.5)
    }
}
