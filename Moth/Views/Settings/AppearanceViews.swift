import SwiftUI

struct ThemePickerView: View {
    @Environment(\.theme) private var theme
    @AppStorage(SettingsKey.theme, store: AppGroup.defaults) private var themeID = Theme.all[0].id

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(Theme.all) { option in
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) { themeID = option.id }
                        Haptics.impact(.light)
                    } label: {
                        ThemeSwatch(option: option, isSelected: option.id == theme.id)
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            .padding(20)
        }
        .background(theme.background.ignoresSafeArea())
        .navigationTitle("Theme")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The five icons: the glowing M is the primary icon, the rest are alternates
/// (asset catalog app icon sets named AppIcon-*).
struct AppIconOption: Identifiable {
    let iconName: String?
    let title: String
    let detail: String
    let preview: String
    var id: String { iconName ?? "primary" }

    static let all: [AppIconOption] = [
        AppIconOption(iconName: nil, title: "Glow", detail: "The original", preview: "IconPreview-Glow"),
        AppIconOption(iconName: "AppIcon-Outline", title: "Outline", detail: "Lit edges only", preview: "IconPreview-Outline"),
        AppIconOption(iconName: "AppIcon-Ring", title: "Ring", detail: "M inside a faint ring", preview: "IconPreview-Ring"),
        AppIconOption(iconName: "AppIcon-Illuminated", title: "Illuminated", detail: "Manuscript initial", preview: "IconPreview-Illuminated"),
        AppIconOption(iconName: "AppIcon-Wordmark", title: "Wordmark", detail: "Full name on parchment", preview: "IconPreview-Wordmark"),
    ]

    @MainActor static var current: AppIconOption {
        let name = UIApplication.shared.alternateIconName
        return all.first { $0.iconName == name } ?? all[0]
    }
}

struct AppIconPickerView: View {
    @Environment(\.theme) private var theme
    @State private var selected = AppIconOption.current.id
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(AppIconOption.all) { option in
                    Button { choose(option) } label: {
                        HStack(spacing: 14) {
                            Image(option.preview)
                                .resizable()
                                .frame(width: 60, height: 60)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.12)))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.title).foregroundStyle(theme.text)
                                Text(option.detail).font(.footnote).foregroundStyle(theme.secondaryText)
                            }
                            Spacer()
                            if option.id == selected {
                                Image(systemName: "checkmark").font(.headline).foregroundStyle(theme.accent)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if option.id != AppIconOption.all.last?.id {
                        Divider().overlay(theme.text.opacity(0.06)).padding(.leading, 88)
                    }
                }
            }
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(20)

            if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(.red.opacity(0.85)).padding(.horizontal, 24)
            }
        }
        .background(theme.background.ignoresSafeArea())
        .navigationTitle("App Icon")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func choose(_ option: AppIconOption) {
        guard option.id != selected else { return }
        Task { @MainActor in
            do {
                try await UIApplication.shared.setAlternateIconName(option.iconName)
                selected = option.id
                errorMessage = nil
            } catch {
                errorMessage = "Couldn't change the icon: \(error.localizedDescription)"
            }
        }
    }
}

struct ThemeSwatch: View {
    let option: Theme
    let isSelected: Bool
    @Environment(\.theme) private var current

    var body: some View {
        VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(option.background)
                .overlay {
                    if let backdrop = option.backdrop {
                        Image(backdrop).resizable().scaledToFill()
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
