import SwiftUI

/// The + sheet: paste a link, or find an artist and save their releases as a stack.
struct AddLinkView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case link, artist
        var id: String { rawValue }
        var label: String { self == .link ? "Link" : "Artist" }
    }

    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode = .link
    @State private var detent: PresentationDetent = .medium

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Add", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                switch mode {
                case .link: LinkForm(onDone: { dismiss() })
                case .artist: ArtistStackForm(onDone: { dismiss() })
                }
            }
            .padding(20)
            .background(theme.background.ignoresSafeArea())
            .navigationTitle(mode == .link ? "Add Link" : "Add Artist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large], selection: $detent)
        .onChange(of: mode) { _, mode in
            withAnimation { detent = mode == .artist ? .large : .medium }
        }
    }
}

// MARK: Link

private struct LinkForm: View {
    let onDone: () -> Void
    @Environment(ItemStore.self) private var store
    @Environment(\.theme) private var theme

    @State private var text = ""
    @State private var isSaving = false
    @FocusState private var fieldFocused: Bool

    private var url: URL? { LinkCleaner.firstURL(in: text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Paste a link from any music app or website.")
                .font(.subheadline)
                .foregroundStyle(theme.secondaryText)

            TextField("https://…", text: $text, axis: .vertical)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($fieldFocused)
                .padding(14)
                .foregroundStyle(theme.text)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            HStack {
                PasteButton(payloadType: URL.self) { urls in
                    if let first = urls.first { text = first.absoluteString }
                }
                .buttonBorderShape(.capsule)
                .labelStyle(.titleAndIcon)
                Spacer()
            }

            Spacer()

            Button(action: save) {
                HStack {
                    if isSaving { ProgressView().tint(theme.onAccent) }
                    Text(isSaving ? "Saving…" : "Save to Queue")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .foregroundStyle(theme.onAccent)
                .background(theme.accent.opacity(url == nil ? 0.4 : 1), in: Capsule())
            }
            .disabled(url == nil || isSaving)
        }
        .onAppear { fieldFocused = true }
    }

    private func save() {
        guard let url else { return }
        isSaving = true
        Task {
            _ = await LibrarySaver.save(url)
            store.reload()
            isSaving = false
            onDone()
        }
    }
}

// MARK: Artist

/// Type an artist, pick a service and which kinds of release, choose the right
/// artist, then save everything as one stack.
private struct ArtistStackForm: View {
    let onDone: () -> Void
    @Environment(ItemStore.self) private var store
    @Environment(Connections.self) private var connections
    @Environment(\.theme) private var theme

    @State private var name = ""
    @State private var service: Platform = .appleMusic
    @State private var types: Set<StackRelease.ReleaseType> = [.album, .ep]
    @State private var results: [ArtistResult] = []
    @State private var searching = false
    @State private var message: String?
    @State private var chosen: ArtistResult?
    @State private var releases: [StackRelease]?
    @State private var saving = false
    /// Releases you've unticked (re-releases, duplicates, ones you don't want).
    @State private var excluded: Set<String> = []
    @FocusState private var fieldFocused: Bool

    private var services: [Platform] { ArtistCatalog.services(spotifyConnected: connections.spotifyConnected) }
    /// Everything of the chosen kinds, ticked or not.
    private var shown: [StackRelease] { (releases ?? []).filter { types.contains($0.type) } }
    /// What will actually be added.
    private var picked: [StackRelease] { shown.filter { !excluded.contains($0.id) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let chosen {
                preview(chosen)
            } else {
                searchForm
            }
        }
        .onAppear { fieldFocused = chosen == nil }
    }

    // MARK: Search

    private var searchForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(theme.secondaryText)
                TextField("Artist name", text: $name)
                    .focused($fieldFocused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .foregroundStyle(theme.text)
                    .onSubmit(search)
            }
            .padding(14)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            chips(title: "From") {
                ForEach(services) { platform in
                    chip(platform.name, on: service == platform, led: platform.color) {
                        service = platform
                        if !results.isEmpty { search() }
                    }
                }
            }
            typeChips

            if searching {
                HStack { Spacer(); ProgressView(); Spacer() }.padding(.top, 20)
            } else if let message {
                Text(message).font(.footnote).foregroundStyle(theme.secondaryText).padding(.top, 8)
            }

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(results) { artist in
                        Button { choose(artist) } label: { ArtistResultRow(artist: artist) }
                            .buttonStyle(.plain)
                        Divider().overlay(theme.text.opacity(0.06)).padding(.leading, 62)
                    }
                }
            }
            .scrollDismissesKeyboard(.immediately)

            if results.isEmpty && !searching {
                Spacer()
                Button(action: search) {
                    Text("Search")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .foregroundStyle(theme.onAccent)
                        .background(theme.accent.opacity(name.isEmpty ? 0.4 : 1), in: Capsule())
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private var typeChips: some View {
        chips(title: "Add") {
            ForEach(StackRelease.ReleaseType.allCases) { type in
                chip(type.pluralLabel, on: types.contains(type)) {
                    if types.contains(type) {
                        if types.count > 1 { types.remove(type) }
                    } else {
                        types.insert(type)
                    }
                }
            }
        }
    }

    // MARK: Preview

    private func preview(_ artist: ArtistResult) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                withAnimation(.snappy) {
                    chosen = nil
                    releases = nil
                }
            } label: {
                Label("Artists", systemImage: "chevron.left").font(.subheadline.weight(.medium))
            }
            .foregroundStyle(theme.accent)

            HStack(spacing: 14) {
                ArtistPhoto(artist: artist, size: 72)
                VStack(alignment: .leading, spacing: 4) {
                    Text(artist.name).font(MothFont.gothic(28)).foregroundStyle(theme.text)
                    PlatformBadge(platform: artist.platform, seed: artist.id.hashValue)
                }
            }

            typeChips

            if let releases {
                Text(summary(releases))
                    .font(.footnote)
                    .foregroundStyle(theme.secondaryText)
                HStack {
                    Text("\(picked.count) of \(shown.count) selected · tap to leave one out")
                        .font(.caption)
                        .foregroundStyle(theme.secondaryText)
                    Spacer()
                    Button(picked.count == shown.count ? "Select None" : "Select All") {
                        if picked.count == shown.count {
                            excluded.formUnion(shown.map(\.id))
                        } else {
                            excluded.subtract(shown.map(\.id))
                        }
                        Haptics.impact(.light)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.accent)
                }
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(shown) { release in
                            let on = !excluded.contains(release.id)
                            HStack(spacing: 12) {
                                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 20))
                                    .foregroundStyle(on ? theme.accent : theme.secondaryText.opacity(0.5))
                                AsyncImage(url: release.artworkURL) { image in
                                    image.resizable().scaledToFill()
                                } placeholder: {
                                    artist.platform.color.opacity(0.3)
                                }
                                .frame(width: 44, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(release.title).font(.subheadline).foregroundStyle(theme.text).lineLimit(2)
                                    Text([release.year, release.type.label].compactMap { $0 }.joined(separator: " · "))
                                        .font(.caption)
                                        .foregroundStyle(theme.secondaryText)
                                }
                                Spacer()
                            }
                            .opacity(on ? 1 : 0.45)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if on { excluded.insert(release.id) } else { excluded.remove(release.id) }
                                Haptics.impact(.light)
                            }
                        }
                    }
                }
                Button(action: save) {
                    HStack {
                        if saving { ProgressView().tint(theme.onAccent) }
                        Text(saving ? "Saving…" : picked.count == 1 ? "Add 1 Release" : "Add \(picked.count) Releases")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .foregroundStyle(theme.onAccent)
                    .background(theme.accent.opacity(picked.isEmpty ? 0.4 : 1), in: Capsule())
                }
                .disabled(picked.isEmpty || saving)
            } else if let message {
                Text(message).font(.footnote).foregroundStyle(theme.secondaryText)
                Spacer()
            } else {
                HStack { Spacer(); ProgressView(); Spacer() }.padding(.top, 30)
                Spacer()
            }
        }
    }

    private func summary(_ releases: [StackRelease]) -> String {
        StackRelease.ReleaseType.allCases.compactMap { type in
            let count = releases.filter { $0.type == type }.count
            return count == 0 ? nil : "\(count) \(count == 1 ? type.label : type.pluralLabel)"
        }
        .joined(separator: " · ")
    }

    // MARK: Pieces

    private func chips<Content: View>(title: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.secondaryText)
                .frame(width: 38, alignment: .leading)
            ScrollView(.horizontal) {
                HStack(spacing: 8) { content() }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func chip(_ label: String, on: Bool, led: Color? = nil, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.impact(.light)
            action()
        } label: {
            HStack(spacing: 6) {
                if let led { Circle().fill(led).frame(width: 7, height: 7) }
                Text(label)
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .foregroundStyle(on ? theme.onAccent : theme.text)
            .background(on ? theme.accent : theme.surface, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: Actions

    private func search() {
        let term = name.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return }
        fieldFocused = false
        searching = true
        message = nil
        let platform = service
        Task {
            do {
                results = try await ArtistCatalog.search(term, on: platform)
                if results.isEmpty { message = "No artists called “\(term)” on \(platform.name)." }
            } catch {
                results = []
                message = "Couldn't search \(platform.name) right now."
            }
            searching = false
        }
    }

    private func choose(_ artist: ArtistResult) {
        withAnimation(.snappy) {
            chosen = artist
            releases = nil
            message = nil
            excluded = []
        }
        Task {
            do {
                let found = try await ArtistCatalog.releases(for: artist)
                if found.isEmpty { message = "\(artist.name) has no releases on \(artist.platform.name)." }
                releases = found.isEmpty ? nil : found
            } catch {
                message = "Couldn't load \(artist.name)'s releases right now."
            }
        }
    }

    private func save() {
        guard let chosen else { return }
        saving = true
        let releases = picked
        Task {
            await ArtistCatalog.saveStack(chosen, releases: releases)
            store.reload()
            Haptics.success()
            saving = false
            onDone()
        }
    }
}

private struct ArtistResultRow: View {
    let artist: ArtistResult
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            ArtistPhoto(artist: artist, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(artist.name).font(.body.weight(.medium)).foregroundStyle(theme.text)
                if let detail = artist.detail {
                    Text(detail).font(.caption).foregroundStyle(theme.secondaryText)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(theme.secondaryText.opacity(0.6))
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

/// The artist's picture, fetched from their page when the search didn't include one.
struct ArtistPhoto: View {
    let artist: ArtistResult
    var size: CGFloat = 48
    @State private var url: URL?

    var body: some View {
        AsyncImage(url: url ?? artist.imageURL) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            ZStack {
                artist.platform.color.opacity(0.25)
                Image(systemName: "person.fill").foregroundStyle(.white.opacity(0.7))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: artist.id) {
            if artist.imageURL == nil { url = await ArtistCatalog.image(for: artist) }
        }
    }
}
