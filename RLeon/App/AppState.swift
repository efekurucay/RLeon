import SwiftUI

/// Root application state container.
///
/// Vends all major ObservableObjects so they can be injected as EnvironmentObjects.
@MainActor
final class AppState: ObservableObject {
    let settings: AppSettings
    let speech: SpeechTranscriber
    let fnCoordinator: FnPushToTalkCoordinator
    let toolSelection: ToolSelectionStore
    let mediaBatchTool: MediaBatchToolStore
    let appEnvironment: AppEnvironmentStore

    init() {
        let s = SpeechTranscriber()
        let appSettings = AppSettings()   // registers UserDefaults defaults
        settings     = appSettings
        speech       = s
        fnCoordinator = FnPushToTalkCoordinator(speech: s)
        toolSelection = ToolSelectionStore()
        mediaBatchTool = MediaBatchToolStore()
        appEnvironment = AppEnvironmentStore()
    }
}
