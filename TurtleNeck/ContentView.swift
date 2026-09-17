import SwiftUI

struct SignalBar: View {
    let label: String
    let value: Double
    var body: some View {
        HStack {
            Text(label).font(.caption2).frame(width: 76, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(.gray.opacity(0.15))
                    RoundedRectangle(cornerRadius: 3).fill(.orange)
                        .frame(width: min(geo.size.width, value / 30 * geo.size.width))
                }
            }.frame(height: 10)
            Text(String(format: "%.0f", value)).font(.caption2).monospacedDigit()
                .frame(width: 28, alignment: .trailing)
        }
    }
}

struct ContentView: View {
    @StateObject private var bridge = PoseBridge()
    @State private var showDetails = false

    private var isBad: Bool { bridge.detected && bridge.score >= 5 }

    // 상태에 따른 색과 문구
    private var stateColor: Color {
        if !bridge.calibrated { return .secondary }
        if !bridge.detected { return .secondary }
        if bridge.score < 5 { return .green }
        if bridge.score < 12 { return .yellow }
        return .orange
    }
    private var stateLabel: String {
        if !bridge.calibrated { return "기준 잡기를 눌러주세요" }
        if !bridge.detected { return "감지 대기" }
        if bridge.score < 5 { return "정자세" }
        if bridge.score < 12 { return "경증 거북목" }
        if bridge.score < 18 { return "중등도 거북목" }
        return "중증 거북목"
    }
    var body: some View {
        VStack(spacing: 16) {
            // 작은 카메라 썸네일
            DetectorWebView(bridge: bridge)
                .frame(width: 200, height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(stateColor.opacity(0.5), lineWidth: 2)
                )

            // 현재 상태 (큼직하게)
            VStack(spacing: 4) {
                Text(stateLabel)
                    .font(.title2).bold()
                    .foregroundStyle(stateColor)
                Text(bridge.detected ? String(format: "점수 %.0f", bridge.score) : "—")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            // 기준 잡기
            Button("기준 잡기") { bridge.calibrate() }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)

            Divider()

            // 접이식 상세 (개발·튜닝용)
            DisclosureGroup("상세 보기", isExpanded: $showDetails) {
                VStack(spacing: 6) {
                    SignalBar(label: "숙임", value: bridge.cAngle)
                    SignalBar(label: "얼굴크기", value: bridge.cZ)
                    SignalBar(label: "머리높이", value: bridge.cHeight)
                    HStack {
                        Text("오버레이").font(.caption2).foregroundStyle(.secondary)
                        ProgressView(value: bridge.overlayIntensity)
                        Text(String(format: "%.0f%%", bridge.overlayIntensity * 100))
                            .font(.caption2).monospacedDigit().frame(width: 36, alignment: .trailing)
                    }
                }
                .padding(.top, 6)
            }
            .font(.caption)

            Text(bridge.status)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .padding(18)
        .frame(width: 260)
        .fixedSize(horizontal: false, vertical: true)
    }
}
