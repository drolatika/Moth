import Foundation
import Observation

/// Connection state for Settings and Stats.
@MainActor
@Observable
final class Connections {
    var spotifyConnected = SpotifyService.shared.isConnected
    var lastFMUser = LastFMService.username
    var appleMusicAuthorized = AppleMusicService.isAuthorized
    var working: String?
    var errorMessage: String?

    var spotifyConfigured: Bool { SpotifyService.shared.isConfigured }
    var lastFMConfigured: Bool { LastFMService.isConfigured }
    var anyConnected: Bool { spotifyConnected || lastFMUser != nil || appleMusicAuthorized }

    func connectSpotify() async {
        working = "Spotify"
        defer { working = nil }
        do {
            try await SpotifyService.shared.connect()
            spotifyConnected = true
        } catch ServiceError.cancelled {
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func disconnectSpotify() {
        SpotifyService.shared.disconnect()
        spotifyConnected = false
    }

    func connectLastFM(user: String) async {
        let trimmed = user.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        working = "Last.fm"
        defer { working = nil }
        do {
            let name = try await LastFMService.verify(trimmed)
            LastFMService.username = name
            lastFMUser = name
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func disconnectLastFM() {
        LastFMService.username = nil
        lastFMUser = nil
    }

    func connectAppleMusic() async {
        appleMusicAuthorized = await AppleMusicService.connect()
        if !appleMusicAuthorized {
            errorMessage = "Moth needs permission to read your Apple Music history. You can allow it in Settings › Moth."
        }
    }
}
