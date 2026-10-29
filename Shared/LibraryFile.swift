import Foundation

/// The saved library lives as one JSON file in the App Group container so the
/// share extension and the app read and write the same data.
enum LibraryFile {
    static var url: URL { AppGroup.containerURL.appendingPathComponent("library.json") }

    static func load() -> [SavedItem] {
        read(at: url)
    }

    /// Reads, changes and writes the library under a file coordinator, so a save
    /// from the share extension can't clobber a change made in the app.
    @discardableResult
    static func mutate<T>(_ body: (inout [SavedItem]) -> T) -> T {
        var result: T?
        var error: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forMerging, error: &error) { url in
            var items = read(at: url)
            result = body(&items)
            write(items, to: url)
        }
        if let result { return result }

        var items = load()
        let fallback = body(&items)
        write(items, to: url)
        return fallback
    }

    private static func read(at url: URL) -> [SavedItem] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([SavedItem].self, from: data)) ?? []
    }

    private static func write(_ items: [SavedItem], to url: URL) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(items) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
