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

/// Press, hold for a moment, then flick: the album flies off toward the other page.
/// A quick swipe without the hold still pages, and a longer still hold opens the menu.
struct ThrowableCard<Content: View>: View {
    /// +1 throws to the right (Queue → Heard), -1 to the left (Heard → Queue).
    let direction: CGFloat
    @Binding var isDragging: Bool
    let onThrow: () -> Void
    @ViewBuilder let content: Content

    private enum DragState: Equatable {
        case idle, armed, dragging(CGSize)
        var translation: CGSize {
            if case .dragging(let t) = self { return t }
            return .zero
        }
        var isActive: Bool { self != .idle }
    }

    @GestureState private var drag: DragState = .idle
    @State private var flyOffset: CGSize = .zero
    @State private var flying = false
    @State private var thrown = false

    var body: some View {
        let offset = flying ? flyOffset : drag.translation
        content
            .scaleEffect(drag.isActive ? 1.05 : 1)
            .rotationEffect(.degrees(Double(offset.width) / 14))
            .offset(offset)
            .opacity(thrown ? 0.15 : 1)
            .zIndex(drag.isActive || flying ? 10 : 0)
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: drag.isActive)
            .simultaneousGesture(throwGesture)
            .onChange(of: drag.isActive) { _, active in
                isDragging = active
                if active { Haptics.impact(.medium) }
            }
    }

    private var throwGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.18)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
            .updating($drag) { value, state, _ in
                switch value {
                case .first(true):
                    state = .armed
                case .second(true, let dragValue):
                    state = dragValue.map { DragState.dragging($0.translation) } ?? .armed
                default:
                    state = .idle
                }
            }
            .onEnded { value in
                guard case .second(true, let dragValue?) = value else { return }
                let distance = dragValue.translation.width * direction
                let predicted = dragValue.predictedEndTranslation.width * direction
                guard distance > 70 || predicted > 220 else { return }
                throwAway(from: dragValue.translation)
            }
    }

    private func throwAway(from start: CGSize) {
        flyOffset = start
        flying = true
        Haptics.impact(.rigid)
        withAnimation(.easeIn(duration: 0.28)) {
            flyOffset = CGSize(width: direction * 520, height: start.height - 120)
            thrown = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onThrow()
            flying = false
            thrown = false
            flyOffset = .zero
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
