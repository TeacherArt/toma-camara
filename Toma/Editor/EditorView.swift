import SwiftUI

enum EditorTool: String, CaseIterable, Identifiable {
    case estilo, ajustes, marco, formato, texto, stickers, marca

    var id: String { rawValue }

    var title: String {
        switch self {
        case .estilo: return "Estilo"
        case .ajustes: return "Ajustes"
        case .marco: return "Marco"
        case .formato: return "Formato"
        case .texto: return "Texto"
        case .stickers: return "Stickers"
        case .marca: return "Marca"
        }
    }

    var icon: String {
        switch self {
        case .estilo: return "camera.filters"
        case .ajustes: return "slider.horizontal.3"
        case .marco: return "square.on.square"
        case .formato: return "aspectratio"
        case .texto: return "textformat"
        case .stickers: return "face.smiling"
        case .marca: return "signature"
        }
    }

    static func available(video: Bool) -> [EditorTool] {
        video ? [.estilo, .ajustes, .texto, .stickers, .marca] : allCases
    }
}

/// Borrador para la hoja de texto (nuevo o editando uno existente).
struct TextDraft: Identifiable {
    let id = UUID()
    var overlayID: UUID?
    var spec: TextSpec
    var border: OverlayBorder
}

/// Editor de fotos y videos: estilos, ajustes, marcos, formatos, textos, stickers y marca Arthur.
struct EditorView: View {
    @StateObject private var model: EditorModel
    @Environment(\.dismiss) private var dismiss
    private let onDone: (UIImage?, Bool) -> Void
    @State private var tool: EditorTool = .estilo
    @State private var textDraft: TextDraft?
    @State private var showStickers = false
    @State private var errorText: String?

    init(session: EditorSession, style: LookStyle, formats: Set<OutputFormat>,
         onDone: @escaping (UIImage?, Bool) -> Void) {
        _model = StateObject(wrappedValue: EditorModel(source: session.source, style: style, formats: formats))
        self.onDone = onDone
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 10) {
                header
                EditorCanvas(model: model, onEditText: editText)
                    .padding(.horizontal, 14)
                if model.selected != nil {
                    SelectionBar(model: model, onEditText: editText)
                }
                panel
                    .frame(height: 112)
                ToolTabs(tools: EditorTool.available(video: model.isVideo), selected: $tool)
                saveBar
            }
            if let errorText {
                Text(errorText)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(Capsule().fill(Color.red.opacity(0.85)))
            }
        }
        .preferredColorScheme(.dark)
        .sheet(item: $textDraft) { draft in
            TextEditorSheet(draft: draft) { result in applyText(result) }
        }
        .sheet(isPresented: $showStickers) {
            StickerPicker { content, border in
                model.addOverlay(content, border: border)
            }
        }
    }

    // MARK: Partes

    private var header: some View {
        HStack {
            Button("Descartar") { dismiss() }
                .foregroundStyle(.white.opacity(0.8))
            Spacer()
            VStack(spacing: 2) {
                Text(model.isVideo ? "EDITAR VIDEO" : "REVELADO")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .tracking(2)
                if model.isRaw {
                    Text("RAW").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(.yellow)
                }
            }
            .foregroundStyle(.white)
            Spacer()
            Text("Descartar").hidden()
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    @ViewBuilder private var panel: some View {
        switch tool {
        case .estilo:
            StylePanel(model: model)
        case .ajustes:
            AdjustPanel(model: model)
        case .marco:
            FramePanel(model: model)
        case .formato:
            FormatPanel(model: model)
        case .texto:
            TextPanel(model: model, onNewText: newText)
        case .stickers:
            StickerPanel(onOpen: { showStickers = true })
        case .marca:
            MarkPanel(model: model)
        }
    }

    private var saveBar: some View {
        HStack {
            Text(saveSummary)
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
            Spacer()
            Button(action: save) {
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
                .frame(height: 48)
                .background(Capsule().fill(Color.yellow))
            }
            .disabled(model.isSaving)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    private var saveSummary: String {
        if model.isVideo { return "Se guarda como video nuevo" }
        return model.formats.count > 1 ? "Se guardan \(model.formats.count) archivos" : "Se guarda 1 archivo"
    }

    // MARK: Acciones

    private func save() {
        model.selectedID = nil
        if model.isVideo {
            model.saveVideo { ok in
                if ok {
                    onDone(nil, true)
                    dismiss()
                } else {
                    showError("No se pudo guardar el video")
                }
            }
        } else {
            model.savePhoto { thumbnail in
                if let thumbnail {
                    onDone(thumbnail, true)
                    dismiss()
                } else {
                    showError("No se pudo guardar")
                }
            }
        }
    }

    private func showError(_ text: String) {
        errorText = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { errorText = nil }
    }

    private func newText() {
        textDraft = TextDraft(overlayID: nil,
                              spec: TextSpec(text: "", font: .firma, color: .white),
                              border: .none)
    }

    private func editText(_ overlay: EditorOverlay) {
        guard case .text(let spec) = overlay.content else { return }
        textDraft = TextDraft(overlayID: overlay.id, spec: spec, border: overlay.border)
    }

    private func applyText(_ draft: TextDraft) {
        let text = draft.spec.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let id = draft.overlayID, var overlay = model.overlays.first(where: { $0.id == id }) {
            if text.isEmpty {
                model.selectedID = id
                model.removeSelected()
                return
            }
            overlay.content = .text(draft.spec)
            overlay.border = draft.border
            model.update(overlay)
        } else if !text.isEmpty {
            model.addOverlay(.text(draft.spec), border: draft.border, size: 0.6)
        }
    }
}

/// Pestañas de herramientas.
struct ToolTabs: View {
    let tools: [EditorTool]
    @Binding var selected: EditorTool

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(tools) { tool in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { selected = tool }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: tool.icon).font(.system(size: 17))
                            Text(tool.title).font(.system(size: 10, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(selected == tool ? Color.yellow : Color.white.opacity(0.6))
                        .frame(width: 60, height: 46)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
        }
        .frame(height: 50)
    }
}
