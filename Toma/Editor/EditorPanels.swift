import SwiftUI

// MARK: - Estilos

struct StylePanel: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(LookStyle.allCases) { style in
                        Button { model.style = style } label: {
                            VStack(spacing: 6) {
                                StyleThumb(image: model.thumbs[style], isVideo: model.isVideo, style: style)
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
                        .id(style)
                    }
                }
                .padding(.horizontal, 20)
            }
            .onAppear { proxy.scrollTo(model.style, anchor: .center) }
        }
    }
}

private struct StyleThumb: View {
    let image: UIImage?
    let isVideo: Bool
    let style: LookStyle

    var body: some View {
        if let image {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            ZStack {
                LinearGradient(colors: [Color(white: 0.25), Color(white: 0.1)], startPoint: .top, endPoint: .bottom)
                Text(String(style.title.prefix(2)))
                    .font(.system(size: 16, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }
}

// MARK: - Ajustes

struct AdjustPanel: View {
    @ObservedObject var model: EditorModel
    @State private var kind: AdjustmentKind = .exposure

    var body: some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(AdjustmentKind.allCases) { item in
                        let value = model.adjust[keyPath: item.keyPath]
                        Button { kind = item } label: {
                            HStack(spacing: 5) {
                                Image(systemName: item.icon)
                                Text(item.title)
                                if value != 0 {
                                    Circle().fill(Color.yellow).frame(width: 5, height: 5)
                                }
                            }
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(kind == item ? Color.black : Color.white.opacity(0.85))
                            .padding(.horizontal, 11)
                            .frame(height: 30)
                            .background(Capsule().fill(kind == item ? Color.yellow : Color.white.opacity(0.1)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
            HStack(spacing: 12) {
                Slider(value: binding, in: kind.range)
                    .tint(.yellow)
                Text(String(format: "%+.2f", model.adjust[keyPath: kind.keyPath]))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 52)
                Button {
                    model.adjust[keyPath: kind.keyPath] = 0
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .padding(.horizontal, 20)
            if model.isRaw && kind == .exposure {
                Text("RAW: la exposición se revela desde el sensor, con más margen.")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.yellow.opacity(0.8))
            }
        }
    }

    private var binding: Binding<Double> {
        Binding(
            get: { model.adjust[keyPath: kind.keyPath] },
            set: { model.adjust[keyPath: kind.keyPath] = $0 }
        )
    }
}

// MARK: - Marcos y formatos

struct FramePanel: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(FrameStyle.allCases) { frame in
                    let selected = model.frame == frame
                    Button { model.frame = frame } label: {
                        VStack(spacing: 5) {
                            Image(systemName: frame.icon)
                                .font(.system(size: 18, weight: .medium))
                                .frame(width: 46, height: 42)
                                .background(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .stroke(selected ? Color.yellow : Color.white.opacity(0.25), lineWidth: selected ? 2 : 1)
                                )
                            Text(frame.title)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .lineLimit(1)
                        }
                        .foregroundStyle(selected ? Color.yellow : Color.white.opacity(0.75))
                        .frame(minWidth: 62)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
    }
}

struct FormatPanel: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                ForEach(OutputFormat.allCases) { format in
                    let selected = model.formats.contains(format)
                    Button { model.toggle(format) } label: {
                        Text(format.title)
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(selected ? Color.black : Color.white.opacity(0.85))
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .background(Capsule().fill(selected ? Color.yellow : Color.white.opacity(0.1)))
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("Elige varios y se guarda un archivo por formato (por ejemplo 9:16 para stories y 4:5 para el feed).")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
    }
}

// MARK: - Texto

struct TextPanel: View {
    @ObservedObject var model: EditorModel
    let onNewText: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Button(action: onNewText) {
                Label("Nuevo texto", systemImage: "plus")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 18)
                    .frame(height: 36)
                    .background(Capsule().fill(Color.yellow))
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    QuickChip(title: "ARTHVR", icon: "crown.fill") {
                        add(TextSpec(text: "ARTHVR", font: .avenir, color: .white), border: .none, at: CGPoint(x: 0.5, y: 0.15))
                    }
                    QuickChip(title: "Hora", icon: "clock") {
                        let date = model.isVideo ? Date() : model.info.date
                        add(TextSpec(text: "\(AutoText.timeOfDay(date)) · \(AutoText.clock(date))", font: .firma, color: .white),
                            border: .none, at: CGPoint(x: 0.5, y: 0.85))
                    }
                    QuickChip(title: "Lugar", icon: "location.fill") {
                        model.loadPlace()
                        addPlaceWhenReady()
                    }
                    Menu {
                        ForEach(AutoText.feelings, id: \.self) { feeling in
                            Button(feeling) {
                                add(TextSpec(text: feeling, font: .cursiva, color: .white), border: .none,
                                    at: CGPoint(x: 0.5, y: 0.8))
                            }
                        }
                    } label: {
                        ChipLabel(title: "Feeling", icon: "heart.fill")
                    }
                    QuickChip(title: "Fecha", icon: "calendar") {
                        let date = model.isVideo ? Date() : model.info.date
                        add(TextSpec(text: AutoText.dayText(date), font: .maquina, color: .white), border: .none,
                            at: CGPoint(x: 0.5, y: 0.9))
                    }
                    QuickChip(title: "Revista", icon: "textformat.size") {
                        model.loadPlace()
                        addMagazineWhenReady()
                    }
                    QuickChip(title: "Cuentas", icon: "circle.grid.3x3.fill") {
                        add(TextSpec(text: "ARTHVR", font: .cuentas, color: .black), border: .none, at: CGPoint(x: 0.5, y: 0.5))
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private func add(_ spec: TextSpec, border: OverlayBorder, at center: CGPoint, size: CGFloat = 0.6) {
        model.addOverlay(.text(spec), border: border, center: center, size: size)
    }

    private func addPlaceWhenReady(attempt: Int = 0) {
        if let place = model.placeName {
            add(TextSpec(text: place, font: .didot, color: .white), border: .none, at: CGPoint(x: 0.5, y: 0.12))
        } else if attempt < 20 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { addPlaceWhenReady(attempt: attempt + 1) }
        }
    }

    /// Combinación tipo revista: palabra en cursiva + frase en mayúsculas con serifa.
    private func addMagazineWhenReady(attempt: Int = 0) {
        if let place = model.placeName ?? (attempt >= 12 ? "México" : nil) {
            let city = place.components(separatedBy: ",").first ?? place
            add(TextSpec(text: city, font: .firma, color: .wine), border: .none, at: CGPoint(x: 0.42, y: 0.12), size: 0.7)
            add(TextSpec(text: "IS ALWAYS A\nGOOD IDEA", font: .didot, color: .wine), border: .none,
                at: CGPoint(x: 0.62, y: 0.22), size: 0.5)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { addMagazineWhenReady(attempt: attempt + 1) }
        }
    }
}

struct QuickChip: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) { ChipLabel(title: title, icon: icon) }
            .buttonStyle(.plain)
    }
}

struct ChipLabel: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
            Text(title)
        }
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(Capsule().fill(Color.white.opacity(0.12)))
    }
}

// MARK: - Stickers

struct StickerPanel: View {
    let onOpen: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Button(action: onOpen) {
                Label("Agregar sticker", systemImage: "plus")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 18)
                    .frame(height: 36)
                    .background(Capsule().fill(Color.yellow))
            }
            Text("Frases con acrílico, stickers y siluetas de tu gato. Toca uno para elegirlo; pellizca para cambiar tamaño y gira con dos dedos.")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
    }
}

// MARK: - Marca Arthur

struct MarkPanel: View {
    @ObservedObject var model: EditorModel
    @State private var silhouette = "sil_ar27"
    @State private var title = "ARTHVR"
    @State private var color: Color = .white
    @State private var showPlace = false
    @State private var showTime = true
    @State private var showSpecs = false
    @State private var feeling: String?

    var body: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(StickerCatalog.siluetas) { item in
                        Button {
                            silhouette = item.name
                            apply()
                        } label: {
                            StickerThumbView(name: item.name, tint: .white)
                                .frame(width: 44, height: 44)
                                .padding(4)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(silhouette == item.name ? Color.yellow : Color.white.opacity(0.2),
                                                lineWidth: silhouette == item.name ? 2 : 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ColorDot(color: .white, selected: color == .white) { color = .white; apply() }
                    ColorDot(color: .black, selected: color == .black) { color = .black; apply() }
                    ColorPicker("", selection: $color, supportsOpacity: false)
                        .labelsHidden()
                        .frame(width: 30)
                    Menu {
                        ForEach(["ARTHVR", "ARTHUR", "AR27", "HYBRID ATHLETE"], id: \.self) { name in
                            Button(name) { title = name; apply() }
                        }
                    } label: {
                        ChipLabel(title: title, icon: "textformat")
                    }
                    Toggle("Lugar", isOn: $showPlace).toggleStyle(.button)
                    Toggle("Hora", isOn: $showTime).toggleStyle(.button)
                    Toggle("Cámara", isOn: $showSpecs).toggleStyle(.button)
                    Menu {
                        Button("Sin feeling") { feeling = nil; apply() }
                        ForEach(AutoText.feelings, id: \.self) { item in
                            Button(item) { feeling = item; apply() }
                        }
                    } label: {
                        ChipLabel(title: feeling ?? "Feeling", icon: "heart.fill")
                    }
                    Button {
                        model.removeMark()
                    } label: {
                        Image(systemName: "trash").foregroundStyle(.white.opacity(0.7))
                    }
                }
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .tint(.yellow)
                .padding(.horizontal, 20)
            }
        }
        .onChange(of: color) { _, _ in apply() }
        .onChange(of: showPlace) { _, on in
            if on { model.loadPlace() }
            apply()
        }
        .onChange(of: showTime) { _, _ in apply() }
        .onChange(of: showSpecs) { _, _ in apply() }
        .onChange(of: model.placeName) { _, _ in if showPlace { apply() } }
    }

    private func apply() {
        let date = model.isVideo ? Date() : model.info.date
        var parts: [String] = []
        if showPlace, let place = model.placeName { parts.append(place) }
        if showTime { parts.append("\(AutoText.clock(date)) · \(AutoText.timeOfDay(date))") }
        if let feeling { parts.append(feeling) }
        if showSpecs, !model.isVideo {
            let specs = model.specsText()
            if !specs.isEmpty { parts.append(specs) }
        }
        model.setMark(MarkSpec(silhouette: silhouette, color: UIColor(color), title: title,
                               subtitle: parts.joined(separator: " · ")))
    }
}

struct ColorDot: View {
    let color: Color
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: 26, height: 26)
                .overlay(Circle().stroke(selected ? Color.yellow : Color.white.opacity(0.4), lineWidth: selected ? 2.5 : 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Elemento seleccionado

struct SelectionBar: View {
    @ObservedObject var model: EditorModel
    let onEditText: (EditorOverlay) -> Void

    var body: some View {
        if let selected = model.selected {
            HStack(spacing: 10) {
                Picker("Borde", selection: borderBinding(selected)) {
                    ForEach(OverlayBorder.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
                Slider(value: sizeBinding(selected), in: 0.05...2.5)
                    .tint(.yellow)
                if selected.content.isText {
                    Button { onEditText(selected) } label: {
                        Image(systemName: "pencil").foregroundStyle(.white)
                    }
                }
                Button {
                    var straight = selected
                    straight.rotation = 0
                    model.update(straight)
                } label: {
                    Image(systemName: "rotate.left").foregroundStyle(.white.opacity(0.8))
                }
                Button { model.removeSelected() } label: {
                    Image(systemName: "trash").foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func borderBinding(_ overlay: EditorOverlay) -> Binding<OverlayBorder> {
        Binding(
            get: { model.selected?.border ?? overlay.border },
            set: { value in
                guard var current = model.selected else { return }
                current.border = value
                model.update(current)
            }
        )
    }

    private func sizeBinding(_ overlay: EditorOverlay) -> Binding<Double> {
        Binding(
            get: { Double(model.selected?.size ?? overlay.size) },
            set: { value in
                guard var current = model.selected else { return }
                current.size = CGFloat(value)
                model.update(current)
            }
        )
    }
}

// MARK: - Miniaturas de stickers

struct StickerThumbView: View {
    let name: String
    var tint: UIColor?
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                if let tint {
                    Image(uiImage: image)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(Color(uiColor: tint))
                } else {
                    Image(uiImage: image).resizable().scaledToFit()
                }
            } else {
                Color.white.opacity(0.05)
            }
        }
        .onAppear {
            ThumbCache.shared.thumb(name) { image = $0 }
        }
    }
}
