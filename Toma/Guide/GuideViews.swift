import SwiftUI

/// Capa sobre la vista previa: tipo de escena, indicación, caja objetivo y nivel.
struct GuideOverlay: View {
    @ObservedObject var analyzer: SceneAnalyzer
    @ObservedObject var level: LevelMonitor

    var body: some View {
        let advice = GuideEngine.advise(analyzer.reading, level: level.reading)
        GeometryReader { geo in
            ZStack {
                if let target = advice.target {
                    GuideBox(rect: target, size: geo.size, color: .yellow, dashed: false)
                }
                if let subject = advice.subject {
                    GuideBox(rect: subject, size: geo.size, color: advice.good ? .yellow : .white, dashed: true)
                }
                if level.reading.gz > -0.8 {
                    LevelLine(roll: level.reading.roll)
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                }
                VStack(spacing: 8) {
                    AdviceBubble(advice: advice)
                    Spacer()
                    HStack {
                        SceneChip(kind: analyzer.reading.kind, people: analyzer.reading.people)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 150)
                }
                .padding(.top, 10)

                if analyzer.stillProgress > 0.02 {
                    StillRing(progress: analyzer.stillProgress)
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: advice.message)
        }
        .allowsHitTesting(false)
    }
}

private struct GuideBox: View {
    let rect: CGRect
    let size: CGSize
    let color: Color
    let dashed: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(color.opacity(0.9), style: StrokeStyle(lineWidth: dashed ? 1.5 : 2.5, dash: dashed ? [6, 5] : []))
            .frame(width: max(rect.width * size.width, 10), height: max(rect.height * size.height, 10))
            .position(x: rect.midX * size.width, y: rect.midY * size.height)
            .animation(.easeOut(duration: 0.25), value: rect)
    }
}

private struct LevelLine: View {
    let roll: Double

    var body: some View {
        let isLevel = abs(roll) < 1.5
        HStack(spacing: 6) {
            Rectangle().frame(width: 34, height: 1.5)
            Circle().stroke(lineWidth: 1.5).frame(width: 8, height: 8)
            Rectangle().frame(width: 34, height: 1.5)
        }
        .foregroundStyle(isLevel ? Color.yellow : Color.white.opacity(0.85))
        .rotationEffect(.degrees(-roll))
        .animation(.easeOut(duration: 0.12), value: roll)
    }
}

private struct AdviceBubble: View {
    let advice: GuideAdvice

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                if let arrow = advice.arrow {
                    Image(systemName: arrow.icon).font(.system(size: 15, weight: .bold))
                } else if advice.good {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 15, weight: .bold))
                }
                Text(advice.message).font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(advice.good ? Color.yellow : Color.white)
            Text(advice.tip)
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.black.opacity(0.6)))
        .padding(.horizontal, 18)
    }
}

private struct SceneChip: View {
    let kind: SceneKind
    let people: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: kind.icon)
            Text(people > 0 ? "\(kind.title) · \(people)" : kind.title)
        }
        .font(.system(size: 11, weight: .bold, design: .monospaced))
        .foregroundStyle(.black)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.yellow))
    }
}

private struct StillRing: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.25), lineWidth: 5)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.yellow, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("Quieto…").font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(.white)
        }
        .frame(width: 74, height: 74)
        .animation(.linear(duration: 0.25), value: progress)
    }
}

/// Indicación de la pose elegida, arriba de la vista previa.
struct ActivePoseChip: View {
    let pose: PoseIdea
    let onClose: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: pose.symbol)
                .font(.system(size: 20))
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(pose.title).font(.system(size: 13, weight: .bold, design: .rounded))
                Text(pose.detail).font(.system(size: 11, design: .rounded)).opacity(0.85)
            }
            Spacer(minLength: 0)
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 12, weight: .bold))
            }
        }
        .foregroundStyle(.white)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.black.opacity(0.65)))
        .padding(.horizontal, 12)
    }
}

/// Coach de poses: sugiere según cuántas personas hay y qué quieres mostrar.
struct PosePanel: View {
    let detectedPeople: Int
    @Binding var selected: PoseIdea?
    @Binding var autoShot: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var group: PeopleGroup
    @State private var focus: PoseFocus = .outfit

    init(detectedPeople: Int, selected: Binding<PoseIdea?>, autoShot: Binding<Bool>) {
        self.detectedPeople = detectedPeople
        _selected = selected
        _autoShot = autoShot
        _group = State(initialValue: PeopleGroup(count: detectedPeople))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if detectedPeople > 0 {
                        Label("Detecté \(detectedPeople) \(detectedPeople == 1 ? "persona" : "personas")",
                              systemImage: "person.crop.rectangle")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Picker("Personas", selection: $group) {
                        ForEach(PeopleGroup.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if group == .solo {
                        Text("¿Qué quieres mostrar?").font(.subheadline.weight(.semibold))
                        Picker("Enfoque", selection: $focus) {
                            ForEach(PoseFocus.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }

                    Toggle(isOn: $autoShot) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Disparo automático").font(.subheadline.weight(.semibold))
                            Text("Toma la foto cuando te quedas quieto en la pose.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .tint(.yellow)

                    ForEach(PoseLibrary.ideas(for: group, focus: focus)) { pose in
                        Button {
                            selected = pose
                            dismiss()
                        } label: {
                            PoseCard(pose: pose, isSelected: selected == pose)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .navigationTitle("Poses")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct PoseCard: View {
    let pose: PoseIdea
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: pose.symbol)
                .font(.system(size: 26))
                .frame(width: 52, height: 52)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.yellow.opacity(0.18)))
                .foregroundStyle(Color.yellow)
            VStack(alignment: .leading, spacing: 3) {
                Text(pose.title).font(.headline)
                Text(pose.detail).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if isSelected {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.yellow)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.secondarySystemBackground)))
    }
}
