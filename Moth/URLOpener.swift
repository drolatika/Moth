import UIKit

enum URLOpener {
    /// Tries the universal link first so it lands in the installed app (Spotify,
    /// Music, Bandcamp…), then the app's own URL scheme, then Safari.
    @MainActor
    static func open(_ item: SavedItem) {
        open(item.url, platform: item.platform)
    }

    @MainActor
    static func open(_ url: URL, platform: Platform) {
        let application = UIApplication.shared
        application.open(url, options: [.universalLinksOnly: true]) { opened in
            guard !opened else { return }
            if let schemeURL = platform.appSchemeURL(for: url) {
                application.open(schemeURL, options: [:]) { opened in
                    if !opened { application.open(url) }
                }
            } else {
                application.open(url)
            }
        }
    }
}
