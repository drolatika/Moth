import Foundation

/// An artist found by name on one service.
struct ArtistResult: Identifiable, Hashable {
    var id: String
    var name: String
    var detail: String?
    var imageURL: URL?
    var url: URL
    var platform: Platform
}

/// Finds artists by name and lists their releases, so a whole discography can be
/// saved as one stack. Apple Music (iTunes Search) and Deezer need no account;
/// Spotify needs to be connected.
enum ArtistCatalog {
    static func services(spotifyConnected: Bool) -> [Platform] {
        spotifyConnected ? [.appleMusic, .spotify, .deezer] : [.appleMusic, .deezer]
    }

    static func search(_ name: String, on platform: Platform) async throws -> [ArtistResult] {
        let term = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return [] }
        switch platform {
        case .appleMusic: return try await appleMusicSearch(term)
        case .deezer: return try await deezerSearch(term)
        case .spotify: return try await SpotifyService.shared.searchArtists(term)
        default: return []
        }
    }

    /// A picture for an artist whose search result didn't include one.
    static func image(for artist: ArtistResult) async -> URL? {
        if let url = artist.imageURL { return url }
        guard artist.platform == .appleMusic,
              let (data, _) = try? await MetadataFetcher.session.data(from: artist.url)
        else { return nil }
        let tags = MetadataFetcher.parseMetaTags(String(decoding: data.prefix(600_000), as: UTF8.self))
        guard let image = tags["og:image"] else { return nil }
        return URL(string: squareAppleImage(image))
    }

    static func releases(for artist: ArtistResult) async throws -> [StackRelease] {
        let releases: [StackRelease]
        switch artist.platform {
        case .appleMusic: releases = try await appleMusicReleases(artist)
        case .deezer: releases = try await deezerReleases(artist)
        case .spotify: releases = try await SpotifyService.shared.artistReleases(id: artist.id)
        default: releases = []
        }
        // Services list clean and explicit versions, or the same single twice.
        var seen = Set<String>()
        return releases
            .filter { seen.insert("\($0.type.rawValue)|\($0.title.lowercased())").inserted }
            .sorted { ($0.releaseDate ?? .distantPast) > ($1.releaseDate ?? .distantPast) }
    }

    // MARK: Apple Music

    private static var country: String {
        (Locale.current.region?.identifier ?? "US").lowercased()
    }

    private static func appleMusicSearch(_ term: String) async throws -> [ArtistResult] {
        let query = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? term
        let json = try await fetchJSON("https://itunes.apple.com/search?term=\(query)&entity=musicArtist&limit=12&country=\(country)")
        return (json["results"] as? [[String: Any]] ?? []).compactMap { result in
            guard let id = result["artistId"] as? Int,
                  let name = result["artistName"] as? String,
                  let link = (result["artistLinkUrl"] as? String).flatMap(URL.init(string:))
            else { return nil }
            return ArtistResult(id: String(id), name: name, detail: result["primaryGenreName"] as? String,
                                imageURL: nil, url: LinkCleaner.clean(link), platform: .appleMusic)
        }
    }

    private static func appleMusicReleases(_ artist: ArtistResult) async throws -> [StackRelease] {
        let json = try await fetchJSON("https://itunes.apple.com/lookup?id=\(artist.id)&entity=album&limit=200&country=\(country)")
        return (json["results"] as? [[String: Any]] ?? []).compactMap { result in
            guard result["wrapperType"] as? String == "collection",
                  let id = result["collectionId"] as? Int,
                  var title = result["collectionName"] as? String,
                  let link = (result["collectionViewUrl"] as? String).flatMap(URL.init(string:))
            else { return nil }
            var type = StackRelease.ReleaseType.album
            if title.hasSuffix(" - EP") {
                type = .ep
                title.removeLast(5)
            } else if title.hasSuffix(" - Single") {
                type = .single
                title.removeLast(9)
            }
            let art = (result["artworkUrl100"] as? String)
                .map { $0.replacingOccurrences(of: "100x100bb", with: "600x600bb") }
                .flatMap(URL.init(string:))
            return StackRelease(id: String(id), title: title, url: LinkCleaner.clean(link), artworkURL: art,
                                releaseDate: (result["releaseDate"] as? String).flatMap(parseDate), type: type)
        }
    }

    /// Apple's share images are wide crops; ask the image server for a square one.
    private static func squareAppleImage(_ string: String) -> String {
        guard string.contains("mzstatic.com"),
              let range = string.range(of: #"/\d+x\d+[a-z]*\.(jpg|jpeg|png|webp)$"#, options: .regularExpression)
        else { return string }
        return string.replacingCharacters(in: range, with: "/600x600cc.jpg")
    }

    // MARK: Deezer

    private static func deezerSearch(_ term: String) async throws -> [ArtistResult] {
        let query = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? term
        let json = try await fetchJSON("https://api.deezer.com/search/artist?q=\(query)&limit=12")
        return (json["data"] as? [[String: Any]] ?? []).compactMap { artist in
            guard let id = artist["id"] as? Int, let name = artist["name"] as? String else { return nil }
            let albums = artist["nb_album"] as? Int ?? 0
            return ArtistResult(
                id: String(id), name: name,
                detail: albums == 1 ? "1 release" : "\(albums) releases",
                imageURL: (artist["picture_xl"] as? String).flatMap(URL.init(string:)),
                url: URL(string: "https://www.deezer.com/artist/\(id)")!,
                platform: .deezer
            )
        }
    }

    private static func deezerReleases(_ artist: ArtistResult) async throws -> [StackRelease] {
        let json = try await fetchJSON("https://api.deezer.com/artist/\(artist.id)/albums?limit=300")
        return (json["data"] as? [[String: Any]] ?? []).compactMap { album in
            guard let id = album["id"] as? Int, let title = album["title"] as? String else { return nil }
            let type: StackRelease.ReleaseType = switch album["record_type"] as? String ?? "" {
            case "ep": .ep
            case "single": .single
            default: .album
            }
            return StackRelease(id: String(id), title: title,
                                url: URL(string: "https://www.deezer.com/album/\(id)")!,
                                artworkURL: (album["cover_xl"] as? String).flatMap(URL.init(string:)),
                                releaseDate: (album["release_date"] as? String).flatMap(parseDate), type: type)
        }
    }

    // MARK: Saving

    /// Saves the artist as one stack holding these releases. Saving the same artist
    /// again adds any new releases and keeps what's already marked heard.
    @discardableResult
    static func saveStack(_ artist: ArtistResult, releases: [StackRelease]) async -> SavedItem {
        let key = LinkCleaner.key(for: artist.url)
        let imageURL = await image(for: artist)
        let merged = LibraryFile.mutate { items -> SavedItem? in
            guard let index = items.firstIndex(where: { $0.linkKey == key }) else { return nil }
            var item = items.remove(at: index)
            let existing = Set((item.stack ?? []).map(\.id))
            let added = releases.filter { !existing.contains($0.id) }
            item.stack = ((item.stack ?? []) + added)
                .sorted { ($0.releaseDate ?? .distantPast) > ($1.releaseDate ?? .distantPast) }
            item.dateAdded = .now
            if !added.isEmpty { item.listenedAt = nil }
            items.insert(item, at: 0)
            return item
        }
        if let merged { return merged }

        var item = SavedItem(
            id: UUID(), url: artist.url, title: artist.name, artist: nil, kind: .artist,
            platform: artist.platform, artworkURL: imageURL, artworkFile: nil,
            dateAdded: .now, listenedAt: nil, stack: releases
        )
        if let imageURL, let (data, _) = try? await MetadataFetcher.session.data(from: imageURL) {
            item.artworkFile = ArtworkStore.save(data, id: item.id)
        }
        let saved = item
        LibraryFile.mutate { $0.insert(saved, at: 0) }
        return saved
    }

    // MARK: Helpers

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 12
        return URLSession(configuration: config)
    }()

    private static func fetchJSON(_ string: String) async throws -> [String: Any] {
        guard let url = URL(string: string) else { throw ServiceError.badResponse }
        let (data, _) = try await session.data(from: url)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ServiceError.badResponse }
        return object
    }

    static func parseDate(_ text: String) -> Date? {
        if let date = ISO8601DateFormatter().date(from: text) { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        for format in ["yyyy-MM-dd", "yyyy-MM", "yyyy"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: String(text.prefix(format.count))) { return date }
        }
        return nil
    }
}
