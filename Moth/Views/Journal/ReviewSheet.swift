import SwiftUI

/// Rate (in half stars), review, keep private notes on, and log a listen of one release.
struct ReviewSheet: View {
    let ref: ReleaseRef
    @Environment(JournalStore.self) private var journal
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var rating: Double?
    @State private var review = ""
    @State private var notes = ""
    @State private var logListen = false
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    VStack(alignment: .leading, spacing: 8) {
                        label("Rating")
                        HStack {
                            StarRatingInput(rating: $rating, size: 34)
                            Spacer()
                            if let rating {
                                Text(StarRating.text(rating))
                                    .font(.title3.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(theme.accent)
                            }
                        }
                        Text("Tap or drag across the stars. Tap the same rating again to clear it.")
                            .font(.caption)
                            .foregroundStyle(theme.secondaryText.opacity(0.8))
                    }
                    field("Review", text: $review, prompt: "What did you make of it?")
                    field("Notes", text: $notes, prompt: "Private notes: favourite tracks, where you heard it, what to revisit…")
                    Toggle(isOn: $logListen) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Log a listen today").foregroundStyle(theme.text)
                            let count = journal.listens(for: ref.key)
                            if count > 0 {
                                Text(count == 1 ? "Logged once before" : "Logged \(count) times before")
                                    .font(.caption)
                                    .foregroundStyle(theme.secondaryText)
                            }
                        }
                    }
                    .tint(theme.accent)
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(theme.background.ignoresSafeArea())
            .navigationTitle("Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).fontWeight(.semibold)
                }
            }
            .onAppear(perform: load)
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            ReleaseArtwork(ref: ref, size: 72)
            VStack(alignment: .leading, spacing: 3) {
                Text(ref.title).font(.headline).foregroundStyle(theme.text).lineLimit(2)
                if let artist = ref.artist {
                    Text(artist).font(.subheadline).foregroundStyle(theme.secondaryText)
                }
                PlatformBadge(platform: ref.platform, seed: ref.key.hashValue)
            }
        }
    }

    private func label(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(0.8)
            .foregroundStyle(theme.secondaryText)
    }

    private func field(_ title: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            label(title)
            TextField(prompt, text: text, axis: .vertical)
                .lineLimit(4...12)
                .padding(14)
                .foregroundStyle(theme.text)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        let record = journal.record(for: ref.key)
        rating = record?.rating
        review = record?.review ?? ""
        notes = record?.notes ?? ""
        let lastListen = journal.log.first { $0.ref.key == ref.key }?.date
        logListen = lastListen.map { Date().timeIntervalSince($0) > 86_400 } ?? true
    }

    private func save() {
        journal.save(ref, rating: rating, review: review, notes: notes)
        if logListen { journal.logListen(ref) }
        Haptics.success()
        dismiss()
    }
}

/// Five stars in half steps; drag or tap to set.
struct StarRatingInput: View {
    @Binding var rating: Double?
    var size: CGFloat = 30
    /// The rating before this touch, so tapping it again can clear it.
    @State private var previous: Double?

    var body: some View {
        let spacing = size * 0.18
        StarRating(rating: rating ?? 0, size: size, spacing: spacing, emptyOpacity: 0.35)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let next = Self.value(at: value.location.x, size: size, spacing: spacing)
                        if next != rating {
                            rating = next
                            Haptics.impact(.light)
                        }
                    }
                    .onEnded { value in
                        // A tap on the current rating clears it.
                        if abs(value.translation.width) < 4,
                           Self.value(at: value.location.x, size: size, spacing: spacing) == previous {
                            rating = nil
                        }
                        previous = rating
                    }
            )
            .onAppear { previous = rating }
            .accessibilityElement()
            .accessibilityLabel("Rating")
            .accessibilityValue(rating.map { StarRating.text($0) + " stars" } ?? "None")
            .accessibilityAdjustableAction { direction in
                let current = rating ?? 0
                switch direction {
                case .increment: rating = min(5, current + 0.5)
                case .decrement: rating = current <= 0.5 ? nil : current - 0.5
                @unknown default: break
                }
            }
    }

    private static func value(at x: CGFloat, size: CGFloat, spacing: CGFloat) -> Double {
        let step = size + spacing
        let star = floor(x / step)
        let within = x - star * step
        let half = within < size / 2 ? 0.5 : 1
        return min(5, max(0.5, Double(star) + half))
    }
}

/// Read-only stars, with half stars.
struct StarRating: View {
    let rating: Double
    var size: CGFloat = 11
    var spacing: CGFloat = 1.5
    var emptyOpacity: Double = 0.25
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(1...5, id: \.self) { index in
                let value = Double(index)
                Image(systemName: rating >= value ? "star.fill" : rating >= value - 0.5 ? "star.leadinghalf.filled" : "star")
                    .font(.system(size: size, weight: .semibold))
                    .foregroundStyle(theme.accent.opacity(rating >= value - 0.5 ? 1 : emptyOpacity))
                    .frame(width: size, height: size)
            }
        }
    }

    /// "3.5", "4".
    static func text(_ rating: Double) -> String {
        rating.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(rating)) : String(format: "%.1f", rating)
    }
}

/// A release's cover, from the library's saved copy or its link.
struct ReleaseArtwork: View {
    let ref: ReleaseRef
    var size: CGFloat = 48
    var cornerRadius: CGFloat = 6

    var body: some View {
        Group {
            if let file = ref.artworkFile, let image = ArtworkStore.image(named: file) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                AsyncImage(url: ref.artworkURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    ZStack {
                        ref.platform.color.opacity(0.35)
                        Image(systemName: "music.note").foregroundStyle(.white.opacity(0.8))
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
