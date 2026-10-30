import MusicKit

struct RecentlyPlayed: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let artworkURL: URL?
}

/// Apple Music through MusicKit. Needs the MusicKit app service enabled for the
/// app's identifier (paid developer account). Apple doesn't expose listening
/// time, so this shows what you've played recently.
enum AppleMusicService {
    static var isAuthorized: Bool { MusicAuthorization.currentStatus == .authorized }

    static func connect() async -> Bool {
        await MusicAuthorization.request() == .authorized
    }

    static func recentlyPlayed() async throws -> [RecentlyPlayed] {
        var request = MusicRecentlyPlayedContainerRequest()
        request.limit = 12
        let response = try await request.response()
        return response.items.compactMap { (item: RecentlyPlayedMusicItem) -> RecentlyPlayed? in
            switch item {
            case .album(let album):
                return RecentlyPlayed(id: album.id.rawValue, title: album.title, subtitle: album.artistName,
                                      artworkURL: album.artwork?.url(width: 300, height: 300))
            case .playlist(let playlist):
                return RecentlyPlayed(id: playlist.id.rawValue, title: playlist.name, subtitle: playlist.curatorName ?? "Playlist",
                                      artworkURL: playlist.artwork?.url(width: 300, height: 300))
            case .station(let station):
                return RecentlyPlayed(id: station.id.rawValue, title: station.name, subtitle: "Station",
                                      artworkURL: station.artwork?.url(width: 300, height: 300))
            @unknown default:
                return nil
            }
        }
    }
}
