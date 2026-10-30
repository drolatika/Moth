import SwiftUI

@main
struct MothApp: App {
    @State private var store = ItemStore()
    @AppStorage(SettingsKey.theme, store: AppGroup.defaults) private var themeID = Theme.all[0].id

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environment(store)
                .themed(Theme.named(themeID))
        }
    }
}
