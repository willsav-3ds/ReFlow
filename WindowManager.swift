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
        guard let screen = screenForWindow(window) else { return }

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
        guard let screen = screenForWindow(window) else { return }

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
        guard let screen = screenForWindow(window) else { return }

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
        guard let screen = screenForWindow(window) else { return }

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
        guard let screen = screenForWindow(window) else { return }

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
        guard let screen = screenForWindow(window) else { return }

        let screenFrame = screen.visibleFrame
        setWindowFrame(window, frame: screenFrame)
    }

    func centerActiveWindow() {
        guard let window = getFrontmostWindow() else { return }
        guard let screen = screenForWindow(window) else { return }

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

    // MARK: - Thirds

    func moveActiveWindowToLeftThird() {
        guard let window = getFrontmostWindow() else { return }
        guard let screen = screenForWindow(window) else { return }

        let screenFrame = screen.visibleFrame
        let thirdWidth = screenFrame.width / 3
        let newFrame = CGRect(
            x: screenFrame.minX,
            y: screenFrame.minY,
            width: thirdWidth,
            height: screenFrame.height
        )

        setWindowFrame(window, frame: newFrame)
    }

    func moveActiveWindowToCenterThird() {
        guard let window = getFrontmostWindow() else { return }
        guard let screen = screenForWindow(window) else { return }

        let screenFrame = screen.visibleFrame
        let thirdWidth = screenFrame.width / 3
        let newFrame = CGRect(
            x: screenFrame.minX + thirdWidth,
            y: screenFrame.minY,
            width: thirdWidth,
            height: screenFrame.height
        )

        setWindowFrame(window, frame: newFrame)
    }

    func moveActiveWindowToRightThird() {
        guard let window = getFrontmostWindow() else { return }
        guard let screen = screenForWindow(window) else { return }

        let screenFrame = screen.visibleFrame
        let thirdWidth = screenFrame.width / 3
        let newFrame = CGRect(
            x: screenFrame.minX + thirdWidth * 2,
            y: screenFrame.minY,
            width: thirdWidth,
            height: screenFrame.height
        )

        setWindowFrame(window, frame: newFrame)
    }

    func moveActiveWindowToLeftTwoThirds() {
        guard let window = getFrontmostWindow() else { return }
        guard let screen = screenForWindow(window) else { return }

        let screenFrame = screen.visibleFrame
        let twoThirdsWidth = screenFrame.width * 2 / 3
        let newFrame = CGRect(
            x: screenFrame.minX,
            y: screenFrame.minY,
            width: twoThirdsWidth,
            height: screenFrame.height
        )

        setWindowFrame(window, frame: newFrame)
    }

    func moveActiveWindowToRightTwoThirds() {
        guard let window = getFrontmostWindow() else { return }
        guard let screen = screenForWindow(window) else { return }

        let screenFrame = screen.visibleFrame
        let thirdWidth = screenFrame.width / 3
        let twoThirdsWidth = screenFrame.width * 2 / 3
        let newFrame = CGRect(
            x: screenFrame.minX + thirdWidth,
            y: screenFrame.minY,
            width: twoThirdsWidth,
            height: screenFrame.height
        )

        setWindowFrame(window, frame: newFrame)
    }

    // MARK: - Multi-Display

    func moveActiveWindowToPreviousDisplay() {
        moveActiveWindowToAdjacentDisplay(offset: -1)
    }

    func moveActiveWindowToNextDisplay() {
        moveActiveWindowToAdjacentDisplay(offset: 1)
    }

    private func moveActiveWindowToAdjacentDisplay(offset: Int) {
        guard let window = getFrontmostWindow() else { return }
        guard let currentFrame = getWindowFrame(window) else { return }

        let screens = NSScreen.screens
        guard screens.count > 1 else { return }

        let windowCenter = CGPoint(x: currentFrame.midX, y: currentFrame.midY)
        guard let currentIndex = screens.firstIndex(where: { $0.frame.contains(windowCenter) }) else { return }

        let targetIndex = (currentIndex + offset + screens.count) % screens.count
        let currentScreen = screens[currentIndex]
        let targetScreen = screens[targetIndex]

        // Preserve the window's position relative to its current screen's visible frame.
        let relativeX = currentFrame.minX - currentScreen.visibleFrame.minX
        let relativeY = currentFrame.minY - currentScreen.visibleFrame.minY
        let newFrame = CGRect(
            x: targetScreen.visibleFrame.minX + relativeX,
            y: targetScreen.visibleFrame.minY + relativeY,
            width: currentFrame.width,
            height: currentFrame.height
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
        if !AXIsProcessTrusted() {
            print("ReFlow[tiling]: Accessibility permission not granted — cannot read/move any window.")
            return nil
        }

        guard let app = NSWorkspace.shared.frontmostApplication else {
            print("ReFlow[tiling]: no frontmost application.")
            return nil
        }
        // Never tile our own windows (e.g. Settings) — otherwise a global tiling hotkey
        // pressed while Settings is focused (such as while recording that very shortcut)
        // would grab and move Settings itself instead of doing nothing.
        guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            print("ReFlow[tiling]: frontmost app is ReFlow itself — refusing to tile our own window.")
            return nil
        }

        let appRef = AXUIElementCreateApplication(app.processIdentifier)
        var window: CFTypeRef?

        let result = AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &window)

        if result == .success, let windowRef = window {
            return (windowRef as! AXUIElement)
        }

        print("ReFlow[tiling]: could not get focused window of \(app.localizedName ?? "?"), AXError=\(result.rawValue)")

        return nil
    }

    /// The screen that actually contains `window`, rather than `NSScreen.main` (which tracks
    /// whichever window is currently key/focused *in this process* — for a background/menu-bar
    /// app like ReFlow that's frequently nil and falls back to the primary display). Using
    /// `.main` here silently tiles against the wrong display's bounds on any multi-monitor
    /// setup where the target window isn't on the primary screen, which is what open-source
    /// tiling tools (e.g. Rectangle, Amethyst) resolve by locating the screen from the window's
    /// own frame — mirrored below and already done correctly for `moveActiveWindowToAdjacentDisplay`.
    private func screenForWindow(_ window: AXUIElement) -> NSScreen? {
        guard let frame = getWindowFrame(window) else {
            print("ReFlow[tiling]: could not read window frame to resolve its screen — falling back to NSScreen.main.")
            return NSScreen.main
        }

        let center = CGPoint(x: frame.midX, y: frame.midY)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }) {
            return screen
        }

        // The window's center can fall outside every screen's frame (e.g. it's mostly
        // off-screen). Fall back to whichever screen it overlaps most, then finally .main.
        return NSScreen.screens.max { lhs, rhs in
            lhs.frame.intersection(frame).width * lhs.frame.intersection(frame).height
                < rhs.frame.intersection(frame).width * rhs.frame.intersection(frame).height
        } ?? NSScreen.main
    }

    private func getWindowFrame(_ window: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?

        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else {
            return nil
        }

        return CGRect(origin: position, size: size)
    }

    private func setWindowFrame(_ window: AXUIElement, frame: CGRect) {
        // A window in native full-screen (or one that just doesn't expose a resizable AX
        // frame, e.g. some utility panels) can't be repositioned via AX at all — Rectangle
        // and Amethyst both special-case this rather than issuing a set that will silently
        // no-op. Surface it instead of failing quietly.
        var isSettable: DarwinBoolean = false
        let positionSettable = AXUIElementIsAttributeSettable(window, kAXPositionAttribute as CFString, &isSettable) == .success && isSettable.boolValue
        let sizeSettable = AXUIElementIsAttributeSettable(window, kAXSizeAttribute as CFString, &isSettable) == .success && isSettable.boolValue
        guard positionSettable, sizeSettable else {
            print("ReFlow[tiling]: window's position/size isn't settable (often means it's in native full screen or the app doesn't support AX resizing) — skipping.")
            return
        }

        var position = CGPoint(x: frame.origin.x, y: frame.origin.y)
        var size = CGSize(width: frame.size.width, height: frame.size.height)
        let positionValue = AXValueCreate(.cgPoint, &position)!
        let sizeValue = AXValueCreate(.cgSize, &size)!

        // Setting position then size unconditionally makes some moves visibly double-step
        // (jump to the new spot at the old size, then resize) instead of moving cleanly in
        // one motion. Shrinking first and growing last keeps the window from momentarily
        // overlapping past where it's headed.
        let currentFrame = getWindowFrame(window)
        let shrinking = currentFrame.map { $0.width > frame.width || $0.height > frame.height } ?? false

        var positionResult: AXError = .success
        var sizeResult: AXError = .success
        if shrinking {
            sizeResult = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
            positionResult = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
        } else {
            positionResult = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
            sizeResult = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        }

        if positionResult != .success || sizeResult != .success {
            print("ReFlow[tiling]: setWindowFrame failed (positionAXError=\(positionResult.rawValue), sizeAXError=\(sizeResult.rawValue)).")
        }
    }
}
