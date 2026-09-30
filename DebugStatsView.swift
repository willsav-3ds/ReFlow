import SwiftUI
import AppKit

/// A normal titled window, unlike the launcher's borderless non-activating panel — this
/// is a tool window, so it should show up in Cmd+Tab/Window cycling and behave like any
/// other window when closed (rather than just hiding, the way `LauncherWindowController`
/// keeps its single panel alive across show/hide cycles).
@MainActor
final class DebugStatsWindowController: NSObject, NSWindowDelegate {
    static let shared = DebugStatsWindowController()

    private var window: NSWindow?

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
        } else {
            let hosting = NSHostingController(rootView: DebugStatsView())
            let newWindow = NSWindow(contentViewController: hosting)
            newWindow.title = "ReFlow Debug Stats"
            newWindow.styleMask = [.titled, .closable, .miniaturizable]
            newWindow.isReleasedWhenClosed = false
            newWindow.delegate = self
            newWindow.center()
            window = newWindow
            newWindow.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
        // Only pay for the sampling timer while the window is actually open — see the
        // matching `stopSampling()` in `windowWillClose` below.
        ResourceMonitor.shared.startSampling()
    }

    func windowWillClose(_ notification: Notification) {
        ResourceMonitor.shared.stopSampling()
    }
}

/// Read-only view of how resource-intensive ReFlow currently is: live process stats
/// (memory, CPU, threads) straight from the kernel, plus the sizes of the in-memory
/// caches and the state of every timer-driven background monitor the app runs — so it's
/// obvious at a glance whether anything is unexpectedly growing or polling.
struct DebugStatsView: View {
    @ObservedObject private var monitor = ResourceMonitor.shared
    @ObservedObject private var clipboard = ClipboardHistoryStore.shared

    var body: some View {
        Form {
            Section("Process") {
                StatRow(label: "Memory (footprint)", value: String(format: "%.1f MB", monitor.memoryFootprintMB))
                StatRow(label: "CPU", value: String(format: "%.1f%%", monitor.cpuUsagePercent))
                StatRow(label: "Threads", value: "\(monitor.threadCount)")
            }

            Section("Launcher Caches") {
                let stats = SearchEngine.shared.cacheStats
                StatRow(label: "Cached applications", value: stats.apps.map(String.init) ?? "not built yet")
                StatRow(label: "Cached app icons", value: "\(stats.icons)")
                StatRow(label: "Cached sticker thumbnails", value: "\(stats.stickerIcons)")
            }

            Section("Background Monitors") {
                StatRow(
                    label: "Clipboard history",
                    value: clipboard.isEnabled
                        ? "on — polling every \(String(format: "%.2f", ClipboardHistoryStore.pollInterval))s"
                        : "off"
                )
                StatRow(label: "Clipboard entries", value: "\(clipboard.entries.count)")
                StatRow(label: "Global hotkeys registered", value: "\(HotKeyCenter.shared.registeredCount)")
            }

            Section {
                HStack {
                    Spacer()
                    Button("Repoll") {
                        monitor.resample()
                    }
                    Spacer()
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 380, height: 340)
    }
}

private struct StatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

#Preview {
    DebugStatsView()
}
