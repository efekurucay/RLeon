import AppKit
import Foundation

/// Persisted hotkey binding for push-to-talk.
///
/// Stored as two `UserDefaults` integers so the binding survives app restarts.
/// The default is the **Fn** key (keyCode 63, no modifier flags) which matches
/// the original hard-coded behaviour.
public struct HotkeyBinding: Equatable {
    /// `NSEvent.keyCode` of the trigger key (e.g. 63 = Fn, 49 = Space).
    public let keyCode: UInt16
    /// Required `NSEvent.ModifierFlags` (e.g. `.command`, `.option`, `.control`).
    public let modifiers: NSEvent.ModifierFlags

    public static let fnDefault = HotkeyBinding(keyCode: 63, modifiers: [])

    public var displayString: String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("^") }
        if modifiers.contains(.option)  { parts.append("⌥") }
        if modifiers.contains(.shift)   { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }
        if keyCode == 63 { parts.append("Fn") }
        else { parts.append("key(\(keyCode))") }
        return parts.joined()
    }
}

/// Reads and writes the active `HotkeyBinding` to `UserDefaults`.
enum HotkeySettings {
    static let keyCodeKey    = "rleonHotkeyKeyCode"
    static let modifiersKey  = "rleonHotkeyModifiers"

    static var current: HotkeyBinding {
        get {
            let ud = UserDefaults.standard
            guard ud.object(forKey: keyCodeKey) != nil else { return .fnDefault }
            let kc   = UInt16(ud.integer(forKey: keyCodeKey))
            let mods = NSEvent.ModifierFlags(rawValue: UInt(ud.integer(forKey: modifiersKey)))
            return HotkeyBinding(keyCode: kc, modifiers: mods)
        }
        set {
            let ud = UserDefaults.standard
            ud.set(Int(newValue.keyCode),              forKey: keyCodeKey)
            ud.set(Int(newValue.modifiers.rawValue),   forKey: modifiersKey)
        }
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: keyCodeKey)
        UserDefaults.standard.removeObject(forKey: modifiersKey)
    }
}
