import SwiftUI

/// Menu bar extra: avoid heavy animation (recording must not block the main run loop).
private struct MenuBarLabel: View {
    @ObservedObject var fn: FnPushToTalkCoordinator

    var body: some View {
        switch fn.phase {
        case .recording:
            Image(systemName: "mic.fill")
                .foregroundStyle(RLeonTheme.accent)
                .accessibilityLabel("Recording")
        case .sending:
            ProgressView()
                .scaleEffect(0.55)
                .frame(width: 14, height: 14)
                .accessibilityLabel("Processing")
        case .idle:
            Image(systemName: "mic")
                .accessibilityLabel("RLeon FN ready")
        }
    }
}

private struct MenuBarPopover: View {
    @ObservedObject var fn: FnPushToTalkCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("RLeon")
                .font(.headline)
            Text(phaseDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let err = fn.lastError {
                Text(err)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
            if let reply = fn.lastOllamaReply, !reply.isEmpty {
                Divider()
                Text("Last reply")
                    .font(.caption.weight(.semibold))
                ScrollView {
                    Text(reply)
                        .font(.caption)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 160)
            }
        }
        .padding(12)
        .frame(minWidth: 280)
    }

    private var phaseDescription: String {
        switch fn.phase {
        case .idle:      return "Short FN tap \u2192 dictation-only; hold \u2192 OCR + LLM."
        case .recording: return "Listening\u2026"
        case .sending:   return "Processing\u2026"
        }
    }
}

@main
struct RLeonApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState.speech)
                .environmentObject(appState.fnCoordinator)
                .environmentObject(appState.toolSelection)
                .environmentObject(appState.settings)
                .tint(RLeonTheme.accent)
                .onAppear {
                    // UserDefaults.register is now handled inside AppSettings.init()
                    FocusedTextInsertion.requestAccessibilityPromptIfNeeded()
                    appState.fnCoordinator.startMonitoring()
                }
        }
        .defaultSize(width: 920, height: 760)

        MenuBarExtra {
            MenuBarPopover(fn: appState.fnCoordinator)
        } label: {
            MenuBarLabel(fn: appState.fnCoordinator)
        }
        .menuBarExtraStyle(.window)
    }
}
