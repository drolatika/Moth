import SwiftUI

enum Platform: String, Codable, CaseIterable, Identifiable {
    case spotify, appleMusic, bandcamp, soundcloud, youtubeMusic, youtube, tidal, deezer, amazonMusic, other

    var id: String { rawValue }

    var name: String {
        switch self {
        case .spotify: "Spotify"
        case .appleMusic: "Apple Music"
        case .bandcamp: "Bandcamp"
        case .soundcloud: "SoundCloud"
        case .youtubeMusic: "YouTube Music"
        case .youtube: "YouTube"
        case .tidal: "Tidal"
        case .deezer: "Deezer"
        case .amazonMusic: "Amazon Music"
        case .other: "Web"
        }
    }

    var color: Color {
        switch self {
        case .spotify: Color(hex: 0x1DB954)
        case .appleMusic: Color(hex: 0xFA2D48)
        case .bandcamp: Color(hex: 0x1DA0C3)
        case .soundcloud: Color(hex: 0xFF5500)
        case .youtubeMusic, .youtube: Color(hex: 0xFF0033)
        case .tidal: Color(hex: 0x33C3F0)
        case .deezer: Color(hex: 0xA238FF)
        case .amazonMusic: Color(hex: 0x25D1DA)
        case .other: Color(hex: 0x8E8E93)
        }
    }

    static func detect(_ url: URL) -> Platform {
        let host = (url.host ?? "").lowercased()
        func matches(_ domain: String) -> Bool { host == domain || host.hasSuffix("." + domain) }

        if matches("spotify.com") || matches("spotify.link") { return .spotify }
        if matches("music.apple.com") || matches("itunes.apple.com") { return .appleMusic }
        if matches("bandcamp.com") { return .bandcamp }
        if matches("soundcloud.com") || matches("snd.sc") { return .soundcloud }
        if matches("music.youtube.com") { return .youtubeMusic }
        if matches("youtube.com") || matches("youtu.be") { return .youtube }
        if matches("tidal.com") || matches("tidal.link") { return .tidal }
        if matches("deezer.com") || matches("deezer.page.link") || matches("link.deezer.com") { return .deezer }
        if host.contains("music.amazon.") || (matches("amazon.com") && url.path.contains("/music")) { return .amazonMusic }
        return .other
    }

    /// A native-app URL to try when the universal link isn't claimed by an installed app.
    func appSchemeURL(for url: URL) -> URL? {
        switch self {
        case .spotify:
            let parts = url.pathComponents.filter { $0 != "/" && !$0.hasPrefix("intl-") }
            guard parts.count >= 2 else { return nil }
            return URL(string: "spotify:\(parts[0]):\(parts[1])")
        case .appleMusic:
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.scheme = "music"
            return components?.url
        default:
            return nil
        }
    }
}
