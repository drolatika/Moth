import Foundation

/// Bandcamp's app doesn't pick up bandcamp.com links (artist pages live on their own
/// subdomains), so Moth opens albums and tracks with the app's own scheme instead:
/// bandcamp://show_tralbum?tralbum_type=a&tralbum_id=…&play (the form Bandcamp's own
/// "open in app" links use), with the older x-bandcamp:// form as a second try. The
/// ID comes from the page itself and is remembered after the first lookup.
enum BandcampLink {
    private static let cacheKey = "bandcampTralbumIDs.v2"

    /// Links to try in order; the caller falls back to the web page if none opens.
    static func appURLs(for url: URL) async -> [URL] {
        guard let (type, id) = await tralbum(for: url) else { return [] }
        let query = "show_tralbum?tralbum_type=\(type)&tralbum_id=\(id)"
        return ["bandcamp://\(query)&play", "x-bandcamp://\(query)"].compactMap(URL.init(string:))
    }

    /// ("a" or "t", numeric ID) for an album or track page.
    private static func tralbum(for url: URL) async -> (String, String)? {
        let key = LinkCleaner.key(for: url)
        var cache = AppGroup.defaults.dictionary(forKey: cacheKey) as? [String: String] ?? [:]
        if let cached = cache[key], let split = cached.firstIndex(of: ":") {
            return (String(cached[..<split]), String(cached[cached.index(after: split)...]))
        }
        guard url.path.contains("/album/") || url.path.contains("/track/"),
              let (data, _) = try? await MetadataFetcher.session.data(from: url)
        else { return nil }
        let html = String(decoding: data, as: UTF8.self)
        guard let found = pageProperties(html) ?? tralbumAttribute(html) else { return nil }
        cache[key] = "\(found.0):\(found.1)"
        AppGroup.defaults.set(cache, forKey: cacheKey)
        return found
    }

    /// `<meta name="bc-page-properties" content='{"item_type":"a","item_id":123,…}'>`
    private static func pageProperties(_ html: String) -> (String, String)? {
        guard let content = MetadataFetcher.parseMetaTags(html)["bc-page-properties"],
              let json = try? JSONSerialization.jsonObject(with: Data(content.utf8)) as? [String: Any],
              let type = json["item_type"] as? String, ["a", "t"].contains(type),
              let id = json["item_id"] as? Int
        else { return nil }
        return (type, String(id))
    }

    /// The player's `data-tralbum` blob: `"id":123` and `"item_type":"album"`.
    private static func tralbumAttribute(_ html: String) -> (String, String)? {
        guard let range = html.range(of: #"data-tralbum="[^"]*""#, options: .regularExpression) else { return nil }
        let blob = MetadataFetcher.decodeEntities(String(html[range].dropFirst("data-tralbum=\"".count).dropLast()))
        guard let json = try? JSONSerialization.jsonObject(with: Data(blob.utf8)) as? [String: Any],
              let id = json["id"] as? Int
        else { return nil }
        return ((json["item_type"] as? String) == "track" ? "t" : "a", String(id))
    }
}
