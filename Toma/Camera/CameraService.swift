import AVFoundation
import CoreImage
import ImageIO
import UIKit

enum CaptureMode: String {
    case photo, video
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
}

struct CapturedShot: Identifiable {
    let id = UUID()
    let image: CIImage
    let info: ShotInfo
}

/// Controla la cámara: sesión, vista previa con estilo en vivo, fotos y video doble.
final class CameraService: NSObject, ObservableObject {
    // MARK: Estado para la interfaz (hilo principal)
    @Published private(set) var mode: CaptureMode = .photo
    @Published private(set) var isRecording = false
    @Published private(set) var recordingSeconds = 0
    @Published private(set) var isFront = false
    @Published private(set) var zoomStops: [CGFloat] = [1]
    @Published private(set) var zoomDisplay: CGFloat = 1
    @Published var style: LookStyle = .film {
        didSet {
            let newStyle = style
            videoQueue.async { self.pipelineStyle = newStyle }
        }
    }
    @Published private(set) var flash: FlashSetting = .off
    @Published private(set) var timer: TimerSetting = .off
    @Published var dualFormat = true
    @Published private(set) var maxResolution = false
    @Published private(set) var countdown = 0
    @Published var lastShot: CapturedShot?
    @Published var lastThumbnail: UIImage?
    @Published private(set) var cameraDenied = false
    @Published private(set) var toastText: String?
    @Published private(set) var shutterBlink = false

    let session = AVCaptureSession()
    let previewRenderer = PreviewRenderer.make()

    // MARK: Interno
    private let sessionQueue = DispatchQueue(label: "toma.session")
    private let videoQueue = DispatchQueue(label: "toma.video", qos: .userInitiated)
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?
    private var zoomBase: CGFloat = 1
    private var inFlight: [Int64: PhotoProcessor] = [:]
    private var configured = false

    // Estado del flujo de video (solo en videoQueue)
    private var pipelineStyle: LookStyle = .film
    private var pipelineFront = false
    private var frameCounter = 0
    private let recorder = DualRecorder()
    private let renderContext = CIContext(options: [.cacheIntermediates: false])

    private var countdownTimer: Timer?
    private var recordingTimer: Timer?
    private var toastWork: DispatchWorkItem?

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
        sessionQueue.async {
            if !self.configured {
                self.configure(front: front, mode: currentMode, maxRes: maxRes)
                self.configured = true
            }
            if !self.session.isRunning { self.session.startRunning() }
        }
    }

    private func reconfigure() {
        let front = isFront, currentMode = mode, maxRes = maxResolution
        sessionQueue.async { self.configure(front: front, mode: currentMode, maxRes: maxRes) }
    }

    // MARK: Configuración de la sesión (sessionQueue)

    private func configure(front: Bool, mode: CaptureMode, maxRes: Bool) {
        session.beginConfiguration()

        if let current = videoInput {
            session.removeInput(current)
            videoInput = nil
        }
        guard let device = front ? Self.frontCamera() : Self.backCamera(),
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

        if mode == .photo {
            if let mic = audioInput {
                session.removeInput(mic)
                audioInput = nil
            }
            if session.outputs.contains(audioOutput) { session.removeOutput(audioOutput) }
            if session.canSetSessionPreset(.photo) { session.sessionPreset = .photo }
            if !session.outputs.contains(photoOutput), session.canAddOutput(photoOutput) {
                session.addOutput(photoOutput)
            }
            videoOutput.deliversPreviewSizedOutputBuffers = true
        } else {
            if session.outputs.contains(photoOutput) { session.removeOutput(photoOutput) }
            videoOutput.deliversPreviewSizedOutputBuffers = false
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

        // La resolución de foto se fija después de aplicar el formato de la sesión,
        // para elegir entre las resoluciones que de verdad ofrece la cámara.
        if mode == .photo, session.outputs.contains(photoOutput) {
            session.beginConfiguration()
            configurePhotoOutput(device: device, maxRes: maxRes)
            session.commitConfiguration()
        }
    }

    private func configurePhotoOutput(device: AVCaptureDevice, maxRes: Bool) {
        let dims = device.activeFormat.supportedMaxPhotoDimensions.sorted {
            Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height)
        }
        let target: CMVideoDimensions?
        if maxRes {
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
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = min(base, device.maxAvailableVideoZoomFactor)
            device.unlockForConfiguration()
        } catch {}
        DispatchQueue.main.async {
            self.zoomStops = stops
            self.zoomDisplay = 1
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
        guard newMode != mode, !isRecording else { return }
        mode = newMode
        if newMode == .video, AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                DispatchQueue.main.async { self.reconfigure() }
            }
        } else {
            reconfigure()
        }
    }

    func flipCamera() {
        guard !isRecording else { return }
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
        sessionQueue.async {
            guard let device = self.videoInput?.device, self.session.outputs.contains(self.photoOutput) else { return }
            self.session.beginConfiguration()
            self.configurePhotoOutput(device: device, maxRes: on)
            self.session.commitConfiguration()
        }
        toast(on ? "Fotos a máxima resolución (48 MP)" : "Fotos a 24 MP")
    }

    func openPhotos() {
        if let url = URL(string: "photos-redirect://") { UIApplication.shared.open(url) }
    }

    func toast(_ text: String) {
        toastText = text
        toastWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.toastText = nil }
        toastWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2, execute: work)
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
        sessionQueue.async {
            guard self.session.outputs.contains(self.photoOutput) else { return }
            let settings: AVCapturePhotoSettings
            if self.photoOutput.availablePhotoCodecTypes.contains(.hevc) {
                settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
            } else {
                settings = AVCapturePhotoSettings()
            }
            settings.maxPhotoDimensions = self.photoOutput.maxPhotoDimensions
            settings.photoQualityPrioritization = .quality
            if self.photoOutput.supportedFlashModes.contains(flashMode) {
                settings.flashMode = flashMode
            }
            let id = settings.uniqueID
            let processor = PhotoProcessor(front: front) { [weak self] shot in
                guard let self else { return }
                self.sessionQueue.async { self.inFlight[id] = nil }
                DispatchQueue.main.async {
                    if let shot {
                        self.lastShot = shot
                    } else {
                        self.toast("No se pudo tomar la foto")
                    }
                }
            }
            self.inFlight[id] = processor
            self.photoOutput.capturePhoto(with: settings, delegate: processor)
        }
    }

    // MARK: Grabación

    private func startRecording() {
        let kinds: [DualRecorder.Kind] = dualFormat ? [.vertical, .horizontal] : [.vertical]
        sessionQueue.async {
            var audioSettings: [String: Any]?
            if self.session.outputs.contains(self.audioOutput) {
                audioSettings = self.audioOutput.recommendedAudioSettingsForAssetWriter(writingTo: .mov) as? [String: Any]
            }
            self.videoQueue.async {
                do {
                    try self.recorder.prepare(kinds: kinds, audioSettings: audioSettings)
                    DispatchQueue.main.async { self.didBeginRecording() }
                } catch {
                    DispatchQueue.main.async { self.toast("No se pudo iniciar la grabación") }
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
            recorder.appendAudio(sampleBuffer)
            return
        }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        frameCounter &+= 1

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
            recorder.appendVideo(frame,
                                 time: CMSampleBufferGetPresentationTimeStamp(sampleBuffer),
                                 style: currentStyle,
                                 grainOffset: grainOffset,
                                 context: renderContext)
        }
    }
}

// MARK: - Procesador de foto

final class PhotoProcessor: NSObject, AVCapturePhotoCaptureDelegate {
    private let front: Bool
    private let completion: (CapturedShot?) -> Void
    private var finished = false

    init(front: Bool, completion: @escaping (CapturedShot?) -> Void) {
        self.front = front
        self.completion = completion
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard !finished else { return }
        finished = true
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let raw = CIImage(data: data, options: [.applyOrientationProperty: true]) else {
            completion(nil)
            return
        }
        let image = raw.transformed(by: CGAffineTransform(translationX: -raw.extent.minX, y: -raw.extent.minY))

        var info = ShotInfo()
        info.isFront = front
        if let exif = photo.metadata[kCGImagePropertyExifDictionary as String] as? [String: Any] {
            info.iso = (exif[kCGImagePropertyExifISOSpeedRatings as String] as? [NSNumber])?.first?.intValue
            info.exposure = (exif[kCGImagePropertyExifExposureTime as String] as? NSNumber)?.doubleValue
            info.aperture = (exif[kCGImagePropertyExifFNumber as String] as? NSNumber)?.doubleValue
            info.focal35 = (exif[kCGImagePropertyExifFocalLenIn35mmFilm as String] as? NSNumber)?.intValue
            info.lens = exif[kCGImagePropertyExifLensModel as String] as? String
        }
        completion(CapturedShot(image: image, info: info))
    }
}
