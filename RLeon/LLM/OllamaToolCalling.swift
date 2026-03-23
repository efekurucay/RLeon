import AppKit
import Foundation

/// OpenAI-style **tool calling** with Ollama `/api/chat`: model returns `tool_calls`
/// → run in Swift → send results back as `role: tool`.
/// Requires Ollama 0.4+ and a model that supports tools (e.g. llama3.1, qwen2.5 with tools).
enum OllamaToolCalling {
    private static let maxRounds = 8

    // MARK: - Tool definitions

    /// Tool definitions (JSON): built-ins from `BuiltInToolDefinitions`; `mcp_*` tools from `MCPToolBridge`.
    /// Uses the Codable `ToolDefinition` type from ToolDefinitionModels.swift (Suggestion 1).
    static func localToolDefinitionsJSON(session: URLSession = .shared) -> [[String: Any]] {
        let enabled = LocalToolStore.loadEnabled()
        // Build typed definitions, apply user-customised descriptions, convert to [String:Any]
        let builtIns: [[String: Any]] = BuiltInToolDefinitions.all.compactMap { def in
            guard enabled.contains(def.function.name) else { return nil }
            guard ToolSafetySettings.isExposedToModel(toolId: def.function.name) else { return nil }
            // Apply user-overridden description if set
            let effectiveDesc = LocalToolStore.effectiveModelDescription(
                for: def.function.name,
                default: def.function.description
            )
            let updated = ToolDefinition(
                function: ToolFunction(
                    name: def.function.name,
                    description: effectiveDesc,
                    parameters: def.function.parameters
                )
            )
            return updated.asDictionary()
        }

        let mcpTools: [[String: Any]] = MCPToolBridge.shared.isEnabled
            ? MCPToolBridge.shared.openAIToolDefinitions()
            : []

        return builtIns + mcpTools
    }

    // MARK: - Chat loop

    /// Single-turn chat with a multi-round tool loop when needed; returns the final assistant text.
    /// - Parameters:
    ///   - baseURL: Ollama server base URL.
    ///   - model:   Model name.
    ///   - systemPrompt: Optional system message.
    ///   - userContent:  User message.
    ///   - session: URLSession to use (injectable for testing; defaults to `.shared`).
    static func chatWithLocalTools(
        baseURL: URL,
        model: String,
        systemPrompt: String?,
        userContent: String,
        session: URLSession = .shared
    ) async throws -> String {
        var messages: [[String: Any]] = []
        if let s = systemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
            messages.append(["role": "system", "content": s])
        }
        messages.append(["role": "user", "content": userContent])

        let tools = localToolDefinitionsJSON(session: session)

        for _ in 0 ..< maxRounds {
            var body: [String: Any] = [
                "model": model,
                "messages": messages,
                "stream": false,
            ]
            if !tools.isEmpty {
                body["tools"] = tools
            }

            let data = try JSONSerialization.data(withJSONObject: body, options: [])
            let url = baseURL.appendingPathComponent("api/chat")
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = data
            req.timeoutInterval = 600

            let (respData, resp) = try await session.data(for: req)
            try OllamaClient.throwIfHTTPError(resp, data: respData)

            guard
                let json = try JSONSerialization.jsonObject(with: respData) as? [String: Any],
                let msg = json["message"] as? [String: Any]
            else {
                throw OllamaClient.OllamaError(message: "Could not parse Ollama response.")
            }

            if let toolCalls = msg["tool_calls"] as? [[String: Any]], !toolCalls.isEmpty {
                messages.append(msg)
                for tc in toolCalls {
                    guard let fn = tc["function"] as? [String: Any],
                          let name = fn["name"] as? String
                    else { continue }
                    guard let argsStr = jsonStringFromToolArguments(fn["arguments"]) else { continue }
                    let result = try await executeLocalTool(name: name, argumentsJSON: argsStr)
                    var toolMsg: [String: Any] = [
                        "role": "tool",
                        "content": result,
                        "name": name,
                        "tool_name": name,
                    ]
                    if let id = tc["id"] as? String {
                        toolMsg["tool_call_id"] = id
                    }
                    messages.append(toolMsg)
                }
                continue
            }

            return (msg["content"] as? String) ?? ""
        }

        throw OllamaClient.OllamaError(message: "Tool round limit (\(maxRounds)) exceeded.")
    }

    // MARK: - Private helpers

    /// In `/api/chat` responses, `function.arguments` may be a string or a JSON object.
    private static func jsonStringFromToolArguments(_ value: Any?) -> String? {
        if let s = value as? String { return s }
        guard let obj = value else { return nil }
        guard JSONSerialization.isValidJSONObject(obj),
              let data = try? JSONSerialization.data(withJSONObject: obj, options: [])
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func normalizeHTTPURLString(_ raw: String) -> URL? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        if let u = URL(string: t), u.scheme != nil { return u }
        return URL(string: "https://\(t)")
    }

    // MARK: - Shell execution (Suggestion 4: Process instead of AppleScript)

    /// Runs a shell command via `/bin/zsh -c` using `Process`, captures stdout+stderr,
    /// and returns the combined output to the model.
    ///
    /// This replaces the previous AppleScript `do script` approach which:
    ///  - could not capture command output
    ///  - relied on string interpolation inside AppleScript (injection surface)
    ///  - opened a persistent Terminal window that blocked automated tests
    private static func runShellCommand(_ command: String) -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.arguments = ["-c", command]

        let outPipe = Pipe()
        let errPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError  = errPipe

        do {
            try task.run()
        } catch {
            return "Error: could not start zsh: \(error.localizedDescription)"
        }

        // Cap reading to avoid blocking on huge output.
        let maxBytes = 65_536
        var outData = Data()
        var errData = Data()

        // Read in chunks to honour the byte cap.
        let outHandle = outPipe.fileHandleForReading
        let errHandle = errPipe.fileHandleForReading

        task.waitUntilExit()

        outData = outHandle.readDataToEndOfFile()
        errData = errHandle.readDataToEndOfFile()

        let stdout = String(data: outData.prefix(maxBytes), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let stderr = String(data: errData.prefix(maxBytes), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let exitCode = task.terminationStatus
        if exitCode != 0 {
            let errPart = stderr.isEmpty ? "(no stderr)" : stderr
            let outPart = stdout.isEmpty ? "" : "\nstdout: \(stdout)"
            return "Error (exit \(exitCode)): \(errPart)\(outPart)"
        }
        return stdout.isEmpty ? "Command completed (no output)." : stdout
    }

    // MARK: - Tool dispatcher

    private static func executeLocalTool(name: String, argumentsJSON: String) async throws -> String {
        if LocalToolStore.allToolIds.contains(name), !LocalToolStore.isEnabled(name) {
            return "Error: tool \"\(name)\" is disabled in Settings → Local tools."
        }
        if name.hasPrefix("mcp_"), !MCPToolBridge.shared.isEnabled {
            return "Error: MCP bridge is off in Settings → Dangerous tools & MCP."
        }
        if let mcpResult = await MCPToolBridge.shared.executeIfNeeded(name: name, argumentsJSON: argumentsJSON) {
            return mcpResult
        }
        if name == "run_terminal_command", !ToolSafetySettings.allowRunTerminalCommand {
            return "Error: run_terminal_command is turned off in Settings → Dangerous tools."
        }
        if name == "type_into_focused_field", !ToolSafetySettings.allowTypeIntoFocusedField {
            return "Error: type_into_focused_field is turned off in Settings → Dangerous tools."
        }

        switch name {
        case "copy_to_clipboard":
            guard let data = argumentsJSON.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let text = obj["text"] as? String
            else {
                return "Error: copy_to_clipboard requires valid JSON with text."
            }
            await MainActor.run {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
            return "OK: \(text.count) characters copied to pasteboard."

        case "get_app_info":
            let bundleName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "App"
            let ver = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
            return "App: \(bundleName), version: \(ver)"

        case "open_application":
            return await openApplicationResult(argumentsJSON: argumentsJSON)

        case "open_url":
            guard let data = argumentsJSON.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let raw = obj["url"] as? String,
                  let url = normalizeHTTPURLString(raw)
            else {
                return "Error: open_url requires a valid `url`."
            }
            let browser = ((obj["browser"] as? String) ?? "default")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            return await MainActor.run {
                if browser == "safari" {
                    let p = Process()
                    p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                    p.arguments = ["-a", "Safari", url.absoluteString]
                    do {
                        try p.run(); p.waitUntilExit()
                        return p.terminationStatus == 0
                            ? "Opened in Safari: \(url.absoluteString)"
                            : "Error: could not open with Safari."
                    } catch {
                        return "Error: \(error.localizedDescription)"
                    }
                }
                let ok = NSWorkspace.shared.open(url)
                return ok ? "Opened in default browser: \(url.absoluteString)" : "Error: could not open URL."
            }

        case "whatsapp_compose":
            guard let data = argumentsJSON.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                return "Error: whatsapp_compose requires valid JSON."
            }
            let text = obj["text"] as? String
            let phoneRaw = obj["phone"] as? String
            var items: [URLQueryItem] = []
            if let p = phoneRaw?.filter(\.isNumber), !p.isEmpty {
                items.append(URLQueryItem(name: "phone", value: String(p)))
            }
            if let t = text, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                items.append(URLQueryItem(name: "text", value: t))
            }
            var comps = URLComponents()
            comps.scheme = "whatsapp"
            comps.host = "send"
            comps.queryItems = items.isEmpty ? nil : items
            guard let wurl = comps.url else { return "Error: could not build WhatsApp URL." }
            return await MainActor.run {
                NSWorkspace.shared.open(wurl)
                    ? "Opened WhatsApp."
                    : "Error: could not open WhatsApp (installed?)."
            }

        case "run_terminal_command":
            guard let data = argumentsJSON.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let cmd = obj["command"] as? String,
                  !cmd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                return "Error: run_terminal_command requires a non-empty `command`."
            }
            if cmd.count > 16_384 {
                return "Error: command exceeds maximum length (16384 characters)."
            }
            // Confirmation dialog (if enabled in Settings)
            let confirmed = await MainActor.run {
                if ToolSafetySettings.askBeforeEachTerminalCommand {
                    return ToolInvocationConfirmation.confirmTerminalCommand(cmd)
                }
                return true
            }
            guard confirmed else { return "User cancelled: terminal command was not run." }
            // Run via zsh; return captured output (Suggestion 4)
            return runShellCommand(cmd)

        case "type_into_focused_field":
            guard let data = argumentsJSON.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let text = obj["text"] as? String
            else {
                return "Error: type_into_focused_field requires `text`."
            }
            if text.count > 50_000 {
                return "Error: text exceeds maximum length (50000 characters)."
            }
            return await MainActor.run {
                if ToolSafetySettings.askBeforeEachTypeIntoFocusedField,
                   !ToolInvocationConfirmation.confirmTypeIntoFocusedField(text) {
                    return "User cancelled: text was not inserted into the focused field."
                }
                let code = FocusedTextInsertion.insertText(text)
                return FocusedTextInsertion.localizedUserMessage(for: code)
            }

        default:
            return "Unknown tool: \(name)"
        }
    }

    // MARK: - open_application helpers

    private static func openApplicationResult(argumentsJSON: String) async -> String {
        guard let data = argumentsJSON.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return "Error: open_application requires valid JSON."
        }
        let appName  = (obj["name"]      as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let bundleId = (obj["bundle_id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let bid = bundleId, !bid.isEmpty {
            guard let url = await MainActor.run(body: {
                NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid)
            }) else {
                return "Error: no app found for bundle_id: \(bid)"
            }
            return await openApplicationAtURL(url, summary: "bundle: \(bid)")
        }
        if let n = appName, !n.isEmpty {
            guard let url = applicationURLForDisplayName(n) else {
                return "Error: '\(n)' not found under /Applications or ~/Applications."
            }
            return await openApplicationAtURL(url, summary: n)
        }
        return "Error: open_application requires `name` or `bundle_id`."
    }

    private static func applicationURLForDisplayName(_ name: String) -> URL? {
        let candidates = [
            URL(fileURLWithPath: "/Applications/\(name).app"),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications/\(name).app", isDirectory: true),
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static func openApplicationAtURL(_ url: URL, summary: String) async -> String {
        if #available(macOS 11.0, *) {
            return await withCheckedContinuation { cont in
                NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, error in
                    if let error {
                        cont.resume(returning: "Error: \(error.localizedDescription)")
                    } else {
                        cont.resume(returning: "Opened: \(summary).")
                    }
                }
            }
        }
        let ok = await MainActor.run { NSWorkspace.shared.open(url) }
        return ok ? "Opened: \(summary)." : "Error: could not open application."
    }
}
