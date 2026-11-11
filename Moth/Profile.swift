import Observation
import UIKit

/// An artist, album or track pinned to the profile.
struct ShowcaseItem: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    var subtitle: String?
    var imageURL: URL?
    var imageFile: String?
    var url: URL?
    var platform: Platform
}

enum ShowcaseKind: String, CaseIterable, Identifiable {
    case artists, albums, tracks
    var id: String { rawValue }
    var title: String {
        switch self {
        case .artists: "Top 4 Artists"
        case .albums: "Top 4 Albums"
        case .tracks: "Top 4 Tracks"
        }
    }
    var singular: String {
        switch self {
        case .artists: "artist"
        case .albums: "album"
        case .tracks: "track"
        }
    }
}

/// Your profile: name, picture, and the artists, albums and tracks you pin to it.
/// Just for you on this device for now.
@Observable
final class ProfileStore {
    private(set) var name: String
    private(set) var bio: String
    private(set) var photo: UIImage?
    private(set) var showcase: [ShowcaseKind: [ShowcaseItem?]]

    private struct Saved: Codable {
        var name: String
        var bio: String?
        var showcase: [String: [ShowcaseItem?]]
    }

    private static let key = "profile"
    private static var photoURL: URL { AppGroup.containerURL.appendingPathComponent("profile.jpg") }

    init() {
        let saved = AppGroup.defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(Saved.self, from: $0) }
        name = saved?.name ?? ""
        bio = saved?.bio ?? ""
        var showcase: [ShowcaseKind: [ShowcaseItem?]] = [:]
        for kind in ShowcaseKind.allCases {
            let slots = saved?.showcase[kind.rawValue] ?? []
            showcase[kind] = (0..<4).map { $0 < slots.count ? slots[$0] : nil }
        }
        self.showcase = showcase
        photo = UIImage(contentsOfFile: Self.photoURL.path)
    }

    func setName(_ name: String, bio: String) {
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.bio = bio.trimmingCharacters(in: .whitespacesAndNewlines)
        persist()
    }

    func slots(_ kind: ShowcaseKind) -> [ShowcaseItem?] { showcase[kind] ?? Array(repeating: nil, count: 4) }

    func set(_ item: ShowcaseItem?, at index: Int, in kind: ShowcaseKind) {
        var slots = slots(kind)
        guard slots.indices.contains(index) else { return }
        slots[index] = item
        showcase[kind] = slots
        persist()
    }

    func move(_ kind: ShowcaseKind, from: Int, to: Int) {
        var slots = slots(kind)
        guard slots.indices.contains(from), slots.indices.contains(to) else { return }
        slots.swapAt(from, to)
        showcase[kind] = slots
        persist()
    }

    func setPhoto(_ data: Data) {
        guard let image = UIImage(data: data) else { return }
        let side: CGFloat = 900
        let scale = min(1, side / max(image.size.width, image.size.height))
        let target = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        try? resized.jpegData(compressionQuality: 0.88)?.write(to: Self.photoURL, options: .atomic)
        photo = resized
    }

    func removePhoto() {
        try? FileManager.default.removeItem(at: Self.photoURL)
        photo = nil
    }

    private func persist() {
        let saved = Saved(name: name, bio: bio, showcase: Dictionary(uniqueKeysWithValues: showcase.map { ($0.key.rawValue, $0.value) }))
        if let data = try? JSONEncoder().encode(saved) { AppGroup.defaults.set(data, forKey: Self.key) }
    }
}

/// Searching for something to pin: Apple Music's catalogue (no account needed).
enum ShowcaseSearch {
    static func search(_ term: String, kind: ShowcaseKind) async -> [ShowcaseItem] {
        let term = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return [] }
        if kind == .artists {
            let artists = (try? await ArtistCatalog.search(term, on: .appleMusic)) ?? []
            return artists.map {
                ShowcaseItem(id: "am-artist-\($0.id)", title: $0.name, subtitle: $0.detail, imageURL: nil, url: $0.url, platform: .appleMusic)
            }
        }
        let entity = kind == .albums ? "album" : "song"
        let query = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? term
        let country = (Locale.current.region?.identifier ?? "US").lowercased()
        guard let url = URL(string: "https://itunes.apple.com/search?term=\(query)&entity=\(entity)&limit=20&country=\(country)"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [] }
        return (json["results"] as? [[String: Any]] ?? []).compactMap { result in
            let id = kind == .albums ? result["collectionId"] as? Int : result["trackId"] as? Int
            let title = kind == .albums ? result["collectionName"] as? String : result["trackName"] as? String
            guard let id, let title else { return nil }
            let link = (kind == .albums ? result["collectionViewUrl"] : result["trackViewUrl"]) as? String
            return ShowcaseItem(
                id: "am-\(entity)-\(id)", title: title, subtitle: result["artistName"] as? String,
                imageURL: (result["artworkUrl100"] as? String).flatMap { URL(string: $0.replacingOccurrences(of: "100x100bb", with: "600x600bb")) },
                url: link.flatMap(URL.init(string:)).map(LinkCleaner.clean), platform: .appleMusic
            )
        }
    }
}
