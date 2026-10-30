import UIKit

enum URLOpener {
    /// Tries the universal link first so it lands in the installed app (Spotify,
    /// Music, Bandcamp…), then the app's own URL scheme, then Safari.
    @MainActor
    static func open(_ item: SavedItem) {
        let application = UIApplication.shared
        application.open(item.url, options: [.universalLinksOnly: true]) { opened in
            guard !opened else { return }
            if let schemeURL = item.platform.appSchemeURL(for: item.url) {
                application.open(schemeURL, options: [:]) { opened in
                    if !opened { application.open(item.url) }
                }
            } else {
                application.open(item.url)
            }
        }
    }
}
