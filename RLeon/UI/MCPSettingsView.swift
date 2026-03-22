import SwiftUI

/// Settings section for MCP server management.
///
/// Lets the user add, remove, and inspect configured MCP servers.
/// Full transport wiring (tools/list, tools/call) requires swift-sdk + Xcode 16+.
struct MCPSettingsView: View {
    @State private var servers: [MCPServerConfig] = MCPToolBridge.shared.configuredServers
    @State private var showAddSheet = false
    @State private var newID          = ""
    @State private var newDisplayName = ""
    @State private var newCommand     = ""
    @State private var newURLString   = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("MCP servers")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button { showAddSheet = true } label: {
                    Label("Add server", systemImage: "plus")
                }
                .controlSize(.small)
            }

            if servers.isEmpty {
                Text("No MCP servers configured. Add one to get started.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(servers) { server in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(server.displayName).font(.subheadline)
                            Text(server.transportDescription)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { server.isEnabled },
                            set: { newVal in
                                if let idx = servers.firstIndex(where: { $0.id == server.id }) {
                                    servers[idx].isEnabled = newVal
                                    MCPToolBridge.shared.configuredServers = servers
                                }
                            }
                        ))
                        .labelsHidden()
                        Button(role: .destructive) {
                            MCPToolBridge.shared.removeServer(id: server.id)
                            servers = MCPToolBridge.shared.configuredServers
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.red)
                    }
                    .padding(8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
            }

            Text("Full tool calling (tools/list + tools/call) requires the modelcontextprotocol/swift-sdk package and Xcode 16+.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .rleonCard()
        .sheet(isPresented: $showAddSheet) {
            addServerSheet
        }
    }

    @ViewBuilder
    private var addServerSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add MCP server").font(.headline)

            Group {
                LabeledContent("Slug (unique ID)") {
                    TextField("e.g. filesystem", text: $newID)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledContent("Display name") {
                    TextField("e.g. Filesystem", text: $newDisplayName)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledContent("Command (stdio)") {
                    TextField("/usr/local/bin/mcp-server", text: $newCommand)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledContent("URL (HTTP/SSE)") {
                    TextField("http://localhost:8080", text: $newURLString)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Text("Provide either a command (stdio) or a URL (HTTP/SSE), not both.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack {
                Button("Add") {
                    let config = MCPServerConfig(
                        id: newID.trimmingCharacters(in: .whitespacesAndNewlines),
                        displayName: newDisplayName.trimmingCharacters(in: .whitespacesAndNewlines),
                        command: newCommand.isEmpty ? nil : newCommand,
                        urlString: newURLString.isEmpty ? nil : newURLString
                    )
                    MCPToolBridge.shared.addServer(config)
                    servers = MCPToolBridge.shared.configuredServers
                    showAddSheet = false
                    newID = ""; newDisplayName = ""; newCommand = ""; newURLString = ""
                }
                .disabled(newID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                          newDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.defaultAction)

                Button("Cancel") { showAddSheet = false }
            }
            .controlSize(.regular)
        }
        .padding(24)
        .frame(minWidth: 420)
    }
}
