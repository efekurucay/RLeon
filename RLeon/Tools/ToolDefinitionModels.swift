import Foundation

// MARK: - Codable models for OpenAI-compatible tool definitions

/// A single property inside a tool's parameter schema.
struct ToolProperty: Codable, Equatable {
    let type: String
    let description: String

    enum CodingKeys: String, CodingKey {
        case type, description
    }
}

/// JSON Schema for a tool's parameters object.
struct ToolParameters: Codable, Equatable {
    let type: String
    let properties: [String: ToolProperty]
    let required: [String]

    init(properties: [String: ToolProperty] = [:], required: [String] = []) {
        self.type = "object"
        self.properties = properties
        self.required = required
    }
}

/// The `function` block sent inside a tool definition.
struct ToolFunction: Codable, Equatable {
    let name: String
    let description: String
    let parameters: ToolParameters
}

/// Top-level tool definition entry (`type: "function"`).
struct ToolDefinition: Codable, Equatable {
    let type: String
    let function: ToolFunction

    init(function: ToolFunction) {
        self.type = "function"
        self.function = function
    }

    /// Convert to the `[String: Any]` format that legacy code and Ollama serialization expect.
    func asDictionary() -> [String: Any] {
        guard let data = try? JSONEncoder().encode(self),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return obj
    }
}

// MARK: - Built-in tool catalogue

/// Single source of truth for all built-in tool schemas.
/// OllamaToolCalling.allToolDefinitionsUnfiltered() reads from here.
enum BuiltInToolDefinitions {

    static let all: [ToolDefinition] = [
        .init(function: .init(
            name: "copy_to_clipboard",
            description: LocalToolStore.referenceModelDescription(for: "copy_to_clipboard"),
            parameters: .init(
                properties: [
                    "text": .init(type: "string", description: "Text to place on the pasteboard."),
                ],
                required: ["text"]
            )
        )),
        .init(function: .init(
            name: "get_app_info",
            description: LocalToolStore.referenceModelDescription(for: "get_app_info"),
            parameters: .init()
        )),
        .init(function: .init(
            name: "open_application",
            description: LocalToolStore.referenceModelDescription(for: "open_application"),
            parameters: .init(
                properties: [
                    "name": .init(type: "string", description: "Application name without .app, e.g. Safari, Notes, Calendar."),
                    "bundle_id": .init(type: "string", description: "Cocoa bundle identifier, e.g. com.apple.Safari. Takes precedence over name when set."),
                ],
                required: []
            )
        )),
        .init(function: .init(
            name: "open_url",
            description: LocalToolStore.referenceModelDescription(for: "open_url"),
            parameters: .init(
                properties: [
                    "url": .init(type: "string", description: "Full URL or hostname (e.g. https://example.com or apple.com)."),
                    "browser": .init(type: "string", description: "\"safari\" or \"default\" (default browser)."),
                ],
                required: ["url"]
            )
        )),
        .init(function: .init(
            name: "whatsapp_compose",
            description: LocalToolStore.referenceModelDescription(for: "whatsapp_compose"),
            parameters: .init(
                properties: [
                    "text": .init(type: "string", description: "Optional prefilled message text."),
                    "phone": .init(type: "string", description: "Digits only with country code (e.g. 14155552671)."),
                ],
                required: []
            )
        )),
        .init(function: .init(
            name: "run_terminal_command",
            description: LocalToolStore.referenceModelDescription(for: "run_terminal_command"),
            parameters: .init(
                properties: [
                    "command": .init(type: "string", description: "Shell command to run (e.g. ls -la, cd ~/Desktop && pwd)."),
                ],
                required: ["command"]
            )
        )),
        .init(function: .init(
            name: "type_into_focused_field",
            description: LocalToolStore.referenceModelDescription(for: "type_into_focused_field"),
            parameters: .init(
                properties: [
                    "text": .init(type: "string", description: "Text to type (any Unicode)."),
                ],
                required: ["text"]
            )
        )),
    ]
}
