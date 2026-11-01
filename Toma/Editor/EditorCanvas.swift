import AVFoundation
import SwiftUI

/// Vista previa con los elementos encima. Se arrastran con un dedo;
/// con dos dedos (pellizcar y girar) se cambia el tamaño y el giro del elemento elegido.
struct EditorCanvas: View {
    @ObservedObject var model: EditorModel
    let onEditText: (EditorOverlay) -> Void
    @State private var pinchStart: CGFloat?
    @State private var rotateStart: Double?

    var body: some View {
        GeometryReader { geo in
            let content = contentRect(in: geo.size)
            let photo = CGRect(x: content.minX + model.photoRect.minX * content.width,
                               y: content.minY + model.photoRect.minY * content.height,
                               width: model.photoRect.width * content.width,
                               height: model.photoRect.height * content.height)
            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.001)
                    .onTapGesture { model.selectedID = nil }

                baseLayer
                    .frame(width: content.width, height: content.height)
                    .position(x: content.midX, y: content.midY)

                OverlayLayer(model: model, box: photo.size, onEditText: onEditText)
                    .frame(width: photo.width, height: photo.height)
                    .clipped()
                    .position(x: photo.midX, y: photo.midY)
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
                guard var overlay = model.selected else { return }
                if pinchStart == nil { pinchStart = overlay.size }
                overlay.size = min(max((pinchStart ?? overlay.size) * value.magnification, 0.06), 1.6)
                model.update(overlay)
            }
            .onEnded { _ in pinchStart = nil }
    }

    private var rotate: some Gesture {
        RotateGesture()
            .onChanged { value in
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
                moved.center = CGPoint(
                    x: min(max(start.x + value.translation.width / box.width, 0), 1),
                    y: min(max(start.y + value.translation.height / box.height, 0), 1)
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
