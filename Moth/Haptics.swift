import UIKit

@MainActor
enum Haptics {
    static var isEnabled: Bool {
        AppGroup.defaults.object(forKey: SettingsKey.haptics) as? Bool ?? true
    }

    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        guard isEnabled else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    static func success() {
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
