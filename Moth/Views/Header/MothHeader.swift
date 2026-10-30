import SwiftUI

/// Top of the library: settings / wordmark / add, then the page title with the
/// lantern on the right and the moths between them. `progress` is the pager
/// position, 0 on Queue and 1 on Heard.
struct MothHeader: View {
    let progress: Double
    let queueCount: Int
    let heardCount: Int
    let selection: SelectionBar?
    let onSettings: () -> Void
    let onAdd: () -> Void

    struct SelectionBar {
        let count: Int
        let onCancel: () -> Void
        let onSelectAll: () -> Void
    }

    static let height: CGFloat = 128
    private static let topBarHeight: CGFloat = 44
    private static let titleRowY: CGFloat = 54
    private static let titleRowHeight: CGFloat = 64

    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            // The lantern's base (y 62.5 of 64) sits on the bottom edge of the initial's box.
            let lanternOrigin = CGPoint(x: width - 16 - 60, y: Self.titleRowY + Self.titleRowHeight - 62.5)
            ZStack(alignment: .topLeading) {
                titles
                    .frame(height: Self.titleRowHeight, alignment: .bottomLeading)
                    .offset(x: 20, y: Self.titleRowY)

                // Only the lantern and moths animate, and they never take touches,
                // so the buttons above always get the tap.
                TimelineView(.animation(minimumInterval: nil, paused: reduceMotion)) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 10_000)
                    ZStack(alignment: .topLeading) {
                        LanternView(lit: lanternLevel, time: t)
                            .offset(x: lanternOrigin.x, y: lanternOrigin.y)
                        MothSwarm(
                            progress: progress,
                            time: t,
                            titleCenter: CGPoint(x: 96, y: Self.titleRowY + 37),
                            lanternCenter: CGPoint(x: lanternOrigin.x + 28, y: lanternOrigin.y + 28.5),
                            onDark: theme.isDark
                        )
                        .frame(width: width, height: Self.height)
                    }
                }
                .allowsHitTesting(false)

                topBar
                    .frame(width: width - 32, height: Self.topBarHeight)
                    .offset(x: 16)
            }
        }
        .frame(height: Self.height)
    }

    /// Dark on Queue; catches with a brief flare as the moths arrive, then flickers.
    private var lanternLevel: Double {
        let ignite = clamp((progress - 0.6) / 0.2)
        let flare = sin(.pi * clamp((progress - 0.6) / 0.3)) * 0.6
        return ignite * (1 + flare * 0.4)
    }

    private func clamp(_ x: Double) -> Double { min(1, max(0, x)) }

    private var titles: some View {
        ZStack(alignment: .bottomLeading) {
            GildedTitle(word: "Queue", count: queueCount)
                .opacity(1 - clamp(progress * 2))
            GildedTitle(word: "Heard", count: heardCount)
                .opacity(clamp(progress * 2 - 1))
        }
    }

    @ViewBuilder
    private var topBar: some View {
        if let selection {
            HStack {
                Button("Cancel", action: selection.onCancel)
                Spacer()
                Text(selection.count == 1 ? "1 Selected" : "\(selection.count) Selected")
                    .font(.headline)
                    .foregroundStyle(theme.text)
                Spacer()
                Button("Select All", action: selection.onSelectAll)
            }
            .font(.body.weight(.medium))
            .foregroundStyle(theme.accent)
        } else {
            HStack {
                circleButton("gearshape", label: "Settings", action: onSettings)
                Spacer()
                Wordmark()
                Spacer()
                circleButton("plus", label: "Add link", action: onAdd)
            }
        }
    }

    private func circleButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(theme.accent)
                .frame(width: 42, height: 42)
                .background(theme.surface, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
