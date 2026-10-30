import SwiftUI

struct SettingsView: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(Connections.self) private var connections
    @AppStorage(SettingsKey.theme, store: AppGroup.defaults) private var themeID = Theme.all[0].id
    @AppStorage(SettingsKey.autoMarkListened, store: AppGroup.defaults) private var autoMarkHeard = false
    @AppStorage(SettingsKey.haptics, store: AppGroup.defaults) private var haptics = true
    @AppStorage(SettingsKey.openLinksIn, store: AppGroup.defaults) private var openLinksIn = LinkDestination.app.rawValue

    @State private var askingLastFMUser = false
    @State private var lastFMEntry = ""
    @State private var setupHelp: SetupHelp?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    profileCard

                    sectionHeader("Appearance")
                    group {
                        navRow("Theme", icon: "paintpalette.fill", tint: theme.accent, value: Theme.named(themeID).name) { ThemePickerView() }
                        divider
                        navRow("App Icon", icon: "app.badge.fill", tint: Color(hex: 0x2A2930), value: AppIconOption.current.title) { AppIconPickerView() }
                    }

                    sectionHeader("General")
                    group {
                        toggleRow("Mark heard when opened", icon: "checkmark", tint: Color(hex: 0x3A7D5C), isOn: $autoMarkHeard)
                        divider
                        pickerRow
                        divider
                        toggleRow("Haptics", icon: "waveform", tint: Color(hex: 0x7A4AB5), isOn: $haptics)
                    }

                    sectionHeader("Connections")
                    group {
                        spotifyRow
                        divider
                        appleMusicRow
                        divider
                        lastFMRow
                    }
                    if let message = connections.errorMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.red.opacity(0.85))
                            .padding(.horizontal, 6)
                            .padding(.top, 8)
                    }

                    sectionHeader("Listening")
                    group {
                        navRow("Listening Stats", icon: "chart.bar.fill", tint: theme.accent, value: nil) { StatsView() }
                    }

                    Text("Moth · Alighieri Softworks")
                        .font(MothFont.gothic(15))
                        .foregroundStyle(theme.secondaryText.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 28)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 30)
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
            .alert("Last.fm username", isPresented: $askingLastFMUser) {
                TextField("Username", text: $lastFMEntry)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Connect") { Task { await connections.connectLastFM(user: lastFMEntry) } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Moth reads your public scrobbles. No password needed.")
            }
            .sheet(item: $setupHelp) { help in SetupHelpView(help: help).themed(theme) }
        }
    }

    // MARK: Profile

    private var profileCard: some View {
        HStack(spacing: 14) {
            GildedInitial(letter: "M", size: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text("Your Profile").font(.headline).foregroundStyle(theme.text)
                Text("Accounts and sync are coming soon").font(.footnote).foregroundStyle(theme.secondaryText)
            }
            Spacer()
        }
        .padding(16)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.top, 8)
    }

    // MARK: Connections

    private var spotifyRow: some View {
        connectionRow("Spotify", badge: "S", tint: Color(hex: 0x1DB954)) {
            if !connections.spotifyConfigured {
                needsSetup(.spotify)
            } else if connections.spotifyConnected {
                connectedMenu { connections.disconnectSpotify() }
            } else {
                connectButton("Spotify") { Task { await connections.connectSpotify() } }
            }
        }
    }

    private var appleMusicRow: some View {
        connectionRow("Apple Music", badge: "♪", tint: Color(hex: 0xFA2D48)) {
            if connections.appleMusicAuthorized {
                Text("Connected").font(.subheadline).foregroundStyle(theme.secondaryText)
            } else {
                connectButton("Apple Music") { Task { await connections.connectAppleMusic() } }
            }
        }
    }

    private var lastFMRow: some View {
        connectionRow("Last.fm", badge: "fm", tint: Color(hex: 0xD51007)) {
            if !connections.lastFMConfigured {
                needsSetup(.lastFM)
            } else if let user = connections.lastFMUser {
                Menu {
                    Button("Disconnect", role: .destructive) { connections.disconnectLastFM() }
                } label: {
                    Text(user).font(.subheadline).foregroundStyle(theme.secondaryText)
                }
            } else {
                connectButton("Last.fm") {
                    lastFMEntry = ""
                    askingLastFMUser = true
                }
            }
        }
    }

    @ViewBuilder
    private func connectButton(_ service: String, action: @escaping () -> Void) -> some View {
        if connections.working == service {
            ProgressView()
        } else {
            Button("Connect", action: action)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.accent)
        }
    }

    private func connectedMenu(disconnect: @escaping () -> Void) -> some View {
        Menu {
            Button("Disconnect", role: .destructive, action: disconnect)
        } label: {
            Text("Connected").font(.subheadline).foregroundStyle(theme.secondaryText)
        }
    }

    private func needsSetup(_ help: SetupHelp) -> some View {
        Button("Needs setup") { setupHelp = help }
            .font(.footnote.weight(.medium))
            .foregroundStyle(theme.secondaryText)
    }

    // MARK: Rows

    private var pickerRow: some View {
        HStack(spacing: 12) {
            iconTile("arrow.up.forward.app", tint: Color(hex: 0x4A5FC1))
            Text("Open links in").foregroundStyle(theme.text)
            Spacer()
            Picker("Open links in", selection: $openLinksIn) {
                ForEach(LinkDestination.allCases) { Text($0.label).tag($0.rawValue) }
            }
            .labelsHidden()
            .tint(theme.secondaryText)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func navRow<Destination: View>(_ title: String, icon: String, tint: Color, value: String?,
                                           @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink {
            destination().themed(theme)
        } label: {
            HStack(spacing: 12) {
                iconTile(icon, tint: tint)
                Text(title).foregroundStyle(theme.text)
                Spacer()
                if let value { Text(value).foregroundStyle(theme.secondaryText) }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(theme.secondaryText.opacity(0.6))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func toggleRow(_ title: String, icon: String, tint: Color, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 12) {
                iconTile(icon, tint: tint)
                Text(title).foregroundStyle(theme.text)
            }
        }
        .tint(theme.accent)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private func connectionRow<Trailing: View>(_ title: String, badge: String, tint: Color,
                                               @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 12) {
            Text(badge)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(tint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(title).foregroundStyle(theme.text)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func iconTile(_ symbol: String, tint: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(tint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(0.8)
            .foregroundStyle(theme.secondaryText)
            .padding(.leading, 6)
            .padding(.top, 24)
            .padding(.bottom, 8)
    }

    private func group<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var divider: some View {
        Divider().overlay(theme.text.opacity(0.06)).padding(.leading, 56)
    }
}

/// Explains the one-time developer setup a connection needs.
enum SetupHelp: String, Identifiable {
    case spotify, lastFM
    var id: String { rawValue }

    var title: String { self == .spotify ? "Set up Spotify" : "Set up Last.fm" }

    var steps: [String] {
        switch self {
        case .spotify:
            [
                "Go to developer.spotify.com/dashboard, sign in and create an app.",
                "Add the redirect URI moth://spotify-callback and tick the iOS option.",
                "Under Users and Access, add the Spotify account you'll sign in with.",
                "Copy the Client ID into SPOTIFY_CLIENT_ID in project.yml, run xcodegen and rebuild.",
            ]
        case .lastFM:
            [
                "Go to last.fm/api/account/create and create an API account.",
                "Copy the API key into LASTFM_API_KEY in project.yml.",
                "Run xcodegen and rebuild, then connect with your Last.fm username.",
            ]
        }
    }
}

private struct SetupHelpView: View {
    let help: SetupHelp
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("This connection needs a free developer key first. It's a one-time step done by the app's developer.")
                    .font(.subheadline)
                    .foregroundStyle(theme.secondaryText)
                ForEach(Array(help.steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(index + 1)")
                            .font(.caption.weight(.bold))
                            .frame(width: 22, height: 22)
                            .foregroundStyle(theme.onAccent)
                            .background(theme.accent, in: Circle())
                        Text(step).foregroundStyle(theme.text)
                    }
                }
                Spacer()
            }
            .padding(22)
            .background(theme.background.ignoresSafeArea())
            .navigationTitle(help.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium])
    }
}
