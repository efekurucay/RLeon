import SwiftUI

private struct EditingToolWrapper: Identifiable, Hashable {
    let id: String
}

struct ToolsSettingsSection: View {
    @ObservedObject var toolStore: ToolSelectionStore
    @State private var editing: EditingToolWrapper?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            RLeonSectionHeader("Local tools", subtitle: "Reorder, add or remove tools from the list; customize titles and model descriptions.")
            HStack(spacing: 10) {
                Button("Enable all") { toolStore.enableAll() }
                    .controlSize(.small)
                Button("Disable all") { toolStore.disableAll() }
                    .controlSize(.small)
                Spacer()
            }
            Text("Tools not in the list are not sent to Ollama. Order may affect how the model prioritizes tools.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            List {
                ForEach(toolStore.orderedIds, id: \.self) { id in
                    HStack(alignment: .center, spacing: 10) {
                        Image(systemName: RLeonToolLabel.symbol(id))
                            .foregroundStyle(RLeonTheme.accent)
                            .frame(width: 22, alignment: .center)
                        Toggle(isOn: Binding(
                            get: { toolStore.isOn(id) },
                            set: { toolStore.setOn(id, $0) }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(RLeonToolLabel.title(id))
                                    .font(.subheadline.weight(.medium))
                                Text(RLeonToolLabel.subtitle(id))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 8)
                        Button {
                            editing = EditingToolWrapper(id: id)
                        } label: {
                            Label("Edit", systemImage: "slider.horizontal.3")
                        }
                        .controlSize(.small)
                        .labelStyle(.iconOnly)
                        .help("Title and description")

                        Button {
                            toolStore.removeFromList(id)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Remove from list")
                    }
                    .padding(.vertical, 4)
                }
                .onMove { source, dest in
                    toolStore.move(fromOffsets: source, toOffset: dest)
                }
            }
            .frame(minHeight: 220)
            .scrollContentBackground(.hidden)

            if !toolStore.idsNotInList.isEmpty {
                Menu {
                    ForEach(toolStore.idsNotInList, id: \.self) { id in
                        Button(RLeonToolLabel.defaultTitle(id)) {
                            toolStore.addToList(id)
                        }
                    }
                } label: {
                    Label("Add tool to list", systemImage: "plus.circle.fill")
                }
                .controlSize(.regular)
            }
        }
        .sheet(item: $editing) { wrap in
            ToolEditSheet(toolId: wrap.id, toolStore: toolStore)
        }
    }
}

struct ToolEditSheet: View {
    let toolId: String
    @ObservedObject var toolStore: ToolSelectionStore
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var subtitle: String = ""
    @State private var modelDescription: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("List title", text: $title, prompt: Text(RLeonToolLabel.defaultTitle(toolId)))
                    TextField("Subtitle", text: $subtitle, prompt: Text(RLeonToolLabel.defaultSubtitle(toolId)))
                } header: {
                    Text("Appearance")
                } footer: {
                    Text("Empty fields use the app default.")
                        .font(.caption)
                }

                Section {
                    TextEditor(text: $modelDescription)
                        .font(.body)
                        .frame(minHeight: 120)
                } header: {
                    Text("Model description (Ollama)")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("This text is sent to the model only as `function.description`. If empty, the default below is used.")
                            .font(.caption)
                        Text(LocalToolStore.referenceModelDescription(for: toolId))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                Section {
                    Button("Reset customization", role: .destructive) {
                        toolStore.resetProfileCustomization(toolId)
                        loadFromStore()
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("\(RLeonToolLabel.defaultTitle(toolId)) — \(toolId)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        toolStore.updateProfile(
                            toolId,
                            title: title,
                            subtitle: subtitle,
                            modelDescription: modelDescription
                        )
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(minWidth: 480, minHeight: 420)
        .onAppear { loadFromStore() }
    }

    private func loadFromStore() {
        let p = LocalToolStore.profile(for: toolId) ?? ToolProfile()
        title = p.customTitle ?? ""
        subtitle = p.customSubtitle ?? ""
        modelDescription = p.customDescription ?? ""
    }
}
