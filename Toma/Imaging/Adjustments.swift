import CoreImage

/// Ajustes manuales del editor (como en la app Fotos).
struct Adjustments: Equatable {
    var exposure: Double = 0     // -2...2 EV
    var contrast: Double = 0     // -1...1
    var saturation: Double = 0   // -1...1
    var warmth: Double = 0       // -1...1
    var shadows: Double = 0      // 0...1
    var highlights: Double = 0   // 0...1

    /// `includeExposure` es falso cuando la exposición ya se aplicó al revelar el RAW.
    func apply(to image: CIImage, includeExposure: Bool = true) -> CIImage {
        let extent = image.extent
        var img = image
        if includeExposure, exposure != 0 {
            img = img.exposure(CGFloat(exposure))
        }
        if contrast != 0 || saturation != 0 {
            img = img.colorControls(saturation: 1 + CGFloat(saturation), contrast: 1 + CGFloat(contrast) * 0.5)
        }
        if warmth != 0 {
            img = img.warm(CGFloat(warmth) * 1500)
        }
        if shadows != 0 || highlights != 0 {
            img = img.shadowsHighlights(shadows: CGFloat(shadows), highlights: 1 - CGFloat(highlights) * 0.7)
        }
        return img.cropped(to: extent)
    }
}

enum AdjustmentKind: String, CaseIterable, Identifiable {
    case exposure, contrast, saturation, warmth, shadows, highlights

    var id: String { rawValue }

    var title: String {
        switch self {
        case .exposure: return "Exposición"
        case .contrast: return "Contraste"
        case .saturation: return "Saturación"
        case .warmth: return "Calidez"
        case .shadows: return "Sombras"
        case .highlights: return "Luces"
        }
    }

    var icon: String {
        switch self {
        case .exposure: return "plusminus.circle"
        case .contrast: return "circle.lefthalf.filled"
        case .saturation: return "drop.fill"
        case .warmth: return "thermometer.sun"
        case .shadows: return "moon.fill"
        case .highlights: return "sun.max.fill"
        }
    }

    var range: ClosedRange<Double> {
        switch self {
        case .exposure: return -2...2
        case .shadows, .highlights: return 0...1
        default: return -1...1
        }
    }

    var keyPath: WritableKeyPath<Adjustments, Double> {
        switch self {
        case .exposure: return \.exposure
        case .contrast: return \.contrast
        case .saturation: return \.saturation
        case .warmth: return \.warmth
        case .shadows: return \.shadows
        case .highlights: return \.highlights
        }
    }
}
