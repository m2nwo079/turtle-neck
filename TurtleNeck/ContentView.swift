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

    var webView: WKWebView?

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
    <html>
    <head><meta charset="utf-8"><style>
      body{margin:0;background:#111;overflow:hidden}
      video{width:100%;display:block}
    </style></head>
    <body>
    <video id="v" autoplay playsinline muted></video>
    <script type="module">
    import { FilesetResolver, PoseLandmarker }
      from "https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.14";

    function send(o){ window.webkit.messageHandlers.pose.postMessage(o); }

    let landmarker, baseline = null;
    let emaAngle = null, emaZ = null, emaHeight = null;
    const A = 0.15;

    // 가중치 — 튜닝 대상
    const W_ANGLE = 1.0;
    const W_Z = 80.0;
    const W_HEIGHT = 60.0;
    const DEADZONE = 6;

    function angle(a, b, c){
      const v1 = {x:a.x-b.x, y:a.y-b.y}, v2 = {x:c.x-b.x, y:c.y-b.y};
      const dot = v1.x*v2.x + v1.y*v2.y;
      const m1 = Math.hypot(v1.x,v1.y), m2 = Math.hypot(v2.x,v2.y);
      if(m1===0||m2===0) return 0;
      return Math.acos(Math.max(-1,Math.min(1,dot/(m1*m2)))) * 180/Math.PI;
    }

    window.calibrate = () => {
      if(emaAngle !== null){
        baseline = { angle:emaAngle, z:emaZ, height:emaHeight };
        send({status:"기준 저장 완료 — 이제 자세를 무너뜨려 보세요"});
      } else { send({status:"먼저 자세가 잡혀야 합니다"}); }
    };

    async function init(){
      try{
        const vision = await FilesetResolver.forVisionTasks(
          "https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.14/wasm");
        landmarker = await PoseLandmarker.createFromOptions(vision, {
          baseOptions:{ modelAssetPath:
            "https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_lite/float16/1/pose_landmarker_lite.task" },
          runningMode:"VIDEO", numPoses:1
        });
        send({status:"카메라 요청 중…"});
        const stream = await navigator.mediaDevices.getUserMedia({video:true});
        const v = document.getElementById("v");
        v.srcObject = stream;
        await v.play();
        send({status:"감지 중… 바르게 앉아 ‘기준 잡기’를 누르세요"});
        loop();
      }catch(e){ send({status:"오류: "+e.message}); }
    }

    function loop(){
      const v = document.getElementById("v");
      if(landmarker && v.readyState >= 2){
        const res = landmarker.detectForVideo(v, performance.now());
        if(res.landmarks && res.landmarks.length){
          const lm = res.landmarks[0];
          const nose = lm[0];
          const ear = { x:(lm[7].x+lm[8].x)/2, y:(lm[7].y+lm[8].y)/2, z:(lm[7].z+lm[8].z)/2 };
          const shoulder = { x:(lm[11].x+lm[12].x)/2, y:(lm[11].y+lm[12].y)/2, z:(lm[11].z+lm[12].z)/2 };

          // 신호 1: 코-귀-어깨 각도
          const rawAngle = angle(nose, ear, shoulder);
          // 신호 2: 귀와 어깨의 앞뒤 깊이 차 (귀가 앞으로 나오면 커짐)
          const rawZ = shoulder.z - ear.z;
          // 신호 3: 어깨 대비 머리 높이 (머리가 내려가면 작아짐)
          const rawHeight = shoulder.y - ear.y;

          emaAngle  = emaAngle===null ? rawAngle : A*rawAngle + (1-A)*emaAngle;
          emaZ      = emaZ===null ? rawZ : A*rawZ + (1-A)*emaZ;
          emaHeight = emaHeight===null ? rawHeight : A*rawHeight + (1-A)*emaHeight;

          let sc = 0, st = "기준 미설정 — ‘기준 잡기’를 누르세요";
          let cA = 0, cZv = 0, cH = 0;

          if(baseline !== null){
            // 각 신호를 기준 대비 나쁜 방향으로만 점수화
            cA  = Math.max(0, baseline.angle - emaAngle) * W_ANGLE;
            cZv = Math.max(0, emaZ - baseline.z) * W_Z;
            cH  = Math.max(0, baseline.height - emaHeight) * W_HEIGHT;

            const total = cA + cZv + cH;
            sc = total < DEADZONE ? 0 : total - DEADZONE;

            if(sc < 5) st = "정자세";
            else if(sc < 12) st = "경증 거북목";
            else if(sc < 22) st = "중등도 거북목";
            else st = "중증 거북목";
          }

          send({ detected:true, score:sc, status:st,
                 cAngle:cA, cZ:cZv, cHeight:cH });
        } else {
          send({detected:false, status:"사람이 감지되지 않음"});
        }
      }
      requestAnimationFrame(loop);
    }
    init();
    </script>
    </body>
    </html>
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
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.orange)
                        .frame(width: min(geo.size.width, value / 30 * geo.size.width))
                }
            }
            .frame(height: 14)
            Text(String(format: "%.1f", value))
                .font(.caption).monospacedDigit()
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
            }
            .padding(.horizontal, 8)

            Button("기준 잡기") { bridge.calibrate() }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
        }
        .padding(20)
        .frame(minWidth: 480, minHeight: 620)
    }
}
