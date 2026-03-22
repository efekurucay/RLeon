import Foundation

/// Extension point to attach [Model Context Protocol (MCP)](https://modelcontextprotocol.io)-compatible tools
/// to the Ollama `tools` list.
///
/// **Official Swift SDK:** [github.com/modelcontextprotocol/swift-sdk](https://github.com/modelcontextprotocol/swift-sdk)  
/// Requires **Swift 6.0+ / Xcode 16+** to link the `MCP` product. Until then, this type stays a stub.
///
/// Intended wiring (from SDK docs): `Client` + `StdioTransport` or HTTP transport → `tools/list` → map each
/// MCP tool to OpenAI-style `function` entries → on `tool_calls`, `tools/call` with decoded arguments.
///
/// Prefer the `mcp_` prefix and names like `mcp_<serverSlug>_<toolName>` to avoid collisions with built-ins.
final class MCPToolBridge {
    static let shared = MCPToolBridge()

    /// `UserDefaults` key — when the MCP bridge is on, extra tools are merged into the model payload.
    private let enabledKey = "rleonMCPBridgeEnabled"

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// OpenAI-compatible `tools` entries. Empty until `tools/list` is implemented with swift-sdk.
    func openAIToolDefinitions() -> [[String: Any]] {
        guard isEnabled else { return [] }
        return []
    }

    /// If this is an MCP tool name, return a result; otherwise `nil` (built-in switch handles it).
    func executeIfNeeded(name: String, argumentsJSON: String) async -> String? {
        guard isEnabled, name.hasPrefix("mcp_") else { return nil }
        let parsed = MCPBridgeNaming.parse(toolId: name)
        // Future: resolve `parsed.serverSlug` to a live `Client`, dispatch `tools/call` with `argumentsJSON`.
        let argHint = argumentsJSON.prefix(200)
        return """
        MCP: not connected (tool: \(name)). \
        Parsed: server=\(parsed.serverSlug), tool=\(parsed.toolName). \
        Add swift-sdk (Xcode 16+), implement tools/list + tools/call. Args preview: \(argHint)
        """
    }
}

// MARK: - Naming

enum MCPBridgeNaming {
    /// Expects `mcp_<serverSlug>_<toolName>` with at least two underscores after `mcp`.
    static func parse(toolId: String) -> (serverSlug: String, toolName: String) {
        let without = toolId.dropFirst(4) // "mcp_"
        let parts = without.split(separator: "_", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else {
            return (serverSlug: "default", toolName: String(without))
        }
        return (serverSlug: String(parts[0]), toolName: String(parts[1]))
    }
}
