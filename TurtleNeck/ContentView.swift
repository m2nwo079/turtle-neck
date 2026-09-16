import SwiftUI
import WebKit
import AppKit
import Combine

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

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }
}

struct VignetteView: View {
    let intensity: Double
    var body: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(Color.clear)
                .overlay(
                    RadialGradient(
                        colors: [Color.clear, Color.orange.opacity(intensity * 0.7)],
                        center: .center,
                        startRadius: geo.size.width * 0.28,
                        endRadius: geo.size.width * 0.72
                    )
                )
                .ignoresSafeArea()
        }
        .ignoresSafeArea()
    }
}

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

    private var badStreak = 0
    private var smoothScore = 0.0

    private func tick() {
        smoothScore = 0.3 * score + 0.7 * smoothScore

        let bad = detected && smoothScore >= 5
        if bad { badStreak = min(badStreak + 1, 10) }
        else   { badStreak = 0 }

        if badStreak >= 5 {
            sustain = min(1.0, sustain + 0.06)
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

struct DetectorWebView: NSViewRepresentable {
    let bridge: PoseBridge
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(bridge, name: "pose")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        bridge.webView = webView
        webView.loadHTMLString(Self.html, baseURL: URL(string: "https://localhost"))
        return webView
    }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator() }
    class Coordinator: NSObject, WKNavigationDelegate {}

    static let html = """
    <!DOCTYPE html>
    <html><head><meta charset="utf-8"><style>
      body{margin:0;background:#111;overflow:hidden} video{width:100%;display:block}
    </style></head><body>
    <video id="v" autoplay playsinline muted></video>
    <script type="module">
    import { FilesetResolver, PoseLandmarker }
      from "https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.14";
    function send(o){ window.webkit.messageHandlers.pose.postMessage(o); }
    let landmarker, baseline = null;
    let emaAngle = null, emaZ = null, emaHeight = null;
    const A = 0.15;
    const W_ANGLE = 1.0, W_Z = 80.0, W_HEIGHT = 60.0, DEADZONE = 6;
    function angle(a,b,c){
      const v1={x:a.x-b.x,y:a.y-b.y}, v2={x:c.x-b.x,y:c.y-b.y};
      const dot=v1.x*v2.x+v1.y*v2.y, m1=Math.hypot(v1.x,v1.y), m2=Math.hypot(v2.x,v2.y);
      if(m1===0||m2===0) return 0;
      return Math.acos(Math.max(-1,Math.min(1,dot/(m1*m2))))*180/Math.PI;
    }
    window.calibrate = () => {
      if(emaAngle!==null){ baseline={angle:emaAngle,z:emaZ,height:emaHeight};
        send({status:"기준 저장 완료 — 이제 자세를 무너뜨려 보세요"}); }
      else { send({status:"먼저 자세가 잡혀야 합니다"}); }
    };
    async function init(){
      try{
        const vision = await FilesetResolver.forVisionTasks(
          "https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.14/wasm");
        landmarker = await PoseLandmarker.createFromOptions(vision, {
          baseOptions:{ modelAssetPath:
            "https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_lite/float16/1/pose_landmarker_lite.task" },
          runningMode:"VIDEO", numPoses:1 });
        send({status:"카메라 요청 중…"});
        const stream = await navigator.mediaDevices.getUserMedia({video:true});
        const v = document.getElementById("v"); v.srcObject = stream; await v.play();
        send({status:"감지 중… 바르게 앉아 ‘기준 잡기’를 누르세요"});
        loop();
      }catch(e){ send({status:"오류: "+e.message}); }
    }
    function loop(){
      const v = document.getElementById("v");
      if(landmarker && v.readyState>=2){
        const res = landmarker.detectForVideo(v, performance.now());
        if(res.landmarks && res.landmarks.length){
          const lm = res.landmarks[0];
          const nose = lm[0];
          const ear = {x:(lm[7].x+lm[8].x)/2, y:(lm[7].y+lm[8].y)/2, z:(lm[7].z+lm[8].z)/2};
          const shoulder = {x:(lm[11].x+lm[12].x)/2, y:(lm[11].y+lm[12].y)/2, z:(lm[11].z+lm[12].z)/2};
          const rawAngle = angle(nose, ear, shoulder);
          const rawZ = shoulder.z - ear.z;
          const rawHeight = shoulder.y - ear.y;
          emaAngle  = emaAngle===null ? rawAngle : A*rawAngle+(1-A)*emaAngle;
          emaZ      = emaZ===null ? rawZ : A*rawZ+(1-A)*emaZ;
          emaHeight = emaHeight===null ? rawHeight : A*rawHeight+(1-A)*emaHeight;
          let sc=0, st="기준 미설정 — ‘기준 잡기’를 누르세요", cA=0, cZv=0, cH=0;
          if(baseline!==null){
            cA  = Math.max(0, baseline.angle - emaAngle) * W_ANGLE;
            cZv = Math.max(0, emaZ - baseline.z) * W_Z;
            cH  = Math.max(0, baseline.height - emaHeight) * W_HEIGHT;
            const total = cA+cZv+cH;
            sc = total < DEADZONE ? 0 : total - DEADZONE;
            if(sc<5) st="정자세"; else if(sc<12) st="경증 거북목";
            else if(sc<22) st="중등도 거북목"; else st="중증 거북목";
          }
          send({detected:true, score:sc, status:st, cAngle:cA, cZ:cZv, cHeight:cH});
        } else { send({detected:false, status:"사람이 감지되지 않음"}); }
      }
      requestAnimationFrame(loop);
    }
    init();
    </script></body></html>
    """
}

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
