import Combine
import CoreMotion
import QuartzCore
import Vision

enum SceneKind: String {
    case buscando, retrato, persona, pareja, grupo, paisaje, atardecer, noche, comida, cuarto, detalle

    var title: String {
        switch self {
        case .buscando: return "ANALIZANDO"
        case .retrato: return "RETRATO"
        case .persona: return "PERSONA"
        case .pareja: return "PAREJA"
        case .grupo: return "GRUPO"
        case .paisaje: return "PAISAJE"
        case .atardecer: return "ATARDECER"
        case .noche: return "NOCHE / LUNA"
        case .comida: return "COMIDA"
        case .cuarto: return "CUARTO"
        case .detalle: return "DUMP / DETALLE"
        }
    }

    var icon: String {
        switch self {
        case .buscando: return "viewfinder"
        case .retrato: return "person.crop.square"
        case .persona: return "figure.stand"
        case .pareja: return "person.2.fill"
        case .grupo: return "person.3.fill"
        case .paisaje: return "mountain.2.fill"
        case .atardecer: return "sun.horizon.fill"
        case .noche: return "moon.stars.fill"
        case .comida: return "fork.knife"
        case .cuarto: return "sofa.fill"
        case .detalle: return "sparkles"
        }
    }
}

/// Lo que se ve en el cuadro. Las cajas están normalizadas (0–1) con origen arriba a la izquierda,
/// igual que la vista previa vertical.
struct SceneReading: Equatable {
    var kind: SceneKind = .buscando
    var people = 0
    var faces: [CGRect] = []
    var bodies: [CGRect] = []
    var subject: CGRect?
}

/// Analiza la escena con Vision unas 4 veces por segundo, sin frenar la vista previa.
final class SceneAnalyzer: ObservableObject {
    @Published private(set) var reading = SceneReading()
    @Published private(set) var stillProgress: Double = 0

    var onStillShot: (() -> Void)?
    var autoShot = false

    private let queue = DispatchQueue(label: "toma.vision", qos: .userInitiated)
    private let lock = NSLock()
    private var busy = false
    private var lastRun: CFTimeInterval = 0

    // Solo en `queue`
    private var lastClassify: CFTimeInterval = 0
    private var labels: [String: Float] = [:]
    private var lastJoints: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
    private var stillTime: Double = 0
    private var lastPoseTime: CFTimeInterval = 0
    private var cooldownUntil: CFTimeInterval = 0
    private var smoothedKind: SceneKind = .buscando
    private var kindVotes: [SceneKind] = []

    func reset() {
        DispatchQueue.main.async {
            self.reading = SceneReading()
            self.stillProgress = 0
        }
    }

    func submit(_ pixelBuffer: CVPixelBuffer, front: Bool) {
        let now = CACurrentMediaTime()
        lock.lock()
        if busy || now - lastRun < 0.25 {
            lock.unlock()
            return
        }
        busy = true
        lastRun = now
        lock.unlock()

        let wantsPose = autoShot
        queue.async {
            self.analyze(pixelBuffer, front: front, wantsPose: wantsPose, now: now)
            self.lock.lock()
            self.busy = false
            self.lock.unlock()
        }
    }

    private func analyze(_ pixelBuffer: CVPixelBuffer, front: Bool, wantsPose: Bool, now: CFTimeInterval) {
        let orientation: CGImagePropertyOrientation = front ? .leftMirrored : .right
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])

        let faces = VNDetectFaceRectanglesRequest()
        let humans = VNDetectHumanRectanglesRequest()
        humans.upperBodyOnly = false
        let saliency = VNGenerateAttentionBasedSaliencyImageRequest()
        var requests: [VNRequest] = [faces, humans, saliency]

        var classify: VNClassifyImageRequest?
        if now - lastClassify > 1.0 {
            let request = VNClassifyImageRequest()
            classify = request
            requests.append(request)
            lastClassify = now
        }
        var body: VNDetectHumanBodyPoseRequest?
        if wantsPose {
            let request = VNDetectHumanBodyPoseRequest()
            body = request
            requests.append(request)
        }

        do {
            try handler.perform(requests)
        } catch {
            return
        }

        let faceBoxes = (faces.results ?? []).map { Self.flip($0.boundingBox) }
            .filter { $0.width * $0.height > 0.002 }
        let bodyBoxes = (humans.results ?? []).map { Self.flip($0.boundingBox) }
            .filter { $0.width * $0.height > 0.01 }
        let salient = saliency.results?.first?.salientObjects?
            .max { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height }
            .map { Self.flip($0.boundingBox) }

        if let classify, let results = classify.results {
            var map: [String: Float] = [:]
            for observation in results.prefix(40) where observation.confidence > 0.2 {
                map[observation.identifier.lowercased()] = observation.confidence
            }
            labels = map
        }

        let people = max(faceBoxes.count, bodyBoxes.count)
        var kind: SceneKind
        if people >= 3 {
            kind = .grupo
        } else if people == 2 {
            kind = .pareja
        } else if people == 1 {
            let faceArea = faceBoxes.map { $0.width * $0.height }.max() ?? 0
            kind = faceArea > 0.045 ? .retrato : .persona
        } else {
            kind = Self.kind(from: labels)
        }
        kind = smooth(kind)

        var subject: CGRect?
        switch kind {
        case .retrato: subject = faceBoxes.max { $0.width * $0.height < $1.width * $1.height }
        case .persona: subject = bodyBoxes.max { $0.height < $1.height } ?? faceBoxes.first
        case .pareja, .grupo: subject = Self.union(bodyBoxes.isEmpty ? faceBoxes : bodyBoxes)
        default: subject = salient
        }

        var progress: Double = 0
        if wantsPose, let observation = body?.results?.first {
            progress = updateStillness(observation, now: now)
        } else {
            lastJoints = [:]
            stillTime = 0
        }

        let reading = SceneReading(kind: kind, people: people, faces: faceBoxes, bodies: bodyBoxes, subject: subject)
        DispatchQueue.main.async {
            if self.reading != reading { self.reading = reading }
            self.stillProgress = progress
        }
    }

    /// Evita que el tipo de escena cambie a cada rato: necesita la mayoría de las últimas lecturas.
    private func smooth(_ kind: SceneKind) -> SceneKind {
        kindVotes.append(kind)
        if kindVotes.count > 5 { kindVotes.removeFirst() }
        var counts: [SceneKind: Int] = [:]
        for vote in kindVotes { counts[vote, default: 0] += 1 }
        if let best = counts.max(by: { $0.value < $1.value }), best.value >= 3 {
            smoothedKind = best.key
        } else if smoothedKind == .buscando {
            smoothedKind = kind
        }
        return smoothedKind
    }

    /// Disparo automático: cuando la persona se queda quieta ~1.2 s en su pose.
    private func updateStillness(_ observation: VNHumanBodyPoseObservation, now: CFTimeInterval) -> Double {
        guard let points = try? observation.recognizedPoints(.all) else { return 0 }
        var joints: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
        for (name, point) in points where point.confidence > 0.3 {
            joints[name] = point.location
        }
        let dt = lastPoseTime > 0 ? min(now - lastPoseTime, 0.6) : 0
        lastPoseTime = now
        guard joints.count >= 8 else {
            lastJoints = [:]
            stillTime = 0
            return 0
        }
        var total: CGFloat = 0
        var count: CGFloat = 0
        for (name, point) in joints {
            if let previous = lastJoints[name] {
                total += hypot(point.x - previous.x, point.y - previous.y)
                count += 1
            }
        }
        lastJoints = joints
        let movement = count > 0 ? total / count : 1
        stillTime = movement < 0.012 ? stillTime + dt : 0

        let needed = 1.2
        if stillTime >= needed, now > cooldownUntil {
            stillTime = 0
            cooldownUntil = now + 3
            DispatchQueue.main.async { self.onStillShot?() }
            return 0
        }
        return now > cooldownUntil ? min(stillTime / needed, 1) : 0
    }

    private static func kind(from labels: [String: Float]) -> SceneKind {
        func has(_ keys: [String], minimum: Float = 0.25) -> Bool {
            labels.contains { key, value in value >= minimum && keys.contains { key.contains($0) } }
        }
        if has(["food", "dish", "dessert", "meal", "drink", "coffee", "cake", "pizza", "fruit", "baked", "taco", "bread", "cocktail"]) {
            return .comida
        }
        if has(["sunset", "sunrise", "dusk"]) { return .atardecer }
        if has(["night", "moon", "star", "firework"]) { return .noche }
        if has(["mountain", "beach", "ocean", "sea", "lake", "sky", "cloud", "landscape", "field", "forest",
                "desert", "shore", "river", "hill", "volcano", "canyon", "waterfall", "park", "outdoor"]) {
            return .paisaje
        }
        if has(["interior", "room", "furniture", "shelf", "bedroom", "living", "kitchen", "sofa", "table", "decor", "lamp"]) {
            return .cuarto
        }
        return labels.isEmpty ? .buscando : .detalle
    }

    private static func flip(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: 1 - rect.maxY, width: rect.width, height: rect.height)
    }

    private static func union(_ rects: [CGRect]) -> CGRect? {
        guard var result = rects.first else { return nil }
        for rect in rects.dropFirst() { result = result.union(rect) }
        return result
    }
}

// MARK: - Nivel con el acelerómetro

struct LevelReading: Equatable {
    /// Inclinación lateral en grados (0 = derecho).
    var roll: Double = 0
    /// -1 = teléfono acostado mirando hacia abajo (toma cenital).
    var gz: Double = 0
}

final class LevelMonitor: ObservableObject {
    @Published private(set) var reading = LevelReading()
    private let manager = CMMotionManager()

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 15
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let g = motion?.gravity else { return }
            let roll = atan2(g.x, -g.y) * 180 / .pi
            let next = LevelReading(roll: roll, gz: g.z)
            if abs(next.roll - self.reading.roll) > 0.3 || abs(next.gz - self.reading.gz) > 0.02 {
                self.reading = next
            }
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }
}
