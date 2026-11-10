import SwiftUI

enum JournalFilter: String, CaseIterable, Identifiable {
    case diary, topRated, lowestRated, reviews, notes, artists

    var id: String { rawValue }
    var title: String {
        switch self {
        case .diary: "Diary"
        case .topRated: "Top Rated"
        case .lowestRated: "Lowest Rated"
        case .reviews: "Reviews"
        case .notes: "Notes"
        case .artists: "Most Listened Artists"
        }
    }
    var symbol: String {
        switch self {
        case .diary: "book.closed"
        case .topRated: "star.fill"
        case .lowestRated: "star.slash"
        case .reviews: "text.quote"
        case .notes: "note.text"
        case .artists: "person.2"
        }
    }
}

/// The diary of listens, and your ratings, reviews and notes, sorted and filtered.
/// Tap anything to rate or review it; hold for more.
struct JournalView: View {
    @State var filter: JournalFilter
    @Environment(JournalStore.self) private var journal
    @Environment(\.theme) private var theme
    @State private var reviewing: ReleaseRef?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                filterBar.padding(.bottom, 14)
                switch filter {
                case .diary: diary
                case .topRated: ranked(journal.topRated)
                case .lowestRated: ranked(journal.lowestRated)
                case .reviews: writing(journal.reviewed, text: \.review)
                case .notes: writing(journal.withNotes, text: \.notes)
                case .artists: artists
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 30)
        }
        .background(theme.background.ignoresSafeArea())
        .navigationTitle(filter.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(theme.background, for: .navigationBar)
        .sheet(item: $reviewing) { ref in
            ReviewSheet(ref: ref).environment(journal).themed(theme)
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(JournalFilter.allCases) { option in
                    Button {
                        withAnimation(.snappy) { filter = option }
                    } label: {
                        Text(option == .artists ? "Artists" : option.title)
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .foregroundStyle(filter == option ? theme.onAccent : theme.text)
                            .background(filter == option ? theme.accent : theme.surface, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollIndicators(.hidden)
        .padding(.top, 8)
    }

    // MARK: Diary

    @ViewBuilder
    private var diary: some View {
        if journal.log.isEmpty {
            empty("No listens yet. Marking an album heard logs it here, and so does saving a review with “Log a listen” on.")
        } else {
            let months = Dictionary(grouping: journal.log) { Calendar.current.dateInterval(of: .month, for: $0.date)?.start ?? $0.date }
            ForEach(months.keys.sorted(by: >), id: \.self) { month in
                Text(month, format: .dateTime.month(.wide).year())
                    .font(MothFont.gothic(22))
                    .foregroundStyle(theme.text)
                    .padding(.top, 10)
                    .padding(.bottom, 6)
                ForEach(months[month] ?? []) { entry in
                    diaryRow(entry)
                    rule
                }
            }
        }
    }

    private func diaryRow(_ entry: LogEntry) -> some View {
        Button { reviewing = entry.ref } label: {
            HStack(spacing: 12) {
                VStack(spacing: 0) {
                    Text(entry.date, format: .dateTime.day())
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .foregroundStyle(theme.text)
                    Text(entry.date, format: .dateTime.weekday(.abbreviated))
                        .font(.caption2)
                        .foregroundStyle(theme.secondaryText)
                }
                .frame(width: 34)
                ReleaseArtwork(ref: entry.ref, size: 46)
                releaseText(entry.ref)
                Spacer(minLength: 0)
                if journal.listens(for: entry.ref.key) > 1 {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.caption)
                        .foregroundStyle(theme.secondaryText)
                        .accessibilityLabel("Relisten")
                }
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            listenButton(entry.ref)
            Button(role: .destructive) { journal.delete(entry) } label: {
                Label("Delete from Diary", systemImage: "trash")
            }
        }
    }

    // MARK: Ratings

    @ViewBuilder
    private func ranked(_ records: [ReleaseRecord]) -> some View {
        if records.isEmpty {
            empty("Nothing rated yet. Open an album and tap the stars under its title.")
        } else {
            ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                Button { reviewing = record.ref } label: {
                    HStack(spacing: 12) {
                        Text("\(index + 1)")
                            .font(.callout.weight(.semibold).monospacedDigit())
                            .foregroundStyle(theme.secondaryText)
                            .frame(width: 28, alignment: .trailing)
                        ReleaseArtwork(ref: record.ref, size: 52)
                        releaseText(record.ref)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu { listenButton(record.ref) }
                rule
            }
        }
    }

    // MARK: Reviews and notes

    @ViewBuilder
    private func writing(_ records: [ReleaseRecord], text: KeyPath<ReleaseRecord, String?>) -> some View {
        if records.isEmpty {
            empty(filter == .notes
                  ? "No notes yet. Notes are private: favourite tracks, where you heard it, what to come back to."
                  : "No reviews yet. Open an album and tap “Rate & review”.")
        } else {
            ForEach(records) { record in
                Button { reviewing = record.ref } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            ReleaseArtwork(ref: record.ref, size: 52)
                            releaseText(record.ref)
                            Spacer(minLength: 0)
                        }
                        Text(record[keyPath: text] ?? "")
                            .font(.subheadline)
                            .italic(filter == .reviews)
                            .foregroundStyle(theme.text.opacity(0.9))
                            .multilineTextAlignment(.leading)
                            .lineLimit(8)
                        Text(record.updatedAt, format: .dateTime.day().month(.abbreviated).year())
                            .font(.caption2)
                            .foregroundStyle(theme.secondaryText)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu { listenButton(record.ref) }
                .padding(.bottom, 12)
            }
        }
    }

    // MARK: Artists

    @ViewBuilder
    private var artists: some View {
        let tallies = journal.topArtists
        if tallies.isEmpty {
            empty("Your most listened artists show up once you've logged some listens.")
        } else {
            ForEach(Array(tallies.enumerated()), id: \.element.id) { index, tally in
                HStack(spacing: 12) {
                    Text("\(index + 1)")
                        .font(.callout.weight(.semibold).monospacedDigit())
                        .foregroundStyle(theme.secondaryText)
                        .frame(width: 28, alignment: .trailing)
                    ReleaseArtwork(ref: tally.artwork, size: 46, cornerRadius: 23)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(tally.name).font(.subheadline.weight(.semibold)).foregroundStyle(theme.text)
                        HStack(spacing: 6) {
                            Text(tally.listens == 1 ? "1 listen" : "\(tally.listens) listens")
                                .font(.caption)
                                .foregroundStyle(theme.secondaryText)
                            if let average = tally.averageRating {
                                StarRating(rating: (average * 2).rounded() / 2, size: 9, spacing: 1)
                                Text("avg \(String(format: "%.1f", average))")
                                    .font(.caption2)
                                    .foregroundStyle(theme.secondaryText)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 8)
                rule
            }
        }
    }

    // MARK: Pieces

    private func releaseText(_ ref: ReleaseRef) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(ref.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.text)
                .lineLimit(1)
            if let artist = ref.artist {
                Text(artist).font(.caption).foregroundStyle(theme.secondaryText).lineLimit(1)
            }
            if let rating = journal.rating(for: ref.key) {
                StarRating(rating: rating, size: 10, spacing: 1)
            }
        }
    }

    private func listenButton(_ ref: ReleaseRef) -> some View {
        Button { URLOpener.open(ref.url, platform: ref.platform) } label: {
            Label("Listen in \(ref.platform.name)", systemImage: "play")
        }
    }

    private var rule: some View {
        Rectangle()
            .fill(theme.text.opacity(theme.isDark ? 0.08 : 0.1))
            .frame(height: 0.5)
    }

    private func empty(_ message: String) -> some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(theme.secondaryText)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            .padding(.top, 50)
            .padding(.horizontal, 20)
    }
}
