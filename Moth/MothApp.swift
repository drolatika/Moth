import SwiftUI

@main
struct MothApp: App {
    @State private var store = ItemStore()
    @State private var connections = Connections()
    @State private var trackIndex = TrackIndex()
    @State private var profile = ProfileStore()
    @AppStorage(SettingsKey.theme, store: AppGroup.defaults) private var themeID = Theme.all[0].id

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environment(store)
                .environment(store.journal)
                .environment(connections)
                .environment(trackIndex)
                .environment(profile)
                .themed(Theme.named(themeID))
        }
    }
}
