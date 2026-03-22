import Foundation

/// Local Ollama tools: order, on/off, user-facing copy (persisted as JSON in `UserDefaults`).
enum LocalToolStore {
    static let registryKey = "rleonToolRegistryJSON"
    /// Legacy key — one-time migration from CSV.
    static let legacyEnabledCsvKey = "rleonEnabledToolIdsCSV"

    static let allToolIds: [String] = [
        "copy_to_clipboard",
        "get_app_info",
        "open_application",
        "open_url",
        "whatsapp_compose",
        "run_terminal_command",
        "type_into_focused_field",
    ]

    static func loadRegistry() -> ToolRegistryState {
        if let data = UserDefaults.standard.data(forKey: registryKey),
           let decoded = try? JSONDecoder().decode(ToolRegistryState.self, from: data) {
            return normalize(decoded)
        }
        let migrated = normalize(migrateFromLegacyCsv())
        if let data = try? JSONEncoder().encode(migrated) {
            UserDefaults.standard.set(data, forKey: registryKey)
        }
        return migrated
    }

    @discardableResult
    static func saveRegistry(_ state: ToolRegistryState) -> ToolRegistryState {
        let normalized = normalize(state)
        if let data = try? JSONEncoder().encode(normalized) {
            UserDefaults.standard.set(data, forKey: registryKey)
        }
        return normalized
    }

    private static func migrateFromLegacyCsv() -> ToolRegistryState {
        var profiles = [String: ToolProfile]()
        if let csv = UserDefaults.standard.string(forKey: legacyEnabledCsvKey), !csv.isEmpty {
            let enabled = Set(csv.split(separator: ",").map(String.init).filter { !$0.isEmpty })
            for id in allToolIds {
                var p = ToolProfile()
                p.isEnabled = enabled.contains(id)
                profiles[id] = p
            }
        }
        return ToolRegistryState(orderedIds: allToolIds, profiles: profiles)
    }

    private static func normalize(_ raw: ToolRegistryState) -> ToolRegistryState {
        let valid = Set(allToolIds)
        var ordered = raw.orderedIds.filter { valid.contains($0) }
        for id in allToolIds where !ordered.contains(id) {
            ordered.append(id)
        }
        var profiles = raw.profiles
        for id in allToolIds {
            if profiles[id] == nil {
                profiles[id] = ToolProfile()
            }
        }
        return ToolRegistryState(orderedIds: ordered, profiles: profiles)
    }

    /// Enabled tool IDs exposed to the model.
    static func loadEnabled() -> Set<String> {
        let r = loadRegistry()
        return Set(r.orderedIds.filter { id in
            r.profiles[id]?.isEnabled ?? true
        })
    }

    static func isEnabled(_ toolId: String) -> Bool {
        loadEnabled().contains(toolId)
    }

    static func profile(for id: String) -> ToolProfile? {
        loadRegistry().profiles[id]
    }

    static func effectiveTitle(for id: String, default def: @autoclosure () -> String) -> String {
        if let t = profile(for: id)?.customTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
            return t
        }
        return def()
    }

    static func effectiveSubtitle(for id: String, default def: @autoclosure () -> String) -> String {
        if let t = profile(for: id)?.customSubtitle?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
            return t
        }
        return def()
    }

    /// Ollama `function.description`; falls back to `defaultDescription` when not customized.
    static func effectiveModelDescription(for id: String, default defaultDescription: String) -> String {
        if let d = profile(for: id)?.customDescription?.trimmingCharacters(in: .whitespacesAndNewlines), !d.isEmpty {
            return d
        }
        return defaultDescription
    }

    /// Single source of default model-facing strings for Settings previews and `OllamaToolCalling`.
    static func referenceModelDescription(for id: String) -> String {
        switch id {
        case "copy_to_clipboard":
            return "Copies the given text to the system pasteboard."
        case "get_app_info":
            return "Returns brief info about the RLeon macOS app (name, version)."
        case "open_application":
            return "Opens an installed macOS app. Prefer bundle_id when known; otherwise use the app name as shown in Finder (e.g. Safari, Terminal)."
        case "open_url":
            return "Opens an http(s) URL in the browser—Safari or the system default."
        case "whatsapp_compose":
            return "Opens the WhatsApp desktop compose/chat flow via whatsapp:// with optional phone and prefilled text. Automatic insertion into an existing chat is not guaranteed."
        case "run_terminal_command":
            return "Runs a shell command in a new Terminal window (zsh). Multi-line commands are joined with semicolons. WARNING: destructive commands are possible—only use with trusted requests."
        case "type_into_focused_field":
            return "Types into the focused text field. Returns short codes: OK_PASTE, OK_CG, OK_AX_SEL, AX_NOT_TRUSTED, FAILED_FOCUS. If AX_NOT_TRUSTED, reply in one short sentence; do not paste long system-settings text."
        default:
            return ""
        }
    }
}
