import SwiftUI
import AVFoundation
import Vision

/// 손거울의 실시간 뷰 영역 및 메인 레이아웃 컨테이너
struct CameraContainerView: View {
    @StateObject private var cameraManager = CameraManager()
    let onClose: () -> Void
    
    var body: some View {
        ZStack {
            // 배경을 투명하게 하여 원 밖 영역은 아무것도 보이지 않게 처리
            Color.clear
            
            if cameraManager.permissionGranted {
                if cameraManager.hasDevices {
                    // 카메라 프리뷰가 정상 활성화 되었을 때
                    // LERP로 연산된 부드러운 Scale과 Offset을 적용하여 원 내부에서 얼굴 추적 렌더링
                    CameraPreviewView(session: cameraManager.session)
                        .scaleEffect(x: -1, y: 1) // 100% 확실한 좌우 반전(포토부스 동일 거울 모드) 강제 부여
                        .scaleEffect(cameraManager.smoothScale)
                        .offset(cameraManager.smoothOffset)
                        .clipShape(Circle())
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // 카메라 디바이스가 연결되지 않았을 때
                    NoCameraView(
                        iconName: "camera.metering.unknown",
                        title: "카메라를 찾을 수 없음",
                        description: "맥북에 내장된 카메라 혹은 연결된 외장 웹캠이 작동하고 있는지 확인해주세요."
                    )
                }
            } else {
                // 카메라 권한 승인 대기 혹은 거부 상태
                NoCameraView(
                    iconName: "camera.badge.ellipsis",
                    title: "카메라 권한 대기 중",
                    description: "얼굴 및 헤어를 확인하기 위해 카메라 승인이 필요합니다.\n\n양쪽 Option 키로 창을 닫으신 후,\n[시스템 설정 -> 개인정보 보호 및 보안 -> 카메라]\n메뉴에서 HandMirror 권한을 허용해주세요."
                )
            }
            
            // 프리미엄 마이크로 테두리 디자인 (Glassmorphic 은빛 테두리 및 입체 섀도우)
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.85),
                            .gray.opacity(0.35),
                            .white.opacity(0.15),
                            .gray.opacity(0.40),
                            .white.opacity(0.85)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 3.5
                )
                // 은은한 글로우와 그림자 효과로 레이어 구분감 강화
                .shadow(color: Color.black.opacity(0.35), radius: 10, x: 0, y: 5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
        .onAppear {
            cameraManager.checkPermissionAndStart()
        }
        .onDisappear {
            cameraManager.stopSession()
        }
    }
}

/// 카메라 구동 및 Vision 기반 얼굴 인식을 처리하는 코어 매니저 클래스
class CameraManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published var permissionGranted = false
    @Published var hasDevices = true
    
    // SwiftUI가 부드러운 그래픽 보간을 위해 사용하는 상태 변수
    @Published var smoothOffset = CGSize.zero
    @Published var smoothScale: CGFloat = 1.15 // 얼굴 프레이밍을 위한 기본 자연스러운 1.15배 줌
    
    let session = AVCaptureSession()
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "com.konslie.HandMirror.cameraQueue", qos: .userInteractive)
    
    // 센터 스테이지(Center Stage) 활성화 여부
    private var isCenterStageActive = false
    
    // LERP(선형 보간) 대상 목표 수치
    private var targetOffset = CGSize.zero
    private var targetScale: CGFloat = 1.15
    private var displaySize = CGSize(width: 430, height: 430) // 10cm 지름 (약 430pt)
    private var lerpTimer: Timer?
    
    override init() {
        super.init()
    }
    
    deinit {
        lerpTimer?.invalidate()
    }
    
    func checkPermissionAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            self.permissionGranted = true
            self.setupAndStartSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.permissionGranted = granted
                    if granted {
                        self?.setupAndStartSession()
                    }
                }
            }
        default:
            self.permissionGranted = false
        }
    }
    
    private func setupAndStartSession() {
        queue.async { [weak self] in
            guard let self = self else { return }
            if self.session.isRunning { return }
            
            self.session.beginConfiguration()
            
            // 1. 카메라 입력 장치 탑재
            guard let videoDevice = AVCaptureDevice.default(for: .video) else {
                DispatchQueue.main.async { self.hasDevices = false }
                return
            }
            
            do {
                let videoInput = try AVCaptureDeviceInput(device: videoDevice)
                if self.session.canAddInput(videoInput) {
                    self.session.addInput(videoInput)
                }
                
                // 2. 하드웨어 센터 스테이지 자동 인에이블러 (KVC 런타임 바인딩으로 안전성 극대화)
                if videoDevice.responds(to: Selector(("isCenterStageSupported"))) {
                    if let supported = videoDevice.value(forKey: "centerStageSupported") as? Bool, supported {
                        videoDevice.setValue(true, forKey: "centerStageActive")
                        if let active = videoDevice.value(forKey: "centerStageActive") as? Bool {
                            self.isCenterStageActive = active
                            print("HandMirror [Camera]: Hardware Center Stage successfully enabled via KVC!")
                        }
                    }
                }
                
                // 3. 비디오 프레임 캡처 아웃풋 추가 (얼굴 검출 소프트웨어 센터 스테이지용)
                if self.session.canAddOutput(self.videoDataOutput) {
                    self.session.addOutput(self.videoDataOutput)
                    self.videoDataOutput.alwaysDiscardsLateVideoFrames = true
                    self.videoDataOutput.setSampleBufferDelegate(self, queue: self.queue)
                    
                    // 비디오 데이터 아웃풋 커넥션 방향 동기화 (Vision 얼굴 인식율 극대화)
                    if let outputConnection = self.videoDataOutput.connection(with: .video) {
                        if outputConnection.isVideoOrientationSupported {
                            outputConnection.videoOrientation = .landscapeRight
                        }
                        if outputConnection.isVideoMirroringSupported {
                            outputConnection.isVideoMirrored = false // Vision 프레임워크는 가로 정방향 수신
                        }
                    }
                }
                
                self.session.commitConfiguration()
                self.session.startRunning()
                
                print("HandMirror [Camera]: AVCaptureSession started successfully with Center Stage support.")
                
            } catch {
                print("HandMirror [Camera]: Capture Session init error: \(error.localizedDescription)")
            }
        }
        
        // 4. 버터처럼 부드러운 60FPS LERP 모션 스레드 실행
        DispatchQueue.main.async {
            self.lerpTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                self?.updateLerpValues()
            }
        }
    }
    
    func stopSession() {
        lerpTimer?.invalidate()
        lerpTimer = nil
        queue.async { [weak self] in
            guard let self = self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }
    
    // CMSampleBuffer 실시간 스트림 분석
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // 하드웨어 센터 스테이지가 활성화되어 있는 기기라면 
        // 소프트웨어 CPU 파이프라인을 중지하여 발열 및 리소스를 아낍니다.
        if isCenterStageActive {
            return
        }
        
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        // 5. Vision API 기반 얼굴 영역 분석 요구
        let faceDetectionRequest = VNDetectFaceRectanglesRequest { [weak self] request, error in
            guard let self = self else { return }
            if let results = request.results as? [VNFaceObservation], let face = results.first {
                // 실시간 얼굴 감지 성공!
                let bbox = face.boundingBox
                
                // Normalized 좌표 (0.0 ~ 1.0) 획득
                let faceX = bbox.midX
                let faceY = bbox.midY
                let faceWidth = bbox.width
                
                let viewWidth = self.displaySize.width
                let viewHeight = self.displaySize.height
                
                // 너무 과하게 클로즈업되지 않도록 가이드라인 축소 (최소 1.1배 ~ 최대 1.35배)
                let calculatedScale = max(1.10, min(1.35, 0.22 / faceWidth))
                
                // 줌이 가해짐에 따라 카메라 프레임 바깥의 빈 캔버스(여백)가 드러나지 않도록 가동 최대 오프셋 계산
                let maxOffsetW = max(0, viewWidth * (calculatedScale - 1.0) / 2.0)
                let maxOffsetH = max(0, viewHeight * (calculatedScale - 1.0) / 2.0)
                
                // 거울 프레임 맵핑에 완벽히 동조하는 X축 오프셋 계산
                let rawOffsetX = (faceX - 0.5) * viewWidth * calculatedScale
                let rawOffsetY = (faceY - 0.5) * viewHeight * calculatedScale
                
                // 바운더리 클램핑(Clamping)하여 검은 빈 틈 차단
                let finalOffsetX = max(-maxOffsetW, min(maxOffsetW, rawOffsetX))
                let finalOffsetY = max(-maxOffsetH, min(maxOffsetH, rawOffsetY))
                
                DispatchQueue.main.async {
                    self.targetOffset = CGSize(width: finalOffsetX, height: -finalOffsetY)
                    self.targetScale = calculatedScale
                }
            } else {
                // 얼굴이 미감지된 경우 서서히 기본의 여유로운 1.15배 줌 상태로 복귀
                DispatchQueue.main.async {
                    self.targetOffset = .zero
                    self.targetScale = 1.15
                }
            }
        }
        
        let requestHandler = VNImageRequestHandler(cvPixelBuffer: imageBuffer, options: [:])
        try? requestHandler.perform([faceDetectionRequest])
    }
    
    // 매 초 60번 보간을 주어 자연스러운 반응 속도(0.08)를 부여
    private func updateLerpValues() {
        let factor: CGFloat = 0.08 // 묵직하고 은은하게 얼굴을 팔로잉하는 프레임워크 댐핑 값
        
        smoothScale = smoothScale * (1 - factor) + targetScale * factor
        
        let smoothW = smoothOffset.width * (1 - factor) + targetOffset.width * factor
        let smoothH = smoothOffset.height * (1 - factor) + targetOffset.height * factor
        smoothOffset = CGSize(width: smoothW, height: smoothH)
    }
}

/// SwiftUI 내에 AVFoundation AVCaptureVideoPreviewLayer를 브릿징하는 컴포넌트
struct CameraPreviewView: NSViewRepresentable {
    let session: AVCaptureSession
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        
        // 거울 모드 (좌우 반전) 기본 활성화하여 포토부스처럼 자연스러운 시야 제공
        if let connection = previewLayer.connection {
            if connection.isVideoMirroringSupported {
                connection.isVideoMirrored = true
            }
        }
        
        view.layer?.addSublayer(previewLayer)
        context.coordinator.previewLayer = previewLayer
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let layer = context.coordinator.previewLayer {
                layer.frame = nsView.bounds
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {
        var previewLayer: AVCaptureVideoPreviewLayer?
    }
}

/// 카메라 권한 오류 및 디바이스 오동작 시 노출되는 메인 세레모니 뷰
struct NoCameraView: View {
    let iconName: String
    let title: String
    let description: String
    
    var body: some View {
        ZStack {
            // 다크하고 미니멀한 반투명 유리 배경
            Circle()
                .fill(Color(NSColor.windowBackgroundColor).opacity(0.95))
            
            VStack(spacing: 12) {
                Image(systemName: iconName)
                    .font(.system(size: 38, weight: .thin))
                    .foregroundColor(.gray)
                
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.primary)
                
                Text(description)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 32)
            }
        }
        .clipShape(Circle())
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
