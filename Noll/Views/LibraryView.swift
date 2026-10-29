import SwiftUI

enum Shelf: String, CaseIterable, Identifiable {
    case queue, listened
    var id: String { rawValue }
    var title: String { self == .queue ? "Queue" : "Listened" }
}

struct LibraryView: View {
    @Environment(ItemStore.self) private var store
    @Environment(\.theme) private var theme
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(SettingsKey.autoMarkListened, store: AppGroup.defaults) private var autoMarkListened = false

    @State private var shelf: Shelf = .queue
    @State private var platformFilter: Platform?
    @State private var searchText = ""
    @State private var showingAdd = false
    @State private var showingSettings = false

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    private var shelfItems: [SavedItem] {
        store.items.filter { shelf == .queue ? !$0.isListened : $0.isListened }
    }

    private var visibleItems: [SavedItem] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return shelfItems.filter { item in
            (platformFilter == nil || item.platform == platformFilter)
                && (query.isEmpty
                    || item.title.localizedCaseInsensitiveContains(query)
                    || (item.artist?.localizedCaseInsensitiveContains(query) ?? false))
        }
    }

    private var platformsOnShelf: [Platform] {
        let present = Set(shelfItems.map(\.platform))
        return Platform.allCases.filter(present.contains)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ShelfSwitcher(
                        shelf: $shelf,
                        queueCount: store.items.filter { !$0.isListened }.count,
                        listenedCount: store.items.filter(\.isListened).count
                    )

                    if platformsOnShelf.count > 1 {
                        PlatformFilterBar(platforms: platformsOnShelf, selection: $platformFilter)
                    }

                    if visibleItems.isEmpty {
                        EmptyShelfView(shelf: shelf, isFiltering: !searchText.isEmpty || platformFilter != nil)
                            .padding(.top, 60)
                    } else {
                        LazyVGrid(columns: columns, spacing: 22) {
                            ForEach(visibleItems) { item in
                                Button { open(item) } label: { AlbumCard(item: item) }
                                    .buttonStyle(PressableStyle())
                                    .contextMenu { menu(for: item) }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
                .animation(.snappy, value: visibleItems.map(\.id))
            }
            .scrollDismissesKeyboard(.immediately)
            .background(theme.background.ignoresSafeArea())
            .navigationTitle("Noll")
            .toolbarBackground(theme.background, for: .navigationBar)
            .searchable(text: $searchText, prompt: "Search albums & artists")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingSettings = true } label: { Image(systemName: "paintpalette") }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if shelf == .listened && !shelfItems.isEmpty {
                        Menu {
                            Button(role: .destructive) { store.clearListened() } label: {
                                Label("Clear Listened", systemImage: "trash")
                            }
                        } label: { Image(systemName: "ellipsis.circle") }
                    }
                    Button { showingAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showingAdd) {
                AddLinkView().themed(theme)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView().themed(theme)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { store.reload() }
            }
            .onChange(of: shelf) { _, _ in platformFilter = nil }
        }
    }

    private func open(_ item: SavedItem) {
        URLOpener.open(item)
        if autoMarkListened && !item.isListened {
            // Let the app switch happen before the card animates away.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { store.setListened(item, true) }
        }
    }

    @ViewBuilder
    private func menu(for item: SavedItem) -> some View {
        Button { open(item) } label: {
            Label("Open in \(item.platform.name)", systemImage: "arrow.up.forward.app")
        }
        Button { store.toggleListened(item) } label: {
            item.isListened
                ? Label("Back to Queue", systemImage: "tray.and.arrow.up")
                : Label("Mark as Listened", systemImage: "checkmark.circle")
        }
        Button { UIPasteboard.general.url = item.url } label: {
            Label("Copy Link", systemImage: "link")
        }
        ShareLink(item: item.url) {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        Divider()
        Button(role: .destructive) { store.delete(item) } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}

struct AlbumCard: View {
    let item: SavedItem
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ArtworkView(item: item)
                .shadow(color: .black.opacity(theme.isDark ? 0.45 : 0.15), radius: 10, y: 6)
                .overlay(alignment: .topTrailing) {
                    if item.isListened {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(theme.onAccent, theme.accent)
                            .padding(6)
                    }
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let artist = item.artist {
                    Text(artist)
                        .font(.footnote)
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    PlatformBadge(platform: item.platform)
                    if item.kind != .other {
                        Text("· \(item.kind.label)")
                            .font(.caption2)
                            .foregroundStyle(theme.secondaryText.opacity(0.8))
                    }
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct ShelfSwitcher: View {
    @Binding var shelf: Shelf
    let queueCount: Int
    let listenedCount: Int
    @Environment(\.theme) private var theme
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Shelf.allCases) { option in
                Button {
                    withAnimation(.snappy) { shelf = option }
                } label: {
                    HStack(spacing: 6) {
                        Text(option.title)
                        Text("\(option == .queue ? queueCount : listenedCount)")
                            .monospacedDigit()
                            .opacity(0.6)
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .foregroundStyle(shelf == option ? theme.onAccent : theme.secondaryText)
                    .background {
                        if shelf == option {
                            Capsule().fill(theme.accent).matchedGeometryEffect(id: "pill", in: namespace)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(theme.surface, in: Capsule())
    }
}

private struct PlatformFilterBar: View {
    let platforms: [Platform]
    @Binding var selection: Platform?
    @Environment(\.theme) private var theme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "All", color: nil, isOn: selection == nil) { selection = nil }
                ForEach(platforms) { platform in
                    chip(title: platform.name, color: platform.color, isOn: selection == platform) {
                        selection = selection == platform ? nil : platform
                    }
                }
            }
        }
        .scrollClipDisabled()
    }

    private func chip(title: String, color: Color?, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy) { action() }
        } label: {
            HStack(spacing: 6) {
                if let color { Circle().fill(color).frame(width: 7, height: 7) }
                Text(title)
            }
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .foregroundStyle(isOn ? theme.background : theme.text)
            .background(isOn ? theme.text : theme.surface, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct EmptyShelfView: View {
    let shelf: Shelf
    let isFiltering: Bool
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: isFiltering ? "magnifyingglass" : (shelf == .queue ? "opticaldisc" : "checkmark.seal"))
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(theme.accent)
            Text(title)
                .font(.title3.weight(.semibold))
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
        if isFiltering { return "Nothing matches" }
        return shelf == .queue ? "Your queue is empty" : "Nothing listened yet"
    }

    private var message: String {
        if isFiltering { return "Try a different search or platform." }
        return shelf == .queue
            ? "In Spotify, Apple Music, Bandcamp or anywhere else, tap Share and pick Noll. The album lands here with its artwork."
            : "Long-press an album and choose Mark as Listened, or turn on auto-marking in settings."
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.snappy(duration: 0.2), value: configuration.isPressed)
    }
}
