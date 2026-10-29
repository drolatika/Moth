import UIKit

/// Artwork is downloaded once at save time and kept locally, so the library
/// still looks right offline or if a service changes its image URLs.
enum ArtworkStore {
    private static let cache = NSCache<NSString, UIImage>()

    static var directory: URL { AppGroup.containerURL.appendingPathComponent("Artwork", isDirectory: true) }

    static func save(_ data: Data, id: UUID) -> String? {
        guard let image = UIImage(data: data) else { return nil }
        guard let jpeg = downsample(image, maxSide: 800).jpegData(compressionQuality: 0.85) else { return nil }
        let name = "\(id.uuidString).jpg"
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try jpeg.write(to: directory.appendingPathComponent(name), options: .atomic)
            return name
        } catch {
            return nil
        }
    }

    static func image(named name: String) -> UIImage? {
        if let cached = cache.object(forKey: name as NSString) { return cached }
        guard let image = UIImage(contentsOfFile: directory.appendingPathComponent(name).path) else { return nil }
        cache.setObject(image, forKey: name as NSString)
        return image
    }

    static func delete(named name: String) {
        cache.removeObject(forKey: name as NSString)
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
    }

    private static func downsample(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let size = image.size
        let scale = min(1, maxSide / max(size.width, size.height))
        guard scale < 1 else { return image }
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
