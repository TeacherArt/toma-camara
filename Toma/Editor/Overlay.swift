import UIKit

/// Contorno que la app agrega a stickers y textos.
enum OverlayBorder: String, CaseIterable, Identifiable {
    case none, white, acrylic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "Sin borde"
        case .white: return "Blanco"
        case .acrylic: return "Acrílico"
        }
    }
}

enum TextFont: String, CaseIterable, Identifiable {
    case didot, bodoni, cursiva, firma, maquina, futura, avenir, marker, notas, georgia, copperplate, pizarron, redonda, cuentas

    var id: String { rawValue }

    var title: String {
        switch self {
        case .didot: return "Didot"
        case .bodoni: return "Bodoni"
        case .cursiva: return "Cursiva"
        case .firma: return "Firma"
        case .maquina: return "Máquina"
        case .futura: return "Futura"
        case .avenir: return "Avenir"
        case .marker: return "Marker"
        case .notas: return "Notas"
        case .georgia: return "Georgia"
        case .copperplate: return "Copperplate"
        case .pizarron: return "Pizarrón"
        case .redonda: return "Redonda"
        case .cuentas: return "Cuentas"
        }
    }

    /// Las letras cursivas sobresalen de su caja; necesitan más margen.
    var isScript: Bool { self == .cursiva || self == .firma || self == .georgia }

    func font(size: CGFloat) -> UIFont {
        let name: String?
        switch self {
        case .didot: name = "Didot-Bold"
        case .bodoni: name = "BodoniSvtyTwoITCTT-Bold"
        case .cursiva: name = "SnellRoundhand-Black"
        case .firma: name = "SavoyeLetPlain"
        case .maquina: name = "AmericanTypewriter-Bold"
        case .futura: name = "Futura-CondensedExtraBold"
        case .avenir: name = "AvenirNext-Heavy"
        case .marker: name = "MarkerFelt-Wide"
        case .notas: name = "Noteworthy-Bold"
        case .georgia: name = "Georgia-BoldItalic"
        case .copperplate: name = "Copperplate-Bold"
        case .pizarron: name = "Chalkduster"
        case .redonda, .cuentas: name = nil
        }
        if let name, let font = UIFont(name: name, size: size) { return font }
        let base = UIFont.systemFont(ofSize: size, weight: .black)
        if self == .redonda, let rounded = base.fontDescriptor.withDesign(.rounded) {
            return UIFont(descriptor: rounded, size: size)
        }
        return base
    }
}

enum TextBackground: String, CaseIterable, Identifiable {
    case none, pill

    var id: String { rawValue }

    var title: String { self == .none ? "Sin fondo" : "Con fondo" }
}

struct TextSpec: Equatable {
    var text: String
    var font: TextFont
    var color: UIColor
    var background: TextBackground = .none

    var cacheKey: String { "\(text)|\(font.rawValue)|\(color.keyString)|\(background.rawValue)" }
}

/// Marca personal tipo Garmin: silueta + ARTHVR + datos.
struct MarkSpec: Equatable {
    var silhouette: String
    var color: UIColor
    var title: String = "ARTHVR"
    var subtitle: String

    var cacheKey: String { "\(silhouette)|\(color.keyString)|\(title)|\(subtitle)" }
}

enum OverlayContent: Equatable {
    case sticker(String)
    case silhouette(String, UIColor)
    case text(TextSpec)
    case mark(MarkSpec)

    var cacheKey: String {
        switch self {
        case .sticker(let name): return "s:\(name)"
        case .silhouette(let name, let color): return "v:\(name)|\(color.keyString)"
        case .text(let spec): return "t:\(spec.cacheKey)"
        case .mark(let spec): return "m:\(spec.cacheKey)"
        }
    }

    var isText: Bool {
        if case .text = self { return true }
        return false
    }

    var isMark: Bool {
        if case .mark = self { return true }
        return false
    }
}

/// Un elemento encima de la foto. La posición y el tamaño son relativos a la foto,
/// así se ve igual en la vista previa y en el archivo final.
struct EditorOverlay: Identifiable, Equatable {
    let id: UUID
    var content: OverlayContent
    var border: OverlayBorder
    var center: CGPoint
    /// Ancho como fracción del lado corto de la foto.
    var size: CGFloat
    var rotation: Double

    init(content: OverlayContent, border: OverlayBorder = .none,
         center: CGPoint = CGPoint(x: 0.5, y: 0.5), size: CGFloat = 0.45, rotation: Double = 0) {
        self.id = UUID()
        self.content = content
        self.border = border
        self.center = center
        self.size = size
        self.rotation = rotation
    }

    var cacheKey: String { content.cacheKey + "|" + border.rawValue }
}

extension UIColor {
    var keyString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%.3f,%.3f,%.3f,%.3f", r, g, b, a)
    }

    var isLight: Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return 0.299 * r + 0.587 * g + 0.114 * b > 0.6
    }

    static let wine = UIColor(red: 0.62, green: 0.08, blue: 0.13, alpha: 1)
    static let mexicanPink = UIColor(red: 1.0, green: 0.18, blue: 0.53, alpha: 1)
    static let mexicoGreen = UIColor(red: 0.0, green: 0.41, blue: 0.28, alpha: 1)
    static let gold = UIColor(red: 0.83, green: 0.63, blue: 0.09, alpha: 1)
    static let toma = UIColor(red: 1.0, green: 0.84, blue: 0.0, alpha: 1)

    static let palette: [UIColor] = [
        .white, .black, .wine, .systemRed, .mexicanPink, .toma, .gold, .systemCyan, .mexicoGreen, .systemBlue
    ]
}
