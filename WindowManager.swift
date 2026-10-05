import AppKit
import ApplicationServices

class WindowManager {
    static let shared = WindowManager()

    enum Corner {
        case topLeft, topRight, bottomLeft, bottomRight
    }

    /// Whatever a tiling command acts on. Almost always another app's window, reached via
    /// Accessibility — but a few of ReFlow's own ordinary windows (Camera) should tile like
    /// any other window too. Those are moved directly through AppKit instead: AX calls into
    /// our *own* process from the main thread would have to be serviced by that same,
    /// currently-blocked main thread, so they stall until they time out.
    enum TileTarget {
        case accessibility(AXUIElement)
        case own(NSWindow)
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

        setWindowFrame(window, frame: newFrame, within: screen.visibleFrame)
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

        setWindowFrame(window, frame: newFrame, within: screen.visibleFrame)
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

        setWindowFrame(window, frame: newFrame, within: screen.visibleFrame)
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

        setWindowFrame(window, frame: newFrame, within: screen.visibleFrame)
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

        setWindowFrame(window, frame: newFrame, within: screen.visibleFrame)
    }

    func maximizeActiveWindow() {
        guard let window = getFrontmostWindow() else { return }
        guard let screen = screenForWindow(window) else { return }

        let screenFrame = screen.visibleFrame
        setWindowFrame(window, frame: screenFrame, within: screenFrame)
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

        setWindowFrame(window, frame: newFrame, within: screen.visibleFrame)
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

        setWindowFrame(window, frame: newFrame, within: screen.visibleFrame)
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

        setWindowFrame(window, frame: newFrame, within: screen.visibleFrame)
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

        setWindowFrame(window, frame: newFrame, within: screen.visibleFrame)
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

        setWindowFrame(window, frame: newFrame, within: screen.visibleFrame)
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

        setWindowFrame(window, frame: newFrame, within: screen.visibleFrame)
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
        // Everything below (screen containment checks, relative-offset math) is done in
        // NSScreen's coordinate space — see the note on `screenSpaceFrame(fromAX:)`.
        guard let currentFrame = currentScreenSpaceFrame(of: window) else { return }

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

        setWindowFrame(window, frame: newFrame, within: targetScreen.visibleFrame)
    }

    // MARK: - Helper Methods

    private func getFrontmostWindow() -> TileTarget? {
        if !AXIsProcessTrusted() {
            print("ReFlow[tiling]: Accessibility permission not granted — cannot read/move any window.")
            return nil
        }

        // Asking the Accessibility subsystem itself which application is focused, rather
        // than asking NSWorkspace for the frontmost app and handing its pid to AX
        // separately, avoids a real mismatch we hit with Safari: NSWorkspace reported it
        // as frontmost, but `NSRunningApplication.processIdentifier` came back -1 for it,
        // making every AX query against `AXUIElementCreateApplication(-1)` fail with
        // `kAXErrorInvalidUIElement` no matter what attribute was asked for — nothing to
        // do with Safari's windows/tabs specifically, just a bad pid from the start. Going
        // through `AXUIElementCreateSystemWide` + `kAXFocusedApplicationAttribute` keeps
        // everything on one consistent API instead of crossing between AppKit's and AX's
        // own bookkeeping of "what's focused."
        let systemWide = AXUIElementCreateSystemWide()
        var focusedAppValue: CFTypeRef?
        let focusedAppResult = AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &focusedAppValue)

        let appRef: AXUIElement
        if focusedAppResult == .success, let focusedAppValue {
            appRef = focusedAppValue as! AXUIElement
        } else {
            // The system-wide query itself can apparently fail for some apps (seen with
            // Claude's desktop app) the same way the NSWorkspace-based approach failed
            // for Safari — so fall back to that original path instead of giving up,
            // rather than assuming one of the two will always work for every app.
            print("ReFlow[tiling]: could not determine the focused application via AXUIElementCreateSystemWide, AXError=\(focusedAppResult.rawValue) — falling back to NSWorkspace.")
            guard let app = NSWorkspace.shared.frontmostApplication else {
                print("ReFlow[tiling]: NSWorkspace also has no frontmost application.")
                return nil
            }
            appRef = AXUIElementCreateApplication(app.processIdentifier)
        }

        var pid: pid_t = 0
        let havePid = AXUIElementGetPid(appRef, &pid) == .success
        let appName = (havePid ? NSRunningApplication(processIdentifier: pid)?.localizedName : nil) ?? "?"

        // Never tile most of our own windows (e.g. Settings) — otherwise a global tiling
        // hotkey pressed while Settings is focused (such as while recording that very
        // shortcut) would grab and move Settings itself instead of doing nothing. The
        // Camera window is the exception: it's an ordinary content window people expect
        // to snap around like any other.
        if havePid && pid == ProcessInfo.processInfo.processIdentifier {
            if let keyWindow = NSApp.keyWindow, CameraWindowController.shared.owns(keyWindow) {
                return .own(keyWindow)
            }
            print("ReFlow[tiling]: frontmost app is ReFlow itself — refusing to tile our own window.")
            return nil
        }

        var window: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &window)

        if result == .success, let windowRef = window {
            return .accessibility(windowRef as! AXUIElement)
        }

        print("ReFlow[tiling]: could not get focused window of \(appName) via AXFocusedWindow, AXError=\(result.rawValue) — falling back to AXWindows.")

        // Some apps' tabbed/full-screen-capable windows can answer kAXFocusedWindowAttribute
        // with kAXErrorInvalidUIElement even though they have a perfectly normal window on
        // screen. Falling back to the full AXWindows list and picking whichever one is
        // flagged main is the standard, more robust way other AX-driven tools work around
        // exactly this.
        var windowsValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsValue) == .success,
              let windows = windowsValue as? [AXUIElement], !windows.isEmpty else {
            print("ReFlow[tiling]: could not get any window of \(appName) via AXWindows either.")
            return nil
        }

        if let mainWindow = windows.first(where: { candidate in
            var isMainValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(candidate, kAXMainAttribute as CFString, &isMainValue) == .success else { return false }
            return (isMainValue as? Bool) == true
        }) {
            return .accessibility(mainWindow)
        }

        return .accessibility(windows[0])
    }

    /// The screen that actually contains `window`, rather than `NSScreen.main` (which tracks
    /// whichever window is currently key/focused *in this process* — for a background/menu-bar
    /// app like ReFlow that's frequently nil and falls back to the primary display). Using
    /// `.main` here silently tiles against the wrong display's bounds on any multi-monitor
    /// setup where the target window isn't on the primary screen, which is what open-source
    /// tiling tools (e.g. Rectangle, Amethyst) resolve by locating the screen from the window's
    /// own frame — mirrored below and already done correctly for `moveActiveWindowToAdjacentDisplay`.
    private func screenForWindow(_ window: TileTarget) -> NSScreen? {
        guard let frame = currentScreenSpaceFrame(of: window) else {
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

    /// The target's current frame in NSScreen's coordinate space, however it's reached.
    private func currentScreenSpaceFrame(of target: TileTarget) -> CGRect? {
        switch target {
        case .accessibility(let window):
            return getWindowFrame(window).map(screenSpaceFrame(fromAX:))
        case .own(let window):
            return window.frame
        }
    }

    /// Returns the window's frame in the Accessibility API's own coordinate space: origin at
    /// the top-left of the primary screen, Y increasing *downward*. Don't compare this directly
    /// against `NSScreen.frame`/`.visibleFrame` — those use AppKit's space (origin at the
    /// bottom-left, Y increasing *upward*). Convert with `screenSpaceFrame(fromAX:)` first.
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

    /// Converts between the AX API's coordinate space (origin top-left, Y down) and AppKit's
    /// `NSScreen` coordinate space (origin bottom-left of the primary screen, Y up) — the two
    /// disagree only on Y, and the flip about the primary screen's height is its own inverse,
    /// so this same formula converts in either direction. Skipping it (i.e. feeding an
    /// `NSScreen.visibleFrame`-derived rect straight into `kAXPositionAttribute`, or an AX
    /// frame straight into an `NSScreen.frame.contains(_:)` check) is what made "snap to top
    /// left" land at the bottom of the screen with the gap on the wrong edge.
    private func verticallyFlipped(_ frame: CGRect) -> CGRect {
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return frame }
        return CGRect(
            x: frame.minX,
            y: primaryHeight - frame.maxY,
            width: frame.width,
            height: frame.height
        )
    }

    private func screenSpaceFrame(fromAX axFrame: CGRect) -> CGRect { verticallyFlipped(axFrame) }
    private func axFrame(fromScreenSpace frame: CGRect) -> CGRect { verticallyFlipped(frame) }

    /// Sets the owning app's "AXEnhancedUserInterface" attribute and returns whatever it was
    /// set to *before* this call, so the caller can restore it afterward. Returns `nil` if the
    /// app doesn't expose the attribute at all — the common case, meaning nothing to toggle.
    @discardableResult
    private func setEnhancedUserInterface(for window: AXUIElement, enabled: Bool) -> Bool? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success else { return nil }
        let appElement = AXUIElementCreateApplication(pid)

        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, "AXEnhancedUserInterface" as CFString, &value) == .success,
              let previous = value as? Bool else {
            return nil
        }

        AXUIElementSetAttributeValue(appElement, "AXEnhancedUserInterface" as CFString, (enabled ? kCFBooleanTrue : kCFBooleanFalse) as CFTypeRef)
        return previous
    }


    /// The work item for whichever `setWindowFrame` call is still waiting out the debounce
    /// below. Rapid-fire hotkey presses (cycling through several tiling positions quickly)
    /// used to make the window visibly bounce: each press issued its own AX position/size
    /// set immediately, and if the previous one hadn't been fully processed by the target
    /// app yet, the two sets could interleave into a frame neither press asked for.
    private var pendingWindowFrameWork: DispatchWorkItem?
    private static let tileDebounceInterval: TimeInterval = 0.05

    /// `bounds` is the screen-space area the window must stay inside (the target screen's
    /// `visibleFrame`, i.e. clear of the menu bar and Dock) if it turns out it can't take
    /// `frame`'s exact size — see `fittedFrame(size:target:bounds:)`.
    private func setWindowFrame(_ window: TileTarget, frame screenSpaceFrame: CGRect, within bounds: CGRect) {
        // Coalesce to only the most recently requested frame: cancel anything still
        // pending so a fast burst of presses resolves to a single, clean apply of the
        // last one, instead of every intermediate press racing to actually take effect.
        pendingWindowFrameWork?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            switch window {
            case .accessibility(let axWindow):
                self?.applyWindowFrame(axWindow, frame: screenSpaceFrame, within: bounds)
            case .own(let nsWindow):
                self?.applyOwnWindowFrame(nsWindow, frame: screenSpaceFrame, within: bounds)
            }
        }
        pendingWindowFrameWork = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.tileDebounceInterval, execute: workItem)
    }

    private func applyOwnWindowFrame(_ window: NSWindow, frame screenSpaceFrame: CGRect, within bounds: CGRect) {
        // `setFrame` doesn't enforce the window's own minimum size the way a user drag
        // does, so apply it here — then place that size exactly like an AX window that
        // refused to shrink.
        let minFrame = window.frameRect(forContentRect: NSRect(origin: .zero, size: window.contentMinSize))
        let size = CGSize(
            width: max(screenSpaceFrame.width, window.minSize.width, minFrame.width),
            height: max(screenSpaceFrame.height, window.minSize.height, minFrame.height)
        )
        window.setFrame(fittedFrame(size: size, target: screenSpaceFrame, bounds: bounds), display: true)
    }

    /// Where a window of `size` should go when it was asked to fill `target` but couldn't
    /// take that exact size (a minimum size, like Music's, or a fixed-size window): keep it
    /// as close to the requested tile as possible, but never let it hang off the screen or
    /// under the Dock — staying fully visible wins over matching the tile exactly.
    ///
    /// Per axis, the window keeps whichever edge of the tile sits on a screen edge (a left
    /// third stays flush left, a bottom-right corner stays flush right and bottom), or is
    /// centered on the tile when the tile touches neither (the center third). The result
    /// is then clamped into `bounds`; if the window is bigger than `bounds` outright, it's
    /// pinned to the left and *top* so its title bar stays reachable.
    private func fittedFrame(size: CGSize, target: CGRect, bounds: CGRect) -> CGRect {
        func place(length: CGFloat, targetMin: CGFloat, targetMax: CGFloat, boundsMin: CGFloat, boundsMax: CGFloat, oversizedAtMax: Bool) -> CGFloat {
            let tolerance: CGFloat = 2
            let touchesMin = abs(targetMin - boundsMin) <= tolerance
            let touchesMax = abs(targetMax - boundsMax) <= tolerance
            if length >= boundsMax - boundsMin {
                return oversizedAtMax ? boundsMax - length : boundsMin
            }
            let origin: CGFloat
            if touchesMax && !touchesMin {
                origin = targetMax - length
            } else if touchesMin {
                origin = targetMin
            } else {
                origin = targetMin + (targetMax - targetMin - length) / 2
            }
            return min(max(origin, boundsMin), boundsMax - length)
        }

        // Screen space has Y increasing upward, so "top" is the max edge.
        let x = place(length: size.width, targetMin: target.minX, targetMax: target.maxX, boundsMin: bounds.minX, boundsMax: bounds.maxX, oversizedAtMax: false)
        let y = place(length: size.height, targetMin: target.minY, targetMax: target.maxY, boundsMin: bounds.minY, boundsMax: bounds.maxY, oversizedAtMax: true)
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    private func applyWindowFrame(_ window: AXUIElement, frame screenSpaceFrame: CGRect, within bounds: CGRect) {
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

        // `screenSpaceFrame` (the caller's target, computed from NSScreen) has to be converted
        // to the AX API's own coordinate space before it's written — see `verticallyFlipped`.
        let targetFrame = axFrame(fromScreenSpace: screenSpaceFrame)

        // Safari (and a handful of other apps — Rectangle and Silica/Slate carry the same
        // workaround) can have "AXEnhancedUserInterface" on, an undocumented but fully
        // public app-level AX attribute. While it's on, that app's own accessibility bridge
        // intercepts position/size sets and quietly drops them — `AXUIElementSetAttributeValue`
        // still reports `.success`, the window just never actually moves. Toggling it off for
        // the duration of the set, then restoring it, is what real tiling apps do about it.
        let wasEnhancedUIEnabled = setEnhancedUserInterface(for: window, enabled: false)

        // Safari's AX bridge doesn't reliably apply a position and a size sent as two
        // separate calls in the order we actually sent them — it can reconcile them using
        // a *stale* value for whichever one it processes second, no matter which order
        // that was ("writing position after size makes it discard the size it was just
        // given" is the documented half of this; the reverse direction is what caused the
        // maximize→corner bug: writing a new *position* using a still-stale, still-maximized
        // *size* pins the window's bottom edge to the true bottom of the screen — behind
        // the Dock — instead of `visibleFrame.minY`). A single combined write can't be made
        // reliably safe against that in either order.
        //
        // Splitting the write into two phases sidesteps it structurally instead of by
        // guessing an order: phase 1 settles X and size while leaving Y pinned at
        // whichever edge is safe to keep fixed, so there's no stale-Y/new-size
        // combination for anything to get wrong; phase 2 then moves only Y, once size is
        // already independently confirmed correct, so there's no stale-size/new-Y
        // combination left to get wrong either.
        //
        // "Safe to keep fixed" depends on which way the height is changing. Shrinking
        // can always pin the *top* and let the bottom edge move up — a shorter window
        // can only move away from the Dock, never into it. Growing has to pin the
        // *bottom* instead and grow upward: pinning the top while growing downward (as if
        // it were always shrinking) walks the bottom edge past `visibleFrame.minY` into
        // the Dock before phase 2 ever gets a chance to correct it, gets clamped by the
        // app, and phase 2 then only moves that already-wrong-height frame — which is
        // exactly how a bottom-corner→maximize move ended up occupying only the top half
        // of the screen.
        let current = getWindowFrame(window)
        let isGrowing = (current?.height ?? 0) < targetFrame.height
        let sizeSettledFrame: CGRect
        if let current, isGrowing {
            let currentBottomAX = current.origin.y + current.height
            sizeSettledFrame = CGRect(x: targetFrame.origin.x, y: currentBottomAX - targetFrame.height, width: targetFrame.width, height: targetFrame.height)
        } else {
            let currentY = current?.origin.y ?? targetFrame.origin.y
            sizeSettledFrame = CGRect(x: targetFrame.origin.x, y: currentY, width: targetFrame.width, height: targetFrame.height)
        }

        let (phase1Position, phase1Size) = writeAndVerify(target: sizeSettledFrame, to: window, setPosition: true, setSize: true)
        var (phase2Position, _) = writeAndVerify(target: targetFrame, to: window, setPosition: true, setSize: false)

        // Some windows simply can't take the requested size — Music and other apps with a
        // minimum size, or fixed-size utility windows — and positioning those at the tile's
        // exact origin anyway is what pushed them off the side of the screen or down
        // behind the Dock. Whatever frame the window actually ended up with, re-place it
        // so it's fully inside the visible area while sitting as close to the requested
        // tile as it can. For a window that did take the exact size this is a no-op: its
        // fitted frame *is* the target.
        if let landed = getWindowFrame(window) {
            let fitted = axFrame(fromScreenSpace: fittedFrame(size: landed.size, target: screenSpaceFrame, bounds: bounds))
            if !framesMatch(landed, fitted) {
                print("ReFlow[tiling]: window landed at \(landed) instead of \(targetFrame) — re-placing it at \(fitted.origin) to keep it fully visible.")
                phase2Position = writeAndVerify(target: fitted, to: window, setPosition: true, setSize: false).positionResult
            }
        }

        if let wasEnhancedUIEnabled, wasEnhancedUIEnabled {
            _ = setEnhancedUserInterface(for: window, enabled: true)
        }

        if phase1Position != .success || phase1Size != .success || phase2Position != .success {
            print("ReFlow[tiling]: setWindowFrame failed (phase1PositionAXError=\(phase1Position.rawValue), phase1SizeAXError=\(phase1Size.rawValue), phase2PositionAXError=\(phase2Position.rawValue)).")
        }
    }

    /// Writes `target` to `window`, touching only the AX attributes the caller asks for —
    /// see the two-phase strategy in `applyWindowFrame` for why that matters — then reads
    /// the frame back to confirm it actually landed, retrying up to twice more if it
    /// didn't. A single AX write reporting `.success` doesn't guarantee the frame actually
    /// ended up where asked (some apps still treat a window as "zoomed" for a moment after
    /// our own AX-driven maximize and quietly clamp what they're given), and Safari
    /// specifically can need the retry just for its window-server IPC to catch up: it
    /// doesn't always finish reconciling a write before `AXUIElementSetAttributeValue`
    /// returns, so the very next read-back can catch it mid-settle and report a false
    /// mismatch — the short sleep before each verification gives it a moment to finish.
    @discardableResult
    private func writeAndVerify(target: CGRect, to window: AXUIElement, setPosition: Bool, setSize: Bool) -> (positionResult: AXError, sizeResult: AXError) {
        var positionResult: AXError = .success
        var sizeResult: AXError = .success

        var position = CGPoint(x: target.origin.x, y: target.origin.y)
        var size = CGSize(width: target.width, height: target.height)
        let positionValue = AXValueCreate(.cgPoint, &position)!
        let sizeValue = AXValueCreate(.cgSize, &size)!

        for attempt in 1...3 {
            // When both are being set together (phase 1), order still matters for the
            // same Safari-interdependency reason described above — position-then-size is
            // the direction documented to actually stick.
            if setPosition {
                positionResult = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
            }
            if setSize {
                sizeResult = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
            }

            Thread.sleep(forTimeInterval: 0.02)

            let landedFrame = getWindowFrame(window)
            let landed = landedFrame.map { framesMatch($0, target) } ?? false
            if landed {
                break
            } else if attempt < 3 {
                print("ReFlow[tiling]: frame didn't land as requested on attempt \(attempt) (wanted \(target), got \(String(describing: landedFrame))) — retrying.")
            }
        }

        return (positionResult, sizeResult)
    }

    /// Tolerance-based comparison for verifying an AX write actually landed. A tolerance
    /// (rather than exact equality) is needed because some apps round or snap frames to
    /// their own internal grid, which would otherwise make a perfectly-successful write
    /// look like a mismatch and trigger a needless retry.
    private func framesMatch(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat = 2.0) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) <= tolerance &&
            abs(lhs.origin.y - rhs.origin.y) <= tolerance &&
            abs(lhs.width - rhs.width) <= tolerance &&
            abs(lhs.height - rhs.height) <= tolerance
    }
}
