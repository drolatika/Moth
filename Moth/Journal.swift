import Foundation
import Observation

/// Enough about a release to show and open it from the journal, even after it has
/// left the library.
struct ReleaseRef: Codable, Hashable {
    var key: String
    var title: String
    var artist: String?
    var url: URL
    var platform: Platform
    var artworkURL: URL?
    var artworkFile: String?

    init(key: String, title: String, artist: String?, url: URL, platform: Platform, artworkURL: URL?, artworkFile: String? = nil) {
        self.key = key
        self.title = title
        self.artist = artist
        self.url = url
        self.platform = platform
        self.artworkURL = artworkURL
        self.artworkFile = artworkFile
    }

    init(_ item: SavedItem) {
        self.init(key: item.linkKey, title: item.title, artist: item.artist, url: item.url,
                  platform: item.platform, artworkURL: item.artworkURL, artworkFile: item.artworkFile)
    }

    init(_ release: StackRelease, in stack: SavedItem) {
        self.init(key: LinkCleaner.key(for: release.url), title: release.title, artist: stack.title,
                  url: release.url, platform: stack.platform, artworkURL: release.artworkURL)
    }
}

/// Your rating, review and private notes on one release.
struct ReleaseRecord: Codable, Identifiable {
    var ref: ReleaseRef
    /// 0.5 … 5, in half stars.
    var rating: Double?
    var review: String?
    var notes: String?
    var updatedAt: Date

    var id: String { ref.key }
    var hasContent: Bool { rating != nil || !(review ?? "").isEmpty || !(notes ?? "").isEmpty }
}

/// One listen in the diary.
struct LogEntry: Codable, Identifiable {
    var id: UUID
    var ref: ReleaseRef
    var date: Date
    /// Logged by marking something heard, rather than by hand.
    var auto: Bool
}

struct ArtistTally: Identifiable {
    let name: String
    let listens: Int
    let averageRating: Double?
    let artwork: ReleaseRef
    var id: String { name }
}

/// Ratings, reviews, notes and the listening log. Lives next to the library in
/// the App Group container.
@Observable
final class JournalStore {
    private(set) var records: [String: ReleaseRecord] = [:]
    private(set) var log: [LogEntry] = []

    private struct File: Codable {
        var records: [ReleaseRecord]
        var log: [LogEntry]
    }

    private static var url: URL { AppGroup.containerURL.appendingPathComponent("journal.json") }

    init() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: Self.url), let file = try? decoder.decode(File.self, from: data) {
            records = Dictionary(file.records.map { ($0.ref.key, $0) }, uniquingKeysWith: { $1 })
            log = file.log
        }
    }

    // MARK: Ratings, reviews and notes

    func record(for key: String) -> ReleaseRecord? { records[key] }
    func rating(for key: String) -> Double? { records[key]?.rating }

    func save(_ ref: ReleaseRef, rating: Double?, review: String, notes: String) {
        let review = review.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let record = ReleaseRecord(ref: ref, rating: rating, review: review.isEmpty ? nil : review,
                                   notes: notes.isEmpty ? nil : notes, updatedAt: .now)
        records[ref.key] = record.hasContent ? record : nil
        persist()
    }

    var rated: [ReleaseRecord] { records.values.filter { $0.rating != nil } }
    var topRated: [ReleaseRecord] {
        rated.sorted { ($0.rating!, $0.updatedAt) > ($1.rating!, $1.updatedAt) }
    }
    var lowestRated: [ReleaseRecord] {
        rated.sorted { ($0.rating!, $1.updatedAt) < ($1.rating!, $0.updatedAt) }
    }
    var reviewed: [ReleaseRecord] {
        records.values.filter { !($0.review ?? "").isEmpty }.sorted { $0.updatedAt > $1.updatedAt }
    }
    var withNotes: [ReleaseRecord] {
        records.values.filter { !($0.notes ?? "").isEmpty }.sorted { $0.updatedAt > $1.updatedAt }
    }

    // MARK: Listening log

    func logListen(_ ref: ReleaseRef, on date: Date = .now, auto: Bool = false) {
        log.insert(LogEntry(id: UUID(), ref: ref, date: date, auto: auto), at: 0)
        log.sort { $0.date > $1.date }
        persist()
    }

    /// Undo the automatic entries for a release that was moved back to the queue.
    func removeAutoLogs(for key: String, since date: Date) {
        log.removeAll { $0.auto && $0.ref.key == key && $0.date >= date.addingTimeInterval(-1) }
        persist()
    }

    func delete(_ entry: LogEntry) {
        log.removeAll { $0.id == entry.id }
        persist()
    }

    func listens(for key: String) -> Int { log.filter { $0.ref.key == key }.count }

    /// Artists by how many listens are logged, with their average rating.
    var topArtists: [ArtistTally] {
        let byArtist = Dictionary(grouping: log.filter { $0.ref.artist != nil }) { $0.ref.artist! }
        return byArtist.map { name, entries in
            let ratings = Set(entries.map(\.ref.key)).compactMap { records[$0]?.rating }
            return ArtistTally(name: name, listens: entries.count,
                               averageRating: ratings.isEmpty ? nil : ratings.reduce(0, +) / Double(ratings.count),
                               artwork: entries[0].ref)
        }
        .sorted { ($0.listens, $1.name) > ($1.listens, $0.name) }
    }

    // MARK: Storage

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let file = File(records: Array(records.values), log: log)
        guard let data = try? encoder.encode(file) else { return }
        try? FileManager.default.createDirectory(at: Self.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: Self.url, options: .atomic)
    }
}

extension ReleaseRef: Identifiable {
    var id: String { key }
}
