import SwiftUI

struct RoundIcon: View {
    let system: String
    var label: String = ""
    var active = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: system)
                    .font(.system(size: 15, weight: .semibold))
                if !label.isEmpty {
                    Text(label).font(.system(size: 12, weight: .bold, design: .rounded))
                }
            }
            .foregroundStyle(active ? Color.yellow : Color.white)
            .frame(minWidth: 36, minHeight: 36)
            .padding(.horizontal, label.isEmpty ? 0 : 6)
            .background(Capsule().fill(Color.white.opacity(0.12)))
        }
    }
}

struct PillToggle: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(isOn ? Color.black : Color.white.opacity(0.85))
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(Capsule().fill(isOn ? Color.yellow : Color.white.opacity(0.12)))
        }
    }
}

struct StyleStrip: View {
    let selected: LookStyle
    let onSelect: (LookStyle) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 20) {
                ForEach(LookStyle.allCases) { style in
                    Button { onSelect(style) } label: {
                        Text(style.title)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .tracking(1.2)
                            .foregroundStyle(style == selected ? Color.yellow : Color.white.opacity(0.55))
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        .frame(height: 26)
    }
}

struct ZoomPills: View {
    let stops: [CGFloat]
    let current: CGFloat
    let onSelect: (CGFloat) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(stops, id: \.self) { stop in
                Button { onSelect(stop) } label: {
                    Text(label(for: stop, selected: stop == current))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(stop == current ? Color.yellow : Color.white)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Color.black.opacity(0.45)))
                }
            }
        }
    }

    private func label(for stop: CGFloat, selected: Bool) -> String {
        let text = stop < 1 ? ".5" : String(Int(stop))
        return selected ? "\(text)×" : text
    }
}

struct ShutterButton: View {
    let mode: CaptureMode
    let recording: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(Color.white, lineWidth: 4)
                    .frame(width: 78, height: 78)
                if mode == .video {
                    RoundedRectangle(cornerRadius: recording ? 8 : 31, style: .continuous)
                        .fill(Color.red)
                        .frame(width: recording ? 32 : 62, height: recording ? 32 : 62)
                } else {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 64, height: 64)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: recording)
        }
        .buttonStyle(.plain)
    }
}

struct RecordingBadge: View {
    let seconds: Int

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(Color.red).frame(width: 8, height: 8)
            Text(String(format: "%02d:%02d", seconds / 60, seconds % 60))
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.black.opacity(0.55)))
    }
}

/// Cuadrícula de tercios.
struct ThirdsGrid: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for i in 1...2 {
            let x = rect.minX + rect.width * CGFloat(i) / 3
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
            let y = rect.minY + rect.height * CGFloat(i) / 3
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        return path
    }
}

/// Muestra qué parte del cuadro sale en vertical (9:16) y cuál en horizontal (16:9).
struct DualGuides: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let verticalWidth = h * 9 / 16
            let horizontalHeight = w * 9 / 16
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.yellow.opacity(0.85), style: StrokeStyle(lineWidth: 1.2, dash: [6, 5]))
                    .frame(width: verticalWidth, height: h - 2)
                    .position(x: w / 2, y: h / 2)
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.white.opacity(0.8), style: StrokeStyle(lineWidth: 1.2, dash: [6, 5]))
                    .frame(width: w - 2, height: horizontalHeight)
                    .position(x: w / 2, y: h / 2)
                Text("9:16")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.yellow)
                    .position(x: w / 2, y: 14)
                Text("16:9")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .position(x: 22, y: h / 2 - horizontalHeight / 2 + 12)
            }
        }
        .allowsHitTesting(false)
    }
}
