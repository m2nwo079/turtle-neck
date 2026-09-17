//
//  DetectorWebView.swift
//  TurtleNeck
//

import SwiftUI
import WebKit

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
      body{margin:0;background:#111;overflow:hidden;position:relative}
      #wrap{position:relative;width:100%}
      video{width:100%;display:block}
      canvas{position:absolute;top:0;left:0;width:100%;height:100%}
    </style></head><body>
    <div id="wrap">
      <video id="v" autoplay playsinline muted></video>
      <canvas id="c"></canvas>
    </div>
    <script type="module">
    import { FilesetResolver, PoseLandmarker }
      from "https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.14";
    function send(o){ window.webkit.messageHandlers.pose.postMessage(o); }

    let landmarker, baseline = null;
    const WIN = 5;
    const WIN_Z = 12;        // z축은 더 길게 평균 (노이즈 큼)
    let bufDrop = [], bufZ = [], bufHeight = [];
    let curDrop = null, curZ = null, curHeight = null;

    // 가중치 · 데드존 (조정 손잡이)
    const W_DROP = 900.0;    // 숙임(코가 귀보다 내려간 정도)
    const W_Z = 100.0;       // 목빼기(귀가 어깨보다 앞)
    const W_HEIGHT = 60.0;   // 머리높이 보조
    const DEADZONE = 6;
    const DROP_DEAD = 0.012; // 숙임 정자세 튐 차단
    const Z_DEAD = 0.010;    // 목빼기 정자세 튐 차단

    function pushAvg(buf, v){
      buf.push(v);
      if(buf.length > WIN) buf.shift();
      return buf.reduce((a,b)=>a+b, 0) / buf.length;
    }
    function pushAvgN(buf, v, n){
      buf.push(v);
      if(buf.length > n) buf.shift();
      return buf.reduce((a,b)=>a+b, 0) / buf.length;
    }

    window.calibrate = () => {
      if(curDrop!==null){ baseline={drop:curDrop, z:curZ, height:curHeight};
        send({status:"기준 저장 완료 — 이제 자세를 무너뜨려 보세요"}); }
      else { send({status:"먼저 자세가 잡혀야 합니다"}); }
    };

    // 코·귀·어깨 초록 점 그리기
    function draw(pts){
      const v = document.getElementById("v");
      const c = document.getElementById("c");
      c.width = v.videoWidth; c.height = v.videoHeight;
      const ctx = c.getContext("2d");
      ctx.clearRect(0,0,c.width,c.height);
      ctx.fillStyle = "#22ff55";
      ctx.strokeStyle = "#22ff55";
      ctx.font = "bold 20px sans-serif";
      for(const p of pts){
        const x = p.x * c.width, y = p.y * c.height;
        ctx.beginPath(); ctx.arc(x, y, 8, 0, Math.PI*2); ctx.fill();
        ctx.fillText(p.name, x + 12, y - 10);
      }
    }

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
          const earL = lm[7], earR = lm[8], shL = lm[11], shR = lm[12];
          const ear = {x:(earL.x+earR.x)/2, y:(earL.y+earR.y)/2, z:(earL.z+earR.z)/2};
          const shoulder = {x:(shL.x+shR.x)/2, y:(shL.y+shR.y)/2, z:(shL.z+shR.z)/2};

          // 초록 점 그리기 (코 + 양쪽 귀 + 양쪽 어깨)
          draw([
            {x:nose.x, y:nose.y, name:"코"},
            {x:earL.x, y:earL.y, name:"귀"},
            {x:earR.x, y:earR.y, name:"귀"},
            {x:shL.x, y:shL.y, name:"어깨"},
            {x:shR.x, y:shR.y, name:"어깨"}
          ]);

          // 숙임: 코가 귀보다 아래로 내려간 정도
          const rawDrop = nose.y - ear.y;
          // 목빼기: 귀가 어깨보다 앞
          const rawZ = shoulder.z - ear.z;
          // 머리높이 보조
          const rawHeight = shoulder.y - ear.y;

          const drop = pushAvg(bufDrop, rawDrop);
          const z = pushAvgN(bufZ, rawZ, WIN_Z);
          const height = pushAvg(bufHeight, rawHeight);
          curDrop = drop; curZ = z; curHeight = height;

          let sc=0, st="기준 미설정 — ‘기준 잡기’를 누르세요", cA=0, cZv=0, cH=0;
          if(baseline!==null){
            // 숙임
            const dropDiff = Math.max(0, (drop - baseline.drop) - DROP_DEAD);
            cA = dropDiff * W_DROP;
            // 목빼기 (낮은 구간 민감 + 세기 1.3)
            const zDiff = Math.max(0, (z - baseline.z) - Z_DEAD);
            cZv = Math.sqrt(zDiff) * W_Z * 1.3;
            // 머리높이 보조
            cH = Math.max(0, baseline.height - height) * W_HEIGHT;

            // 지배 신호만 강조 (약한 쪽 60%로)
            if (cA > cZv) { cZv *= 0.6; } else { cA *= 0.6; }

            const total = cA + cZv + cH;
            sc = total < DEADZONE ? 0 : total - DEADZONE;
            if(sc<5) st="정자세"; else if(sc<12) st="경증 거북목";
            else if(sc<22) st="중등도 거북목"; else st="중증 거북목";
          }
          send({detected:true, score:sc, status:st, cAngle:cA, cZ:cZv, cHeight:cH});
        } else {
          send({detected:false, status:"사람이 감지되지 않음"});
        }
      }
      requestAnimationFrame(loop);
    }
    init();
    </script></body></html>
    """
}
