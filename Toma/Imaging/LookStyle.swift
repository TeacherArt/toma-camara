import CoreGraphics
import CoreImage

/// Estilos de color. Se aplican en vivo en la vista previa, al grabar y al revelar la foto.
enum LookStyle: String, CaseIterable, Identifiable {
    case natural, film, g7x, glow, dusk, harbor, noche, relic, mono

    var id: String { rawValue }

    var title: String {
        switch self {
        case .natural: return "NATURAL"
        case .film: return "FILM 35"
        case .g7x: return "G7X"
        case .glow: return "SUAVE"
        case .dusk: return "DUSK"
        case .harbor: return "HARBOR"
        case .noche: return "NOCHE"
        case .relic: return "RELIC"
        case .mono: return "B/N"
        }
    }

    /// `grainOffset` mueve el grano de un cuadro a otro para que en video no se vea fijo.
    func apply(to input: CIImage, grainOffset: CGPoint = .zero) -> CIImage {
        let extent = input.extent
        let unit = max(extent.width, extent.height) / 1920
        var img = input

        switch self {
        case .natural:
            img = img
                .vibrance(0.12)
                .curve([(0, 0.01), (0.25, 0.24), (0.5, 0.5), (0.75, 0.77), (1, 0.99)])

        case .film:
            // Película cálida y saturada, sombras profundas (referencias tipo Portra/Gold).
            img = img
                .warm(900)
                .colorControls(saturation: 1.12, contrast: 1.06)
                .curve([(0, 0.03), (0.25, 0.21), (0.5, 0.5), (0.75, 0.79), (1, 0.97)])
                .splitTone(cool: 0.03, warm: 0.04)
                .vignette(0.45)
                .grain(0.07, unit: unit, offset: grainOffset)

        case .g7x:
            // Compacta Canon: cálida, piel suave, brillo ligero en altas luces.
            img = img
                .warm(450)
                .channelScale(r: 1.02, g: 0.985, b: 1.0)
                .shadowsHighlights(shadows: 0.2, highlights: 0.9)
                .colorControls(saturation: 1.08, brightness: 0.015, contrast: 1.0)
                .curve([(0, 0.02), (0.25, 0.255), (0.5, 0.52), (0.75, 0.78), (1, 0.98)])
                .bloom(0.18, unit: unit)

        case .glow:
            // Retrato y selfie: luz suave y piel luminosa.
            img = img
                .warm(300)
                .shadowsHighlights(shadows: 0.25, highlights: 0.95)
                .colorControls(saturation: 1.04, brightness: 0.02, contrast: 0.97)
                .bloom(0.35, unit: unit)

        case .dusk:
            // Sombras frías, luces cálidas.
            img = img
                .warm(200)
                .splitTone(cool: 0.07, warm: 0.06)
                .colorControls(saturation: 1.06, contrast: 1.06)
                .curve([(0, 0.02), (0.25, 0.22), (0.5, 0.5), (0.75, 0.78), (1, 0.98)])
                .vignette(0.3)

        case .harbor:
            // Azules limpios y nítidos.
            img = img
                .warm(-600)
                .vibrance(0.25)
                .colorControls(saturation: 1.0, contrast: 1.1)
                .curve([(0, 0), (0.25, 0.22), (0.5, 0.5), (0.75, 0.79), (1, 1)])

        case .noche:
            // Oscuro y cálido (café, restaurante de noche).
            img = img
                .exposure(-0.3)
                .curve([(0, 0), (0.2, 0.1), (0.5, 0.44), (0.8, 0.82), (1, 1)])
                .warm(600)
                .colorControls(saturation: 0.92, contrast: 1.05)
                .vignette(0.9, radius: 1.0)
                .grain(0.05, unit: unit, offset: grainOffset)

        case .relic:
            // Vintage deslavado.
            img = img
                .curve([(0, 0.1), (0.25, 0.3), (0.5, 0.53), (0.75, 0.76), (1, 0.93)])
                .colorControls(saturation: 0.72)
                .warm(700)
                .sepia(0.18)
                .vignette(0.5)
                .grain(0.09, unit: unit, offset: grainOffset)

        case .mono:
            img = img
                .colorControls(saturation: 0, contrast: 1.15)
                .curve([(0, 0.02), (0.25, 0.22), (0.5, 0.5), (0.75, 0.8), (1, 0.98)])
                .grain(0.06, unit: unit, offset: grainOffset)
        }
        return img.cropped(to: extent)
    }
}

// MARK: - Bloques de color

extension CIImage {
    /// Positivo = más cálido, negativo = más frío.
    func warm(_ amount: CGFloat) -> CIImage {
        applyingFilter("CITemperatureAndTint", parameters: [
            "inputNeutral": CIVector(x: 6500 + amount, y: 0),
            "inputTargetNeutral": CIVector(x: 6500, y: 0)
        ])
    }

    func colorControls(saturation: CGFloat = 1, brightness: CGFloat = 0, contrast: CGFloat = 1) -> CIImage {
        applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: saturation,
            kCIInputBrightnessKey: brightness,
            kCIInputContrastKey: contrast
        ])
    }

    func vibrance(_ amount: CGFloat) -> CIImage {
        applyingFilter("CIVibrance", parameters: ["inputAmount": amount])
    }

    func exposure(_ ev: CGFloat) -> CIImage {
        applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: ev])
    }

    func sepia(_ intensity: CGFloat) -> CIImage {
        applyingFilter("CISepiaTone", parameters: [kCIInputIntensityKey: intensity])
    }

    func curve(_ points: [(CGFloat, CGFloat)]) -> CIImage {
        var params: [String: Any] = [:]
        for (index, point) in points.prefix(5).enumerated() {
            params["inputPoint\(index)"] = CIVector(x: point.0, y: point.1)
        }
        return applyingFilter("CIToneCurve", parameters: params)
    }

    func channelScale(r: CGFloat, g: CGFloat, b: CGFloat,
                      bias: (CGFloat, CGFloat, CGFloat) = (0, 0, 0)) -> CIImage {
        applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: r, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: g, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: b, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: bias.0, y: bias.1, z: bias.2, w: 0)
        ])
    }

    func shadowsHighlights(shadows: CGFloat, highlights: CGFloat) -> CIImage {
        applyingFilter("CIHighlightShadowAdjust", parameters: [
            "inputShadowAmount": shadows,
            "inputHighlightAmount": highlights
        ])
    }

    func vignette(_ intensity: CGFloat, radius: CGFloat = 1.2) -> CIImage {
        applyingFilter("CIVignette", parameters: [
            kCIInputIntensityKey: intensity,
            kCIInputRadiusKey: radius
        ])
    }

    func bloom(_ intensity: CGFloat, unit: CGFloat) -> CIImage {
        let original = extent
        return clampedToExtent()
            .applyingFilter("CIBloom", parameters: [
                kCIInputIntensityKey: intensity,
                kCIInputRadiusKey: 10 * unit
            ])
            .cropped(to: original)
    }

    /// Sombras hacia el azul y luces hacia el ámbar.
    func splitTone(cool: CGFloat, warm: CGFloat) -> CIImage {
        let original = extent
        let mask = colorControls(saturation: 0, contrast: 1.1)
        let warmVersion = channelScale(r: 1 + warm, g: 1 + warm * 0.3, b: 1 - warm)
        let coolVersion = channelScale(r: 1 - cool, g: 1, b: 1 + cool, bias: (0, 0.005, cool * 0.15))
        return warmVersion
            .applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: coolVersion,
                kCIInputMaskImageKey: mask
            ])
            .cropped(to: original)
    }

    /// Grano de película con tamaño proporcional a la imagen.
    func grain(_ amount: CGFloat, unit: CGFloat, offset: CGPoint = .zero) -> CIImage {
        guard amount > 0, let noise = CIFilter(name: "CIRandomGenerator")?.outputImage else { return self }
        let original = extent
        let size = max(1, unit * 1.2)
        let base = 0.5 - amount / 2
        let gray = noise
            .transformed(by: CGAffineTransform(translationX: offset.x, y: offset.y))
            .transformed(by: CGAffineTransform(scaleX: size, y: size))
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: amount, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: amount, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: amount, y: 0, z: 0, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBiasVector": CIVector(x: base, y: base, z: base, w: 1)
            ])
            .cropped(to: original)
        return gray
            .applyingFilter("CISoftLightBlendMode", parameters: [kCIInputBackgroundImageKey: self])
            .cropped(to: original)
    }
}
