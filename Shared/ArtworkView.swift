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
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(platform.color).frame(width: 7, height: 7)
            Text(platform.name)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)
        }
    }
}
