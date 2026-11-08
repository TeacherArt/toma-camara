import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct CameraScreen: View {
    @StateObject private var cam = CameraService()
    @State private var editorSession: EditorSession?
    @State private var showPicker = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var showPoses = false
    @State private var activePose: PoseIdea?
    @State private var showGhost = true
    @State private var mirrorGhost = false
    @State private var loadingPick = false
    @State private var pinching = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 12) {
                topBar
                previewArea
                Spacer(minLength: 0)
                ModeSwitcher(selected: cam.mode) { cam.setMode($0) }
                bottomBar
            }
            .padding(.bottom, 6)

            if let text = cam.toastText {
                VStack {
                    Text(text)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Color.black.opacity(0.75)))
                        .padding(.top, 70)
                        .padding(.horizontal, 20)
                    Spacer()
                }
                .transition(.opacity)
            }

            if loadingPick {
                ProgressView().tint(.white).scaleEffect(1.4)
            }

            if cam.cameraDenied { deniedOverlay }
        }
        .animation(.easeInOut(duration: 0.2), value: cam.toastText)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            cam.start()
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .onReceive(cam.$lastShot) { shot in
            guard let shot else { return }
            editorSession = EditorSession(source: .photo(image: shot.image, info: shot.info, raw: shot.raw))
        }
        .onChange(of: editorSession?.id) { _, id in
            cam.setEditorOpen(id != nil)
            if id == nil { cam.lastShot = nil }
        }
        .photosPicker(isPresented: $showPicker, selection: $pickerItem, matching: .any(of: [.images, .videos]))
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await loadPicked(item) }
        }
        .sheet(isPresented: $showPoses) {
            PosePanel(detectedPeople: cam.analyzer.reading.people,
                      selected: $activePose,
                      autoShot: $cam.autoPoseShot)
        }
        .fullScreenCover(item: $editorSession) { session in
            EditorView(session: session,
                       style: cam.style,
                       formats: cam.dualFormat ? [.vertical, .horizontal] : [.original]) { thumbnail, saved in
                if saved {
                    if let thumbnail { cam.lastThumbnail = thumbnail }
                    cam.toast("Guardado en Fotos")
                }
            }
        }
    }

    // MARK: Galería

    private func loadPicked(_ item: PhotosPickerItem) async {
        loadingPick = true
        defer {
            loadingPick = false
            pickerItem = nil
        }
        let isMovie = item.supportedContentTypes.contains { $0.conforms(to: .movie) }
        if isMovie {
            if let movie = try? await item.loadTransferable(type: PickedMovie.self) {
                editorSession = EditorSession(source: .video(movie.url))
            } else {
                cam.toast("No se pudo abrir el video")
            }
            return
        }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = CIImage(data: data, options: [.applyOrientationProperty: true]) else {
            cam.toast("No se pudo abrir la foto")
            return
        }
        let normalized = Framing.normalized(image)
        editorSession = EditorSession(source: .photo(image: normalized, info: ShotInfo(imageData: data), raw: nil))
    }

    // MARK: Partes

    private var topBar: some View {
        HStack(spacing: 8) {
            if cam.mode.isPhoto {
                RoundIcon(system: cam.flash.icon, active: cam.flash != .off) { cam.cycleFlash() }
                RoundIcon(system: "timer", label: cam.timer.label, active: cam.timer != .off) { cam.cycleTimer() }
            }
            RoundIcon(system: "viewfinder.circle", active: cam.guideOn) {
                cam.guideOn.toggle()
                cam.toast(cam.guideOn ? "Guía de escena activada" : "Guía desactivada")
            }
            RoundIcon(system: "figure.stand", active: activePose != nil) { showPoses = true }
            Spacer(minLength: 4)
            if cam.mode == .video {
                PillToggle(title: "PLANO", isOn: cam.flatVideo) { cam.flatVideo.toggle() }
                    .disabled(cam.isRecording)
            }
            if cam.mode != .raw {
                PillToggle(title: "9:16×16:9", isOn: cam.dualFormat) { cam.dualFormat.toggle() }
                    .disabled(cam.isRecording)
            }
            if cam.mode == .photo || cam.mode == .g7x {
                PillToggle(title: cam.maxResolution ? "48MP" : "24MP", isOn: cam.maxResolution) {
                    cam.setMaxResolution(!cam.maxResolution)
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
    }

    private var previewArea: some View {
        ZStack {
            if let renderer = cam.previewRenderer {
                MetalPreview(renderer: renderer)
            } else {
                Color(white: 0.08)
            }

            ThirdsGrid()
                .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
                .allowsHitTesting(false)

            if cam.dualFormat && cam.mode != .raw && !cam.guideOn { DualGuides() }

            if let pose = activePose, showGhost, let ghost = pose.image {
                PoseGhost(image: ghost, mirrored: mirrorGhost)
            }

            if cam.guideOn {
                GuideOverlay(analyzer: cam.analyzer, level: cam.level)
            }

            if cam.countdown > 0 {
                Text("\(cam.countdown)")
                    .font(.system(size: 120, weight: .thin, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(radius: 10)
            }

            VStack {
                if let pose = activePose {
                    ActivePoseChip(pose: pose,
                                   ghostOn: showGhost,
                                   hasGhost: pose.image != nil,
                                   onToggleGhost: { showGhost.toggle() },
                                   onMirror: { mirrorGhost.toggle() },
                                   onClose: { activePose = nil })
                        .padding(.top, cam.guideOn ? 92 : 10)
                }
                if cam.isRecording {
                    RecordingBadge(seconds: cam.recordingSeconds)
                        .padding(.top, 12)
                }
                Spacer()
                ZoomPills(stops: cam.zoomStops, current: cam.zoomDisplay) { cam.setZoom($0) }
                    .padding(.bottom, 6)
                DialPicker(items: LookStyle.allCases.filter { $0 != .plano },
                           selected: cam.style,
                           title: { $0.title },
                           icon: { $0.icon },
                           onSelect: { cam.style = $0 })
                    .opacity(cam.mode == .video && cam.flatVideo ? 0.35 : 1)
                    .disabled(cam.mode == .video && cam.flatVideo)
                    .padding(.bottom, 10)
            }

            if cam.mode == .raw {
                VStack {
                    HStack {
                        Spacer()
                        Text("RAW · DNG")
                            .font(.system(size: 10, weight: .heavy, design: .monospaced))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.yellow))
                            .padding(10)
                    }
                    Spacer()
                }
                .allowsHitTesting(false)
            }

            if cam.shutterBlink {
                Color.black.opacity(0.55).allowsHitTesting(false)
            }
        }
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contentShape(Rectangle())
        .gesture(swipeModes)
        .simultaneousGesture(pinchZoom)
        .padding(.horizontal, 6)
    }

    /// Deslizar a los lados sobre la vista previa cambia de modo, como en la cámara del iPhone.
    private var swipeModes: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height
                guard abs(dx) > 50, abs(dx) > abs(dy) * 1.4 else { return }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    cam.nextMode(dx < 0 ? 1 : -1)
                }
            }
    }

    private var pinchZoom: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if !pinching {
                    pinching = true
                    cam.beginPinch()
                }
                cam.pinch(value.magnification)
            }
            .onEnded { _ in pinching = false }
    }

    private var bottomBar: some View {
        HStack {
            Button { showPicker = true } label: {
                Group {
                    if let thumb = cam.lastThumbnail {
                        Image(uiImage: thumb).resizable().scaledToFill()
                    } else {
                        ZStack {
                            Color.white.opacity(0.12)
                            Image(systemName: "photo.on.rectangle").foregroundStyle(.white)
                        }
                    }
                }
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            Spacer()
            ShutterButton(mode: cam.mode, recording: cam.isRecording) { cam.shutter() }
            Spacer()

            Button { cam.flipCamera() } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(Color.white.opacity(0.12)))
            }
            .disabled(cam.isRecording)
        }
        .padding(.horizontal, 28)
    }

    private var deniedOverlay: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill").font(.system(size: 40))
            Text("Toma necesita permiso para usar la cámara.")
                .multilineTextAlignment(.center)
            Button("Abrir Configuración") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.yellow)
            .foregroundStyle(.black)
        }
        .foregroundStyle(.white)
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}
