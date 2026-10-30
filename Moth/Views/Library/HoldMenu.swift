import SwiftUI

/// What appears when you press and hold an album: the screen dims, the album
/// lifts, and three actions sit beneath it. Tap outside to close.
struct HoldMenu: View {
    let item: SavedItem
    let onListen: () -> Void
    let onSelect: () -> Void
    let onRemove: () -> Void
    let onDismiss: () -> Void

    @Environment(\.theme) private var theme
    @State private var appeared = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(0.45))
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    ArtworkView(item: item, cornerRadius: 14)
                        .frame(width: 230, height: 230)
                        .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
                    Text(item.title)
                        .font(.headline)
                        .foregroundStyle(theme.text)
                        .lineLimit(2)
                    if let artist = item.artist {
                        Text(artist).font(.subheadline).foregroundStyle(theme.secondaryText)
                    }
                }
                .frame(width: 230, alignment: .leading)

                VStack(spacing: 0) {
                    row("Listen in \(item.platform.name)", symbol: "play.fill", tint: theme.accent, action: onListen)
                    Divider().overlay(theme.text.opacity(0.08))
                    row("Select", symbol: "checkmark.circle", tint: theme.text, action: onSelect)
                    Divider().overlay(theme.text.opacity(0.08))
                    row("Remove", symbol: "trash", tint: .red, action: onRemove)
                }
                .frame(width: 250)
                .background(theme.surface.opacity(0.97), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
            }
            .scaleEffect(appeared ? 1 : 0.92)
            .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            Haptics.impact(.light)
            withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) { appeared = true }
        }
    }

    private func row(_ title: String, symbol: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).foregroundStyle(tint == .red ? .red : theme.text)
                Spacer()
                Image(systemName: symbol).foregroundStyle(tint)
            }
            .font(.body.weight(.medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The page background: the theme's colour, plus artwork for themes that have it.
struct ThemeBackdrop: View {
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            theme.background
            if let backdrop = theme.backdrop {
                Image(backdrop)
                    .resizable()
                    .scaledToFill()
                    .accessibilityHidden(true)
            }
        }
        .ignoresSafeArea()
    }
}
