import AppKit
import SwiftUI

/// Settings section that lets the user rebind the push-to-talk hotkey.
///
/// State machine:
///  - `.idle`     — shows current binding + "Record new" button
///  - `.recording` — waits for the next key event via a global NSEvent monitor
///  - `.pending`  — shows the captured binding for confirmation before saving
struct HotkeySettingsView: View {

    private enum RecordState {
        case idle, recording, pending(HotkeyBinding)
    }

    @State private var current   = HotkeySettings.current
    @State private var state: RecordState = .idle
    @State private var monitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Push-to-talk hotkey")
                .font(.subheadline.weight(.semibold))

            HStack {
                Text("Current binding:")
                    .foregroundStyle(.secondary)
                Text(current.displayString)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            }

            switch state {
            case .idle:
                HStack {
                    Button("Record new") { beginRecording() }
                    Button("Reset to Fn") { resetToDefault() }
                        .disabled(current == .fnDefault)
                }
                .controlSize(.small)

            case .recording:
                Label("Press any key (+ optional modifiers)…", systemImage: "keyboard")
                    .foregroundStyle(RLeonTheme.accent)
                Button("Cancel") { cancelRecording() }
                    .controlSize(.small)

            case .pending(let binding):
                HStack {
                    Text("New binding: ")
                        .foregroundStyle(.secondary)
                    Text(binding.displayString)
                        .fontWeight(.semibold)
                }
                HStack {
                    Button("Save") { save(binding) }
                        .keyboardShortcut(.defaultAction)
                    Button("Try again") { beginRecording() }
                    Button("Cancel") { cancelRecording() }
                }
                .controlSize(.small)
            }

            Text("The app must be restarted (or monitoring restarted) for a new binding to take effect.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .rleonCard()
        .onDisappear { cancelRecording() }
    }

    // MARK: - Actions

    private func beginRecording() {
        state = .recording
        stopMonitor()
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            DispatchQueue.main.async {
                guard case .recording = self.state else { return }
                // Ignore pure modifier keystrokes (no character)
                if event.type == .flagsChanged { return }
                let binding = HotkeyBinding(
                    keyCode: event.keyCode,
                    modifiers: event.modifierFlags.intersection([.command, .option, .control, .shift])
                )
                self.stopMonitor()
                self.state = .pending(binding)
            }
        }
    }

    private func save(_ binding: HotkeyBinding) {
        HotkeySettings.current = binding
        current = binding
        state = .idle
    }

    private func resetToDefault() {
        HotkeySettings.reset()
        current = .fnDefault
        state = .idle
    }

    private func cancelRecording() {
        stopMonitor()
        state = .idle
    }

    private func stopMonitor() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }
}
