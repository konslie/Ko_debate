import Cocoa

class StatusMenuController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let onToggle: () -> Void
    private let onQuit: () -> Void
    
    init(onToggle: @escaping () -> Void, onQuit: @escaping () -> Void) {
        self.onToggle = onToggle
        self.onQuit = onQuit
        super.init()
        setupMenu()
    }
    
    private func setupMenu() {
        if let button = statusItem.button {
            if #available(macOS 11.0, *) {
                let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
                if let image = NSImage(systemSymbolName: "face.smiling", accessibilityDescription: "HandMirror")?
                    .withSymbolConfiguration(config) {
                    button.image = image
                } else {
                    button.title = "🪞"
                }
            } else {
                button.title = "🪞"
            }
            
            button.target = self
            button.action = #selector(statusBarButtonClicked(_:))
            // 좌클릭과 우클릭 이벤트를 모두 수신하도록 전송 마스크 지정
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        
        // 팝업 메뉴 구성 (우클릭 시에만 노출할 메뉴)
        let titleItem = NSMenuItem(title: "손거울 (HandMirror) v1.0", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let toggleItem = NSMenuItem(title: "거울 켜기/끄기 (좌클릭과 동일)", action: #selector(toggleMirror), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "손거울 완전히 종료 (Quit)", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }
    
    @objc private func toggleMirror() {
        onToggle()
    }
    
    @objc private func quitApp() {
        onQuit()
    }
    
    /// 트레이 아이콘 마우스 업 클릭 핸들러 (좌클릭 시 즉시 거울 토글, 우클릭 시 설정/종료 메뉴 노출)
    @objc private func statusBarButtonClicked(_ sender: Any?) {
        guard let event = NSApp.currentEvent else { return }
        
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            // 우클릭 혹은 Control + 클릭 시 현대적인 팝업 API를 통해 메뉴 노출
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        } else {
            // 일반 좌클릭 시 단축키 오동작 부담 없이 즉시 거울 온/오프!
            onToggle()
        }
    }
}
