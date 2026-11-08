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
                .padding(.horizontal, 9)
                .frame(height: 32)
                .background(Capsule().fill(isOn ? Color.yellow : Color.white.opacity(0.12)))
        }
    }
}

/// Ruedita como la de "Studio Light" del iPhone: se desliza con el dedo, cambia en vivo,
/// vibra en cada paso y muestra el nombre del elegido en una etiqueta amarilla.
struct DialPicker<Item: Hashable>: View {
    let items: [Item]
    let selected: Item
    let title: (Item) -> String
    let icon: (Item) -> String
    let onSelect: (Item) -> Void
    var spacing: CGFloat = 56

    @State private var dragStartIndex: Int?
    @State private var dragTranslation: CGFloat = 0

    private var selectedIndex: Int { items.firstIndex(of: selected) ?? 0 }

    var body: some View {
        VStack(spacing: 8) {
            Text(title(selected).uppercased())
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .tracking(0.5)
                .foregroundStyle(.black)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.yellow))

            GeometryReader { geo in
                let center = geo.size.width / 2
                let anchor = CGFloat(dragStartIndex ?? selectedIndex)
                ZStack {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        let x = (CGFloat(index) - anchor) * spacing + dragTranslation
                        let distance = abs(x) / spacing
                        DialItem(icon: icon(item), isSelected: item == selected)
                            .scaleEffect(max(0.62, 1 - distance * 0.11))
                            .opacity(max(0.12, 1 - distance * 0.24))
                            .offset(y: distance * distance * 1.6)
                            .position(x: center + x, y: geo.size.height / 2)
                            .onTapGesture { choose(index) }
                    }
                }
            }
            .frame(height: 52)
            .contentShape(Rectangle())
            .gesture(drag)
        }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if dragStartIndex == nil { dragStartIndex = selectedIndex }
                dragTranslation = value.translation.width
                let start = CGFloat(dragStartIndex ?? selectedIndex)
                live(clamp(Int((start - dragTranslation / spacing).rounded())))
            }
            .onEnded { value in
                let start = CGFloat(dragStartIndex ?? selectedIndex)
                live(clamp(Int((start - value.predictedEndTranslation.width / spacing).rounded())))
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    dragStartIndex = nil
                    dragTranslation = 0
                }
            }
    }

    private func clamp(_ index: Int) -> Int {
        min(max(index, 0), items.count - 1)
    }

    private func live(_ index: Int) {
        guard items.indices.contains(index), items[index] != selected else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        onSelect(items[index])
    }

    private func choose(_ index: Int) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { live(index) }
    }
}

private struct DialItem: View {
    let icon: String
    let isSelected: Bool

    var body: some View {
        ZStack {
            if isSelected {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black.opacity(0.35))
                    .frame(width: 46, height: 46)
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.yellow, lineWidth: 2.5)
                    .frame(width: 46, height: 46)
            } else {
                Circle()
                    .fill(Color.black.opacity(0.25))
                    .frame(width: 38, height: 38)
                Circle()
                    .stroke(Color.white.opacity(0.75), lineWidth: 1.2)
                    .frame(width: 38, height: 38)
            }
            Image(systemName: icon)
                .font(.system(size: isSelected ? 18 : 15, weight: .semibold))
                .foregroundStyle(isSelected ? Color.yellow : Color.white)
        }
        .frame(width: 50, height: 50)
        .contentShape(Rectangle())
    }
}

struct ZoomPills: View {
    let stops: [CGFloat]
    let current: CGFloat
    let onSelect: (CGFloat) -> Void

    /// La pastilla activa es la del lente que se está usando; muestra el zoom exacto al pellizcar.
    private var activeStop: CGFloat {
        stops.last(where: { $0 <= current + 0.01 }) ?? stops.first ?? 1
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(stops, id: \.self) { stop in
                let isActive = stop == activeStop
                Button { onSelect(stop) } label: {
                    Text(label(for: stop, active: isActive))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(isActive ? Color.yellow : Color.white)
                        .frame(width: isActive ? 46 : 38, height: 38)
                        .background(Circle().fill(Color.black.opacity(0.45)))
                }
            }
        }
    }

    private func label(for stop: CGFloat, active: Bool) -> String {
        guard active else { return stop < 1 ? ".5" : String(Int(stop)) }
        let value = current
        if abs(value - value.rounded()) < 0.05 { return "\(Int(value.rounded()))×" }
        if value < 1 { return String(format: ".%d×", Int((value * 10).rounded())) }
        return String(format: "%.1f×", value)
    }
}

/// Selector de modos en cápsula (como la cámara de iOS 26): el modo activo queda al centro,
/// dentro de una pastilla; se desliza con el dedo o se toca.
struct ModeSwitcher: View {
    let selected: CaptureMode
    let onSelect: (CaptureMode) -> Void
    private let itemWidth: CGFloat = 92

    var body: some View {
        GeometryReader { geo in
            let modes = CaptureMode.allCases
            let index = CGFloat(modes.firstIndex(of: selected) ?? 0)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.16))
                    .frame(width: itemWidth, height: 38)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                HStack(spacing: 0) {
                    ForEach(modes) { mode in
                        Text(mode.title)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .tracking(0.8)
                            .foregroundStyle(mode == selected ? Color.yellow : Color.white.opacity(0.75))
                            .frame(width: itemWidth, height: geo.size.height)
                            .contentShape(Rectangle())
                            .onTapGesture { onSelect(mode) }
                    }
                }
                .offset(x: geo.size.width / 2 - itemWidth / 2 - index * itemWidth)
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: selected)
            }
        }
        .frame(width: 290, height: 48)
        .background(Capsule().fill(Color.white.opacity(0.08)))
        .clipShape(Capsule())
        .contentShape(Capsule())
        .gesture(
            DragGesture(minimumDistance: 12)
                .onEnded { value in
                    let modes = CaptureMode.allCases
                    guard let i = modes.firstIndex(of: selected), abs(value.translation.width) > 25 else { return }
                    let next = value.translation.width < 0 ? i + 1 : i - 1
                    if next >= 0, next < modes.count { onSelect(modes[next]) }
                }
        )
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
