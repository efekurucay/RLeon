import Combine
import Foundation

/// Centralised configuration store for every UserDefaults-backed preference.
///
/// Use `@EnvironmentObject var settings: AppSettings` in SwiftUI views instead of
/// scattering raw `UserDefaults.standard.string(forKey:"...")` calls throughout
/// the codebase.  All keys live here as `static let` constants so a typo produces
/// a compile-time error rather than a silent miss-default at runtime.
@MainActor
final class AppSettings: ObservableObject {

    // MARK: - UserDefaults keys (single source of truth)

    static let ollamaBaseURLKey          = "ollamaBaseURL"
    static let ollamaModelKey            = "ollamaModel"
    static let ollamaUseToolsKey         = "ollamaUseTools"
    static let systemPromptKey           = "rleonSystemPrompt"

    // ToolSafetySettings keys (mirrored here for centralised access)
    static let allowRunTerminalCommandKey        = ToolSafetySettings.allowRunTerminalCommandKey
    static let allowTypeIntoFocusedFieldKey      = ToolSafetySettings.allowTypeIntoFocusedFieldKey
    static let askBeforeEachTerminalCommandKey   = ToolSafetySettings.askBeforeEachTerminalCommandKey
    static let askBeforeEachTypeIntoFocusedFieldKey = ToolSafetySettings.askBeforeEachTypeIntoFocusedFieldKey

    // MARK: - Default values

    static let defaultBaseURL  = "http://127.0.0.1:11434"
    static let defaultModel    = "qwen2.5:7b"

    // MARK: - Published properties

    @Published var ollamaBaseURL: String {
        didSet { UserDefaults.standard.set(ollamaBaseURL, forKey: Self.ollamaBaseURLKey) }
    }

    @Published var ollamaModel: String {
        didSet { UserDefaults.standard.set(ollamaModel, forKey: Self.ollamaModelKey) }
    }

    @Published var ollamaUseTools: Bool {
        didSet { UserDefaults.standard.set(ollamaUseTools, forKey: Self.ollamaUseToolsKey) }
    }

    @Published var systemPrompt: String {
        didSet { UserDefaults.standard.set(systemPrompt, forKey: Self.systemPromptKey) }
    }

    @Published var allowRunTerminalCommand: Bool {
        didSet {
            UserDefaults.standard.set(allowRunTerminalCommand, forKey: Self.allowRunTerminalCommandKey)
            ToolSafetySettings.allowRunTerminalCommand = allowRunTerminalCommand
        }
    }

    @Published var allowTypeIntoFocusedField: Bool {
        didSet {
            UserDefaults.standard.set(allowTypeIntoFocusedField, forKey: Self.allowTypeIntoFocusedFieldKey)
            ToolSafetySettings.allowTypeIntoFocusedField = allowTypeIntoFocusedField
        }
    }

    @Published var askBeforeEachTerminalCommand: Bool {
        didSet {
            UserDefaults.standard.set(askBeforeEachTerminalCommand, forKey: Self.askBeforeEachTerminalCommandKey)
            ToolSafetySettings.askBeforeEachTerminalCommand = askBeforeEachTerminalCommand
        }
    }

    @Published var askBeforeEachTypeIntoFocusedField: Bool {
        didSet {
            UserDefaults.standard.set(askBeforeEachTypeIntoFocusedField, forKey: Self.askBeforeEachTypeIntoFocusedFieldKey)
            ToolSafetySettings.askBeforeEachTypeIntoFocusedField = askBeforeEachTypeIntoFocusedField
        }
    }

    // MARK: - Init

    init() {
        let ud = UserDefaults.standard

        // Register defaults once (matches what RLeonApp.swift used to do inline).
        ud.register(defaults: [
            Self.ollamaBaseURLKey: Self.defaultBaseURL,
            Self.ollamaModelKey: Self.defaultModel,
            Self.ollamaUseToolsKey: false,
            Self.askBeforeEachTerminalCommandKey: true,
            Self.askBeforeEachTypeIntoFocusedFieldKey: true,
        ])

        ollamaBaseURL             = ud.string(forKey: Self.ollamaBaseURLKey) ?? Self.defaultBaseURL
        ollamaModel               = ud.string(forKey: Self.ollamaModelKey)   ?? Self.defaultModel
        ollamaUseTools            = ud.bool(forKey: Self.ollamaUseToolsKey)
        systemPrompt              = ud.string(forKey: Self.systemPromptKey)  ?? ""
        allowRunTerminalCommand   = ud.bool(forKey: Self.allowRunTerminalCommandKey)
        allowTypeIntoFocusedField = ud.bool(forKey: Self.allowTypeIntoFocusedFieldKey)
        askBeforeEachTerminalCommand      = ud.object(forKey: Self.askBeforeEachTerminalCommandKey) == nil
            ? true : ud.bool(forKey: Self.askBeforeEachTerminalCommandKey)
        askBeforeEachTypeIntoFocusedField = ud.object(forKey: Self.askBeforeEachTypeIntoFocusedFieldKey) == nil
            ? true : ud.bool(forKey: Self.askBeforeEachTypeIntoFocusedFieldKey)
    }

    // MARK: - Computed helpers

    /// Validated Ollama base URL; returns nil when the string is malformed.
    var validatedBaseURL: URL? {
        guard let u = URL(string: ollamaBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = u.scheme,
              scheme == "http" || scheme == "https"
        else { return nil }
        return u
    }
}
