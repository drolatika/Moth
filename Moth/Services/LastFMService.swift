import Foundation

/// Last.fm's public read API: only an API key and a username, no sign-in needed.
enum LastFMService {
    static var isConfigured: Bool { !ServiceConfig.lastFMAPIKey.isEmpty }

    static var username: String? {
        get { AppGroup.defaults.string(forKey: SettingsKey.lastFMUser) }
        set { AppGroup.defaults.set(newValue, forKey: SettingsKey.lastFMUser) }
    }

    /// Checks the account exists and returns its canonical name.
    static func verify(_ user: String) async throws -> String {
        let json = try await call("user.getinfo", ["user": user])
        guard let info = json["user"] as? [String: Any], let name = info["name"] as? String else {
            throw ServiceError.message("Couldn't find a Last.fm user called \u{201C}\(user)\u{201D}.")
        }
        return name
    }

    /// Number of scrobbles since `date`.
    static func scrobbleCount(for user: String, since date: Date) async throws -> Int {
        let json = try await call("user.getrecenttracks", [
            "user": user, "from": String(Int(date.timeIntervalSince1970)), "limit": "1",
        ])
        let attributes = (json["recenttracks"] as? [String: Any])?["@attr"] as? [String: Any]
        return Int(attributes?["total"] as? String ?? "") ?? 0
    }

    static func topArtists(for user: String) async throws -> [RankedArtist] {
        let json = try await call("user.gettopartists", ["user": user, "period": "7day", "limit": "5"])
        let artists = (json["topartists"] as? [String: Any])?["artist"] as? [[String: Any]] ?? []
        return artists.compactMap { artist in
            guard let name = artist["name"] as? String else { return nil }
            let plays = artist["playcount"] as? String ?? "0"
            return RankedArtist(name: name, detail: plays == "1" ? "1 play" : "\(plays) plays")
        }
    }

    private static func call(_ method: String, _ params: [String: String]) async throws -> [String: Any] {
        guard isConfigured else { throw ServiceError.notConfigured }
        var components = URLComponents(string: "https://ws.audioscrobbler.com/2.0/")!
        components.queryItems = [
            URLQueryItem(name: "method", value: method),
            URLQueryItem(name: "api_key", value: ServiceConfig.lastFMAPIKey),
            URLQueryItem(name: "format", value: "json"),
        ] + params.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components.url else { throw ServiceError.badResponse }
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ServiceError.badResponse }
        if let message = json["message"] as? String, json["error"] != nil { throw ServiceError.message(message) }
        return json
    }
}
