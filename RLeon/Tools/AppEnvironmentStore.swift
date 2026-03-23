import Foundation

@MainActor
final class AppEnvironmentStore: ObservableObject {
    struct Entry: Codable, Identifiable, Hashable {
        var id: UUID
        var key: String
        var value: String

        init(id: UUID = UUID(), key: String, value: String) {
            self.id = id
            self.key = key
            self.value = value
        }
    }

    struct Template: Identifiable, Hashable {
        let key: String
        let placeholder: String
        let note: String

        var id: String { key }
    }

    @Published private(set) var entries: [Entry] = []

    private let defaultsKey = "rleonAppEnvironmentEntries"

    static let geminiTemplates: [Template] = [
        Template(key: "GEMINI_API_KEY", placeholder: "AIza...", note: "Media Batch API key"),
        Template(key: "GEMINI_MODEL", placeholder: "gemini-3-pro-preview", note: "Default Gemini model"),
        Template(key: "GEMINI_BATCH_SYSTEM_PROMPT", placeholder: "Optional override", note: "Default system prompt"),
        Template(key: "GEMINI_BATCH_USER_PROMPT", placeholder: "Optional override", note: "Default user prompt"),
        Template(key: "GEMINI_BATCH_RESPONSE_MIME_TYPE", placeholder: "application/json", note: "Optional output MIME type"),
        Template(key: "GEMINI_BATCH_OUTPUT_EXTENSION", placeholder: "md", note: "Default output extension"),
    ]

    init() {
        load()
    }

    func value(for key: String) -> String? {
        let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedKey.isEmpty else { return nil }

        return entries
            .last { $0.key.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(normalizedKey) == .orderedSame }
            .map { $0.value.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }
    }

    func addEmptyEntry() {
        entries.append(Entry(key: "", value: ""))
        save()
    }

    func ensureEntry(for key: String, placeholderValue: String = "") {
        guard entries.contains(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame }) == false else { return }
        entries.append(Entry(key: key, value: placeholderValue))
        save()
    }

    func updateKey(_ key: String, for entryID: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return }
        entries[index].key = key
        save()
    }

    func updateValue(_ value: String, for entryID: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return }
        entries[index].value = value
        save()
    }

    func remove(_ entryID: UUID) {
        entries.removeAll { $0.id == entryID }
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([Entry].self, from: data)
        else {
            entries = []
            return
        }
        entries = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
