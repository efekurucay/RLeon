import Foundation

/// Per-tool user customization (title, subtitle, model-facing description).
struct ToolProfile: Codable, Equatable {
    var isEnabled: Bool = true
    var customTitle: String?
    var customSubtitle: String?
    /// Ollama `function.description`; empty means use the app default.
    var customDescription: String?
}

struct ToolRegistryState: Codable, Equatable {
    /// Display order; IDs must come from `LocalToolStore.allToolIds`.
    var orderedIds: [String]
    var profiles: [String: ToolProfile]
}
