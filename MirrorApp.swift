import Cocoa

/// 맥OS 핵심 이벤트 루프를 직접 커스터마이징하여 모든 키 이벤트를 선점하는 커스텀 NSApplication 클래스
class HandMirrorApplication: NSApplication {
    override func sendEvent(_ event: NSEvent) {
        // Command + Q 조합 감지 시 완전히 종료하는 대신 창을 즉시 숨김(Hide) 처리하여 백그라운드 유지
        if event.type == .keyDown {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags == .command && (event.keyCode == 12 || event.charactersIgnoringModifiers?.lowercased() == "q") {
                if let delegate = NSApp.delegate as? AppDelegate {
                    DispatchQueue.main.async {
                        delegate.windowController?.hide()
                    }
                }
                return
            }
        }
        super.sendEvent(event)
    }
}

@main
class MirrorApp {
    static func main() {
        let app = HandMirrorApplication.shared // 커스텀 이벤트 처리 루프 클래스 주입
        app.setActivationPolicy(.regular)
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var windowController: MirrorWindowController?
    var statusMenuController: StatusMenuController?
    var optionKeyMonitor: OptionKeyMonitor?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 윈도우 컨트롤러 생성
        windowController = MirrorWindowController()
        
        // 메뉴바 트레이 아이콘 컨트롤러 생성
        statusMenuController = StatusMenuController(
            onToggle: { [weak self] in
                self?.windowController?.toggle()
            },
            onQuit: {
                NSApp.terminate(nil)
            }
        )
        
        // 양쪽 Option 키 감지 모니터 생성 및 시작
        optionKeyMonitor = OptionKeyMonitor { [weak self] in
            self?.windowController?.toggle()
        }
        optionKeyMonitor?.start()
        
        // 앱이 처음 구동될 때 10cm 거울을 즉시 표시하여 사용자 인지 도모
        DispatchQueue.main.async {
            self.windowController?.show()
        }
        
        // 로컬 키보드 모니터에서도 Cmd + Q 입력 시 즉각 숨김(Hide) 연동
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags == .command && (event.keyCode == 12 || event.charactersIgnoringModifiers?.lowercased() == "q") {
                DispatchQueue.main.async {
                    self?.windowController?.hide()
                }
                return nil
            }
            return event
        }
        
        print("MirrorApp: Custom HandMirrorApplication launched. Cmd+Q highly secured.")
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        optionKeyMonitor?.stop()
        print("MirrorApp: Application terminating.")
    }
}

/// 양쪽 Option 키의 동시 눌림 상태를 감지하여 이벤트를 내보내는 모니터 클래스
class OptionKeyMonitor {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var wasBothOptionPressed = false
    private let onTrigger: () -> Void
    
    private let leftOptionMask: UInt = 0x0020
    private let rightOptionMask: UInt = 0x0040
    
    init(onTrigger: @escaping () -> Void) {
        self.onTrigger = onTrigger
    }
    
    func start() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(with: event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(with: event)
            return event
        }
    }
    
    func stop() {
        if let gm = globalMonitor {
            NSEvent.removeMonitor(gm)
            globalMonitor = nil
        }
        if let lm = localMonitor {
            NSEvent.removeMonitor(lm)
            localMonitor = nil
        }
    }
    
    private func handleFlagsChanged(with event: NSEvent) {
        let rawFlags = event.modifierFlags.rawValue
        let leftOption = (rawFlags & leftOptionMask) != 0
        let rightOption = (rawFlags & rightOptionMask) != 0
        let isBothPressed = leftOption && rightOption
        
        if isBothPressed && !wasBothOptionPressed {
            DispatchQueue.main.async {
                self.onTrigger()
            }
        }
        wasBothOptionPressed = isBothPressed
    }
}
