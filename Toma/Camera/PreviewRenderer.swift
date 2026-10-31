import CoreImage
import MetalKit
import SwiftUI

/// Dibuja la vista previa ya con el estilo aplicado, usando la GPU.
final class PreviewRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let context: CIContext
    private let lock = NSLock()
    private var latest: CIImage?
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    static func make() -> PreviewRenderer? {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else { return nil }
        return PreviewRenderer(device: device, queue: queue)
    }

    private init(device: MTLDevice, queue: MTLCommandQueue) {
        self.device = device
        self.commandQueue = queue
        self.context = CIContext(mtlDevice: device, options: [.cacheIntermediates: false])
        super.init()
    }

    func update(_ image: CIImage) {
        lock.lock()
        latest = image
        lock.unlock()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        lock.lock()
        let image = latest
        lock.unlock()
        guard let image,
              image.extent.width > 0,
              let drawable = view.currentDrawable,
              let buffer = commandQueue.makeCommandBuffer() else { return }

        let target = view.drawableSize
        let scale = max(target.width / image.extent.width, target.height / image.extent.height)
        var fitted = image
            .transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let dx = (target.width - fitted.extent.width) / 2
        let dy = (target.height - fitted.extent.height) / 2
        fitted = fitted.transformed(by: CGAffineTransform(translationX: dx, y: dy))

        let bounds = CGRect(origin: .zero, size: target)
        let background = CIImage(color: CIColor.black).cropped(to: bounds)
        context.render(fitted.composited(over: background),
                       to: drawable.texture,
                       commandBuffer: buffer,
                       bounds: bounds,
                       colorSpace: colorSpace)
        buffer.present(drawable)
        buffer.commit()
    }
}

struct MetalPreview: UIViewRepresentable {
    let renderer: PreviewRenderer

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: renderer.device)
        view.framebufferOnly = false
        view.colorPixelFormat = .bgra8Unorm
        view.preferredFramesPerSecond = 30
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.backgroundColor = .black
        view.delegate = renderer
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {}
}
