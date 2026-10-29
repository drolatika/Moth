import Foundation

/// The one save pipeline used by both the share extension and the in-app "Add link" sheet.
enum LibrarySaver {
    struct Result {
        var item: SavedItem
        var duplicate: Bool
    }

    static func save(_ rawURL: URL) async -> Result {
        let cleaned = LinkCleaner.clean(rawURL)
        if let existing = bumpExisting(key: LinkCleaner.key(for: cleaned)) {
            return Result(item: existing, duplicate: true)
        }

        let meta = await MetadataFetcher.fetch(cleaned)
        if let existing = bumpExisting(key: LinkCleaner.key(for: meta.url)) {
            return Result(item: existing, duplicate: true)
        }

        var item = SavedItem(
            id: UUID(),
            url: meta.url,
            title: meta.title,
            artist: meta.artist,
            kind: meta.kind,
            platform: meta.platform,
            artworkURL: meta.artworkURL,
            artworkFile: nil,
            dateAdded: .now,
            listenedAt: nil
        )
        if let artworkURL = meta.artworkURL,
           let (data, _) = try? await MetadataFetcher.session.data(from: artworkURL) {
            item.artworkFile = ArtworkStore.save(data, id: item.id)
        }

        let saved = item
        LibraryFile.mutate { $0.insert(saved, at: 0) }
        return Result(item: saved, duplicate: false)
    }

    /// Saving something already in the library moves it back to the top of the queue.
    private static func bumpExisting(key: String) -> SavedItem? {
        LibraryFile.mutate { items -> SavedItem? in
            guard let index = items.firstIndex(where: { $0.linkKey == key }) else { return nil }
            var item = items.remove(at: index)
            item.dateAdded = .now
            item.listenedAt = nil
            items.insert(item, at: 0)
            return item
        }
    }
}
