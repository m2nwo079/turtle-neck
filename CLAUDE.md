# TurtleNeck

macOS SwiftUI 앱. 웹캠으로 거북목(고개 숙임/전방 머리 자세)을 감지하고 경고한다.
개인 프로젝트, 테스트·README 없음. 빌드는 Xcode(`TurtleNeck.xcodeproj`, 스킴 `TurtleNeck`).

## 제품 방향 (확정: Electron + React 크로스플랫폼)
- 실제 제품은 **Electron + React로 macOS/Windows 동시 지원**. 감지는 MediaPipe JS(Electron 내부)로 이식 예정
- 이 Swift 레포는 감지 전략 검증용 프로토타입. 이식 대상: pitch 주신호 + 얼굴크기 게이트 + 5샘플 평균 + 개인 기준값(수치는 재튜닝 필요)

### 챌린지 1: 데스크톱 전체 오버레이 (OpenPets `apps/desktop/src/pet-window.ts`, `main.ts`, `docs/desktop.md` 참고)
- macOS: `setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true })` + `setAlwaysOnTop(true, 'floating')` + `app.dock.hide()`
- Windows: 전체화면 앱 진입 시 셸이 TOPMOST를 조용히 제거 → 1초 주기로 `setAlwaysOnTop(false)` 후 재설정(Electron 캐시 우회)
- Windows: `disable-features=CalculateNativeWinOcclusion`으로 전체화면 중 투명 창 페인트 중단 방지
- 클릭 통과: `setIgnoreMouseEvents(true, { forward: true })`. 위 Windows 동작은 OpenPets 측 실측 기록이며 우리 환경 미검증

### 챌린지 2: OS 카메라 사용 (OpenPets는 카메라 미사용 → 직접 검증 필요)
- macOS: `NSCameraUsageDescription`(electron-builder `mac.extendInfo`) 필수. Hardened Runtime 사용 시 `com.apple.security.device.camera` entitlement 없으면 팝업 없이 거부
- macOS: ad-hoc 서명은 빌드마다 cdhash가 바뀌어 **업데이트할 때마다 카메라 권한 재요청**
- Windows: 앱별 권한 팝업 없음, 전역 "데스크톱 앱 카메라 허용" 토글만 존재. Zoom 등과 동시 사용 시 `NotReadableError` 가능성(미검증)
- 창 숨김·가림 시 rAF 스로틀 → `backgroundThrottling: false` 또는 항상 보이는 펫 창에서 감지(미검증)
- MediaPipe wasm·모델은 CDN이 아닌 앱에 번들 (`FilesetResolver.forVisionTasks(<local path>)`)

### 배포·서명·공증 (OpenPets `apps/desktop/electron-builder.yml`, `docs/release.md`, `docs/install.mdx` 참고)
- macOS: Developer ID·공증 없이 ad-hoc 서명(`identity: "-"`, `hardenedRuntime: false`). 완전 무서명은 Apple Silicon에서 "손상됨" 오류 → ad-hoc은 필수
- macOS 설치 안내: `xattr -dr com.apple.quarantine /Applications/<App>.app`
- Windows: GitHub Actions + SignPath(오픈소스 무료 서명)로 앱 exe와 NSIS 설치파일을 각각 서명. 우리 적용 가능 여부(레포 공개 등 조건) 미확인
- OpenPets와 달리 우리는 카메라를 쓰므로 ad-hoc이면 업데이트 배포마다 권한 재요청 → Apple Developer ID 도입 여부 결정 필요

## 프로젝트 설정 (모든 브랜치 동일한 pbxproj)
- macOS 15.7, Swift 5, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, Approachable Concurrency 켜짐
- App Sandbox 켜짐: 카메라 허용, outgoing network 허용(webview 버전 CDN 용), 오디오 등 나머지 차단
- `PBXFileSystemSynchronizedRootGroup` 사용 → `TurtleNeck/`에 .swift 파일만 넣으면 타깃에 자동 포함, pbxproj 수정 불필요
- Bundle ID `com.minwoo.TurtleNeck`, 카메라 사용 문구는 `INFOPLIST_KEY_NSCameraUsageDescription`

## 브랜치 (분기가 아닌 일렬 진화: webview → vision-native → turtle-pet)

| 브랜치 | 감지 엔진 | 신호 | 경고 방식 | UI |
|---|---|---|---|---|
| `webview-version` | WKWebView + MediaPipe Pose/Face (CDN, 네트워크 필수) | pitch + 머리높이(어깨 대비) + 얼굴/어깨 크기비 | 전체화면 주황 비네트 | 260pt 사이드 도킹, 상세 신호 바 |
| `main` = `vision-native` (같은 커밋) | Apple Vision `VNDetectFaceRectanglesRequest` rev3, 15fps | pitch + 얼굴 크기 | 전체화면 주황 비네트 | 큰 프리뷰 + 얼굴 박스 + 점수 (단순) |
| `turtle-pet-experiment` | main과 동일 | main과 동일 | 비네트 제거, 우하단 거북이 펫 목이 늘어남 | 안내 텍스트 + 상태 |

### webview-version
- 파일: `DetectorWebView.swift`(HTML/JS 인라인), `PoseBridge.swift`(JS↔Swift, `pose` 메시지 핸들러), `OverlayPanel.swift`, `ContentView.swift`
- JS에서 프레임 교대로 Pose/Face 실행, 5프레임 이동평균. 점수 = `cP + 0.5*cH + 0.5*cS`
  - `cP` = pitch 변화 − 2° 데드존, 보조신호는 pitch 3° 초과 시에만 게이트(5° 구간 선형)
- 기준 잡기: Swift → `window.calibrate()` 호출, 기준은 JS 메모리에만 존재(앱 재시작 시 소실)
- 비공개 API `_setWindowOcclusionDetectionEnabled:` 사용(가려져도 감지 유지), 카메라 권한 자동 grant
- 상태 임계값 5/12/18, 오버레이: `smoothScore >= 5` 2틱 연속 → sustain 상승, 강도 = min(1, score/25) × sustain

### main / vision-native
- 파일: `VisionDetector.swift`(카메라+Vision+점수+오버레이 tick), `CameraPreview.swift`, `OverlayPanel.swift`, `ContentView.swift`
- 2프레임마다 감지, 5샘플 평균. `cPitch = (dP − 1.5) × 1.4`, 크기 신호는 pitch 6° 초과 시 게이트, 합계에서 데드존 4 차감
- 상태 임계값 3/10/18, 오버레이 강도 = min(1, score/20) × sustain

### turtle-pet-experiment
- main에서 `OverlayPanel.swift` 및 detector의 오버레이 로직 삭제
- `TurtlePetOverlay.swift`: 우하단 260×220 `NSPanel`(`.floating`, 클릭 통과)
- `TurtleExperimentView.swift`: `TurtleView`(score/20 비율로 목 길이 10→100pt, 색 녹→주황)

## 공통 구조 / 관례
- 오버레이는 `NSPanel`(borderless, nonactivating, `ignoresMouseEvents`, `.canJoinAllSpaces + .fullScreenAuxiliary`)로 전체화면 위에 띄움
- 오버레이 갱신은 0.1초 `Timer` tick
- 기존 코드의 주석·UI 문자열은 한국어. 새로 작성하는 주석은 영어, 코드와 별도 줄에

## 알려진 문제 (코드 읽기 기반, 실행 미확인)
- main/pet: 얼굴이 사라지면 `hasFace`만 false가 되고 `score`는 마지막 값에 고정 → 오버레이/거북이 목이 그대로 유지될 수 있음. webview는 `detected`로 게이트함
- main: `captureOutput`이 `cam` 큐에서 호출되는데 기본 actor 격리가 MainActor라 동시성 경고/런타임 문제 가능성 있음(미확인)
- 기준값이 영속되지 않음(모든 브랜치)
