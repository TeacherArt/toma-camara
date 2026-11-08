import UIKit

enum PeopleGroup: String, CaseIterable, Identifiable {
    case solo, pareja, grupo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .solo: return "1 persona"
        case .pareja: return "Pareja"
        case .grupo: return "Grupo"
        }
    }

    init(count: Int) {
        if count >= 3 {
            self = .grupo
        } else if count == 2 {
            self = .pareja
        } else {
            self = .solo
        }
    }
}

/// Categorías como en las apps de poses: tendencia, de pie, 3/4, sentado, espejo y close-up.
enum PoseCategory: String, CaseIterable, Identifiable {
    case tendencia, dePie, tresCuartos, sentado, espejo, closeUp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tendencia: return "Tendencia"
        case .dePie: return "De pie"
        case .tresCuartos: return "3/4"
        case .sentado: return "Sentado"
        case .espejo: return "Espejo"
        case .closeUp: return "Close-up"
        }
    }
}

struct PoseIdea: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let inspiration: String?
    let symbol: String
    let group: PeopleGroup
    let categories: [PoseCategory]

    /// Imagen del maniquí (pose_<id>.png). Si todavía no existe, se usa el ícono.
    var imageName: String { "pose_\(id)" }
    var image: UIImage? { UIImage(named: imageName) }

    static func == (lhs: PoseIdea, rhs: PoseIdea) -> Bool { lhs.id == rhs.id }
}

enum PoseLibrary {
    static let all: [PoseIdea] = solo + parejas + grupos

    // MARK: Una persona

    static let solo: [PoseIdea] = [
        // Campaña Calvin Klein "Icon" con Jude Bellingham (nov 2026): minimalista, de frente y de espaldas con brazos arriba.
        PoseIdea(id: "ck_brazos", title: "Brazos arriba",
                 detail: "De frente, manos detrás de la cabeza y codos abiertos. Mentón un poco abajo, mirada intensa. Fondo liso y B/N.",
                 inspiration: "Campaña Calvin Klein de Jude Bellingham",
                 symbol: "figure.arms.open", group: .solo, categories: [.tendencia, .dePie]),
        PoseIdea(id: "ck_espalda", title: "De espaldas, brazos arriba",
                 detail: "De espaldas a la cámara, brazos estirados hacia arriba, una pierna relajada. Luz de lado para marcar la espalda.",
                 inspiration: "Campaña Calvin Klein de Jude Bellingham",
                 symbol: "figure.stand", group: .solo, categories: [.tendencia, .dePie]),
        PoseIdea(id: "ck_cintura", title: "Pulgares en la cintura",
                 detail: "Pulgares en la pretina o el cinturón, hombros sueltos, peso en una pierna y mirada directa.",
                 inspiration: "Clásico de las campañas de Calvin Klein",
                 symbol: "figure.stand", group: .solo, categories: [.tendencia, .dePie]),
        PoseIdea(id: "cuclillas", title: "Cuclillas street",
                 detail: "Agáchate sobre los talones, codos en las rodillas y manos juntas. Lentes oscuros y mirada a la cámara, cámara a tu altura.",
                 inspiration: "Portadas de reguetón y corridos",
                 symbol: "figure.cooldown", group: .solo, categories: [.tendencia, .sentado]),
        PoseIdea(id: "auto", title: "Rey del camino",
                 detail: "Recárgate en el cofre o la puerta de un auto, brazos cruzados o una mano en el bolsillo. Cámara baja.",
                 inspiration: "Portada de Bad Bunny para Vogue",
                 symbol: "car.fill", group: .solo, categories: [.tendencia, .dePie]),
        PoseIdea(id: "espejo_lado", title: "Espejo de lado",
                 detail: "De lado al espejo, cadera hacia afuera y cabeza un poco inclinada; mira la pantalla del teléfono, no el espejo.",
                 inspiration: "Selfie de espejo de Kylie Jenner",
                 symbol: "iphone", group: .solo, categories: [.tendencia, .espejo]),

        // De pie
        PoseIdea(id: "caminata", title: "La caminata",
                 detail: "Camina hacia la cámara y mira a un lado; dispara a mitad del paso (usa ráfaga o temporizador).",
                 inspiration: "Street style",
                 symbol: "figure.walk", group: .solo, categories: [.dePie]),
        PoseIdea(id: "tobillos", title: "Tobillos cruzados",
                 detail: "Cruza un pie sobre el otro, peso atrás y cuerpo en ángulo, no de frente. Alarga las piernas.",
                 inspiration: "Pose de Alexa Chung",
                 symbol: "figure.stand", group: .solo, categories: [.dePie]),
        PoseIdea(id: "recargado", title: "Recargado en la pared",
                 detail: "Hombro en la pared, un pie cruzado por delante y manos en los bolsillos.",
                 inspiration: nil,
                 symbol: "figure.stand.line.dotted.figure.stand", group: .solo, categories: [.dePie]),
        PoseIdea(id: "mano_cabello", title: "Mano en el cabello",
                 detail: "Un brazo arriba con la mano en la cabeza, codo hacia afuera; la otra mano relajada. Mira a la cámara.",
                 inspiration: "Pose de brazo arriba de Kylie Jenner",
                 symbol: "figure.wave", group: .solo, categories: [.dePie, .closeUp]),

        // 3/4
        PoseIdea(id: "hombro", title: "Mirada por el hombro",
                 detail: "De espaldas, un pie adelante; gira la cintura hacia el pie de atrás y mira a la cámara con el mentón arriba.",
                 inspiration: "Pose de Gigi Hadid",
                 symbol: "arrow.uturn.left", group: .solo, categories: [.tresCuartos]),
        PoseIdea(id: "tres_cuartos", title: "Cuerpo a 45°",
                 detail: "Cuerpo girado 45°, cara hacia la cámara, peso en el pie de atrás y una mano en la cintura.",
                 inspiration: nil,
                 symbol: "person.crop.square", group: .solo, categories: [.tresCuartos]),
        PoseIdea(id: "perfil", title: "Perfil con hombro",
                 detail: "Ponte de perfil, baja un poco el hombro de adelante y apunta un pie hacia la cámara. Cámara a la altura de los ojos.",
                 inspiration: "Pose de perfil de Taylor Swift",
                 symbol: "person.fill.turn.right", group: .solo, categories: [.tresCuartos]),
        PoseIdea(id: "chamarra", title: "Ajustando la chamarra",
                 detail: "Cuerpo a 3/4, toma el cuello o las mangas como acomodándola y mira hacia abajo.",
                 inspiration: nil,
                 symbol: "tshirt.fill", group: .solo, categories: [.tresCuartos]),

        // Sentado
        PoseIdea(id: "cansado", title: "Cansado",
                 detail: "Sentado en un escalón, codos en las rodillas y manos juntas; mira abajo o a la cámara.",
                 inspiration: nil,
                 symbol: "figure.seated.side", group: .solo, categories: [.sentado]),
        PoseIdea(id: "de_lado", title: "Mirando a otro lado",
                 detail: "Sentado de lado, una pierna doblada y el brazo sobre la rodilla; mira lejos de la cámara.",
                 inspiration: nil,
                 symbol: "figure.mind.and.body", group: .solo, categories: [.sentado]),
        PoseIdea(id: "piso", title: "En el piso",
                 detail: "Sentado en el piso, rodillas arriba y brazos sobre ellas; cabeza un poco inclinada.",
                 inspiration: "Pose casual de Kylie Jenner",
                 symbol: "figure.roll", group: .solo, categories: [.sentado]),
        PoseIdea(id: "banca", title: "Brazo en el respaldo",
                 detail: "En una banca, un brazo sobre el respaldo y piernas abiertas y relajadas.",
                 inspiration: nil,
                 symbol: "sofa.fill", group: .solo, categories: [.sentado]),

        // Espejo
        PoseIdea(id: "espejo_frente", title: "Espejo de frente",
                 detail: "De frente al espejo, una cadera fuera; el teléfono tapa parte de la cara.",
                 inspiration: "Selfie de espejo de Kylie Jenner",
                 symbol: "iphone", group: .solo, categories: [.espejo]),
        PoseIdea(id: "espejo_gym", title: "Espejo de gym",
                 detail: "De lado al espejo, brazo libre flexionado y puño cerrado; teléfono a la altura del pecho.",
                 inspiration: nil,
                 symbol: "dumbbell.fill", group: .solo, categories: [.espejo]),

        // Close-up
        PoseIdea(id: "menton", title: "Mano en el mentón",
                 detail: "Apoya el mentón en la mano, sin aplastar; mirada directa y relajada.",
                 inspiration: nil,
                 symbol: "hand.raised.fill", group: .solo, categories: [.closeUp]),
        PoseIdea(id: "sien", title: "Dedos en la sien",
                 detail: "Yemas de los dedos en las sienes como masajeando; enmarca pómulos y manos.",
                 inspiration: "Pose de tendencia en Instagram",
                 symbol: "brain.head.profile", group: .solo, categories: [.closeUp]),
        PoseIdea(id: "lentes", title: "Mirada sobre los lentes",
                 detail: "Baja un poco los lentes oscuros con un dedo y mira por encima.",
                 inspiration: "Portadas de músicos",
                 symbol: "eyeglasses", group: .solo, categories: [.closeUp, .tendencia]),
        PoseIdea(id: "sombra", title: "Media sombra",
                 detail: "Media cara en sombra con luz de lado o contraluz; mirada lejos, como portada de álbum.",
                 inspiration: "Fotos de músicos en concierto",
                 symbol: "circle.lefthalf.filled", group: .solo, categories: [.closeUp])
    ]

    // MARK: Pareja y grupo

    static let parejas: [PoseIdea] = [
        PoseIdea(id: "p_frente", title: "Frente a frente", detail: "Mírense de cerca, con las frentes casi juntas.",
                 inspiration: nil, symbol: "person.2.fill", group: .pareja, categories: []),
        PoseIdea(id: "p_mano", title: "De la mano", detail: "Caminen hacia la cámara de la mano, mirándose.",
                 inspiration: nil, symbol: "figure.walk", group: .pareja, categories: []),
        PoseIdea(id: "p_abrazo", title: "Abrazo por detrás", detail: "Uno abraza al otro por la espalda; ambos miran a la cámara.",
                 inspiration: nil, symbol: "heart.fill", group: .pareja, categories: []),
        PoseIdea(id: "p_secreto", title: "Secreto", detail: "Uno le dice algo al oído al otro; capta la risa.",
                 inspiration: nil, symbol: "ear.fill", group: .pareja, categories: []),
        PoseIdea(id: "p_espaldas", title: "Espalda con espalda", detail: "Recárguense espalda con espalda, brazos cruzados.",
                 inspiration: nil, symbol: "arrow.left.and.right", group: .pareja, categories: []),
        PoseIdea(id: "p_sentados", title: "Sentados juntos", detail: "Lado a lado; uno recarga la cabeza en el hombro del otro.",
                 inspiration: nil, symbol: "sofa.fill", group: .pareja, categories: [])
    ]

    static let grupos: [PoseIdea] = [
        PoseIdea(id: "g_escalonados", title: "Escalonados", detail: "Unos sentados y otros de pie; que no queden en línea.",
                 inspiration: nil, symbol: "person.3.fill", group: .grupo, categories: []),
        PoseIdea(id: "g_caminando", title: "Caminando juntos", detail: "Caminen hacia la cámara platicando entre ustedes.",
                 inspiration: nil, symbol: "figure.walk", group: .grupo, categories: []),
        PoseIdea(id: "g_abrazo", title: "Abrazo de grupo", detail: "Brazos sobre los hombros, cabezas un poco al centro.",
                 inspiration: nil, symbol: "person.3.sequence.fill", group: .grupo, categories: []),
        PoseIdea(id: "g_arriba", title: "Desde arriba", detail: "Todos miran hacia arriba, a la cámara en alto.",
                 inspiration: nil, symbol: "arrow.up.circle", group: .grupo, categories: []),
        PoseIdea(id: "g_salto", title: "Salto", detail: "Salten al mismo tiempo con el temporizador de 3 s.",
                 inspiration: nil, symbol: "figure.jumprope", group: .grupo, categories: []),
        PoseIdea(id: "g_triangulo", title: "Triángulo", detail: "El más alto al centro y atrás; los demás a los lados.",
                 inspiration: nil, symbol: "triangle.fill", group: .grupo, categories: [])
    ]

    static func ideas(for group: PeopleGroup, category: PoseCategory, search: String) -> [PoseIdea] {
        var list: [PoseIdea]
        switch group {
        case .solo: list = solo.filter { $0.categories.contains(category) }
        case .pareja: list = parejas
        case .grupo: list = grupos
        }
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return list }
        let pool = group == .solo ? solo : list
        return pool.filter {
            $0.title.lowercased().contains(query)
                || $0.detail.lowercased().contains(query)
                || ($0.inspiration?.lowercased().contains(query) ?? false)
        }
    }
}
