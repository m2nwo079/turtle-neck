//
//  VisionDetector.swift
//  TurtleNeck
//

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
    private var frameCount = 0

    private var curPitch: Double? = nil
    private var curSize: Double? = nil
    private var pitchBuf: [Double] = []
    private var sizeBuf: [Double] = []

    private var basePitch: Double = 0
    private var baseSize: Double = 0

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
        session.sessionPreset = .medium
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
        queue.async {
            self.session.startRunning()
            try? device.lockForConfiguration()
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 15)
            device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 15)
            device.unlockForConfiguration()
        }
        DispatchQueue.main.async { self.status = "감지 중… 바르게 앉아 ‘기준 잡기’를 누르세요" }
    }

    private func avg(_ buf: inout [Double], _ v: Double, _ n: Int) -> Double {
        buf.append(v); if buf.count > n { buf.removeFirst() }
        return buf.reduce(0,+) / Double(buf.count)
    }

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        frameCount += 1
        guard frameCount % 2 == 0 else { return }
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
        let dP = p - basePitch
        let dS = s - baseSize

        cPitch = dP > PITCH_DEAD ? (dP - PITCH_DEAD) * W_PITCH : 0
        let gate = dP > 6 ? min(1, (dP - 6) / 5) : 0
        cSize = max(0, dS * W_SIZE) * gate

        let total = cPitch + cSize
        score = total < DEADZONE ? 0 : total - DEADZONE
        status = score < 3 ? "정자세"
               : score < 10 ? "경증 거북목"
               : score < 18 ? "중등도 거북목" : "중증 거북목"
    }
}
