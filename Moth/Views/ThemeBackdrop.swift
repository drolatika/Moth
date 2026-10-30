import SwiftUI

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
                // A soft veil behind the header keeps the art from crowding the title.
                LinearGradient(
                    stops: [.init(color: theme.background.opacity(0.6), location: 0),
                            .init(color: theme.background.opacity(0.45), location: 0.14),
                            .init(color: theme.background.opacity(0), location: 0.3)],
                    startPoint: .top, endPoint: .bottom
                )
            }
        }
        .ignoresSafeArea()
    }
}
