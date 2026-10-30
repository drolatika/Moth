import SwiftUI

/// The bundled typefaces, all SIL Open Font License (see Design/fonts).
enum MothFont {
    /// UnifrakturMaguntia: the "M" of the wordmark and app icon.
    static func fraktur(_ size: CGFloat) -> Font { .custom("UnifrakturMaguntia", size: size) }
    /// Grenze Gotisch Medium: readable Gothic for "oth" and the page titles.
    static func gothic(_ size: CGFloat) -> Font { .custom("GrenzeGotisch-Medium", size: size) }
    /// Cinzel Decorative Black: the illuminated capitals.
    static func initial(_ size: CGFloat) -> Font { .custom("CinzelDecorative-Black", size: size) }
}

/// Manuscript colours used by the header art regardless of theme.
enum Manuscript {
    static let parchment = Color(hex: 0xEDE1C6)
    static let oxblood = Color(hex: 0x6E1C19)
    static let ember = Color(hex: 0xFF8A4A)
    static let flame = Color(hex: 0xFFC48A)
    static let mothCream = Color(hex: 0xF1E6CF)
    static let mothLine = Color(hex: 0x6B5A45)
}

/// "Moth" with the Fraktur M from the icon and readable Gothic "oth".
struct Wordmark: View {
    var size: CGFloat = 21
    @Environment(\.theme) private var theme

    var body: some View {
        (Text("M").font(MothFont.fraktur(size * 1.3)).foregroundStyle(theme.accent)
            + Text("oth").font(MothFont.gothic(size)).foregroundStyle(theme.text))
            .shadow(color: Manuscript.ember.opacity(0.35), radius: 6)
            .accessibilityLabel("Moth")
    }
}

/// A manuscript initial: an oxblood capital on a parchment square with a double frame.
struct GildedInitial: View {
    let letter: String
    var size: CGFloat = 54

    var body: some View {
        ZStack {
            Rectangle().fill(Manuscript.parchment)
            Rectangle().strokeBorder(Manuscript.oxblood, lineWidth: 2)
            Rectangle().inset(by: 4).strokeBorder(Manuscript.oxblood, lineWidth: 1)
            Text(letter)
                .font(MothFont.initial(size * 0.74))
                .foregroundStyle(Manuscript.oxblood)
                .offset(y: size * 0.02)
                .fixedSize()
        }
        .frame(width: size, height: size)
        .overlay(alignment: .topLeading) { cornerDot.offset(x: -4, y: -4) }
        .overlay(alignment: .bottomTrailing) { cornerDot.offset(x: 4, y: 4) }
        .shadow(color: .black.opacity(0.35), radius: 5, y: 2)
    }

    private var cornerDot: some View {
        Circle().fill(Manuscript.oxblood).frame(width: 7, height: 7)
    }
}

/// "Queue" / "Heard": gilded initial, Gothic remainder and a small count.
struct GildedTitle: View {
    let word: String
    let count: Int
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            GildedInitial(letter: String(word.prefix(1)))
            Text(word.dropFirst())
                .font(MothFont.gothic(40))
                .foregroundStyle(theme.text)
                .padding(.bottom, 1)
            Text("\(count)")
                .font(.system(size: 16, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(theme.secondaryText)
                .padding(.leading, 6)
                .padding(.bottom, 9)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(word), \(count)")
    }
}
