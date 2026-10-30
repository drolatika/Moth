import SwiftUI

/// Opens beneath an album when you tap it, as if the page were cut open: a
/// recessed panel with the tracklist (hold a track for its menu; heard tracks are
/// struck through) and credits in soft type at the bottom.
struct AlbumTracksPanel: View {
    let item: SavedItem
    /// Where the album sits above, 0…1 across the panel, for the notch.
    let notchX: CGFloat
    let onListen: (URL, _ album: SavedItem?) -> Void
    let onSelect: () -> Void
    let onRemove: () -> Void

    @Environment(ItemStore.self) private var store
    @Environment(\.theme) private var theme

    @State private var details: AlbumDetails?
    @State private var loading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            actionBar
            trackSection
            creditsSection
        }
        .padding(.horizontal, 14)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .background { CutOpenBackground(notchX: notchX) }
        .task(id: item.id) {
            loading = true
            details = await AlbumDetailsService.details(for: item)
            loading = false
        }
    }

    // MARK: Album actions

    private var actionBar: some View {
        HStack(spacing: 14) {
            Button { onListen(item.url, item) } label: {
                Label("Listen in \(item.platform.name)", systemImage: "arrow.up.forward")
            }
            .foregroundStyle(theme.accent)
            Spacer()
            Button { store.setListened(item, !item.isListened) } label: {
                Text(item.isListened ? "Move to Queue" : "Mark Heard")
            }
            .foregroundStyle(theme.secondaryText)
            Menu {
                Button(action: onSelect) { Label("Select", systemImage: "checkmark.circle") }
                Button(role: .destructive, action: onRemove) { Label("Remove", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(theme.secondaryText)
                    .frame(width: 28, height: 22)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Album options")
        }
        .font(.footnote.weight(.semibold))
        .buttonStyle(.plain)
        .padding(.bottom, 10)
    }

    // MARK: Tracks

    @ViewBuilder
    private var trackSection: some View {
        if loading {
            HStack { Spacer(); ProgressView().tint(theme.secondaryText); Spacer() }
                .padding(.vertical, 22)
        } else if let tracks = details?.tracks, !tracks.isEmpty {
            let heard = Set(item.heardTrackIDs ?? [])
            let multiDisc = Set(tracks.compactMap(\.disc)).count > 1
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                    if multiDisc, let disc = track.disc, index == 0 || tracks[index - 1].disc != disc {
                        Text("Disc \(disc)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(theme.secondaryText)
                            .padding(.top, 10)
                            .padding(.bottom, 2)
                    }
                    rule
                    trackRow(track, index: index, heard: heard.contains(track.id))
                }
                rule
            }
        } else {
            Text(AlbumDetailsService.supports(item.platform)
                 ? "Couldn't load the tracklist right now."
                 : "Tracklists aren't available for \(item.platform.name) links yet.")
                .font(.footnote)
                .foregroundStyle(theme.secondaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        }
    }

    private var rule: some View {
        Rectangle()
            .fill(theme.text.opacity(theme.isDark ? 0.09 : 0.12))
            .frame(height: 0.5)
    }

    private func trackRow(_ track: AlbumDetails.Track, index: Int, heard: Bool) -> some View {
        HStack(spacing: 10) {
            Text("\(track.number ?? index + 1)")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(theme.secondaryText.opacity(0.7))
                .frame(width: 22, alignment: .trailing)
            VStack(alignment: .leading, spacing: 1) {
                Text(track.title)
                    .font(.subheadline)
                    .foregroundStyle(heard ? theme.secondaryText : theme.text)
                    .strikethrough(heard, pattern: .solid, color: theme.accent.opacity(0.75))
                    .lineLimit(2)
                if let artist = track.artist, !artist.isEmpty, artist != item.artist {
                    Text(artist).font(.caption).foregroundStyle(theme.secondaryText.opacity(0.85)).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let ms = track.durationMs {
                Text(Self.trackLength(ms))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(theme.secondaryText.opacity(0.7))
            }
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .contextMenu {
            if let url = track.url {
                Button { onListen(url, nil) } label: {
                    Label("Listen in \(item.platform.name)", systemImage: "play")
                }
            }
            Button { store.toggleTrackHeard(track.id, in: item) } label: {
                heard
                    ? Label("Mark Not Heard", systemImage: "circle")
                    : Label("Mark Heard", systemImage: "checkmark.circle")
            }
        }
    }

    // MARK: Credits

    @ViewBuilder
    private var creditsSection: some View {
        if let details {
            let lines = creditLines(details)
            if !lines.isEmpty || details.credits != nil {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(lines, id: \.self) { Text($0) }
                    if let credits = details.credits, !credits.isEmpty {
                        Text(credits).padding(.top, lines.isEmpty ? 0 : 6)
                    }
                }
                .font(.caption2)
                .foregroundStyle(theme.secondaryText.opacity(0.8))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 12)
            }
        }
    }

    private func creditLines(_ details: AlbumDetails) -> [String] {
        var lines: [String] = []
        if !details.tracks.isEmpty {
            let count = details.tracks.count == 1 ? "1 track" : "\(details.tracks.count) tracks"
            let total = details.totalDurationMs
            lines.append(total > 0 ? "\(count) · \(Self.totalLength(total))" : count)
        }
        if let date = details.releaseDate { lines.append("Released \(date.formatted(date: .long, time: .omitted))") }
        if let label = details.label, !label.isEmpty { lines.append("Label: \(label)") }
        if let genre = details.genre, !genre.isEmpty { lines.append(genre) }
        if let copyright = details.copyright, !copyright.isEmpty { lines.append(copyright) }
        return lines
    }

    static func trackLength(_ ms: Int) -> String {
        let seconds = ms / 1000
        return seconds >= 3600
            ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
            : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    static func totalLength(_ ms: Int) -> String {
        let minutes = ms / 60_000
        return minutes >= 60 ? "\(minutes / 60) hr \(minutes % 60) min" : "\(minutes) min"
    }
}

/// A recess in the page: darker than the surface, shadowed along its top edge,
/// catching light along its bottom edge, with a notch pointing at the album.
private struct CutOpenBackground: View {
    let notchX: CGFloat
    @Environment(\.theme) private var theme

    var body: some View {
        GeometryReader { geo in
            let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
            let recess = theme.isDark ? Color.black.opacity(0.34) : Color(hex: 0x5A4024).opacity(0.09)
            ZStack(alignment: .topLeading) {
                theme.background.opacity(theme.backdrop == nil ? 0 : 0.85)
                    .clipShape(shape)
                shape.fill(recess)
                VStack(spacing: 0) {
                    LinearGradient(colors: [.black.opacity(theme.isDark ? 0.5 : 0.18), .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 14)
                    Spacer()
                    LinearGradient(colors: [.clear, .black.opacity(theme.isDark ? 0.25 : 0.08)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 8)
                }
                .clipShape(shape)
                shape.strokeBorder(
                    LinearGradient(colors: [.black.opacity(theme.isDark ? 0.6 : 0.2), .white.opacity(theme.isDark ? 0.07 : 0.5)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 1
                )
                Notch()
                    .fill(theme.isDark ? Color.black.opacity(0.55) : Color(hex: 0x5A4024).opacity(0.16))
                    .frame(width: 16, height: 8)
                    .offset(x: geo.size.width * notchX - 8, y: -8)
            }
        }
    }
}

private struct Notch: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Reveals a view from the top down, like a cut opening.
struct RevealFromTop: ViewModifier {
    let progress: CGFloat

    func body(content: Content) -> some View {
        content.mask(alignment: .top) {
            GeometryReader { geo in
                Rectangle().frame(height: geo.size.height * progress)
            }
        }
    }
}
