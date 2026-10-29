import SwiftUI

struct SettingsView: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.theme, store: AppGroup.defaults) private var themeID = Theme.all[0].id
    @AppStorage(SettingsKey.autoMarkListened, store: AppGroup.defaults) private var autoMarkListened = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    section("Theme") {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(Theme.all) { option in
                                Button {
                                    withAnimation(.easeInOut(duration: 0.25)) { themeID = option.id }
                                } label: {
                                    ThemeSwatch(option: option, isSelected: option.id == theme.id)
                                }
                                .buttonStyle(PressableStyle())
                            }
                        }
                    }

                    section("Listening") {
                        Toggle(isOn: $autoMarkListened) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Mark as listened when opened")
                                    .foregroundStyle(theme.text)
                                Text("Moves an album to Listened as soon as you tap it.")
                                    .font(.footnote)
                                    .foregroundStyle(theme.secondaryText)
                            }
                        }
                        .padding(14)
                        .background(theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    section("Saving from other apps") {
                        VStack(alignment: .leading, spacing: 12) {
                            step(1, "Open an album, track or playlist in Spotify, Apple Music, Bandcamp, SoundCloud, YouTube Music, Tidal or Deezer.")
                            step(2, "Tap Share. In Spotify use “More”; in Apple Music it's in the ••• menu.")
                            step(3, "Pick Noll. If it's not there, scroll the app row to the end, tap More, and add it to Favorites.")
                        }
                        .padding(14)
                        .background(theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .padding(20)
            }
            .background(theme.background.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(theme.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(0.8)
                .foregroundStyle(theme.secondaryText)
            content()
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .frame(width: 20, height: 20)
                .foregroundStyle(theme.onAccent)
                .background(theme.accent, in: Circle())
            Text(text)
                .font(.subheadline)
                .foregroundStyle(theme.text)
        }
    }
}

private struct ThemeSwatch: View {
    let option: Theme
    let isSelected: Bool
    @Environment(\.theme) private var current

    var body: some View {
        VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(option.background)
                .frame(height: 88)
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 4).fill(option.accent).frame(width: 24, height: 24)
                            RoundedRectangle(cornerRadius: 4).fill(option.surface).frame(width: 24, height: 24)
                        }
                        Capsule().fill(option.text).frame(width: 40, height: 4)
                        Capsule().fill(option.secondaryText).frame(width: 28, height: 4)
                    }
                    .padding(11)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(isSelected ? current.accent : current.text.opacity(0.12), lineWidth: isSelected ? 2.5 : 1)
                }
                .overlay(alignment: .bottomTrailing) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(current.onAccent, current.accent)
                            .padding(7)
                    }
                }
            Text(option.name)
                .font(.caption.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? current.text : current.secondaryText)
        }
    }
}
