import Foundation

/// Keys for the listening services, injected into Info.plist from project.yml
/// (SPOTIFY_CLIENT_ID, LASTFM_API_KEY). Empty means "not set up yet".
enum ServiceConfig {
    static var spotifyClientID: String { value("SpotifyClientID") }
    static var lastFMAPIKey: String { value("LastFMAPIKey") }
    static let callbackScheme = "moth"
    static let spotifyRedirectURI = "moth://spotify-callback"

    private static func value(_ key: String) -> String {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
    }
}

/// An artist with a short stat line, from any source.
struct RankedArtist: Identifiable, Hashable {
    let name: String
    let detail: String
    var imageURL: URL? = nil
    var id: String { name }
}

enum ServiceError: LocalizedError {
    case notConfigured, notConnected, cancelled, badResponse, message(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: "This service hasn't been set up yet."
        case .notConnected: "Not connected."
        case .cancelled: "Sign-in was cancelled."
        case .badResponse: "The service sent back something unexpected. Try again in a moment."
        case .message(let text): text
        }
    }
}
