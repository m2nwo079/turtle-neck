import SwiftUI

struct SignalBar: View {
    let label: String
    let value: Double
    var body: some View {
        HStack {
            Text(label).font(.caption).frame(width: 92, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(.gray.opacity(0.15))
                    RoundedRectangle(cornerRadius: 4).fill(.orange)
                        .frame(width: min(geo.size.width, value / 30 * geo.size.width))
                }
            }.frame(height: 14)
            Text(String(format: "%.1f", value)).font(.caption).monospacedDigit()
                .frame(width: 40, alignment: .trailing)
        }
    }
}

struct ContentView: View {
    @StateObject private var bridge = PoseBridge()
    private var isBad: Bool { bridge.detected && bridge.score >= 5 }

    var body: some View {
        VStack(spacing: 14) {
            DetectorWebView(bridge: bridge)
                .frame(width: 420, height: 315)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            Text(bridge.detected ? String(format: "%.0f", bridge.score) : "—")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(isBad ? .orange : .primary)

            Text(bridge.status)
                .font(.callout)
                .foregroundStyle(isBad ? .orange : .secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 6) {
                SignalBar(label: "각도(숙임)", value: bridge.cAngle)
                SignalBar(label: "z축(목빼기)", value: bridge.cZ)
                SignalBar(label: "머리높이", value: bridge.cHeight)
            }.padding(.horizontal, 8)

            HStack {
                Text("오버레이").font(.caption).foregroundStyle(.secondary)
                ProgressView(value: bridge.overlayIntensity)
                Text(String(format: "%.0f%%", bridge.overlayIntensity * 100))
                    .font(.caption).monospacedDigit().frame(width: 44, alignment: .trailing)
            }.padding(.horizontal, 8)

            Button("기준 잡기") { bridge.calibrate() }
                .controlSize(.large).buttonStyle(.borderedProminent)
        }
        .padding(20)
        .frame(minWidth: 480, minHeight: 660)
    }
}
