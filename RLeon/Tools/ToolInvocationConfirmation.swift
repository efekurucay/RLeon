import AppKit
import Foundation

/// Modal confirmation for high-risk tool invocations (main thread / `runModal`).
enum ToolInvocationConfirmation {
    @MainActor
    static func confirmTerminalCommand(_ command: String) -> Bool {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = Self.truncateForAlert(trimmed, limit: 4000)
        let alert = NSAlert()
        alert.messageText = "Run this command in Terminal?"
        alert.informativeText = body.isEmpty ? "(empty command)" : body
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Run")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    @MainActor
    static func confirmTypeIntoFocusedField(_ text: String) -> Bool {
        let body = Self.truncateForAlert(text, limit: 2000)
        let alert = NSAlert()
        alert.messageText = "Type this text into the focused field?"
        alert.informativeText = body.isEmpty ? "(empty text)" : body
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Type")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private static func truncateForAlert(_ s: String, limit: Int) -> String {
        guard s.count > limit else { return s }
        let idx = s.index(s.startIndex, offsetBy: limit, limitedBy: s.endIndex) ?? s.endIndex
        return String(s[..<idx]) + "\n\n… (\(s.count) characters total — truncated for display)"
    }
}
