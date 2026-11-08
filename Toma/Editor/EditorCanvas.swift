import AVFoundation
import SwiftUI

/// Vista previa con los elementos encima. Se arrastran con un dedo a cualquier parte
/// (también sobre el marco); con dos dedos, en cualquier punto de la pantalla,
/// se cambia el tamaño y el giro del elemento elegido.
struct EditorCanvas: View {
    @ObservedObject var model: EditorModel
    let onEditText: (EditorOverlay) -> Void
    @State private var pinchStart: CGFloat?
    @State private var rotateStart: Double?

    static let sizeRange: ClosedRange<CGFloat> = 0.05...3.0

    var body: some View {
        GeometryReader { geo in
            let content = contentRect(in: geo.size)
            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.001)
                    .onTapGesture { model.selectedID = nil }

                baseLayer
                    .frame(width: content.width, height: content.height)
                    .position(x: content.midX, y: content.midY)

                OverlayLayer(model: model, box: content.size, onEditText: onEditText)
                    .frame(width: content.width, height: content.height)
                    .clipped()
                    .position(x: content.midX, y: content.midY)
            }
            .simultaneousGesture(pinch)
            .simultaneousGesture(rotate)
        }
    }

    @ViewBuilder private var baseLayer: some View {
        if model.isVideo, let player = model.player {
            PlayerView(player: player)
        } else if let image = model.preview {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .shadow(color: .black.opacity(0.6), radius: 14)
        } else {
            ProgressView().tint(.white)
        }
    }

    private func contentRect(in size: CGSize) -> CGRect {
        let aspect: CGFloat
        if model.isVideo {
            aspect = model.videoAspect
        } else if let image = model.preview, image.size.height > 0 {
            aspect = image.size.width / image.size.height
        } else {
            aspect = 3.0 / 4.0
        }
        var width = size.width
        var height = width / aspect
        if height > size.height {
            height = size.height
            width = height * aspect
        }
        return CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
    }

    private var pinch: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                // Si no hay nada elegido, se toma el último elemento agregado.
                if model.selected == nil, let last = model.overlays.last { model.selectedID = last.id }
                guard var overlay = model.selected else { return }
                if pinchStart == nil { pinchStart = overlay.size }
                let range = Self.sizeRange
                overlay.size = min(max((pinchStart ?? overlay.size) * value.magnification, range.lowerBound), range.upperBound)
                model.update(overlay)
            }
            .onEnded { _ in pinchStart = nil }
    }

    private var rotate: some Gesture {
        RotateGesture()
            .onChanged { value in
                if model.selected == nil, let last = model.overlays.last { model.selectedID = last.id }
                guard var overlay = model.selected else { return }
                if rotateStart == nil { rotateStart = overlay.rotation }
                overlay.rotation = (rotateStart ?? overlay.rotation) + value.rotation.radians
                model.update(overlay)
            }
            .onEnded { _ in rotateStart = nil }
    }
}

private struct OverlayLayer: View {
    @ObservedObject var model: EditorModel
    let box: CGSize
    let onEditText: (EditorOverlay) -> Void

    var body: some View {
        ZStack {
            ForEach(model.overlays) { overlay in
                OverlayItemView(
                    overlay: overlay,
                    image: model.overlayImages[overlay.id],
                    box: box,
                    isSelected: overlay.id == model.selectedID,
                    onChange: { model.update($0) },
                    onSelect: {
                        model.selectedID = overlay.id
                        model.bringToFront(overlay.id)
                    },
                    onDoubleTap: {
                        if overlay.content.isText { onEditText(overlay) }
                    }
                )
            }
        }
        .frame(width: box.width, height: box.height)
    }
}

private struct OverlayItemView: View {
    let overlay: EditorOverlay
    let image: UIImage?
    let box: CGSize
    let isSelected: Bool
    let onChange: (EditorOverlay) -> Void
    let onSelect: () -> Void
    let onDoubleTap: () -> Void
    @State private var dragStart: CGPoint?

    var body: some View {
        let side = min(box.width, box.height)
        let width = max(overlay.size * side, 1)
        let aspect = image.map { $0.size.height / max($0.size.width, 1) } ?? 0.5
        item(width: width, height: width * aspect)
            .rotationEffect(.radians(overlay.rotation))
            .gesture(drag)
            .onTapGesture(count: 2) { onDoubleTap() }
            .onTapGesture { onSelect() }
            .position(x: overlay.center.x * box.width, y: overlay.center.y * box.height)
    }

    private func item(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
            } else {
                ProgressView().tint(.white)
            }
        }
        .frame(width: width, height: height)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(isSelected ? Color.yellow : Color.clear, style: StrokeStyle(lineWidth: 1.4, dash: [5, 4]))
        )
        .contentShape(Rectangle())
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                if dragStart == nil {
                    dragStart = overlay.center
                    onSelect()
                }
                guard let start = dragStart, box.width > 0, box.height > 0 else { return }
                var moved = overlay
                // Puede salirse un poco del borde (para cortes creativos), sin perderse.
                moved.center = CGPoint(
                    x: min(max(start.x + value.translation.width / box.width, -0.3), 1.3),
                    y: min(max(start.y + value.translation.height / box.height, -0.3), 1.3)
                )
                onChange(moved)
            }
            .onEnded { _ in dragStart = nil }
    }
}

/// Reproductor de video sin controles (se repite en bucle).
struct PlayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {}

    final class PlayerUIView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer {
            guard let layer = layer as? AVPlayerLayer else { fatalError("AVPlayerLayer esperado") }
            return layer
        }
    }
}
