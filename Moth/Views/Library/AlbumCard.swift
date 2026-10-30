import SwiftUI

struct AlbumCard: View {
    let item: SavedItem
    /// nil outside select mode; otherwise whether this card is selected.
    var selected: Bool? = nil
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ArtworkView(item: item)
                .shadow(color: .black.opacity(theme.isDark ? 0.45 : 0.15), radius: 10, y: 6)
                .overlay(alignment: .topTrailing) {
                    if let selected { checkmark(selected).padding(8) }
                }
                .opacity(selected == false ? 0.75 : 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let artist = item.artist {
                    Text(artist)
                        .font(.footnote)
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    PlatformBadge(platform: item.platform)
                    if item.kind != .other {
                        Text("· \(item.kind.label)")
                            .font(.caption2)
                            .foregroundStyle(theme.secondaryText.opacity(0.8))
                    }
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func checkmark(_ on: Bool) -> some View {
        ZStack {
            Circle().fill(on ? theme.accent : Color.black.opacity(0.25))
            Circle().strokeBorder(on ? theme.accent : Color.white.opacity(0.85), lineWidth: 2)
            if on {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(theme.onAccent)
            }
        }
        .frame(width: 26, height: 26)
    }
}

/// Press and hold still: the menu opens. Press, then move: the album lifts and
/// follows your finger; flick it toward the other page to send it there.
/// A plain swipe never triggers either, so the pages and the grid still scroll.
struct ThrowableCard<Content: View>: View {
    /// +1 throws to the right (Queue → Heard), -1 to the left (Heard → Queue).
    let direction: CGFloat
    @Binding var isDragging: Bool
    let onThrow: () -> Void
    let onHold: () -> Void
    @ViewBuilder let content: Content

    @State private var armed = false
    @State private var translation: CGSize = .zero
    @State private var thrown = false
    @State private var menuShown = false
    @State private var menuTimer: DispatchWorkItem?

    var body: some View {
        content
            .scaleEffect(armed ? 1.05 : 1)
            .rotationEffect(.degrees(Double(translation.width) / 14))
            .offset(translation)
            .opacity(thrown ? 0.15 : 1)
            .zIndex(armed || thrown ? 10 : 0)
            .gesture(CardPressGesture(
                onBegan: began,
                onChanged: changed,
                onEnded: ended,
                onCancelled: { settle() }
            ))
    }

    private func began() {
        menuShown = false
        isDragging = true
        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { armed = true }
        Haptics.impact(.medium)
        let timer = DispatchWorkItem {
            menuShown = true
            settle()
            onHold()
        }
        menuTimer = timer
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: timer)
    }

    private func changed(_ newTranslation: CGSize) {
        guard !menuShown else { return }
        if hypot(newTranslation.width, newTranslation.height) > 8 { menuTimer?.cancel() }
        translation = newTranslation
    }

    private func ended(_ finalTranslation: CGSize, _ velocity: CGSize) {
        menuTimer?.cancel()
        guard !menuShown else { return }
        let distance = finalTranslation.width * direction
        let projected = (finalTranslation.width + velocity.width * 0.2) * direction
        if distance > 70 || projected > 220 {
            throwAway(from: finalTranslation)
        } else {
            settle()
        }
    }

    private func settle() {
        menuTimer?.cancel()
        isDragging = false
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            armed = false
            translation = .zero
        }
    }

    private func throwAway(from start: CGSize) {
        isDragging = false
        armed = false
        Haptics.impact(.rigid)
        translation = start
        withAnimation(.easeIn(duration: 0.28)) {
            translation = CGSize(width: direction * 520, height: start.height - 120)
            thrown = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onThrow()
            thrown = false
            translation = .zero
        }
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.snappy(duration: 0.2), value: configuration.isPressed)
    }
}
