import AuthenticationServices
import CryptoKit
import UIKit

struct SpotifyPlay: Identifiable {
    let id: String
    let track: String
    let artist: String
    let durationMs: Int
    let playedAt: Date
}

/// Spotify Web API with Authorization Code + PKCE (no client secret in the app).
/// Spotify only exposes your last 50 plays and your top lists, so listening time
/// from Spotify covers those 50 plays.
final class SpotifyService: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = SpotifyService()

    private let tokenKey = "spotify.tokens"
    private let scopes = "user-read-recently-played user-top-read"
    private var authSession: ASWebAuthenticationSession?

    private struct Tokens: Codable {
        var accessToken: String
        var refreshToken: String
        var expiresAt: Date
    }

    var isConfigured: Bool { !ServiceConfig.spotifyClientID.isEmpty }
    var isConnected: Bool { tokens != nil }

    private var tokens: Tokens? {
        get { Keychain.data(for: tokenKey).flatMap { try? JSONDecoder().decode(Tokens.self, from: $0) } }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                Keychain.set(data, for: tokenKey)
            } else {
                Keychain.remove(tokenKey)
            }
        }
    }

    // MARK: Sign in / out

    @MainActor
    func connect() async throws {
        guard isConfigured else { throw ServiceError.notConfigured }
        let verifier = Self.makeVerifier()
        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: ServiceConfig.spotifyClientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: ServiceConfig.spotifyRedirectURI),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: Self.challenge(for: verifier)),
            URLQueryItem(name: "scope", value: scopes),
        ]
        guard let authURL = components.url else { throw ServiceError.badResponse }
        let callback = try await authenticate(at: authURL)
        let query = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard let code = query.first(where: { $0.name == "code" })?.value else {
            throw query.contains(where: { $0.name == "error" }) ? ServiceError.cancelled : ServiceError.badResponse
        }
        tokens = try await requestTokens([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": ServiceConfig.spotifyRedirectURI,
            "client_id": ServiceConfig.spotifyClientID,
            "code_verifier": verifier,
        ], keepingRefreshToken: nil)
    }

    func disconnect() {
        tokens = nil
    }

    @MainActor
    private func authenticate(at url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: ServiceConfig.callbackScheme) { callback, error in
                if let callback {
                    continuation.resume(returning: callback)
                } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: ServiceError.cancelled)
                } else {
                    continuation.resume(throwing: error ?? ServiceError.badResponse)
                }
            }
            session.presentationContextProvider = self
            authSession = session
            session.start()
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            if let key = scenes.flatMap(\.windows).first(where: \.isKeyWindow) { return key }
            if let scene = scenes.first { return UIWindow(windowScene: scene) }
            return ASPresentationAnchor()
        }
    }

    // MARK: Data

    func displayName() async throws -> String {
        let json = try await get("/me")
        return (json["display_name"] as? String) ?? (json["id"] as? String) ?? "Spotify"
    }

    func recentPlays() async throws -> [SpotifyPlay] {
        let json = try await get("/me/player/recently-played?limit=50")
        let items = json["items"] as? [[String: Any]] ?? []
        return items.compactMap { item in
            guard let track = item["track"] as? [String: Any],
                  let name = track["name"] as? String,
                  let playedAtText = item["played_at"] as? String,
                  let playedAt = Self.parseDate(playedAtText)
            else { return nil }
            let artists = (track["artists"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
            return SpotifyPlay(
                id: playedAtText + name,
                track: name,
                artist: artists.joined(separator: ", "),
                durationMs: track["duration_ms"] as? Int ?? 0,
                playedAt: playedAt
            )
        }
    }

    func topArtists() async throws -> [RankedArtist] {
        let json = try await get("/me/top/artists?time_range=short_term&limit=5")
        let items = json["items"] as? [[String: Any]] ?? []
        return items.compactMap { artist in
            guard let name = artist["name"] as? String else { return nil }
            let genres = (artist["genres"] as? [String] ?? []).prefix(2).joined(separator: ", ")
            let image = ((artist["images"] as? [[String: Any]])?.last?["url"] as? String).flatMap(URL.init(string:))
            return RankedArtist(name: name, detail: genres.isEmpty ? "Top artist" : genres, imageURL: image)
        }
    }

    /// Tracklist, label and copyright for an album (or the album a track is on).
    func albumDetails(kind: String, id: String) async throws -> AlbumDetails {
        var albumID = id
        if kind == "track" {
            let track = try await get("/tracks/\(id)")
            guard let album = (track["album"] as? [String: Any])?["id"] as? String else { throw ServiceError.badResponse }
            albumID = album
        }
        let album = try await get("/albums/\(albumID)")
        var details = AlbumDetails()
        details.label = album["label"] as? String
        details.copyright = (album["copyrights"] as? [[String: Any]])?.compactMap { $0["text"] as? String }.first
        details.genre = (album["genres"] as? [String])?.prefix(3).joined(separator: ", ")
        if let release = album["release_date"] as? String {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = release.count == 4 ? "yyyy" : "yyyy-MM-dd"
            details.releaseDate = formatter.date(from: release)
        }
        let items = ((album["tracks"] as? [String: Any])?["items"] as? [[String: Any]]) ?? []
        details.tracks = items.compactMap { track in
            guard let name = track["name"] as? String else { return nil }
            let artists = (track["artists"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
            return AlbumDetails.Track(
                id: track["id"] as? String ?? name,
                number: track["track_number"] as? Int,
                disc: track["disc_number"] as? Int,
                title: name,
                artist: artists.joined(separator: ", "),
                durationMs: track["duration_ms"] as? Int,
                url: ((track["external_urls"] as? [String: Any])?["spotify"] as? String).flatMap(URL.init(string:))
            )
        }
        return details
    }

    // MARK: Plumbing

    private func get(_ path: String) async throws -> [String: Any] {
        guard let url = URL(string: "https://api.spotify.com/v1" + path) else { throw ServiceError.badResponse }
        let accessToken = try await validAccessToken()
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { tokens = nil; throw ServiceError.notConnected }
        if status == 403 {
            throw ServiceError.message("Spotify refused the request. While your Spotify app is in development mode, add your account under Users and Access in the Spotify developer dashboard.")
        }
        guard status == 200, let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ServiceError.badResponse
        }
        return json
    }

    private func validAccessToken() async throws -> String {
        guard var current = tokens else { throw ServiceError.notConnected }
        if current.expiresAt < Date() {
            current = try await requestTokens([
                "grant_type": "refresh_token",
                "refresh_token": current.refreshToken,
                "client_id": ServiceConfig.spotifyClientID,
            ], keepingRefreshToken: current.refreshToken)
            tokens = current
        }
        return current.accessToken
    }

    private func requestTokens(_ form: [String: String], keepingRefreshToken: String?) async throws -> Tokens {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = form.map { "\($0.key)=\(Self.formEncode($0.value))" }
            .joined(separator: "&")
            .data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = json["access_token"] as? String
        else { throw ServiceError.badResponse }
        let refresh = (json["refresh_token"] as? String) ?? keepingRefreshToken ?? ""
        let expiresIn = (json["expires_in"] as? Double) ?? 3600
        return Tokens(accessToken: access, refreshToken: refresh, expiresAt: Date().addingTimeInterval(expiresIn - 60))
    }

    private static func makeVerifier() -> String {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return String((0..<64).map { _ in chars.randomElement()! })
    }

    private static func challenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func parseDate(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}
