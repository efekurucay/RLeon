import AppKit
import Foundation

/// OpenAI-style **tool calling** with Ollama `/api/chat`: model returns `tool_calls` → run in Swift → send results back as `role: tool`.
/// Requires Ollama 0.4+ and a model that supports tools (e.g. llama3.1, qwen2.5 with tools).
enum OllamaToolCalling {
    private static let maxRounds = 8

    /// Tanımlar (JSON) — yerleşik araçlar `LocalToolStore` ile; `mcp_*` araçları `MCPToolBridge` ile.
    static func localToolDefinitionsJSON() -> [[String: Any]] {
        let enabled = LocalToolStore.loadEnabled()
        let combined = allToolDefinitionsUnfiltered() + MCPToolBridge.shared.openAIToolDefinitions()
        return combined.filter { item in
            guard let fn = item["function"] as? [String: Any],
                  let n = fn["name"] as? String else { return false }
            if n.hasPrefix("mcp_") {
                return MCPToolBridge.shared.isEnabled
            }
            guard enabled.contains(n) else { return false }
            return ToolSafetySettings.isExposedToModel(toolId: n)
        }
    }

    private static func allToolDefinitionsUnfiltered() -> [[String: Any]] {
        [
            toolFunction(
                name: "copy_to_clipboard",
                description: LocalToolStore.effectiveModelDescription(
                    for: "copy_to_clipboard",
                    default: LocalToolStore.referenceModelDescription(for: "copy_to_clipboard")
                ),
                parameters: [
                    "type": "object",
                    "properties": [
                        "text": [
                            "type": "string",
                            "description": "Text to place on the pasteboard.",
                        ] as [String: Any],
                    ] as [String: Any],
                    "required": ["text"],
                ] as [String: Any],
            ),
            toolFunction(
                name: "get_app_info",
                description: LocalToolStore.effectiveModelDescription(
                    for: "get_app_info",
                    default: LocalToolStore.referenceModelDescription(for: "get_app_info")
                ),
                parameters: [
                    "type": "object",
                    "properties": [:] as [String: Any],
                    "required": [] as [String],
                ] as [String: Any],
            ),
            toolFunction(
                name: "open_application",
                description: LocalToolStore.effectiveModelDescription(
                    for: "open_application",
                    default: LocalToolStore.referenceModelDescription(for: "open_application")
                ),
                parameters: [
                    "type": "object",
                    "properties": [
                        "name": [
                            "type": "string",
                            "description": "Application name without .app, e.g. Safari, Notes, Calendar.",
                        ] as [String: Any],
                        "bundle_id": [
                            "type": "string",
                            "description": "Cocoa bundle identifier, e.g. com.apple.Safari. Takes precedence over name when set.",
                        ] as [String: Any],
                    ] as [String: Any],
                    "required": [] as [String],
                ] as [String: Any],
            ),
            toolFunction(
                name: "open_url",
                description: LocalToolStore.effectiveModelDescription(
                    for: "open_url",
                    default: LocalToolStore.referenceModelDescription(for: "open_url")
                ),
                parameters: [
                    "type": "object",
                    "properties": [
                        "url": [
                            "type": "string",
                            "description": "Full URL or hostname (e.g. https://example.com or apple.com).",
                        ] as [String: Any],
                        "browser": [
                            "type": "string",
                            "description": "\"safari\" or \"default\" (default browser).",
                        ] as [String: Any],
                    ] as [String: Any],
                    "required": ["url"],
                ] as [String: Any],
            ),
            toolFunction(
                name: "whatsapp_compose",
                description: LocalToolStore.effectiveModelDescription(
                    for: "whatsapp_compose",
                    default: LocalToolStore.referenceModelDescription(for: "whatsapp_compose")
                ),
                parameters: [
                    "type": "object",
                    "properties": [
                        "text": [
                            "type": "string",
                            "description": "Optional prefilled message text.",
                        ] as [String: Any],
                        "phone": [
                            "type": "string",
                            "description": "Digits only with country code (e.g. 14155552671).",
                        ] as [String: Any],
                    ] as [String: Any],
                    "required": [] as [String],
                ] as [String: Any],
            ),
            toolFunction(
                name: "run_terminal_command",
                description: LocalToolStore.effectiveModelDescription(
                    for: "run_terminal_command",
                    default: LocalToolStore.referenceModelDescription(for: "run_terminal_command")
                ),
                parameters: [
                    "type": "object",
                    "properties": [
                        "command": [
                            "type": "string",
                            "description": "Shell command to run (e.g. ls -la, cd ~/Desktop && pwd).",
                        ] as [String: Any],
                    ] as [String: Any],
                    "required": ["command"],
                ] as [String: Any],
            ),
            toolFunction(
                name: "type_into_focused_field",
                description: LocalToolStore.effectiveModelDescription(
                    for: "type_into_focused_field",
                    default: LocalToolStore.referenceModelDescription(for: "type_into_focused_field")
                ),
                parameters: [
                    "type": "object",
                    "properties": [
                        "text": [
                            "type": "string",
                            "description": "Text to type (any Unicode).",
                        ] as [String: Any],
                    ] as [String: Any],
                    "required": ["text"],
                ] as [String: Any],
            ),
        ]
    }

    private static func toolFunction(name: String, description: String, parameters: [String: Any]) -> [String: Any] {
        [
            "type": "function",
            "function": [
                "name": name,
                "description": description,
                "parameters": parameters,
            ],
        ]
    }

    /// Tek girişli sohbet + gerekirse çok tur araç döngüsü; son metin cevabı döner.
    static func chatWithLocalTools(
        baseURL: URL,
        model: String,
        systemPrompt: String?,
        userContent: String
    ) async throws -> String {
        var messages: [[String: Any]] = []
        if let s = systemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
            messages.append(["role": "system", "content": s])
        }
        messages.append(["role": "user", "content": userContent])

        let tools = localToolDefinitionsJSON()

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

            let (respData, resp) = try await URLSession.shared.data(for: req)
            try throwIfHTTPError(resp, data: respData)

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
                    // Ollama çoğu sürümde `arguments` nesne döner; bazıları string. İkisini de kabul et.
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

    /// Ollama `/api/chat` yanıtında `function.arguments` string veya JSON nesnesi olabilir.
    private static func jsonStringFromToolArguments(_ value: Any?) -> String? {
        if let s = value as? String { return s }
        guard let obj = value else { return nil }
        guard JSONSerialization.isValidJSONObject(obj),
              let data = try? JSONSerialization.data(withJSONObject: obj, options: [])
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func throwIfHTTPError(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200 ... 299).contains(http.statusCode) else {
            let snippet = String(data: data, encoding: .utf8) ?? ""
            throw OllamaClient.OllamaError(message: "HTTP \(http.statusCode): \(snippet.prefix(400))")
        }
    }

    /// `do script "..."` içinde kullanılacak metin için kaçış.
    private static func escapeForAppleScriptDoScriptString(_ s: String) -> String {
        var r = ""
        for ch in s {
            switch ch {
            case "\\": r += "\\\\"
            case "\"": r += "\\\""
            default: r.append(ch)
            }
        }
        return r
    }

    private static func normalizeHTTPURLString(_ raw: String) -> URL? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        if let u = URL(string: t), u.scheme != nil { return u }
        return URL(string: "https://\(t)")
    }

    private static func runTerminalDoScript(command: String) -> String {
        let normalized = command
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: true)
            .joined(separator: "; ")
        let inner = escapeForAppleScriptDoScriptString(normalized)
        let script = """
        tell application "Terminal"
            activate
            do script "\(inner)"
        end tell
        """
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]
        let errPipe = Pipe()
        task.standardOutput = Pipe()
        task.standardError = errPipe
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return "Error: could not start osascript: \(error.localizedDescription)"
        }
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        let errStr = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if task.terminationStatus != 0 {
            return "Error (AppleScript/Terminal): \(errStr.isEmpty ? "exit \(task.terminationStatus)" : errStr)"
        }
        return "Command ran in Terminal."
    }

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
                  let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
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
            let browser = ((obj["browser"] as? String) ?? "default").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return await MainActor.run {
                if browser == "safari" {
                    let p = Process()
                    p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                    p.arguments = ["-a", "Safari", url.absoluteString]
                    do {
                        try p.run()
                        p.waitUntilExit()
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
            guard let wurl = comps.url else {
                return "Error: could not build WhatsApp URL."
            }
            return await MainActor.run {
                NSWorkspace.shared.open(wurl)
                    ? "Opened WhatsApp (text/phone passed via URL; behavior varies by app version)."
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
            return await MainActor.run {
                if ToolSafetySettings.askBeforeEachTerminalCommand,
                   !ToolInvocationConfirmation.confirmTerminalCommand(cmd)
                {
                    return "User cancelled: terminal command was not run."
                }
                return runTerminalDoScript(command: cmd)
            }

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
                   !ToolInvocationConfirmation.confirmTypeIntoFocusedField(text)
                {
                    return "User cancelled: text was not inserted into the focused field."
                }
                let code = FocusedTextInsertion.insertText(text)
                return FocusedTextInsertion.localizedUserMessage(for: code)
            }

        default:
            return "Unknown tool: \(name)"
        }
    }

    private static func openApplicationResult(argumentsJSON: String) async -> String {
        guard let data = argumentsJSON.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return "Error: open_application requires valid JSON."
        }
        let appName = (obj["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
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
                return "Error: '\(n)' not found under /Applications or ~/Applications (try exact name or use bundle_id)."
            }
            return await openApplicationAtURL(url, summary: n)
        }
        return "Error: open_application requires `name` or `bundle_id`."
    }

    private static func applicationURLForDisplayName(_ name: String) -> URL? {
        let candidates = [
            URL(fileURLWithPath: "/Applications/\(name).app"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/\(name).app", isDirectory: true),
        ]
        for u in candidates where FileManager.default.fileExists(atPath: u.path) {
            return u
        }
        return nil
    }

    private static func openApplicationAtURL(_ url: URL, summary: String) async -> String {
        if #available(macOS 11.0, *) {
            return await withCheckedContinuation { cont in
                let config = NSWorkspace.OpenConfiguration()
                NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
                    if let error {
                        cont.resume(returning: "Error: could not open application: \(error.localizedDescription)")
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
