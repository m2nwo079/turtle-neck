import SwiftUI

// 옆에서 본 거북이 — 자세 점수에 따라 목이 앞으로 뻗음
struct TurtleView: View {
    var score: Double

    private var t: Double { min(1, max(0, score / 20)) }
    private var neckLength: CGFloat { 10 + CGFloat(t) * 90 }
    private var bodyColor: Color {
        Color(hue: 0.33 - 0.25 * t, saturation: 0.55, brightness: 0.72)
    }

    var body: some View {
        GeometryReader { geo in
            let cx = geo.size.width / 2
            let cy = geo.size.height / 2

            ZStack {
                Ellipse()
                    .fill(bodyColor)
                    .frame(width: 150, height: 110)
                    .overlay(
                        Ellipse().stroke(bodyColor.opacity(0.45), lineWidth: 10)
                            .scaleEffect(0.65)
                    )
                    .position(x: cx + 30, y: cy)

                ForEach([-40.0, 55.0], id: \.self) { dx in
                    Capsule()
                        .fill(bodyColor)
                        .frame(width: 24, height: 38)
                        .position(x: cx + 30 + dx, y: cy + 60)
                }

                Triangle()
                    .fill(bodyColor)
                    .frame(width: 30, height: 22)
                    .rotationEffect(.degrees(-90))
                    .position(x: cx + 110, y: cy + 5)

                Capsule()
                    .fill(bodyColor)
                    .frame(width: 30, height: neckLength + 20)
                    .rotationEffect(.degrees(-90))
                    .position(x: cx - 40 - neckLength / 2, y: cy - 8)

                ZStack {
                    Circle().fill(bodyColor).frame(width: 48, height: 48)
                    ZStack {
                        Circle().fill(.white).frame(width: 15, height: 15)
                        Circle().fill(.black).frame(width: 7, height: 7)
                            .offset(y: CGFloat(t) * 3)
                    }
                    .offset(x: -8, y: -6)
                }
                .position(x: cx - 40 - neckLength - 8, y: cy - 8)
            }
        }
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

struct TurtleExperimentView: View {
    @StateObject private var detector = VisionDetector()
    private let pet = TurtlePetController()

    private var stateLabel: String {
        if !detector.calibrated { return "기준 잡기를 눌러주세요" }
        if detector.score < 3 { return "정자세" }
        if detector.score < 10 { return "경증 거북목" }
        if detector.score < 18 { return "중등도 거북목" }
        return "중증 거북목"
    }

    var body: some View {
        VStack(spacing: 18) {
            Text("거북이 펫")
                .font(.title2).bold()
            Text("거북이가 화면 오른쪽 아래에 떠 있습니다.\n자세가 나빠지면 목이 늘어납니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text(stateLabel)
                .font(.headline)
                .foregroundStyle(detector.score < 3 ? .green : (detector.score < 18 ? .orange : .red))

            Text(detector.calibrated ? String(format: "자세 점수: %.0f", detector.score) : detector.status)
                .font(.callout).monospacedDigit()
                .foregroundStyle(.secondary)

            Button("기준 잡기") { detector.calibrate() }
                .controlSize(.large).buttonStyle(.borderedProminent)
        }
        .padding(30)
        .frame(minWidth: 380, minHeight: 320)
        .onAppear {
            detector.start()
            pet.show(detector: detector)
        }
    }
}
