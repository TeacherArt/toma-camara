import UIKit

/// Marcos para presentar la foto (inspirados en las referencias: White/Paper/Specs/Date,
/// Polaroid, ticket impreso y estampilla).
enum FrameStyle: String, CaseIterable, Identifiable {
    case none, white, paper, specs, date, polaroid, ticket, stamp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "Sin marco"
        case .white: return "White"
        case .paper: return "Paper"
        case .specs: return "Specs"
        case .date: return "Date"
        case .polaroid: return "Polaroid"
        case .ticket: return "Ticket"
        case .stamp: return "Sello"
        }
    }

    var icon: String {
        switch self {
        case .none: return "circle.slash"
        case .white: return "square"
        case .paper: return "square.fill"
        case .specs: return "rectangle.bottomhalf.filled"
        case .date: return "calendar"
        case .polaroid: return "photo"
        case .ticket: return "doc.text"
        case .stamp: return "seal"
        }
    }

    /// Ticket y sello tienen bordes recortados: se guardan como PNG con transparencia.
    var isTransparent: Bool { self == .ticket || self == .stamp }

    /// Ticket y sello no necesitan 24 MP; se reducen para que el PNG pese poco.
    var sizeLimit: CGFloat? { isTransparent ? 2000 : nil }
}

enum FrameRenderer {
    private enum Anchor { case left, center, right }

    private static let ink = UIColor(red: 0.12, green: 0.12, blue: 0.13, alpha: 1)
    private static let softInk = UIColor(red: 0.45, green: 0.45, blue: 0.47, alpha: 1)
    private static let dateOrange = UIColor(red: 1.0, green: 0.48, blue: 0.1, alpha: 1)

    static func render(photo cgImage: CGImage, frame: FrameStyle, info: ShotInfo, styleName: String) -> UIImage {
        let photo = UIImage(cgImage: cgImage)
        let w = CGFloat(cgImage.width)
        let h = CGFloat(cgImage.height)
        switch frame {
        case .none:
            return photo
        case .white:
            return bordered(photo, w: w, h: h, pad: min(w, h) * 0.035, color: .white)
        case .paper:
            return bordered(photo, w: w, h: h, pad: min(w, h) * 0.06,
                            color: UIColor(red: 0.94, green: 0.92, blue: 0.87, alpha: 1))
        case .specs:
            return specs(photo, w: w, h: h, info: info, styleName: styleName)
        case .date:
            return dateStamp(photo, w: w, h: h, info: info)
        case .polaroid:
            return polaroid(photo, w: w, h: h, info: info)
        case .ticket:
            return ticket(photo, w: w, h: h, info: info, styleName: styleName)
        case .stamp:
            return stamp(photo, w: w, h: h, info: info)
        }
    }

    // MARK: Marcos

    private static func bordered(_ photo: UIImage, w: CGFloat, h: CGFloat, pad: CGFloat, color: UIColor) -> UIImage {
        let size = CGSize(width: w + 2 * pad, height: h + 2 * pad)
        return renderer(size, opaque: true).image { ctx in
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            photo.draw(in: CGRect(x: pad, y: pad, width: w, height: h))
        }
    }

    private static func specs(_ photo: UIImage, w: CGFloat, h: CGFloat, info: ShotInfo, styleName: String) -> UIImage {
        let u = min(w, h)
        let side = u * 0.035
        let bottom = u * 0.17
        let size = CGSize(width: w + 2 * side, height: h + side + bottom)
        let big = UIFont.monospacedSystemFont(ofSize: bottom * 0.2, weight: .semibold)
        let small = UIFont.monospacedSystemFont(ofSize: bottom * 0.14, weight: .regular)
        let exif = [
            info.focal35.map { "\($0)mm" },
            apertureText(info.aperture),
            shutterText(info.exposure),
            info.iso.map { "ISO\($0)" }
        ].compactMap { $0 }.joined(separator: "  ")

        return renderer(size, opaque: true).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            photo.draw(in: CGRect(x: side, y: side, width: w, height: h))
            let top = h + side
            drawText("TOMA · iPhone", font: big, color: ink, x: side, y: top + bottom * 0.22, anchor: .left)
            drawText(dateText(info.date, "dd.MM.yyyy  HH:mm"), font: small, color: softInk,
                     x: side, y: top + bottom * 0.56, anchor: .left)
            drawText(exif, font: big, color: ink, x: size.width - side, y: top + bottom * 0.22, anchor: .right)
            drawText(styleName, font: small, color: softInk, x: size.width - side, y: top + bottom * 0.56, anchor: .right)
        }
    }

    private static func dateStamp(_ photo: UIImage, w: CGFloat, h: CGFloat, info: ShotInfo) -> UIImage {
        let u = min(w, h)
        let font = UIFont.monospacedDigitSystemFont(ofSize: u * 0.05, weight: .bold)
        let glow = NSShadow()
        glow.shadowColor = dateOrange.withAlphaComponent(0.9)
        glow.shadowBlurRadius = u * 0.012
        glow.shadowOffset = .zero
        return renderer(CGSize(width: w, height: h), opaque: true).image { _ in
            photo.draw(in: CGRect(x: 0, y: 0, width: w, height: h))
            drawText(dateText(info.date, "''yy MM dd"), font: font, color: dateOrange,
                     x: w - u * 0.06, y: h - u * 0.06 - font.lineHeight, anchor: .right,
                     kern: u * 0.004, shadow: glow)
        }
    }

    private static func polaroid(_ photo: UIImage, w: CGFloat, h: CGFloat, info: ShotInfo) -> UIImage {
        let u = min(w, h)
        let side = u * 0.055
        let bottom = u * 0.24
        let size = CGSize(width: w + 2 * side, height: h + side + bottom)
        let font = UIFont(name: "Noteworthy-Light", size: bottom * 0.2)
            ?? UIFont.italicSystemFont(ofSize: bottom * 0.2)
        return renderer(size, opaque: true).image { ctx in
            UIColor(red: 0.98, green: 0.98, blue: 0.965, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            photo.draw(in: CGRect(x: side, y: side, width: w, height: h))
            drawText(dateText(info.date, "d 'de' MMMM, yyyy"), font: font,
                     color: UIColor(red: 0.2, green: 0.2, blue: 0.26, alpha: 1),
                     x: size.width / 2, y: side + h + bottom * 0.32, anchor: .center)
        }
    }

    private static func ticket(_ photo: UIImage, w: CGFloat, h: CGFloat, info: ShotInfo, styleName: String) -> UIImage {
        let m = w * 0.09
        let width = w + 2 * m
        let paper = UIColor(red: 0.965, green: 0.955, blue: 0.93, alpha: 1)
        let titleFont = UIFont.monospacedSystemFont(ofSize: w * 0.075, weight: .medium)
        let subFont = UIFont.monospacedSystemFont(ofSize: w * 0.03, weight: .regular)
        let rowFont = UIFont.monospacedSystemFont(ofSize: w * 0.036, weight: .regular)
        let rows: [(String, String)] = [
            ("TOMADA", dateText(info.date, "HH:mm")),
            ("FECHA", dateText(info.date, "dd.MM.yyyy")),
            ("ESTILO", styleName),
            ("LENTE", info.focal35.map { "\($0) MM" } ?? "—"),
            ("APERTURA", apertureText(info.aperture) ?? "—"),
            ("VELOCIDAD", shutterText(info.exposure) ?? "—"),
            ("ISO", info.iso.map { String($0) } ?? "—")
        ]
        let teeth = w * 0.03
        let rowHeight = rowFont.lineHeight * 1.45
        let barHeight = w * 0.14

        var y = m
        let titleY = y; y += titleFont.lineHeight * 1.1
        let subY = y; y += subFont.lineHeight + m * 0.6
        let photoY = y; y += h + m * 0.6
        let dash1 = y; y += m * 0.5
        let rowsY = y; y += rowHeight * CGFloat(rows.count) + m * 0.3
        let dash2 = y; y += m * 0.5
        let barY = y; y += barHeight + m * 0.25
        let codeY = y; y += subFont.lineHeight * 1.4
        let thanksY = y; y += subFont.lineHeight + m
        let height = y + teeth
        let size = CGSize(width: width, height: height)

        return renderer(size, opaque: false).image { ctx in
            let cg = ctx.cgContext

            // Papel con borde inferior dentado
            let path = UIBezierPath()
            path.move(to: .zero)
            path.addLine(to: CGPoint(x: width, y: 0))
            path.addLine(to: CGPoint(x: width, y: height - teeth))
            let count = max(4, Int(width / (teeth * 1.6)))
            let step = width / CGFloat(count)
            for i in 0..<count {
                let x0 = width - CGFloat(i) * step
                path.addLine(to: CGPoint(x: x0 - step / 2, y: height))
                path.addLine(to: CGPoint(x: x0 - step, y: height - teeth))
            }
            path.close()
            paper.setFill()
            path.fill()

            drawText("TOMA RECEIPT", font: titleFont, color: ink, x: width / 2, y: titleY, anchor: .center, kern: w * 0.008)
            drawText(dateText(info.date, "EEEE d MMM yyyy").uppercased(), font: subFont, color: softInk,
                     x: width / 2, y: subY, anchor: .center)
            photo.draw(in: CGRect(x: m, y: photoY, width: w, height: h))
            dashedLine(cg, y: dash1, from: m, to: width - m, color: ink, lineWidth: w * 0.004)

            for (i, row) in rows.enumerated() {
                let rowY = rowsY + CGFloat(i) * rowHeight
                drawText(row.0, font: rowFont, color: ink, x: m, y: rowY, anchor: .left)
                drawText(row.1, font: rowFont, color: ink, x: width - m, y: rowY, anchor: .right)
                let left = (row.0 as NSString).size(withAttributes: [.font: rowFont]).width
                let right = (row.1 as NSString).size(withAttributes: [.font: rowFont]).width
                dottedLine(cg, y: rowY + rowFont.lineHeight * 0.78,
                           from: m + left + w * 0.02, to: width - m - right - w * 0.02,
                           color: ink.withAlphaComponent(0.45), lineWidth: w * 0.004)
            }

            dashedLine(cg, y: dash2, from: m, to: width - m, color: ink, lineWidth: w * 0.004)
            barcode(cg, rect: CGRect(x: width * 0.15, y: barY, width: width * 0.7, height: barHeight),
                    seed: UInt64(max(0, info.date.timeIntervalSince1970)), color: ink)
            drawText("#### \(dateText(info.date, "MMdd")) ####", font: subFont, color: ink,
                     x: width / 2, y: codeY, anchor: .center, kern: w * 0.006)
            drawText("GRACIAS POR TU VISITA", font: subFont, color: softInk,
                     x: width / 2, y: thanksY, anchor: .center, kern: w * 0.004)
        }
    }

    private static func stamp(_ photo: UIImage, w: CGFloat, h: CGFloat, info: ShotInfo) -> UIImage {
        let u = min(w, h)
        let r = u * 0.022
        let border = r * 2.4
        let gap = r * 2.7
        let size = CGSize(width: w + 2 * border, height: h + 2 * border)
        let numberFont = UIFont.monospacedDigitSystemFont(ofSize: u * 0.06, weight: .bold)
        let shade = NSShadow()
        shade.shadowColor = UIColor.black.withAlphaComponent(0.35)
        shade.shadowBlurRadius = u * 0.01
        shade.shadowOffset = .zero

        return renderer(size, opaque: false).image { _ in
            // Papel con perforaciones: los círculos en el borde quedan como huecos.
            let path = UIBezierPath(rect: CGRect(origin: .zero, size: size))
            let nx = max(2, Int(size.width / gap))
            let ny = max(2, Int(size.height / gap))
            let sx = size.width / CGFloat(nx)
            let sy = size.height / CGFloat(ny)
            for i in 0...nx {
                let x = CGFloat(i) * sx
                path.append(circle(x, 0, r))
                path.append(circle(x, size.height, r))
            }
            for j in 1..<ny {
                let y = CGFloat(j) * sy
                path.append(circle(0, y, r))
                path.append(circle(size.width, y, r))
            }
            path.usesEvenOddFillRule = true
            UIColor(white: 0.985, alpha: 1).setFill()
            path.fill()

            photo.draw(in: CGRect(x: border, y: border, width: w, height: h))
            drawText(dateText(info.date, "dd"), font: numberFont, color: .white,
                     x: border + w - u * 0.04, y: border + h - u * 0.04 - numberFont.lineHeight,
                     anchor: .right, shadow: shade)
        }
    }

    // MARK: Ayudantes de dibujo

    private static func renderer(_ size: CGSize, opaque: Bool) -> UIGraphicsImageRenderer {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = opaque
        return UIGraphicsImageRenderer(size: size, format: format)
    }

    private static func drawText(_ text: String, font: UIFont, color: UIColor,
                                 x: CGFloat, y: CGFloat, anchor: Anchor,
                                 kern: CGFloat = 0, shadow: NSShadow? = nil) {
        var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .kern: kern]
        if let shadow { attributes[.shadow] = shadow }
        let string = NSAttributedString(string: text, attributes: attributes)
        let width = string.size().width
        let originX: CGFloat
        switch anchor {
        case .left: originX = x
        case .center: originX = x - width / 2
        case .right: originX = x - width
        }
        string.draw(at: CGPoint(x: originX, y: y))
    }

    private static func dashedLine(_ cg: CGContext, y: CGFloat, from x0: CGFloat, to x1: CGFloat,
                                   color: UIColor, lineWidth: CGFloat) {
        cg.saveGState()
        cg.setStrokeColor(color.cgColor)
        cg.setLineWidth(lineWidth)
        cg.setLineDash(phase: 0, lengths: [lineWidth * 4, lineWidth * 3])
        cg.move(to: CGPoint(x: x0, y: y))
        cg.addLine(to: CGPoint(x: x1, y: y))
        cg.strokePath()
        cg.restoreGState()
    }

    private static func dottedLine(_ cg: CGContext, y: CGFloat, from x0: CGFloat, to x1: CGFloat,
                                   color: UIColor, lineWidth: CGFloat) {
        guard x1 > x0 else { return }
        cg.saveGState()
        cg.setStrokeColor(color.cgColor)
        cg.setLineWidth(lineWidth)
        cg.setLineCap(.round)
        cg.setLineDash(phase: 0, lengths: [0.01, lineWidth * 2.5])
        cg.move(to: CGPoint(x: x0, y: y))
        cg.addLine(to: CGPoint(x: x1, y: y))
        cg.strokePath()
        cg.restoreGState()
    }

    private static func barcode(_ cg: CGContext, rect: CGRect, seed: UInt64, color: UIColor) {
        var state = seed &* 6364136223846793005 &+ 1442695040888963407
        cg.setFillColor(color.cgColor)
        let unit = rect.width / 95
        var x = rect.minX
        var isBar = true
        while x < rect.maxX {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let barWidth = unit * CGFloat(1 + (state >> 33) % 3)
            if isBar {
                cg.fill(CGRect(x: x, y: rect.minY, width: min(barWidth, rect.maxX - x), height: rect.height))
            }
            x += barWidth
            isBar.toggle()
        }
    }

    private static func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> UIBezierPath {
        UIBezierPath(ovalIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
    }

    // MARK: Textos

    private static func dateText(_ date: Date, _ format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_MX")
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    private static func shutterText(_ seconds: Double?) -> String? {
        guard let seconds, seconds > 0 else { return nil }
        if seconds >= 1 { return String(format: "%.1fs", seconds) }
        return "1/\(Int((1 / seconds).rounded()))s"
    }

    private static func apertureText(_ value: Double?) -> String? {
        guard let value else { return nil }
        return String(format: "ƒ%.1f", value)
    }
}
