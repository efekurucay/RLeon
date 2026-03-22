import SwiftUI

struct DangerousToolsSettingsSection: View {
    @AppStorage(ToolSafetySettings.allowRunTerminalCommandKey) private var allowTerminal = false
    @AppStorage(ToolSafetySettings.allowTypeIntoFocusedFieldKey) private var allowTyping = false
    @AppStorage("rleonMCPBridgeEnabled") private var mcpBridge = false

    @State private var confirmTerminal = false
    @State private var confirmTyping = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            RLeonSectionHeader("Dangerous tools & MCP", subtitle: "Off by default. Enable only with trusted models.")

            Toggle(isOn: terminalToggle) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Terminal commands (`run_terminal_command`)")
                        .font(.subheadline.weight(.medium))
                    Text("Runs shell in a new Terminal via AppleScript — arbitrary command risk.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(RLeonTheme.accent)

            Toggle(isOn: typingToggle) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Type into focused field (`type_into_focused_field`)")
                        .font(.subheadline.weight(.medium))
                    Text("Inserts text into the frontmost app — requires Accessibility trust.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(RLeonTheme.accent)

            Divider().padding(.vertical, 4)

            Toggle("Expose MCP-prefixed tools (`mcp_*`)", isOn: $mcpBridge)
                .tint(RLeonTheme.accent)
            Text("Experimental. Requires swift-sdk wiring; see README. Only enable with trusted MCP servers.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .rleonCard()
        .confirmationDialog(
            "Enable Terminal commands?",
            isPresented: $confirmTerminal,
            titleVisibility: .visible
        ) {
            Button("Enable", role: .destructive) { allowTerminal = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The model can run shell commands in a new Terminal window as you. Use only with models you trust.")
        }
        .confirmationDialog(
            "Enable typing into other apps?",
            isPresented: $confirmTyping,
            titleVisibility: .visible
        ) {
            Button("Enable", role: .destructive) { allowTyping = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The model can insert text into the focused field in other applications. Grant Accessibility when prompted.")
        }
    }

    private var terminalToggle: Binding<Bool> {
        Binding(
            get: { allowTerminal },
            set: { new in
                if new { confirmTerminal = true } else { allowTerminal = false }
            }
        )
    }

    private var typingToggle: Binding<Bool> {
        Binding(
            get: { allowTyping },
            set: { new in
                if new { confirmTyping = true } else { allowTyping = false }
            }
        )
    }
}
