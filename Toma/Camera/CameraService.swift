import AVFoundation
import CoreImage
import CoreLocation
import ImageIO
import UIKit

enum CaptureMode: String, CaseIterable, Identifiable {
    case video, photo, g7x, raw

    var id: String { rawValue }

    var title: String {
        switch self {
        case .video: return "VIDEO"
        case .photo: return "FOTO"
        case .g7x: return "G7X"
        case .raw: return "RAW"
        }
    }

    var isPhoto: Bool { self != .video }
}

enum FlashSetting: CaseIterable {
    case off, auto, on

    var icon: String {
        switch self {
        case .off: return "bolt.slash"
        case .auto: return "bolt.badge.automatic"
        case .on: return "bolt.fill"
        }
    }

    var avMode: AVCaptureDevice.FlashMode {
        switch self {
        case .off: return .off
        case .auto: return .auto
        case .on: return .on
        }
    }
}

enum TimerSetting: Int, CaseIterable {
    case off = 0, three = 3, ten = 10

    var label: String { self == .off ? "" : "\(rawValue)s" }
}

struct ShotInfo {
    var date = Date()
    var iso: Int?
    var exposure: Double?
    var aperture: Double?
    var focal35: Int?
    var lens: String?
    var isFront = false
    var location: CLLocation?

    init() {}

    /// Lee los datos de la toma (EXIF y GPS) de los metadatos de una foto.
    init(metadata: [String: Any], front: Bool = false) {
        isFront = front
        if let exif = metadata[kCGImagePropertyExifDictionary as String] as? [String: Any] {
            iso = (exif[kCGImagePropertyExifISOSpeedRatings as String] as? [NSNumber])?.first?.intValue
            exposure = (exif[kCGImagePropertyExifExposureTime as String] as? NSNumber)?.doubleValue
            aperture = (exif[kCGImagePropertyExifFNumber as String] as? NSNumber)?.doubleValue
            focal35 = (exif[kCGImagePropertyExifFocalLenIn35mmFilm as String] as? NSNumber)?.intValue
            lens = exif[kCGImagePropertyExifLensModel as String] as? String
            if let original = exif[kCGImagePropertyExifDateTimeOriginal as String] as? String {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
                if let parsed = formatter.date(from: original) { date = parsed }
            }
        }
        if let gps = metadata[kCGImagePropertyGPSDictionary as String] as? [String: Any],
           let lat = (gps[kCGImagePropertyGPSLatitude as String] as? NSNumber)?.doubleValue,
           let lon = (gps[kCGImagePropertyGPSLongitude as String] as? NSNumber)?.doubleValue {
            let latRef = gps[kCGImagePropertyGPSLatitudeRef as String] as? String ?? "N"
            let lonRef = gps[kCGImagePropertyGPSLongitudeRef as String] as? String ?? "E"
            location = CLLocation(latitude: latRef == "S" ? -lat : lat, longitude: lonRef == "W" ? -lon : lon)
        }
    }

    init(imageData: Data) {
        if let source = CGImageSourceCreateWithData(imageData as CFData, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] {
            self.init(metadata: props)
        } else {
            self.init()
        }
    }
}

struct CapturedShot: Identifiable {
    let id = UUID()
    let image: CIImage
    let info: ShotInfo
    let raw: Data?
}

/// Controla la cámara: sesión, vista previa con estilo en vivo, fotos, RAW y video doble.
final class CameraService: NSObject, ObservableObject {
    // MARK: Estado para la interfaz (hilo principal)
    @Published private(set) var mode: CaptureMode = .photo
    @Published private(set) var isRecording = false
    @Published private(set) var recordingSeconds = 0
    @Published private(set) var isFront = false
    @Published private(set) var zoomStops: [CGFloat] = [1]
    @Published private(set) var zoomDisplay: CGFloat = 1
    @Published var style: LookStyle = .film { didSet { syncPipeline() } }
    @Published private(set) var flash: FlashSetting = .off
    @Published private(set) var timer: TimerSetting = .off
    @Published var dualFormat = true
    @Published var flatVideo = false { didSet { syncPipeline() } }
    @Published private(set) var maxResolution = false
    @Published var guideOn = false { didSet { guideChanged() } }
    @Published var autoPoseShot = false { didSet { analyzer.autoShot = autoPoseShot } }
    @Published private(set) var countdown = 0
    @Published var lastShot: CapturedShot?
    @Published var lastThumbnail: UIImage?
    @Published private(set) var cameraDenied = false
    @Published private(set) var toastText: String?
    @Published private(set) var shutterBlink = false

    let session = AVCaptureSession()
    let previewRenderer = PreviewRenderer.make()
    let analyzer = SceneAnalyzer()
    let level = LevelMonitor()

    // MARK: Interno
    private let sessionQueue = DispatchQueue(label: "toma.session")
    private let videoQueue = DispatchQueue(label: "toma.video", qos: .userInitiated)
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?
    private var zoomBase: CGFloat = 1
    private var maxZoomDisplay: CGFloat = 10
    private var pinchStartZoom: CGFloat = 1
    private var inFlight: [Int64: PhotoProcessor] = [:]
    private var configured = false
    private var editorOpen = false
    private var styleBeforeG7X: LookStyle?
    private var flashBeforeG7X: FlashSetting = .off

    // Estado del flujo de video (solo en videoQueue)
    private var pipelineStyle: LookStyle = .film
    private var pipelineFront = false
    private var pipelineGuide = false
    private var frameCounter = 0
    private let recorder = DualRecorder()
    private let renderContext = CIContext(options: [.cacheIntermediates: false])

    private var countdownTimer: Timer?
    private var recordingTimer: Timer?
    private var toastWork: DispatchWorkItem?

    override init() {
        super.init()
        analyzer.onStillShot = { [weak self] in self?.autoShoot() }
    }

    private var effectiveStyle: LookStyle {
        (mode == .video && flatVideo) ? .plano : style
    }

    private func syncPipeline() {
        let style = effectiveStyle
        let guide = guideOn
        videoQueue.async {
            self.pipelineStyle = style
            self.pipelineGuide = guide
        }
    }

    private func guideChanged() {
        if guideOn { level.start() } else { level.stop(); analyzer.reset() }
        syncPipeline()
    }

    // MARK: Arranque

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            run()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted { self.run() } else { self.cameraDenied = true }
                }
            }
        default:
            cameraDenied = true
        }
    }

    private func run() {
        let front = isFront, currentMode = mode, maxRes = maxResolution
        syncPipeline()
        sessionQueue.async {
            if !self.configured {
                self.configure(front: front, mode: currentMode, maxRes: maxRes)
                self.configured = true
            }
            if !self.session.isRunning { self.session.startRunning() }
        }
    }

    /// Mientras el editor está abierto se pausa la cámara para ahorrar batería.
    func setEditorOpen(_ open: Bool) {
        editorOpen = open
        sessionQueue.async {
            guard self.configured else { return }
            if open {
                if self.session.isRunning { self.session.stopRunning() }
            } else if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    private func reconfigure() {
        let front = isFront, currentMode = mode, maxRes = maxResolution
        sessionQueue.async { self.configure(front: front, mode: currentMode, maxRes: maxRes) }
    }

    // MARK: Configuración de la sesión (sessionQueue)

    /// Si AVFoundation rechaza algún ajuste, se muestra el error en pantalla en vez de cerrar la app.
    private func configure(front: Bool, mode: CaptureMode, maxRes: Bool) {
        let failure = ExceptionCatcher.catchException {
            self.configureUnsafe(front: front, mode: mode, maxRes: maxRes)
        }
        if let failure {
            _ = ExceptionCatcher.catchException { self.session.commitConfiguration() }
            report("Error de cámara: \(failure)")
        }
    }

    private func report(_ message: String) {
        DispatchQueue.main.async { self.toast(message) }
    }

    private func configureUnsafe(front: Bool, mode: CaptureMode, maxRes: Bool) {
        session.beginConfiguration()

        if let current = videoInput {
            session.removeInput(current)
            videoInput = nil
        }
        let chosen: AVCaptureDevice?
        if front {
            chosen = Self.frontCamera()
        } else if mode == .raw {
            // El RAW (Bayer) solo funciona con una cámara física, no con la virtual.
            chosen = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        } else {
            chosen = Self.backCamera()
        }
        guard let device = chosen,
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)
        videoInput = input

        if !session.outputs.contains(videoOutput), session.canAddOutput(videoOutput) {
            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            ]
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
            session.addOutput(videoOutput)
        }

        if mode.isPhoto {
            if let mic = audioInput {
                session.removeInput(mic)
                audioInput = nil
            }
            if session.outputs.contains(audioOutput) { session.removeOutput(audioOutput) }
            if session.canSetSessionPreset(.photo) { session.sessionPreset = .photo }
            if !session.outputs.contains(photoOutput), session.canAddOutput(photoOutput) {
                session.addOutput(photoOutput)
            }
        } else {
            if session.outputs.contains(photoOutput) { session.removeOutput(photoOutput) }
            if let format = Self.bestVideoFormat(for: device) {
                do {
                    try device.lockForConfiguration()
                    device.activeFormat = format
                    device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
                    device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
                    device.unlockForConfiguration()
                } catch {}
            } else if session.canSetSessionPreset(.high) {
                session.sessionPreset = .high
            }
            if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized, audioInput == nil,
               let mic = AVCaptureDevice.default(for: .audio),
               let micInput = try? AVCaptureDeviceInput(device: mic),
               session.canAddInput(micInput) {
                session.addInput(micInput)
                audioInput = micInput
            }
            if audioInput != nil, !session.outputs.contains(audioOutput), session.canAddOutput(audioOutput) {
                audioOutput.setSampleBufferDelegate(self, queue: videoQueue)
                session.addOutput(audioOutput)
            }
        }

        // Fotos en vertical; la selfie se guarda como espejo, igual que en la vista previa.
        if let connection = photoOutput.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = front
            }
        }
        if let connection = videoOutput.connection(with: .video), connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = false
        }

        videoQueue.async { self.pipelineFront = front }
        setupZoom(device: device, front: front)
        session.commitConfiguration()

        // La resolución de foto se fija después de aplicar el formato de la sesión.
        if mode.isPhoto, session.outputs.contains(photoOutput) {
            session.beginConfiguration()
            configurePhotoOutput(device: device, maxRes: maxRes, raw: mode == .raw)
            session.commitConfiguration()
        }
    }

    private func configurePhotoOutput(device: AVCaptureDevice, maxRes: Bool, raw: Bool) {
        let dims = device.activeFormat.supportedMaxPhotoDimensions.sorted {
            Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height)
        }
        let target: CMVideoDimensions?
        if raw {
            target = dims.last(where: { Int($0.width) * Int($0.height) <= 13_000_000 }) ?? dims.first
        } else if maxRes {
            target = dims.last
        } else {
            target = dims.last(where: { Int($0.width) * Int($0.height) <= 26_000_000 }) ?? dims.last
        }
        if let target { photoOutput.maxPhotoDimensions = target }
        photoOutput.maxPhotoQualityPrioritization = .quality
    }

    private func setupZoom(device: AVCaptureDevice, front: Bool) {
        var base: CGFloat = 1
        if device.isVirtualDevice, let first = device.virtualDeviceSwitchOverVideoZoomFactors.first {
            base = CGFloat(truncating: first)
        }
        zoomBase = base
        var stops: [CGFloat] = base > 1 ? [0.5, 1, 2] : (front ? [1] : [1, 2])
        stops = stops.filter { $0 * base <= device.maxAvailableVideoZoomFactor }
        let maxDisplay = min(device.maxAvailableVideoZoomFactor / base, 10)
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = min(base, device.maxAvailableVideoZoomFactor)
            device.unlockForConfiguration()
        } catch {}
        DispatchQueue.main.async {
            self.zoomStops = stops
            self.zoomDisplay = 1
            self.maxZoomDisplay = maxDisplay
        }
    }

    private static func backCamera() -> AVCaptureDevice? {
        let types: [AVCaptureDevice.DeviceType] = [.builtInTripleCamera, .builtInDualWideCamera, .builtInWideAngleCamera]
        let found = AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .video, position: .back).devices
        for type in types {
            if let device = found.first(where: { $0.deviceType == type }) { return device }
        }
        return AVCaptureDevice.default(for: .video)
    }

    private static func frontCamera() -> AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
    }

    /// Formato 4:3 a 30 cps: deja sacar el corte vertical y el horizontal del mismo cuadro.
    private static func bestVideoFormat(for device: AVCaptureDevice) -> AVCaptureDevice.Format? {
        func width(_ format: AVCaptureDevice.Format) -> Int32 {
            CMVideoFormatDescriptionGetDimensions(format.formatDescription).width
        }
        let candidates = device.formats.filter { format in
            let d = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let ratio = Double(d.width) / Double(d.height)
            let subtype = CMFormatDescriptionGetMediaSubType(format.formatDescription)
            return abs(ratio - 4.0 / 3.0) < 0.01
                && d.width >= 1920 && d.width <= 4032
                && subtype == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
                && format.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= 30 }
        }
        let preferred = candidates.filter { width($0) <= 3264 }.max { width($0) < width($1) }
        return preferred ?? candidates.max { width($0) < width($1) }
    }

    // MARK: Controles

    func setMode(_ newMode: CaptureMode) {
        guard newMode != mode, !isRecording, countdown == 0 else { return }
        let old = mode
        mode = newMode
        UISelectionFeedbackGenerator().selectionChanged()

        if newMode == .g7x {
            styleBeforeG7X = style
            flashBeforeG7X = flash
            style = .g7x
            flash = .on
        } else if old == .g7x {
            if let previous = styleBeforeG7X { style = previous }
            flash = flashBeforeG7X
        }
        if newMode == .raw && isFront { isFront = false }
        syncPipeline()

        let needsReconfig = (old == .video) != (newMode == .video) || old == .raw || newMode == .raw
        guard needsReconfig else { return }
        if newMode == .video, AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                DispatchQueue.main.async { self.reconfigure() }
            }
        } else {
            reconfigure()
        }
    }

    func nextMode(_ step: Int) {
        let all = CaptureMode.allCases
        guard let index = all.firstIndex(of: mode) else { return }
        let next = index + step
        guard next >= 0, next < all.count else { return }
        setMode(all[next])
    }

    func flipCamera() {
        guard !isRecording else { return }
        if mode == .raw {
            toast("El RAW solo funciona con la cámara trasera")
            return
        }
        isFront.toggle()
        zoomDisplay = 1
        reconfigure()
    }

    func setZoom(_ display: CGFloat) {
        zoomDisplay = display
        sessionQueue.async {
            guard let device = self.videoInput?.device else { return }
            let factor = max(device.minAvailableVideoZoomFactor,
                             min(display * self.zoomBase, device.maxAvailableVideoZoomFactor))
            do {
                try device.lockForConfiguration()
                device.ramp(toVideoZoomFactor: factor, withRate: 10)
                device.unlockForConfiguration()
            } catch {}
        }
    }

    func beginPinch() { pinchStartZoom = zoomDisplay }

    func pinch(_ magnification: CGFloat) {
        let minDisplay = zoomStops.first ?? 1
        let display = min(max(pinchStartZoom * magnification, minDisplay), maxZoomDisplay)
        zoomDisplay = display
        sessionQueue.async {
            guard let device = self.videoInput?.device else { return }
            let factor = max(device.minAvailableVideoZoomFactor,
                             min(display * self.zoomBase, device.maxAvailableVideoZoomFactor))
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = factor
                device.unlockForConfiguration()
            } catch {}
        }
    }

    func cycleFlash() {
        let all = FlashSetting.allCases
        let index = all.firstIndex(of: flash) ?? 0
        flash = all[(index + 1) % all.count]
    }

    func cycleTimer() {
        let all = TimerSetting.allCases
        let index = all.firstIndex(of: timer) ?? 0
        timer = all[(index + 1) % all.count]
    }

    func setMaxResolution(_ on: Bool) {
        maxResolution = on
        let raw = mode == .raw
        sessionQueue.async {
            guard let device = self.videoInput?.device, self.session.outputs.contains(self.photoOutput) else { return }
            let failure = ExceptionCatcher.catchException {
                self.session.beginConfiguration()
                self.configurePhotoOutput(device: device, maxRes: on, raw: raw)
                self.session.commitConfiguration()
            }
            if let failure {
                _ = ExceptionCatcher.catchException { self.session.commitConfiguration() }
                self.report("Error de cámara: \(failure)")
            }
        }
        toast(on ? "Fotos a máxima resolución (48 MP)" : "Fotos a 24 MP")
    }

    func toast(_ text: String) {
        toastText = text
        toastWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.toastText = nil }
        toastWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4, execute: work)
    }

    // MARK: Disparo

    func shutter() {
        if mode == .video {
            if isRecording { stopRecording() } else { startRecording() }
            return
        }
        guard countdown == 0 else { return }
        if timer == .off {
            capturePhoto()
        } else {
            runCountdown(timer.rawValue)
        }
    }

    private func autoShoot() {
        guard mode.isPhoto, !isRecording, countdown == 0, !editorOpen, lastShot == nil else { return }
        toast("Disparo automático")
        capturePhoto()
    }

    private func runCountdown(_ seconds: Int) {
        countdown = seconds
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            self.countdown -= 1
            if self.countdown <= 0 {
                t.invalidate()
                self.countdown = 0
                self.capturePhoto()
            }
        }
    }

    private func capturePhoto() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        shutterBlink = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { self.shutterBlink = false }
        let flashMode = flash.avMode
        let front = isFront
        let wantsRaw = mode == .raw
        sessionQueue.async {
            guard self.session.outputs.contains(self.photoOutput) else { return }
            let output = self.photoOutput
            let processedFormat: [String: Any] = output.availablePhotoCodecTypes.contains(.hevc)
                ? [AVVideoCodecKey: AVVideoCodecType.hevc]
                : [AVVideoCodecKey: AVVideoCodecType.jpeg]

            var settings = AVCapturePhotoSettings(format: processedFormat)
            var isRaw = false
            if wantsRaw,
               let rawType = output.availableRawPhotoPixelFormatTypes.first(where: { AVCapturePhotoOutput.isBayerRAWPixelFormat($0) }) {
                settings = AVCapturePhotoSettings(rawPixelFormatType: rawType, processedFormat: processedFormat)
                isRaw = true
            } else if wantsRaw {
                self.report("Este modo de cámara no ofrece RAW; se toma foto normal")
            }
            settings.maxPhotoDimensions = output.maxPhotoDimensions
            settings.photoQualityPrioritization = isRaw ? .speed : .quality
            if output.supportedFlashModes.contains(flashMode) {
                settings.flashMode = flashMode
            }

            let id = settings.uniqueID
            let processor = PhotoProcessor(front: front) { [weak self] shot in
                guard let self else { return }
                self.sessionQueue.async { self.inFlight[id] = nil }
                DispatchQueue.main.async { self.handleCaptured(shot) }
            }
            self.inFlight[id] = processor
            let failure = ExceptionCatcher.catchException {
                output.capturePhoto(with: settings, delegate: processor)
            }
            if let failure {
                self.inFlight[id] = nil
                self.report("Error al tomar la foto: \(failure)")
            }
        }
    }

    private func handleCaptured(_ result: PhotoProcessor.Result?) {
        guard let result else {
            toast("No se pudo tomar la foto")
            return
        }
        if let raw = result.rawData, let processed = result.processedData {
            PhotoSaver.saveRawPair(processed: processed, raw: raw) { ok in
                self.toast(ok ? "RAW guardado en Fotos" : "No se pudo guardar el RAW")
            }
        }
        lastShot = result.shot
    }

    // MARK: Grabación

    private func startRecording() {
        let kinds: [DualRecorder.Kind] = dualFormat ? [.vertical, .horizontal] : [.vertical]
        let bitrate = flatVideo ? 26_000_000 : 16_000_000
        sessionQueue.async {
            var audioSettings: [String: Any]?
            if self.session.outputs.contains(self.audioOutput) {
                audioSettings = self.audioOutput.recommendedAudioSettingsForAssetWriter(writingTo: .mov) as? [String: Any]
            }
            self.videoQueue.async {
                var prepared = false
                let failure = ExceptionCatcher.catchException {
                    prepared = (try? self.recorder.prepare(kinds: kinds, audioSettings: audioSettings, bitrate: bitrate)) != nil
                }
                if prepared, failure == nil {
                    DispatchQueue.main.async { self.didBeginRecording() }
                } else {
                    self.report("No se pudo iniciar la grabación\(failure.map { ": \($0)" } ?? "")")
                }
            }
        }
    }

    private func didBeginRecording() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        isRecording = true
        recordingSeconds = 0
        recordingTimer?.invalidate()
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.recordingSeconds += 1
        }
    }

    private func stopRecording() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        isRecording = false
        recordingTimer?.invalidate()
        videoQueue.async {
            self.recorder.finish { urls in
                PhotoSaver.saveVideos(urls) { ok in
                    if ok {
                        self.toast(urls.count > 1 ? "Guardados: vertical y horizontal" : "Video guardado")
                    } else {
                        self.toast("No se pudo guardar el video")
                    }
                }
            }
        }
    }
}

// MARK: - Cuadros de video y audio

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if output === audioOutput {
            _ = ExceptionCatcher.catchException { self.recorder.appendAudio(sampleBuffer) }
            return
        }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        frameCounter &+= 1

        if pipelineGuide {
            analyzer.submit(pixelBuffer, front: pipelineFront)
        }

        // El sensor entrega cuadros horizontales; los giramos a vertical.
        var frame = CIImage(cvPixelBuffer: pixelBuffer).oriented(pipelineFront ? .leftMirrored : .right)
        frame = frame.transformed(by: CGAffineTransform(translationX: -frame.extent.minX, y: -frame.extent.minY))

        let currentStyle = pipelineStyle
        let grainOffset = CGPoint(x: CGFloat((frameCounter * 37) % 512), y: CGFloat((frameCounter * 91) % 512))

        if let renderer = previewRenderer {
            let longest = max(frame.extent.width, frame.extent.height)
            let scale = min(1, 1440 / longest)
            let small = scale < 1 ? frame.transformed(by: CGAffineTransform(scaleX: scale, y: scale)) : frame
            renderer.update(currentStyle.apply(to: small, grainOffset: grainOffset))
        }

        if recorder.isActive {
            let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            _ = ExceptionCatcher.catchException {
                self.recorder.appendVideo(frame, time: time, style: currentStyle,
                                          grainOffset: grainOffset, context: self.renderContext)
            }
        }
    }
}

// MARK: - Procesador de foto

/// Junta la foto procesada y, si hay, el RAW; avisa cuando termina la captura completa.
final class PhotoProcessor: NSObject, AVCapturePhotoCaptureDelegate {
    struct Result {
        let shot: CapturedShot
        let processedData: Data?
        let rawData: Data?
    }

    private let front: Bool
    private let completion: (Result?) -> Void
    private var processedData: Data?
    private var rawData: Data?
    private var metadata: [String: Any] = [:]
    private var finished = false

    init(front: Bool, completion: @escaping (Result?) -> Void) {
        self.front = front
        self.completion = completion
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation() else { return }
        if photo.isRawPhoto {
            rawData = data
            if metadata.isEmpty { metadata = photo.metadata }
        } else {
            processedData = data
            metadata = photo.metadata
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        guard !finished else { return }
        finished = true

        var image: CIImage?
        if let processedData {
            image = CIImage(data: processedData, options: [.applyOrientationProperty: true])
        }
        if image == nil, let rawData, let filter = CIRAWFilter(imageData: rawData, identifierHint: nil) {
            image = filter.outputImage
        }
        guard let image else {
            completion(nil)
            return
        }
        let normalized = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
        let info = ShotInfo(metadata: metadata, front: front)
        let shot = CapturedShot(image: normalized, info: info, raw: rawData)
        completion(Result(shot: shot, processedData: processedData, rawData: rawData))
    }
}
