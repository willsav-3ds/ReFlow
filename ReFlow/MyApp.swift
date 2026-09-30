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

/// Lets pure-AppKit code — like the status item's right-click menu below, which has no
/// SwiftUI environment of its own — trigger the real `openSettings` environment action.
/// `LauncherView` registers it (it's the one place in the app that already has it) as
/// soon as its body first evaluates. Falls back to the private `showSettingsWindow:`
/// selector (prints SwiftUI's own "use SettingsLink" warning, but still works) for the
/// unlikely case this fires before that's happened even once.
enum SettingsOpener {
    static var openAction: (() -> Void)?

    /// The actual Settings `NSWindow`, captured by `SettingsWindowAccessor` (in
    /// SettingsView.swift) once SwiftUI creates it. Weak since we don't own it — the
    /// `Settings` scene does, same as any other SwiftUI-managed window.
    static weak var window: NSWindow?

    static func open() {
        // If Settings is already open — possibly on a different Space/desktop — just
        // asking SwiftUI to "open" it again would only call `makeKeyAndOrderFront` on
        // that same existing window, which reveals it wherever it already is by
        // switching you (Mission-Control-style) to whatever desktop it was left open on,
        // instead of bringing it to the one you're actually on. Closing it first means
        // there's nothing left to "reveal" on the old Space, so whatever opens next —
        // whether SwiftUI reuses this window or builds a fresh one — always lands on the
        // current Space.
        if let window, window.isVisible {
            window.close()
        }

        if let openAction {
            openAction()
        } else {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
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
            // Template mode makes AppKit treat the icon as a monochrome stencil (using
            // just its alpha channel) and tint it to match the menu bar's current
            // appearance — light glyph on a dark menu bar, dark glyph on a light one,
            // plus the dimmed/inverted look while the item is highlighted — the same way
            // every other menu bar icon behaves. Also set on the image set itself
            // ("Render As: Template Image"); setting it here too means this stays correct
            // even if the image is ever loaded some other way.
            icon?.isTemplate = true
            button.image = icon
            button.action = #selector(statusItemClicked)
            button.target = self
            // Left-click still just toggles the launcher (the common case); right-click
            // (or Control-click) instead shows a menu — both need to reach the same
            // action method so it can tell which one happened.
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // Warm up the launcher's SwiftUI content now, off-screen, so `SettingsOpener.openAction`
        // (registered in `LauncherView.onAppear`) is ready before the user gets a chance to
        // right-click the status item and choose Settings — without this, that path falls back
        // to a private selector that no-ops on newer macOS instead of opening anything.
        LauncherWindowController.shared.prepareContentOffscreen()

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
        case .toggleEmojiMode:
            LauncherWindowController.shared.showEmojiPicker()
        case .trashTopResult, .moveTopResult, .showInFinderTopResult, .openSettings:
            // Launcher-scope actions are handled locally by LauncherView while it's focused.
            break
        }
    }

    @objc func toggleLauncher() {
        LauncherWindowController.shared.toggle()
    }

    @objc func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showStatusMenu()
        } else {
            toggleLauncher()
        }
    }

    /// Shown via the standard "assign a menu, synthesize a click, clear it again" trick
    /// — assigning `statusBarItem.menu` directly (instead of just for this one moment)
    /// would make it pop up on *every* click, left or right alike, which isn't what we
    /// want here.
    private func showStatusMenu() {
        let menu = NSMenu()

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettingsFromMenu), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let debugStatsItem = NSMenuItem(title: "Debug Stats…", action: #selector(openDebugStatsFromMenu), keyEquivalent: "")
        debugStatsItem.target = self
        menu.addItem(debugStatsItem)

        menu.addItem(.separator())

        // A nil target lets this reach `NSApplication.terminate(_:)` via the normal
        // responder chain, the same way a standard File > Quit menu item works.
        menu.addItem(NSMenuItem(title: "Quit ReFlow", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusBarItem.menu = menu
        statusBarItem.button?.performClick(nil)
        statusBarItem.menu = nil
    }

    @objc func openDebugStatsFromMenu() {
        DebugStatsWindowController.shared.show()
    }

    @objc func openSettingsFromMenu() {
        SettingsOpener.open()
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

    /// Whichever app was active right before the panel opened — captured fresh on every
    /// open since our nonactivating panel never steals "active application" status from
    /// it. Selecting an emoji or sticker pastes back into this app (see `ClipboardPaste`),
    /// since there's no public API to insert text/images into another app's focused field
    /// directly.
    private(set) var appToRestoreFocusTo: NSRunningApplication?

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

    /// Briefly orders the panel on-screen far off any real display, then off again, purely so
    /// `LauncherView`'s `.onAppear` runs and captures the real `openSettings` environment action
    /// into `SettingsOpener.openAction` — without ever flashing the launcher where the user would
    /// actually see it. Guarded with `isProgrammaticMove` so this synthetic position never gets
    /// persisted as the user's saved launcher origin, and deferred a beat before hiding again so
    /// SwiftUI has a run loop turn to actually deliver `onAppear` before we order out.
    func prepareContentOffscreen() {
        configureContentIfNeeded()
        isProgrammaticMove = true
        panel.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        isProgrammaticMove = false
        panel.orderFrontRegardless()
        DispatchQueue.main.async { [weak self] in
            self?.panel.orderOut(nil)
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
        appToRestoreFocusTo = NSWorkspace.shared.frontmostApplication
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

    /// Opens directly into emoji/sticker search — or, if already open, just flips between
    /// emoji and launcher mode in place, same as the toolbar toggle button. Used by the
    /// global ⌃⌘Space hotkey so it behaves the same whether or not the launcher is
    /// already open, in place of macOS's own (much slower) Character Viewer on that same
    /// shortcut.
    func showEmojiPicker() {
        if isVisible {
            SearchEngine.shared.toggleMode()
        } else {
            SearchEngine.shared.searchMode = .emoji
            show()
        }
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
