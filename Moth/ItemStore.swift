import Foundation
import Observation

@Observable
final class ItemStore {
    private(set) var items: [SavedItem] = []

    init() {
        reload()
    }

    /// Picks up anything the share extension saved while the app was in the background.
    func reload() {
        items = LibraryFile.load()
    }

    func setListened(_ item: SavedItem, _ listened: Bool) {
        update(item) {
            $0.listenedAt = listened ? .now : nil
            if !listened { $0.heardTrackIDs = nil }
        }
    }

    func delete(_ item: SavedItem) {
        LibraryFile.mutate { $0.removeAll { $0.id == item.id } }
        if let file = item.artworkFile { ArtworkStore.delete(named: file) }
        AlbumDetailsService.forget(item.id)
        reload()
    }

    func toggleTrackHeard(_ trackID: String, in item: SavedItem) {
        update(item) { item in
            var heard = Set(item.heardTrackIDs ?? [])
            if heard.contains(trackID) { heard.remove(trackID) } else { heard.insert(trackID) }
            item.heardTrackIDs = heard.isEmpty ? nil : Array(heard)
        }
    }

    func setListened(ids: Set<UUID>, _ listened: Bool) {
        LibraryFile.mutate { items in
            for index in items.indices where ids.contains(items[index].id) {
                items[index].listenedAt = listened ? .now : nil
                if !listened { items[index].heardTrackIDs = nil }
            }
        }
        reload()
    }

    func delete(ids: Set<UUID>) {
        let removed = LibraryFile.mutate { items -> [SavedItem] in
            let gone = items.filter { ids.contains($0.id) }
            items.removeAll { ids.contains($0.id) }
            return gone
        }
        removed.compactMap(\.artworkFile).forEach(ArtworkStore.delete(named:))
        removed.forEach { AlbumDetailsService.forget($0.id) }
        reload()
    }

    private func update(_ item: SavedItem, _ change: (inout SavedItem) -> Void) {
        LibraryFile.mutate { items in
            guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
            change(&items[index])
        }
        reload()
    }
}
