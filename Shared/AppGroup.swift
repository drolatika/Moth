import Foundation

/// The App Group shared by the app and the share extension. The identifier is
/// injected into both Info.plists from the APP_GROUP_ID build setting.
enum AppGroup {
    static let id: String =
        Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String ?? "group.com.ryanschlecht.moth"

    static var containerURL: URL {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) {
            return url
        }
        // Fallback keeps the app usable (without the extension) if the group isn't provisioned.
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    static let defaults: UserDefaults = UserDefaults(suiteName: id) ?? .standard
}

enum SettingsKey {
    static let theme = "themeID"
    static let autoMarkListened = "autoMarkListened"
    static let haptics = "haptics"
    static let openLinksIn = "openLinksIn"
    static let lastFMUser = "lastFMUser"
    static let libraryLayout = "libraryLayout"
    static let libraryGrouping = "libraryGrouping"
}
