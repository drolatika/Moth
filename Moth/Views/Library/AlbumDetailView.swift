import SwiftUI

/// The page an album opens to: artwork (tap to listen), the tracklist with soft
/// lengths, and credits in small type at the bottom. Tapping a track opens its menu;
/// heard tracks are struck through, and marking one adds the album to Heard too.
struct AlbumDetailView: View {
    let itemID: UUID
    let onSelect: (SavedItem) -> Void

    @Environment(ItemStore.self) private var store
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.autoMarkListened, store: AppGroup.defaults) private var autoMarkHeard = false
    @AppStorage(SettingsKey.openLinksIn, store: AppGroup.defaults) private var openLinksIn = LinkDestination.app.rawValue

    @State private var details: AlbumDetails?
    @State private var loading = true
    @State private var browserLink: BrowserLink?

    private var item: SavedItem? { store.items.first { $0.id == itemID } }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let item {
                    VStack(alignment: .leading, spacing: 22) {
                        header(item)
                        trackSection(item)
                        creditsSection(item)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
            .scrollIndicators(.hidden)
            .background { ThemeBackdrop() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    if let item { albumMenu(item) }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .task {
            guard let item else { return }
            details = await AlbumDetailsService.details(for: item)
            loading = false
        }
        .sheet(item: $browserLink) { link in SafariView(url: link.url).ignoresSafeArea() }
    }

    // MARK: Header

    private func header(_ item: SavedItem) -> some View {
        VStack(spacing: 12) {
            Button { listen(item.url, platform: item.platform, album: item) } label: {
                ArtworkView(item: item, cornerRadius: 14)
                    .frame(width: 188, height: 188)
                    .shadow(color: .black.opacity(theme.isDark ? 0.5 : 0.2), radius: 22, y: 12)
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Listen to \(item.title) in \(item.platform.name)")

            VStack(spacing: 4) {
                Text(item.title)
                    .font(MothFont.gothic(28))
                    .foregroundStyle(theme.text)
                    .multilineTextAlignment(.center)
                if let artist = item.artist {
                    Text(artist).font(.subheadline).foregroundStyle(theme.secondaryText)
                }
                Button { listen(item.url, platform: item.platform, album: item) } label: {
                    Label("Listen in \(item.platform.name)", systemImage: "arrow.up.forward")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(theme.accent)
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    private func albumMenu(_ item: SavedItem) -> some View {
        Menu {
            Button {
                store.setListened(item, !item.isListened)
            } label: {
                item.isListened
                    ? Label("Move to Queue", systemImage: "tray.and.arrow.up")
                    : Label("Mark Heard", systemImage: "checkmark.circle")
            }
            Button {
                dismiss()
                onSelect(item)
            } label: {
                Label("Select", systemImage: "checkmark.circle.badge.plus")
            }
            Divider()
            Button(role: .destructive) {
                dismiss()
                store.delete(item)
            } label: {
                Label("Remove", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle").foregroundStyle(theme.accent)
        }
        .accessibilityLabel("Album options")
    }

    // MARK: Tracks

    @ViewBuilder
    private func trackSection(_ item: SavedItem) -> some View {
        if loading {
            HStack { Spacer(); ProgressView().tint(theme.secondaryText); Spacer() }
                .padding(.vertical, 30)
        } else if let tracks = details?.tracks, !tracks.isEmpty {
            let heard = Set(item.heardTrackIDs ?? [])
            let multiDisc = Set(tracks.compactMap(\.disc)).count > 1
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                    if multiDisc, let disc = track.disc, index == 0 || tracks[index - 1].disc != disc {
                        Text("Disc \(disc)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(theme.secondaryText)
                            .padding(.top, index == 0 ? 0 : 14)
                            .padding(.bottom, 4)
                    }
                    trackRow(track, index: index, in: item, heard: heard.contains(track.id))
                    if index < tracks.count - 1 {
                        Divider().overlay(theme.text.opacity(0.06)).padding(.leading, 34)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(theme.surface.opacity(theme.backdrop == nil ? 1 : 0.9), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else {
            Text(AlbumDetailsService.supports(item.platform)
                 ? "Couldn't load the tracklist right now."
                 : "Tracklists aren't available for \(item.platform.name) links yet.")
                .font(.footnote)
                .foregroundStyle(theme.secondaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
        }
    }

    private func trackRow(_ track: AlbumDetails.Track, index: Int, in item: SavedItem, heard: Bool) -> some View {
        Menu {
            if let url = track.url {
                Button { listen(url, platform: item.platform, album: nil) } label: {
                    Label("Listen in \(item.platform.name)", systemImage: "play")
                }
            }
            Button { store.toggleTrackHeard(track.id, in: item) } label: {
                heard
                    ? Label("Mark Not Heard", systemImage: "circle")
                    : Label("Mark Heard", systemImage: "checkmark.circle")
            }
        } label: {
            HStack(spacing: 10) {
                Text("\(track.number ?? index + 1)")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(theme.secondaryText.opacity(0.7))
                    .frame(width: 24, alignment: .trailing)
                VStack(alignment: .leading, spacing: 1) {
                    Text(track.title)
                        .font(.subheadline)
                        .foregroundStyle(heard ? theme.secondaryText : theme.text)
                        .strikethrough(heard, pattern: .solid, color: theme.accent.opacity(0.75))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
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
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
    }

    // MARK: Credits

    @ViewBuilder
    private func creditsSection(_ item: SavedItem) -> some View {
        if let details {
            let lines = creditLines(details)
            if !lines.isEmpty || details.credits != nil {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(lines, id: \.self) { line in
                        Text(line)
                    }
                    if let credits = details.credits, !credits.isEmpty {
                        Text(credits)
                            .padding(.top, lines.isEmpty ? 0 : 8)
                    }
                }
                .font(.caption)
                .foregroundStyle(theme.secondaryText.opacity(0.8))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .modifier(BackdropLabel())
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
        if let date = details.releaseDate {
            lines.append("Released \(date.formatted(date: .long, time: .omitted))")
        }
        if let label = details.label, !label.isEmpty { lines.append("Label: \(label)") }
        if let genre = details.genre, !genre.isEmpty { lines.append(genre) }
        if let copyright = details.copyright, !copyright.isEmpty { lines.append(copyright) }
        return lines
    }

    // MARK: Actions

    private func listen(_ url: URL, platform: Platform, album: SavedItem?) {
        if LinkDestination(rawValue: openLinksIn) == .browser {
            browserLink = BrowserLink(url: url)
        } else {
            URLOpener.open(url, platform: platform)
        }
        if let album, autoMarkHeard, !album.isListened {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { store.setListened(album, true) }
        }
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
