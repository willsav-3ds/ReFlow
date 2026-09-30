import Foundation
import AppKit
import Combine

/// A user-defined shortcut to a file, folder, or URL, searchable by name from the launcher.
struct QuickLink: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var target: String
}

final class QuickLinkStore: ObservableObject {
    static let shared = QuickLinkStore()

    @Published private(set) var links: [QuickLink]

    private static let defaultsKey = "quickLinks"

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode([QuickLink].self, from: data) {
            links = decoded
        } else {
            links = []
        }
    }

    func add(name: String, target: String) {
        links.append(QuickLink(name: name, target: target))
        persist()
    }

    func remove(_ link: QuickLink) {
        links.removeAll { $0.id == link.id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(links) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    /// Opens a quick link's target — an http(s) URL directly, or a `~`-expanded
    /// filesystem path (file, folder, or app) via NSWorkspace either way.
    static func open(_ target: String) {
        if let url = URL(string: target), let scheme = url.scheme, scheme.hasPrefix("http") {
            NSWorkspace.shared.open(url)
        } else {
            let expanded = (target as NSString).expandingTildeInPath
            NSWorkspace.shared.open(URL(fileURLWithPath: expanded))
        }
    }
}
