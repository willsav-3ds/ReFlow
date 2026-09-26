import SwiftUI
import AppKit

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
    var popover: NSPopover!
    var statusBarItem: NSStatusItem!
    var hotkeyMonitor: Any?
    var windowManager = WindowManager.shared
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Request accessibility permissions
        requestAccessibilityPermissions()
        
        // Create the popover
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 600, height: 450)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: LauncherView())
        self.popover = popover
        
        // Create status bar item
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusBarItem.button {
            button.image = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: "ReFlow")
            button.action = #selector(togglePopover)
            button.target = self
        }
        
        // Set up global hotkeys
        setupGlobalHotkeys()
    }
    
    func setupGlobalHotkeys() {
        // Main launcher hotkey (Cmd+Shift+Space)
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleGlobalKeyEvent(event)
        }
        
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.handleGlobalKeyEvent(event) == true {
                return nil
            }
            return event
        }
    }
    
    @discardableResult
    func handleGlobalKeyEvent(_ event: NSEvent) -> Bool {
        let prefs = UserDefaults.standard
        
        // Main launcher hotkey (Cmd+Shift+Space by default)
        if event.modifierFlags.contains([.command, .shift]) && event.keyCode == 49 {
            togglePopover()
            return true
        }
        
        // Window management hotkeys
        let mods = event.modifierFlags
        let key = event.keyCode
        
        // Ctrl+Option+Cmd combinations for window management
        if mods.contains([.control, .option, .command]) {
            switch key {
            case 123: // Left arrow - Left half
                windowManager.moveActiveWindowToLeftHalf()
                return true
            case 124: // Right arrow - Right half
                windowManager.moveActiveWindowToRightHalf()
                return true
            case 125: // Down arrow - Bottom half
                windowManager.moveActiveWindowToBottomHalf()
                return true
            case 126: // Up arrow - Maximize
                windowManager.maximizeActiveWindow()
                return true
            case 6: // Z - Top left
                windowManager.moveActiveWindowToCorner(.topLeft)
                return true
            case 7: // X - Top right
                windowManager.moveActiveWindowToCorner(.topRight)
                return true
            case 8: // C - Bottom left
                windowManager.moveActiveWindowToCorner(.bottomLeft)
                return true
            case 9: // V - Bottom right
                windowManager.moveActiveWindowToCorner(.bottomRight)
                return true
            case 15: // R - Restore
                windowManager.centerActiveWindow()
                return true
            default:
                break
            }
        }
        
        // Ctrl+Option for desktop switching
        if mods.contains([.control, .option]) && !mods.contains(.command) {
            switch key {
            case 123: // Left arrow - Previous desktop
                windowManager.moveToPreviousDesktop()
                return true
            case 124: // Right arrow - Next desktop
                windowManager.moveToNextDesktop()
                return true
            default:
                break
            }
        }
        
        return false
    }
    
    @objc func togglePopover() {
        if let button = statusBarItem?.button {
            if popover.isShown {
                popover.performClose(nil)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                popover.contentViewController?.view.window?.makeKey()
            }
        } else {
            // Show at center of screen if no status bar item
            if popover.isShown {
                popover.performClose(nil)
            } else {
                if let screen = NSScreen.main {
                    let rect = NSRect(x: screen.frame.midX - 300, 
                                    y: screen.frame.midY + 225, 
                                    width: 600, 
                                    height: 450)
                    popover.show(relativeTo: rect, of: NSApp.keyWindow?.contentView ?? NSView(), preferredEdge: .minY)
                    popover.contentViewController?.view.window?.makeKey()
                }
            }
        }
    }
    
    func requestAccessibilityPermissions() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options)
    }
}
