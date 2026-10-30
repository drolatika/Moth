import SwiftUI

struct ArtworkView: View {
    let item: SavedItem
    var cornerRadius: CGFloat = 10

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay { content }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
            }
    }

    @ViewBuilder
    private var content: some View {
        if let file = item.artworkFile, let image = ArtworkStore.image(named: file) {
            Image(uiImage: image).resizable().scaledToFill()
        } else if let url = item.artworkURL {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        LinearGradient(
            colors: [item.platform.color.opacity(0.9), item.platform.color.opacity(0.35)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Image(systemName: "music.note")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
        }
    }
}

struct PlatformBadge: View {
    let platform: Platform
    /// Gives each badge its own flicker rhythm (pass something stable per item).
    var seed: Int = 0
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 5) {
            ServiceLED(color: platform.color, seed: seed)
            Text(platform.name)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)
        }
    }
}

/// A little indicator light in the service's colour. Mostly steady with a soft
/// glow; now and then it stutters, flutters rapidly, or sticks dim for a while.
/// Every LED runs on its own random rhythm.
struct ServiceLED: View {
    let color: Color
    var seed: Int = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
            let level = reduceMotion ? 1 : Self.brightness(at: timeline.date.timeIntervalSinceReferenceDate, seed: seed)
            ZStack {
                Circle()
                    .fill(color.opacity(0.55 * level))
                    .frame(width: 13, height: 13)
                    .blur(radius: 3)
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                    .opacity(0.3 + 0.7 * level)
                Circle()
                    .fill(.white.opacity(0.55 * level))
                    .frame(width: 2.2, height: 2.2)
                    .offset(x: -1.2, y: -1.2)
            }
            .frame(width: 9, height: 9)
        }
        .accessibilityHidden(true)
    }

    /// 0 (off) … 1 (fully lit). Time is cut into slots of just under a second;
    /// each slot independently decides to stay steady, flutter, or stick dim.
    static func brightness(at time: TimeInterval, seed: Int) -> Double {
        let slotLength = 0.85
        let slot = Int(floor(time / slotLength))
        let within = time - Double(slot) * slotLength
        let roll = random(seed, slot, 0)

        if roll < 0.035 {
            // Stuck dim for the whole slot, catching again at a random moment near its end.
            return within < slotLength * (0.6 + 0.4 * random(seed, slot, 1)) ? 0.22 : 1
        }
        if roll < 0.13 {
            // A stutter: rapid on/off for a random stretch at the start of the slot.
            let burst = 0.12 + 0.35 * random(seed, slot, 2)
            guard within < burst else { return 1 }
            let tick = Int(within / 0.035)
            return random(seed, slot, 10 + tick) < 0.55 ? 0.15 : 1
        }
        if roll < 0.2 {
            // A single quick blink somewhere in the slot.
            let at = random(seed, slot, 3) * (slotLength - 0.08)
            return (at..<(at + 0.06)).contains(within) ? 0.3 : 1
        }
        // Steady, with the faintest shimmer.
        return 0.93 + 0.07 * random(seed, slot, 4)
    }

    /// Deterministic hash → 0..<1, so the pattern is stable frame to frame.
    private static func random(_ seed: Int, _ slot: Int, _ salt: Int) -> Double {
        var x = UInt64(bitPattern: Int64(seed)) &* 0x9E37_79B9_7F4A_7C15
        x ^= UInt64(bitPattern: Int64(slot)) &* 0xBF58_476D_1CE4_E5B9
        x ^= UInt64(bitPattern: Int64(salt)) &* 0x94D0_49BB_1331_11EB
        x ^= x >> 31
        x &*= 0xD6E8_FEB8_6659_FD93
        x ^= x >> 32
        return Double(x % 1_000_000) / 1_000_000
    }
}
