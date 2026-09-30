import AppKit
import Combine

/// A single captured clipboard snapshot — either text, or an image/GIF along with its
/// raw bytes and pasteboard type so it can be pasted back exactly as it was copied.
struct ClipboardHistoryEntry: Identifiable {
    let id = UUID()
    let date = Date()
    let text: String?
    let image: NSImage?
    let rawData: Data?
    let rawType: NSPasteboard.PasteboardType?
}

/// Optional, opt-in clipboard history — toggled from Settings, off by default. There's
/// no system notification for "the clipboard changed," so like every other clipboard
/// manager this polls `NSPasteboard.general.changeCount` on a timer. History is
/// deliberately in-memory only (never written to disk) and is cleared the moment
/// monitoring is turned off, since clipboard contents can include passwords and other
/// sensitive text that shouldn't linger anywhere persistent.
@MainActor
final class ClipboardHistoryStore: ObservableObject {
    static let shared = ClipboardHistoryStore()

    @Published private(set) var entries: [ClipboardHistoryEntry] = []
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledDefaultsKey)
            if isEnabled {
                startMonitoring()
            } else {
                stopMonitoring()
            }
        }
    }

    private static let enabledDefaultsKey = "clipboardHistoryEnabled"
    private static let maxEntries = 50
    /// Not `private`: the debug stats window reports this alongside whether monitoring
    /// is currently on, so it's visible without duplicating the number there.
    static let pollInterval: TimeInterval = 0.75

    private var timer: Timer?
    private var lastChangeCount: Int
    /// Set around ReFlow's own programmatic pasteboard writes (see `ClipboardPaste`) so
    /// copying an emoji/sticker — and reverting the clipboard afterward — doesn't pollute
    /// history with noise the user never actually copied themselves.
    private var suppressNextCapture = false

    private init() {
        lastChangeCount = NSPasteboard.general.changeCount
        // `didSet` doesn't fire for this initial assignment (Swift never runs property
        // observers for a type's own init), so monitoring has to be started explicitly
        // here if it was left on from a previous run.
        isEnabled = UserDefaults.standard.bool(forKey: Self.enabledDefaultsKey)
        if isEnabled {
            startMonitoring()
        }
    }

    func suppressNextChange() {
        suppressNextCapture = true
    }

    func clear() {
        entries.removeAll()
    }

    private func startMonitoring() {
        guard timer == nil else { return }
        lastChangeCount = NSPasteboard.general.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollPasteboard() }
        }
    }

    private func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        entries.removeAll()
    }

    private func pollPasteboard() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        guard !suppressNextCapture else {
            suppressNextCapture = false
            return
        }

        let gifType = NSPasteboard.PasteboardType("com.compuserve.gif")
        if let gifData = pasteboard.data(forType: gifType) {
            addEntry(ClipboardHistoryEntry(text: nil, image: NSImage(data: gifData), rawData: gifData, rawType: gifType))
        } else if let tiffData = pasteboard.data(forType: .tiff) {
            addEntry(ClipboardHistoryEntry(text: nil, image: NSImage(data: tiffData), rawData: tiffData, rawType: .tiff))
        } else if let string = pasteboard.string(forType: .string), !string.isEmpty {
            addEntry(ClipboardHistoryEntry(text: string, image: nil, rawData: nil, rawType: nil))
        }
    }

    private func addEntry(_ entry: ClipboardHistoryEntry) {
        // Skip an exact repeat of the most recent entry (e.g. copying the same thing twice).
        if let last = entries.first {
            if let text = entry.text, text == last.text { return }
            if let data = entry.rawData, data == last.rawData { return }
        }

        entries.insert(entry, at: 0)
        if entries.count > Self.maxEntries {
            entries.removeLast(entries.count - Self.maxEntries)
        }
    }
}
