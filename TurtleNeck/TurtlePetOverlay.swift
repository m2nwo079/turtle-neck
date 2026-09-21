//
//  TurtlePetOverlay.swift
//  TurtleNeck
//
//  Created by 이민우 on 9/21/26.
//

import SwiftUI
import AppKit

// 거북이 펫을 데스크톱 한구석에 띄우는 오버레이 창
class TurtlePetController {
    private var panel: NSPanel?

    func show(detector: VisionDetector) {
        guard panel == nil, let screen = NSScreen.main else { return }

        let petW: CGFloat = 260
        let petH: CGFloat = 220
        // 화면 오른쪽 아래 구석에 배치 (여백 40)
        let x = screen.frame.maxX - petW - 40
        let y = screen.frame.minY + 40

        let p = NSPanel(
            contentRect: NSRect(x: x, y: y, width: petW, height: petH),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered, defer: false
        )
        p.isFloatingPanel = true
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = true   // 클릭 통과 (작업 방해 안 함)
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.hidesOnDeactivate = false

        p.contentView = NSHostingView(rootView: TurtlePetView(detector: detector))
        p.orderFrontRegardless()
        panel = p
    }

    func hide() { panel?.orderOut(nil); panel = nil }
}

// 오버레이에 그려질 거북이 (배경 투명)
struct TurtlePetView: View {
    @ObservedObject var detector: VisionDetector

    var body: some View {
        TurtleView(score: detector.score)
            .frame(width: 260, height: 220)
            .background(Color.clear)
    }
}
