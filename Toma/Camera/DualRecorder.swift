import AVFoundation
import CoreImage

/// Graba al mismo tiempo un video vertical (9:16) y uno horizontal (16:9)
/// a partir del mismo cuadro 4:3 de la cámara. Todo se llama desde la cola de video.
final class DualRecorder {
    enum Kind {
        case vertical, horizontal

        var size: CGSize {
            switch self {
            case .vertical: return CGSize(width: 1080, height: 1920)
            case .horizontal: return CGSize(width: 1920, height: 1080)
            }
        }
    }

    struct RecorderError: Error {}

    private struct Track {
        let kind: Kind
        let url: URL
        let writer: AVAssetWriter
        let video: AVAssetWriterInput
        let audio: AVAssetWriterInput?
        let adaptor: AVAssetWriterInputPixelBufferAdaptor
    }

    private var tracks: [Track] = []
    private var started = false
    private(set) var isActive = false
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    func prepare(kinds: [Kind], audioSettings: [String: Any]?) throws {
        tracks = []
        started = false
        for kind in kinds {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("toma-\(UUID().uuidString).mov")
            let writer = try AVAssetWriter(outputURL: url, fileType: .mov)

            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.hevc,
                AVVideoWidthKey: Int(kind.size.width),
                AVVideoHeightKey: Int(kind.size.height),
                AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 16_000_000]
            ]
            let videoIn = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            videoIn.expectsMediaDataInRealTime = true
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: videoIn,
                sourcePixelBufferAttributes: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                    kCVPixelBufferWidthKey as String: Int(kind.size.width),
                    kCVPixelBufferHeightKey as String: Int(kind.size.height),
                    kCVPixelBufferMetalCompatibilityKey as String: true
                ])
            guard writer.canAdd(videoIn) else { throw RecorderError() }
            writer.add(videoIn)

            var audioIn: AVAssetWriterInput?
            if let audioSettings {
                let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
                input.expectsMediaDataInRealTime = true
                if writer.canAdd(input) {
                    writer.add(input)
                    audioIn = input
                }
            }
            tracks.append(Track(kind: kind, url: url, writer: writer, video: videoIn, audio: audioIn, adaptor: adaptor))
        }
        isActive = true
    }

    func appendVideo(_ frame: CIImage, time: CMTime, style: LookStyle, grainOffset: CGPoint, context: CIContext) {
        guard isActive else { return }
        if !started {
            for track in tracks {
                track.writer.startWriting()
                track.writer.startSession(atSourceTime: time)
            }
            started = true
        }
        for track in tracks {
            guard track.writer.status == .writing,
                  track.video.isReadyForMoreMediaData,
                  let pool = track.adaptor.pixelBufferPool else { continue }
            var output: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &output)
            guard let output else { continue }
            let bounds = CGRect(origin: .zero, size: track.kind.size)
            let framed = Framing.fill(frame, to: track.kind.size)
            let styled = style.apply(to: framed, grainOffset: grainOffset).cropped(to: bounds)
            context.render(styled, to: output, bounds: bounds, colorSpace: colorSpace)
            track.adaptor.append(output, withPresentationTime: time)
        }
    }

    func appendAudio(_ sampleBuffer: CMSampleBuffer) {
        guard isActive, started else { return }
        for track in tracks {
            if let audio = track.audio, track.writer.status == .writing, audio.isReadyForMoreMediaData {
                audio.append(sampleBuffer)
            }
        }
    }

    /// Cierra los archivos. `completion` se llama en el hilo principal con los videos listos.
    func finish(_ completion: @escaping ([URL]) -> Void) {
        guard isActive else {
            DispatchQueue.main.async { completion([]) }
            return
        }
        isActive = false
        let current = tracks
        tracks = []
        guard started else {
            DispatchQueue.main.async { completion([]) }
            return
        }
        started = false
        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []
        for track in current {
            track.video.markAsFinished()
            track.audio?.markAsFinished()
            group.enter()
            track.writer.finishWriting {
                if track.writer.status == .completed {
                    lock.lock()
                    urls.append(track.url)
                    lock.unlock()
                }
                group.leave()
            }
        }
        group.notify(queue: .main) { completion(urls) }
    }
}
