## RLeon v0.1.0

First public release: **local-first macOS** assistant — on-device speech, Vision OCR, **Ollama** `/api/chat` with OpenAI-compatible **tool calling**, and explicit safety gates for high-risk actions.

### Highlights

- **Speech** — `SFSpeechRecognizer` (on-device), FN push-to-talk + menu bar status
- **OCR** — screen capture + images via `VNRecognizeTextRequest`
- **LLM** — configurable Ollama base URL and model; optional function calling
- **Tools** — clipboard, open URL/app, WhatsApp compose, Terminal, type-into-focused-field (dangerous tools off by default)
- **MCP** — `mcp_*` naming + toggle; **stub** until [swift-sdk](https://github.com/modelcontextprotocol/swift-sdk) wiring
- **CI** — GitHub Actions (`xcodebuild` Debug on macOS)

### Build from source

- **macOS 14+**, **Xcode 15+**
- Clone, open `SwiftSpeechVisionDemo.xcodeproj`, scheme **SwiftSpeechVisionDemo**, destination **My Mac**

See the [README](https://github.com/efekurucay/RLeon#readme) for configuration, tool tables, and security notes.

### Note on binaries

This release is **source-first**. Pre-built signed/notarized `.app` bundles may appear in a later release; track [ROADMAP](https://github.com/efekurucay/RLeon/blob/main/ROADMAP.md).
