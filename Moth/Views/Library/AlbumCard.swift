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
                    if let selected { SelectionMark(on: selected).padding(8) }
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
                    if item.isPartlyHeard {
                        Text("· \(item.heardTrackCount) heard")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(theme.accent.opacity(0.85))
                    }
                }
                .padding(.top, 2)
            }
            .modifier(BackdropLabel())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// A compact row for the Rows layout: small artwork beside the text.
struct AlbumRow: View {
    let item: SavedItem
    var selected: Bool? = nil
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 14) {
            ArtworkView(item: item, cornerRadius: 8)
                .frame(width: 64, height: 64)
                .shadow(color: .black.opacity(theme.isDark ? 0.4 : 0.12), radius: 6, y: 3)
                .opacity(selected == false ? 0.75 : 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                if let artist = item.artist {
                    Text(artist).font(.footnote).foregroundStyle(theme.secondaryText).lineLimit(1)
                }
                HStack(spacing: 6) {
                    PlatformBadge(platform: item.platform)
                    if item.kind != .other {
                        Text("· \(item.kind.label)").font(.caption2).foregroundStyle(theme.secondaryText.opacity(0.8))
                    }
                    if item.isPartlyHeard {
                        Text("· \(item.heardTrackCount) heard").font(.caption2.weight(.semibold)).foregroundStyle(theme.accent.opacity(0.85))
                    }
                }
            }
            .modifier(BackdropLabel())
            Spacer(minLength: 0)
            if let selected { SelectionMark(on: selected) }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

/// On themes with background artwork, sets text on a soft label of the page colour
/// so it stays readable over the art. Does nothing on plain themes.
struct BackdropLabel: ViewModifier {
    @Environment(\.theme) private var theme

    @ViewBuilder
    func body(content: Content) -> some View {
        if theme.backdrop != nil {
            content
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(theme.background.opacity(0.88), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .padding(.horizontal, -6)
        } else {
            content
        }
    }
}

struct SelectionMark: View {
    let on: Bool
    @Environment(\.theme) private var theme

    var body: some View {
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

/// Tap: opens the album's menu. Press and hold: the album lifts and follows your
/// finger; throw it toward the other page to send it there. Plain swipes still
/// scroll, because the hold only takes over once the finger has stayed put.
struct ThrowableCard<Content: View>: View {
    /// +1 throws to the right (Queue → Heard), -1 to the left (Heard → Queue).
    let direction: CGFloat
    @Binding var isDragging: Bool
    let onThrow: () -> Void
    let onTap: () -> Void
    @ViewBuilder let content: Content

    @State private var armed = false
    @State private var translation: CGSize = .zero
    @State private var thrown = false
    /// Last time a hold was active; a tap right after a hold is ignored.
    @State private var lastPress = Date.distantPast

    var body: some View {
        content
            .scaleEffect(armed ? 1.06 : 1)
            .shadow(color: .black.opacity(armed ? 0.45 : 0), radius: 18, y: 12)
            .rotationEffect(.degrees(Double(translation.width) / 14))
            .offset(translation)
            .opacity(thrown ? 0.15 : 1)
            .zIndex(armed || thrown ? 10 : 0)
            .contentShape(Rectangle())
            .onTapGesture {
                guard Date().timeIntervalSince(lastPress) > 0.4 else { return }
                Haptics.impact(.light)
                onTap()
            }
            .gesture(CardPressGesture(
                onBegan: began,
                onChanged: changed,
                onEnded: ended,
                onCancelled: { settle() }
            ))
    }

    private func began() {
        lastPress = Date()
        isDragging = true
        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { armed = true }
        Haptics.impact(.medium)
    }

    private func changed(_ newTranslation: CGSize) {
        lastPress = Date()
        translation = newTranslation
    }

    private func ended(_ finalTranslation: CGSize, _ velocity: CGSize) {
        lastPress = Date()
        let distance = finalTranslation.width * direction
        let projected = (finalTranslation.width + velocity.width * 0.2) * direction
        if distance > 70 || projected > 220 {
            throwAway(from: finalTranslation)
        } else {
            settle()
        }
    }

    private func settle() {
        lastPress = Date()
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
