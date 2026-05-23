import Cocoa
import SwiftUI

/// 테두리가 없고 투명하며 드래그 가능한 원형 윈도우 클래스
class MirrorWindow: NSWindow {
    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: [.borderless], backing: backingStoreType, defer: flag)
        
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true
        
        // 맨 앞 레이어로 지정
        self.level = .statusBar
        // 모든 가상 데스크톱(Spaces)에 따라다니고 풀스크린 위에서도 작동 가능하도록 설정
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // 원형 백그라운드를 잡아서 창을 마우스로 드래그하여 움직일 수 있도록 허용
        self.isMovableByWindowBackground = true
        self.hidesOnDeactivate = false
    }
    
    // ESC 키(KeyCode 53) 또는 Cmd+Q를 가로채는 기능 구현
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC
            if let controller = self.windowController as? MirrorWindowController {
                controller.hide()
            }
        } else if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "q" {
            NSApp.terminate(nil)
        } else {
            super.keyDown(with: event)
        }
    }
    
    // Command 조합 단축키가 일반 keyDown 함수에 도달하기 전 윈도우 매칭 체인에서 확실히 잡아채 화면 은닉(Hide)
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command && (event.keyCode == 12 || event.charactersIgnoringModifiers?.lowercased() == "q") {
            if let controller = self.windowController as? MirrorWindowController {
                controller.hide()
            }
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
    
    // Key Window와 Main Window가 될 수 있도록 확실히 반환
    override var canBecomeKey: Bool {
        return true
    }
    
    override var canBecomeMain: Bool {
        return true
    }
    
    // 윈도우 클릭 시 맥OS 상에서 앱 자체를 '활성 상태(Active)'로 강제 전환하여 키보드 단축키 작동 보장
    override func mouseDown(with event: NSEvent) {
        NSApp.activate(ignoringOtherApps: true)
        self.makeKeyAndOrderFront(nil)
        super.mouseDown(with: event)
    }
}

/// 윈도우 생명주기 및 디스플레이 연산을 제어하는 윈도우 컨트롤러
class MirrorWindowController: NSWindowController, NSWindowDelegate {
    private var isShown = false
    
    init() {
        super.init(window: nil)
        setupWindow()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupWindow() {
        // 1. 내장 모니터 감지 및 물리 10cm 지름 계산
        let (targetScreen, diameter) = calculateTargetScreenAndSize()
        
        // 2. 스크린 중앙 배치 좌표 연산
        let screenFrame = targetScreen.frame
        let x = screenFrame.minX + (screenFrame.width - diameter) / 2
        let y = screenFrame.minY + (screenFrame.height - diameter) / 2
        let rect = NSRect(x: x, y: y, width: diameter, height: diameter)
        
        // 3. 커스텀 윈도우 인스턴스 생성
        let window = MirrorWindow(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)
        window.delegate = self
        window.windowController = self
        self.window = window
        
        // 켤 때 동적으로 뷰를 할당하여 카메라 세션을 켜고 끄기 위해 초기 contentView 설정은 생략합니다.
    }
    
    /// 내장 디스플레이를 색출하고 해당 화면 기준 정확한 물리 10cm에 매핑되는 포인트 크기를 계산합니다.
    private func calculateTargetScreenAndSize() -> (NSScreen, CGFloat) {
        let screens = NSScreen.screens
        // 기본값: 메인 모니터 또는 첫 번째 모니터
        var targetScreen = NSScreen.main ?? screens.first ?? NSScreen()
        
        // 1. CGDisplayIsBuiltin를 사용해 맥북 본체 스크린 필터링
        for screen in screens {
            if let screenNumberVal = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                let displayID = CGDirectDisplayID(screenNumberVal.uint32Value)
                if CGDisplayIsBuiltin(displayID) != 0 {
                    targetScreen = screen
                    break
                }
            }
        }
        
        // 2. 물리 밀리미터를 활용하여 정확히 10cm (100mm)의 지름 포인트 산출
        var diameter: CGFloat = 430.0 // 기본 폴백(Fallback) 지름
        if let screenNumberVal = targetScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            let displayID = CGDirectDisplayID(screenNumberVal.uint32Value)
            let physicalSize = CGDisplayScreenSize(displayID) // 밀리미터(mm) 반환
            
            if physicalSize.width > 0 {
                let widthMM = CGFloat(physicalSize.width)
                let pointsWidth = targetScreen.frame.width
                let pointsPerMM = pointsWidth / widthMM
                diameter = 100.0 * pointsPerMM // 10cm = 100mm
                
                print("HandMirror [Math]: Built-in monitor detected. Physical width: \(widthMM)mm, Screen Points Width: \(pointsWidth)pt.")
                print("HandMirror [Math]: Calculated Points-Per-MM = \(pointsPerMM). Target 10cm Diameter = \(diameter)pt.")
            } else {
                print("HandMirror [Math]: Physical size measurement failed. Using default 430pt diameter.")
            }
        }
        
        return (targetScreen, diameter)
    }
    
    func toggle() {
        if isShown {
            hide()
        } else {
            show()
        }
    }
    
    func show() {
        guard let window = self.window else { return }
        isShown = true
        
        // 토글 활성화 시 항상 내장 디스플레이 정중앙에 고정되도록 강제 좌표 재지정
        let (targetScreen, diameter) = calculateTargetScreenAndSize()
        let screenFrame = targetScreen.frame
        let x = screenFrame.minX + (screenFrame.width - diameter) / 2
        let y = screenFrame.minY + (screenFrame.height - diameter) / 2
        
        window.setFrame(NSRect(x: x, y: y, width: diameter, height: diameter), display: true)
        
        // 켤 때마다 SwiftUI 카메라 뷰를 새롭게 생성하여 탑재 (onAppear 트리거 -> 카메라 전원 가동 및 녹색 LED 점등)
        let cameraView = CameraContainerView(onClose: { [weak self] in
            self?.hide()
        })
        let hostingView = NSHostingView(rootView: cameraView)
        hostingView.frame = NSRect(x: 0, y: 0, width: diameter, height: diameter)
        
        // 마우스 우클릭 시 나타날 빠른 컨텍스트 메뉴 바인딩
        let contextMenu = NSMenu()
        let closeItem = NSMenuItem(title: "손거울 닫기 (ESC)", action: #selector(closeMenuPressed), keyEquivalent: "")
        closeItem.target = self
        contextMenu.addItem(closeItem)
        
        contextMenu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "손거울 완전히 종료 (Quit)", action: #selector(quitAppPressed), keyEquivalent: "q")
        quitItem.target = self
        contextMenu.addItem(quitItem)
        
        hostingView.menu = contextMenu
        
        // 윈도우에 뷰 장착
        window.contentView = hostingView
        
        // 부드러운 페이드인(Fade-in) 마이크로 애니메이션 연출
        window.alphaValue = 0.0
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().alphaValue = 1.0
        }
    }
    
    func hide() {
        guard let window = self.window else { return }
        isShown = false
        
        // 부드러운 페이드아웃(Fade-out) 마이크로 애니메이션 연출 후 은닉
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().alphaValue = 0.0
        }, completionHandler: {
            if !self.isShown { // 애니메이션 도중 유저가 다시 토글한 경우 처리 방지
                // 윈도우의 contentView를 완전히 날림으로써 카메라 세션을 메모리 해제하여 물리적인 카메라 구동 완전 차단 (녹색 경고 LED 소등)
                window.contentView = nil
                window.orderOut(nil)
            }
        })
    }
    
    @objc private func closeMenuPressed() {
        hide()
    }
    
    @objc private func quitAppPressed() {
        NSApp.terminate(nil)
    }
}
