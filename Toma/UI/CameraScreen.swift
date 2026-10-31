import SwiftUI

struct CameraScreen: View {
    @StateObject private var cam = CameraService()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 12) {
                topBar
                previewArea
                StyleStrip(selected: cam.style) { cam.style = $0 }
                modeSwitch
                bottomBar
            }
            .padding(.bottom, 6)

            if let text = cam.toastText {
                VStack {
                    Text(text)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Color.black.opacity(0.75)))
                        .padding(.top, 70)
                    Spacer()
                }
                .transition(.opacity)
            }

            if cam.cameraDenied { deniedOverlay }
        }
        .animation(.easeInOut(duration: 0.2), value: cam.toastText)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            cam.start()
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .fullScreenCover(item: $cam.lastShot) { shot in
            RevealView(shot: shot,
                       style: cam.style,
                       formats: cam.dualFormat ? [.vertical, .horizontal] : [.original]) { thumbnail in
                if let thumbnail {
                    cam.lastThumbnail = thumbnail
                    cam.toast("Guardado en Fotos")
                } else {
                    cam.toast("No se pudo guardar")
                }
            }
        }
    }

    // MARK: Partes

    private var topBar: some View {
        HStack(spacing: 10) {
            if cam.mode == .photo {
                RoundIcon(system: cam.flash.icon, active: cam.flash != .off) { cam.cycleFlash() }
                RoundIcon(system: "timer", label: cam.timer.label, active: cam.timer != .off) { cam.cycleTimer() }
            }
            Spacer()
            PillToggle(title: "9:16 × 16:9", isOn: cam.dualFormat) { cam.dualFormat.toggle() }
                .disabled(cam.isRecording)
            if cam.mode == .photo {
                PillToggle(title: cam.maxResolution ? "48 MP" : "24 MP", isOn: cam.maxResolution) {
                    cam.setMaxResolution(!cam.maxResolution)
                }
            }
        }
        .padding(.horizontal, 16)
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

            if cam.dualFormat { DualGuides() }

            if cam.countdown > 0 {
                Text("\(cam.countdown)")
                    .font(.system(size: 120, weight: .thin, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(radius: 10)
            }

            VStack {
                if cam.isRecording {
                    RecordingBadge(seconds: cam.recordingSeconds)
                        .padding(.top, 12)
                }
                Spacer()
                ZoomPills(stops: cam.zoomStops, current: cam.zoomDisplay) { cam.setZoom($0) }
                    .padding(.bottom, 12)
            }

            if cam.shutterBlink {
                Color.black.opacity(0.55).allowsHitTesting(false)
            }
        }
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 6)
    }

    private var modeSwitch: some View {
        HStack(spacing: 28) {
            ForEach([CaptureMode.photo, CaptureMode.video], id: \.self) { mode in
                Button { cam.setMode(mode) } label: {
                    Text(mode == .photo ? "FOTO" : "VIDEO")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .tracking(1.5)
                        .foregroundStyle(cam.mode == mode ? Color.yellow : Color.white.opacity(0.55))
                }
                .disabled(cam.isRecording)
            }
        }
    }

    private var bottomBar: some View {
        HStack {
            Button { cam.openPhotos() } label: {
                Group {
                    if let thumb = cam.lastThumbnail {
                        Image(uiImage: thumb).resizable().scaledToFill()
                    } else {
                        Color.white.opacity(0.12)
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
