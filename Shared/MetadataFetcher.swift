import Foundation

struct LinkMetadata {
    var url: URL
    var title: String
    var artist: String?
    var kind: SavedItem.Kind
    var platform: Platform
    var artworkURL: URL?
    var hasRealTitle = false

    var isComplete: Bool { hasRealTitle && artworkURL != nil }

    mutating func setTitle(_ value: String?) {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return }
        title = value
        hasRealTitle = true
    }

    mutating func setArtist(_ value: String?) {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return }
        artist = value
    }
}

/// Turns a share link into a title, artist and album art. Uses each service's
/// public oEmbed/lookup API where one exists, and falls back to the page's
/// Open Graph tags (which is what Bandcamp, Tidal and everything else get).
enum MetadataFetcher {
    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 12
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            "Accept-Language": "en-US,en;q=0.9",
        ]
        return URLSession(configuration: config)
    }()

    private static let shortLinkHosts = [
        "spotify.link", "deezer.page.link", "link.deezer.com", "on.soundcloud.com", "tidal.link", "snd.sc",
    ]

    static func fetch(_ input: URL) async -> LinkMetadata {
        var url = input
        if let host = url.host?.lowercased(), shortLinkHosts.contains(where: { host.hasSuffix($0) }) {
            url = LinkCleaner.clean(await resolve(url))
        }

        let platform = Platform.detect(url)
        var meta = LinkMetadata(
            url: url,
            title: fallbackTitle(for: url),
            kind: kind(for: url, platform: platform),
            platform: platform
        )

        switch platform {
        case .spotify: meta = await spotify(meta)
        case .appleMusic: meta = await appleMusic(meta)
        case .soundcloud: meta = await soundcloud(meta)
        case .youtube, .youtubeMusic: meta = await youtube(meta)
        case .deezer: meta = await deezer(meta)
        default: break
        }

        if !meta.isComplete {
            meta = await openGraph(meta)
        }
        return meta
    }

    // MARK: - Services

    private static func spotify(_ input: LinkMetadata) async -> LinkMetadata {
        var meta = input
        if let json = try? await json(from: "https://open.spotify.com/oembed?url=" + encoded(meta.url)) {
            meta.setTitle(json["title"] as? String)
            meta.artworkURL = (json["thumbnail_url"] as? String).flatMap(URL.init(string:))
        }
        // oEmbed has no artist, so pull it from the page's meta tags.
        if let tags = await metaTags(for: meta.url) {
            if meta.kind == .album || meta.kind == .track {
                meta.setArtist(tags["music:musician_description"])
            }
            if meta.artist == nil, let description = tags["og:description"] {
                meta.setArtist(spotifyArtist(fromDescription: description))
            }
            if !meta.hasRealTitle { meta.setTitle(tags["og:title"]) }
            if meta.artworkURL == nil { meta.artworkURL = tags["og:image"].flatMap(URL.init(string:)) }
        }
        return meta
    }

    /// Spotify descriptions look like "Artist · Album · 2023 · 12 songs" or "Playlist · Owner · 50 items".
    private static func spotifyArtist(fromDescription description: String) -> String? {
        let segments = description.components(separatedBy: " · ").map { $0.trimmingCharacters(in: .whitespaces) }
        guard segments.count >= 2 else { return nil }
        let labels: Set<String> = ["Playlist", "Album", "Single", "EP", "Song", "Podcast", "Compilation"]
        let first = segments[0].components(separatedBy: ". ").last ?? segments[0]
        return labels.contains(first) ? segments[1] : first
    }

    private static func appleMusic(_ input: LinkMetadata) async -> LinkMetadata {
        var meta = input
        let components = URLComponents(url: meta.url, resolvingAgainstBaseURL: false)
        let parts = meta.url.pathComponents.filter { $0 != "/" }
        let country = parts.first.flatMap { $0.count == 2 ? $0 : nil } ?? "us"

        var lookupID: String?
        if let trackID = components?.queryItems?.first(where: { $0.name == "i" })?.value {
            lookupID = trackID
            meta.kind = .track
        } else if let last = parts.last {
            let id = last.hasPrefix("id") ? String(last.dropFirst(2)) : last
            if id.allSatisfy(\.isNumber) { lookupID = id }
        }

        if let lookupID,
           let json = try? await json(from: "https://itunes.apple.com/lookup?id=\(lookupID)&country=\(country)"),
           let result = (json["results"] as? [[String: Any]])?.first {
            meta.setTitle((result["trackName"] as? String) ?? (result["collectionName"] as? String) ?? (result["artistName"] as? String))
            if meta.kind != .artist { meta.setArtist(result["artistName"] as? String) }
            if let art = result["artworkUrl100"] as? String {
                let large = art.replacingOccurrences(of: #"\d+x\d+bb"#, with: "1000x1000bb", options: .regularExpression)
                meta.artworkURL = URL(string: large)
            }
        }
        return meta
    }

    private static func soundcloud(_ input: LinkMetadata) async -> LinkMetadata {
        var meta = input
        guard let json = try? await json(from: "https://soundcloud.com/oembed?format=json&url=" + encoded(meta.url)) else { return meta }
        let author = json["author_name"] as? String
        var title = json["title"] as? String
        if let author, let current = title, current.hasSuffix(" by " + author) {
            title = String(current.dropLast(author.count + 4))
        }
        meta.setTitle(title)
        meta.setArtist(author)
        meta.artworkURL = (json["thumbnail_url"] as? String).flatMap(URL.init(string:))
        return meta
    }

    private static func youtube(_ input: LinkMetadata) async -> LinkMetadata {
        var meta = input
        var lookup = URLComponents(url: meta.url, resolvingAgainstBaseURL: false)
        if lookup?.host == "music.youtube.com" { lookup?.host = "www.youtube.com" }
        guard let lookupURL = lookup?.url,
              let json = try? await json(from: "https://www.youtube.com/oembed?format=json&url=" + encoded(lookupURL))
        else { return meta }
        meta.setTitle(json["title"] as? String)
        meta.setArtist((json["author_name"] as? String)?.replacingOccurrences(of: " - Topic", with: ""))
        meta.artworkURL = (json["thumbnail_url"] as? String).flatMap(URL.init(string:))
        return meta
    }

    private static func deezer(_ input: LinkMetadata) async -> LinkMetadata {
        var meta = input
        let parts = meta.url.pathComponents.filter { $0 != "/" }
        guard let typeIndex = parts.firstIndex(where: { ["album", "track", "playlist", "artist"].contains($0) }),
              typeIndex + 1 < parts.count,
              let json = try? await json(from: "https://api.deezer.com/\(parts[typeIndex])/\(parts[typeIndex + 1])")
        else { return meta }

        meta.setTitle((json["title"] as? String) ?? (json["name"] as? String))
        let artist = (json["artist"] as? [String: Any])?["name"] as? String
        let creator = (json["creator"] as? [String: Any])?["name"] as? String
        meta.setArtist(artist ?? creator)
        let album = json["album"] as? [String: Any]
        let cover = (json["cover_xl"] as? String) ?? (album?["cover_xl"] as? String) ?? (json["picture_xl"] as? String)
        meta.artworkURL = cover.flatMap(URL.init(string:))
        return meta
    }

    private static func openGraph(_ input: LinkMetadata) async -> LinkMetadata {
        var meta = input
        guard let tags = await metaTags(for: meta.url) else { return meta }

        if meta.platform == .other, tags["og:site_name"]?.lowercased().contains("bandcamp") == true {
            meta.platform = .bandcamp // Bandcamp artists on custom domains
            meta.kind = kind(for: meta.url, platform: .bandcamp)
        }

        if !meta.hasRealTitle {
            var title = tags["og:title"] ?? tags["twitter:title"] ?? tags["title"]
            title = title.map(stripSiteSuffix)
            if meta.artist == nil, let full = title {
                let separator = meta.platform == .bandcamp ? ", by " : " by "
                if [.bandcamp, .appleMusic, .tidal, .soundcloud, .amazonMusic].contains(meta.platform),
                   let range = full.range(of: separator, options: .backwards) {
                    title = String(full[..<range.lowerBound])
                    meta.setArtist(String(full[range.upperBound...]))
                }
            }
            meta.setTitle(title)
        }
        if meta.artist == nil {
            meta.setArtist(tags["music:musician_description"] ?? tags["twitter:audio:artist_name"])
        }
        if meta.artworkURL == nil {
            let image = tags["og:image:secure_url"] ?? tags["og:image"] ?? tags["twitter:image"]
            meta.artworkURL = image.flatMap { URL(string: $0, relativeTo: meta.url)?.absoluteURL }
        }
        return meta
    }

    // MARK: - Helpers

    private static func kind(for url: URL, platform: Platform) -> SavedItem.Kind {
        let parts = Set(url.pathComponents.map { $0.lowercased() })
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if platform == .soundcloud {
            if parts.contains("sets") { return .album }
            return url.pathComponents.filter { $0 != "/" }.count == 1 ? .artist : .track
        }
        if platform == .youtube || platform == .youtubeMusic {
            if parts.contains("playlist") || parts.contains("browse") { return .album }
            if query.contains(where: { $0.name == "v" }) || url.host == "youtu.be" { return .track }
        }
        if parts.contains("album") { return .album }
        if parts.contains("track") || parts.contains("song") { return .track }
        if parts.contains("playlist") { return .playlist }
        if parts.contains("artist") { return .artist }
        if parts.contains("episode") || parts.contains("show") { return .episode }
        return .other
    }

    private static func fallbackTitle(for url: URL) -> String {
        let slug = url.pathComponents.last(where: { $0 != "/" && !$0.allSatisfy(\.isNumber) }) ?? url.host ?? url.absoluteString
        return slug.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ").capitalized
    }

    private static func stripSiteSuffix(_ title: String) -> String {
        let suffixes = [
            " on Apple Music", " | Spotify", " - song and lyrics by", " - YouTube Music", " - YouTube",
            " | Listen online for free on SoundCloud", " | Deezer", " on TIDAL", " | TIDAL", " | Bandcamp",
        ]
        var result = title
        for suffix in suffixes {
            if let range = result.range(of: suffix) {
                result = String(result[..<range.lowerBound])
            }
        }
        return result
    }

    private static func encoded(_ url: URL) -> String {
        url.absoluteString.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? url.absoluteString
    }

    private static func json(from string: String) async throws -> [String: Any] {
        guard let url = URL(string: string) else { throw URLError(.badURL) }
        let (data, response) = try await session.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw URLError(.badServerResponse) }
        if object["error"] != nil { throw URLError(.resourceUnavailable) }
        return object
    }

    /// Follows a short link to the real page. Some short-link services redirect with
    /// JavaScript rather than HTTP, so the HTML is also searched for a known music URL.
    private static func resolve(_ url: URL) async -> URL {
        guard let (data, response) = try? await session.data(from: url) else { return url }
        if let final = response.url, Platform.detect(final) != .other,
           !shortLinkHosts.contains(where: { final.host?.hasSuffix($0) == true }) {
            return final
        }
        let html = String(decoding: data.prefix(400_000), as: UTF8.self)
        let pattern = #"https://(open\.spotify\.com|www\.deezer\.com|soundcloud\.com|tidal\.com|listen\.tidal\.com)/[^"'\s<>\\]+"#
        if let range = html.range(of: pattern, options: .regularExpression),
           let found = URL(string: decodeEntities(String(html[range]))) {
            return found
        }
        return response.url ?? url
    }

    private static func metaTags(for url: URL) async -> [String: String]? {
        guard let (data, _) = try? await session.data(from: url) else { return nil }
        let html = String(decoding: data.prefix(800_000), as: UTF8.self)
        return parseMetaTags(html)
    }

    private static let metaTagRegex = try! NSRegularExpression(pattern: "<meta\\s[^>]*>", options: .caseInsensitive)
    private static let attributeRegex = try! NSRegularExpression(pattern: "([a-zA-Z:_-]+)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)')")
    private static let titleRegex = try! NSRegularExpression(pattern: "<title[^>]*>([^<]*)</title>", options: .caseInsensitive)

    static func parseMetaTags(_ html: String) -> [String: String] {
        var result: [String: String] = [:]
        let ns = html as NSString
        for match in metaTagRegex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let tag = ns.substring(with: match.range)
            let tagNS = tag as NSString
            var attributes: [String: String] = [:]
            for attribute in attributeRegex.matches(in: tag, range: NSRange(location: 0, length: tagNS.length)) {
                let name = tagNS.substring(with: attribute.range(at: 1)).lowercased()
                let valueRange = attribute.range(at: 2).location != NSNotFound ? attribute.range(at: 2) : attribute.range(at: 3)
                attributes[name] = tagNS.substring(with: valueRange)
            }
            if let key = (attributes["property"] ?? attributes["name"])?.lowercased(),
               let content = attributes["content"], result[key] == nil {
                result[key] = decodeEntities(content)
            }
        }
        if result["title"] == nil,
           let match = titleRegex.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)) {
            result["title"] = decodeEntities(ns.substring(with: match.range(at: 1)))
        }
        return result
    }

    private static let numericEntityRegex = try! NSRegularExpression(pattern: "&#([xX]?)([0-9a-fA-F]+);")

    static func decodeEntities(_ string: String) -> String {
        guard string.contains("&") else { return string }
        let ns = string as NSString
        var result = ""
        var cursor = 0
        for match in numericEntityRegex.matches(in: string, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let isHex = match.range(at: 1).length > 0
            let digits = ns.substring(with: match.range(at: 2))
            if let code = UInt32(digits, radix: isHex ? 16 : 10), let scalar = Unicode.Scalar(code) {
                result.append(Character(scalar))
            } else {
                result += ns.substring(with: match.range)
            }
            cursor = match.range.location + match.range.length
        }
        result += ns.substring(from: cursor)

        let named = [("&quot;", "\""), ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " "), ("&amp;", "&")]
        for (entity, character) in named {
            result = result.replacingOccurrences(of: entity, with: character)
        }
        return result
    }
}
