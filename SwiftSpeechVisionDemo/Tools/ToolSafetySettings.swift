import Foundation

/// High-risk tools are **off** by default; the model cannot see or invoke them until enabled in Settings.
enum ToolSafetySettings {
    static let allowRunTerminalCommandKey = "rleonAllowRunTerminalCommand"
    static let allowTypeIntoFocusedFieldKey = "rleonAllowTypeIntoFocusedField"

    static var allowRunTerminalCommand: Bool {
        get { UserDefaults.standard.bool(forKey: allowRunTerminalCommandKey) }
        set { UserDefaults.standard.set(newValue, forKey: allowRunTerminalCommandKey) }
    }

    static var allowTypeIntoFocusedField: Bool {
        get { UserDefaults.standard.bool(forKey: allowTypeIntoFocusedFieldKey) }
        set { UserDefaults.standard.set(newValue, forKey: allowTypeIntoFocusedFieldKey) }
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
