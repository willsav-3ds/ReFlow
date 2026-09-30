import Foundation
import AppKit

struct SearchResult: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String?
    let type: ResultType
    var icon: NSImage?
    var systemIcon: String?
    var emoji: String?
    let relevance: Double
    let fileURL: URL?
    /// Stable identity used to persist a usage-based ranking boost (app/file path, or an
    /// emoji character). `nil` for one-off entries with no stable identity, like ad-hoc
    /// shell commands or the "File Search" mode-switch result.
    let rankingKey: String?
    let action: () -> Void

    init(title: String, subtitle: String? = nil, type: ResultType, icon: NSImage? = nil, systemIcon: String? = nil, emoji: String? = nil, relevance: Double, fileURL: URL? = nil, rankingKey: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.type = type
        self.icon = icon
        self.systemIcon = systemIcon
        self.emoji = emoji
        self.relevance = relevance
        self.fileURL = fileURL
        self.rankingKey = rankingKey
        self.action = action
    }

    func execute() {
        if let rankingKey {
            RankingStore.shared.recordUse(rankingKey)
        }
        action()
    }
}

enum ResultType {
    case application
    case file
    case script
    case command
    case windowAction
    case emoji
    case sticker
    case quickLink
    case clipboardHistory
    case calculator

    var displayName: String {
        switch self {
        case .application: return "App"
        case .file: return "File"
        case .script: return "Script"
        case .command: return "Command"
        case .windowAction: return "Window"
        case .emoji: return "Emoji"
        case .sticker: return "Sticker"
        case .quickLink: return "Quick Link"
        case .clipboardHistory: return "Clipboard"
        case .calculator: return "Calculator"
        }
    }
}

