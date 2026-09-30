import Foundation
import AppKit
import Combine

/// A user-added custom image/GIF, searchable by name from the emoji picker alongside
/// built-in emoji, and pasted the same way (see `ClipboardPaste`).
struct Sticker: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    /// Filename within `StickerStore`'s own storage directory — not the original path
    /// the user added it from, since that file could later move or be deleted.
    var fileName: String
}

extension NSImage {
    /// Flattens to PNG via `NSBitmapImageRep` — macOS's `NSImage`, unlike iOS's `UIImage`,
    /// has no built-in `pngData()`. Used to normalize whatever format a source app puts
    /// on the clipboard (HEIC, JPEG, etc.) into one predictable, widely-supported sticker
    /// format instead of storing it as-is.
    func pngData() -> Data? {
        guard let tiff = tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}

extension NSPasteboard {
    /// Everything `canReadObject`/`readObjects(forClasses: [NSImage.self])` misses: apps
    /// that copy an image wrapped in RTFD (rich text with an embedded attachment)
    /// instead of putting a bare image type on the pasteboard. Falls back to pulling the
    /// first embedded image out of the RTFD's attachments.
    ///
    /// Known gap: Messages' "Copy" on a photo bubble doesn't reliably produce an RTFD
    /// attachment this can extract an image from, even though the same clipboard
    /// contents paste as an image into apps like Notes — that path isn't supported yet.
    func readEmbeddedImage() -> NSImage? {
        if canReadObject(forClasses: [NSImage.self], options: nil),
           let images = readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let image = images.first {
            return image
        }

        // "Copy Image" from a webpage can leave the image under a pasteboard type
        // `NSImage.imageTypes` doesn't recognize (WEBP and other newer web formats
        // aren't in that static list) even though the raw bytes are right there and
        // ImageIO — which is what `NSImage(data:)` actually decodes through — handles
        // them fine. Trying every type actually present, instead of only the ones the
        // class-based reader above pre-approves, catches those.
        for type in types ?? [] {
            guard let data = data(forType: type), let image = NSImage(data: data) else { continue }
            return image
        }

        // A source that only wrote a file reference rather than embedding the bytes
        // directly still resolves to a real, already-materialized file most of the time.
        if let fileURL = pasteboardFileURL, let image = NSImage(contentsOf: fileURL) {
            return image
        }

        guard let rtfdData = data(forType: .rtfd),
              let attributed = NSAttributedString(rtfd: rtfdData, documentAttributes: nil) else {
            return nil
        }

        var foundImage: NSImage?
        attributed.enumerateAttribute(.attachment, in: NSRange(location: 0, length: attributed.length)) { value, _, stop in
            guard let attachment = value as? NSTextAttachment else { return }
            if let image = attachment.image {
                foundImage = image
                stop.pointee = true
            } else if let data = attachment.fileWrapper?.regularFileContents, let image = NSImage(data: data) {
                foundImage = image
                stop.pointee = true
            }
        }
        return foundImage
    }

    private var pasteboardFileURL: URL? {
        guard let items = pasteboardItems else { return nil }
        for item in items {
            if let urlString = item.string(forType: .fileURL), let url = URL(string: urlString) {
                return url
            }
        }
        return nil
    }
}

final class StickerStore: ObservableObject {
    static let shared = StickerStore()

    @Published private(set) var stickers: [Sticker]

    private static let defaultsKey = "stickers"

    /// Stickers are copied into Application Support rather than referenced by their
    /// original path, so a sticker keeps working even if the source file is later moved,
    /// renamed, or deleted — the same reasoning `QuickLinkStore` doesn't need (it only
    /// ever stores a path/URL, never owns a copy).
    private let storageDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = appSupport.appendingPathComponent("ReFlow/Stickers", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode([Sticker].self, from: data) {
            stickers = decoded
        } else {
            stickers = []
        }
    }

    func fileURL(for sticker: Sticker) -> URL {
        storageDirectory.appendingPathComponent(sticker.fileName)
    }

    /// Copies `sourceURL` into ReFlow's own storage and adds it to the searchable list.
    @discardableResult
    func add(name: String, sourceURL: URL) -> Bool {
        guard let data = try? Data(contentsOf: sourceURL) else {
            print("ReFlow[stickers]: could not read \(sourceURL.path).")
            return false
        }
        return add(name: name, data: data, fileExtension: sourceURL.pathExtension)
    }

    /// Writes raw image/GIF data (e.g. straight off the clipboard) into ReFlow's own
    /// storage under a fresh, collision-proof name and adds it to the searchable list.
    /// `fileExtension` matters beyond just the filename — it's how both `NSImage` and the
    /// pasteboard later figure out whether a given sticker is a GIF.
    @discardableResult
    func add(name: String, data: Data, fileExtension: String) -> Bool {
        let destinationFileName = UUID().uuidString + "." + fileExtension.lowercased()
        let destinationURL = storageDirectory.appendingPathComponent(destinationFileName)

        do {
            try data.write(to: destinationURL)
        } catch {
            print("ReFlow[stickers]: could not write sticker data into storage: \(error.localizedDescription)")
            return false
        }

        stickers.append(Sticker(name: name, fileName: destinationFileName))
        persist()
        return true
    }

    func remove(_ sticker: Sticker) {
        try? FileManager.default.removeItem(at: fileURL(for: sticker))
        stickers.removeAll { $0.id == sticker.id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(stickers) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}
