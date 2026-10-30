import Charts
import SwiftUI

/// This week's listening, from Moth's own history plus any connected services.
struct WeeklyStats {
    struct Day: Identifiable {
        let id: Int
        let label: String
        let count: Int
    }

    let weekStart: Date
    let heardCount: Int
    let days: [Day]
    let topArtists: [RankedArtist]
    let sources: [(platform: Platform, count: Int)]

    static var calendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = 2   // weeks start on Monday
        return calendar
    }

    static func compute(from items: [SavedItem], now: Date = .now) -> WeeklyStats {
        let calendar = Self.calendar
        let start = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
        let heard = items.filter { ($0.listenedAt ?? .distantPast) >= start }

        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        let days = (0..<7).map { offset -> Day in
            let dayStart = calendar.date(byAdding: .day, value: offset, to: start) ?? start
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
            let count = heard.filter { ($0.listenedAt ?? .distantPast) >= dayStart && ($0.listenedAt ?? .distantPast) < dayEnd }.count
            return Day(id: offset, label: formatter.string(from: dayStart), count: count)
        }

        var artistCounts: [String: Int] = [:]
        for item in heard { if let artist = item.artist { artistCounts[artist, default: 0] += 1 } }
        let topArtists = artistCounts.sorted { $0.value > $1.value || ($0.value == $1.value && $0.key < $1.key) }
            .prefix(5)
            .map { RankedArtist(name: $0.key, detail: $0.value == 1 ? "1 album" : "\($0.value) albums") }

        var platformCounts: [Platform: Int] = [:]
        for item in heard { platformCounts[item.platform, default: 0] += 1 }
        let sources = platformCounts.sorted { $0.value > $1.value }.map { (platform: $0.key, count: $0.value) }

        return WeeklyStats(weekStart: start, heardCount: heard.count, days: days, topArtists: Array(topArtists), sources: sources)
    }
}

struct StatsView: View {
    @Environment(ItemStore.self) private var store
    @Environment(Connections.self) private var connections
    @Environment(\.theme) private var theme

    @State private var spotifyMinutes: Int?
    @State private var spotifyArtists: [RankedArtist] = []
    @State private var lastFMScrobbles: Int?
    @State private var lastFMArtists: [RankedArtist] = []
    @State private var appleRecent: [RecentlyPlayed] = []
    @State private var serviceError: String?

    private var stats: WeeklyStats { WeeklyStats.compute(from: store.items) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Stats")
                    .font(MothFont.gothic(38))
                    .foregroundStyle(theme.text)
                    .shadow(color: Manuscript.ember.opacity(0.3), radius: 10)

                weekCard

                if connections.spotifyConnected { spotifySection }
                if connections.lastFMUser != nil { lastFMSection }
                if connections.appleMusicAuthorized && !appleRecent.isEmpty { appleSection }

                if !stats.topArtists.isEmpty {
                    section("MOST HEARD IN MOTH") { artistList(stats.topArtists) }
                }
                if !stats.sources.isEmpty {
                    section("WHERE YOU LISTENED") { sourcesBar }
                }
                if !connections.anyConnected {
                    Text("Connect Spotify, Apple Music or Last.fm in Settings to add listening time and top artists from those services.")
                        .font(.footnote)
                        .foregroundStyle(theme.secondaryText)
                }
                if let serviceError {
                    Text(serviceError).font(.footnote).foregroundStyle(.red.opacity(0.85))
                }
            }
            .padding(20)
        }
        .background(theme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadServices() }
        .refreshable { await loadServices() }
    }

    // MARK: Sections

    private var weekCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("THIS WEEK")
                .font(.caption.weight(.semibold)).tracking(0.8)
                .foregroundStyle(theme.secondaryText)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(stats.heardCount)")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(theme.text)
                Text(stats.heardCount == 1 ? "album heard" : "albums heard")
                    .font(.headline)
                    .foregroundStyle(theme.secondaryText)
            }
            if let spotifyMinutes, spotifyMinutes > 0 {
                Text("\(Self.duration(spotifyMinutes)) on Spotify (last 50 plays)")
                    .font(.subheadline)
                    .foregroundStyle(theme.accent)
            }
            Chart(stats.days) { day in
                BarMark(x: .value("Day", day.label), y: .value("Albums", day.count))
                    .foregroundStyle(theme.accent.gradient)
                    .cornerRadius(4)
            }
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel().foregroundStyle(theme.secondaryText)
                }
            }
            .frame(height: 130)
            .padding(.top, 8)
        }
        .padding(16)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var spotifySection: some View {
        section("SPOTIFY") {
            VStack(alignment: .leading, spacing: 0) {
                if let spotifyMinutes {
                    statRow("Listening this week", value: Self.duration(spotifyMinutes), note: "From your last 50 plays")
                }
                if !spotifyArtists.isEmpty { artistList(spotifyArtists, title: "Top artists, last 4 weeks") }
            }
        }
    }

    private var lastFMSection: some View {
        section("LAST.FM · \(connections.lastFMUser ?? "")") {
            VStack(alignment: .leading, spacing: 0) {
                if let lastFMScrobbles {
                    statRow("Scrobbles this week", value: "\(lastFMScrobbles)",
                            note: "About \(Self.duration(lastFMScrobbles * 7 / 2)) at 3½ min a track")
                }
                if !lastFMArtists.isEmpty { artistList(lastFMArtists, title: "Top artists, last 7 days") }
            }
        }
    }

    private var appleSection: some View {
        section("APPLE MUSIC · RECENTLY PLAYED") {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(appleRecent) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            AsyncImage(url: entry.artworkURL) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                theme.surface
                            }
                            .frame(width: 96, height: 96)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            Text(entry.title).font(.caption.weight(.semibold)).foregroundStyle(theme.text).lineLimit(1)
                            Text(entry.subtitle).font(.caption2).foregroundStyle(theme.secondaryText).lineLimit(1)
                        }
                        .frame(width: 96)
                    }
                }
                .padding(14)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var sourcesBar: some View {
        let total = max(1, stats.sources.reduce(0) { $0 + $1.count })
        return VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(stats.sources, id: \.platform) { source in
                        source.platform.color
                            .frame(width: max(4, geo.size.width * CGFloat(source.count) / CGFloat(total) - 2))
                    }
                }
            }
            .frame(height: 10)
            .clipShape(Capsule())
            FlowingLegend(sources: stats.sources, total: total)
        }
        .padding(16)
    }

    // MARK: Building blocks

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold)).tracking(0.8)
                .foregroundStyle(theme.secondaryText)
                .padding(.leading, 4)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func statRow(_ label: String, value: String, note: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).foregroundStyle(theme.text)
                Spacer()
                Text(value).font(.headline).foregroundStyle(theme.accent)
            }
            Text(note).font(.caption).foregroundStyle(theme.secondaryText)
        }
        .padding(14)
    }

    private func artistList(_ artists: [RankedArtist], title: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                Text(title).font(.caption).foregroundStyle(theme.secondaryText)
                    .padding(.horizontal, 14).padding(.top, 10)
            }
            ForEach(Array(artists.enumerated()), id: \.element.id) { index, artist in
                HStack(spacing: 12) {
                    Text("\(index + 1)").font(.subheadline.monospacedDigit()).foregroundStyle(theme.secondaryText).frame(width: 16)
                    if let url = artist.imageURL {
                        AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { theme.background }
                            .frame(width: 36, height: 36)
                            .clipShape(Circle())
                    }
                    Text(artist.name).foregroundStyle(theme.text).lineLimit(1)
                    Spacer()
                    Text(artist.detail).font(.subheadline).foregroundStyle(theme.secondaryText).lineLimit(1)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
            }
        }
    }

    static func duration(_ minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }

    // MARK: Loading

    private func loadServices() async {
        serviceError = nil
        let weekStart = stats.weekStart
        if connections.spotifyConnected {
            do {
                let plays = try await SpotifyService.shared.recentPlays()
                spotifyMinutes = plays.filter { $0.playedAt >= weekStart }.reduce(0) { $0 + $1.durationMs } / 60_000
                spotifyArtists = try await SpotifyService.shared.topArtists()
            } catch {
                serviceError = "Spotify: \(error.localizedDescription)"
                if !SpotifyService.shared.isConnected { connections.spotifyConnected = false }
            }
        }
        if let user = connections.lastFMUser {
            do {
                lastFMScrobbles = try await LastFMService.scrobbleCount(for: user, since: weekStart)
                lastFMArtists = try await LastFMService.topArtists(for: user)
            } catch {
                serviceError = "Last.fm: \(error.localizedDescription)"
            }
        }
        if connections.appleMusicAuthorized {
            do {
                appleRecent = try await AppleMusicService.recentlyPlayed()
            } catch {
                serviceError = "Apple Music: \(error.localizedDescription)"
            }
        }
    }
}

private struct FlowingLegend: View {
    let sources: [(platform: Platform, count: Int)]
    let total: Int
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(sources, id: \.platform) { source in
                HStack(spacing: 6) {
                    Circle().fill(source.platform.color).frame(width: 8, height: 8)
                    Text(source.platform.name).foregroundStyle(theme.text)
                    Spacer()
                    Text("\(Int((Double(source.count) / Double(total) * 100).rounded()))%")
                        .monospacedDigit()
                        .foregroundStyle(theme.secondaryText)
                }
                .font(.footnote)
            }
        }
    }
}
