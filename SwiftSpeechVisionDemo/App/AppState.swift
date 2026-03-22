import SwiftUI

@MainActor
final class AppState: ObservableObject {
    let speech: SpeechTranscriber
    let fnCoordinator: FnPushToTalkCoordinator
    let toolSelection: ToolSelectionStore

    init() {
        let s = SpeechTranscriber()
        speech = s
        fnCoordinator = FnPushToTalkCoordinator(speech: s)
        toolSelection = ToolSelectionStore()
    }
}
