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
    /// For an artist stack: the releases it holds. The item's artwork is the artist's picture.
    var stack: [StackRelease]? = nil

    var isStack: Bool { stack != nil }
    var isListened: Bool { listenedAt != nil }
    /// Some tracks (or, for a stack, some releases) are marked heard but the item itself isn't.
    var isPartlyHeard: Bool { !isListened && heardTrackCount > 0 }
    var heardTrackCount: Int {
        if let stack { return stack.filter(\.isHeard).count }
        return heardTrackIDs?.count ?? 0
    }
    var linkKey: String { LinkCleaner.key(for: url) }
}

/// One album, EP or single inside an artist stack.
struct StackRelease: Identifiable, Codable, Hashable {
    enum ReleaseType: String, Codable, CaseIterable, Identifiable {
        case album, ep, single

        var id: String { rawValue }
        var label: String {
            switch self {
            case .album: "Album"
            case .ep: "EP"
            case .single: "Single"
            }
        }
        var pluralLabel: String {
            switch self {
            case .album: "Albums"
            case .ep: "EPs"
            case .single: "Singles"
            }
        }
    }

    var id: String
    var title: String
    var url: URL
    var artworkURL: URL?
    var releaseDate: Date?
    var type: ReleaseType
    var heardAt: Date?

    var isHeard: Bool { heardAt != nil }
    var year: String? { releaseDate.map { String(Calendar.current.component(.year, from: $0)) } }
}
