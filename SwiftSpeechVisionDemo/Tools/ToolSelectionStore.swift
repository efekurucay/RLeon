import Foundation
import SwiftUI

@MainActor
final class ToolSelectionStore: ObservableObject {
    @Published private(set) var registry: ToolRegistryState

    init() {
        registry = LocalToolStore.loadRegistry()
    }

    var orderedIds: [String] { registry.orderedIds }

    func refresh() {
        registry = LocalToolStore.loadRegistry()
    }

    func isOn(_ id: String) -> Bool {
        registry.profiles[id]?.isEnabled ?? true
    }

    func setOn(_ id: String, _ on: Bool) {
        var p = registry.profiles[id] ?? ToolProfile()
        p.isEnabled = on
        registry.profiles[id] = p
        persist()
    }

    func toggle(_ id: String) {
        setOn(id, !isOn(id))
    }

    func enableAll() {
        for id in registry.orderedIds {
            var p = registry.profiles[id] ?? ToolProfile()
            p.isEnabled = true
            registry.profiles[id] = p
        }
        persist()
    }

    func disableAll() {
        for id in registry.orderedIds {
            var p = registry.profiles[id] ?? ToolProfile()
            p.isEnabled = false
            registry.profiles[id] = p
        }
        persist()
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        registry.orderedIds.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    func removeFromList(_ id: String) {
        registry.orderedIds.removeAll { $0 == id }
        persist()
    }

    func addToList(_ id: String) {
        guard LocalToolStore.allToolIds.contains(id), !registry.orderedIds.contains(id) else { return }
        if registry.profiles[id] == nil {
            registry.profiles[id] = ToolProfile()
        }
        registry.orderedIds.append(id)
        persist()
    }

    var idsNotInList: [String] {
        let inList = Set(registry.orderedIds)
        return LocalToolStore.allToolIds.filter { !inList.contains($0) }
    }

    func updateProfile(_ id: String, title: String?, subtitle: String?, modelDescription: String?) {
        var p = registry.profiles[id] ?? ToolProfile()
        let t = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let s = subtitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let m = modelDescription?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        p.customTitle = t.isEmpty ? nil : t
        p.customSubtitle = s.isEmpty ? nil : s
        p.customDescription = m.isEmpty ? nil : m
        registry.profiles[id] = p
        persist()
    }

    func resetProfileCustomization(_ id: String) {
        var p = registry.profiles[id] ?? ToolProfile()
        p.customTitle = nil
        p.customSubtitle = nil
        p.customDescription = nil
        registry.profiles[id] = p
        persist()
    }

    private func persist() {
        registry = LocalToolStore.saveRegistry(registry)
    }
}
