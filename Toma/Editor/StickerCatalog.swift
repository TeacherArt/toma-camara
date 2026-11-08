import UIKit

struct StickerItem: Identifiable, Hashable {
    let name: String
    let title: String
    var id: String { name }
}

enum StickerSection: String, CaseIterable, Identifiable {
    case frases, stickers, siluetas

    var id: String { rawValue }

    var title: String {
        switch self {
        case .frases: return "Frases"
        case .stickers: return "Stickers"
        case .siluetas: return "Siluetas"
        }
    }

    /// Las frases lucen mejor como acrílico; los stickers ya traen borde blanco.
    var defaultBorder: OverlayBorder {
        self == .frases ? .acrylic : .none
    }
}

enum StickerCatalog {
    static let frases: [StickerItem] = [
        StickerItem(name: "frase_arthur_corona", title: "Arthur"),
        StickerItem(name: "frase_grateful_blessed", title: "Grateful & Blessed"),
        StickerItem(name: "frase_modo_maestro", title: "Modo maestro"),
        StickerItem(name: "frase_hecho_en_mexico", title: "Hecho en México"),
        StickerItem(name: "frase_con_dios_por_delante", title: "Con Dios por delante"),
        StickerItem(name: "frase_nunca_fue_suerte", title: "Nunca fue suerte"),
        StickerItem(name: "frase_the_world_is_yours", title: "The world is yours"),
        StickerItem(name: "frase_siempre_imitado", title: "Siempre imitado"),
        StickerItem(name: "frase_me_queda_1", title: "Me queda 1%"),
        StickerItem(name: "frase_si_subo_gordas", title: "Si subo gordas"),
        StickerItem(name: "frase_todas_mienten", title: "Todas mienten"),
        StickerItem(name: "frase_en_boca_de_todos", title: "En boca de todos"),
        StickerItem(name: "frase_fruto_prohibido", title: "Fruto prohibido"),
        StickerItem(name: "frase_modo_diablo", title: "Modo diablo")
    ]

    static let stickers: [StickerItem] = [
        StickerItem(name: "stk_gato_natacion", title: "Gato nadador"),
        StickerItem(name: "stk_arthur_cuentas", title: "ARTHUR cuentas"),
        StickerItem(name: "stk_camara_retro", title: "Cámara retro"),
        StickerItem(name: "stk_cdmx_atardecer", title: "CDMX"),
        StickerItem(name: "stk_autobus_tizayuca", title: "Autobús Tizayuca"),
        StickerItem(name: "stk_combi_flamas", title: "Combi")
    ]

    static let siluetas: [StickerItem] = [
        StickerItem(name: "sil_ar27", title: "AR27"),
        StickerItem(name: "sil_gato_perfil", title: "Gato"),
        StickerItem(name: "sil_gato_maestro", title: "Maestro"),
        StickerItem(name: "sil_gato_gym", title: "Gym"),
        StickerItem(name: "sil_gato_nadador", title: "Natación"),
        StickerItem(name: "sil_gato_chill", title: "Chill"),
        StickerItem(name: "sil_gato_fotografo", title: "Fotógrafo"),
        StickerItem(name: "sil_cdmx", title: "CDMX"),
        StickerItem(name: "sil_edomex", title: "Edomex"),
        StickerItem(name: "sil_camara", title: "Cámara"),
        StickerItem(name: "sil_autobus", title: "Autobús"),
        StickerItem(name: "sil_combi", title: "Combi")
    ]

    static func items(_ section: StickerSection) -> [StickerItem] {
        switch section {
        case .frases: return frases
        case .stickers: return stickers
        case .siluetas: return siluetas
        }
    }
}

/// Miniaturas pequeñas para las cuadrículas (las originales son grandes).
final class ThumbCache {
    static let shared = ThumbCache()
    private let cache = NSCache<NSString, UIImage>()
    private let queue = DispatchQueue(label: "toma.thumbs", qos: .userInitiated)

    func thumb(_ name: String, side: CGFloat = 220, completion: @escaping (UIImage?) -> Void) {
        let key = "\(name)@\(Int(side))" as NSString
        if let hit = cache.object(forKey: key) {
            completion(hit)
            return
        }
        queue.async {
            var result: UIImage?
            if let image = UIImage(named: name) {
                let scale = side / max(image.size.width, image.size.height)
                let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                result = image.preparingThumbnail(of: size) ?? image
            }
            if let result { self.cache.setObject(result, forKey: key) }
            DispatchQueue.main.async { completion(result) }
        }
    }
}
