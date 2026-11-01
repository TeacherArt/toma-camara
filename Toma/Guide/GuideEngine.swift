import CoreGraphics
import Foundation

enum GuideArrow: Equatable {
    case left, right, up, down, closer, back, rotateLeft, rotateRight

    var icon: String {
        switch self {
        case .left: return "arrow.left"
        case .right: return "arrow.right"
        case .up: return "arrow.up"
        case .down: return "arrow.down"
        case .closer: return "arrow.down.right.and.arrow.up.left"
        case .back: return "arrow.up.left.and.arrow.down.right"
        case .rotateLeft: return "arrow.counterclockwise"
        case .rotateRight: return "arrow.clockwise"
        }
    }
}

struct GuideAdvice: Equatable {
    var message: String
    var tip: String
    var arrow: GuideArrow?
    var target: CGRect?
    var subject: CGRect?
    var good = false
}

/// Convierte lo que ve la cámara en indicaciones concretas para mejorar la toma.
enum GuideEngine {
    static func advise(_ reading: SceneReading, level: LevelReading) -> GuideAdvice {
        let flat = level.gz < -0.8
        // Primero, que el teléfono esté derecho (salvo en tomas cenitales).
        if !flat, reading.kind != .buscando, abs(level.roll) > 3 {
            return GuideAdvice(message: "Endereza el teléfono",
                               tip: "Las líneas rectas hacen que la foto se vea profesional.",
                               arrow: level.roll > 0 ? .rotateLeft : .rotateRight,
                               subject: reading.subject)
        }

        switch reading.kind {
        case .buscando:
            return GuideAdvice(message: "Analizando la escena…", tip: "Apunta a lo que quieres fotografiar.")

        case .retrato:
            guard let face = reading.subject else { return generic(reading) }
            let target = CGRect(x: 0.5 - face.width / 2, y: 0.36 - face.height / 2, width: face.width, height: face.height)
            if face.height > 0.55 {
                return GuideAdvice(message: "Aléjate un poco", tip: "Deja aire arriba de la cabeza.",
                                   arrow: .back, target: target, subject: face)
            }
            return positioned(subject: face, target: target,
                              good: "¡Así! Ojos en el tercio superior",
                              tip: "Luz de frente o de lado. Cámara a la altura de los ojos.")

        case .persona:
            guard let body = reading.subject else { return generic(reading) }
            if body.maxY > 0.97, body.height > 0.75 {
                return GuideAdvice(message: "Aléjate un paso: se cortan los pies",
                                   tip: "Deja un poco de espacio bajo los pies.", arrow: .back, subject: body)
            }
            if body.height < 0.45 {
                return GuideAdvice(message: "Acércate un poco", tip: "Que la persona ocupe más del cuadro.",
                                   arrow: .closer, subject: body)
            }
            let target = CGRect(x: 0.5 - body.width / 2, y: 0.06, width: body.width, height: body.height)
            return positioned(subject: body, target: target,
                              good: "¡Buen encuadre de cuerpo completo!",
                              tip: "Baja la cámara a la altura de la cintura y apunta un poco arriba: alarga las piernas.")

        case .pareja, .grupo:
            guard let all = reading.subject else { return generic(reading) }
            if all.minX < 0.03 || all.maxX > 0.97 {
                return GuideAdvice(message: "Aléjate o usa .5× para que quepan todos",
                                   tip: "Deja margen a los lados.", arrow: .back, subject: all)
            }
            let target = CGRect(x: 0.5 - all.width / 2, y: max(0.08, 0.45 - all.height / 2),
                                width: all.width, height: all.height)
            let tip = reading.kind == .pareja
                ? "Hombros en ángulo, cerca uno del otro; mírense o miren a la cámara."
                : "Escalonen alturas y dejen poco espacio entre ustedes."
            return positioned(subject: all, target: target, good: "¡Todos dentro y centrados!", tip: tip)

        case .paisaje:
            return thirds(reading, good: "Horizonte derecho. ¡Dispara!",
                          tip: "Pon el horizonte en el tercio de abajo si el cielo está bonito; si no, en el de arriba.")

        case .atardecer:
            return thirds(reading, good: "Sol en un tercio. ¡Perfecto!",
                          tip: "Toca el cielo para exponer bien y baja un poco la exposición para colores intensos.")

        case .noche:
            return GuideAdvice(message: "Mantén el teléfono muy quieto",
                               tip: "Apóyalo o usa el temporizador. Para la luna, usa 2× y baja la exposición.",
                               subject: reading.subject)

        case .comida:
            if !flat {
                return GuideAdvice(message: "Prueba desde arriba",
                                   tip: "Teléfono paralelo a la mesa para una toma cenital limpia.",
                                   arrow: .down, subject: reading.subject)
            }
            return GuideAdvice(message: "¡Toma cenital perfecta!",
                               tip: "Luz de ventana de lado; quita lo que distraiga.",
                               subject: reading.subject, good: true)

        case .cuarto:
            if abs(level.gz) > 0.18 {
                return GuideAdvice(message: "Mantén el teléfono vertical",
                                   tip: "Baja la cámara a la altura de la repisa para una perspectiva recta y limpia.",
                                   arrow: level.gz < 0 ? .up : .down, subject: reading.subject)
            }
            return thirds(reading, good: "Líneas rectas. ¡Bien!",
                          tip: "Baja la cámara a la altura de la repisa para una perspectiva recta y limpia.")

        case .detalle:
            return thirds(reading, good: "Detalle en su lugar",
                          tip: "Acércate, busca un fondo simple y luz suave. Ideal para tu dump de IG.")
        }
    }

    private static func generic(_ reading: SceneReading) -> GuideAdvice {
        GuideAdvice(message: reading.kind.title.capitalized, tip: "Busca buena luz y un fondo limpio.",
                    subject: reading.subject)
    }

    /// Lleva al sujeto al punto de tercios más cercano.
    private static func thirds(_ reading: SceneReading, good: String, tip: String) -> GuideAdvice {
        guard let subject = reading.subject else {
            return GuideAdvice(message: good, tip: tip, good: true)
        }
        let points = [CGPoint(x: 1.0 / 3, y: 1.0 / 3), CGPoint(x: 2.0 / 3, y: 1.0 / 3),
                      CGPoint(x: 1.0 / 3, y: 2.0 / 3), CGPoint(x: 2.0 / 3, y: 2.0 / 3)]
        let center = CGPoint(x: subject.midX, y: subject.midY)
        let nearest = points.min { hypot($0.x - center.x, $0.y - center.y) < hypot($1.x - center.x, $1.y - center.y) }
            ?? CGPoint(x: 0.5, y: 0.5)
        // Si el sujeto es muy grande, centrarlo está bien.
        let anchor = subject.width > 0.55 ? CGPoint(x: 0.5, y: center.y) : nearest
        let target = CGRect(x: anchor.x - subject.width / 2, y: anchor.y - subject.height / 2,
                            width: subject.width, height: subject.height)
        return positioned(subject: subject, target: target, good: good, tip: tip)
    }

    private static func positioned(subject: CGRect, target: CGRect, good: String, tip: String) -> GuideAdvice {
        let dx = subject.midX - target.midX
        let dy = subject.midY - target.midY
        let tolerance: CGFloat = 0.06
        if abs(dx) < tolerance, abs(dy) < tolerance {
            return GuideAdvice(message: good, tip: tip, target: target, subject: subject, good: true)
        }
        // Mover la cámara hacia el sujeto lo lleva hacia el centro del cuadro.
        if abs(dx) >= abs(dy) {
            return GuideAdvice(message: dx > 0 ? "Mueve a la derecha" : "Mueve a la izquierda",
                               tip: tip, arrow: dx > 0 ? .right : .left, target: target, subject: subject)
        }
        return GuideAdvice(message: dy > 0 ? "Baja un poco la cámara" : "Sube un poco la cámara",
                           tip: tip, arrow: dy > 0 ? .down : .up, target: target, subject: subject)
    }
}
