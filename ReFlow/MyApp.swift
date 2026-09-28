import SwiftUI
import AppKit
import Combine

@main
struct ReFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarItem: NSStatusItem!
    var windowManager = WindowManager.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Request accessibility permissions
        requestAccessibilityPermissions()

        // Create status bar item
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusBarItem.button {
            let icon = NSImage(named: "Image")
            icon?.size = NSSize(width: 18, height: 18)
            icon?.accessibilityDescription = "ReFlow"
            button.image = icon
            button.action = #selector(toggleLauncher)
            button.target = self
        }

        // Set up global hotkeys, driven by the user's customizable bindings
        HotKeyCenter.shared.handler = { [weak self] action in
            self?.perform(action)
        }
        ShortcutStore.shared.onChange = {
            HotKeyCenter.shared.registerAll()
        }
        HotKeyCenter.shared.registerAll()
    }

    func perform(_ action: ShortcutAction) {
        switch action {
        case .toggleLauncher:
            toggleLauncher()
        case .windowLeftHalf:
            windowManager.moveActiveWindowToLeftHalf()
        case .windowRightHalf:
            windowManager.moveActiveWindowToRightHalf()
        case .windowTopHalf:
            windowManager.moveActiveWindowToTopHalf()
        case .windowBottomHalf:
            windowManager.moveActiveWindowToBottomHalf()
        case .windowMaximize:
            windowManager.maximizeActiveWindow()
        case .windowRestore:
            windowManager.centerActiveWindow()
        case .cornerTopLeft:
            windowManager.moveActiveWindowToCorner(.topLeft)
        case .cornerTopRight:
            windowManager.moveActiveWindowToCorner(.topRight)
        case .cornerBottomLeft:
            windowManager.moveActiveWindowToCorner(.bottomLeft)
        case .cornerBottomRight:
            windowManager.moveActiveWindowToCorner(.bottomRight)
        case .windowLeftThird:
            windowManager.moveActiveWindowToLeftThird()
        case .windowCenterThird:
            windowManager.moveActiveWindowToCenterThird()
        case .windowRightThird:
            windowManager.moveActiveWindowToRightThird()
        case .windowLeftTwoThirds:
            windowManager.moveActiveWindowToLeftTwoThirds()
        case .windowRightTwoThirds:
            windowManager.moveActiveWindowToRightTwoThirds()
        case .displayPrevious:
            windowManager.moveActiveWindowToPreviousDisplay()
        case .displayNext:
            windowManager.moveActiveWindowToNextDisplay()
        case .desktopPrevious:
            windowManager.moveToPreviousDesktop()
        case .desktopNext:
            windowManager.moveToNextDesktop()
        case .toggleEmojiMode, .trashTopResult, .moveTopResult, .showInFinderTopResult, .openSettings:
            // Launcher-scope actions are handled locally by LauncherView while it's focused.
            break
        }
    }

    @objc func toggleLauncher() {
        LauncherWindowController.shared.toggle()
    }

    func requestAccessibilityPermissions() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options)
    }
}

/// A borderless, non-activating panel — the standard shape for a Spotlight/Raycast-style
/// launcher. It needs to become key (so its search field accepts keystrokes) without the
/// system-default refusal that borderless/nonactivating panels have by default.
class LauncherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Owns the single floating launcher window: where it opens by default, where the user
/// last dragged it to, and showing/hiding it in place of the old status-item popover.
@MainActor
final class LauncherWindowController: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = LauncherWindowController()

    /// Since the panel and its hosted SwiftUI view are created once and reused across
    /// show/hide cycles (unlike the old popover, which reattached its content each time),
    /// SwiftUI's `.onAppear` won't refire on every reopen. LauncherView observes this
    /// instead so it can refocus and reset itself every time the window becomes visible.
    @Published private(set) var isVisible = false

    private let panel: LauncherPanel
    private static let originDefaultsKey = "launcherWindowOrigin_v2"
    private static let panelSize = NSSize(width: 600, height: 450)

    /// `setFrameOrigin` in `show()` fires the same `windowDidMove` delegate callback as a
    /// genuine user drag. Without this guard, our own positioning would immediately get
    /// persisted as if the user had dragged it there — which is how a bad position (e.g.
    /// from an earlier broken run) could get permanently locked in.
    private var isProgrammaticMove = false

    private override init() {
        let panel = LauncherPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        self.panel = panel
        super.init()
        panel.delegate = self
    }

    func toggle() {
        if panel.isVisible {
            hide()
        } else {
            show()
        }
    }

    private var contentConfigured = false

    /// Deferred until after `init()` returns and `.shared` is fully assigned. `LauncherView`
    /// itself reads `LauncherWindowController.shared` — building it any earlier (e.g. directly
    /// inside `init()`) re-enters the same one-time `static let` initialization and deadlocks
    /// the main thread before anything can appear.
    private func configureContentIfNeeded() {
        guard !contentConfigured else { return }
        contentConfigured = true
        panel.contentViewController = NSHostingController(rootView: LauncherView())
        // NSHostingController can nudge the window to fit its content once SwiftUI's
        // layout settles, which doesn't necessarily happen before defaultOrigin() below
        // reads the frame size — that race is why the very first open (and only that one)
        // used to land in the wrong spot. Pin it back to the fixed size immediately.
        panel.setContentSize(Self.panelSize)
    }

    func show() {
        configureContentIfNeeded()
        isProgrammaticMove = true
        panel.setFrameOrigin(savedOrigin() ?? defaultOrigin())
        isProgrammaticMove = false
        // Deliberately not calling NSApp.activate here: this is a nonactivating panel
        // precisely so the previously-active app stays frontmost while the panel takes
        // keyboard focus. Force-activating ReFlow instead broke two things at once —
        // window-tiling hotkeys would see ReFlow (not the app you meant) as frontmost,
        // and a hotkey owned by the *currently active* app doesn't reliably preempt
        // normal key dispatch the way one owned by a background app does, so the
        // keystroke could fall through to the search field instead of firing the hotkey.
        panel.makeKeyAndOrderFront(nil)
        isVisible = true
    }

    func hide() {
        panel.orderOut(nil)
        isVisible = false
    }

    private func defaultOrigin() -> NSPoint {
        guard let screen = NSScreen.main else { return .zero }
        let screenFrame = screen.visibleFrame
        let size = Self.panelSize
        let x = screenFrame.minX + (screenFrame.width - size.width) / 2
        // Slightly above true vertical center (Raycast/Spotlight-style placement):
        // center the window on a point 42% down from the top of the screen.
        let y = screenFrame.minY + screenFrame.height * 0.58 - size.height / 2
        return NSPoint(x: x, y: y)
    }

    private func savedOrigin() -> NSPoint? {
        guard let dict = UserDefaults.standard.dictionary(forKey: Self.originDefaultsKey),
              let x = dict["x"] as? Double, let y = dict["y"] as? Double else { return nil }
        return NSPoint(x: x, y: y)
    }

    private func persistOrigin(_ origin: NSPoint) {
        UserDefaults.standard.set(["x": origin.x, "y": origin.y], forKey: Self.originDefaultsKey)
    }

    func windowDidMove(_ notification: Notification) {
        guard !isProgrammaticMove else { return }
        persistOrigin(panel.frame.origin)
    }

    /// Closes like Spotlight when the user clicks away — but only to a genuinely
    /// different app, not when one of our own windows (Settings, the "Move to..." Open
    /// panel, a sheet) takes over key status. `NSApp.keyWindow` only reports windows
    /// owned by this process, so once the transition settles, nil means key status left
    /// ReFlow entirely; non-nil means it just moved to another one of our own windows.
    func windowDidResignKey(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self, NSApp.keyWindow == nil else { return }
            self.hide()
        }
    }
}
