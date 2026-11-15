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

/// What sits behind the launcher's contents. Every option except `solid` lets the desktop
/// show through, blurred, to a different degree.
enum ThemeMaterial: String, Codable, CaseIterable, Identifiable {
    case ultraThin
    case thin
    case regular
    case thick
    case solid

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ultraThin: return "Clear Glass"
        case .thin: return "Light Blur"
        case .regular: return "Blur"
        case .thick: return "Heavy Blur"
        case .solid: return "Solid"
        }
    }
}

enum ThemeGradientDirection: String, Codable, CaseIterable, Identifiable {
    case vertical
    case horizontal
    case diagonal

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .vertical: return "Top to Bottom"
        case .horizontal: return "Left to Right"
        case .diagonal: return "Diagonal"
        }
    }

    var points: (start: UnitPoint, end: UnitPoint) {
        switch self {
        case .vertical: return (.top, .bottom)
        case .horizontal: return (.leading, .trailing)
        case .diagonal: return (.topLeading, .bottomTrailing)
        }
    }
}

enum ThemeFontDesign: String, Codable, CaseIterable, Identifiable {
    case standard
    case rounded
    case serif
    case monospaced

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard: return "Standard"
        case .rounded: return "Rounded"
        case .serif: return "Serif"
        case .monospaced: return "Monospaced"
        }
    }

    var design: Font.Design {
        switch self {
        case .standard: return .default
        case .rounded: return .rounded
        case .serif: return .serif
        case .monospaced: return .monospaced
        }
    }
}

/// How the selected (and hovered) result is marked.
enum ThemeSelectionStyle: String, Codable, CaseIterable, Identifiable {
    /// A tinted row with a bar down its leading edge — the original look.
    case bar
    /// A tinted, rounded highlight inset from the edges.
    case pill
    /// A rounded outline with no fill.
    case outline
    /// A rounded highlight in the full accent color, with the text switched to contrast.
    case filled

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bar: return "Bar"
        case .pill: return "Pill"
        case .outline: return "Outline"
        case .filled: return "Filled"
        }
    }
}

enum ThemeDensity: String, Codable, CaseIterable, Identifiable {
    case compact
    case regular
    case spacious

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .compact: return "Compact"
        case .regular: return "Regular"
        case .spacious: return "Spacious"
        }
    }

    var rowVerticalPadding: CGFloat {
        switch self {
        case .compact: return 4
        case .regular: return 8
        case .spacious: return 12
        }
    }

    var iconSize: CGFloat {
        switch self {
        case .compact: return 24
        case .regular: return 32
        case .spacious: return 40
        }
    }

    var titleFontSize: CGFloat {
        switch self {
        case .compact: return 13
        case .regular: return 14
        case .spacious: return 15
        }
    }

    var subtitleFontSize: CGFloat {
        switch self {
        case .compact: return 10
        case .regular: return 11
        case .spacious: return 12
        }
    }
}

/// Every property past `appearance` defaults to how ReFlow looked before it could be
/// changed, so a theme only has to mention what it does differently.
struct Theme: Encodable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var appearance: ThemeAppearance
    /// `nil` uses the accent color chosen in System Settings.
    var accent: ThemeColor?
    /// Tinted over the launcher's material; `nil` leaves the plain material showing.
    var background: ThemeColor?
    /// How strongly `background` covers the material: 0 is invisible, 1 is fully solid.
    var backgroundOpacity: Double = 0.85
    /// Set to fade `background` into a second color; `nil` keeps it flat.
    var backgroundEnd: ThemeColor?
    var gradientDirection: ThemeGradientDirection = .vertical
    var material: ThemeMaterial = .regular
    /// `nil` uses the standard text color for the theme's appearance.
    var text: ThemeColor?
    /// Drawn around the edge of the launcher; `nil` for no border.
    var border: ThemeColor?
    var borderWidth: Double = 1
    var cornerRadius: Double = 0
    var fontDesign: ThemeFontDesign = .standard
    var selectionStyle: ThemeSelectionStyle = .bar
    var density: ThemeDensity = .regular
    /// The "App", "File", … label at the trailing edge of each result.
    var showsTypeBadges = true
    /// The line between the search field and the results.
    var showsDivider = true

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }

    /// Text drawn directly on the accent color (the `filled` selection): black or white,
    /// whichever reads better against it.
    var onAccentColor: Color {
        guard let accent else { return .white }
        let luminance = 0.2126 * accent.red + 0.7152 * accent.green + 0.0722 * accent.blue
        return luminance > 0.6 ? .black : .white
    }
}

/// Decoded by hand so that themes saved by an earlier version, from before a property
/// existed, still load — the synthesized decoder would reject them over the missing key,
/// and the user's custom themes would be gone.
extension Theme: Decodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            name: try container.decode(String.self, forKey: .name),
            appearance: try container.decode(ThemeAppearance.self, forKey: .appearance)
        )

        func value<Value: Decodable>(_ key: CodingKeys, default defaultValue: Value) throws -> Value {
            try container.decodeIfPresent(Value.self, forKey: key) ?? defaultValue
        }

        id = try container.decode(UUID.self, forKey: .id)
        accent = try container.decodeIfPresent(ThemeColor.self, forKey: .accent)
        background = try container.decodeIfPresent(ThemeColor.self, forKey: .background)
        backgroundOpacity = try value(.backgroundOpacity, default: backgroundOpacity)
        backgroundEnd = try container.decodeIfPresent(ThemeColor.self, forKey: .backgroundEnd)
        gradientDirection = try value(.gradientDirection, default: gradientDirection)
        material = try value(.material, default: material)
        text = try container.decodeIfPresent(ThemeColor.self, forKey: .text)
        border = try container.decodeIfPresent(ThemeColor.self, forKey: .border)
        borderWidth = try value(.borderWidth, default: borderWidth)
        cornerRadius = try value(.cornerRadius, default: cornerRadius)
        fontDesign = try value(.fontDesign, default: fontDesign)
        selectionStyle = try value(.selectionStyle, default: selectionStyle)
        density = try value(.density, default: density)
        showsTypeBadges = try value(.showsTypeBadges, default: showsTypeBadges)
        showsDivider = try value(.showsDivider, default: showsDivider)
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
        Theme(
            id: UUID(uuidString: "5F0A7E10-0000-4000-8000-000000000006")!,
            name: "Glass",
            appearance: .system,
            material: .ultraThin,
            cornerRadius: 18,
            selectionStyle: .pill
        ),
        Theme(
            id: UUID(uuidString: "5F0A7E10-0000-4000-8000-000000000007")!,
            name: "Aurora",
            appearance: .dark,
            accent: ThemeColor(red: 0.45, green: 0.95, blue: 0.80),
            background: ThemeColor(red: 0.04, green: 0.22, blue: 0.26),
            backgroundOpacity: 0.8,
            backgroundEnd: ThemeColor(red: 0.24, green: 0.10, blue: 0.38),
            gradientDirection: .diagonal,
            material: .thin,
            cornerRadius: 16,
            selectionStyle: .pill
        ),
        Theme(
            id: UUID(uuidString: "5F0A7E10-0000-4000-8000-000000000008")!,
            name: "Neon",
            appearance: .dark,
            accent: ThemeColor(red: 1.00, green: 0.25, blue: 0.70),
            background: ThemeColor(red: 0.09, green: 0.02, blue: 0.14),
            backgroundOpacity: 0.92,
            backgroundEnd: ThemeColor(red: 0.02, green: 0.03, blue: 0.10),
            text: ThemeColor(red: 0.90, green: 0.95, blue: 1.00),
            border: ThemeColor(red: 0.20, green: 0.90, blue: 1.00),
            borderWidth: 1.5,
            cornerRadius: 12,
            selectionStyle: .outline
        ),
        Theme(
            id: UUID(uuidString: "5F0A7E10-0000-4000-8000-000000000009")!,
            name: "Terminal",
            appearance: .dark,
            accent: ThemeColor(red: 0.25, green: 1.00, blue: 0.45),
            background: ThemeColor(red: 0.02, green: 0.04, blue: 0.02),
            backgroundOpacity: 1,
            material: .solid,
            text: ThemeColor(red: 0.45, green: 1.00, blue: 0.55),
            border: ThemeColor(red: 0.25, green: 1.00, blue: 0.45),
            fontDesign: .monospaced,
            selectionStyle: .filled,
            density: .compact
        ),
        Theme(
            id: UUID(uuidString: "5F0A7E10-0000-4000-8000-00000000000A")!,
            name: "Graphite",
            appearance: .dark,
            accent: ThemeColor(red: 0.86, green: 0.86, blue: 0.88),
            background: ThemeColor(red: 0.12, green: 0.12, blue: 0.13),
            backgroundOpacity: 0.95,
            material: .thick,
            cornerRadius: 10,
            selectionStyle: .filled,
            density: .compact,
            showsDivider: false
        ),
        Theme(
            id: UUID(uuidString: "5F0A7E10-0000-4000-8000-00000000000B")!,
            name: "Blossom",
            appearance: .light,
            accent: ThemeColor(red: 0.90, green: 0.35, blue: 0.55),
            background: ThemeColor(red: 1.00, green: 0.90, blue: 0.93),
            backgroundOpacity: 0.9,
            backgroundEnd: ThemeColor(red: 0.93, green: 0.88, blue: 1.00),
            text: ThemeColor(red: 0.35, green: 0.14, blue: 0.25),
            cornerRadius: 22,
            fontDesign: .rounded,
            selectionStyle: .pill,
            density: .spacious
        ),
        Theme(
            id: UUID(uuidString: "5F0A7E10-0000-4000-8000-00000000000C")!,
            name: "Newsprint",
            appearance: .light,
            accent: ThemeColor(red: 0.10, green: 0.10, blue: 0.10),
            background: ThemeColor(red: 0.96, green: 0.95, blue: 0.91),
            backgroundOpacity: 1,
            material: .solid,
            text: ThemeColor(red: 0.10, green: 0.10, blue: 0.10),
            border: ThemeColor(red: 0.10, green: 0.10, blue: 0.10),
            cornerRadius: 2,
            fontDesign: .serif,
            selectionStyle: .outline,
            showsTypeBadges: false
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
            switch theme.material {
            case .ultraThin: Rectangle().fill(.ultraThinMaterial)
            case .thin: Rectangle().fill(.thinMaterial)
            case .regular: Rectangle().fill(.regularMaterial)
            case .thick: Rectangle().fill(.thickMaterial)
            case .solid: Color(nsColor: .windowBackgroundColor)
            }
            if let background = theme.background {
                if let end = theme.backgroundEnd {
                    LinearGradient(
                        colors: [background.color, end.color],
                        startPoint: theme.gradientDirection.points.start,
                        endPoint: theme.gradientDirection.points.end
                    )
                    .opacity(theme.backgroundOpacity)
                } else {
                    background.color.opacity(theme.backgroundOpacity)
                }
            }
        }
    }
}

/// Everything a theme does to the launcher as a whole: backdrop, text color and typeface,
/// tint, rounded corners, border. Also what the preview in Settings is wrapped in, with
/// `scale` shrinking the corner radius to suit its smaller size.
private struct ThemedSurface: ViewModifier {
    let theme: Theme
    let accent: Color
    let scale: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: theme.cornerRadius * scale, style: .continuous)
        textColored(content)
            .fontDesign(theme.fontDesign.design)
            .tint(accent)
            .background(ThemeBackground(theme: theme))
            .clipShape(shape)
            .overlay {
                if let border = theme.border {
                    shape.strokeBorder(border.color, lineWidth: theme.borderWidth)
                }
            }
    }

    // Left untouched without a custom color, rather than set to `.primary`, so the
    // standard themes render exactly as they did before text color was an option.
    @ViewBuilder
    private func textColored(_ content: Content) -> some View {
        if let text = theme.text {
            content.foregroundStyle(text.color)
        } else {
            content
        }
    }
}

/// How a theme marks a result as selected or hovered.
private struct ThemedRowHighlight: ViewModifier {
    let theme: Theme
    let accent: Color
    let isSelected: Bool
    let isHovering: Bool

    func body(content: Content) -> some View {
        switch theme.selectionStyle {
        case .bar:
            content
                .background(
                    isHovering ? accent.opacity(0.1) :
                    isSelected ? accent.opacity(0.15) : Color.clear
                )
                .overlay(alignment: .leading) {
                    if isSelected {
                        Rectangle()
                            .fill(accent)
                            .frame(width: 3)
                    }
                }
        case .pill:
            content.background {
                shape.fill(isSelected ? accent.opacity(0.22) : isHovering ? accent.opacity(0.1) : Color.clear)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
            }
        case .outline:
            content.background {
                ZStack {
                    shape.fill(isHovering ? accent.opacity(0.1) : Color.clear)
                    if isSelected {
                        shape.strokeBorder(accent, lineWidth: 1.5)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
            }
        case .filled:
            // The text has to switch to something readable on the accent color while the
            // row is selected, then back to the theme's own text color.
            content
                .foregroundStyle(isSelected ? theme.onAccentColor : theme.text?.color ?? .primary)
                .background {
                    shape.fill(isSelected ? accent : isHovering ? accent.opacity(0.12) : Color.clear)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                }
        }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
    }
}

extension View {
    func themedSurface(_ theme: Theme, accent: Color, scale: CGFloat = 1) -> some View {
        modifier(ThemedSurface(theme: theme, accent: accent, scale: scale))
    }

    func themedRowHighlight(_ theme: Theme, accent: Color, isSelected: Bool, isHovering: Bool) -> some View {
        modifier(ThemedRowHighlight(theme: theme, accent: accent, isSelected: isSelected, isHovering: isHovering))
    }
}
