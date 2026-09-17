import SwiftUI
import AVFoundation
import Vision
import Combine

class VisionTest: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published var status = "카메라 준비 중…"
    @Published var pitch: Double = 0
    @Published var hasFace = false
    @Published var hasPitch = false
    @Published var faceBox: CGRect? = nil

    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "cam")
    private var buf: [Double] = []

    func start() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            if granted { self.configure() }
            else { DispatchQueue.main.async { self.status = "카메라 권한 거부됨" } }
        }
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
        DispatchQueue.main.async { self.status = "감지 중…" }
    }

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let request = VNDetectFaceRectanglesRequest { [weak self] req, _ in
            guard let self = self,
                  let face = (req.results as? [VNFaceObservation])?.first else {
                DispatchQueue.main.async { self?.hasFace = false; self?.faceBox = nil }
                return
            }
            DispatchQueue.main.async {
                self.hasFace = true
                self.faceBox = face.boundingBox
                if let p = face.pitch?.doubleValue {
                    self.hasPitch = true
                    let deg = p * 180 / .pi
                    // 5프레임 평균으로 안정화
                    self.buf.append(deg)
                    if self.buf.count > 5 { self.buf.removeFirst() }
                    self.pitch = self.buf.reduce(0,+) / Double(self.buf.count)
                } else {
                    self.hasPitch = false
                }
            }
        }
        request.revision = VNDetectFaceRectanglesRequestRevision3
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
        try? handler.perform([request])
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
    @StateObject private var vt = VisionTest()

    var body: some View {
        VStack(spacing: 16) {
            Text("Vision pitch 검증")
                .font(.title3).bold()

            ZStack {
                CameraPreview(session: vt.session)
                GeometryReader { geo in
                    if let box = vt.faceBox {
                        let rect = CGRect(x: box.minX * geo.size.width,
                                          y: (1 - box.maxY) * geo.size.height,
                                          width: box.width * geo.size.width,
                                          height: box.height * geo.size.height)
                        Rectangle()
                            .stroke(vt.hasPitch ? Color.green : Color.orange, lineWidth: 3)
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                    }
                }
            }
            .frame(width: 400, height: 300)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            if vt.hasFace {
                if vt.hasPitch {
                    Text(String(format: "pitch(숙임): %.1f°", vt.pitch))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.green)
                        .monospacedDigit()
                } else {
                    Text("얼굴은 잡히는데 pitch가 안 나옴")
                        .foregroundStyle(.orange)
                }
            } else {
                Text("얼굴 미감지")
                    .foregroundStyle(.secondary)
            }

            Text(vt.status).font(.caption).foregroundStyle(.tertiary)
        }
        .padding(20)
        .frame(minWidth: 440, minHeight: 440)
        .onAppear { vt.start() }
    }
}
