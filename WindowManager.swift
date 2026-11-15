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

    private init() {
        // AX calls block until the target app answers, and the default timeout is 6
        // seconds — a hung or busy app could freeze ReFlow (launcher included) for that
        // long. Set on the system-wide element, this applies to every AX call we make.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 1.0)
    }

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

        // `NSScreen.screens` is ordered primary-first, then however the system happens
        // to list the rest — not by where the displays physically sit. Sort them into
        // their arrangement (left to right, then bottom to top) so "previous" and "next"
        // actually mean the display to the left and right.
        let screens = NSScreen.screens.sorted {
            $0.frame.minX != $1.frame.minX ? $0.frame.minX < $1.frame.minX : $0.frame.minY < $1.frame.minY
        }
        guard screens.count > 1 else {
            print("ReFlow[tiling]: only one display connected — nothing to move the window to.")
            return
        }

        // Same screen resolution as every other tiling command. Requiring the window's
        // exact center to be on a screen (as this used to) silently did nothing for a
        // window hanging partly off its display.
        guard let currentScreen = screenForWindow(window),
              let currentIndex = screens.firstIndex(of: currentScreen) else { return }

        let targetIndex = (currentIndex + offset + screens.count) % screens.count
        let targetScreen = screens[targetIndex]

        // Preserve the window's position relative to its current screen's visible frame,
        // but shrink and shift it to fit if the target display is smaller — otherwise a
        // window that lands exactly where asked would hang off the edge of it.
        let bounds = targetScreen.visibleFrame
        let width = min(currentFrame.width, bounds.width)
        let height = min(currentFrame.height, bounds.height)
        let relativeX = currentFrame.minX - currentScreen.visibleFrame.minX
        let relativeY = currentFrame.minY - currentScreen.visibleFrame.minY
        let newFrame = CGRect(
            x: min(max(bounds.minX + relativeX, bounds.minX), bounds.maxX - width),
            y: min(max(bounds.minY + relativeY, bounds.minY), bounds.maxY - height),
            width: width,
            height: height
        )

        setWindowFrame(window, frame: newFrame, within: targetScreen.visibleFrame)
    }

    // MARK: - Desktops

    func moveActiveWindowToPreviousDesktop() {
        moveActiveWindowToAdjacentDesktop(towardLeft: true)
    }

    func moveActiveWindowToNextDesktop() {
        moveActiveWindowToAdjacentDesktop(towardLeft: false)
    }

    /// True from the simulated mouse-down until the matching mouse-up has been posted, so a
    /// second press can't start another sequence on top of a window that's still held.
    private var isMovingBetweenDesktops = false
    /// The direction of a press that arrived mid-move, run as soon as that move finishes —
    /// so pressing the shortcut twice in a row moves the window two desktops over instead
    /// of dropping the second press. Only the latest one is kept.
    private var queuedDesktopMoveIsTowardLeft: Bool?
    /// The system's space-switching shortcut, if it was off and had to be switched on for
    /// the move in progress. Switched back off when the move ends.
    private var shortcutToDisableAgain: Int32?

    /// Nothing can move another app's window to a different Space directly any more. The
    /// private SkyLight calls that used to (`CGSMoveWindowsToManagedSpace`, the
    /// add/remove pair, the compat-ID workaround yabai found for 14.5) are all silently
    /// ignored for windows of other processes on current macOS, and yabai's remaining
    /// route is injecting code into the Dock with System Integrity Protection off. What's
    /// left is what Amethyst and the Hammerspoon scripts ended up with too: do what you'd
    /// do by hand. Hold the window by its title bar and press the "Move left/right a
    /// space" shortcut, which carries the held window along when macOS switches desktops.
    ///
    /// SkyLight's read-only calls do still work (see `Spaces`), and they take the guesswork
    /// out of it: whether there's a desktop on that side at all, which keys the shortcut
    /// is really set to, and the moment the window has landed.
    private func moveActiveWindowToAdjacentDesktop(towardLeft: Bool) {
        guard !isMovingBetweenDesktops else {
            queuedDesktopMoveIsTowardLeft = towardLeft
            return
        }
        guard let window = getFrontmostWindow() else { return }

        // A full-screen window is its own Space and can't be dragged, so the ⌃-arrow would
        // switch desktops and leave the window behind.
        if case .accessibility(let axWindow) = window, isFullScreen(axWindow) {
            print("ReFlow[desktops]: window is in native full screen — can't move it to another desktop.")
            return
        }

        // Checked before touching the mouse, so that at the last desktop nothing happens
        // at all, rather than the cursor darting to the window and back for no reason.
        let windowID = Spaces.windowID(of: window)
        let originalSpaces = windowID.flatMap { Spaces.spaces(ofWindow: $0) } ?? []
        if Spaces.hasSpace(beside: originalSpaces, offset: towardLeft ? -1 : 1) == false {
            print("ReFlow[desktops]: no desktop on that side to move the window to.")
            NSSound.beep()
            return
        }

        guard let originalFrame = currentAXFrame(of: window) else { return }
        let grabPoints = titleBarGrabPoints(of: window, frame: originalFrame)
        guard !grabPoints.isEmpty else {
            print("ReFlow[desktops]: window's title bar isn't on any screen — can't grab it.")
            return
        }

        isMovingBetweenDesktops = true
        // The simulated drag moves the window on purpose; a settle check still pending
        // from an earlier tile shouldn't fight it.
        tileGeneration += 1
        let move = DesktopMove(
            window: window,
            windowID: windowID,
            originalSpaces: originalSpaces,
            originalFrame: originalFrame,
            // ⌃← / ⌃→ unless the shortcut can be read and says otherwise. Real arrow-key
            // events carry the function and numeric-pad flags too, and the system's
            // shortcut is registered with the function flag included.
            shortcut: Spaces.moveShortcut(towardLeft: towardLeft) ?? Spaces.Shortcut(
                id: nil,
                keyCode: towardLeft ? 123 : 124,
                flags: [.maskControl, .maskSecondaryFn, .maskNumericPad],
                isEnabled: true
            ),
            source: CGEventSource(stateID: .privateState),
            originalCursorLocation: CGEvent(source: nil)?.location
        )
        whenModifiersReleased(deadline: Date().addingTimeInterval(0.3)) { [weak self] in
            self?.grabWindow(for: move, at: grabPoints[...])
        }
    }

    /// The hotkey's own modifiers are usually still physically down when it fires, and a
    /// click with ⌃ held is a right-click. Waiting for them to come up (checking every 10ms)
    /// avoids that; the deadline keeps someone holding them from stalling the move, with
    /// the explicit flags on every posted event covering that case.
    private func whenModifiersReleased(deadline: Date, _ body: @escaping () -> Void) {
        let held = CGEventSource.flagsState(.hidSystemState)
            .intersection([.maskControl, .maskAlternate, .maskShift, .maskCommand])
        guard !held.isEmpty, Date() < deadline else {
            body()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [weak self] in
            self?.whenModifiersReleased(deadline: deadline, body)
        }
    }

    /// Everything one move between desktops needs to carry from step to step.
    private struct DesktopMove {
        let window: TileTarget
        /// The window server's own ID for the window and the Space(s) it started on, for
        /// telling when it has arrived. `nil`/empty if they couldn't be looked up.
        let windowID: CGWindowID?
        let originalSpaces: Set<UInt64>
        /// Where the window was before it was grabbed, in AX coordinates. Used both to tell
        /// whether a grab took hold and to put the window back exactly afterward.
        let originalFrame: CGRect
        /// The keys that switch desktops in the wanted direction.
        let shortcut: Spaces.Shortcut
        let source: CGEventSource?
        let originalCursorLocation: CGPoint?
    }

    private func postMouse(_ type: CGEventType, at point: CGPoint, for move: DesktopMove) {
        guard let event = CGEvent(mouseEventSource: move.source, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else { return }
        event.flags = []
        // Always a single click, so repeating the shortcut quickly can't register as a
        // double-click on the title bar, which would zoom or minimize the window.
        if type != .mouseMoved {
            event.setIntegerValueField(.mouseEventClickState, value: 1)
        }
        event.post(tap: .cghidEventTap)
    }

    private func postShortcutKey(keyDown: Bool, for move: DesktopMove) {
        guard let event = CGEvent(keyboardEventSource: move.source, virtualKey: move.shortcut.keyCode, keyDown: keyDown) else { return }
        event.flags = move.shortcut.flags
        event.post(tap: .cghidEventTap)
    }

    /// Presses at the first of `grabPoints` and drags a few pixels, then checks whether the
    /// window actually followed. Where a title bar can be dragged from varies by app, and
    /// can't always be worked out up front: Claude's desktop app and others that draw
    /// their own title bar put buttons right beside the window controls, and pressing
    /// there holds a button rather than the window. So rather than trust one spot, try
    /// each in turn until the window moves.
    private func grabWindow(for move: DesktopMove, at grabPoints: ArraySlice<CGPoint>) {
        guard let grabPoint = grabPoints.first else {
            print("ReFlow[desktops]: couldn't find anywhere on the title bar that drags the window — leaving it where it is.")
            finishDesktopMove(move)
            return
        }

        // A plain mouse-down isn't always treated as holding the window — it takes actual
        // movement. The offset is undone before letting go.
        let draggedPoint = CGPoint(x: grabPoint.x + 6, y: grabPoint.y)
        let steps: [(delay: TimeInterval, action: () -> Void)] = [
            (0, { [self] in postMouse(.mouseMoved, at: grabPoint, for: move) }),
            (0.03, { [self] in postMouse(.leftMouseDown, at: grabPoint, for: move) }),
            (0.06, { [self] in postMouse(.leftMouseDragged, at: CGPoint(x: grabPoint.x + 3, y: grabPoint.y), for: move) }),
            (0.02, { [self] in postMouse(.leftMouseDragged, at: draggedPoint, for: move) }),
            (0.05, { [self] in
                confirmWindowHeld(for: move, checksLeft: 3) { [self] isHeld in
                    if isHeld {
                        carryWindow(for: move, heldAt: grabPoint)
                    } else {
                        releaseWithoutClicking(for: move, pressedAt: grabPoint) { [self] in
                            grabWindow(for: move, at: grabPoints.dropFirst())
                        }
                    }
                }
            }),
        ]
        runSteps(steps[...])
    }

    /// The window has been dragged a few pixels if it's held, so it's held exactly when
    /// its position has changed. Checked a few times, since an app can take a moment to
    /// report where its window has been dragged to.
    private func confirmWindowHeld(for move: DesktopMove, checksLeft: Int, _ completion: @escaping (Bool) -> Void) {
        if let origin = currentAXFrame(of: move.window)?.origin,
           abs(origin.x - move.originalFrame.minX) >= 1 || abs(origin.y - move.originalFrame.minY) >= 1 {
            completion(true)
            return
        }
        guard checksLeft > 1 else {
            completion(false)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.confirmWindowHeld(for: move, checksLeft: checksLeft - 1, completion)
        }
    }

    /// Lets go of whatever the press landed on instead of the window. Releasing in place
    /// would complete a click on it (toggling a sidebar, say), so the pointer is first
    /// dragged up off the top of the window, where a release doesn't count as one.
    private func releaseWithoutClicking(for move: DesktopMove, pressedAt grabPoint: CGPoint, then next: @escaping () -> Void) {
        let outsidePoint = CGPoint(x: grabPoint.x, y: move.originalFrame.minY - 4)
        let steps: [(delay: TimeInterval, action: () -> Void)] = [
            (0, { [self] in postMouse(.leftMouseDragged, at: outsidePoint, for: move) }),
            (0.03, { [self] in postMouse(.leftMouseUp, at: outsidePoint, for: move) }),
            (0.05, next),
        ]
        runSteps(steps[...])
    }

    private func carryWindow(for move: DesktopMove, heldAt grabPoint: CGPoint) {
        // With "Move left/right a space" switched off in System Settings the key press
        // would do nothing, so it's switched on just for as long as this takes.
        if let id = move.shortcut.id, !move.shortcut.isEnabled, Spaces.setShortcutEnabled(id, true) {
            shortcutToDisableAgain = id
        }
        let steps: [(delay: TimeInterval, action: () -> Void)] = [
            (0, { [self] in postShortcutKey(keyDown: true, for: move) }),
            (0.03, { [self] in postShortcutKey(keyDown: false, for: move) }),
            (0, { [self] in
                whenWindowHasLanded(for: move, deadline: Date().addingTimeInterval(Self.longestDesktopSwitch)) { [self] in
                    releaseWindow(for: move, heldAt: grabPoint)
                }
            }),
        ]
        runSteps(steps[...])
    }

    /// How long to keep hold of a window that never reports arriving, and the fixed wait
    /// used when its Space can't be watched at all. The switch itself takes about 0.3s.
    private static let longestDesktopSwitch: TimeInterval = 1.0
    private static let unobservedDesktopSwitch: TimeInterval = 0.45

    /// Runs `body` once the held window is on a different Space. While it's being carried
    /// it's reported as being on no Space at all, then on the new one the moment the
    /// switch completes — so this lets go right then, rather than after a fixed wait that
    /// has to be long enough for the slowest switch.
    private func whenWindowHasLanded(for move: DesktopMove, deadline: Date, _ body: @escaping () -> Void) {
        guard let windowID = move.windowID, !move.originalSpaces.isEmpty else {
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.unobservedDesktopSwitch, execute: body)
            return
        }
        if let spaces = Spaces.spaces(ofWindow: windowID), !spaces.isEmpty, spaces.isDisjoint(with: move.originalSpaces) {
            body()
            return
        }
        guard Date() < deadline else {
            print("ReFlow[desktops]: the window never arrived on another desktop — letting go of it where it is.")
            body()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
            self?.whenWindowHasLanded(for: move, deadline: deadline, body)
        }
    }

    private func releaseWindow(for move: DesktopMove, heldAt grabPoint: CGPoint) {
        let steps: [(delay: TimeInterval, action: () -> Void)] = [
            (0.03, { [self] in postMouse(.leftMouseDragged, at: grabPoint, for: move) }),
            (0.03, { [self] in postMouse(.leftMouseUp, at: grabPoint, for: move) }),
            (0.05, { [self] in
                restoreOriginalPosition(for: move)
                finishDesktopMove(move)
            }),
            // Dragging back to the grab point doesn't reliably undo the drag to the pixel,
            // and the window can still be settling onto its new desktop when it's let go,
            // so put it back where it started once more after things have calmed down.
            (0.25, { [self] in
                guard !isMovingBetweenDesktops, NSEvent.pressedMouseButtons == 0 else { return }
                restoreOriginalPosition(for: move)
            }),
        ]
        runSteps(steps[...])
    }

    private func restoreOriginalPosition(for move: DesktopMove) {
        guard let current = currentAXFrame(of: move.window),
              current.origin != move.originalFrame.origin else { return }
        switch move.window {
        case .accessibility(let window):
            setPosition(move.originalFrame.origin, of: window)
        case .own(let window):
            window.setFrameOrigin(screenSpaceFrame(fromAX: move.originalFrame).origin)
        }
    }

    private func finishDesktopMove(_ move: DesktopMove) {
        if let originalCursorLocation = move.originalCursorLocation {
            postMouse(.mouseMoved, at: originalCursorLocation, for: move)
        }
        if let id = shortcutToDisableAgain {
            Spaces.setShortcutEnabled(id, false)
            shortcutToDisableAgain = nil
        }
        isMovingBetweenDesktops = false

        if let towardLeft = queuedDesktopMoveIsTowardLeft {
            queuedDesktopMoveIsTowardLeft = nil
            moveActiveWindowToAdjacentDesktop(towardLeft: towardLeft)
        }
    }

    /// Runs each step after its delay without blocking the main thread: ReFlow has to stay
    /// responsive throughout, and a step skipped here could leave the mouse button held down.
    private func runSteps(_ steps: ArraySlice<(delay: TimeInterval, action: () -> Void)>) {
        guard let step = steps.first else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + step.delay) { [self] in
            step.action()
            runSteps(steps.dropFirst())
        }
    }

    private func isFullScreen(_ window: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &value) == .success else { return false }
        return (value as? Bool) == true
    }

    /// Points in the window's title bar worth trying to drag it by, most promising first,
    /// in the AX/CoreGraphics coordinate space mouse events use. Just right of the zoom
    /// button is the most reliable empty spot in apps with a standard title bar: the middle
    /// is often a tab or toolbar control in apps like browsers, where a click would do
    /// something else. Apps that draw their own title bar tend to be the other way around
    /// (controls beside the zoom button, empty space further along), so the rest of the
    /// row follows, then the thin strip above where controls usually sit.
    ///
    /// Anything Accessibility identifies as a control is left out. That can't catch
    /// everything — a web-based app often reports nothing more specific than its window —
    /// which is why `grabWindow` still checks that each press really took hold.
    private func titleBarGrabPoints(of target: TileTarget, frame: CGRect) -> [CGPoint] {
        var zoomButtonFrame: CGRect?
        var appElement: AXUIElement?
        if case .accessibility(let window) = target {
            var zoomButton: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, kAXZoomButtonAttribute as CFString, &zoomButton) == .success,
               let zoomButton {
                zoomButtonFrame = getWindowFrame(zoomButton as! AXUIElement)
            }
            var pid: pid_t = 0
            if AXUIElementGetPid(window, &pid) == .success {
                appElement = AXUIElementCreateApplication(pid)
            }
        }

        var besideWindowControls = CGPoint(x: frame.minX + 80, y: frame.minY + 14)
        if let zoomButtonFrame {
            let besideZoomButton = CGPoint(x: zoomButtonFrame.maxX + 6, y: zoomButtonFrame.midY)
            if frame.contains(besideZoomButton) {
                besideWindowControls = besideZoomButton
            }
        }

        let rowY = besideWindowControls.y
        let stripY = frame.minY + 5
        var points = [besideWindowControls]
        points += [0.5, 0.35, 0.65, 0.8].map { CGPoint(x: frame.minX + frame.width * $0, y: rowY) }
        points += [0.5, 0.25, 0.75].map { CGPoint(x: frame.minX + frame.width * $0, y: stripY) }

        return points.filter { point in
            guard frame.contains(point) else { return false }
            // Flipped only to check it against `NSScreen`, as a zero-size rect at the point.
            let screenSpacePoint = screenSpaceFrame(fromAX: CGRect(origin: point, size: .zero)).origin
            guard NSScreen.screens.contains(where: { $0.frame.contains(screenSpacePoint) }) else { return false }
            guard let appElement else { return true }
            return !isControl(at: point, in: appElement)
        }
    }

    private static let controlRoles: Set<String> = [
        kAXButtonRole, kAXMenuButtonRole, kAXPopUpButtonRole, kAXRadioButtonRole, kAXCheckBoxRole,
        kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole, kAXSliderRole, kAXIncrementorRole,
        kAXDisclosureTriangleRole, kAXColorWellRole, kAXScrollBarRole, "AXLink",
    ]

    /// Whether pressing at `point` would land on a control, going by the element
    /// Accessibility reports there and its nearest few ancestors (a button's label or icon
    /// is often an element of its own). An unanswered query counts as "no": better to try
    /// the point than to rule out a title bar the app just doesn't describe.
    private func isControl(at point: CGPoint, in appElement: AXUIElement) -> Bool {
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(appElement, Float(point.x), Float(point.y), &hit) == .success else { return false }

        var element = hit
        for _ in 0..<4 {
            guard let current = element else { break }
            var roleValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(current, kAXRoleAttribute as CFString, &roleValue) == .success,
                  let role = roleValue as? String else { break }
            if role == kAXWindowRole { break }
            if Self.controlRoles.contains(role) { return true }

            var parent: CFTypeRef?
            guard AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parent) == .success,
                  let parent, CFGetTypeID(parent) == AXUIElementGetTypeID() else { break }
            element = (parent as! AXUIElement)
        }
        return false
    }

    // MARK: - Helper Methods

    private func getFrontmostWindow() -> TileTarget? {
        if !AXIsProcessTrusted() {
            print("ReFlow[tiling]: Accessibility permission not granted — cannot read/move any window.")
            promptForAccessibility()
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

    private var lastAccessibilityPrompt = Date.distantPast

    /// Tiling used to fail completely silently without Accessibility access — and an
    /// update can revoke it without the switch in System Settings visibly turning off,
    /// since the grant is tied to the exact app signature it was given to. Ask again
    /// (at most every 30 seconds, so mashing a hotkey doesn't stack up prompts).
    private func promptForAccessibility() {
        guard Date().timeIntervalSince(lastAccessibilityPrompt) > 30 else { return }
        lastAccessibilityPrompt = Date()
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options)
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

    /// The target's current frame in the AX coordinate space, however it's reached.
    private func currentAXFrame(of target: TileTarget) -> CGRect? {
        switch target {
        case .accessibility(let window):
            return getWindowFrame(window)
        case .own(let window):
            return axFrame(fromScreenSpace: window.frame)
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
    private var lastTileApplied = Date.distantPast

    /// `bounds` is the screen-space area the window must stay inside (the target screen's
    /// `visibleFrame`, i.e. clear of the menu bar and Dock) if it turns out it can't take
    /// `frame`'s exact size — see `fittedFrame(size:target:bounds:)`.
    private func setWindowFrame(_ window: TileTarget, frame screenSpaceFrame: CGRect, within bounds: CGRect) {
        // Coalesce to only the most recently requested frame: cancel anything still
        // pending so a fast burst of presses resolves to a single, clean apply of the
        // last one, instead of every intermediate press racing to actually take effect.
        pendingWindowFrameWork?.cancel()
        tileGeneration += 1
        let workItem = DispatchWorkItem { [weak self] in
            switch window {
            case .accessibility(let axWindow):
                self?.applyWindowFrame(axWindow, frame: screenSpaceFrame, within: bounds)
            case .own(let nsWindow):
                self?.applyOwnWindowFrame(nsWindow, frame: screenSpaceFrame, within: bounds)
            }
            self?.lastTileApplied = Date()
            // Runs synchronously on the main thread, so no newer press can have been
            // scheduled meanwhile — whatever's pending is this item, now done.
            self?.pendingWindowFrameWork = nil
        }
        // Only a press that follows closely on another needs coalescing. A lone press
        // (the common case) applies right away instead of always waiting out the
        // debounce first.
        let isBurst = pendingWindowFrameWork != nil
            || Date().timeIntervalSince(lastTileApplied) < Self.tileDebounceInterval
        if isBurst {
            pendingWindowFrameWork = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.tileDebounceInterval, execute: workItem)
        } else {
            pendingWindowFrameWork = nil
            workItem.perform()
        }
    }

    /// Bumped by every new tiling request (and move between desktops), so settle checks
    /// left over from an earlier one stand down instead of dragging the window back.
    private var tileGeneration = 0
    /// The gaps between settle checks: frequent at first, when a late change is most
    /// likely, and running for a little over a second in all.
    private static let settleCheckDelays: [TimeInterval] = [0.05, 0.05, 0.05, 0.1, 0.15, 0.2, 0.3, 0.4]
    /// How many checks are left when about 0.6s has passed.
    private static let patientSettleChecks = 2

    /// Some apps keep adjusting their window after a tile has been applied and verified.
    /// Music is the one this was seen with: tiled to the right half it sits fully in view,
    /// then a moment later ends up hanging off the edge — consistent with it settling on
    /// its minimum size late and growing from its top-left corner. Nothing reports that,
    /// so look again a few times shortly afterward and re-fit the window if it's no longer
    /// where a window of its size belongs. For a window that stayed put, each check is a
    /// single frame read.
    private func scheduleSettleChecks(for window: AXUIElement, target screenSpaceFrame: CGRect, within bounds: CGRect) {
        settleCheck(window, target: screenSpaceFrame, within: bounds, generation: tileGeneration, delays: Self.settleCheckDelays[...])
    }

    private func settleCheck(_ window: AXUIElement, target screenSpaceFrame: CGRect, within bounds: CGRect, generation: Int, delays: ArraySlice<TimeInterval>) {
        guard let delay = delays.first else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.tileGeneration == generation else { return }
            // A held mouse button means the user has already taken over the window —
            // leave it alone from here on.
            guard NSEvent.pressedMouseButtons == 0 else {
                self.tileGeneration += 1
                return
            }
            let remaining = delays.dropFirst()
            defer {
                self.settleCheck(window, target: screenSpaceFrame, within: bounds, generation: generation, delays: remaining)
            }

            func placement(for size: CGSize) -> CGRect {
                self.axFrame(fromScreenSpace: self.fittedFrame(size: size, target: screenSpaceFrame, bounds: bounds))
            }
            guard let landed = self.settledFrame(of: window, where: { self.framesMatch($0, placement(for: $0.size)) }) else { return }
            let fitted = placement(for: landed.frame.size)
            guard !self.framesMatch(landed.frame, fitted) else { return }

            // Out of place, but only worth moving once it has stopped changing: correcting
            // a window that's still resizing or animating means correcting it again a
            // moment later, and each of those is a visible jump. Likewise one that's
            // smaller than a minimum it showed before, which may be about to grow back
            // (see `applyWindowFrame`). The last few checks stop waiting for either.
            if remaining.count > Self.patientSettleChecks {
                let expectedSize = self.expectedSize(of: window, whenAskedFor: screenSpaceFrame.size)
                let mayStillGrow = landed.frame.width < expectedSize.width - 2 || landed.frame.height < expectedSize.height - 2
                guard landed.hasStopped, !mayStillGrow else { return }
            }
            print("ReFlow[tiling]: window drifted to \(landed.frame) after tiling — re-placing it at \(fitted.origin) to keep it fully visible.")
            self.noteSize(landed.frame.size, of: window, whenAskedFor: screenSpaceFrame.size)
            self.setPosition(fitted.origin, of: window)
        }
    }

    /// Sizes that windows turned out not to shrink below, by window. Knowing one up front
    /// means the window can be put where a window of *that* size belongs straight away,
    /// instead of being placed for the size that was asked for and corrected once it's
    /// seen to be bigger — which is the window jumping out of view and back.
    private var learnedMinimumSizes: [AXUIElement: CGSize] = [:]

    /// The size `window` is expected to end up when asked to be `size`.
    private func expectedSize(of window: AXUIElement, whenAskedFor size: CGSize) -> CGSize {
        guard let minimum = learnedMinimumSizes[window] else { return size }
        return CGSize(width: max(size.width, minimum.width), height: max(size.height, minimum.height))
    }

    /// Records what `window` actually did when asked to be `requested`. Ending up bigger
    /// means it has a minimum; taking a size below a recorded minimum means that minimum
    /// is out of date (Music's differs between its full window and the MiniPlayer).
    private func noteSize(_ actual: CGSize, of window: AXUIElement, whenAskedFor requested: CGSize) {
        func minimum(_ actual: CGFloat, _ requested: CGFloat, _ known: CGFloat) -> CGFloat {
            if actual > requested + 2 { return actual }
            return requested < known - 2 ? 0 : known
        }
        let known = learnedMinimumSizes[window] ?? .zero
        let updated = CGSize(
            width: minimum(actual.width, requested.width, known.width),
            height: minimum(actual.height, requested.height, known.height)
        )
        guard updated != known else { return }
        if updated == .zero {
            learnedMinimumSizes[window] = nil
        } else {
            // Entries for windows that have since closed are never looked up again, so
            // rather than track which those are, start over once there are a lot.
            if learnedMinimumSizes.count >= 64 {
                learnedMinimumSizes.removeAll()
            }
            learnedMinimumSizes[window] = updated
        }
    }

    /// Moves a window without touching its size, working around "AXEnhancedUserInterface"
    /// the same way `applyWindowFrame` does.
    private func setPosition(_ origin: CGPoint, of window: AXUIElement) {
        let wasEnhancedUIEnabled = setEnhancedUserInterface(for: window, enabled: false)
        defer {
            if let wasEnhancedUIEnabled, wasEnhancedUIEnabled {
                _ = setEnhancedUserInterface(for: window, enabled: true)
            }
        }
        write(origin: origin, to: window)
    }

    @discardableResult
    private func write(origin: CGPoint, to window: AXUIElement) -> AXError {
        var position = origin
        return AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &position)!)
    }

    @discardableResult
    private func write(size: CGSize, to window: AXUIElement) -> AXError {
        var size = size
        return AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, AXValueCreate(.cgSize, &size)!)
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
        defer {
            if let wasEnhancedUIEnabled, wasEnhancedUIEnabled {
                _ = setEnhancedUserInterface(for: window, enabled: true)
            }
        }

        // However the window gets there, check back on it afterward: see `scheduleSettleChecks`.
        defer { scheduleSettleChecks(for: window, target: screenSpaceFrame, within: bounds) }

        // The aim is for the window to go to its tile in one visible step, and never to be
        // anywhere it shouldn't be on the way. Two things used to get in the way of that.
        //
        // A position and a size can only be written one after the other, so there's always
        // a moment with one applied and not the other. Written in the wrong order, that
        // moment has the window hanging off the screen (a full-width window moved to the
        // right half before being narrowed), and it's long enough to see. So the order
        // depends on which way the window is changing: if it's only growing, move it
        // first, since the size it already has fits inside the tile; otherwise resize it
        // first.
        //
        // And a window doesn't always take the size it's given — Music won't go narrower
        // than its minimum. Placing one at the tile's own origin regardless pushed it off
        // the side of the screen or behind the Dock until a later step noticed and pulled
        // it back. So a window is only ever placed where a window of the size it really
        // has belongs (`fittedFrame`): its size is read back before it's moved, or already
        // known from last time (`learnedMinimumSizes`).
        let tileSize = screenSpaceFrame.size
        let expectedSize = expectedSize(of: window, whenAskedFor: tileSize)
        func placement(for size: CGSize) -> CGRect {
            axFrame(fromScreenSpace: fittedFrame(size: size, target: screenSpaceFrame, bounds: bounds))
        }
        let expected = placement(for: expectedSize)
        let current = getWindowFrame(window)

        if let current, current.width <= expected.width + 1, current.height <= expected.height + 1 {
            write(origin: expected.origin, to: window)
            write(size: tileSize, to: window)
        } else {
            write(size: tileSize, to: window)
            // Only waited for if the window is still bigger than it should be, which is
            // what a minimum size looks like. Coming out *smaller* is something else: the
            // app clamping the size to what fit on screen at the window's old position.
            // That's fixed by asking again once the window has moved (the order Rectangle
            // uses: size, position, size), so those dimensions are placed as if they'd
            // already taken.
            let resized = settledFrame(of: window, where: {
                $0.width <= expectedSize.width + 2 && $0.height <= expectedSize.height + 2
            })?.frame.size ?? expectedSize
            let sizeToPlace = CGSize(width: max(resized.width, expectedSize.width), height: max(resized.height, expectedSize.height))
            write(origin: sizesMatch(sizeToPlace, expectedSize) ? expected.origin : placement(for: sizeToPlace).origin, to: window)
            if !sizesMatch(resized, expectedSize) {
                write(size: tileSize, to: window)
            }
        }

        guard let landed = settledFrame(of: window, where: { self.framesMatch($0, expected) }) else { return }
        // A window that's still changing (an app animating its own resize) is left to the
        // settle checks: writing to it again now would only make it jump mid-animation.
        guard landed.hasStopped else { return }
        if framesMatch(landed.frame, expected) {
            noteSize(landed.frame.size, of: window, whenAskedFor: tileSize)
            return
        }

        // Smaller than asked in some direction isn't a minimum size at work. It's either a
        // window that can't be resized that far (rare), or an app that mishandled the
        // writes — which the slower, more careful route below exists for.
        if landed.frame.width < tileSize.width - 2 || landed.frame.height < tileSize.height - 2 {
            applyInPhases(window, targetFrame: targetFrame, screenSpaceFrame: screenSpaceFrame, within: bounds)
            return
        }

        // Smaller than a minimum it showed before. Either that minimum no longer applies,
        // or the window takes any size and then grows back a moment later. It's in view
        // where it is, so wait and see: the settle checks move it if it stays this size.
        if landed.frame.width < expectedSize.width - 2 || landed.frame.height < expectedSize.height - 2 {
            return
        }

        // Bigger than expected: a minimum size nobody knew about yet. Remember it, and move
        // the window to where one of that size belongs.
        noteSize(landed.frame.size, of: window, whenAskedFor: tileSize)
        let fitted = placement(for: landed.frame.size)
        if !framesMatch(landed.frame, fitted) {
            print("ReFlow[tiling]: window landed at \(landed.frame) instead of \(targetFrame) — re-placing it at \(fitted.origin) to keep it fully visible.")
            write(origin: fitted.origin, to: window)
        }
    }

    /// Reads the window's frame, giving it a moment (up to 60ms) if it isn't yet what
    /// `isExpected` is looking for: an app doesn't always finish applying a write before
    /// the write returns. Safari in particular reconciles with the window server
    /// afterward, so an immediate read-back can catch it mid-way. `hasStopped` is false
    /// if the frame was still changing when time ran out.
    private func settledFrame(of window: AXUIElement, where isExpected: (CGRect) -> Bool) -> (frame: CGRect, hasStopped: Bool)? {
        guard var frame = getWindowFrame(window) else { return nil }
        if isExpected(frame) { return (frame, true) }
        for _ in 0..<4 {
            Thread.sleep(forTimeInterval: 0.015)
            guard let next = getWindowFrame(window) else { return nil }
            if isExpected(next) || next == frame { return (next, true) }
            frame = next
        }
        return (frame, false)
    }

    private func sizesMatch(_ lhs: CGSize, _ rhs: CGSize, tolerance: CGFloat = 2.0) -> Bool {
        abs(lhs.width - rhs.width) <= tolerance && abs(lhs.height - rhs.height) <= tolerance
    }

    /// The careful way to write a frame, for a window the direct writes in
    /// `applyWindowFrame` left the wrong size. Slower, and the window visibly moves in two
    /// steps, which is why it isn't the first thing tried.
    private func applyInPhases(_ window: AXUIElement, targetFrame: CGRect, screenSpaceFrame: CGRect, within bounds: CGRect) {
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

/// What ReFlow can find out about Spaces. None of it has a public API, so these are
/// SkyLight's private calls, looked up by name at run time: if a macOS update drops one, its
/// lookup comes back `nil` and whatever relied on it falls back to working without, rather
/// than ReFlow failing to launch. Only calls that read are used, plus switching a system
/// keyboard shortcut on and off.
private enum Spaces {
    private static let handle = dlopen(nil, RTLD_LAZY)

    private static func function<Function>(_ name: String, as type: Function.Type) -> Function? {
        dlsym(handle, name).map { unsafeBitCast($0, to: type) }
    }

    private static let mainConnection = function("CGSMainConnectionID", as: (@convention(c) () -> Int32).self)
    private static let copySpacesForWindows = function("CGSCopySpacesForWindows", as: (@convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?).self)
    private static let copyManagedDisplaySpaces = function("CGSCopyManagedDisplaySpaces", as: (@convention(c) (Int32) -> Unmanaged<CFArray>?).self)
    private static let getWindow = function("_AXUIElementGetWindow", as: (@convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError).self)
    private static let isHotKeyEnabled = function("CGSIsSymbolicHotKeyEnabled", as: (@convention(c) (Int32) -> Bool).self)
    private static let setHotKeyEnabled = function("CGSSetSymbolicHotKeyEnabled", as: (@convention(c) (Int32, Bool) -> Int32).self)
    private static let getHotKeyValue = function("CGSGetSymbolicHotKeyValue", as: (@convention(c) (Int32, UnsafeMutablePointer<UInt16>, UnsafeMutablePointer<UInt16>, UnsafeMutablePointer<UInt64>) -> Int32).self)

    static func windowID(of target: WindowManager.TileTarget) -> CGWindowID? {
        switch target {
        case .accessibility(let window):
            var id: CGWindowID = 0
            guard let getWindow, getWindow(window, &id) == .success, id != 0 else { return nil }
            return id
        case .own(let window):
            return window.windowNumber > 0 ? CGWindowID(window.windowNumber) : nil
        }
    }

    /// The Spaces a window is on: normally one, or none while it's being carried between two.
    static func spaces(ofWindow id: CGWindowID) -> Set<UInt64>? {
        let allSpaces: Int32 = 7
        guard let mainConnection, let copySpacesForWindows,
              let spaces = copySpacesForWindows(mainConnection(), allSpaces, [NSNumber(value: id)] as CFArray)?.takeRetainedValue() as? [NSNumber] else { return nil }
        return Set(spaces.map(\.uint64Value))
    }

    /// Whether the display showing `spaces` has another Space `offset` places along from
    /// it, in Mission Control's order. `nil` if that can't be worked out.
    static func hasSpace(beside spaces: Set<UInt64>, offset: Int) -> Bool? {
        guard !spaces.isEmpty, let mainConnection, let copyManagedDisplaySpaces,
              let displays = copyManagedDisplaySpaces(mainConnection())?.takeRetainedValue() as? [[String: Any]] else { return nil }
        for display in displays {
            let ids = (display["Spaces"] as? [[String: Any]] ?? []).compactMap { ($0["ManagedSpaceID"] as? NSNumber)?.uint64Value }
            if let index = ids.firstIndex(where: spaces.contains) {
                return ids.indices.contains(index + offset)
            }
        }
        return nil
    }

    /// A system keyboard shortcut ("symbolic hot key").
    struct Shortcut {
        /// `nil` for a stand-in used when the real shortcut couldn't be read.
        let id: Int32?
        let keyCode: CGKeyCode
        let flags: CGEventFlags
        let isEnabled: Bool
    }

    /// "Move left a space" / "Move right a space" as currently set in System Settings →
    /// Keyboard → Keyboard Shortcuts → Mission Control.
    static func moveShortcut(towardLeft: Bool) -> Shortcut? {
        let id: Int32 = towardLeft ? 79 : 81
        guard let getHotKeyValue, let isHotKeyEnabled else { return nil }
        var character: UInt16 = 0
        var keyCode: UInt16 = 0
        var modifiers: UInt64 = 0
        guard getHotKeyValue(id, &character, &keyCode, &modifiers) == 0, keyCode != UInt16.max else { return nil }

        var flags = CGEventFlags(rawValue: modifiers)
            .intersection([.maskControl, .maskAlternate, .maskShift, .maskCommand, .maskSecondaryFn])
        if (123...126).contains(keyCode) {
            flags.formUnion([.maskSecondaryFn, .maskNumericPad])
        }
        return Shortcut(id: id, keyCode: keyCode, flags: flags, isEnabled: isHotKeyEnabled(id))
    }

    @discardableResult
    static func setShortcutEnabled(_ id: Int32, _ enabled: Bool) -> Bool {
        guard let setHotKeyEnabled else { return false }
        return setHotKeyEnabled(id, enabled) == 0
    }
}
