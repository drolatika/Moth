import SwiftUI

struct ShareView: View {
    let model: ShareModel
    let done: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Moth")
                    .font(.headline)
                    .foregroundStyle(theme.text)
                Spacer()
                Button("Done", action: done)
                    .fontWeight(.semibold)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Spacer(minLength: 12)
            content
                .padding(.horizontal, 32)
            Spacer(minLength: 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.background.ignoresSafeArea())
        .task(id: isSaved) {
            guard isSaved else { return }
            try? await Task.sleep(for: .seconds(1.6))
            done()
        }
    }

    private var isSaved: Bool {
        if case .saved = model.phase { return true }
        return false
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .working(let host):
            VStack(spacing: 16) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(theme.surface)
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: 240)
                    .overlay { ProgressView().controlSize(.large) }
                Text("Grabbing artwork…")
                    .font(.headline)
                    .foregroundStyle(theme.text)
                if let host {
                    Text(host).font(.footnote).foregroundStyle(theme.secondaryText)
                }
            }

        case .saved(let item, let duplicate):
            VStack(spacing: 14) {
                ArtworkView(item: item, cornerRadius: 14)
                    .frame(maxWidth: 240)
                    .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
                VStack(spacing: 4) {
                    Text(item.title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(theme.text)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                    if let artist = item.artist {
                        Text(artist).font(.subheadline).foregroundStyle(theme.secondaryText)
                    }
                }
                Label(duplicate ? "Already saved — moved to the top" : "Saved to your queue",
                      systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.accent)
                    .padding(.top, 4)
            }
            .transition(.scale(scale: 0.92).combined(with: .opacity))

        case .failed(let message):
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 40))
                    .foregroundStyle(theme.accent)
                Text(message)
                    .font(.headline)
                    .foregroundStyle(theme.text)
                    .multilineTextAlignment(.center)
            }
        }
    }
}
