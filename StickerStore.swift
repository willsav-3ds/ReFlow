import Foundation
import AppKit

/// A user-added custom image/GIF, searchable by name from the emoji picker alongside
/// built-in emoji, and pasted the same way (see `ClipboardPaste`).
struct Sticker: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    /// Filename within `StickerStore`'s own storage directory — not the original path
    /// the user added it from, since that file could later move or be deleted.
    var fileName: String
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

    /// Copies `sourceURL` into ReFlow's own storage under a fresh, collision-proof name
    /// (keeping the original extension, since that's how both `NSImage` and the pasteboard
    /// figure out whether something's a GIF) and adds it to the searchable list.
    @discardableResult
    func add(name: String, sourceURL: URL) -> Bool {
        let destinationFileName = UUID().uuidString + "." + sourceURL.pathExtension.lowercased()
        let destinationURL = storageDirectory.appendingPathComponent(destinationFileName)

        do {
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        } catch {
            print("ReFlow[stickers]: could not copy \(sourceURL.path) into sticker storage: \(error.localizedDescription)")
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
