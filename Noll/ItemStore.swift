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
        update(item) { $0.listenedAt = listened ? .now : nil }
    }

    func toggleListened(_ item: SavedItem) {
        setListened(item, !item.isListened)
    }

    func delete(_ item: SavedItem) {
        LibraryFile.mutate { $0.removeAll { $0.id == item.id } }
        if let file = item.artworkFile { ArtworkStore.delete(named: file) }
        reload()
    }

    func clearListened() {
        let removed = LibraryFile.mutate { items -> [SavedItem] in
            let listened = items.filter(\.isListened)
            items.removeAll(where: \.isListened)
            return listened
        }
        removed.compactMap(\.artworkFile).forEach(ArtworkStore.delete(named:))
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
