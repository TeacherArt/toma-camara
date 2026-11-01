import CoreGraphics
import CoreImage
import Foundation

/// Estilos de color. Se aplican en vivo en la vista previa, al grabar y al revelar la foto.
enum LookStyle: String, CaseIterable, Identifiable {
    case natural, film, g7x, glow, dusk, harbor, noche, relic, mono, plano

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
        case .plano: return "PLANO"
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
            // Compacta Canon con flash: cielos azul profundo, piel cálida, mucho contraste y nitidez.
            img = img
                .warm(250)
                .colorCube(ColorLUT.g7x)
                .vibrance(0.18)
                .curve([(0, 0.0), (0.18, 0.15), (0.5, 0.53), (0.82, 0.88), (1, 1)])
                .sharpenLuminance(0.45)
                .bloom(0.1, unit: unit)
                .vignette(0.3)

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

        case .plano:
            // Video plano: sombras levantadas y luces suaves para editar después.
            img = img
                .curve([(0, 0.07), (0.25, 0.29), (0.5, 0.5), (0.75, 0.71), (1, 0.93)])
                .colorControls(saturation: 0.86)
        }
        return img.cropped(to: extent)
    }
}

// MARK: - Tabla de color (LUT)

/// Tabla 3D que cambia colores por tono: así se imita la "ciencia de color" de una cámara.
struct ColorLUT {
    let dimension: Int
    let data: Data

    /// Canon compacta: azules y cian más profundos, piel y rojos cálidos, verdes contenidos.
    static let g7x = ColorLUT.make(dimension: 33, transform: ColorLUT.g7xTransform)

    static func make(dimension n: Int, transform: (Float, Float, Float) -> (Float, Float, Float)) -> ColorLUT {
        var cube = [Float](repeating: 0, count: n * n * n * 4)
        var i = 0
        let step = Float(n - 1)
        for bi in 0..<n {
            for gi in 0..<n {
                for ri in 0..<n {
                    let out = transform(Float(ri) / step, Float(gi) / step, Float(bi) / step)
                    cube[i] = out.0
                    cube[i + 1] = out.1
                    cube[i + 2] = out.2
                    cube[i + 3] = 1
                    i += 4
                }
            }
        }
        let data = cube.withUnsafeBufferPointer { Data(buffer: $0) }
        return ColorLUT(dimension: n, data: data)
    }

    static func g7xTransform(_ r: Float, _ g: Float, _ b: Float) -> (Float, Float, Float) {
        let hsv = rgbToHsv(r, g, b)
        let hue = hsv.0
        var s = hsv.1
        var v = hsv.2

        func band(_ center: Float, _ width: Float) -> Float {
            var d = abs(hue - center)
            if d > 180 { d = 360 - d }
            return max(0, 1 - d / width)
        }
        let blue = band(218, 38)
        let cyan = band(188, 22)
        let skin = band(24, 22)
        let red = band(358, 18)
        let green = band(110, 45)

        let originalSat = s
        s *= 1 + 0.30 * blue + 0.16 * cyan + 0.08 * skin + 0.06 * red - 0.10 * green
        v *= 1 - 0.12 * blue * originalSat
        var h = hue + 5 * band(8, 16) - 7 * green
        if h < 0 { h += 360 }
        if h >= 360 { h -= 360 }
        s = min(max(s, 0), 1)
        v = min(max(v, 0), 1)
        return hsvToRgb(h, s, v)
    }

    static func rgbToHsv(_ r: Float, _ g: Float, _ b: Float) -> (Float, Float, Float) {
        let maxV = max(r, max(g, b))
        let minV = min(r, min(g, b))
        let d = maxV - minV
        var h: Float = 0
        if d > 1e-6 {
            if maxV == r {
                h = 60 * fmodf((g - b) / d, 6)
            } else if maxV == g {
                h = 60 * ((b - r) / d + 2)
            } else {
                h = 60 * ((r - g) / d + 4)
            }
        }
        if h < 0 { h += 360 }
        let s: Float = maxV <= 1e-6 ? 0 : d / maxV
        return (h, s, maxV)
    }

    static func hsvToRgb(_ h: Float, _ s: Float, _ v: Float) -> (Float, Float, Float) {
        let c = v * s
        let hp = fmodf(h / 60, 6)
        let x = c * (1 - abs(fmodf(hp, 2) - 1))
        var rgb: (Float, Float, Float)
        if hp < 1 {
            rgb = (c, x, 0)
        } else if hp < 2 {
            rgb = (x, c, 0)
        } else if hp < 3 {
            rgb = (0, c, x)
        } else if hp < 4 {
            rgb = (0, x, c)
        } else if hp < 5 {
            rgb = (x, 0, c)
        } else {
            rgb = (c, 0, x)
        }
        let m = v - c
        return (rgb.0 + m, rgb.1 + m, rgb.2 + m)
    }
}

// MARK: - Bloques de color

extension CIImage {
    func colorCube(_ lut: ColorLUT) -> CIImage {
        applyingFilter("CIColorCubeWithColorSpace", parameters: [
            "inputCubeDimension": lut.dimension,
            "inputCubeData": lut.data,
            "inputColorSpace": CGColorSpace(name: CGColorSpace.sRGB) as Any
        ])
    }

    func sharpenLuminance(_ amount: CGFloat) -> CIImage {
        applyingFilter("CISharpenLuminance", parameters: [kCIInputSharpnessKey: amount])
    }

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
