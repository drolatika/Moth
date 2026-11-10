import SwiftUI

/// Opens beneath an artist stack: every release in it, grouped by albums, EPs and
/// singles. Tap one to open it in its app, tap the circle to mark it heard, hold
/// for more (rate, review, remove).
struct ArtistStackPanel: View {
    let item: SavedItem
    let notchX: CGFloat
    var highlight: String = ""
    let onListen: (URL, _ album: SavedItem?) -> Void
    let onSelect: () -> Void
    let onRemove: () -> Void

    @Environment(ItemStore.self) private var store
    @Environment(JournalStore.self) private var journal
    @Environment(\.theme) private var theme
    @State private var reviewing: ReleaseRef?

    private var releases: [StackRelease] { item.stack ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            actionBar
            if releases.isEmpty {
                Text("This stack is empty.")
                    .font(.footnote)
                    .foregroundStyle(theme.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            ForEach(StackRelease.ReleaseType.allCases) { type in
                let group = releases.filter { $0.type == type }
                if !group.isEmpty {
                    if Set(releases.map(\.type)).count > 1 {
                        Text(type.pluralLabel)
                            .font(MothFont.gothic(19))
                            .foregroundStyle(theme.text)
                            .padding(.top, 12)
                            .padding(.bottom, 4)
                    }
                    ForEach(group) { release in
                        rule
                        row(release)
                    }
                    rule
                }
            }
            Text("\(item.heardTrackCount) of \(releases.count) heard")
                .font(.caption2)
                .foregroundStyle(theme.secondaryText.opacity(0.8))
                .padding(.top, 12)
        }
        .padding(.horizontal, 14)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .background { CutOpenBackground(notchX: notchX) }
        .sheet(item: $reviewing) { ref in
            ReviewSheet(ref: ref).environment(journal).themed(theme)
        }
    }

    private var actionBar: some View {
        HStack(spacing: 14) {
            Button { onListen(item.url, nil) } label: {
                Label("Open in \(item.platform.name)", systemImage: "arrow.up.forward")
            }
            .foregroundStyle(theme.accent)
            Spacer()
            Button { store.setListened(item, !item.isListened) } label: {
                Text(item.isListened ? "Move to Queue" : "Mark All Heard")
            }
            .foregroundStyle(theme.secondaryText)
            Menu {
                Button(action: onSelect) { Label("Select", systemImage: "checkmark.circle") }
                Button(role: .destructive, action: onRemove) { Label("Remove Stack", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(theme.secondaryText)
                    .frame(width: 28, height: 22)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Stack options")
        }
        .font(.footnote.weight(.semibold))
        .buttonStyle(.plain)
        .padding(.bottom, 10)
    }

    private var rule: some View {
        Rectangle()
            .fill(theme.text.opacity(theme.isDark ? 0.09 : 0.12))
            .frame(height: 0.5)
    }

    private func row(_ release: StackRelease) -> some View {
        let ref = ReleaseRef(release, in: item)
        let matches = !highlight.isEmpty && release.title.localizedCaseInsensitiveContains(highlight)
        return HStack(spacing: 12) {
            AsyncImage(url: release.artworkURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                item.platform.color.opacity(0.25)
            }
            .frame(width: 46, height: 46)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .opacity(release.isHeard ? 0.6 : 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(release.title)
                    .font(.subheadline.weight(matches ? .semibold : .regular))
                    .foregroundStyle(release.isHeard ? theme.secondaryText : matches ? theme.accent : theme.text)
                    .strikethrough(release.isHeard, pattern: .solid, color: theme.accent.opacity(0.75))
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text([release.year, release.type.label].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(theme.secondaryText.opacity(0.8))
                    if let rating = journal.rating(for: ref.key) {
                        StarRating(rating: rating, size: 9, spacing: 1)
                    }
                }
            }
            Spacer(minLength: 8)
            Button {
                Haptics.impact(.light)
                withAnimation(.snappy) { store.toggleReleaseHeard(release.id, in: item) }
            } label: {
                Image(systemName: release.isHeard ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(release.isHeard ? theme.accent : theme.secondaryText.opacity(0.6))
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(release.isHeard ? "Mark not heard" : "Mark heard")
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture { onListen(release.url, nil) }
        .contextMenu {
            Button { onListen(release.url, nil) } label: {
                Label("Listen in \(item.platform.name)", systemImage: "play")
            }
            Button { store.toggleReleaseHeard(release.id, in: item) } label: {
                release.isHeard
                    ? Label("Mark Not Heard", systemImage: "circle")
                    : Label("Mark Heard", systemImage: "checkmark.circle")
            }
            Button { reviewing = ref } label: { Label("Rate & Review", systemImage: "star") }
            Button(role: .destructive) {
                withAnimation(.snappy) { store.removeRelease(release.id, from: item) }
            } label: {
                Label("Remove from Stack", systemImage: "minus.circle")
            }
        }
    }
}
