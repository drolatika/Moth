import SwiftUI
import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private let model = ShareModel()

    override func viewDidLoad() {
        super.viewDidLoad()

        let theme = Theme.named(AppGroup.defaults.string(forKey: SettingsKey.theme) ?? "")
        let root = ShareView(model: model) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
        .themed(theme)

        let host = UIHostingController(rootView: root)
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        host.didMove(toParent: self)

        let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        Task { await model.run(with: items) }
    }
}

@MainActor
@Observable
final class ShareModel {
    enum Phase {
        case working(host: String?)
        case saved(SavedItem, duplicate: Bool)
        case failed(String)
    }

    var phase: Phase = .working(host: nil)

    func run(with items: [NSExtensionItem]) async {
        guard let url = await Self.firstURL(in: items) else {
            phase = .failed("Couldn't find a link in what was shared.")
            return
        }
        phase = .working(host: url.host)
        let result = await LibrarySaver.save(url)
        withAnimation(.snappy) {
            phase = .saved(result.item, duplicate: result.duplicate)
        }
    }

    /// Music apps share either a URL attachment, plain text containing a link, or both.
    private static func firstURL(in items: [NSExtensionItem]) async -> URL? {
        for item in items {
            for provider in item.attachments ?? [] where provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                guard let value = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) else { continue }
                if let url = value as? URL, url.scheme?.hasPrefix("http") == true { return url }
                if let data = value as? Data, let url = URL(dataRepresentation: data, relativeTo: nil),
                   url.scheme?.hasPrefix("http") == true { return url }
            }
            for provider in item.attachments ?? [] where provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                guard let value = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) else { continue }
                let text = (value as? String) ?? (value as? Data).map { String(decoding: $0, as: UTF8.self) } ?? ""
                if let url = LinkCleaner.firstURL(in: text) { return url }
            }
            if let text = item.attributedContentText?.string, let url = LinkCleaner.firstURL(in: text) {
                return url
            }
        }
        return nil
    }
}
