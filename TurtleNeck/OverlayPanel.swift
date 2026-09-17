//
//  OverlayPanel.swift
//  TurtleNeck
//
//  Created by 이민우 on 9/17/26.
//

import SwiftUI
import AppKit

class FloatingPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.nonactivatingPanel, .borderless],
                   backing: .buffered, defer: false)
        self.isFloatingPanel = true
        self.level = .screenSaver
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.ignoresMouseEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        self.hidesOnDeactivate = false
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

class OverlayController {
    private var panel: FloatingPanel?
    func show() {
        guard panel == nil, let screen = NSScreen.main else { return }
        let p = FloatingPanel(contentRect: screen.frame)
        p.contentView = NSHostingView(rootView: VignetteView(intensity: 0))
        p.orderFrontRegardless()
        panel = p
    }
    func update(intensity: Double) {
        guard let p = panel else { return }
        p.contentView = NSHostingView(rootView: VignetteView(intensity: intensity))
    }
    func hide() { panel?.orderOut(nil); panel = nil }
}

struct VignetteView: View {
    let intensity: Double
    var body: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(Color.clear)
                .overlay(
                    RadialGradient(
                        colors: [Color.clear, Color.orange.opacity(intensity * 0.6)],
                        center: .center,
                        startRadius: geo.size.width * 0.30,
                        endRadius: geo.size.width * 0.72
                    )
                )
                .ignoresSafeArea()
        }
        .ignoresSafeArea()
    }
}
