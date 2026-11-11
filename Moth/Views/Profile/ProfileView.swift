import PhotosUI
import SwiftUI

/// The profile, opened full-screen from the framed avatar in the library header.
struct ProfileScreen: View {
    var body: some View {
        NavigationStack { ProfileView() }
    }
}

enum ProfileTab: String, CaseIterable, Identifiable {
    case profile, diary, reviews, ratings
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

/// Your page, laid out like a Letterboxd profile: tabs along the top, then your
/// framed portrait, name and bio, a row of counts, your favourites, recent
/// activity with your stars, how your ratings spread, and links into the journal.
struct ProfileView: View {
    /// Pushed from Settings rather than opened from the library: no gear or close button.
    var fromSettings = false

    @Environment(ProfileStore.self) private var profile
    @Environment(JournalStore.self) private var journal
    @Environment(ItemStore.self) private var store
    @Environment(Connections.self) private var connections
    @Environment(TrackIndex.self) private var trackIndex
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.showTopAlbums, store: AppGroup.defaults) private var showAlbums = false
    @AppStorage(SettingsKey.showTopTracks, store: AppGroup.defaults) private var showTracks = false

    @State private var tab: ProfileTab = .profile
    @State private var lowestFirst = false
    @State private var photoPick: PhotosPickerItem?
    @State private var picking: SlotTarget?
    @State private var editingName = false
    @State private var nameEntry = ""
    @State private var bioEntry = ""
    @State private var reviewing: ReleaseRef?
    @State private var showingSettings = false
    /// The favourites row being edited, if any.
    @State private var editing: ShowcaseKind?

    private var shownKinds: [ShowcaseKind] {
        [.artists] + (showAlbums ? [.albums] : []) + (showTracks ? [.tracks] : [])
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                tabBar
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 14)
                switch tab {
                case .profile:
                    profileTab
                case .diary:
                    JournalView(filter: .diary, embedded: true).id("diary").padding(.horizontal, 16)
                case .reviews:
                    JournalView(filter: .reviews, embedded: true).id("reviews").padding(.horizontal, 16)
                case .ratings:
                    VStack(spacing: 12) {
                        Picker("Order", selection: $lowestFirst) {
                            Text("Highest").tag(false)
                            Text("Lowest").tag(true)
                        }
                        .pickerStyle(.segmented)
                        JournalView(filter: lowestFirst ? .lowestRated : .topRated, embedded: true)
                            .id(lowestFirst ? "lowest" : "highest")
                    }
                    .padding(.horizontal, 16)
                }
            }
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(theme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(theme.background, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(profile.name.isEmpty ? "Profile" : profile.name)
                    .font(.headline)
                    .foregroundStyle(theme.text)
            }
            if !fromSettings {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingSettings = true } label: {
                        Image(systemName: "gearshape").foregroundStyle(theme.text)
                    }
                    .accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").foregroundStyle(theme.text)
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
        .onChange(of: photoPick) { _, pick in
            guard let pick else { return }
            Task {
                if let data = try? await pick.loadTransferable(type: Data.self) { profile.setPhoto(data) }
                photoPick = nil
            }
        }
        .alert("Edit profile", isPresented: $editingName) {
            TextField("Name", text: $nameEntry)
            TextField("Bio", text: $bioEntry)
            Button("Save") { profile.setName(nameEntry, bio: bioEntry) }
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
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environment(store)
                .environment(journal)
                .environment(connections)
                .environment(profile)
                .environment(trackIndex)
                .themed(theme)
        }
    }

    // MARK: Tabs

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(ProfileTab.allCases) { option in
                Button {
                    withAnimation(.snappy(duration: 0.2)) { tab = option }
                    Haptics.impact(.light)
                } label: {
                    Text(option.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(tab == option ? theme.text : theme.secondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background {
                            if tab == option {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(theme.text.opacity(theme.isDark ? 0.16 : 0.1))
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: Profile tab

    private var profileTab: some View {
        VStack(spacing: 0) {
            header
            statsRow
                .padding(.top, 18)
                .padding(.bottom, 4)
            ForEach(shownKinds) { kind in
                section(kind.favouritesTitle, trailing: {
                    Button(editing == kind ? "Done" : "Edit") {
                        withAnimation(.snappy) { editing = editing == kind ? nil : kind }
                        Haptics.impact(.light)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.accent)
                }) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(0..<4, id: \.self) { index in
                            slot(kind, index: index).frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            recentActivity
            ratingsChart
            journalRows
        }
    }

    private var header: some View {
        VStack(spacing: 4) {
            PhotosPicker(selection: $photoPick, matching: .images) {
                HauntedPortrait(photo: profile.photo)
                    .scaleEffect(0.74)
                    .frame(width: HauntedPortrait.size * 0.74, height: HauntedPortrait.size * 0.74)
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
                bioEntry = profile.bio
                editingName = true
            } label: {
                VStack(spacing: 4) {
                    Text(profile.name.isEmpty ? "Your Name" : profile.name)
                        .font(MothFont.gothic(30))
                        .foregroundStyle(profile.name.isEmpty ? theme.secondaryText : theme.text)
                    Text(profile.bio.isEmpty ? "Tap to add a bio" : profile.bio)
                        .font(.footnote)
                        .foregroundStyle(theme.secondaryText.opacity(profile.bio.isEmpty ? 0.6 : 1))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 30)
            .padding(.top, 6)
        }
    }

    private var statsRow: some View {
        let year = Calendar.current.component(.year, from: .now)
        let thisYear = journal.log.filter { Calendar.current.component(.year, from: $0.date) == year }.count
        let stats: [(Int, String, ProfileTab)] = [
            (journal.log.count, "Heard", .diary),
            (thisYear, "This Year", .diary),
            (journal.rated.count, "Rated", .ratings),
            (journal.reviewed.count, "Reviews", .reviews),
        ]
        return HStack(spacing: 0) {
            ForEach(Array(stats.enumerated()), id: \.offset) { index, stat in
                if index > 0 {
                    Rectangle().fill(theme.text.opacity(0.1)).frame(width: 0.5, height: 30)
                }
                Button {
                    withAnimation(.snappy(duration: 0.2)) { tab = stat.2 }
                } label: {
                    VStack(spacing: 2) {
                        Text("\(stat.0)")
                            .font(.title3.weight(.semibold).monospacedDigit())
                            .foregroundStyle(theme.text)
                        Text(stat.1.uppercased())
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(0.6)
                            .foregroundStyle(theme.secondaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: Sections

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        section(title, trailing: { EmptyView() }, content: content)
    }

    private func section<Trailing: View, Content: View>(
        _ title: String,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Rectangle().fill(theme.text.opacity(0.1)).frame(height: 0.5)
            HStack(alignment: .firstTextBaseline) {
                Text(title.uppercased())
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(theme.secondaryText)
                Spacer()
                trailing()
            }
            .padding(.horizontal, 16)
            content()
                .padding(.horizontal, 16)
        }
        .padding(.top, 14)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func slot(_ kind: ShowcaseKind, index: Int) -> some View {
        let item = profile.slots(kind)[index]
        let target = SlotTarget(kind: kind, index: index)
        let isEditing = editing == kind
        let radius: CGFloat = kind == .artists ? 999 : 4
        VStack(spacing: 6) {
            Group {
                if let item {
                    ShowcaseImage(item: item, round: kind == .artists)
                        .overlay {
                            if isEditing {
                                ZStack {
                                    Color.black.opacity(0.45)
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(.white)
                                }
                                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                            }
                        }
                        .overlay(alignment: .topLeading) {
                            if isEditing {
                                Button {
                                    withAnimation(.snappy) { profile.set(nil, at: index, in: kind) }
                                    Haptics.impact(.light)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .font(.system(size: 22))
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, Color(hex: 0xB0302A))
                                }
                                .buttonStyle(.plain)
                                .offset(x: -6, y: -6)
                                .accessibilityLabel("Remove \(item.title)")
                            }
                        }
                } else {
                    emptySlot(radius: radius)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .onTapGesture {
                if !isEditing, let url = item?.url, let item {
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

            if kind == .artists, let item {
                Text(item.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
            }
        }
    }

    private func emptySlot(radius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return shape
            .strokeBorder(theme.secondaryText.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            .background(shape.fill(theme.surface.opacity(0.6)))
            .overlay {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(theme.secondaryText)
            }
            .contentShape(shape)
    }

    // MARK: Recent activity

    private var recentActivity: some View {
        section("Recent Activity") {
            VStack(spacing: 12) {
                if journal.log.isEmpty {
                    Text("Albums you mark heard, and listens you log from a review, show up here.")
                        .font(.footnote)
                        .foregroundStyle(theme.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(0..<4, id: \.self) { index in
                            Group {
                                if index < journal.log.count {
                                    let entry = journal.log[index]
                                    Button { reviewing = entry.ref } label: {
                                        VStack(alignment: .leading, spacing: 5) {
                                            ReleaseArtwork(ref: entry.ref, size: nil, cornerRadius: 4)
                                                .shadow(color: .black.opacity(theme.isDark ? 0.4 : 0.12), radius: 4, y: 2)
                                            if let rating = journal.rating(for: entry.ref.key) {
                                                StarRating(rating: rating, size: 9, spacing: 1)
                                            } else {
                                                Text(" ").font(.system(size: 9))
                                            }
                                        }
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    Color.clear.aspectRatio(1, contentMode: .fit)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
                Button {
                    withAnimation(.snappy(duration: 0.2)) { tab = .diary }
                } label: {
                    HStack {
                        Text("More activity").foregroundStyle(theme.text)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(theme.secondaryText)
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Ratings

    private var ratingsChart: some View {
        let buckets = (1...10).map { step in
            journal.rated.filter { Int((($0.rating ?? 0) * 2).rounded()) == step }.count
        }
        let peak = max(buckets.max() ?? 0, 1)
        return section("Ratings", trailing: {
            Text("\(journal.rated.count)")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(theme.secondaryText)
        }) {
            HStack(alignment: .bottom, spacing: 8) {
                Image(systemName: "star.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(theme.accent)
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(0..<10, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(theme.secondaryText.opacity(buckets[index] == 0 ? 0.15 : 0.45))
                            .frame(height: max(3, 54 * CGFloat(buckets[index]) / CGFloat(peak)))
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 56, alignment: .bottom)
                StarRating(rating: 5, size: 8, spacing: 0.5)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(journal.rated.count) ratings")
        }
    }

    // MARK: Journal links

    private var journalRows: some View {
        let rows: [(JournalFilter, Int)] = [
            (.diary, journal.log.count),
            (.reviews, journal.reviewed.count),
            (.notes, journal.withNotes.count),
            (.topRated, journal.rated.count),
            (.artists, journal.topArtists.count),
        ]
        return VStack(spacing: 0) {
            Rectangle().fill(theme.text.opacity(0.1)).frame(height: 0.5)
            ForEach(rows, id: \.0) { row in
                let (filter, count) = row
                NavigationLink {
                    JournalView(filter: filter).themed(theme)
                } label: {
                    HStack {
                        Text(filter == .topRated ? "Ratings" : filter.title).foregroundStyle(theme.text)
                        Spacer()
                        Text("\(count)").foregroundStyle(theme.secondaryText).monospacedDigit()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(theme.secondaryText.opacity(0.6))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Rectangle().fill(theme.text.opacity(0.1)).frame(height: 0.5).padding(.leading, 16)
            }
        }
        .padding(.top, 14)
    }
}

extension ShowcaseKind {
    var favouritesTitle: String {
        switch self {
        case .artists: "Favorite Artists"
        case .albums: "Favorite Albums"
        case .tracks: "Favorite Tracks"
        }
    }
}

/// Your photo in a tiny copy of the portrait frame: the way into your profile.
struct FramedAvatar: View {
    var size: CGFloat = 42
    @Environment(ProfileStore.self) private var profile

    var body: some View {
        let opening = size * (1 - 2 * 110.0 / 900)
        ZStack {
            Group {
                if let photo = profile.photo {
                    Image(uiImage: photo).resizable().scaledToFill()
                } else {
                    Color(hex: 0x241C16)
                    Image(systemName: "person.fill")
                        .font(.system(size: size * 0.32))
                        .foregroundStyle(Color(hex: 0x6A5A4A))
                }
            }
            .frame(width: opening + 1, height: opening + 1)
            .clipped()
            Image("PortraitFrame").resizable().frame(width: size, height: size)
        }
        .frame(width: size, height: size)
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
