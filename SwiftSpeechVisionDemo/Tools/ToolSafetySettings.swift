import Foundation

/// High-risk tools are **off** by default; the model cannot see or invoke them until enabled in Settings.
enum ToolSafetySettings {
    static let allowRunTerminalCommandKey = "rleonAllowRunTerminalCommand"
    static let allowTypeIntoFocusedFieldKey = "rleonAllowTypeIntoFocusedField"
    /// When `true` (default), each `run_terminal_command` shows a confirmation dialog with the command text.
    static let askBeforeEachTerminalCommandKey = "rleonAskBeforeEachTerminalCommand"
    /// When `true` (default), each `type_into_focused_field` asks before inserting.
    static let askBeforeEachTypeIntoFocusedFieldKey = "rleonAskBeforeEachTypeIntoFocusedField"

    static var allowRunTerminalCommand: Bool {
        get { UserDefaults.standard.bool(forKey: allowRunTerminalCommandKey) }
        set { UserDefaults.standard.set(newValue, forKey: allowRunTerminalCommandKey) }
    }

    static var allowTypeIntoFocusedField: Bool {
        get { UserDefaults.standard.bool(forKey: allowTypeIntoFocusedFieldKey) }
        set { UserDefaults.standard.set(newValue, forKey: allowTypeIntoFocusedFieldKey) }
    }

    /// Default **true** when unset — ask every time unless the user opts out.
    static var askBeforeEachTerminalCommand: Bool {
        get {
            if UserDefaults.standard.object(forKey: askBeforeEachTerminalCommandKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: askBeforeEachTerminalCommandKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: askBeforeEachTerminalCommandKey) }
    }

    /// Default **true** when unset.
    static var askBeforeEachTypeIntoFocusedField: Bool {
        get {
            if UserDefaults.standard.object(forKey: askBeforeEachTypeIntoFocusedFieldKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: askBeforeEachTypeIntoFocusedFieldKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: askBeforeEachTypeIntoFocusedFieldKey) }
    }

    static func isExposedToModel(toolId: String) -> Bool {
        switch toolId {
        case "run_terminal_command":
            return allowRunTerminalCommand
        case "type_into_focused_field":
            return allowTypeIntoFocusedField
        default:
            return true
        }
    }
}
