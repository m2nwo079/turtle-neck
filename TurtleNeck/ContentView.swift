import SwiftUI

struct ContentView: View {
    @StateObject private var vd = VisionDetector()
    private var isBad: Bool { vd.calibrated && vd.score >= 3 }

    var body: some View {
        VStack(spacing: 14) {
            Text("TurtleNeck")
                .font(.title3).bold()

            ZStack {
                CameraPreview(session: vd.session)
                GeometryReader { geo in
                    if let box = vd.faceBox {
                        let rect = CGRect(x: box.minX * geo.size.width,
                                          y: (1 - box.maxY) * geo.size.height,
                                          width: box.width * geo.size.width,
                                          height: box.height * geo.size.height)
                        Rectangle()
                            .stroke(isBad ? Color.orange : Color.green, lineWidth: 3)
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                    }
                }
            }
            .frame(width: 380, height: 285)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Text(vd.calibrated ? String(format: "%.0f", vd.score) : "—")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(isBad ? .orange : .primary)

            Text(vd.status)
                .font(.callout)
                .foregroundStyle(isBad ? .orange : .secondary)

            Button("기준 잡기") { vd.calibrate() }
                .controlSize(.large).buttonStyle(.borderedProminent)
        }
        .padding(20)
        .frame(minWidth: 420, minHeight: 480)
        .onAppear { vd.start() }
    }
}
