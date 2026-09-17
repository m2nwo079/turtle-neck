//
//  PoseBridge.swift
//  TurtleNeck
//
//  Created by 이민우 on 9/17/26.
//

import SwiftUI
import WebKit
import Combine

class PoseBridge: NSObject, ObservableObject, WKScriptMessageHandler {
    @Published var score: Double = 0
    @Published var status: String = "웹 감지 엔진 로딩 중…"
    @Published var detected: Bool = false
    @Published var cAngle: Double = 0
    @Published var cZ: Double = 0
    @Published var cHeight: Double = 0
    @Published var overlayIntensity: Double = 0

    var webView: WKWebView?
    private let overlay = OverlayController()
    private var sustain: Double = 0
    private var badStreak = 0
    private var smoothScore = 0.0
    private var timer: Timer?

    override init() {
        super.init()
        overlay.show()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func userContentController(_ userContentController: WKUserContentController,
                              didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        DispatchQueue.main.async {
            if let s = body["status"] as? String { self.status = s }
            if let d = body["detected"] as? Bool { self.detected = d }
            if let sc = body["score"] as? Double { self.score = sc }
            if let a = body["cAngle"] as? Double { self.cAngle = a }
            if let z = body["cZ"] as? Double { self.cZ = z }
            if let h = body["cHeight"] as? Double { self.cHeight = h }
        }
    }

    private func tick() {
        smoothScore = 0.7 * score + 0.3 * smoothScore
        let bad = detected && smoothScore >= 5
        if bad { badStreak = min(badStreak + 1, 10) } else { badStreak = 0 }
        if badStreak >= 2 {
            sustain = min(1.0, sustain + 0.14)
        } else {
            sustain = max(0.0, sustain - 0.12)
        }
        let severity = min(1.0, smoothScore / 25.0)
        let intensity = severity * sustain
        overlayIntensity = intensity
        overlay.update(intensity: intensity)
    }

    func calibrate() {
        webView?.evaluateJavaScript("window.calibrate && window.calibrate();")
    }
}
