import SwiftUI

/// Hoja para escribir un texto: fuente, color, fondo y borde.
struct TextEditorSheet: View {
    @State private var draft: TextDraft
    @State private var color: Color
    let onDone: (TextDraft) -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    init(draft: TextDraft, onDone: @escaping (TextDraft) -> Void) {
        _draft = State(initialValue: draft)
        _color = State(initialValue: Color(uiColor: draft.spec.color))
        self.onDone = onDone
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    previewBox

                    TextField("Escribe aquí", text: $draft.spec.text, axis: .vertical)
                        .lineLimit(1...4)
                        .font(.title3)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
                        .focused($focused)

                    Text("Fuente").font(.subheadline.weight(.semibold))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(TextFont.allCases) { font in
                                FontChip(font: font, selected: draft.spec.font == font) { draft.spec.font = font }
                            }
                        }
                    }

                    Text("Color").font(.subheadline.weight(.semibold))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(UIColor.palette, id: \.keyString) { swatch in
                                ColorDot(color: Color(uiColor: swatch), selected: draft.spec.color.keyString == swatch.keyString) {
                                    color = Color(uiColor: swatch)
                                }
                            }
                            ColorPicker("", selection: $color, supportsOpacity: false).labelsHidden()
                        }
                        .padding(.vertical, 2)
                    }

                    Text("Fondo").font(.subheadline.weight(.semibold))
                    Picker("Fondo", selection: $draft.spec.background) {
                        ForEach(TextBackground.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    Text("Borde").font(.subheadline.weight(.semibold))
                    Picker("Borde", selection: $draft.border) {
                        ForEach(OverlayBorder.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(16)
            }
            .navigationTitle(draft.overlayID == nil ? "Nuevo texto" : "Editar texto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") {
                        onDone(draft)
                        dismiss()
                    }
                    .bold()
                }
            }
            .onChange(of: color) { _, newColor in
                draft.spec.color = UIColor(newColor)
            }
            .onAppear { focused = draft.spec.text.isEmpty }
        }
        .presentationDetents([.large])
    }

    private var previewBox: some View {
        ZStack {
            Checkerboard()
            if let image = previewImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(14)
            } else {
                Text("Vista previa")
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .frame(height: 150)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var previewImage: UIImage? {
        guard let base = TextRenderer.render(draft.spec) else { return nil }
        if draft.border == .none { return base }
        let scale = 500 / max(base.size.width, base.size.height)
        let small = scale < 1
            ? (base.preparingThumbnail(of: CGSize(width: base.size.width * scale, height: base.size.height * scale)) ?? base)
            : base
        return OverlayRenderer.bordered(small, border: draft.border)
    }
}

private struct FontChip: View {
    let font: TextFont
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(font == .cuentas ? "ABC" : "Aa")
                    .font(Font(font.font(size: 24) as CTFont))
                    .frame(height: 34)
                Text(font.title).font(.caption2)
            }
            .foregroundStyle(selected ? Color.black : Color.primary)
            .frame(width: 72, height: 66)
            .background(RoundedRectangle(cornerRadius: 12).fill(selected ? Color.yellow : Color(.secondarySystemBackground)))
        }
        .buttonStyle(.plain)
    }
}

/// Fondo de cuadros para ver transparencias.
struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            let cell: CGFloat = 12
            let cols = Int(size.width / cell) + 1
            let rows = Int(size.height / cell) + 1
            for row in 0..<rows {
                for col in 0..<cols {
                    let rect = CGRect(x: CGFloat(col) * cell, y: CGFloat(row) * cell, width: cell, height: cell)
                    let light = (row + col) % 2 == 0
                    context.fill(Path(rect), with: .color(light ? Color(white: 0.32) : Color(white: 0.24)))
                }
            }
        }
    }
}

/// Catálogo de stickers: frases (acrílico), stickers y siluetas para teñir.
struct StickerPicker: View {
    let onPick: (OverlayContent, OverlayBorder) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var section: StickerSection = .frases
    @State private var border: OverlayBorder = .acrylic
    @State private var tint: Color = .white

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Picker("Sección", selection: $section) {
                    ForEach(StickerSection.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)

                if section == .siluetas {
                    HStack(spacing: 10) {
                        Text("Color").font(.subheadline.weight(.semibold))
                        ForEach([Color.white, Color.black, Color(uiColor: .wine), Color(uiColor: .toma), Color(uiColor: .mexicanPink)],
                                id: \.self) { swatch in
                            ColorDot(color: swatch, selected: tint == swatch) { tint = swatch }
                        }
                        ColorPicker("", selection: $tint, supportsOpacity: false).labelsHidden()
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                } else {
                    Picker("Borde", selection: $border) {
                        ForEach(OverlayBorder.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                }

                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 12)], spacing: 12) {
                        ForEach(StickerCatalog.items(section)) { item in
                            Button {
                                pick(item)
                            } label: {
                                VStack(spacing: 6) {
                                    StickerThumbView(name: item.name, tint: section == .siluetas ? UIColor(tint) : nil)
                                        .frame(height: 92)
                                    Text(item.title)
                                        .font(.caption2)
                                        .lineLimit(1)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(8)
                                .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.2)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Stickers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
            .onChange(of: section) { _, newSection in
                border = newSection.defaultBorder
            }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }

    private func pick(_ item: StickerItem) {
        if section == .siluetas {
            onPick(.silhouette(item.name, UIColor(tint)), .none)
        } else {
            onPick(.sticker(item.name), border)
        }
        dismiss()
    }
}
