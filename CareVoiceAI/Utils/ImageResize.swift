import UIKit

enum ImageResize {
    static func resizedJPEGData(from image: UIImage, maxDimension: CGFloat = 1600, compressionQuality: CGFloat = 0.82) -> Data? {
        let size = image.size
        let scale = min(1, maxDimension / max(size.width, size.height))
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return resized.jpegData(compressionQuality: compressionQuality)
    }
}
