import SwiftUI
import AppKit
import Combine

class FloatingPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.nonactivatingPanel, .borderless],
                   backing: .buffered,
                   defer: false)
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

class OverlayController: ObservableObject {
    private var panel: FloatingPanel?

    @Published var intensity: Double = 0 {
        didSet { updateOverlay() }
    }

    func showOverlay() {
        guard panel == nil else { return }
        guard let screen = NSScreen.main else { return }
        let p = FloatingPanel(contentRect: screen.frame)
        p.contentView = NSHostingView(rootView: VignetteView(intensity: intensity))
        p.orderFrontRegardless()
        self.panel = p
        updateOverlay()
    }

    func hideOverlay() {
        panel?.orderOut(nil)
        panel = nil
    }

    private func updateOverlay() {
        guard let p = panel else { return }
        p.contentView = NSHostingView(rootView: VignetteView(intensity: intensity))
    }
}

struct VignetteView: View {
    let intensity: Double

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Rectangle()
                    .fill(Color.clear)
                    .overlay(
                        RadialGradient(
                            colors: [Color.clear, Color.orange.opacity(intensity * 0.9)],
                            center: .center,
                            startRadius: geo.size.width * 0.28,
                            endRadius: geo.size.width * 0.72
                        )
                    )
            }
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
    }
}

struct ContentView: View {
    @StateObject private var overlay = OverlayController()

    var body: some View {
        VStack(spacing: 24) {
            Text("오버레이 검증 (전체화면 대응)")
                .font(.title2).bold()

            Text("오버레이를 켠 뒤 다른 앱을 전체화면으로 전환해\n그 위에 주황이 보이는지 확인하세요.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Text("약").font(.caption).foregroundStyle(.secondary)
                Slider(value: $overlay.intensity, in: 0...1)
                Text("강").font(.caption).foregroundStyle(.secondary)
            }

            Text(String(format: "강도: %.0f%%", overlay.intensity * 100))
                .font(.headline)
                .monospacedDigit()

            HStack(spacing: 12) {
                Button("오버레이 켜기") { overlay.showOverlay() }
                    .buttonStyle(.borderedProminent)
                Button("끄기") { overlay.hideOverlay() }
            }
        }
        .padding(32)
        .frame(minWidth: 460, minHeight: 340)
    }
}
