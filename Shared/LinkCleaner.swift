import Foundation

enum LinkCleaner {
    private static let trackingParams: Set<String> = [
        "si", "fbclid", "igshid", "ls", "app", "nd", "context", "feature", "ref",
        "dl_branch", "_branch_match_id", "_branch_referrer", "deferredfl", "from", "pp",
    ]

    /// Strips share-tracking junk so the same album saved twice is recognised as a duplicate.
    static func clean(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        if components.scheme?.lowercased() == "http" { components.scheme = "https" }
        let kept = (components.queryItems ?? []).filter { item in
            let name = item.name.lowercased()
            return !name.hasPrefix("utm_") && !trackingParams.contains(name)
        }
        components.queryItems = kept.isEmpty ? nil : kept
        components.fragment = nil
        return components.url ?? url
    }

    static func key(for url: URL) -> String {
        let cleaned = clean(url)
        var host = (cleaned.host ?? "").lowercased()
        if host.hasPrefix("www.") { host.removeFirst(4) }
        var path = cleaned.path
        while path.hasSuffix("/") { path.removeLast() }
        let query = (URLComponents(url: cleaned, resolvingAgainstBaseURL: false)?.queryItems ?? [])
            .map { "\($0.name)=\($0.value ?? "")" }
            .sorted()
            .joined(separator: "&")
        return host + path + (query.isEmpty ? "" : "?" + query)
    }

    static func firstURL(in text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, range: range)
            .compactMap(\.url)
            .first { $0.scheme?.hasPrefix("http") == true }
    }
}
