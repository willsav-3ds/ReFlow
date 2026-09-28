import AppKit

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

        // Short delays after the launcher panel starts closing (triggered by the
        // caller's own result-execution flow, just before or right after this runs)
        // before reactivating the original app and simulating ⌘V — giving the window
        // server a moment to actually hand focus back avoids the paste landing nowhere,
        // or in ReFlow's own panel as it's disappearing.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            appToRestore?.activate()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                postCommandV()

                // Give the target app a moment to actually read the pasteboard on its
                // end before we swap the contents back out from under it.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    ClipboardHistoryStore.shared.suppressNextChange()
                    restorePasteboard(previousClipboard)
                }
            }
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
    private static func snapshotPasteboard() -> [NSPasteboardItem] {
        guard let items = NSPasteboard.general.pasteboardItems else { return [] }
        return items.map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
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
    /// whatever the target app prefers to accept on paste is available: the raw file data
    /// under its own animated-GIF type (so apps that support pasting animated GIFs, e.g.
    /// Messages, keep the animation instead of freezing on one frame), a flattened
    /// bitmap for apps that only accept image data, and the file's own URL for apps that
    /// treat a paste as attaching a file.
    static func copySticker(fileURL: URL) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        if let data = try? Data(contentsOf: fileURL) {
            if fileURL.pathExtension.lowercased() == "gif" {
                pasteboard.setData(data, forType: NSPasteboard.PasteboardType("com.compuserve.gif"))
            }
            if let image = NSImage(data: data), let tiff = image.tiffRepresentation {
                pasteboard.setData(tiff, forType: .tiff)
            }
        }
        pasteboard.setString(fileURL.absoluteString, forType: .fileURL)
    }
}
