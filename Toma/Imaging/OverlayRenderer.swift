import CoreImage
import UIKit

/// Convierte stickers, textos y la marca en imágenes, con contorno blanco o de acrílico.
enum OverlayRenderer {
    private static let ciContext = CIContext(options: [.cacheIntermediates: false])
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 40
        return cache
    }()

    static func image(for overlay: EditorOverlay) -> UIImage? {
        let key = overlay.cacheKey as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let base = baseImage(for: overlay.content) else { return nil }
        let result = bordered(base, border: overlay.border)
        cache.setObject(result, forKey: key)
        return result
    }

    static func baseImage(for content: OverlayContent) -> UIImage? {
        switch content {
        case .sticker(let name):
            return UIImage(named: name)
        case .silhouette(let name, let color):
            return UIImage(named: name).map { tinted($0, color) }
        case .text(let spec):
            return TextRenderer.render(spec)
        case .mark(let spec):
            return markImage(spec)
        }
    }

    static func renderer(_ size: CGSize, opaque: Bool = false) -> UIGraphicsImageRenderer {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = opaque
        return UIGraphicsImageRenderer(size: size, format: format)
    }

    static func tinted(_ image: UIImage, _ color: UIColor) -> UIImage {
        let size = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        return renderer(size).image { ctx in
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size), blendMode: .destinationIn, alpha: 1)
        }
    }

    // MARK: Contornos

    static func bordered(_ image: UIImage, border: OverlayBorder) -> UIImage {
        guard border != .none, let cg = image.cgImage else { return image }
        let w = CGFloat(cg.width)
        let h = CGFloat(cg.height)
        let r = (max(w, h) * (border == .white ? 0.022 : 0.034)).rounded()
        let pad = r + max(w, h) * 0.03
        let canvas = CGRect(x: 0, y: 0, width: (w + 2 * pad).rounded(), height: (h + 2 * pad).rounded())

        let clear = CIImage(color: .clear).cropped(to: canvas)
        let placed = CIImage(cgImage: cg)
            .transformed(by: CGAffineTransform(translationX: pad, y: pad))
            .composited(over: clear)

        func solid(_ color: CIColor, maskedBy mask: CIImage) -> CIImage {
            CIImage(color: color).cropped(to: canvas)
                .applyingFilter("CIBlendWithAlphaMask", parameters: [
                    kCIInputBackgroundImageKey: clear,
                    kCIInputMaskImageKey: mask
                ])
        }

        let shape = solid(CIColor(red: 1, green: 1, blue: 1, alpha: 1), maskedBy: placed)
        let grown = shape
            .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: r])
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 1.2])
            .cropped(to: canvas)

        let shadow = solid(CIColor(red: 0, green: 0, blue: 0, alpha: border == .white ? 0.32 : 0.22), maskedBy: grown)
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: r * 0.45])
            .transformed(by: CGAffineTransform(translationX: 0, y: -r * 0.3))
            .cropped(to: canvas)

        var result: CIImage
        if border == .white {
            result = grown.composited(over: shadow)
        } else {
            let body = solid(CIColor(red: 1, green: 1, blue: 1, alpha: 0.26), maskedBy: grown)
            let inner = grown.applyingFilter("CIMorphologyMinimum", parameters: [kCIInputRadiusKey: max(2, r * 0.12)])
            let rimMask = grown.applyingFilter("CISourceOutCompositing", parameters: [kCIInputBackgroundImageKey: inner])
            let rim = solid(CIColor(red: 1, green: 1, blue: 1, alpha: 0.9), maskedBy: rimMask)
            var layers = body.composited(over: shadow)
            if let gradient = CIFilter(name: "CILinearGradient", parameters: [
                "inputPoint0": CIVector(x: 0, y: canvas.height),
                "inputPoint1": CIVector(x: canvas.width * 0.55, y: canvas.height * 0.45),
                "inputColor0": CIColor(red: 1, green: 1, blue: 1, alpha: 0.4),
                "inputColor1": CIColor(red: 1, green: 1, blue: 1, alpha: 0)
            ])?.outputImage?.cropped(to: canvas) {
                let shine = gradient.applyingFilter("CIBlendWithAlphaMask", parameters: [
                    kCIInputBackgroundImageKey: clear,
                    kCIInputMaskImageKey: grown
                ])
                layers = shine.composited(over: layers)
            }
            result = rim.composited(over: layers)
        }
        result = placed.composited(over: result)

        guard let out = ciContext.createCGImage(result, from: canvas) else { return image }
        return UIImage(cgImage: out)
    }

    // MARK: Marca tipo Garmin

    static func markImage(_ spec: MarkSpec) -> UIImage? {
        guard let silhouette = UIImage(named: spec.silhouette) else { return nil }
        let icon = tinted(silhouette, spec.color)
        let iconH: CGFloat = 260
        let iconW = iconH * icon.size.width / max(icon.size.height, 1)
        let titleFont = UIFont(name: "AvenirNext-Heavy", size: 118) ?? .systemFont(ofSize: 118, weight: .heavy)
        let subFont = UIFont(name: "AvenirNext-DemiBold", size: 50) ?? .systemFont(ofSize: 50, weight: .semibold)
        let shadow = NSShadow()
        shadow.shadowColor = (spec.color.isLight ? UIColor.black : UIColor.white).withAlphaComponent(0.25)
        shadow.shadowBlurRadius = 8
        shadow.shadowOffset = .zero

        let title = NSAttributedString(string: spec.title, attributes: [
            .font: titleFont, .foregroundColor: spec.color, .kern: 14, .shadow: shadow
        ])
        let sub = NSAttributedString(string: spec.subtitle.uppercased(), attributes: [
            .font: subFont, .foregroundColor: spec.color.withAlphaComponent(0.92), .kern: 5, .shadow: shadow
        ])
        let titleSize = title.size()
        let subSize = spec.subtitle.isEmpty ? .zero : sub.size()
        let gap: CGFloat = 34
        let textW = max(titleSize.width, subSize.width)
        let textH = titleSize.height + (subSize.height > 0 ? subSize.height + 2 : 0)
        let size = CGSize(width: (iconW + gap + textW + 12).rounded(), height: (max(iconH, textH) + 12).rounded())

        return renderer(size).image { _ in
            icon.draw(in: CGRect(x: 4, y: (size.height - iconH) / 2, width: iconW, height: iconH))
            let x = iconW + gap
            var y = (size.height - textH) / 2
            title.draw(at: CGPoint(x: x, y: y))
            y += titleSize.height + 2
            if subSize.height > 0 { sub.draw(at: CGPoint(x: x, y: y)) }
        }
    }

    // MARK: Composición final

    /// Dibuja los elementos sobre la imagen terminada (foto con marco) para guardarla.
    static func composite(_ overlays: [EditorOverlay], onto base: UIImage, opaque: Bool) -> UIImage {
        guard !overlays.isEmpty else { return base }
        let size = CGSize(width: base.size.width * base.scale, height: base.size.height * base.scale)
        return renderer(size, opaque: opaque).image { ctx in
            base.draw(in: CGRect(origin: .zero, size: size))
            draw(overlays, in: ctx.cgContext, size: size)
        }
    }

    /// Solo los elementos, sobre fondo transparente (para video).
    static func layer(_ overlays: [EditorOverlay], size: CGSize) -> UIImage {
        renderer(size).image { ctx in
            draw(overlays, in: ctx.cgContext, size: size)
        }
    }

    private static func draw(_ overlays: [EditorOverlay], in cg: CGContext, size: CGSize) {
        let side = min(size.width, size.height)
        for overlay in overlays {
            guard let image = image(for: overlay) else { continue }
            let w = overlay.size * side
            let h = w * image.size.height / max(image.size.width, 1)
            cg.saveGState()
            cg.translateBy(x: overlay.center.x * size.width, y: overlay.center.y * size.height)
            cg.rotate(by: CGFloat(overlay.rotation))
            image.draw(in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
            cg.restoreGState()
        }
    }
}

// MARK: - Textos

enum TextRenderer {
    static func render(_ spec: TextSpec) -> UIImage? {
        let text = spec.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if spec.font == .cuentas { return beads(text, letterColor: spec.color) }

        let pointSize: CGFloat = 160
        let font = spec.font.font(size: pointSize)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let pill = spec.background == .pill
        let foreground: UIColor = pill ? (spec.color.isLight ? .black : .white) : spec.color
        let attributed = NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: foreground, .paragraphStyle: paragraph
        ])
        let bounds = attributed.boundingRect(with: CGSize(width: 2600, height: 10_000),
                                             options: [.usesLineFragmentOrigin, .usesFontLeading],
                                             context: nil).integral
        let padX: CGFloat = spec.font.isScript ? pointSize * 0.45 : (pill ? 70 : 28)
        let padY: CGFloat = spec.font.isScript ? pointSize * 0.3 : (pill ? 38 : 18)
        let canvas = CGSize(width: bounds.width + padX * 2, height: bounds.height + padY * 2)

        return OverlayRenderer.renderer(canvas).image { _ in
            if pill {
                spec.color.setFill()
                UIBezierPath(roundedRect: CGRect(origin: .zero, size: canvas),
                             cornerRadius: min(canvas.height / 2, 90)).fill()
            }
            attributed.draw(with: CGRect(x: padX, y: padY, width: bounds.width, height: bounds.height),
                            options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        }
    }

    /// Letras en cuentas blancas, como pulsera (referencia de Barcelona).
    static func beads(_ text: String, letterColor: UIColor) -> UIImage? {
        let lines = text.uppercased()
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { Array($0) }
        let maxCount = lines.map { $0.count }.max() ?? 0
        guard maxCount > 0 else { return nil }
        let d: CGFloat = 150
        let gap: CGFloat = 10
        let margin: CGFloat = 24
        let size = CGSize(width: CGFloat(maxCount) * (d + gap) - gap + margin * 2,
                          height: CGFloat(lines.count) * (d + gap) - gap + margin * 2)
        let font = UIFont(name: "AvenirNext-Bold", size: 84) ?? .boldSystemFont(ofSize: 84)
        let shade = NSShadow()
        shade.shadowColor = UIColor.black.withAlphaComponent(0.25)
        shade.shadowBlurRadius = 10
        shade.shadowOffset = CGSize(width: 0, height: 4)

        return OverlayRenderer.renderer(size).image { ctx in
            for (row, line) in lines.enumerated() {
                let lineWidth = CGFloat(line.count) * (d + gap) - gap
                var x = (size.width - lineWidth) / 2
                let y = margin + CGFloat(row) * (d + gap)
                for char in line {
                    defer { x += d + gap }
                    if char == " " { continue }
                    let rect = CGRect(x: x, y: y, width: d, height: d)
                    ctx.cgContext.saveGState()
                    ctx.cgContext.setShadow(offset: shade.shadowOffset, blur: shade.shadowBlurRadius,
                                            color: (shade.shadowColor as? UIColor)?.cgColor)
                    UIColor(white: 0.98, alpha: 1).setFill()
                    UIBezierPath(ovalIn: rect).fill()
                    ctx.cgContext.restoreGState()
                    UIColor(white: 0.82, alpha: 1).setStroke()
                    let ring = UIBezierPath(ovalIn: rect.insetBy(dx: 2, dy: 2))
                    ring.lineWidth = 3
                    ring.stroke()
                    let letter = NSAttributedString(string: String(char), attributes: [
                        .font: font, .foregroundColor: letterColor.isLight ? UIColor.black : letterColor
                    ])
                    let ls = letter.size()
                    letter.draw(at: CGPoint(x: rect.midX - ls.width / 2, y: rect.midY - ls.height / 2))
                }
            }
        }
    }
}
