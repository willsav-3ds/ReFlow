import AppKit
import Carbon.HIToolbox
import Combine

/// A single key + modifier combination that can be assigned to a `ShortcutAction`.
///
/// Equality/hashing are based on `keyCode` + the masked `modifierFlags`, not the raw
/// stored bits: arrow keys (and some others) set `.numericPad` as part of their real
/// `NSEvent.modifierFlags`, so a binding *recorded* from a keypress can carry that extra
/// bit while one built programmatically (e.g. `defaultBinding`) never does. Carbon's
/// `RegisterEventHotKey` only ever looks at control/option/shift/command — comparing the
/// raw bits directly let two Carbon-identical bindings look "different" to Swift,
/// silently breaking conflict detection.
struct KeyBinding: Codable {
    var keyCode: UInt16
    private var rawModifiers: UInt

    private static let relevantModifierMask: NSEvent.ModifierFlags = [.control, .option, .shift, .command]

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.rawModifiers = modifiers.rawValue
    }

    var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: rawModifiers).intersection(Self.relevantModifierMask)
    }

    func matches(_ event: NSEvent) -> Bool {
        event.keyCode == keyCode &&
            event.modifierFlags.intersection(Self.relevantModifierMask) == modifierFlags
    }

    var carbonModifiers: UInt32 {
        let flags = modifierFlags
        var carbon: UInt32 = 0
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        return carbon
    }

    var displayString: String {
        let flags = modifierFlags
        var s = ""
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option) { s += "⌥" }
        if flags.contains(.shift) { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        s += KeyBinding.keyNames[keyCode] ?? "Key\(keyCode)"
        return s
    }

    static let keyNames: [UInt16: String] = [
        49: "Space", 36: "⏎", 51: "⌫", 53: "⎋", 48: "⇥",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H",
        34: "I", 38: "J", 40: "K", 37: "L", 46: "M", 45: "N", 31: "O", 35: "P",
        12: "Q", 15: "R", 1: "S", 17: "T", 32: "U", 9: "V", 13: "W", 7: "X",
        16: "Y", 6: "Z",
        18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
        43: ",", 47: ".", 44: "/", 41: ";", 39: "'", 33: "[", 30: "]", 42: "\\", 50: "`", 27: "-", 24: "="
    ]
}

extension KeyBinding: Equatable {
    static func == (lhs: KeyBinding, rhs: KeyBinding) -> Bool {
        lhs.keyCode == rhs.keyCode && lhs.modifierFlags == rhs.modifierFlags
    }
}

extension KeyBinding: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(keyCode)
        hasher.combine(modifierFlags.rawValue)
    }
}

enum ShortcutScope {
    case global
    case launcher
}

/// Every user-triggerable action in ReFlow that can be bound to a key combination.
enum ShortcutAction: String, CaseIterable, Codable {
    case toggleLauncher
    case windowLeftHalf
    case windowRightHalf
    case windowTopHalf
    case windowBottomHalf
    case windowMaximize
    case windowRestore
    case cornerTopLeft
    case cornerTopRight
    case cornerBottomLeft
    case cornerBottomRight
    case windowLeftThird
    case windowCenterThird
    case windowRightThird
    case windowLeftTwoThirds
    case windowRightTwoThirds
    case displayPrevious
    case displayNext
    case toggleEmojiMode
    case trashTopResult
    case moveTopResult
    case showInFinderTopResult
    case openSettings

    var scope: ShortcutScope {
        switch self {
        case .trashTopResult, .moveTopResult, .showInFinderTopResult, .openSettings:
            return .launcher
        default:
            // .toggleEmojiMode is global rather than launcher-scoped (unlike its
            // siblings above): it needs to work — and take over the system's own
            // Character Viewer shortcut — even when the launcher isn't already open,
            // not just while browsing an already-open one.
            return .global
        }
    }

    var section: String {
        switch self {
        case .toggleLauncher:
            return "General"
        case .windowLeftHalf, .windowRightHalf, .windowTopHalf, .windowBottomHalf,
             .windowMaximize, .windowRestore:
            return "Halves & Maximize"
        case .cornerTopLeft, .cornerTopRight, .cornerBottomLeft, .cornerBottomRight:
            return "Corners"
        case .windowLeftThird, .windowCenterThird, .windowRightThird,
             .windowLeftTwoThirds, .windowRightTwoThirds:
            return "Thirds"
        case .displayPrevious, .displayNext:
            return "Displays"
        case .toggleEmojiMode, .trashTopResult, .moveTopResult, .showInFinderTopResult, .openSettings:
            return "Launcher"
        }
    }

    var displayName: String {
        switch self {
        case .toggleLauncher: return "Toggle Launcher"
        case .windowLeftHalf: return "Snap Window Left"
        case .windowRightHalf: return "Snap Window Right"
        case .windowTopHalf: return "Snap Window Top"
        case .windowBottomHalf: return "Snap Window Bottom"
        case .windowMaximize: return "Maximize Window"
        case .windowRestore: return "Center Window"
        case .cornerTopLeft: return "Snap Window Top Left"
        case .cornerTopRight: return "Snap Window Top Right"
        case .cornerBottomLeft: return "Snap Window Bottom Left"
        case .cornerBottomRight: return "Snap Window Bottom Right"
        case .windowLeftThird: return "Snap Window Left Third"
        case .windowCenterThird: return "Snap Window Center Third"
        case .windowRightThird: return "Snap Window Right Third"
        case .windowLeftTwoThirds: return "Snap Window Left Two-Thirds"
        case .windowRightTwoThirds: return "Snap Window Right Two-Thirds"
        case .displayPrevious: return "Move Window to Previous Display"
        case .displayNext: return "Move Window to Next Display"
        case .toggleEmojiMode: return "Toggle Emoji Search"
        case .trashTopResult: return "Move Top Result to Trash"
        case .moveTopResult: return "Move Top Result to…"
        case .showInFinderTopResult: return "Show Top Result in Finder"
        case .openSettings: return "Open Settings"
        }
    }

    var defaultBinding: KeyBinding {
        switch self {
        case .toggleLauncher: return KeyBinding(keyCode: 49, modifiers: [.command]) // Space
        // Magnet's default scheme: plain Control+Option for all tiling actions.
        case .windowLeftHalf: return KeyBinding(keyCode: 123, modifiers: [.control, .option]) // Left
        case .windowRightHalf: return KeyBinding(keyCode: 124, modifiers: [.control, .option]) // Right
        case .windowTopHalf: return KeyBinding(keyCode: 126, modifiers: [.control, .option]) // Up
        case .windowBottomHalf: return KeyBinding(keyCode: 125, modifiers: [.control, .option]) // Down
        case .windowMaximize: return KeyBinding(keyCode: 36, modifiers: [.control, .option]) // Return
        case .windowRestore: return KeyBinding(keyCode: 8, modifiers: [.control, .option]) // C (Center)
        case .cornerTopLeft: return KeyBinding(keyCode: 32, modifiers: [.control, .option]) // U
        case .cornerTopRight: return KeyBinding(keyCode: 34, modifiers: [.control, .option]) // I
        case .cornerBottomLeft: return KeyBinding(keyCode: 38, modifiers: [.control, .option]) // J
        case .cornerBottomRight: return KeyBinding(keyCode: 40, modifiers: [.control, .option]) // K
        case .windowLeftThird: return KeyBinding(keyCode: 2, modifiers: [.control, .option]) // D
        case .windowCenterThird: return KeyBinding(keyCode: 3, modifiers: [.control, .option]) // F
        case .windowRightThird: return KeyBinding(keyCode: 5, modifiers: [.control, .option]) // G
        case .windowLeftTwoThirds: return KeyBinding(keyCode: 14, modifiers: [.control, .option]) // E
        case .windowRightTwoThirds: return KeyBinding(keyCode: 17, modifiers: [.control, .option]) // T
        case .displayPrevious: return KeyBinding(keyCode: 123, modifiers: [.control, .option, .command]) // Left
        case .displayNext: return KeyBinding(keyCode: 124, modifiers: [.control, .option, .command]) // Right
        case .toggleEmojiMode: return KeyBinding(keyCode: 49, modifiers: [.control, .command]) // Space
        case .trashTopResult: return KeyBinding(keyCode: 51, modifiers: [.command]) // Delete
        case .moveTopResult: return KeyBinding(keyCode: 46, modifiers: [.command]) // M
        case .showInFinderTopResult: return KeyBinding(keyCode: 15, modifiers: [.command, .shift]) // R
        case .openSettings: return KeyBinding(keyCode: 43, modifiers: [.command]) // Comma
        }
    }
}

/// Persists user-customized key bindings and resolves key events to actions.
final class ShortcutStore: ObservableObject {
    static let shared = ShortcutStore()

    @Published private(set) var bindings: [ShortcutAction: KeyBinding]

    /// Called after any binding changes, so global hotkeys can be re-registered.
    var onChange: (() -> Void)?

    private static let defaultsKey = "shortcutBindings"

    private init() {
        var saved: [String: KeyBinding] = [:]
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode([String: KeyBinding].self, from: data) {
            saved = decoded
        }

        // Self-heal stale persisted bindings: if an earlier default scheme (or a past
        // recording) left two actions in the same scope pointing at the same combo,
        // registering the second one as a Carbon hotkey fails silently later — so any
        // conflict found here falls back to that action's current default instead.
        var result: [ShortcutAction: KeyBinding] = [:]
        var claimed: [ShortcutScope: Set<KeyBinding>] = [:]
        for action in ShortcutAction.allCases {
            let candidate = saved[action.rawValue] ?? action.defaultBinding
            let binding = claimed[action.scope]?.contains(candidate) == true ? action.defaultBinding : candidate
            result[action] = binding
            claimed[action.scope, default: []].insert(binding)
        }
        self.bindings = result
        persist()
    }

    func binding(for action: ShortcutAction) -> KeyBinding {
        bindings[action] ?? action.defaultBinding
    }

    /// Returns the action already using `binding` within the same scope, if any.
    func conflictingAction(for binding: KeyBinding, excluding action: ShortcutAction) -> ShortcutAction? {
        bindings.first { $0.key != action && $0.key.scope == action.scope && $0.value == binding }?.key
    }

    /// Assigns `binding` to `action`. Returns the conflicting action and leaves bindings
    /// unchanged if another action in the same scope already uses that combination.
    @discardableResult
    func set(_ binding: KeyBinding, for action: ShortcutAction) -> ShortcutAction? {
        if let conflict = conflictingAction(for: binding, excluding: action) {
            return conflict
        }
        bindings[action] = binding
        persist()
        onChange?()
        return nil
    }

    func reset(_ action: ShortcutAction) {
        bindings[action] = action.defaultBinding
        persist()
        onChange?()
    }

    func resetAll() {
        for action in ShortcutAction.allCases {
            bindings[action] = action.defaultBinding
        }
        persist()
        onChange?()
    }

    func action(matching event: NSEvent, scope: ShortcutScope) -> ShortcutAction? {
        for (action, binding) in bindings where action.scope == scope {
            if binding.matches(event) {
                return action
            }
        }
        return nil
    }

    private func persist() {
        let dict = Dictionary(uniqueKeysWithValues: bindings.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(dict) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}

/// Registers every global-scope `ShortcutAction` as a system-wide Carbon hotkey.
/// Carbon hotkeys work from within the App Sandbox and consume the key combination,
/// unlike `NSEvent` global monitors which only observe and can't stop other apps from seeing it.
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    var handler: ((ShortcutAction) -> Void)?

    private var hotKeyRefs: [ShortcutAction: EventHotKeyRef] = [:]
    private var idToAction: [UInt32: ShortcutAction] = [:]
    private var eventHandler: EventHandlerRef?

    /// How many global hotkeys are currently live with the OS — for the debug stats
    /// window only. Can be less than the number of global-scope actions if any failed
    /// to register (see the `print` in `registerAll` below).
    var registeredCount: Int { hotKeyRefs.count }

    private static let signature: FourCharCode = {
        var result: FourCharCode = 0
        for byte in "RFLW".utf8 { result = (result << 8) + FourCharCode(byte) }
        return result
    }()

    private init() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), reflowHotKeyHandler, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
    }

    func registerAll() {
        unregisterAll()
        var nextID: UInt32 = 1
        for action in ShortcutAction.allCases where action.scope == .global {
            let binding = ShortcutStore.shared.binding(for: action)
            let hotKeyID = EventHotKeyID(signature: Self.signature, id: nextID)
            var hotKeyRef: EventHotKeyRef?
            let status = RegisterEventHotKey(
                UInt32(binding.keyCode),
                binding.carbonModifiers,
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &hotKeyRef
            )
            if status == noErr, let ref = hotKeyRef {
                hotKeyRefs[action] = ref
                idToAction[nextID] = action
                nextID += 1
            } else {
                print("ReFlow[hotkeys]: FAILED to register \(action.rawValue) (\(binding.displayString)), OSStatus=\(status)")
            }
        }
        print("ReFlow[hotkeys]: registered \(hotKeyRefs.count)/\(ShortcutAction.allCases.filter { $0.scope == .global }.count) global hotkeys.")
    }

    func unregisterAll() {
        for (_, ref) in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
        idToAction.removeAll()
    }

    fileprivate func handleHotKey(id: UInt32) {
        guard let action = idToAction[id] else { return }
        handler?(action)
    }
}

private func reflowHotKeyHandler(_ nextHandler: EventHandlerCallRef?, _ event: EventRef?, _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event = event, let userData = userData else { return noErr }
    var hotKeyID = EventHotKeyID()
    GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
    Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue().handleHotKey(id: hotKeyID.id)
    return noErr
}
