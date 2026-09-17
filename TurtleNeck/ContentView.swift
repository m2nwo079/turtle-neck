import SwiftUI
import AVFoundation
import Vision
import Combine

class VisionDetector: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published var status = "카메라 준비 중…"
    @Published var score: Double = 0
    @Published var hasFace = false
    @Published var faceBox: CGRect? = nil
    @Published var calibrated = false
    @Published var cPitch: Double = 0
    @Published var cSize: Double = 0

    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "cam")

    // 현재 평활화된 값
    private var curPitch: Double? = nil
    private var curSize: Double? = nil
    private var pitchBuf: [Double] = []
    private var sizeBuf: [Double] = []

    // 기준값
    private var basePitch: Double = 0
    private var baseSize: Double = 0

    // 튜닝 손잡이
    private let W_PITCH = 1.4
    private let W_SIZE = 120.0
    private let DEADZONE = 4.0
    private let PITCH_DEAD = 1.5

    func start() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            if granted { self.configure() }
            else { DispatchQueue.main.async { self.status = "카메라 권한 거부됨" } }
        }
    }

    func calibrate() {
        guard let p = curPitch, let s = curSize else {
            status = "먼저 얼굴이 잡혀야 합니다"
            return
        }
        basePitch = p; baseSize = s
        calibrated = true
        status = "기준 저장 완료 — 자세를 바꿔보세요"
    }

    private func configure() {
        session.beginConfiguration()
        session.sessionPreset = .high
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            DispatchQueue.main.async { self.status = "카메라를 찾을 수 없음" }
            return
        }
        session.addInput(input)
        let output = AVCaptureVideoDataOutput()
        output.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()
        queue.async { self.session.startRunning() }
        DispatchQueue.main.async { self.status = "감지 중… 바르게 앉아 ‘기준 잡기’를 누르세요" }
    }

    private func avg(_ buf: inout [Double], _ v: Double, _ n: Int) -> Double {
        buf.append(v); if buf.count > n { buf.removeFirst() }
        return buf.reduce(0,+) / Double(buf.count)
    }

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let req = VNDetectFaceRectanglesRequest { [weak self] r, _ in
            guard let self = self,
                  let face = (r.results as? [VNFaceObservation])?.first,
                  let p = face.pitch?.doubleValue else {
                DispatchQueue.main.async { self?.hasFace = false; self?.faceBox = nil }
                return
            }
            let pitchDeg = p * 180 / .pi
            let size = face.boundingBox.height
            DispatchQueue.main.async {
                self.hasFace = true
                self.faceBox = face.boundingBox
                let sp = self.avg(&self.pitchBuf, pitchDeg, 5)
                let ss = self.avg(&self.sizeBuf, size, 5)
                self.curPitch = sp; self.curSize = ss
                self.updateScore(sp, ss)
            }
        }
        req.revision = VNDetectFaceRectanglesRequestRevision3
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
        try? handler.perform([req])
    }

    private func updateScore(_ p: Double, _ s: Double) {
        guard calibrated else { status = "기준 미설정 — ‘기준 잡기’를 누르세요"; return }
        let dP = p - basePitch          // 숙임(양수=숙임)
        let dS = s - baseSize           // 얼굴 커짐

        // 주 신호: pitch
        cPitch = dP > PITCH_DEAD ? (dP - PITCH_DEAD) * W_PITCH : 0
        // 게이트: pitch가 3도 넘게 숙여졌을 때만 얼굴크기 인정
        let gate = dP > 6 ? min(1, (dP - 6) / 5) : 0
        cSize = max(0, dS * W_SIZE) * gate

        let total = cPitch + cSize
        score = total < DEADZONE ? 0 : total - DEADZONE
        status = score < 3 ? "정자세"
               : score < 10 ? "경증 거북목"
               : score < 18 ? "중등도 거북목" : "중증 거북목"
    }
}

struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.wantsLayer = true
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        preview.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        view.layer = CALayer()
        view.layer?.addSublayer(preview)
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct ContentView: View {
    @StateObject private var vd = VisionDetector()
    private var isBad: Bool { vd.calibrated && vd.score >= 3 }

    var body: some View {
        VStack(spacing: 14) {
            Text("Vision 감지 (얼굴 + pitch)")
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

            HStack(spacing: 16) {
                Text(String(format: "숙임 %.1f", vd.cPitch)).font(.caption).monospacedDigit()
                Text(String(format: "얼굴크기 %.1f", vd.cSize)).font(.caption).monospacedDigit()
            }.foregroundStyle(.secondary)

            Button("기준 잡기") { vd.calibrate() }
                .controlSize(.large).buttonStyle(.borderedProminent)
        }
        .padding(20)
        .frame(minWidth: 420, minHeight: 520)
        .onAppear { vd.start() }
    }
}
