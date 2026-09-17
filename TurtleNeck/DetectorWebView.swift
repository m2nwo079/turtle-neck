//
//  DetectorWebView.swift
//  TurtleNeck
//
//  Created by 이민우 on 9/17/26.
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
      body{margin:0;background:#111;overflow:hidden} video{width:100%;display:block}
    </style></head><body>
    <video id="v" autoplay playsinline muted></video>
    <script type="module">
    import { FilesetResolver, PoseLandmarker }
      from "https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.14";
    function send(o){ window.webkit.messageHandlers.pose.postMessage(o); }
    let landmarker, baseline = null;
    let emaAngle = null, emaZ = null, emaHeight = null;
        const W_ANGLE = 2.0, W_Z = 100.0, W_HEIGHT = 60.0, DEADZONE = 4;
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
          const Az = 0.4, Aa = 0.3, Ah = 0.3;
          emaAngle  = emaAngle===null ? rawAngle : Aa*rawAngle+(1-Aa)*emaAngle;
          emaZ      = emaZ===null ? rawZ : Az*rawZ+(1-Az)*emaZ;
          emaHeight = emaHeight===null ? rawHeight : Ah*rawHeight+(1-Ah)*emaHeight;
          let sc=0, st="기준 미설정 — ‘기준 잡기’를 누르세요", cA=0, cZv=0, cH=0;
          if(baseline!==null){
            cA  = Math.max(0, baseline.angle - emaAngle) * W_ANGLE;
            const Z_DEAD = 0.004;
            const zDiff = Math.max(0, (emaZ - baseline.z) - Z_DEAD);
            cZv = Math.sqrt(zDiff) * W_Z * 0.85;
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
