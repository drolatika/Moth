import PhotosUI
import SwiftUI

/// Your page: the haunted portrait, your name, your top fours, what you've heard
/// lately, and the way into your diary, ratings, reviews and notes.
struct ProfileView: View {
    @Environment(ProfileStore.self) private var profile
    @Environment(JournalStore.self) private var journal
    @Environment(ItemStore.self) private var store
    @Environment(\.theme) private var theme
    @AppStorage(SettingsKey.showTopAlbums, store: AppGroup.defaults) private var showAlbums = false
    @AppStorage(SettingsKey.showTopTracks, store: AppGroup.defaults) private var showTracks = false

    @State private var photoPick: PhotosPickerItem?
    @State private var picking: SlotTarget?
    @State private var editingName = false
    @State private var nameEntry = ""
    @State private var reviewing: ReleaseRef?

    private var shownKinds: [ShowcaseKind] {
        [.artists] + (showAlbums ? [.albums] : []) + (showTracks ? [.tracks] : [])
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 26) {
                VStack(spacing: 6) {
                    PhotosPicker(selection: $photoPick, matching: .images) {
                        HauntedPortrait(photo: profile.photo)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if profile.photo != nil {
                            Button(role: .destructive) { profile.removePhoto() } label: {
                                Label("Remove Photo", systemImage: "trash")
                            }
                        }
                    }
                    .accessibilityLabel("Profile photo")
                    .accessibilityHint("Choose a photo")

                    Button {
                        nameEntry = profile.name
                        editingName = true
                    } label: {
                        Text(profile.name.isEmpty ? "Your Name" : profile.name)
                            .font(MothFont.gothic(36))
                            .foregroundStyle(profile.name.isEmpty ? theme.secondaryText : theme.text)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, -14)

                    Text(statsLine)
                        .font(.footnote)
                        .foregroundStyle(theme.secondaryText)
                }

                ForEach(shownKinds) { kind in
                    showcase(kind)
                }

                recentlyHeard
                journalLinks
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 36)
        }
        .background(theme.background.ignoresSafeArea())
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(theme.background, for: .navigationBar)
        .onChange(of: photoPick) { _, pick in
            guard let pick else { return }
            Task {
                if let data = try? await pick.loadTransferable(type: Data.self) { profile.setPhoto(data) }
                photoPick = nil
            }
        }
        .alert("Your name", isPresented: $editingName) {
            TextField("Name", text: $nameEntry)
            Button("Save") { profile.setName(nameEntry) }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: $picking) { target in
            ShowcasePicker(target: target)
                .environment(profile)
                .environment(store)
                .environment(journal)
                .themed(theme)
        }
        .sheet(item: $reviewing) { ref in
            ReviewSheet(ref: ref).environment(journal).themed(theme)
        }
    }

    private var statsLine: String {
        let listens = journal.log.count
        let rated = journal.rated.count
        let reviews = journal.reviewed.count
        return [
            listens == 1 ? "1 listen" : "\(listens) listens",
            "\(rated) rated",
            reviews == 1 ? "1 review" : "\(reviews) reviews",
        ].joined(separator: " · ")
    }

    // MARK: Top fours

    private func showcase(_ kind: ShowcaseKind) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(kind.title)
            HStack(alignment: .top, spacing: 12) {
                ForEach(0..<4, id: \.self) { index in
                    slot(kind, index: index)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    @ViewBuilder
    private func slot(_ kind: ShowcaseKind, index: Int) -> some View {
        let item = profile.slots(kind)[index]
        let target = SlotTarget(kind: kind, index: index)
        VStack(spacing: 6) {
            Group {
                if let item {
                    ShowcaseImage(item: item, round: kind == .artists)
                } else {
                    emptySlot(round: kind == .artists)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .onTapGesture {
                if let url = item?.url, let item {
                    URLOpener.open(url, platform: item.platform)
                } else {
                    picking = target
                }
            }
            .contextMenu {
                if item != nil {
                    Button { picking = target } label: { Label("Replace", systemImage: "arrow.triangle.2.circlepath") }
                    if index > 0 {
                        Button { profile.move(kind, from: index, to: index - 1) } label: { Label("Move Left", systemImage: "arrow.left") }
                    }
                    if index < 3 {
                        Button { profile.move(kind, from: index, to: index + 1) } label: { Label("Move Right", systemImage: "arrow.right") }
                    }
                    Button(role: .destructive) { profile.set(nil, at: index, in: kind) } label: {
                        Label("Remove", systemImage: "minus.circle")
                    }
                } else {
                    Button { picking = target } label: { Label("Choose \(kind.singular)", systemImage: "plus") }
                }
            }

            if let item {
                VStack(spacing: 1) {
                    Text(item.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.text)
                    if kind != .artists, let subtitle = item.subtitle {
                        Text(subtitle).font(.caption2).foregroundStyle(theme.secondaryText)
                    }
                }
                .lineLimit(1)
                .multilineTextAlignment(.center)
            }
        }
    }

    private func emptySlot(round: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: round ? 999 : 6, style: .continuous)
        return shape
            .strokeBorder(theme.secondaryText.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            .background(shape.fill(theme.surface.opacity(0.5)))
            .overlay {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(theme.secondaryText)
            }
            .contentShape(shape)
    }

    // MARK: Recently heard

    @ViewBuilder
    private var recentlyHeard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                sectionTitle("Recently Heard")
                Spacer()
                NavigationLink("See All") { JournalView(filter: .diary).themed(theme) }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(theme.accent)
            }
            if journal.log.isEmpty {
                Text("Albums you mark heard, and listens you log from a review, show up here.")
                    .font(.footnote)
                    .foregroundStyle(theme.secondaryText)
            } else {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(journal.log.prefix(12)) { entry in
                            Button { reviewing = entry.ref } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    ReleaseArtwork(ref: entry.ref, size: 86)
                                    if let rating = journal.rating(for: entry.ref.key) {
                                        StarRating(rating: rating, size: 9, spacing: 1)
                                    }
                                    Text(entry.date, format: .dateTime.month(.abbreviated).day())
                                        .font(.caption2)
                                        .foregroundStyle(theme.secondaryText)
                                }
                                .frame(width: 86, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    // MARK: Journal

    private var journalLinks: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Journal")
            VStack(spacing: 0) {
                ForEach(JournalFilter.allCases) { filter in
                    NavigationLink {
                        JournalView(filter: filter).themed(theme)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: filter.symbol)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(theme.accent)
                                .frame(width: 24)
                            Text(filter.title).foregroundStyle(theme.text)
                            Spacer()
                            Text("\(count(filter))").foregroundStyle(theme.secondaryText)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(theme.secondaryText.opacity(0.6))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if filter != JournalFilter.allCases.last {
                        Divider().overlay(theme.text.opacity(0.06)).padding(.leading, 50)
                    }
                }
            }
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func count(_ filter: JournalFilter) -> Int {
        switch filter {
        case .diary: journal.log.count
        case .topRated, .lowestRated: journal.rated.count
        case .reviews: journal.reviewed.count
        case .notes: journal.withNotes.count
        case .artists: journal.topArtists.count
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(MothFont.gothic(24))
            .foregroundStyle(theme.text)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SlotTarget: Identifiable {
    let kind: ShowcaseKind
    let index: Int
    var id: String { "\(kind.rawValue)-\(index)" }
}

/// A pinned item's picture: round for artists, square for albums and tracks.
struct ShowcaseImage: View {
    let item: ShowcaseItem
    var round = false
    @Environment(\.theme) private var theme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: round ? 999 : 6, style: .continuous)
        Color.clear
            .overlay {
                if let file = item.imageFile, let image = ArtworkStore.image(named: file) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    AsyncImage(url: item.imageURL) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        ZStack {
                            item.platform.color.opacity(0.25)
                            Image(systemName: round ? "person.fill" : "music.note").foregroundStyle(.white.opacity(0.7))
                        }
                    }
                }
            }
            .clipShape(shape)
            .overlay { shape.strokeBorder(FrameArt.gold.opacity(round ? 0.55 : 0.2), lineWidth: round ? 1.5 : 0.5) }
            .shadow(color: .black.opacity(theme.isDark ? 0.4 : 0.12), radius: 6, y: 3)
    }
}

/// Pick something for one of the top-four slots: from your library and ratings,
/// or by searching Apple Music.
private struct ShowcasePicker: View {
    let target: SlotTarget
    @Environment(ProfileStore.self) private var profile
    @Environment(ItemStore.self) private var store
    @Environment(JournalStore.self) private var journal
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [ShowcaseItem] = []
    @State private var searching = false
    @State private var saving = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(theme.secondaryText)
                    TextField("Search for an \(target.kind.singular)", text: $query)
                        .submitLabel(.search)
                        .autocorrectionDisabled()
                        .foregroundStyle(theme.text)
                        .onSubmit(search)
                }
                .padding(12)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 18)

                if searching { ProgressView().padding(.top, 20) }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        let list = results.isEmpty && query.isEmpty ? suggestions : results
                        if results.isEmpty && query.isEmpty && !list.isEmpty {
                            Text("From your library")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(theme.secondaryText)
                                .padding(.bottom, 4)
                        }
                        ForEach(list) { item in
                            Button { choose(item) } label: {
                                HStack(spacing: 12) {
                                    ShowcaseImage(item: item, round: target.kind == .artists)
                                        .frame(width: 48, height: 48)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.title).foregroundStyle(theme.text).lineLimit(1)
                                        if let subtitle = item.subtitle {
                                            Text(subtitle).font(.caption).foregroundStyle(theme.secondaryText).lineLimit(1)
                                        }
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 7)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(saving)
                        }
                    }
                    .padding(.horizontal, 18)
                }
                .scrollDismissesKeyboard(.immediately)
            }
            .padding(.top, 8)
            .background(theme.background.ignoresSafeArea())
            .navigationTitle(target.kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                if saving { ToolbarItem(placement: .confirmationAction) { ProgressView() } }
            }
        }
    }

    /// What you already have: stacked and saved artists, or your best-rated and saved albums.
    private var suggestions: [ShowcaseItem] {
        var seen = Set<String>()
        func unique(_ items: [ShowcaseItem]) -> [ShowcaseItem] {
            items.filter { seen.insert($0.title.lowercased()).inserted }
        }
        switch target.kind {
        case .artists:
            let stacks = store.items.filter(\.isStack).map {
                ShowcaseItem(id: "stack-\($0.id)", title: $0.title, subtitle: $0.subtitle, imageURL: $0.artworkURL,
                             imageFile: $0.artworkFile, url: $0.url, platform: $0.platform)
            }
            let heard = journal.topArtists.map {
                ShowcaseItem(id: "artist-\($0.name)", title: $0.name, subtitle: $0.listens == 1 ? "1 listen" : "\($0.listens) listens",
                             imageURL: nil, url: nil, platform: $0.artwork.platform)
            }
            let saved = store.items.compactMap(\.artist).map {
                ShowcaseItem(id: "artist-\($0)", title: $0, subtitle: nil, imageURL: nil, url: nil, platform: .appleMusic)
            }
            return unique(stacks + heard + saved)
        case .albums:
            let rated = journal.topRated.map {
                ShowcaseItem(id: $0.ref.key, title: $0.ref.title, subtitle: $0.ref.artist, imageURL: $0.ref.artworkURL,
                             imageFile: $0.ref.artworkFile, url: $0.ref.url, platform: $0.ref.platform)
            }
            let saved = store.items.filter { !$0.isStack && $0.kind == .album }.map {
                ShowcaseItem(id: $0.linkKey, title: $0.title, subtitle: $0.artist, imageURL: $0.artworkURL,
                             imageFile: $0.artworkFile, url: $0.url, platform: $0.platform)
            }
            return unique(rated + saved)
        case .tracks:
            return []
        }
    }

    private func search() {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        searching = true
        let term = query, kind = target.kind
        Task {
            results = await ShowcaseSearch.search(term, kind: kind)
            searching = false
        }
    }

    private func choose(_ item: ShowcaseItem) {
        saving = true
        Task {
            var item = item
            if target.kind == .artists, item.imageURL == nil, item.imageFile == nil {
                // Find a picture: the artist on Apple Music.
                if let found = try? await ArtistCatalog.search(item.title, on: .appleMusic).first {
                    item.imageURL = await ArtistCatalog.image(for: found)
                    if item.url == nil { item.url = found.url }
                }
            }
            profile.set(item, at: target.index, in: target.kind)
            Haptics.success()
            saving = false
            dismiss()
        }
    }
}
