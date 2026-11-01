import Foundation

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

enum PoseFocus: String, CaseIterable, Identifiable {
    case outfit, rostro, lugar, ambiente

    var id: String { rawValue }

    var title: String {
        switch self {
        case .outfit: return "Outfit"
        case .rostro: return "Rostro"
        case .lugar: return "Lugar"
        case .ambiente: return "Ambiente"
        }
    }
}

struct PoseIdea: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let group: PeopleGroup
    let focus: PoseFocus?
}

enum PoseLibrary {
    static let all: [PoseIdea] = [
        // Una persona · outfit
        PoseIdea(id: "o1", title: "Paso casual", detail: "Camina hacia la cámara y mira a un lado; dispara a mitad del paso.",
                 symbol: "figure.walk", group: .solo, focus: .outfit),
        PoseIdea(id: "o2", title: "Mano en el bolsillo", detail: "Peso en una pierna, una mano en el bolsillo, hombros relajados.",
                 symbol: "figure.stand", group: .solo, focus: .outfit),
        PoseIdea(id: "o3", title: "Mirada abajo", detail: "Mira hacia abajo como acomodando tu ropa o tu bolsa.",
                 symbol: "eye", group: .solo, focus: .outfit),
        PoseIdea(id: "o4", title: "Recargado", detail: "Recárgate en una pared o barandal y cruza un pie por delante.",
                 symbol: "figure.stand.line.dotted.figure.stand", group: .solo, focus: .outfit),
        PoseIdea(id: "o5", title: "Ajustando la chamarra", detail: "Toma el cuello o las mangas como si la acomodaras.",
                 symbol: "tshirt.fill", group: .solo, focus: .outfit),
        PoseIdea(id: "o6", title: "Cámara baja", detail: "Que te tomen desde la cintura apuntando un poco arriba: alarga las piernas.",
                 symbol: "camera.fill", group: .solo, focus: .outfit),

        // Una persona · rostro
        PoseIdea(id: "r1", title: "Mentón adelante", detail: "Lleva el mentón un poco adelante y abajo; define la mandíbula.",
                 symbol: "person.crop.circle", group: .solo, focus: .rostro),
        PoseIdea(id: "r2", title: "Tres cuartos", detail: "Gira el cuerpo 45° y la cara hacia la cámara.",
                 symbol: "person.crop.square", group: .solo, focus: .rostro),
        PoseIdea(id: "r3", title: "Mano en el rostro", detail: "Apoya la mano suave en la mejilla o el cabello, sin aplastar.",
                 symbol: "hand.raised.fill", group: .solo, focus: .rostro),
        PoseIdea(id: "r4", title: "Sonrisa real", detail: "Ríe de algo y vuelve a mirar a la cámara a medio gesto.",
                 symbol: "face.smiling", group: .solo, focus: .rostro),
        PoseIdea(id: "r5", title: "Mirada lejos", detail: "Mira fuera de cuadro, hacia la luz.",
                 symbol: "sun.max.fill", group: .solo, focus: .rostro),
        PoseIdea(id: "r6", title: "Desde arriba", detail: "Cámara un poco arriba de los ojos; mira hacia ella.",
                 symbol: "arrow.down.circle", group: .solo, focus: .rostro),

        // Una persona · lugar
        PoseIdea(id: "l1", title: "Pequeño en grande", detail: "Ocupa solo un tercio del cuadro; que luzca el lugar.",
                 symbol: "mountain.2.fill", group: .solo, focus: .lugar),
        PoseIdea(id: "l2", title: "De espaldas", detail: "Mira el paisaje de espaldas a la cámara.",
                 symbol: "figure.stand", group: .solo, focus: .lugar),
        PoseIdea(id: "l3", title: "Brazos abiertos", detail: "Abre los brazos frente a la vista.",
                 symbol: "figure.arms.open", group: .solo, focus: .lugar),
        PoseIdea(id: "l4", title: "Sentado al borde", detail: "Siéntate en una banca o escalón mirando al horizonte.",
                 symbol: "figure.mind.and.body", group: .solo, focus: .lugar),
        PoseIdea(id: "l5", title: "Señalando", detail: "Señala algo del lugar como si lo descubrieras.",
                 symbol: "hand.point.up.left.fill", group: .solo, focus: .lugar),
        PoseIdea(id: "l6", title: "Caminando lejos", detail: "Camina alejándote por el camino o la calle.",
                 symbol: "figure.walk", group: .solo, focus: .lugar),

        // Una persona · ambiente
        PoseIdea(id: "a1", title: "Café en mano", detail: "Sostén tu bebida cerca del pecho y mira hacia la ventana.",
                 symbol: "cup.and.saucer.fill", group: .solo, focus: .ambiente),
        PoseIdea(id: "a2", title: "Riendo", detail: "Ríe de verdad y tápate un poco la boca.",
                 symbol: "face.smiling.inverse", group: .solo, focus: .ambiente),
        PoseIdea(id: "a3", title: "Movimiento", detail: "Gira o sacude el cabello o la chamarra; usa el temporizador.",
                 symbol: "figure.dance", group: .solo, focus: .ambiente),
        PoseIdea(id: "a4", title: "Flash directo", detail: "De noche, modo G7X con flash y mirada seria a la cámara.",
                 symbol: "bolt.fill", group: .solo, focus: .ambiente),
        PoseIdea(id: "a5", title: "Selfie de espejo", detail: "Teléfono a la altura del pecho y cadera hacia un lado.",
                 symbol: "iphone", group: .solo, focus: .ambiente),
        PoseIdea(id: "a6", title: "Solo detalles", detail: "Solo manos, accesorios o zapatos; sin cara.",
                 symbol: "hand.raised.fingers.spread.fill", group: .solo, focus: .ambiente),

        // Pareja
        PoseIdea(id: "p1", title: "Frente a frente", detail: "Mírense de cerca, con las frentes casi juntas.",
                 symbol: "person.2.fill", group: .pareja, focus: nil),
        PoseIdea(id: "p2", title: "De la mano", detail: "Caminen hacia la cámara de la mano, mirándose.",
                 symbol: "figure.walk", group: .pareja, focus: nil),
        PoseIdea(id: "p3", title: "Abrazo por detrás", detail: "Uno abraza al otro por la espalda; ambos miran a la cámara.",
                 symbol: "heart.fill", group: .pareja, focus: nil),
        PoseIdea(id: "p4", title: "Secreto", detail: "Uno le dice algo al oído al otro; capta la risa.",
                 symbol: "ear.fill", group: .pareja, focus: nil),
        PoseIdea(id: "p5", title: "Espalda con espalda", detail: "Recárguense espalda con espalda, brazos cruzados.",
                 symbol: "arrow.left.and.right", group: .pareja, focus: nil),
        PoseIdea(id: "p6", title: "Sentados juntos", detail: "Lado a lado; uno recarga la cabeza en el hombro del otro.",
                 symbol: "sofa.fill", group: .pareja, focus: nil),

        // Grupo
        PoseIdea(id: "g1", title: "Escalonados", detail: "Unos sentados y otros de pie; que no queden en línea.",
                 symbol: "person.3.fill", group: .grupo, focus: nil),
        PoseIdea(id: "g2", title: "Caminando juntos", detail: "Caminen hacia la cámara platicando entre ustedes.",
                 symbol: "figure.walk", group: .grupo, focus: nil),
        PoseIdea(id: "g3", title: "Abrazo de grupo", detail: "Brazos sobre los hombros, cabezas un poco al centro.",
                 symbol: "person.3.sequence.fill", group: .grupo, focus: nil),
        PoseIdea(id: "g4", title: "Desde arriba", detail: "Todos miran hacia arriba, a la cámara en alto.",
                 symbol: "arrow.up.circle", group: .grupo, focus: nil),
        PoseIdea(id: "g5", title: "Salto", detail: "Salten al mismo tiempo con el temporizador de 3 s.",
                 symbol: "figure.jumprope", group: .grupo, focus: nil),
        PoseIdea(id: "g6", title: "Triángulo", detail: "El más alto al centro y atrás; los demás a los lados.",
                 symbol: "triangle.fill", group: .grupo, focus: nil)
    ]

    static func ideas(for group: PeopleGroup, focus: PoseFocus) -> [PoseIdea] {
        if group == .solo {
            return all.filter { $0.group == .solo && $0.focus == focus }
        }
        return all.filter { $0.group == group }
    }
}
