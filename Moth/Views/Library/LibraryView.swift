import SafariServices
import SwiftUI

enum Shelf: String, CaseIterable, Identifiable {
    case queue, heard
    var id: String { rawValue }
}

/// How the albums are laid out.
enum LibraryLayout: String, CaseIterable, Identifiable {
    case grid, rows
    var id: String { rawValue }
    var label: String { self == .grid ? "Grid" : "Rows" }
    var symbol: String { self == .grid ? "square.grid.2x2" : "list.bullet" }
}

/// How the albums are ordered: newest first, or in sections by type or service.
enum LibraryGrouping: String, CaseIterable, Identifiable {
    case newest, type, service
    var id: String { rawValue }
    var label: String {
        switch self {
        case .newest: "Newest First"
        case .type: "By Type"
        case .service: "By Service"
        }
    }
}

/// Where "Listen" takes you.
enum LinkDestination: String, CaseIterable, Identifiable {
    case app, browser
    var id: String { rawValue }
    var label: String { self == .app ? "The app" : "In Moth" }
}

struct LibraryView: View {
    @Environment(ItemStore.self) private var store
    @Environment(Connections.self) private var connections
    @Environment(\.theme) private var theme
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(SettingsKey.libraryLayout, store: AppGroup.defaults) private var layoutRaw = LibraryLayout.grid.rawValue
    @AppStorage(SettingsKey.libraryGrouping, store: AppGroup.defaults) private var groupingRaw = LibraryGrouping.newest.rawValue

    @State private var progress: Double = 0
    @State private var page: Shelf? = .queue
    @State private var searchText = ""
    @State private var showingAdd = false
    @State private var showingSettings = false
    @State private var selecting = false
    @State private var selection: Set<UUID> = []
    @State private var draggingCard = false
    @State private var openItem: SavedItem?
    @State private var searchVisible = false
    @FocusState private var searchFocused: Bool

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    private var currentShelf: Shelf { progress < 0.5 ? .queue : .heard }
    private var layout: LibraryLayout { LibraryLayout(rawValue: layoutRaw) ?? .grid }
    private var grouping: LibraryGrouping { LibraryGrouping(rawValue: groupingRaw) ?? .newest }

    private func items(on shelf: Shelf) -> [SavedItem] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return store.items.filter { item in
            (shelf == .queue ? !item.isListened : item.isListened)
                && (query.isEmpty
                    || item.title.localizedCaseInsensitiveContains(query)
                    || (item.artist?.localizedCaseInsensitiveContains(query) ?? false))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            MothHeader(
                progress: progress,
                queueCount: store.items.filter { !$0.isListened }.count,
                heardCount: store.items.filter(\.isListened).count,
                selection: selecting ? MothHeader.SelectionBar(
                    count: selection.count,
                    onCancel: endSelecting,
                    onSelectAll: { selection = Set(items(on: currentShelf).map(\.id)) }
                ) : nil,
                onSettings: { showingSettings = true },
                onAdd: { showingAdd = true }
            )
            if searchVisible {
                searchBar
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            pager
        }
        .background { ThemeBackdrop() }
        .overlay(alignment: .bottom) { bottomBar }
        .sheet(item: $openItem) { item in
            AlbumDetailView(itemID: item.id, onSelect: { selected in
                selecting = true
                selection = [selected.id]
            })
            .environment(store)
            .themed(theme)
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingAdd) {
            AddLinkView().environment(store).themed(theme)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView().environment(store).environment(connections).themed(theme)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.reload() }
        }
        .onChange(of: currentShelf) { _, _ in
            if selecting { endSelecting() }
        }
    }

    // MARK: Pager

    private var pager: some View {
        GeometryReader { geo in
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(Shelf.allCases) { shelf in
                        shelfPage(shelf)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .id(shelf)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollIndicators(.hidden)
            .scrollPosition(id: $page)
            .scrollDisabled(draggingCard)
            .onScrollGeometryChange(for: Double.self) { scroll in
                scroll.contentOffset.x / max(scroll.containerSize.width, 1)
            } action: { _, offset in
                progress = min(1, max(0, offset))
            }
        }
    }

    private func shelfPage(_ shelf: Shelf) -> some View {
        let list = items(on: shelf)
        return ScrollView {
            if list.isEmpty {
                EmptyShelfView(shelf: shelf, isSearching: !searchText.isEmpty)
                    .padding(.top, 70)
                    .padding(.horizontal, 24)
            } else {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(sections(for: list)) { section in
                        if let title = section.title {
                            Text(title)
                                .font(MothFont.gothic(24))
                                .foregroundStyle(theme.text)
                                .padding(.top, 6)
                        }
                        if layout == .grid {
                            LazyVGrid(columns: columns, spacing: 22) {
                                ForEach(section.items) { item in cell(item, on: shelf) }
                            }
                        } else {
                            LazyVStack(spacing: 12) {
                                ForEach(section.items) { item in cell(item, on: shelf) }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 100)
            }
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .onScrollGeometryChange(for: Double.self) { scroll in
            scroll.contentOffset.y + scroll.contentInsets.top
        } action: { _, pulled in
            revealOrHideSearch(scrollY: pulled)
        }
    }

    private struct ShelfSection: Identifiable {
        let id: String
        let title: String?
        let items: [SavedItem]
    }

    private func sections(for list: [SavedItem]) -> [ShelfSection] {
        switch grouping {
        case .newest:
            return [ShelfSection(id: "all", title: nil, items: list)]
        case .type:
            let order: [SavedItem.Kind] = [.album, .track, .playlist, .artist, .episode, .other]
            return order.compactMap { kind in
                let matches = list.filter { $0.kind == kind }
                return matches.isEmpty ? nil : ShelfSection(id: kind.rawValue, title: kind.pluralLabel, items: matches)
            }
        case .service:
            return Platform.allCases.compactMap { platform in
                let matches = list.filter { $0.platform == platform }
                return matches.isEmpty ? nil : ShelfSection(id: platform.rawValue, title: platform.name, items: matches)
            }
        }
    }

    @ViewBuilder
    private func cell(_ item: SavedItem, on shelf: Shelf) -> some View {
        if selecting {
            Button { toggle(item) } label: {
                if layout == .grid {
                    AlbumCard(item: item, selected: selection.contains(item.id))
                } else {
                    AlbumRow(item: item, selected: selection.contains(item.id))
                }
            }
            .buttonStyle(PressableStyle())
        } else {
            ThrowableCard(
                direction: shelf == .queue ? 1 : -1,
                isDragging: $draggingCard,
                onThrow: { withAnimation(.snappy) { store.setListened(item, shelf == .queue) } },
                onTap: { openItem = item }
            ) {
                if layout == .grid {
                    AlbumCard(item: item)
                } else {
                    AlbumRow(item: item)
                }
            }
        }
    }

    // MARK: Search and view options

    private var searchBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(theme.secondaryText)
                TextField("Search albums & artists", text: $searchText)
                    .focused($searchFocused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .foregroundStyle(theme.text)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(theme.secondaryText)
                    }
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background(theme.surface, in: Capsule())

            Menu {
                Section("View") {
                    Picker("View", selection: $layoutRaw) {
                        ForEach(LibraryLayout.allCases) { option in
                            Label(option.label, systemImage: option.symbol).tag(option.rawValue)
                        }
                    }
                    .pickerStyle(.inline)
                }
                Section("Order") {
                    Picker("Order", selection: $groupingRaw) {
                        ForEach(LibraryGrouping.allCases) { option in
                            Text(option.label).tag(option.rawValue)
                        }
                    }
                    .pickerStyle(.inline)
                }
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(theme.accent)
                    .frame(width: 40, height: 40)
                    .background(theme.surface, in: Circle())
            }
            .accessibilityLabel("View options")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    /// Pulling a page down past the top reveals the search bar; scrolling back
    /// down tucks it away again unless you're using it.
    private func revealOrHideSearch(scrollY: Double) {
        if scrollY < -50 && !searchVisible {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { searchVisible = true }
            Haptics.impact(.light)
        } else if scrollY > 60 && searchVisible && searchText.isEmpty && !searchFocused {
            withAnimation(.easeOut(duration: 0.2)) { searchVisible = false }
        }
    }

    // MARK: Bottom: selection actions

    @ViewBuilder
    private var bottomBar: some View {
        if selecting {
            HStack {
                Spacer()
                Button(currentShelf == .queue ? "Mark Heard" : "Move to Queue") {
                    withAnimation(.snappy) { store.setListened(ids: selection, currentShelf == .queue) }
                    Haptics.success()
                    endSelecting()
                }
                .foregroundStyle(theme.accent)
                Spacer()
                Button("Remove", role: .destructive) {
                    withAnimation(.snappy) { store.delete(ids: selection) }
                    endSelecting()
                }
                .foregroundStyle(.red)
                Spacer()
            }
            .font(.body.weight(.semibold))
            .disabled(selection.isEmpty)
            .frame(height: 58)
            .background(theme.surface.opacity(0.97), in: Capsule())
            .padding(.horizontal, 20)
            .padding(.bottom, 6)
        }
    }

    // MARK: Actions

    private func toggle(_ item: SavedItem) {
        if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
        Haptics.impact(.light)
    }

    private func endSelecting() {
        selecting = false
        selection = []
    }
}

struct BrowserLink: Identifiable {
    let url: URL
    var id: URL { url }
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

extension SavedItem.Kind {
    var pluralLabel: String {
        switch self {
        case .album: "Albums"
        case .track: "Tracks"
        case .playlist: "Playlists"
        case .artist: "Artists"
        case .episode: "Episodes"
        case .other: "Links"
        }
    }
}

private struct EmptyShelfView: View {
    let shelf: Shelf
    let isSearching: Bool
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 12) {
            Text(title)
                .font(MothFont.gothic(26))
                .foregroundStyle(theme.text)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity)
    }

    private var title: String {
        if isSearching { return "Nothing matches" }
        return shelf == .queue ? "The queue is empty" : "Nothing heard yet"
    }

    private var message: String {
        if isSearching { return "Try another album or artist." }
        return shelf == .queue
            ? "In Spotify, Apple Music, Bandcamp or anywhere else, tap Share and choose Moth."
            : "Press and hold an album on the queue, then throw it toward the lantern."
    }
}
