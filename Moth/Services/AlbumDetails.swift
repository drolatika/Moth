import Foundation

/// Tracklist and credits for a saved album or track.
struct AlbumDetails: Codable {
    struct Track: Codable, Identifiable, Hashable {
        var id: String
        var number: Int?
        var disc: Int?
        var title: String
        var artist: String?
        var durationMs: Int?
        var url: URL?
    }

    var tracks: [Track] = []
    var releaseDate: Date?
    var label: String?
    var copyright: String?
    var genre: String?
    /// Free-form credits (mastering, written by, …), as the service writes them.
    var credits: String?
    var fetchedAt = Date()

    var totalDurationMs: Int { tracks.compactMap(\.durationMs).reduce(0, +) }
}

/// Fetches tracklists and credits per service, with a small on-device cache.
/// Apple Music (iTunes Lookup), Bandcamp (the page's JSON-LD) and Deezer (public
/// API) need no account. Spotify uses the Web API when connected, otherwise the
/// public embed page. Other services return nil.
enum AlbumDetailsService {
    static func supports(_ platform: Platform) -> Bool {
        [.appleMusic, .bandcamp, .deezer, .spotify].contains(platform)
    }

    static func details(for item: SavedItem) async -> AlbumDetails? {
        if let cached = cache(for: item.id), !cached.tracks.isEmpty, Date().timeIntervalSince(cached.fetchedAt) < 7 * 86_400 {
            return cached
        }
        let fetched: AlbumDetails?
        switch item.platform {
        case .appleMusic: fetched = try? await appleMusic(item.url)
        case .bandcamp: fetched = try? await bandcamp(item.url)
        case .deezer: fetched = try? await deezer(item.url)
        case .spotify: fetched = try? await spotify(item.url)
        default: fetched = nil
        }
        if let fetched, !fetched.tracks.isEmpty || fetched.credits != nil { store(fetched, for: item.id) }
        return fetched
    }

    // MARK: Apple Music

    private static func appleMusic(_ url: URL) async throws -> AlbumDetails? {
        let parts = url.pathComponents.filter { $0 != "/" }
        let country = parts.first.flatMap { $0.count == 2 ? $0 : nil } ?? "us"
        var collectionID: String?
        if let last = parts.last {
            let id = last.hasPrefix("id") ? String(last.dropFirst(2)) : last
            if id.allSatisfy(\.isNumber), parts.contains("album") { collectionID = id }
        }
        let trackID = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "i" }?.value
            ?? (parts.contains("song") ? parts.last : nil)
        if collectionID == nil, let trackID {
            let lookup = try await json("https://itunes.apple.com/lookup?id=\(trackID)&country=\(country)")
            if let id = ((lookup["results"] as? [[String: Any]])?.first?["collectionId"] as? Int) { collectionID = String(id) }
        }
        guard let collectionID else { return nil }
        let lookup = try await json("https://itunes.apple.com/lookup?id=\(collectionID)&entity=song&country=\(country)")
        let results = lookup["results"] as? [[String: Any]] ?? []
        guard let album = results.first(where: { $0["wrapperType"] as? String == "collection" }) else { return nil }
        var details = AlbumDetails()
        details.copyright = album["copyright"] as? String
        details.genre = album["primaryGenreName"] as? String
        details.releaseDate = (album["releaseDate"] as? String).flatMap(parseISO)
        details.tracks = results.filter { $0["wrapperType"] as? String == "track" }.compactMap { track in
            guard let title = track["trackName"] as? String else { return nil }
            return AlbumDetails.Track(
                id: String(track["trackId"] as? Int ?? title.hashValue),
                number: track["trackNumber"] as? Int,
                disc: track["discNumber"] as? Int,
                title: title,
                artist: track["artistName"] as? String,
                durationMs: track["trackTimeMillis"] as? Int,
                url: (track["trackViewUrl"] as? String).flatMap(URL.init(string:))
            )
        }
        return details
    }

    // MARK: Bandcamp

    /// Bandcamp pages carry the player's data in a `data-tralbum` attribute (track
    /// titles, lengths, links, release date, credits) and schema.org JSON-LD
    /// (label, and a second source for everything else).
    private static func bandcamp(_ url: URL) async throws -> AlbumDetails? {
        let html = try await page(url)
        let ld = bandcampJSONLD(html)
        var details = bandcampTralbum(html, pageURL: url) ?? AlbumDetails()

        if details.tracks.isEmpty, let ld { details.tracks = bandcampLDTracks(ld, pageURL: url) }
        if let ld {
            details.label = details.label
                ?? ((ld["publisher"] as? [String: Any])?["name"] as? String)
                ?? ((ld["recordLabel"] as? [String: Any])?["name"] as? String)
            details.credits = details.credits ?? (ld["creditText"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            details.releaseDate = details.releaseDate ?? (ld["datePublished"] as? String).flatMap(parseBandcampDate)
            details.copyright = details.copyright ?? ld["copyrightNotice"] as? String
            if details.genre == nil, let keywords = ld["keywords"] as? [String], !keywords.isEmpty {
                details.genre = keywords.prefix(3).joined(separator: ", ")
            }
        }
        return details.tracks.isEmpty && details.credits == nil ? nil : details
    }

    private static func bandcampTralbum(_ html: String, pageURL: URL) -> AlbumDetails? {
        guard let range = html.range(of: #"data-tralbum="[^"]*""#, options: .regularExpression) else { return nil }
        var raw = String(html[range])
        raw.removeFirst("data-tralbum=\"".count)
        raw.removeLast()
        guard let data = MetadataFetcher.decodeEntities(raw).data(using: .utf8),
              let tralbum = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        var details = AlbumDetails()
        let current = tralbum["current"] as? [String: Any] ?? [:]
        let albumArtist = tralbum["artist"] as? String
        details.credits = (current["credits"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        details.releaseDate = ((current["release_date"] as? String) ?? (tralbum["album_release_date"] as? String))
            .flatMap(parseBandcampDate)
        let tracks = tralbum["trackinfo"] as? [[String: Any]] ?? []
        details.tracks = tracks.enumerated().compactMap { index, track in
            guard let title = track["title"] as? String else { return nil }
            let link = (track["title_link"] as? String).flatMap { URL(string: $0, relativeTo: pageURL)?.absoluteURL }
            let seconds = (track["duration"] as? Double) ?? Double(track["duration"] as? Int ?? 0)
            let artist = (track["artist"] as? String).flatMap { $0 == albumArtist ? nil : $0 }
            return AlbumDetails.Track(
                id: link?.absoluteString ?? String(track["track_id"] as? Int ?? index),
                number: track["track_num"] as? Int ?? index + 1,
                disc: nil,
                title: title,
                artist: artist,
                durationMs: seconds > 0 ? Int(seconds * 1000) : nil,
                url: link
            )
        }
        return details
    }

    private static func bandcampJSONLD(_ html: String) -> [String: Any]? {
        guard let range = html.range(of: #"(?s)<script type="application/ld\+json"[^>]*>\s*(\{.*?\})\s*</script>"#, options: .regularExpression),
              let start = html[range].firstIndex(of: "{"),
              let end = html[range].lastIndex(of: "}"),
              let data = String(html[range][start...end]).data(using: .utf8)
        else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func bandcampLDTracks(_ ld: [String: Any], pageURL: URL) -> [AlbumDetails.Track] {
        let elements = ((ld["track"] as? [String: Any])?["itemListElement"] as? [[String: Any]]) ?? []
        if elements.isEmpty, let name = ld["name"] as? String {
            return [AlbumDetails.Track(id: pageURL.absoluteString, number: nil, disc: nil, title: name, artist: nil,
                                       durationMs: (ld["duration"] as? String).flatMap(parseISODuration), url: pageURL)]
        }
        return elements.compactMap { element in
            guard let track = element["item"] as? [String: Any], let name = track["name"] as? String else { return nil }
            let link = (track["@id"] as? String).flatMap(URL.init(string:))
            return AlbumDetails.Track(id: link?.absoluteString ?? name, number: element["position"] as? Int, disc: nil,
                                      title: name, artist: nil,
                                      durationMs: (track["duration"] as? String).flatMap(parseISODuration), url: link)
        }
    }

    // MARK: Deezer

    private static func deezer(_ url: URL) async throws -> AlbumDetails? {
        let parts = url.pathComponents.filter { $0 != "/" }
        guard let typeIndex = parts.firstIndex(where: { $0 == "album" || $0 == "track" }), typeIndex + 1 < parts.count else { return nil }
        var albumID = parts[typeIndex + 1]
        if parts[typeIndex] == "track" {
            let track = try await json("https://api.deezer.com/track/\(albumID)")
            guard let id = (track["album"] as? [String: Any])?["id"] as? Int else { return nil }
            albumID = String(id)
        }
        let album = try await json("https://api.deezer.com/album/\(albumID)")
        var details = AlbumDetails()
        details.label = album["label"] as? String
        details.releaseDate = (album["release_date"] as? String).flatMap(parseDay)
        details.genre = ((album["genres"] as? [String: Any])?["data"] as? [[String: Any]])?
            .compactMap { $0["name"] as? String }.prefix(3).joined(separator: ", ")
        let contributors = (album["contributors"] as? [[String: Any]] ?? []).compactMap { c -> String? in
            guard let name = c["name"] as? String else { return nil }
            return (c["role"] as? String).map { "\(name) (\($0.lowercased()))" } ?? name
        }
        if !contributors.isEmpty { details.credits = contributors.joined(separator: ", ") }
        let tracks = ((album["tracks"] as? [String: Any])?["data"] as? [[String: Any]]) ?? []
        details.tracks = tracks.enumerated().compactMap { index, track in
            guard let title = track["title"] as? String else { return nil }
            return AlbumDetails.Track(id: String(track["id"] as? Int ?? index), number: index + 1, disc: nil, title: title,
                                      artist: (track["artist"] as? [String: Any])?["name"] as? String,
                                      durationMs: (track["duration"] as? Int).map { $0 * 1000 },
                                      url: (track["link"] as? String).flatMap(URL.init(string:)))
        }
        return details
    }

    // MARK: Spotify

    private static func spotify(_ url: URL) async throws -> AlbumDetails? {
        let parts = url.pathComponents.filter { $0 != "/" && !$0.hasPrefix("intl-") }
        guard parts.count >= 2, ["album", "track"].contains(parts[0]) else { return nil }
        if SpotifyService.shared.isConnected, let details = try? await SpotifyService.shared.albumDetails(kind: parts[0], id: parts[1]) {
            return details
        }
        return try await spotifyEmbed(kind: parts[0], id: parts[1])
    }

    /// The public embed page carries the tracklist in its Next.js data blob.
    private static func spotifyEmbed(kind: String, id: String) async throws -> AlbumDetails? {
        let html = try await page(URL(string: "https://open.spotify.com/embed/\(kind)/\(id)")!)
        guard let range = html.range(of: #"(?s)<script id="__NEXT_DATA__" type="application/json">(.*?)</script>"#, options: .regularExpression),
              let start = html[range].range(of: ">")?.upperBound,
              let end = html[range].range(of: "</script>", options: .backwards)?.lowerBound,
              let data = String(html[range][start..<end]).data(using: .utf8),
              let blob = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        var details = AlbumDetails()
        if let list = find("trackList", in: blob) as? [[String: Any]] {
            details.tracks = list.enumerated().compactMap { index, track in
                guard let title = track["title"] as? String else { return nil }
                let uri = track["uri"] as? String
                let trackURL = uri.flatMap { $0.split(separator: ":").last }.flatMap { URL(string: "https://open.spotify.com/track/\($0)") }
                return AlbumDetails.Track(id: uri ?? "\(index)", number: index + 1, disc: nil, title: title,
                                          artist: track["subtitle"] as? String,
                                          durationMs: track["duration"] as? Int, url: trackURL)
            }
        }
        if let release = find("releaseDate", in: blob) {
            let text = (release as? [String: Any])?["isoString"] as? String ?? release as? String
            details.releaseDate = text.flatMap(parseISO) ?? text.flatMap(parseDay)
        }
        return details
    }

    // MARK: Cache

    private static var cacheDirectory: URL { AppGroup.containerURL.appendingPathComponent("Details", isDirectory: true) }

    private static func cache(for id: UUID) -> AlbumDetails? {
        guard let data = try? Data(contentsOf: cacheDirectory.appendingPathComponent("\(id.uuidString).json")) else { return nil }
        return try? JSONDecoder().decode(AlbumDetails.self, from: data)
    }

    private static func store(_ details: AlbumDetails, for id: UUID) {
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(details) {
            try? data.write(to: cacheDirectory.appendingPathComponent("\(id.uuidString).json"), options: .atomic)
        }
    }

    static func forget(_ id: UUID) {
        try? FileManager.default.removeItem(at: cacheDirectory.appendingPathComponent("\(id.uuidString).json"))
    }

    // MARK: Helpers

    private static func json(_ string: String) async throws -> [String: Any] {
        guard let url = URL(string: string) else { throw ServiceError.badResponse }
        let (data, _) = try await MetadataFetcher.session.data(from: url)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ServiceError.badResponse }
        return object
    }

    private static func page(_ url: URL) async throws -> String {
        let (data, _) = try await MetadataFetcher.session.data(from: url)
        return String(decoding: data, as: UTF8.self)
    }

    /// Depth-first search for the first value stored under `key`.
    private static func find(_ key: String, in object: Any) -> Any? {
        if let dict = object as? [String: Any] {
            if let value = dict[key] { return value }
            for value in dict.values { if let found = find(key, in: value) { return found } }
        } else if let array = object as? [Any] {
            for value in array { if let found = find(key, in: value) { return found } }
        }
        return nil
    }

    private static func parseISO(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text) ?? parseDay(String(text.prefix(10)))
    }

    private static func parseDay(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: text)
    }

    /// Bandcamp writes dates like "03 Mar 2020 00:00:00 GMT".
    private static func parseBandcampDate(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: text)
    }

    /// "P00H03M45S" → milliseconds.
    private static func parseISODuration(_ text: String) -> Int? {
        var total = 0.0, number = ""
        for char in text.uppercased() {
            if char.isNumber || char == "." { number.append(char); continue }
            let value = Double(number) ?? 0
            switch char {
            case "H": total += value * 3600
            case "M": total += value * 60
            case "S": total += value
            default: break
            }
            number = ""
        }
        return total > 0 ? Int(total * 1000) : nil
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
