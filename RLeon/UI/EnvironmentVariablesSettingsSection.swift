import SwiftUI

struct EnvironmentVariablesSettingsSection: View {
    @EnvironmentObject private var appEnvironment: AppEnvironmentStore

    @State private var revealSensitiveValues = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            RLeonSectionHeader("Environment variables", subtitle: "App-local key/value settings for tools. Media Batch reads `GEMINI_*` values from here.")

            HStack(spacing: 10) {
                Button("Add variable") { appEnvironment.addEmptyEntry() }
                    .controlSize(.small)

                Menu("Add Gemini variable") {
                    ForEach(AppEnvironmentStore.geminiTemplates) { template in
                        Button(template.key) {
                            appEnvironment.ensureEntry(for: template.key)
                        }
                    }
                }
                .controlSize(.small)

                Toggle("Show sensitive values", isOn: $revealSensitiveValues)
                    .toggleStyle(.checkbox)

                Spacer()
            }

            if appEnvironment.entries.isEmpty {
                Text("No environment variables defined yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(appEnvironment.entries) { entry in
                        row(for: entry)
                    }
                }
            }

            Text("Recommended keys for Media Batch: `GEMINI_API_KEY`, `GEMINI_MODEL`, `GEMINI_BATCH_SYSTEM_PROMPT`, `GEMINI_BATCH_USER_PROMPT`, `GEMINI_BATCH_RESPONSE_MIME_TYPE`, `GEMINI_BATCH_OUTPUT_EXTENSION`.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .rleonCard()
    }

    private func row(for entry: AppEnvironmentStore.Entry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Key")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("VARIABLE_NAME", text: Binding(
                    get: { entry.key },
                    set: { appEnvironment.updateKey($0, for: entry.id) }
                ))
                .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Value")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Group {
                    if shouldHideValue(for: entry.key) && !revealSensitiveValues {
                        SecureField("Value", text: Binding(
                            get: { entry.value },
                            set: { appEnvironment.updateValue($0, for: entry.id) }
                        ))
                    } else {
                        TextField("Value", text: Binding(
                            get: { entry.value },
                            set: { appEnvironment.updateValue($0, for: entry.id) }
                        ))
                    }
                }
                .textFieldStyle(.roundedBorder)
            }

            Button {
                appEnvironment.remove(entry.id)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 26)
            .help("Remove variable")
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func shouldHideValue(for key: String) -> Bool {
        let uppercased = key.uppercased()
        return uppercased.contains("KEY")
            || uppercased.contains("TOKEN")
            || uppercased.contains("SECRET")
            || uppercased.contains("PASSWORD")
    }
}
