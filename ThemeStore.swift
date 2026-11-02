import SwiftUI
import AppKit
import Combine

/// A color stored as plain sRGB components, since SwiftUI's `Color` isn't `Codable`.
struct ThemeColor: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// Returns `nil` for a color with no sRGB equivalent, such as a pattern color.
    init?(_ nsColor: NSColor) {
        guard let srgb = nsColor.usingColorSpace(.sRGB) else { return nil }
        self.init(red: srgb.redComponent, green: srgb.greenComponent, blue: srgb.blueComponent)
    }

    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue)
    }
}

enum ThemeAppearance: String, Codable, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "Auto"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    /// `nil` tells AppKit to follow the system-wide light/dark setting.
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

struct Theme: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var appearance: ThemeAppearance
    /// `nil` uses the accent color chosen in System Settings.
    var accent: ThemeColor?
    /// Tinted over the launcher's material; `nil` leaves the plain material showing.
    var background: ThemeColor?
    /// How strongly `background` covers the material: 0 is invisible, 1 is fully solid.
    var backgroundOpacity: Double = 0.85

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }
}

/// Holds the built-in and user-created themes, and which one is active. Selecting a theme
/// in Settings is what activates it, so there's no separate "apply" step to get out of sync.
final class ThemeStore: ObservableObject {
    static let shared = ThemeStore()

    /// The theme used on a fresh install, and whenever the active theme is deleted. Matches
    /// how ReFlow looked before themes existed.
    static let defaultTheme = Theme(
        id: UUID(uuidString: "5F0A7E10-0000-4000-8000-000000000001")!,
        name: "System",
        appearance: .system
    )

    /// These IDs are persisted as the active theme, so they must never change.
    static let builtInThemes: [Theme] = [
        defaultTheme,
        Theme(
            id: UUID(uuidString: "5F0A7E10-0000-4000-8000-000000000002")!,
            name: "Midnight",
            appearance: .dark,
            accent: ThemeColor(red: 0.40, green: 0.60, blue: 1.00),
            background: ThemeColor(red: 0.06, green: 0.09, blue: 0.20)
        ),
        Theme(
            id: UUID(uuidString: "5F0A7E10-0000-4000-8000-000000000003")!,
            name: "Forest",
            appearance: .dark,
            accent: ThemeColor(red: 0.40, green: 0.80, blue: 0.50),
            background: ThemeColor(red: 0.06, green: 0.16, blue: 0.11)
        ),
        Theme(
            id: UUID(uuidString: "5F0A7E10-0000-4000-8000-000000000004")!,
            name: "Sunset",
            appearance: .dark,
            accent: ThemeColor(red: 1.00, green: 0.55, blue: 0.35),
            background: ThemeColor(red: 0.20, green: 0.08, blue: 0.16)
        ),
        Theme(
            id: UUID(uuidString: "5F0A7E10-0000-4000-8000-000000000005")!,
            name: "Paper",
            appearance: .light,
            accent: ThemeColor(red: 0.72, green: 0.38, blue: 0.16),
            background: ThemeColor(red: 0.97, green: 0.94, blue: 0.87)
        ),
    ]

    @Published private(set) var customThemes: [Theme]
    @Published private(set) var activeThemeID: UUID

    private static let customThemesDefaultsKey = "customThemes"
    private static let activeThemeDefaultsKey = "activeThemeID"

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.customThemesDefaultsKey),
           let decoded = try? JSONDecoder().decode([Theme].self, from: data) {
            customThemes = decoded
        } else {
            customThemes = []
        }
        activeThemeID = UserDefaults.standard.string(forKey: Self.activeThemeDefaultsKey)
            .flatMap(UUID.init(uuidString:)) ?? Self.defaultTheme.id
    }

    var activeTheme: Theme {
        Self.builtInThemes.first { $0.id == activeThemeID }
            ?? customThemes.first { $0.id == activeThemeID }
            ?? Self.defaultTheme
    }

    var accentColor: Color {
        activeTheme.accent?.color ?? .accentColor
    }

    var isActiveThemeBuiltIn: Bool {
        !customThemes.contains { $0.id == activeTheme.id }
    }

    func activate(_ id: UUID) {
        activeThemeID = id
        UserDefaults.standard.set(id.uuidString, forKey: Self.activeThemeDefaultsKey)
        applyAppearance()
    }

    /// Saves a copy of the active theme as a new custom theme and activates it, since
    /// that's the one the user is about to edit.
    func duplicateActiveTheme() {
        var copy = activeTheme
        copy.id = UUID()
        copy.name = "\(activeTheme.displayName) Copy"
        customThemes.append(copy)
        persist()
        activate(copy.id)
    }

    /// Replaces the custom theme with the same ID. Built-in themes can't be changed.
    func update(_ theme: Theme) {
        guard let index = customThemes.firstIndex(where: { $0.id == theme.id }) else { return }
        customThemes[index] = theme
        persist()
        if theme.id == activeThemeID {
            applyAppearance()
        }
    }

    func remove(_ id: UUID) {
        customThemes.removeAll { $0.id == id }
        persist()
        if id == activeThemeID {
            activate(Self.defaultTheme.id)
        }
    }

    /// Setting this on `NSApp` covers every window at once, including the launcher panel.
    func applyAppearance() {
        NSApp.appearance = activeTheme.appearance.nsAppearance
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(customThemes) {
            UserDefaults.standard.set(data, forKey: Self.customThemesDefaultsKey)
        }
    }
}

/// The launcher's backdrop for a given theme, shared with the preview in Settings so the
/// two can't drift apart.
struct ThemeBackground: View {
    let theme: Theme

    var body: some View {
        ZStack {
            Rectangle().fill(.regularMaterial)
            if let background = theme.background {
                background.color.opacity(theme.backgroundOpacity)
            }
        }
    }
}
