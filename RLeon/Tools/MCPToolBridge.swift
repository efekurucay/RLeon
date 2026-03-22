import Foundation

// MARK: - Server configuration model

/// Configuration for a single MCP server.
///
/// Supports two transport modes:
///  - **stdio**: `command` + optional `args` / `env` (local process)
///  - **HTTP/SSE**: `url` (remote server)
///
/// Persist via `MCPBridgeRegistry`.
public struct MCPServerConfig: Codable, Identifiable, Equatable {
    public var id: String           // user-chosen slug, e.g. "filesystem"
    public var displayName: String  // shown in Settings
    public var command: String?     // stdio: executable path
    public var args: [String]       // stdio: argv
    public var env: [String: String]// stdio: extra environment variables
    public var urlString: String?   // HTTP/SSE: base URL
    public var isEnabled: Bool

    public init(
        id: String,
        displayName: String,
        command: String? = nil,
        args: [String] = [],
        env: [String: String] = [:],
        urlString: String? = nil,
        isEnabled: Bool = true
    ) {
        self.id          = id
        self.displayName = displayName
        self.command     = command
        self.args        = args
        self.env         = env
        self.urlString   = urlString
        self.isEnabled   = isEnabled
    }

    public var transportDescription: String {
        if let url = urlString, !url.isEmpty { return "HTTP: \(url)" }
        if let cmd = command, !cmd.isEmpty   { return "stdio: \(cmd)" }
        return "(not configured)"
    }
}

// MARK: - Registry

/// Persists the list of MCP server configurations to UserDefaults.
enum MCPBridgeRegistry {
    private static let key = "rleonMCPServersJSON"

    static func load() -> [MCPServerConfig] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let servers = try? JSONDecoder().decode([MCPServerConfig].self, from: data)
        else { return [] }
        return servers
    }

    static func save(_ servers: [MCPServerConfig]) {
        guard let data = try? JSONEncoder().encode(servers) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

// MARK: - Bridge

/// Extension point to attach [Model Context Protocol](https://modelcontextprotocol.io)-compatible
/// tools to the Ollama `tools` list.
///
/// **Full client wiring** requires
/// [modelcontextprotocol/swift-sdk](https://github.com/modelcontextprotocol/swift-sdk)
/// (Swift 6 / Xcode 16+). Until then the transport layer is stubbed; server
/// configurations are persisted and displayed in Settings but tool calls return
/// an informative error instead of real results.
final class MCPToolBridge {
    static let shared = MCPToolBridge()

    // MARK: - Global enable/disable

    private let enabledKey = "rleonMCPBridgeEnabled"

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    // MARK: - Server management

    var configuredServers: [MCPServerConfig] {
        get { MCPBridgeRegistry.load() }
        set { MCPBridgeRegistry.save(newValue) }
    }

    func addServer(_ config: MCPServerConfig) {
        var servers = configuredServers
        if let idx = servers.firstIndex(where: { $0.id == config.id }) {
            servers[idx] = config
        } else {
            servers.append(config)
        }
        configuredServers = servers
    }

    func removeServer(id: String) {
        configuredServers = configuredServers.filter { $0.id != id }
    }

    // MARK: - Tool definitions

    /// OpenAI-compatible `tools` entries.
    /// Empty until `tools/list` is implemented with swift-sdk (Xcode 16+).
    ///
    /// TODO (Xcode 16+):
    ///   1. Import `MCP` from modelcontextprotocol/swift-sdk
    ///   2. For each enabled server, create a `Client` + transport
    ///   3. Call `client.listTools()` and map to `ToolDefinition.asDictionary()`
    func openAIToolDefinitions() -> [[String: Any]] {
        guard isEnabled else { return [] }
        // Stub: returns empty until swift-sdk is wired
        return []
    }

    // MARK: - Tool execution

    /// If this is an MCP tool name, return a result; otherwise `nil` (built-in switch handles it).
    ///
    /// TODO (Xcode 16+):
    ///   1. Resolve `parsed.serverSlug` to a live `Client` from the connection pool
    ///   2. Decode `argumentsJSON` as `[String: Any]`
    ///   3. Call `client.callTool(name: parsed.toolName, arguments: args)`
    ///   4. Map the MCP result content array back to a String
    func executeIfNeeded(name: String, argumentsJSON: String) async -> String? {
        guard isEnabled, name.hasPrefix("mcp_") else { return nil }
        let parsed = MCPBridgeNaming.parse(toolId: name)

        // Find the matching server config for a better error message
        let serverConfig = configuredServers.first { $0.id == parsed.serverSlug }
        let transportHint = serverConfig?.transportDescription ?? "(no server configured for slug \"\(parsed.serverSlug)\")"

        return """
        MCP: transport not yet wired (requires swift-sdk + Xcode 16+).
        Tool: \(name) | Server slug: \(parsed.serverSlug) | Transport: \(transportHint)
        To wire: add MCP SPM package, implement tools/list + tools/call in MCPToolBridge.
        """
    }
}

// MARK: - Naming helpers

enum MCPBridgeNaming {
    /// Expects `mcp_<serverSlug>_<toolName>` with at least two underscores after `mcp_`.
    static func parse(toolId: String) -> (serverSlug: String, toolName: String) {
        let without = toolId.dropFirst(4) // drop "mcp_"
        let parts = without.split(separator: "_", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else {
            return (serverSlug: "default", toolName: String(without))
        }
        return (serverSlug: String(parts[0]), toolName: String(parts[1]))
    }
}
