import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Pastes emoji/sticker/clipboard-history selections back into whatever app was
/// frontmost before the launcher opened. There's no public API to insert text or an
/// image directly into another app's focused field, so — the same trick emoji-picker
/// replacements like Rocket use — this puts the content on the clipboard, reactivates
/// that app, and simulates ⌘V.
enum ClipboardPaste {
    /// `setClipboard` should leave the general pasteboard holding whatever should be
    /// pasted (already cleared/populated by the caller) by the time this returns.
    /// Whatever the clipboard held *before* that gets restored afterward — selecting an
    /// emoji or sticker pastes it once and then gets out of the way, rather than
    /// permanently overwriting whatever you'd actually copied.
    static func paste(afterSettingClipboard setClipboard: () -> Void) {
        let appToRestore = LauncherWindowController.shared.appToRestoreFocusTo
        let previousClipboard = snapshotPasteboard()

        ClipboardHistoryStore.shared.suppressNextChange()
        setClipboard()

        // Deferred one run loop turn so the launcher panel (closed by the caller's own
        // result-execution flow right after this returns) is gone first. The panel is
        // nonactivating, so the original app is normally *still* frontmost and only
        // needs its key window back — this used to wait a flat 300ms on every paste
        // regardless; now it only waits as long as focus actually takes to return.
        DispatchQueue.main.async {
            if let appToRestore, NSWorkspace.shared.frontmostApplication != appToRestore {
                appToRestore.activate()
            }
            whenFrontmost(appToRestore, deadline: Date().addingTimeInterval(0.4)) {
                // A beat for the window server to hand key status back to that app's
                // window, so ⌘V doesn't land nowhere or in ReFlow's vanishing panel.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
                    postCommandV()

                    // Give the target app a moment to actually read the pasteboard on its
                    // end before we swap the contents back out from under it. Invisible
                    // to the user — the paste has already happened by now.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        ClipboardHistoryStore.shared.suppressNextChange()
                        restorePasteboard(previousClipboard)
                    }
                }
            }
        }
    }

    /// Runs `body` as soon as `app` is the frontmost application (checking every 10ms),
    /// or at `deadline` regardless, so a slow-to-activate app can't hang the paste.
    private static func whenFrontmost(_ app: NSRunningApplication?, deadline: Date, _ body: @escaping () -> Void) {
        guard let app, NSWorkspace.shared.frontmostApplication != app, Date() < deadline else {
            body()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            whenFrontmost(app, deadline: deadline, body)
        }
    }

    private static func postCommandV() {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true) // V
        keyDown?.flags = [.maskCommand]
        keyDown?.post(tap: .cghidEventTap)

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyUp?.flags = [.maskCommand]
        keyUp?.post(tap: .cghidEventTap)
    }

    /// Copies every item/type currently on the general pasteboard so it can be restored
    /// later — `NSPasteboardItem` doesn't let you hold onto a live reference to what's
    /// already there (the system pasteboard can invalidate it), so each item is copied
    /// into a fresh one holding the same data under the same types.
    ///
    /// `dyn.*` types are skipped: they're conversions the system derives on demand from
    /// the item's real types, and asking for each one makes the source app render yet
    /// another copy of its content — the slow part of snapshotting a big image or rich
    /// text. Restoring the real types brings those conversions back automatically.
    private static func snapshotPasteboard() -> [NSPasteboardItem] {
        guard let items = NSPasteboard.general.pasteboardItems else { return [] }
        return items.map { item in
            let copy = NSPasteboardItem()
            for type in item.types where !type.rawValue.hasPrefix("dyn.") {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        }
    }

    private static func restorePasteboard(_ items: [NSPasteboardItem]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        pasteboard.writeObjects(items)
    }

    /// Puts plain text on the clipboard — emoji, or a text entry from clipboard history.
    static func copyText(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    static func copyEmoji(_ emoji: String) { copyText(emoji) }

    /// Puts raw data on the clipboard under a single type — used for restoring an image
    /// entry from clipboard history exactly as it was captured.
    static func copyRaw(data: Data, type: NSPasteboard.PasteboardType) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(data, forType: type)
    }

    /// Puts a sticker image/GIF file on the clipboard with multiple representations, so
    /// whatever the target app prefers to accept on paste is available: the raw file
    /// bytes under the file's own type (so apps that support pasting animated GIFs, e.g.
    /// Messages, keep the animation instead of freezing on one frame), a flattened
    /// bitmap for apps that only accept TIFF, and the file's own URL for apps that treat
    /// a paste as attaching a file.
    ///
    /// The TIFF is built from the first frame only. `NSImage.tiffRepresentation` on an
    /// animated GIF encodes *every* frame uncompressed — easily tens of megabytes, and
    /// the main reason pasting a sticker used to lag.
    static func copySticker(fileURL: URL) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        if let data = try? Data(contentsOf: fileURL) {
            if let type = UTType(filenameExtension: fileURL.pathExtension), type.conforms(to: .image) {
                pasteboard.setData(data, forType: NSPasteboard.PasteboardType(type.identifier))
            }
            if let source = CGImageSourceCreateWithData(data as CFData, nil),
               let firstFrame = CGImageSourceCreateImageAtIndex(source, 0, nil),
               let tiff = NSBitmapImageRep(cgImage: firstFrame).tiffRepresentation {
                pasteboard.setData(tiff, forType: .tiff)
            }
        }
        pasteboard.setString(fileURL.absoluteString, forType: .fileURL)
    }
}
