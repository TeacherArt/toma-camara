import CoreGraphics
import CoreImage

/// Formatos de salida. Varios se pueden guardar a la vez desde la misma toma.
enum OutputFormat: String, CaseIterable, Identifiable {
    case original, feed, vertical, horizontal, square

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original: return "3:4"
        case .feed: return "4:5"
        case .vertical: return "9:16"
        case .horizontal: return "16:9"
        case .square: return "1:1"
        }
    }

    func aspect(for size: CGSize) -> CGFloat {
        switch self {
        case .original: return size.width / size.height
        case .feed: return 4.0 / 5.0
        case .vertical: return 9.0 / 16.0
        case .horizontal: return 16.0 / 9.0
        case .square: return 1
        }
    }
}

enum Framing {
    static func normalized(_ image: CIImage) -> CIImage {
        image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
    }

    /// Recorte centrado a la proporción pedida (ancho / alto).
    static func centerCrop(_ image: CIImage, aspect: CGFloat) -> CIImage {
        let e = image.extent
        let rect: CGRect
        if e.width / e.height > aspect {
            let w = (e.height * aspect).rounded(.down)
            rect = CGRect(x: (e.midX - w / 2).rounded(.down), y: e.minY, width: w, height: e.height)
        } else {
            let h = (e.width / aspect).rounded(.down)
            rect = CGRect(x: e.minX, y: (e.midY - h / 2).rounded(.down), width: e.width, height: h)
        }
        return normalized(image.cropped(to: rect))
    }

    static func scaled(_ image: CIImage, by scale: CGFloat) -> CIImage {
        guard abs(scale - 1) > 0.001 else { return image }
        let out = image.applyingFilter("CILanczosScaleTransform", parameters: [
            kCIInputScaleKey: scale,
            kCIInputAspectRatioKey: 1.0
        ])
        return normalized(out)
    }

    /// Recorta y escala para llenar exactamente `size`.
    static func fill(_ image: CIImage, to size: CGSize) -> CIImage {
        let cropped = centerCrop(image, aspect: size.width / size.height)
        let scale = size.width / cropped.extent.width
        return scaled(cropped, by: scale)
            .clampedToExtent()
            .cropped(to: CGRect(origin: .zero, size: size))
    }

    static func limit(_ image: CIImage, maxSide: CGFloat) -> CIImage {
        let longest = max(image.extent.width, image.extent.height)
        guard longest > maxSide else { return image }
        return scaled(image, by: maxSide / longest)
    }
}
