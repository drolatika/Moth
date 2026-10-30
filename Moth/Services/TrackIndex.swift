import Foundation
import Observation

/// Track titles for every saved album, so search can find a track inside an album.
/// Starts from the on-device cache, then quietly fetches the rest in the background.
@MainActor
@Observable
final class TrackIndex {
    private(set) var titles: [UUID: [String]] = [:]
    @ObservationIgnored private var fetching = false

    func refresh(_ items: [SavedItem]) {
        for item in items where titles[item.id] == nil {
            if let cached = AlbumDetailsService.cachedDetails(for: item.id), !cached.tracks.isEmpty {
                titles[item.id] = cached.tracks.map(\.title)
            }
        }
        guard !fetching else { return }
        let missing = items.filter { titles[$0.id] == nil && AlbumDetailsService.supports($0.platform) }
        guard !missing.isEmpty else { return }
        fetching = true
        Task {
            for item in missing {
                let details = await AlbumDetailsService.details(for: item)
                // An empty list means "tried"; it isn't retried until the app relaunches.
                titles[item.id] = details?.tracks.map(\.title) ?? []
                try? await Task.sleep(for: .milliseconds(300))
            }
            fetching = false
        }
    }

    func update(_ id: UUID, with details: AlbumDetails) {
        titles[id] = details.tracks.map(\.title)
    }

    /// The first track on this album whose title contains `query`, if any.
    func matchingTrack(in item: SavedItem, query: String) -> String? {
        guard !query.isEmpty else { return nil }
        return titles[item.id]?.first { $0.localizedCaseInsensitiveContains(query) }
    }
}
