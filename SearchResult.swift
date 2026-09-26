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
    let action: () -> Void
    
    init(title: String, subtitle: String? = nil, type: ResultType, icon: NSImage? = nil, systemIcon: String? = nil, emoji: String? = nil, relevance: Double, action: @escaping () -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.type = type
        self.icon = icon
        self.systemIcon = systemIcon
        self.emoji = emoji
        self.relevance = relevance
        self.action = action
    }
    
    func execute() {
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
    
    var displayName: String {
        switch self {
        case .application: return "App"
        case .file: return "File"
        case .script: return "Script"
        case .command: return "Command"
        case .windowAction: return "Window"
        case .emoji: return "Emoji"
        }
    }
}

