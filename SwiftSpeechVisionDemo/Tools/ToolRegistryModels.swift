import Foundation

/// Tek bir yerleşik araç için kullanıcı özelleştirmesi (başlık, alt başlık, modele giden açıklama).
struct ToolProfile: Codable, Equatable {
    var isEnabled: Bool = true
    var customTitle: String?
    var customSubtitle: String?
    /// Ollama `function.description` — boşsa uygulama varsayılanı kullanılır.
    var customDescription: String?
}

struct ToolRegistryState: Codable, Equatable {
    /// Görünen sıra; yalnızca `LocalToolStore.allToolIds` içinden kimlikler.
    var orderedIds: [String]
    var profiles: [String: ToolProfile]
}
