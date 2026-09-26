import AppKit
import ApplicationServices

class WindowManager {
    static let shared = WindowManager()
    
    enum Corner {
        case topLeft, topRight, bottomLeft, bottomRight
    }
    
    private init() {}
    
    // MARK: - Window Positioning
    
    func moveActiveWindowToLeftHalf() {
        guard let window = getFrontmostWindow() else { return }
        guard let screen = NSScreen.main else { return }
        
        let screenFrame = screen.visibleFrame
        let newFrame = CGRect(
            x: screenFrame.minX,
            y: screenFrame.minY,
            width: screenFrame.width / 2,
            height: screenFrame.height
        )
        
        setWindowFrame(window, frame: newFrame)
    }
    
    func moveActiveWindowToRightHalf() {
        guard let window = getFrontmostWindow() else { return }
        guard let screen = NSScreen.main else { return }
        
        let screenFrame = screen.visibleFrame
        let newFrame = CGRect(
            x: screenFrame.minX + screenFrame.width / 2,
            y: screenFrame.minY,
            width: screenFrame.width / 2,
            height: screenFrame.height
        )
        
        setWindowFrame(window, frame: newFrame)
    }
    
    func moveActiveWindowToBottomHalf() {
        guard let window = getFrontmostWindow() else { return }
        guard let screen = NSScreen.main else { return }
        
        let screenFrame = screen.visibleFrame
        let newFrame = CGRect(
            x: screenFrame.minX,
            y: screenFrame.minY,
            width: screenFrame.width,
            height: screenFrame.height / 2
        )
        
        setWindowFrame(window, frame: newFrame)
    }
    
    func moveActiveWindowToTopHalf() {
        guard let window = getFrontmostWindow() else { return }
        guard let screen = NSScreen.main else { return }
        
        let screenFrame = screen.visibleFrame
        let newFrame = CGRect(
            x: screenFrame.minX,
            y: screenFrame.minY + screenFrame.height / 2,
            width: screenFrame.width,
            height: screenFrame.height / 2
        )
        
        setWindowFrame(window, frame: newFrame)
    }
    
    func moveActiveWindowToCorner(_ corner: Corner) {
        guard let window = getFrontmostWindow() else { return }
        guard let screen = NSScreen.main else { return }
        
        let screenFrame = screen.visibleFrame
        let halfWidth = screenFrame.width / 2
        let halfHeight = screenFrame.height / 2
        
        let newFrame: CGRect
        switch corner {
        case .topLeft:
            newFrame = CGRect(
                x: screenFrame.minX,
                y: screenFrame.minY + halfHeight,
                width: halfWidth,
                height: halfHeight
            )
        case .topRight:
            newFrame = CGRect(
                x: screenFrame.minX + halfWidth,
                y: screenFrame.minY + halfHeight,
                width: halfWidth,
                height: halfHeight
            )
        case .bottomLeft:
            newFrame = CGRect(
                x: screenFrame.minX,
                y: screenFrame.minY,
                width: halfWidth,
                height: halfHeight
            )
        case .bottomRight:
            newFrame = CGRect(
                x: screenFrame.minX + halfWidth,
                y: screenFrame.minY,
                width: halfWidth,
                height: halfHeight
            )
        }
        
        setWindowFrame(window, frame: newFrame)
    }
    
    func maximizeActiveWindow() {
        guard let window = getFrontmostWindow() else { return }
        guard let screen = NSScreen.main else { return }
        
        let screenFrame = screen.visibleFrame
        setWindowFrame(window, frame: screenFrame)
    }
    
    func centerActiveWindow() {
        guard let window = getFrontmostWindow() else { return }
        guard let screen = NSScreen.main else { return }
        
        let screenFrame = screen.visibleFrame
        let width = screenFrame.width * 0.7
        let height = screenFrame.height * 0.7
        
        let newFrame = CGRect(
            x: screenFrame.minX + (screenFrame.width - width) / 2,
            y: screenFrame.minY + (screenFrame.height - height) / 2,
            width: width,
            height: height
        )
        
        setWindowFrame(window, frame: newFrame)
    }
    
    // MARK: - Desktop Management
    
    func moveToNextDesktop() {
        // Simulate Ctrl+Right
        let source = CGEventSource(stateID: .hidSystemState)
        
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x7C, keyDown: true) // Right arrow
        keyDown?.flags = [.maskControl]
        keyDown?.post(tap: .cghidEventTap)
        
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x7C, keyDown: false)
        keyUp?.flags = [.maskControl]
        keyUp?.post(tap: .cghidEventTap)
    }
    
    func moveToPreviousDesktop() {
        // Simulate Ctrl+Left
        let source = CGEventSource(stateID: .hidSystemState)
        
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x7B, keyDown: true) // Left arrow
        keyDown?.flags = [.maskControl]
        keyDown?.post(tap: .cghidEventTap)
        
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x7B, keyDown: false)
        keyUp?.flags = [.maskControl]
        keyUp?.post(tap: .cghidEventTap)
    }
    
    // MARK: - Helper Methods
    
    private func getFrontmostWindow() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        
        let appRef = AXUIElementCreateApplication(app.processIdentifier)
        var window: CFTypeRef?
        
        let result = AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &window)
        
        if result == .success, let windowRef = window {
            return (windowRef as! AXUIElement)
        }
        
        return nil
    }
    
    private func setWindowFrame(_ window: AXUIElement, frame: CGRect) {
        // Convert from screen coordinates to window coordinates
        var position = CGPoint(x: frame.origin.x, y: frame.origin.y)
        var size = CGSize(width: frame.size.width, height: frame.size.height)
        
        // Set position
        let positionValue = AXValueCreate(.cgPoint, &position)!
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
        
        // Set size
        let sizeValue = AXValueCreate(.cgSize, &size)!
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
    }
}
