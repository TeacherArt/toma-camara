import AVFoundation
import Combine
import CoreImage
import UIKit

enum EditorSource {
    case photo(image: CIImage, info: ShotInfo, raw: Data?)
    case video(URL)
}

struct EditorSession: Identifiable {
    let id = UUID()
    let source: EditorSource
}

/// Parámetros que el filtro de video lee desde otro hilo.
final class VideoParams {
    private let lock = NSLock()
    private var style: LookStyle = .natural
    private var adjust = Adjustments()

    func set(style: LookStyle, adjust: Adjustments) {
        lock.lock()
        self.style = style
        self.adjust = adjust
        lock.unlock()
    }

    func snapshot() -> (LookStyle, Adjustments) {
        lock.lock()
        defer { lock.unlock() }
        return (style, adjust)
    }
}

/// Capa de stickers para el video: se dibuja una vez al tamaño del cuadro.
final class OverlayLayerBox {
    private let lock = NSLock()
    private let overlays: [EditorOverlay]
    private var cached: (CGSize, CIImage)?

    init(overlays: [EditorOverlay]) {
        self.overlays = overlays
    }

    func image(for extent: CGRect) -> CIImage? {
        guard !overlays.isEmpty else { return nil }
        lock.lock()
        defer { lock.unlock() }
        if let cached, cached.0 == extent.size {
            return cached.1.transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
        }
        let layer = OverlayRenderer.layer(overlays, size: extent.size)
        guard let cg = layer.cgImage else { return nil }
        let ci = CIImage(cgImage: cg)
        cached = (extent.size, ci)
        return ci.transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
    }
}

/// Estado del editor de fotos y videos.
final class EditorModel: ObservableObject {
    let isVideo: Bool
    let info: ShotInfo
    let isRaw: Bool

    @Published var style: LookStyle { didSet { styleOrAdjustChanged() } }
    @Published var adjust = Adjustments() { didSet { styleOrAdjustChanged() } }
    @Published var frame: FrameStyle = .none { didSet { schedulePreview() } }
    @Published private(set) var formats: Set<OutputFormat>
    @Published private(set) var overlays: [EditorOverlay] = []
    @Published var selectedID: UUID?
    @Published private(set) var overlayImages: [UUID: UIImage] = [:]
    @Published private(set) var preview: UIImage?
    @Published private(set) var photoRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    @Published private(set) var thumbs: [LookStyle: UIImage] = [:]
    @Published private(set) var isSaving = false
    @Published private(set) var videoAspect: CGFloat = 9.0 / 16.0
    @Published private(set) var placeName: String?

    let player: AVPlayer?
    private let videoURL: URL?
    private let videoParams = VideoParams()
    private let baseImage: CIImage?
    private let rawData: Data?
    private var smallBase: CIImage?
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let queue = DispatchQueue(label: "toma.editor", qos: .userInitiated)
    private let overlayQueue = DispatchQueue(label: "toma.overlay", qos: .userInitiated)
    private var previewBusy = false
    private var previewPending = false
    private var rawPreview: (Double, CIImage)?
    private var loopObserver: NSObjectProtocol?

    init(source: EditorSource, style: LookStyle, formats: Set<OutputFormat>) {
        switch source {
        case let .photo(image, info, raw):
            isVideo = false
            self.info = info
            baseImage = image
            rawData = raw
            isRaw = raw != nil
            videoURL = nil
            player = nil
        case let .video(url):
            isVideo = true
            info = ShotInfo()
            baseImage = nil
            rawData = nil
            isRaw = false
            videoURL = url
            player = AVPlayer(url: url)
        }
        self.style = style
        self.formats = formats.isEmpty ? [.original] : formats

        if isVideo {
            setupVideo()
        } else {
            smallBase = baseImage.map { Framing.limit($0, maxSide: 1400) }
            schedulePreview()
            makeThumbs()
        }
    }

    deinit {
        if let loopObserver { NotificationCenter.default.removeObserver(loopObserver) }
        player?.pause()
    }

    var primaryFormat: OutputFormat {
        OutputFormat.allCases.first { formats.contains($0) } ?? .original
    }

    var selected: EditorOverlay? {
        overlays.first { $0.id == selectedID }
    }

    func toggle(_ format: OutputFormat) {
        if formats.contains(format) {
            if formats.count > 1 { formats.remove(format) }
        } else {
            formats.insert(format)
        }
        schedulePreview()
    }

    private func styleOrAdjustChanged() {
        if isVideo {
            videoParams.set(style: style, adjust: adjust)
            refreshPausedVideo()
        } else {
            schedulePreview()
        }
    }

    // MARK: Elementos encima

    func addOverlay(_ content: OverlayContent, border: OverlayBorder = .none,
                    center: CGPoint = CGPoint(x: 0.5, y: 0.5), size: CGFloat = 0.45) {
        let overlay = EditorOverlay(content: content, border: border, center: center, size: size)
        overlays.append(overlay)
        selectedID = overlay.id
        renderImage(for: overlay)
    }

    func update(_ overlay: EditorOverlay) {
        guard let index = overlays.firstIndex(where: { $0.id == overlay.id }) else { return }
        let needsImage = overlays[index].cacheKey != overlay.cacheKey
        overlays[index] = overlay
        if needsImage { renderImage(for: overlay) }
    }

    func removeSelected() {
        guard let id = selectedID else { return }
        overlays.removeAll { $0.id == id }
        overlayImages[id] = nil
        selectedID = nil
    }

    func bringToFront(_ id: UUID) {
        guard let index = overlays.firstIndex(where: { $0.id == id }), index != overlays.count - 1 else { return }
        let item = overlays.remove(at: index)
        overlays.append(item)
    }

    /// Una sola marca Arthur por foto: si ya existe, se actualiza.
    func setMark(_ spec: MarkSpec) {
        if let existing = overlays.first(where: { $0.content.isMark }) {
            var updated = existing
            updated.content = .mark(spec)
            update(updated)
            selectedID = existing.id
        } else {
            addOverlay(.mark(spec), center: CGPoint(x: 0.3, y: 0.9), size: 0.42)
        }
    }

    func removeMark() {
        overlays.removeAll { $0.content.isMark }
    }

    private func renderImage(for overlay: EditorOverlay) {
        let key = overlay.cacheKey
        overlayQueue.async {
            let image = OverlayRenderer.image(for: overlay)
            DispatchQueue.main.async {
                guard let image,
                      let current = self.overlays.first(where: { $0.id == overlay.id }),
                      current.cacheKey == key else { return }
                self.overlayImages[overlay.id] = image
            }
        }
    }

    // MARK: Lugar

    func loadPlace() {
        guard placeName == nil else { return }
        let location = info.location
        Task {
            let name = await LocationHelper.shared.placeName(for: location)
            await MainActor.run { self.placeName = name ?? "México" }
        }
    }

    func specsText() -> String {
        [
            info.focal35.map { "\($0)MM" },
            FrameRenderer.apertureText(info.aperture),
            FrameRenderer.shutterText(info.exposure),
            info.iso.map { "ISO \($0)" }
        ].compactMap { $0 }.joined(separator: " · ")
    }

    // MARK: Vista previa de foto

    private func schedulePreview() {
        guard !isVideo else { return }
        if previewBusy {
            previewPending = true
            return
        }
        previewBusy = true
        let style = self.style
        let adjust = self.adjust
        let frame = self.frame
        let format = primaryFormat
        let info = self.info
        queue.async {
            var result: FramedImage?
            if let base = self.previewBase(exposure: adjust.exposure) {
                result = Self.renderPhoto(base: base.0, format: format, style: style, adjust: adjust,
                                          applyExposure: base.1, frame: frame, info: info,
                                          overlays: nil, maxSide: nil, context: self.context)
            }
            DispatchQueue.main.async {
                if let result {
                    self.preview = result.image
                    let size = result.image.size
                    if size.width > 0, size.height > 0 {
                        self.photoRect = CGRect(x: result.photoRect.minX / size.width,
                                                y: result.photoRect.minY / size.height,
                                                width: result.photoRect.width / size.width,
                                                height: result.photoRect.height / size.height)
                    }
                }
                self.previewBusy = false
                if self.previewPending {
                    self.previewPending = false
                    self.schedulePreview()
                }
            }
        }
    }

    /// Base para la vista previa. Con RAW, la exposición se aplica al revelar (más margen).
    /// Devuelve la imagen y si todavía falta aplicar la exposición.
    private func previewBase(exposure: Double) -> (CIImage, Bool)? {
        if rawData != nil, let base = baseImage {
            if let cached = rawPreview, cached.0 == exposure { return (cached.1, false) }
            let scale = 1400 / max(base.extent.width, base.extent.height)
            if let image = rawImage(exposure: exposure, scale: min(scale, 1)) {
                rawPreview = (exposure, image)
                return (image, false)
            }
        }
        guard let smallBase else { return nil }
        return (smallBase, true)
    }

    private func rawImage(exposure: Double, scale: CGFloat) -> CIImage? {
        guard let rawData, let filter = CIRAWFilter(imageData: rawData, identifierHint: nil) else { return nil }
        filter.scaleFactor = Float(scale)
        filter.exposure = Float(exposure)
        filter.boostAmount = 0.75
        guard let output = filter.outputImage else { return nil }
        return Framing.normalized(output)
    }

    static func renderPhoto(base: CIImage, format: OutputFormat, style: LookStyle, adjust: Adjustments,
                            applyExposure: Bool, frame: FrameStyle, info: ShotInfo,
                            overlays: [EditorOverlay]?, maxSide: CGFloat?, context: CIContext) -> FramedImage? {
        var image = Framing.centerCrop(base, aspect: format.aspect(for: base.extent.size))
        if let maxSide { image = Framing.limit(image, maxSide: maxSide) }
        let rect = CGRect(x: 0, y: 0, width: floor(image.extent.width), height: floor(image.extent.height))
        guard rect.width > 0, rect.height > 0 else { return nil }
        var edited = adjust.apply(to: image.cropped(to: rect), includeExposure: applyExposure)
        edited = style.apply(to: edited)
        guard var cg = context.createCGImage(edited, from: rect, format: .RGBA8,
                                             colorSpace: CGColorSpace(name: CGColorSpace.displayP3)) else { return nil }
        if let overlays, !overlays.isEmpty {
            cg = OverlayRenderer.composite(overlays, onto: cg)
        }
        return FrameRenderer.render(photo: cg, frame: frame, info: info, styleName: style.title)
    }

    private func makeThumbs() {
        guard let smallBase else { return }
        let base = Framing.limit(Framing.centerCrop(smallBase, aspect: 1), maxSide: 180)
        queue.async {
            let rect = CGRect(x: 0, y: 0, width: floor(base.extent.width), height: floor(base.extent.height))
            var result: [LookStyle: UIImage] = [:]
            for style in LookStyle.allCases {
                if let cg = self.context.createCGImage(style.apply(to: base.cropped(to: rect)), from: rect) {
                    result[style] = UIImage(cgImage: cg)
                }
            }
            DispatchQueue.main.async { self.thumbs = result }
        }
    }

    // MARK: Guardar foto

    /// Guarda un archivo por cada formato elegido. Devuelve una miniatura si salió bien.
    func savePhoto(_ completion: @escaping (UIImage?) -> Void) {
        guard !isSaving, let base = baseImage else { return }
        isSaving = true
        let chosen = OutputFormat.allCases.filter { formats.contains($0) }
        let style = self.style
        let adjust = self.adjust
        let frame = self.frame
        let info = self.info
        let overlays = self.overlays
        queue.async {
            var fullBase = base
            var applyExposure = true
            if self.rawData != nil, let raw = self.rawImage(exposure: adjust.exposure, scale: 1) {
                fullBase = raw
                applyExposure = false
            }
            var items: [Data] = []
            var thumbnail: UIImage?
            for format in chosen {
                autoreleasepool {
                    guard let framed = Self.renderPhoto(base: fullBase, format: format, style: style, adjust: adjust,
                                                        applyExposure: applyExposure, frame: frame, info: info,
                                                        overlays: overlays, maxSide: frame.sizeLimit,
                                                        context: self.context) else { return }
                    let image = framed.image
                    let data = frame.isTransparent ? image.pngData() : image.jpegData(compressionQuality: 0.93)
                    if let data { items.append(data) }
                    if thumbnail == nil {
                        let ratio = image.size.height / max(image.size.width, 1)
                        thumbnail = image.preparingThumbnail(of: CGSize(width: 160, height: 160 * ratio))
                    }
                }
            }
            PhotoSaver.saveImages(items) { ok in
                self.isSaving = false
                completion(ok ? thumbnail : nil)
            }
        }
    }

    // MARK: Video

    private func setupVideo() {
        guard let url = videoURL, let player else { return }
        videoParams.set(style: style, adjust: adjust)
        let asset = AVURLAsset(url: url)
        let params = videoParams
        Task {
            if let track = try? await asset.loadTracks(withMediaType: .video).first,
               let loaded = try? await track.load(.naturalSize, .preferredTransform) {
                let rect = CGRect(origin: .zero, size: loaded.0).applying(loaded.1)
                let aspect = abs(rect.width) / max(abs(rect.height), 1)
                await MainActor.run { self.videoAspect = aspect }
            }
            let composition = AVMutableVideoComposition(asset: asset) { request in
                let (style, adjust) = params.snapshot()
                let source = request.sourceImage
                var image = adjust.apply(to: source)
                image = style.apply(to: image).cropped(to: source.extent)
                request.finish(with: image, context: nil)
            }
            await MainActor.run {
                let item = AVPlayerItem(asset: asset)
                item.videoComposition = composition
                player.replaceCurrentItem(with: item)
                self.loopObserver = NotificationCenter.default.addObserver(
                    forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
                ) { [weak player] _ in
                    player?.seek(to: .zero)
                    player?.play()
                }
                player.play()
            }
        }
    }

    private func refreshPausedVideo() {
        guard let player, player.rate == 0 else { return }
        player.seek(to: player.currentTime(), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func saveVideo(_ completion: @escaping (Bool) -> Void) {
        guard let url = videoURL, !isSaving else { return }
        isSaving = true
        player?.pause()
        let asset = AVURLAsset(url: url)
        let style = self.style
        let adjust = self.adjust
        let box = OverlayLayerBox(overlays: overlays)
        let composition = AVMutableVideoComposition(asset: asset) { request in
            let source = request.sourceImage
            var image = adjust.apply(to: source)
            image = style.apply(to: image).cropped(to: source.extent)
            if let layer = box.image(for: source.extent) {
                image = layer.composited(over: image)
            }
            request.finish(with: image, context: nil)
        }
        let preset = AVAssetExportSession.exportPresets(compatibleWith: asset).contains(AVAssetExportPresetHEVCHighestQuality)
            ? AVAssetExportPresetHEVCHighestQuality : AVAssetExportPresetHighestQuality
        guard let export = AVAssetExportSession(asset: asset, presetName: preset) else {
            isSaving = false
            completion(false)
            return
        }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("toma-edit-\(UUID().uuidString).mov")
        export.outputURL = output
        export.outputFileType = .mov
        export.videoComposition = composition
        export.exportAsynchronously {
            if export.status == .completed {
                PhotoSaver.saveVideos([output]) { ok in
                    self.isSaving = false
                    completion(ok)
                }
            } else {
                DispatchQueue.main.async {
                    self.isSaving = false
                    completion(false)
                }
            }
        }
    }
}
