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
        webView.uiDelegate = context.coordinator
        webView.perform(Selector(("_setWindowOcclusionDetectionEnabled:")), with: false)
        bridge.webView = webView
        webView.loadHTMLString(Self.html, baseURL: URL(string: "https://localhost"))
        return webView
    }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator() }
    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        func webView(_ webView: WKWebView,
                     requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                     initiatedByFrame frame: WKFrameInfo,
                     type: WKMediaCaptureType,
                     decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            decisionHandler(.grant)
        }
    }
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
    import { FilesetResolver, PoseLandmarker, FaceLandmarker }
      from "https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.14";
    function send(o){ window.webkit.messageHandlers.pose.postMessage(o); }

    let poseLM, faceLM, baseline = null;
    let frame = 0;
    let lastShoulderW = null, lastShoulderY = null;
    let lastFace = null;   // {cx, cy, size, pitch, pts}

    const WIN = 5;
    let bufPitch = [], bufHeadDrop = [], bufSizeRatio = [];
    let curPitch = null, curHeadDrop = null, curSizeRatio = null;

    function pushAvg(buf, v){
      buf.push(v);
      if(buf.length > WIN) buf.shift();
      return buf.reduce((a,b)=>a+b, 0) / buf.length;
    }

    window.calibrate = () => {
      if(curPitch!==null){ baseline={pitch:curPitch, headDrop:curHeadDrop, sizeRatio:curSizeRatio};
        send({status:"기준 저장 완료 — 자세를 바꿔가며 원본값 변화를 관찰하세요"}); }
      else { send({status:"먼저 어깨·얼굴이 모두 잡혀야 합니다"}); }
    };

    function pitchFromMatrix(m){
      // MediaPipe 변환행렬(4x4, 열 우선)에서 회전 3x3 추출
      const r00=m[0], r01=m[4], r02=m[8];
      const r10=m[1], r11=m[5], r12=m[9];
      const r20=m[2], r21=m[6], r22=m[10];
      // pitch = 고개 상하 각도 (X축 회전)
      const pitch = Math.atan2(-r12, Math.sqrt(r02*r02 + r22*r22)) * 180/Math.PI;
      return pitch;
    }

    function draw(){
      const v = document.getElementById("v");
      const c = document.getElementById("c");
      c.width = v.videoWidth; c.height = v.videoHeight;
      const ctx = c.getContext("2d");
      ctx.clearRect(0,0,c.width,c.height);
      // 얼굴 지점 코·눈·귀 (파랑)
      if(lastFace && lastFace.pts){
        ctx.fillStyle = "#3399ff";
        ctx.font = "bold 16px sans-serif";
        for(const p of lastFace.pts){
          ctx.beginPath(); ctx.arc(p.x*c.width, p.y*c.height, 6, 0, Math.PI*2); ctx.fill();
          ctx.fillText(p.name, p.x*c.width + 8, p.y*c.height - 8);
        }
      }
      // 어깨 (초록)
      if(window._shL && window._shR){
        ctx.fillStyle = "#22ff55";
        for(const p of [window._shL, window._shR]){
          ctx.beginPath(); ctx.arc(p.x*c.width, p.y*c.height, 8, 0, Math.PI*2); ctx.fill();
        }
      }
    }

    async function init(){
      try{
        const vision = await FilesetResolver.forVisionTasks(
          "https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.14/wasm");
        poseLM = await PoseLandmarker.createFromOptions(vision, {
          baseOptions:{ modelAssetPath:
            "https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_lite/float16/1/pose_landmarker_lite.task" },
          runningMode:"VIDEO", numPoses:1 });
        faceLM = await FaceLandmarker.createFromOptions(vision, {
          baseOptions:{ modelAssetPath:
            "https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task" },
          runningMode:"VIDEO", numFaces:1,
          outputFacialTransformationMatrixes:true });
        send({status:"카메라 요청 중…"});
        const stream = await navigator.mediaDevices.getUserMedia({video:true});
        const v = document.getElementById("v"); v.srcObject = stream; await v.play();
        send({status:"감지 중… 바르게 앉아 ‘기준 잡기’를 누르세요"});
        loop();
      }catch(e){ send({status:"오류: "+e.message}); }
    }

    function loop(){
      const v = document.getElementById("v");
      if(poseLM && faceLM && v.readyState>=2){
        const t = performance.now();
        frame++;
        if(frame % 2 === 1){
          const r = poseLM.detectForVideo(v, t);
          if(r.landmarks && r.landmarks.length){
            const lm = r.landmarks[0];
            const shL = lm[11], shR = lm[12];
            window._shL = shL; window._shR = shR;
            lastShoulderW = Math.hypot(shL.x - shR.x, shL.y - shR.y);
            lastShoulderY = (shL.y + shR.y) / 2;
          }
        } else {
          const r = faceLM.detectForVideo(v, t);
          if(r.faceLandmarks && r.faceLandmarks.length){
            const lm = r.faceLandmarks[0];
            let minX=1,minY=1,maxX=0,maxY=0;
            for(const p of lm){
              if(p.x<minX)minX=p.x; if(p.x>maxX)maxX=p.x;
              if(p.y<minY)minY=p.y; if(p.y>maxY)maxY=p.y;
            }
            const mat = r.facialTransformationMatrixes
                        && r.facialTransformationMatrixes.length
                        ? r.facialTransformationMatrixes[0].data : null;
            // 코1, 왼눈33, 오눈263, 왼귀234, 오귀454
            lastFace = {
              cx:(minX+maxX)/2, cy:(minY+maxY)/2, size:(maxY-minY),
              pitch: mat ? pitchFromMatrix(mat) : 0,
              pts:[
                {x:lm[1].x, y:lm[1].y, name:"코"},
                {x:lm[33].x, y:lm[33].y, name:"눈"},
                {x:lm[263].x, y:lm[263].y, name:"눈"},
                {x:lm[234].x, y:lm[234].y, name:"귀"},
                {x:lm[454].x, y:lm[454].y, name:"귀"},
                {x:lm[13].x, y:lm[13].y, name:"입"},
                {x:lm[152].x, y:lm[152].y, name:"턱"}
              ]
            };
          }
        }
        draw();

        if(lastFace!==null && lastShoulderW!==null && lastShoulderY!==null){
          const headDrop = lastFace.cy - lastShoulderY;
          const sizeRatio = lastFace.size / lastShoulderW;
          const p = pushAvg(bufPitch, lastFace.pitch);
          const hd = pushAvg(bufHeadDrop, headDrop);
          const sr = pushAvg(bufSizeRatio, sizeRatio);
          curPitch = p; curHeadDrop = hd; curSizeRatio = sr;

          let st = "기준 미설정 — ‘기준 잡기’를 누르세요";
          let sc = 0, cP = 0, cH = 0, cS = 0;
          if(baseline!==null){
            const dP = p - baseline.pitch;      // 숙임(양수=숙임)
            const dH = hd - baseline.headDrop;  // 머리높이 변화
            const dS = sr - baseline.sizeRatio; // 얼굴크기 변화

            // 주 신호: pitch 숙임 (데드존 2도)
            cP = dP > 2 ? (dP - 2) : 0;

            // 게이트: pitch가 3도 이상 숙여졌을 때만 보조신호 인정
            const gate = dP > 3 ? Math.min(1, (dP - 3) / 5) : 0;
            cH = Math.max(0, dH * 100) * gate;   // 머리높이 보조
            cS = Math.max(0, dS * 200) * gate;   // 얼굴크기 보조

            // 합산 (주 신호에 가중, 보조는 게이트로 걸러진 값)
            const total = cP * 1.0 + cH * 0.5 + cS * 0.5;
            sc = total;

            let level = total < 3 ? "정자세"
                      : total < 10 ? "경증 거북목"
                      : total < 18 ? "중등도 거북목" : "중증 거북목";
            st = level + "  (숙임:" + cP.toFixed(1)
               + " 보조:" + (cH*0.5 + cS*0.5).toFixed(1) + ")";
          }
          send({detected:true, score:sc, status:st, cAngle:cP, cZ:cS, cHeight:cH});
        } else {
          send({detected:false, status:"어깨·얼굴 인식 대기 중… 상반신이 보이게 앉아주세요"});
        }
      }
      requestAnimationFrame(loop);
    }
    init();
    </script></body></html>
    """
}
