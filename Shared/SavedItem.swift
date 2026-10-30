import Foundation

struct SavedItem: Identifiable, Codable, Hashable {
    enum Kind: String, Codable {
        case album, track, playlist, artist, episode, other

        var label: String {
            switch self {
            case .album: "Album"
            case .track: "Track"
            case .playlist: "Playlist"
            case .artist: "Artist"
            case .episode: "Episode"
            case .other: "Link"
            }
        }
    }

    var id: UUID
    var url: URL
    var title: String
    var artist: String?
    var kind: Kind
    var platform: Platform
    var artworkURL: URL?
    var artworkFile: String?
    var dateAdded: Date
    var listenedAt: Date?
    /// Tracks marked heard on the album page (track IDs from AlbumDetails).
    var heardTrackIDs: [String]? = nil

    var isListened: Bool { listenedAt != nil }
    var linkKey: String { LinkCleaner.key(for: url) }
}
