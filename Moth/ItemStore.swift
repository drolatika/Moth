import Foundation
import Observation

@Observable
final class ItemStore {
    private(set) var items: [SavedItem] = []
    /// Ratings, reviews, notes and the listening log. Marking something heard logs a listen.
    let journal = JournalStore()

    init() {
        reload()
    }

    /// Picks up anything the share extension saved while the app was in the background.
    func reload() {
        items = LibraryFile.load()
    }

    func setListened(_ item: SavedItem, _ listened: Bool) {
        update(item) { Self.mark(&$0, listened) }
        recordListen(item, listened)
    }

    /// Heard sets the date; back to the queue clears it along with any struck tracks.
    /// A stack marks (or clears) every release it holds.
    private static func mark(_ item: inout SavedItem, _ listened: Bool) {
        let now = Date()
        item.listenedAt = listened ? now : nil
        if !listened { item.heardTrackIDs = nil }
        if let stack = item.stack {
            item.stack = stack.map { release in
                var release = release
                release.heardAt = listened ? (release.heardAt ?? now) : nil
                return release
            }
        }
    }

    /// Albums and tracks go in the listening log when heard, and come out again if
    /// they're moved straight back. Stacks don't: marking a discography isn't a listen.
    private func recordListen(_ item: SavedItem, _ listened: Bool) {
        guard !item.isStack else { return }
        if listened, !item.isListened {
            journal.logListen(ReleaseRef(item), auto: true)
        } else if !listened, let date = item.listenedAt {
            journal.removeAutoLogs(for: item.linkKey, since: date)
        }
    }

    // MARK: Stacks

    func toggleReleaseHeard(_ releaseID: String, in item: SavedItem) {
        guard let release = item.stack?.first(where: { $0.id == releaseID }) else { return }
        let ref = ReleaseRef(release, in: item)
        if let heardAt = release.heardAt {
            journal.removeAutoLogs(for: ref.key, since: heardAt)
        } else {
            journal.logListen(ref, auto: true)
        }
        update(item) { item in
            guard var stack = item.stack, let index = stack.firstIndex(where: { $0.id == releaseID }) else { return }
            stack[index].heardAt = stack[index].heardAt == nil ? .now : nil
            item.stack = stack
            // The stack moves to Heard once everything in it is heard.
            item.listenedAt = stack.allSatisfy(\.isHeard) ? (item.listenedAt ?? .now) : nil
        }
    }

    func removeRelease(_ releaseID: String, from item: SavedItem) {
        update(item) { item in
            item.stack?.removeAll { $0.id == releaseID }
            if let stack = item.stack, !stack.isEmpty, stack.allSatisfy(\.isHeard) {
                item.listenedAt = item.listenedAt ?? .now
            }
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
        items.filter { ids.contains($0.id) }.forEach { recordListen($0, listened) }
        LibraryFile.mutate { items in
            for index in items.indices where ids.contains(items[index].id) {
                Self.mark(&items[index], listened)
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
