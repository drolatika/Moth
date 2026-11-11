import UIKit

enum URLOpener {
    /// Tries the universal link first so it lands in the installed app (Spotify,
    /// Music…), then the app's own URL scheme, then Safari. Bandcamp goes straight
    /// to its scheme.
    @MainActor
    static func open(_ item: SavedItem) {
        open(item.url, platform: item.platform)
    }

    @MainActor
    static func open(_ url: URL, platform: Platform) {
        let application = UIApplication.shared
        if platform == .bandcamp {
            // The Bandcamp app doesn't claim bandcamp.com links, so go straight to its scheme.
            Task { @MainActor in
                for appURL in await BandcampLink.appURLs(for: url) {
                    if await application.open(appURL) { return }
                }
                _ = await application.open(url)
            }
            return
        }
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
