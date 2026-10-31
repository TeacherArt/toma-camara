import CoreImage
import SwiftUI

/// Pantalla de "revelado": eliges estilo, marco y formatos, y guardas.
final class RevealModel: ObservableObject {
    let shot: CapturedShot
    @Published var style: LookStyle { didSet { refresh() } }
    @Published var frame: FrameStyle = .none { didSet { refresh() } }
    @Published private(set) var formats: Set<OutputFormat> { didSet { refresh() } }
    @Published private(set) var preview: UIImage? = nil
    @Published private(set) var thumbs: [LookStyle: UIImage] = [:]
    @Published private(set) var isSaving = false

    private let context = CIContext(options: [.cacheIntermediates: false])
    private let queue = DispatchQueue(label: "toma.reveal", qos: .userInitiated)
    private let small: CIImage
    private var generation = 0

    init(shot: CapturedShot, style: LookStyle, formats: Set<OutputFormat>) {
        self.shot = shot
        self.style = style
        self.formats = formats.isEmpty ? [.original] : formats
        self.small = Framing.limit(shot.image, maxSide: 1400)
        refresh()
        makeThumbs()
    }

    /// El primero de los formatos elegidos es el que se muestra en grande.
    var primaryFormat: OutputFormat {
        OutputFormat.allCases.first { formats.contains($0) } ?? .original
    }

    func toggle(_ format: OutputFormat) {
        if formats.contains(format) {
            if formats.count > 1 { formats.remove(format) }
        } else {
            formats.insert(format)
        }
    }

    private func refresh() {
        generation += 1
        let current = generation
        let base = small, format = primaryFormat, style = self.style, frame = self.frame, info = shot.info
        queue.async {
            let image = Self.renderFinal(base: base, format: format, style: style, frame: frame,
                                         info: info, context: self.context, maxSide: nil)
            DispatchQueue.main.async {
                if current == self.generation { self.preview = image }
            }
        }
    }

    private func makeThumbs() {
        let base = Framing.limit(Framing.centerCrop(small, aspect: 1), maxSide: 180)
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

    /// Guarda un archivo por cada formato elegido. Devuelve una miniatura si salió bien.
    func save(_ completion: @escaping (UIImage?) -> Void) {
        guard !isSaving else { return }
        isSaving = true
        let chosen = OutputFormat.allCases.filter { formats.contains($0) }
        let style = self.style, frame = self.frame, shot = self.shot
        queue.async {
            var items: [Data] = []
            var thumbnail: UIImage?
            for format in chosen {
                autoreleasepool {
                    guard let image = Self.renderFinal(base: shot.image, format: format, style: style, frame: frame,
                                                       info: shot.info, context: self.context,
                                                       maxSide: frame.sizeLimit) else { return }
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

    static func renderFinal(base: CIImage, format: OutputFormat, style: LookStyle, frame: FrameStyle,
                            info: ShotInfo, context: CIContext, maxSide: CGFloat?) -> UIImage? {
        var image = Framing.centerCrop(base, aspect: format.aspect(for: base.extent.size))
        if let maxSide { image = Framing.limit(image, maxSide: maxSide) }
        let rect = CGRect(x: 0, y: 0, width: floor(image.extent.width), height: floor(image.extent.height))
        guard rect.width > 0, rect.height > 0 else { return nil }
        let styled = style.apply(to: image.cropped(to: rect))
        guard let cg = context.createCGImage(styled, from: rect, format: .RGBA8,
                                             colorSpace: CGColorSpace(name: CGColorSpace.displayP3)) else { return nil }
        return FrameRenderer.render(photo: cg, frame: frame, info: info, styleName: style.title)
    }
}

struct RevealView: View {
    @StateObject private var model: RevealModel
    @Environment(\.dismiss) private var dismiss
    private let onDone: (UIImage?) -> Void

    init(shot: CapturedShot, style: LookStyle, formats: Set<OutputFormat>, onDone: @escaping (UIImage?) -> Void) {
        _model = StateObject(wrappedValue: RevealModel(shot: shot, style: style, formats: formats))
        self.onDone = onDone
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 14) {
                header
                previewArea
                styleRow
                frameRow
                formatRow
                saveButton
            }
        }
    }

    private var header: some View {
        HStack {
            Button("Descartar") { dismiss() }
                .foregroundStyle(.white.opacity(0.8))
            Spacer()
            Text("REVELADO")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .tracking(2)
                .foregroundStyle(.white)
            Spacer()
            Text("Descartar").hidden()
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var previewArea: some View {
        ZStack {
            if let image = model.preview {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .shadow(color: .black.opacity(0.6), radius: 14)
            } else {
                ProgressView().tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 20)
    }

    private var styleRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(LookStyle.allCases) { style in
                    Button { model.style = style } label: {
                        VStack(spacing: 6) {
                            Group {
                                if let thumb = model.thumbs[style] {
                                    Image(uiImage: thumb).resizable().scaledToFill()
                                } else {
                                    Color.white.opacity(0.08)
                                }
                            }
                            .frame(width: 62, height: 62)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(model.style == style ? Color.yellow : Color.clear, lineWidth: 2)
                            )
                            Text(style.title)
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(model.style == style ? Color.yellow : Color.white.opacity(0.6))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private var frameRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(FrameStyle.allCases) { frame in
                    let selected = model.frame == frame
                    Button { model.frame = frame } label: {
                        VStack(spacing: 5) {
                            Image(systemName: frame.icon)
                                .font(.system(size: 18, weight: .medium))
                                .frame(width: 44, height: 40)
                                .background(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .stroke(selected ? Color.yellow : Color.white.opacity(0.25), lineWidth: selected ? 2 : 1)
                                )
                            Text(frame.title)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                        }
                        .foregroundStyle(selected ? Color.yellow : Color.white.opacity(0.75))
                        .frame(minWidth: 58)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private var formatRow: some View {
        HStack(spacing: 8) {
            Text("Formatos")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
            ForEach(OutputFormat.allCases) { format in
                let selected = model.formats.contains(format)
                Button { model.toggle(format) } label: {
                    Text(format.title)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(selected ? Color.black : Color.white.opacity(0.8))
                        .padding(.horizontal, 9)
                        .frame(height: 30)
                        .background(Capsule().fill(selected ? Color.yellow : Color.white.opacity(0.1)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
    }

    private var saveButton: some View {
        HStack {
            Text(model.formats.count > 1 ? "Se guardan \(model.formats.count) archivos" : "Se guarda 1 archivo")
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
            Spacer()
            Button {
                model.save { thumbnail in
                    onDone(thumbnail)
                    dismiss()
                }
            } label: {
                HStack(spacing: 8) {
                    if model.isSaving {
                        ProgressView().tint(.black)
                    } else {
                        Image(systemName: "checkmark")
                    }
                    Text("Guardar")
                }
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.black)
                .padding(.horizontal, 26)
                .frame(height: 50)
                .background(Capsule().fill(Color.yellow))
            }
            .disabled(model.isSaving)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
    }
}
