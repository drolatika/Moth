import SafariServices
import SwiftUI

enum Shelf: String, CaseIterable, Identifiable {
    case queue, heard
    var id: String { rawValue }
}

/// Where tapping an album takes you.
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
    @AppStorage(SettingsKey.autoMarkListened, store: AppGroup.defaults) private var autoMarkListened = false
    @AppStorage(SettingsKey.openLinksIn, store: AppGroup.defaults) private var openLinksIn = LinkDestination.app.rawValue

    @State private var progress: Double = 0
    @State private var page: Shelf? = .queue
    @State private var searchText = ""
    @State private var showingAdd = false
    @State private var showingSettings = false
    @State private var selecting = false
    @State private var selection: Set<UUID> = []
    @State private var draggingCard = false
    @State private var browserLink: BrowserLink?
    @State private var heldItem: SavedItem?
    @FocusState private var searchFocused: Bool

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    private var currentShelf: Shelf { progress < 0.5 ? .queue : .heard }

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
            pager
        }
        .background { ThemeBackdrop() }
        .overlay(alignment: .bottom) { bottomBar }
        .overlay {
            if let item = heldItem {
                HoldMenu(
                    item: item,
                    onListen: { dismissMenu(); open(item) },
                    onSelect: {
                        dismissMenu()
                        selecting = true
                        selection = [item.id]
                    },
                    onRemove: {
                        dismissMenu()
                        withAnimation(.snappy) { store.delete(item) }
                    },
                    onDismiss: dismissMenu
                )
                .transition(.opacity)
            }
        }
        .sheet(isPresented: $showingAdd) {
            AddLinkView().environment(store).themed(theme)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView().environment(store).environment(connections).themed(theme)
        }
        .sheet(item: $browserLink) { link in SafariView(url: link.url).ignoresSafeArea() }
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
                LazyVGrid(columns: columns, spacing: 22) {
                    ForEach(list) { item in
                        cell(item, on: shelf)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 110)
            }
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.immediately)
    }

    @ViewBuilder
    private func cell(_ item: SavedItem, on shelf: Shelf) -> some View {
        if selecting {
            Button { toggle(item) } label: {
                AlbumCard(item: item, selected: selection.contains(item.id))
            }
            .buttonStyle(PressableStyle())
        } else {
            ThrowableCard(
                direction: shelf == .queue ? 1 : -1,
                isDragging: $draggingCard,
                onThrow: { withAnimation(.snappy) { store.setListened(item, shelf == .queue) } },
                onHold: { withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) { heldItem = item } }
            ) {
                Button { open(item) } label: { AlbumCard(item: item) }
                    .buttonStyle(PressableStyle())
            }
        }
    }

    // MARK: Bottom: search, or selection actions

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
        } else {
            HStack(spacing: 10) {
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
            .padding(.horizontal, 18)
            .frame(height: 48)
            .background(theme.surface.opacity(0.95), in: Capsule())
            .overlay { Capsule().strokeBorder(theme.text.opacity(0.06)) }
            .padding(.horizontal, 30)
            .padding(.bottom, 6)
            .background(alignment: .bottom) {
                LinearGradient(colors: [theme.background.opacity(0), theme.background], startPoint: .top, endPoint: .bottom)
                    .frame(height: 130)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: Actions

    private func open(_ item: SavedItem) {
        if LinkDestination(rawValue: openLinksIn) == .browser {
            browserLink = BrowserLink(url: item.url)
        } else {
            URLOpener.open(item)
        }
        if autoMarkListened && !item.isListened {
            // Let the app switch happen before the card moves to Heard.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { store.setListened(item, true) }
        }
    }

    private func toggle(_ item: SavedItem) {
        if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
        Haptics.impact(.light)
    }

    private func dismissMenu() {
        withAnimation(.easeOut(duration: 0.2)) { heldItem = nil }
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
            : "Press and hold an album for a moment, then flick it toward the lantern."
    }
}
